import Foundation

/// One row of `public.health_days` — the daily aggregate the client computes
/// from HealthKit. Raw HealthKit samples never leave the device; only the
/// per-day rollup below.
struct HealthDay: Hashable, Codable {
    let day: Date
    let steps: Int?
    let sleepMinutes: Int?
    let restingHrBpm: Double?
    let hrvMs: Double?
    let tier: Int

    enum CodingKeys: String, CodingKey {
        case day
        case steps
        case sleepMinutes = "sleep_minutes"
        case restingHrBpm = "resting_hr_bpm"
        case hrvMs        = "hrv_ms"
        case tier
    }

    /// Tier per the insight-rules skill:
    /// - 0 = no HealthKit (base case; not written here)
    /// - 1 = steps + sleep present
    /// - 2 = steps + sleep + (RHR or HRV) present
    static func tier(steps: Int?, sleep: Int?, rhr: Double?, hrv: Double?) -> Int {
        let hasBasic = steps != nil && sleep != nil
        let hasCardio = rhr != nil || hrv != nil
        if hasBasic && hasCardio { return 2 }
        if hasBasic { return 1 }
        return 0
    }
}
