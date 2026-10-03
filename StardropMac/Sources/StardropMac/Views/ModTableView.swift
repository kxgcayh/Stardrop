import SwiftUI

public struct ModTableView: View {
    @ObservedObject var state: AppState

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar: Column Headers
            topHeaderBar

            Divider()

            if state.filteredMods.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(state.filteredMods) { mod in
                                modRow(mod: mod)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: state.scrollTargetModId) { _, targetId in
                        guard let id = targetId else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 0) {
            // State column header
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .center)

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
        .padding(.horizontal, 24)
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Mod Row

    private func modRow(mod: Mod) -> some View {
        let isSelected = state.selectedModId == mod.id

        return HStack(spacing: 0) {
            // Column 1: Status Icon
            HStack {
                Spacer(minLength: 0)
                Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(mod.isEnabled ? Color.green : Color.secondary.opacity(0.45))
                Spacer(minLength: 0)
            }
            .frame(width: 40)

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
        .id(mod.id)
        .contextMenu {
            Button(mod.isEnabled ? "Disable Mod" : "Enable Mod") {
                state.toggleMod(mod)
            }
            Divider()
            Button("Enable All Mods") {
                state.enableAllMods()
            }
            Button("Disable All Mods") {
                state.disableAllMods()
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
