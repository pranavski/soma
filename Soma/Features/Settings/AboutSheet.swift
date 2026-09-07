import SwiftUI

/// The "what Soma is, isn't" sheet. Static copy; sets the ground rules
/// for the user (no goals, no calorie targets, hedged insights).
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack {
                        Text("Soma.")
                            .font(Font.Soma.logo)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Button("close") { dismiss() }
                            .font(Font.Soma.buttonLg)
                            .foregroundStyle(Color.inkSoft)
                            .buttonStyle(.plain)
                    }

                    AboutSection(
                        title: "what it is",
                        text: "a quiet food–body record. log a meal in ten seconds. each night — or when you pull to refresh — soma looks over your last few weeks and surfaces a few hedged patterns from your own data, if there are any worth watching. before there's enough to go on, it just describes what's written down."
                    )
                    AboutSection(
                        title: "what it isn't",
                        text: "not a diet. no goals, no streaks, no calorie targets. calories are always shown as a range — because that's what an estimate is. never medical advice."
                    )
                    AboutSection(
                        title: "your data",
                        text: "stored in your private supabase, protected by row-level security. raw healthkit samples never leave your phone — only daily summaries. sign out anytime."
                    )
                    AboutSection(
                        title: "why v1",
                        text: "this is a first version. some rules need a couple weeks of data before they'll surface anything. that silence is honest — a fake finding would be worse."
                    )
                }
                .padding(Theme.Spacing.xl)
            }
        }
    }
}

private struct AboutSection: View {
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
