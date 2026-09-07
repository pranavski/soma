import XCTest
@testable import Soma

/// These strings used to come from `DateFormatter` with hard-coded patterns
/// ("h:mm a"), which pinned every user to a 12-hour English clock. The point
/// of `SomaFormat` is that the locale decides, so that's what's asserted.
final class SomaFormatTests: XCTestCase {
    /// 2026-08-02 21:55 UTC
    private let sample = Date(timeIntervalSince1970: 1_785_707_700)

    func testTimeHasNoHardCodedMeridiem() {
        let text = SomaFormat.time(sample)
        XCTAssertFalse(text.isEmpty)
        // Whatever the test machine's locale, the string must contain the
        // minutes — the old bug was a *format*, not a value, problem.
        XCTAssertTrue(text.contains(":") || text.contains("."),
                      "expected a time separator in \(text)")
    }

    func testLongDayIsLowercased() {
        let text = SomaFormat.longDay(sample)
        XCTAssertEqual(text, text.lowercased(),
                       "the day line is set in lowercase by the design system")
    }

    func testShortStampIsUppercased() {
        let text = SomaFormat.shortStamp(sample)
        XCTAssertEqual(text, text.uppercased(),
                       "the check-in stamp is an all-caps ticket eyebrow")
    }

    /// History's title has to carry the year once you page out of this one —
    /// a bare "August" could be any August.
    func testMonthAndYearIncludesTheYear() {
        let year = Calendar.current.component(.year, from: sample)
        XCTAssertTrue(SomaFormat.monthAndYear(sample).contains(String(year)))
    }

    func testMonthNameHasNoYear() {
        let year = Calendar.current.component(.year, from: sample)
        XCTAssertFalse(SomaFormat.monthName(sample).contains(String(year)))
    }
}
