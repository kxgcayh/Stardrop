import Foundation

public final class PathingService {
    public static let shared = PathingService()

    public var homeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Stardrop/Data", isDirectory: true)
    }

    public var profilesURL: URL {
        homeURL.appendingPathComponent("Profiles", isDirectory: true)
    }

    public var selectedModsURL: URL {
        homeURL.appendingPathComponent("Selected Mods", isDirectory: true)
    }

    public var settingsURL: URL {
        homeURL.appendingPathComponent("Settings.json")
    }

    public var logsURL: URL {
        homeURL.appendingPathComponent("Logs", isDirectory: true)
    }

    public var separatorsURL: URL {
        homeURL.appendingPathComponent("Separators", isDirectory: true)
    }

    public var cacheURL: URL {
        homeURL.appendingPathComponent("Cache", isDirectory: true)
    }

    public var collectionDownloadsURL: URL {
        cacheURL.appendingPathComponent("CollectionDownloads", isDirectory: true)
    }

    public var collectionsURL: URL {
        homeURL.appendingPathComponent("Collections", isDirectory: true)
    }

    public var smapiLogURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/StardewValley/ErrorLogs/SMAPI-latest.txt")
    }

    public var defaultSteamGameURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Steam/steamapps/common/Stardew Valley/Contents/MacOS", isDirectory: true)
    }

    public var defaultSteamModsURL: URL {
        defaultSteamGameURL.appendingPathComponent("Mods", isDirectory: true)
    }

    public var defaultSteamSmapiExecutableURL: URL {
        defaultSteamGameURL.appendingPathComponent("StardewModdingAPI")
    }

    public func resolveGameDirectory(configuredPath: String?) -> URL {
        if let configured = configuredPath, !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return defaultSteamGameURL
    }

    public func resolveModsDirectory(configuredPath: String?, gameDirectory: URL) -> URL {
        if let configured = configuredPath, !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let insideGame = gameDirectory.appendingPathComponent("Mods", isDirectory: true)
        if FileManager.default.fileExists(atPath: insideGame.path) {
            return insideGame
        }
        return defaultSteamModsURL
    }

    public func resolveSmapiExecutable(gameDirectory: URL) -> URL? {
        let candidate1 = gameDirectory.appendingPathComponent("StardewModdingAPI")
        if FileManager.default.isExecutableFile(atPath: candidate1.path) {
            return candidate1
        }
        let candidate2 = defaultSteamSmapiExecutableURL
        if FileManager.default.isExecutableFile(atPath: candidate2.path) {
            return candidate2
        }
        return nil
    }

    public func ensureDirectoriesExist() {
        let dirs = [homeURL, profilesURL, selectedModsURL, logsURL, separatorsURL, cacheURL]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
