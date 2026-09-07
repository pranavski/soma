import Foundation
import Supabase

/// Client-side facade for the submit-correction Edge Function.
///
/// The function does all the actual work — write to meal_corrections,
/// update dish_aliases, refresh the meal row — so this repo is thin. We
/// keep the encoding local so the wire shape stays visible next to the
/// server contract in `supabase/functions/submit-correction/index.ts`.
struct CorrectionsRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    /// Send the confirmed correction. Throws on network / auth failure or
    /// on a 4xx server bounce. The caller should surface a soft error.
    func submit(
        mealId: UUID?,
        originalGuess: MealCorrectionOriginal?,
        corrected: MealCorrection,
        photoURL: String? = nil
    ) async throws {
        let body = SubmitCorrectionRequest(
            meal_id: mealId,
            original_ai_guess: originalGuess,
            corrected_meal: corrected,
            photo_url: photoURL
        )
        try await client.functions.invoke(
            "submit-correction",
            options: FunctionInvokeOptions(body: body)
        )
    }

    /// The components parse-meal already found for this meal, so the
    /// correction sheet can start from what's on screen. Without this the
    /// "what was in it" list opens empty on an already-parsed meal and the
    /// user has to retype every component to keep it — and a correction
    /// submitted without retyping archives an empty item list, which is a
    /// false record of what they ate.
    ///
    /// Best-effort: an empty list on failure is the same as today's
    /// behaviour, so a hiccup here never blocks the correction.
    func fetchItems(mealId: UUID) async -> [MealCorrection.Item] {
        struct Row: Decodable { let name: String; let quantity: String? }
        do {
            let response = try await client
                .from("meal_items")
                .select("name,quantity")
                .eq("meal_id", value: mealId)
                .order("position", ascending: true)
                .limit(12)
                .execute()
            let rows = try JSONDecoder().decode([Row].self, from: response.data)
            return rows.map { MealCorrection.Item(name: $0.name, quantity: $0.quantity) }
        } catch {
            return []
        }
    }
}

/// The corrected meal shape sent to the server. Matches the strict
/// revalidator in submit-correction/index.ts — any field mismatch here
/// will 400 there.
struct MealCorrection: Encodable, Equatable {
    var dish_name: String
    var cuisine: String              // one of Cuisine.rawValue
    var calories_low: Int
    var calories_high: Int
    var items: [Item]

    struct Item: Encodable, Equatable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var quantity: String?

        enum CodingKeys: String, CodingKey { case name, quantity }
    }
}

/// Slimmed original guess — server only reads dish_name/cuisine off it
/// (see submit-correction parseOriginal). Snapshotting the whole meal
/// isn't needed and would bloat the archive.
struct MealCorrectionOriginal: Encodable, Equatable {
    var dish_name: String?
    var cuisine: String?
}

private struct SubmitCorrectionRequest: Encodable {
    let meal_id: UUID?
    let original_ai_guess: MealCorrectionOriginal?
    let corrected_meal: MealCorrection
    let photo_url: String?
}

/// UI-facing enum for the cuisine picker. Raw values match the DB CHECK
/// constraint AND the parse-meal contract; changing either requires a
/// migration + Edge-Function-prompt update.
enum Cuisine: String, CaseIterable, Identifiable, Hashable {
    case south_asian
    case east_asian
    case southeast_asian
    case middle_eastern
    case mediterranean
    case african
    case latin_american
    case caribbean
    case western
    case other

    var id: String { rawValue }

    /// Kitchen-notebook lowercase for the picker. No emoji flags — we
    /// deliberately avoid nation flags (many cuisines cross borders).
    var label: String {
        switch self {
        case .south_asian:     return "south asian"
        case .east_asian:      return "east asian"
        case .southeast_asian: return "southeast asian"
        case .middle_eastern:  return "middle eastern"
        case .mediterranean:   return "mediterranean"
        case .african:         return "african"
        case .latin_american:  return "latin american"
        case .caribbean:       return "caribbean"
        case .western:         return "western"
        case .other:           return "other"
        }
    }
}
