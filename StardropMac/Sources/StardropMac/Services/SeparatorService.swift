import Foundation

public final class SeparatorService {
    public static let shared = SeparatorService()

    private let pathing = PathingService.shared
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public func fileURL(for profileName: String) -> URL {
        pathing.ensureDirectoriesExist()
        return pathing.separatorsURL.appendingPathComponent("\(profileName).json")
    }

    public func loadSeparators(for profileName: String) -> [ModSeparator] {
        pathing.ensureDirectoriesExist()
        let url = fileURL(for: profileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let separators = try? jsonDecoder.decode([ModSeparator].self, from: data) else {
            return []
        }
        return separators
    }

    public func saveSeparators(_ separators: [ModSeparator], for profileName: String) {
        pathing.ensureDirectoriesExist()
        let url = fileURL(for: profileName)
        do {
            let data = try jsonEncoder.encode(separators)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save separators for \(profileName): \(error)")
        }
    }

    public func deleteSeparators(for profileName: String) {
        let url = fileURL(for: profileName)
        try? FileManager.default.removeItem(at: url)
    }

    public func duplicateSeparators(from sourceProfile: String, to targetProfile: String) {
        let separators = loadSeparators(for: sourceProfile)
        saveSeparators(separators, for: targetProfile)
    }
}
