import Foundation

public struct ModReference: Codable, Hashable {
    public let uniqueId: String
    public let sourceId: String?

    public init(uniqueId: String, sourceId: String? = nil) {
        self.uniqueId = uniqueId
        self.sourceId = sourceId
    }

    public init(from decoder: Decoder) throws {
        if let singleStr = try? decoder.singleValueContainer().decode(String.self) {
            self.uniqueId = singleStr
            self.sourceId = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        self.sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
    }

    public func encode(to encoder: Encoder) throws {
        if sourceId == nil {
            var container = encoder.singleValueContainer()
            try container.encode(uniqueId)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uniqueId, forKey: .uniqueId)
            try container.encode(sourceId, forKey: .sourceId)
        }
    }

    enum CodingKeys: String, CodingKey {
        case uniqueId = "UniqueId"
        case sourceId = "SourceId"
    }
}

public struct Profile: Codable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var isProtected: Bool
    public var sourceId: String?
    public var enabledModIds: [ModReference]
    public var notes: [String] // Simplified or placeholder for notes

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case isProtected = "IsProtected"
        case sourceId = "SourceId"
        case enabledModIds = "EnabledModIds"
    }

    public init(
        name: String,
        isProtected: Bool = false,
        sourceId: String? = nil,
        enabledModIds: [ModReference] = [],
        notes: [String] = []
    ) {
        self.name = name
        self.isProtected = isProtected
        self.sourceId = sourceId
        self.enabledModIds = enabledModIds
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default"
        self.isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
        self.sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        self.enabledModIds = try container.decodeIfPresent([ModReference].self, forKey: .enabledModIds) ?? []
        self.notes = []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(isProtected, forKey: .isProtected)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(enabledModIds, forKey: .enabledModIds)
    }

    public func isModEnabled(uniqueId: String) -> Bool {
        enabledModIds.contains { $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame }
    }
}
