//
//  Haptics.swift
//  Presentation Layer — Theme
//
//  Tactile feedback on save, delete and selection.
//
//  THE ONE UIKIT TOUCHPOINT IN THE APP. SwiftUI's native `.sensoryFeedback`
//  is iOS 17+, and this app deploys to iOS 16, so the feedback generators are
//  the only way to get haptics on the full supported range. Everything is
//  quarantined behind this enum and guarded by `canImport`, so the rest of the
//  codebase stays pure SwiftUI and this file is the single thing to delete if
//  you ever want to drop the dependency entirely.
//

#if canImport(UIKit)
import UIKit
#endif

enum Haptics {

    /// Called after a successful save.
    @MainActor
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Called when a budget tips over its limit.
    @MainActor
    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// Called when an operation fails.
    @MainActor
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    /// Called when the user changes a segmented selection or filter.
    @MainActor
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Light tap for buttons that don't warrant a full notification haptic.
    @MainActor
    static func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
