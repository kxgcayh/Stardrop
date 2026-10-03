import Foundation
import Combine
import SwiftUI

public enum SidebarCategory: Hashable {
    case allMods
    case enabledOnly
    case disabledOnly
    case updatableOnly
}

public final class AppState: ObservableObject {
    @Published public var mods: [Mod] = []
    @Published public var profiles: [Profile] = []
    @Published public var activeProfile: Profile
    @Published public var selectedModId: String?
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

    public var availableUpdatesCount: Int {
        mods.filter { $0.hasUpdate }.count
    }
    @Published public var editingMod: Mod?
    @Published public var separators: [ModSeparator] = []
    @Published public var isNewSeparatorPresented: Bool = false
    @Published public var pendingNewSeparatorModId: String? = nil
    @Published public var separatorToRename: ModSeparator? = nil

    public var areAllSeparatorsExpanded: Bool {
        guard !separators.isEmpty else { return true }
        return separators.allSatisfy { $0.isExpanded }
    }

    public var isNexusConnected: Bool {
        guard let key = settings.nexusDetails.key, !key.isEmpty else { return false }
        return settings.nexusDetails.username != nil
    }

    public let launcher = SMAPILauncherService.shared

    private let pathing = PathingService.shared
    private let scanner = ModScannerService.shared
    private let profileService = ProfileService.shared
    private let settingsService = SettingsService.shared
    private let separatorService = SeparatorService.shared

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

    public func toggleSelectedMod() {
        if let mod = selectedMod {
            toggleMod(mod)
        } else if let first = visibleModsInDisplayOrder.first {
            selectedModId = first.id
            toggleMod(first)
        }
    }

    @discardableResult
    public func selectNextMod() -> Bool {
        let list = visibleModsInDisplayOrder
        guard !list.isEmpty else { return false }
        guard let currentId = selectedModId,
              let currentIndex = list.firstIndex(where: { $0.id.caseInsensitiveCompare(currentId) == .orderedSame }) else {
            selectedModId = list.first?.id
            if let id = selectedModId { scrollTargetModId = id }
            return true
        }
        let nextIndex = min(currentIndex + 1, list.count - 1)
        if nextIndex != currentIndex {
            let nextMod = list[nextIndex]
            selectedModId = nextMod.id
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
            selectedModId = list.first?.id
            if let id = selectedModId { scrollTargetModId = id }
            return true
        }
        let prevIndex = max(currentIndex - 1, 0)
        if prevIndex != currentIndex {
            let prevMod = list[prevIndex]
            selectedModId = prevMod.id
            scrollTargetModId = prevMod.id
            return true
        }
        return false
    }

    // MARK: - Actions

    public func refreshMods() {
        let enabledSet = Set(activeProfile.enabledModIds.map { $0.uniqueId.lowercased() })
        let previousUpdates = Dictionary(mods.compactMap { mod -> (String, (String?, URL?))? in
            guard mod.suggestedVersion != nil else { return nil }
            return (mod.id.lowercased(), (mod.suggestedVersion, mod.updateURL))
        }, uniquingKeysWith: { first, _ in first })
        var scanned = scanner.scanMods(in: modsDirectory, enabledIds: enabledSet)
        for i in 0..<scanned.count {
            if let prev = previousUpdates[scanned[i].id.lowercased()] {
                scanned[i].suggestedVersion = prev.0
                scanned[i].updateURL = prev.1
            }
        }
        self.mods = scanned
        if let id = selectedModId, !scanned.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            selectedModId = scanned.first?.id
        } else if selectedModId == nil {
            selectedModId = scanned.first?.id
        }
        saveActiveProfileState()
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

        // Set selected mod ID
        selectedModId = targetMod.id

        // Trigger scroll notification
        scrollTargetModId = nil
        DispatchQueue.main.async {
            self.scrollTargetModId = targetMod.id
        }
    }

    public func setModEnabled(_ mod: Mod, isEnabled: Bool) {
        guard let index = mods.firstIndex(where: { $0.id.caseInsensitiveCompare(mod.id) == .orderedSame }) else { return }
        if mod.isCoreSMAPI && !isEnabled { return }
        if mods[index].isEnabled != isEnabled {
            mods[index].isEnabled = isEnabled
            saveActiveProfileState()
        }
    }

    public func toggleMod(_ mod: Mod) {
        guard let index = mods.firstIndex(where: { $0.id.caseInsensitiveCompare(mod.id) == .orderedSame }) else { return }
        if mod.isCoreSMAPI { return }
        mods[index].isEnabled.toggle()
        saveActiveProfileState()
    }

    public func enableAllMods() {
        for i in 0..<mods.count {
            mods[i].isEnabled = true
        }
        saveActiveProfileState()
    }

    public func disableAllMods() {
        for i in 0..<mods.count {
            if !mods[i].isCoreSMAPI {
                mods[i].isEnabled = false
            }
        }
        saveActiveProfileState()
    }

    public func selectProfile(_ profile: Profile) {
        // If already selected, ensure state is saved and avoid stale overwrite
        if profile.id == activeProfile.id {
            saveActiveProfileState()
            saveSeparatorsState()
            return
        }

        // 1. Save current active profile state and separators before switching
        saveActiveProfileState()
        saveSeparatorsState()

        // 2. Fetch latest version of target profile
        let target = profiles.first(where: { $0.id == profile.id })
            ?? profileService.loadProfiles().first(where: { $0.id == profile.id })
            ?? profile

        self.activeProfile = target
        self.settings.lastSelectedProfileName = target.name
        settingsService.saveSettings(self.settings)

        // 3. Load separators for the newly active profile
        self.separators = separatorService.loadSeparators(for: target.name)

        // 4. Apply enabled states for the selected profile, preserving core SMAPI mods
        let enabledSet = Set(target.enabledModIds.map { $0.uniqueId.lowercased() })
        for i in 0..<mods.count {
            if mods[i].isCoreSMAPI {
                mods[i].isEnabled = true
            } else {
                mods[i].isEnabled = enabledSet.contains(mods[i].id.lowercased())
            }
        }

        // 5. Ensure memory and disk states are synced
        saveActiveProfileState()
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
    }

    public func deleteProfile(_ profile: Profile) {
        guard !profile.isProtected else { return }
        let isDeletingActive = (activeProfile.id == profile.id)
        profileService.deleteProfile(profile)
        separatorService.deleteSeparators(for: profile.name)
        self.profiles = profileService.loadProfiles()

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
    }

    public func launchGame() {
        saveActiveProfileState()
        launcher.launch(
            mods: mods,
            gameDirectory: gameDirectory,
            smapiExecutable: pathing.resolveSmapiExecutable(gameDirectory: gameDirectory)
        )
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
        let enabledRefs = mods.filter { $0.isEnabled }.map { mod in
            existingMap[mod.id.lowercased()] ?? ModReference(uniqueId: mod.id)
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
    }

    public func renameSeparator(_ separator: ModSeparator, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = separators.firstIndex(where: { $0.id == separator.id }) else { return }
        separators[idx].name = trimmed
        saveSeparatorsState()
    }

    public func deleteSeparator(_ separator: ModSeparator) {
        separators.removeAll { $0.id == separator.id }
        saveSeparatorsState()
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
        var groups: [String: [String]] = [:]
        for mod in mods {
            let parent = mod.directoryURL.deletingLastPathComponent()
            if parent.standardizedFileURL.path != modsDirectory.standardizedFileURL.path {
                var folderName = parent.lastPathComponent
                if folderName.hasPrefix("[MODS] - ") {
                    folderName = String(folderName.dropFirst("[MODS] - ".count))
                }
                groups[folderName, default: []].append(mod.id)
            } else if mod.isCoreSMAPI {
                groups["Core", default: []].append(mod.id)
            }
        }
        guard !groups.isEmpty else { return }
        for (name, ids) in groups.sorted(by: { $0.key < $1.key }) {
            if let idx = separators.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                var existing = Set(separators[idx].modIds)
                existing.formUnion(ids)
                separators[idx].modIds = Array(existing)
            } else {
                separators.append(ModSeparator(name: name, isExpanded: true, modIds: ids))
            }
        }
        saveSeparatorsState()
    }
}
