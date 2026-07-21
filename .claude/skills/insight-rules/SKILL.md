---
name: insight-rules
description: Soma's weekly insight engine — the four v1 correlation rules,
  their minimum-n thresholds, tier-based data availability gating, and the
  copy contract for the one-sentence hedged finding. Use whenever working on
  the insight engine, the Insights screen, the generate-insights Edge
  Function, or insight copy.
---

# Soma — Insight Rules

## Philosophy
Insights surface honest, hedged correlations from the user's own data.
They never prescribe ("eat less X"), never moralize, and never repeat a
prior insight. The engine computes the finding; Claude writes the sentence.

## Tier gating — what data is available
A user is in exactly one tier per week, based on what synced from HealthKit:

- **Tier 0** — food logs + the daily energy check-in only. No HealthKit.
- **Tier 1** — Tier 0 + steps + coarse sleep duration.
- **Tier 2** — Tier 1 + resting heart rate (RHR) + heart rate variability (HRV).

Each rule declares the minimum tier it requires. If the user is below that
tier, the rule is skipped for the week.

## The four v1 rules
Each rule has: a question, a minimum tier, a minimum-n threshold (number of
qualifying days/meals in the lookback window), and a statistic.

### 1. Late-evening eating × next-day energy
- **Tier:** 0
- **Question:** When you eat after 21:00, does the next morning's energy
  check-in tend to be lower?
- **Min n:** ≥ 5 "late" days AND ≥ 5 "not late" days in the 28-day window.
- **Stat:** Mean energy(0–5) on day-after-late vs. day-after-not-late.
  Surface when |Δ| ≥ 0.6 points.

### 2. Repeat dish × next-day energy
- **Tier:** 0
- **Question:** Of the dishes you eat ≥ 3 times in the window, which one
  most consistently precedes a higher or lower energy day?
- **Min n:** dish eaten ≥ 3 times AND the comparison cohort has ≥ 5 days.
- **Stat:** Mean energy day-after-dish vs. baseline. Surface when
  |Δ| ≥ 0.7 points.

### 3. Step count × sleep duration
- **Tier:** 1
- **Question:** Do higher-step days tend to be followed by longer sleep?
- **Min n:** ≥ 10 paired days in the 28-day window.
- **Stat:** Spearman ρ between steps(day d) and sleep(night d→d+1).
  Surface when |ρ| ≥ 0.35.

### 4. Late-evening eating × RHR / HRV
- **Tier:** 2
- **Question:** When you eat after 21:00, is your overnight RHR higher (or
  HRV lower) than baseline?
- **Min n:** ≥ 5 late days AND ≥ 5 not-late days, all with overnight
  RHR/HRV present.
- **Stat:** Mean overnight RHR (and separately HRV) on late vs. not-late.
  Surface RHR Δ ≥ 2 bpm OR HRV Δ ≥ 4 ms.

## Selection per week
- Compute every rule the user qualifies for. Up to **one** insight is
  shown per week.
- Rank surfaced insights by effect size (normalized within rule), then by
  recency of supporting evidence.
- **Never repeat** the most recent prior insight; skip to the next-ranked.
- If nothing qualifies, show the "no-insights-yet" empty state with the
  honest reason ("we need ~2 more weeks of data to find a pattern").

## Copy contract — for the LLM-written sentence
- Exactly ONE sentence, ≤ 22 words.
- Hedged: includes "tends to," "is associated with," "worth watching, not
  a verdict," or similar. **No** "causes," "makes you," "you should."
- Mentions both sides of the comparison (e.g. "late dinners vs. earlier").
- Never prescriptive. Never medical. Never references calories as a single
  number — use a range or omit.
- Claude is told the **computed numbers**; it never invents the finding.

## Storage
- Surfaced insights persist in an `insights` table with `rule_id`, the
  computed stat, `tier`, the lookback window, and the generated copy.
- The "never repeat" check reads from this table, scoped to `user_id`.
