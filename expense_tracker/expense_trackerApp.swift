//
//  expense_trackerApp.swift
//  expense_tracker
//
//  Application entry point.
//
//  The only place the object graph is created. `DIContainer.shared` is built
//  here, the session view model is created from it and injected into the
//  environment, and everything below receives what it needs by injection.
//

import SwiftUI

@main
struct expense_trackerApp: App {

    /// The composition root, shared for the app's lifetime.
    private let container = DIContainer.shared

    /// Session state lives at the top so it survives every navigation and
    /// every tab switch, and so exactly one instance exists.
    @StateObject private var authViewModel: AuthViewModel

    init() {
        _authViewModel = StateObject(
            wrappedValue: DIContainer.shared.makeAuthViewModel()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
                .environmentObject(authViewModel)
                // Colours come from the asset catalog with light and dark
                // variants, so the app follows the system appearance rather
                // than forcing one.
                .tint(AppTheme.Colors.primary)
        }
    }
}
