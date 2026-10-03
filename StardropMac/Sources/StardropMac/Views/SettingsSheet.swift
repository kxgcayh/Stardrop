import SwiftUI

public struct SettingsSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var smapiPath: String = ""
    @State private var modsPath: String = ""
    @State private var autoSave: Bool = true

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.bold())

            Form {
                Section("Game & SMAPI Paths") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stardew Valley / SMAPI Folder:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Path to Game directory", text: $smapiPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                chooseFolder { path in
                                    smapiPath = path
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mods Folder:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Path to Mods directory", text: $modsPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                chooseFolder { path in
                                    modsPath = path
                                }
                            }
                        }
                    }
                }

                Section("Nexus Mods API") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "globe.americas.fill")
                                    .foregroundStyle(state.isNexusConnected ? Color.orange : Color.secondary)
                                Text(state.isNexusConnected ? "Connected as \(state.settings.nexusDetails.username ?? "User")" : "Not Connected")
                                    .fontWeight(.medium)
                            }
                            Text(state.isNexusConnected 
                                ? (state.settings.nexusDetails.isPremium ? "Nexus Premium Member" : "Nexus Free Member") 
                                : "Connect your Nexus API key to check for mod updates.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(state.isNexusConnected ? "Manage Account..." : "Connect...") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                state.isNexusPresented = true
                            }
                        }
                    }
                }

                Section("Profiles") {
                    Toggle("Automatically save profile changes", isOn: $autoSave)
                }

                if let details = state.settings.gameDetails {
                    Section("System Info") {
                        LabeledContent("Stardew Valley Version", value: details.gameVersion)
                        LabeledContent("SMAPI Version", value: details.smapiVersion)

                        Button("About Stardrop...") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                state.isAboutPresented = true
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Settings") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
        .onAppear {
            smapiPath = state.settings.smapiFolderPath ?? state.gameDirectory.path
            modsPath = state.settings.modFolderPath ?? state.modsDirectory.path
            autoSave = state.settings.shouldAutomaticallySaveProfileChanges
        }
    }

    private func chooseFolder(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }

    private func save() {
        state.settings.smapiFolderPath = smapiPath.isEmpty ? nil : smapiPath
        state.settings.modFolderPath = modsPath.isEmpty ? nil : modsPath
        state.settings.shouldAutomaticallySaveProfileChanges = autoSave
        SettingsService.shared.saveSettings(state.settings)
        state.refreshMods()
    }
}
