import Foundation

/// When a meal is allowed to have happened, and where a fresh entry starts.
///
/// A meal card is a record of something that already happened, so the
/// window has two edges. It never reaches into the future — nothing has
/// been eaten yet — and it never reaches further back than the insight
/// engine's 30-day view, since a meal older than that can't change
/// anything soma notices. Past that edge the ledger stops offering to
/// file one rather than inviting an archive-filling exercise.
///
/// Deliberately the same distance as `DailyCheckinViewModel.maxLookbackDays`:
/// the two halves of a day's record — what you ate, how the day went —
/// should reach back equally far.
enum MealEntryWindow {
    static let maxLookbackDays = 30

    /// The oldest instant a meal can carry: start of the 30th day back.
    static func earliest(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -maxLookbackDays, to: today) ?? today
    }

    /// The whole span a "when" control may offer. `now` is the upper bound,
    /// not end-of-today — you can't file a meal you haven't eaten yet.
    static func range(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date> {
        let low = earliest(now: now, calendar: calendar)
        return low...max(low, now)
    }

    /// Can a meal be filed at this exact instant?
    static func isLoggable(_ when: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        range(now: now, calendar: calendar).contains(when)
    }

    /// Can any meal still be filed on this calendar day? What History asks
    /// before offering the "plate something" row — today counts even though
    /// most of its hours are still in the future.
    static func isLoggableDay(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        return target >= earliest(now: now, calendar: calendar)
            && target <= calendar.startOfDay(for: now)
    }

    /// Where the capture sheet's "when" starts for a given day. Today opens
    /// at the current minute — the 10-second path stays a straight line.
    /// A past day opens at midday: a neutral placeholder that reads as
    /// "adjust me," rather than tonight's clock time silently landing on a
    /// day it has nothing to do with. The hour matters — the insight rules
    /// read `eaten_hour` — so the sheet also says so out loud when the day
    /// isn't today.
    static func defaultWhen(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let noon = calendar.date(
            bySettingHour: 12, minute: 0, second: 0,
            of: calendar.startOfDay(for: day)
        ) ?? calendar.startOfDay(for: day)
        return clamp(noon, now: now, calendar: calendar)
    }

    /// Pull a "when" back inside the window — used when a day change would
    /// otherwise push the entry past `now`.
    static func clamp(_ when: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let span = range(now: now, calendar: calendar)
        return min(max(when, span.lowerBound), span.upperBound)
    }

    /// The ticket stamp for a chosen "when" — "9:55 PM" for today, and the
    /// day spelled out as soon as it isn't, so a backdated entry can never
    /// be sent without the sheet having said which day it lands on.
    static func stamp(for when: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = SomaFormat.time(when).uppercased()
        guard !calendar.isDate(when, inSameDayAs: now) else { return time }
        return "\(SomaFormat.shortStamp(when)) · \(time)"
    }
}
