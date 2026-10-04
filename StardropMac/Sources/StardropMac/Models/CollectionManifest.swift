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

    public init(
        name: String,
        version: String,
        optional: Bool = false,
        domainName: String? = nil,
        source: CollectionSourceInfo,
        instructions: String? = nil,
        author: String? = nil,
        phase: Int? = nil,
        fileOverrides: [String]? = nil
    ) {
        self.name = name
        self.version = version
        self.optional = optional
        self.domainName = domainName
        self.source = source
        self.instructions = instructions
        self.author = author
        self.phase = phase
        self.fileOverrides = fileOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decode(String.self, forKey: .version)
        self.optional = (try? container.decodeIfPresent(Bool.self, forKey: .optional)) ?? false
        self.domainName = try? container.decodeIfPresent(String.self, forKey: .domainName)
        self.source = try container.decode(CollectionSourceInfo.self, forKey: .source)
        self.instructions = try? container.decodeIfPresent(String.self, forKey: .instructions)
        self.author = try? container.decodeIfPresent(String.self, forKey: .author)
        self.phase = try? container.decodeIfPresent(Int.self, forKey: .phase)
        self.fileOverrides = try? container.decodeIfPresent([String].self, forKey: .fileOverrides)
    }

    public var isSMAPI: Bool {
        if source.modId == 2400 {
            return true
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean == "smapi" {
            return true
        }
        if clean.contains("stardew modding api") {
            return true
        }
        if clean.hasPrefix("smapi ") || clean.hasPrefix("smapi-") || clean.hasPrefix("smapi:") || clean.hasPrefix("smapi -") {
            let forbidden = ["cheat", "spawner", "config", "recolor", "helper", "loader", "framework"]
            if forbidden.contains(where: { clean.contains($0) }) {
                return false
            }
            return true
        }
        if let logic = source.logicalFilename?.lowercased(), logic.contains("smapi") && logic.contains("installer") {
            return true
        }
        if let fileExpr = source.fileExpression?.lowercased(), fileExpr.contains("smapi") && fileExpr.contains("installer") {
            return true
        }
        return false
    }

    public static func findInstalledSMAPI(in existingMods: [Mod]) -> Mod? {
        if let coreMod = existingMods.first(where: { $0.isCoreSMAPI }) {
            return coreMod
        }
        if let nexusMod = existingMods.first(where: { $0.nexusModId == 2400 }) {
            return nexusMod
        }
        if let idMatch = existingMods.first(where: {
            let lower = $0.id.lowercased()
            return lower == "smapi.consolecommands" || lower == "smapi"
        }) {
            return idMatch
        }
        if let nameMod = existingMods.first(where: {
            let lower = $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "smapi" || lower.hasPrefix("smapi ") || lower.contains("stardew modding api")
        }) {
            return nameMod
        }
        return nil
    }

    public static func installedSMAPIVersion(in existingMods: [Mod], fallbackVersion: String? = nil) -> String? {
        if let mod = findInstalledSMAPI(in: existingMods) {
            return mod.version
        }
        if let fb = fallbackVersion, !fb.isEmpty {
            return fb
        }
        return nil
    }

    public func findMatchingMod(in existingMods: [Mod], currentSMAPIVersion: String? = nil) -> Mod? {
        // Special handling for SMAPI (core mod in Stardrop)
        if isSMAPI {
            let installedSMAPI = Self.findInstalledSMAPI(in: existingMods)
            let installedVersion = installedSMAPI?.version ?? currentSMAPIVersion

            guard let ver = installedVersion, !ver.isEmpty else {
                return nil
            }

            // If current installed version is lower than contained in collections, make it available to download
            if VersionHelper.isVersion(ver, lowerThan: version) {
                return nil
            }

            return installedSMAPI
        }

        // 1. Direct Nexus Mod ID match
        if let modId = source.modId {
            if let match = existingMods.first(where: { $0.nexusModId == modId }) {
                return match
            }
        }
        // 2. Exact case-insensitive name match
        if let match = existingMods.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        // 3. Exact case-insensitive unique ID match
        if let match = existingMods.first(where: { $0.id.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        // 4. Clean alphanumeric name match
        let cleanName = name.filter { $0.isLetter || $0.isNumber }.lowercased()
        if !cleanName.isEmpty {
            if let match = existingMods.first(where: {
                let existingClean = $0.name.filter { $0.isLetter || $0.isNumber }.lowercased()
                return existingClean == cleanName || $0.id.lowercased() == cleanName
            }) {
                return match
            }
        }
        // 5. Prefix match for descriptive names (e.g. "Content Patcher - Main File")
        if cleanName.count >= 4 {
            if let match = existingMods.first(where: {
                let existingClean = $0.name.filter { $0.isLetter || $0.isNumber }.lowercased()
                guard existingClean.count >= 4 else { return false }
                return cleanName.hasPrefix(existingClean) || existingClean.hasPrefix(cleanName)
            }) {
                return match
            }
        }
        return nil
    }

    public func isInstalled(in existingMods: [Mod], currentSMAPIVersion: String? = nil) -> Bool {
        return findMatchingMod(in: existingMods, currentSMAPIVersion: currentSMAPIVersion) != nil
    }
}

public struct VersionHelper {
    public static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let clean1 = cleanVersionString(v1)
        let clean2 = cleanVersionString(v2)

        let parts1 = clean1.split(separator: "-", maxSplits: 1).map(String.init)
        let parts2 = clean2.split(separator: "-", maxSplits: 1).map(String.init)

        let segments1 = parts1.first?.split(separator: ".").map(String.init) ?? []
        let segments2 = parts2.first?.split(separator: ".").map(String.init) ?? []

        let maxCount = max(segments1.count, segments2.count)
        for i in 0..<maxCount {
            let s1 = i < segments1.count ? segments1[i] : "0"
            let s2 = i < segments2.count ? segments2[i] : "0"

            if let n1 = Int(s1), let n2 = Int(s2) {
                if n1 < n2 { return .orderedAscending }
                if n1 > n2 { return .orderedDescending }
            } else {
                let comp = s1.localizedStandardCompare(s2)
                if comp != .orderedSame {
                    return comp
                }
            }
        }

        let pre1 = parts1.count > 1 ? parts1[1] : nil
        let pre2 = parts2.count > 1 ? parts2[1] : nil

        if pre1 != nil && pre2 == nil {
            return .orderedAscending
        } else if pre1 == nil && pre2 != nil {
            return .orderedDescending
        } else if let p1 = pre1, let p2 = pre2 {
            return p1.localizedStandardCompare(p2)
        }

        return .orderedSame
    }

    public static func isVersion(_ v1: String, lowerThan v2: String) -> Bool {
        return compare(v1, v2) == .orderedAscending
    }

    private static func cleanVersionString(_ v: String) -> String {
        var trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            trimmed = String(trimmed.dropFirst())
        }
        if let plusIndex = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plusIndex])
        }
        return trimmed
    }
}

public struct CollectionModRuleReference: Codable, Hashable {
    public let fileExpression: String?
    public let fileMD5: String?
    public let versionMatch: String?
    public let idHint: String?
    public let tag: String?
    public let logicalFileName: String?

    public func matches(_ mod: CollectionMod) -> Bool {
        if let t = tag, let modTag = mod.source.tag, t.caseInsensitiveCompare(modTag) == .orderedSame {
            return true
        }
        if let expr = fileExpression, let modExpr = mod.source.fileExpression, expr.caseInsensitiveCompare(modExpr) == .orderedSame {
            return true
        }
        if let logName = logicalFileName, let modLog = mod.source.logicalFilename, logName.caseInsensitiveCompare(modLog) == .orderedSame {
            return true
        }
        if let hint = idHint, mod.id.caseInsensitiveCompare(hint) == .orderedSame || mod.name.caseInsensitiveCompare(hint) == .orderedSame {
            return true
        }
        if let md5 = fileMD5, let modMd5 = mod.source.md5, md5.caseInsensitiveCompare(modMd5) == .orderedSame {
            return true
        }
        return false
    }

    public func matches(_ mod: Mod) -> Bool {
        if let hint = idHint {
            if mod.id.caseInsensitiveCompare(hint) == .orderedSame ||
               mod.name.caseInsensitiveCompare(hint) == .orderedSame {
                return true
            }
        }
        if let logName = logicalFileName {
            if mod.name.caseInsensitiveCompare(logName) == .orderedSame {
                return true
            }
        }
        return false
    }

    public var displayName: String {
        idHint ?? logicalFileName ?? fileExpression ?? tag ?? "Specified mod"
    }
}

public struct CollectionModRule: Codable, Hashable {
    public let type: String
    public let source: CollectionModRuleReference?
    public let reference: CollectionModRuleReference?

    public var isConflict: Bool {
        type.caseInsensitiveCompare("conflicts") == .orderedSame
    }

    public var isRequirement: Bool {
        type.caseInsensitiveCompare("requires") == .orderedSame
    }

    public var isRecommendation: Bool {
        type.caseInsensitiveCompare("recommends") == .orderedSame || type.caseInsensitiveCompare("recommend") == .orderedSame
    }

    public var isOrdering: Bool {
        type.caseInsensitiveCompare("before") == .orderedSame || type.caseInsensitiveCompare("after") == .orderedSame
    }
}

public struct CollectionRuleNotice: Identifiable, Hashable {
    public enum NoticeLevel: String, Codable {
        case conflict
        case missingRequirement
        case recommendation
        case ordering
    }

    public let id = UUID()
    public let level: NoticeLevel
    public let sourceModName: String
    public let targetModName: String
    public let message: String

    public init(level: NoticeLevel, sourceModName: String, targetModName: String, message: String) {
        self.level = level
        self.sourceModName = sourceModName
        self.targetModName = targetModName
        self.message = message
    }
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

    public func evaluateRules(existingMods: [Mod]) -> [CollectionRuleNotice] {
        guard let rules = modRules, !rules.isEmpty else { return [] }
        var notices: [CollectionRuleNotice] = []
        var seenMessages = Set<String>()

        for rule in rules {
            let sourceName: String
            if let srcRef = rule.source {
                if let mod = mods.first(where: { srcRef.matches($0) }) {
                    sourceName = mod.name
                } else if let inst = existingMods.first(where: { srcRef.matches($0) }) {
                    sourceName = inst.name
                } else {
                    sourceName = srcRef.displayName
                }
            } else {
                sourceName = info.name
            }

            let targetName: String
            let isTargetPresentInCollection: Bool
            let isTargetPresentInLibrary: Bool

            if let targetRef = rule.reference {
                if let mod = mods.first(where: { targetRef.matches($0) }) {
                    targetName = mod.name
                    isTargetPresentInCollection = true
                    isTargetPresentInLibrary = false
                } else if let inst = existingMods.first(where: { targetRef.matches($0) }) {
                    targetName = inst.name
                    isTargetPresentInCollection = false
                    isTargetPresentInLibrary = true
                } else {
                    targetName = targetRef.displayName
                    isTargetPresentInCollection = false
                    isTargetPresentInLibrary = false
                }
            } else {
                targetName = "Unknown mod"
                isTargetPresentInCollection = false
                isTargetPresentInLibrary = false
            }

            if rule.isConflict {
                if isTargetPresentInCollection || isTargetPresentInLibrary {
                    let loc = isTargetPresentInLibrary ? "already installed in your library" : "also included in this collection"
                    let msg = "\(sourceName) conflicts with \(targetName) (\(loc))."
                    if !seenMessages.contains(msg) {
                        seenMessages.insert(msg)
                        notices.append(CollectionRuleNotice(
                            level: .conflict,
                            sourceModName: sourceName,
                            targetModName: targetName,
                            message: msg
                        ))
                    }
                }
            } else if rule.isRequirement {
                if !isTargetPresentInCollection && !isTargetPresentInLibrary {
                    let msg = "\(sourceName) requires \(targetName), which is not present in this collection or your library."
                    if !seenMessages.contains(msg) {
                        seenMessages.insert(msg)
                        notices.append(CollectionRuleNotice(
                            level: .missingRequirement,
                            sourceModName: sourceName,
                            targetModName: targetName,
                            message: msg
                        ))
                    }
                }
            } else if rule.isRecommendation {
                if !isTargetPresentInCollection && !isTargetPresentInLibrary {
                    let msg = "\(sourceName) recommends \(targetName) for an optimal experience."
                    if !seenMessages.contains(msg) {
                        seenMessages.insert(msg)
                        notices.append(CollectionRuleNotice(
                            level: .recommendation,
                            sourceModName: sourceName,
                            targetModName: targetName,
                            message: msg
                        ))
                    }
                }
            }
        }

        return notices
    }
}
