-- reflections: what the app can honestly say before the statistics can say
-- anything.
--
-- The insight engine cannot produce a finding from fewer than about ten
-- days of paired data, and that is a property of the mathematics rather
-- than a threshold anyone picked. With n paired days the smallest
-- two-tailed p-value a permutation test can report is 2/n!, which sits
-- above the Benjamini-Hochberg threshold until n≈7 no matter how strong
-- the real relationship is. Measured over synthetic windows, detection of a
-- planted deterministic effect is 0% at 3-7 logged days while the
-- false-positive rate is already 1-3%. Loosening the coverage gate would
-- therefore not make findings arrive sooner — it would make the first thing
-- a new user ever read a false positive.
--
-- A reflection is a description of the record, never an inference from it:
-- how many meals a day, when the last plate tends to land, what dish keeps
-- coming back, the spread of a body signal. It relates nothing to anything.
-- "Your last meal has landed between 18:00 and 22:00" requires no
-- correction to be true, which is why it is safe on day three.
--
-- Two ways this table is unlike `insights`, both following from that:
--
--   * It is a SNAPSHOT, not an accumulating feed. An insight is a finding
--     about a window and stays true once found, so `insights` never
--     repeats and never deletes. A reflection describes the log as it
--     currently stands and is wrong as soon as another meal is added, so
--     each run replaces the whole set for the user. Hence the primary key
--     on (user_id, kind) rather than a surrogate id: there is one current
--     answer per kind of observation, and re-running overwrites it.
--
--   * There is no model, no confidence, and no evidence columns. The copy
--     is templated in reflections.ts from numbers computed in the same
--     file, because a description has no selection judgment to delegate
--     and a model given thin data and asked to be interesting produces
--     precisely the causal language this layer must not contain.

create table public.reflections (
  user_id      uuid not null references auth.users(id) on delete cascade,
  -- Which observation this is ('meal_timing', 'repeat_dish', ...). Stable
  -- across runs, which is what makes the replace-in-place upsert work.
  -- Deliberately not an enum: the set is expected to grow, and the client
  -- renders whatever arrives rather than switching on the value.
  kind         text not null check (length(kind) between 1 and 40),
  -- The observation, one sentence.
  body         text not null check (length(body) between 1 and 400),
  -- The counts underneath it, set quieter in the UI.
  detail       text not null check (length(detail) between 1 and 400),
  -- Server-side ordering, so the client does not re-derive the priority
  -- and group rules that chose these three.
  sort_order   smallint not null check (sort_order >= 0),
  window_days  smallint not null check (window_days > 0),
  generated_at timestamptz not null default now(),

  primary key (user_id, kind)
);

-- The client's only query: this user's current set, in order.
create index reflections_user_order_idx
  on public.reflections (user_id, sort_order);

alter table public.reflections enable row level security;

-- Read: owner only. It is a description of their own log.
create policy "owner can read" on public.reflections
  for select using ((select auth.uid()) = user_id);

-- No insert/update/delete policies for any client role, matching
-- pattern_history and insights: generate-insights is the only writer, via
-- the service role, and it always carries the correct user_id.

-- Bounded by construction: at most MAX_REFLECTIONS rows per user, replaced
-- rather than appended, so this needs no retention job.
