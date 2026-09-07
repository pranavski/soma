-- Make the denormalised user_id on meal children provably match the meal.
--
-- meal_items.user_id and meal_corrections.user_id exist for one reason: the
-- spec calls them "denormalized for cheap RLS", so a policy can filter on
-- the row itself instead of joining back to meals on every read. That is a
-- good trade, but it silently assumes the denormalised copy agrees with the
-- meal it points at — and nothing has been enforcing that.
--
-- The gap is narrow but real. The insert policy checks only
-- `(select auth.uid()) = user_id`; it never checks that meal_id belongs to
-- the same person. A caller who learned another user's meal UUID could
-- therefore insert a meal_item carrying their OWN user_id against SOMEONE
-- ELSE'S meal, and the policy would allow it. The victim would not see the
-- row (their own reads filter on their user_id), but anything reading a
-- meal's items by meal_id under the service role — parse-meal, and any
-- future meal → items join — would pick up a stranger's row as part of that
-- meal. Injecting food into another person's record is exactly the kind of
-- thing the insight engine must never have to reason about.
--
-- The fix is declarative rather than another policy clause: point the
-- foreign key at (id, user_id) instead of (id). Postgres then rejects any
-- child row whose user_id disagrees with its parent, on every path —
-- client, service role, SQL console, future Edge Function — instead of only
-- on the paths someone remembered to guard.
--
-- Verified before writing this: zero rows in either table currently violate
-- the invariant, so both constraints validate against live data without a
-- backfill.

-- ---------------------------------------------------------------------
-- 1) The referencable key.
-- ---------------------------------------------------------------------
-- A foreign key needs a unique constraint on exactly the columns it
-- targets. (id) is already the primary key, so (id, user_id) is logically
-- redundant — it cannot be less unique than id alone. It exists purely to
-- give the composite FKs below something to point at. The extra index is
-- the honest cost of enforcing the invariant in the database rather than
-- trusting every writer to preserve it.
alter table public.meals
  add constraint meals_id_user_id_key unique (id, user_id);

-- ---------------------------------------------------------------------
-- 2) meal_items: cascade, now ownership-checked.
-- ---------------------------------------------------------------------
-- Delete behaviour is unchanged — dropping a meal still takes its items
-- with it. The only difference is that the parent is now identified by
-- (id, user_id), so a mismatched user_id is no longer expressible.
alter table public.meal_items
  drop constraint meal_items_meal_id_fkey;

alter table public.meal_items
  add constraint meal_items_meal_id_fkey
    foreign key (meal_id, user_id)
    references public.meals (id, user_id)
    on delete cascade;

-- ---------------------------------------------------------------------
-- 3) meal_corrections: set-null, now ownership-checked.
-- ---------------------------------------------------------------------
-- meal_corrections outlives the meal it corrected on purpose — the
-- correction is training signal about what the parser got wrong, and it
-- stays useful after the user deletes the meal. So the FK is ON DELETE SET
-- NULL, not CASCADE.
--
-- With a composite key that needs care: a bare SET NULL would try to null
-- BOTH referencing columns, and user_id is NOT NULL, so every meal deletion
-- would fail. Postgres 15+ takes a column list saying which side to clear
-- (this project runs 17), which keeps the row and its owner while dropping
-- only the dangling meal pointer.
--
-- meal_id stays nullable, and the default MATCH SIMPLE means the constraint
-- simply does not apply once meal_id is null — which is the correct reading
-- of an orphaned correction: it belongs to a person, not to a meal.
alter table public.meal_corrections
  drop constraint meal_corrections_meal_id_fkey;

alter table public.meal_corrections
  add constraint meal_corrections_meal_id_fkey
    foreign key (meal_id, user_id)
    references public.meals (id, user_id)
    on delete set null (meal_id);

-- ---------------------------------------------------------------------
-- 4) Index the new FK's leading column where it is missing.
-- ---------------------------------------------------------------------
-- meal_items already has (meal_id, position) and (user_id); meal_corrections
-- already has (meal_id) and (user_id, created_at). The composite FKs are
-- served by those existing indexes on their leading column, so no new index
-- is needed here — noted explicitly so a later index audit does not "fix"
-- a gap that was already considered.
--
-- RLS is untouched. Policies remain (select auth.uid()) = user_id on both
-- tables; this migration constrains what user_id is allowed to BE, which is
-- the half the policy could never express.
