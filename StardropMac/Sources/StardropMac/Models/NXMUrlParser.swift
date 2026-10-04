import Foundation

public enum NXMType: Equatable {
    case mod(gameId: String, modId: Int, fileId: Int, key: String?, expires: Int?, userId: Int?)
    case collection(gameId: String, slug: String, revisionNumber: Int?)
    case unknown(String)
}

public struct NXMUrlParser {
    public static func parse(_ url: URL) -> NXMType {
        guard url.scheme?.caseInsensitiveCompare("nxm") == .orderedSame else {
            return .unknown(url.absoluteString)
        }

        let host = url.host ?? ""
        let path = url.path
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        let key = queryItems.first(where: { $0.name == "key" })?.value
        let expiresStr = queryItems.first(where: { $0.name == "expires" })?.value
        let expires = expiresStr != nil ? Int(expiresStr!) : nil
        let userIdStr = queryItems.first(where: { $0.name == "user_id" })?.value
        let userId = userIdStr != nil ? Int(userIdStr!) : nil

        // Pattern 1: /mods/{modId}/files/{fileId}
        let modPattern = #"^/mods/(\d+)/files/(\d+)"#
        if let match = path.range(of: modPattern, options: .regularExpression) {
            let matchedStr = String(path[match])
            let parts = matchedStr.split(separator: "/")
            if parts.count >= 4,
               let modId = Int(parts[1]),
               let fileId = Int(parts[3]) {
                return .mod(
                    gameId: host,
                    modId: modId,
                    fileId: fileId,
                    key: key,
                    expires: expires,
                    userId: userId
                )
            }
        }

        // Pattern 2: /collections/{slug}/revisions/{revisionNumber|latest}
        let collPattern = #"^/collections/([^/]+)/revisions/([^/]+)"#
        if let match = path.range(of: collPattern, options: .regularExpression) {
            let matchedStr = String(path[match])
            let parts = matchedStr.split(separator: "/")
            if parts.count >= 4 {
                let slug = String(parts[1])
                let revStr = String(parts[3])
                let revNum = revStr.caseInsensitiveCompare("latest") == .orderedSame ? nil : Int(revStr)
                return .collection(
                    gameId: host,
                    slug: slug,
                    revisionNumber: revNum
                )
            }
        }

        return .unknown(url.absoluteString)
    }
}
