import Foundation

public final class ProfileService {
    public static let shared = ProfileService()

    private let pathing = PathingService.shared
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public func loadProfiles() -> [Profile] {
        pathing.ensureDirectoriesExist()

        let folder = pathing.profilesURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [defaultProfile()]
        }

        var profiles: [Profile] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: file),
               let profile = try? jsonDecoder.decode(Profile.self, from: data) {
                profiles.append(profile)
            }
        }

        if profiles.isEmpty {
            let def = defaultProfile()
            saveProfile(def)
            profiles.append(def)
        }

        return profiles.sorted { a, b in
            if a.name.caseInsensitiveCompare("Default") == .orderedSame { return true }
            if b.name.caseInsensitiveCompare("Default") == .orderedSame { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public func defaultProfile() -> Profile {
        Profile(name: "Default", isProtected: true, enabledModIds: [])
    }

    private func safeFilename(for name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
    }

    public func saveProfile(_ profile: Profile) {
        pathing.ensureDirectoriesExist()

        let safe = safeFilename(for: profile.name)
        let fileURL = pathing.profilesURL.appendingPathComponent("\(safe).json")
        do {
            let data = try jsonEncoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save profile \(profile.name): \(error)")
        }
    }

    public func deleteProfile(_ profile: Profile) {
        guard !profile.isProtected else { return }
        let safe = safeFilename(for: profile.name)
        let fileURL = pathing.profilesURL.appendingPathComponent("\(safe).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func duplicateProfile(_ profile: Profile, newName: String) -> Profile {
        let copy = Profile(
            name: newName,
            isProtected: false,
            sourceId: nil,
            enabledModIds: profile.enabledModIds
        )
        saveProfile(copy)
        return copy
    }

    public func renameProfile(_ profile: Profile, newName: String) -> Profile {
        guard !profile.isProtected else { return profile }
        deleteProfile(profile)
        var renamed = profile
        renamed.name = newName
        saveProfile(renamed)
        return renamed
    }
}
