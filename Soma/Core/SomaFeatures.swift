import Foundation

/// Ship-time feature switches.
///
/// These exist so what the app *does* can't drift from what its privacy
/// policy, nutrition label and privacy manifest *say* it does. Flipping one
/// on is a compliance change, not just a product change — read the note.
enum SomaFeatures {
    /// Where the hosted privacy policy will live. Apple requires the same
    /// URL in App Store Connect metadata; the in-app `PrivacyPolicySheet`
    /// carries the full text as well, so the requirement is met even before
    /// this resolves.
    ///
    /// Published by `.github/workflows/pages.yml` from
    /// `docs/privacy-policy.md`. Live since 2026-09-08 — verified 200 with
    /// the full policy text and its stylesheet. The same URL goes in the
    /// App Store Connect metadata field; the in-app sheet carries the text
    /// as well, so review passes even if the page is briefly unreachable.
    static let privacyPolicyURL = URL(string: "https://pranavski.github.io/soma/privacy/")

    /// True once `privacyPolicyURL` resolves — it gates the sheet's "read
    /// this policy on the web" link, so a reviewer never taps a dead page.
    static let privacyPolicyIsHosted = true

    /// Support contact, required alongside the privacy policy URL in ASC.
    /// The same address the markdown policy names.
    static let supportEmail = "pranav.surampudi@gmail.com"
}
