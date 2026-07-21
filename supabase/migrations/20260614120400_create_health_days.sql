-- health_days: per-day HealthKit aggregates. Raw HealthKit reads NEVER leave
-- the device; the client computes the daily rollup and writes a single row
-- per local date. sleep_minutes is stored against the night-START day so
-- the steps×sleep rule reads (steps(d), sleep(d)) from one row.

create table public.health_days (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  day             date not null,
  steps           int,
  sleep_minutes   int,
  resting_hr_bpm  numeric(5,1),
  hrv_ms          numeric(6,1),
  tier            smallint not null default 0 check (tier between 0 and 2),
  synced_at       timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, day)
);

create index health_days_user_day_idx on public.health_days (user_id, day desc);

create trigger health_days_set_updated_at
before update on public.health_days
for each row execute function public.set_updated_at();

alter table public.health_days enable row level security;

create policy "owner can read"   on public.health_days for select using (auth.uid() = user_id);
create policy "owner can insert" on public.health_days for insert with check (auth.uid() = user_id);
create policy "owner can update" on public.health_days for update using (auth.uid() = user_id);
create policy "owner can delete" on public.health_days for delete using (auth.uid() = user_id);
