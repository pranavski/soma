# Soma — Deployment Checklist (v1.0 submission)

Everything below is what stands between the current repo and a live
TestFlight/App Store build. Run top to bottom.

## 1. Database

```sh
supabase db push
```

Pushes the one unapplied migration, `20260708120000_add_meal_local_time.sql`
(adds `meals.eaten_date` / `meals.eaten_hour` + backfill + index). Verify:

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

## 4. Vault secrets for the weekly cron

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

Then confirm the job exists: `select * from cron.job;` — expect the weekly
Monday 06:00 UTC `generate-insights` fan-out.

## 5. Supabase Auth — Apple provider

Dashboard → Authentication → Providers → Apple:
- Client ID: `com.pranavsurampudi.soma` (the app bundle id — native flow).
- No secret needed for the native `signInWithIdToken` flow.

## 6. App Store Connect

- **Privacy policy URL** — host `docs/privacy-policy.md` (any static page)
  and set the URL in ASC. Required before submission.
- **App privacy nutrition labels** — declare exactly what
  `PrivacyInfo.xcprivacy` declares: Health & Fitness, Other User Content,
  User ID, Other Diagnostic Data — all "linked to you", none "tracking".
- **App icon** — still outstanding (deliberately skipped); the appiconset
  is empty and Xcode will refuse to archive for distribution without a
  1024pt marketing icon.
- Screenshots: iPhone only (the target is iPhone-only, portrait-only).
  Do not show or mention photo logging — it's deferred to v1.1.

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
6. Invoke `generate-insights` manually with the cron secret and confirm a
   422/insight/empty-state behaves per spec:
   ```sh
   curl -X POST https://<ref>.supabase.co/functions/v1/generate-insights \
     -H "Authorization: Bearer $INSIGHTS_CRON_SECRET" \
     -H "Content-Type: application/json" -d '{"user_id":"<uuid>"}'
   ```
