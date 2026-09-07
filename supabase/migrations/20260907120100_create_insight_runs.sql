-- insight_runs: when generate-insights last ran for each user.
--
-- Pull-to-refresh on the home screen invokes generate-insights with the
-- user's JWT. Past the coverage gate that is one Claude call per pull, and
-- nothing stopped a person (or a stuck gesture) from making that call
-- twenty times a minute. The function now refuses a user-initiated run
-- that lands within INSIGHT_RUN_MIN_GAP of the previous one, and this
-- table is the memory it needs to do so. The nightly cron path records a
-- run but is never throttled — the schedule is the throttle there.
--
-- One row per user, overwritten on every run. Service role only: there is
-- no reason for a client to read it (the app surfaces "thinking…" from its
-- own state) and a client that could write it could lift its own limit.

create table public.insight_runs (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  -- 'cron' or 'user'; kept so a later audit can tell the two apart.
  source     text not null check (source in ('cron', 'user'))
);

alter table public.insight_runs enable row level security;
-- No policies for any client role: RLS on with nothing granted denies all.
