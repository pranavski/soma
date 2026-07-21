import Foundation
import Supabase

/// Read-only access to `public.insights` for the client. Writes come from
/// the `generate-insights` Edge Function via the service role.
struct InsightsRepository {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
    }

    /// The most recent insight, if any. Nil is the intended "no-insights-yet"
    /// state — the copy contract says silence beats a hallucinated finding.
    func fetchLatest() async throws -> Insight? {
        let response = try await client
            .from("insights")
            .select("id,week_start,rule_id,tier,lookback_days,copy")
            .order("week_start", ascending: false)
            .limit(1)
            .execute()

        return try decoder.decode([Insight].self, from: response.data).first
    }

    /// Recent history, most recent first. Insights view uses this to
    /// render a small "prior weeks" strip once the user has more than one.
    func fetchRecent(limit: Int = 8) async throws -> [Insight] {
        let response = try await client
            .from("insights")
            .select("id,week_start,rule_id,tier,lookback_days,copy")
            .order("week_start", ascending: false)
            .limit(limit)
            .execute()

        return try decoder.decode([Insight].self, from: response.data)
    }
}
