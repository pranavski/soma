// Candidate association finding for generate-insights.
//
// Pure functions only — no fetch, no Deno.env — so they can be unit-tested
// (see candidates_test.ts) without serving the function.
//
// This module owns every number the app ever shows a person. It derives
// per-day food features, tests an allowlist of food/signal pairings at lag
// 0 and lag 1, and keeps only the associations that survive a permutation
// test with a Benjamini-Hochberg correction for having looked at ~28 of
// them. What is left is then thinned twice more: one lag per pairing, and
// one finding per group of features that restate each other.
//
// The model never does arithmetic. It receives this table and decides which
// rows are worth saying out loud, then writes the sentence. Anything it
// claims can be traced back to a row here by candidate id.

import { type CheckinRow, type HealthDayRow, type MealRow, dayOfMeal, hourOfMeal } from "./digest.ts";
import {
  type Agreement,
  type EvidenceRow,
  agreementWith,
  evidenceFor,
  priorWeight,
} from "./evidence.ts";

// ─── Tunables ───────────────────────────────────────────────────────────────

/// Fewer paired days than this and there is no association to speak of.
/// Matches the "a pattern needs at least 4 supporting days" rule in the
/// insight-rules skill — the permutation test then does the real filtering
/// (at n=4 the smallest attainable two-tailed p is ~0.083, so almost
/// nothing this thin survives the correction anyway).
export const MIN_PAIR_DAYS = 4;

/// Benjamini-Hochberg false-discovery rate. 0.10 rather than 0.05: this is
/// exploratory, every claim ships hedged, and 0.05 over a 30-day window
/// surfaces essentially nothing.
///
/// CORRECTION (evidence-layer change). This block previously recorded
/// "0/20 false positives" at q=0.10 and described a zero-false-positive
/// property as the thing the app must never trade. Re-measured over 300
/// synthetic noise windows instead of 20 (scripts/fdr-validation.ts), the
/// real rate is:
///
///   pure-noise windows producing at least one finding:  21/300  (7.0%)
///
/// The old number was not wrong so much as unresolvable: 20 windows cannot
/// distinguish 0% from 7%, and the first sample happened to contain no
/// hits. There was never a zero-false-positive property to protect.
///
/// This is expected, not a defect. Benjamini-Hochberg controls the FALSE
/// DISCOVERY RATE — the share of findings that are wrong — not the
/// family-wise error rate, which is what "does a noise window produce
/// anything" measures. At q=0.10 roughly a tenth of surfaced findings are
/// expected to be spurious, and a ~7% chance that a given quiet month
/// produces one is the same statement seen from the other side. Every
/// claim ships hedged ("worth watching, not a verdict") precisely because
/// this number is not zero and cannot be made zero.
///
/// What still holds: loosening q raises both rates together, and detection
/// is limited by having ~26 paired days rather than by the threshold. The
/// lever that actually moves detection is a longer WINDOW_DAYS (a product
/// decision) or a well-founded prior (see weightedBenjaminiHochberg).
export const FDR_Q = 0.10;

/// Ceiling on how many candidates the model is shown. Ranked by |rho|.
export const MAX_CANDIDATES = 20;

/// Zero-inflation floor, for features that are zero on most days —
/// evening alcohol and late caffeine especially. Requiring only that a
/// feature take two distinct values (the existing guard) lets a column of
/// 22 zeros and 2 drinking nights through, where Spearman is reading the
/// gap between two ranks and the permutation test cannot tell that apart
/// from noise.
///
/// Both sides need this many days: at least this many where the feature is
/// present, and at least this many where it is absent. Below that there is
/// no contrast to measure, only two anecdotes.
export const MIN_VARIANT_DAYS = 3;

/// Above this correlation between two features, a finding about one is a
/// restatement of a finding about the other. When breakfast sits at a fixed
/// hour, "eating window" is just "dinner hour" minus a constant, and
/// surfacing both against energy tells someone the same thing twice in
/// different words.
///
/// Measured per person rather than hardcoded as a feature blocklist: a
/// person whose breakfast time genuinely varies has an eating window that
/// is independent of their dinner hour, and both findings deserve to
/// surface for them.
export const REDUNDANT_FEATURE_RHO = 0.7;

/// Permutation iterations per candidate. The smallest p-value this test can
/// report is 1/(PERMUTATIONS+1), so at 2000 it could not resolve values
/// below 0.0005 — uncomfortably close to the FDR threshold it was being
/// judged against. 10000 puts the floor an order of magnitude below the
/// threshold, and ~28 hypotheses x 10000 shuffles of <=30 points still runs
/// in well under a second.
export const PERMUTATIONS = 10_000;

/// Minimum days between two runs before they count as separate evidence for
/// the same pattern.
///
/// Consecutive nightly runs share 29 of their 30 days, so "it survived again
/// tonight" is very nearly a tautology — treating that as replication would
/// manufacture confidence out of the cron schedule. At half the window the
/// two runs share at most half their days, which is corroboration rather
/// than restatement. Must stay >= WINDOW_DAYS / 2 (index.ts).
export const MIN_REPLICATION_GAP_DAYS = 15;

/// Independent windows a pattern must hold across before its confidence is
/// promoted. Counting the current run, so 2 means "held once before, at
/// least MIN_REPLICATION_GAP_DAYS ago".
export const MIN_REPLICATION_WINDOWS = 2;

/// The two intake windows the evidence rows are actually about. 14h follows
/// the caffeine review's modelled ~8.8h cutoff against a typical bedtime;
/// 17h is the conventional start of evening drinking. Exported because
/// reflections.ts describes the same two windows in prose ("caffeine after
/// 2pm") and the description must not be able to drift from the feature.
export const LATE_CAFFEINE_HOUR = 14;
export const EVENING_ALCOHOL_HOUR = 17;

// ─── Feature and signal definitions ─────────────────────────────────────────

export type FeatureKey =
  | "total_kcal"
  | "total_protein_g"
  | "total_fiber_g"
  | "caffeine_mg_late"
  | "alcohol_g_evening"
  | "first_meal_hour"
  | "last_meal_hour"
  | "eating_window_h"
  | "meal_count";

export type SignalKey =
  | "energy"
  | "steps"
  | "sleep_minutes"
  | "resting_hr_bpm"
  | "hrv_ms"
  | "weight_kg"
  | "active_energy_kcal"
  | "workout_minutes";

const FEATURE_LABELS: Record<FeatureKey, string> = {
  total_kcal: "day's total calories",
  total_protein_g: "day's total protein (g)",
  total_fiber_g: "day's total fiber (g)",
  caffeine_mg_late: "caffeine from 2pm onward (mg)",
  alcohol_g_evening: "alcohol from 5pm onward (g)",
  first_meal_hour: "hour of first meal",
  last_meal_hour: "hour of last meal",
  eating_window_h: "eating window (hours first to last meal)",
  meal_count: "meals logged that day",
};

const SIGNAL_LABELS: Record<SignalKey, string> = {
  energy: "energy self-report (1-5)",
  steps: "steps",
  sleep_minutes: "sleep (minutes)",
  resting_hr_bpm: "resting HR (bpm)",
  hrv_ms: "HRV (ms)",
  weight_kg: "weight (kg)",
  active_energy_kcal: "active energy (kcal)",
  workout_minutes: "workout minutes",
};

/// Decimal places when rendering each signal's group means for the prompt.
/// Whole numbers for counts, one place for the things people read as decimals.
const SIGNAL_DECIMALS: Record<SignalKey, number> = {
  energy: 1,
  steps: 0,
  sleep_minutes: 0,
  resting_hr_bpm: 0,
  hrv_ms: 0,
  weight_kg: 1,
  active_energy_kcal: 0,
  workout_minutes: 0,
};

const FEATURE_DECIMALS: Record<FeatureKey, number> = {
  total_kcal: 0,
  total_protein_g: 0,
  total_fiber_g: 0,
  caffeine_mg_late: 0,
  alcohol_g_evening: 1,
  first_meal_hour: 1,
  last_meal_hour: 1,
  eating_window_h: 1,
  meal_count: 1,
};

export const FEATURE_KEYS = Object.keys(FEATURE_LABELS) as FeatureKey[];
export const SIGNAL_KEYS = Object.keys(SIGNAL_LABELS) as SignalKey[];

/// The hypotheses we are willing to test, rather than the full 6x8
/// cross-product.
///
/// Every extra pairing tightens the FDR threshold for all the others, so
/// testing meal_count against weight or first-meal-hour against HRV does not
/// just add noise — it actively buries the findings we care about. Measured:
/// against the full cross-product, a *deterministic* late-dinner effect
/// surfaced in only 5 of 20 synthetic windows.
///
/// The cross-product also made the threshold depend on how much HealthKit
/// data someone had synced: more signals meant more hypotheses meant a
/// stricter bar, so connecting a scale made every other finding harder to
/// surface. A fixed list removes that.
///
/// Each entry is tested at both lags; `strongestLagPerPairing` then keeps
/// one. Additions are cheap to make and expensive to everyone else — add a
/// pairing only when there is a reason to expect a relationship.
export const PAIRINGS: ReadonlyArray<readonly [FeatureKey, SignalKey]> = [
  // Meal timing against how the body feels and recovers overnight.
  ["last_meal_hour", "energy"],
  ["last_meal_hour", "sleep_minutes"],
  ["last_meal_hour", "resting_hr_bpm"],
  ["last_meal_hour", "hrv_ms"],
  ["first_meal_hour", "energy"],
  ["eating_window_h", "energy"],
  ["eating_window_h", "sleep_minutes"],

  // How much, against how it feels and where it shows up.
  ["total_kcal", "energy"],
  ["total_kcal", "weight_kg"],
  ["total_kcal", "steps"],
  ["total_kcal", "active_energy_kcal"],
  ["meal_count", "energy"],

  // Protein against energy and training.
  ["total_protein_g", "energy"],
  ["total_protein_g", "workout_minutes"],

  // Evidence-backed additions. Every one of these has a row in
  // evidence.ts, read out of the source's own abstract — see that file's
  // header for the three candidate pairings that were dropped because the
  // literature turned out not to support them. Nothing goes in this block
  // on a hunch: an unevidenced pairing costs the same FDR budget as an
  // evidenced one but earns none of the prior weight back.
  ["caffeine_mg_late", "sleep_minutes"],
  ["alcohol_g_evening", "sleep_minutes"],
  ["alcohol_g_evening", "resting_hr_bpm"],
  ["alcohol_g_evening", "hrv_ms"],
  ["alcohol_g_evening", "energy"],
  ["total_fiber_g", "sleep_minutes"],
];

// ─── Per-day food features ──────────────────────────────────────────────────

export type DayFeatures = Partial<Record<FeatureKey, number>>;

/// Calorie and protein totals are only computed when EVERY meal that day
/// carries a parsed range. A partial sum silently understates the day and
/// would show up as a real-looking low-calorie day in the correlation.
export function buildDayFeatures(meals: MealRow[]): Map<string, DayFeatures> {
  const byDay = new Map<string, MealRow[]>();
  for (const m of meals) {
    const day = dayOfMeal(m);
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day)!.push(m);
  }

  const out = new Map<string, DayFeatures>();
  for (const [day, dayMeals] of byDay) {
    const hours = dayMeals.map(hourOfMeal);
    const f: DayFeatures = {
      meal_count: dayMeals.length,
      first_meal_hour: Math.min(...hours),
      last_meal_hour: Math.max(...hours),
      eating_window_h: Math.max(...hours) - Math.min(...hours),
    };

    const everyKcal = dayMeals.every((m) => m.calories_low !== null && m.calories_high !== null);
    if (everyKcal) {
      f.total_kcal = dayMeals.reduce((s, m) => s + (m.calories_low! + m.calories_high!) / 2, 0);
    }
    const everyProtein = dayMeals.every((m) => m.protein_g_low !== null && m.protein_g_high !== null);
    if (everyProtein) {
      f.total_protein_g = dayMeals.reduce((s, m) => s + (m.protein_g_low! + m.protein_g_high!) / 2, 0);
    }
    const everyFiber = dayMeals.every((m) => m.fiber_g_low !== null && m.fiber_g_high !== null);
    if (everyFiber) {
      f.total_fiber_g = dayMeals.reduce((s, m) => s + (m.fiber_g_low! + m.fiber_g_high!) / 2, 0);
    }

    // Caffeine and alcohol are windowed, not daily totals: the evidence is
    // specifically about intake late enough to still be on board at
    // bedtime. 14h follows the caffeine review's modelled 8.8h cutoff for a
    // cup of coffee against a typical bedtime; 17h is the conventional
    // start of evening drinking.
    //
    // Unlike the totals above, a missing value counts as zero rather than
    // voiding the day. The asymmetry is deliberate: an unparsed meal could
    // hide any number of calories, but the overwhelming majority of meals
    // genuinely contain no caffeine and no alcohol, so requiring every meal
    // to carry an explicit 0 would throw away nearly every day. What we do
    // require is that the day had SOME parsed nutrition, so that a day of
    // entirely unparsed meals is not silently recorded as a sober,
    // caffeine-free one.
    const anyParsed = dayMeals.some((m) => m.caffeine_mg_high !== null || m.alcohol_g_high !== null);
    if (anyParsed) {
      f.caffeine_mg_late = sumRangeFrom(dayMeals, LATE_CAFFEINE_HOUR, (m) => [m.caffeine_mg_low, m.caffeine_mg_high]);
      f.alcohol_g_evening = sumRangeFrom(dayMeals, EVENING_ALCOHOL_HOUR, (m) => [m.alcohol_g_low, m.alcohol_g_high]);
    }

    out.set(day, f);
  }
  return out;
}

/// Midpoint sum of a nutrient range across the meals at or after `fromHour`.
/// A null range contributes nothing — see the note on `anyParsed` above for
/// why that is safe here and not for calories.
function sumRangeFrom(
  meals: MealRow[],
  fromHour: number,
  pick: (m: MealRow) => [number | null, number | null],
): number {
  let total = 0;
  for (const m of meals) {
    if (hourOfMeal(m) < fromHour) continue;
    const [lo, hi] = pick(m);
    if (lo === null || hi === null) continue;
    total += (lo + hi) / 2;
  }
  return total;
}

// ─── Per-day body signals ───────────────────────────────────────────────────

export type DaySignals = Partial<Record<SignalKey, number>>;

export function buildDaySignals(
  checkins: CheckinRow[],
  health: HealthDayRow[],
): Map<string, DaySignals> {
  const out = new Map<string, DaySignals>();
  const at = (day: string): DaySignals => {
    if (!out.has(day)) out.set(day, {});
    return out.get(day)!;
  };

  for (const c of checkins) at(c.check_date).energy = c.energy;
  for (const h of health) {
    const s = at(h.day);
    if (h.steps != null) s.steps = Number(h.steps);
    if (h.sleep_minutes != null) s.sleep_minutes = Number(h.sleep_minutes);
    if (h.resting_hr_bpm != null) s.resting_hr_bpm = Number(h.resting_hr_bpm);
    if (h.hrv_ms != null) s.hrv_ms = Number(h.hrv_ms);
    if (h.weight_kg != null) s.weight_kg = Number(h.weight_kg);
    if (h.active_energy_kcal != null) s.active_energy_kcal = Number(h.active_energy_kcal);
    if (h.workout_minutes != null) s.workout_minutes = Number(h.workout_minutes);
  }
  return out;
}

// ─── Statistics ─────────────────────────────────────────────────────────────

/// Average-tie ranks, as Spearman requires.
export function rank(xs: number[]): number[] {
  const order = xs.map((v, i) => ({ v, i })).sort((a, b) => a.v - b.v);
  const ranks = new Array<number>(xs.length);
  let i = 0;
  while (i < order.length) {
    let j = i;
    while (j + 1 < order.length && order[j + 1].v === order[i].v) j++;
    const avg = (i + j) / 2 + 1;
    for (let k = i; k <= j; k++) ranks[order[k].i] = avg;
    i = j + 1;
  }
  return ranks;
}

function pearson(xs: number[], ys: number[]): number {
  const n = xs.length;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0, dx = 0, dy = 0;
  for (let i = 0; i < n; i++) {
    const a = xs[i] - mx, b = ys[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  const den = Math.sqrt(dx * dy);
  return den === 0 ? 0 : num / den;
}

/// Clamped, because a ratio of floating-point sums can land a hair outside
/// [-1, 1] on a perfectly monotone series, and a correlation cannot. The
/// pattern_history row carries a `check (rho >= -1 and rho <= 1)`, so 1 +
/// 2e-16 would cost a run its whole memory of that night.
export function spearman(xs: number[], ys: number[]): number {
  const rho = pearson(rank(xs), rank(ys));
  return Math.max(-1, Math.min(1, rho));
}

/// Seeded xorshift32 — the p-values have to be identical run to run, or the
/// tests are flaky and two nightly runs disagree about the same data.
function makeRng(seed: number): () => number {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 0x100000000;
  };
}

/// Two-tailed permutation test: how often does shuffling one side produce an
/// association at least this strong? No distributional assumption, which
/// matters at n=6. The +1s are the standard unbiased correction.
export function permutationP(
  xs: number[],
  ys: number[],
  observedRho: number,
  iterations = PERMUTATIONS,
  seed = 0x5eed,
): number {
  const rng = makeRng(seed);
  const rx = rank(xs);
  const ry = rank(ys).slice();
  const target = Math.abs(observedRho);
  let atLeastAsExtreme = 0;

  for (let it = 0; it < iterations; it++) {
    for (let i = ry.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [ry[i], ry[j]] = [ry[j], ry[i]];
    }
    if (Math.abs(pearson(rx, ry)) >= target - 1e-12) atLeastAsExtreme++;
  }
  return (atLeastAsExtreme + 1) / (iterations + 1);
}

/// Benjamini-Hochberg step-up. Returns, per input index, whether that
/// hypothesis is kept at false-discovery rate q. Without this, testing ~100
/// associations against 30 days of one person's data manufactures a
/// "significant" finding or two every single night.
export function benjaminiHochberg(pValues: number[], q = FDR_Q): boolean[] {
  const m = pValues.length;
  const keep = new Array<boolean>(m).fill(false);
  if (m === 0) return keep;

  const sorted = pValues.map((p, i) => ({ p, i })).sort((a, b) => a.p - b.p);
  let cutoff = -1;
  for (let k = 0; k < m; k++) {
    if (sorted[k].p <= ((k + 1) / m) * q) cutoff = k;
  }
  for (let k = 0; k <= cutoff; k++) keep[sorted[k].i] = true;
  return keep;
}

export type Confidence = "low" | "medium" | "high";

/// Benjamini-Hochberg with per-hypothesis prior weights (Genovese, Roeder
/// & Wasserman 2006). Each p-value is divided by its weight before the
/// ordinary step-up, so a hypothesis the literature already supports needs
/// less from this person's 30 days to clear the bar, and one nobody has
/// studied needs slightly more.
///
/// The FDR is still controlled at q. Two conditions make that true, and
/// both are enforced rather than assumed:
///
///   1. The weights are fixed A PRIORI. They come from evidence.ts, which
///      is a static table of published findings — nothing about the user's
///      data can reach them. Deriving weights from the data being tested
///      would invalidate the guarantee completely.
///   2. The weights average 1. We normalise here rather than trusting the
///      caller, because a table whose weights averaged 1.4 would silently
///      be running at q=0.14 while still claiming 0.10.
///
/// This is what pays for the six new pairings. Measured over 300 PAIRED
/// synthetic windows — both procedures on identical data, so the discordant
/// counts are the real comparison (scripts/fdr-validation.ts):
///
///                                    unweighted -> weighted   discordant
///   pure-noise windows with a finding    21/300 ->   24/300    +4 / -1
///   marginal evidence-backed effect     129/300 ->  141/300   +12 / -0
///
/// Twelve additional true detections for three additional false positives,
/// and not one window lost a detection. On a McNemar test the detection
/// gain is significant (p ~ 0.0005) while the false-positive difference is
/// not distinguishable from noise (p ~ 0.38).
///
/// Note the effect used is deliberately MARGINAL. A deterministic effect
/// clears every threshold and so cannot tell two procedures apart — both
/// find it in 14/20 windows. The prior only matters for findings sitting
/// near the bar, which is exactly where a prior should matter.
export function weightedBenjaminiHochberg(
  pValues: number[],
  weights: number[],
  q = FDR_Q,
): boolean[] {
  const m = pValues.length;
  const keep = new Array<boolean>(m).fill(false);
  if (m === 0) return keep;
  if (weights.length !== m) throw new Error("weights and pValues must align");

  const meanWeight = weights.reduce((a, b) => a + b, 0) / m;
  // All-zero or degenerate weights carry no information; fall back to the
  // unweighted procedure rather than dividing by zero.
  if (!(meanWeight > 0)) return benjaminiHochberg(pValues, q);

  const adjusted = pValues.map((p, i) => {
    const w = weights[i] / meanWeight;
    return w > 0 ? p / w : Number.POSITIVE_INFINITY;
  });
  return benjaminiHochberg(adjusted, q);
}

/// Confidence is derived from the number of supporting days, never
/// self-reported by the model. Thresholds match the insight-rules skill.
export function confidenceForN(n: number): Confidence {
  if (n >= 8) return "high";
  if (n >= 6) return "medium";
  return "low";
}

/// Paired days are one axis of evidence; holding up in a second, largely
/// different window is another. A pattern that cleared the FDR correction
/// twice over windows two weeks apart has been asked the same question of
/// mostly different data and answered the same way — that is worth a tier.
///
/// Promotion is capped at one tier no matter how many windows agree,
/// because the windows are only NEARLY independent (they may share half
/// their days), so this is corroboration and not evidence that multiplies.
/// The day-count floor is never bypassed: replication can lift a finding
/// from low to medium, but nothing lifts a finding that has not passed the
/// permutation test in this window at all.
export function confidenceFor(n: number, windows: number): Confidence {
  const base = confidenceForN(n);
  if (windows < MIN_REPLICATION_WINDOWS) return base;
  return base === "low" ? "medium" : "high";
}

function daysBetween(earlier: string, later: string): number {
  const a = Date.parse(`${earlier}T00:00:00Z`);
  const b = Date.parse(`${later}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

/// How many earlier runs count as separate evidence, given that this run is
/// happening on `today`.
///
/// Greedy from the most recent backwards: a run counts only if it is at
/// least `gapDays` from the last run already counted (starting from today).
/// A month of nightly runs that all found the same thing therefore counts as
/// one or two windows, not thirty — which is the point. Returns the count of
/// PRIOR windows; the caller adds the current one.
export function independentPriorWindows(
  priorRunDates: string[],
  today: string,
  gapDays = MIN_REPLICATION_GAP_DAYS,
): number {
  const newestFirst = [...new Set(priorRunDates)].sort().reverse();
  let anchor = today;
  let count = 0;
  for (const d of newestFirst) {
    // Guard against a future-dated row (clock skew) counting as separate.
    if (daysBetween(d, anchor) >= gapDays) {
      count++;
      anchor = d;
    }
  }
  return count;
}

// ─── Candidates ─────────────────────────────────────────────────────────────

export type Group = { n: number; meanFeature: number; meanSignal: number };

export type Candidate = {
  /// Short handle the model cites so a claim can be traced to its numbers.
  id: string;
  /// Stable identity of the association, independent of wording. This is the
  /// dedupe key — a rephrased repeat of a surfaced finding collides here.
  patternKey: string;
  feature: FeatureKey;
  signal: SignalKey;
  featureLabel: string;
  signalLabel: string;
  lagDays: 0 | 1;
  n: number;
  rho: number;
  pValue: number;
  low: Group;
  high: Group;
  /// Separate windows this association has now held across, counting this
  /// run — 1 for a first sighting. See independentPriorWindows.
  windows: number;
  confidence: Confidence;
  /// The published finding covering this pairing, if there is one. Joined
  /// verbatim into the stored insight by index.ts — the model is never
  /// given a channel through which to write or paraphrase it.
  evidence?: EvidenceRow;
  /// Whether this person's data points the way the literature does. Never
  /// used to suppress a candidate; see agreementWith in evidence.ts.
  agreement: Agreement;
};

/// One association as it was measured this run, survivor or not. Recorded in
/// pattern_history so a later run can tell a pattern that keeps holding from
/// one that cleared the bar once. The rejected rows are the denominator: with
/// only survivors on file, "how often does a finding replicate" is
/// unanswerable.
export type TestedAssociation = {
  patternKey: string;
  feature: FeatureKey;
  signal: SignalKey;
  lagDays: 0 | 1;
  n: number;
  rho: number;
  pValue: number;
  survivedFdr: boolean;
};

function nextDay(day: string): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

function mean(xs: number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

/// Median split on the feature, so the evidence line can say "the 6 latest
/// dinners vs the 9 earlier ones" rather than quoting a correlation
/// coefficient at someone eating breakfast.
function splitGroups(pairs: { f: number; s: number }[]): { low: Group; high: Group } | null {
  const sorted = [...pairs].sort((a, b) => a.f - b.f);
  const mid = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 === 0
    ? (sorted[mid - 1].f + sorted[mid].f) / 2
    : sorted[mid].f;

  const low = pairs.filter((p) => p.f <= median);
  const high = pairs.filter((p) => p.f > median);
  // Every value identical (or all on one side of the median) — nothing to compare.
  if (low.length === 0 || high.length === 0) return null;

  return {
    low: { n: low.length, meanFeature: mean(low.map((p) => p.f)), meanSignal: mean(low.map((p) => p.s)) },
    high: { n: high.length, meanFeature: mean(high.map((p) => p.f)), meanSignal: mean(high.map((p) => p.s)) },
  };
}

/// Whether a feature has enough days on both sides of "present" to support
/// a comparison. Only bites on zero-inflated features: for a continuous one
/// like total calories, every day is non-zero and the absent-side test is
/// vacuous, so the guard passes on the `zero === 0` short-circuit.
export function hasVariantContrast(values: number[], min = MIN_VARIANT_DAYS): boolean {
  let zero = 0;
  let nonZero = 0;
  for (const v of values) {
    if (v === 0) zero++;
    else nonZero++;
  }
  // No zeros at all — a continuous feature, nothing for this guard to say.
  if (zero === 0) return true;
  return zero >= min && nonZero >= min;
}

/// Everything one run measured. `tested` is the full record for
/// pattern_history; `candidates` is the shortlist the model gets.
export type ScoredWindow = {
  tested: TestedAssociation[];
  candidates: Candidate[];
};

/// Test each allowlisted PAIRINGS entry at lag 0 and lag 1, keep the ones
/// that survive the permutation test after FDR correction, collapse to one
/// lag per pairing, and return the strongest MAX_CANDIDATES of those —
/// alongside the full tested set, whether it survived or not.
///
/// `priorWindows` maps a pattern_key to how many earlier, non-overlapping
/// runs it already survived (from pattern_history). It changes only the
/// confidence tier and what the model is told; it never changes which
/// associations are tested, their p-values, or what clears the correction.
/// Learning here accumulates evidence — it does not lower the bar.
export function scoreAssociations(
  meals: MealRow[],
  checkins: CheckinRow[],
  health: HealthDayRow[],
  opts: {
    permutations?: number;
    q?: number;
    max?: number;
    priorWindows?: Map<string, number>;
    /// Test seam only. Production always runs weighted; this exists so the
    /// FDR validation harness can measure the weighted and unweighted
    /// procedures against the same synthetic windows.
    weighted?: boolean;
  } = {},
): ScoredWindow {
  const permutations = opts.permutations ?? PERMUTATIONS;
  const q = opts.q ?? FDR_Q;
  const max = opts.max ?? MAX_CANDIDATES;
  const priorWindows = opts.priorWindows ?? new Map<string, number>();
  const weighted = opts.weighted ?? true;

  const features = buildDayFeatures(meals);
  const signals = buildDaySignals(checkins, health);

  type Raw = Omit<Candidate, "id" | "confidence">;
  const raw: Raw[] = [];

  for (const [feature, signal] of PAIRINGS) {
    for (const lagDays of [0, 1] as const) {
      const pairs: { f: number; s: number }[] = [];
      for (const [day, f] of features) {
        const fv = f[feature];
        if (fv === undefined) continue;
        const sv = signals.get(lagDays === 0 ? day : nextDay(day))?.[signal];
        if (sv === undefined) continue;
        pairs.push({ f: fv, s: sv });
      }
      if (pairs.length < MIN_PAIR_DAYS) continue;

      const fs = pairs.map((p) => p.f);
      const ss = pairs.map((p) => p.s);
      // A constant feature or signal has no association to measure.
      if (new Set(fs).size < 2 || new Set(ss).size < 2) continue;
      // Zero-inflated features (evening alcohol, late caffeine) clear that
      // guard on two drinking nights in a month. Require real contrast on
      // both sides before reading anything into the correlation.
      if (!hasVariantContrast(fs)) continue;

      const groups = splitGroups(pairs);
      if (groups === null) continue;

      const rho = spearman(fs, ss);
      const pValue = permutationP(fs, ss, rho, permutations);
      const patternKey = `${feature}_x_${signal}_lag${lagDays}`;
      const row = evidenceFor(feature, signal);

      raw.push({
        patternKey,
        windows: 1 + (priorWindows.get(patternKey) ?? 0),
        feature,
        signal,
        featureLabel: FEATURE_LABELS[feature],
        signalLabel: SIGNAL_LABELS[signal],
        lagDays,
        n: pairs.length,
        rho,
        pValue,
        low: groups.low,
        high: groups.high,
        evidence: row,
        agreement: agreementWith(row, rho, lagDays),
      });
    }
  }

  // Correct across every pairing we tested, including both lags. Collapsing
  // lags first would mean correcting for ~48 tests after looking at ~96.
  //
  // Weighted, so the six evidence-backed pairings added alongside caffeine
  // and alcohol do not tax the ones that were already here. The weights come
  // from evidence.ts and cannot be influenced by this user's data — that
  // independence is what keeps the FDR guarantee intact.
  const keep = weighted
    ? weightedBenjaminiHochberg(
      raw.map((r) => r.pValue),
      raw.map((r) => priorWeight(r.feature, r.signal, r.lagDays)),
      q,
    )
    : benjaminiHochberg(raw.map((r) => r.pValue), q);

  // The full record goes to pattern_history before any thinning: the lag and
  // restatement collapses below are editorial (they stop the feed saying one
  // thing twice), and a pattern dropped for restating a stronger one still
  // held tonight. Forgetting that would understate its replication later.
  const tested: TestedAssociation[] = raw.map((r, i) => ({
    patternKey: r.patternKey,
    feature: r.feature,
    signal: r.signal,
    lagDays: r.lagDays,
    n: r.n,
    rho: r.rho,
    pValue: r.pValue,
    survivedFdr: keep[i],
  }));

  // Strength first, then a published prior as the tie-break: between two
  // equally strong associations, the one the literature already recognises
  // is the better thing to lead with. Deliberately only a tie-break —
  // letting evidence outrank strength would quietly demote what this
  // person's own data says loudest, which is the wrong way round.
  const survivors = strongestLagPerPairing(raw.filter((_, i) => keep[i]))
    .sort((a, b) => {
      const byStrength = Math.abs(b.rho) - Math.abs(a.rho);
      if (byStrength !== 0) return byStrength;
      return corroborationRank(a) - corroborationRank(b);
    });

  const candidates = dropRestatements(survivors, features)
    .slice(0, max)
    .map((r, i) => ({ ...r, id: `c${i + 1}`, confidence: confidenceFor(r.n, r.windows) }));

  return { tested, candidates };
}

/// How closely two food features track each other for THIS person, over the
/// days where both are known.
export function featureSeriesRho(
  features: Map<string, DayFeatures>,
  a: FeatureKey,
  b: FeatureKey,
): number {
  const xs: number[] = [];
  const ys: number[] = [];
  for (const f of features.values()) {
    const av = f[a];
    const bv = f[b];
    if (av === undefined || bv === undefined) continue;
    xs.push(av);
    ys.push(bv);
  }
  // Too little overlap to judge; treat them as distinct rather than
  // suppressing a finding on thin evidence.
  if (xs.length < MIN_PAIR_DAYS) return 0;
  return spearman(xs, ys);
}

/// Walk strongest-first and drop anything that restates a finding already
/// kept about the same signal at the same lag.
///
/// Same lag is required: "later dinners, lower energy next day" and
/// "later dinners, lower energy same day" are different statements even
/// though the feature is identical, and `strongestLagPerPairing` already
/// handles that case. This is only about two different features saying one
/// thing.
export function dropRestatements<T extends { feature: FeatureKey; signal: SignalKey; lagDays: 0 | 1 }>(
  ranked: T[],
  features: Map<string, DayFeatures>,
): T[] {
  const kept: T[] = [];
  for (const c of ranked) {
    const restatesAKeptOne = kept.some((k) =>
      k.signal === c.signal &&
      k.lagDays === c.lagDays &&
      Math.abs(featureSeriesRho(features, k.feature, c.feature)) >= REDUNDANT_FEATURE_RHO
    );
    if (!restatesAKeptOne) kept.push(c);
  }
  return kept;
}

/// Keep one lag per (feature, signal). When someone's routine has any
/// periodicity — alternating late and early dinners, a weekday/weekend
/// rhythm — the same feature is genuinely associated with the same signal
/// at BOTH lags, in opposite directions. Both are real, and surfacing both
/// reads as the app contradicting itself ("later dinners give you more
/// energy today and less tomorrow"). Keep the stronger one.
function strongestLagPerPairing<T extends { feature: FeatureKey; signal: SignalKey; rho: number; pValue: number; lagDays: 0 | 1 }>(
  cands: T[],
): T[] {
  const best = new Map<string, T>();
  for (const c of cands) {
    const pairing = `${c.feature}_x_${c.signal}`;
    const held = best.get(pairing);
    if (held === undefined || beats(c, held)) best.set(pairing, c);
  }
  return [...best.values()];
}

/// Sort key for the corroboration tie-break: agreeing with the literature
/// leads, no prior sits in the middle, disagreeing goes last. Ordering only —
/// a contradicting finding is still shown, and still shown honestly.
function corroborationRank(c: { agreement: Agreement }): number {
  if (c.agreement === "corroborated") return 0;
  if (c.agreement === "no_prior") return 1;
  return 2;
}

/// Strongest association wins; ties break on p-value, then on lag so the
/// choice is deterministic rather than dependent on enumeration order.
function beats(a: { rho: number; pValue: number; lagDays: 0 | 1 }, b: { rho: number; pValue: number; lagDays: 0 | 1 }): boolean {
  const da = Math.abs(a.rho), db = Math.abs(b.rho);
  if (da !== db) return da > db;
  if (a.pValue !== b.pValue) return a.pValue < b.pValue;
  return a.lagDays < b.lagDays;
}

// ─── Prompt rendering ───────────────────────────────────────────────────────

function round(v: number, places: number): string {
  return v.toFixed(places);
}

/// One line per candidate, with both compared values pre-rounded so the
/// model can quote them verbatim instead of computing anything.
export function renderCandidates(candidates: Candidate[]): string {
  return candidates.map((c) => {
    const fd = FEATURE_DECIMALS[c.feature];
    const sd = SIGNAL_DECIMALS[c.signal];
    const when = c.lagDays === 0 ? "same day" : "next day";
    return [
      `[${c.id}] ${c.featureLabel} vs ${c.signalLabel} (${when})`,
      `n=${c.n} paired days`,
      `rho=${c.rho.toFixed(2)}`,
      // Only when there is something to say. A "1" on every line the first
      // month would read as a weakness rather than the absence of a bonus.
      ...(c.windows > 1 ? [`has held across ${c.windows} separate windows`] : []),
      `lower ${c.low.n} days averaged ${round(c.low.meanFeature, fd)} -> ${round(c.low.meanSignal, sd)}`,
      `higher ${c.high.n} days averaged ${round(c.high.meanFeature, fd)} -> ${round(c.high.meanSignal, sd)}`,
      ...renderEvidence(c),
    ].join(" | ");
  }).join("\n");
}

/// The published context for a candidate, for the model's plausibility call
/// only. It is told what the literature found and whether this person agrees
/// so it can judge how much care a finding needs — NOT so it can repeat any
/// of it. The mechanism sentence and citation the reader eventually sees are
/// joined server-side from the same evidence row, never routed through the
/// model. See the header of evidence.ts.
function renderEvidence(c: Candidate): string[] {
  if (c.evidence === undefined) {
    return ["published evidence: none for this pairing — judge it on this person's data alone"];
  }
  if (c.agreement === "no_prior") {
    // A row exists, but for the other lag. Saying "corroborated" here would
    // borrow authority the source did not lend.
    const expected = c.evidence.expectedLag === 0 ? "same day" : "next day";
    return [
      `published evidence: exists for this pairing but only ${expected} (grade ${c.evidence.grade}); it says nothing about this lag`,
    ];
  }
  const agreement = c.agreement === "corroborated"
    ? "this person's data points the SAME way"
    : "this person's data points the OPPOSITE way — say so plainly, do not split the difference";
  return [
    `published evidence (grade ${c.evidence.grade}): expects ${c.evidence.direction}; ${c.evidence.magnitude} [${agreement}]`,
  ];
}
