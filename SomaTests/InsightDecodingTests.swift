import XCTest
@testable import Soma

/// The Insight decoder is the contract between the `generate-insights`
/// Edge Function's rows and the Insights UI. Exercise the exact wire shape:
/// snake_case columns, the confidence enum, and nullable suggested_action.
final class InsightDecodingTests: XCTestCase {
    private let decoder = SupabaseDates.makeDecoder()

    func testDecodesFullRow() throws {
        let json = """
        {
            "id": "6F1E4B0A-3C5D-4E2F-9A8B-1C2D3E4F5A6B",
            "created_at": "2026-07-18T09:30:00.000Z",
            "claim": "On days you walk more, you tend to sleep a bit longer.",
            "evidence": "Across 21 days, sleep averaged 26 more minutes on your 8k+ step days.",
            "confidence": "medium",
            "suggested_action": "Worth keeping an eye on your step count this week.",
            "window_days": 28
        }
        """
        let insight = try decoder.decode(Insight.self, from: Data(json.utf8))

        XCTAssertEqual(insight.id, UUID(uuidString: "6F1E4B0A-3C5D-4E2F-9A8B-1C2D3E4F5A6B"))
        XCTAssertEqual(insight.createdAt, SupabaseDates.withFractional.date(from: "2026-07-18T09:30:00.000Z"))
        XCTAssertEqual(insight.confidence, .medium)
        XCTAssertEqual(insight.suggestedAction, "Worth keeping an eye on your step count this week.")
        XCTAssertEqual(insight.windowDays, 28)
    }

    func testDecodesNullSuggestedAction() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "created_at": "2026-07-18T09:30:00Z",
            "claim": "claim",
            "evidence": "evidence",
            "confidence": "low",
            "suggested_action": null,
            "window_days": 14
        }
        """
        let insight = try decoder.decode(Insight.self, from: Data(json.utf8))
        XCTAssertNil(insight.suggestedAction)
        XCTAssertEqual(insight.confidence, .low)
    }

    func testUnknownConfidenceFailsLoudly() {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "created_at": "2026-07-18T09:30:00Z",
            "claim": "claim",
            "evidence": "evidence",
            "confidence": "certain",
            "suggested_action": null,
            "window_days": 28
        }
        """
        XCTAssertThrowsError(try decoder.decode(Insight.self, from: Data(json.utf8)))
    }

    func testConfidenceOrdering() {
        XCTAssertLessThan(Insight.Confidence.low, .medium)
        XCTAssertLessThan(Insight.Confidence.medium, .high)
        XCTAssertEqual([Insight.Confidence.high, .low, .medium].sorted(), [.low, .medium, .high])
    }

    func testHedgeCaptionIsInvariant() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000003",
            "created_at": "2026-07-18T09:30:00Z",
            "claim": "claim",
            "evidence": "evidence",
            "confidence": "high",
            "suggested_action": null,
            "window_days": 28
        }
        """
        let insight = try decoder.decode(Insight.self, from: Data(json.utf8))
        XCTAssertEqual(insight.hedgeCaption, "worth watching, not a verdict")
    }
}
