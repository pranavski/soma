import XCTest
@testable import Soma

/// Round-trip coverage for the three columns added for the insight-engine
/// pivot (weight_kg, active_energy_kcal, workout_minutes) — the decoder is
/// what keeps the client's HealthDay aligned with `public.health_days`.
final class HealthDayCodingTests: XCTestCase {
    func testDecodesRowWithNewColumns() throws {
        let json = """
        {
            "day": "2026-07-18",
            "steps": 9200,
            "sleep_minutes": 431,
            "resting_hr_bpm": 57.5,
            "hrv_ms": 44.0,
            "weight_kg": 72.4,
            "active_energy_kcal": 612,
            "workout_minutes": 45,
            "tier": 2
        }
        """
        let day = try SupabaseDates.makeDecoder().decode(HealthDay.self, from: Data(json.utf8))

        XCTAssertEqual(day.weightKg, 72.4)
        XCTAssertEqual(day.activeEnergyKcal, 612)
        XCTAssertEqual(day.workoutMinutes, 45)
        XCTAssertEqual(day.tier, 2)
    }

    func testDecodesNullNewColumnsAsNil() throws {
        let json = """
        {
            "day": "2026-07-18",
            "steps": 9200,
            "sleep_minutes": 431,
            "resting_hr_bpm": null,
            "hrv_ms": null,
            "weight_kg": null,
            "active_energy_kcal": null,
            "workout_minutes": null,
            "tier": 1
        }
        """
        let day = try SupabaseDates.makeDecoder().decode(HealthDay.self, from: Data(json.utf8))

        XCTAssertNil(day.weightKg)
        XCTAssertNil(day.activeEnergyKcal)
        XCTAssertNil(day.workoutMinutes)
    }

    func testNewFieldsRoundTrip() throws {
        let original = HealthDay(
            day: Date(timeIntervalSince1970: 1_784_500_000),
            steps: 10_500,
            sleepMinutes: 402,
            restingHrBpm: 55.0,
            hrvMs: 51.2,
            weightKg: 71.8,
            activeEnergyKcal: 540,
            workoutMinutes: 30,
            tier: 2
        )
        // Default Date strategies match on both sides, so the snake_case
        // CodingKeys are the only mapping under test here.
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthDay.self, from: data)

        XCTAssertEqual(decoded, original)

        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(keys["weight_kg"])
        XCTAssertNotNil(keys["active_energy_kcal"])
        XCTAssertNotNil(keys["workout_minutes"])
    }
}
