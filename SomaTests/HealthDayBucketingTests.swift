import XCTest
@testable import Soma

/// The aggregation rules `HealthKitAggregator` applies before anything is
/// upserted. These are the parts with real ways to be wrong — which day a
/// midnight-crossing session lands on, and whether an empty day gets a row
/// that would blank out an earlier good sync — and they run without an
/// `HKHealthStore`, so they're testable on any device or simulator.
final class HealthDayBucketingTests: XCTestCase {

    /// Fixed calendar: a floating time zone would move every midnight and
    /// make the boundary cases meaningless.
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: day, hour: hour, minute: minute
        ))!
    }

    private func startOfDay(_ day: Int) -> Date {
        calendar.startOfDay(for: date(day, 12))
    }

    // MARK: - Session bucketing

    func testSessionCountsTowardTheDayItStarted() {
        // Asleep 23:00 Aug 3 → 07:00 Aug 4: eight hours, all on Aug 3.
        let sessions = [HealthDayBucketing.Session(start: date(3, 23), end: date(4, 7))]

        let minutes = HealthDayBucketing.minutesByStartDay(sessions, calendar: calendar)

        XCTAssertEqual(minutes[startOfDay(3)], 480)
        XCTAssertNil(minutes[startOfDay(4)], "the night belongs to the day it started, not the day it ended")
    }

    func testSessionsOnTheSameDayAreSummed() {
        let sessions = [
            HealthDayBucketing.Session(start: date(3, 13), end: date(3, 13, 45)),
            HealthDayBucketing.Session(start: date(3, 19), end: date(3, 19, 30))
        ]

        let minutes = HealthDayBucketing.minutesByStartDay(sessions, calendar: calendar)

        XCTAssertEqual(minutes[startOfDay(3)], 75)
    }

    func testZeroLengthSessionsLeaveTheDayAbsentRatherThanZero() {
        let sessions = [HealthDayBucketing.Session(start: date(3, 22), end: date(3, 22))]

        let minutes = HealthDayBucketing.minutesByStartDay(sessions, calendar: calendar)

        XCTAssertTrue(minutes.isEmpty, "a 0 would read as “slept no minutes”; absent reads as “no data”")
    }

    func testWorkoutUsesDurationNotWallClockSpan() {
        // A 90-minute wall-clock window with 30 minutes paused: HealthKit's
        // duration is the honest number.
        let session = HealthDayBucketing.Session(start: date(3, 9), duration: 60 * 60)

        let minutes = HealthDayBucketing.minutesByStartDay([session], calendar: calendar)

        XCTAssertEqual(minutes[startOfDay(3)], 60)
    }

    func testSessionMinutesTruncateRatherThanRound() {
        let session = HealthDayBucketing.Session(start: date(3, 9), end: date(3, 9, 59))

        let minutes = HealthDayBucketing.minutesByStartDay([session], calendar: calendar)

        XCTAssertEqual(minutes[startOfDay(3)], 59)
    }

    // MARK: - Row assembly

    func testDaysWithNoSignalAtAllAreSkipped() {
        let rows = HealthDayBucketing.rows(
            from: startOfDay(1),
            through: startOfDay(3),
            calendar: calendar,
            steps: [startOfDay(1): 8000, startOfDay(3): 6000]
        )

        XCTAssertEqual(rows.map(\.day), [startOfDay(1), startOfDay(3)],
                       "Aug 2 has nothing; writing an all-nil row would blank an earlier sync")
    }

    func testASingleSignalIsEnoughToEarnARow() {
        let rows = HealthDayBucketing.rows(
            from: startOfDay(1),
            through: startOfDay(1),
            calendar: calendar,
            weightKg: [startOfDay(1): 71.2]
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.weightKg, 71.2)
        XCTAssertNil(rows.first?.steps)
        XCTAssertEqual(rows.first?.tier, 0, "weight alone doesn't earn a tier")
    }

    func testRowsCarryTheTierImpliedByWhatIsPresent() {
        let day = startOfDay(1)

        let rows = HealthDayBucketing.rows(
            from: day, through: day, calendar: calendar,
            steps: [day: 9000],
            sleepMinutes: [day: 430],
            restingHr: [day: 58.0]
        )

        XCTAssertEqual(rows.first?.tier, 2)
    }

    func testRowsAreOrderedOldestFirstAndCoverTheWholeWindow() {
        var steps: [Date: Int] = [:]
        for day in 1...5 { steps[startOfDay(day)] = day * 1000 }

        let rows = HealthDayBucketing.rows(
            from: startOfDay(1), through: startOfDay(5),
            calendar: calendar, steps: steps
        )

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.steps), [1000, 2000, 3000, 4000, 5000])
    }

    func testWindowEndsAreInclusive() {
        let rows = HealthDayBucketing.rows(
            from: startOfDay(2), through: startOfDay(2),
            calendar: calendar, steps: [startOfDay(2): 100]
        )

        XCTAssertEqual(rows.count, 1, "a one-day window still yields that day")
    }

    func testMidWindowTimestampsAreNormalizedToTheStartOfTheirDay() {
        // The aggregator anchors on start-of-day, but nothing stops a caller
        // passing an afternoon Date — the window shouldn't silently shrink.
        let rows = HealthDayBucketing.rows(
            from: date(1, 15), through: date(3, 9),
            calendar: calendar,
            steps: [startOfDay(1): 100, startOfDay(2): 200, startOfDay(3): 300]
        )

        XCTAssertEqual(rows.count, 3)
    }

    // MARK: - Window contract

    func testSyncWindowMatchesTheInsightEngineWindow() {
        // generate-insights scores a 30-day window (WINDOW_DAYS in
        // index.ts). Syncing fewer days leaves the oldest days of a fresh
        // connection permanently empty.
        XCTAssertEqual(HealthKitAggregator.windowDays, 30)
    }
}
