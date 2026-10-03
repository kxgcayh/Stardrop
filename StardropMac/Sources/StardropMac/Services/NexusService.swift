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
}
