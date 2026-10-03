import SwiftUI

public struct InspectorView: View {
    @ObservedObject var state: AppState

    public var body: some View {
        if let mod = state.selectedMod {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "shippingbox.fill")
                                .font(.title)
                                .foregroundStyle(.blue)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { mod.isEnabled },
                                set: { _ in state.toggleMod(mod) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }

                        Text(mod.name)
                            .font(.title2.bold())

                        Text("by \(mod.author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Quick Info Grid
                    VStack(alignment: .leading, spacing: 10) {
                        infoRow(label: "Version", value: mod.version)
                        infoRow(label: "Unique ID", value: mod.id)

                        if let group = mod.groupName {
                            infoRow(label: "Group", value: group)
                        }

                        if mod.hasUpdate {
                            HStack {
                                Text("Update")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(mod.suggestedVersion ?? "Available")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.headline)
                        Text(mod.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    // Dependencies
                    if !mod.manifest.dependencies.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dependencies (\(mod.manifest.dependencies.count))")
                                .font(.headline)

                            VStack(spacing: 6) {
                                ForEach(mod.manifest.dependencies) { dep in
                                    HStack {
                                        Image(systemName: dep.isRequired ? "exclamationmark.circle.fill" : "info.circle")
                                            .foregroundStyle(dep.isRequired ? .orange : .secondary)
                                            .font(.caption)
                                        Text(dep.uniqueID)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        if let minVer = dep.minimumVersion {
                                            Text("≥ \(minVer)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
                        }
                    }

                    // Configuration
                    if mod.hasConfig {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Configuration")
                                .font(.headline)

                            Button {
                                state.editingMod = mod
                                state.isConfigEditorPresented = true
                            } label: {
                                Label("Edit config.json", systemImage: "gearshape")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.regular)
                        }
                    }

                    // Links & Actions
                    VStack(spacing: 8) {
                        Button {
                            state.revealInFinder(mod.directoryURL)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.regular)

                        if let nexusURL = mod.nexusURL {
                            Button {
                                NSWorkspace.shared.open(nexusURL)
                            } label: {
                                Label("View on Nexus Mods", systemImage: "arrow.up.right.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.regular)
                        }
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Select a mod to inspect details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }
}
