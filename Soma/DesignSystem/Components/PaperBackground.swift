import SwiftUI

/// Oat-paper canvas with grain + a soft top-window vignette.
/// Drop this as the bottom layer of any screen.
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Color.paper

            // Window light from upper-left, like sun on a kitchen counter.
            RadialGradient(
                colors: [
                    Color.white.opacity(0.22),
                    Color.white.opacity(0.0)
                ],
                center: UnitPoint(x: 0.20, y: 0.06),
                startRadius: 20,
                endRadius: 520
            )
            .blendMode(.softLight)

            // Edge vignette — paper darkens as it bends away from the light.
            RadialGradient(
                colors: [
                    Color.paperShadow.opacity(0.0),
                    Color.paperShadow.opacity(0.55)
                ],
                center: UnitPoint(x: 0.5, y: 0.5),
                startRadius: 240,
                endRadius: 620
            )
            .blendMode(.multiply)

            PaperGrain()
                .opacity(0.45)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Static, photo-like grain produced by drawing many tiny dots at
/// deterministic positions. Seeded so it doesn't shimmer between redraws.
struct PaperGrain: View {
    var density: Int = 1100
    var seed: UInt64 = 0xA1B2C3D4

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(state: seed)
            for _ in 0..<density {
                let x = Double.random(in: 0...size.width,  using: &rng)
                let y = Double.random(in: 0...size.height, using: &rng)
                let r = Double.random(in: 0.25...0.95,     using: &rng)
                let a = Double.random(in: 0.04...0.16,     using: &rng)
                let rect = CGRect(x: x - r/2, y: y - r/2, width: r, height: r)
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.ink.opacity(a))
                )
            }
        }
    }
}

/// Tiny seeded PRNG — splitmix64. Just enough randomness for grain.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
}
