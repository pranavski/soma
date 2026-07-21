import SwiftUI

/// Hand-drawn-feeling horizontal rule — a thin pen line with a slight wobble
/// and a small flick at each end, as if drawn with a felt-tip in one stroke.
struct InkRule: View {
    enum Style {
        case solid       // continuous pen line
        case dotted      // small bead-like dots
        case wavy        // a gentle sine wave, used for section breaks
    }

    var style: Style = .solid
    var color: Color = .ink
    var weight: CGFloat = Theme.Stroke.pen

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch style {
                case .solid:
                    WobblePath(amplitude: 0.6, wavelength: 90)
                        .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
                case .dotted:
                    Path { p in
                        let y = geo.size.height / 2
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(color, style: StrokeStyle(
                        lineWidth: weight,
                        lineCap: .round,
                        dash: [0.1, 6]
                    ))
                case .wavy:
                    WobblePath(amplitude: 2.4, wavelength: 36)
                        .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 8)
    }
}

/// A horizontal path that follows a low-amplitude sine — feels less mechanical
/// than a perfectly straight rule without screaming "wavy".
struct WobblePath: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let yMid = rect.midY
        let steps = max(2, Int(rect.width / 2))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + t * rect.width
            let y = yMid + sin(t * .pi * 2 * (rect.width / wavelength)) * amplitude
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return p
    }
}

/// Dotted vertical line used to connect timeline entries.
struct InkDottedRail: View {
    var color: Color = .rule

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: Theme.Stroke.hairline + 0.3,
                lineCap: .round,
                dash: [0.1, 6]
            ))
        }
        .frame(width: 2)
    }
}
