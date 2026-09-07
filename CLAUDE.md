# Soma — Food–Body Record iOS App

## What this is
10-second meal logging for people who cook (voice / typing / one-tap
repeats; photo logging is deferred to v1.1)
+ read-only HealthKit, with a nightly (plus on-demand) insight engine
surfacing honest correlations. Understanding, NOT dieting: no goals, no
streaks-shaming, no calorie targets, never medical advice.

## Stack
SwiftUI iOS 17+, MVVM, async/await. Supabase (Auth via Sign in with Apple,
Postgres, private Storage, Edge Functions). Claude API called ONLY from
Edge Functions — `claude-sonnet-4-6` for parse-meal, `claude-haiku-4-5`
for generate-insights (it selects and writes copy; it does no arithmetic).
HealthKit read-only.

## Source-of-truth docs — read before relevant work
- docs/food-body-record-mvp-spec.md  (schema, screens, insight rules)
- Soma/DesignSystem/ (Theme.swift, Color+Soma.swift, Components/) — the
  "kitchen notebook" (Mise direction) UI system. There is no visual
  mockup file; the code itself is the reference. See the design-system
  skill.

## Skills
Use .claude/skills/: svg-assets (any icon/illustration work),
design-system (any UI work), supabase-flow (any DB work),
insight-rules (any insight engine work).

## Build & deploy tooling
- Supabase: no Supabase MCP server is configured — use the `supabase`
  CLI directly (`supabase db push`, `supabase functions deploy`,
  `supabase secrets set`, ...). Inspect schema / verify RLS before and
  after migrations.
- Xcode: no xcodebuild MCP server is configured — use `xcodebuild`
  directly. After EVERY Swift change: build, fix errors, then run on the
  iPhone 16 simulator and check logs before reporting done.
- No GitHub MCP either — use `gh`. One PR per phase, conventional commits.
- CI: `.github/workflows/ci.yml` runs the Deno tests and the iOS build +
  unit tests on every push and PR.

## Working conventions
- Ship-time constants (privacy URL, support email) live in
  `Soma/Core/SomaFeatures.swift`; `TODO.md` and `docs/deployment-checklist.md`
  are the live status lists — keep them current when finishing work.

## Hard rules
- Calories are ALWAYS ranges in UI copy ("~550–700"), never bare numbers
- Insights are hedged ("worth watching, not a verdict"), gated by data
  coverage (meal-logging + body-signal days), never repeated, never
  prescriptive
- HealthKit raw reads stay on-device; only daily aggregates sync
- No force-unwraps outside tests; unit tests for parsing decoder,
  insight thresholds, HealthKit aggregation
- API keys never in the iOS bundle
