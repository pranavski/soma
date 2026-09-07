import Foundation
import Supabase

/// Reads/writes for `public.daily_checkins`. RLS handles user scoping; we
/// don't send `user_id` filters from the client.
struct DailyCheckinsRepository {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
    }

    /// The most recent check-in (any date) or nil. Used to decide whether
    /// to nudge the user to log today's yet.
    func fetchLatest() async throws -> DailyCheckin? {
        let response = try await client
            .from("daily_checkins")
            .select()
            .order("check_date", ascending: false)
            .limit(1)
            .execute()

        let rows = try decoder.decode([DailyCheckin].self, from: response.data)
        return rows.first
    }

    /// Fetch a specific local date's check-in, if any.
    func fetch(on day: Date = Date()) async throws -> DailyCheckin? {
        let response = try await client
            .from("daily_checkins")
            .select()
            .eq("check_date", value: SupabaseDates.localDay(day))
            .limit(1)
            .execute()

        return try decoder.decode([DailyCheckin].self, from: response.data).first
    }

    /// Every check-in between two local days, inclusive. One round-trip for a
    /// whole month so History can mark which days still have no check filed.
    func fetch(from start: Date, through end: Date) async throws -> [DailyCheckin] {
        let response = try await client
            .from("daily_checkins")
            .select()
            .gte("check_date", value: SupabaseDates.localDay(start))
            .lte("check_date", value: SupabaseDates.localDay(end))
            .order("check_date", ascending: true)
            .execute()

        return try decoder.decode([DailyCheckin].self, from: response.data)
    }

    /// Insert-or-update the check-in for `day` — today by default, an earlier
    /// local date when the user is filling in one they missed. `energy` is
    /// 0…5. `mood` is optional.
    func upsert(energy: Int, mood: String?, on day: Date = Date()) async throws {
        precondition((0...5).contains(energy), "energy must be 0…5")
        let userId = try await client.auth.session.user.id

        struct Row: Encodable {
            let user_id: UUID
            let check_date: String
            let energy: Int
            let mood: String?
        }

        let row = Row(
            user_id: userId,
            check_date: SupabaseDates.localDay(day),
            energy: energy,
            mood: (mood?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        )

        _ = try await client
            .from("daily_checkins")
            .upsert(row, onConflict: "user_id,check_date")
            .execute()
    }
}
