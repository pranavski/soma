import SwiftUI

/// The kitchen's view of the Claude consent — the "revoke" half of 5.1.1(i)
/// ("how to revoke consent") and 5.1.2(i). Consent the user can't withdraw
/// isn't consent, and the privacy policy promises this row exists.
struct AIConsentSettingsSheet: View {
    @EnvironmentObject private var disclosure: AIDisclosure
    @Environment(\.dismiss) private var dismiss
    @State private var showPolicy = false

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("READING MEALS")
                                .font(Font.Soma.sectionTag)
                                .tracking(3)
                                .foregroundStyle(Color.persimmon)
                            Text("who turns your words into an entry.")
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

                    statusCard

                    Text("with this on, the text of a meal you log goes to Claude — an AI model made by Anthropic — to be parsed, and once a night a compact summary of your recent meals, check-ins and daily health totals goes over so soma can look for patterns. no name, no email, no account id, no raw health samples, no audio.")
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("with it off, meals still save — they just stay unparsed, and you can fill in the details yourself with “not quite right?” on any card.")
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button { showPolicy = true } label: {
                        Text("read the privacy policy")
                            .font(Font.Soma.margin)
                            .underline()
                            .foregroundStyle(Color.inkSoft)
                    }
                    .buttonStyle(.plain)

                    toggleButton

                    Spacer(minLength: Theme.Spacing.xl)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .sheet(isPresented: $showPolicy) {
            PrivacyPolicySheet()
        }
    }

    private var statusCard: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(disclosure.hasConsented ? "ON" : "OFF")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(disclosure.hasConsented ? Color.persimmon : Color.inkSoft)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .stroke(
                            (disclosure.hasConsented ? Color.persimmon : Color.inkSoft).opacity(0.5),
                            lineWidth: Theme.Stroke.hairline
                        )
                )
            Text(disclosure.hasConsented
                 ? "soma sends meals to Claude to be read."
                 : "nothing goes to Claude.")
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var toggleButton: some View {
        Button {
            if disclosure.hasConsented {
                disclosure.decline()
            } else {
                disclosure.accept()
            }
        } label: {
            Text(disclosure.hasConsented ? "turn it off" : "turn it on")
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(disclosure.hasConsented ? Color.persimmon : Color.ink)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.s)
    }
}
