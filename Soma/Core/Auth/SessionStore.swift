import Foundation
import Supabase

/// Single source of truth for "is the user signed in?".
///
/// The Supabase client owns the JWT (stored via KeychainAuthStorage); this
/// store just publishes the SwiftUI-visible mirror so views can gate on it.
/// All access to the underlying client goes through here so view code never
/// touches Auth APIs directly.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isRestoring = true
    @Published var errorText: String?

    private let client: SupabaseClient
    private let appleSignIn = AppleSignInCoordinator()

    init(client: SupabaseClient = .shared) {
        self.client = client
        Task { await restore() }
    }

    var isSignedIn: Bool { session != nil }

    private func restore() async {
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
        isRestoring = false
    }

    func signInWithApple() async {
        errorText = nil
        do {
            let credential = try await appleSignIn.signIn()
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: credential.identityToken,
                    nonce: credential.rawNonce
                )
            )
            self.session = session
        } catch AppleSignInError.canceled {
            // User dismissed the sheet — no copy needed.
        } catch {
            errorText = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorText = error.localizedDescription
        }
        session = nil
        // Both of these live in UserDefaults, which outlives the account.
        // Clearing them means the next person to sign in on this phone is
        // asked afresh instead of inheriting someone else's HealthKit sync
        // and someone else's consent to send meals to Claude.
        // Observers first: they're what would wake the app and sync into
        // whoever signs in next.
        HealthKitSync.shared.stopObserving()
        HealthKitSync.clearConnected()
        AIDisclosure.shared.reset()
    }
}
