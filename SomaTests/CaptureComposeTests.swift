import XCTest
@testable import Soma

/// The "where" field folds into the transcript as the words the person
/// would otherwise have said, so parse-meal's venue gate reads a typed place
/// and a spoken one identically.
@MainActor
final class CaptureComposeTests: XCTestCase {
    func testPlaceIsFoldedIntoTranscript() {
        XCTAssertEqual(
            CaptureSheet.compose("grilled cheese", from: "starbucks"),
            "grilled cheese, from starbucks"
        )
    }

    func testEmptyPlaceLeavesTranscriptAlone() {
        XCTAssertEqual(CaptureSheet.compose("grilled cheese", from: ""), "grilled cheese")
        XCTAssertEqual(CaptureSheet.compose("grilled cheese", from: "   "), "grilled cheese")
    }

    func testWhitespaceIsTrimmedOnBothSides() {
        XCTAssertEqual(
            CaptureSheet.compose("  double-double \n", from: " in n out "),
            "double-double, from in n out"
        )
    }

    /// A place with no meal is not a meal; the send button is disabled on
    /// empty text and compose must not manufacture one.
    func testPlaceAloneIsNotAMeal() {
        XCTAssertEqual(CaptureSheet.compose("", from: "starbucks"), "")
    }
}
