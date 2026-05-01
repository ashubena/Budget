import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = CategoryKind.expense.rawValue
    var icon: String?
    var color: String?

    var parent: Category?

    @Relationship(deleteRule: .nullify, inverse: \Category.parent)
    var children: [Category]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \CategoryKeyword.category)
    var keywords: [CategoryKeyword]? = []

    @Relationship(deleteRule: .cascade, inverse: \CategoryAlias.category)
    var aliases: [CategoryAlias]? = []

    init(
        id: UUID = UUID(),
        name: String,
        kind: CategoryKind = .expense,
        parent: Category? = nil,
        icon: String? = nil,
        color: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.parent = parent
        self.icon = icon
        self.color = color
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class CategoryKeyword {
    var keyword: String = ""
    var category: Category?
    var isStrong: Bool = true

    init(keyword: String, category: Category?, isStrong: Bool = true) {
        self.keyword = keyword.lowercased()
        self.category = category
        self.isStrong = isStrong
    }
}

@Model
final class CategoryAlias {
    var alias: String = ""
    var category: Category?
    var sourceRaw: String = AliasSource.learned.rawValue
    var confidenceScore: Int = 1
    var lastUsedAt: Date?

    init(
        alias: String,
        category: Category?,
        source: AliasSource = .learned,
        confidenceScore: Int = 1,
        lastUsedAt: Date? = nil
    ) {
        self.alias = alias.lowercased()
        self.category = category
        self.sourceRaw = source.rawValue
        self.confidenceScore = confidenceScore
        self.lastUsedAt = lastUsedAt
    }

    var source: AliasSource {
        get { AliasSource(rawValue: sourceRaw) ?? .learned }
        set { sourceRaw = newValue.rawValue }
    }
}
