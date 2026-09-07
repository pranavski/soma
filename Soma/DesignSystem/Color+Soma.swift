import SwiftUI

// "Kitchen notebook" palette (Mise direction).
// Day: warm oat-bond paper + cocoa ink.
// Night: aubergine ink + parchment.
//
// Color jobs (each color has exactly one):
//   persimmon — *marked* (insight underline, "you are here", edits, dot in Soma.)
//   bay       — body data (HealthKit, sleep, steps). Dried-herb, not mint.
//   graphite  — facts the user logged (kcal, times, weights)
//   ink       — voice (everything written or spoken in the app's voice)
//
// Card-stock chrome:
//   cardRule  — the red line at the top of an index card
//   cardLine  — the faint blue horizontal rules
extension Color {
    static let paper        = Color("canvas")
    static let paperRaised  = Color("surfaceRaised")
    static let paperSunk    = Color("surface")

    static let ink          = Color("inkOnLight")
    static let inkSoft      = Color("inkDim")
    static let rule         = Color("rule")
    static let paperShadow  = Color("paperShadow")

    // Marked / accent
    static let persimmon     = Color("persimmon")
    static let persimmonSoft = Color("persimmonSoft")

    // Body data — retinted from mint-sage to dried bay-leaf.
    // The asset is still named "sage" in the catalog; we keep the file name
    // to avoid breaking other references but expose `bay` as the semantic name.
    static let bay           = Color("sage")

    // Facts / logged numerics
    static let graphite      = Color("graphite")

    // Index-card chrome
    static let cardRule      = Color("cardRule")    // red top rule
    static let cardLine      = Color("cardLine")    // faint blue body rules
}
