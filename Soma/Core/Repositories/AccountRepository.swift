import Foundation
import Supabase

/// Account lifecycle actions that must go through an Edge Function
/// (currently: delete-account). Sign-in / sign-out live on SessionStore.
struct AccountRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    /// Invokes the delete-account Edge Function. On success the caller
    /// should immediately clear the session — the JWT is dead the moment
    /// the function returns, but we still call signOut() locally so
    /// KeychainAuthStorage drops the cached token.
    ///
    /// `authorizationCode` is a fresh Sign in with Apple code; when present
    /// the server exchanges it with Apple and revokes the SIWA token, as
    /// Apple requires for account deletion. Best-effort — deletion goes
    /// through either way.
    func deleteAccount(authorizationCode: String? = nil) async throws {
        struct Body: Encodable {
            let authorization_code: String?
        }
        try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(
                body: Body(authorization_code: authorizationCode)
            )
        )
    }
}
