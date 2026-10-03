import Foundation

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

extension KeyedDecodingContainer where K == DynamicCodingKey {
    func decodeCaseInsensitive<T: Decodable>(_ type: T.Type, forKey keyName: String) -> T? {
        if let exactKey = DynamicCodingKey(stringValue: keyName),
           let value = try? decode(type, forKey: exactKey) {
            return value
        }
        for key in allKeys {
            if key.stringValue.caseInsensitiveCompare(keyName) == .orderedSame {
                if let value = try? decode(type, forKey: key) {
                    return value
                }
            }
        }
        return nil
    }
}

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

    public init(uniqueID: String, minimumVersion: String? = nil, isRequired: Bool = true) {
        self.uniqueID = uniqueID
        self.minimumVersion = minimumVersion
        self.isRequired = isRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.uniqueID = container.decodeCaseInsensitive(String.self, forKey: "UniqueID") ?? ""
        self.minimumVersion = container.decodeCaseInsensitive(String.self, forKey: "MinimumVersion")
        self.isRequired = container.decodeCaseInsensitive(Bool.self, forKey: "IsRequired") ?? true
    }
}

public struct ManifestContentPackFor: Codable, Hashable {
    public let uniqueID: String
    public let minimumVersion: String?

    enum CodingKeys: String, CodingKey {
        case uniqueID = "UniqueID"
        case minimumVersion = "MinimumVersion"
    }

    public init(uniqueID: String, minimumVersion: String? = nil) {
        self.uniqueID = uniqueID
        self.minimumVersion = minimumVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.uniqueID = container.decodeCaseInsensitive(String.self, forKey: "UniqueID") ?? ""
        self.minimumVersion = container.decodeCaseInsensitive(String.self, forKey: "MinimumVersion")
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
    public let contentPackFor: ManifestContentPackFor?

    public var allDependencies: [ManifestDependency] {
        var list: [ManifestDependency] = []
        if let cp = contentPackFor {
            list.append(ManifestDependency(uniqueID: cp.uniqueID, minimumVersion: cp.minimumVersion, isRequired: true))
        }
        for dep in dependencies {
            if !list.contains(where: { $0.uniqueID.caseInsensitiveCompare(dep.uniqueID) == .orderedSame }) {
                list.append(dep)
            }
        }
        return list
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case author = "Author"
        case version = "Version"
        case description = "Description"
        case uniqueID = "UniqueID"
        case entryDll = "EntryDll"
        case updateKeys = "UpdateKeys"
        case dependencies = "Dependencies"
        case contentPackFor = "ContentPackFor"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.name = container.decodeCaseInsensitive(String.self, forKey: "Name") ?? "Unnamed Mod"
        self.author = container.decodeCaseInsensitive(String.self, forKey: "Author") ?? "Unknown Author"
        self.version = container.decodeCaseInsensitive(String.self, forKey: "Version") ?? "1.0.0"
        self.description = container.decodeCaseInsensitive(String.self, forKey: "Description")
        self.uniqueID = container.decodeCaseInsensitive(String.self, forKey: "UniqueID") ?? UUID().uuidString
        self.entryDll = container.decodeCaseInsensitive(String.self, forKey: "EntryDll")

        // UpdateKeys can be [String], a single String, or absent
        if let keysArray = container.decodeCaseInsensitive([String].self, forKey: "UpdateKeys") {
            self.updateKeys = keysArray
        } else if let singleKey = container.decodeCaseInsensitive(String.self, forKey: "UpdateKeys") {
            self.updateKeys = singleKey.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            self.updateKeys = []
        }

        self.dependencies = container.decodeCaseInsensitive([ManifestDependency].self, forKey: "Dependencies") ?? []
        self.contentPackFor = container.decodeCaseInsensitive(ManifestContentPackFor.self, forKey: "ContentPackFor")
    }
}
