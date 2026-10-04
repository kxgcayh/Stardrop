import Foundation

public struct CollectionInstallSummary {
    public let collectionName: String
    public let installedMods: [ModInstallResult]
    public let alreadyInstalledCount: Int
    public let skippedMods: [String]
    public let warnings: [String]
    public let errors: [String]
    public let profileName: String
    public let separatorName: String
}

public final class CollectionService {
    public static let shared = CollectionService()

    private let pathing = PathingService.shared
    private let nexusService = NexusService.shared
    private let installer = ModInstallerService.shared
    private let profileService = ProfileService.shared
    private let separatorService = SeparatorService.shared

    private let supportedArchiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz"
    ]

    public func isCollectionFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if !supportedArchiveExtensions.contains(ext) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let manifestURL = url.appendingPathComponent("collection.json")
                return FileManager.default.fileExists(atPath: manifestURL.path)
            }
            return false
        }
        return true
    }

    public func inspect(url: URL) throws -> (manifest: CollectionManifest, contentURL: URL, isTemporary: Bool) {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw NSError(domain: "CollectionService", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found: \(url.lastPathComponent)"])
        }

        if isDir.boolValue {
            let manifestURL = findCollectionJSON(in: url)
            guard let foundURL = manifestURL else {
                throw NSError(domain: "CollectionService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Directory does not contain collection.json."])
            }
            let data = try Data(contentsOf: foundURL)
            let manifest = try JSONDecoder().decode(CollectionManifest.self, from: data)
            return (manifest, foundURL.deletingLastPathComponent(), false)
        } else {
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("StardropCollection_\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            do {
                try installer.extractArchive(at: url, to: tempDir)
            } catch {
                try? fileManager.removeItem(at: tempDir)
                throw error
            }

            guard let foundURL = findCollectionJSON(in: tempDir) else {
                try? fileManager.removeItem(at: tempDir)
                throw NSError(domain: "CollectionService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive does not contain collection.json."])
            }

            let data = try Data(contentsOf: foundURL)
            let manifest = try JSONDecoder().decode(CollectionManifest.self, from: data)
            return (manifest, foundURL.deletingLastPathComponent(), true)
        }
    }

    private func findCollectionJSON(in root: URL) -> URL? {
        let direct = root.appendingPathComponent("collection.json")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "collection.json" {
                    return fileURL
                }
            }
        }
        return nil
    }

    public func installCollection(
        manifest: CollectionManifest,
        contentRootURL: URL,
        targetProfileName: String,
        createNewProfile: Bool,
        includeOptionalMods: Bool,
        apiKey: String?,
        isPremium: Bool,
        existingMods: [Mod],
        modsDirectory: URL,
        onProgress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> CollectionInstallSummary {
        let fileManager = FileManager.default
        let downloadCacheDir = pathing.collectionDownloadsURL
        try fileManager.createDirectory(at: downloadCacheDir, withIntermediateDirectories: true)

        var installedResults: [ModInstallResult] = []
        var alreadyInstalledCount = 0
        var skippedMods: [String] = []
        var warnings: [String] = []
        var errors: [String] = []

        let modsToProcess = includeOptionalMods ? manifest.mods : manifest.requiredMods
        let totalCount = Double(max(1, modsToProcess.count))

        var newlyInstalledUniqueIds: [String] = []

        for (index, colMod) in modsToProcess.enumerated() {
            let baseProgress = Double(index) / totalCount
            let stepProgress = 1.0 / totalCount

            // 1. Check if mod is already installed
            if let matched = colMod.findMatchingMod(in: existingMods) {
                alreadyInstalledCount += 1
                newlyInstalledUniqueIds.append(matched.id)
                onProgress("Already installed: \(colMod.name)", baseProgress + stepProgress)
                continue
            }

            // 2. Check bundled source
            if colMod.source.isBundled {
                onProgress("Installing bundled: \(colMod.name)", baseProgress)
                let bundledDir = contentRootURL.appendingPathComponent("bundled")
                var foundBundledURL: URL?

                if let files = try? fileManager.contentsOfDirectory(at: bundledDir, includingPropertiesForKeys: nil) {
                    for file in files {
                        let nameNoExt = file.deletingPathExtension().lastPathComponent
                        if nameNoExt.localizedCaseInsensitiveContains(colMod.name) ||
                           colMod.name.localizedCaseInsensitiveContains(nameNoExt) {
                            foundBundledURL = file
                            break
                        }
                    }
                    if foundBundledURL == nil, let first = files.first {
                        foundBundledURL = first
                    }
                }

                if let archiveURL = foundBundledURL {
                    do {
                        let summary = try await installer.installMods(from: [archiveURL], into: modsDirectory, existingMods: existingMods)
                        installedResults.append(contentsOf: summary.installedMods)
                        newlyInstalledUniqueIds.append(contentsOf: summary.installedMods.map { $0.uniqueID })
                    } catch {
                        errors.append("Failed to install bundled '\(colMod.name)': \(error.localizedDescription)")
                    }
                } else {
                    warnings.append("Bundled file for '\(colMod.name)' not found in collection.")
                }
                continue
            }

            // 3. Check Nexus source
            if colMod.source.isNexus {
                guard let modId = colMod.source.modId, let fileId = colMod.source.fileId else {
                    skippedMods.append(colMod.name)
                    warnings.append("Missing mod ID or file ID for '\(colMod.name)'.")
                    continue
                }

                // Check local download cache first
                let cachedFileName = "\(modId)_\(fileId).zip"
                let cachedFileURL = downloadCacheDir.appendingPathComponent(cachedFileName)

                var targetArchiveURL: URL?

                if fileManager.fileExists(atPath: cachedFileURL.path) {
                    targetArchiveURL = cachedFileURL
                    onProgress("Using cached download for \(colMod.name)", baseProgress + (stepProgress * 0.3))
                } else if isPremium, let apiKey = apiKey, !apiKey.isEmpty {
                    // Fetch download link via Nexus API
                    onProgress("Fetching download link for \(colMod.name)...", baseProgress + (stepProgress * 0.1))
                    do {
                        let links = try await nexusService.getModDownloadURLs(
                            gameDomain: colMod.domainName ?? "stardewvalley",
                            modId: modId,
                            fileId: fileId,
                            apiKey: apiKey
                        )

                        guard let primaryURI = links.first?.uri, let downloadURL = URL(string: primaryURI) else {
                            throw NSError(domain: "CollectionService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No download mirrors returned."])
                        }

                        onProgress("Downloading \(colMod.name)...", baseProgress + (stepProgress * 0.3))
                        try await nexusService.downloadFile(from: downloadURL, to: cachedFileURL) { subProgress in
                            let currentTotal = baseProgress + (stepProgress * (0.3 + (subProgress * 0.5)))
                            onProgress("Downloading \(colMod.name) (\(Int(subProgress * 100))%)...", currentTotal)
                        }

                        targetArchiveURL = cachedFileURL
                    } catch {
                        errors.append("Failed to download '\(colMod.name)': \(error.localizedDescription)")
                        continue
                    }
                } else {
                    // Non-Premium account without pre-cached archive
                    skippedMods.append(colMod.name)
                    warnings.append("'\(colMod.name)' requires manual download (Nexus Premium needed for direct batch downloads).")
                    continue
                }

                // Install the downloaded/cached archive
                if let archiveToInstall = targetArchiveURL {
                    onProgress("Installing \(colMod.name)...", baseProgress + (stepProgress * 0.85))
                    do {
                        let summary = try await installer.installMods(from: [archiveToInstall], into: modsDirectory, existingMods: existingMods)
                        installedResults.append(contentsOf: summary.installedMods)
                        newlyInstalledUniqueIds.append(contentsOf: summary.installedMods.map { $0.uniqueID })
                    } catch {
                        errors.append("Failed to install '\(colMod.name)': \(error.localizedDescription)")
                    }
                }
                continue
            }

            // Other source types (manual, direct, browse)
            skippedMods.append(colMod.name)
            if let instructions = colMod.instructions, !instructions.isEmpty {
                warnings.append("'\(colMod.name)' requires manual install: \(instructions)")
            } else if let urlStr = colMod.source.url {
                warnings.append("'\(colMod.name)' requires manual download from: \(urlStr)")
            }
        }

        // 4. Manage Profile and Separator Grouping
        let finalProfileName = targetProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let separatorName = "[Collection] \(manifest.info.name)"

        // Update / create target profile
        var profiles = profileService.loadProfiles()
        var targetProfile: Profile

        if createNewProfile || !profiles.contains(where: { $0.name == finalProfileName }) {
            var newProfile = Profile(name: finalProfileName)
            for uid in newlyInstalledUniqueIds {
                newProfile.enabledModIds.append(ModReference(uniqueId: uid))
            }
            targetProfile = newProfile
        } else {
            if let index = profiles.firstIndex(where: { $0.name == finalProfileName }) {
                for uid in newlyInstalledUniqueIds {
                    if !profiles[index].isModEnabled(uniqueId: uid) {
                        profiles[index].enabledModIds.append(ModReference(uniqueId: uid))
                    }
                }
                targetProfile = profiles[index]
            } else {
                targetProfile = Profile(name: finalProfileName)
            }
        }
        profileService.saveProfile(targetProfile)

        // Create or update Mod Separator for this collection
        var separators = separatorService.loadSeparators(for: finalProfileName)
        if let existingSepIndex = separators.firstIndex(where: { $0.name.caseInsensitiveCompare(separatorName) == .orderedSame }) {
            for uid in newlyInstalledUniqueIds {
                if !separators[existingSepIndex].modIds.contains(where: { $0.caseInsensitiveCompare(uid) == .orderedSame }) {
                    separators[existingSepIndex].modIds.append(uid)
                }
            }
        } else {
            let newSep = ModSeparator(name: separatorName, modIds: newlyInstalledUniqueIds)
            separators.insert(newSep, at: 0)
        }
        separatorService.saveSeparators(separators, for: finalProfileName)

        onProgress("Collection installation complete", 1.0)

        return CollectionInstallSummary(
            collectionName: manifest.info.name,
            installedMods: installedResults,
            alreadyInstalledCount: alreadyInstalledCount,
            skippedMods: skippedMods,
            warnings: warnings,
            errors: errors,
            profileName: finalProfileName,
            separatorName: separatorName
        )
    }
}
