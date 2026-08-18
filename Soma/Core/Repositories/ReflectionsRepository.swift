import Foundation
import Supabase

/// Read access to `public.reflections`. Rows are written only by the
/// `generate-insights` Edge Function — the same call that produces insights
/// rebuilds this set, so there is no separate generation trigger here.
struct ReflectionsRepository {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
    }

    /// The current set, in the order the server chose. Bounded server-side
    /// (`MAX_REFLECTIONS`), so there is no limit to pass.
    func fetchCurrent() async throws -> [Reflection] {
        let response = try await client
            .from("reflections")
            .select("kind,body,detail,sort_order,window_days")
            .order("sort_order", ascending: true)
            .execute()

        return try decoder.decode([Reflection].self, from: response.data)
    }
}
