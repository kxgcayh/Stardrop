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
                                set: { newValue in state.setModEnabled(mod, isEnabled: newValue) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(mod.isCoreSMAPI)
                            .help(mod.isCoreSMAPI ? "Core SMAPI components are required and cannot be disabled" : (mod.isEnabled ? "Disable mod" : "Enable mod"))
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
                        if mod.isCoreSMAPI {
                            HStack {
                                Text("Type")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text("Core SMAPI Component")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }
                        }

                        infoRow(label: "Version", value: mod.version)
                        infoRow(label: "Unique ID", value: mod.id)

                        if mod.hasUpdate {
                            HStack {
                                Text("New Version")
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

                    if mod.hasUpdate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Update Available")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                    Text("v\(mod.version) → v\(mod.suggestedVersion ?? "")")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }

                            if let updateURL = mod.updateURL ?? mod.nexusURL {
                                Button {
                                    NSWorkspace.shared.open(updateURL)
                                } label: {
                                    Label("Download Update", systemImage: "arrow.down.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.regular)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }

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
                    let deps = mod.manifest.allDependencies
                    if !deps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dependencies (\(deps.count))")
                                .font(.headline)

                            VStack(spacing: 6) {
                                ForEach(deps) { dep in
                                    let isDepInstalled = isInstalled(dependencyId: dep.uniqueID)
                                    let matchedMod = installedMod(for: dep.uniqueID)

                                    HStack(spacing: 8) {
                                        // Checked and green when required and installed
                                        if dep.isRequired {
                                            if isDepInstalled {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.green)
                                                    .font(.caption)
                                            } else {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(Color.red)
                                                    .font(.caption)
                                            }
                                        } else {
                                            if isDepInstalled {
                                                Image(systemName: "checkmark.circle")
                                                    .foregroundStyle(Color.secondary)
                                                    .font(.caption)
                                            } else {
                                                Image(systemName: "info.circle")
                                                    .foregroundStyle(Color.secondary)
                                                    .font(.caption)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            if let matched = matchedMod, matched.name != dep.uniqueID {
                                                Text(matched.name)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                Text(dep.uniqueID)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            } else {
                                                Text(dep.uniqueID)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        if let minVer = dep.minimumVersion {
                                            Text("≥ \(minVer)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        if !dep.isRequired {
                                            Text("Optional")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
                                        } else if !isDepInstalled {
                                            Text("Missing")
                                                .font(.caption2.bold())
                                                .foregroundStyle(Color.red)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.15)))
                                        } else {
                                            Text("Installed")
                                                .font(.caption2)
                                                .foregroundStyle(Color.green)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.15)))
                                        }
                                        if matchedMod != nil {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let matched = matchedMod {
                                            state.selectAndRevealMod(id: matched.id)
                                        }
                                    }
                                    .help(matchedMod != nil ? "Installed: \(matchedMod!.name). Click to expand, select, and scroll to this mod." : (isDepInstalled ? "Installed" : "Required dependency is missing!"))
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

    private func isInstalled(dependencyId: String) -> Bool {
        if dependencyId.caseInsensitiveCompare("Pathoschild.SMAPI") == .orderedSame || 
           dependencyId.caseInsensitiveCompare("SMAPI") == .orderedSame {
            return state.settings.gameDetails?.smapiVersion != nil || 
                   PathingService.shared.resolveSmapiExecutable(gameDirectory: state.gameDirectory) != nil
        }
        return state.mods.contains { $0.id.caseInsensitiveCompare(dependencyId) == .orderedSame }
    }

    private func installedMod(for dependencyId: String) -> Mod? {
        state.mods.first { $0.id.caseInsensitiveCompare(dependencyId) == .orderedSame }
    }
}
