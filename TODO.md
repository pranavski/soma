# Soma — TODO

Live list. Everything the audit of 2026-09-07 called partially built or
broken has been fixed in code; what remains is hosting, App Store Connect
and deploy steps that need a human with credentials.

## Before the next TestFlight build
- [ ] `supabase db push` — two migrations (insights read-only for clients,
      `insight_runs`), then `supabase migration list` to confirm.
- [ ] `supabase functions deploy generate-insights submit-correction delete-account`
      (`parse-meal` is deployed separately with menu awareness).
- [ ] Confirm the four `APPLE_*` secrets are set, or SIWA token revocation
      silently no-ops during account deletion.
- [ ] Host `docs/privacy-policy.md` (GitHub Pages), set
      `SomaFeatures.privacyPolicyURL`, flip `privacyPolicyIsHosted`.
- [ ] App Store Connect: privacy URL, support URL, nutrition label, age
      rating, review notes, screenshots — docs/app-store-compliance.md §6.

## Nice to have, not blocking
- [ ] `scripts/build-fdc-reference.ts` has never been run to completion;
      `_shared/fdc-reference.json` is empty and the composition block in
      the parse prompt is dormant until it is.
- [ ] Macro / caffeine / alcohol ranges are not editable from the
      correction sheet; after a correction the meal keeps Claude's values
      for those six.
- [ ] Feedback rows (`app_feedback`) have no inbox beyond the SQL console.
- [ ] Meal plans — design note only (docs/meal-plans-design.md), no code.

## Done (kept for the record)
- Voice / typed meal → pending row → Claude parse → Today card.
- Declined AI consent files the meal as written, correction open.
- Corrections rewrite meal_items; corrected rows repeatable and re-correctable.
- HealthKit read-only rollup, background delivery, disconnect, purpose
  string names all seven types.
- Nightly + on-demand insight engine with FDR, evidence layer, reflections,
  per-user throttle on pull-to-refresh.
- Fonts bundled (Caveat, Fraunces, IBM Plex Mono).
- Wax-paper "compare yesterday" on Today.
- CI (Deno tests + iOS build/tests), README.
