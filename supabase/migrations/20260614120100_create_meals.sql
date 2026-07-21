-- meals: one row per meal logged by the user.
-- eaten_at drives the late-evening rule; logged_at is informational.

create table public.meals (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  eaten_at         timestamptz not null,
  logged_at        timestamptz not null default now(),
  source           text not null check (source in ('photo','voice','manual','repeat')),
  photo_path       text,
  voice_transcript text,
  notes            text,
  dish_name        text,
  calories_low     int,
  calories_high    int,
  parse_status     text not null default 'pending'
                   check (parse_status in ('pending','parsed','failed','manual')),
  parsed_at        timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint meals_calorie_range_ok
    check (calories_high is null or calories_low is null or calories_high >= calories_low)
);

create index meals_user_eaten_at_idx on public.meals (user_id, eaten_at desc);
create index meals_user_dish_idx
  on public.meals (user_id, dish_name)
  where dish_name is not null;

create trigger meals_set_updated_at
before update on public.meals
for each row execute function public.set_updated_at();

alter table public.meals enable row level security;

create policy "owner can read"   on public.meals for select using (auth.uid() = user_id);
create policy "owner can insert" on public.meals for insert with check (auth.uid() = user_id);
create policy "owner can update" on public.meals for update using (auth.uid() = user_id);
create policy "owner can delete" on public.meals for delete using (auth.uid() = user_id);
