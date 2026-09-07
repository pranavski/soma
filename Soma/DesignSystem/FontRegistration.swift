import CoreText
import Foundation
import os

/// Registers the bundled typefaces with CoreText at launch.
///
/// The project generates its Info.plist from build settings, and Xcode has
/// no `INFOPLIST_KEY_UIAppFonts` — the setting is silently ignored, which is
/// how the app shipped Bradley Hand for weeks with the .ttf files sitting
/// right there in the bundle. Registering by URL at launch needs no plist
/// key at all and fails loudly in the log (and in `BundledFontsTests`)
/// rather than quietly.
///
/// Called once from `SomaApp.init`, before any view asks `Theme` for a font.
enum SomaFonts {
    private static let log = Logger(subsystem: "soma", category: "fonts")
    private static var registered = false

    /// The files under Soma/Fonts. Fraunces ships as two variable files;
    /// its named instances (Regular, Italic, SemiBold) come from those.
    static let bundledFiles = [
        "Caveat-Regular", "Caveat-Bold",
        "Fraunces-Regular", "Fraunces-Italic",
        "IBMPlexMono-Regular", "IBMPlexMono-Medium",
    ]

    static func registerBundledFaces(bundle: Bundle = .main) {
        guard !registered else { return }
        registered = true
        for file in bundledFiles {
            guard let url = bundle.url(forResource: file, withExtension: "ttf") else {
                log.error("font file missing from bundle: \(file, privacy: .public).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            // .process: visible to this app only, for its lifetime — the
            // scope UIAppFonts would have given.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
                log.error("font registration failed for \(file, privacy: .public): \(reason, privacy: .public)")
            }
        }
    }
}
