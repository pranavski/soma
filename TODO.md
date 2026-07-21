# Soma — TODO

Prove the meal-log loop end-to-end before anything else. Voice transcript →
row insert → real Claude parse → Today shows the result. Skip photos, skip
HealthKit, skip insights until this slice works.

## Move 1 — Wire `parse-meal` to Claude (voice-only) ✅
- [x] Anthropic Messages call in `supabase/functions/parse-meal/index.ts`
      against the strict JSON contract.
- [x] Server-side shape validator (`isParsedMeal`); mismatch → 422 fallback.
- [x] Voice branch only; photo branch short-circuits to 422 fallback.
- [ ] Set `ANTHROPIC_API_KEY` via `supabase secrets set` (do NOT commit).
- [ ] Deploy: `supabase functions deploy parse-meal`.
- [ ] Smoke-test with a real user JWT + stub `meals` row.

## Move 2 — Capture sheet + `MealsRepository.insert` ✅
- [x] `MealsRepository.insertPendingMeal(source:, voiceTranscript:, eatenAt:)`.
- [x] `CaptureSheet` replaces the two-Text stub: Speak (SFSpeechRecognizer)
      + Type it (TextField), Send button.
- [x] `TodayViewModel.submit(transcript:)` inserts pending row + invokes
      `parse-meal` + reloads.
- [x] `Meal.displayName` state-aware ("parsing…" / "couldn't read that").
- [x] Info.plist mic + speech usage strings.

## Move 3 — Cheap unblockers ✅
- [x] `IPHONEOS_DEPLOYMENT_TARGET` 26.0 → 17.0 (both Debug + Release).
- [x] Sign-out row in `SettingsView` wired to `SessionStore.signOut()`.

## Explicitly deferred
- HealthKit (entitlement, NSHealthShareUsageDescription, HKHealthStore,
  daily aggregation, `health_days` upsert). No value until ~7 days of meals
  exist to correlate against.
- `generate-insights` v1 rules. Need real meals + `health_days` to tune
  thresholds against; synthetic data will mislead.
- History / Insights / Settings data wiring. Cosmetic until meals exist.
- AppIcon, missing `docs/food-body-record-mockup.jsx`, XCTest target.

## One-week target
Open the sim, tap +, say "two eggs on sourdough with avocado," wait ~2s,
see "Eggs on sourdough · ~380–520" on Today with three `meal_items`
underneath.
