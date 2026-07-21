import SwiftUI

/// The central primitive of the Mise direction — a simplified recipe card.
///
/// Anatomy, top to bottom:
///   ┌─────────────────────────┐
///   │ time                    │  ← time stamp in ticket mono
///   │ Dish name (italic)      │  ← display serif italic
///   │ ~ 320–420 kcal · usual  │  ← caloric range in ticket mono, optional aside
///   │   [Plate № NN]          │  ← single plate glyph
///   └─────────────────────────┘
///
/// One look across Today + History — no variants, no tilt, no wash,
/// no signature, no ruled paper substrate, no per-card grain.
struct RecipeCard: View {
    let timeLabel: String
    let dishName: String
    let calorieRange: String?
    let macros: MacroBreakdown?
    let aside: String?
    let glyph: FoodGlyph

    init(
        timeLabel: String,
        dishName: String,
        calorieRange: String?,
        macros: MacroBreakdown? = nil,
        aside: String?,
        glyph: FoodGlyph
    ) {
        self.timeLabel = timeLabel
        self.dishName = dishName
        self.calorieRange = calorieRange
        self.macros = macros
        self.aside = aside
        self.glyph = glyph
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(timeLabel.lowercased())
                    .font(Font.Soma.stampTime)
                    .foregroundStyle(Color.graphite.opacity(0.85))
                    .tracking(0.6)
                Spacer(minLength: 0)
            }

            Text(dishName)
                .font(Font.Soma.dish)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(spacing: 6) {
                if let range = calorieRange {
                    Text("\(range) kcal")
                        .font(Font.Soma.caloric)
                        .foregroundStyle(Color.graphite.opacity(0.80))
                }
                if let aside, !aside.isEmpty {
                    if calorieRange != nil {
                        Text("·")
                            .font(Font.Soma.caloric)
                            .foregroundStyle(Color.inkSoft)
                    }
                    Text(aside)
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            if let macros, !macros.isEmpty {
                MacroStrip(macros: macros)
                    .padding(.top, 4)
            }

            Spacer(minLength: Theme.Spacing.m)

            Plate(glyph: glyph, size: 44, ink: Color.ink, wash: nil, weight: .pen)
        }
        .padding(.horizontal, Theme.Card.bodyInset)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .fill(Color.paperRaised)
        )
        .overlay(
            // Hairline edge so the card reads as a separate sheet, not a panel.
            RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                .stroke(Color.rule.opacity(0.55), lineWidth: Theme.Stroke.hairline)
        )
        .shadow(color: Color.paperShadow.opacity(0.45), radius: 4, x: 0, y: 3)
    }
}

// MARK: - Macro strip
// One glanceable line under the calorie range — "P ~20–28g · C ~45–60g · …".
// Hidden entirely when nothing has been parsed yet.

struct MacroStrip: View {
    let macros: MacroBreakdown

    var body: some View {
        HStack(spacing: 6) {
            ForEach(entries, id: \.label) { entry in
                if entry.index > 0 {
                    Text("·")
                        .font(Font.Soma.caloric)
                        .foregroundStyle(Color.inkSoft.opacity(0.6))
                }
                Text("\(entry.label) \(entry.value)")
                    .font(Font.Soma.caloric)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }

    private struct Entry { let index: Int; let label: String; let value: String }

    private var entries: [Entry] {
        var out: [Entry] = []
        let raw: [(String, String?)] = [
            ("P",   macros.proteinRange),
            ("C",   macros.carbsRange),
            ("F",   macros.fatRange),
            ("Fib", macros.fiberRange),
        ]
        for (label, value) in raw {
            guard let value else { continue }
            out.append(Entry(index: out.count, label: label, value: value))
        }
        return out
    }
}

// MARK: - Ruled-paper substrate
// Procedural horizontal rules — used by the Insights lab page. Honest blue
// "school index card" lines, drawn at a given rule height.

struct RuledPaper: View {
    var rule: CGFloat = 24
    var color: Color = .cardLine
    var inset: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: inset, y: y))
                    p.addLine(to: CGPoint(x: size.width - inset, y: y))
                    ctx.stroke(p, with: .color(color), lineWidth: 0.5)
                    y += rule
                }
                _ = geo  // silence unused warning
            }
        }
    }
}
