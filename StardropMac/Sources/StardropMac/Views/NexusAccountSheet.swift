import SwiftUI

public struct NexusAccountSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var errorMessage: String?

    public var isConnected: Bool {
        state.isNexusConnected
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nexus Mods API")
                        .font(.headline)
                    Text(isConnected ? "Connected Account" : "Connect your account to check for mod updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            if isConnected {
                connectedView
            } else {
                connectView
            }
        }
        .frame(width: 440)
        .onAppear {
            apiKeyInput = state.nexusApiKey ?? ""
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(state.settings.nexusDetails.username ?? "Nexus User")
                    .font(.title3.bold())

                if state.settings.nexusDetails.isPremium {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text("PREMIUM MEMBER")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
                } else {
                    Text("Free Member")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))

            HStack {
                Button("Disconnect Account", role: .destructive) {
                    disconnect()
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    // MARK: - Connect Form View

    private var connectView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Step 1: Open Nexus to get key
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Obtain your Personal API Key:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Button {
                    NSWorkspace.shared.open(NexusService.shared.getApiKeyURL)
                } label: {
                    Label("Open Nexus Mods API Settings", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }

            // Step 2: Paste API Key
            VStack(alignment: .leading, spacing: 6) {
                Text("2. Paste your API Key here:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                SecureField("Nexus API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
            }

            // Error notice if validation failed
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Security note
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Your API key is saved locally in Settings.json and only used to contact api.nexusmods.com.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button("Connect Account") {
                    validateAndSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }
        }
        .padding(20)
    }

    // MARK: - Logic

    private func validateAndSave() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidating = true
        errorMessage = nil

        Task {
            do {
                let response = try await NexusService.shared.validateKey(key)
                let encryptedKey = SimpleObscureService.shared.encryptAndSaveKey(key) ?? key
                await MainActor.run {
                    isValidating = false
                    state.settings.nexusDetails.key = encryptedKey
                    state.settings.nexusDetails.username = response.name
                    state.settings.nexusDetails.isPremium = response.isPremium ?? false
                    SettingsService.shared.saveSettings(state.settings)
                }
                await state.fetchEndorsements()
            } catch {
                await MainActor.run {
                    isValidating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func disconnect() {
        SimpleObscureService.shared.clearNotionCache()
        state.settings.nexusDetails.key = nil
        state.settings.nexusDetails.username = nil
        state.settings.nexusDetails.isPremium = false
        SettingsService.shared.saveSettings(state.settings)
        for i in 0..<state.mods.count {
            state.mods[i].isEndorsed = false
        }
    }
}
