import SwiftUI

/// The privacy policy, in the app.
///
/// Guideline 5.1.1(i) requires the policy to be reachable **inside** the app,
/// not only from App Store Connect metadata. Carrying the full text here (as
/// well as linking the hosted copy) means the requirement is satisfied even
/// if the hosted page is briefly unreachable during review.
///
/// This text must stay in sync with `docs/privacy-policy.md` — they are the
/// same document, and a reviewer who finds them disagreeing has found a
/// 5.1.1(i) failure.
struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PRIVACY")
                                .font(Font.Soma.sectionTag)
                                .tracking(3)
                                .foregroundStyle(Color.persimmon)
                            Text("what soma does with your data.")
                                .font(Font.Soma.pullQuote)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("close") { dismiss() }
                            .font(Font.Soma.buttonLg)
                            .foregroundStyle(Color.inkSoft)
                            .buttonStyle(.plain)
                    }

                    Text("last updated 2 august 2026")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)

                    ForEach(Self.sections, id: \.title) { section in
                        PolicySection(title: section.title, text: section.text)
                    }

                    if let url = SomaFeatures.privacyPolicyURL {
                        Link(destination: url) {
                            Text("read this policy on the web")
                                .font(Font.Soma.margin)
                                .underline()
                                .foregroundStyle(Color.persimmon)
                        }
                    }

                    Text("questions: \(SomaFeatures.supportEmail)")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                        .textSelection(.enabled)

                    Spacer(minLength: Theme.Spacing.xl)
                }
                .padding(Theme.Spacing.xl)
            }
        }
    }

    private struct Section { let title: String; let text: String }

    private static let sections: [Section] = [
        Section(
            title: "the short version",
            text: "raw Apple Health samples never leave your phone — only small daily totals sync. your data is yours: export it as a spreadsheet or delete the account and everything in it, from inside the app. no ads, no tracking, no analytics SDKs, nothing sold. ever."
        ),
        Section(
            title: "your account",
            text: "signing in with Apple gives soma a stable, app-scoped identifier, and your email address only if you choose to share it (Hide My Email works fine). it links your meals to your account and is used for nothing else."
        ),
        Section(
            title: "meal logs",
            text: "soma stores what you said or typed, the parsed result (dish name, estimated calorie and macro ranges, cuisine, time eaten), any corrections you make, and optional notes. rows live in a Supabase database behind row-level security — only your signed-in account can read them."
        ),
        Section(
            title: "apple health — optional, read-only",
            text: "if you connect it, soma reads steps, sleep, resting heart rate, HRV, weight, active energy and workouts. it never writes anything back. the raw samples are processed on your device and never leave it: soma computes one summary per day and syncs only those numbers. disconnect any time in iOS Settings → Privacy & Security → Health."
        ),
        Section(
            title: "third-party AI — Anthropic's Claude",
            text: "two things go to Claude, from soma's server rather than your phone, and only after you've agreed. first: the text of a meal you log, so it can be parsed into a structured entry. second: once a night, a compact summary of your recent meals, energy check-ins and daily health totals, so it can look for patterns. no name, no email, no account id, no raw health samples, and no audio. nothing travels past Anthropic. Anthropic processes this as a service provider and does not train models on it. you can withdraw consent in the kitchen at any time — logging keeps working, meals just stay unparsed."
        ),
        Section(
            title: "insights",
            text: "computed from your data alone, always hedged, never prescriptive, never medical advice. soma performs no research and never pools your data with anyone else's."
        ),
        Section(
            title: "the one shared thing: dish names",
            text: "when you correct a dish name (\u{201C}chole\u{201D} → \u{201C}chana masala\u{201D}), soma may record that name-to-name mapping so the next person's parse is better. it carries no user identifier, no macros, no health data, and no link back to you."
        ),
        Section(
            title: "who else sees anything",
            text: "Apple, for sign-in only. Supabase, which hosts the database and functions. Anthropic, as described above. that's the whole list — there are no advertising or analytics SDKs in this app."
        ),
        Section(
            title: "export and deletion",
            text: "the kitchen has an export row that builds a spreadsheet of every meal on demand, and a delete-account row that permanently removes your account and all of its data — meals, corrections, daily summaries, check-ins, insights. if you complete the Apple prompt during deletion, soma also revokes its sign-in token with Apple. deletion is immediate and irreversible."
        ),
        Section(
            title: "children",
            text: "soma isn't directed at children under 13, or the equivalent minimum age where you live, and doesn't knowingly collect their data."
        ),
        Section(
            title: "changes",
            text: "if this policy changes materially, the date above changes with it and the release notes will say so."
        )
    ]
}

private struct PolicySection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.persimmon)
            Text(text)
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
