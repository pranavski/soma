import XCTest
@testable import Soma

/// A meal can be filed onto a day other than today — from the capture
/// sheet's "when" control, or from History's day card. The window that
/// allows is the whole feature's contract: never the future, never past
/// the edge of what the insight engine can see. Both entry points read
/// this rule, so it's asserted directly rather than through either screen.
final class MealEntryWindowTests: XCTestCase {
    private let cal = Calendar.current
    /// A fixed "now" with a clock time in it — several of these assertions
    /// are exactly about the difference between an instant and a day.
    private lazy var now: Date = cal.date(
        bySettingHour: 21, minute: 30, second: 0, of: Date()
    ) ?? Date()

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    // MARK: - The instant-level window

    func testNowIsLoggable() {
        XCTAssertTrue(MealEntryWindow.isLoggable(now, now: now))
    }

    func testEarlierTodayIsLoggable() {
        let lunch = cal.date(bySettingHour: 13, minute: 0, second: 0, of: now)!
        XCTAssertTrue(MealEntryWindow.isLoggable(lunch, now: now))
    }

    /// Later tonight hasn't been eaten yet — the picker's upper bound is
    /// `now`, not end-of-today.
    func testLaterTodayIsNotLoggable() {
        let future = now.addingTimeInterval(60 * 60)
        XCTAssertFalse(MealEntryWindow.isLoggable(future, now: now),
                       "a meal can't be filed before it's been eaten")
    }

    func testTomorrowIsNotLoggable() {
        XCTAssertFalse(MealEntryWindow.isLoggable(day(1), now: now))
    }

    /// The far edge is inclusive: the 30th day back is still reachable, the
    /// 31st isn't. An off-by-one here silently costs the user a day.
    func testWindowEdgeIsInclusive() {
        let edge = MealEntryWindow.maxLookbackDays
        XCTAssertTrue(MealEntryWindow.isLoggableDay(day(-edge), now: now))
        XCTAssertFalse(MealEntryWindow.isLoggableDay(day(-(edge + 1)), now: now))
    }

    /// Same distance back as the check-in sheet reaches. The two halves of
    /// a day's record — what you ate, how the day went — have to agree, or
    /// History offers to fill in one and not the other.
    func testMatchesTheCheckinWindow() {
        XCTAssertEqual(MealEntryWindow.maxLookbackDays,
                       DailyCheckinViewModel.maxLookbackDays)
    }

    // MARK: - Day-level window

    /// Today counts as loggable even though most of its hours are still
    /// ahead — History's row would otherwise disappear every morning.
    func testTodayIsALoggableDay() {
        XCTAssertTrue(MealEntryWindow.isLoggableDay(now, now: now))
    }

    func testFutureDayIsNotLoggable() {
        XCTAssertFalse(MealEntryWindow.isLoggableDay(day(1), now: now))
    }

    // MARK: - Where a fresh entry starts

    func testTodayOpensAtNow() {
        XCTAssertEqual(MealEntryWindow.defaultWhen(on: now, now: now), now)
    }

    /// A past day opens at midday, not at tonight's clock time — the hour
    /// is data the insight rules read, so a default that silently borrows
    /// "now" would put 9:30pm on a day it has nothing to do with.
    func testPastDayOpensAtMidday() {
        let when = MealEntryWindow.defaultWhen(on: day(-3), now: now)
        XCTAssertEqual(cal.component(.hour, from: when), 12)
        XCTAssertEqual(cal.component(.minute, from: when), 0)
        XCTAssertTrue(cal.isDate(when, inSameDayAs: day(-3)))
    }

    /// Clamping is the guard behind a sheet left open across a minute
    /// boundary, or a day-picker landing on today with a stale time.
    func testClampPullsTheFutureBackToNow() {
        let future = now.addingTimeInterval(3600)
        XCTAssertEqual(MealEntryWindow.clamp(future, now: now), now)
    }

    func testClampLeavesAnInsideValueAlone() {
        let lunch = cal.date(bySettingHour: 13, minute: 0, second: 0, of: now)!
        XCTAssertEqual(MealEntryWindow.clamp(lunch, now: now), lunch)
    }

    func testClampPushesTooOldForwardToTheEdge() {
        let ancient = day(-90)
        XCTAssertEqual(MealEntryWindow.clamp(ancient, now: now),
                       MealEntryWindow.earliest(now: now))
    }

    // MARK: - The ticket stamp

    /// Today's stamp is the time alone — the ORDER UP ticket doesn't need
    /// to spell out the day you're standing in.
    func testStampForTodayIsTimeOnly() {
        let stamp = MealEntryWindow.stamp(for: now, now: now)
        XCTAssertFalse(stamp.contains("·"),
                       "today's stamp carries no day segment: \(stamp)")
    }

    /// A backdated entry can never be sent without the sheet having said
    /// which day it lands on.
    func testStampNamesTheDayWhenBackdated() {
        let when = MealEntryWindow.defaultWhen(on: day(-2), now: now)
        let stamp = MealEntryWindow.stamp(for: when, now: now)
        XCTAssertTrue(stamp.contains(SomaFormat.shortStamp(when)),
                      "backdated stamp must name the day: \(stamp)")
    }
}
