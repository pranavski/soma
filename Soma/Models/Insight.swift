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

    /// Published context for the pattern, when the finding matches something
    /// the research literature has established and points the same way.
    ///
    /// Written by neither the model nor this app's copywriting: the Edge
    /// Function copies these out of a reviewed, cited source table keyed by
    /// the pattern it describes. That is why they can be shown as fact while
    /// `claim` is always hedged — one is a published finding, the other is an
    /// observation about 30 days of one person's life.
    ///
    /// Optional, and usually absent. Most of what someone notices about
    /// themselves has never been studied, and those findings still surface —
    /// they just arrive without a clipping attached.
    let mechanism: String?
    let evidenceCitation: String?
    let evidenceGrade: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt       = "created_at"
        case claim
        case evidence
        case confidence
        case suggestedAction = "suggested_action"
        case windowDays      = "window_days"
        case mechanism
        case evidenceCitation = "evidence_citation"
        case evidenceGrade    = "evidence_grade"
    }

    /// Both halves are required to show the block. A mechanism without its
    /// citation is an unsourced health claim — the database enforces the same
    /// all-or-nothing rule, and this is the client-side belt to that
    /// suspenders in case a row predates the constraint.
    var publishedContext: (mechanism: String, citation: String)? {
        guard let mechanism, let evidenceCitation else { return nil }
        return (mechanism, evidenceCitation)
    }

    /// The persimmon caption under the finding — invariant copy that
    /// carries the hedge so the LLM sentence never has to.
    var hedgeCaption: String { "worth watching, not a verdict" }
}
