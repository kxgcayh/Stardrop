import Foundation

public final class CollectionPersistenceService {
    public static let shared = CollectionPersistenceService()

    private let pathing = PathingService.shared
    private let fileManager = FileManager.default

    private var storageFileURL: URL {
        pathing.collectionsURL.appendingPathComponent("installed_collections.json")
    }

    public func loadCollections() -> [InstalledCollection] {
        let url = storageFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([InstalledCollection].self, from: data)
        } catch {
            print("Failed to decode installed collections: \(error)")
            return []
        }
    }

    public func saveCollections(_ collections: [InstalledCollection]) {
        do {
            try fileManager.createDirectory(at: pathing.collectionsURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(collections)
            try data.write(to: storageFileURL, options: .atomic)
        } catch {
            print("Failed to save installed collections: \(error)")
        }
    }

    public func addOrUpdateCollection(_ collection: InstalledCollection) {
        var existing = loadCollections()
        if let index = existing.firstIndex(where: { $0.id == collection.id }) {
            existing[index] = collection
        } else {
            existing.append(collection)
        }
        saveCollections(existing)
    }

    public func removeCollection(id: String) {
        var existing = loadCollections()
        existing.removeAll(where: { $0.id == id })
        saveCollections(existing)
    }

    public func getCollection(slug: String, domainName: String = "stardewvalley") -> InstalledCollection? {
        let targetId = "\(domainName)-\(slug)"
        return loadCollections().first(where: { $0.id.caseInsensitiveCompare(targetId) == .orderedSame })
    }
}
