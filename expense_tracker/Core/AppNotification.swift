//
//  AppNotification.swift
//  Core
//
//  Change broadcasts, so screens that are already on-screen stay in sync.
//
//  WHY NOTIFICATIONS: adding an expense from the Home tab has to refresh the
//  Expenses list, Statistics and Budget tabs, all of which are alive inside
//  the TabView. Passing a callback down five view hierarchies would couple
//  them together; a broadcast keeps each ViewModel responsible only for
//  reloading itself. ViewModels subscribe with `NotificationCenter.notifications`
//  inside a `.task`, so SwiftUI cancels the subscription with the view.
//

import Foundation

extension Notification.Name {

    /// Posted by `ExpenseRepositoryImpl` after any successful expense write.
    static let expenseDataDidChange = Notification.Name("app.expenseDataDidChange")

    /// Posted by `BudgetRepositoryImpl` after any successful budget write.
    static let budgetDataDidChange = Notification.Name("app.budgetDataDidChange")
}
