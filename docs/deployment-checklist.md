# Soma — Deployment Checklist (v1.0 submission)

Everything below is what stands between the current repo and a live
TestFlight/App Store build. Run top to bottom.

## 1. Database

```sh
supabase migration list   # local and remote columns must match
supabase db push
```

Pushes whatever is unapplied. As of 2026-09-07 that is the three newest
migrations: `20260907120000_insights_read_only_for_clients.sql` (drops the
client write policies on `insights`), `20260907120100_create_insight_runs.sql`
(the per-user throttle table `generate-insights` reads) and
`20260907140000_create_ai_consent.sql` (the server-side consent row the
function and the cron fan-out check — without it no user gets nightly
insights, which is the safe direction). Verify:

```sh
supabase db diff        # should be empty
```

## 2. Edge Function secrets

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set INSIGHTS_CRON_SECRET=$(openssl rand -hex 32)

# SIWA token revocation (delete-account). All four required or the
# function silently skips revocation:
supabase secrets set APPLE_CLIENT_ID=com.pranavsurampudi.soma
supabase secrets set APPLE_TEAM_ID=<10-char team id>
supabase secrets set APPLE_KEY_ID=<key id of the .p8 SIWA key>
supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
```

The `.p8` key comes from developer.apple.com → Certificates → Keys →
create a key with "Sign in with Apple" enabled, configured for the Soma
App ID.

## 3. Deploy functions

```sh
supabase functions deploy parse-meal
supabase functions deploy submit-correction
supabase functions deploy delete-account
supabase functions deploy generate-insights --no-verify-jwt
```

`generate-insights` must skip JWT verification (it authenticates with the
cron bearer secret, not a user JWT) — `config.toml` already carries
`[functions.generate-insights] verify_jwt = false`, and the flag makes it
explicit on deploy.

## 4. Vault secrets for the nightly cron

In the SQL editor (values must match step 2/3):

```sql
select vault.create_secret(
  'https://<project-ref>.supabase.co/functions/v1',
  'edge_function_base_url'
);
select vault.create_secret(
  '<same value as INSIGHTS_CRON_SECRET>',
  'insights_cron_secret'
);
```

Then confirm the job exists: `select * from cron.job;` — expect the nightly
03:30 UTC `generate-insights` fan-out (one POST per user with a meal in the
last 30 days; migration `20260720120200`).

## 5. Supabase Auth — Apple provider

Dashboard → Authentication → Providers → Apple:
- Client ID: `com.pranavsurampudi.soma` (the app bundle id — native flow).
- No secret needed for the native `signInWithIdToken` flow.

## 6. App Store Connect

- **Privacy policy URL** — host `docs/privacy-policy.md` (GitHub Pages is
  the plan), set the URL in ASC, then point `SomaFeatures.privacyPolicyURL`
  at it and flip `SomaFeatures.privacyPolicyIsHosted`. Required before
  submission.
- **Support URL / email** — `SomaFeatures.supportEmail`.
- **App privacy nutrition labels** — declare exactly what
  `PrivacyInfo.xcprivacy` declares: Health & Fitness, Other User Content,
  User ID, Email, Other Diagnostic Data — all "linked to you", none
  "tracking". See docs/app-store-compliance.md §2.
- **App icon** — present; `DesignAssets/build-assets.sh` regenerates it
  from the master PNG.
- Screenshots: iPhone only (the target is iPhone-only, portrait-only).
  Do not show or mention photo logging — it is not in this version.
- **Copy and review notes** — drafted in `docs/app-store-connect-copy.md`;
  paste from there.
- **Reviewer can't see an insight** — the engine needs ~10 paired days.
  Run `docs/reviewer-seed.sql` against your own account before the
  screenshots and the review video (see that file's header).

## 7. Xcode / signing sanity

- `MARKETING_VERSION = 1.0`, `TARGETED_DEVICE_FAMILY = 1`, portrait-only —
  already set in the project.
- Capabilities on the App ID: Sign in with Apple + HealthKit.
- Build with a real distribution certificate; HealthKit + SIWA need the
  entitlements present in the profile.

## 8. Post-deploy smoke test

1. Fresh install → Sign in with Apple → log a meal by voice and by typing.
2. Check `meals` row has `eaten_date`/`eaten_hour` populated in local time.
3. Connect HealthKit in Settings → confirm `health_days` rows appear and
   that re-foregrounding the app within 6h does **not** re-sync.
4. Settings → export CSV → share sheet opens with data.
5. Settings → delete account → complete the Apple prompt → confirm all
   rows gone and sign-in state cleared; then cancel-path: delete again on
   a second account, dismiss the Apple prompt, deletion must still finish.
6. Pull to refresh on the Noticed tab twice in a row: the second pull
   should show "thought it over a few minutes ago" (the 429 throttle),
   not a failure.
7. Consent, server-side: on an account that tapped "not now", confirm
   `select * from ai_consent where user_id = '<uuid>'` shows
   `consented = false`, then run step 8's curl for that user — expect
   `{"surfaced":false,"reason":"no_ai_consent",...}` and no row in
   `insight_runs` with a model call behind it. Flip consent on in the
   kitchen → Reading meals and re-run: the reason changes.
8. Invoke `generate-insights` manually with the cron secret and confirm the
   insufficient-data / insight / empty-state responses behave per spec:
   ```sh
   curl -X POST https://<ref>.supabase.co/functions/v1/generate-insights \
     -H "Authorization: Bearer $INSIGHTS_CRON_SECRET" \
     -H "Content-Type: application/json" -d '{"user_id":"<uuid>"}'
   ```
