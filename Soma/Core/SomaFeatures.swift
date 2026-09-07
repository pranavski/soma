import Foundation

/// Ship-time feature switches.
///
/// These exist so what the app *does* can't drift from what its privacy
/// policy, nutrition label and privacy manifest *say* it does. Flipping one
/// on is a compliance change, not just a product change — read the note.
enum SomaFeatures {
    /// Where the hosted privacy policy lives. Apple requires the same URL in
    /// App Store Connect metadata; the in-app `PrivacyPolicySheet` carries the
    /// full text as well so the requirement is met even before this resolves.
    static let privacyPolicyURL = URL(string: "https://soma.app/privacy")

    /// Support contact, required alongside the privacy policy URL in ASC.
    static let supportEmail = "support@soma.app"
}
