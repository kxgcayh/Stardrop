import SwiftUI

public struct ModTableView: View {
    @ObservedObject var state: AppState

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar: Column Headers & Expand/Collapse All
            topHeaderBar

            Divider()

            if state.filteredMods.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.groupedMods) { group in
                            groupSection(group: group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 0) {
            // Expand/Collapse All Quick Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if state.areAllGroupsExpanded {
                        state.collapseAllGroups()
                    } else {
                        state.expandAllGroups()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.areAllGroupsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.bold())
                    Text(state.areAllGroupsExpanded ? "Collapse All" : "Expand All")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)

            Spacer()

            // Column Alignment Labels
            HStack(spacing: 0) {
                Text("Enabled")
                    .frame(width: 60, alignment: .center)

                Text("Mod Name")
                    .frame(minWidth: 180, alignment: .leading)
                    .padding(.leading, 8)

                Spacer()

                Text("Version")
                    .frame(width: 110, alignment: .leading)

                Text("Status")
                    .frame(width: 75, alignment: .center)

                Text("Actions")
                    .frame(width: 70, alignment: .center)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.trailing, 16)
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Group Section

    private func groupSection(group: ModGroup) -> some View {
        let isExpanded = state.expandedGroups.contains(group.name)

        return VStack(spacing: 0) {
            // Group Header Bar
            HStack(spacing: 8) {
                // Chevron & Title Click Area
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.toggleGroupExpansion(group.name)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)

                        Image(systemName: group.name == "Standalone Mods" ? "shippingbox" : "folder.fill")
                            .foregroundStyle(group.name == "Standalone Mods" ? Color.secondary : Color.blue)
                            .font(.system(size: 13))

                        Text(group.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        // Count badge
                        Text("\(group.enabledCount)/\(group.totalCount) enabled")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(group.enabledCount > 0 ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(group.enabledCount > 0 ? Color.green : Color.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Batch Enable / Disable Button for this entire group
                Button {
                    state.toggleAllModsInGroup(group)
                } label: {
                    Text(group.allEnabled ? "Disable All" : "Enable All")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(group.allEnabled ? "Disable all mods in \(group.name)" : "Enable all mods in \(group.name)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
            )

            // Expanded Mods List
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(group.mods) { mod in
                        modRow(mod: mod)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Mod Row

    private func modRow(mod: Mod) -> some View {
        let isSelected = state.selectedModId == mod.id

        return HStack(spacing: 0) {
            // Column 1: Centered Checkbox
            HStack {
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { mod.isEnabled },
                    set: { _ in state.toggleMod(mod) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                Spacer(minLength: 0)
            }
            .frame(width: 60)

            // Column 2: Name & Author
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(mod.isEnabled ? .primary : .secondary)
                    .lineLimit(1)

                Text(mod.author)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, alignment: .leading)
            .padding(.leading, 8)

            Spacer()

            // Column 3: Version & Update Badge
            HStack(spacing: 6) {
                Text(mod.version)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                if mod.hasUpdate {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text(mod.suggestedVersion ?? "Update")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.orange))
                    .foregroundStyle(.white)
                }
            }
            .frame(width: 110, alignment: .leading)

            // Column 4: Status Indicator
            Group {
                if mod.isEnabled {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                } else {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 75, alignment: .center)

            // Column 5: Action Buttons
            HStack(spacing: 6) {
                if mod.hasConfig {
                    Button {
                        state.editingMod = mod
                        state.isConfigEditorPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit config.json")
                }

                Button {
                    state.revealInFinder(mod.directoryURL)
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            .frame(width: 70, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedModId = mod.id
        }
        .contextMenu {
            Button(mod.isEnabled ? "Disable Mod" : "Enable Mod") {
                state.toggleMod(mod)
            }
            Divider()
            if mod.hasConfig {
                Button("Edit config.json") {
                    state.editingMod = mod
                    state.isConfigEditorPresented = true
                }
            }
            Button("Reveal in Finder") {
                state.revealInFinder(mod.directoryURL)
            }
            if let nexusURL = mod.nexusURL {
                Button("Open on Nexus Mods") {
                    NSWorkspace.shared.open(nexusURL)
                }
            }
            Divider()
            Button("Copy Unique ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mod.id, forType: .string)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(state.searchText.isEmpty ? "No mods found in this category" : "No mods matching \"\(state.searchText)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
            if state.totalCount == 0 {
                Text("Mods folder: \(state.modsDirectory.path)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
