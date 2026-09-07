import XCTest
import UIKit
@testable import Soma

/// The design system names three typefaces and falls back silently when a
/// name doesn't resolve — which is how the app shipped Bradley Hand and SF
/// Mono for weeks without anyone noticing. This test runs inside the app
/// host on the simulator, so it exercises the real bundle registration
/// (`SomaFonts.registerBundledFaces()` over the files under Soma/Fonts):
/// if a face stops resolving, the fallback is no longer quiet.
final class BundledFontsTests: XCTestCase {
    func testEveryNamedFaceResolvesFromTheBundle() {
        // The app host has already run SomaApp.init; calling again is a
        // no-op, and makes the test honest when run in isolation.
        SomaFonts.registerBundledFaces()
        for name in SomaFontName.all {
            XCTAssertNotNil(UIFont(name: name, size: 17),
                            "\(name) did not resolve — Theme will fall back to a system face")
        }
    }
}
