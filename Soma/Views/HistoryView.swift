import SwiftUI

/// History — the index-card box.
/// Each day is a card, the month is the box, tabs across the top let you
/// flip through. Tapping a day brings its card to the front.
struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()
    @State private var selectedDay: Int = Calendar.current.component(.day, from: Date())
    /// The day whose check-in sheet is open. Nil = dismissed.
    @State private var checkingIn: DayTarget?
    /// The day whose capture sheet is open — filing a meal onto a day that
    /// already happened. Nil = dismissed.
    ///
    /// Same family as TodayView's SOMA_PREVIEW_SHEET: a headless simulator
    /// run can open the ticket on yesterday, which is the state worth
    /// screenshotting — the backdated stamp and the time note only show up
    /// on a day that isn't today.
    @State private var loggingDay: DayTarget? = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW_SHEET"] == "capture" {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            return DayTarget(date: yesterday ?? Date())
        }
        #endif
        return nil
    }()
    /// Meal the card menu asked to remove, awaiting confirmation. Held
    /// here rather than on the card for the reason in `MealCardActions`.
    @State private var deletingMeal: Meal?

    /// A `Date` can't be a `.sheet(item:)` subject on its own — this is the
    /// smallest wrapper that makes a chosen day identifiable.
    private struct DayTarget: Identifiable {
        let date: Date
        var id: Date { date }
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack(spacing: Theme.Spacing.m) {
                        Text(vm.monthTitle)
                            .font(Font.Soma.dish)
                            .foregroundStyle(Color.ink)

                        Spacer()

                        Button {
                            Task { await page(by: -1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(vm.canPageBack ? Color.inkSoft : Color.inkSoft.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().stroke(Color.rule, lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.canPageBack)
                        .accessibilityLabel("Previous month")

                        Button {
                            Task { await page(by: 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(vm.canPageForward ? Color.inkSoft : Color.inkSoft.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().stroke(Color.rule, lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.canPageForward)
                        .accessibilityLabel("Next month")
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    MonthLedger(
                        loggedDays: vm.glyphByDay,
                        daysInMonth: vm.daysInMonth,
                        selected: $selectedDay
                    )
                    .padding(.horizontal, Theme.Spacing.xl)

                    DayCardStack(
                        day: selectedDay,
                        monthAnchor: vm.anchor,
                        meals: vm.meals(onDayOfMonth: selectedDay),
                        checkin: vm.checkin(onDayOfMonth: selectedDay),
                        checkinDate: vm.date(forDayOfMonth: selectedDay),
                        onDeleteRequest: { meal in deletingMeal = meal },
                        onCheckin: { date in checkingIn = DayTarget(date: date) },
                        onLog: { date in loggingDay = DayTarget(date: date) }
                    )
                        .padding(.horizontal, Theme.Spacing.xl)

                    if let err = vm.errorText {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Spacer(minLength: Theme.TabBar.scrollBottomInset)
                }
                .padding(.top, Theme.Spacing.l)
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
        .mealDeleteConfirmation(for: $deletingMeal) { meal in
            deletingMeal = nil
            Task { await vm.delete(meal) }
        }
        .sheet(item: $loggingDay) { target in
            CaptureSheet(
                day: target.date,
                recentDishes: vm.recentDishes,
                onSubmit: { transcript, source, eatenAt in
                    loggingDay = nil
                    Task { await vm.log(transcript: transcript, source: source, eatenAt: eatenAt) }
                },
                onRepeat: { dish, eatenAt in
                    loggingDay = nil
                    Task { await vm.repeatDish(dish, eatenAt: eatenAt) }
                },
                onCancel: { loggingDay = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $checkingIn) { target in
            DailyCheckinSheet(day: target.date) {
                Task { await vm.reloadCheckins() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func page(by months: Int) async {
        await vm.page(by: months)
        // Keep the selection meaningful in the new month: today when we're
        // back on the current month, else the first day.
        let cal = Calendar.current
        if cal.isDate(vm.anchor, equalTo: Date(), toGranularity: .month) {
            selectedDay = cal.component(.day, from: Date())
        } else {
            selectedDay = min(selectedDay, vm.daysInMonth)
        }
    }
}

#Preview {
    HistoryView()
}

// MARK: - Day card stack
// The selected day's meals as a small stack of recipe cards.

private struct DayCardStack: View {
    let day: Int
    let monthAnchor: Date
    let meals: [Meal]
    let checkin: DailyCheckin?
    /// The concrete date this card stands for. Nil only if the anchor month
    /// and day can't form a date, which the ledger never offers.
    let checkinDate: Date?
    var onDeleteRequest: (Meal) -> Void
    var onCheckin: (Date) -> Void
    /// Open the capture sheet against this day. Absent for days outside the
    /// window a meal can still be filed in.
    var onLog: (Date) -> Void

    /// The ledger runs past today in the current month, and only reaches
    /// back as far as the insight engine can see.
    private var loggableDate: Date? {
        guard let checkinDate, MealEntryWindow.isLoggableDay(checkinDate) else { return nil }
        return checkinDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(dayLabel(day))
                    .font(Font.Soma.dish)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(meals.count) plated")
                    .font(Font.Soma.caloric)
                    .foregroundStyle(Color.graphite)
            }
            .padding(.bottom, Theme.Spacing.xs)

            // Nothing to say about a day that hasn't happened yet — the
            // current month's ledger runs past today.
            if let checkinDate, !isFuture(checkinDate) {
                DayCheckinRow(
                    checkin: checkin,
                    // Days outside the check-in window still show what was
                    // filed; they just can't be edited any more.
                    canEdit: DailyCheckinViewModel.isEditable(checkinDate),
                    action: { onCheckin(checkinDate) }
                )
                .padding(.bottom, Theme.Spacing.xs)
            }

            if meals.isEmpty {
                // The invitation replaces the note where a meal can still
                // be filed — an empty day you can fill in shouldn't read
                // like a closed one.
                if let loggableDate {
                    PlateOnDayRow(hasMeals: false) { onLog(loggableDate) }
                } else {
                    EmptyDayNote()
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(meals, id: \.id) { meal in
                        RecipeCard(
                            timeLabel: meal.timeLabel,
                            dishName: meal.displayName,
                            calorieRange: meal.calorieRange,
                            macros: meal.macros,
                            aside: meal.isRepeat ? "a familiar one" : nil,
                            glyph: FoodGlyph.from(meal.displayName)
                        )
                        // No correction path back here — History is the
                        // index, not the kitchen — so the menu offers
                        // only "take it off the record."
                        .mealCardActions(for: meal, onDeleteRequest: onDeleteRequest)
                    }

                    MealCardHint(canCorrect: false)

                    if let loggableDate {
                        PlateOnDayRow(hasMeals: true) { onLog(loggableDate) }
                    }
                }
            }
        }
    }

    private func dayLabel(_ day: Int) -> String {
        "\(SomaFormat.monthName(monthAnchor)) \(day)"
    }

    private func isFuture(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: date) > cal.startOfDay(for: Date())
    }
}

// MARK: - The day's quiet check
// How the day felt, alongside what was eaten — and the way back into a
// check-in that got missed. Tapping opens the DailyCheckinSheet on this
// day rather than today.

private struct DayCheckinRow: View {
    let checkin: DailyCheckin?
    let canEdit: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text("◷")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(checkin == nil ? Color.inkSoft : Color.persimmon)

                if let checkin {
                    Text("energy \(checkin.energy)/5")
                        .font(Font.Soma.caloric)
                        .foregroundStyle(Color.graphite)
                    if let mood = checkin.mood, !mood.isEmpty {
                        Text(mood)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                    }
                } else {
                    Text("no check filed")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }

                Spacer(minLength: Theme.Spacing.s)

                if canEdit {
                    Text(checkin == nil ? "check in" : "edit")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.persimmon)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                    .strokeBorder(
                        (checkin == nil ? Color.rule.opacity(0.4) : Color.rule),
                        style: StrokeStyle(lineWidth: 0.8, dash: checkin == nil ? [3, 4] : [])
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityLabel(checkin == nil ? "Check in for this day" : "Edit this day's check-in")
    }
}

// MARK: - Filing a meal onto this day
// The way a meal that never got logged still gets onto the record. Same
// dashed, quiet shape as the check-in row above it: both are the day
// card admitting something is missing and offering to take it.

private struct PlateOnDayRow: View {
    /// Days that already have cards get the quieter phrasing — nothing is
    /// missing, there's just room for more.
    let hasMeals: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text("+")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(Color.persimmon)

                Text(hasMeals ? "something else that day?" : "no card filed for this day.")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)

                Spacer(minLength: Theme.Spacing.s)

                Text(hasMeals ? "add one" : "plate one")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.persimmon)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                    .strokeBorder(
                        Color.persimmon.opacity(0.55),
                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a meal to this day")
    }
}

private struct EmptyDayNote: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("—")
                .font(Font.Soma.dishSmall)
                .foregroundStyle(Color.inkSoft.opacity(0.5))
            Text("no card filed for this day.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .strokeBorder(Color.rule.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
        )
    }
}

// MARK: - Month ledger

private struct MonthLedger: View {
    let loggedDays: [Int: FoodGlyph]
    let daysInMonth: Int
    @Binding var selected: Int

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            let rows = Int(ceil(Double(daysInMonth) / 6.0))
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { col in
                        let day = row * 6 + col + 1
                        if day <= daysInMonth {
                            LedgerCell(
                                day: day,
                                glyph: loggedDays[day],
                                isSelected: day == selected
                            ) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    selected = day
                                }
                            }
                        } else {
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct LedgerCell: View {
    let day: Int
    let glyph: FoodGlyph?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(Font.Soma.stampTime)
                    .foregroundStyle(Color.graphite.opacity(0.8))
                if let glyph {
                    FoodGlyphView(glyph: glyph, size: 18, ink: Color.ink, stroke: 1.0)
                } else {
                    Circle()
                        .fill(Color.inkSoft.opacity(0.18))
                        .frame(width: 3, height: 3)
                        .frame(height: 18)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.persimmon, lineWidth: 1.0)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
