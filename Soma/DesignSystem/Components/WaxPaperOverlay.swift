import SwiftUI

/// The signature move — tap "compare" in the Today header to lay
/// yesterday over today as a translucent wax-paper sheet. Yesterday's
/// cards ghost through at ~55% opacity; tap "lift" (or the sheet's own
/// tab) to peel it back off.
///
/// A pull-down gesture was the original idea, but Today's scroll view
/// already answers a pull with a refresh, so the pill is the entry point.
/// With Reduce Motion on, the sheet appears and lifts without animation.
///
/// This is the "could only be Soma" move. Overlay materials are
/// everywhere in a kitchen (parchment, wax paper, deli sheets) and
/// nowhere in journal apps.
struct WaxPaperOverlay: View {
    let mealsYesterday: [Meal]
    /// 0 = wax paper is lifted (invisible), 1 = fully stuck.
    let progress: Double
    /// Tapping the tab at the top of the sheet peels it off.
    var onLift: () -> Void = {}

    var body: some View {
        // Progress under a threshold is invisible — no draw cost.
        if progress > 0.01 {
            ZStack(alignment: .top) {
                // The wax-paper sheet — a warm, slightly greasy translucent
                // wash. Blends with the paper beneath rather than sitting on
                // top like a modal.
                LinearGradient(
                    colors: [
                        Color.paperRaised.opacity(0.72),
                        Color.paperRaised.opacity(0.62),
                        Color.paperRaised.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(progress)

                PaperGrain(density: 380, seed: 0xB3D9F1)
                    .opacity(0.14 * progress)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)

                // Scrolls, because a full day is often taller than the
                // screen and the sheet has to show all of it.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Button(action: onLift) {
                            WaxTab(progress: progress)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Lift the wax paper")
                        .padding(.top, Theme.Spacing.xxl + 10)
                        .padding(.bottom, Theme.Spacing.m)

                        // Yesterday's cards — ghosted, slightly desaturated.
                        // They ride the same margin as today's card stream
                        // so the eye reads them as the *previous version of
                        // the same day.*
                        VStack(spacing: Theme.Spacing.l) {
                            ForEach(mealsYesterday, id: \.id) { meal in
                                RecipeCard(
                                    timeLabel: meal.timeLabel,
                                    dishName: meal.displayName,
                                    calorieRange: meal.calorieRange,
                                    macros: meal.macros,
                                    detail: meal.stimulantNote,
                                    aside: "yesterday",
                                    glyph: FoodGlyph.from(meal.displayName)
                                )
                                .opacity(0.82)
                                .saturation(0.75)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.xl)
                        .opacity(progress)

                        Spacer(minLength: Theme.TabBar.scrollBottomInset)
                    }
                }
            }
            .allowsHitTesting(progress > 0.5)
        }
    }
}

/// The visible handle at the top of the wax paper — a small mono-label
/// pill. Serves as both a Reduce-Motion tap-target and a "you can pull
/// this" affordance during the drag.
private struct WaxTab: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            WaxGrip()
                .stroke(Color.inkSoft, style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                .frame(width: 16, height: 6)
            Text(progress > 0.85 ? "YESTERDAY" : "wax paper —")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.inkSoft)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.paper.opacity(0.7))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.rule.opacity(0.5), lineWidth: 0.6)
                )
        )
    }
}

private struct WaxGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 1))
        return p
    }
}

/// Small tap target that lives inside the Today header when Reduce Motion
/// is on. Shows a compact "◴ compare" affordance so gesture-averse users
/// can still deploy the wax paper.
struct WaxPaperToggleButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("◴")
                    .font(Font.Soma.sectionTag)
                    .foregroundStyle(Color.inkSoft)
                Text(isOn ? "lift" : "compare")
                    .font(Font.Soma.buttonSm)
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .stroke(Color.rule, style: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
            )
        }
        .buttonStyle(.plain)
    }
}
