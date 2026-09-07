// Statistical re-validation of the insight engine under evidence-weighted
// Benjamini-Hochberg.
//
// The engine's tunables (FDR_Q = 0.10) are justified in candidates.ts by a
// measured "0/20 false positives, 7/20 detection" over synthetic 30-day
// windows. Adding six pairings and switching to weighted BH invalidates that
// measurement, so it has to be re-run rather than assumed.
//
// Run: deno run --allow-read fdr_validation.ts

import {
  type CheckinRow,
  type HealthDayRow,
  type MealRow,
} from "../supabase/functions/generate-insights/digest.ts";
import {
  PAIRINGS,
  scoreAssociations,
} from "../supabase/functions/generate-insights/candidates.ts";

const WINDOWS = 20;
const DAYS = 30;

function makeRng(seed: number): () => number {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 0x100000000;
  };
}

function day(n: number): string {
  const d = new Date("2026-07-01T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function meal(over: Partial<MealRow>): MealRow {
  return {
    eaten_at: "2026-07-18T15:10:00Z",
    eaten_date: "2026-07-18",
    eaten_hour: 8,
    dish_name: null,
    voice_transcript: null,
    calories_low: null,
    calories_high: null,
    protein_g_low: null,
    protein_g_high: null,
    fiber_g_low: null,
    fiber_g_high: null,
    caffeine_mg_low: null,
    caffeine_mg_high: null,
    alcohol_g_low: null,
    alcohol_g_high: null,
    ...over,
  };
}

function healthDay(over: Partial<HealthDayRow>): HealthDayRow {
  return {
    day: "2026-07-18",
    steps: null,
    sleep_minutes: null,
    resting_hr_bpm: null,
    hrv_ms: null,
    weight_kg: null,
    active_energy_kcal: null,
    workout_minutes: null,
    ...over,
  };
}

type Window = { meals: MealRow[]; checkins: CheckinRow[]; health: HealthDayRow[] };
type Effect = "none" | "late_dinner_energy" | "caffeine_sleep" | "caffeine_sleep_weak";

/// A realistic 30-day window: three logged meals a day with full nutrition,
/// coffee most mornings and sometimes late, a few drinking evenings, and the
/// body signals Soma syncs.
///
/// Everything is independent noise unless `effect` plants a relationship. It
/// matters that the *whole* feature set is populated: a window missing
/// caffeine and alcohol would only ever test the old 14 pairings, and would
/// measure a correction that no real user is subject to.
function buildWindow(seed: number, effect: Effect): Window {
  const rng = makeRng(seed);
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  const health: HealthDayRow[] = [];

  for (let i = 0; i < DAYS; i++) {
    const d = day(i);

    // Breakfast, with the morning coffee.
    meals.push(meal({
      eaten_date: d,
      eaten_hour: 7 + Math.floor(rng() * 2),
      calories_low: 300, calories_high: 450,
      protein_g_low: 15, protein_g_high: 25,
      fiber_g_low: 4 + Math.floor(rng() * 6), fiber_g_high: 10 + Math.floor(rng() * 6),
      caffeine_mg_low: 80, caffeine_mg_high: 110,
      alcohol_g_low: 0, alcohol_g_high: 0,
    }));

    // An afternoon coffee on roughly half the days — this is the feature the
    // caffeine_sleep effect acts through.
    const lateCoffee = rng() < 0.5;
    if (lateCoffee) {
      meals.push(meal({
        eaten_date: d,
        eaten_hour: 15 + Math.floor(rng() * 2),
        calories_low: 5, calories_high: 20,
        protein_g_low: 0, protein_g_high: 1,
        fiber_g_low: 0, fiber_g_high: 0,
        caffeine_mg_low: 90, caffeine_mg_high: 130,
        alcohol_g_low: 0, alcohol_g_high: 0,
      }));
    }

    // Dinner. Its hour is the late_dinner_energy driver.
    const dinnerHour = effect === "late_dinner_energy"
      ? (i % 2 === 0 ? 18 : 22)
      : 18 + Math.floor(rng() * 5);
    const drinking = rng() < 0.3;
    meals.push(meal({
      eaten_date: d,
      eaten_hour: dinnerHour,
      calories_low: 600, calories_high: 850,
      protein_g_low: 30, protein_g_high: 45,
      fiber_g_low: 5 + Math.floor(rng() * 8), fiber_g_high: 12 + Math.floor(rng() * 8),
      caffeine_mg_low: 0, caffeine_mg_high: 0,
      alcohol_g_low: drinking ? 10 : 0, alcohol_g_high: drinking ? 25 : 0,
    }));

    // Body signals. Deterministic where an effect is planted, noise otherwise.
    let energy = 1 + Math.floor(rng() * 5);
    if (effect === "late_dinner_energy" && i > 0) {
      // Yesterday's dinner drives today's energy (lag 1).
      energy = (i - 1) % 2 === 0 ? 4 : 2;
    }
    checkins.push({ check_date: d, energy });

    let sleep = 330 + Math.floor(rng() * 180);
    if (effect === "caffeine_sleep") {
      sleep = lateCoffee ? 360 + Math.floor(rng() * 20) : 460 + Math.floor(rng() * 20);
    }
    // A marginal effect: the same direction, but the two groups overlap
    // heavily. This is where a prior should earn its keep — a deterministic
    // effect clears any threshold, so it cannot distinguish the procedures.
    if (effect === "caffeine_sleep_weak") {
      sleep = (lateCoffee ? 390 : 430) + Math.floor(rng() * 90);
    }

    health.push(healthDay({
      day: d,
      steps: 4000 + Math.floor(rng() * 8000),
      sleep_minutes: sleep,
      resting_hr_bpm: 55 + Math.floor(rng() * 12),
      hrv_ms: 35 + Math.floor(rng() * 30),
      active_energy_kcal: 300 + Math.floor(rng() * 500),
      workout_minutes: Math.floor(rng() * 60),
    }));
  }

  return { meals, checkins, health };
}

function run(
  effect: Effect,
  weighted: boolean,
  windows: number,
): { hits: number; targeted: number; fired: Map<string, number> } {
  let hits = 0;
  let targeted = 0;
  const fired = new Map<string, number>();
  for (let w = 0; w < windows; w++) {
    const { meals, checkins, health } = buildWindow(0x1000 + w * 7919, effect);
    const { candidates } = scoreAssociations(meals, checkins, health, { weighted });
    if (candidates.length > 0) hits++;
    for (const c of candidates) {
      fired.set(c.patternKey, (fired.get(c.patternKey) ?? 0) + 1);
    }
    const wanted = effect === "late_dinner_energy"
      ? "last_meal_hour_x_energy_lag1"
      : "caffeine_mg_late_x_sleep_minutes_lag0";
    if (candidates.some((c) => c.patternKey === wanted)) targeted++;
  }
  return { hits, targeted, fired };
}

// 20 windows cannot tell 0% from 5%. The false-positive rate is the number
// this change must not move, so it gets a sample size that can resolve it.
const N = 300;

/// Both procedures on the SAME window, so the comparison is paired. The
/// unpaired marginals at n=100 could not separate 6% from 8%; the discordant
/// counts can, because they discard every window where the two procedures
/// agree (which is nearly all of them).
function paired(effect: Effect, windows: number, target: string) {
  let onlyUnweighted = 0;
  let onlyWeighted = 0;
  let both = 0;
  let neither = 0;
  for (let w = 0; w < windows; w++) {
    const win = buildWindow(0x1000 + w * 7919, effect);
    const hit = (weighted: boolean) => {
      const { candidates } = scoreAssociations(win.meals, win.checkins, win.health, { weighted });
      return effect === "none"
        ? candidates.length > 0
        : candidates.some((c) => c.patternKey === target);
    };
    const u = hit(false);
    const g = hit(true);
    if (u && g) both++;
    else if (u) onlyUnweighted++;
    else if (g) onlyWeighted++;
    else neither++;
  }
  return { onlyUnweighted, onlyWeighted, both, neither };
}

console.log(`pairings: ${PAIRINGS.length}  hypotheses: ${PAIRINGS.length * 2}`);
console.log(`paired windows per cell: ${N}, days per window: ${DAYS}\n`);

const cells: [string, Effect, string][] = [
  ["false positives (pure noise)", "none", ""],
  ["MARGINAL caffeine-sleep     ", "caffeine_sleep_weak", "caffeine_mg_late_x_sleep_minutes_lag0"],
];

for (const [label, effect, target] of cells) {
  const r = paired(effect, N, target);
  const unweighted = r.both + r.onlyUnweighted;
  const weighted = r.both + r.onlyWeighted;
  console.log(
    `${label} | unweighted ${unweighted}/${N} -> weighted ${weighted}/${N}` +
      ` | discordant: +${r.onlyWeighted} / -${r.onlyUnweighted}`,
  );
}
