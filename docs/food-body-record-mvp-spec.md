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

| column           | type           | notes |
|------------------|----------------|-------|
| `id`             | uuid pk        | |
| `user_id`        | uuid not null  | |
| `day`            | date not null  | User's local date. **unique `(user_id, day)`** |
| `steps`          | int            | Nullable (tier 1). |
| `sleep_minutes`  | int            | Sleep that **started** this night (so `day d` pairs with the night d→d+1 needed by the steps×sleep rule). Nullable (tier 1). |
| `resting_hr_bpm` | numeric(5,1)   | Nullable (tier 2). |
| `hrv_ms`         | numeric(6,1)   | Nullable (tier 2). |
| `tier`           | smallint not null default 0 | Computed: 0/1/2 based on which fields are present. |
| `synced_at`      | timestamptz    | Last sync from device. |
| `created_at`     | timestamptz default `now()` | |
| `updated_at`     | timestamptz default `now()` | trigger-maintained |

### `insights`
One surfaced finding per user per week (or zero).

| column         | type          | notes |
|----------------|---------------|-------|
| `id`           | uuid pk       | |
| `user_id`      | uuid not null | |
| `week_start`   | date not null | ISO week start (Mon). **unique `(user_id, week_start)`** |
| `rule_id`      | text not null | check in (`'late_eat_energy'`,`'repeat_dish_energy'`,`'steps_sleep'`,`'late_eat_overnight'`) |
| `tier`         | smallint not null | Effective tier at compute time. |
| `lookback_days`| int not null  | Typically 28. |
| `stat`         | jsonb not null | Computed numbers: `{ delta, n_a, n_b, mean_a, mean_b, rho, ... }`. Shape depends on rule. |
| `copy`         | text not null | Claude-generated sentence. **≤ 22 words, hedged.** |
| `model`        | text          | e.g. `'claude-sonnet-4-6'`. |
| `created_at`   | timestamptz default `now()` | |

Index: `(user_id, week_start desc)` — for the "never repeat" check and the Insights screen.

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

`insights` is written by the `generate-insights` Edge Function using the
**service role** (which bypasses RLS); rows still carry the correct `user_id`
so client reads work under the owner-can-read policy.

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
**Trigger:** scheduled weekly via `pg_cron` (Mon 06:00 UTC). A SQL function
`private.invoke_generate_insights_weekly()` fans out one async `pg_net`
POST per user with activity in the lookback window. The base URL and
shared cron secret live in `vault.decrypted_secrets`
(`edge_function_base_url`, `insights_cron_secret`); the Edge Function
authorizes the request by comparing the bearer token against the
`INSIGHTS_CRON_SECRET` env var.

**Behavior:**
1. Determine tier from the past 28 days of `health_days`.
2. For each rule whose minimum tier is met, compute the stat with the
   thresholds in `insight-rules`. Skip if min-n unmet.
3. Rank surfaced findings by effect size (normalized within rule), then
   recency of supporting evidence.
4. Drop any finding whose `rule_id + stat-shape` matches the **most recent
   prior insight** for this user.
5. If a finding remains, call Claude to write the one-sentence copy per
   the copy contract; insert one row into `insights`.
6. If nothing remains, **do not** write a row — the client shows the
   "no-insights-yet" empty state.

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
