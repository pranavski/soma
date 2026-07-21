import SwiftUI

/// One-tap-per-day energy + mood check-in.
/// The 0…5 scale is the input for the tier-0 insight rules — it MUST stay
/// this shape (see insight-rules skill; the late_eat_energy and
/// repeat_dish_energy rules read `energy` as an integer 0…5).
struct DailyCheckinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = DailyCheckinViewModel()

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("QUIET CHECK")
                        .font(Font.Soma.sectionTag)
                        .tracking(3)
                        .foregroundStyle(Color.ink)
                    Text("·")
                        .font(Font.Soma.sectionTag)
                        .foregroundStyle(Color.inkSoft)
                    Text(dateStamp())
                        .font(Font.Soma.sectionTag)
                        .tracking(2)
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(.top, Theme.Spacing.s)

                Text("how's the day?")
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
                    if ok { dismiss() }
                }
            } label: {
                Text(vm.alreadyLoggedToday ? "update" : "save")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(Capsule(style: .continuous).fill(Color.ink))
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving)
        }
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date()).uppercased()
    }
}

#Preview {
    DailyCheckinSheet()
}
