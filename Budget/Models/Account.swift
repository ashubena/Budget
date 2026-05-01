import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String?
    var realBalance: Decimal = Decimal(0)
    var isActive: Bool = true
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType? = nil,
        realBalance: Decimal = 0,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type?.rawValue
        self.realBalance = realBalance
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var type: AccountType? {
        get { typeRaw.flatMap(AccountType.init(rawValue:)) }
        set { typeRaw = newValue?.rawValue }
    }
}
