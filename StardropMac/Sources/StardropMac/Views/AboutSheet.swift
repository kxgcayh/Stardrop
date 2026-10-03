import SwiftUI
import AppKit

public struct AboutSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.10.4"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var systemArch: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Universal"
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with Icon and App Details
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

                VStack(spacing: 4) {
                    Text("Stardrop")
                        .font(.system(size: 22, weight: .bold))

                    Text("Native Mod Manager for Stardew Valley")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(systemArch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Description
                    Text("Stardrop for macOS is a fast, native mod manager engineered with Swift and SwiftUI specifically for modern macOS. It provides zero-latency profile management, mod group discovery, in-app configuration, live SMAPI launching, and official Nexus Mods API integration.")
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    // Links Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Links & Resources")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            LinkButton(title: "GitHub Repository", icon: "link", urlString: "https://github.com/Floogen/Stardrop")
                            LinkButton(title: "Documentation", icon: "book", urlString: "https://floogen.gitbook.io/stardrop/")
                            LinkButton(title: "SMAPI.io", icon: "bolt.fill", urlString: "https://smapi.io/")
                        }

                        HStack(spacing: 10) {
                            LinkButton(title: "Nexus Mods", icon: "globe.americas.fill", urlString: "https://www.nexusmods.com/stardewvalley")
                            LinkButton(title: "Report an Issue", icon: "exclamationmark.bubble", urlString: "https://github.com/Floogen/Stardrop/issues")
                        }
                    }

                    Divider()

                    // System / Environment Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Environment")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("macOS Version:")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(ProcessInfo.processInfo.operatingSystemVersionString)
                                    .font(.caption)
                            }

                            if let details = state.settings.gameDetails {
                                GridRow {
                                    Text("Stardew Valley:")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text(details.gameVersion)
                                        .font(.caption)
                                }
                                GridRow {
                                    Text("SMAPI Version:")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text(details.smapiVersion)
                                        .font(.caption)
                                }
                            }

                            GridRow {
                                Text("Game Directory:")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(state.gameDirectory.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            GridRow {
                                Text("Mods Directory:")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(state.modsDirectory.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    Divider()

                    // Attribution & License
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Attribution & License")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Text("• Stardrop was originally created by Floogen and the open-source community.\n• Stardew Valley is created by ConcernedApe.\n• SMAPI is created and maintained by Pathoschild.\n• Released under the GNU General Public License v3.0 (GPL-3.0).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("View GPL-3.0 License on GitHub") {
                            if let url = URL(string: "https://github.com/Floogen/Stardrop/blob/master/LICENSE") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                        .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 340)

            Divider()

            // Footer
            HStack {
                Text("Copyright © 2026 Floogen & Contributors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.3))
        }
        .frame(width: 500, height: 550)
    }
}

private struct LinkButton: View {
    let title: String
    let icon: String
    let urlString: String

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
    }
}
