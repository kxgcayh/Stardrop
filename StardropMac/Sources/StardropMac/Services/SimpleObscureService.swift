import Foundation
import CommonCrypto

public struct PairedKeys: Codable {
    public var lock: String?
    public var vector: String?

    enum CodingKeys: String, CodingKey {
        case lock = "Lock"
        case vector = "Vector"
    }

    public init(lock: String? = nil, vector: String? = nil) {
        self.lock = lock
        self.vector = vector
    }
}

public final class SimpleObscureService {
    public static let shared = SimpleObscureService()

    private let pathing = PathingService.shared

    public var notionURL: URL {
        pathing.cacheURL.appendingPathComponent("Notion.json")
    }

    /// Attempts to decrypt the stored key using Notion.json (Lock & Vector).
    /// If Notion.json does not exist or decryption fails, returns rawKey if it appears to be a plaintext key.
    public func getDecryptedKey(rawKey: String?) -> String? {
        guard let rawKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines), !rawKey.isEmpty else {
            return nil
        }

        guard let notionData = try? Data(contentsOf: notionURL),
              let pairedKeys = try? JSONDecoder().decode(PairedKeys.self, from: notionData),
              let lockB64 = pairedKeys.lock,
              let vectorB64 = pairedKeys.vector,
              let keyData = Data(base64Encoded: lockB64),
              let ivData = Data(base64Encoded: vectorB64),
              let cipherData = Data(base64Encoded: rawKey) else {
            return rawKey
        }

        var outBytes = [UInt8](repeating: 0, count: cipherData.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0

        let status = cipherData.withUnsafeBytes { cipherRaw in
            keyData.withUnsafeBytes { keyRaw in
                ivData.withUnsafeBytes { ivRaw in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyRaw.baseAddress,
                        keyData.count,
                        ivRaw.baseAddress,
                        cipherRaw.baseAddress,
                        cipherData.count,
                        &outBytes,
                        outBytes.count,
                        &numBytesDecrypted
                    )
                }
            }
        }

        if status == kCCSuccess {
            let decryptedData = Data(bytes: outBytes, count: numBytesDecrypted)
            if let plain = String(data: decryptedData, encoding: .utf8), !plain.isEmpty {
                return plain
            }
        }

        return rawKey
    }

    /// Encrypts a plaintext key, saves the paired keys to Notion.json, and returns the encrypted base64 string
    /// to be stored in Settings.json (matching C# Stardrop behavior).
    public func encryptAndSaveKey(_ plainKey: String) -> String? {
        let trimmed = plainKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let plainData = trimmed.data(using: .utf8) else {
            return nil
        }

        // Generate 32 bytes AES-256 key and 16 bytes IV
        var keyBytes = [UInt8](repeating: 0, count: kCCKeySizeAES256)
        var ivBytes = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        guard SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes) == errSecSuccess,
              SecRandomCopyBytes(kSecRandomDefault, ivBytes.count, &ivBytes) == errSecSuccess else {
            return nil
        }

        let keyData = Data(keyBytes)
        let ivData = Data(ivBytes)

        var outBytes = [UInt8](repeating: 0, count: plainData.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0

        let status = plainData.withUnsafeBytes { plainRaw in
            keyData.withUnsafeBytes { keyRaw in
                ivData.withUnsafeBytes { ivRaw in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyRaw.baseAddress,
                        keyData.count,
                        ivRaw.baseAddress,
                        plainRaw.baseAddress,
                        plainData.count,
                        &outBytes,
                        outBytes.count,
                        &numBytesEncrypted
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }

        let cipherData = Data(bytes: outBytes, count: numBytesEncrypted)
        let cipherB64 = cipherData.base64EncodedString()

        // Write Notion.json
        let paired = PairedKeys(lock: keyData.base64EncodedString(), vector: ivData.base64EncodedString())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(paired) {
            try? FileManager.default.createDirectory(at: pathing.cacheURL, withIntermediateDirectories: true)
            try? encoded.write(to: notionURL, options: .atomic)
        }

        return cipherB64
    }

    /// Clears Notion.json when disconnecting account
    public func clearNotionCache() {
        let empty = PairedKeys()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(empty) {
            try? encoded.write(to: notionURL, options: .atomic)
        }
    }
}
