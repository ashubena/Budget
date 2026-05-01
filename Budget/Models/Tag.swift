import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var color: String?

    @Relationship(inverse: \Transaction.tags)
    var transactions: [Transaction]? = []

    init(id: UUID = UUID(), name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}
