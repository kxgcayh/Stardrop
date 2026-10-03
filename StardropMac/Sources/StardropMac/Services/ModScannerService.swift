import Foundation

public final class ModScannerService {
    public static let shared = ModScannerService()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return decoder
    }()

    public static let coreModIds: Set<String> = [
        "smapi.consolecommands",
        "smapi.errorhandler",
        "smapi.savebackup"
    ]

    public func scanMods(in modsFolder: URL, enabledIds: Set<String>? = nil) -> [Mod] {
        var results: [Mod] = []
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: modsFolder.path) else {
            return []
        }

        scanDirectory(modsFolder, results: &results)

        // Apply enabled state if provided, but core SMAPI mods are always enabled
        let lowercasedEnabled = enabledIds.map { Set($0.map { $0.lowercased() }) }
        for i in 0..<results.count {
            let id = results[i].manifest.uniqueID.lowercased()
            if Self.coreModIds.contains(id) {
                results[i].isEnabled = true
            } else if let enabledSet = lowercasedEnabled {
                results[i].isEnabled = enabledSet.contains(id)
            }
        }

        // Sort alphabetically by name
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanDirectory(
        _ url: URL,
        results: inout [Mod]
    ) {
        let fileManager = FileManager.default
        let manifestURL = url.appendingPathComponent("manifest.json")

        // If this folder has a manifest.json, it is a mod!
        if fileManager.fileExists(atPath: manifestURL.path) {
            if let mod = parseMod(at: url) {
                results.append(mod)
            }
            return // Don't search inside this mod directory for sub-mods
        }

        // Otherwise, inspect its subdirectories
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for item in contents {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                scanDirectory(item, results: &results)
            }
        }
    }

    public func parseMod(at folderURL: URL) -> Mod? {
        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }

        do {
            let manifest = try jsonDecoder.decode(ModManifest.self, from: data)
            return Mod(
                manifest: manifest,
                directoryURL: folderURL,
                isEnabled: true
            )
        } catch {
            print("Failed to decode manifest at \(manifestURL.path): \(error)")
            return nil
        }
    }
}
