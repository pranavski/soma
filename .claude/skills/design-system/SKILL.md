---
name: design-system
description: Soma's "midnight lab" SwiftUI design system — color and type
  tokens, plus the inventory of reusable components (PlateView, GlassCard,
  CompletionRing, SleepBar, Sparkline, InsightCard, TimelineRow, RepeatChip).
  Use for any UI work: new screen, new component, restyling, or referencing
  tokens. Reference mockup: docs/food-body-record-mockup.jsx.
---

# Soma Design System — "midnight lab"

## Source of truth
The visual reference is `docs/food-body-record-mockup.jsx`. When the spec and
the mockup disagree, the mockup wins for visual decisions; the spec wins for
data shape and copy.

## Color tokens
Defined twice: once as a SwiftUI `Color` extension in `Soma/DesignSystem/Color+Soma.swift`,
once as Color Sets in `Soma/Assets.xcassets/` (so SwiftUI previews and
SF Symbols can reach them by name).

| Token              | Hex      | Use                                          |
|--------------------|----------|----------------------------------------------|
| `canvas`           | #090D13  | App background                               |
| `surface`          | #0E1820  | Cards, sheets                                |
| `surfaceRaised`    | #142230  | Elevated cards (hero glass)                  |
| `mint`             | #4FE3C1  | Primary brand — luminous on dark             |
| `mintHi`           | #7BF2D8  | Gradient stop 0                              |
| `mintMid`          | #17B894  | Gradient stop 1                              |
| `mintLo`           | #0C6E5C  | Gradient stop 2                              |
| `violet`           | #8B7CF6  | Secondary, sparing                           |
| `coral`            | #F2786D  | Flag / "not really" signal                   |
| `porcelainHi`      | #F4F9FA  | Insight card top                             |
| `porcelainLo`      | #DFEAEC  | Insight card bottom                          |
| `inkOnLight`       | #16242B  | Text on porcelain surfaces                   |
| `inkOnDark`        | #E8F1F4  | Text on canvas                               |
| `inkDim`           | #8FA0AB  | Secondary text on dark                       |

The mint gradient is 135° from `mintHi` → `mintMid` → `mintLo`.

## Type
- **Display / numerals / dish names:** Instrument Serif (or New York fallback).
  Tabular for numerals. Loose tracking on large display sizes.
- **UI:** SF Pro Rounded for chips and timeline rows; SF Pro for body.
- **Sizing scale:** 11 (caption), 13 (label), 15 (body), 17 (body-strong),
  22 (title3), 28 (title2), 40 (hero stat), 64 (insight stat).

## Component inventory
Every component lives in `Soma/DesignSystem/Components/` as a single file.

- **`HeroGlassCard`** — `surfaceRaised` background, 1px top-light inner
  highlight, layered shadows (tight 0 1 2 black/40, wide 0 24 48 black/55).
  Corner radius 28. Contains today's plate + ring.
- **`PlateView`** — porcelain disc with mint gradient ring, gloss highlight
  arc top-left, rim shadow underneath. Driven by a fraction (0…1) for fill
  state. Always renders calories as a **range** string ("~550–700"), never
  a single number.
- **`CompletionRing`** — SwiftUI Canvas/Path, not SVG. Mint gradient stroke,
  rounded line cap, soft outer glow. Backing track at 18% opacity.
- **`SleepBar`** — horizontal stacked bar showing sleep stages or simply
  duration; mint primary, violet accent for deep/REM when Tier 2 data exists.
- **`Sparkline`** — SwiftUI Canvas, 2px mint stroke, optional dot at latest
  point. Width-flexible; pass `[Double]` and a y-range.
- **`InsightCard`** — porcelain surface, oversized serif stat (64pt),
  comparison bars beneath, True/Not-really chips at the bottom.
- **`TimelineRow`** — dish thumbnail (or plate glyph) + dish name (serif) +
  calorie range + repeat chip if recurring; tappable to expand.
- **`RepeatChip`** — small pill: "x5 this week" in inkDim.
- **`GlassCard`** — generic version of HeroGlassCard for secondary surfaces.

## Rules
- Glass surfaces ALWAYS get the 1px top-light inner highlight (mimics a real
  glass edge under a downlight) — implement as an overlay stroke at the top.
- Shadows are layered: one tight + one wide, both black with opacity ≤ 60%.
- Calories in copy: always a range — `"~\(low)–\(high)"`. Never a bare number.
- Prefer SF Symbols for utility glyphs (chevrons, camera, mic). Custom SVGs
  are only for brand moments (covered by the [[svg-assets]] skill).
- New components go through the inventory above before being created — if it
  fits an existing component, extend it; don't invent a parallel one.
