import Foundation

/// One plain description of what's in the log — matches `public.reflections`,
/// written by the `generate-insights` Edge Function.
///
/// Deliberately *not* an `Insight`, and the difference is the whole point.
/// An insight is an inference: it relates something eaten to something the
/// body did, and it only exists because a permutation test with a
/// false-discovery correction let it through. That machinery cannot produce
/// anything from fewer than about ten days of paired data — not because
/// someone set the bar there, but because the smallest p-value attainable
/// from n days sits above the corrected threshold until n is around seven.
///
/// A reflection relates nothing to anything. "Your last meal has landed
/// between 18:00 and 22:00" is arithmetic over what the person typed, true
/// on day three without any correction to earn. That is why it can carry the
/// first week of the app, and why it must never be dressed as a finding:
/// there is no confidence tier here, no hedge caption, no published context,
/// because there is no claim to hedge.
///
/// It is also a snapshot, not history. The server replaces the whole set on
/// every run — a description of the log is wrong the moment another meal is
/// added — so nothing here is worth keeping or comparing across days.
struct Reflection: Identifiable, Hashable, Codable {
    /// Which observation this is (`meal_timing`, `repeat_dish`, …). Stable
    /// across runs, which is what makes it the identity: there is one
    /// current answer per kind. The client never switches on the value —
    /// new kinds ship server-side and render without an app update.
    let kind: String
    /// The observation, one sentence.
    let body: String
    /// The counts underneath it, set quieter.
    let detail: String
    /// Server-side order, so the client doesn't re-derive the priority and
    /// grouping rules that chose these.
    let sortOrder: Int
    let windowDays: Int

    var id: String { kind }

    enum CodingKeys: String, CodingKey {
        case kind
        case body
        case detail
        case sortOrder  = "sort_order"
        case windowDays = "window_days"
    }
}
