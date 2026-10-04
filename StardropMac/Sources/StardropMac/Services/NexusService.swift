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

public struct NexusDownloadURL: Codable, Hashable {
    public let name: String
    public let shortName: String?
    public let uri: String

    enum CodingKeys: String, CodingKey {
        case name
        case shortName = "short_name"
        case uri = "URI"
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
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")

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
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")

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
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")
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

    public func getModDownloadURLs(
        gameDomain: String = "stardewvalley",
        modId: Int,
        fileId: Int,
        apiKey: String,
        key: String? = nil,
        expires: Int? = nil
    ) async throws -> [NexusDownloadURL] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(domain: "NexusService", code: 400, userInfo: [NSLocalizedDescriptionKey: "API Key cannot be empty."])
        }

        var urlString = "https://api.nexusmods.com/v1/games/\(gameDomain)/mods/\(modId)/files/\(fileId)/download_link.json"
        var queryItems: [URLQueryItem] = []
        if let key = key, !key.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: key))
        }
        if let expires = expires {
            queryItems.append(URLQueryItem(name: "expires", value: String(expires)))
        }
        if !queryItems.isEmpty, var comps = URLComponents(string: urlString) {
            comps.queryItems = queryItems
            if let fullURL = comps.url {
                urlString = fullURL.absoluteString
            }
        }

        guard let requestURL = URL(string: urlString) else {
            throw NSError(domain: "NexusService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid request URL."])
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "apikey")
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "NexusService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Nexus returned error \(statusCode): \(errorText)"])
        }

        return try JSONDecoder().decode([NexusDownloadURL].self, from: data)
    }

    public func downloadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        var request = URLRequest(url: sourceURL)
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "NexusDownload", code: code, userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(code)"])
        }

        let expectedLength = response.expectedContentLength
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let tempDestination = destinationURL.appendingPathExtension("downloading")
        if FileManager.default.fileExists(atPath: tempDestination.path) {
            try? FileManager.default.removeItem(at: tempDestination)
        }
        FileManager.default.createFile(atPath: tempDestination.path, contents: nil)

        guard let fileHandle = FileHandle(forWritingAtPath: tempDestination.path) else {
            throw NSError(domain: "NexusDownload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to open destination file for writing."])
        }

        defer {
            try? fileHandle.close()
        }

        var downloadedBytes: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(65536)
        var lastReportTime = Date()

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloadedBytes += 1

            if buffer.count >= 65536 {
                fileHandle.write(buffer)
                buffer.removeAll(keepingCapacity: true)

                if expectedLength > 0, Date().timeIntervalSince(lastReportTime) > 0.1 {
                    lastReportTime = Date()
                    let progress = Double(downloadedBytes) / Double(expectedLength)
                    onProgress?(progress)
                }
            }
        }

        if !buffer.isEmpty {
            fileHandle.write(buffer)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempDestination, to: destinationURL)
        onProgress?(1.0)
    }

    public struct CollectionRevisionData: Codable {
        public let id: Int?
        public let revisionNumber: Int?
        public let downloadLink: String?
        public let collection: CollectionBasicInfo?

        public struct CollectionBasicInfo: Codable {
            public let id: Int?
            public let name: String?
            public let summary: String?
        }
    }

    public func getCollectionRevision(
        slug: String,
        revision: Int? = nil,
        domainName: String = "stardewvalley",
        apiKey: String? = nil
    ) async throws -> CollectionRevisionData {
        let graphURL = URL(string: "https://api.nexusmods.com/v2/graphql")!
        var request = URLRequest(url: graphURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")

        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "apikey")
        }

        let query = """
        query GetCollectionRevision($slug: String!, $revision: Int, $domainName: String) {
          collectionRevision(slug: $slug, revision: $revision, domainName: $domainName) {
            id
            revisionNumber
            downloadLink
            collection {
              id
              name
              summary
            }
          }
        }
        """

        var variables: [String: Any] = [
            "slug": slug,
            "domainName": domainName
        ]
        if let rev = revision {
            variables["revision"] = rev
        }

        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "NexusService", code: code, userInfo: [NSLocalizedDescriptionKey: "GraphQL request failed with HTTP \(code)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "NexusService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from GraphQL API."])
        }

        if let errors = json["errors"] as? [[String: Any]], let first = errors.first, let msg = first["message"] as? String {
            throw NSError(domain: "NexusService", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let dataObj = json["data"] as? [String: Any],
              let revObj = dataObj["collectionRevision"] as? [String: Any] else {
            throw NSError(domain: "NexusService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Collection revision not found."])
        }

        let revData = try JSONSerialization.data(withJSONObject: revObj)
        return try JSONDecoder().decode(CollectionRevisionData.self, from: revData)
    }

    public func getCollectionDownloadURLs(from downloadLink: String, apiKey: String? = nil) async throws -> [NexusDownloadURL] {
        guard let url = URL(string: downloadLink) else {
            throw NSError(domain: "NexusService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid download link URL."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Stardrop", forHTTPHeaderField: "Application-Name")
        request.setValue(AppVersion.current, forHTTPHeaderField: "Application-Version")
        request.setValue("Stardrop/\(AppVersion.current) macOS", forHTTPHeaderField: "User-Agent")

        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "apikey")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "NexusService", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve collection download link (HTTP \(code))."])
        }

        return try JSONDecoder().decode([NexusDownloadURL].self, from: data)
    }
}
