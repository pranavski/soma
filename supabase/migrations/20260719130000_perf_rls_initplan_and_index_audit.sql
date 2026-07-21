-- Performance audit (2026-07-19).
--
-- 1) RLS initplan fix: every owner policy compared `auth.uid() = user_id`
--    directly, which Postgres evaluates PER ROW. Wrapping the call as
--    `(select auth.uid())` lets the planner run it once as an InitPlan.
--    Flagged by the Supabase performance advisor (auth_rls_initplan) on
--    all 24 owner policies. Semantics are identical.
--
-- 2) Drop two exact-duplicate indexes: the `unique (user_id, day)` /
--    `unique (user_id, week_start)` constraint indexes already serve the
--    same (user_id, X desc) scans — btrees scan backwards — so the extra
--    non-unique desc indexes only add write cost.
--
-- 3) Index the one unindexed foreign key: meal_items.user_id references
--    auth.users on delete cascade; account deletion (delete-account Edge
--    Function and the FK cascade itself) looks meal_items up by user_id,
--    which was a seq scan. Also tightens the RLS user_id filter on
--    embedded meal_items reads.
--
-- 4) Pin search_path on public.set_updated_at (security advisor:
--    function_search_path_mutable). The body touches no tables, so an
--    empty search_path is safe.

-- ---------------------------------------------------------------------
-- 1) RLS: evaluate auth.uid() once per statement, not per row.
-- ---------------------------------------------------------------------

-- meals
alter policy "owner can read"   on public.meals using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.meals with check ((select auth.uid()) = user_id);
alter policy "owner can update" on public.meals using ((select auth.uid()) = user_id);
alter policy "owner can delete" on public.meals using ((select auth.uid()) = user_id);

-- meal_items
alter policy "owner can read"   on public.meal_items using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.meal_items with check ((select auth.uid()) = user_id);
alter policy "owner can update" on public.meal_items using ((select auth.uid()) = user_id);
alter policy "owner can delete" on public.meal_items using ((select auth.uid()) = user_id);

-- daily_checkins
alter policy "owner can read"   on public.daily_checkins using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.daily_checkins with check ((select auth.uid()) = user_id);
alter policy "owner can update" on public.daily_checkins using ((select auth.uid()) = user_id);
alter policy "owner can delete" on public.daily_checkins using ((select auth.uid()) = user_id);

-- health_days
alter policy "owner can read"   on public.health_days using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.health_days with check ((select auth.uid()) = user_id);
alter policy "owner can update" on public.health_days using ((select auth.uid()) = user_id);
alter policy "owner can delete" on public.health_days using ((select auth.uid()) = user_id);

-- insights
alter policy "owner can read"   on public.insights using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.insights with check ((select auth.uid()) = user_id);
alter policy "owner can update" on public.insights using ((select auth.uid()) = user_id);
alter policy "owner can delete" on public.insights using ((select auth.uid()) = user_id);

-- meal_corrections (select + insert only; append-only from client)
alter policy "owner can select" on public.meal_corrections using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.meal_corrections with check ((select auth.uid()) = user_id);

-- app_feedback (select + insert only)
alter policy "owner can select" on public.app_feedback using ((select auth.uid()) = user_id);
alter policy "owner can insert" on public.app_feedback with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- 2) Drop duplicate indexes (the unique constraints already cover them).
-- ---------------------------------------------------------------------

drop index public.health_days_user_day_idx;   -- duplicate of unique (user_id, day)
drop index public.insights_user_week_idx;     -- duplicate of unique (user_id, week_start)

-- ---------------------------------------------------------------------
-- 3) Cover the meal_items.user_id foreign key.
-- ---------------------------------------------------------------------

create index meal_items_user_idx on public.meal_items (user_id);

-- ---------------------------------------------------------------------
-- 4) Pin the trigger function's search_path.
-- ---------------------------------------------------------------------

alter function public.set_updated_at() set search_path = '';
