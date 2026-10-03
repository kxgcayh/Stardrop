import Foundation
import Combine
import SwiftUI

public enum SidebarCategory: Hashable {
    case allMods
    case enabledOnly
    case disabledOnly
    case updatableOnly
}

public struct ModGroup: Identifiable {
    public var id: String { name }
    public let name: String
    public let mods: [Mod]

    public var enabledCount: Int {
        mods.filter { $0.isEnabled }.count
    }
    public var totalCount: Int {
        mods.count
    }
    public var allEnabled: Bool {
        enabledCount == totalCount && totalCount > 0
    }
}

public final class AppState: ObservableObject {
    @Published public var mods: [Mod] = []
    @Published public var profiles: [Profile] = []
    @Published public var activeProfile: Profile
    @Published public var selectedModId: String?
    @Published public var searchText: String = ""
    @Published public var selectedCategory: SidebarCategory = .allMods
    @Published public var expandedGroups: Set<String> = []

    @Published public var settings: StardropSettings
    @Published public var isSettingsPresented: Bool = false
    @Published public var isNewProfilePresented: Bool = false
    @Published public var isConfigEditorPresented: Bool = false
    @Published public var isNexusPresented: Bool = false
    @Published public var isAboutPresented: Bool = false
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
                $0.id.lowercased().contains(query) ||
                ($0.groupName?.lowercased().contains(query) ?? false)
            }
        }

        return list
    }

    public var groupedMods: [ModGroup] {
        let currentFiltered = filteredMods
        let dict = Dictionary(grouping: currentFiltered) { $0.groupName ?? "Standalone Mods" }

        return dict.keys.sorted { g1, g2 in
            if g1 == "Standalone Mods" { return false }
            if g2 == "Standalone Mods" { return true }
            return g1.localizedCaseInsensitiveCompare(g2) == .orderedAscending
        }.map { name in
            ModGroup(name: name, mods: dict[name] ?? [])
        }
    }

    public var areAllGroupsExpanded: Bool {
        let groupNames = Set(groupedMods.map { $0.name })
        return !groupNames.isEmpty && groupNames.isSubset(of: expandedGroups)
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
        let enabledSet = Set(activeProfile.enabledModIds.map { $0.uniqueId })
        let scanned = scanner.scanMods(in: modsDirectory, enabledIds: enabledSet)
        self.mods = scanned

        // By default, expand all groups so everything is visible
        let allGroupNames = Set(scanned.compactMap { $0.groupName } + ["Standalone Mods"])
        self.expandedGroups = allGroupNames
    }

    public func toggleGroupExpansion(_ groupName: String) {
        if expandedGroups.contains(groupName) {
            expandedGroups.remove(groupName)
        } else {
            expandedGroups.insert(groupName)
        }
    }

    public func expandAllGroups() {
        expandedGroups = Set(groupedMods.map { $0.name })
    }

    public func collapseAllGroups() {
        expandedGroups.removeAll()
    }

    public func toggleMod(_ mod: Mod) {
        guard let index = mods.firstIndex(where: { $0.id == mod.id }) else { return }
        mods[index].isEnabled.toggle()

        saveActiveProfileState()
    }

    public func toggleAllModsInGroup(_ group: ModGroup) {
        let targetState = !group.allEnabled
        for mod in group.mods {
            if let idx = mods.firstIndex(where: { $0.id == mod.id }) {
                mods[idx].isEnabled = targetState
            }
        }
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
        saveActiveProfileState()

        self.activeProfile = profile
        self.settings.lastSelectedProfileName = profile.name
        settingsService.saveSettings(self.settings)

        // Apply enabled states for the selected profile
        let enabledSet = Set(profile.enabledModIds.map { $0.uniqueId })
        for i in 0..<mods.count {
            let id = mods[i].id
            mods[i].isEnabled = enabledSet.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
        }
    }

    public func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newProfile = Profile(
            name: trimmed,
            isProtected: false,
            enabledModIds: mods.filter { $0.isEnabled }.map { ModReference(uniqueId: $0.id) }
        )
        profileService.saveProfile(newProfile)
        self.profiles = profileService.loadProfiles()
        selectProfile(newProfile)
    }

    public func deleteProfile(_ profile: Profile) {
        guard !profile.isProtected else { return }
        profileService.deleteProfile(profile)
        self.profiles = profileService.loadProfiles()

        if activeProfile.id == profile.id {
            if let first = profiles.first {
                selectProfile(first)
            }
        }
    }

    public func duplicateProfile(_ profile: Profile) {
        let newName = "\(profile.name) Copy"
        let copy = profileService.duplicateProfile(profile, newName: newName)
        self.profiles = profileService.loadProfiles()
        selectProfile(copy)
    }

    public func launchGame() {
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

    private func saveActiveProfileState() {
        let enabledRefs = mods.filter { $0.isEnabled }.map { ModReference(uniqueId: $0.id) }
        activeProfile.enabledModIds = enabledRefs
        profileService.saveProfile(activeProfile)
    }
}
