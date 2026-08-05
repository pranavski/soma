// Candidate association finding for generate-insights.
//
// Pure functions only — no fetch, no Deno.env — so they can be unit-tested
// (see candidates_test.ts) without serving the function.
//
// This module owns every number the app ever shows a person. It derives
// per-day food features, pairs each against every body signal at lag 0 and
// lag 1, ranks the associations by Spearman rho, and keeps only the ones
// that survive a permutation test with a Benjamini-Hochberg correction for
// having looked at ~100 of them.
//
// The model never does arithmetic. It receives this table and decides which
// rows are worth saying out loud, then writes the sentence. Anything it
// claims can be traced back to a row here by candidate id.

import { type CheckinRow, type HealthDayRow, type MealRow, dayOfMeal, hourOfMeal } from "./digest.ts";

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
export const FDR_Q = 0.10;

/// Ceiling on how many candidates the model is shown. Ranked by |rho|.
export const MAX_CANDIDATES = 20;

/// Permutation iterations per candidate. ~100 candidates x 2000 shuffles of
/// <=30 points is a few hundred milliseconds — cheap enough to run inline,
/// and it avoids assuming a t-distribution at n=5.
export const PERMUTATIONS = 2000;

// ─── Feature and signal definitions ─────────────────────────────────────────

export type FeatureKey =
  | "total_kcal"
  | "total_protein_g"
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
  first_meal_hour: 1,
  last_meal_hour: 1,
  eating_window_h: 1,
  meal_count: 1,
};

export const FEATURE_KEYS = Object.keys(FEATURE_LABELS) as FeatureKey[];
export const SIGNAL_KEYS = Object.keys(SIGNAL_LABELS) as SignalKey[];

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

    out.set(day, f);
  }
  return out;
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

export function spearman(xs: number[], ys: number[]): number {
  return pearson(rank(xs), rank(ys));
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

/// Confidence is derived from the number of supporting days, never
/// self-reported by the model. Thresholds match the insight-rules skill.
export function confidenceForN(n: number): "low" | "medium" | "high" {
  if (n >= 8) return "high";
  if (n >= 6) return "medium";
  return "low";
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
  confidence: "low" | "medium" | "high";
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

/// Enumerate every food-feature x body-signal pairing at lag 0 and lag 1,
/// keep the ones that survive the permutation test after FDR correction,
/// and return the strongest MAX_CANDIDATES of those.
export function buildCandidates(
  meals: MealRow[],
  checkins: CheckinRow[],
  health: HealthDayRow[],
  opts: { permutations?: number; q?: number; max?: number } = {},
): Candidate[] {
  const permutations = opts.permutations ?? PERMUTATIONS;
  const q = opts.q ?? FDR_Q;
  const max = opts.max ?? MAX_CANDIDATES;

  const features = buildDayFeatures(meals);
  const signals = buildDaySignals(checkins, health);

  type Raw = Omit<Candidate, "id" | "confidence">;
  const raw: Raw[] = [];

  for (const feature of FEATURE_KEYS) {
    for (const signal of SIGNAL_KEYS) {
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

        const groups = splitGroups(pairs);
        if (groups === null) continue;

        const rho = spearman(fs, ss);
        const pValue = permutationP(fs, ss, rho, permutations);

        raw.push({
          patternKey: `${feature}_x_${signal}_lag${lagDays}`,
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
        });
      }
    }
  }

  // Correct across every pairing we tested, including both lags. Collapsing
  // lags first would mean correcting for ~48 tests after looking at ~96.
  const keep = benjaminiHochberg(raw.map((r) => r.pValue), q);

  return strongestLagPerPairing(raw.filter((_, i) => keep[i]))
    .sort((a, b) => Math.abs(b.rho) - Math.abs(a.rho))
    .slice(0, max)
    .map((r, i) => ({ ...r, id: `c${i + 1}`, confidence: confidenceForN(r.n) }));
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
      `lower ${c.low.n} days averaged ${round(c.low.meanFeature, fd)} -> ${round(c.low.meanSignal, sd)}`,
      `higher ${c.high.n} days averaged ${round(c.high.meanFeature, fd)} -> ${round(c.high.meanSignal, sd)}`,
    ].join(" | ");
  }).join("\n");
}
