//
//  ExpenseCategory+Presentation.swift
//  Presentation Layer — Theme
//
//  The visual half of `ExpenseCategory`.
//
//  Kept out of the domain deliberately: the entity stays free of SwiftUI, so
//  the business rules compile and test anywhere, while everything the UI needs
//  still reads as `category.color`.
//

import SwiftUI

extension ExpenseCategory {

    /// Accent colour, defined in the asset catalog with a dark variant.
    var color: Color {
        switch self {
        case .food:          return Color("CategoryFood")
        case .transport:     return Color("CategoryTransport")
        case .entertainment: return Color("CategoryEntertainment")
        case .utilities:     return Color("CategoryUtilities")
        case .shopping:      return Color("CategoryShopping")
        case .health:        return Color("CategoryHealth")
        case .other:         return Color("CategoryOther")
        }
    }

    /// Low-opacity version of the accent, for badge and row backgrounds.
    var softColor: Color {
        color.opacity(0.15)
    }
}
