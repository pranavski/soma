import Foundation
import Supabase

/// Reads/writes for the `meals` table. The RLS policy "owner can read" on
/// the row means we don't filter by user_id from the client — the JWT in
/// the session does it server-side.
struct MealsRepository {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    init(client: SupabaseClient = .shared) {
        self.client = client
        self.decoder = Self.makeDecoder()
    }

    /// Meals whose `eaten_at` falls within the given calendar day, ordered
    /// earliest first.
    func fetchToday(
        on day: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [Meal] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }

        let response = try await client
            .from("meals")
            .select()
            .gte("eaten_at", value: Self.iso(start))
            .lt("eaten_at",  value: Self.iso(end))
            .order("eaten_at", ascending: true)
            .execute()

        return try decoder.decode([Meal].self, from: response.data)
    }

    /// Insert a new meal in `pending` state. The Edge Function fills in
    /// dish_name/calories on success; the row exists in the meantime so the
    /// Today screen can render a "parsing…" card without waiting.
    ///
    /// `id` can be supplied by the caller — the photo path convention
    /// (`<user_id>/<meal_id>.jpg`) needs the meal id before the row exists,
    /// so the photo flow generates the UUID client-side, uploads, then
    /// inserts.
    @discardableResult
    func insertPendingMeal(
        source: Meal.Source,
        voiceTranscript: String?,
        photoPath: String? = nil,
        id: UUID? = nil,
        eatenAt: Date = Date()
    ) async throws -> UUID {
        let userId = try await client.auth.session.user.id

        let row = PendingMealInsert(
            id: id,
            userId: userId,
            eatenAt: Self.iso(eatenAt),
            eatenDate: Self.localDateString(eatenAt),
            eatenHour: Self.localHour(eatenAt),
            source: source.rawValue,
            voiceTranscript: voiceTranscript,
            photoPath: photoPath
        )

        let response = try await client
            .from("meals")
            .insert(row, returning: .representation)
            .select("id")
            .single()
            .execute()

        struct InsertedId: Decodable { let id: UUID }
        let decoded = try JSONDecoder().decode(InsertedId.self, from: response.data)
        return decoded.id
    }

    private struct PendingMealInsert: Encodable {
        let id: UUID?
        let userId: UUID
        let eatenAt: String
        let eatenDate: String
        let eatenHour: Int
        let source: String
        let voiceTranscript: String?
        let photoPath: String?

        enum CodingKeys: String, CodingKey {
            case id
            case userId          = "user_id"
            case eatenAt         = "eaten_at"
            case eatenDate       = "eaten_date"
            case eatenHour       = "eaten_hour"
            case source
            case voiceTranscript = "voice_transcript"
            case photoPath       = "photo_path"
        }
    }

    /// Upload a prepared JPEG to the private `meal-photos` bucket under the
    /// RLS-enforced path `<user_id>/<meal_id>.jpg` and return that path.
    /// The bucket's insert policy only admits paths whose first segment is
    /// the caller's own auth.uid(), so a bad path fails server-side too.
    func uploadMealPhoto(_ data: Data, mealId: UUID) async throws -> String {
        let userId = try await client.auth.session.user.id
        let path = "\(userId.uuidString.lowercased())/\(mealId.uuidString.lowercased()).jpg"
        try await client.storage
            .from("meal-photos")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    /// One-tap repeat. Copies the most recent parsed row that carries the
    /// given `dish_name`, inserting a new `source='repeat'` row with the
    /// same dish and macro ranges. Returns the new meal id.
    ///
    /// Repeats do NOT hit parse-meal — we already have the parse from the
    /// original. The `insight-rules` skill wants repeat rows in place so the
    /// `repeat_dish_energy` rule can find them.
    @discardableResult
    func repeatMeal(dishName: String, eatenAt: Date = Date()) async throws -> UUID {
        let userId = try await client.auth.session.user.id

        // Pull the most recent parsed row of this dish. RLS scopes it to the
        // caller so we don't need to filter by user_id here. `.limit(1)` +
        // array-decode avoids `.maybeSingle()` — PostgrestTransformBuilder
        // doesn't expose it after `.limit(...)`.
        let template = try await client
            .from("meals")
            .select("dish_name,calories_low,calories_high,protein_g_low,protein_g_high,carbs_g_low,carbs_g_high,fat_g_low,fat_g_high,fiber_g_low,fiber_g_high")
            .eq("dish_name", value: dishName)
            .eq("parse_status", value: "parsed")
            .order("eaten_at", ascending: false)
            .limit(1)
            .execute()

        struct Template: Decodable {
            let dish_name: String?
            let calories_low: Int?; let calories_high: Int?
            let protein_g_low: Int?; let protein_g_high: Int?
            let carbs_g_low: Int?; let carbs_g_high: Int?
            let fat_g_low: Int?; let fat_g_high: Int?
            let fiber_g_low: Int?; let fiber_g_high: Int?
        }

        let candidates = (try? JSONDecoder().decode([Template].self, from: template.data)) ?? []
        let t: Template = candidates.first ?? Template(
            dish_name: dishName,
            calories_low: nil, calories_high: nil,
            protein_g_low: nil, protein_g_high: nil,
            carbs_g_low: nil, carbs_g_high: nil,
            fat_g_low: nil, fat_g_high: nil,
            fiber_g_low: nil, fiber_g_high: nil
        )

        struct RepeatInsert: Encodable {
            let user_id: UUID
            let eaten_at: String
            let eaten_date: String
            let eaten_hour: Int
            let source: String
            let dish_name: String?
            let parse_status: String
            let parsed_at: String
            let calories_low: Int?; let calories_high: Int?
            let protein_g_low: Int?; let protein_g_high: Int?
            let carbs_g_low: Int?; let carbs_g_high: Int?
            let fat_g_low: Int?; let fat_g_high: Int?
            let fiber_g_low: Int?; let fiber_g_high: Int?
        }

        let now = Self.iso(Date())
        let row = RepeatInsert(
            user_id: userId,
            eaten_at: Self.iso(eatenAt),
            eaten_date: Self.localDateString(eatenAt),
            eaten_hour: Self.localHour(eatenAt),
            source: "repeat",
            dish_name: t.dish_name ?? dishName,
            parse_status: "parsed",
            parsed_at: now,
            calories_low: t.calories_low, calories_high: t.calories_high,
            protein_g_low: t.protein_g_low, protein_g_high: t.protein_g_high,
            carbs_g_low: t.carbs_g_low, carbs_g_high: t.carbs_g_high,
            fat_g_low: t.fat_g_low, fat_g_high: t.fat_g_high,
            fiber_g_low: t.fiber_g_low, fiber_g_high: t.fiber_g_high
        )

        let response = try await client
            .from("meals")
            .insert(row, returning: .representation)
            .select("id")
            .single()
            .execute()

        struct InsertedId: Decodable { let id: UUID }
        return try JSONDecoder().decode(InsertedId.self, from: response.data).id
    }

    /// Distinct recent dish names ordered by most-recent-eaten. Used to
    /// power the repeat-a-meal chips.
    func fetchRecentDishNames(limit: Int = 6) async throws -> [String] {
        let response = try await client
            .from("meals")
            .select("dish_name,eaten_at")
            .not("dish_name", operator: .is, value: "null")
            .eq("parse_status", value: "parsed")
            .order("eaten_at", ascending: false)
            .limit(limit * 4) // over-fetch to dedupe client-side
            .execute()

        struct Row: Decodable { let dish_name: String? }
        let rows = try JSONDecoder().decode([Row].self, from: response.data)
        var seen = Set<String>()
        var out: [String] = []
        for r in rows {
            guard let name = r.dish_name, !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            out.append(name)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Decoder

    /// Postgres returns timestamps with or without fractional seconds
    /// depending on column precision; accept both.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = withFractional.date(from: text) { return date }
            if let date = withoutFractional.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized timestamp: \(text)"
            )
        }
        return decoder
    }

    private static func iso(_ date: Date) -> String {
        withFractional.string(from: date)
    }

    // Local wall-clock capture — eaten_at is timestamptz (normalized to
    // UTC server-side), so the insight engine's "ate after 21:00" rule
    // needs the local date/hour recorded at log time.
    private static func localDateString(_ date: Date) -> String {
        localDateFormatter.string(from: date)
    }

    private static func localHour(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
