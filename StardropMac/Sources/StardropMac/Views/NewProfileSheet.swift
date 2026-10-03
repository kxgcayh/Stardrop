import SwiftUI

public struct NewProfileSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var profileName: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Profile")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Profile Name:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Multiplayer, SVE, Vanilla+", text: $profileName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Profile") {
                    state.createProfile(name: profileName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
