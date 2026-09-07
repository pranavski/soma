# Soma

A food–body record for people who cook. Log a meal in about ten seconds
(speak it, type it, or tap a recent dish), optionally connect Apple Health,
and a nightly statistics engine looks for honest, hedged patterns between
what you ate and how your body responded. Not a diet app: no goals, no
streaks, no calorie targets, never medical advice.

- `Soma/` — SwiftUI app, iOS 17+, iPhone only. MVVM, async/await.
- `supabase/` — Postgres migrations and Deno Edge Functions
  (`parse-meal`, `generate-insights`, `submit-correction`, `delete-account`).
- `docs/` — the MVP spec, privacy policy, App Store compliance map and
  deployment checklist. Read `docs/food-body-record-mvp-spec.md` first.
- `.claude/skills/` — the design system, Supabase workflow and insight
  rules, as skills for Claude Code.

## Build

Open `Soma.xcodeproj` in Xcode 16 or later, or:

```sh
xcodebuild -project Soma.xcodeproj -scheme Soma \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The anon Supabase key and project URL are compiled in (`SupabaseConfig`);
they are public by design — RLS is what authorises. No other key lives in
the bundle.

## Test

```sh
# iOS unit tests (decoder, insight thresholds, HealthKit bucketing, fonts…)
xcodebuild -project Soma.xcodeproj -scheme Soma \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Edge Function tests
deno test --allow-read supabase/functions
```

CI runs both on every push and pull request (`.github/workflows/ci.yml`).

## Deploy

See `docs/deployment-checklist.md`. In short: `supabase db push`, set the
secrets, `supabase functions deploy <name>`, then the App Store Connect
items in `docs/app-store-compliance.md` §6.

## Screenshot mode

Debug builds honour `SOMA_PREVIEW=1` (skip sign-in, load sample data),
`SOMA_PREVIEW_TAB`, `SOMA_PREVIEW_SHEET=capture|checkin`,
`SOMA_PREVIEW_COMPARE=1` (wax paper down), `SOMA_PREVIEW_SCROLL` and
`SOMA_PREVIEW_EMPTY=1` as environment variables
on the simulator run. All of it compiles out of Release.

## Fonts

Caveat, Fraunces and IBM Plex Mono ship in `Soma/Fonts` under the SIL Open
Font License; see the README there.
