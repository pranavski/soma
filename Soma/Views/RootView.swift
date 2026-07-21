import SwiftUI

enum SomaTab: String, CaseIterable, Hashable {
    case today, history, insights, settings

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
    @State private var tab: SomaTab = {
        #if DEBUG
        if let t = ProcessInfo.processInfo.environment["SOMA_PREVIEW_TAB"],
           let parsed = SomaTab(rawValue: t) {
            return parsed
        }
        #endif
        return .today
    }()

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

            SomaTabBar(selected: $tab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Fresh identity per user id — signing out then in as a different
        // account discards every child @StateObject (TodayViewModel etc.)
        // instead of letting them re-emit the previous user's cached rows.
        .id(session.session?.user.id ?? UUID())
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
            .padding(.bottom, 16)
            .padding(.horizontal, Theme.Spacing.s)
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
        )
    }
}

private struct TabItem: View {
    let tab: SomaTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbolName(for: tab))
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)

                Text(tab.label)
                    .font(Font.Soma.tabLabel)
                    .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)
            }
        }
        .buttonStyle(.plain)
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
