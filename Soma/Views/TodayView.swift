import PhotosUI
import SwiftUI

struct TodayView: View {
    @StateObject private var vm = TodayViewModel()
    @State private var showCapture = false
    @State private var showCheckin = false
    /// Meal currently being corrected via the "not quite right?" sheet.
    /// Nil = sheet dismissed. We hold the whole `Meal` (not just id) so
    /// the sheet can pre-fill fields without another round-trip.
    @State private var correctingMeal: Meal?

    private let now = Date()

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HeaderBlock(date: now)
                        .padding(.top, Theme.Spacing.l)
                        .padding(.horizontal, Theme.Spacing.xl)

                    PhaseQuote()
                        .padding(.horizontal, Theme.Spacing.xl)

                    if vm.needsCheckin {
                        CheckinNudge { showCheckin = true }
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    CardStream(
                        meals: vm.meals,
                        repeats: vm.recentDishes,
                        onRepeat: { dish in Task { await vm.repeatDish(dish) } },
                        onCorrect: { meal in correctingMeal = meal }
                    )
                        .padding(.horizontal, Theme.Spacing.xl)

                    NextSlot(now: now)
                        .padding(.horizontal, Theme.Spacing.xl)

                    if let err = vm.errorText {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Spacer(minLength: 140)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }

            VStack {
                Spacer()
                CaptureButton {
                    showCapture = true
                }
                // The SomaTabBar in RootView overlays the bottom ~86pt of
                // this view. Push the capture pill above the bar so it isn't
                // eaten by the tab strip.
                .padding(.bottom, 96)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet(
                recentDishes: vm.recentDishes,
                onSubmit: { transcript, source in
                    showCapture = false
                    Task { await vm.submit(transcript: transcript, source: source) }
                },
                onPhoto: { image in
                    showCapture = false
                    Task { await vm.submitPhoto(image) }
                },
                onRepeat: { dish in
                    showCapture = false
                    Task { await vm.repeatDish(dish) }
                },
                onCancel: { showCapture = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCheckin) {
            DailyCheckinSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $correctingMeal) { meal in
            CorrectionSheet(meal: meal) {
                Task { await vm.load() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Quiet-check nudge
// Shown once a day when the user hasn't logged their energy check-in yet.
// Tapping opens the DailyCheckinSheet.

private struct CheckinNudge: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text("◷")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(Color.persimmon)
                Text("a quiet check — how's the day going?")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("check in")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.persimmon)
            }
            .padding(Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                    .stroke(Color.persimmon.opacity(0.55), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header
// Single left-aligned row: weekday/date line + logo. Nothing on the right.

private struct HeaderBlock: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(weekdayHand(date))
                .font(Font.Soma.dateLabel)
                .foregroundStyle(Color.inkSoft)

            HStack(spacing: 0) {
                Text("Soma")
                    .font(Font.Soma.logo)
                    .foregroundStyle(Color.ink)
                Text(".")
                    .font(Font.Soma.logo)
                    .foregroundStyle(Color.persimmon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekdayHand(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: d).lowercased()
    }
}

// MARK: - Phase quote
// Reduced to a single line — no signature, no "the day so far —" prefix.
// The recipe cards carry the personality; the headline is one beat of voice.

private struct PhaseQuote: View {
    private let hour = Calendar.current.component(.hour, from: Date())

    var body: some View {
        Text(phaseHeadline)
            .font(Font.Soma.pullQuote)
            .foregroundStyle(Color.inkSoft)
            .lineSpacing(2)
    }

    private var phaseHeadline: String {
        switch hour {
        case 5..<12:  return "A new morning."
        case 12..<14: return "Midday, quietly."
        case 14..<17: return "Afternoon things."
        case 17..<21: return "Evening, settling."
        default:      return "A late hour."
        }
    }
}

// MARK: - Card stream
// The recipe-card stream — one card per meal. Flat, no tilt, no wash.

private struct CardStream: View {
    let meals: [Meal]
    let repeats: [String]
    var onRepeat: (String) -> Void
    var onCorrect: (Meal) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ForEach(meals, id: \.id) { meal in
                RecipeCard(
                    timeLabel: meal.timeLabel,
                    dishName: meal.displayName,
                    calorieRange: meal.calorieRange,
                    macros: meal.macros,
                    aside: meal.isRepeat ? "a familiar one" : nil,
                    glyph: FoodGlyph.from(meal.displayName)
                )
                .overlay(alignment: .topTrailing) {
                    if meal.parseStatus == .pending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.inkSoft)
                            .padding(Theme.Spacing.m)
                    }
                }
                // "Not quite right?" — bottom-right of every card that has
                // an AI-derived guess. Hidden while parsing and on
                // manually-entered rows since there's nothing to correct.
                .overlay(alignment: .bottomTrailing) {
                    if meal.parseStatus == .parsed || meal.parseStatus == .failed {
                        Button {
                            onCorrect(meal)
                        } label: {
                            Text("not quite right?")
                                .font(Font.Soma.margin)
                                .foregroundStyle(Color.persimmon)
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.paperRaised.opacity(0.9))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.persimmon.opacity(0.4), lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Correct this meal")
                        .padding(Theme.Spacing.m)
                    }
                }
            }
        }
    }
}

// MARK: - Next slot
// An *empty* card-shaped slot for "what comes next." The Mise version
// of the now marker — instead of a pulsing dot on a timeline, it's an
// awaiting recipe card.

private struct NextSlot: View {
    let now: Date

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .strokeBorder(
                    Color.persimmon.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 5])
                )
                .frame(height: 96)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("now — \(handTime(now).lowercased())")
                        .font(Font.Soma.timestamp)
                        .foregroundStyle(Color.persimmon)
                    Spacer()
                }
                Text("nothing plated yet")
                    .font(Font.Soma.dishSmall)
                    .foregroundStyle(Color.inkSoft.opacity(0.85))
                Text("tap tell me when you eat next.")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.horizontal, Theme.Card.bodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

// MARK: - Capture button (fountain pen feel)

private struct CaptureButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                NibMark()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.paper)
                Text("tell me")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
            }
            .padding(.horizontal, Theme.Spacing.xl + 4)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.ink)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.persimmon.opacity(0.45), lineWidth: 1)
                    .blur(radius: 0.4)
                    .offset(y: 0.5)
            )
            .shadow(color: Color.paperShadow.opacity(0.6), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(.plain)
    }
}

private struct NibMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.08)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY + 2))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + 2))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.midX, y: r.minY + 4))
        p.addLine(to: CGPoint(x: r.midX, y: r.midY + 4))
        return p
    }
}

// MARK: - Capture sheet — ORDER UP ticket

private struct CaptureSheet: View {
    var recentDishes: [String]
    var onSubmit: (String, Meal.Source) -> Void
    var onPhoto: (UIImage) -> Void
    var onRepeat: (String) -> Void
    var onCancel: () -> Void

    @StateObject private var speech = SpeechCapture()
    @State private var typed: String = ""
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var typedFocused: Bool

    /// Live source of truth for what we'd send to parse-meal. Mirrors the
    /// recognizer while it's running, otherwise the user's typed edits.
    private var workingText: String {
        speech.isRecording ? speech.transcript : typed
    }

    private var canSubmit: Bool {
        !workingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    Text(stampedTime())
                        .font(Font.Soma.sectionTag)
                        .tracking(2)
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(.top, Theme.Spacing.s)

                Text("tell me")
                    .font(Font.Soma.dayLine)
                    .foregroundStyle(Color.ink)

                transcriptField

                photoRow

                if let err = speech.errorText {
                    Text(err)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }

                if !recentDishes.isEmpty {
                    RepeatStrip(dishes: recentDishes, onRepeat: onRepeat)
                }

                Spacer(minLength: 0)

                actionRow
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { speech.stop() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in onPhoto(image) }
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onPhoto(image)
                }
                photoItem = nil
            }
        }
    }

    /// "or show me" — camera + library entry points. The camera chip hides
    /// itself where no camera exists (simulator); the library chip is the
    /// out-of-process PhotosPicker, so no permission prompt is needed.
    private var photoRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("or show me")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)

            if CameraPicker.isAvailable {
                Button {
                    typedFocused = false
                    showCamera = true
                } label: {
                    photoChip("camera", "snap it")
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                photoChip("photo.on.rectangle", "from photos")
            }
            .buttonStyle(.plain)
        }
    }

    private func photoChip(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol)
            .font(Font.Soma.dishSmall)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color.ink)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .stroke(Color.rule, lineWidth: 0.6)
            )
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
                onSubmit(payload, fromVoice ? .voice : .manual)
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

    private func stampedTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date()).uppercased()
    }
}

// MARK: - Repeat-a-meal chip strip
// Small horizontal chips of recently-eaten dishes. Tapping inserts a
// pending meal with source='repeat', copying the dish's dish_name so the
// insight engine can attribute the repeat correctly.

private struct RepeatStrip: View {
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

#Preview {
    TodayView()
}
