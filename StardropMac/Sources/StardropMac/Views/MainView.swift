import SwiftUI

public struct MainView: View {
    @StateObject private var state = AppState()
    @State private var isInspectorPresented = true
    @State private var showingErrorAlert = false

    public var body: some View {
        NavigationSplitView {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            ModTableView(state: state)
                .searchable(text: $state.searchText, prompt: "Filter mods...")
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorView(state: state)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                // Profile Selector Menu in Toolbar
                Menu {
                    ForEach(state.profiles) { profile in
                        Button {
                            state.selectProfile(profile)
                        } label: {
                            HStack {
                                Text(profile.name)
                                if state.activeProfile.id == profile.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("New Profile...") {
                        state.isNewProfilePresented = true
                    }
                } label: {
                    Label(state.activeProfile.name, systemImage: "person.crop.circle")
                }
                .help("Select Active Profile")
            }

            ToolbarItem(placement: .automatic) {
                // Mod Stats Pill
                HStack(spacing: 4) {
                    Text("\(state.enabledCount) Enabled")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(state.totalCount) Total")
                        .foregroundStyle(.secondary)

                    if state.availableUpdatesCount > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Button {
                            withAnimation {
                                state.selectedCategory = (state.selectedCategory == .updatableOnly) ? .allMods : .updatableOnly
                            }
                        } label: {
                            Text("\(state.availableUpdatesCount) Updates")
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Click to filter by available updates")
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Bulk Mod & Separator Actions Menu
                Menu {
                    Button("New Separator...") {
                        state.promptNewSeparator()
                    }
                    Divider()
                    Button(state.areAllSeparatorsExpanded ? "Collapse All Separators" : "Expand All Separators") {
                        if state.areAllSeparatorsExpanded {
                            state.collapseAllSeparators()
                        } else {
                            state.expandAllSeparators()
                        }
                    }
                    .disabled(state.separators.isEmpty)

                    Button("Auto-generate Separators from Folders") {
                        state.autoGenerateSeparatorsFromFolders()
                    }
                    Divider()
                    Button("Enable All Mods") {
                        state.enableAllMods()
                    }
                    Button("Disable All Mods") {
                        state.disableAllMods()
                    }
                } label: {
                    Image(systemName: "checklist")
                }
                .help("Bulk Mod & Separator Actions")

                Button {
                    state.refreshMods()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Mod List")

                Button {
                    Task {
                        await state.checkForModUpdates()
                    }
                } label: {
                    if state.isCheckingUpdates {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(state.availableUpdatesCount > 0 ? Color.orange : Color.primary)
                    }
                }
                .disabled(state.isCheckingUpdates)
                .help(state.isCheckingUpdates ? "Checking for mod updates..." : (state.availableUpdatesCount > 0 ? "\(state.availableUpdatesCount) mod update\(state.availableUpdatesCount == 1 ? "" : "s") available (⌘U)" : "Check for Mod Updates (⌘U)"))

                Button {
                    state.isNexusPresented = true
                } label: {
                    Image(systemName: "globe.americas.fill")
                        .foregroundStyle(state.isNexusConnected ? Color.orange : Color.secondary)
                }
                .help(state.isNexusConnected ? "Nexus Mods: Connected (\(state.settings.nexusDetails.username ?? ""))" : "Connect Nexus Mods API")

                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle Inspector")

                // Primary SMAPI Launch Button
                Button {
                    state.launchGame()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: state.launcher.isRunning ? "stop.fill" : "play.fill")
                        Text(state.launcher.isRunning ? "Running..." : "Launch SMAPI")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.launcher.isRunning ? .green : .blue)
                .disabled(state.launcher.isRunning)
                .help(state.launcher.isRunning ? "Game is running" : "Launch Stardew Valley with SMAPI")
            }
        }
        .sheet(isPresented: $state.isNewProfilePresented) {
            NewProfileSheet(state: state)
        }
        .sheet(isPresented: $state.isSettingsPresented) {
            SettingsSheet(state: state)
        }
        .sheet(isPresented: $state.isNexusPresented) {
            NexusAccountSheet(state: state)
        }
        .sheet(isPresented: $state.isAboutPresented) {
            AboutSheet(state: state)
        }
        .sheet(isPresented: $state.isConfigEditorPresented) {
            if let mod = state.editingMod {
                ConfigEditorSheet(mod: mod)
            }
        }
        .sheet(isPresented: $state.isNewSeparatorPresented) {
            NewSeparatorSheet(state: state)
        }
        .sheet(item: $state.separatorToRename) { separator in
            RenameSeparatorSheet(state: state, separator: separator)
        }
        .onChange(of: state.launcher.launchError) { _, error in
            showingErrorAlert = error != nil
        }
        .alert("SMAPI Launch Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {
                state.launcher.launchError = nil
            }
        } message: {
            Text(state.launcher.launchError ?? "Unknown error occurred while starting SMAPI.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            state.isSettingsPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNexus)) { _ in
            state.isNexusPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAbout)) { _ in
            state.isAboutPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkForUpdates)) { _ in
            Task {
                await state.checkForModUpdates()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshMods)) { _ in
            state.refreshMods()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enableAllMods)) { _ in
            state.enableAllMods()
        }
        .onReceive(NotificationCenter.default.publisher(for: .disableAllMods)) { _ in
            state.disableAllMods()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSelectedMod)) { _ in
            state.toggleSelectedMod()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSeparator)) { _ in
            state.promptNewSeparator()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchSmapi)) { _ in
            state.launchGame()
        }
    }
}
