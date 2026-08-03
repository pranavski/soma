-- Insight-engine pivot: insights are no longer one templated finding per
-- ISO week from the four v1 rules — they are LLM-generated correlations
-- over a rolling window, several per run, deduped by normalized claim.
--
-- Old rule-based rows are pre-pivot dev data and are incompatible with the
-- new shape (claim/evidence are not derivable from rule_id + stat), so the
-- table is truncated. If this ever runs against rows that matter, the
-- not-null adds below will fail loudly rather than silently fabricating.
--
-- claim_norm is computed by the Edge Function (lowercase, alphanumerics
-- only, collapsed whitespace); unique (user_id, claim_norm) is the
-- "never repeat itself" guarantee at the storage layer — the prompt-level
-- "already surfaced" list is best-effort, this is the backstop.

truncate table public.insights;

alter table public.insights
  drop column rule_id,
  drop column tier,
  drop column week_start,   -- also drops unique(user_id, week_start) + insights_user_week_idx
  drop column lookback_days,
  drop column stat,
  drop column copy;

alter table public.insights
  add column claim            text not null,
  add column evidence         text not null,
  add column confidence       text not null check (confidence in ('low', 'medium', 'high')),
  add column suggested_action text,
  add column window_days      int  not null,
  add column claim_norm       text not null,
  add constraint insights_user_claim_norm_key unique (user_id, claim_norm);

create index insights_user_created_idx on public.insights (user_id, created_at desc);

-- RLS stays as created in 20260614120500: enabled, owner-can-read/insert.
-- Writes come from the Edge Function via service role (bypasses RLS) but
-- always carry the correct user_id.
