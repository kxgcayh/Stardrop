import SwiftUI

public struct NewSeparatorSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var separatorName: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("New Separator")
                    .font(.title2.bold())
            }

            Text("Enter a name to group and organize your mods (e.g. 'Frameworks', 'Visuals', 'Audio', 'Dialogue'):")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Separator Name", text: $separatorName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit()
                }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Separator") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(separatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
    }

    private func submit() {
        let trimmed = separatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.createSeparator(name: trimmed)
        dismiss()
    }
}

public struct RenameSeparatorSheet: View {
    @ObservedObject var state: AppState
    let separator: ModSeparator
    @Environment(\.dismiss) private var dismiss
    @State private var separatorName: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Rename Separator")
                    .font(.title2.bold())
            }

            TextField("Separator Name", text: $separatorName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit()
                }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(separatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .onAppear {
            separatorName = separator.name
        }
    }

    private func submit() {
        let trimmed = separatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.renameSeparator(separator, newName: trimmed)
        dismiss()
    }
}
