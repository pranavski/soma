-- pattern_history: what the insight engine measured, not just what it said.
--
-- Every run scores ~28 associations and throws all but the survivors away.
-- The survivors are remembered (via insights.pattern_key, so a finding is
-- never repeated) but everything else — including how strong a rejected
-- association was, and whether a surviving one keeps surviving — is lost
-- the moment the function returns. Each nightly run is therefore amnesiac:
-- it re-derives the same hypotheses from a window that overlaps yesterday's
-- by 29 days and has no idea it has seen them before.
--
-- This table is the engine's memory. It costs nothing statistically — these
-- are numbers already computed — and it is what lets a pattern accumulate
-- evidence across windows instead of getting one shot per night.
--
-- What it currently buys (see candidates.ts `confidenceFor`):
--   * Replication. A pattern that clears the FDR correction in two windows
--     15+ days apart is better evidence than one that cleared it once, and
--     the confidence tier now says so.
--   * Editorial signal. The candidate line tells the model how many windows
--     a pattern has held across — exactly the judgment call it is there to
--     make, and one a single p-value cannot inform.
--
-- What it makes possible later, without another migration:
--   * Reversal detection ("this stopped holding three weeks ago") — a
--     better insight than the stale original.
--   * Empirical calibration of FDR_Q and WINDOW_DAYS. How often does a
--     q=0.10 finding replicate in the next non-overlapping window? That is
--     a measured false-discovery rate over real users, replacing the 20
--     synthetic windows the tunables were set from.
--
-- Every association tested in a run is recorded, survivor or not. The
-- rejected ones are the control group — without them "how often does a
-- finding replicate" has no denominator. A pairing that was skipped for
-- having too few paired days is simply absent, which is itself the honest
-- record: it was not tested, so it neither passed nor failed.

create table public.pattern_history (
  user_id      uuid not null references auth.users(id) on delete cascade,
  -- The run's date, not a timestamp: on-demand pull-to-refresh can fire the
  -- same function many times a day over near-identical data, and those are
  -- one observation, not many. The primary key collapses them.
  run_date     date not null,
  -- '<feature>_x_<signal>_lag<0|1>', identical to insights.pattern_key, so
  -- a surfaced claim joins to its own measurement history.
  pattern_key  text not null,
  feature      text not null,
  signal       text not null,
  lag_days     smallint not null check (lag_days in (0, 1)),
  n            int  not null check (n >= 0),
  rho          real not null check (rho >= -1 and rho <= 1),
  p_value      real not null check (p_value > 0 and p_value <= 1),
  survived_fdr boolean not null,
  created_at   timestamptz not null default now(),

  primary key (user_id, run_date, pattern_key)
);

-- The replication lookup: every surviving run of one pattern for one user,
-- newest first. Partial, because only survivors are ever queried this way
-- and they are a small minority of the rows.
create index pattern_history_replication_idx
  on public.pattern_history (user_id, pattern_key, run_date desc)
  where survived_fdr;

alter table public.pattern_history enable row level security;

-- Read: owner only. This is derived data about the reader's own body, and
-- it is the audit trail behind every claim they were shown.
create policy "owner can read" on public.pattern_history
  for select using ((select auth.uid()) = user_id);

-- No insert/update/delete policies for any client role. generate-insights
-- is the only writer, via the service role (which bypasses RLS), and it
-- always carries the correct user_id. A client that could write here could
-- manufacture the evidence behind its own insights.

-- Growth is ~28 rows per active user per day. generate-insights prunes rows
-- older than PATTERN_HISTORY_RETENTION_DAYS on every run, so the table stays
-- bounded without a separate cron job.

-- ─── insights.support_windows ───────────────────────────────────────────────
--
-- support_days already records the evidence base a confidence tier was
-- derived from, so a surfaced claim can be audited against it. Confidence is
-- now derived from paired days AND replication, so the second input has to
-- be recorded for the same reason.
--
-- Defaults to 1: every claim is supported by at least the window it was
-- found in. Existing rows predate replication tracking and are exactly that
-- case, so the default backfills them correctly rather than by guess.

alter table public.insights
  add column support_windows int not null default 1
    check (support_windows >= 1);
