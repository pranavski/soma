-- Finish the initplan fix that 20260719130000 started.
--
-- That migration rewrote all 24 owner policies in `public` from
-- `auth.uid() = user_id` to `(select auth.uid()) = user_id`, so the planner
-- evaluates the function once per statement as an InitPlan instead of once
-- per row. It missed the four meal-photos policies on storage.objects,
-- which were written the same way and have the same problem.
--
-- It matters more here than it looked. storage.objects holds every object
-- in every bucket, and the policy re-evaluates auth.uid() per candidate row
-- while scanning, so the per-row cost is paid against the whole table
-- rather than against one user's meals. Today the bucket is small; the fix
-- is free and does not get easier later.
--
-- Semantics are identical — the subselect returns the same value as the
-- bare call, this is purely about when Postgres chooses to evaluate it.
-- ALTER POLICY (rather than drop/create) keeps the existing policy names
-- and avoids a window where storage.objects has no meal-photos policy at
-- all.

alter policy "meal-photos owner can read"
  on storage.objects using (
    bucket_id = 'meal-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

alter policy "meal-photos owner can insert"
  on storage.objects with check (
    bucket_id = 'meal-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

alter policy "meal-photos owner can update"
  on storage.objects using (
    bucket_id = 'meal-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

alter policy "meal-photos owner can delete"
  on storage.objects using (
    bucket_id = 'meal-photos'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

-- The bucket itself stays private (public = false, set in 20260614120600).
-- Reads continue to go through short-TTL signed URLs.
