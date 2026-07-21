-- insights: at most one surfaced finding per user per ISO week.
-- Written by the generate-insights Edge Function via the service role
-- (bypasses RLS) but the row still carries the correct user_id so the
-- owner-can-read policy lets the client load its own history.

create table public.insights (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  week_start    date not null,
  rule_id       text not null check (rule_id in (
                  'late_eat_energy',
                  'repeat_dish_energy',
                  'steps_sleep',
                  'late_eat_overnight'
                )),
  tier          smallint not null check (tier between 0 and 2),
  lookback_days int  not null,
  stat          jsonb not null,
  copy          text not null,
  model         text,
  created_at    timestamptz not null default now(),
  unique (user_id, week_start)
);

create index insights_user_week_idx on public.insights (user_id, week_start desc);

alter table public.insights enable row level security;

create policy "owner can read"   on public.insights for select using (auth.uid() = user_id);
create policy "owner can insert" on public.insights for insert with check (auth.uid() = user_id);
create policy "owner can update" on public.insights for update using (auth.uid() = user_id);
create policy "owner can delete" on public.insights for delete using (auth.uid() = user_id);
