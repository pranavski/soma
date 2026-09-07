---
name: insight-rules
description: Soma's insight engine — the nightly/on-demand job that scores
  every food–body association over 30 days in TypeScript, hands the
  survivors to Claude to select and phrase, the coverage-based data gate,
  the statistical filtering, the confidence tiers, and the copy contract
  for each hedged claim. Use whenever working on the insight engine, the
  Insights screen, the generate-insights Edge Function, or insight copy.
---

# Soma — Insight Rules

## Philosophy
Insights surface honest, hedged correlations from the user's own data.
They never prescribe ("eat less X"), never moralize, and never repeat a
prior insight.

**TypeScript owns every number; Claude owns judgment and language.** The
engine derives per-day food features, tests each against every body signal
at lag 0 and lag 1, and keeps only what survives a permutation test with a
false-discovery-rate correction. Claude receives that scored shortlist and
decides which rows are worth telling someone about, then writes the
sentence. It never does arithmetic, and it can only describe a candidate it
was handed — a claim citing no candidate id is rejected wholesale.

This split is deliberate. The earlier design asked the model to find
correlations by eyeballing 30 lines of text and to quote the resulting
means, which is exactly the shape of task language models are unreliable
at, and nothing downstream could tell a real number from an invented one.

## The evidence layer — published science as a prior
`evidence.ts` is a small, hand-verified table of findings from the research
literature (7 rows), each naming a `(feature, signal)` pairing, the expected
direction and lag, an evidence grade (A/B/C), a one-sentence mechanism, and
its citations. It does three jobs:

1. **It is a prior on the correction.** `weightedBenjaminiHochberg` divides
   each p-value by a per-hypothesis weight before the step-up (Genovese,
   Roeder & Wasserman 2006). FDR is still controlled at q because the
   weights are fixed a priori — they come from published work, never from
   the user's data — and are normalised to mean 1. This is what pays for
   the six caffeine/alcohol/fiber pairings without taxing the existing ones.
2. **It grounds Claude's plausibility call**, which was previously unaided
   judgment. The candidate line says what the literature expects and
   whether this person agrees.
3. **It supplies the reader-facing mechanism**, joined server-side.

**The rule that matters: the evidence table owns every scientific claim.**
Claude writes the personal sentence and nothing else. `mechanism` is absent
from `RESPONSE_SCHEMA` on purpose; `index.ts` joins it from the table by
candidate id. A fabricated citation is structurally impossible, exactly as
a fabricated number already is.

Two honesty constraints:
- **Weights attach to the pairing, not the direction.** A finding running
  *opposite* to the literature gets the same weight. Down-weighting
  disagreement would be confirmation bias applied to someone's own body.
- **A contradicting finding still surfaces**, but with no mechanism
  attached — explaining physiology that did not happen to them is worse
  than saying nothing.

Adding a row requires reading the actual abstract. Three planned rows were
dropped for not surviving that check (protein×workouts, eating-window,
fiber×energy) — see the header of `evidence.ts`. `evidence_test.ts` lints
the table: pairings must exist, citations must be complete, and no
mechanism may contain second-person address or an imperative.

**On the old "0/20 false positives" claim.** That number was measured over
20 synthetic windows, which cannot distinguish 0% from 7%. Re-measured over
300 (`scripts/fdr-validation.ts`), the real rate is 21/300 (7.0%)
unweighted, 24/300 weighted. BH controls the false *discovery* rate, not
the family-wise error rate, so this is expected behaviour and not a
regression — but there was never a zero-false-positive property to protect,
and the hedged copy is why that is survivable.

## Before the statistics can speak — reflections
`reflections.ts` is the first-week layer, and it exists because of a
measured fact about the engine: **it cannot produce a finding from fewer
than about ten days of data, and no threshold in this repo is what's
stopping it.** With n paired days the smallest two-tailed p-value a
permutation test can report is 2/n!, which sits above the BH threshold
until n≈7 however strong the real relationship is. Swept over synthetic
windows (200 per cell, `scripts/` has the generator pattern):

```
days | deterministic effect | marginal effect | false positives
   3 |         0.0%          |      0.0%       |      0.0%
   5 |         0.0%          |      0.0%       |      0.0%
   7 |         0.0%          |      0.0%       |      2.0%
   8 |         2.0%          |      0.0%       |      3.0%
  10 |        69.0%          |      2.5%       |      8.0%
  14 |        83.0%          |     15.0%       |      6.0%
  30 |        83.0%          |     50.5%       |      7.5%
```

Read the 6–8 day rows carefully: real detection is 0–2% while the
false-positive rate is already 1–3%. **Below ~day 8 the only thing the
engine can emit is noise.** Lowering `MIN_MEAL_DAYS`/`MIN_BODY_DAYS` to
"let insights arrive sooner" therefore does the opposite of what it sounds
like — it makes the first thing a new user reads a fabrication. Don't.

A reflection is the honest alternative: a **description of the record**,
never an inference from it. "Your last meal has landed between 18:00 and
22:00 across these 5 days" is arithmetic over what someone typed, true on
day three with no correction to earn.

- **The line, and it is absolute:** a reflection never relates a food
  feature to a body signal. One domain per sentence. The moment it puts a
  meal and a body signal in the same sentence it is an uncorrected claim,
  which is exactly what everything above exists to prevent.
- **No model call.** The copy is templated in `reflections.ts` from
  numbers computed in the same file. There is no selection judgment to
  delegate — a description is accurate or it's a bug — and a model handed
  thin data and told to be interesting reaches for causal language.
- **A snapshot, not a feed.** Each run replaces the whole set (upsert on
  `(user_id, kind)`, then delete the kinds that dropped out). Unlike
  insights there is no never-repeat rule; repeating is the point, and a
  description of the log is wrong as soon as another meal is logged.
- Floor: **≥ 3 days with a meal** (`MIN_REFLECTION_DAYS`). Body-signal
  reflections need **≥ 3 days of that specific signal**, per signal, for
  the same reason the coverage gate uses `max(...)` and not the sum.
- At most **3** reach the feed (`MAX_REFLECTIONS`), **one per group**
  (timing / repetition / nutrition / cadence / stimulant / body) — top
  three by a fixed priority would otherwise be three facts about food.
  `candidateReflections` exposes the unthinned set; the copy constraints
  are tested against *that*, so they hold for every sentence the module
  can emit rather than only the three that fit.
- Calories still only ever as ranges. `dayRangeTotals` keeps the parser's
  low/high per day instead of reusing `buildDayFeatures`' midpoints,
  precisely so the printed figure cannot collapse to a bare number.

Client side: `InsightsViewModel.showsReflections` is `insights.isEmpty &&
!reflections.isEmpty` — they yield the moment a real finding exists. The
`ReflectionsBlock` is deliberately the visual inverse of an
`InsightFeedCard`: recessed `paperSunk`, flat, no shadow, no confidence
badge, no persimmon, and a footer that says "not findings — just what's
written down." A reader should be able to tell nothing here is a claim
before reading a word of it.

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

## Finding patterns — candidates.ts, before Claude is called
The old four hand-coded rules (late-eat×energy, repeat-dish×energy,
steps×sleep ρ, late-eat×RHR/HRV) are gone, and so is free-forming over the
digest. `candidates.ts` enumerates the search space instead:

- **9 food features per day** — total calories, total protein, total fiber,
  late caffeine (mg from 14:00, per the caffeine review's ~8.8 h cutoff),
  evening alcohol (g from 17:00), first meal hour, last meal hour, eating
  window, meal count. Calorie and protein
  totals are computed **only when every meal that day carries a parsed
  range**; a partial sum would read as a genuine low-calorie day.
- **8 body signals** — energy, steps, sleep, resting HR, HRV, weight,
  active energy, workout minutes.
- **An allowlist of 20 pairings**, not the full cross-product — see
  `PAIRINGS` in `candidates.ts`. Each is tested at **both lags** (same day,
  next day), so ~40 hypotheses. The six most recent additions are all
  evidence-backed; nothing goes in on a hunch, because an unevidenced
  pairing costs the same budget and earns none of the prior weight back.

For each pairing with **≥ 4 paired days** (`MIN_PAIR_DAYS`), it computes
Spearman ρ and a two-tailed **permutation p-value** (10,000 seeded
shuffles — deterministic, no t-distribution assumption at n=6, and a floor
of 0.0001 so values near the threshold are actually resolvable). Then
**Benjamini–Hochberg at q = 0.10** across the whole set.

That correction is not optional decoration. Testing this many associations
against 30 days of one person's data manufactures a "significant" finding
most nights; without it the app would confidently surface noise, which is
the one thing it exists not to do. At n=4 the smallest attainable p is
~0.083, so thin data almost never survives — the statistics enforce the
floor rather than the prompt asking nicely.

**Why the allowlist rather than every pairing.** Each extra hypothesis
tightens the threshold for all the others, so testing meal count against
weight does not merely add noise — it buries the findings that matter.
Measured against the full cross-product, a *deterministic* late-dinner
effect surfaced in only 5 of 20 synthetic windows; the allowlist raised
that to 7 with the false-positive rate still at 0/20. The cross-product
also made the bar depend on how much HealthKit data someone had synced —
more signals meant more hypotheses meant a stricter threshold, so
connecting a scale made every *other* finding harder to surface. **Adding
a pairing is cheap for you and expensive for every other pairing.** Add
one only when there is a reason to expect a relationship.

**Only the stronger lag survives per (feature, signal) pairing.** When
someone's routine has any periodicity — alternating late and early
dinners, a weekday/weekend rhythm — the same feature is genuinely
associated with the same signal at *both* lags, in opposite directions.
Both are real; surfacing both reads as the app contradicting itself
("later dinners give you more energy today and less tomorrow"). The
collapse happens **after** the BH correction, not before: correcting for
~14 tests when we looked at ~28 would under-count what was tested.

**On q.** Loosening to 0.15 or 0.20 raises detection (9/20 and 11/20 at
deterministic effect) but costs the zero-false-positive property (1/20
noise windows produce a finding at both). That is the one trade this app
cannot make — a false positive means telling someone an invented thing
about their own body. Detection is limited by having ~26 paired days, not
by the threshold; the lever that would actually move it is a longer
`WINDOW_DAYS`, which is a product decision, not a statistical one.

**One finding per group of features that restate each other.** Two
features can be the same fact for a given person: when breakfast sits at a
fixed hour, "eating window" is just "dinner hour" minus a constant, so
both surface against energy and the feed says one thing twice in different
words. Among survivors sharing a **signal and a lag**, if the two features
correlate at |ρ| ≥ **0.7** *for this person*, only the stronger is kept.

Measured per person, not hardcoded as a feature blocklist — someone whose
breakfast time genuinely varies has an eating window independent of their
dinner hour, and both findings deserve to surface for them. Below
`MIN_PAIR_DAYS` of overlap the two count as distinct, so a finding is
never suppressed on thin evidence.

The survivors are then ranked by |ρ|, capped at **20**, and given ids
(`c1`, `c2`, …) plus a **median split** into lower/higher groups so the
evidence line can say "the 7 latest dinners vs the 9 earlier ones" instead
of quoting a correlation coefficient at someone.

**confidence is derived, never claimed**: `high` at n ≥ 8, `medium` at
n ≥ 6, `low` down to the n ≥ 4 floor, then **one** tier of promotion if the
pattern has also replicated (below). The model does not return it.

If nothing survives — or everything that did has already been surfaced —
**Claude is not called at all**.

## Memory across runs — pattern_history
Each run used to be amnesiac: it scored ~28 associations, kept the
survivors, and threw the rest away. But consecutive nightly runs share 29 of
their 30 days, so the engine was re-asking the same questions of nearly the
same data every night with no idea it had asked before.

`pattern_history` records **every association a run measured, survivor or
not**, keyed `(user_id, run_date, pattern_key)`. Rejections are recorded
deliberately — they are the denominator; with only survivors on file "how
often does a finding replicate" has no answer. A pairing skipped for thin
data is simply absent: it was not tested, so it neither passed nor failed.
The write happens **before** the shortlist is thinned and before Claude is
called, so a night that surfaces nothing still records what it measured, and
a survivor dropped for restating a stronger finding is still remembered as
having held.

**Replication.** For each candidate, count the earlier runs where it
survived, keeping only runs **≥ 15 days apart** (`MIN_REPLICATION_GAP_DAYS`,
half the window — two runs then share at most half their days). Nightly
survival for a fortnight counts as *one* window, not fourteen; anything else
would manufacture confidence out of the cron schedule.

Holding across **≥ 2** such windows promotes `confidence` by **exactly one
tier**, however many windows agree. The windows are only *nearly*
independent, so this is corroboration, not evidence that multiplies. The
candidate line also tells the model `has held across N separate windows` —
the strongest signal it has for the plausible-vs-spurious judgment, and one
a single p-value cannot give it. The model may reflect that in plain
language ("this has kept showing up over the past couple of months"), never
as a count of runs or tests.

**The line that must not be crossed.** Replication only ever *adds*
evidence. It never changes which hypotheses are tested, their p-values,
`FDR_Q`, or what clears the correction — nothing reaches the feed that
would not have passed the permutation test in this window on its own. A
self-improving engine that learns to loosen its own filter is exactly the
failure this design exists to prevent.

The table also makes two things possible without another migration:
**reversal detection** ("this stopped holding three weeks ago" — a better
insight than a stale original), and **empirical calibration** of `FDR_Q` and
`WINDOW_DAYS` from how often real findings replicate in real users' next
windows, replacing the 20 synthetic windows the tunables were set from.

Growth is ~28 rows per active user per day; the function prunes rows older
than 180 days inline on every run.

## What Claude actually decides
Given the candidate table, the digest for context, and the last 15 claims,
the model (`claude-haiku-4-5`, constrained by a JSON response schema) picks
**at most 5** candidates and writes each one up. Its job is the judgment a
p-value can't make: is this an interpretable pattern in how someone eats
and feels, or a coincidence dressed up as a finding — a spurious pairing,
reversed causality, something nobody could notice or act on?

Selecting **none** is a good, honest answer. Every claim must carry the
`candidate_id` it describes; `validateInsights` rejects the entire payload
if any id is unknown or reused, so an invented finding has nothing to cite.

## Copy contract — for the claim + evidence Claude writes
- **claim**: one sentence naming the pattern, using the numbers from that
  candidate's line (e.g. "Energy tends to run lower the day after your
  latest dinners — 2.2 of 5 across those 7 days against 3.6 on the earlier
  9"). Hedged language only: "tends to," "seems," "is associated with."
  **Never** "causes," "makes you," "you should."
- **evidence**: the supporting comparison spelled out — how many days on
  each side, and both compared averages.
- **suggested_action**: a single gentle, observational next step ("worth
  watching whether earlier dinners shift this"), or `null`. Never
  prescriptive, never a target, never medical.
- Calories only ever as ranges ("~550–700"), never a bare number.
- An association is not causation and the copy must never imply it is.
- No number may appear that isn't on the cited candidate's line.
- **Never name a statistic.** ρ, p-values, and the word "correlation" are
  given to the model to judge strength, not to repeat. The reader gets the
  comparison; "n=14" reaches them as "14 days".

## Never repeat — by pattern, not by wording
`pattern_key` is the association's identity, independent of language:
`<feature>_x_<signal>_lag<0|1>`. Two runs that notice the same thing
collide there no matter how differently they phrase it.

- **Pre-call filter**: every `pattern_key` already stored for the user is
  removed from the candidate list *before* the model sees it, so a
  surfaced finding can't be restated.
- **Storage guarantee**: unique `(user_id, pattern_key)`, with
  `onConflict: "user_id,pattern_key", ignoreDuplicates: true`.
- The last 15 claims still go in the prompt, now only to keep phrasing
  fresh rather than to carry the dedupe.

`claim_norm` survives as a debugging column but no longer has a
constraint — it only ever caught verbatim repeats, which `pattern_key`
subsumes, and two unique constraints would give the upsert two ways to
conflict when `ON CONFLICT` can name only one.

## Cadence
Nightly via `pg_cron` at 03:30 UTC, fanning out to every user who has
logged a meal in the last 30 days, **plus** on-demand: the iOS Insights
screen's pull-to-refresh calls the same Edge Function with the user's own
JWT instead of the cron secret. Both paths are the same code — idempotent
via `pattern_key`, so calling on-demand right after a nightly run finds
nothing new to add and returns without spending a model call.

## Client-side ranking
No "one per week" cap — the feed shows everything surfaced across runs
(bounded only by per-claim uniqueness and however much history the client
fetches, currently the most recent 20). `InsightsViewModel.ranked` sorts
**confidence high → low, then newest first within a level.**

## Storage
See the `insights` table in `docs/food-body-record-mvp-spec.md`:
`claim`, `evidence`, `confidence`, `suggested_action`, `window_days`,
`pattern_key`, `support_days`, `support_windows`, `claim_norm`, `model`,
`created_at`. The two `support_*` columns are what `confidence` was derived
from, kept so a tier can be audited against its own evidence base.

`pattern_history` holds the per-run measurement record behind all of it.
Both are written only by `generate-insights` via the service role; RLS
scopes client reads to `auth.uid() = user_id`, and `pattern_history` grants
clients **no** write policy at all.

## Where the code lives
- `candidates.ts` — features, associations, permutation test, BH
  correction, replication, prompt rendering. Pure; every threshold has a
  test in `candidates_test.ts`. The entry point is `scoreAssociations`,
  which returns both the shortlist (`candidates`) and the full measured set
  (`tested`, for `pattern_history`).
- `digest.ts` — the day-line digest, coverage gate, response validation.
- `index.ts` — auth, the data window, the one Claude call, the upsert.
