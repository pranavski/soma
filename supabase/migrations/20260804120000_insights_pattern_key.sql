-- Dedupe insights by the association they describe, not by their wording.
--
-- claim_norm (unique per user) only ever caught a verbatim repeat. Any
-- rephrase of the same finding — which is exactly what a language model
-- produces on a second pass over the same 30 days — sailed straight through
-- it, and the prompt-level "already surfaced" list is best-effort by
-- construction.
--
-- pattern_key is the association's identity, independent of language:
-- '<food feature>_x_<body signal>_lag<0|1>', computed in candidates.ts. Two
-- runs that notice the same thing collide here no matter how differently
-- they say it, so unique (user_id, pattern_key) is now the "never repeat
-- itself" guarantee and the Edge Function's single conflict target.
--
-- claim_norm stays as a column for debugging, but loses its constraint —
-- pattern_key strictly subsumes it (identical text implies identical
-- pattern), and two unique constraints would give the upsert two ways to
-- conflict when ON CONFLICT can only name one.
--
-- support_days records the paired-day count the confidence tier was derived
-- from, so a surfaced claim can be audited against its own evidence base.
--
-- Existing rows predate candidate scoring and have no derivable pattern_key
-- or support_days, so they are cleared rather than backfilled with a guess.
-- These are pre-launch dev rows; if this ever runs against rows that matter,
-- the not-null adds below would have failed loudly instead.

truncate table public.insights;

alter table public.insights
  drop constraint insights_user_claim_norm_key;

alter table public.insights
  add column pattern_key  text not null,
  add column support_days int  not null,
  add constraint insights_user_pattern_key_key unique (user_id, pattern_key),
  add constraint insights_support_days_positive check (support_days >= 4);

-- RLS is unchanged from 20260614120500: enabled, owner-can-read. Writes come
-- from the Edge Function via service role (bypasses RLS) but always carry
-- the correct user_id.
