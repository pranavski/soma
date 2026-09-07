import Foundation
import Supabase
import UIKit

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var meals: [Meal] = []
    /// Yesterday's cards, for the wax-paper compare. Best-effort like the
    /// repeat chips — an empty list just hides the "compare" pill.
    @Published private(set) var mealsYesterday: [Meal] = []
    @Published private(set) var recentDishes: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// True when there's no daily_checkin for today yet — surfaces the
    /// "quiet check" nudge on Today.
    @Published private(set) var needsCheckin: Bool = false

    /// The clock the Today screen renders against. Refreshed whenever the
    /// screen reloads so a phone left open overnight rolls the header, the
    /// phase headline and the "now —" slot over to the new day instead of
    /// showing yesterday's date forever.
    @Published private(set) var now: Date = Date()

    private let repository: MealsRepository
    private let checkins: DailyCheckinsRepository
    /// Insert + parse for every meal this screen files. Shared with History,
    /// which files the same meals against a day you pick.
    private let logger: MealLogger

    init(
        repository: MealsRepository = MealsRepository(),
        checkins: DailyCheckinsRepository = DailyCheckinsRepository(),
        client: SupabaseClient = .shared,
        // Resolved in the body rather than as a default: AIDisclosure is
        // @MainActor, and default arguments are evaluated at the call site,
        // which isn't.
        disclosure: AIDisclosure? = nil
    ) {
        self.repository = repository
        self.checkins = checkins
        self.logger = MealLogger(
            repository: repository,
            client: client,
            disclosure: disclosure
        )
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" {
            self.meals = SampleData.logged
            self.mealsYesterday = SampleData.loggedYesterday
        }
        #endif
    }

    /// True in screenshot mode, where `load()` must not replace the sample
    /// data with a real (empty) fetch.
    private static var isPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1"
        #else
        return false
        #endif
    }

    func load() async {
        // Screenshot mode keeps its sample cards; a real fetch would replace
        // them with an empty day.
        guard !Self.isPreview else { return }
        // Only show the loading flash on a cold load; refreshes happen quietly.
        if meals.isEmpty {
            isLoading = true
        }
        now = Date()
        errorText = nil
        do {
            meals = try await repository.fetchToday()
        } catch {
            errorText = error.localizedDescription
        }
        // Recent dishes, yesterday's cards and check-in status are
        // best-effort — a failure here shouldn't blank the Today screen.
        recentDishes = (try? await repository.fetchRecentDishNames(limit: 5)) ?? []
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) {
            mealsYesterday = (try? await repository.fetchToday(on: yesterday)) ?? []
        }
        do {
            let existing = try await checkins.fetch(on: Date())
            needsCheckin = existing == nil
        } catch {
            // Any error (network, missing table on first-ever launch) — hide
            // the nudge rather than nag.
            needsCheckin = false
        }
        isLoading = false
    }

    /// One-tap repeat of a prior dish. Inserts a `source='repeat'` row
    /// carrying the previous parse; no Edge Function round-trip.
    ///
    /// `eatenAt` is usually now — the capture sheet can hand back an earlier
    /// time when the meal is being written up after the fact.
    func repeatDish(_ dish: String, eatenAt: Date = Date()) async {
        errorText = nil
        do {
            _ = try await logger.repeatDish(dish, eatenAt: eatenAt)
        } catch {
            errorText = error.localizedDescription
            return
        }
        await load()
        errorText = compose(nil, eatenAt)
    }

    /// Take a meal off the record. Optimistic: the card leaves the screen
    /// on confirm and only comes back if the delete failed, because the
    /// person has already said twice that it shouldn't be there.
    ///
    /// The reload afterwards isn't redundant — dropping the only row that
    /// carried a dish name also drops it from the repeat chips.
    func delete(_ meal: Meal) async {
        errorText = nil
        let previous = meals
        meals.removeAll { $0.id == meal.id }

        do {
            try await repository.deleteMeal(meal)
        } catch {
            meals = previous
            errorText = "couldn't take that one off the record — try again?"
            return
        }

        await load()
    }

    /// Insert a pending meal, kick off the Edge Function, then refresh so the
    /// row reappears with whatever parse_status the function landed on.
    /// The card renders "parsing…" while we wait — see `Meal.displayName`.
    ///
    /// `eatenAt` is when the food happened, not when it was written down —
    /// the capture sheet's "when" control can put it earlier today, or on an
    /// earlier day entirely.
    func submit(
        transcript: String,
        source: Meal.Source = .voice,
        eatenAt: Date = Date()
    ) async {
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

        // Only a parse can have changed the row we just loaded.
        if receipt.parseAttempted { await load() }
        // After the reload, not before — `load()` clears errorText, so a note
        // set ahead of it would flash and vanish.
        errorText = compose(receipt.note, eatenAt)
    }

    /// What to leave on screen after a meal is filed.
    ///
    /// This screen only ever shows today, so a meal put on an earlier day is
    /// saved and gone from view in the same breath. Saying where it went is
    /// the difference between "it worked" and "did that just vanish?".
    private func compose(_ note: String?, _ eatenAt: Date) -> String? {
        var parts: [String] = []
        if let note { parts.append(note) }
        if !Calendar.current.isDateInToday(eatenAt) {
            parts.append("filed on \(SomaFormat.longDay(eatenAt)) — it's in the ledger.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
