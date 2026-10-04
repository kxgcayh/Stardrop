import SwiftUI
import UniformTypeIdentifiers

public struct MainView: View {
    @ObservedObject var state: AppState
    @State private var isInspectorPresented = true
    @State private var showingErrorAlert = false
    @State private var isDropTargeted = false

    public init(state: AppState? = nil) {
        self.state = state ?? AppState()
    }

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
                    state.promptInstallModArchive()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Install Mod Archive (.zip, .7z, .rar) (⌘O)")

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
        .modifier(MainSheetsModifier(state: state))
        .modifier(MainAlertsModifier(
            state: state,
            showingErrorAlert: $showingErrorAlert
        ))
        .overlay {
            if isDropTargeted {
                dropTargetOverlay
            }
            if state.isInstallingMods {
                installingProgressOverlay
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onOpenURL { url in
            state.handleOpenURL(url)
        }
        .modifier(MainNotificationsModifier(state: state))
    }

    // MARK: - Drag and Drop & Installation Overlays

    private var dropTargetOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)

            VStack(spacing: 14) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Drop Mod Archive to Install")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text("Supports .zip, .7z, .rar, .tar.gz and mod folders")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            )
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var installingProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)

                Text(state.modInstallProgressMessage ?? "Installing mod...")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Extracting files and validating manifests...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 12)
            )
        }
        .allowsHitTesting(true)
        .transition(.opacity)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let dispatchGroup = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                dispatchGroup.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { dispatchGroup.leave() }
                    if let url = item as? URL {
                        urls.append(url)
                    } else if let nsurl = item as? NSURL {
                        urls.append(nsurl as URL)
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    } else if let str = item as? String, let url = URL(string: str) {
                        urls.append(url)
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            let fileURLs = urls.filter { $0.isFileURL || FileManager.default.fileExists(atPath: $0.path) }
            if !fileURLs.isEmpty {
                Task {
                    await state.installMods(from: fileURLs)
                }
            }
        }
        return true
    }
}

// MARK: - View Modifiers to keep type checking fast

private struct MainSheetsModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        content
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
            .sheet(isPresented: $state.isCollectionInstallPresented) {
                if let package = state.activeCollectionPackage {
                    CollectionInstallSheet(
                        state: state,
                        manifest: package.manifest,
                        contentURL: package.contentURL,
                        isTemporary: package.isTemporary
                    )
                }
            }
            .sheet(isPresented: $state.isFreeUserQueuePresented) {
                if let manager = state.activeQueueManager {
                    FreeUserQueueSheet(state: state, manager: manager)
                }
            }
    }
}

private struct MainAlertsModifier: ViewModifier {
    @ObservedObject var state: AppState
    @Binding var showingErrorAlert: Bool

    private var endorsementBinding: Binding<Bool> {
        Binding(
            get: { state.endorsementAlertMessage != nil },
            set: { if !$0 { state.endorsementAlertMessage = nil } }
        )
    }

    private var modInstallBinding: Binding<Bool> {
        Binding(
            get: { state.modInstallResultAlert != nil },
            set: { if !$0 { state.modInstallResultAlert = nil } }
        )
    }

    private var modDeletionBinding: Binding<Bool> {
        Binding(
            get: { state.modToDelete != nil },
            set: { if !$0 { state.modToDelete = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
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
            .alert("Endorsement", isPresented: endorsementBinding) {
                Button("OK", role: .cancel) {
                    state.endorsementAlertMessage = nil
                }
            } message: {
                Text(state.endorsementAlertMessage ?? "")
            }
            .alert("Mod Installation", isPresented: modInstallBinding) {
                Button("OK", role: .cancel) {
                    state.modInstallResultAlert = nil
                }
            } message: {
                Text(state.modInstallResultAlert ?? "")
            }
            .alert(state.modToDelete?.title ?? "Delete Mod", isPresented: modDeletionBinding) {
                Button("Cancel", role: .cancel) {
                    state.modToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    state.confirmDeleteMod()
                }
            } message: {
                Text(state.modToDelete?.message ?? "")
            }
    }
}

private struct MainNotificationsModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        content
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
            .onReceive(NotificationCenter.default.publisher(for: .installModArchive)) { _ in
                state.promptInstallModArchive()
            }
            .onReceive(NotificationCenter.default.publisher(for: .launchSmapi)) { _ in
                state.launchGame()
            }
    }
}

