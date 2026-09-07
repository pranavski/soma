import Foundation

/// Locale-aware date/time strings for the UI.
///
/// Every screen used to build its own `DateFormatter` with a hard-coded
/// `dateFormat` ("h:mm a", "EEEE, MMMM d"). A fixed pattern ignores the
/// user's 12-/24-hour setting, so a phone set to 24-hour time still read
/// "9:55 PM", and non-English locales got English month names regardless.
/// `Date.FormatStyle` keeps the *shape* we want and lets the locale decide
/// the rendering — and unlike a shared `DateFormatter` it's a value type,
/// so these are safe to call from anywhere.
enum SomaFormat {
    /// "9:55 PM" or "21:55", per the user's clock setting.
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "sunday, august 2" — the day line above the wordmark.
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day()).lowercased()
    }

    /// "SUN, AUG 2" — the check-in sheet's stamp.
    static func shortStamp(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .uppercased()
    }

    /// "august" — month name alone, for the history day label.
    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide)).lowercased()
    }

    /// "August 2026" — history's month title. The year matters: paging back
    /// far enough otherwise shows a bare "August" that could be any year.
    static func monthAndYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    /// "2 hours ago" — how long since something last happened, for status
    /// lines where the exact timestamp is noise. Named presentation ("
    /// yesterday") rather than numeric, since these are read at a glance.
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named)).lowercased()
    }
}
