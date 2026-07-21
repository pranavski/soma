import Foundation

/// One weekly finding — matches `public.insights`.
/// Rule ids are pinned to the four v1 rules in the `insight-rules` skill.
struct Insight: Identifiable, Hashable, Codable {
    let id: UUID
    let weekStart: Date
    let ruleId: RuleId
    let tier: Int
    let lookbackDays: Int
    let copy: String

    enum RuleId: String, Codable, Hashable {
        case lateEatEnergy      = "late_eat_energy"
        case repeatDishEnergy   = "repeat_dish_energy"
        case stepsSleep         = "steps_sleep"
        case lateEatOvernight   = "late_eat_overnight"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case weekStart    = "week_start"
        case ruleId       = "rule_id"
        case tier
        case lookbackDays = "lookback_days"
        case copy
    }

    /// The persimmon caption under the finding — invariant copy that
    /// carries the hedge so the LLM sentence never has to.
    var hedgeCaption: String { "worth watching, not a verdict" }
}
