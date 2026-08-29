//
//  MainTabView.swift
//  Presentation Layer — Views
//
//  The five-tab shell.
//
//  Each tab owns its own `NavigationStack`, which is what preserves each
//  tab's navigation and scroll position independently when switching between
//  them. A single shared stack would reset the others on every switch.
//

import SwiftUI

struct MainTabView: View {

    enum Tab: Hashable {
        case home
        case expenses
        case transactions
        case statistics
        case budget
    }

    @State private var selectedTab: Tab = .home
    private let container: DIContainer

    init(container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.container = container
    }

    var body: some View {
        TabView(selection: $selectedTab) {

            HomeView(selectedTab: $selectedTab, container: container)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

            ExpensesListView(container: container)
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet.rectangle.fill")
                }
                .tag(Tab.expenses)

            TransactionsView(container: container)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.transactions)

            StatisticsView(container: container)
                .tabItem {
                    Label("Stats", systemImage: "chart.pie.fill")
                }
                .tag(Tab.statistics)

            BudgetView(container: container)
                .tabItem {
                    Label("Budget", systemImage: "target")
                }
                .tag(Tab.budget)
        }
        .tint(AppTheme.Colors.primary)
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Main tabs") {
    let container = DIContainer.preview
    return MainTabView(container: container)
        .environmentObject(container.makeAuthViewModel())
        .environmentObject(DIContainer.previewCurrencyStore)
}

#endif
