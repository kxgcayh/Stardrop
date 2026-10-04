import SwiftUI

public struct CollectionInstallSheet: View {
    @ObservedObject var state: AppState
    let manifest: CollectionManifest
    let contentURL: URL
    let isTemporary: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var createNewProfile: Bool = true
    @State private var targetProfileName: String = ""
    @State private var includeOptionalMods: Bool = false
    @State private var isInstalling: Bool = false
    @State private var progressMessage: String = "Preparing..."
    @State private var progressValue: Double = 0.0
    @State private var installSummary: CollectionInstallSummary? = nil
    @State private var errorMessage: String? = nil

    public init(
        state: AppState,
        manifest: CollectionManifest,
        contentURL: URL,
        isTemporary: Bool
    ) {
        self.state = state
        self.manifest = manifest
        self.contentURL = contentURL
        self.isTemporary = isTemporary
        _targetProfileName = State(initialValue: "[Collection] \(manifest.info.name)")
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manifest.info.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let author = manifest.info.author, !author.isEmpty {
                        Text("Curated by \(author)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !isInstalling && installSummary == nil {
                    Button("Close") {
                        cleanupAndDismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding()

            Divider()

            if let summary = installSummary {
                // Summary View
                summaryView(summary)
            } else if isInstalling {
                // Installing Progress View
                installingView
            } else {
                // Configuration Form View
                configFormView
            }
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - Subviews

    private var configFormView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Description Box
                if let desc = manifest.info.description, !desc.isEmpty {
                    GroupBox(label: Text("Description").fontWeight(.medium)) {
                        Text(desc)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                // Statistics
                GroupBox(label: Text("Collection Contents").fontWeight(.medium)) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Mods")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(manifest.mods.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        Divider().frame(height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Required")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(manifest.requiredMods.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        Divider().frame(height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Optional")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(manifest.optionalMods.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Profile Configuration
                GroupBox(label: Text("Installation Target").fontWeight(.medium)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Target Profile", selection: $createNewProfile) {
                            Text("Create new profile").tag(true)
                            Text("Install into active profile (\(state.activeProfile.name))").tag(false)
                        }
                        .pickerStyle(.radioGroup)

                        if createNewProfile {
                            HStack {
                                Text("Profile Name:")
                                    .font(.subheadline)
                                TextField("Profile Name", text: $targetProfileName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Options
                if !manifest.optionalMods.isEmpty {
                    GroupBox(label: Text("Options").fontWeight(.medium)) {
                        Toggle("Include \(manifest.optionalMods.count) optional mods", isOn: $includeOptionalMods)
                            .padding(.vertical, 2)
                    }
                }

                // Membership Notice
                if !state.isPremiumNexusUser {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nexus Account Note")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("You are currently using a Free Nexus Mods account. Bundled mods and pre-cached files will install directly. Any remaining mods can be downloaded step-by-step with the Download Assistant.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.callout)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") {
                    cleanupAndDismiss()
                }

                Spacer()

                Button("Install Collection") {
                    startInstallation()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    private var installingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: progressValue, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 380)

            Text(progressMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Text("\(Int(progressValue * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private func summaryView(_ summary: CollectionInstallSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Installation Complete")
                        .font(.headline)

                    Text("Successfully processed collection for profile '\(summary.profileName)'.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("Installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(summary.installedMods.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                        }

                        if summary.alreadyInstalledCount > 0 {
                            VStack(alignment: .leading) {
                                Text("Already Installed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(summary.alreadyInstalledCount)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                        }

                        if !summary.skippedMods.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Skipped / Manual")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(summary.skippedMods.count)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            let pendingNexusMods = manifest.mods.filter { colMod in
                colMod.source.isNexus && summary.skippedMods.contains { $0.caseInsensitiveCompare(colMod.name) == .orderedSame }
            }

            if !pendingNexusMods.isEmpty {
                GroupBox(label: Text("Download Assistant").fontWeight(.medium)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(pendingNexusMods.count) mod\(pendingNexusMods.count == 1 ? "" : "s") in this collection require download from Nexus Mods.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button("Launch Download Assistant (\(pendingNexusMods.count) mods)") {
                            state.selectProfile(named: summary.profileName)
                            state.startFreeUserQueue(
                                mods: pendingNexusMods,
                                targetProfileName: summary.profileName,
                                separatorName: "[Collection] \(manifest.info.name)",
                                collectionName: manifest.info.name
                            )
                            cleanupAndDismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }

            if !summary.warnings.isEmpty || !summary.errors.isEmpty {
                GroupBox(label: Text("Notices").fontWeight(.medium)) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(summary.warnings, id: \.self) { w in
                                Text("Warning: \(w)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            ForEach(summary.errors, id: \.self) { e in
                                Text("Error: \(e)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    state.selectProfile(named: summary.profileName)
                    state.refreshMods()
                    cleanupAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func startInstallation() {
        isInstalling = true
        errorMessage = nil

        let targetName = createNewProfile ? targetProfileName : state.activeProfile.name

        Task {
            do {
                let summary = try await CollectionService.shared.installCollection(
                    manifest: manifest,
                    contentRootURL: contentURL,
                    targetProfileName: targetName,
                    createNewProfile: createNewProfile,
                    includeOptionalMods: includeOptionalMods,
                    apiKey: state.nexusApiKey,
                    isPremium: state.isPremiumNexusUser,
                    existingMods: state.mods,
                    modsDirectory: state.modsDirectory
                ) { msg, progress in
                    Task { @MainActor in
                        self.progressMessage = msg
                        self.progressValue = progress
                    }
                }

                await MainActor.run {
                    self.isInstalling = false
                    self.installSummary = summary
                }
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.errorMessage = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func cleanupAndDismiss() {
        if isTemporary {
            try? FileManager.default.removeItem(at: contentURL)
        }
        dismiss()
    }
}
