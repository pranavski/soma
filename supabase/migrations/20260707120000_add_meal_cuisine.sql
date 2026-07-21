-- Cuisine tag on meals. parse-meal already emits one of the ten cuisine
-- enum values (see supabase/functions/parse-meal/index.ts); this column
-- gives it a place to land. Nullable — pre-cuisine rows stay valid and
-- the manual-entry path may leave it blank.
--
-- We deliberately keep this as a plain text column with a CHECK constraint
-- rather than a Postgres enum type: the enum set may grow as more
-- cuisines get seed lists in the prompt, and text + check is one migration
-- to change instead of an ALTER TYPE dance.

alter table public.meals
  add column cuisine text
  check (cuisine is null or cuisine in (
    'south_asian',
    'east_asian',
    'southeast_asian',
    'middle_eastern',
    'mediterranean',
    'african',
    'latin_american',
    'caribbean',
    'western',
    'other'
  ));

create index meals_user_cuisine_idx
  on public.meals (user_id, cuisine)
  where cuisine is not null;
