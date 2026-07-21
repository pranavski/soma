import SwiftUI

/// Insights — the tipped-in lab page.
///
/// The finding lives on a slightly different paper stock. Hedged sentence,
/// persimmon caption carrying the hedge, small ledger of prior weeks.
/// When there's no insight, we say so plainly — no fake finding, ever.
struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let insight = vm.latest {
                        TippedInLabPage(
                            finding: insight.copy,
                            confidence: insight.hedgeCaption,
                            weekLabel: weekLabel(for: insight.weekStart, tier: insight.tier)
                        )
                        .padding(.horizontal, Theme.Spacing.xl)

                        if !vm.prior.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                                SectionHeader(text: "quieter notes")
                                    .padding(.horizontal, Theme.Spacing.xl)

                                ForEach(vm.prior, id: \.id) { note in
                                    QuietNote(
                                        note: note.copy,
                                        aside: priorWeekLabel(note.weekStart)
                                    )
                                    .padding(.horizontal, Theme.Spacing.xl)
                                }
                            }
                        }
                    } else {
                        EmptyLabPage(note: vm.emptyStateNote)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    if let err = vm.errorText {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    GentleFooter()
                        .padding(.horizontal, Theme.Spacing.xl)

                    Spacer(minLength: 140)
                }
                .padding(.top, Theme.Spacing.l)
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    private func weekLabel(for weekStart: Date, tier: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "'WEEK OF' MMM d"
        let base = f.string(from: weekStart).uppercased()
        return "\(base) · TIER \(tier)"
    }

    private func priorWeekLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "'week of' MMM d"
        return f.string(from: date)
    }
}

#Preview {
    InsightsView()
}

// MARK: - Tipped-in lab page (finding present)

private struct TippedInLabPage: View {
    let finding: String
    let confidence: String
    let weekLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.s) {
                Text("◷")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(Color.inkSoft)
                Text(weekLabel)
                    .font(Font.Soma.sectionTag)
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(finding)
                    .font(Font.Soma.pullQuote)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(confidence)
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.persimmon)
            }
        }
        .padding(Theme.Spacing.l + 2)
        .background(labPaper)
        .shadow(color: Color.paperShadow.opacity(0.50), radius: 12, x: 1, y: 8)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var labPaper: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.paperRaised)
                .overlay(
                    RuledPaper(rule: 14, color: Color.cardRule.opacity(0.10), inset: 0)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color.rule.opacity(0.55), lineWidth: Theme.Stroke.hairline)
                )
        }
    }
}

// MARK: - Empty state (honest, hedged, not a fake finding)

private struct EmptyLabPage: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.s) {
                Text("◷")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(Color.inkSoft)
                Text("NOTHING TO SURFACE YET")
                    .font(Font.Soma.sectionTag)
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
            }

            Text(note)
                .font(Font.Soma.pullQuote)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("keep logging — insights arrive quietly.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.persimmon)
        }
        .padding(Theme.Spacing.l + 2)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.paperRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color.rule.opacity(0.55), lineWidth: Theme.Stroke.hairline)
                )
        )
        .shadow(color: Color.paperShadow.opacity(0.35), radius: 10, x: 0, y: 6)
        .padding(.vertical, Theme.Spacing.s)
    }
}

private struct QuietNote: View {
    let note: String
    let aside: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note)
                .font(Font.Soma.dishSmall)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)

            Text(aside)
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GentleFooter: View {
    var body: some View {
        InkRule(style: .dotted, color: Color.rule, weight: 1.1)
            .frame(height: 6)
    }
}
