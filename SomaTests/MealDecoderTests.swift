import XCTest
@testable import Soma

/// The parse-meal Edge Function returns two shapes: success 200 (fields flat)
/// or 422 (fields nested under `fallback`). The iOS side only decodes the
/// `Meal` row it fetches from Postgres after the fact, but the calorie-range
/// contract lives on this type so the tests below pin the contract.
final class MealDecoderTests: XCTestCase {
    // MARK: - Calorie range (always a range, never a bare number)

    func testCalorieRangeIsRenderedWithBothEndpoints() {
        let meal = makeMeal(dishName: "eggs on sourdough", calLow: 320, calHigh: 420)
        XCTAssertEqual(meal.calorieRange, "~320–420")
    }

    func testCalorieRangeNilWhenEitherEndpointMissing() {
        XCTAssertNil(makeMeal(calLow: 320, calHigh: nil).calorieRange)
        XCTAssertNil(makeMeal(calLow: nil, calHigh: 420).calorieRange)
    }

    // MARK: - Display name state machine

    func testDisplayNameFallsBackToParseStatusWhenNoDishName() {
        XCTAssertEqual(makeMeal(dishName: nil, parseStatus: .pending).displayName, "parsing…")
        XCTAssertEqual(makeMeal(dishName: nil, parseStatus: .failed).displayName, "couldn't read that")
        XCTAssertEqual(makeMeal(dishName: nil, parseStatus: .parsed).displayName, "untitled")
    }

    func testDisplayNamePrefersDishNameWhenPresent() {
        let meal = makeMeal(dishName: "miso salmon", parseStatus: .parsed)
        XCTAssertEqual(meal.displayName, "miso salmon")
    }

    // MARK: - Row decoding (matches PostgREST default shape)

    func testDecodesRowFromPostgrest() throws {
        let json = """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "user_id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "eaten_at": "2026-07-01T12:30:00+00:00",
          "logged_at": "2026-07-01T12:31:00+00:00",
          "source": "voice",
          "dish_name": "lentil dal with rice",
          "calories_low": 520,
          "calories_high": 680,
          "protein_g_low": 22, "protein_g_high": 30,
          "carbs_g_low": 70, "carbs_g_high": 90,
          "fat_g_low": 8, "fat_g_high": 14,
          "fiber_g_low": 10, "fiber_g_high": 14,
          "notes": null,
          "photo_path": null,
          "voice_transcript": "lentil dal with rice",
          "parse_status": "parsed"
        }
        """.data(using: .utf8)!

        let decoder = SupabaseDates.makeDecoder()
        let meal = try decoder.decode(Meal.self, from: json)
        XCTAssertEqual(meal.dishName, "lentil dal with rice")
        XCTAssertEqual(meal.calorieRange, "~520–680")
        XCTAssertEqual(meal.macros.proteinRange, "~22–30g")
        XCTAssertEqual(meal.parseStatus, .parsed)
    }

    func testDecodesRowMissingFractionalSeconds() throws {
        // Older Postgres columns omit fractional seconds. The decoder has to
        // accept both — otherwise a fresh query pattern silently 500s on us.
        let json = """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "user_id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "eaten_at": "2026-07-01T12:30:00Z",
          "logged_at": "2026-07-01T12:31:00Z",
          "source": "voice",
          "dish_name": "eggs",
          "calories_low": 200,
          "calories_high": 300,
          "protein_g_low": null, "protein_g_high": null,
          "carbs_g_low": null, "carbs_g_high": null,
          "fat_g_low": null, "fat_g_high": null,
          "fiber_g_low": null, "fiber_g_high": null,
          "notes": null,
          "photo_path": null,
          "voice_transcript": null,
          "parse_status": "pending"
        }
        """.data(using: .utf8)!

        let decoder = SupabaseDates.makeDecoder()
        let meal = try decoder.decode(Meal.self, from: json)
        XCTAssertEqual(meal.parseStatus, .pending)
        XCTAssertNil(meal.macros.proteinRange)
        XCTAssertTrue(meal.macros.isEmpty)
    }

    func testRepeatSourceRoundtrips() throws {
        // `repeat` collides with a Swift keyword; the enum uses the raw
        // string "repeat" via `case repeated = "repeat"`. Regression guard.
        let json = "\"repeat\"".data(using: .utf8)!
        let source = try JSONDecoder().decode(Meal.Source.self, from: json)
        XCTAssertEqual(source, .repeated)
        let re = try JSONEncoder().encode(source)
        XCTAssertEqual(String(data: re, encoding: .utf8), "\"repeat\"")
    }

    // MARK: - Helpers

    private func makeMeal(
        dishName: String? = "eggs",
        calLow: Int? = nil,
        calHigh: Int? = nil,
        parseStatus: Meal.ParseStatus = .parsed
    ) -> Meal {
        Meal(
            id: UUID(),
            userId: UUID(),
            eatenAt: Date(),
            loggedAt: Date(),
            source: .voice,
            dishName: dishName,
            caloriesLow: calLow, caloriesHigh: calHigh,
            proteinLow: nil, proteinHigh: nil,
            carbsLow: nil, carbsHigh: nil,
            fatLow: nil, fatHigh: nil,
            fiberLow: nil, fiberHigh: nil,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: parseStatus
        )
    }
}
