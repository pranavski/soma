---
name: insight-rules
description: Soma's insight engine — the nightly/on-demand digest that
  compresses 30 days of meals, check-ins, and HealthKit data and hands it
  to Claude to find correlations directly, the coverage-based data gate,
  the confidence tiers, and the copy contract for each hedged claim. Use
  whenever working on the insight engine, the Insights screen, the
  generate-insights Edge Function, or insight copy.
---

# Soma — Insight Rules

## Philosophy
Insights surface honest, hedged correlations from the user's own data.
They never prescribe ("eat less X"), never moralize, and never repeat a
prior insight. There is no fixed rule set anymore — the engine compresses
30 days of the user's own data into a compact digest and hands the whole
thing to Claude, which finds the patterns **and** writes the sentence in
one call. TypeScript's job is disciplined compression and strict
validation of what comes back; it never invents or discards a finding on
its own, and it never lets a structurally-broken response through.

## Data gating — what's needed before Claude is called
There are no HealthKit tiers gating generation anymore (the old 0/1/2
tier scheme still exists on `health_days.tier`, computed client-side, but
it's informational only — the engine does not read it). Instead,
`generate-insights` computes two coverage numbers over the last 30 days
and gates on both:

- **meal days** — distinct days with at least one meal logged. Need **≥ 7**.
- **body days** — the single best-covered body signal (energy check-in,
  steps, sleep, resting HR, HRV, weight, active energy, or workout
  minutes), i.e. `max(...)` across those counts, **not the sum**. Need
  **≥ 7**. Four days of steps plus four days of sleep is not eight days of
  a reliable signal — it's two unreliable ones.

Below either bar, the function returns `{ surfaced: false, reason:
"insufficient_data" }` without calling Claude at all.

## The digest
One line per day that has any signal, ascending by date:

```
2026-07-18 | wt 78.4kg | sleep 6h50m | steps 9102 | actE 520kcal | workout 35m | RHR 61 | HRV 44ms | energy 3/5 | meals: 08h greek yogurt + berries (~220-320kcal, ~18-24g prot), 21h pizza
```

- A metric that didn't sync is **omitted from the line**, never rendered
  as `0` — the model must not mistake "didn't sync" for "didn't move."
- Meals are sorted by local hour within the day and labeled with their
  calorie/protein ranges when parsed.
- Alongside the digest, the model also gets a per-metric coverage count
  (`days with weight: 3`, `days with steps: 22`, ...) so it can tell a
  real trend from a handful of stray readings.

## Finding patterns — no fixed rule set
The old four hand-coded rules (late-eat×energy, repeat-dish×energy,
steps×sleep ρ, late-eat×RHR/HRV) are gone. Claude free-forms over the
digest instead, bound by non-negotiable evidence discipline baked into
the system prompt:

- A pattern needs **≥ 4 supporting days** to be claimed at all. Fewer than
  that, it does not go in the output.
- **confidence: high** requires a consistent pattern with **n ≥ 8**
  supporting days; **medium** needs **n ≥ 6**; anything qualifying below
  that is **low**.
- Never claim a trend in a metric with fewer days of data than the
  coverage counts show. Never treat a missing metric on a day as zero.
- At most **5** claims per run. An empty array is a good, honest answer —
  better than an invented pattern.

## Copy contract — for the claim + evidence Claude writes
- **claim**: one sentence naming a specific pattern with real numbers from
  the digest (e.g. "Energy dips to 2/5 tend to follow sub-20g-protein
  mornings — 5 of the 6 such days"). Hedged language only: "tends to,"
  "seems," "is associated with." **Never** "causes," "makes you," "you
  should."
- **evidence**: the supporting observation spelled out — which days, how
  many, the compared values (e.g. "mean energy 2.2/5 after the 6
  low-protein mornings vs 3.6/5 after the 9 higher-protein ones").
- **suggested_action**: a single gentle, observational next step ("worth
  watching whether earlier dinners shift this"), or `null`. Never
  prescriptive, never a target, never medical.
- Calories only ever as ranges ("~550–700"), never a bare number.
- Must not repeat or rephrase any claim already shown to this person (see
  dedupe below) — genuinely new patterns only.

## Never repeat — two layers
- **Prompt-level**: the user's last 15 claims (most recent first) are
  handed to Claude as "already surfaced — do not repeat or rephrase
  these." Best-effort — a sufficiently different phrasing of the same
  finding could slip through.
- **Storage-level backstop**: `claim_norm` (the claim lowercased,
  alphanumerics only, whitespace collapsed) is unique per
  `(user_id, claim_norm)`. Inserts use
  `onConflict: "user_id,claim_norm", ignoreDuplicates: true`, so even an
  exact-text repeat silently no-ops instead of duplicating.

## Cadence
Nightly via `pg_cron` at 03:30 UTC, fanning out to every user who has
logged a meal in the last 30 days, **plus** on-demand: the iOS Insights
screen's pull-to-refresh calls the same Edge Function with the user's own
JWT instead of the cron secret. Both paths are the same code — idempotent
via `claim_norm`, so calling on-demand right after a nightly run just
finds nothing new to add.

## Client-side ranking
No "one per week" cap — the feed shows everything surfaced across runs
(bounded only by per-claim uniqueness and however much history the client
fetches, currently the most recent 20). `InsightsViewModel.ranked` sorts
**confidence high → low, then newest first within a level.**

## Storage
See the `insights` table in `docs/food-body-record-mvp-spec.md`:
`claim`, `evidence`, `confidence`, `suggested_action`, `window_days`,
`claim_norm`, `model`, `created_at`. Written only by `generate-insights`
via the service role; RLS still scopes client reads to `auth.uid() =
user_id`.
