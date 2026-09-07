import Foundation
import SwiftUI

/// Consent state for sending meal text to Anthropic's Claude.
///
/// App Review Guideline 5.1.2(i), as revised 2025-11-13, requires that an app
/// "clearly disclose where personal data will be shared with third parties,
/// **including with third-party AI**, and obtain **explicit permission**
/// before doing so." A privacy-policy mention is explicitly not enough: the
/// provider has to be named and the user has to agree, in the app, before the
/// first send.
///
/// So `parse-meal` — which posts what the user typed or said to Claude — is
/// gated on `hasConsented`. Declining leaves logging fully usable: the meal is
/// still saved, it just stays unparsed until the user changes their mind, and
/// the correction sheet can fill in the details by hand.
///
/// **The storage key is versioned on purpose.** Consent is to a described
/// flow, not to a vendor in the abstract, so when what leaves the phone
/// changes (a new recipient, a new kind of data), bump the version: the old
/// answer stops covering it and everyone is asked again. 5.1.2(i) is
/// explicit that a privacy-policy mention doesn't stand in for asking.
@MainActor
final class AIDisclosure: ObservableObject {
    static let shared = AIDisclosure()

    private static let key = "soma.ai.parseConsent.v1"

    /// nil = never answered (show the sheet), true = agreed, false = declined.
    @Published private(set) var decision: Bool?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.decision = defaults.object(forKey: Self.key) as? Bool
    }

    var hasConsented: Bool { decision == true }
    var hasAnswered: Bool { decision != nil }

    func accept() {
        decision = true
        defaults.set(true, forKey: Self.key)
    }

    func decline() {
        decision = false
        defaults.set(false, forKey: Self.key)
    }

    /// Settings offers a way back — consent has to be revocable to be real.
    func reset() {
        decision = nil
        defaults.removeObject(forKey: Self.key)
    }
}

/// The pre-first-use disclosure. Names the vendor, says exactly what leaves
/// the phone and what doesn't, and gives a real decline that doesn't break
/// the app.
struct AIDisclosureSheet: View {
    @EnvironmentObject private var disclosure: AIDisclosure
    @Environment(\.dismiss) private var dismiss
    @State private var showPolicy = false

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("BEFORE THE FIRST ONE")
                        .font(Font.Soma.sectionTag)
                        .tracking(3)
                        .foregroundStyle(Color.persimmon)

                    Text("soma reads your meal with help from Claude.")
                        .font(Font.Soma.pullQuote)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("when you log a meal, the words you type or say are sent to Claude — an AI model made by Anthropic — to turn “eggs on sourdough” into a structured entry with an estimated range. it comes straight back to you.")
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("and once a night, if there's enough to go on, soma sends Claude a compact summary of your last few weeks — meals, energy check-ins, and the daily Apple Health numbers you've connected — to look for patterns worth mentioning. never the raw health samples; those stay on your phone.")
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    bullets

                    Text("you can change your mind any time in the kitchen.")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.persimmon)

                    Button {
                        showPolicy = true
                    } label: {
                        Text("read the privacy policy")
                            .font(Font.Soma.margin)
                            .underline()
                            .foregroundStyle(Color.inkSoft)
                    }
                    .buttonStyle(.plain)

                    actionRow

                    Spacer(minLength: Theme.Spacing.xl)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showPolicy) {
            PrivacyPolicySheet()
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            row(sent: true,  "what you typed or said about a meal")
            row(sent: true,  "daily totals — sleep, steps, resting heart rate, HRV, weight — for the nightly look-back")
            row(sent: false, "your name, email, or account id")
            row(sent: false, "raw Apple Health samples — only the daily totals, never the readings behind them")
            row(sent: false, "your recordings — audio never leaves the phone")
        }
    }

    private func row(sent: Bool, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(sent ? "sent" : "never")
                .font(Font.Soma.sectionTag)
                .tracking(1)
                .foregroundStyle(sent ? Color.persimmon : Color.inkSoft)
                .frame(width: 46, alignment: .leading)
            Text(text)
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button {
                disclosure.accept()
                dismiss()
            } label: {
                Text("that's fine")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule(style: .continuous).fill(Color.ink))
            }
            .buttonStyle(.plain)

            Button {
                disclosure.decline()
                dismiss()
            } label: {
                Text("not now — I'll write meals out myself")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Spacing.s)
    }
}
