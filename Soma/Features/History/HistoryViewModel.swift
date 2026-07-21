import Foundation
import Supabase

/// Loads meals for a given month and lets the view drill into one day.
///
/// The month strip shows a small glyph per logged day (one per meal's dish
/// picks a glyph); tapping a day loads that day's meals in order.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var monthMeals: [Meal] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// Anchor date: use `Calendar.current.component(.month, from: anchor)` for
    /// the visible month label. Defaults to today.
    @Published var anchor: Date = Date()

    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
    }

    /// Fetch all meals whose `eaten_at` falls in the month containing
    /// `anchor`. Ordered ascending so the view can group by day in-place.
    func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: anchor)
        guard let start = cal.date(from: comps),
              let end = cal.date(byAdding: .month, value: 1, to: start) else {
            monthMeals = []
            return
        }

        do {
            let response = try await client
                .from("meals")
                .select()
                .gte("eaten_at", value: SupabaseDates.iso(start))
                .lt("eaten_at",  value: SupabaseDates.iso(end))
                .order("eaten_at", ascending: true)
                .execute()
            monthMeals = try decoder.decode([Meal].self, from: response.data)
        } catch {
            errorText = error.localizedDescription
            monthMeals = []
        }
    }

    // MARK: - Paging

    /// True while the anchor month is before the current month — we never
    /// page into the future.
    var canPageForward: Bool {
        Calendar.current.compare(anchor, to: Date(), toGranularity: .month) == .orderedAscending
    }

    func page(by months: Int) async {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: months, to: anchor) else { return }
        if months > 0,
           cal.compare(next, to: Date(), toGranularity: .month) == .orderedDescending {
            return
        }
        anchor = next
        await load()
    }

    // MARK: - Derived views

    var monthTitle: String {
        let cal = Calendar.current
        let f = DateFormatter()
        let sameYear = cal.component(.year, from: anchor) == cal.component(.year, from: Date())
        f.dateFormat = sameYear ? "MMMM" : "MMMM yyyy"
        return f.string(from: anchor)
    }

    var daysInMonth: Int {
        let cal = Calendar.current
        return cal.range(of: .day, in: .month, for: anchor)?.count ?? 30
    }

    /// Map of day-of-month → glyph, one per day that has any meal logged.
    /// The glyph chosen is the earliest meal's — arbitrary but stable.
    var glyphByDay: [Int: FoodGlyph] {
        let cal = Calendar.current
        var out: [Int: FoodGlyph] = [:]
        for m in monthMeals {
            let day = cal.component(.day, from: m.eatenAt)
            if out[day] == nil {
                out[day] = FoodGlyph.from(m.displayName)
            }
        }
        return out
    }

    /// Meals on a specific day-of-month (within the current anchor month).
    func meals(onDayOfMonth day: Int) -> [Meal] {
        let cal = Calendar.current
        return monthMeals.filter { cal.component(.day, from: $0.eatenAt) == day }
    }
}
