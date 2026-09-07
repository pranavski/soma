---
name: design-system
description: Soma's "kitchen notebook" (Mise direction) SwiftUI design
  system — paper/ink color tokens with named color jobs, the Fraunces /
  Caveat / IBM Plex Mono type system, and the inventory of reusable
  components (PaperBackground, InkRule, FoodGlyph/Plate, RecipeCard,
  ScreenTitle). Use for any UI work: new screen, new component,
  restyling, or referencing tokens.
---

# Soma Design System — "kitchen notebook" (Mise direction)

## Source of truth
There is no visual mockup file — `docs/food-body-record-mockup.jsx` was
planned but was never created and isn't coming. **The code is the
reference**: `Soma/DesignSystem/Theme.swift` and `Color+Soma.swift` for
tokens, `Soma/DesignSystem/Components/` for reusable pieces, and the
shipped screens (`InsightsView`, `TodayView`, `SettingsView`, ...) for
how they compose in practice. `docs/food-body-record-mvp-spec.md` is the
data-shape/copy authority, not a visual one.

The direction is called **"Mise"** in code comments (`RecipeCard.swift`:
"the central primitive of the Mise direction") — paper, ink, and a
kitchen notebook, not a glass/dark-mode dashboard. If you see references
to `mint`, `porcelain`, `HeroGlassCard`, or `CompletionRing` anywhere
(old docs, old chat history), they describe a direction that was
discarded before it shipped — don't build against it.

## Color tokens
Defined twice: once as a SwiftUI `Color` extension in
`Soma/DesignSystem/Color+Soma.swift`, once as Color Sets in
`Soma/Assets.xcassets/` (so SwiftUI previews and Xcode's asset catalog
can reach them by name). Every Color Set has a **light and dark
appearance** — day is warm oat-bond paper + cocoa ink, night is aubergine
ink + parchment. Build UI against the semantic name (`Color.persimmon`),
never a literal hex — dark mode falls out of the asset catalog for free.

**Each color has exactly one job.** Don't reach for `persimmon` because
it's pretty; reach for it because something is *marked*. This is the
rule most worth protecting as the app grows.

| Token (semantic)     | Asset name    | Light (day)         | Dark (night)         | Job |
|-----------------------|--------------|----------------------|-----------------------|-----|
| `Color.paper`          | canvas       | `#F0E6D2`            | `#1C1418`             | App background — the page. |
| `Color.paperRaised`    | surfaceRaised| `#F8EFDF`            | `#2C2024`             | Cards, sheets, anything sitting a layer above the page. |
| `Color.paperSunk`      | surface      | `#EFE5CE`            | `#241A1E`             | Recessed surfaces (code/ticket blocks, input wells). |
| `Color.ink`            | inkOnLight/inkOnDark | `#3A2A20`    | `#EFE3CC`             | **Voice** — everything written or spoken in the app's own voice: headlines, body copy. |
| `Color.inkSoft`        | inkDim       | `#8C7460`            | `#A8927E`             | Secondary/quiet text — captions, asides, timestamps. |
| `Color.rule`           | rule         | `#4A3A30` @45%        | `#B8A894` @38%         | Hairline dividers, borders. |
| `Color.paperShadow`    | paperShadow  | `#604C42` @28%        | `#000000` @55%         | Drop shadows, vignettes — never a flat black shadow. |
| `Color.persimmon`      | persimmon    | `#C8542B`            | `#DC6A42`              | **Marked** — the insight hedge caption, "you are here," edits, the dot in "Soma." Nothing else. |
| `Color.persimmonSoft`  | persimmonSoft| `#E8C4B0`            | `#443838`              | Wash/border for a persimmon-marked block (e.g. the "pivot" callout style). |
| `Color.bay` (asset: sage) | sage      | `#6F7A5C`            | `#828E6F`              | **Body data** — HealthKit, sleep, steps, the trend chart line. Dried-herb, not mint. |
| `Color.graphite`       | graphite     | `#3A4860`            | `#98A8B8`              | **Facts the user logged** — kcal, times, weights. A slate blue-grey, not literal pencil-graphite. |
| `Color.cardRule`       | cardRule     | `#B55246`            | `#C2605C`              | The red rule across the top of an index card. |
| `Color.cardLine`       | cardLine     | `#6088B0` @42%        | `#80A0C0` @38%         | Faint ruled-notebook horizontal lines (`RuledPaper`). |

`Color.sage` still exists as a deprecated alias for `Color.bay` — the
underlying asset is still named `sage` in the catalog (renaming assets is
a larger sweep), but new code should say `bay`.

## Type
Three typefaces, three jobs — this triangle (not any single face) is
what reads as "not a wellness template":

- **Fraunces** (`Font.display(...)`, `Font.Soma.logo/dayLine/pullQuote/dish/dishSmall/dishNote/buttonLg`) —
  display serif, mostly set *italic*. Cookbook-title warmth. This is the
  app's voice at headline size.
- **Caveat** (`Font.hand(...)`, `Font.Soma.dateLabel/timestamp/margin/signature/tabLabel/countDim`) —
  the handwritten voice. Used only for small, human-touch text: margin
  notes, timestamps, tab labels, the "pr." signature mark. Never body
  copy — it doesn't hold up at paragraph length.
- **IBM Plex Mono** (`Font.ticket(...)`, `Font.Soma.sectionTag/caloric/numeric/stampTime/buttonSm`) —
  the "kitchen ticket" voice, for numeric/structured data: eyebrows,
  calorie ranges, timestamps-as-data, small buttons. This is the detail
  that separates Soma from every other paper-journal wellness app.

**Status: the `.ttf` files are not yet bundled.** `Soma/Fonts/README.md`
has the fetch list (all three are free on Google Fonts) and the
`INFOPLIST_KEY_UIAppFonts` step. Until they're dropped in,
`Theme.swift`'s `customOrFallback` silently substitutes system faces
(serif-italic for Fraunces, Bradley Hand for Caveat, SF Mono for Plex
Mono) — the app still looks intentional, just "borrowed" rather than
"ours." Check `UIFont(name:size:)` behavior before assuming a screenshot
reflects the real type system.

Full scale lives in `Font.Soma` in `Theme.swift` — reach for an existing
role (`.pullQuote`, `.sectionTag`, `.margin`, ...) before hand-rolling a
new `Font.display(size:)` call.

## Component inventory
Every reusable component lives in `Soma/DesignSystem/Components/` as a
single file. Go through this list before adding a new one — if it fits
an existing component, extend it.

- **`PaperBackground`** (+ `PaperGrain`) — the page substrate. Warm paper
  color, a soft upper-left "window light" radial gradient, an edge
  vignette, and deterministic (seeded) grain via `Canvas`-drawn dots so
  it doesn't shimmer on redraw. Drop as the bottom layer of any screen.
- **`InkRule`** (+ `WobblePath`, `InkDottedRail`) — hand-drawn-feeling
  horizontal rule. Three styles: `.solid` (a low-amplitude sine wobble,
  not a straight line), `.dotted` (bead-like), `.wavy` (higher-amplitude
  sine, used for section breaks). `InkDottedRail` is the vertical
  version, for timeline connectors.
- **`FoodGlyph`** (+ `FoodGlyphView`, `Plate`, `Signature`) — 12
  hand-authored ink illustrations (lemon, egg, mug, bowl, sprig, toast,
  leaf, knife, cherry, fish, noodle, wine) as `Shape`s with deliberately
  imperfect control points — "19th-century food encyclopedia," not clip
  art. Each has a stable plate numeral (`FoodGlyph.numeral`, e.g. lemon
  is always № 01) and a semi-invented Latin caption. `FoodGlyph.from(_:)`
  best-effort-matches a dish name to a glyph. `Plate` composes glyph +
  numeral + optional caption; `Signature` is the small rotated "pr."
  hand-mark.
- **`RecipeCard`** (+ `MacroStrip`, `RuledPaper`) — the central card
  primitive: time (mono) → dish name (serif italic) → calorie range +
  aside (mono/hand) → optional macro strip → a `Plate` glyph. One look
  everywhere it's used — no variants, no tilt, no per-card grain.
  `RuledPaper` is the procedural blue-line notebook-page texture (used
  behind insight feed cards via `.overlay`).
- **`ScreenTitle`** (+ `SectionHeader`) — top-of-screen eyebrow (mono,
  tracked) + big italic Fraunces title. `SectionHeader` is the smaller
  wavy-rule-plus-label pattern used to open a subsection.
- **`WaxPaperOverlay`** (+ `WaxTab`, `WaxPaperToggleButton`) —
  ⚠️ **dormant.** The "drag yesterday over today as translucent wax
  paper" gesture was retired from `TodayView`; the file still compiles
  (kept working against the simplified `RecipeCard`) but nothing calls
  it. Don't build new features assuming it's live — check `TodayView`
  first. Safe to delete in a follow-up per its own header comment.

**Screen-local patterns that aren't (yet) promoted to the shared
inventory**, worth knowing about before you duplicate them elsewhere:
`InsightsView`'s `InsightFeedCard` (a `RuledPaper`-backed "lab page" card
— claim in `.pullQuote`, evidence in `.dishNote`, the hedge caption
always in `Color.persimmon`) and `ConfidenceBadge` (ink-intensity scale,
not traffic-light colors: low fades toward `inkSoft`, high is full
`ink`). `Features/Insights/TrendChart.swift` is a feature-level
composition built entirely from the tokens above — good reference for
"how do I build a new feature that still looks like Soma," since it
doesn't introduce anything not in this inventory.

`Features/Meals/MealCardActions.swift` is the press-and-hold menu on a
meal card (correct it / take it off the record, delete always behind a
confirmation) plus the `MealCardHint` margin note that makes the
long-press findable. Both Today and History attach it via
`.mealCardActions(for:onCorrect:onDelete:)` — extend that rather than
adding a second gesture for editing meals.

`Features/Meals/CaptureSheet.swift` is the ORDER UP ticket — speak /
type / "a familiar one" chips, plus the bounded "when" control that lets
an entry be filed onto an earlier time or day. Today presents it against
now; History presents the same sheet against the day selected in the
ledger (`PlateOnDayRow`, the dashed "plate one" invitation under the
day's check-in row). Both hand the work to `MealLogger`, and the window a
"when" may land in is `MealEntryWindow` — never the future, never past
the insight engine's 30 days.

Logging belongs to **Today and History** — capture now, or fill in a day
you missed. It does **not** belong on Insights: that feed used to carry a
pinned quick-log input (`QuickLogField`, removed), it's read-only now, and
new "just type it here" entry points don't belong on it.

## Rules
- **One job per color.** Before using a token, ask what job it's doing —
  if the answer isn't one of the jobs in the color table, it's the wrong
  token.
- **Hand-drawn imperfection over pixel-perfect vector.** Rules wobble
  (`WobblePath`), grain is seeded-random not a flat texture, glyph
  control points are deliberately slightly off "perfect." A brand-new
  component that renders as crisp, mechanical vector will look foreign
  next to everything else — bring some imperfection in on purpose.
- Calories (and macros) in copy: always a range —
  `"~\(low)–\(high)"`. Never a bare number. Enforced today by
  `Meal.calorieRange` / `MacroBreakdown` on the model side.
- The index-card / notebook-paper motif (`Theme.Radius.indexCard` = 3,
  `Theme.Card` metrics, `RuledPaper`) is the closest thing to a signature
  shape language — sharp-ish corners, not chunky rounded pills
  (`Theme.Radius.card` is only 6). Reach for it before inventing a new
  card silhouette.
- Prefer SF Symbols for utility glyphs (chevrons, camera, mic, tab bar
  icons). Custom hand-drawn shapes are reserved for `FoodGlyph` brand
  moments (covered by the [[svg-assets]] skill for anything exported as
  an asset rather than drawn live as a SwiftUI `Shape`).
- New components go through the inventory above before being created —
  if it fits an existing component, extend it; don't invent a parallel
  one.
