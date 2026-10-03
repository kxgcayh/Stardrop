import Foundation

public struct ManifestDependency: Codable, Identifiable, Hashable {
    public var id: String { uniqueID }
    public let uniqueID: String
    public let minimumVersion: String?
    public let isRequired: Bool

    enum CodingKeys: String, CodingKey {
        case uniqueID = "UniqueID"
        case minimumVersion = "MinimumVersion"
        case isRequired = "IsRequired"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uniqueID = try container.decode(String.self, forKey: .uniqueID)
        self.minimumVersion = try container.decodeIfPresent(String.self, forKey: .minimumVersion)
        self.isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
    }
}

public struct ModManifest: Codable, Hashable {
    public let name: String
    public let author: String
    public let version: String
    public let description: String?
    public let uniqueID: String
    public let entryDll: String?
    public let updateKeys: [String]
    public let dependencies: [ManifestDependency]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case author = "Author"
        case version = "Version"
        case description = "Description"
        case uniqueID = "UniqueID"
        case entryDll = "EntryDll"
        case updateKeys = "UpdateKeys"
        case dependencies = "Dependencies"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Mod"
        self.author = try container.decodeIfPresent(String.self, forKey: .author) ?? "Unknown Author"
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.uniqueID = try container.decodeIfPresent(String.self, forKey: .uniqueID) ?? UUID().uuidString
        self.entryDll = try container.decodeIfPresent(String.self, forKey: .entryDll)

        // UpdateKeys can be [String], a single String, or absent
        if let keysArray = try? container.decode([String].self, forKey: .updateKeys) {
            self.updateKeys = keysArray
        } else if let singleKey = try? container.decode(String.self, forKey: .updateKeys) {
            self.updateKeys = singleKey.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            self.updateKeys = []
        }

        self.dependencies = try container.decodeIfPresent([ManifestDependency].self, forKey: .dependencies) ?? []
    }
}
