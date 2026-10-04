import Foundation

public struct ModInstallResult: Identifiable {
    public var id: String { uniqueID }
    public let modName: String
    public let version: String
    public let uniqueID: String
    public let installedPath: URL
    public let isUpdate: Bool
}

public struct ModInstallSummary {
    public let installedMods: [ModInstallResult]
    public let warnings: [String]
    public let errors: [String]
}

public final class ModInstallerService {
    public static let shared = ModInstallerService()

    private let scanner = ModScannerService.shared

    private let supportedArchiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz"
    ]

    public func installMods(
        from urls: [URL],
        into modsDirectory: URL,
        existingMods: [Mod]
    ) async throws -> ModInstallSummary {
        let fileManager = FileManager.default

        // Ensure mods directory exists
        try fileManager.createDirectory(at: modsDirectory, withIntermediateDirectories: true)

        var installedResults: [ModInstallResult] = []
        var warnings: [String] = []
        var errors: [String] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDir) else {
                errors.append("File not found: \(url.lastPathComponent)")
                continue
            }

            if isDir.boolValue {
                // User dropped an uncompressed mod directory directly
                let detectedMods = scanner.scanMods(in: standardizedURL)
                if detectedMods.isEmpty {
                    warnings.append("'\(url.lastPathComponent)' does not contain a valid SMAPI mod manifest (manifest.json).")
                    continue
                }

                for detected in detectedMods {
                    do {
                        let result = try installDetectedMod(
                            detected,
                            searchRoot: standardizedURL,
                            into: modsDirectory,
                            existingMods: existingMods
                        )
                        installedResults.append(result)
                    } catch {
                        errors.append("Failed to install '\(detected.name)': \(error.localizedDescription)")
                    }
                }
            } else {
                // User provided an archive file
                let ext = standardizedURL.pathExtension.lowercased()
                guard supportedArchiveExtensions.contains(ext) else {
                    warnings.append("Skipping '\(url.lastPathComponent)': Unsupported format (expected .zip, .7z, .rar, .tar.gz).")
                    continue
                }

                // Create unique temporary extraction directory
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent("StardropInstall_\(UUID().uuidString)")
                try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer {
                    try? fileManager.removeItem(at: tempDir)
                }

                do {
                    try extractArchive(at: standardizedURL, to: tempDir)
                } catch {
                    errors.append("Failed to extract '\(url.lastPathComponent)': \(error.localizedDescription)")
                    continue
                }

                cleanExtractedFiles(in: tempDir)

                // Check if this archive contains a SMAPI installer script
                let macInstaller = findFile(named: "install on macOS.command", in: tempDir)
                if let installerScript = macInstaller {
                    let installerDir = installerScript.deletingLastPathComponent()
                    let downloadsDir = PathingService.shared.collectionDownloadsURL.appendingPathComponent("SMAPI_Installer")
                    try? fileManager.removeItem(at: downloadsDir)
                    try? fileManager.createDirectory(at: downloadsDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fileManager.copyItem(at: installerDir, to: downloadsDir)
                    warnings.append("SMAPI installer extracted to Collection Downloads/SMAPI_Installer. Run 'install on macOS.command' to complete setup.")
                }

                let detectedMods = scanner.scanMods(in: tempDir)
                if detectedMods.isEmpty {
                    if macInstaller != nil {
                        continue
                    }
                    warnings.append("'\(url.lastPathComponent)' does not contain a valid SMAPI mod manifest (manifest.json).")
                    continue
                }

                for detected in detectedMods {
                    do {
                        let result = try installDetectedMod(
                            detected,
                            searchRoot: tempDir,
                            into: modsDirectory,
                            existingMods: existingMods
                        )
                        installedResults.append(result)
                    } catch {
                        errors.append("Failed to install '\(detected.name)': \(error.localizedDescription)")
                    }
                }
            }
        }

        return ModInstallSummary(
            installedMods: installedResults,
            warnings: warnings,
            errors: errors
        )
    }

    private func installDetectedMod(
        _ detected: Mod,
        searchRoot: URL,
        into modsDirectory: URL,
        existingMods: [Mod]
    ) throws -> ModInstallResult {
        let fileManager = FileManager.default

        // Determine destination folder name
        let folderName: String
        if detected.directoryURL.standardizedFileURL.path == searchRoot.standardizedFileURL.path {
            folderName = sanitizeFolderName(detected.name)
        } else {
            folderName = detected.directoryURL.lastPathComponent
        }

        // Check if an existing mod with the same UniqueID exists
        let matchingExisting = existingMods.first { $0.id.caseInsensitiveCompare(detected.id) == .orderedSame }
        let isUpdate = matchingExisting != nil

        let destinationFolderURL = matchingExisting?.directoryURL ?? modsDirectory.appendingPathComponent(folderName)

        // Preserve existing config.json if old mod has one and incoming mod does not
        if let existing = matchingExisting, existing.hasConfig {
            let oldConfigURL = existing.configURL
            let newConfigURL = detected.directoryURL.appendingPathComponent("config.json")
            if !fileManager.fileExists(atPath: newConfigURL.path) {
                try? fileManager.copyItem(at: oldConfigURL, to: newConfigURL)
            }
        }

        // If destination folder already exists, remove it before replacing
        if fileManager.fileExists(atPath: destinationFolderURL.path) {
            try fileManager.removeItem(at: destinationFolderURL)
        }

        // Ensure parent directory exists
        try fileManager.createDirectory(at: destinationFolderURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Copy mod files to final destination
        try fileManager.copyItem(at: detected.directoryURL, to: destinationFolderURL)

        return ModInstallResult(
            modName: detected.name,
            version: detected.version,
            uniqueID: detected.id,
            installedPath: destinationFolderURL,
            isUpdate: isUpdate
        )
    }

    public func extractArchive(at sourceURL: URL, to destinationURL: URL) throws {
        let ext = sourceURL.pathExtension.lowercased()
        let process = Process()
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        if ext == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", sourceURL.path, destinationURL.path]
        } else if ext == "tar" || ext == "gz" || ext == "tgz" || ext == "bz2" || ext == "xz" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", sourceURL.path, "-C", destinationURL.path]
        } else if ext == "7z" {
            if let p7zip = findExecutable(named: "7z") ?? findExecutable(named: "7za") {
                process.executableURL = p7zip
                process.arguments = ["x", "-y", "-o\(destinationURL.path)", sourceURL.path]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-xf", sourceURL.path, "-C", destinationURL.path]
            }
        } else if ext == "rar" {
            if let unrar = findExecutable(named: "unrar") ?? findExecutable(named: "7z") {
                process.executableURL = unrar
                if unrar.lastPathComponent == "7z" {
                    process.arguments = ["x", "-y", "-o\(destinationURL.path)", sourceURL.path]
                } else {
                    process.arguments = ["x", "-y", sourceURL.path, destinationURL.path]
                }
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-xf", sourceURL.path, "-C", destinationURL.path]
            }
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", sourceURL.path, destinationURL.path]
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fullError = errorMsg.isEmpty ? "Archive extraction failed (exit code \(process.terminationStatus))." : errorMsg
            throw NSError(domain: "ModInstaller", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: fullError])
        }
    }

    private func cleanExtractedFiles(in directory: URL) {
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            var itemsToDelete: [URL] = []
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "__MACOSX" || fileURL.lastPathComponent == ".DS_Store" {
                    itemsToDelete.append(fileURL)
                }
            }
            for item in itemsToDelete {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func sanitizeFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "InstalledMod" : trimmed
    }

    private func findExecutable(named name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                return URL(fileURLWithPath: c)
            }
        }
        return nil
    }

    private func findFile(named name: String, in root: URL) -> URL? {
        let fileManager = FileManager.default
        let direct = root.appendingPathComponent(name)
        if fileManager.fileExists(atPath: direct.path) {
            return direct
        }
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                    return fileURL
                }
            }
        }
        return nil
    }
}
