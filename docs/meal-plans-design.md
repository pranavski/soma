# Meal plans — design note (not built)

_Written 2026-08-05, alongside the evidence layer. **No meal-plan code
exists.** This records why the evidence work was shaped the way it was, so
that whoever picks this up inherits a foundation rather than a migration._

## The problem with the obvious version

The obvious meal-plan feature is: ask Claude for a week of meals hitting
some macro target. Soma must not ship that, and the reason is not squeamishness
about scope — it is that the app's entire claim on a user's trust is
"understanding, not dieting." A generic plan is advice Soma has no standing to
give: it knows nothing about this person that a search engine doesn't, it
implies targets the app promises never to set, and the moment it appears the
insight engine's careful hedging reads as throat-clearing before the real
product.

It also fails on its own terms. Every diet app can generate a meal plan. The
one thing Soma has that they do not is a per-person record of which foods
actually track with how that person's body behaved, scored honestly enough that
most candidate findings get thrown away.

## What Soma can offer that nothing else can

A plan composed from **this person's own corroborated findings**, and nothing
else. The shape:

1. The insight engine surfaces a finding — say, caffeine after 2pm tracking with
   ~70 fewer minutes of sleep across 12 days.
2. That finding is corroborated by published evidence, so it carries an
   `evidence_source_id`.
3. The evidence row names the **nutrient lever** — caffeine, and specifically
   caffeine late in the day.
4. FoodData Central knows which foods carry that nutrient and in what quantity.
5. A suggestion can therefore be assembled that is traceable end to end:
   *this food, because of this nutrient, because of this finding in your data,
   corroborated by this paper.*

Nothing in that chain is invented, and every step is already built except the
last.

## What already exists, and why

The evidence layer shipped these deliberately, so a meal-plan feature needs no
schema change to begin:

- **`insights.evidence_source_id`** — the join key. Given a user, "which of
  their findings trace back to which science" is one indexed query
  (`insights_evidence_source_idx`). This column exists for this feature; the
  insight card itself only needs `mechanism` and `evidence_citation`.
- **`evidence.ts`** — each row already carries `feature`, `direction`, and
  `grade`. `feature` *is* the nutrient lever (`caffeine_mg_late`,
  `alcohol_g_evening`, `total_fiber_g`), and `direction` says which way to move
  it.
- **`_shared/fdc-reference.json`** + `parse-meal/fdc.ts` — per-100g composition
  and standard servings, already keyed by the same nutrients.
- **`pattern_history`** — whether a finding *kept* holding. A plan should only
  ever be built on patterns that replicated, and that table is the record.

## The rules any such feature must keep

These are not negotiable without changing what Soma is:

- **Never a target.** No calorie goals, no macro targets, no "aim for". The
  output is a suggestion of what to cook, not a specification to hit.
- **Only from corroborated, replicated findings.** A one-window finding is not
  a basis for telling someone what to eat. Require `support_windows >= 2` and a
  non-null `evidence_source_id`.
- **Never from the literature alone.** If a person has no relevant finding,
  they get no plan. "People sleep worse after late caffeine" is not a reason to
  plan *this* person's meals; "your last 30 days show this, and it is a known
  effect" is.
- **Cite the same way the card does.** Every suggestion carries the finding it
  came from and the paper behind it. If a suggestion cannot show its work, it
  does not ship.
- **Still not medical.** Same hard rule as everywhere else — no therapeutic
  claims, no advice for any condition.

## Open questions

- Does a meal plan need recipes, or is "these ingredients, roughly this time of
  day" closer to how someone who cooks actually works? The logging flow assumes
  people cook; the plan probably should too.
- The FDC extract is currently near-empty (see `scripts/build-fdc-reference.ts`
  — it needs a free API key to populate). Composition-driven suggestions need it
  filled in first.
- Nothing here has been user-tested. The chain above is coherent; whether anyone
  wants it is a separate question and should be answered before it is built.
