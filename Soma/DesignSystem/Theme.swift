import SwiftUI
import UIKit

enum Theme {
    enum Radius {
        static let card: CGFloat   = 6      // paper has sharp edges, not chunky pills
        static let pill: CGFloat   = 999
        static let chip: CGFloat   = 4
        static let sheet: CGFloat  = 24
        static let indexCard: CGFloat = 3   // 3x5 cards are nearly square-cornered
    }

    enum Spacing {
        static let xs: CGFloat  = 4
        static let s:  CGFloat  = 8
        static let m:  CGFloat  = 12
        static let l:  CGFloat  = 16
        static let xl: CGFloat  = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Stroke {
        static let hairline: CGFloat = 0.6
        static let pen:      CGFloat = 1.25
        static let nib:      CGFloat = 1.6
    }

    /// Chrome the tab bar owns at the bottom of every signed-in screen.
    /// `barHeight` is the painted strip above the home indicator; screens
    /// that pin something (Today's capture pill, Insights' quick-log) sit
    /// `contentClearance` up from the bottom so they clear the bar instead
    /// of guessing at a magic number each time.
    enum TabBar {
        static let barHeight: CGFloat = 62
        static let contentClearance: CGFloat = barHeight + Spacing.xl
        /// Bottom padding for the last element of a scrolling screen.
        static let scrollBottomInset: CGFloat = contentClearance + Spacing.xxl
    }

    /// 3×5 index card proportions, the spine of the Mise direction.
    enum Card {
        static let aspect: CGFloat = 5.0 / 3.0     // h/w when laid as a portrait card
        static let rule: CGFloat = 24              // distance between ruled blue lines
        static let topRuleInset: CGFloat = 28      // red top rule offset from top edge
        static let bodyInset: CGFloat = 18
    }
}

/// Font names of the custom faces the design system uses. The files live
/// in Soma/Fonts and are registered at launch by `SomaFonts` (CoreText, not
/// a plist key — see that file); if a name ever stops resolving (a file
/// dropped from the target, a renamed face) `customOrFallback` still
/// degrades to a system face so the app keeps looking intentional — and
/// `BundledFontsTests` fails, so the fallback can't ship unnoticed again.
///
/// Fraunces is bundled as its two variable files (roman and italic);
/// "Fraunces-SemiBold" is a named instance of the roman file, which
/// CoreText exposes under that PostScript name.
enum SomaFontName {
    static let hand        = "Caveat-Regular"          // OFL, Google Fonts
    static let handBold    = "Caveat-Bold"
    static let displayReg  = "Fraunces-Regular"        // OFL, Google Fonts
    static let displayItal = "Fraunces-Italic"
    static let displaySemi = "Fraunces-SemiBold"
    static let mono        = "IBMPlexMono-Regular"     // OFL, Google Fonts
    static let monoMed     = "IBMPlexMono-Medium"

    static let all = [hand, handBold, displayReg, displayItal, displaySemi, mono, monoMed]
}

private func customOrFallback(_ name: String, size: CGFloat, fallback: Font) -> Font {
    UIFont(name: name, size: size) != nil ? Font.custom(name, size: size) : fallback
}

extension Font {
    /// Display serif. Fraunces if available; system serif italic otherwise.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = true) -> Font {
        let name = italic ? SomaFontName.displayItal
                          : (weight >= .semibold ? SomaFontName.displaySemi : SomaFontName.displayReg)
        let fallback: Font = {
            let base = Font.system(size: size, weight: weight, design: .serif)
            return italic ? base.italic() : base
        }()
        return customOrFallback(name, size: size, fallback: fallback)
    }

    /// Handwritten. Caveat if available; Bradley Hand as a stand-in.
    /// Caveat reads as a specific person's writing; Bradley Hand reads as
    /// "system handwritten" — keep that fact in mind when reviewing the
    /// app pre- vs. post-font.
    static func hand(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight >= .semibold ? SomaFontName.handBold : SomaFontName.hand
        let fallback = Font.custom("Bradley Hand", size: size).weight(weight)
        return customOrFallback(name, size: size, fallback: fallback)
    }

    /// Kitchen-ticket monospace. Plex Mono if available; SF Mono otherwise.
    /// This is the *new* voice — it's what separates Soma from every
    /// other "paper journal" wellness app.
    static func ticket(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight >= .medium ? SomaFontName.monoMed : SomaFontName.mono
        let fallback = Font.system(size: size, weight: weight, design: .monospaced)
        return customOrFallback(name, size: size, fallback: fallback)
    }

    enum Soma {
        // Wordmark + hero  — Fraunces italic (display)
        static let logo       = Font.display(34, weight: .regular, italic: true)
        static let dayLine    = Font.display(42, weight: .regular, italic: true)
        static let pullQuote  = Font.display(26, weight: .regular, italic: true)

        // Section / structure — ticket all-caps for eyebrows
        static let sectionTag = Font.ticket(10, weight: .medium)
        static let dateLabel  = Font.hand(15, weight: .regular)

        // Dish copy — italic serif
        static let dish       = Font.display(22, weight: .regular, italic: true)
        static let dishSmall  = Font.display(18, weight: .regular, italic: true)
        static let dishNote   = Font.display(14, weight: .regular, italic: false)

        // Numeric / data — kitchen ticket mono
        static let caloric    = Font.ticket(11, weight: .regular)
        static let numeric    = Font.ticket(13, weight: .medium)
        static let stampTime  = Font.ticket(10, weight: .medium)

        // Handwritten — the human voice
        static let timestamp  = Font.hand(17, weight: .regular)
        static let margin     = Font.hand(13, weight: .regular)
        static let signature  = Font.hand(12, weight: .regular)

        // Buttons + small chrome
        static let buttonLg   = Font.display(17, weight: .semibold, italic: true)
        static let buttonSm   = Font.ticket(12, weight: .medium)
        static let countDim   = Font.hand(13, weight: .regular)
        static let tabLabel   = Font.hand(12, weight: .regular)
    }
}

// MARK: - Font.Weight comparable shim
// Default Font.Weight is not Comparable. We just need >= for the helpers above.
extension Font.Weight {
    fileprivate static func >= (lhs: Font.Weight, rhs: Font.Weight) -> Bool {
        weightOrder(lhs) >= weightOrder(rhs)
    }
    fileprivate static func weightOrder(_ w: Font.Weight) -> Int {
        switch w {
        case .ultraLight: return 0
        case .thin:       return 1
        case .light:      return 2
        case .regular:    return 3
        case .medium:     return 4
        case .semibold:   return 5
        case .bold:       return 6
        case .heavy:      return 7
        case .black:      return 8
        default:          return 3
        }
    }
}
