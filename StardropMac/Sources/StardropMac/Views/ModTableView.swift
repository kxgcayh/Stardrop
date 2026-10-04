import SwiftUI

public struct ModTableView: View {
    @ObservedObject var state: AppState
    @State private var eventMonitor: Any? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar: Column Headers
            topHeaderBar

            Divider()

            if let message = state.updateCheckMessage, state.availableUpdatesCount > 0 {
                updateBanner(message: message)
            }

            if state.filteredMods.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            if state.separators.isEmpty {
                                ForEach(state.filteredMods) { mod in
                                    modRow(mod: mod)
                                }
                            } else {
                                // 1. Render Separators
                                ForEach(state.separators) { separator in
                                    let sepMods = separatorMods(for: separator)
                                    // If searching, only show separator if it has matching mods
                                    if state.searchText.isEmpty || !sepMods.isEmpty {
                                        separatorSection(separator: separator, mods: sepMods)
                                    }
                                }

                                // 2. Render Unassigned Mods
                                let unassigned = unassignedMods
                                if !unassigned.isEmpty {
                                    unassignedSection(mods: unassigned)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: state.scrollTargetModId) { _, targetId in
                        guard let id = targetId else { return }
                        if let sep = state.separator(forId: id), !sep.isExpanded {
                            state.toggleSeparatorExpansion(sep)
                        }
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
        .onAppear {
            setupEventMonitor()
        }
        .onDisappear {
            removeEventMonitor()
        }
    }

    // MARK: - Separator Helpers

    private func separatorMods(for separator: ModSeparator) -> [Mod] {
        let filteredMap = Dictionary(state.filteredMods.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return separator.modIds.compactMap { filteredMap[$0.lowercased()] }
    }

    private var unassignedMods: [Mod] {
        state.filteredMods.filter { state.separator(for: $0) == nil }
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
                .frame(width: 90, alignment: .leading)

            Text("Status")
                .frame(width: 75, alignment: .center)

            Text("Actions")
                .frame(width: 95, alignment: .center)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Update Notification Banner

    private func updateBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if state.selectedCategory != .updatableOnly {
                Button {
                    withAnimation {
                        state.selectedCategory = .updatableOnly
                    }
                } label: {
                    Label("View Updates (\(state.availableUpdatesCount))", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
            } else {
                Button {
                    withAnimation {
                        state.selectedCategory = .allMods
                    }
                } label: {
                    Label("Show All Mods", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                withAnimation {
                    state.updateCheckMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss notification")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Separator Section

    private func separatorSection(separator: ModSeparator, mods: [Mod]) -> some View {
        VStack(spacing: 2) {
            separatorHeaderRow(separator: separator, displayCount: mods.count)

            if separator.isExpanded {
                if mods.isEmpty {
                    HStack {
                        Text("No mods in this separator — right-click a mod to move it here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                            .padding(.vertical, 4)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                } else {
                    ForEach(mods) { mod in
                        modRow(mod: mod)
                            .padding(.leading, 8)
                    }
                }
            }
        }
    }

    private func separatorHeaderRow(separator: ModSeparator, displayCount: Int) -> some View {
        let allModsInSep = state.mods.filter { mod in
            separator.modIds.contains { $0.caseInsensitiveCompare(mod.id) == .orderedSame }
        }
        let totalCount = allModsInSep.count
        let enabledCount = allModsInSep.filter { $0.isEnabled }.count
        let isFirst = state.separators.first?.id == separator.id
        let isLast = state.separators.last?.id == separator.id

        return HStack(spacing: 8) {
            // Expand/Collapse Chevron
            Image(systemName: separator.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            // Separator Icon
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 12))
                .foregroundStyle(.blue)

            // Separator Title
            Text(separator.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)

            // Horizontal decorative divider
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)

            // Enabled/Total stats badge
            Text("\(enabledCount)/\(totalCount) enabled")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))

            // 3-dots Action Menu
            Menu {
                Button("Enable All in Separator") {
                    state.enableAllModsInSeparator(separator)
                }
                .disabled(totalCount == 0)

                Button("Disable All in Separator") {
                    state.disableAllModsInSeparator(separator)
                }
                .disabled(totalCount == 0)

                Divider()

                Button("Rename Separator...") {
                    state.separatorToRename = separator
                }

                Button("Move Up") {
                    state.moveSeparatorUp(separator)
                }
                .disabled(isFirst)

                Button("Move Down") {
                    state.moveSeparatorDown(separator)
                }
                .disabled(isLast)

                Divider()

                Button("Delete Separator", role: .destructive) {
                    state.deleteSeparator(separator)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.toggleSeparatorExpansion(separator)
            }
        }
        .contextMenu {
            Button("Enable All in Separator") {
                state.enableAllModsInSeparator(separator)
            }
            .disabled(totalCount == 0)

            Button("Disable All in Separator") {
                state.disableAllModsInSeparator(separator)
            }
            .disabled(totalCount == 0)

            Divider()

            Button("Rename Separator...") {
                state.separatorToRename = separator
            }

            Button("Move Up") {
                state.moveSeparatorUp(separator)
            }
            .disabled(isFirst)

            Button("Move Down") {
                state.moveSeparatorDown(separator)
            }
            .disabled(isLast)

            Divider()

            Button("Delete Separator", role: .destructive) {
                state.deleteSeparator(separator)
            }
        }
    }

    // MARK: - Unassigned Section

    private func unassignedSection(mods: [Mod]) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Unassigned Mods")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 1)

                Text("\(mods.count) mods")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
            )

            ForEach(mods) { mod in
                modRow(mod: mod)
                    .padding(.leading, 8)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Mod Row

    private func modRow(mod: Mod) -> some View {
        let isSelected = state.selectedModId == mod.id

        return HStack(spacing: 0) {
            // Column 1: Status Icon / Checkbox
            HStack {
                Spacer(minLength: 0)
                if mod.isCoreSMAPI {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.blue)
                        .help("Core SMAPI Component (Always Active)")
                } else {
                    Button {
                        state.selectedModId = mod.id
                        state.toggleMod(mod)
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    } label: {
                        Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(mod.isEnabled ? Color.green : Color.secondary.opacity(0.45))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(mod.isEnabled ? "Click to disable mod (Space)" : "Click to enable mod (Space)")
                }
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

            // Column 3: Version
            Text(mod.version)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            // Column 4: Status Indicator
            Group {
                if mod.isCoreSMAPI {
                    Text("Core")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.12))
                        )
                        .help("Core SMAPI Component (Always Active)")
                } else {
                    Button {
                        state.selectedModId = mod.id
                        state.toggleMod(mod)
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    } label: {
                        Text(mod.isEnabled ? "Active" : "Disabled")
                            .font(.caption.bold())
                            .foregroundStyle(mod.isEnabled ? Color.green : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(mod.isEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mod.isEnabled ? "Click to disable mod (Space)" : "Click to enable mod (Space)")
                }
            }
            .frame(width: 75, alignment: .center)

            // Column 5: Action Buttons
            HStack(spacing: 6) {
                if mod.hasUpdate, let url = mod.updateURL ?? mod.nexusURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("Update available to v\(mod.suggestedVersion ?? "") — Click to download")
                }

                if mod.nexusModId != nil {
                    Button {
                        Task {
                            await state.toggleEndorsement(for: mod)
                        }
                    } label: {
                        if mod.isEndorsing {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 13, height: 13)
                        } else {
                            Image(systemName: mod.isEndorsed ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12))
                                .foregroundStyle(mod.isEndorsed ? Color.orange : Color.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(mod.isEndorsing)
                    .help(mod.isEndorsed ? "Endorsed on Nexus Mods — Click to abstain" : (state.isNexusConnected ? "Endorse on Nexus Mods" : "Connect Nexus Mods to endorse"))
                }

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
            .frame(width: 95, alignment: .center)
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
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .id(mod.id)
        .contextMenu {
            if mod.isCoreSMAPI {
                Label("Core SMAPI Component", systemImage: "shield.fill")
                Text("Always active (required by SMAPI)")
                    .font(.caption)
            } else {
                Button(mod.isEnabled ? "Disable Mod (Space)" : "Enable Mod (Space)") {
                    state.toggleMod(mod)
                }
            }

            if mod.hasUpdate, let url = mod.updateURL ?? mod.nexusURL {
                Divider()
                Button("Download Update (v\(mod.suggestedVersion ?? ""))") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Menu("Move to Separator") {
                if let currentSep = state.separator(for: mod) {
                    Button("Remove from '\(currentSep.name)'") {
                        state.assignMod(mod, to: nil)
                    }
                    Divider()
                }

                ForEach(state.separators) { sep in
                    Button {
                        state.assignMod(mod, to: sep)
                    } label: {
                        HStack {
                            Text(sep.name)
                            if state.separator(for: mod)?.id == sep.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button("New Separator...") {
                    state.promptNewSeparator(forModId: mod.id)
                }
            }

            if let sep = state.separator(for: mod) {
                let modIds = sep.modIds
                let idx = modIds.firstIndex(where: { $0.caseInsensitiveCompare(mod.id) == .orderedSame }) ?? -1
                let canMoveUp = idx > 0
                let canMoveDown = idx >= 0 && idx < modIds.count - 1

                Menu("Reorder in Separator") {
                    Button("Move Up") {
                        state.moveModUpInSeparator(mod)
                    }
                    .disabled(!canMoveUp)

                    Button("Move Down") {
                        state.moveModDownInSeparator(mod)
                    }
                    .disabled(!canMoveDown)
                }
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
            if mod.nexusModId != nil {
                Button {
                    Task {
                        await state.toggleEndorsement(for: mod)
                    }
                } label: {
                    Label(
                        mod.isEndorsed ? "Unendorse on Nexus Mods" : "Endorse on Nexus Mods",
                        systemImage: mod.isEndorsed ? "hand.thumbsup.slash" : "hand.thumbsup"
                    )
                }
                .disabled(mod.isEndorsing)
            }

            Divider()

            Button("Install Mod Archive... (⌘O)") {
                state.promptInstallModArchive()
            }

            Button("Copy Unique ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mod.id, forType: .string)
            }

            Divider()

            Button(role: .destructive) {
                state.promptDeleteMod(mod)
            } label: {
                Label("Delete Mod...", systemImage: "trash")
            }
            .disabled(mod.isCoreSMAPI)
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

            Button {
                state.promptInstallModArchive()
            } label: {
                Label("Install Mod Archive...", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Event Monitoring

    private func setupEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 1. If modifier keys like Cmd/Ctrl/Opt/Shift are pressed, let standard shortcuts handle them
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard flags.isEmpty else { return event }

            // 2. If the user is currently typing in an input field (Search bar, sheet text field, etc.), do not intercept
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField || responder is NSText {
                return event
            }

            // 3. If any modal sheets or dialogs are presented, do not intercept
            guard !state.isSettingsPresented,
                  !state.isNewProfilePresented,
                  !state.isConfigEditorPresented,
                  !state.isNexusPresented,
                  !state.isAboutPresented,
                  !state.isNewSeparatorPresented,
                  state.separatorToRename == nil else {
                return event
            }

            // 4. Spacebar (keyCode 49) -> Toggle selected mod
            if event.keyCode == 49 {
                state.toggleSelectedMod()
                return nil // Handled, suppress system beep
            }

            // 5. Down Arrow (keyCode 125) -> Navigate to next mod
            if event.keyCode == 125 {
                if state.selectNextMod() {
                    return nil
                }
            }

            // 6. Up Arrow (keyCode 126) -> Navigate to previous mod
            if event.keyCode == 126 {
                if state.selectPreviousMod() {
                    return nil
                }
            }

            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
