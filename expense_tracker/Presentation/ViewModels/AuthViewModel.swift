//
//  AuthViewModel.swift
//  Presentation Layer — ViewModels
//
//  App-wide session state: who is signed in, and which root screen shows.
//
//  Owned by the App struct and injected as an `@EnvironmentObject`, so there
//  is exactly one instance and every screen reads the same session.
//

import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject, ErrorPresenting {

    /// Which root the app should render.
    enum State: Equatable {
        /// Checking for a stored session at launch — shows the splash.
        case restoring
        case signedOut
        case signedIn(User)
    }

    @Published private(set) var state: State = .restoring
    @Published private(set) var session: AuthSession?
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    private let restoreSession: RestoreSessionUseCase
    private let signOutUseCase: SignOutUseCase
    private let seeder: SampleDataSeeder

    /// Optional because previews and offline test graphs run without sync.
    private let syncCoordinator: SyncCoordinator?

    /// `nonisolated` so SwiftUI can build this inside a `StateObject`
    /// autoclosure, which runs outside actor isolation. The initializer only
    /// assigns stored properties, so nothing here needs the main actor.
    nonisolated init(
        restoreSession: RestoreSessionUseCase,
        signOutUseCase: SignOutUseCase,
        seeder: SampleDataSeeder,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.restoreSession = restoreSession
        self.signOutUseCase = signOutUseCase
        self.seeder = seeder
        self.syncCoordinator = syncCoordinator
    }

    var currentUser: User? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { currentUser != nil }

    // MARK: - Lifecycle

    /// Auto-login. Runs once at launch from the root view's `.task`.
    func restore() async {
        do {
            if let session = try await restoreSession.execute() {
                await adopt(session)
            } else {
                state = .signedOut
            }
        } catch {
            // A broken stored session should land the user on sign-in, not on
            // an error screen they can't get past.
            present(error)
            state = .signedOut
        }
    }

    /// Called by the sign-in and sign-up flows once credentials check out.
    func adopt(_ session: AuthSession) async {
        self.session = session
        self.state = .signedIn(session.user)
        clearError()

        // Give a brand-new install something to look at. No-ops afterwards.
        await seeder.seedIfNeeded()

        // Sync starts only once somebody is signed in: every endpoint it calls
        // needs a token, so starting earlier would just log 401s.
        syncCoordinator?.start()
        await syncCoordinator?.syncNow()
    }

    /// Swaps in a freshly saved version of the signed-in user, e.g. after a
    /// profile photo change.
    ///
    /// Rebuilds the cached session around the new user as well, so the two
    /// can't disagree about who is signed in — every screen reads `state`, but
    /// anything reaching for `session.user` would otherwise see the old copy.
    /// No-ops when signed out: there is nothing to update, and forcing a
    /// signed-in state here would resurrect a session the user just ended.
    func updateCurrentUser(_ user: User) {
        guard case .signedIn = state else { return }

        state = .signedIn(user)

        if let session {
            self.session = AuthSession(
                token: session.token, user: user, issuedAt: session.issuedAt
            )
        }
    }

    func signOut() async {
        do {
            try await signOutUseCase.execute()
        } catch {
            present(error)
        }

        // Wipe local data and the sync cursor. Without this the next account
        // to sign in on this device would inherit the previous one's expenses
        // and then upload them as its own.
        await syncCoordinator?.reset()

        // Clear local state even if the repository call failed — the user
        // asked to sign out, and leaving them signed in would be worse than
        // a stale token on disk.
        session = nil
        state = .signedOut
    }
}
