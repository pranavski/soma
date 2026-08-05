---
name: supabase-flow
description: Soma's Supabase workflow — schema, migrations, RLS, storage,
  and Edge Functions. Use for any database change, new table, new policy,
  new bucket, or new Edge Function. Also use when wiring the iOS client to
  Supabase Auth (Sign in with Apple).
---

# Soma — Supabase Flow

## Source of truth
The full schema and screen-to-table mapping lives in
`docs/food-body-record-mvp-spec.md`. Always read it before writing a
migration; the spec describes the columns, constraints, and intent.

## Migrations
- Every schema change is a **new file** under `supabase/migrations/`, named
  `YYYYMMDDHHMMSS_<change>.sql`. Never edit an old migration — even an
  unshipped one — once it has been applied to any environment.
- Migrations are SQL only. Use `create table if not exists` only for the
  initial bootstrap; subsequent migrations should assume the prior state.
- Before writing a migration: use the **Supabase MCP** to inspect the
  currently-applied schema. After applying: use the MCP again to verify
  the diff matches intent.

## RLS — non-negotiable
- Every user-owned table gets RLS enabled in the same migration that
  creates it.
- The default policy shape is:
  ```sql
  create policy "owner can read"   on <table> for select using (auth.uid() = user_id);
  create policy "owner can insert" on <table> for insert with check (auth.uid() = user_id);
  create policy "owner can update" on <table> for update using (auth.uid() = user_id);
  create policy "owner can delete" on <table> for delete using (auth.uid() = user_id);
  ```
- Aggregated/derived tables (e.g. `health_days`) still carry `user_id` and
  follow the same pattern.
- Service-role writes (Edge Functions inserting insights) bypass RLS by
  using the service key — but the row still includes the correct `user_id`.

## Storage
- Meal photos live in a **private** bucket (`meal-photos`).
- The iOS client uploads via a signed upload URL minted server-side; reads
  go through signed download URLs with short TTL (≤10 min).
- Never make the bucket public. Never embed a signed URL in a long-lived
  record.

## Edge Functions
- Two functions in v1: `parse-meal` (image/voice → structured meal JSON via
  Claude) and `generate-insights` (nightly job per user, plus on-demand —
  see [[insight-rules]]).
- **Anthropic API keys live ONLY in Edge Function secrets.** Never in the
  iOS bundle, never in a migration, never in source.
- Models: `claude-sonnet-4-6` for `parse-meal`; `claude-haiku-4-5` for
  `generate-insights`, which is cheap enough because the statistics happen
  in TypeScript and the model only selects and writes.
- Functions return strict JSON matching the contracts in the spec. If
  Claude returns malformed JSON, the function returns a 422 with a
  fallback payload — the client must handle this gracefully (see the
  decoder tests in Core/Models).

## iOS client
- Auth: Sign in with Apple via Supabase's native flow. Persist the session
  through `Keychain` (not UserDefaults).
- Never call the Anthropic API directly from the app. All Claude traffic
  goes through Edge Functions.

## Verification checklist (before reporting a DB task done)
1. Migration file exists under `supabase/migrations/` with a timestamped name.
2. Supabase MCP confirms the schema matches the migration's intent.
3. RLS is enabled on every user-owned table touched.
4. No secrets in repo (`git grep -i 'anthropic\|sk-ant'` returns nothing).
