import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var showHealthKit = false
    @State private var showAbout = false
    @State private var showCheckin = false
    @State private var showFeedback = false
    @State private var showDeleteAccount = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    ScreenTitle(eyebrow: "CONTENTS",
                                title: "The kitchen.")

                    ContentsList(actions: rowActions())
                        .padding(.horizontal, Theme.Spacing.xl)

                    if let err = exportError {
                        Text(err)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Footer()
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.top, Theme.Spacing.xl)

                    Spacer(minLength: 160)
                }
                .padding(.top, Theme.Spacing.l)
            }
        }
        .sheet(isPresented: $showHealthKit) {
            HealthKitSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCheckin) {
            DailyCheckinSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountSheet()
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { exportURL.map(ExportItem.init) },
            set: { newValue in exportURL = newValue?.url }
        )) { item in
            ShareSheet(url: item.url)
        }
    }

    private func rowActions() -> ContentsList.Actions {
        ContentsList.Actions(
            onSignIn:       { showAbout = true }, // "Sign-in" row shows account details via About for v1
            onHealthKit:    { showHealthKit = true },
            onRanges:       { showAbout = true },
            onInsights:     { showCheckin = true }, // link Insights row to check-in — that's the input the engine needs
            onExport:       { Task { await runExport() } },
            onAbout:        { showAbout = true },
            onFeedback:     { showFeedback = true },
            onDeleteAccount:{ showDeleteAccount = true },
            onSignOut:      { Task { await session.signOut() } }
        )
    }

    private func runExport() async {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let url = try await MealExport.buildCSV()
            exportURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// UIActivityViewController bridge so SwiftUI can hand a temp file URL to
/// the standard share sheet. `ShareLink` would be simpler but requires the
/// URL to be present up-front; we build the CSV on demand.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: URL { url }
}

#Preview {
    SettingsView()
        .environmentObject(SessionStore())
}

private struct ContentsList: View {
    struct Actions {
        var onSignIn: () -> Void
        var onHealthKit: () -> Void
        var onRanges: () -> Void
        var onInsights: () -> Void
        var onExport: () -> Void
        var onAbout: () -> Void
        var onFeedback: () -> Void
        var onDeleteAccount: () -> Void
        var onSignOut: () -> Void
    }

    let actions: Actions

    private struct Entry {
        let title: String
        let note: String
        let glyph: FoodGlyph
        var action: (() -> Void)? = nil
    }

    private var entries: [Entry] {
        [
            Entry(title: "Sign-in",       note: "Apple ID · signed in",   glyph: .leaf,   action: actions.onSignIn),
            Entry(title: "HealthKit",     note: "sleep, steps, energy",   glyph: .sprig,  action: actions.onHealthKit),
            Entry(title: "Check-in",      note: "how the day felt",       glyph: .cherry, action: actions.onInsights),
            Entry(title: "Ranges",        note: "always shown as a span", glyph: .lemon,  action: actions.onRanges),
            Entry(title: "Export",        note: "your data, plainly",     glyph: .knife,  action: actions.onExport),
            Entry(title: "Send feedback", note: "tell us what could be better", glyph: .cherry, action: actions.onFeedback),
            Entry(title: "About",         note: "what soma is, isn't",  glyph: .bowl,   action: actions.onAbout),
            Entry(title: "Sign out",      note: "close the kitchen",      glyph: .knife,  action: actions.onSignOut),
            Entry(title: "Delete account", note: "erase everything, forever", glyph: .knife, action: actions.onDeleteAccount)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                ContentsRow(
                    chapter: idx + 1,
                    title: entry.title,
                    note: entry.note,
                    glyph: entry.glyph,
                    action: entry.action
                )
                if idx < entries.count - 1 {
                    InkRule(style: .dotted, color: Color.rule.opacity(0.7), weight: 0.9)
                        .frame(height: 6)
                        .padding(.horizontal, Theme.Spacing.s)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.paperRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.rule, lineWidth: Theme.Stroke.hairline)
        )
        .shadow(color: Color.paperShadow.opacity(0.45), radius: 12, x: 0, y: 8)
    }
}

private struct ContentsRow: View {
    let chapter: Int
    let title: String
    let note: String
    let glyph: FoodGlyph
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: Theme.Spacing.m) {
                FoodGlyphView(glyph: glyph, size: 22, ink: Color.inkSoft, stroke: 1.1)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Font.Soma.dishSmall)
                        .foregroundStyle(Color.ink)
                    Text(note)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }

                Spacer()

                Text("\(roman(chapter))")
                    .font(Font.Soma.timestamp)
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.vertical, Theme.Spacing.m)
        }
        .buttonStyle(.plain)
    }

    private func roman(_ n: Int) -> String {
        let map: [String] = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return map[min(n, map.count - 1)]
    }
}

private struct Footer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            InkRule(style: .wavy, color: Color.rule, weight: 1.0)
                .frame(width: 120)
            Text("soma remembers gently.\nnever shames. never prescribes.")
                .font(Font.Soma.dishNote)
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(3)

            // Legal / safety line. Required visible somewhere the user can
            // reasonably reach — Settings footer is the calmest home for it.
            Text("not medical advice. soma surfaces patterns, not diagnoses. talk to a clinician for anything that matters.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft.opacity(0.85))
                .lineSpacing(2)
                .padding(.top, Theme.Spacing.s)
        }
    }
}
