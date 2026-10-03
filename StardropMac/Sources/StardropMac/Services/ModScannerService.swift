import Foundation

public final class ModScannerService {
    public static let shared = ModScannerService()

    private let jsonDecoder = JSONDecoder()

    public func scanMods(in modsFolder: URL, enabledIds: Set<String>? = nil) -> [Mod] {
        var results: [Mod] = []
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: modsFolder.path) else {
            return []
        }

        scanDirectory(modsFolder, rootModsURL: modsFolder, currentGroup: nil, results: &results)

        // Apply enabled state if provided
        if let enabledIds = enabledIds {
            for i in 0..<results.count {
                let id = results[i].manifest.uniqueID
                results[i].isEnabled = enabledIds.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
            }
        }

        // Sort alphabetically by name
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanDirectory(
        _ url: URL,
        rootModsURL: URL,
        currentGroup: String?,
        results: inout [Mod]
    ) {
        let fileManager = FileManager.default
        let manifestURL = url.appendingPathComponent("manifest.json")

        // If this folder has a manifest.json, it is a mod!
        if fileManager.fileExists(atPath: manifestURL.path) {
            if let mod = parseMod(at: url, group: currentGroup) {
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
                // If we're at the top-level Mods folder and the folder looks like a group (e.g. "[MODS] - Core")
                let group = (url == rootModsURL) ? item.lastPathComponent : currentGroup
                scanDirectory(item, rootModsURL: rootModsURL, currentGroup: group, results: &results)
            }
        }
    }

    public func parseMod(at folderURL: URL, group: String?) -> Mod? {
        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }

        do {
            let manifest = try jsonDecoder.decode(ModManifest.self, from: data)
            return Mod(
                manifest: manifest,
                directoryURL: folderURL,
                isEnabled: true,
                groupName: group
            )
        } catch {
            print("Failed to decode manifest at \(manifestURL.path): \(error)")
            return nil
        }
    }
}
