import XCTest
@testable import Soma

/// Tier detection is the gate for which insight rules run. The rules are:
///   - tier 0 = no HealthKit (baseline)
///   - tier 1 = steps + sleep present
///   - tier 2 = steps + sleep + (RHR or HRV) present
/// If this drifts, `generate-insights` will silently skip rules the user
/// qualifies for — or run rules on tier-1 data with tier-2 assumptions.
final class HealthDayTierTests: XCTestCase {
    func testNoDataIsTier0() {
        XCTAssertEqual(HealthDay.tier(steps: nil, sleep: nil, rhr: nil, hrv: nil), 0)
    }

    func testStepsOnlyIsTier0() {
        XCTAssertEqual(HealthDay.tier(steps: 8_000, sleep: nil, rhr: nil, hrv: nil), 0)
    }

    func testSleepOnlyIsTier0() {
        XCTAssertEqual(HealthDay.tier(steps: nil, sleep: 420, rhr: nil, hrv: nil), 0)
    }

    func testStepsAndSleepIsTier1() {
        XCTAssertEqual(HealthDay.tier(steps: 8_000, sleep: 420, rhr: nil, hrv: nil), 1)
    }

    func testStepsSleepAndRhrIsTier2() {
        XCTAssertEqual(HealthDay.tier(steps: 8_000, sleep: 420, rhr: 58.4, hrv: nil), 2)
    }

    func testStepsSleepAndHrvIsTier2() {
        XCTAssertEqual(HealthDay.tier(steps: 8_000, sleep: 420, rhr: nil, hrv: 44.2), 2)
    }

    func testCardioAloneDoesNotEarnTier2() {
        // RHR without steps+sleep isn't enough — tier 2 requires the tier-1
        // basics too. Guard against a permissive edit.
        XCTAssertEqual(HealthDay.tier(steps: nil, sleep: nil, rhr: 60, hrv: 40), 0)
        XCTAssertEqual(HealthDay.tier(steps: 8_000, sleep: nil, rhr: 60, hrv: 40), 0)
    }
}
