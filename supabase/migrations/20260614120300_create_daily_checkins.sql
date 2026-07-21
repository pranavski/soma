-- daily_checkins: once-a-day energy + mood check-in. The user's local date
-- is computed client-side before write so there is exactly one row per day.

create table public.daily_checkins (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  check_date date not null,
  energy     smallint not null check (energy between 0 and 5),
  mood       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, check_date)
);

create trigger daily_checkins_set_updated_at
before update on public.daily_checkins
for each row execute function public.set_updated_at();

alter table public.daily_checkins enable row level security;

create policy "owner can read"   on public.daily_checkins for select using (auth.uid() = user_id);
create policy "owner can insert" on public.daily_checkins for insert with check (auth.uid() = user_id);
create policy "owner can update" on public.daily_checkins for update using (auth.uid() = user_id);
create policy "owner can delete" on public.daily_checkins for delete using (auth.uid() = user_id);
