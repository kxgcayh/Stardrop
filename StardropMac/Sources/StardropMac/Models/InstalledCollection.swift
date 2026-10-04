import Foundation

public struct InstalledCollection: Codable, Identifiable, Hashable {
    public var id: String { "\(domainName)-\(slug)" }
    public let slug: String
    public let domainName: String
    public var revisionNumber: Int
    public var name: String
    public var author: String?
    public var summary: String?
    public var installedDate: Date
    public var profileName: String
    public var installedModIds: [String]
    public var latestRevisionNumber: Int?
    public var lastCheckedDate: Date?
    public var isDedicatedProfile: Bool

    public var hasUpdate: Bool {
        guard let latest = latestRevisionNumber else { return false }
        return latest > revisionNumber
    }

    public var nexusURL: URL? {
        URL(string: "https://www.nexusmods.com/\(domainName)/collections/\(slug)")
    }

    enum CodingKeys: String, CodingKey {
        case slug
        case domainName
        case revisionNumber
        case name
        case author
        case summary
        case installedDate
        case profileName
        case installedModIds
        case latestRevisionNumber
        case lastCheckedDate
        case isDedicatedProfile
    }

    public init(
        slug: String,
        domainName: String = "stardewvalley",
        revisionNumber: Int,
        name: String,
        author: String? = nil,
        summary: String? = nil,
        installedDate: Date = Date(),
        profileName: String,
        installedModIds: [String] = [],
        latestRevisionNumber: Int? = nil,
        lastCheckedDate: Date? = nil,
        isDedicatedProfile: Bool = false
    ) {
        self.slug = slug
        self.domainName = domainName
        self.revisionNumber = revisionNumber
        self.name = name
        self.author = author
        self.summary = summary
        self.installedDate = installedDate
        self.profileName = profileName
        self.installedModIds = installedModIds
        self.latestRevisionNumber = latestRevisionNumber
        self.lastCheckedDate = lastCheckedDate
        self.isDedicatedProfile = isDedicatedProfile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.domainName = (try? container.decodeIfPresent(String.self, forKey: .domainName)) ?? "stardewvalley"
        self.revisionNumber = try container.decode(Int.self, forKey: .revisionNumber)
        self.name = try container.decode(String.self, forKey: .name)
        self.author = try? container.decodeIfPresent(String.self, forKey: .author)
        self.summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        self.installedDate = (try? container.decodeIfPresent(Date.self, forKey: .installedDate)) ?? Date()
        self.profileName = try container.decode(String.self, forKey: .profileName)
        self.installedModIds = (try? container.decodeIfPresent([String].self, forKey: .installedModIds)) ?? []
        self.latestRevisionNumber = try? container.decodeIfPresent(Int.self, forKey: .latestRevisionNumber)
        self.lastCheckedDate = try? container.decodeIfPresent(Date.self, forKey: .lastCheckedDate)
        self.isDedicatedProfile = (try? container.decodeIfPresent(Bool.self, forKey: .isDedicatedProfile)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(domainName, forKey: .domainName)
        try container.encode(revisionNumber, forKey: .revisionNumber)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(installedDate, forKey: .installedDate)
        try container.encode(profileName, forKey: .profileName)
        try container.encode(installedModIds, forKey: .installedModIds)
        try container.encodeIfPresent(latestRevisionNumber, forKey: .latestRevisionNumber)
        try container.encodeIfPresent(lastCheckedDate, forKey: .lastCheckedDate)
        try container.encode(isDedicatedProfile, forKey: .isDedicatedProfile)
    }
}
