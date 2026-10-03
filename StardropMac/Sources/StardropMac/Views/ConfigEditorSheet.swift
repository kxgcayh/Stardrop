import SwiftUI

public struct ConfigEditorSheet: View {
    let mod: Mod
    @Environment(\.dismiss) private var dismiss
    @State private var configText: String = ""
    @State private var errorMessage: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configuration Editor")
                        .font(.headline)
                    Text(mod.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([mod.configURL])
                } label: {
                    Label("Reveal File", systemImage: "folder")
                        .font(.caption)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $configText)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                .frame(minWidth: 460, minHeight: 320)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Configuration") {
                    saveConfig()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 420)
        .onAppear {
            loadConfig()
        }
    }

    private func loadConfig() {
        if let data = try? Data(contentsOf: mod.configURL),
           let str = String(data: data, encoding: .utf8) {
            configText = str
        } else {
            errorMessage = "Could not read config.json at \(mod.configURL.path)"
        }
    }

    private func saveConfig() {
        do {
            try configText.write(to: mod.configURL, atomically: true, encoding: .utf8)
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
