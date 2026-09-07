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
/// filed as written — a `manual` row titled with the person's own words, no
/// estimate — and the correction sheet fills in the details by hand. (See
/// `MealLogger.log`; a `pending` row would spin forever with nothing coming
/// to finish it.)
///
/// **The storage key is versioned on purpose.** Consent is to a described
/// flow, not to a vendor in the abstract, so when what leaves the phone
/// changes (a new recipient, a new kind of data), bump the version: the old
/// answer stops covering it and everyone is asked again. 5.1.2(i) is
/// explicit that a privacy-policy mention doesn't stand in for asking.
///
/// **The answer is also written to the server.** The nightly look-back runs
/// server-side with no phone in the loop, so `generate-insights` and the
/// cron that enqueues it read the `ai_consent` row, not UserDefaults. Every
/// accept/decline is pushed through `publish`, and `syncToServer()` re-pushes
/// the current answer on sign-in so a write that failed offline heals.
/// Until the row says yes, the server treats the person as declined.
@MainActor
final class AIDisclosure: ObservableObject {
    /// Pushes a decision to the server. Injected so tests never touch the
    /// network; the shared instance writes through `AIConsentRepository`.
    typealias Publisher = @Sendable (Bool) async throws -> Void

    static let shared = AIDisclosure(publish: { consented in
        try await AIConsentRepository().set(consented: consented)
    })

    /// Version of the described flow. Shared with the UserDefaults key, the
    /// `ai_consent.consent_version` column and `generate-insights`; a wider
    /// flow bumps it everywhere and everyone is asked again.
    static let consentVersion = "v1"

    private static let key = "soma.ai.parseConsent.\(consentVersion)"

    /// nil = never answered (show the sheet), true = agreed, false = declined.
    @Published private(set) var decision: Bool?

    private let defaults: UserDefaults
    private let publish: Publisher?

    init(defaults: UserDefaults = .standard, publish: Publisher? = nil) {
        self.defaults = defaults
        self.publish = publish
        self.decision = defaults.object(forKey: Self.key) as? Bool
    }

    var hasConsented: Bool { decision == true }
    var hasAnswered: Bool { decision != nil }

    func accept() {
        decision = true
        defaults.set(true, forKey: Self.key)
        push(true)
    }

    func decline() {
        decision = false
        defaults.set(false, forKey: Self.key)
        push(false)
    }

    /// Settings offers a way back — consent has to be revocable to be real.
    /// Local only: sign-out calls this, and the server row belongs to the
    /// account, not the phone. It is rewritten the next time that account
    /// answers or signs in.
    func reset() {
        decision = nil
        defaults.removeObject(forKey: Self.key)
    }

    /// Re-push the current answer. Called once per sign-in; idempotent.
    func syncToServer() {
        guard let decision else { return }
        push(decision)
    }

    private func push(_ consented: Bool) {
        guard let publish else { return }
        Task {
            do {
                try await publish(consented)
            } catch {
                // Retried on the next sign-in. A failed decline is the case
                // that matters: the server keeps the previous answer until
                // then, so say so in the log rather than swallowing it.
                print("AIDisclosure: consent sync failed — \(error.localizedDescription)")
            }
        }
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
            row(sent: true,  "daily totals — sleep, steps, resting heart rate, HRV, weight, active energy, workout minutes — for the nightly look-back")
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
