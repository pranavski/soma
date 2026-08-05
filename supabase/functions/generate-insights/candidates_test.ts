import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type CheckinRow, type HealthDayRow, type MealRow } from "./digest.ts";
import {
  benjaminiHochberg,
  buildCandidates,
  buildDayFeatures,
  buildDaySignals,
  confidenceForN,
  permutationP,
  rank,
  renderCandidates,
  spearman,
} from "./candidates.ts";

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

/// "2026-07-01" + n days.
function day(n: number): string {
  const d = new Date("2026-07-01T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// ─── rank / spearman ────────────────────────────────────────────────────────

Deno.test("rank averages ties", () => {
  assertEquals(rank([10, 20, 30]), [1, 2, 3]);
  assertEquals(rank([10, 10, 30]), [1.5, 1.5, 3]);
  assertEquals(rank([5, 5, 5, 5]), [2.5, 2.5, 2.5, 2.5]);
  assertEquals(rank([30, 10, 20]), [3, 1, 2]);
});

Deno.test("spearman is +1 / -1 on monotone data and ~0 on none", () => {
  assertAlmostEquals(spearman([1, 2, 3, 4], [10, 20, 30, 40]), 1, 1e-9);
  // Monotone but not linear — Spearman still reads 1 where Pearson would not.
  assertAlmostEquals(spearman([1, 2, 3, 4], [1, 4, 90, 10000]), 1, 1e-9);
  assertAlmostEquals(spearman([1, 2, 3, 4], [40, 30, 20, 10]), -1, 1e-9);
  assertEquals(spearman([1, 1, 1, 1], [4, 2, 7, 1]), 0); // constant → no association
});

// ─── permutationP ───────────────────────────────────────────────────────────

Deno.test("permutationP is small for a perfect association, large for noise", () => {
  const xs = [1, 2, 3, 4, 5, 6, 7, 8];
  const perfect = [1, 2, 3, 4, 5, 6, 7, 8];
  assert(permutationP(xs, perfect, spearman(xs, perfect)) < 0.01);

  const shuffled = [5, 1, 8, 3, 7, 2, 6, 4];
  assert(permutationP(xs, shuffled, spearman(xs, shuffled)) > 0.2);
});

Deno.test("permutationP floors out at tiny n — n=4 can never look significant", () => {
  // 4! = 24 orderings, so the smallest attainable two-tailed p is ~2/24.
  // This is why MIN_PAIR_DAYS=4 does not by itself let thin data through.
  const xs = [1, 2, 3, 4];
  const ys = [1, 2, 3, 4];
  assert(permutationP(xs, ys, spearman(xs, ys)) > 0.05);
});

Deno.test("permutationP is deterministic across runs", () => {
  const xs = [1, 2, 3, 4, 5, 6, 7];
  const ys = [2, 1, 4, 3, 6, 5, 7];
  const rho = spearman(xs, ys);
  assertEquals(permutationP(xs, ys, rho), permutationP(xs, ys, rho));
});

// ─── benjaminiHochberg ──────────────────────────────────────────────────────

Deno.test("benjaminiHochberg keeps only what survives the correction", () => {
  // A single p=0.04 among 20 tests is exactly what multiple comparisons
  // manufactures — at q=0.10 the threshold for the smallest is 0.005.
  const many = [0.04, ...Array.from({ length: 19 }, () => 0.6)];
  assertEquals(benjaminiHochberg(many, 0.10).filter(Boolean).length, 0);

  // The same p-value stands on its own when it is the only test.
  assertEquals(benjaminiHochberg([0.04], 0.10), [true]);
});

Deno.test("benjaminiHochberg is step-up, not per-test", () => {
  // p=0.05 fails its own rank-2 threshold (0.05 vs 2/4*0.1=0.05 passes
  // exactly), while a later small p can rescue earlier ones in the ordering.
  const keep = benjaminiHochberg([0.001, 0.049, 0.7, 0.8], 0.10);
  assertEquals(keep, [true, true, false, false]);
  assertEquals(benjaminiHochberg([], 0.10), []);
});

// ─── buildDayFeatures ───────────────────────────────────────────────────────

Deno.test("buildDayFeatures derives counts, hours, and the eating window", () => {
  const f = buildDayFeatures([
    meal({ eaten_date: "2026-07-18", eaten_hour: 8 }),
    meal({ eaten_date: "2026-07-18", eaten_hour: 13 }),
    meal({ eaten_date: "2026-07-18", eaten_hour: 21 }),
  ]).get("2026-07-18")!;
  assertEquals(f.meal_count, 3);
  assertEquals(f.first_meal_hour, 8);
  assertEquals(f.last_meal_hour, 21);
  assertEquals(f.eating_window_h, 13);
});

Deno.test("buildDayFeatures totals macros only when every meal is parsed", () => {
  const full = buildDayFeatures([
    meal({ eaten_date: "2026-07-18", calories_low: 200, calories_high: 300, protein_g_low: 10, protein_g_high: 20 }),
    meal({ eaten_date: "2026-07-18", calories_low: 400, calories_high: 600, protein_g_low: 30, protein_g_high: 40 }),
  ]).get("2026-07-18")!;
  assertEquals(full.total_kcal, 250 + 500);
  assertEquals(full.total_protein_g, 15 + 35);

  // One unparsed meal makes the day's total a lie — better absent than low.
  const partial = buildDayFeatures([
    meal({ eaten_date: "2026-07-18", calories_low: 200, calories_high: 300 }),
    meal({ eaten_date: "2026-07-18", dish_name: "leftovers" }),
  ]).get("2026-07-18")!;
  assertEquals(partial.total_kcal, undefined);
  assertEquals(partial.meal_count, 2);
});

// ─── buildDaySignals ────────────────────────────────────────────────────────

Deno.test("buildDaySignals merges check-ins and health rows, omitting nulls", () => {
  const s = buildDaySignals(
    [{ check_date: "2026-07-18", energy: 4 }],
    [healthDay({ day: "2026-07-18", steps: 9102, sleep_minutes: null })],
  ).get("2026-07-18")!;
  assertEquals(s.energy, 4);
  assertEquals(s.steps, 9102);
  assertEquals(s.sleep_minutes, undefined); // absent, not 0
});

// ─── confidenceForN ─────────────────────────────────────────────────────────

Deno.test("confidenceForN matches the documented tiers", () => {
  assertEquals(confidenceForN(4), "low");
  assertEquals(confidenceForN(5), "low");
  assertEquals(confidenceForN(6), "medium");
  assertEquals(confidenceForN(7), "medium");
  assertEquals(confidenceForN(8), "high");
  assertEquals(confidenceForN(30), "high");
});

// ─── buildCandidates ────────────────────────────────────────────────────────

/// 20 days where a later last meal goes with lower energy the NEXT day,
/// and nothing else is correlated with anything.
function plantedWindow(): { meals: MealRow[]; checkins: CheckinRow[]; health: HealthDayRow[] } {
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  for (let i = 0; i < 20; i++) {
    const late = i % 2 === 0;
    meals.push(meal({ eaten_date: day(i), eaten_hour: 8, dish_name: "oats" }));
    meals.push(meal({ eaten_date: day(i), eaten_hour: late ? 22 : 18, dish_name: "dinner" }));
    // Next-day energy tracks last night's dinner hour, with a little wobble.
    checkins.push({ check_date: day(i + 1), energy: late ? 2 : 4 });
  }
  return { meals, checkins, health: [] };
}

Deno.test("buildCandidates finds a planted association and scores it", () => {
  const { meals, checkins, health } = plantedWindow();
  const cands = buildCandidates(meals, checkins, health);

  const hit = cands.find((c) => c.patternKey === "last_meal_hour_x_energy_lag1");
  assert(hit !== undefined, "planted last-meal-hour → next-day energy not found");
  assertEquals(hit.n, 20);
  assert(hit.rho < -0.8, `expected a strong negative rho, got ${hit.rho}`);
  assertEquals(hit.confidence, "high");
  assertEquals(hit.lagDays, 1);
  // Median split: the later dinners sit lower on energy than the earlier ones.
  assert(hit.high.meanSignal < hit.low.meanSignal);
  assertEquals(hit.low.n + hit.high.n, 20);
});

Deno.test("buildCandidates assigns contiguous ids ranked by |rho|", () => {
  const { meals, checkins, health } = plantedWindow();
  const cands = buildCandidates(meals, checkins, health);
  assert(cands.length > 0);
  assertEquals(cands.map((c) => c.id), cands.map((_, i) => `c${i + 1}`));
  for (let i = 1; i < cands.length; i++) {
    assert(Math.abs(cands[i - 1].rho) >= Math.abs(cands[i].rho));
  }
});

/// Seeded xorshift32. Modular sequences like (i*7)%5 are NOT noise — they
/// are periodic in i, so two of them correlate with each other and the
/// engine rightly finds it. Fixtures that need noise need real noise.
function makeRng(seed: number): () => number {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 0x100000000;
  };
}

Deno.test("buildCandidates finds nothing in pure noise", () => {
  // ~100 associations tested against 30 days of unrelated data. Without the
  // FDR correction this is where the engine would invent a finding a night.
  const rng = makeRng(0xC0FFEE);
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  const health: HealthDayRow[] = [];
  for (let i = 0; i < 30; i++) {
    meals.push(meal({ eaten_date: day(i), eaten_hour: 6 + Math.floor(rng() * 5) }));
    meals.push(meal({ eaten_date: day(i), eaten_hour: 17 + Math.floor(rng() * 6) }));
    checkins.push({ check_date: day(i), energy: 1 + Math.floor(rng() * 5) });
    health.push(healthDay({
      day: day(i),
      steps: 4000 + Math.floor(rng() * 8000),
      sleep_minutes: 330 + Math.floor(rng() * 180),
      resting_hr_bpm: 55 + Math.floor(rng() * 12),
    }));
  }
  assertEquals(buildCandidates(meals, checkins, health), []);
});

Deno.test("buildCandidates skips pairings below MIN_PAIR_DAYS", () => {
  // Three days of data cannot produce any candidate, however clean.
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  for (let i = 0; i < 3; i++) {
    meals.push(meal({ eaten_date: day(i), eaten_hour: 18 + i }));
    checkins.push({ check_date: day(i), energy: 5 - i });
  }
  assertEquals(buildCandidates(meals, checkins, []), []);
});

Deno.test("buildCandidates ignores a constant signal", () => {
  // Energy pinned at 3 every day — no association exists to find.
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  for (let i = 0; i < 20; i++) {
    meals.push(meal({ eaten_date: day(i), eaten_hour: 17 + (i % 6) }));
    checkins.push({ check_date: day(i), energy: 3 });
  }
  assertFalse(buildCandidates(meals, checkins, []).some((c) => c.signal === "energy"));
});

// ─── renderCandidates ───────────────────────────────────────────────────────

Deno.test("renderCandidates gives the model pre-rounded numbers to quote", () => {
  const { meals, checkins, health } = plantedWindow();
  const cands = buildCandidates(meals, checkins, health);
  const line = renderCandidates(cands).split("\n")
    .find((l) => l.includes("hour of last meal") && l.includes("next day"))!;

  assert(line.startsWith("["), line);
  assert(line.includes("n=20 paired days"), line);
  assert(line.includes("rho="), line);
  assert(line.includes("lower 10 days averaged"), line);
  assert(line.includes("higher 10 days averaged"), line);
  // Energy is rendered to one decimal, steps to none — the model quotes
  // these verbatim, so the rounding has to happen here.
  assert(/-> \d+\.\d(?: |$)/.test(line), line);
});
