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

    init(container: DIContainer = .shared) {
        self.container = container
    }

    var body: some View {
        RootView(container: container)
    }
}

// MARK: - Preview

#Preview {
    let container = DIContainer.preview
    return ContentView(container: container)
        .environmentObject(container.makeAuthViewModel())
}
