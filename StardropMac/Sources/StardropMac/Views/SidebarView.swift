import SwiftUI

public struct SidebarView: View {
    @ObservedObject var state: AppState

    public var body: some View {
        List(selection: $state.selectedCategory) {
            Section("Library") {
                NavigationLink(value: SidebarCategory.allMods) {
                    Label {
                        HStack {
                            Text("All Mods")
                            Spacer()
                            Text("\(state.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.blue)
                    }
                }

                NavigationLink(value: SidebarCategory.enabledOnly) {
                    Label {
                        HStack {
                            Text("Enabled")
                            Spacer()
                            Text("\(state.enabledCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                NavigationLink(value: SidebarCategory.disabledOnly) {
                    Label {
                        HStack {
                            Text("Disabled")
                            Spacer()
                            Text("\(state.totalCount - state.enabledCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                let updatesCount = state.mods.filter { $0.hasUpdate }.count
                if updatesCount > 0 {
                    NavigationLink(value: SidebarCategory.updatableOnly) {
                        Label {
                            HStack {
                                Text("Updates")
                                Spacer()
                                Text("\(updatesCount)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.orange))
                                    .foregroundStyle(.white)
                            }
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section("Profiles") {
                ForEach(state.profiles) { profile in
                    ProfileSidebarRow(state: state, profile: profile)
                }

                Button {
                    state.isNewProfilePresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                        Text("New Profile...")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
            }

            Section("Tools") {
                Button {
                    state.revealInFinder(state.modsDirectory)
                } label: {
                    Label("Open Mods Folder", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.plain)

                Button {
                    state.openLogs()
                } label: {
                    Label("Stardrop Logs", systemImage: "doc.text")
                }
                .buttonStyle(.plain)

                Button {
                    state.openSmapiLog()
                } label: {
                    Label("SMAPI Error Logs", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await state.checkForModUpdates()
                    }
                } label: {
                    Label(state.isCheckingUpdates ? "Checking Updates..." : "Check for Mod Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(state.isCheckingUpdates)
                .buttonStyle(.plain)

                Button {
                    state.isAboutPresented = true
                } label: {
                    Label("About Stardrop", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
            }

            Section("Services") {
                Button {
                    state.isNexusPresented = true
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Nexus Mods")
                                if let username = state.settings.nexusDetails.username {
                                    Text(username)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not Connected")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "globe.americas.fill")
                                .foregroundStyle(state.isNexusConnected ? .orange : .secondary)
                        }

                        Spacer()

                        if state.isNexusConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}

public struct ProfileSidebarRow: View {
    @ObservedObject var state: AppState
    let profile: Profile
    @State private var isHovered: Bool = false

    public var body: some View {
        let isActive = state.activeProfile.id == profile.id

        Button {
            state.selectProfile(profile)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? Color.blue : Color.secondary)
                    .frame(width: 16)

                Text(profile.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : (isHovered ? Color.primary : Color.secondary))
                    .lineLimit(1)

                Spacer()

                Text("\(profile.enabledModIds.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isActive ? Color.blue : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(isActive ? Color.blue.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.12)))
                    )

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.blue.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Duplicate Profile") {
                state.duplicateProfile(profile)
            }
            if !profile.isProtected {
                Divider()
                Button("Delete Profile", role: .destructive) {
                    state.deleteProfile(profile)
                }
            }
        }
    }
}
