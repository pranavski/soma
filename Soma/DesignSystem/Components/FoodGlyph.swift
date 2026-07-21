import SwiftUI

/// A small cast of hand-drawn ink illustrations.
/// Each case maps to a Shape that strokes in the current ink color, and
/// carries a stable plate numeral + latin-style caption — like illustrations
/// in a 19th-century food encyclopedia. The numeral is stable per case so
/// users gradually learn `№ 03 = the egg`.
enum FoodGlyph: String, CaseIterable, Hashable {
    case lemon
    case egg
    case mug          // coffee / tea
    case bowl         // salad, soup, anything in a bowl
    case sprig        // herbs / greens
    case toast        // bread, sandwich
    case leaf         // light/vegetable accent
    case knife        // utensil divider
    case cherry       // fruit / sweet
    case fish         // protein
    case noodle       // pasta / noodles
    case wine         // beverage

    /// Stable plate number — never changes per case. New glyphs append.
    var numeral: Int {
        switch self {
        case .lemon:  return 1
        case .toast:  return 2
        case .egg:    return 3
        case .mug:    return 4
        case .bowl:   return 5
        case .sprig:  return 6
        case .leaf:   return 7
        case .knife:  return 8
        case .cherry: return 9
        case .fish:   return 10
        case .noodle: return 11
        case .wine:   return 12
        }
    }

    /// Latin-binomial-style caption (slightly invented where the real one
    /// would feel pedantic). Shown only in the dictionary / large plates.
    var caption: String {
        switch self {
        case .lemon:  return "Citrus limon"
        case .toast:  return "Triticum vulgare"
        case .egg:    return "Gallus gallus"
        case .mug:    return "Camellia sinensis"
        case .bowl:   return "Olla mixta"
        case .sprig:  return "Herba culinaris"
        case .leaf:   return "Folium tenue"
        case .knife:  return "Ferrum cocinae"
        case .cherry: return "Prunus avium"
        case .fish:   return "Pisces"
        case .noodle: return "Pasta longa"
        case .wine:   return "Vitis vinifera"
        }
    }

    /// Pick one from a free-form dish string. Best-effort keyword match.
    static func from(_ name: String) -> FoodGlyph {
        let n = name.lowercased()
        if n.contains("lemon") || n.contains("citrus") { return .lemon }
        if n.contains("egg") || n.contains("toast") || n.contains("bread") { return .toast }
        if n.contains("coffee") || n.contains("tea") || n.contains("matcha") { return .mug }
        if n.contains("wine") || n.contains("cocktail") || n.contains("beer") { return .wine }
        if n.contains("salmon") || n.contains("fish") || n.contains("tuna") { return .fish }
        if n.contains("noodle") || n.contains("pasta") || n.contains("ramen") { return .noodle }
        if n.contains("salad") || n.contains("soup") || n.contains("curry") || n.contains("bowl") { return .bowl }
        if n.contains("cherry") || n.contains("berry") || n.contains("fruit") { return .cherry }
        if n.contains("herb") || n.contains("basil") || n.contains("mint") { return .sprig }
        if n.contains("leaf") || n.contains("greens") || n.contains("kale") { return .leaf }
        return .bowl
    }
}

/// Stroke weights for a glyph — hairline whispers in margins, pen is the
/// default, bold is hero-on-card.
enum GlyphWeight {
    case hairline, pen, bold
    var stroke: CGFloat {
        switch self {
        case .hairline: return Theme.Stroke.hairline + 0.2
        case .pen:      return Theme.Stroke.pen
        case .bold:     return Theme.Stroke.nib + 0.2
        }
    }
}

/// Renders a FoodGlyph at the given size. `ink` strokes the linework,
/// `fill` optionally tints the interior (e.g. yellow inside a lemon).
struct FoodGlyphView: View {
    var glyph: FoodGlyph
    var size: CGFloat = 36
    var ink: Color = .ink
    var fill: Color? = nil
    var stroke: CGFloat = Theme.Stroke.pen

    var body: some View {
        ZStack {
            shape(for: glyph)
                .fill(fill ?? Color.clear)
            shape(for: glyph)
                .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }

    private func shape(for glyph: FoodGlyph) -> AnyShape {
        switch glyph {
        case .lemon:   return AnyShape(LemonShape())
        case .egg:     return AnyShape(EggShape())
        case .mug:     return AnyShape(MugShape())
        case .bowl:    return AnyShape(BowlShape())
        case .sprig:   return AnyShape(SprigShape())
        case .toast:   return AnyShape(ToastShape())
        case .leaf:    return AnyShape(LeafShape())
        case .knife:   return AnyShape(KnifeShape())
        case .cherry:  return AnyShape(CherryShape())
        case .fish:    return AnyShape(FishShape())
        case .noodle:  return AnyShape(NoodleShape())
        case .wine:    return AnyShape(WineShape())
        }
    }
}

// MARK: - Shapes
// Each shape is drawn in a normalized rect so it scales cleanly.
// Control points are slightly offset from "perfect" — that's the felt-tip look.

struct LemonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.18)
        // An oval with one nipple end (left) and a softer pointed right.
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.midY))
        p.addCurve(
            to: CGPoint(x: r.midX, y: r.minY),
            control1: CGPoint(x: r.minX, y: r.minY + r.height * 0.20),
            control2: CGPoint(x: r.minX + r.width * 0.25, y: r.minY)
        )
        p.addCurve(
            to: CGPoint(x: r.maxX, y: r.midY),
            control1: CGPoint(x: r.minX + r.width * 0.85, y: r.minY),
            control2: CGPoint(x: r.maxX, y: r.minY + r.height * 0.30)
        )
        p.addCurve(
            to: CGPoint(x: r.midX, y: r.maxY),
            control1: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.20),
            control2: CGPoint(x: r.minX + r.width * 0.80, y: r.maxY)
        )
        p.addCurve(
            to: CGPoint(x: r.minX + r.width * 0.05, y: r.midY),
            control1: CGPoint(x: r.minX + r.width * 0.20, y: r.maxY),
            control2: CGPoint(x: r.minX, y: r.maxY - r.height * 0.25)
        )
        // Tiny leaf
        let lx = r.midX + r.width * 0.08
        let ly = r.minY - r.height * 0.05
        p.move(to: CGPoint(x: lx, y: ly))
        p.addQuadCurve(to: CGPoint(x: lx + r.width * 0.18, y: ly - r.height * 0.10),
                       control: CGPoint(x: lx + r.width * 0.20, y: ly + r.height * 0.05))
        return p
    }
}

struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.20, dy: rect.height * 0.10)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(
            to: CGPoint(x: r.midX, y: r.maxY),
            control1: CGPoint(x: r.minX - r.width * 0.05, y: r.minY + r.height * 0.45),
            control2: CGPoint(x: r.minX, y: r.maxY)
        )
        p.addCurve(
            to: CGPoint(x: r.midX, y: r.minY),
            control1: CGPoint(x: r.maxX, y: r.maxY),
            control2: CGPoint(x: r.maxX + r.width * 0.05, y: r.minY + r.height * 0.40)
        )
        return p
    }
}

struct MugShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.18)
        let body = CGRect(
            x: r.minX,
            y: r.minY + r.height * 0.10,
            width: r.width * 0.78,
            height: r.height * 0.85
        )
        // Body
        p.move(to: CGPoint(x: body.minX, y: body.minY))
        p.addLine(to: CGPoint(x: body.minX + 1, y: body.maxY - 4))
        p.addQuadCurve(
            to: CGPoint(x: body.maxX - 1, y: body.maxY - 4),
            control: CGPoint(x: body.midX, y: body.maxY + 6)
        )
        p.addLine(to: CGPoint(x: body.maxX, y: body.minY))
        // Rim cap
        p.move(to: CGPoint(x: body.minX - 2, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX + 2, y: body.minY))
        // Handle
        let hx = body.maxX
        p.move(to: CGPoint(x: hx, y: body.minY + body.height * 0.20))
        p.addCurve(
            to: CGPoint(x: hx, y: body.minY + body.height * 0.65),
            control1: CGPoint(x: hx + r.width * 0.22, y: body.minY + body.height * 0.18),
            control2: CGPoint(x: hx + r.width * 0.22, y: body.minY + body.height * 0.70)
        )
        // Steam
        let sx = body.midX
        p.move(to: CGPoint(x: sx - 6, y: body.minY - 4))
        p.addQuadCurve(to: CGPoint(x: sx - 6, y: body.minY - 14),
                       control: CGPoint(x: sx - 12, y: body.minY - 9))
        p.move(to: CGPoint(x: sx + 4, y: body.minY - 4))
        p.addQuadCurve(to: CGPoint(x: sx + 4, y: body.minY - 14),
                       control: CGPoint(x: sx + 10, y: body.minY - 9))
        return p
    }
}

struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.22)
        // Bowl arc
        p.move(to: CGPoint(x: r.minX, y: r.minY + 2))
        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY + 2),
            control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.45)
        )
        // Rim line
        p.move(to: CGPoint(x: r.minX - 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + 2, y: r.minY))
        // Two little contents dots
        p.move(to: CGPoint(x: r.midX - 4, y: r.minY - 4))
        p.addLine(to: CGPoint(x: r.midX - 4, y: r.minY - 4.5))
        p.move(to: CGPoint(x: r.midX + 5, y: r.minY - 3))
        p.addLine(to: CGPoint(x: r.midX + 5, y: r.minY - 3.5))
        return p
    }
}

struct SprigShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.10)
        // Main stem (curved)
        p.move(to: CGPoint(x: r.minX + r.width * 0.85, y: r.maxY))
        p.addQuadCurve(
            to: CGPoint(x: r.minX, y: r.minY + r.height * 0.15),
            control: CGPoint(x: r.minX + r.width * 0.20, y: r.maxY - r.height * 0.10)
        )
        // Four little leaves along the stem
        let positions: [(CGPoint, CGPoint)] = [
            (CGPoint(x: r.minX + r.width * 0.60, y: r.maxY - r.height * 0.18),
             CGPoint(x: r.minX + r.width * 0.80, y: r.maxY - r.height * 0.32)),
            (CGPoint(x: r.minX + r.width * 0.40, y: r.maxY - r.height * 0.42),
             CGPoint(x: r.minX + r.width * 0.20, y: r.maxY - r.height * 0.50)),
            (CGPoint(x: r.minX + r.width * 0.28, y: r.maxY - r.height * 0.60),
             CGPoint(x: r.minX + r.width * 0.48, y: r.maxY - r.height * 0.72)),
            (CGPoint(x: r.minX + r.width * 0.12, y: r.maxY - r.height * 0.78),
             CGPoint(x: r.minX + r.width * 0.00, y: r.maxY - r.height * 0.90))
        ]
        for (a, b) in positions {
            p.move(to: a)
            p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x)/2 + 4, y: (a.y + b.y)/2 - 4))
        }
        return p
    }
}

struct ToastShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.16)
        // Crust outline — a bread slice with a rounded crown
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.04, y: r.minY + r.height * 0.30))
        p.addQuadCurve(
            to: CGPoint(x: r.midX, y: r.minY),
            control: CGPoint(x: r.minX + r.width * 0.18, y: r.minY - r.height * 0.05)
        )
        p.addQuadCurve(
            to: CGPoint(x: r.maxX - r.width * 0.04, y: r.minY + r.height * 0.30),
            control: CGPoint(x: r.maxX - r.width * 0.18, y: r.minY - r.height * 0.05)
        )
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        // Inner crust ring
        let inner = r.insetBy(dx: r.width * 0.12, dy: r.height * 0.18)
        p.move(to: CGPoint(x: inner.minX, y: inner.maxY))
        p.addLine(to: CGPoint(x: inner.minX + 1, y: inner.minY + inner.height * 0.30))
        p.addQuadCurve(
            to: CGPoint(x: inner.maxX - 1, y: inner.minY + inner.height * 0.30),
            control: CGPoint(x: inner.midX, y: inner.minY - inner.height * 0.05)
        )
        p.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        return p
    }
}

struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.18)
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY),
            control: CGPoint(x: r.maxX, y: r.maxY)
        )
        p.addQuadCurve(
            to: CGPoint(x: r.minX, y: r.maxY),
            control: CGPoint(x: r.minX, y: r.minY)
        )
        // Vein
        p.move(to: CGPoint(x: r.minX + r.width * 0.10, y: r.maxY - 4))
        p.addQuadCurve(
            to: CGPoint(x: r.maxX - r.width * 0.10, y: r.minY + 4),
            control: CGPoint(x: r.midX, y: r.midY)
        )
        return p
    }
}

struct KnifeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.36)
        // Blade
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.60, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.65, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        // Handle
        let hx = r.minX + r.width * 0.65
        p.move(to: CGPoint(x: hx, y: r.minY + 2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY - 1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY + 1))
        p.addLine(to: CGPoint(x: hx, y: r.maxY - 2))
        return p
    }
}

struct CherryShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.10)
        let leftCenter  = CGPoint(x: r.minX + r.width * 0.30, y: r.maxY - r.height * 0.18)
        let rightCenter = CGPoint(x: r.maxX - r.width * 0.22, y: r.maxY - r.height * 0.10)
        let radius = r.width * 0.22
        p.addEllipse(in: CGRect(x: leftCenter.x - radius, y: leftCenter.y - radius, width: radius*2, height: radius*2))
        p.addEllipse(in: CGRect(x: rightCenter.x - radius, y: rightCenter.y - radius, width: radius*2, height: radius*2))
        // Stems
        p.move(to: CGPoint(x: leftCenter.x, y: leftCenter.y - radius))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY),
                       control: CGPoint(x: leftCenter.x - 4, y: r.minY + r.height * 0.20))
        p.move(to: CGPoint(x: rightCenter.x, y: rightCenter.y - radius))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY),
                       control: CGPoint(x: rightCenter.x + 4, y: r.minY + r.height * 0.20))
        // Leaf
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX + r.width * 0.20, y: r.minY + r.height * 0.10),
                       control: CGPoint(x: r.midX + r.width * 0.22, y: r.minY - 2))
        return p
    }
}

struct FishShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.30)
        // Body
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.22, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.maxY))
        // Tail
        p.move(to: CGPoint(x: r.maxX - r.width * 0.22, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY - r.height * 0.40))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY + r.height * 0.40))
        p.closeSubpath()
        // Eye
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.18, y: r.midY - 1.5, width: 2.5, height: 2.5))
        return p
    }
}

struct NoodleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.18)
        // Bowl rim
        p.move(to: CGPoint(x: r.minX - 2, y: r.midY + r.height * 0.10))
        p.addLine(to: CGPoint(x: r.maxX + 2, y: r.midY + r.height * 0.10))
        // Bowl body
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.10))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY + r.height * 0.10),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.30))
        // Squiggle noodles
        for i in 0..<3 {
            let y = r.midY - CGFloat(i) * 4 - 2
            p.move(to: CGPoint(x: r.minX + 3, y: y))
            let len = 4
            for j in 0..<len {
                let dir: CGFloat = (j % 2 == 0) ? -3 : 3
                p.addQuadCurve(
                    to: CGPoint(x: r.minX + 3 + CGFloat(j + 1) * (r.width / CGFloat(len + 1)), y: y),
                    control: CGPoint(x: r.minX + 3 + (CGFloat(j) + 0.5) * (r.width / CGFloat(len + 1)), y: y + dir)
                )
            }
        }
        return p
    }
}

struct WineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.06)
        // Bowl
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.42),
                       control: CGPoint(x: r.minX, y: r.minY + r.height * 0.40))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.40))
        // Stem
        p.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.08))
        // Foot
        p.move(to: CGPoint(x: r.minX + r.width * 0.10, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.10, y: r.maxY))
        return p
    }
}

// MARK: - Plate
// The authored treatment — glyph + plate numeral + optional caption.
// This is what goes on a RecipeCard. Think "single illustration in a
// 19th-century food encyclopedia."

struct Plate: View {
    let glyph: FoodGlyph
    var size: CGFloat = 56
    var ink: Color = .ink
    var wash: Color? = nil
    var weight: GlyphWeight = .pen
    var showNumeral: Bool = true
    var showCaption: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                FoodGlyphView(
                    glyph: glyph,
                    size: size,
                    ink: ink,
                    fill: wash,
                    stroke: weight.stroke
                )

                if showNumeral {
                    Text("№ \(String(format: "%02d", glyph.numeral))")
                        .font(Font.Soma.stampTime)
                        .foregroundStyle(ink.opacity(0.55))
                        .offset(x: 2, y: 4)
                }
            }

            if showCaption {
                Text(glyph.caption)
                    .font(.system(size: 9, weight: .regular, design: .serif).italic())
                    .foregroundStyle(ink.opacity(0.55))
                    .tracking(0.2)
            }
        }
    }
}

/// A pencilled signature mark — `pr.` in the hand. Drop in the corner of
/// any plate / card / page Soma "signed."
struct Signature: View {
    var initials: String = "pr."
    var color: Color = .inkSoft

    var body: some View {
        Text(initials)
            .font(Font.Soma.signature)
            .foregroundStyle(color.opacity(0.65))
            .rotationEffect(.degrees(-4))
    }
}
