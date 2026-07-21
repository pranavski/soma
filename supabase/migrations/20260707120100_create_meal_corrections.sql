-- meal_corrections: the per-user retrieval-augmentation store.
--
-- When the user taps "not quite right?" on a meal card and corrects the
-- AI's guess, we archive both the original AI guess and the confirmed
-- version here. parse-meal reads the last ~20 of these rows for the
-- caller before each Claude call and injects them as grounding — so the
-- model learns this user's specific pantry over time WITHOUT any
-- fine-tuning and WITHOUT any cross-user leakage (RLS enforces owner-only).
--
-- Shape choices:
--   * original_ai_guess and corrected_meal are jsonb (not columns) because
--     the parse contract may grow (macros, items, cuisines) — we want to
--     archive whatever shape existed at correction time, without a
--     migration each time.
--   * meal_id is the row this correction is against, nullable so a user
--     could in principle log a canonical dish without a specific meal.
--   * cuisine is a top-level column so we can index / filter for the
--     dish_aliases updater (see submit-correction Edge Function).

create table public.meal_corrections (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  meal_id           uuid references public.meals(id) on delete set null,
  original_ai_guess jsonb,
  corrected_meal    jsonb not null,
  photo_url         text,
  cuisine           text
    check (cuisine is null or cuisine in (
      'south_asian','east_asian','southeast_asian','middle_eastern',
      'mediterranean','african','latin_american','caribbean',
      'western','other'
    )),
  created_at        timestamptz not null default now()
);

create index meal_corrections_user_created_idx
  on public.meal_corrections (user_id, created_at desc);

create index meal_corrections_meal_idx
  on public.meal_corrections (meal_id)
  where meal_id is not null;

alter table public.meal_corrections enable row level security;

-- Owner-only. Service role bypasses RLS for the parse-meal retrieval step
-- (it reads across users? no — parse-meal filters by the caller's user_id
-- explicitly; service role only avoids re-checking the JWT).
create policy "owner can select" on public.meal_corrections
  for select using (auth.uid() = user_id);

create policy "owner can insert" on public.meal_corrections
  for insert with check (auth.uid() = user_id);

-- No update / delete policies for v1: corrections are append-only from
-- the client. A future "revoke correction" flow would add a delete policy.
