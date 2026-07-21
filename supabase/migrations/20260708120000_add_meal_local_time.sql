-- Local wall-clock capture for meals.
--
-- eaten_at is timestamptz: Postgres normalizes it to UTC, so the insight
-- engine cannot recover the user's local hour from it ("ate after 21:00"
-- was silently evaluated in UTC). The client now writes the local calendar
-- date and hour it observed at log time; generate-insights prefers these
-- and falls back to the UTC prefix for legacy rows.

alter table public.meals
  add column eaten_date date,
  add column eaten_hour smallint
    check (eaten_hour is null or (eaten_hour >= 0 and eaten_hour <= 23));

-- Best-effort backfill for existing rows (UTC — matches what the engine
-- was already assuming for them).
update public.meals
set eaten_date = (eaten_at at time zone 'utc')::date,
    eaten_hour = extract(hour from eaten_at at time zone 'utc')::smallint
where eaten_date is null;

create index meals_user_eaten_date_idx on public.meals (user_id, eaten_date desc);
