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

    enum ModListFilter: String, CaseIterable {
        case all = "All"
        case installed = "Installed"
        case needsDownload = "Needs Download"
    }

    struct ModReviewItem: Identifiable {
        let id: String
        let mod: CollectionMod
        let installedMod: Mod?
        let isBundled: Bool
        let isCached: Bool
        let isOutdatedSMAPI: Bool
        let installedSMAPIVersion: String?

        var isInstalled: Bool { installedMod != nil && !isOutdatedSMAPI }
        var needsDownload: Bool { !isInstalled && !isBundled && !isCached }
    }

    @State private var listFilter: ModListFilter = .all
    @State private var reviewSearchText: String = ""

    private var reviewItems: [ModReviewItem] {
        let cacheDir = PathingService.shared.collectionDownloadsURL
        let installedSMAPI = CollectionMod.findInstalledSMAPI(in: state.mods)
        let smapiVersion = installedSMAPI?.version ?? state.settings.gameDetails?.smapiVersion

        return manifest.mods.map { colMod in
            let matched = colMod.findMatchingMod(in: state.mods, currentSMAPIVersion: smapiVersion)
            let bundled = colMod.source.isBundled
            var cached = false
            if let modId = colMod.source.modId, let fileId = colMod.source.fileId {
                let cachedFile = cacheDir.appendingPathComponent("\(modId)_\(fileId).zip")
                cached = FileManager.default.fileExists(atPath: cachedFile.path)
            }

            var isOutdatedSMAPI = false
            if colMod.isSMAPI, let currentVer = smapiVersion {
                if VersionHelper.isVersion(currentVer, lowerThan: colMod.version) {
                    isOutdatedSMAPI = true
                }
            }

            return ModReviewItem(
                id: colMod.id,
                mod: colMod,
                installedMod: matched ?? (colMod.isSMAPI ? installedSMAPI : nil),
                isBundled: bundled,
                isCached: cached,
                isOutdatedSMAPI: isOutdatedSMAPI,
                installedSMAPIVersion: smapiVersion
            )
        }
    }

    private var installedItems: [ModReviewItem] {
        reviewItems.filter { $0.isInstalled }
    }

    private var needsDownloadItems: [ModReviewItem] {
        reviewItems.filter { $0.needsDownload }
    }

    private var bundledOrCachedItems: [ModReviewItem] {
        reviewItems.filter { $0.isBundled || $0.isCached }
    }

    private var filteredReviewItems: [ModReviewItem] {
        var items: [ModReviewItem]
        switch listFilter {
        case .all:
            items = reviewItems
        case .installed:
            items = installedItems
        case .needsDownload:
            items = needsDownloadItems
        }

        let query = reviewSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter { item in
                item.mod.name.lowercased().contains(query) ||
                (item.installedMod?.name.lowercased().contains(query) ?? false) ||
                (item.mod.author?.lowercased().contains(query) ?? false)
            }
        }
        return items
    }

    private var actionButtonTitle: String {
        if needsDownloadItems.isEmpty {
            return "Apply Collection (\(manifest.mods.count) Mods)"
        } else if installedItems.isEmpty {
            return "Install Collection (\(manifest.mods.count) Mods)"
        } else {
            return "Install Collection (\(installedItems.count) Ready, \(needsDownloadItems.count) to Download)"
        }
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
        .frame(width: 620, height: 620)
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

                // Statistics & Library Status
                GroupBox(label: Text("Collection Contents & Library Status").fontWeight(.medium)) {
                    HStack(spacing: 20) {
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
                            Text("Already Installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(installedItems.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }

                        Divider().frame(height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Needs Download")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(needsDownloadItems.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(needsDownloadItems.isEmpty ? .secondary : .orange)
                        }

                        if !bundledOrCachedItems.isEmpty {
                            Divider().frame(height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bundled / Cached")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(bundledOrCachedItems.count)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Informative Callout for Outdated SMAPI
                if let smapiItem = reviewItems.first(where: { $0.isOutdatedSMAPI }) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SMAPI Update Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("This collection specifies SMAPI v\(smapiItem.mod.version), but version v\(smapiItem.installedSMAPIVersion ?? "unknown") is currently installed in your library. SMAPI is added to the download list to ensure compatibility.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }

                // Informative Callout for Already Installed Mods
                if !installedItems.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(installedItems.count) of \(manifest.mods.count) mods are already installed in your Stardrop library.")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("These mods will be linked to your profile automatically and will not be re-downloaded or re-installed.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }

                // Mod Review Section
                GroupBox(label: Text("Mod Review").fontWeight(.medium)) {
                    VStack(spacing: 8) {
                        HStack {
                            Picker("Filter", selection: $listFilter) {
                                Text("All (\(manifest.mods.count))").tag(ModListFilter.all)
                                Text("Installed (\(installedItems.count))").tag(ModListFilter.installed)
                                Text("Needs Download (\(needsDownloadItems.count))").tag(ModListFilter.needsDownload)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Spacer()

                            TextField("Filter mods...", text: $reviewSearchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                        }

                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(filteredReviewItems) { item in
                                    modReviewRow(item)
                                    if item.id != filteredReviewItems.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 160)
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

                Button(actionButtonTitle) {
                    startInstallation()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    private func modReviewRow(_ item: ModReviewItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.mod.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if item.mod.optional {
                        Text("Optional")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                }

                if item.isOutdatedSMAPI {
                    Text("Installed in library: v\(item.installedSMAPIVersion ?? "unknown") (Collection requires v\(item.mod.version))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if let matched = item.installedMod {
                    Text("Installed in library: \(matched.name) v\(matched.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let author = item.mod.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            modStatusBadge(for: item)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func modStatusBadge(for item: ModReviewItem) -> some View {
        Group {
            if item.isOutdatedSMAPI {
                Text("Update Required (v\(item.mod.version))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            } else if let matched = item.installedMod {
                Text("Installed (v\(matched.version))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            } else if item.isBundled {
                Text("Bundled")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
            } else if item.isCached {
                Text("Cached")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.teal.opacity(0.15))
                    .foregroundColor(.teal)
                    .cornerRadius(4)
            } else {
                Text("Needs Download")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }
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
