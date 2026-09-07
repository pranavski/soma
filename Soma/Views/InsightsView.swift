import SwiftUI

/// Insights — the home page. The app is an insight engine first, so the
/// feed of hedged findings opens the app: ranked lab pages with a 30-day
/// body trend beneath them.
///
/// Read-only on purpose. Logging lives on Today, behind "tell me" — one
/// place to write a meal down means one path to get it right, and this
/// page stays what it says it is: what Soma noticed, not another box to
/// type into.
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
                            // One block or the other, never both: they would
                            // otherwise say "nothing yet" twice in a row.
                            // The reflections block carries the same note in
                            // its footer when it wins.
                            if vm.showsReflections {
                                ReflectionsBlock(
                                    reflections: vm.reflections,
                                    note: vm.emptyStateNote
                                )
                                .padding(.horizontal, Theme.Spacing.xl)
                            } else {
                                EmptyFeedPage(note: vm.emptyStateNote)
                                    .padding(.horizontal, Theme.Spacing.xl)
                            }
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

                    // On the screen where the claims live, not only in the
                    // kitchen footer: once cards cite journals, the reader
                    // has to be told here what they are not.
                    Text("not medical advice. soma surfaces patterns, not diagnoses. talk to a clinician for anything that matters.")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft.opacity(0.85))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.xl)

                    Spacer(minLength: Theme.TabBar.scrollBottomInset)
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
            Text(SomaFormat.longDay(date))
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

// MARK: - Published context
//
// The one block on this card that is not Soma talking. Everything else is
// an observation about this person's own 30 days, hedged because it has to
// be; this is established physiology with a citation under it.
//
// So it is styled as a clipping pasted into the notebook rather than more
// of the page: recessed paper (`paperSunk`), a mono eyebrow, and the
// citation set small underneath. The visual break is doing real work — a
// reader should never have to wonder which sentence is about them and
// which is about people in general.
//
// Never rendered without a citation (see `Insight.publishedContext`), and
// never rendered for a finding that ran counter to the literature — the
// server omits the whole block in that case rather than explaining the
// opposite of what someone experienced.
private struct PublishedContextBlock: View {
    let mechanism: String
    let citation: String
    let grade: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("WHY THIS MIGHT HAPPEN")
                    .font(Font.Soma.sectionTag)
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                if let grade {
                    // Strength of the underlying literature, not of this
                    // person's pattern — ConfidenceBadge already carries
                    // that, and conflating the two would be the whole
                    // mistake this feature is trying to avoid.
                    Text("EVIDENCE \(grade)")
                        .font(Font.Soma.sectionTag)
                        .tracking(1.5)
                        .foregroundStyle(Color.inkSoft)
                }
            }

            Text(mechanism)
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(citation)
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .fill(Color.paperSunk)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                        .strokeBorder(Color.rule.opacity(0.5), lineWidth: 0.8)
                )
        )
    }
}

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

            if let context = insight.publishedContext {
                PublishedContextBlock(
                    mechanism: context.mechanism,
                    citation: context.citation,
                    grade: insight.evidenceGrade
                )
            }

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

// MARK: - Reflections (the early days)
//
// What the app can say before the statistics can say anything. These are
// descriptions of the log — when the last plate lands, what keeps coming
// back, the spread of a signal — and they relate nothing to anything, which
// is what makes them honest on day three when a correlation would not be.
//
// So they must not look like findings. An InsightFeedCard is a raised lab
// page with a shadow, ruled paper, a confidence badge and a persimmon hedge;
// this is the opposite move — recessed into the page (`paperSunk`, the same
// surface PublishedContextBlock uses for "this is not Soma concluding
// something"), flat, no shadow, no badge, no persimmon. A reader should be
// able to tell at a glance that nothing here is a claim, before reading a
// word of it.
//
// One block rather than one card each, for the same reason: three separate
// cards would read as three findings.

private struct ReflectionsBlock: View {
    let reflections: [Reflection]
    /// Why there are no findings under this yet. Carried here rather than
    /// left to EmptyFeedPage because only one of the two blocks is ever on
    /// screen — two cards both opening with "nothing yet" reads as the app
    /// apologising twice.
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("FROM THE PAGE SO FAR")
                    .font(Font.Soma.sectionTag)
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                if let days = reflections.first?.windowDays {
                    Text("LAST \(days) DAYS")
                        .font(Font.Soma.sectionTag)
                        .tracking(2)
                        .foregroundStyle(Color.inkSoft)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(reflections) { reflection in
                    ReflectionRow(reflection: reflection)
                }
            }

            InkRule(style: .dotted, color: Color.rule, weight: 0.8)
                .frame(height: 4)

            // The disclosure that keeps this block from being read as a
            // weaker insight feed. inkSoft rather than persimmon on purpose:
            // persimmon marks the hedge on a claim, and there is no claim
            // here to hedge.
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("not findings — just what's written down.")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)

                Text(note)
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .fill(Color.paperSunk)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                        .strokeBorder(Color.rule.opacity(0.5), lineWidth: 0.8)
                )
        )
    }
}

private struct ReflectionRow: View {
    let reflection: Reflection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s + 2) {
            Text("·")
                .font(Font.Soma.sectionTag)
                .foregroundStyle(Color.inkSoft)

            VStack(alignment: .leading, spacing: 4) {
                Text(reflection.body)
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reflection.detail)
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
