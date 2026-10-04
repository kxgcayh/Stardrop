import Foundation

public struct CollectionInfo: Codable, Hashable {
    public let author: String?
    public let authorUrl: String?
    public let name: String
    public let description: String?
    public let installInstructions: String?
    public let domainName: String?
    public let gameVersions: [String]?

    enum CodingKeys: String, CodingKey {
        case author
        case authorUrl
        case name
        case description
        case installInstructions
        case domainName
        case gameVersions
    }

    public init(
        author: String? = nil,
        authorUrl: String? = nil,
        name: String,
        description: String? = nil,
        installInstructions: String? = nil,
        domainName: String? = "stardewvalley",
        gameVersions: [String]? = nil
    ) {
        self.author = author
        self.authorUrl = authorUrl
        self.name = name
        self.description = description
        self.installInstructions = installInstructions
        self.domainName = domainName
        self.gameVersions = gameVersions
    }
}

public struct CollectionSourceInfo: Codable, Hashable {
    public let type: String
    public let modId: Int?
    public let fileId: Int?
    public let updatePolicy: String?
    public let adultContent: Bool?
    public let md5: String?
    public let fileSize: Int?
    public let logicalFilename: String?
    public let fileExpression: String?
    public let tag: String?
    public let url: String?
    public let instructions: String?

    enum CodingKeys: String, CodingKey {
        case type
        case modId
        case fileId
        case updatePolicy
        case adultContent
        case md5
        case fileSize
        case logicalFilename
        case fileExpression
        case tag
        case url
        case instructions
    }

    public var isNexus: Bool {
        type.caseInsensitiveCompare("nexus") == .orderedSame
    }

    public var isBundled: Bool {
        type.caseInsensitiveCompare("bundle") == .orderedSame
    }

    public var isDirect: Bool {
        type.caseInsensitiveCompare("direct") == .orderedSame
    }

    public var isManual: Bool {
        type.caseInsensitiveCompare("browse") == .orderedSame || type.caseInsensitiveCompare("manual") == .orderedSame
    }
}

public struct CollectionMod: Codable, Identifiable, Hashable {
    public var id: String {
        if let modId = source.modId, let fileId = source.fileId {
            return "\(modId)_\(fileId)"
        }
        return "\(name)_\(version)"
    }

    public let name: String
    public let version: String
    public let optional: Bool
    public let domainName: String?
    public let source: CollectionSourceInfo
    public let instructions: String?
    public let author: String?
    public let phase: Int?
    public let fileOverrides: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case optional
        case domainName
        case source
        case instructions
        case author
        case phase
        case fileOverrides
    }
}

public struct CollectionModRule: Codable, Hashable {
    public let type: String?
}

public struct CollectionManifest: Codable {
    public let info: CollectionInfo
    public let mods: [CollectionMod]
    public let modRules: [CollectionModRule]?

    enum CodingKeys: String, CodingKey {
        case info
        case mods
        case modRules
    }

    public var requiredMods: [CollectionMod] {
        mods.filter { !$0.optional }
    }

    public var optionalMods: [CollectionMod] {
        mods.filter { $0.optional }
    }
}
