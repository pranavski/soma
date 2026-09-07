import Foundation
import Supabase

/// The server-side copy of the third-party-AI consent decision.
///
/// `AIDisclosure` is the source of truth the UI reads, but its answer lives
/// in UserDefaults, and the nightly `generate-insights` job runs on the
/// server without the phone in the loop. This row is what that job (and
/// the cron fan-out that enqueues it) checks before anything reaches
/// Claude. Owner-only RLS; one row per user, overwritten on every change.
struct AIConsentRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func set(consented: Bool) async throws {
        let userId = try await client.auth.session.user.id
        let row = ConsentUpsert(
            user_id: userId,
            consented: consented,
            consent_version: AIDisclosure.consentVersion
        )
        try await client.from("ai_consent")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    private struct ConsentUpsert: Encodable {
        let user_id: UUID
        let consented: Bool
        let consent_version: String
    }
}
