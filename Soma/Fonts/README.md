# Fonts — Soma type system

Three typefaces, all under the SIL Open Font License (the OFL texts sit
alongside the files and ship in the bundle, as the licence asks):

- **Caveat** — `Caveat-Regular.ttf`, `Caveat-Bold.ttf` (static).
  The handwritten voice: `Font.hand(...)`, `Font.Soma.timestamp`,
  `Font.Soma.margin`, `Font.Soma.dateLabel`, `Font.Soma.signature`,
  `Font.Soma.tabLabel`.
- **Fraunces** — `Fraunces-Regular.ttf`, `Fraunces-Italic.ttf`
  (the variable roman and italic files, opsz/wght/SOFT/WONK axes).
  `Theme.swift` asks for the named instances `Fraunces-Regular`,
  `Fraunces-Italic` and `Fraunces-SemiBold`; CoreText exposes those from
  the variable files, and the optical-size axis lets the same file serve
  the wordmark and a dish name. `Font.display(...)`, `Font.Soma.dayLine`,
  `Font.Soma.dish`, `Font.Soma.pullQuote`, `Font.Soma.logo`,
  `Font.Soma.buttonLg`.
- **IBM Plex Mono** — `IBMPlexMono-Regular.ttf`, `IBMPlexMono-Medium.ttf`
  (static). The kitchen-ticket voice: `Font.ticket(...)`,
  `Font.Soma.caloric`, `Font.Soma.numeric`, `Font.Soma.stampTime`,
  `Font.Soma.sectionTag`, `Font.Soma.buttonSm`.

## How they're registered

The project uses a file-system-synchronized group, so anything in this
folder is a bundle resource automatically. The faces are registered at
launch by `SomaFonts.registerBundledFaces()` (`DesignSystem/FontRegistration.swift`)
with CoreText — not through `UIAppFonts`, because this project generates
its Info.plist from build settings and Xcode has no `INFOPLIST_KEY_` for
that key (it is silently ignored). Adding a file here means adding its
name to `SomaFonts.bundledFiles`.

`SomaTests/BundledFontsTests` checks that every name in
`SomaFontName.all` resolves with `UIFont(name:)` inside the app host. The
runtime fallback in `Theme.swift` (`customOrFallback`) still exists, so a
missing face degrades to Bradley Hand / system serif / SF Mono rather than
crashing — but the test makes sure that never ships silently.

## Updating a face

Replace the file in place (same name), keep the OFL text next to it, and
run the test target. If the file name changes, update `SomaFonts.bundledFiles`;
if the PostScript name changes, update `SomaFontName` too.

## Why these three

- **Caveat** reads as one specific person's writing. Bradley Hand reads
  as "system handwritten." That shift is the single biggest "this is no
  longer a wellness template" moment in the type system.
- **Fraunces** has cookbook-title warmth at display sizes and stays
  legible at body sizes via its optical-size axis.
- **IBM Plex Mono** is the *kitchen ticket* voice — the dot-matrix
  POS-printer tone that nothing else in the wellness category uses.
