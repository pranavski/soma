import XCTest
@testable import Soma

final class SupabaseDatesTests: XCTestCase {
    // Local-day math is what pins the insight engine's per-user timezone
    // semantics. If localDay drifts, the "did you eat late yesterday" rule
    // will misalign the check-in and the meal.

    func testLocalDayFormat() {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 4
        comps.hour = 22
        comps.minute = 15
        comps.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let date = cal.date(from: comps)!
        var laCal = cal
        laCal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(SupabaseDates.localDay(date, calendar: laCal), "2026-07-04")
    }

    func testDecoderAcceptsBothFractionalAndPlain() throws {
        let d = SupabaseDates.makeDecoder()
        // The date-decoder is a value strategy, not a top-level decoder, so
        // wrap the timestamps as a single string field to exercise it.
        struct Row: Decodable { let t: Date }
        let a = try d.decode(Row.self, from: #"{"t":"2026-07-01T12:30:00.000Z"}"#.data(using: .utf8)!)
        let b = try d.decode(Row.self, from: #"{"t":"2026-07-01T12:30:00Z"}"#.data(using: .utf8)!)
        XCTAssertEqual(a.t, b.t)
    }
}
