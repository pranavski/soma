# Food–Body Record — MVP Spec (v1)

> Status: draft for review. This is the source-of-truth schema/contract doc
> referenced by `CLAUDE.md` and the `supabase-flow` / `insight-rules` skills.

## Scope of v1
- 10-second meal logging (voice / one-tap repeat / manual typing).
- Once-a-day energy + mood check-in (0–5 scale).
- Read-only HealthKit → daily aggregates only.
- Weekly insight engine implementing the four rules in `insight-rules`.
- No goals, no streaks, no calorie targets, never medical.

**Photo logging is deferred to v1.1.** The schema, the `meal-photos`
bucket, and `parse-meal`'s photo path all exist server-side and stay
dormant; the v1 iOS client has no camera UI and never writes
`source = 'photo'` or `photo_path`. Nothing user-facing (App Store copy,
onboarding, screenshots) may claim photo support until v1.1 ships.

## Naming & conventions
- All tables in `public` schema. Primary keys: `uuid default gen_random_uuid()`.
- Timestamps: `timestamptz`, default `now()` for system-set columns.
- Local-date columns (`check_date`, `day`, `week_start`) are `date` — the
  client converts from the user's local timezone before writing.
- Every user-owned row carries `user_id uuid not null references auth.users(id) on delete cascade`.
- RLS enabled on every user-owned table with the 4-policy shape from the
  `supabase-flow` skill (owner select / insert / update / delete on
  `auth.uid() = user_id`).
- `updated_at` is maintained by a single shared trigger `set_updated_at()`.

---

## Tables

### `meals`
One row per meal logged.

| column           | type           | notes |
|------------------|----------------|-------|
| `id`             | uuid pk        | `gen_random_uuid()` |
| `user_id`        | uuid not null  | FK `auth.users(id)` cascade |
| `eaten_at`       | timestamptz not null | When the meal was eaten (UTC instant). |
| `eaten_date`     | date           | Meal's date in the **user's local timezone**, written by the client. Insight rules prefer this over `eaten_at`. |
| `eaten_hour`     | smallint       | Local hour 0–23, written by the client. Drives the late-evening rule (falls back to UTC hour for legacy rows). |
| `logged_at`      | timestamptz not null default `now()` | When entered into the app. |
| `source`         | text not null  | check in (`'photo'`,`'voice'`,`'manual'`,`'repeat'`). `'photo'` is reserved for v1.1 — the v1 client never writes it. |
| `photo_path`     | text           | Object path in `meal-photos` bucket. Always null in v1 (photo logging is v1.1). |
| `voice_transcript` | text         | Raw transcript if source = voice. |
| `notes`          | text           | Free-form user notes. |
| `dish_name`      | text           | Normalized dish name for the repeat-dish rule. Lowercased, trimmed. |
| `calories_low`   | int            | Range low. **UI always shows a range, never a bare number.** |
| `calories_high`  | int            | Range high. `check (calories_high >= calories_low)`. |
| `caffeine_mg_low` / `caffeine_mg_high` | int | Milligrams of caffeine, whole meal. Anchored at parse time against a USDA/NIAAA standard-serving table (`parse-meal/fdc.ts`) rather than estimated freehand — the insight engine's `caffeine_mg_late` feature sums these from 14:00 onward. |
| `alcohol_g_low` / `alcohol_g_high` | int | Grams of pure ethanol, whole meal. One US standard drink = 14 g. Feeds `alcohol_g_evening` (17:00 onward). |
| `parse_status`   | text not null default `'pending'` | check in (`'pending'`,`'parsed'`,`'failed'`,`'manual'`) |
| `parsed_at`      | timestamptz    | Set when `parse-meal` completes. |
| `created_at`     | timestamptz default `now()` | |
| `updated_at`     | timestamptz default `now()` | trigger-maintained |

Indexes:
- `(user_id, eaten_at desc)` — timeline screen, and the late-evening rule's window scan.
- `(user_id, dish_name)` where `dish_name is not null` — repeat-dish rule.

### `meal_items`
Individual items within a meal (from `parse-meal`).

| column      | type          | notes |
|-------------|---------------|-------|
| `id`        | uuid pk       | |
| `meal_id`   | uuid not null | FK `meals(id)` cascade |
| `user_id`   | uuid not null | Denormalized for cheap RLS. |
| `name`      | text not null | e.g. `"brown rice"` |
| `quantity`  | text          | Free-form, e.g. `"1 cup"`. Claude parses; we don't normalize in v1. |
| `position`  | int not null default 0 | Display ordering within the meal. |
| `created_at`| timestamptz default `now()` | |

Index: `(meal_id, position)`.

### `daily_checkins`
The once-a-day energy + mood check-in.

| column        | type          | notes |
|---------------|---------------|-------|
| `id`          | uuid pk       | |
| `user_id`     | uuid not null | |
| `check_date`  | date not null | User's local date. **unique `(user_id, check_date)`** |
| `energy`      | smallint not null | `check between 0 and 5` |
| `mood`        | text          | Optional free-form tag/word. |
| `created_at`  | timestamptz default `now()` | |
| `updated_at`  | timestamptz default `now()` | trigger-maintained |

### `health_days`
Daily HealthKit aggregates. **Raw HealthKit reads stay on device.**

Synced by `HealthKitSync` over a trailing 30-day window — matching the
insight engine's `WINDOW_DAYS`, so a fresh connection doesn't leave the
oldest scored days empty. Three triggers: the Settings sheet's
connect/sync-now, an `HKObserverQuery` background wakeup (throttled to 3h),
and app foreground (throttled to 6h). Days with no signal at all are
skipped rather than written as an all-nil row, which would blank an earlier
good sync and drop that day's tier.

| column               | type           | notes |
|----------------------|----------------|-------|
| `id`                 | uuid pk        | |
| `user_id`            | uuid not null  | |
| `day`                | date not null  | User's local date. **unique `(user_id, day)`** |
| `steps`              | int            | Nullable. |
| `sleep_minutes`      | int            | Sleep that **started** this night (so `day d` pairs with the night d→d+1). Nullable. |
| `resting_hr_bpm`     | numeric(5,1)   | Nullable. |
| `hrv_ms`             | numeric(6,1)   | Nullable. |
| `weight_kg`          | numeric(5,2)   | Nullable. Added for the insight-engine pivot — feeds the body-trend chart and the digest. |
| `active_energy_kcal` | int            | Nullable. Added for the insight-engine pivot. |
| `workout_minutes`    | int            | Nullable. Added for the insight-engine pivot. |
| `tier`               | smallint not null default 0 | Computed client-side (0/1/2) from steps/sleep/RHR/HRV presence. **Informational only** — `generate-insights` does not gate on it; see that section for the current (coverage-based) gate. |
| `synced_at`          | timestamptz    | Last sync from device. |
| `created_at`         | timestamptz default `now()` | |
| `updated_at`         | timestamptz default `now()` | trigger-maintained |

### `insights`
Zero or more statistically-screened correlations per run — **not** one
templated finding per ISO week. `generate-insights` runs nightly (plus
on-demand) over a rolling window: TypeScript scores every food–body
association and keeps what survives an FDR correction, then Claude selects
from those survivors and writes them, up to 5 per run. See `insight-rules`
for how a pattern qualifies.

| column             | type          | notes |
|--------------------|---------------|-------|
| `id`               | uuid pk       | |
| `user_id`          | uuid not null | |
| `claim`            | text not null | One hedged sentence naming the pattern, carrying real numbers from the digest. |
| `evidence`         | text not null | The supporting comparison spelled out — which days, how many, the compared values. |
| `confidence`       | text not null | check in (`'low'`,`'medium'`,`'high'`). Derived from `support_days` **and** `support_windows`, never self-reported by the model: `high` needs n≥8, `medium` n≥6, `low` down to the n≥4 floor, then **one** tier of promotion if the pattern also held in an earlier, non-overlapping window. |
| `suggested_action` | text          | Nullable. A single gentle, observational next step. Never prescriptive, never a target, never medical. |
| `window_days`      | int not null  | The lookback window used to find the claim; currently 30. |
| `pattern_key`      | text not null | The association's identity, independent of wording: `'<feature>_x_<signal>_lag<0\|1>'`. **unique `(user_id, pattern_key)`** — the "never repeat itself" guarantee, and the Edge Function's upsert conflict target. A rephrased repeat collides here where `claim_norm` would have missed it. |
| `support_days`     | int not null  | Paired days behind the association (check `>= 4`). Half of what `confidence` is derived from, kept so a claim can be audited against its own evidence base. |
| `support_windows`  | int not null default 1 | Separate windows the association had held across when the claim was written (check `>= 1`), counted from `pattern_history`. The other half of `confidence`, recorded for the same audit reason. |
| `claim_norm`       | text not null | Lowercased, alphanumerics-only, whitespace-collapsed form of `claim`. Retained for debugging; no longer carries a uniqueness constraint (`pattern_key` subsumes it). |
| `mechanism`        | text          | Nullable. One declarative sentence of general physiology, shown to the reader under "why this might happen". **Copied verbatim from `generate-insights/evidence.ts`, never written by the model** — Claude picks the candidate, TypeScript joins the science. Same division as numbers. |
| `evidence_source_id` | text        | Nullable. Stable id of the evidence row (e.g. `'caffeine_late_x_sleep'`). The join key a future meal-plan feature composes against — see `docs/meal-plans-design.md`. Indexed. |
| `evidence_grade`   | text          | Nullable, check in (`'A'`,`'B'`,`'C'`). Strength of the *literature*, not of this person's pattern (that is `confidence`). |
| `evidence_citation`| text          | Nullable. Rendered citation, denormalised at write time so a surfaced claim keeps the reference it was shown with. |
| `model`            | text          | e.g. `'claude-haiku-4-5'`. |
| `created_at`       | timestamptz default `now()` | |

Index: `(user_id, created_at desc)` — for the "recent claims" prompt context and the Insights feed.
Index: `(evidence_source_id) where evidence_source_id is not null` — "which findings lean on which science".

The four evidence columns are all-or-nothing (`insights_evidence_all_or_nothing`):
a mechanism without a citation is an unsourced health claim, and the constraint
makes that unrepresentable. They are null for most rows, which is the honest
shape — most of what someone notices about themselves has never been studied,
and those findings still surface, just without a clipping attached.

### `pattern_history`
The insight engine's memory: **every association a run measured, survivor or
not**. Without it each nightly run is amnesiac — it re-derives the same ~28
hypotheses from a window overlapping yesterday's by 29 days and has no idea
it has seen them before. Written by `generate-insights` on every run that
gets past the coverage gate, including runs that surface nothing.

Rejected associations are recorded deliberately: they are the denominator.
With only survivors on file, "how often does a finding replicate" has no
answer. A pairing skipped for having too few paired days is simply absent —
it was not tested, so it neither passed nor failed.

| column         | type          | notes |
|----------------|---------------|-------|
| `user_id`      | uuid not null | |
| `run_date`     | date not null | The run's date, not a timestamp. On-demand refresh can fire many times a day over near-identical data; those are one observation, and the primary key collapses them. |
| `pattern_key`  | text not null | Identical to `insights.pattern_key`, so a surfaced claim joins to its own measurement history. |
| `feature`      | text not null | |
| `signal`       | text not null | |
| `lag_days`     | smallint not null | check in (0, 1). |
| `n`            | int not null  | Paired days behind this measurement. |
| `rho`          | real not null | Spearman ρ, check in [-1, 1]. |
| `p_value`      | real not null | Permutation p-value, check in (0, 1]. |
| `survived_fdr` | boolean not null | Whether it cleared Benjamini–Hochberg **this run**. |
| `created_at`   | timestamptz default `now()` | |

Primary key `(user_id, run_date, pattern_key)`. Partial index
`(user_id, pattern_key, run_date desc) where survived_fdr` — the replication
lookup.

**RLS:** owner can read (it is the audit trail behind claims about their own
body); **no** insert/update/delete policy for any client role. A client able
to write here could manufacture the evidence behind its own insights.
`generate-insights` is the only writer, via the service role.

Growth is ~28 rows per active user per day; `generate-insights` prunes rows
older than 180 days inline on every run, so no separate cron is needed.

### `reflections`
What the app can honestly say **before the statistics can say anything** —
plain descriptions of the log ("your last meal has landed between 19:00 and
21:00 across these 5 days"), never an inference from it.

They exist because the engine cannot produce a finding from fewer than about
ten days of paired data, and that is a property of the mathematics rather
than a tunable: the smallest two-tailed p-value a permutation test can
report from n days is 2/n!, which sits above the Benjamini–Hochberg
threshold until n≈7. Measured over synthetic windows, detection of a
*planted, deterministic* effect is 0% at 3–7 logged days while the
false-positive rate is already 1–3%. Loosening the coverage gate would not
make findings arrive sooner — it would make the first thing a new user reads
a false positive. A description needs no correction to be true, so it can
carry the first week instead. See the `insight-rules` skill.

| column         | type              | notes |
|----------------|-------------------|-------|
| `user_id`      | uuid not null     | |
| `kind`         | text not null     | Which observation (`meal_timing`, `repeat_dish`, …). Stable across runs — that is what makes it the identity. Not an enum; the client renders whatever arrives, so new kinds ship server-side without an app update. |
| `body`         | text not null     | The observation, one sentence. |
| `detail`       | text not null     | The counts underneath it, set quieter in the UI. |
| `sort_order`   | smallint not null | Server-side order, so the client does not re-derive the priority/group rules. |
| `window_days`  | smallint not null | |
| `generated_at` | timestamptz default `now()` | |

Primary key `(user_id, kind)` — a **snapshot, not a feed**. An insight is a
finding about a window and stays true, so `insights` never repeats and never
deletes; a reflection describes the log as it currently stands and is wrong
the moment another meal is added, so each run replaces the whole set (upsert
on the key, then delete the kinds that dropped out). At most
`MAX_REFLECTIONS` rows per user, so no retention job is needed.

No model, no confidence, no evidence columns: the copy is templated in
`reflections.ts` from numbers computed there, because a description has no
selection judgment to delegate.

**RLS:** owner can read; **no** insert/update/delete policy for any client
role. `generate-insights` is the only writer, via the service role.

---

## Row Level Security
Enabled on **every** table above. The four policies per table follow the
`supabase-flow` skill's default shape:

```sql
create policy "owner can read"   on <t> for select using (auth.uid() = user_id);
create policy "owner can insert" on <t> for insert with check (auth.uid() = user_id);
create policy "owner can update" on <t> for update using (auth.uid() = user_id);
create policy "owner can delete" on <t> for delete using (auth.uid() = user_id);
```

`insights` and `pattern_history` are written by the `generate-insights` Edge
Function using the **service role** (which bypasses RLS); rows still carry the
correct `user_id` so client reads work under the owner-can-read policy.
`pattern_history` carries **only** that read policy — no client role may write
to the evidence behind its own insights.

---

## Storage

### Bucket: `meal-photos` (private) — dormant until v1.1
The bucket and its owner-scoped policies exist (see the
`create_meal_photos_bucket` migration) but the v1 client never uploads.
Rules for when photo logging ships in v1.1:
- Path layout: `<user_id>/<meal_id>.<ext>` (jpg/heic).
- Upload: iOS client requests a signed upload URL from `parse-meal` (or a
  thin `mint-upload-url` helper if we split it later).
- Read: signed download URLs with **TTL ≤ 10 min**. Never stored in DB rows.
- No public access. No public policy.

---

## Edge Functions

### `parse-meal`
**Input** (JSON):
```json
{ "meal_id": "uuid", "photo_path": "user_id/meal_id.jpg", "voice_transcript": null }
```
Exactly one of `photo_path` / `voice_transcript` must be present. In v1
the client only ever sends `voice_transcript` (typed text uses the same
field); the `photo_path` branch is live server-side but unused until v1.1.

**Behavior:** fetches the photo via signed URL (or uses the transcript),
calls Claude (`claude-sonnet-4-6`) with the structured-output contract
below, then **updates the `meals` row** and inserts `meal_items` rows
using the service role.

**Claude output contract** (strict JSON, validated server-side):
```json
{
  "dish_name": "lentil dal with rice",
  "calories_low": 520,
  "calories_high": 680,
  "items": [
    { "name": "lentil dal", "quantity": "1 cup" },
    { "name": "basmati rice", "quantity": "3/4 cup" }
  ]
}
```

**On malformed output:** function returns **422** with
`{ "fallback": { "dish_name": null, "calories_low": null, "calories_high": null, "items": [] } }`
and sets `meals.parse_status = 'failed'`. The iOS decoder must handle this
(unit-tested in `Core/Models`).

**Secrets:** `ANTHROPIC_API_KEY` lives in Edge Function secrets only.

### `generate-insights`
**Trigger:** two auth paths.
1. Nightly via `pg_cron` (03:30 UTC). A SQL function
   `private.invoke_generate_insights_nightly()` fans out one async
   `pg_net` POST per user who has logged a meal in the last 30 days. The
   base URL and shared cron secret live in `vault.decrypted_secrets`
   (`edge_function_base_url`, `insights_cron_secret`); the Edge Function
   authorizes the request by comparing the bearer token against the
   `INSIGHTS_CRON_SECRET` env var. The run is idempotent per user
   (`pattern_key` dedupe), so a nightly re-run only inserts genuinely new
   claims.
2. On-demand: caller's own JWT as the bearer token, empty body `{}`. This
   is what the iOS Insights screen's pull-to-refresh hits.

**Behavior:**
1. Load the caller's last 30 days of `meals`, `daily_checkins`, and
   `health_days`.
2. Compress into one line per day that has any signal, ascending by date,
   plus a per-metric coverage count. Missing metrics are **omitted** from
   the line, never rendered as zero.
3. Rebuild `reflections` — plain descriptions of the log, which need 3
   logged days rather than the ~10 the statistics need. Computed before the
   gate and on **every** run (not only gated ones), templated in
   TypeScript with no model call, and replacing the previous set wholesale.
   See `insight-rules` for why they may never relate a food feature to a
   body signal.
4. Gate: skip the Claude call entirely unless the window has **≥ 7 days
   with a meal logged AND ≥ 7 days of the single best-covered body
   signal** (energy check-in counts as the tier-0 body signal; coverage
   is the max across metrics, not the sum — see `insight-rules`). Note
   this gate is *not* what makes findings take two weeks: below ~8 paired
   days the permutation test plus the FDR correction cannot produce a real
   finding at any threshold, which is why the answer to "surface something
   sooner" is step 3 and not a smaller number here.
5. Score candidate associations in TypeScript (`candidates.ts`): an
   allowlist of 14 food-feature × body-signal pairings (not the 48-way
   cross-product — every extra hypothesis tightens the threshold for the
   rest), each tested at 2 lags and needing ≥ 4 paired days, scored with
   Spearman ρ and a 10,000-shuffle seeded permutation p-value, then
   filtered by Benjamini–Hochberg at q = 0.10. Survivors are then thinned
   twice, both *after* the correction: one lag per pairing, and one finding
   per group of features that restate each other for this person (features
   correlating at |ρ| ≥ 0.7 against the same signal and lag). Ranked by |ρ|
   and capped at 20. See `insight-rules` for why the correction is
   load-bearing, why the allowlist exists, and why q stays at 0.10.
6. Fold in replication from `pattern_history`: for each candidate, count the
   earlier runs where it survived, keeping only runs ≥ 15 days apart
   (consecutive nightly windows share 29 of 30 days, so nightly survival is
   near-tautological). Holding across ≥ 2 such windows promotes `confidence`
   by exactly one tier, and the candidate line tells the model how many
   windows it has held across. **Replication never changes which hypotheses
   are tested, their p-values, or what clears the correction** — it adds
   evidence, it does not lower the bar.
7. Write every association tested this run — survivor or not — to
   `pattern_history`, then prune rows older than 180 days. This happens
   before the shortlist is thinned and before Claude is called, so a night
   that surfaces nothing still records what it measured.
8. Drop any candidate whose `pattern_key` the user has already been shown.
   If none remain, return without calling Claude.
9. Fetch the user's last 15 claims, most recent first, to keep phrasing
   fresh in the prompt.
10. Call Claude once (`claude-haiku-4-5`) with the candidate table + digest
   + coverage counts + prior claims, constrained by a JSON response
   schema. It selects at most 5 candidates and returns
   `{ candidate_id, claim, evidence, suggested_action }` each, per the copy
   contract in `insight-rules`. Selecting none is a valid, good answer —
   "nothing worth saying" beats an invented pattern. `confidence` is
   **not** returned; it is derived from `support_days` and `support_windows`.
11. Strict server-side validation. Any structural violation, an unknown or
    reused `candidate_id`, or more than 5 items rejects the **whole**
    payload — a partially-trustworthy run is worse than no run; the next
    nightly/on-demand call just tries again.
12. Upsert the validated claims with `onConflict: "user_id,pattern_key"`,
    `ignoreDuplicates: true` — re-runs are safe no-ops for anything
    already surfaced.

**Response:**
- `200 { surfaced: boolean, inserted: number, candidates: number, reflections: number }` — ran.
- `200 { surfaced: false, inserted: 0, reason: "insufficient_data", reflections }` — gated before scoring. `reflections` is how many descriptions were written instead, so a gated run is distinguishable from a silent one.
- `200 { surfaced: false, inserted: 0, reason: "no_qualifying_patterns", candidates, reflections }` — nothing survived the correction, everything surviving was already surfaced, or Claude selected none.
- `500 { error: "bad_model_output" | "claude_call_failed" | "insert_failed" }`.

**Secrets:** `ANTHROPIC_API_KEY`, `INSIGHTS_CRON_SECRET` (set via `supabase secrets set`).

### `submit-correction`
**Trigger:** meal-detail "not quite right?" sheet.

**Input** (JSON):
```json
{
  "meal_id": "uuid | null",
  "original_ai_guess": { "dish_name": "...", "cuisine": "..." },
  "corrected_meal": {
    "dish_name": "chana masala",
    "cuisine": "south_asian",
    "calories_low": 420,
    "calories_high": 560,
    "items": [{ "name": "chana masala", "quantity": "1 bowl" }]
  }
}
```

**Behavior:** revalidates every field server-side, writes the correction
to `meal_corrections` (owner-scoped), and — only when the correction
actually *renames* the dish — upserts the (canonical, alias) pair into
the community `dish_aliases` table with the service role. `dish_aliases`
carries name mappings only: no user ids, no macros, no photos. It is the
only cross-user surface in the system.

**Output:** `200 { "id": "uuid" }`.

### `delete-account`
**Trigger:** Settings → "delete account" (required by App Review
guideline 5.1.1(v)).

**Input** (JSON): `{ "authorization_code": "string?" }` — auth comes from
the caller's bearer token; the optional value is a fresh single-use Sign
in with Apple authorization code.

**Behavior:**
1. Best-effort SIWA token revocation: exchange the code for a refresh
   token at `appleid.apple.com` and revoke it (client secret is an ES256
   JWT signed with the `.p8` key from Edge Function secrets
   `APPLE_CLIENT_ID` / `APPLE_TEAM_ID` / `APPLE_KEY_ID` /
   `APPLE_PRIVATE_KEY`; if any is missing or the exchange fails, skip —
   **revocation must never block deletion**).
2. Explicitly delete every owned row (`meal_corrections`, `app_feedback`,
   `meals` → cascades to `meal_items`, `daily_checkins`, `health_days`,
   `insights`).
3. Delete the `auth.users` row via the admin API (service role only —
   the reason this is an Edge Function).

**Output:** `204` empty body.

---

## Open questions to resolve before shipping
- Do we need a `users` profile table at all, or is `auth.users.id` enough
  for v1? (Current draft: no profile table.)
- Soft-delete (`deleted_at`) vs. hard delete on `meals` — current draft is
  hard delete with cascade.
- Photo retention policy — moot for v1 (photo logging deferred to v1.1);
  decide before the v1.1 camera flow ships. Account deletion must also
  purge the user's `meal-photos` objects once uploads exist.
