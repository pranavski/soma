import Foundation
import Supabase
import UIKit

/// Loads meals for a given month and lets the view drill into one day.
///
/// The month strip shows a small glyph per logged day (one per meal's dish
/// picks a glyph); tapping a day loads that day's meals in order.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var monthMeals: [Meal] = []
    /// The visible month's check-ins, so each day card can show how the day
    /// felt — or offer to fill it in when it was missed.
    @Published private(set) var monthCheckins: [DailyCheckin] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// Anchor date: use `Calendar.current.component(.month, from: anchor)` for
    /// the visible month label. Defaults to today.
    @Published var anchor: Date = Date()

    /// Month of the user's very first logged meal — the floor for paging
    /// back. Nil until the first load, or when there are no meals at all.
    @Published private(set) var earliestMonth: Date?

    /// Recent dish names, for the capture sheet's "a familiar one" chips —
    /// filling in a day you missed is usually a day of familiar meals.
    @Published private(set) var recentDishes: [String] = []

    private let client: SupabaseClient
    private let decoder: JSONDecoder
    /// Reads here are month-shaped and stay inline; writes go through the
    /// repository so Today and History delete a meal the same way.
    private let repository: MealsRepository
    private let checkins: DailyCheckinsRepository
    /// The same insert-then-parse path Today uses — a meal filed onto an
    /// earlier day is an ordinary meal, not a second kind of row.
    private let logger: MealLogger

    init(client: SupabaseClient = .shared) {
        let repository = MealsRepository(client: client)
        self.client = client
        self.decoder = SupabaseDates.makeDecoder()
        self.repository = repository
        self.checkins = DailyCheckinsRepository(client: client)
        self.logger = MealLogger(repository: repository, client: client)
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

        // Best-effort: a check-in read that fails shouldn't blank the month's
        // meals, it just leaves every day card reading "no check filed".
        monthCheckins = (try? await checkins.fetch(
            from: start,
            through: cal.date(byAdding: .day, value: -1, to: end) ?? start
        )) ?? []

        // Best-effort like the check-ins: the chips are a convenience, and
        // a failed read shouldn't cost the month its cards.
        recentDishes = (try? await repository.fetchRecentDishNames(limit: 5)) ?? recentDishes

        if earliestMonth == nil {
            await loadEarliestMonth()
        }
    }

    /// Re-read just the check-ins for the visible month. Called after the
    /// check-in sheet saves, so the day card updates without re-fetching
    /// every meal in the month.
    func reloadCheckins() async {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: anchor)),
              let end = cal.date(byAdding: .month, value: 1, to: start),
              let last = cal.date(byAdding: .day, value: -1, to: end) else { return }
        monthCheckins = (try? await checkins.fetch(from: start, through: last)) ?? monthCheckins
    }

    /// One cheap query for the oldest meal, so the back chevron can stop at
    /// the start of the record instead of walking backwards forever through
    /// empty months.
    private func loadEarliestMonth() async {
        struct Row: Decodable { let eaten_at: String }
        do {
            let response = try await client
                .from("meals")
                .select("eaten_at")
                .order("eaten_at", ascending: true)
                .limit(1)
                .execute()
            guard let first = try? decoder.decode([Row].self, from: response.data).first,
                  let date = SupabaseDates.date(from: first.eaten_at) else { return }
            let cal = Calendar.current
            earliestMonth = cal.date(from: cal.dateComponents([.year, .month], from: date))
        } catch {
            // Leave the floor unset — paging stays permissive rather than
            // wrongly locking the user out of their own history.
        }
    }

    /// Take a meal off the record from the index. Optimistic like Today's
    /// — the card drops out of the month immediately and is put back only
    /// if the delete failed.
    ///
    /// No reload afterwards: `monthMeals` already reflects the removal, and
    /// re-fetching the month would flicker the whole ledger for one card.
    func delete(_ meal: Meal) async {
        errorText = nil
        let previous = monthMeals
        monthMeals.removeAll { $0.id == meal.id }

        do {
            try await repository.deleteMeal(meal)
        } catch {
            monthMeals = previous
            errorText = "couldn't take that one off the record — try again?"
        }
    }

    // MARK: - Filing a meal onto a day

    /// Put a meal on a day that already happened. Same path as Today's —
    /// insert the pending row, show it, then let `parse-meal` fill it in —
    /// with `eatenAt` carrying the day and time the ticket was filed for.
    ///
    /// The month reloads rather than the day: a new row changes the ledger's
    /// glyph strip too, and there's no cheaper query that keeps both honest.
    func log(transcript: String, source: Meal.Source, eatenAt: Date) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorText = nil

        let receipt: MealLogger.Receipt
        do {
            receipt = try await logger.log(
                transcript: trimmed,
                source: source,
                eatenAt: eatenAt,
                onInserted: { await self.load() }
            )
        } catch {
            errorText = error.localizedDescription
            return
        }

        // Only a parse can have changed the row we just loaded. The note is
        // set after, since `load()` clears it.
        if receipt.parseAttempted { await load() }
        errorText = receipt.note
    }

    /// "a familiar one," filed onto the chosen day.
    func repeatDish(_ dish: String, eatenAt: Date) async {
        errorText = nil
        do {
            _ = try await logger.repeatDish(dish, eatenAt: eatenAt)
        } catch {
            errorText = error.localizedDescription
            return
        }
        await load()
    }

    // MARK: - Paging

    /// True while the anchor month is before the current month — we never
    /// page into the future.
    var canPageForward: Bool {
        Calendar.current.compare(anchor, to: Date(), toGranularity: .month) == .orderedAscending
    }

    /// True while there's recorded history before the anchor month. With no
    /// meals logged at all the floor is unknown, so paging back stays open.
    var canPageBack: Bool {
        guard let earliestMonth else { return true }
        return Calendar.current.compare(anchor, to: earliestMonth, toGranularity: .month) == .orderedDescending
    }

    func page(by months: Int) async {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: months, to: anchor) else { return }
        if months > 0,
           cal.compare(next, to: Date(), toGranularity: .month) == .orderedDescending {
            return
        }
        if months < 0, let earliestMonth,
           cal.compare(next, to: earliestMonth, toGranularity: .month) == .orderedAscending {
            return
        }
        anchor = next
        await load()
    }

    // MARK: - Derived views

    var monthTitle: String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: anchor) == cal.component(.year, from: Date())
        return sameYear ? SomaFormat.monthName(anchor).capitalized
                        : SomaFormat.monthAndYear(anchor)
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

    /// The check-in filed for a day-of-month in the anchor month, if any.
    func checkin(onDayOfMonth day: Int) -> DailyCheckin? {
        let cal = Calendar.current
        return monthCheckins.first { cal.component(.day, from: $0.checkDate) == day }
    }

    /// The concrete date for a day-of-month in the anchor month — what the
    /// check-in sheet needs to know which day it's filling in.
    func date(forDayOfMonth day: Int) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: anchor)
        comps.day = day
        return cal.date(from: comps)
    }
}
