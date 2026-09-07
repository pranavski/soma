import SwiftUI

/// The ORDER UP ticket — speak it, type it, or tap a familiar one.
///
/// Lived inside `TodayView` while now was the only time a meal could
/// happen. It's shared now: History opens the same ticket pinned to a day
/// you picked out of the ledger, so a meal you forgot to log on Thursday
/// is filed by the same motions as one you're eating right now.
///
/// The "when" is part of the ticket rather than a mode: the stamp shows
/// what will be saved, and the picker beside it is bounded by
/// `MealEntryWindow` so no entry can land in the future or past the edge
/// of what the insight engine can see.
struct CaptureSheet: View {
    var recentDishes: [String]
    var onSubmit: (String, Meal.Source, Date) -> Void
    var onRepeat: (String, Date) -> Void
    var onCancel: () -> Void

    /// Frozen at open. The picker's bounds and the "is this today?" copy
    /// both read it, and a clock that moved mid-sentence would shuffle the
    /// range out from under the control.
    private let now: Date
    @State private var eatenAt: Date

    @StateObject private var speech = SpeechCapture()
    @State private var typed: String = ""
    @FocusState private var typedFocused: Bool

    /// `day` names the day this ticket files against — today from the Today
    /// screen, the selected card from History. The exact time inside that
    /// day comes from `MealEntryWindow.defaultWhen`.
    init(
        day: Date = Date(),
        now: Date = Date(),
        recentDishes: [String],
        onSubmit: @escaping (String, Meal.Source, Date) -> Void,
        onRepeat: @escaping (String, Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.now = now
        self.recentDishes = recentDishes
        self.onSubmit = onSubmit
        self.onRepeat = onRepeat
        self.onCancel = onCancel
        _eatenAt = State(initialValue: MealEntryWindow.defaultWhen(on: day, now: now))
    }

    /// Live source of truth for what we'd send to parse-meal. Mirrors the
    /// recognizer while it's running, otherwise the user's typed edits.
    private var workingText: String {
        speech.isRecording ? speech.transcript : typed
    }

    private var canSubmit: Bool {
        !workingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isBackdated: Bool {
        !Calendar.current.isDate(eatenAt, inSameDayAs: now)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("ORDER UP")
                        .font(Font.Soma.sectionTag)
                        .tracking(3)
                        .foregroundStyle(Color.ink)
                    Text("·")
                        .font(Font.Soma.sectionTag)
                        .foregroundStyle(Color.inkSoft)
                    Text(MealEntryWindow.stamp(for: eatenAt, now: now))
                        .font(Font.Soma.sectionTag)
                        .tracking(2)
                        // A stamp that isn't today's is an edit to the
                        // record — the one job persimmon has.
                        .foregroundStyle(isBackdated ? Color.persimmon : Color.inkSoft)
                }
                .padding(.top, Theme.Spacing.s)

                Text(isBackdated ? "tell me what you ate" : "tell me")
                    .font(Font.Soma.dayLine)
                    .foregroundStyle(Color.ink)

                whenRow

                transcriptField

                if let err = speech.errorText {
                    Text(err)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }

                if !recentDishes.isEmpty {
                    RepeatStrip(dishes: recentDishes) { dish in
                        onRepeat(dish, eatenAt)
                    }
                }

                Spacer(minLength: 0)

                actionRow
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { speech.stop() }
    }

    /// "when — [ Aug 23 ][ 1:15 PM ]". Always present, not just when
    /// backdating: logging dinner at bedtime is the same small correction
    /// as logging Thursday's lunch on Friday.
    private var whenRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Text("when —")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)

                DatePicker(
                    "when you ate",
                    selection: $eatenAt,
                    in: MealEntryWindow.range(now: now),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.persimmon)
                .onTapGesture { typedFocused = false }

                Spacer(minLength: 0)
            }

            // The hour isn't decoration — the insight rules read it — so
            // say so on the entries where it won't have set itself.
            if isBackdated {
                Text("set the time too — soma reads when you ate, not just what.")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transcriptField: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .strokeBorder(Color.rule, lineWidth: 0.6)

            if speech.isRecording {
                // Read-only mirror of the recognizer's output.
                Text(speech.transcript.isEmpty ? "listening…" : speech.transcript)
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(speech.transcript.isEmpty ? Color.inkSoft : Color.ink)
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("eggs on sourdough, avocado", text: $typed, axis: .vertical)
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(Color.ink)
                    .focused($typedFocused)
                    .lineLimit(3...6)
                    .padding(Theme.Spacing.l)
            }
        }
        .frame(minHeight: 120)
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                Task {
                    if speech.isRecording {
                        speech.stop()
                        typed = speech.transcript
                    } else {
                        typedFocused = false
                        speech.reset()
                        await speech.start()
                    }
                }
            } label: {
                Label(
                    speech.isRecording ? "stop" : "speak",
                    systemImage: speech.isRecording ? "stop.circle" : "mic"
                )
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .stroke(Color.ink, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                // Capture before stop() — stopping flips isRecording, which
                // would swap workingText back to the stale typed field.
                let payload = workingText.trimmingCharacters(in: .whitespacesAndNewlines)
                let fromVoice = speech.isRecording ||
                    (!speech.transcript.isEmpty &&
                     payload == speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
                speech.stop()
                guard !payload.isEmpty else { return }
                // The picker is bounded, but a sheet left open across the
                // minute it was opened in can still hand back a "now" that
                // has since become the past-tense kind of future.
                onSubmit(payload, fromVoice ? .voice : .manual,
                         MealEntryWindow.clamp(eatenAt))
            } label: {
                Text("send")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canSubmit ? Color.ink : Color.inkSoft.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }
}

// MARK: - Repeat-a-meal chip strip
// Small horizontal chips of recently-eaten dishes. Tapping inserts a
// pending meal with source='repeat', copying the dish's dish_name so the
// insight engine can attribute the repeat correctly.

struct RepeatStrip: View {
    let dishes: [String]
    var onRepeat: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("a familiar one")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(dishes, id: \.self) { dish in
                        Button {
                            onRepeat(dish)
                        } label: {
                            Text(dish)
                                .font(Font.Soma.dishSmall)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .stroke(Color.rule, lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
