import XCTest
@testable import Soma

/// The check-in sheet can walk backwards to fill in a day that got missed.
/// The window it can reach is the whole feature's contract: never into the
/// future, never further back than the insight engine's 30-day view. Both
/// the sheet's stepper and History's per-day row read from the same rule,
/// so it's asserted directly rather than through either screen.
@MainActor
final class DailyCheckinWindowTests: XCTestCase {
    private let cal = Calendar.current

    private func day(offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: Date())!
    }

    func testTodayIsEditable() {
        XCTAssertTrue(DailyCheckinViewModel.isEditable(Date()))
    }

    func testYesterdayIsEditable() {
        XCTAssertTrue(DailyCheckinViewModel.isEditable(day(offset: -1)))
    }

    func testTomorrowIsNotEditable() {
        XCTAssertFalse(DailyCheckinViewModel.isEditable(day(offset: 1)),
                       "you can't report on a day that hasn't happened")
    }

    /// The far edge is inclusive: the 30th day back is still reachable, the
    /// 31st isn't. An off-by-one here silently costs the user a day.
    func testWindowEdgeIsInclusive() {
        let edge = DailyCheckinViewModel.maxLookbackDays
        XCTAssertTrue(DailyCheckinViewModel.isEditable(day(offset: -edge)))
        XCTAssertFalse(DailyCheckinViewModel.isEditable(day(offset: -(edge + 1))))
    }

    /// A time-of-day component must not decide the answer — the window is
    /// counted in local days, and `Date()` in the test carries a clock time.
    func testLaterInTheDayStillCountsAsTheSameDay() {
        let today = cal.startOfDay(for: Date())
        let lateToday = cal.date(byAdding: .hour, value: 23, to: today)!
        XCTAssertTrue(DailyCheckinViewModel.isEditable(today))
        XCTAssertTrue(DailyCheckinViewModel.isEditable(lateToday))
    }

    // MARK: - Stepper bounds

    func testStepperCannotLeaveTheWindow() {
        let onToday = DailyCheckinViewModel(day: Date())
        XCTAssertTrue(onToday.isToday)
        XCTAssertFalse(onToday.canStepForward, "today is the forward edge")
        XCTAssertTrue(onToday.canStepBack)

        let onFloor = DailyCheckinViewModel(
            day: day(offset: -DailyCheckinViewModel.maxLookbackDays)
        )
        XCTAssertFalse(onFloor.canStepBack, "the 30-day floor is the back edge")
        XCTAssertTrue(onFloor.canStepForward)
    }
}
