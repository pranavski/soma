# Soma — Food–Body Record iOS App

## What this is
10-second meal logging for people who cook (voice / typing / one-tap
repeats; photo logging is deferred to v1.1)
+ read-only HealthKit, with a weekly insight engine surfacing honest
correlations. Understanding, NOT dieting: no goals, no streaks-shaming,
no calorie targets, never medical advice.

## Stack
SwiftUI iOS 17+, MVVM, async/await. Supabase (Auth via Sign in with Apple,
Postgres, private Storage, Edge Functions). Claude API (claude-sonnet-4-6)
called ONLY from Edge Functions. HealthKit read-only.

## Source-of-truth docs — read before relevant work
- docs/food-body-record-mvp-spec.md  (schema, screens, insight rules)
- docs/food-body-record-mockup.jsx   (UI reference, midnight lab)

## Skills
Use .claude/skills/: svg-assets (any icon/illustration work),
design-system (any UI work), supabase-flow (any DB work),
insight-rules (any insight engine work).

## MCP usage
- supabase MCP: inspect schema / verify RLS before and after migrations
- xcodebuild MCP: after EVERY Swift change — build, fix errors, then run
  on iPhone 16 simulator and check logs before reporting done
- github MCP: one PR per phase, conventional commits

## Hard rules
- Calories are ALWAYS ranges in UI copy ("~550–700"), never bare numbers
- Insights are hedged ("worth watching, not a verdict"), tier-gated by
  data availability, never repeated, never prescriptive
- HealthKit raw reads stay on-device; only daily aggregates sync
- No force-unwraps outside tests; unit tests for parsing decoder,
  insight thresholds, HealthKit aggregation
- API keys never in the iOS bundle
