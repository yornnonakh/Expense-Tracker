//
//  AppTheme.swift
//  Presentation Layer — Theme
//
//  The single source of truth for colour, spacing, radius and type.
//
//  Colours resolve from the asset catalog, where each one carries a light and
//  a dark variant. That is what gives the app free dark-mode support without
//  importing UIKit or threading `@Environment(\.colorScheme)` through every
//  view — the system picks the right value at render time.
//
//  The light-appearance values match the specified palette exactly:
//    primary     RGB(1.00, 0.60, 0.20)
//    secondary   RGB(0.40, 0.60, 0.95)
//    background  RGB(0.98, 0.97, 0.96)
//    card        white
//    textPrimary RGB(0.20, 0.20, 0.20)
//    textSecond. RGB(0.60, 0.60, 0.60)
//    divider     RGB(0.90, 0.90, 0.90)
//

import SwiftUI

enum AppTheme {

    // MARK: - Colours

    enum Colors {
        static let primary = Color("AppPrimary")
        static let secondary = Color("AppSecondary")
        static let background = Color("AppBackground")
        static let card = Color("AppCardBackground")
        static let textPrimary = Color("AppTextPrimary")
        static let textSecondary = Color("AppTextSecondary")
        static let divider = Color("AppDivider")

        static let success = Color("AppSuccess")
        static let warning = Color("AppWarning")
        static let danger = Color("AppDanger")

        /// Tinted fill behind icons and badges — the category colour at low
        /// opacity, which reads correctly in both appearances.
        static func softFill(_ color: Color) -> Color {
            color.opacity(0.15)
        }

        /// Warm gradient used on the dashboard header and primary buttons.
        static let primaryGradient = LinearGradient(
            colors: [primary, primary.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let secondaryGradient = LinearGradient(
            colors: [secondary, secondary.opacity(0.80)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Spacing

    /// A 4pt scale. Using named steps instead of literals keeps rhythm
    /// consistent and makes a global density change a one-file edit.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
    }

    // MARK: - Corner radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 26, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 15, weight: .regular)
        /// 14pt — the specified size for text fields.
        static let field = Font.system(size: 14, weight: .regular)
        static let callout = Font.system(size: 14, weight: .medium)
        static let caption = Font.system(size: 12, weight: .regular)
        static let captionBold = Font.system(size: 12, weight: .semibold)
        static let amount = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let bigAmount = Font.system(size: 36, weight: .bold, design: .rounded)
    }

    // MARK: - Elevation

    enum Shadow {
        static let cardRadius: CGFloat = 10
        static let cardY: CGFloat = 4
        /// Kept subtle — a heavy shadow looks muddy against the dark palette.
        static let cardOpacity: Double = 0.06
    }

    // MARK: - Layout constants

    enum Metrics {
        /// Specified height for the primary button.
        static let buttonHeight: CGFloat = 50
        static let fieldHeight: CGFloat = 48
        static let iconCircle: CGFloat = 44
        static let avatarSize: CGFloat = 44
        static let fabSize: CGFloat = 58
        static let progressBarHeight: CGFloat = 10
        static let chartHeight: CGFloat = 150
        static let pieChartSize: CGFloat = 220
    }

    // MARK: - Animation

    enum Motion {
        static let standard = Animation.easeInOut(duration: 0.25)
        static let spring = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let quick = Animation.easeOut(duration: 0.18)
    }
}
