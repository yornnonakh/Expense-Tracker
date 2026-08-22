//
//  ExpenseCategory.swift
//  Domain Layer — Entities
//
//  The fixed set of buckets an expense can belong to.
//
//  NOTE ON PURITY: this type deliberately knows nothing about SwiftUI. The
//  `Color` associated with each category lives in an extension in the
//  Presentation layer (`ExpenseCategory+Presentation.swift`) so the domain
//  stays framework-free and unit-testable on any platform.
//

import Foundation

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case food
    case transport
    case entertainment
    case utilities
    case shopping
    case health
    case other

    var id: String { rawValue }

    /// Human readable label shown in the UI.
    var displayName: String {
        switch self {
        case .food:          return "Food"
        case .transport:     return "Transport"
        case .entertainment: return "Entertainment"
        case .utilities:     return "Utilities"
        case .shopping:      return "Shopping"
        case .health:        return "Health"
        case .other:         return "Other"
        }
    }

    /// Compact glyph used in badges and list rows.
    var emoji: String {
        switch self {
        case .food:          return "🍔"
        case .transport:     return "🚗"
        case .entertainment: return "🎬"
        case .utilities:     return "💡"
        case .shopping:      return "🛍️"
        case .health:        return "🏥"
        case .other:         return "📦"
        }
    }

    /// SF Symbol alternative, used where an emoji would not tint correctly.
    var systemImageName: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .entertainment: return "film.fill"
        case .utilities:     return "bolt.fill"
        case .shopping:      return "bag.fill"
        case .health:        return "cross.case.fill"
        case .other:         return "shippingbox.fill"
        }
    }

    /// Bucket used when we cannot recognise a stored value.
    static let fallback: ExpenseCategory = .other

    // MARK: - Forward compatible decoding

    /// A build that adds new categories writes raw values this build has never
    /// seen. Rather than failing the whole decode (and losing every expense in
    /// the file), unknown values degrade gracefully to `.other`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ExpenseCategory(rawValue: rawValue) ?? Self.fallback
    }
}
