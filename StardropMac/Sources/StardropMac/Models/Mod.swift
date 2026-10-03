import Foundation

public struct Mod: Identifiable, Hashable {
    public var id: String { manifest.uniqueID }
    public let manifest: ModManifest
    public let directoryURL: URL
    public var isEnabled: Bool
    public var suggestedVersion: String?
    public var updateURL: URL?

    public var name: String { manifest.name }
    public var author: String { manifest.author }
    public var version: String { manifest.version }
    public var description: String { manifest.description ?? "No description provided." }
    public var updateKeys: [String] { manifest.updateKeys }

    public var configURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    public var hasConfig: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    public var nexusModId: Int? {
        for key in manifest.updateKeys {
            let lower = key.lowercased()
            if lower.hasPrefix("nexus:") {
                let idStr = String(key.dropFirst("nexus:".count)).trimmingCharacters(in: .whitespaces)
                if let id = Int(idStr) {
                    return id
                }
            }
        }
        return nil
    }

    public var nexusURL: URL? {
        if let update = updateURL {
            return update
        }
        if let id = nexusModId {
            return URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(id)")
        }
        return nil
    }

    public var hasUpdate: Bool {
        guard let suggested = suggestedVersion, !suggested.isEmpty else { return false }
        return suggested != manifest.version
    }

    public var isCoreSMAPI: Bool {
        ModScannerService.coreModIds.contains(id.lowercased())
    }

    public init(
        manifest: ModManifest,
        directoryURL: URL,
        isEnabled: Bool = true,
        suggestedVersion: String? = nil
    ) {
        self.manifest = manifest
        self.directoryURL = directoryURL
        self.isEnabled = isEnabled
        self.suggestedVersion = suggestedVersion
    }
}
