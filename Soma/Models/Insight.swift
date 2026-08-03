import Foundation

/// One generated finding — matches the new `public.insights` shape produced
/// on demand by the `generate-insights` Edge Function.
struct Insight: Identifiable, Hashable, Codable {
    enum Confidence: String, Codable, CaseIterable, Comparable {
        case low, medium, high

        static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            guard let l = allCases.firstIndex(of: lhs),
                  let r = allCases.firstIndex(of: rhs) else { return false }
            return l < r
        }
    }

    let id: UUID
    let createdAt: Date
    let claim: String
    let evidence: String
    let confidence: Confidence
    let suggestedAction: String?
    let windowDays: Int

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt       = "created_at"
        case claim
        case evidence
        case confidence
        case suggestedAction = "suggested_action"
        case windowDays      = "window_days"
    }

    /// The persimmon caption under the finding — invariant copy that
    /// carries the hedge so the LLM sentence never has to.
    var hedgeCaption: String { "worth watching, not a verdict" }
}
