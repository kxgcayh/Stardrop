import Foundation

public struct NexusValidationResponse: Codable {
    public let name: String?
    public let isPremium: Bool?
    public let profileUrl: String?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case name
        case isPremium = "is_premium"
        case profileUrl = "profile_url"
        case message
    }
}

public struct NexusEndorsement: Codable {
    public let modId: Int
    public let domainName: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case modId = "mod_id"
        case domainName = "domain_name"
        case status
    }

    public var isEndorsed: Bool {
        status?.caseInsensitiveCompare("ENDORSED") == .orderedSame
    }
}

public enum EndorsementResponse: Equatable {
    case endorsed
    case abstained
    case isOwnMod
    case tooSoonAfterDownload
    case notDownloadedMod
    case unknown(String?)
}

public struct NexusEndorsementResult: Codable {
    public let message: String?
    public let status: String?
}

public final class NexusService {
    public static let shared = NexusService()

    public let apiBaseURL = URL(string: "https://api.nexusmods.com/v1/")!
    public let getApiKeyURL = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api")!

    public func validateKey(_ apiKey: String) async throws -> NexusValidationResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(domain: "NexusService", code: 400, userInfo: [NSLocalizedDescriptionKey: "API Key cannot be empty."])
        }

        let validateURL = apiBaseURL.appendingPathComponent("users/validate.json")
        var request = URLRequest(url: validateURL)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "apikey")
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue("1.10.4", forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/1.10.4 macOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NexusService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        if httpResponse.statusCode == 401 {
            throw NSError(domain: "NexusService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid Nexus API Key. Please verify your key on Nexus Mods."])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "NexusService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Nexus Mods returned status \(httpResponse.statusCode)."])
        }

        let decoded = try JSONDecoder().decode(NexusValidationResponse.self, from: data)
        if let msg = decoded.message, !msg.isEmpty {
            throw NSError(domain: "NexusService", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return decoded
    }

    public func getEndorsements(apiKey: String) async throws -> [NexusEndorsement] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return []
        }

        let url = apiBaseURL.appendingPathComponent("user/endorsements")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "apikey")
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue("1.10.4", forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/1.10.4 macOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        let endorsements = try JSONDecoder().decode([NexusEndorsement].self, from: data)
        return endorsements.filter { $0.domainName?.caseInsensitiveCompare("stardewvalley") == .orderedSame }
    }

    public func setModEndorsement(modId: Int, endorse: Bool, apiKey: String) async throws -> EndorsementResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .unknown("API key is missing.")
        }

        let endpoint = "games/stardewvalley/mods/\(modId)/\(endorse ? "endorse.json" : "abstain.json")"
        let url = apiBaseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(trimmedKey, forHTTPHeaderField: "apikey")
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue("1.10.4", forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/1.10.4 macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = "{\"Version\":\"1.0.0\"}"
        request.httpBody = payload.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let decoded = try? JSONDecoder().decode(NexusEndorsementResult.self, from: data) {
            let statusUpper = decoded.status?.uppercased()
            if statusUpper == "ENDORSED" {
                return .endorsed
            } else if statusUpper == "ABSTAINED" {
                return .abstained
            } else if statusUpper == "ERROR" {
                let msgUpper = decoded.message?.uppercased() ?? ""
                if msgUpper.contains("IS_OWN_MOD") {
                    return .isOwnMod
                } else if msgUpper.contains("TOO_SOON_AFTER_DOWNLOAD") {
                    return .tooSoonAfterDownload
                } else if msgUpper.contains("NOT_DOWNLOADED_MOD") {
                    return .notDownloadedMod
                }
                return .unknown(decoded.message)
            } else {
                return .unknown(decoded.message)
            }
        }

        return .unknown(nil)
    }
}
