import Foundation
import Combine

public final class SMAPILauncherService: ObservableObject {
    public static let shared = SMAPILauncherService()

    @Published public private(set) var isRunning: Bool = false
    @Published public var launchError: String?

    private var activeProcess: Process?

    public func launch(
        mods: [Mod],
        gameDirectory: URL,
        smapiExecutable: URL?
    ) {
        guard !isRunning else { return }

        let pathing = PathingService.shared
        pathing.ensureDirectoriesExist()

        let selectedModsURL = pathing.selectedModsURL
        let fileManager = FileManager.default

        // 1. Clear previous symlinks in Selected Mods
        if let existing = try? fileManager.contentsOfDirectory(at: selectedModsURL, includingPropertiesForKeys: nil) {
            for item in existing {
                try? fileManager.removeItem(at: item)
            }
        }

        // 2. Link enabled mods into Selected Mods
        let enabledMods = mods.filter { $0.isEnabled }
        var usedNames = Set<String>()

        for mod in enabledMods {
            var folderName = mod.directoryURL.lastPathComponent
            if usedNames.contains(folderName.lowercased()) {
                folderName = "\(folderName)_\(mod.id)"
            }
            usedNames.insert(folderName.lowercased())

            let destination = selectedModsURL.appendingPathComponent(folderName)
            try? fileManager.createSymbolicLink(at: destination, withDestinationURL: mod.directoryURL)
        }

        // 3. Resolve executable
        guard let executable = smapiExecutable ?? pathing.resolveSmapiExecutable(gameDirectory: gameDirectory) else {
            DispatchQueue.main.async {
                self.launchError = "Could not locate StardewModdingAPI executable at \(gameDirectory.path)"
            }
            return
        }

        // 4. Launch process
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = gameDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["SMAPI_MODS_PATH"] = selectedModsURL.path
        process.environment = environment

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.activeProcess = nil
            }
        }

        do {
            try process.run()
            DispatchQueue.main.async {
                self.activeProcess = process
                self.isRunning = true
                self.launchError = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.launchError = "Failed to start SMAPI: \(error.localizedDescription)"
                self.isRunning = false
            }
        }
    }

    public func stop() {
        activeProcess?.terminate()
    }
}
