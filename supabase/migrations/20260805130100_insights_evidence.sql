-- Published evidence on the insight row.
--
-- Until now an insight was purely personal: "energy runs lower after your
-- latest dinners" is true, and useless on its own. These columns carry the
-- literature that makes the finding interpretable — what is known about the
-- relationship in general, and where that knowledge comes from.
--
-- ─── Where these values come from ───────────────────────────────────────────
--
-- NOT from the model. `mechanism` and `evidence_citation` are copied
-- verbatim out of the static table in generate-insights/evidence.ts by the
-- Edge Function, after Claude has chosen which candidate to describe.
-- Claude writes the personal sentence (`claim`, `evidence`) and never sees
-- a channel through which it could author a scientific statement or a
-- citation. This mirrors the rule that already governs numbers: the model
-- owns judgment and language, TypeScript owns every fact.
--
-- That is a storage-shape decision as much as a prompt decision. If these
-- columns were model-writable, a hallucinated citation would be
-- indistinguishable from a real one at rest.
--
-- ─── Nullable on purpose ────────────────────────────────────────────────────
--
-- Most findings have no matching literature, and they still surface. A
-- pattern in someone's own data does not need a paper to be worth showing
-- them; it needs to be honestly labelled. A null mechanism renders as a card
-- without a "why this might happen" block, which is the correct
-- presentation of "nobody has studied this".

alter table public.insights
  -- One declarative sentence of general physiology, shown to the reader.
  add column mechanism         text,
  -- Stable id of the evidence row (e.g. 'caffeine_late_x_sleep'). This is
  -- the join key: it is what lets a future feature ask "which findings for
  -- this person trace back to which science", which is the substrate a meal
  -- planner would compose against. Kept as a plain text id rather than a FK
  -- because the evidence base lives in version control, not in the database
  -- — it is reviewed, cited and diffed like code, and a table would put it
  -- behind a migration every time a paper is added.
  add column evidence_source_id text,
  add column evidence_grade    text,
  -- Rendered citation string, denormalised at write time. Storing it means a
  -- surfaced claim keeps the exact reference it was shown with, even after
  -- the evidence table is revised — an insight is a record of what the app
  -- told someone, and that record should not silently change underneath it.
  add column evidence_citation text;

alter table public.insights
  add constraint insights_evidence_grade_ok
    check (evidence_grade is null or evidence_grade in ('A', 'B', 'C')),
  -- Either the whole evidence block is present or none of it is. A
  -- mechanism without a citation is an unsourced health claim, which is the
  -- one shape this feature must never produce.
  add constraint insights_evidence_all_or_nothing
    check (
      (mechanism is null and evidence_source_id is null
        and evidence_grade is null and evidence_citation is null)
      or
      (mechanism is not null and evidence_source_id is not null
        and evidence_grade is not null and evidence_citation is not null)
    );

-- Lets the meal-plan work (and any audit of "what science are we leaning on
-- across the user base") scan by source without a sequential scan. Partial,
-- because the majority of insight rows will carry no evidence at all.
create index insights_evidence_source_idx
  on public.insights (evidence_source_id)
  where evidence_source_id is not null;

-- RLS unchanged from 20260614120500: enabled, owner-scoped reads. Writes come
-- from generate-insights via the service role, which bypasses RLS but always
-- carries the correct user_id. Existing rows keep null across all four
-- columns and satisfy the all-or-nothing constraint by construction.
