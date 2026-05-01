import Foundation
import SwiftData

@Model
final class Loan {
    var id: UUID = UUID()
    var typeRaw: String = LoanType.givenOut.rawValue
    var counterparty: String = ""
    var counterpartyContact: String?
    var principal: Decimal = Decimal(0)
    var currentBalance: Decimal = Decimal(0)
    var interestRate: Decimal?
    var startDate: Date = Date()
    var dueDate: Date?
    var statusRaw: String = LoanStatus.active.rawValue
    var reminderDate: Date?
    var notes: String?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.loan)
    var transactions: [Transaction]? = []

    init(
        id: UUID = UUID(),
        type: LoanType,
        counterparty: String,
        counterpartyContact: String? = nil,
        principal: Decimal,
        currentBalance: Decimal? = nil,
        interestRate: Decimal? = nil,
        startDate: Date = Date(),
        dueDate: Date? = nil,
        status: LoanStatus = .active,
        reminderDate: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.counterparty = counterparty
        self.counterpartyContact = counterpartyContact
        self.principal = principal
        self.currentBalance = currentBalance ?? principal
        self.interestRate = interestRate
        self.startDate = startDate
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.reminderDate = reminderDate
        self.notes = notes
    }

    var type: LoanType {
        get { LoanType(rawValue: typeRaw) ?? .givenOut }
        set { typeRaw = newValue.rawValue }
    }

    var status: LoanStatus {
        get { LoanStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return due < Date() && currentBalance > 0
    }
}
