import Foundation

/// Shared timestamp helpers for talking to Postgres via PostgREST.
///
/// Postgres returns `timestamptz` with or without fractional seconds
/// depending on the column and the query — accept both when decoding,
/// always write the fractional form so round-tripping is stable.
enum SupabaseDates {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso(_ date: Date) -> String {
        withFractional.string(from: date)
    }

    /// Parse a `timestamptz` string in either precision. Mirrors the decoder
    /// below, for the few places that read a raw column without going
    /// through `Codable`.
    static func date(from text: String) -> Date? {
        withFractional.date(from: text) ?? withoutFractional.date(from: text)
    }

    /// `YYYY-MM-DD` in the caller's local timezone. Used for `date` columns
    /// (`check_date`, `day`, `week_start`) where the spec pins to *user local*
    /// rather than UTC — the "did you eat late yesterday" question lives on
    /// the user's clock, not the server's.
    static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// ISO-week Monday for the given date, formatted `YYYY-MM-DD` in local tz.
    /// Matches Postgres's `date_trunc('week', ...)` semantics used by the
    /// insights `week_start` column.
    static func isoWeekStart(_ date: Date, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4 // ISO 8601
        let weekday = cal.component(.weekday, from: date)
        // Monday = 2 in Gregorian; offset back to Monday of this week.
        let daysToMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysToMonday, to: date) ?? date
        return localDay(monday, calendar: cal)
    }

    /// A JSONDecoder pre-configured to accept both timestamp shapes above.
    /// Repositories call this once at init.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = withFractional.date(from: text) { return date }
            if let date = withoutFractional.date(from: text) { return date }
            // `date` columns come back as `YYYY-MM-DD`.
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = Calendar(identifier: .iso8601)
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.timeZone = TimeZone.current
            dayFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dayFormatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized timestamp: \(text)"
            )
        }
        return decoder
    }
}
