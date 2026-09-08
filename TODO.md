# Soma — TODO

Live list. Everything the audit of 2026-09-07 called partially built or
broken has been fixed in code; what remains is hosting, App Store Connect
and deploy steps that need a human with credentials.

## Before the next TestFlight build

Done 2026-09-08: PR #3 merged to main; all 30 migrations applied; all four
Edge Functions deployed; GitHub Pages live; `privacyPolicyIsHosted` flipped.

- [ ] **Create the Sign in with Apple key and set the last two secrets.**
      `APPLE_CLIENT_ID` and `APPLE_TEAM_ID` (8VZH2497GC) are set;
      `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` are not, because the `.p8`
      only exists once a human makes it at developer.apple.com →
      Certificates → Keys → new key with "Sign in with Apple" enabled for
      the Soma App ID. Until then deletion works but Apple is never told —
      `delete-account` now logs exactly that, so check the function logs
      after the first test deletion.
- [ ] App Store Connect: privacy URL (https://pranavski.github.io/soma/privacy/),
      support URL (https://pranavski.github.io/soma/), nutrition label, age
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
