import SwiftUI

public struct ModTableView: View {
    @ObservedObject var state: AppState
    @State private var eventMonitor: Any? = nil
    @State private var dropTargetKey: String? = nil

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
                        VStack(spacing: 4) {
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
                        // Safety net: ensure the separator is expanded before scrolling.
                        // selectAndRevealMod already does this synchronously, but guard
                        // against any code paths that set scrollTargetModId directly.
                        if let sep = state.separator(forId: id), !sep.isExpanded {
                            if let idx = state.separators.firstIndex(where: { $0.id == sep.id }) {
                                state.separators[idx].isExpanded = true
                                state.saveSeparatorsState()
                            }
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

    // MARK: - Drag and Drop Helpers

    /// Dropping a mod onto another mod reuses that row's position inside its separator,
    /// or unassigns the dragged mod when the target row lives outside any separator.
    private func handleModDrop(items: [String], onto target: Mod) -> Bool {
        for item in items {
            guard item.hasPrefix("mod:") else { continue }
            let draggedId = String(item.dropFirst(4))
            guard draggedId.caseInsensitiveCompare(target.id) != .orderedSame else { return false }
            guard let draggedMod = state.mods.first(where: { $0.id.caseInsensitiveCompare(draggedId) == .orderedSame }) else { continue }

            let sourceSep = state.separator(forId: draggedId)
            if let targetSep = state.separator(forId: target.id) {
                var targetIndex = targetSep.modIds.firstIndex(where: { $0.caseInsensitiveCompare(target.id) == .orderedSame }) ?? targetSep.modIds.count
                if let sourceSep, sourceSep.id == targetSep.id,
                   let sourceIndex = sourceSep.modIds.firstIndex(where: { $0.caseInsensitiveCompare(draggedId) == .orderedSame }),
                   sourceIndex < targetIndex {
                    targetIndex -= 1
                }
                state.moveMod(id: draggedMod.id, toSeparator: targetSep, atIndex: targetIndex)
            } else {
                state.moveMod(id: draggedMod.id, toSeparator: nil, atIndex: nil)
            }
            return true
        }
        return false
    }

    /// Dropping onto a separator header: a mod joins that separator, a separator reorders.
    private func handleSeparatorDrop(items: [String], onto target: ModSeparator) -> Bool {
        for item in items {
            if item.hasPrefix("sep:"), let sourceId = UUID(uuidString: String(item.dropFirst(4))) {
                state.moveSeparator(id: sourceId, toIndexAt: target.id)
                return true
            }
            if item.hasPrefix("mod:") {
                state.moveMod(id: String(item.dropFirst(4)), toSeparator: target, atIndex: nil)
                return true
            }
        }
        return false
    }

    private func handleUnassignedDrop(items: [String]) -> Bool {
        for item in items where item.hasPrefix("mod:") {
            state.moveMod(id: String(item.dropFirst(4)), toSeparator: nil, atIndex: nil)
            return true
        }
        return false
    }

    private func dropHighlight(for key: String) -> (Bool) -> Void {
        { targeted in
            if targeted { dropTargetKey = key }
            else if dropTargetKey == key { dropTargetKey = nil }
        }
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
                        Text("No mods in this separator — drag a mod here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                            .padding(.vertical, 4)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 2)
                            .opacity(dropTargetKey == "mod:empty-\(separator.id.uuidString)" ? 1 : 0)
                    )
                    .dropDestination(for: String.self, action: { items, _ in
                        guard items.contains(where: { $0.hasPrefix("mod:") }) else { return false }
                        for item in items where item.hasPrefix("mod:") {
                            state.moveMod(id: String(item.dropFirst(4)), toSeparator: separator, atIndex: nil)
                        }
                        return true
                    }, isTargeted: dropHighlight(for: "mod:empty-\(separator.id.uuidString)"))
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

        let content = HStack(spacing: 8) {
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
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
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
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue, lineWidth: 2)
                .opacity(dropTargetKey == "sep:\(separator.id.uuidString)" ? 1 : 0)
        )
        .dropDestination(for: String.self, action: { items, _ in
            handleSeparatorDrop(items: items, onto: separator)
        }, isTargeted: dropHighlight(for: "sep:\(separator.id.uuidString)"))

        return draggableSeparatorContent(content, separator: separator)
    }

    // Only collapsed separators can be dragged (to reorder); expanded ones stay put.
    @ViewBuilder
    private func draggableSeparatorContent<V: View>(_ content: V, separator: ModSeparator) -> some View {
        if separator.isExpanded {
            content
        } else {
            content.draggable("sep:\(separator.id.uuidString)")
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
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: 2)
                    .opacity(dropTargetKey == "unassigned" ? 1 : 0)
            )
            .contentShape(Rectangle())
            .dropDestination(for: String.self, action: { items, _ in
                handleUnassignedDrop(items: items)
            }, isTargeted: dropHighlight(for: "unassigned"))

            ForEach(mods) { mod in
                modRow(mod: mod)
                    .padding(.leading, 8)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Mod Row

    private func modRow(mod: Mod) -> some View {
        let isSelected = state.isModSelected(mod.id)
        let isPrimary = state.selectedModId == mod.id

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
                        if state.selectedModIds.contains(mod.id) && state.selectedModIds.count > 1 {
                            state.toggleSelectedMods()
                        } else {
                            state.handleModClick(mod, isShift: false, isCommand: false)
                            state.toggleMod(mod)
                        }
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
                } else if state.hasMissingDependencyRequirements(mod) {
                    let missing = state.missingDependencies(for: mod)
                    let disabled = state.disabledDependencies(for: mod)
                    let details = (missing.map { "\($0) (missing)" } + disabled.map { "\($0) (disabled)" }).joined(separator: ", ")
                    Button {
                        if state.selectedModIds.contains(mod.id) && state.selectedModIds.count > 1 {
                            state.toggleSelectedMods()
                        } else {
                            state.handleModClick(mod, isShift: false, isCommand: false)
                            state.toggleMod(mod)
                        }
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    } label: {
                        Text("?")
                            .font(.caption.bold())
                            .foregroundStyle(Color.orange)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.orange.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .help("Missing dependencies requirement: \(details)")
                } else {
                    Button {
                        if state.selectedModIds.contains(mod.id) && state.selectedModIds.count > 1 {
                            state.toggleSelectedMods()
                        } else {
                            state.handleModClick(mod, isShift: false, isCommand: false)
                            state.toggleMod(mod)
                        }
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
                .fill(isSelected ? Color.accentColor.opacity(isPrimary ? 0.22 : 0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            state.handleModClick(
                mod,
                isShift: flags.contains(.shift),
                isCommand: flags.contains(.command)
            )
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .id(mod.id)
        .contextMenu {
            let isBatch = state.selectedModIds.contains(mod.id) && state.selectedModIds.count > 1
            if isBatch {
                let count = state.selectedModIds.count
                Label("\(count) Mods Selected", systemImage: "checklist")
                Divider()
                Button("Toggle Selected Mods (\(count)) (Space)") {
                    state.toggleSelectedMods()
                }
                Button("Enable Selected Mods") {
                    state.enableSelectedMods()
                }
                Button("Disable Selected Mods") {
                    state.disableSelectedMods()
                }
                Divider()
            } else if mod.isCoreSMAPI {
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

            if isBatch {
                Button(role: .destructive) {
                    state.promptDeleteSelectedMods()
                } label: {
                    Label("Delete \(state.selectedModIds.count) Mods...", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    state.promptDeleteMod(mod)
                } label: {
                    Label("Delete Mod...", systemImage: "trash")
                }
                .disabled(mod.isCoreSMAPI)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue, lineWidth: 2)
                .opacity(dropTargetKey == "mod:\(mod.id)" ? 1 : 0)
        )
        .draggable("mod:\(mod.id)")
        .dropDestination(for: String.self, action: { items, _ in
            handleModDrop(items: items, onto: mod)
        }, isTargeted: dropHighlight(for: "mod:\(mod.id)"))
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
            // 1. If the user is currently typing in an input field (Search bar, sheet text field, etc.), do not intercept
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField || responder is NSText {
                return event
            }

            // 2. If any modal sheets or dialogs are presented, do not intercept
            guard !state.isSettingsPresented,
                  !state.isNewProfilePresented,
                  !state.isConfigEditorPresented,
                  !state.isNexusPresented,
                  !state.isAboutPresented,
                  !state.isNewSeparatorPresented,
                  state.separatorToRename == nil,
                  state.modToDelete == nil else {
                return event
            }

            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])

            // 3. Command shortcuts
            if flags == [.command] {
                // Command + A (keyCode 0) -> Select All
                if event.keyCode == 0 {
                    state.selectAllMods()
                    return nil
                }
                return event
            }

            // 4. Shift shortcuts (Batch selection)
            if flags == [.shift] {
                // Shift + Down Arrow (keyCode 125) -> Extend selection down
                if event.keyCode == 125 {
                    if state.extendSelectionDown() {
                        return nil
                    }
                }

                // Shift + Up Arrow (keyCode 126) -> Extend selection up
                if event.keyCode == 126 {
                    if state.extendSelectionUp() {
                        return nil
                    }
                }

                // Shift + Space (keyCode 49) -> Toggle selected mods
                if event.keyCode == 49 {
                    state.toggleSelectedMods()
                    return nil
                }

                return event
            }

            // 5. If other modifier combinations are pressed, let system handle them
            guard flags.isEmpty else { return event }

            // 6. Spacebar (keyCode 49) -> Toggle selected mod(s)
            if event.keyCode == 49 {
                state.toggleSelectedMods()
                return nil // Handled, suppress system beep
            }

            // 7. Down Arrow (keyCode 125) -> Navigate to next mod
            if event.keyCode == 125 {
                if state.selectNextMod() {
                    return nil
                }
            }

            // 8. Up Arrow (keyCode 126) -> Navigate to previous mod
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
