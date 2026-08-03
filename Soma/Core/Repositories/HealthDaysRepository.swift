import Foundation
import Supabase

/// Reads/writes for `public.health_days`. The client computes the daily
/// aggregate off-device HealthKit reads and upserts one row per local date.
struct HealthDaysRepository {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
    }

    /// Fetch the last N days of aggregates ordered most-recent-first.
    /// Used by `generate-insights` inputs on the server, and by the client
    /// to short-circuit sync if nothing has changed.
    func fetchRecent(days: Int = 28) async throws -> [HealthDay] {
        let response = try await client
            .from("health_days")
            .select(Self.columns)
            .order("day", ascending: false)
            .limit(days)
            .execute()

        return try decoder.decode([HealthDay].self, from: response.data)
    }

    /// The owner's rows for the trailing window, oldest first — the shape
    /// the Insights charts want (RLS scopes the query to the caller).
    func fetchLastDays(_ days: Int) async throws -> [HealthDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -days, to: today) ?? today

        let response = try await client
            .from("health_days")
            .select(Self.columns)
            .gte("day", value: SupabaseDates.localDay(cutoff))
            .order("day", ascending: true)
            .execute()

        return try decoder.decode([HealthDay].self, from: response.data)
    }

    private static let columns =
        "day,steps,sleep_minutes,resting_hr_bpm,hrv_ms,weight_kg,active_energy_kcal,workout_minutes,tier"

    /// Insert-or-update a batch of daily aggregates. Called by
    /// `HealthKitAggregator` after it computes the rollup on-device.
    func upsert(_ rows: [HealthDay]) async throws {
        guard !rows.isEmpty else { return }
        let userId = try await client.auth.session.user.id

        struct Row: Encodable {
            let user_id: UUID
            let day: String
            let steps: Int?
            let sleep_minutes: Int?
            let resting_hr_bpm: Double?
            let hrv_ms: Double?
            let weight_kg: Double?
            let active_energy_kcal: Int?
            let workout_minutes: Int?
            let tier: Int
            let synced_at: String
        }

        let now = SupabaseDates.iso(Date())
        let payload = rows.map {
            Row(
                user_id: userId,
                day: SupabaseDates.localDay($0.day),
                steps: $0.steps,
                sleep_minutes: $0.sleepMinutes,
                resting_hr_bpm: $0.restingHrBpm,
                hrv_ms: $0.hrvMs,
                weight_kg: $0.weightKg,
                active_energy_kcal: $0.activeEnergyKcal,
                workout_minutes: $0.workoutMinutes,
                tier: $0.tier,
                synced_at: now
            )
        }

        _ = try await client
            .from("health_days")
            .upsert(payload, onConflict: "user_id,day")
            .execute()
    }
}
