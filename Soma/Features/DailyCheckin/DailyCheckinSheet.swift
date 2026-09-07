import SwiftUI

/// One-tap-per-day energy + mood check-in.
/// The 0…5 scale is the input for the tier-0 insight rules — it MUST stay
/// this shape (see insight-rules skill; the late_eat_energy and
/// repeat_dish_energy rules read `energy` as an integer 0…5).
///
/// Opens on today by default; the stamp in the header is a day stepper so a
/// day that got missed can still be filled in (back as far as
/// `DailyCheckinViewModel.maxLookbackDays`).
struct DailyCheckinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: DailyCheckinViewModel
    /// Fired after a successful save so the presenting screen can refresh —
    /// Today drops its nudge, History re-reads the day's check.
    private let onSave: (() -> Void)?

    init(day: Date = Date(), onSave: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: DailyCheckinViewModel(day: day))
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                    .padding(.top, Theme.Spacing.s)

                Text(vm.isToday ? "how's the day?" : "how was the day?")
                    .font(Font.Soma.dayLine)
                    .foregroundStyle(Color.ink)

                energyScale

                moodField

                if let err = vm.errorText {
                    Text(err)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.persimmon)
                }

                Spacer(minLength: 0)

                actionRow
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await vm.load() }
    }

    /// "QUIET CHECK · ‹ SUN, AUG 2 ›" — the stamp doubles as the day
    /// stepper. Chevrons stay in place when they can't move so the header
    /// doesn't reflow as you walk backwards through the week.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Text("QUIET CHECK")
                    .font(Font.Soma.sectionTag)
                    .tracking(3)
                    .foregroundStyle(Color.ink)
                Text("·")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(Color.inkSoft)

                stepButton(days: -1, symbol: "chevron.left", enabled: vm.canStepBack)
                    .accessibilityLabel("Previous day")

                Text(SomaFormat.shortStamp(vm.day))
                    .font(Font.Soma.sectionTag)
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
                    .frame(minWidth: 92)
                    .animation(nil, value: vm.day)

                stepButton(days: 1, symbol: "chevron.right", enabled: vm.canStepForward)
                    .accessibilityLabel("Next day")
            }

            if !vm.isToday {
                Text("filling in a day you missed.")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.persimmon)
            }
        }
    }

    private func stepButton(days: Int, symbol: String, enabled: Bool) -> some View {
        Button {
            Task { await vm.step(by: days) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? Color.inkSoft : Color.inkSoft.opacity(0.3))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || vm.isLoading || vm.isSaving)
    }

    private var energyScale: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("energy — 0 flat, 5 lit up")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)

            HStack(spacing: Theme.Spacing.m) {
                ForEach(0...5, id: \.self) { n in
                    Button {
                        vm.energy = n
                    } label: {
                        Text("\(n)")
                            .font(Font.Soma.dish)
                            .foregroundStyle(vm.energy == n ? Color.paper : Color.ink)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(vm.energy == n ? Color.ink : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.ink, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var moodField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("a word, if you'd like")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                    .strokeBorder(Color.rule, lineWidth: 0.6)
                TextField("bright / slow / distracted", text: $vm.mood)
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(Color.ink)
                    .padding(Theme.Spacing.l)
            }
            .frame(minHeight: 56)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("not now") { dismiss() }
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.inkSoft)
                .buttonStyle(.plain)

            Spacer()

            Button {
                Task {
                    let ok = await vm.save()
                    if ok {
                        onSave?()
                        dismiss()
                    }
                }
            } label: {
                Text(vm.alreadyLogged ? "update" : "save")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(Capsule(style: .continuous).fill(Color.ink))
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving || vm.isLoading)
        }
    }
}

#Preview("today") {
    DailyCheckinSheet()
}

#Preview("a missed day") {
    DailyCheckinSheet(day: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date())
}
