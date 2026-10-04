import Foundation
import AppKit

public enum QueueItemStatus: Equatable {
    case pending
    case ready
    case awaitingBrowser
    case downloading(Double)
    case installed
    case skipped
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .installed, .skipped:
            return true
        default:
            return false
        }
    }

    public var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .ready:
            return "Ready"
        case .awaitingBrowser:
            return "Awaiting Browser"
        case .downloading(let p):
            return "Downloading (\(Int(p * 100))%)"
        case .installed:
            return "Installed"
        case .skipped:
            return "Skipped"
        case .failed(let err):
            return "Failed: \(err)"
        }
    }
}

public final class CollectionQueueItem: ObservableObject, Identifiable {
    public let id = UUID()
    public let mod: CollectionMod
    @Published public var status: QueueItemStatus

    public init(mod: CollectionMod, status: QueueItemStatus = .pending) {
        self.mod = mod
        self.status = status
    }
}

@MainActor
public final class CollectionQueueManager: ObservableObject {
    @Published public var items: [CollectionQueueItem] = []
    @Published public var currentIndex: Int = 0
    @Published public var isRunning: Bool = false
    @Published public var isFinished: Bool = false
    @Published public var autoOpenNext: Bool = true
    @Published public var statusMessage: String = "Ready to start download queue"

    public let targetProfileName: String
    public let separatorName: String
    public let collectionName: String
    public var onFinished: (() -> Void)?

    public var currentItem: CollectionQueueItem? {
        guard !isFinished else { return nil }
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        let item = items[currentIndex]
        guard !item.status.isTerminal else { return nil }
        return item
    }

    public var completedCount: Int {
        items.filter { $0.status == .installed }.count
    }

    public var skippedCount: Int {
        items.filter { $0.status == .skipped }.count
    }

    public var remainingCount: Int {
        items.filter { !$0.status.isTerminal }.count
    }

    public init(
        mods: [CollectionMod],
        targetProfileName: String,
        separatorName: String,
        collectionName: String,
        existingMods: [Mod] = [],
        currentSMAPIVersion: String? = nil
    ) {
        self.targetProfileName = targetProfileName
        self.separatorName = separatorName
        self.collectionName = collectionName
        self.items = mods.map { mod in
            if mod.isInstalled(in: existingMods, currentSMAPIVersion: currentSMAPIVersion) {
                return CollectionQueueItem(mod: mod, status: .installed)
            } else {
                return CollectionQueueItem(mod: mod, status: .pending)
            }
        }
        advanceToNextPending()
    }

    public func startQueue() {
        guard !isFinished else { return }
        isRunning = true
        if let current = currentItem {
            openInBrowser(item: current)
        }
    }

    public func openInBrowser(item: CollectionQueueItem) {
        guard !item.status.isTerminal else { return }
        guard let modId = item.mod.source.modId, let fileId = item.mod.source.fileId else {
            item.status = .skipped
            advanceToNextPending()
            return
        }

        let domain = item.mod.domainName ?? "stardewvalley"
        let urlString = "https://www.nexusmods.com/\(domain)/mods/\(modId)?tab=files&file_id=\(fileId)&nmm=1"

        if let url = URL(string: urlString) {
            item.status = .awaitingBrowser
            statusMessage = "Opened \(item.mod.name) in browser. Click 'Slow Download' on Nexus Mods."
            NSWorkspace.shared.open(url)
        }
    }

    public func skip(item: CollectionQueueItem) {
        item.status = .skipped
        advanceToNextPending()
        if autoOpenNext, isRunning, let next = currentItem {
            openInBrowser(item: next)
        }
    }

    public func advanceToNextPending() {
        if let nextIdx = items.firstIndex(where: { !$0.status.isTerminal }) {
            currentIndex = nextIdx
            if items[nextIdx].status == .pending {
                items[nextIdx].status = .ready
            }
            isFinished = false
        } else {
            currentIndex = -1
            isFinished = true
            isRunning = false
            statusMessage = "All items in queue processed."
            onFinished?()
        }
    }

    public func handleIncomingNXM(
        gameId: String,
        modId: Int,
        fileId: Int,
        key: String?,
        expires: Int?,
        apiKey: String?,
        modsDirectory: URL,
        existingMods: [Mod]
    ) async -> Bool {
        // Find matching item in queue: exact modId + fileId, or fallback to modId
        guard let item = items.first(where: {
            $0.mod.source.modId == modId && $0.mod.source.fileId == fileId && !$0.status.isTerminal
        }) ?? items.first(where: {
            $0.mod.source.modId == modId && !$0.status.isTerminal
        }) else {
            return false
        }

        if case .downloading = item.status {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)

        item.status = .downloading(0.0)
        statusMessage = "Downloading \(item.mod.name)..."

        let cacheDir = PathingService.shared.collectionDownloadsURL
        let cacheFile = cacheDir.appendingPathComponent("\(modId)_\(fileId).zip")

        do {
            let keyToUse = (apiKey != nil && !apiKey!.isEmpty) ? apiKey! : (key ?? "")

            let links = try await NexusService.shared.getModDownloadURLs(
                gameDomain: item.mod.domainName ?? gameId,
                modId: modId,
                fileId: fileId,
                apiKey: keyToUse,
                key: key,
                expires: expires
            )

            guard let primary = links.first?.uri, let downloadURL = URL(string: primary) else {
                throw NSError(domain: "CollectionQueue", code: 404, userInfo: [NSLocalizedDescriptionKey: "No download mirrors returned."])
            }

            try await NexusService.shared.downloadFile(from: downloadURL, to: cacheFile) { progress in
                Task { @MainActor in
                    item.status = .downloading(progress)
                }
            }

            statusMessage = "Installing \(item.mod.name)..."
            _ = try await ModInstallerService.shared.installMods(from: [cacheFile], into: modsDirectory, existingMods: existingMods)

            item.status = .installed
            statusMessage = "Installed \(item.mod.name)."

            advanceToNextPending()

            if autoOpenNext, isRunning, let next = currentItem {
                openInBrowser(item: next)
            }

            return true
        } catch {
            item.status = .failed(error.localizedDescription)
            statusMessage = "Failed \(item.mod.name): \(error.localizedDescription)"
            return false
        }
    }
}
