import Foundation

public struct NexusDetails: Codable, Hashable {
    public var username: String?
    public var isPremium: Bool
    public var key: String?

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case isPremium = "IsPremium"
        case key = "Key"
    }

    public init(username: String? = nil, isPremium: Bool = false, key: String? = nil) {
        self.username = username
        self.isPremium = isPremium
        self.key = key
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        self.key = try container.decodeIfPresent(String.self, forKey: .key)
    }
}

public struct GameDetails: Codable, Hashable {
    public var gameVersion: String
    public var smapiVersion: String
    public var system: Int

    enum CodingKeys: String, CodingKey {
        case gameVersion = "GameVersion"
        case smapiVersion = "SmapiVersion"
        case system = "System"
    }
}

public struct StardropSettings: Codable {
    public var lastSelectedProfileName: String
    public var smapiFolderPath: String?
    public var modFolderPath: String?
    public var modInstallPath: String?
    public var shouldAutomaticallySaveProfileChanges: Bool
    public var nexusDetails: NexusDetails
    public var gameDetails: GameDetails?

    enum CodingKeys: String, CodingKey {
        case lastSelectedProfileName = "LastSelectedProfileName"
        case smapiFolderPath = "SMAPIFolderPath"
        case modFolderPath = "ModFolderPath"
        case modInstallPath = "ModInstallPath"
        case shouldAutomaticallySaveProfileChanges = "ShouldAutomaticallySaveProfileChanges"
        case nexusDetails = "NexusDetails"
        case gameDetails = "GameDetails"
    }

    public init() {
        self.lastSelectedProfileName = "Default"
        self.smapiFolderPath = nil
        self.modFolderPath = nil
        self.modInstallPath = nil
        self.shouldAutomaticallySaveProfileChanges = true
        self.nexusDetails = NexusDetails()
        self.gameDetails = nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastSelectedProfileName = try container.decodeIfPresent(String.self, forKey: .lastSelectedProfileName) ?? "Default"
        self.smapiFolderPath = try container.decodeIfPresent(String.self, forKey: .smapiFolderPath)
        self.modFolderPath = try container.decodeIfPresent(String.self, forKey: .modFolderPath)
        self.modInstallPath = try container.decodeIfPresent(String.self, forKey: .modInstallPath)
        self.shouldAutomaticallySaveProfileChanges = try container.decodeIfPresent(Bool.self, forKey: .shouldAutomaticallySaveProfileChanges) ?? true
        self.nexusDetails = try container.decodeIfPresent(NexusDetails.self, forKey: .nexusDetails) ?? NexusDetails()
        self.gameDetails = try container.decodeIfPresent(GameDetails.self, forKey: .gameDetails)
    }
}
