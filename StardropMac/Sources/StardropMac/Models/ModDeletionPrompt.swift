import Foundation

public struct ModDeletionPrompt: Identifiable, Hashable {
    public var id: String { mods.map { $0.id }.joined(separator: ",") }
    public let mods: [Mod]
    public let dependentMods: [Mod]

    public init(mods: [Mod], dependentMods: [Mod]) {
        self.mods = mods
        self.dependentMods = dependentMods
    }

    public init(mod: Mod, dependentMods: [Mod]) {
        self.mods = [mod]
        self.dependentMods = dependentMods
    }

    public var mod: Mod? {
        mods.first
    }

    public var hasDependentRequirements: Bool {
        !dependentMods.isEmpty
    }

    public var title: String {
        if hasDependentRequirements {
            return "Warning: Required Mod Dependency"
        }
        if mods.count > 1 {
            return "Delete \(mods.count) Mods?"
        }
        return "Delete Mod?"
    }

    public var message: String {
        if mods.count == 1, let singleMod = mods.first {
            if hasDependentRequirements {
                let names = dependentMods.map { "• \($0.name) (\($0.id))" }.joined(separator: "\n")
                return "'\(singleMod.name)' is currently required by \(dependentMods.count) enabled mod(s):\n\n\(names)\n\nDeleting this mod will likely cause them to fail to load or malfunction.\n\nAre you sure you want to permanently delete '\(singleMod.name)'?"
            } else {
                return "Are you sure you want to delete '\(singleMod.name)'?\n\nThis will remove the mod folder from your Mods directory and move it to the Trash."
            }
        } else {
            if hasDependentRequirements {
                let names = dependentMods.map { "• \($0.name) (\($0.id))" }.joined(separator: "\n")
                return "\(dependentMods.count) enabled mod(s) require one or more mods in your selection:\n\n\(names)\n\nDeleting these mods will likely cause them to fail to load or malfunction.\n\nAre you sure you want to permanently delete \(mods.count) selected mods?"
            } else {
                return "Are you sure you want to delete \(mods.count) selected mods?\n\nThis will remove their folders from your Mods directory and move them to the Trash."
            }
        }
    }
}
