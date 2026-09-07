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
    /// Served by `.github/workflows/pages.yml` once Pages is enabled on the
    /// repo (Settings → Pages → Source: GitHub Actions). The sheet only
    /// renders the "read on the web" link while `privacyPolicyIsHosted` is
    /// true, so a reviewer never taps through to a dead page. Open this URL
    /// in a browser, then flip the flag. Tracked in
    /// docs/app-store-compliance.md §6.
    static let privacyPolicyURL = URL(string: "https://pranavski.github.io/soma/privacy/")

    /// Flip to true once `privacyPolicyURL` actually resolves.
    static let privacyPolicyIsHosted = false

    /// Support contact, required alongside the privacy policy URL in ASC.
    /// The same address the markdown policy names.
    static let supportEmail = "pranav.surampudi@gmail.com"
}
