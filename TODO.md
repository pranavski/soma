# Soma — TODO

Live list. Everything the audit of 2026-09-07 called partially built or
broken has been fixed in code; what remains is hosting, App Store Connect
and deploy steps that need a human with credentials.

## Before the next TestFlight build
- [x] `supabase db push` — all 30 migrations applied on the linked project
      (2026-09-07; `ai_consent` was the only one outstanding).
- [x] `supabase functions deploy` — parse-meal, submit-correction,
      delete-account, generate-insights (no JWT) all deployed 2026-09-07.
- [ ] **Set the four `APPLE_*` secrets** — `supabase secrets list` shows
      only `ANTHROPIC_API_KEY` and `INSIGHTS_CRON_SECRET`, so SIWA token
      revocation silently no-ops during account deletion until they exist
      (docs/deployment-checklist.md §2).
- [ ] Merge PR #3 → the `pages` workflow publishes
      https://pranavski.github.io/soma/privacy/ (Pages is enabled with the
      Actions source; the repo is public). Open it, then flip
      `SomaFeatures.privacyPolicyIsHosted`.
- [ ] App Store Connect: privacy URL, support URL, nutrition label, age
      rating, review notes, screenshots — paste from
      docs/app-store-connect-copy.md; status in docs/app-store-compliance.md §6.
- [ ] Seed a reviewer-visible insight with docs/reviewer-seed.sql, record a
      short video, attach it to the submission.
- [ ] Device smoke test, docs/deployment-checklist.md §8 — especially
      deletion (step 5) and the consent-decline path (step 7).

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
- AI consent enforced server-side (`ai_consent`), not just on the phone.
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
