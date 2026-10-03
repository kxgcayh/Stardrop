import Foundation

public struct ModSearchEntry: Codable {
    public let id: String
    public let installedVersion: String?
    public let updateKeys: [String]

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case installedVersion = "InstalledVersion"
        case updateKeys = "UpdateKeys"
    }

    public init(id: String, installedVersion: String?, updateKeys: [String]) {
        self.id = id
        self.installedVersion = installedVersion
        self.updateKeys = updateKeys
    }
}

public struct ModSearchData: Codable {
    public let mods: [ModSearchEntry]
    public let apiVersion: String?
    public let gameVersion: String?
    public let platform: String
    public let includeExtendedMetadata: Bool

    enum CodingKeys: String, CodingKey {
        case mods = "Mods"
        case apiVersion = "ApiVersion"
        case gameVersion = "GameVersion"
        case platform = "Platform"
        case includeExtendedMetadata = "IncludeExtendedMetadata"
    }
}

public struct ModEntryVersion: Codable {
    public let version: String?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case url = "Url"
    }
}

public struct ModEntry: Codable {
    public let id: String
    public let suggestedUpdate: ModEntryVersion?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case suggestedUpdate = "SuggestedUpdate"
    }
}

public final class ModUpdateService {
    public static let shared = ModUpdateService()

    public func fetchUpdates(mods: [Mod], gameDetails: GameDetails?) async throws -> [ModEntry] {
        let entries = mods.compactMap { mod -> ModSearchEntry? in
            guard !mod.updateKeys.isEmpty else { return nil }
            return ModSearchEntry(
                id: mod.id,
                installedVersion: mod.version,
                updateKeys: mod.updateKeys
            )
        }

        guard !entries.isEmpty else {
            return []
        }

        let searchData = ModSearchData(
            mods: entries,
            apiVersion: gameDetails?.smapiVersion ?? "4.1.8",
            gameVersion: gameDetails?.gameVersion ?? "1.6.14",
            platform: "Mac",
            includeExtendedMetadata: true
        )

        let url = URL(string: "https://smapi.io/api/v3.0/mods")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue("1.10.4", forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/1.10.4 macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(searchData)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        let results = try JSONDecoder().decode([ModEntry].self, from: data)
        return results
    }
}
