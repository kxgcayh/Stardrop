import SwiftUI

public struct FreeUserQueueSheet: View {
    @ObservedObject var state: AppState
    @ObservedObject var manager: CollectionQueueManager
    @Environment(\.dismiss) private var dismiss

    public init(state: AppState, manager: CollectionQueueManager) {
        self.state = state
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download Assistant")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Step-by-step download queue for \(manager.collectionName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close") {
                    finishAndDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(spacing: 16) {
                // Active Mod Card
                if let current = manager.currentItem {
                    activeModCard(current)
                } else if manager.isFinished {
                    allCompletedCard
                }

                // Controls and Auto-open
                HStack {
                    Toggle("Automatically open next mod in browser", isOn: $manager.autoOpenNext)
                        .font(.subheadline)

                    Spacer()

                    Text("Completed: \(manager.completedCount) / \(manager.items.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)

                // Mod List
                GroupBox(label: Text("Queue Status").fontWeight(.medium)) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(manager.items.enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, alignment: .leading)

                                    Text(item.mod.name)
                                        .font(.subheadline)
                                        .fontWeight(item.id == manager.currentItem?.id ? .semibold : .regular)

                                    Text("v\(item.mod.version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    statusBadge(for: item.status)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    item.id == manager.currentItem?.id
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear
                                )
                                .cornerRadius(6)

                                if index < manager.items.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Text(manager.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(manager.isFinished ? "Apply and Finish" : "Finish Early") {
                    finishAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.regularMaterial)
        }
        .frame(width: 600, height: 520)
    }

    // MARK: - Subviews

    private func activeModCard(_ item: CollectionQueueItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.mod.name)
                            .font(.headline)
                        Text("Version \(item.mod.version) - \(item.mod.optional ? "Optional" : "Required")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    statusBadge(for: item.status)
                }

                Divider()

                switch item.status {
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                        Text("Downloading (\(Int(progress * 100))%)...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .awaitingBrowser:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for 'Slow Download' click in browser...")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Skip") {
                            manager.skip(item: item)
                        }

                        Button("Reopen Page") {
                            manager.openInBrowser(item: item)
                        }
                    }

                default:
                    HStack {
                        Button("Download on Nexus Mods") {
                            manager.openInBrowser(item: item)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Skip This Mod") {
                            manager.skip(item: item)
                        }

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var allCompletedCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("All Downloads Completed")
                    .font(.headline)
                Text("All available mods have been downloaded and installed into your Stardrop library.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func statusBadge(for status: QueueItemStatus) -> some View {
        Text(status.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBackground(for: status))
            .foregroundColor(badgeForeground(for: status))
            .cornerRadius(4)
    }

    private func badgeBackground(for status: QueueItemStatus) -> Color {
        switch status {
        case .installed:
            return Color.green.opacity(0.15)
        case .downloading:
            return Color.blue.opacity(0.15)
        case .awaitingBrowser:
            return Color.orange.opacity(0.15)
        case .failed:
            return Color.red.opacity(0.15)
        case .skipped:
            return Color.secondary.opacity(0.15)
        default:
            return Color.secondary.opacity(0.1)
        }
    }

    private func badgeForeground(for status: QueueItemStatus) -> Color {
        switch status {
        case .installed:
            return Color.green
        case .downloading:
            return Color.blue
        case .awaitingBrowser:
            return Color.orange
        case .failed:
            return Color.red
        default:
            return Color.primary
        }
    }

    private func finishAndDismiss() {
        state.applyCompletedQueue(manager: manager)
        dismiss()
    }
}
