-- caffeine + alcohol: the two nutrients with the best-quantified effects on
-- signals Soma already syncs.
--
-- Everything else the parser extracts is a whole-day nutrition figure.
-- These two are different in kind: what the literature quantifies is not
-- how much was consumed but how much was still on board at bedtime, so the
-- insight engine reads them through time windows (caffeine from 14:00,
-- alcohol from 17:00 — see caffeine_mg_late / alcohol_g_evening in
-- candidates.ts). The columns themselves stay per-meal and un-windowed;
-- the windowing is a query-time decision and should not be baked into
-- storage where it could not be revisited.
--
-- Ranges, like every other nutrient here. "A coffee" is not a precise dose
-- — brewed coffee runs roughly 70-140 mg depending on bean and volume —
-- and a bare number would imply a certainty the parse does not have. The
-- range shape is also what keeps the UI honest, since the app's hard rule
-- is that estimates are always shown as ranges.
--
-- Units: caffeine in milligrams (an espresso is ~63 mg, so grams would
-- round everything to zero); alcohol in grams of ethanol, which is how the
-- literature and the NIAAA standard drink (14 g) are both expressed.

alter table public.meals
  add column caffeine_mg_low  int,
  add column caffeine_mg_high int,
  add column alcohol_g_low    int,
  add column alcohol_g_high   int;

alter table public.meals
  add constraint meals_caffeine_range_ok
    check (caffeine_mg_high is null or caffeine_mg_low is null or caffeine_mg_high >= caffeine_mg_low),
  add constraint meals_alcohol_range_ok
    check (alcohol_g_high   is null or alcohol_g_low   is null or alcohol_g_high   >= alcohol_g_low),
  -- Nutrient quantities are never negative. The macro columns predate this
  -- habit and go without; there is no reason to repeat that here.
  add constraint meals_caffeine_nonneg
    check (caffeine_mg_low is null or caffeine_mg_low >= 0),
  add constraint meals_alcohol_nonneg
    check (alcohol_g_low is null or alcohol_g_low >= 0);

alter table public.meal_items
  add column caffeine_mg_low  int,
  add column caffeine_mg_high int,
  add column alcohol_g_low    int,
  add column alcohol_g_high   int;

alter table public.meal_items
  add constraint meal_items_caffeine_range_ok
    check (caffeine_mg_high is null or caffeine_mg_low is null or caffeine_mg_high >= caffeine_mg_low),
  add constraint meal_items_alcohol_range_ok
    check (alcohol_g_high   is null or alcohol_g_low   is null or alcohol_g_high   >= alcohol_g_low),
  add constraint meal_items_caffeine_nonneg
    check (caffeine_mg_low is null or caffeine_mg_low >= 0),
  add constraint meal_items_alcohol_nonneg
    check (alcohol_g_low is null or alcohol_g_low >= 0);

-- RLS is unchanged: both tables already have the four owner-scoped policies
-- from their create migrations, and policies are per-row, not per-column, so
-- new columns inherit them. No new grants, no new policies.
--
-- Existing rows keep null, which the engine reads as "not parsed" rather
-- than "none" — see the anyParsed guard in buildDayFeatures. Backfilling
-- zeros would silently assert that every meal ever logged was caffeine-free
-- and alcohol-free, which is exactly the kind of invented fact the insight
-- engine exists not to produce.
