import Foundation
import Supabase

/// Builds a CSV of the caller's meals for local export. First-party data
/// export is a common App Review privacy expectation and satisfies the
/// "your data, plainly" Settings promise.
///
/// Emits a temp-file URL so `ShareLink(item: url)` can hand it off to the
/// standard share sheet.
enum MealExport {
    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func buildCSV() async throws -> URL {
        let client = SupabaseClient.shared
        let response = try await client
            .from("meals")
            .select("eaten_at,source,dish_name,calories_low,calories_high,protein_g_low,protein_g_high,carbs_g_low,carbs_g_high,fat_g_low,fat_g_high,fiber_g_low,fiber_g_high,parse_status,voice_transcript,notes")
            .order("eaten_at", ascending: false)
            .execute()

        struct Row: Decodable {
            let eaten_at: String
            let source: String
            let dish_name: String?
            let calories_low: Int?; let calories_high: Int?
            let protein_g_low: Int?; let protein_g_high: Int?
            let carbs_g_low: Int?; let carbs_g_high: Int?
            let fat_g_low: Int?; let fat_g_high: Int?
            let fiber_g_low: Int?; let fiber_g_high: Int?
            let parse_status: String
            let voice_transcript: String?
            let notes: String?
        }

        let rows = try JSONDecoder().decode([Row].self, from: response.data)

        var out = ""
        out += "eaten_at,source,dish_name,calories_low,calories_high,protein_g_low,protein_g_high,carbs_g_low,carbs_g_high,fat_g_low,fat_g_high,fiber_g_low,fiber_g_high,parse_status,voice_transcript,notes\n"
        for r in rows {
            var fields: [String] = []
            fields.append(r.eaten_at)
            fields.append(r.source)
            fields.append(csvEscape(r.dish_name))
            fields.append(intField(r.calories_low))
            fields.append(intField(r.calories_high))
            fields.append(intField(r.protein_g_low))
            fields.append(intField(r.protein_g_high))
            fields.append(intField(r.carbs_g_low))
            fields.append(intField(r.carbs_g_high))
            fields.append(intField(r.fat_g_low))
            fields.append(intField(r.fat_g_high))
            fields.append(intField(r.fiber_g_low))
            fields.append(intField(r.fiber_g_high))
            fields.append(r.parse_status)
            fields.append(csvEscape(r.voice_transcript))
            fields.append(csvEscape(r.notes))
            out += fields.joined(separator: ",") + "\n"
        }

        let fname = "soma-meals-\(SupabaseDates.localDay(Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fname)
        try out.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private static func intField(_ v: Int?) -> String {
        v.map(String.init) ?? ""
    }

    /// RFC 4180-ish: wrap in quotes when the field contains a comma, quote,
    /// or newline; escape embedded quotes by doubling them.
    private static func csvEscape(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let needsQuote = raw.contains(",") || raw.contains("\"") || raw.contains("\n")
        if !needsQuote { return raw }
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
