import SwiftUI

/// Insights — the home page. The app is an insight engine first, so the
/// feed of hedged findings opens the app: ranked lab pages, a 30-day body
/// trend beneath them, and a quick-log field pinned within thumb's reach.
///
/// Tone rules carried from the copy contract: findings are hedged, the
/// persimmon caption carries the hedge, empty states explain honestly,
/// and nothing here ever prescribes.
struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HeaderBlock(date: Date())
                        .padding(.top, Theme.Spacing.l)
                        .padding(.horizontal, Theme.Spacing.xl)

                    if vm.isGenerating {
                        ThinkingRow()
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    if vm.insights.isEmpty {
                        if !vm.isLoading && !vm.isGenerating {
                            EmptyFeedPage(note: vm.emptyStateNote)
                                .padding(.horizontal, Theme.Spacing.xl)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                            SectionHeader(text: "noticed, lately")

                            ForEach(vm.insights) { insight in
                                InsightFeedCard(insight: insight)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.xl)
                    }

                    TrendChart()
                        .id("trend")
                        .padding(.horizontal, Theme.Spacing.xl)

                    if let err = vm.errorText {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    InkRule(style: .dotted, color: Color.rule, weight: 1.1)
                        .frame(height: 6)
                        .padding(.horizontal, Theme.Spacing.xl)

                    // Room for the pinned quick-log field + tab bar.
                    Spacer(minLength: 170)
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            // Same family as SOMA_PREVIEW_TAB in RootView: lets headless
            // simulator runs land on a given anchor for screenshots.
            .onAppear {
                #if DEBUG
                if let target = ProcessInfo.processInfo.environment["SOMA_PREVIEW_SCROLL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                    }
                }
                #endif
            }
            }

            VStack {
                Spacer()
                QuickLogField()
                    .padding(.horizontal, Theme.Spacing.xl)
                    // Paper fade behind the pinned field so scrolled card
                    // text doesn't read through the gap above the tab bar.
                    .background {
                        LinearGradient(
                            colors: [
                                Color.paper.opacity(0),
                                Color.paper.opacity(0.92),
                                Color.paper
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .padding(.horizontal, -Theme.Spacing.xl)
                        .padding(.top, -Theme.Spacing.l)
                        .allowsHitTesting(false)
                    }
            }
        }
    }
}

#Preview {
    InsightsView()
}

// MARK: - Header
// Same single left-aligned block as Today — this is the front door now,
// so the wordmark lives here.

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

// MARK: - Thinking row (generation in flight)

private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.inkSoft)
            Text("thinking about your last few weeks…")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
        }
    }
}

// MARK: - Feed card
// One finding on tipped-in lab paper. Claim is the serif headline,
// evidence the quiet second line, the persimmon caption carries the
// hedge, and a suggested action (when present) sits as a dotted-off
// footer aside — an option, never an instruction.

private struct InsightFeedCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                ConfidenceBadge(level: insight.confidence)
                Spacer()
                Text("LAST \(insight.windowDays) DAYS")
                    .font(Font.Soma.sectionTag)
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
            }

            Text(insight.claim)
                .font(Font.Soma.pullQuote)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(insight.evidence)
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(insight.hedgeCaption)
                .font(Font.Soma.margin)
                .foregroundStyle(Color.persimmon)

            if let action = insight.suggestedAction {
                InkRule(style: .dotted, color: Color.rule, weight: 0.8)
                    .frame(height: 4)

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("↳")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                    Text(action)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Spacing.l + 2)
        .background(labPaper)
        .shadow(color: Color.paperShadow.opacity(0.45), radius: 10, x: 1, y: 6)
    }

    private var labPaper: some View {
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

// MARK: - Confidence badge
// Ink-intensity scale, not traffic lights: low fades into the margin,
// high is full ink. Persimmon stays reserved for the hedge caption;
// bay stays reserved for body data.

private struct ConfidenceBadge: View {
    let level: Insight.Confidence

    var body: some View {
        Text(label.uppercased())
            .font(Font.Soma.sectionTag)
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.s + 2)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(color.opacity(0.5), lineWidth: Theme.Stroke.hairline)
            )
    }

    private var label: String {
        switch level {
        case .high:   return "keeps showing up"
        case .medium: return "taking shape"
        case .low:    return "a quiet hunch"
        }
    }

    private var color: Color {
        switch level {
        case .high:   return Color.ink
        case .medium: return Color.graphite
        case .low:    return Color.inkSoft
        }
    }
}

// MARK: - Empty state (honest, hedged, never shame)

private struct EmptyFeedPage: View {
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

            Text("patterns need a little more to go on.")
                .font(Font.Soma.pullQuote)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(note)
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.inkSoft)
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
    }
}
