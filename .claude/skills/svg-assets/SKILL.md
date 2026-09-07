---
name: svg-assets
description: Create and maintain Soma's custom SVG assets — app icon, tab bar
  icons, empty-state illustrations, and decorative marks. Use whenever a task
  involves icons, illustrations, the app icon, launch screen, or any vector
  graphic. Also covers converting SVGs into Xcode asset catalog formats.
---

# Soma SVG Assets

## Where things live
- Source SVGs: `DesignAssets/svg/` (committed; the source of truth)
- App icon master: `DesignAssets/master/app-icon-1024.png` (a supplied raster,
  not an SVG — edit or replace that file, never the asset catalog PNG)
- Generated: `Soma/Assets.xcassets/` (never hand-edit generated PNGs)
- Conversion script: `DesignAssets/build-assets.sh`

## Visual language ("midnight lab")
- Canvas: deep blue-black #090D13; surfaces #0E1820
- Primary: mint #4FE3C1 (luminous — pair with soft outer glow on dark)
- Gradient: #7BF2D8 → #17B894 → #0C6E5C at 135°
- Secondary: violet #8B7CF6, sparingly
- Signals: mint = good, coral #F2786D = flag
- Light surfaces (insight cards): #F4F9FA → #DFEAEC
- Strokes: 2–2.5px, round caps/joins. Geometry: circles and smooth curves
  (plates, rings, waves) over sharp angles. No emoji inside SVGs.

## Required assets
1. App icon: a line-drawn profile lifting chopsticks from a persimmon bowl on
   paper (`#F7F2E8`) — the record of a person eating, not a diet badge. Flat,
   bold, readable at 60px. 1024×1024 master, no alpha in the built PNG.
2. Tab icons (4): today (plate ring), record (stacked bars), insights
   (spark/asterisk), dishes (bowl) — 24×24 viewBox, stroke-based, single
   currentColor so SwiftUI can tint active/inactive.
3. Empty states (3): no-meals-yet, no-insights-yet (needs ~2 weeks of data),
   no-health-permissions — simple 200×160 line illustrations, one mint accent.
4. Launch mark: wordmark "Soma." with mint period.

## Rules
- Hand-write clean SVG: viewBox, no editor cruft, no embedded rasters
- Stroke-based icons must use `stroke="currentColor"` (tintable);
  illustrations may use the palette directly
- Optimize: no hidden layers, merged paths where sensible, 2-decimal coords
- After creating/changing any SVG, run `DesignAssets/build-assets.sh`
  (rsvg-convert → PNG @1x/2x/3x into the asset catalog; app icon → all sizes).
  If rsvg-convert is missing: `brew install librsvg`
- In SwiftUI prefer SF Symbols for generic glyphs (chevrons, camera, mic);
  custom SVGs are ONLY for brand moments (tabs, icon, empty states)
- Data viz (ring, sparkline) is drawn natively in SwiftUI (Canvas/Path),
  NOT shipped as static SVG — but match the SVG language above
