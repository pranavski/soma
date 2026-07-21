-- app_feedback: free-text feedback from Settings → "send feedback".
--
-- Separate from meal_corrections because the intent differs — this is
-- product feedback (bugs, ideas), not training signal. Owner-only for
-- both read and insert; we don't display other users' feedback.

create table public.app_feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  category    text not null default 'other'
              check (category in ('bug', 'idea', 'ai_wrong', 'other')),
  body        text not null check (char_length(body) between 1 and 4000),
  app_version text,
  os_version  text,
  created_at  timestamptz not null default now()
);

create index app_feedback_user_created_idx
  on public.app_feedback (user_id, created_at desc);

alter table public.app_feedback enable row level security;

create policy "owner can select" on public.app_feedback
  for select using (auth.uid() = user_id);

create policy "owner can insert" on public.app_feedback
  for insert with check (auth.uid() = user_id);
