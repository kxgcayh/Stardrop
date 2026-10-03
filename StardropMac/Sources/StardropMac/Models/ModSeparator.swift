import Foundation

public struct ModSeparator: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var isExpanded: Bool
    public var modIds: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        isExpanded: Bool = true,
        modIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.modIds = modIds
    }
}
