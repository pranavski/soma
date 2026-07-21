-- meal_items: structured items within a meal, populated by parse-meal.
-- user_id is denormalized so RLS stays a single-column equality check.

create table public.meal_items (
  id         uuid primary key default gen_random_uuid(),
  meal_id    uuid not null references public.meals(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  quantity   text,
  position   int  not null default 0,
  created_at timestamptz not null default now()
);

create index meal_items_meal_position_idx on public.meal_items (meal_id, position);

alter table public.meal_items enable row level security;

create policy "owner can read"   on public.meal_items for select using (auth.uid() = user_id);
create policy "owner can insert" on public.meal_items for insert with check (auth.uid() = user_id);
create policy "owner can update" on public.meal_items for update using (auth.uid() = user_id);
create policy "owner can delete" on public.meal_items for delete using (auth.uid() = user_id);
