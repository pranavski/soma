import Foundation

/// One logged meal — shape matches the `public.meals` row.
///
/// Calories and macros are stored as *ranges* (low/high). Anywhere they get
/// rendered the spec requires the range form ("~320–420"), never a bare
/// number — `calorieRange` / `MacroBreakdown` enforce that contract.
struct Meal: Identifiable, Hashable, Codable {
    let id: UUID
    let userId: UUID
    let eatenAt: Date
    let loggedAt: Date
    let source: Source
    let dishName: String?
    let caloriesLow: Int?
    let caloriesHigh: Int?
    let proteinLow: Int?
    let proteinHigh: Int?
    let carbsLow: Int?
    let carbsHigh: Int?
    let fatLow: Int?
    let fatHigh: Int?
    let fiberLow: Int?
    let fiberHigh: Int?
    let notes: String?
    let photoPath: String?
    let voiceTranscript: String?
    let parseStatus: ParseStatus
    // Raw string (not the Cuisine enum) so an unrecognized server value
    // can't fail the whole row decode.
    var cuisine: String? = nil
    // Caffeine (mg) and alcohol (g of ethanol) — meal-level, anchored by
    // parse-meal against reference servings. The insight engine reads them,
    // so the card shows them too; a finding about afternoon coffee should
    // never be the first time the user sees soma record caffeine.
    var caffeineMgLow: Int? = nil
    var caffeineMgHigh: Int? = nil
    var alcoholGLow: Int? = nil
    var alcoholGHigh: Int? = nil

    enum Source: String, Codable, Hashable {
        case photo, voice, manual
        case repeated = "repeat"   // `repeat` is a Swift keyword
    }

    enum ParseStatus: String, Codable, Hashable {
        case pending, parsed, failed, manual
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId          = "user_id"
        case eatenAt         = "eaten_at"
        case loggedAt        = "logged_at"
        case source
        case dishName        = "dish_name"
        case caloriesLow     = "calories_low"
        case caloriesHigh    = "calories_high"
        case proteinLow      = "protein_g_low"
        case proteinHigh     = "protein_g_high"
        case carbsLow        = "carbs_g_low"
        case carbsHigh       = "carbs_g_high"
        case fatLow          = "fat_g_low"
        case fatHigh         = "fat_g_high"
        case fiberLow        = "fiber_g_low"
        case fiberHigh       = "fiber_g_high"
        case notes
        case photoPath       = "photo_path"
        case voiceTranscript = "voice_transcript"
        case parseStatus     = "parse_status"
        case cuisine
        case caffeineMgLow   = "caffeine_mg_low"
        case caffeineMgHigh  = "caffeine_mg_high"
        case alcoholGLow     = "alcohol_g_low"
        case alcoholGHigh    = "alcohol_g_high"
    }
}

// MARK: - View helpers

extension Meal {
    var displayName: String {
        if let dishName, !dishName.isEmpty { return dishName }
        switch parseStatus {
        case .pending: return "parsing…"
        case .failed:  return "couldn't read that"
        case .parsed, .manual: return "untitled"
        }
    }

    var isRepeat: Bool { source == .repeated }

    var timeLabel: String { SomaFormat.time(eatenAt) }

    /// "~320–420" or nil if we haven't parsed yet. Always a range — the
    /// spec forbids a bare number anywhere it might be read as a target.
    var calorieRange: String? {
        guard let lo = caloriesLow, let hi = caloriesHigh else { return nil }
        return "~\(lo)–\(hi)"
    }

    /// Macro ranges rendered as "~lo–hi g" strings, nil when unparsed.
    /// Follows the calorie-range contract exactly.
    var macros: MacroBreakdown { MacroBreakdown(meal: self) }

    /// "~80–120 mg caffeine · ~14–20 g alcohol" for a meal that carries
    /// either; nil when both are zero or unparsed, which is most meals.
    /// Ranges, like everything else on the card.
    var stimulantNote: String? {
        var parts: [String] = []
        if let lo = caffeineMgLow, let hi = caffeineMgHigh, hi > 0 {
            parts.append("~\(lo)–\(hi) mg caffeine")
        }
        if let lo = alcoholGLow, let hi = alcoholGHigh, hi > 0 {
            parts.append("~\(lo)–\(hi) g alcohol")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// True when the dish on the row came from Claude rather than from the
    /// person — the only case where a correction has an "original guess"
    /// worth teaching the community alias table from. A `manual` row's name
    /// is human-written (a correction, or a meal filed with consent off), so
    /// there is nothing there to learn a mapping from.
    var dishWasParsed: Bool {
        parseStatus == .parsed || parseStatus == .failed
    }
}

/// Per-macro range strings for the parsed meal. A field returns nil if
/// either endpoint is missing — the row-level UI hides the whole strip
/// when *all* four are nil (still parsing / failed).
struct MacroBreakdown {
    let proteinRange: String?
    let carbsRange:   String?
    let fatRange:     String?
    let fiberRange:   String?

    init(meal: Meal) {
        proteinRange = Self.range(meal.proteinLow, meal.proteinHigh)
        carbsRange   = Self.range(meal.carbsLow,   meal.carbsHigh)
        fatRange     = Self.range(meal.fatLow,     meal.fatHigh)
        fiberRange   = Self.range(meal.fiberLow,   meal.fiberHigh)
    }

    var isEmpty: Bool {
        proteinRange == nil && carbsRange == nil && fatRange == nil && fiberRange == nil
    }

    private static func range(_ lo: Int?, _ hi: Int?) -> String? {
        guard let lo, let hi else { return nil }
        return "~\(lo)–\(hi)g"
    }
}

// MARK: - Preview-only sample data

enum SampleData {
    static let logged: [Meal] = [
        Meal(
            id: UUID(),
            userId: UUID(),
            eatenAt: date(8, 10),
            loggedAt: date(8, 12),
            source: .repeated,
            dishName: "Eggs + toast",
            caloriesLow: 320, caloriesHigh: 420,
            proteinLow: 18, proteinHigh: 24,
            carbsLow: 30, carbsHigh: 40,
            fatLow: 12, fatHigh: 18,
            fiberLow: 3, fiberHigh: 5,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: .manual
        ),
        Meal(
            id: UUID(),
            userId: UUID(),
            eatenAt: date(10, 30),
            loggedAt: date(10, 31),
            source: .repeated,
            dishName: "Matcha",
            caloriesLow: 30, caloriesHigh: 70,
            proteinLow: 1, proteinHigh: 3,
            carbsLow: 4, carbsHigh: 8,
            fatLow: 0, fatHigh: 2,
            fiberLow: 0, fiberHigh: 1,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: .manual
        ),
        Meal(
            id: UUID(),
            userId: UUID(),
            eatenAt: date(12, 45),
            loggedAt: date(12, 50),
            source: .manual,
            dishName: "Big chop salad",
            caloriesLow: 380, caloriesHigh: 500,
            proteinLow: 22, proteinHigh: 30,
            carbsLow: 28, carbsHigh: 38,
            fatLow: 18, fatHigh: 26,
            fiberLow: 8, fiberHigh: 12,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: .manual
        )
    ]

    /// Yesterday's plated meals — used behind the wax-paper overlay so
    /// "compare yesterday" has something to draw. Sample only.
    static let loggedYesterday: [Meal] = [
        Meal(
            id: UUID(), userId: UUID(),
            eatenAt: dateOffset(days: -1, h: 7, m: 45),
            loggedAt: dateOffset(days: -1, h: 7, m: 46),
            source: .repeated,
            dishName: "Yogurt + berries",
            caloriesLow: 210, caloriesHigh: 290,
            proteinLow: 12, proteinHigh: 18,
            carbsLow: 26, carbsHigh: 34,
            fatLow: 4, fatHigh: 8,
            fiberLow: 3, fiberHigh: 6,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: .manual
        ),
        Meal(
            id: UUID(), userId: UUID(),
            eatenAt: dateOffset(days: -1, h: 13, m: 15),
            loggedAt: dateOffset(days: -1, h: 13, m: 16),
            source: .manual,
            dishName: "Ramen at Ippudo",
            caloriesLow: 640, caloriesHigh: 820,
            proteinLow: 28, proteinHigh: 40,
            carbsLow: 70, carbsHigh: 90,
            fatLow: 24, fatHigh: 34,
            fiberLow: 4, fiberHigh: 6,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: .manual
        ),
        Meal(
            id: UUID(), userId: UUID(),
            eatenAt: dateOffset(days: -1, h: 19, m: 30),
            loggedAt: dateOffset(days: -1, h: 19, m: 31),
            source: .manual,
            dishName: "Miso salmon",
            caloriesLow: 520, caloriesHigh: 680,
            proteinLow: 38, proteinHigh: 50,
            carbsLow: 32, carbsHigh: 44,
            fatLow: 22, fatHigh: 32,
            fiberLow: 3, fiberHigh: 5,
            notes: nil, photoPath: nil, voiceTranscript: nil,
            parseStatus: .manual
        )
    ]

    private static func date(_ h: Int, _ m: Int) -> Date {
        dateOffset(days: 0, h: h, m: m)
    }

    private static func dateOffset(days: Int, h: Int, m: Int) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        var c = Calendar.current.dateComponents([.year, .month, .day], from: base)
        c.hour = h
        c.minute = m
        return Calendar.current.date(from: c) ?? base
    }
}
