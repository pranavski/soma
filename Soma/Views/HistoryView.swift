import SwiftUI

/// History — the index-card box.
/// Each day is a card, the month is the box, tabs across the top let you
/// flip through. Tapping a day brings its card to the front.
struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()
    @State private var selectedDay: Int = Calendar.current.component(.day, from: Date())

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
                                .foregroundStyle(Color.inkSoft)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().stroke(Color.rule, lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
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
                        meals: vm.meals(onDayOfMonth: selectedDay)
                    )
                        .padding(.horizontal, Theme.Spacing.xl)

                    if let err = vm.errorText {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Spacer(minLength: 160)
                }
                .padding(.top, Theme.Spacing.l)
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
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

            if meals.isEmpty {
                EmptyDayNote()
            } else {
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
                    }
                }
            }
        }
    }

    private func dayLabel(_ day: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        let month = f.string(from: monthAnchor).lowercased()
        return "\(month) \(day)"
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
