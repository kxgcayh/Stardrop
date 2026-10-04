import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

public enum SidebarCategory: Hashable {
    case allMods
    case enabledOnly
    case disabledOnly
    case updatableOnly
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var mods: [Mod] = []
    @Published public var profiles: [Profile] = []
    @Published public var activeProfile: Profile
    @Published public var selectedModId: String?
    @Published public var selectedModIds: Set<String> = []
    @Published public var selectionAnchorId: String? = nil
    @Published public var searchText: String = ""
    @Published public var selectedCategory: SidebarCategory = .allMods

    @Published public var settings: StardropSettings
    @Published public var isSettingsPresented: Bool = false
    @Published public var isNewProfilePresented: Bool = false
    @Published public var isConfigEditorPresented: Bool = false
    @Published public var isNexusPresented: Bool = false
    @Published public var isAboutPresented: Bool = false
    @Published public var scrollTargetModId: String? = nil
    @Published public var isCheckingUpdates: Bool = false
    @Published public var lastUpdateCheckDate: Date? = nil
    @Published public var updateCheckMessage: String? = nil
    @Published public var endorsementAlertMessage: String? = nil
    @Published public var isInstallingMods: Bool = false
    @Published public var modInstallProgressMessage: String? = nil
    @Published public var modInstallResultAlert: String? = nil
    @Published public var modToDelete: ModDeletionPrompt? = nil

    public var availableUpdatesCount: Int {
        mods.filter { $0.hasUpdate }.count
    }
    @Published public var editingMod: Mod?
    @Published public var separators: [ModSeparator] = []
    @Published public var isNewSeparatorPresented: Bool = false
    @Published public var pendingNewSeparatorModId: String? = nil
    @Published public var separatorToRename: ModSeparator? = nil

    public struct ActiveCollectionPackage: Identifiable {
        public let id = UUID()
        public let manifest: CollectionManifest
        public let contentURL: URL
        public let isTemporary: Bool
        public let slug: String?
        public let revisionNumber: Int?
        public let domainName: String?

        public init(
            manifest: CollectionManifest,
            contentURL: URL,
            isTemporary: Bool,
            slug: String? = nil,
            revisionNumber: Int? = nil,
            domainName: String? = nil
        ) {
            self.manifest = manifest
            self.contentURL = contentURL
            self.isTemporary = isTemporary
            self.slug = slug
            self.revisionNumber = revisionNumber
            self.domainName = domainName
        }
    }

    @Published public var activeCollectionPackage: ActiveCollectionPackage?
    @Published public var isCollectionInstallPresented: Bool = false
    @Published public var activeQueueManager: CollectionQueueManager?
    @Published public var isFreeUserQueuePresented: Bool = false
    @Published public var installedCollections: [InstalledCollection] = []
    @Published public var isCheckingCollectionUpdates: Bool = false
    @Published public var collectionPendingRemoval: InstalledCollection? = nil

    public var isPremiumNexusUser: Bool {
        settings.nexusDetails.isPremium
    }

    public var areAllSeparatorsExpanded: Bool {
        guard !separators.isEmpty else { return true }
        return separators.allSatisfy { $0.isExpanded }
    }

    public var nexusApiKey: String? {
        SimpleObscureService.shared.getDecryptedKey(rawKey: settings.nexusDetails.key)
    }

    public var isNexusConnected: Bool {
        guard let key = nexusApiKey, !key.isEmpty else { return false }
        return settings.nexusDetails.username != nil
    }

    public let launcher = SMAPILauncherService.shared

    private let pathing = PathingService.shared
    private let scanner = ModScannerService.shared
    private let profileService = ProfileService.shared
    private let settingsService = SettingsService.shared
    private let separatorService = SeparatorService.shared
    private let actionLog = ActionLogger.shared

    public init() {
        let loadedSettings = settingsService.loadSettings()
        self.settings = loadedSettings

        let loadedProfiles = profileService.loadProfiles()
        self.profiles = loadedProfiles

        if let matching = loadedProfiles.first(where: { $0.name == loadedSettings.lastSelectedProfileName }) {
            self.activeProfile = matching
        } else {
            self.activeProfile = loadedProfiles.first ?? profileService.defaultProfile()
        }

        self.separators = separatorService.loadSeparators(for: self.activeProfile.name)

        refreshMods()
        if self.selectedModId == nil {
            self.selectedModId = self.mods.first?.id
        }
        if let first = self.selectedModId {
            self.selectedModIds = [first]
            self.selectionAnchorId = first
        }

        self.installedCollections = CollectionPersistenceService.shared.loadCollections()

        if self.isNexusConnected {
            Task { [weak self] in
                await self?.fetchEndorsements()
            }
        }
    }

    public var gameDirectory: URL {
        pathing.resolveGameDirectory(configuredPath: settings.smapiFolderPath)
    }

    public var modsDirectory: URL {
        pathing.resolveModsDirectory(configuredPath: settings.modFolderPath, gameDirectory: gameDirectory)
    }

    public var filteredMods: [Mod] {
        var list = mods

        // 1. Sidebar Category
        switch selectedCategory {
        case .allMods:
            break
        case .enabledOnly:
            list = list.filter { $0.isEnabled }
        case .disabledOnly:
            list = list.filter { !$0.isEnabled }
        case .updatableOnly:
            list = list.filter { $0.hasUpdate }
        }

        // 2. Search Text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(query) ||
                $0.author.lowercased().contains(query) ||
                $0.id.lowercased().contains(query)
            }
        }

        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var enabledCount: Int {
        mods.filter { $0.isEnabled }.count
    }

    public var totalCount: Int {
        mods.count
    }

    public var selectedMod: Mod? {
        guard let id = selectedModId else { return nil }
        return mods.first { $0.id == id }
    }

    public var selectedMods: [Mod] {
        if selectedModIds.isEmpty {
            if let single = selectedMod {
                return [single]
            }
            return []
        }
        let set = selectedModIds
        return visibleModsInDisplayOrder.filter { set.contains($0.id) }
    }

    public func isModSelected(_ modId: String) -> Bool {
        selectedModIds.contains(modId) || selectedModId == modId
    }

    public var visibleModsInDisplayOrder: [Mod] {
        if separators.isEmpty {
            return filteredMods
        }
        var result: [Mod] = []
        let filteredMap = Dictionary(filteredMods.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for sep in separators {
            let sepMods = sep.modIds.compactMap { filteredMap[$0.lowercased()] }
            if searchText.isEmpty || !sepMods.isEmpty {
                if sep.isExpanded {
                    result.append(contentsOf: sepMods)
                }
            }
        }
        let assignedIds = Set(separators.flatMap { $0.modIds.map { $0.lowercased() } })
        let unassigned = filteredMods.filter { !assignedIds.contains($0.id.lowercased()) }
        result.append(contentsOf: unassigned)
        return result
    }

    public func handleModClick(_ mod: Mod, isShift: Bool, isCommand: Bool) {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return }

        if isShift {
            let anchorId = selectionAnchorId ?? selectedModId ?? mod.id
            let anchorIdx = list.firstIndex(where: { $0.id.caseInsensitiveCompare(anchorId) == .orderedSame }) ?? 0
            let targetIdx = list.firstIndex(where: { $0.id.caseInsensitiveCompare(mod.id) == .orderedSame }) ?? 0

            let start = min(anchorIdx, targetIdx)
            let end = max(anchorIdx, targetIdx)

            var newSet = Set<String>()
            for i in start...end {
                newSet.insert(list[i].id)
            }
            self.selectedModIds = newSet
            self.selectedModId = mod.id
            if self.selectionAnchorId == nil {
                self.selectionAnchorId = anchorId
            }
        } else if isCommand {
            if selectedModIds.contains(mod.id) && selectedModIds.count > 1 {
                selectedModIds.remove(mod.id)
                if selectedModId == mod.id {
                    selectedModId = selectedModIds.first
                }
            } else {
                selectedModIds.insert(mod.id)
                selectedModId = mod.id
                selectionAnchorId = mod.id
            }
        } else {
            selectedModIds = [mod.id]
            selectedModId = mod.id
            selectionAnchorId = mod.id
        }
    }

    public func selectAllMods() {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return }
        selectedModIds = Set(list.map { $0.id })
        if selectedModId == nil || !selectedModIds.contains(selectedModId!) {
            selectedModId = list.first?.id
        }
    }

    public func toggleSelectedMods() {
        let targets = selectedMods
        guard !targets.isEmpty else {
            if let first = visibleModsInDisplayOrder.first {
                handleModClick(first, isShift: false, isCommand: false)
                toggleMod(first)
            }
            return
        }

        if targets.count == 1 {
            toggleMod(targets[0])
            return
        }

        let nonCoreTargets = targets.filter { !$0.isCoreSMAPI }
        guard !nonCoreTargets.isEmpty else { return }

        // If any selected non-core mod is disabled, enable all of them.
        // If all selected non-core mods are already enabled, disable all of them.
        let shouldEnable = nonCoreTargets.contains { !$0.isEnabled }
        let targetIdSet = Set(nonCoreTargets.map { $0.id.lowercased() })

        for i in 0..<mods.count {
            if targetIdSet.contains(mods[i].id.lowercased()) && !mods[i].isCoreSMAPI {
                mods[i].isEnabled = shouldEnable
            }
        }
        saveActiveProfileState()
    }

    public func toggleSelectedMod() {
        toggleSelectedMods()
    }

    public func enableSelectedMods() {
        let targets = selectedMods.filter { !$0.isCoreSMAPI }
        guard !targets.isEmpty else { return }
        let idSet = Set(targets.map { $0.id.lowercased() })
        for i in 0..<mods.count {
            if idSet.contains(mods[i].id.lowercased()) && !mods[i].isCoreSMAPI {
                mods[i].isEnabled = true
            }
        }
        saveActiveProfileState()
    }

    public func disableSelectedMods() {
        let targets = selectedMods.filter { !$0.isCoreSMAPI }
        guard !targets.isEmpty else { return }
        let idSet = Set(targets.map { $0.id.lowercased() })
        for i in 0..<mods.count {
            if idSet.contains(mods[i].id.lowercased()) && !mods[i].isCoreSMAPI {
                mods[i].isEnabled = false
            }
        }
        saveActiveProfileState()
    }

    @discardableResult
    public func selectNextMod() -> Bool {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return false }
        guard let currentId = selectedModId,
              let currentIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(currentId) == .orderedSame }) else {
            if let first = list.first {
                selectedModId = first.id
                selectedModIds = [first.id]
                selectionAnchorId = first.id
                scrollTargetModId = first.id
                return true
            }
            return false
        }
        let nextIndex = min(currentIndex + 1, list.count - 1)
        if nextIndex != currentIndex {
            let nextMod = list[nextIndex]
            selectedModId = nextMod.id
            selectedModIds = [nextMod.id]
            selectionAnchorId = nextMod.id
            scrollTargetModId = nextMod.id
            return true
        }
        return false
    }

    @discardableResult
    public func selectPreviousMod() -> Bool {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return false }
        guard let currentId = selectedModId,
              let currentIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(currentId) == .orderedSame }) else {
            if let first = list.first {
                selectedModId = first.id
                selectedModIds = [first.id]
                selectionAnchorId = first.id
                scrollTargetModId = first.id
                return true
            }
            return false
        }
        let prevIndex = max(currentIndex - 1, 0)
        if prevIndex != currentIndex {
            let prevMod = list[prevIndex]
            selectedModId = prevMod.id
            selectedModIds = [prevMod.id]
            selectionAnchorId = prevMod.id
            scrollTargetModId = prevMod.id
            return true
        }
        return false
    }

    @discardableResult
    public func extendSelectionDown() -> Bool {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return false }

        let currentId = selectedModId ?? list.first!.id
        let currentIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(currentId) == .orderedSame }) ?? 0

        let anchorId = selectionAnchorId ?? currentId
        let anchorIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(anchorId) == .orderedSame }) ?? currentIndex
        self.selectionAnchorId = list[anchorIndex].id

        let newIndex = min(currentIndex + 1, list.count - 1)
        guard newIndex != currentIndex || selectedModIds.count <= 1 else { return false }

        let start = min(anchorIndex, newIndex)
        let end = max(anchorIndex, newIndex)

        var newSet = Set<String>()
        for i in start...end {
            newSet.insert(list[i].id)
        }
        self.selectedModIds = newSet
        self.selectedModId = list[newIndex].id
        self.scrollTargetModId = list[newIndex].id
        return true
    }

    @discardableResult
    public func extendSelectionUp() -> Bool {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return false }

        let currentId = selectedModId ?? list.first!.id
        let currentIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(currentId) == .orderedSame }) ?? 0

        let anchorId = selectionAnchorId ?? currentId
        let anchorIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(anchorId) == .orderedSame }) ?? currentIndex
        self.selectionAnchorId = list[anchorIndex].id

        let newIndex = max(currentIndex - 1, 0)
        guard newIndex != currentIndex || selectedModIds.count <= 1 else { return false }

        let start = min(anchorIndex, newIndex)
        let end = max(anchorIndex, newIndex)

        var newSet = Set<String>()
        for i in start...end {
            newSet.insert(list[i].id)
        }
        self.selectedModIds = newSet
        self.selectedModId = list[newIndex].id
        self.scrollTargetModId = list[newIndex].id
        return true
    }

    // MARK: - Dependency Enforcement

    // Required dependencies that are not installed
    public func missingDependencies(for mod: Mod) -> [String] {
        mod.manifest.allDependencies.compactMap { dep in
            guard dep.isRequired else { return nil }
            let depId = dep.uniqueID.lowercased()
            if depId == "pathoschild.smapi" || depId == "smapi" { return nil }
            if mods.contains(where: { $0.id.caseInsensitiveCompare(dep.uniqueID) == .orderedSame }) {
                return nil
            }
            return dep.uniqueID
        }
    }

    // Required dependencies that are installed but currently disabled
    public func disabledDependencies(for mod: Mod) -> [String] {
        mod.manifest.allDependencies.compactMap { dep in
            guard dep.isRequired else { return nil }
            let depId = dep.uniqueID.lowercased()
            if depId == "pathoschild.smapi" || depId == "smapi" { return nil }
            guard let depMod = mods.first(where: { $0.id.caseInsensitiveCompare(dep.uniqueID) == .orderedSame }) else {
                return nil
            }
            return depMod.isEnabled ? nil : dep.uniqueID
        }
    }

    public func hasMissingDependencyRequirements(_ mod: Mod) -> Bool {
        !missingDependencies(for: mod).isEmpty || !disabledDependencies(for: mod).isEmpty
    }

    // MARK: - Actions

    public func refreshMods() {
        if let freshActive = profileService.loadProfiles().first(where: { $0.id == activeProfile.id }) {
            self.activeProfile = freshActive
            if let idx = self.profiles.firstIndex(where: { $0.id == freshActive.id }) {
                self.profiles[idx] = freshActive
            }
        }

        let enabledSet = Set(activeProfile.enabledModIds.map { $0.uniqueId.lowercased() })
        let previousUpdates = Dictionary(mods.compactMap { mod -> (String, (String?, URL?))? in
            guard mod.suggestedVersion != nil else { return nil }
            return (mod.id.lowercased(), (mod.suggestedVersion, mod.updateURL))
        }, uniquingKeysWith: { first, _ in first })
        let previousEndorsements = Dictionary(mods.map { ($0.id.lowercased(), $0.isEndorsed) }, uniquingKeysWith: { first, _ in first })
        var scanned = scanner.scanMods(in: modsDirectory, enabledIds: enabledSet)
        for i in 0..<scanned.count {
            if let prev = previousUpdates[scanned[i].id.lowercased()] {
                scanned[i].suggestedVersion = prev.0
                scanned[i].updateURL = prev.1
            }
            if let prevEndorsed = previousEndorsements[scanned[i].id.lowercased()] {
                scanned[i].isEndorsed = prevEndorsed
            }
        }
        self.mods = scanned
        if let id = selectedModId, !scanned.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            selectedModId = scanned.first?.id
        } else if selectedModId == nil {
            selectedModId = scanned.first?.id
        }
        saveActiveProfileState()

        if isNexusConnected {
            Task { [weak self] in
                await self?.fetchEndorsements()
            }
        }
    }

    public func checkForModUpdates() async {
        await MainActor.run {
            self.isCheckingUpdates = true
            self.updateCheckMessage = nil
        }

        do {
            let updates = try await ModUpdateService.shared.fetchUpdates(
                mods: self.mods,
                gameDetails: self.settings.gameDetails
            )

            await MainActor.run {
                let updateMap = Dictionary(updates.map { ($0.id.lowercased(), $0.suggestedUpdate) }, uniquingKeysWith: { first, _ in first })
                for i in 0..<self.mods.count {
                    let modKey = self.mods[i].id.lowercased()
                    if let entryUpdate = updateMap[modKey],
                       let suggested = entryUpdate?.version,
                       !suggested.isEmpty,
                       suggested != self.mods[i].version {
                        self.mods[i].suggestedVersion = suggested
                        if let urlStr = entryUpdate?.url, let url = URL(string: urlStr) {
                            self.mods[i].updateURL = url
                        }
                    } else if updateMap[modKey] != nil {
                        self.mods[i].suggestedVersion = nil
                        self.mods[i].updateURL = nil
                    }
                }
                self.lastUpdateCheckDate = Date()
                self.isCheckingUpdates = false
                let count = self.availableUpdatesCount
                if count > 0 {
                    self.updateCheckMessage = "\(count) mod update\(count == 1 ? " is" : "s are") available"
                } else {
                    self.updateCheckMessage = "All mods are up to date"
                }
                ActionLogger.shared.log("Checked mod updates: \(count) update\(count == 1 ? "" : "s") available")
            }

            if self.isNexusConnected {
                await self.fetchEndorsements()
            }
        } catch {
            print("Failed to fetch mod updates: \(error)")
            await MainActor.run {
                self.isCheckingUpdates = false
                self.updateCheckMessage = "Could not check updates: network error"
            }
        }
    }

    public func selectAndRevealMod(id: String) {
        guard let targetMod = mods.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return }

        // If currently filtered out by category or search, reset so the mod is visible
        if !filteredMods.contains(where: { $0.id == targetMod.id }) {
            selectedCategory = .allMods
            searchText = ""
        }

        // Expand the containing separator synchronously if it is collapsed,
        // so the mod row exists in the list before the scroll fires.
        if let idx = separators.firstIndex(where: {
            $0.modIds.contains { $0.caseInsensitiveCompare(targetMod.id) == .orderedSame }
        }), !separators[idx].isExpanded {
            separators[idx].isExpanded = true
            saveSeparatorsState()
        }

        // Set selected mod ID
        selectedModId = targetMod.id
        selectedModIds = [targetMod.id]
        selectionAnchorId = targetMod.id

        // Trigger scroll after a short delay so SwiftUI can lay out the
        // newly expanded separator rows before scrollTo is called.
        scrollTargetModId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.scrollTargetModId = targetMod.id
        }
    }

    public func setModEnabled(_ mod: Mod, isEnabled: Bool) {
        guard let index = mods.firstIndex(where: { $0.id.caseInsensitiveCompare(mod.id) == .orderedSame }) else { return }
        if mod.isCoreSMAPI && !isEnabled { return }
        if mods[index].isEnabled != isEnabled {
            mods[index].isEnabled = isEnabled
            saveActiveProfileState()
            actionLog.log("\(isEnabled ? "Enabled" : "Disabled") mod '\(mod.name)' in profile '\(activeProfile.name)'")
        }
    }

    public func toggleMod(_ mod: Mod) {
        guard let index = mods.firstIndex(where: { $0.id.caseInsensitiveCompare(mod.id) == .orderedSame }) else { return }
        if mod.isCoreSMAPI { return }
        mods[index].isEnabled.toggle()
        saveActiveProfileState()
        actionLog.log("\(mods[index].isEnabled ? "Enabled" : "Disabled") mod '\(mod.name)' in profile '\(activeProfile.name)'")
    }

    public func enableAllMods() {
        for i in 0..<mods.count {
            mods[i].isEnabled = true
        }
        saveActiveProfileState()
        actionLog.log("Enabled all mods in profile '\(activeProfile.name)'")
    }

    public func disableAllMods() {
        for i in 0..<mods.count {
            if !mods[i].isCoreSMAPI {
                mods[i].isEnabled = false
            }
        }
        saveActiveProfileState()
        actionLog.log("Disabled all mods in profile '\(activeProfile.name)'")
    }

    public func selectProfile(_ profile: Profile) {
        // 1. If switching from a different profile, save the previous active profile's state first
        if profile.id != activeProfile.id {
            saveActiveProfileState()
            saveSeparatorsState()
        }

        // 2. Load the freshest version of the target profile from disk
        let target = profileService.loadProfiles().first(where: { $0.id == profile.id })
            ?? profiles.first(where: { $0.id == profile.id })
            ?? profile

        self.activeProfile = target
        self.settings.lastSelectedProfileName = target.name
        settingsService.saveSettings(self.settings)
        actionLog.log("Switched to profile '\(target.name)'")

        // 3. Keep in-memory profiles array in sync
        if let idx = self.profiles.firstIndex(where: { $0.id == target.id }) {
            self.profiles[idx] = target
        } else {
            self.profiles.append(target)
        }

        // 4. Load separators for the newly active profile
        self.separators = separatorService.loadSeparators(for: target.name)

        // 5. Apply enabled states for the selected profile, preserving core SMAPI mods
        let enabledSet = Set(target.enabledModIds.map { $0.uniqueId.lowercased() })
        for i in 0..<mods.count {
            if mods[i].isCoreSMAPI {
                mods[i].isEnabled = true
            } else {
                mods[i].isEnabled = enabledSet.contains(mods[i].id.lowercased())
            }
        }
    }

    public func selectProfile(named name: String) {
        self.profiles = profileService.loadProfiles()
        if let target = self.profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            selectProfile(target)
        }
    }

    public func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Save current active profile first
        saveActiveProfileState()
        saveSeparatorsState()

        let existingMap = Dictionary(activeProfile.enabledModIds.map { ($0.uniqueId.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let newEnabledRefs = mods.filter { $0.isEnabled }.map { mod in
            existingMap[mod.id.lowercased()] ?? ModReference(uniqueId: mod.id)
        }

        let newProfile = Profile(
            name: trimmed,
            isProtected: false,
            enabledModIds: newEnabledRefs
        )
        profileService.saveProfile(newProfile)
        self.profiles = profileService.loadProfiles()
        selectProfile(newProfile)
        actionLog.log("Created profile '\(trimmed)'")
    }

    public func deleteProfile(_ profile: Profile) {
        guard !profile.isProtected else { return }
        let isDeletingActive = (activeProfile.id == profile.id)
        profileService.deleteProfile(profile)
        separatorService.deleteSeparators(for: profile.name)
        actionLog.log("Deleted profile '\(profile.name)'")
        self.profiles = profileService.loadProfiles()

        // Clean up any collections dedicated to this deleted profile
        let dedicatedCols = installedCollections.filter {
            $0.profileName.caseInsensitiveCompare(profile.name) == .orderedSame && $0.isDedicatedProfile
        }
        for col in dedicatedCols {
            CollectionPersistenceService.shared.removeCollection(id: col.id)
        }
        if !dedicatedCols.isEmpty {
            refreshInstalledCollections()
        }

        if isDeletingActive {
            if let first = profiles.first {
                self.activeProfile = first
                self.settings.lastSelectedProfileName = first.name
                settingsService.saveSettings(self.settings)
                self.separators = separatorService.loadSeparators(for: first.name)

                let enabledSet = Set(first.enabledModIds.map { $0.uniqueId.lowercased() })
                for i in 0..<mods.count {
                    if mods[i].isCoreSMAPI {
                        mods[i].isEnabled = true
                    } else {
                        mods[i].isEnabled = enabledSet.contains(mods[i].id.lowercased())
                    }
                }
                saveActiveProfileState()
            }
        }
    }

    public func duplicateProfile(_ profile: Profile) {
        saveActiveProfileState()
        saveSeparatorsState()

        let source = (profile.id == activeProfile.id) ? activeProfile : (profiles.first(where: { $0.id == profile.id }) ?? profile)
        let newName = "\(source.name) Copy"
        let copy = profileService.duplicateProfile(source, newName: newName)
        separatorService.duplicateSeparators(from: source.name, to: copy.name)
        self.profiles = profileService.loadProfiles()
        selectProfile(copy)
        actionLog.log("Duplicated profile '\(source.name)' as '\(newName)'")
    }

    public func renameProfile(_ profile: Profile, newName: String) {
        guard !profile.isProtected else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }

        saveActiveProfileState()
        saveSeparatorsState()
        let oldSeparators = separatorService.loadSeparators(for: profile.name)
        separatorService.deleteSeparators(for: profile.name)
        separatorService.saveSeparators(oldSeparators, for: trimmed)

        let isRenamingActive = (activeProfile.id == profile.id)
        let renamed = profileService.renameProfile(profile, newName: trimmed)
        self.profiles = profileService.loadProfiles()
        if isRenamingActive {
            selectProfile(renamed)
        }
        actionLog.log("Renamed profile '\(profile.name)' to '\(trimmed)'")
    }

    public func launchGame() {
        saveActiveProfileState()
        launcher.launch(
            mods: mods,
            gameDirectory: gameDirectory,
            smapiExecutable: pathing.resolveSmapiExecutable(gameDirectory: gameDirectory)
        )
        actionLog.log("Launched SMAPI with profile '\(activeProfile.name)'")
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openLogs() {
        let logFolder = pathing.logsURL
        NSWorkspace.shared.open(logFolder)
    }

    public func openSmapiLog() {
        let smapiLog = pathing.smapiLogURL
        if FileManager.default.fileExists(atPath: smapiLog.path) {
            NSWorkspace.shared.open(smapiLog)
        } else {
            NSWorkspace.shared.open(pathing.smapiLogURL.deletingLastPathComponent())
        }
    }

    public func saveActiveProfileState() {
        let existingMap = Dictionary(activeProfile.enabledModIds.map { ($0.uniqueId.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let knownModsSet = Set(mods.map { $0.id.lowercased() })

        var enabledRefs = mods.filter { $0.isEnabled }.map { mod in
            existingMap[mod.id.lowercased()] ?? ModReference(uniqueId: mod.id)
        }

        // Preserve any references in activeProfile that are not currently present in mods
        for ref in activeProfile.enabledModIds {
            if !knownModsSet.contains(ref.uniqueId.lowercased()) {
                enabledRefs.append(ref)
            }
        }

        activeProfile.enabledModIds = enabledRefs

        // Keep in-memory profiles array in sync
        if let idx = profiles.firstIndex(where: { $0.id == activeProfile.id }) {
            profiles[idx] = activeProfile
        } else {
            profiles.append(activeProfile)
        }

        // Persist to disk
        profileService.saveProfile(activeProfile)
    }

    @MainActor
    public func addInstalledModsToProfile(named profileName: String, uniqueIds: [String]) {
        guard !uniqueIds.isEmpty else { return }
        let cleanName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        // 1. Ensure latest profiles from disk
        let allProfiles = profileService.loadProfiles()
        var targetProfile: Profile

        if let existing = allProfiles.first(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            targetProfile = existing
        } else {
            targetProfile = Profile(name: cleanName, enabledModIds: [])
        }

        // 2. Add unique IDs without duplicates (case-insensitive)
        for uid in uniqueIds {
            if !targetProfile.enabledModIds.contains(where: { $0.uniqueId.caseInsensitiveCompare(uid) == .orderedSame }) {
                targetProfile.enabledModIds.append(ModReference(uniqueId: uid))
            }
        }

        // 3. Save to disk
        profileService.saveProfile(targetProfile)
        self.profiles = profileService.loadProfiles()

        // 4. If this is the active profile, update activeProfile directly
        if activeProfile.name.caseInsensitiveCompare(cleanName) == .orderedSame {
            self.activeProfile = targetProfile
            refreshMods()

            // 6. Explicitly ensure activeProfile and mods in memory have all new IDs enabled
            let targetIdSet = Set(uniqueIds.map { $0.lowercased() })
            for i in 0..<mods.count {
                if targetIdSet.contains(mods[i].id.lowercased()) {
                    mods[i].isEnabled = true
                }
            }
            saveActiveProfileState()
        } else {
            refreshMods()
        }
    }

    // MARK: - Separator Actions

    public func saveSeparatorsState() {
        separatorService.saveSeparators(separators, for: activeProfile.name)
    }

    public func promptNewSeparator(forModId modId: String? = nil) {
        pendingNewSeparatorModId = modId
        isNewSeparatorPresented = true
    }

    public func createSeparator(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var initialModIds: [String] = []
        if let modId = pendingNewSeparatorModId {
            initialModIds = [modId]
            for i in 0..<separators.count {
                separators[i].modIds.removeAll { $0.caseInsensitiveCompare(modId) == .orderedSame }
            }
            pendingNewSeparatorModId = nil
        }

        let newSeparator = ModSeparator(name: trimmed, isExpanded: true, modIds: initialModIds)
        separators.append(newSeparator)
        saveSeparatorsState()
        actionLog.log("Created separator '\(trimmed)'")
    }

    public func renameSeparator(_ separator: ModSeparator, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = separators.firstIndex(where: { $0.id == separator.id }) else { return }
        separators[idx].name = trimmed
        saveSeparatorsState()
        actionLog.log("Renamed separator '\(separator.name)' to '\(trimmed)'")
    }

    public func deleteSeparator(_ separator: ModSeparator) {
        separators.removeAll { $0.id == separator.id }
        saveSeparatorsState()
        actionLog.log("Deleted separator '\(separator.name)'")
    }

    public func moveSeparatorUp(_ separator: ModSeparator) {
        guard let idx = separators.firstIndex(where: { $0.id == separator.id }), idx > 0 else { return }
        separators.swapAt(idx, idx - 1)
        saveSeparatorsState()
    }

    public func moveSeparatorDown(_ separator: ModSeparator) {
        guard let idx = separators.firstIndex(where: { $0.id == separator.id }), idx < separators.count - 1 else { return }
        separators.swapAt(idx, idx + 1)
        saveSeparatorsState()
    }

    /// Moves a separator so it occupies the position previously held by `targetId`.
    public func moveSeparator(id: UUID, toIndexAt targetId: UUID) {
        guard let from = separators.firstIndex(where: { $0.id == id }),
              var targetIdx = separators.firstIndex(where: { $0.id == targetId }),
              from != targetIdx else { return }
        let item = separators.remove(at: from)
        if targetIdx > from { targetIdx -= 1 }
        separators.insert(item, at: targetIdx)
        saveSeparatorsState()
        actionLog.log("Moved separator '\(item.name)' to position \(targetIdx + 1)")
    }

    /// Moves (or unassigns) a mod. When `target` is nil the mod is removed from all separators.
    /// `atIndex` refers to a position in the target separator's mod list with the dragged mod already removed.
    public func moveMod(id: String, toSeparator target: ModSeparator?, atIndex index: Int?) {
        let storedId: String
        if let found = separators.flatMap(\.modIds).first(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
            storedId = found
        } else if let mod = mods.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            storedId = mod.id
        } else {
            return
        }

        for i in separators.indices {
            separators[i].modIds.removeAll { $0.caseInsensitiveCompare(id) == .orderedSame }
        }

        if let target = target, let tIdx = separators.firstIndex(where: { $0.id == target.id }) {
            let insertAt = min(max(index ?? separators[tIdx].modIds.count, 0), separators[tIdx].modIds.count)
            separators[tIdx].modIds.insert(storedId, at: insertAt)
            actionLog.log("Moved mod '\(storedId)' to separator '\(target.name)'")
        } else {
            actionLog.log("Unassigned mod '\(storedId)' from separators")
        }
        saveSeparatorsState()
    }

    public func toggleSeparatorExpansion(_ separator: ModSeparator) {
        guard let idx = separators.firstIndex(where: { $0.id == separator.id }) else { return }
        separators[idx].isExpanded.toggle()
        saveSeparatorsState()
    }

    public func collapseAllSeparators() {
        for i in 0..<separators.count {
            separators[i].isExpanded = false
        }
        saveSeparatorsState()
    }

    public func expandAllSeparators() {
        for i in 0..<separators.count {
            separators[i].isExpanded = true
        }
        saveSeparatorsState()
    }

    public func separator(for mod: Mod) -> ModSeparator? {
        separator(forId: mod.id)
    }

    public func separator(forId modId: String) -> ModSeparator? {
        separators.first { $0.modIds.contains { $0.caseInsensitiveCompare(modId) == .orderedSame } }
    }

    public func assignMod(_ mod: Mod, to targetSeparator: ModSeparator?) {
        let id = mod.id
        for i in 0..<separators.count {
            separators[i].modIds.removeAll { $0.caseInsensitiveCompare(id) == .orderedSame }
        }
        if let target = targetSeparator, let idx = separators.firstIndex(where: { $0.id == target.id }) {
            separators[idx].modIds.append(mod.id)
        }
        saveSeparatorsState()
    }

    public func moveModUpInSeparator(_ mod: Mod) {
        guard let sep = separator(for: mod),
              let sepIdx = separators.firstIndex(where: { $0.id == sep.id }),
              let modIdx = separators[sepIdx].modIds.firstIndex(where: { $0.caseInsensitiveCompare(mod.id) == .orderedSame }),
              modIdx > 0 else { return }
        separators[sepIdx].modIds.swapAt(modIdx, modIdx - 1)
        saveSeparatorsState()
    }

    public func moveModDownInSeparator(_ mod: Mod) {
        guard let sep = separator(for: mod),
              let sepIdx = separators.firstIndex(where: { $0.id == sep.id }),
              let modIdx = separators[sepIdx].modIds.firstIndex(where: { $0.caseInsensitiveCompare(mod.id) == .orderedSame }),
              modIdx < separators[sepIdx].modIds.count - 1 else { return }
        separators[sepIdx].modIds.swapAt(modIdx, modIdx + 1)
        saveSeparatorsState()
    }

    public func enableAllModsInSeparator(_ separator: ModSeparator) {
        let modIdSet = Set(separator.modIds.map { $0.lowercased() })
        for i in 0..<mods.count {
            if modIdSet.contains(mods[i].id.lowercased()) {
                mods[i].isEnabled = true
            }
        }
        saveActiveProfileState()
    }

    public func disableAllModsInSeparator(_ separator: ModSeparator) {
        let modIdSet = Set(separator.modIds.map { $0.lowercased() })
        for i in 0..<mods.count {
            if modIdSet.contains(mods[i].id.lowercased()) && !mods[i].isCoreSMAPI {
                mods[i].isEnabled = false
            }
        }
        saveActiveProfileState()
    }

    public func autoGenerateSeparatorsFromFolders() {
        let modsRoot = modsDirectory.standardizedFileURL.path
        let fileManager = FileManager.default

        // Single pass: separator folder name -> Set of mod ids (deduped, case-insensitively keyed)
        var groups: [String: (displayName: String, ids: Set<String>)] = [:]
        for mod in mods {
            let modPath = mod.directoryURL.standardizedFileURL.path
            guard modPath.hasPrefix(modsRoot) else { continue }

            let relative = modPath.dropFirst(modsRoot.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = relative.split(separator: "/", omittingEmptySubsequences: true)

            // Mod folder sitting directly in the Mods root is not inside a separator folder
            if components.count <= 1 {
                guard mod.isCoreSMAPI else { continue }
                let key = "core"
                if groups[key] == nil { groups[key] = ("Core", []) }
                groups[key]?.ids.insert(mod.id)
                continue
            }

            // The folder directly under Mods defines the separator; nesting below
            // it is allowed (separator tree), any depth rolls up to this folder.
            let folderName = String(components[0])
            let folderURL = URL(fileURLWithPath: modsRoot).appendingPathComponent(folderName)
            let manifestURL = folderURL.appendingPathComponent("manifest.json")

            // No manifest.json in that folder => it is a separator folder, not a mod
            guard !fileManager.fileExists(atPath: manifestURL.path) else { continue }

            let key = folderName.lowercased()
            if groups[key] == nil {
                groups[key] = (folderName, [])
            }
            groups[key]?.ids.insert(mod.id)
        }
        guard !groups.isEmpty else { return }

        // O(1) lookup of existing separators by lowercased name
        var indexByName: [String: Int] = [:]
        indexByName.reserveCapacity(separators.count)
        for (index, separator) in separators.enumerated() {
            indexByName[separator.name.lowercased()] = index
        }

        for (key, group) in groups.sorted(by: { $0.value.displayName.localizedCaseInsensitiveCompare($1.value.displayName) == .orderedAscending }) {
            if let idx = indexByName[key] {
                var existing = Set(separators[idx].modIds)
                existing.formUnion(group.ids)
                separators[idx].modIds = Array(existing)
            } else {
                indexByName[key] = separators.count
                separators.append(ModSeparator(name: group.displayName, isExpanded: true, modIds: Array(group.ids)))
            }
        }
        saveSeparatorsState()
    }

    // MARK: - Nexus Endorsements

    public func fetchEndorsements() async {
        guard isNexusConnected, let apiKey = nexusApiKey, !apiKey.isEmpty else {
            return
        }

        do {
            let endorsements = try await NexusService.shared.getEndorsements(apiKey: apiKey)
            await MainActor.run {
                let endorsementMap = Dictionary(endorsements.map { ($0.modId, $0.isEndorsed) }, uniquingKeysWith: { first, _ in first })
                for i in 0..<self.mods.count {
                    if let modId = self.mods[i].nexusModId {
                        if let isEndorsed = endorsementMap[modId] {
                            self.mods[i].isEndorsed = isEndorsed
                        }
                    }
                }
            }
        } catch {
            print("Failed to fetch endorsements from Nexus Mods: \(error)")
        }
    }

    public func toggleEndorsement(for mod: Mod) async {
        guard let modId = mod.nexusModId else { return }

        guard isNexusConnected, let apiKey = nexusApiKey, !apiKey.isEmpty else {
            await MainActor.run {
                self.endorsementAlertMessage = "Please connect your Nexus Mods account in Settings before endorsing mods."
            }
            return
        }

        await MainActor.run {
            for i in 0..<self.mods.count {
                if self.mods[i].nexusModId == modId {
                    self.mods[i].isEndorsing = true
                }
            }
        }

        let targetState = !mod.isEndorsed

        do {
            let response = try await NexusService.shared.setModEndorsement(modId: modId, endorse: targetState, apiKey: apiKey)

            await MainActor.run {
                for i in 0..<self.mods.count {
                    if self.mods[i].nexusModId == modId {
                        self.mods[i].isEndorsing = false
                    }
                }

                switch response {
                case .endorsed:
                    for i in 0..<self.mods.count {
                        if self.mods[i].nexusModId == modId {
                            self.mods[i].isEndorsed = true
                        }
                    }
                case .abstained:
                    for i in 0..<self.mods.count {
                        if self.mods[i].nexusModId == modId {
                            self.mods[i].isEndorsed = false
                        }
                    }
                case .isOwnMod:
                    self.endorsementAlertMessage = "Unable to set the endorsement state:\n\nYou are the owner of this mod."
                case .tooSoonAfterDownload:
                    self.endorsementAlertMessage = "Unable to set the endorsement state:\n\nYou must wait 15 minutes after downloading this mod.\n\nAttempting to endorse will reset this timer."
                case .notDownloadedMod:
                    self.endorsementAlertMessage = "Unable to set the endorsement state:\n\nYou must download this mod from Nexus Mods in order to endorse it."
                case .unknown(let msg):
                    let details = msg ?? "An unknown error occurred."
                    self.endorsementAlertMessage = "Unable to set the endorsement state:\n\n\(details)"
                }
                ActionLogger.shared.log("Set endorsement for mod '\(mod.name)' to \(targetState ? "endorsed" : "abstained")")
            }
        } catch {
            await MainActor.run {
                for i in 0..<self.mods.count {
                    if self.mods[i].nexusModId == modId {
                        self.mods[i].isEndorsing = false
                    }
                }
                self.endorsementAlertMessage = "Unable to set the endorsement state:\n\n\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Mod Archive Installation

    public func promptInstallModArchive() {
        let panel = NSOpenPanel()
        panel.title = "Install Mod Archive"
        panel.prompt = "Install"
        panel.message = "Choose mod archive files (.zip, .7z, .rar, .tar.gz) or mod folders"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        var contentTypes: [UTType] = [.zip, .gzip, .bz2]
        if let t7z = UTType(filenameExtension: "7z") { contentTypes.append(t7z) }
        if let rar = UTType(filenameExtension: "rar") { contentTypes.append(rar) }
        if let tar = UTType(filenameExtension: "tar") { contentTypes.append(tar) }
        contentTypes.append(.folder)
        panel.allowedContentTypes = contentTypes

        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task {
                await installMods(from: urls)
            }
        }
    }

    public func installMods(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        // Check if single URL is a Nexus Collection archive or directory
        if urls.count == 1, let firstURL = urls.first {
            if CollectionService.shared.isCollectionFile(at: firstURL) {
                if let inspected = try? CollectionService.shared.inspect(url: firstURL) {
                    await MainActor.run {
                        self.activeCollectionPackage = ActiveCollectionPackage(
                            manifest: inspected.manifest,
                            contentURL: inspected.contentURL,
                            isTemporary: inspected.isTemporary
                        )
                        self.isCollectionInstallPresented = true
                    }
                    return
                }
            }
        }

        await MainActor.run {
            self.isInstallingMods = true
            self.modInstallProgressMessage = "Installing \(urls.count) item\(urls.count == 1 ? "" : "s")..."
        }

        do {
            let summary = try await ModInstallerService.shared.installMods(
                from: urls,
                into: self.modsDirectory,
                existingMods: self.mods
            )

            await MainActor.run {
                self.isInstallingMods = false
                self.modInstallProgressMessage = nil

                let installedIds = summary.installedMods.map { $0.uniqueID }
                self.addInstalledModsToProfile(named: self.activeProfile.name, uniqueIds: installedIds)
                ActionLogger.shared.log("Installed \(summary.installedMods.count) mod(s) into profile '\(self.activeProfile.name)': \(summary.installedMods.map { $0.modName }.joined(separator: ", "))")

                if let first = summary.installedMods.first {
                    self.selectAndRevealMod(id: first.uniqueID)
                }

                var messageLines: [String] = []
                if !summary.installedMods.isEmpty {
                    let count = summary.installedMods.count
                    messageLines.append("Successfully installed \(count) mod\(count == 1 ? "" : "s"):")
                    for installed in summary.installedMods {
                        let action = installed.isUpdate ? "Updated" : "Installed"
                        messageLines.append("• \(installed.modName) v\(installed.version) (\(action))")
                    }
                }

                if !summary.warnings.isEmpty {
                    if !messageLines.isEmpty { messageLines.append("") }
                    messageLines.append("Warnings:")
                    for w in summary.warnings {
                        messageLines.append("• \(w)")
                    }
                }

                if !summary.errors.isEmpty {
                    if !messageLines.isEmpty { messageLines.append("") }
                    messageLines.append("Errors:")
                    for e in summary.errors {
                        messageLines.append("• \(e)")
                    }
                }

                if !messageLines.isEmpty {
                    self.modInstallResultAlert = messageLines.joined(separator: "\n")
                }
            }
        } catch {
            await MainActor.run {
                self.isInstallingMods = false
                self.modInstallProgressMessage = nil
                self.modInstallResultAlert = "Failed to install mods: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Free User Download Queue & Collection Assistant

    @MainActor
    public func startFreeUserQueue(
        mods: [CollectionMod],
        targetProfileName: String,
        separatorName: String,
        collectionName: String,
        slug: String? = nil,
        revisionNumber: Int? = nil,
        domainName: String? = nil,
        isDedicatedProfile: Bool = false
    ) {
        let smapiVersion = self.settings.gameDetails?.smapiVersion
        let manager = CollectionQueueManager(
            mods: mods,
            targetProfileName: targetProfileName,
            separatorName: separatorName,
            collectionName: collectionName,
            slug: slug,
            revisionNumber: revisionNumber,
            domainName: domainName,
            existingMods: self.mods,
            currentSMAPIVersion: smapiVersion,
            modsDirectory: self.modsDirectory,
            isDedicatedProfile: isDedicatedProfile
        )
        self.activeQueueManager = manager
        self.isFreeUserQueuePresented = true
        manager.startQueue()
        actionLog.log("Started collection download queue for '\(collectionName)' into profile '\(targetProfileName)'")
    }

    @MainActor
    public func applyCompletedQueue(manager: CollectionQueueManager) {
        refreshMods()

        let installedItems = manager.items.filter { $0.status == .installed }
        guard !installedItems.isEmpty else {
            self.activeQueueManager = nil
            self.isFreeUserQueuePresented = false
            return
        }

        var installedUniqueIds: [String] = []
        let smapiVersion = self.settings.gameDetails?.smapiVersion
        for item in installedItems {
            for uid in item.installedUniqueIds {
                if !installedUniqueIds.contains(where: { $0.caseInsensitiveCompare(uid) == .orderedSame }) {
                    installedUniqueIds.append(uid)
                }
            }
            if let matched = item.mod.findMatchingMod(in: self.mods, currentSMAPIVersion: smapiVersion) {
                if !installedUniqueIds.contains(where: { $0.caseInsensitiveCompare(matched.id) == .orderedSame }) {
                    installedUniqueIds.append(matched.id)
                }
            }
        }

        guard !installedUniqueIds.isEmpty else {
            self.activeQueueManager = nil
            self.isFreeUserQueuePresented = false
            return
        }

        // Add mods to target profile and save to disk
        addInstalledModsToProfile(named: manager.targetProfileName, uniqueIds: installedUniqueIds)

        // Add to collection separator
        var existingSeparators = separatorService.loadSeparators(for: manager.targetProfileName)
        let sepName = manager.separatorName
        if let idx = existingSeparators.firstIndex(where: { $0.name.caseInsensitiveCompare(sepName) == .orderedSame }) {
            var set = Set(existingSeparators[idx].modIds)
            for uniqueId in installedUniqueIds {
                set.insert(uniqueId)
            }
            existingSeparators[idx].modIds = Array(set)
        } else {
            let newSep = ModSeparator(name: sepName, isExpanded: true, modIds: installedUniqueIds)
            existingSeparators.append(newSep)
        }
        separatorService.saveSeparators(existingSeparators, for: manager.targetProfileName)

        // Track or update InstalledCollection record if slug is present
        if let slug = manager.slug, !slug.isEmpty {
            let domain = manager.domainName ?? "stardewvalley"
            let collectionRecord = InstalledCollection(
                slug: slug,
                domainName: domain,
                revisionNumber: manager.revisionNumber ?? 1,
                name: manager.collectionName,
                installedDate: Date(),
                profileName: manager.targetProfileName,
                installedModIds: installedUniqueIds,
                isDedicatedProfile: manager.isDedicatedProfile
            )
            CollectionPersistenceService.shared.addOrUpdateCollection(collectionRecord)
            refreshInstalledCollections()
        }

        self.activeQueueManager = nil
        self.isFreeUserQueuePresented = false

        selectProfile(named: manager.targetProfileName)
        refreshMods()
        actionLog.log("Applied completed download queue for collection '\(manager.collectionName)'")
    }

    // MARK: - Installed Collections & Updates

    public func refreshInstalledCollections() {
        self.installedCollections = CollectionPersistenceService.shared.loadCollections()
    }

    public func checkForCollectionUpdates(userInitiated: Bool = true) async {
        let collections = CollectionPersistenceService.shared.loadCollections()
        guard !collections.isEmpty else {
            if userInitiated {
                await MainActor.run {
                    self.updateCheckMessage = "No collections are currently installed."
                }
            }
            return
        }

        await MainActor.run {
            self.isCheckingCollectionUpdates = true
        }

        var updateCount = 0
        for col in collections {
            var mutableCol = col
            do {
                let latestRev = try await NexusService.shared.getCollectionRevision(
                    slug: col.slug,
                    revision: nil,
                    domainName: col.domainName,
                    apiKey: self.nexusApiKey
                )
                mutableCol.lastCheckedDate = Date()
                if let latestNum = latestRev.revisionNumber {
                    mutableCol.latestRevisionNumber = latestNum
                    if latestNum > col.revisionNumber {
                        updateCount += 1
                    }
                }
            } catch {
                print("Failed to check update for collection \(col.slug): \(error)")
            }
            CollectionPersistenceService.shared.addOrUpdateCollection(mutableCol)
        }

        await MainActor.run {
            self.refreshInstalledCollections()
            self.isCheckingCollectionUpdates = false
            if userInitiated {
                if updateCount > 0 {
                    self.updateCheckMessage = "\(updateCount) collection update\(updateCount == 1 ? "" : "s") available."
                } else {
                    self.updateCheckMessage = "All installed collections are up to date."
                }
            }
            ActionLogger.shared.log("Checked updates for \(collections.count) collection(s): \(updateCount) update(s) available")
        }
    }

    public func checkForCollectionUpdate(for collection: InstalledCollection) async {
        await MainActor.run {
            self.isCheckingCollectionUpdates = true
        }

        var mutableCol = collection
        do {
            let latestRev = try await NexusService.shared.getCollectionRevision(
                slug: collection.slug,
                revision: nil,
                domainName: collection.domainName,
                apiKey: self.nexusApiKey
            )
            mutableCol.lastCheckedDate = Date()
            if let latestNum = latestRev.revisionNumber {
                mutableCol.latestRevisionNumber = latestNum
            }
            CollectionPersistenceService.shared.addOrUpdateCollection(mutableCol)

            await MainActor.run {
                self.refreshInstalledCollections()
                self.isCheckingCollectionUpdates = false
                if let latestNum = latestRev.revisionNumber, latestNum > collection.revisionNumber {
                    self.updateCheckMessage = "Revision \(latestNum) is available for '\(collection.name)' (currently on revision \(collection.revisionNumber))."
                } else {
                    self.updateCheckMessage = "'\(collection.name)' is up to date (revision \(collection.revisionNumber))."
                }
            }
        } catch {
            await MainActor.run {
                self.refreshInstalledCollections()
                self.isCheckingCollectionUpdates = false
                self.updateCheckMessage = "Failed to check update for '\(collection.name)': \(error.localizedDescription)"
            }
        }
    }

    public func updateCollection(_ collection: InstalledCollection) {
        let targetRev = collection.latestRevisionNumber ?? (collection.revisionNumber + 1)
        Task { @MainActor in
            await self.handleIncomingCollection(
                gameId: collection.domainName,
                slug: collection.slug,
                revisionNumber: targetRev
            )
        }
    }

    public func promptRemoveCollection(_ collection: InstalledCollection) {
        self.collectionPendingRemoval = collection
    }

    public func canDeleteAssociatedProfile(for collection: InstalledCollection) -> Bool {
        guard let prof = profiles.first(where: { $0.name.caseInsensitiveCompare(collection.profileName) == .orderedSame }) else {
            return false
        }
        guard !prof.isProtected else {
            return false
        }
        return collection.isDedicatedProfile || collection.profileName.hasPrefix("[Collection]")
    }

    public func confirmRemoveCollection(deleteProfile: Bool) {
        guard let collection = collectionPendingRemoval else { return }

        CollectionPersistenceService.shared.removeCollection(id: collection.id)
        refreshInstalledCollections()
        actionLog.log("Removed collection '\(collection.name)' (profile '\(collection.profileName)', deleteProfile: \(deleteProfile))")

        if deleteProfile {
            if let prof = profiles.first(where: { $0.name.caseInsensitiveCompare(collection.profileName) == .orderedSame }), !prof.isProtected {
                self.deleteProfile(prof)
            }
        }

        self.collectionPendingRemoval = nil
    }

    public func deleteCollectionRecord(_ collection: InstalledCollection) {
        promptRemoveCollection(collection)
    }

    // MARK: - NXM Deep Link Handler

    @MainActor
    public func handleOpenURL(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let parsed = NXMUrlParser.parse(url)
        switch parsed {
        case .mod(let gameId, let modId, let fileId, let key, let expires, _):
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                await self.handleIncomingModDownload(
                    gameDomain: gameId,
                    modId: modId,
                    fileId: fileId,
                    key: key,
                    expires: expires
                )
            }

        case .collection(let gameId, let slug, let revisionNumber):
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                await self.handleIncomingCollection(
                    gameId: gameId,
                    slug: slug,
                    revisionNumber: revisionNumber
                )
            }

        case .unknown(let urlStr):
            print("Unhandled NXM or URL: \(urlStr)")
        }
    }

    @MainActor
    private func handleIncomingModDownload(
        gameDomain: String,
        modId: Int,
        fileId: Int,
        key: String?,
        expires: Int?
    ) async {
        if let queueManager = self.activeQueueManager {
            let handled = await queueManager.handleIncomingNXM(
                gameId: gameDomain,
                modId: modId,
                fileId: fileId,
                key: key,
                expires: expires,
                apiKey: self.nexusApiKey,
                modsDirectory: self.modsDirectory,
                existingMods: self.mods
            )
            if handled {
                return
            }
        }

        self.isInstallingMods = true
        self.modInstallProgressMessage = "Downloading mod \(modId)..."

        let cacheDir = pathing.collectionDownloadsURL
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let destinationFile = cacheDir.appendingPathComponent("\(modId)_\(fileId).zip")

        do {
            let apiKeyToUse = self.nexusApiKey ?? ""
            let links = try await NexusService.shared.getModDownloadURLs(
                gameDomain: gameDomain,
                modId: modId,
                fileId: fileId,
                apiKey: apiKeyToUse.isEmpty ? (key ?? "") : apiKeyToUse,
                key: key,
                expires: expires
            )

            guard let primary = links.first?.uri, let downloadURL = URL(string: primary) else {
                throw NSError(domain: "NXMDownload", code: 404, userInfo: [NSLocalizedDescriptionKey: "No download mirrors returned."])
            }

            try await NexusService.shared.downloadFile(from: downloadURL, to: destinationFile) { progress in
                Task { @MainActor in
                    self.modInstallProgressMessage = "Downloading mod (\(Int(progress * 100))%)..."
                }
            }

            self.modInstallProgressMessage = "Installing mod..."
            let summary = try await ModInstallerService.shared.installMods(
                from: [destinationFile],
                into: self.modsDirectory,
                existingMods: self.mods
            )

            self.isInstallingMods = false
            self.modInstallProgressMessage = nil

            let installedIds = summary.installedMods.map { $0.uniqueID }
            self.addInstalledModsToProfile(named: self.activeProfile.name, uniqueIds: installedIds)

            if let queueManager = self.activeQueueManager {
                for item in queueManager.items where !item.status.isTerminal {
                    if item.mod.source.modId == modId || item.status == .awaitingBrowser {
                        item.installedUniqueIds = installedIds
                        item.status = .installed
                        queueManager.advanceToNextPending()
                        break
                    }
                }
            }

            if let first = summary.installedMods.first {
                self.selectAndRevealMod(id: first.uniqueID)
                self.modInstallResultAlert = "Successfully installed \(first.modName) v\(first.version)."
            }
        } catch {
            self.isInstallingMods = false
            self.modInstallProgressMessage = nil
            self.modInstallResultAlert = "Failed to download mod from Nexus: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func handleIncomingCollection(
        gameId: String,
        slug: String,
        revisionNumber: Int?
    ) async {
        self.isInstallingMods = true
        self.modInstallProgressMessage = "Fetching collection '\(slug)' metadata..."

        do {
            let revData = try await NexusService.shared.getCollectionRevision(
                slug: slug,
                revision: revisionNumber,
                domainName: gameId,
                apiKey: self.nexusApiKey
            )

            guard let downloadLink = revData.downloadLink, !downloadLink.isEmpty else {
                throw NSError(domain: "NXMCollection", code: 404, userInfo: [NSLocalizedDescriptionKey: "No download link available for this collection revision."])
            }

            guard let apiKey = self.nexusApiKey, !apiKey.isEmpty else {
                self.isInstallingMods = false
                self.modInstallProgressMessage = nil
                self.modInstallResultAlert = "Please connect your Nexus Mods account in Settings before downloading collections."
                return
            }

            self.modInstallProgressMessage = "Resolving collection download..."
            let mirrors = try await NexusService.shared.getCollectionDownloadURLs(
                from: downloadLink,
                apiKey: apiKey
            )

            guard let firstMirror = mirrors.first?.uri, let downloadURL = URL(string: firstMirror) else {
                throw NSError(domain: "NXMCollection", code: 404, userInfo: [NSLocalizedDescriptionKey: "No download mirror returned for collection archive."])
            }

            let cacheDir = pathing.collectionDownloadsURL
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let revNumStr = revData.revisionNumber != nil ? "_\(revData.revisionNumber!)" : ""
            let archiveDest = cacheDir.appendingPathComponent("\(slug)\(revNumStr).7z")

            self.modInstallProgressMessage = "Downloading collection package..."
            try await NexusService.shared.downloadFile(from: downloadURL, to: archiveDest) { progress in
                Task { @MainActor in
                    self.modInstallProgressMessage = "Downloading collection package (\(Int(progress * 100))%)..."
                }
            }

            self.modInstallProgressMessage = "Inspecting collection..."
            let inspected = try CollectionService.shared.inspect(url: archiveDest)

            self.isInstallingMods = false
            self.modInstallProgressMessage = nil

            self.activeCollectionPackage = ActiveCollectionPackage(
                manifest: inspected.manifest,
                contentURL: inspected.contentURL,
                isTemporary: inspected.isTemporary,
                slug: slug,
                revisionNumber: revData.revisionNumber ?? revisionNumber,
                domainName: gameId
            )
            self.isCollectionInstallPresented = true
        } catch {
            self.isInstallingMods = false
            self.modInstallProgressMessage = nil
            self.modInstallResultAlert = "Failed to load collection from Nexus: \(error.localizedDescription)"
        }
    }

    // MARK: - Mod Deletion & Dependency Verification

    public func findEnabledDependents(for mod: Mod) -> [Mod] {
        findEnabledDependents(forMods: [mod])
    }

    public func findEnabledDependents(forMods targets: [Mod]) -> [Mod] {
        let targetIdSet = Set(targets.map { $0.id.lowercased() })
        return mods.filter { other in
            guard !targetIdSet.contains(other.id.lowercased()), other.isEnabled else { return false }
            return other.manifest.allDependencies.contains { dep in
                dep.isRequired && targetIdSet.contains(dep.uniqueID.lowercased())
            }
        }
    }

    public func promptDeleteMod(_ mod: Mod) {
        guard !mod.isCoreSMAPI else {
            self.modInstallResultAlert = "Core SMAPI component '\(mod.name)' cannot be deleted as it is required by SMAPI."
            return
        }
        let dependents = findEnabledDependents(for: mod)
        self.modToDelete = ModDeletionPrompt(mod: mod, dependentMods: dependents)
    }

    public func promptDeleteSelectedMods() {
        let targets = selectedMods.filter { !$0.isCoreSMAPI }
        guard !targets.isEmpty else {
            if let first = selectedMod, first.isCoreSMAPI {
                self.modInstallResultAlert = "Core SMAPI component '\(first.name)' cannot be deleted as it is required by SMAPI."
            }
            return
        }

        if targets.count == 1 {
            promptDeleteMod(targets[0])
            return
        }

        let dependents = findEnabledDependents(forMods: targets)
        self.modToDelete = ModDeletionPrompt(mods: targets, dependentMods: dependents)
    }

    public func confirmDeleteMod() {
        guard let prompt = modToDelete else { return }
        let toDelete = prompt.mods
        self.modToDelete = nil
        deleteMods(toDelete)
    }

    public func deleteMods(_ modsToDelete: [Mod]) {
        let fileManager = FileManager.default
        let deleteIds = Set(modsToDelete.filter { !$0.isCoreSMAPI }.map { $0.id.lowercased() })
        guard !deleteIds.isEmpty else { return }

        // 1. Deselect deleted mods
        selectedModIds = selectedModIds.filter { !deleteIds.contains($0.lowercased()) }
        if let current = selectedModId, deleteIds.contains(current.lowercased()) {
            selectedModId = selectedModIds.first
            selectionAnchorId = selectedModId
        }

        // 2. Remove from active profile and all saved profiles
        let savedProfiles = profileService.loadProfiles()
        for var p in savedProfiles {
            let originalCount = p.enabledModIds.count
            p.enabledModIds.removeAll { deleteIds.contains($0.uniqueId.lowercased()) }
            if p.enabledModIds.count != originalCount {
                profileService.saveProfile(p)
            }
        }
        self.profiles = profileService.loadProfiles()
        if let current = self.profiles.first(where: { $0.id == activeProfile.id }) {
            self.activeProfile = current
        }

        // 3. Remove from separators
        for i in 0..<separators.count {
            separators[i].modIds.removeAll { deleteIds.contains($0.lowercased()) }
        }
        saveSeparatorsState()

        // 4. Move mod directories to Trash
        for mod in modsToDelete where !mod.isCoreSMAPI {
            if fileManager.fileExists(atPath: mod.directoryURL.path) {
                do {
                    try fileManager.trashItem(at: mod.directoryURL, resultingItemURL: nil)
                } catch {
                    try? fileManager.removeItem(at: mod.directoryURL)
                }
            }
        }

        // 5. Refresh mod list
        refreshMods()
        actionLog.log("Deleted \(deleteIds.count) mod(s): \(modsToDelete.map { $0.name }.joined(separator: ", "))")
    }

    public func deleteMod(_ mod: Mod) {
        deleteMods([mod])
    }
}
