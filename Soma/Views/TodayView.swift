import SwiftUI

struct TodayView: View {
    @StateObject private var vm = TodayViewModel()
    /// Same family as showCheckin below: a headless simulator run can open
    /// the ORDER UP ticket for a screenshot.
    @State private var showCapture: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SOMA_PREVIEW_SHEET"] == "capture"
        #else
        return false
        #endif
    }()
    /// Same family as SOMA_PREVIEW_TAB in RootView: lets a headless
    /// simulator run open the check-in sheet for a screenshot.
    @State private var showCheckin: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SOMA_PREVIEW_SHEET"] == "checkin"
        #else
        return false
        #endif
    }()
    /// Meal currently being corrected via the "not quite right?" sheet.
    /// Nil = sheet dismissed. We hold the whole `Meal` (not just id) so
    /// the sheet can pre-fill fields without another round-trip.
    @State private var correctingMeal: Meal?
    /// Meal the card menu asked to remove, awaiting confirmation. Held
    /// here rather than on the card for the reason in `MealCardActions`.
    @State private var deletingMeal: Meal?
    /// 0 = wax paper lifted, 1 = yesterday laid over today. Driven by the
    /// "compare" pill in the header; see `WaxPaperOverlay`.
    @State private var waxProgress: Double = {
        #if DEBUG
        // Same family as SOMA_PREVIEW_SHEET: a headless run can open the
        // wax paper for a screenshot.
        return ProcessInfo.processInfo.environment["SOMA_PREVIEW_COMPARE"] == "1" ? 1 : 0
        #else
        return 0
        #endif
    }()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HeaderBlock(
                        date: vm.now,
                        // Nothing to lay over today if yesterday has no cards.
                        compare: vm.mealsYesterday.isEmpty ? nil : toggleWaxPaper,
                        isComparing: waxProgress > 0.5
                    )
                        .padding(.top, Theme.Spacing.l)
                        .padding(.horizontal, Theme.Spacing.xl)

                    PhaseQuote(now: vm.now)
                        .padding(.horizontal, Theme.Spacing.xl)

                    if vm.needsCheckin {
                        CheckinNudge { showCheckin = true }
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    CardStream(
                        meals: vm.meals,
                        repeats: vm.recentDishes,
                        onRepeat: { dish in Task { await vm.repeatDish(dish, eatenAt: Date()) } },
                        onCorrect: { meal in correctingMeal = meal },
                        onDeleteRequest: { meal in deletingMeal = meal }
                    )
                        .padding(.horizontal, Theme.Spacing.xl)

                    NextSlot(now: vm.now)
                        .padding(.horizontal, Theme.Spacing.xl)

                    if let err = vm.errorText {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Spacer(minLength: Theme.TabBar.scrollBottomInset)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            // Coming back from the background after midnight has to re-date
            // the screen; without this the header keeps yesterday's day.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await vm.load() }
            }

            // Yesterday, laid over today. Sits under the capture pill so
            // "tell me" stays reachable with the sheet down.
            WaxPaperOverlay(
                mealsYesterday: vm.mealsYesterday,
                progress: waxProgress,
                onLift: toggleWaxPaper
            )

            VStack {
                Spacer()
                CaptureButton {
                    showCapture = true
                }
                // Sit above the tab strip in RootView. Shared constant so the
                // pill and the bar can't drift apart.
                .padding(.bottom, Theme.TabBar.contentClearance)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet(
                recentDishes: vm.recentDishes,
                onSubmit: { transcript, source, eatenAt in
                    showCapture = false
                    Task { await vm.submit(transcript: transcript, source: source, eatenAt: eatenAt) }
                },
                onRepeat: { dish, eatenAt in
                    showCapture = false
                    Task { await vm.repeatDish(dish, eatenAt: eatenAt) }
                },
                onCancel: { showCapture = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCheckin) {
            DailyCheckinSheet {
                // Drop the nudge as soon as the check is filed — the screen
                // otherwise keeps asking until the next full reload.
                Task { await vm.load() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .mealDeleteConfirmation(for: $deletingMeal) { meal in
            deletingMeal = nil
            Task { await vm.delete(meal) }
        }
        .sheet(item: $correctingMeal) { meal in
            CorrectionSheet(meal: meal) {
                Task { await vm.load() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Lay the wax paper down or peel it off. A soft spring, or a cut when
    /// the person has asked for less motion.
    private func toggleWaxPaper() {
        let target: Double = waxProgress > 0.5 ? 0 : 1
        if reduceMotion {
            waxProgress = target
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                waxProgress = target
            }
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
// Left-aligned: weekday/date line + logo. The only thing on the right is
// the "compare" pill, and only when yesterday has cards to lay over today.

private struct HeaderBlock: View {
    let date: Date
    /// Nil hides the pill.
    var compare: (() -> Void)? = nil
    var isComparing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(SomaFormat.longDay(date))
                    .font(Font.Soma.dateLabel)
                    .foregroundStyle(Color.inkSoft)
                Spacer(minLength: Theme.Spacing.m)
                if let compare {
                    WaxPaperToggleButton(isOn: isComparing, action: compare)
                        .accessibilityLabel(isComparing ? "Lift yesterday off today" : "Compare with yesterday")
                }
            }

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
}

// MARK: - Phase quote
// Reduced to a single line — no signature, no "the day so far —" prefix.
// The recipe cards carry the personality; the headline is one beat of voice.

private struct PhaseQuote: View {
    let now: Date

    var body: some View {
        Text(phaseHeadline)
            .font(Font.Soma.pullQuote)
            .foregroundStyle(Color.inkSoft)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var phaseHeadline: String {
        switch Calendar.current.component(.hour, from: now) {
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
    var onDeleteRequest: (Meal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(meals, id: \.id) { meal in
                RecipeCard(
                    timeLabel: meal.timeLabel,
                    dishName: meal.displayName,
                    calorieRange: meal.calorieRange,
                    macros: meal.macros,
                    detail: meal.stimulantNote,
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
                // "Not quite right?" — bottom-right of every card except one
                // still parsing. That covers the AI's guess, a failed parse,
                // a meal filed with consent off (nothing but the person's
                // words), and a meal corrected once already. Same gate as
                // `MealCardActions.canCorrect`.
                .overlay(alignment: .bottomTrailing) {
                    if meal.parseStatus != .pending {
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
                .mealCardActions(
                    for: meal,
                    onCorrect: onCorrect,
                    onDeleteRequest: onDeleteRequest
                )
            }

            if !meals.isEmpty {
                MealCardHint()
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
        VStack(alignment: .leading, spacing: 4) {
            Text("now — \(SomaFormat.time(now).lowercased())")
                .font(Font.Soma.timestamp)
                .foregroundStyle(Color.persimmon)
            Text("nothing plated yet")
                .font(Font.Soma.dishSmall)
                .foregroundStyle(Color.inkSoft.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Text("tap tell me when you eat next.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Card.bodyInset)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        // minHeight, not height: at accessibility text sizes a fixed 96
        // let the three lines spill straight out of the dashed border.
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .strokeBorder(
                    Color.persimmon.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 5])
                )
        )
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


#Preview {
    TodayView()
}
