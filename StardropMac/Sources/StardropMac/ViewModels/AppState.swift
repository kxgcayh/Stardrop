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
    @Published public var editingMod: Mod?

    public var isNexusConnected: Bool {
        guard let key = settings.nexusDetails.key, !key.isEmpty else { return false }
        return settings.nexusDetails.username != nil
    }

    public let launcher = SMAPILauncherService.shared

    private let pathing = PathingService.shared
    private let scanner = ModScannerService.shared
    private let profileService = ProfileService.shared
    private let settingsService = SettingsService.shared

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

        refreshMods()
        if self.selectedModId == nil {
            self.selectedModId = self.mods.first?.id
        }

        // Auto-check for mod updates in background on launch
        Task { [weak self] in
            await self?.checkForModUpdates()
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

    // MARK: - Actions

    public func refreshMods() {
        let enabledSet = Set(activeProfile.enabledModIds.map { $0.uniqueId.lowercased() })
        let previousUpdates = Dictionary(uniqueKeysWithValues: mods.compactMap { mod in
            mod.suggestedVersion != nil ? (mod.id, (mod.suggestedVersion, mod.updateURL)) : nil
        })
        var scanned = scanner.scanMods(in: modsDirectory, enabledIds: enabledSet)
        for i in 0..<scanned.count {
            if let prev = previousUpdates[scanned[i].id] {
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
        }

        do {
            let updates = try await ModUpdateService.shared.fetchUpdates(
                mods: self.mods,
                gameDetails: self.settings.gameDetails
            )

            await MainActor.run {
                for entry in updates {
                    if let suggested = entry.suggestedUpdate?.version,
                       !suggested.isEmpty,
                       let idx = self.mods.firstIndex(where: { $0.id.caseInsensitiveCompare(entry.id) == .orderedSame }) {
                        if suggested != self.mods[idx].version {
                            self.mods[idx].suggestedVersion = suggested
                            if let urlStr = entry.suggestedUpdate?.url, let url = URL(string: urlStr) {
                                self.mods[idx].updateURL = url
                            }
                        }
                    }
                }
                self.lastUpdateCheckDate = Date()
                self.isCheckingUpdates = false
            }
        } catch {
            print("Failed to fetch mod updates: \(error)")
            await MainActor.run {
                self.isCheckingUpdates = false
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
        if mods[index].isEnabled != isEnabled {
            mods[index].isEnabled = isEnabled
            saveActiveProfileState()
        }
    }

    public func toggleMod(_ mod: Mod) {
        guard let index = mods.firstIndex(where: { $0.id.caseInsensitiveCompare(mod.id) == .orderedSame }) else { return }
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
            mods[i].isEnabled = false
        }
        saveActiveProfileState()
    }

    public func selectProfile(_ profile: Profile) {
        // If already selected, ensure state is saved and avoid stale overwrite
        if profile.id == activeProfile.id {
            saveActiveProfileState()
            return
        }

        // 1. Save current active profile state before switching
        saveActiveProfileState()

        // 2. Fetch latest version of target profile
        let target = profiles.first(where: { $0.id == profile.id })
            ?? profileService.loadProfiles().first(where: { $0.id == profile.id })
            ?? profile

        self.activeProfile = target
        self.settings.lastSelectedProfileName = target.name
        settingsService.saveSettings(self.settings)

        // 3. Apply enabled states for the selected profile
        let enabledSet = Set(target.enabledModIds.map { $0.uniqueId.lowercased() })
        for i in 0..<mods.count {
            mods[i].isEnabled = enabledSet.contains(mods[i].id.lowercased())
        }

        // 4. Ensure memory and disk states are synced
        saveActiveProfileState()
    }

    public func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Save current active profile first
        saveActiveProfileState()

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
        self.profiles = profileService.loadProfiles()

        if isDeletingActive {
            if let first = profiles.first {
                self.activeProfile = first
                self.settings.lastSelectedProfileName = first.name
                settingsService.saveSettings(self.settings)

                let enabledSet = Set(first.enabledModIds.map { $0.uniqueId.lowercased() })
                for i in 0..<mods.count {
                    mods[i].isEnabled = enabledSet.contains(mods[i].id.lowercased())
                }
                saveActiveProfileState()
            }
        }
    }

    public func duplicateProfile(_ profile: Profile) {
        saveActiveProfileState()

        let source = (profile.id == activeProfile.id) ? activeProfile : (profiles.first(where: { $0.id == profile.id }) ?? profile)
        let newName = "\(source.name) Copy"
        let copy = profileService.duplicateProfile(source, newName: newName)
        self.profiles = profileService.loadProfiles()
        selectProfile(copy)
    }

    public func renameProfile(_ profile: Profile, newName: String) {
        guard !profile.isProtected else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }

        saveActiveProfileState()
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
}
