import Foundation

public struct ModDeletionPrompt: Identifiable, Hashable {
    public var id: String { mod.id }
    public let mod: Mod
    public let dependentMods: [Mod]

    public init(mod: Mod, dependentMods: [Mod]) {
        self.mod = mod
        self.dependentMods = dependentMods
    }

    public var hasDependentRequirements: Bool {
        !dependentMods.isEmpty
    }

    public var title: String {
        hasDependentRequirements ? "Warning: Required Mod Dependency" : "Delete Mod?"
    }

    public var message: String {
        if hasDependentRequirements {
            let names = dependentMods.map { "• \($0.name) (\($0.id))" }.joined(separator: "\n")
            return "'\(mod.name)' is currently required by \(dependentMods.count) enabled mod(s):\n\n\(names)\n\nDeleting this mod will likely cause them to fail to load or malfunction.\n\nAre you sure you want to permanently delete '\(mod.name)'?"
        } else {
            return "Are you sure you want to delete '\(mod.name)'?\n\nThis will remove the mod folder from your Mods directory and move it to the Trash."
        }
    }
}
