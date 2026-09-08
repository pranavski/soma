import SwiftUI

enum SomaTab: String, CaseIterable, Hashable {
    // Declaration order IS presentation order (CaseIterable drives the tab
    // bar). Insights lead — the app is an insight engine first.
    case insights, today, history, settings

    var label: String {
        switch self {
        case .today:    return "today"
        case .history:  return "back"
        case .insights: return "noticed"
        case .settings: return "kitchen"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var disclosure = AIDisclosure.shared
    @State private var tab: SomaTab = {
        #if DEBUG
        if let t = ProcessInfo.processInfo.environment["SOMA_PREVIEW_TAB"],
           let parsed = SomaTab(rawValue: t) {
            return parsed
        }
        #endif
        return .insights
    }()

    /// True whenever the tabbed app is on screen — the real signed-in case,
    /// or a SOMA_PREVIEW simulator run. The AI consent gate keys off this so
    /// preview runs exercise it too.
    private var isShowingApp: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" { return true }
        #endif
        return session.isSignedIn
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" {
                signedInBody
            } else if session.isSignedIn {
                signedInBody
            } else if session.isRestoring {
                PaperBackground()
            } else {
                SignInView()
            }
            #else
            if session.isSignedIn {
                signedInBody
            } else if session.isRestoring {
                // Brief paper-only flash on cold launch while we read the
                // keychain — keeps the SignInView from blinking in before
                // we know there's no session.
                PaperBackground()
            } else {
                SignInView()
            }
            #endif
        }
        .environmentObject(disclosure)
        // The server-side copy of the answer (ai_consent) is what the
        // nightly job checks. Re-push it every sign-in so a write that
        // failed earlier heals, and so accounts that answered before the
        // row existed get one.
        .task(id: session.session?.user.id) {
            guard session.isSignedIn else { return }
            disclosure.syncToServer()
        }
        // Named, explicit, before the first send — guideline 5.1.2(i). It
        // rides on `isSignedIn` so it lands right after sign-in and before
        // any meal can be logged, and never appears for a signed-out user.
        .sheet(isPresented: Binding(
            get: { isShowingApp && !disclosure.hasAnswered },
            set: { _ in }
        )) {
            AIDisclosureSheet()
                .environmentObject(disclosure)
                .presentationDetents([.large])
        }
    }

    private var signedInBody: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .today:    TodayView()
                case .history:  HistoryView()
                case .insights: InsightsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Only the bar itself ignores the keyboard — the tab content
            // must keep respecting it so the insights quick-log field can
            // ride up above the keyboard instead of hiding under it.
            SomaTabBar(selected: $tab)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        // Fresh identity per user id — signing out then in as a different
        // account discards every child @StateObject (TodayViewModel etc.)
        // instead of letting them re-emit the previous user's cached rows.
        .id(session.session?.user.id ?? UUID())
        // The type scale already starts large (the day line is 42pt), so the
        // top two accessibility steps only push text off screen. Capping at
        // accessibility3 still roughly doubles body copy while keeping every
        // control reachable.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Tab bar

private struct SomaTabBar: View {
    @Binding var selected: SomaTab

    var body: some View {
        VStack(spacing: 0) {
            // hand-drawn top rule
            InkRule(style: .solid, color: Color.rule, weight: Theme.Stroke.hairline + 0.3)
                .frame(height: 6)
                .padding(.horizontal, Theme.Spacing.l)

            HStack(spacing: 0) {
                ForEach(SomaTab.allCases, id: \.self) { item in
                    TabItem(
                        tab: item,
                        isSelected: item == selected,
                        action: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selected = item
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, Theme.Spacing.s)
            // The bar is chrome, not content: it stays a fixed strip so the
            // pinned capture pill and quick-log field can offset off
            // Theme.TabBar and stay correct. Without this the labels wrap at
            // accessibility sizes, the bar grows past 250pt, and Today's
            // "tell me" button gets pushed off the bottom of the screen.
            .frame(height: Theme.TabBar.barHeight - 6)
        }
        .background(
            Color.paper
                .overlay(
                    PaperGrain(density: 320, seed: 0x4A4A4A)
                        .opacity(0.30)
                        .blendMode(.multiply)
                )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.paperShadow.opacity(0.0), Color.paperShadow.opacity(0.25)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 24)
                    .offset(y: -24)
                    .allowsHitTesting(false)
                }
                // Paint through the home-indicator strip. Only the background
                // extends — the buttons stay above the safe area. Without it
                // scrolled card text is visible in the gap under the bar.
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct TabItem: View {
    let tab: SomaTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbolName(for: tab))
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .frame(width: 28, height: 24)
                    .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)

                Text(tab.label)
                    .font(Font.Soma.tabLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)
            }
            // Tab labels are chrome. They honour Dynamic Type up to xLarge
            // and then hold — a wrapped "kitchen" over two lines reads as a
            // bug, and the bar has to keep a predictable height.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func symbolName(for tab: SomaTab) -> String {
        switch tab {
        case .today:    return "sun.min"
        case .history:  return "book.closed"
        case .insights: return "leaf"
        case .settings: return "slider.horizontal.3"
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SessionStore())
}
