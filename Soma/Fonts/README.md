# Fonts — Soma type system

The app references three custom typefaces. Until the `.ttf` files are
dropped into this folder and registered with the bundle, `Theme.swift`
falls back to sensible system substitutes — the design still works, but
it's reading "borrowed" rather than "ours."

## Files to drop here

All three are free, from Google Fonts:

- **Caveat** — `Caveat-Regular.ttf`, `Caveat-Bold.ttf`
  https://fonts.google.com/specimen/Caveat
  Used as: `Font.hand(...)`, `Font.Soma.timestamp`,
  `Font.Soma.margin`, `Font.Soma.dateLabel`, `Font.Soma.signature`,
  `Font.Soma.tabLabel`.
  Fallback today: **Bradley Hand**.

- **Fraunces** — `Fraunces-Regular.ttf`, `Fraunces-Italic.ttf`,
  `Fraunces-SemiBold.ttf`
  https://fonts.google.com/specimen/Fraunces
  Used as: `Font.display(...)`, `Font.Soma.dayLine`,
  `Font.Soma.dish`, `Font.Soma.pullQuote`, `Font.Soma.logo`,
  `Font.Soma.buttonLg`.
  Fallback today: **system .serif italic**.

- **IBM Plex Mono** — `IBMPlexMono-Regular.ttf`, `IBMPlexMono-Medium.ttf`
  https://fonts.google.com/specimen/IBM+Plex+Mono
  Used as: `Font.ticket(...)`, `Font.Soma.caloric`,
  `Font.Soma.numeric`, `Font.Soma.stampTime`,
  `Font.Soma.sectionTag`, `Font.Soma.buttonSm`.
  Fallback today: **system .monospaced** (SF Mono).

## Registering the fonts in the bundle

Two steps after dropping the `.ttf` files into this folder:

1. Confirm the files appear in Xcode's file navigator under
   `Soma/Fonts/` and are checked into the **Soma** target's
   `Copy Bundle Resources` build phase.
   (The project uses file-system synchronized groups, so the files
   should appear automatically — but the target membership is worth
   double-checking.)

2. In the **Soma** target's *Build Settings*, add an entry for
   `Info.plist Values → Application Fonts Resource Path` — or, since
   this project uses `GENERATE_INFOPLIST_FILE = YES`, add this build
   setting directly:

   ```
   INFOPLIST_KEY_UIAppFonts = "Caveat-Regular.ttf Caveat-Bold.ttf Fraunces-Regular.ttf Fraunces-Italic.ttf Fraunces-SemiBold.ttf IBMPlexMono-Regular.ttf IBMPlexMono-Medium.ttf"
   ```

Once that's done, `Theme.swift`'s `customOrFallback` helper notices the
fonts via `UIFont(name:size:) != nil` and switches over — no code
change needed.

## Why these three

- **Caveat** reads as one specific person's writing. Bradley Hand reads
  as "system handwritten." The shift from B.H. → Caveat is the single
  biggest "this is no longer a wellness template" moment in the type
  system.
- **Fraunces** has cookbook-title warmth at display sizes and stays
  legible at body sizes via its optical-size axis.
- **IBM Plex Mono** is the *kitchen ticket* voice — the dot-matrix
  POS-printer tone that nothing else in the wellness category uses.
