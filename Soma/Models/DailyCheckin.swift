import Foundation

/// One row of `public.daily_checkins`. The uniqueness is `(user_id, check_date)`,
/// so upsert by `check_date` when the user re-does a same-day check-in.
struct DailyCheckin: Identifiable, Hashable, Codable {
    let id: UUID
    let userId: UUID
    let checkDate: Date
    let energy: Int
    let mood: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case checkDate = "check_date"
        case energy
        case mood
    }
}
