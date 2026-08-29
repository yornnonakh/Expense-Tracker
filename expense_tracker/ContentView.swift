//
//  ContentView.swift
//  expense_tracker
//
//  Thin wrapper kept as the app's conventional entry view. The actual
//  routing decision lives in `RootView`.
//

import SwiftUI

struct ContentView: View {

    private let container: DIContainer

    init(container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.container = container
    }

    var body: some View {
        RootView(container: container)
    }
}

#if DEBUG

// MARK: - Preview

#Preview {
    let container = DIContainer.preview
    return ContentView(container: container)
        .environmentObject(container.makeAuthViewModel())
        .environmentObject(DIContainer.previewCurrencyStore)
}

#endif
