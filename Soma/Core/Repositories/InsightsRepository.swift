import Foundation
import Supabase

/// Read access to `public.insights` plus the on-demand generation trigger.
/// Rows are written only by the `generate-insights` Edge Function; the
/// client never inserts insights directly.
struct InsightsRepository {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
    }

    /// Recent history, most recent first. Empty is the intended
    /// "no-insights-yet" state — silence beats a hallucinated finding.
    func fetchRecent(limit: Int = 20) async throws -> [Insight] {
        let response = try await client
            .from("insights")
            // The evidence trio rides along: without it every row decodes
            // with a nil mechanism and the published-context block silently
            // never renders, however much science the row actually carries.
            .select("id,created_at,claim,evidence,confidence,suggested_action,window_days,mechanism,evidence_citation,evidence_grade")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        return try decoder.decode([Insight].self, from: response.data)
    }

    /// Ask the Edge Function to generate insights for the caller now.
    /// The function reads the user from the JWT; the body is intentionally
    /// empty. New rows land in `insights` — refetch to see them.
    func requestGeneration() async throws {
        try await client.functions.invoke(
            "generate-insights",
            options: FunctionInvokeOptions(body: [String: String]())
        )
    }
}
