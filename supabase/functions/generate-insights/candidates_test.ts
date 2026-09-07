import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type CheckinRow, type HealthDayRow, type MealRow } from "./digest.ts";
import {
  FEATURE_KEYS,
  PAIRINGS,
  SIGNAL_KEYS,
  MIN_REPLICATION_GAP_DAYS,
  benjaminiHochberg,
  buildDayFeatures,
  dropRestatements,
  featureSeriesRho,
  buildDaySignals,
  confidenceFor,
  confidenceForN,
  independentPriorWindows,
  permutationP,
  rank,
  renderCandidates,
  scoreAssociations,
  spearman,
  MIN_VARIANT_DAYS,
  hasVariantContrast,
  weightedBenjaminiHochberg,
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

Deno.test("spearman never escapes [-1, 1] through float error", () => {
  // pattern_history has a check constraint on rho; 1 + 2e-16 from a ratio of
  // floating-point sums would cost a run its whole memory of that night.
  for (let n = 4; n <= 40; n++) {
    const xs = Array.from({ length: n }, (_, i) => i * 1.1);
    const asc = xs.map((x) => x * 7919 + 0.3);
    const desc = [...asc].reverse();
    assert(spearman(xs, asc) <= 1, `n=${n} exceeded +1`);
    assert(spearman(xs, desc) >= -1, `n=${n} exceeded -1`);
  }
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

// ─── replication ────────────────────────────────────────────────────────────

Deno.test("independentPriorWindows does not count overlapping runs", () => {
  // A pattern found every night for a fortnight is one observation seen
  // fourteen times — consecutive 30-day windows share 29 of their days.
  const nightly = Array.from({ length: 14 }, (_, i) => day(16 + i)); // ..to day 29
  assertEquals(independentPriorWindows(nightly, day(30)), 0);
});

Deno.test("independentPriorWindows counts runs a gap apart, greedily", () => {
  const today = day(60);
  assertEquals(independentPriorWindows([day(45)], today), 1);
  assertEquals(independentPriorWindows([day(45), day(30)], today), 2);
  // day(50) is inside the gap from today and does not reset the anchor, so
  // day(45) still counts from today and day(30) still counts from day(45).
  assertEquals(independentPriorWindows([day(50), day(45), day(30)], today), 2);
  // Exactly at the boundary counts; one day short does not.
  assertEquals(independentPriorWindows([day(60 - MIN_REPLICATION_GAP_DAYS)], today), 1);
  assertEquals(independentPriorWindows([day(60 - MIN_REPLICATION_GAP_DAYS + 1)], today), 0);
  assertEquals(independentPriorWindows([], today), 0);
});

Deno.test("independentPriorWindows ignores duplicate and future run dates", () => {
  const today = day(60);
  assertEquals(independentPriorWindows([day(40), day(40), day(40)], today), 1);
  // Clock skew must not manufacture a second window out of one run.
  assertEquals(independentPriorWindows([day(70)], today), 0);
});

Deno.test("confidenceFor promotes at most one tier, and only on replication", () => {
  // A single window is exactly the old behaviour.
  assertEquals(confidenceFor(4, 1), confidenceForN(4));
  assertEquals(confidenceFor(6, 1), confidenceForN(6));
  assertEquals(confidenceFor(8, 1), confidenceForN(8));

  assertEquals(confidenceFor(4, 2), "medium");
  assertEquals(confidenceFor(6, 2), "high");
  // Windows corroborate; they do not compound. Five agreeing windows say the
  // same thing as two, because they are only nearly independent.
  assertEquals(confidenceFor(4, 5), "medium");
  assertEquals(confidenceFor(8, 9), "high");
});

// ─── scoreAssociations ──────────────────────────────────────────────────────

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

Deno.test("scoreAssociations finds a planted association and scores it", () => {
  const { meals, checkins, health } = plantedWindow();
  const cands = scoreAssociations(meals, checkins, health).candidates;

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

Deno.test("PAIRINGS is an allowlist, not the cross-product", () => {
  // Every extra hypothesis tightens the FDR threshold for all the others,
  // so this list staying short is load-bearing, not tidiness.
  assert(PAIRINGS.length < FEATURE_KEYS.length * SIGNAL_KEYS.length / 2,
    `${PAIRINGS.length} pairings is approaching the ${FEATURE_KEYS.length * SIGNAL_KEYS.length} cross-product`);

  const seen = new Set(PAIRINGS.map(([f, s]) => `${f}_x_${s}`));
  assertEquals(seen.size, PAIRINGS.length, "duplicate pairing");

  for (const [f, s] of PAIRINGS) {
    assert(FEATURE_KEYS.includes(f), `unknown feature ${f}`);
    assert(SIGNAL_KEYS.includes(s), `unknown signal ${s}`);
  }
});

Deno.test("scoreAssociations never returns a pairing outside the allowlist", () => {
  const { meals, checkins, health } = plantedWindow();
  const allowed = new Set(PAIRINGS.map(([f, s]) => `${f}_x_${s}`));
  for (const c of scoreAssociations(meals, checkins, health).candidates) {
    assert(allowed.has(`${c.feature}_x_${c.signal}`), `${c.patternKey} is not allowlisted`);
  }
});

Deno.test("scoreAssociations keeps only the stronger lag per feature/signal pairing", () => {
  // plantedWindow alternates dinner time every day, so same-day energy is
  // necessarily anti-correlated with same-day dinner hour while next-day
  // energy is correlated with it. Both associations are real; surfacing
  // both would read as the app contradicting itself.
  const { meals, checkins, health } = plantedWindow();
  const cands = scoreAssociations(meals, checkins, health).candidates;

  const pairings = cands.map((c) => `${c.feature}_x_${c.signal}`);
  assertEquals(pairings.length, new Set(pairings).size, "a pairing appeared at both lags");

  const lastMealEnergy = cands.filter((c) => c.feature === "last_meal_hour" && c.signal === "energy");
  assertEquals(lastMealEnergy.length, 1);
});

// ─── redundancy ─────────────────────────────────────────────────────────────

Deno.test("featureSeriesRho measures how closely two features track for this person", () => {
  // Fixed breakfast: eating window is dinner hour minus a constant.
  const fixed = buildDayFeatures([0, 1, 2, 3, 4, 5].flatMap((i) => [
    meal({ eaten_date: day(i), eaten_hour: 8 }),
    meal({ eaten_date: day(i), eaten_hour: 17 + i }),
  ]));
  assertAlmostEquals(featureSeriesRho(fixed, "last_meal_hour", "eating_window_h"), 1, 1e-9);

  // Breakfast that moves opposite to dinner: the window is its own thing.
  const varying = buildDayFeatures([0, 1, 2, 3, 4, 5].flatMap((i) => [
    meal({ eaten_date: day(i), eaten_hour: 11 - i }),
    meal({ eaten_date: day(i), eaten_hour: 18 + (i % 2) }),
  ]));
  assert(
    Math.abs(featureSeriesRho(varying, "last_meal_hour", "eating_window_h")) < 0.7,
    "a varying breakfast should decouple the eating window from dinner hour",
  );
});

Deno.test("featureSeriesRho reports no relationship on too little overlap", () => {
  // Below MIN_PAIR_DAYS we must not suppress a finding on thin evidence.
  const thin = buildDayFeatures([0, 1].flatMap((i) => [
    meal({ eaten_date: day(i), eaten_hour: 8 }),
    meal({ eaten_date: day(i), eaten_hour: 19 + i }),
  ]));
  assertEquals(featureSeriesRho(thin, "last_meal_hour", "eating_window_h"), 0);
});

Deno.test("dropRestatements keeps the strongest of a restating group", () => {
  const features = buildDayFeatures([0, 1, 2, 3, 4, 5].flatMap((i) => [
    meal({ eaten_date: day(i), eaten_hour: 8 }),
    meal({ eaten_date: day(i), eaten_hour: 17 + i }),
  ]));
  const strong = { feature: "last_meal_hour", signal: "energy", lagDays: 1 } as const;
  const restatement = { feature: "eating_window_h", signal: "energy", lagDays: 1 } as const;
  const otherSignal = { feature: "eating_window_h", signal: "sleep_minutes", lagDays: 1 } as const;
  const otherLag = { feature: "eating_window_h", signal: "energy", lagDays: 0 } as const;

  // Ranked strongest-first, as buildCandidates hands them over.
  assertEquals(
    dropRestatements([strong, restatement], features),
    [strong],
  );
  // A different signal is a different finding, however alike the features.
  assertEquals(
    dropRestatements([strong, otherSignal], features).length,
    2,
  );
  // So is a different lag — that case belongs to strongestLagPerPairing.
  assertEquals(
    dropRestatements([strong, otherLag], features).length,
    2,
  );
});

Deno.test("scoreAssociations does not surface a feature that restates a stronger one", () => {
  // plantedWindow holds breakfast at 08h, so eating window and last-meal
  // hour are the same fact. Only one may reach the feed.
  const { meals, checkins, health } = plantedWindow();
  const againstEnergy = scoreAssociations(meals, checkins, health).candidates
    .filter((c) => c.signal === "energy")
    .map((c) => c.feature);
  const timing = againstEnergy.filter((f) => f === "last_meal_hour" || f === "eating_window_h");
  assertEquals(timing.length, 1, `both timing features surfaced: ${againstEnergy.join(", ")}`);
});

Deno.test("scoreAssociations assigns contiguous ids ranked by |rho|", () => {
  const { meals, checkins, health } = plantedWindow();
  const cands = scoreAssociations(meals, checkins, health).candidates;
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

/// 30 days where nothing is related to anything.
function noiseWindow(): { meals: MealRow[]; checkins: CheckinRow[]; health: HealthDayRow[] } {
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
  return { meals, checkins, health };
}

Deno.test("scoreAssociations finds nothing in pure noise", () => {
  // ~100 associations tested against 30 days of unrelated data. Without the
  // FDR correction this is where the engine would invent a finding a night.
  const { meals, checkins, health } = noiseWindow();
  assertEquals(scoreAssociations(meals, checkins, health).candidates, []);
});

// ─── the tested record (pattern_history) ────────────────────────────────────

Deno.test("scoreAssociations reports every association it tested, rejects included", () => {
  // A night that surfaces nothing still measured ~28 things, and those
  // rejections are what a replication rate is later measured against.
  const noise = noiseWindow();
  const { tested, candidates } = scoreAssociations(noise.meals, noise.checkins, noise.health);
  assertEquals(candidates, []);
  assert(tested.length > 0, "a run that found nothing still tested something");
  assertFalse(tested.some((t) => t.survivedFdr));

  const keys = tested.map((t) => t.patternKey);
  assertEquals(keys.length, new Set(keys).size, "one row per pattern per run");
  for (const t of tested) {
    assertEquals(t.patternKey, `${t.feature}_x_${t.signal}_lag${t.lagDays}`);
    assert(t.n >= 4 && t.pValue > 0 && t.pValue <= 1, JSON.stringify(t));
  }
});

Deno.test("the tested record keeps a pattern the shortlist drops for restating another", () => {
  // plantedWindow fixes breakfast at 08h, so eating window restates dinner
  // hour and one of them never reaches the model. It still held tonight, and
  // forgetting that would understate its replication later.
  const { meals, checkins, health } = plantedWindow();
  const { tested, candidates } = scoreAssociations(meals, checkins, health);

  const surfaced = new Set(candidates.map((c) => c.patternKey));
  const survived = tested.filter((t) => t.survivedFdr).map((t) => t.patternKey);
  assert(
    survived.some((k) => !surfaced.has(k)),
    "expected a survivor thinned out of the shortlist",
  );
  for (const key of surfaced) assert(survived.includes(key), `${key} surfaced without surviving`);
});

Deno.test("prior windows change confidence and copy, never the statistics", () => {
  const { meals, checkins, health } = plantedWindow();
  const planted = "last_meal_hour_x_energy_lag1";

  const first = scoreAssociations(meals, checkins, health);
  const replicated = scoreAssociations(meals, checkins, health, {
    priorWindows: new Map([[planted, 2]]),
  });

  // Same data, same numbers. Replication is allowed to raise a tier and to
  // inform the model's choice; it may never move a p-value or let something
  // through the correction that would not have passed on its own.
  assertEquals(replicated.tested, first.tested);
  assertEquals(
    replicated.candidates.map((c) => [c.patternKey, c.n, c.rho, c.pValue]),
    first.candidates.map((c) => [c.patternKey, c.n, c.rho, c.pValue]),
  );

  assertEquals(first.candidates.find((c) => c.patternKey === planted)!.windows, 1);
  assertEquals(replicated.candidates.find((c) => c.patternKey === planted)!.windows, 3);
  // Unmentioned patterns stay first sightings.
  for (const c of replicated.candidates) {
    if (c.patternKey !== planted) assertEquals(c.windows, 1);
  }
});

Deno.test("scoreAssociations skips pairings below MIN_PAIR_DAYS", () => {
  // Three days of data cannot produce any candidate, however clean.
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  for (let i = 0; i < 3; i++) {
    meals.push(meal({ eaten_date: day(i), eaten_hour: 18 + i }));
    checkins.push({ check_date: day(i), energy: 5 - i });
  }
  assertEquals(scoreAssociations(meals, checkins, []).candidates, []);
});

Deno.test("scoreAssociations ignores a constant signal", () => {
  // Energy pinned at 3 every day — no association exists to find.
  const meals: MealRow[] = [];
  const checkins: CheckinRow[] = [];
  for (let i = 0; i < 20; i++) {
    meals.push(meal({ eaten_date: day(i), eaten_hour: 17 + (i % 6) }));
    checkins.push({ check_date: day(i), energy: 3 });
  }
  assertFalse(scoreAssociations(meals, checkins, []).candidates.some((c) => c.signal === "energy"));
});

// ─── renderCandidates ───────────────────────────────────────────────────────

Deno.test("renderCandidates gives the model pre-rounded numbers to quote", () => {
  const { meals, checkins, health } = plantedWindow();
  const cands = scoreAssociations(meals, checkins, health).candidates;
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

Deno.test("renderCandidates mentions replication only when there is some", () => {
  const { meals, checkins, health } = plantedWindow();
  const planted = "last_meal_hour_x_energy_lag1";

  // A first sighting says nothing about windows — "1 window" on every line
  // for a new user's whole first month would read as a weakness.
  const first = scoreAssociations(meals, checkins, health).candidates;
  assertFalse(renderCandidates(first).includes("separate windows"));

  const replicated = scoreAssociations(meals, checkins, health, {
    priorWindows: new Map([[planted, 2]]),
  }).candidates;
  const line = renderCandidates(replicated).split("\n")
    .find((l) => l.includes("hour of last meal") && l.includes("next day"))!;
  assert(line.includes("has held across 3 separate windows"), line);
});

// ─── weighted Benjamini-Hochberg ────────────────────────────────────────────

Deno.test("weightedBenjaminiHochberg with equal weights is plain BH", () => {
  const ps = [0.001, 0.02, 0.04, 0.3, 0.7];
  const flat = new Array(ps.length).fill(1);
  assertEquals(weightedBenjaminiHochberg(ps, flat), benjaminiHochberg(ps));
  // Any constant weight, not just 1 — normalisation divides it out.
  assertEquals(weightedBenjaminiHochberg(ps, new Array(ps.length).fill(7)), benjaminiHochberg(ps));
});

Deno.test("weightedBenjaminiHochberg normalises weights to mean 1", () => {
  // A table whose weights all exceeded 1 must NOT silently run at a looser
  // q. If normalisation were skipped, every hypothesis here would clear a
  // threshold 3x wider than the one the caller asked for.
  const ps = [0.03, 0.2, 0.5];
  const inflated = [3, 3, 3];
  assertEquals(weightedBenjaminiHochberg(ps, inflated), benjaminiHochberg(ps));
});

Deno.test("weight moves a hypothesis across the threshold, in both directions", () => {
  // p=0.04 sits just outside plain BH at q=0.10 with 3 hypotheses.
  const ps = [0.04, 0.6, 0.9];
  assertFalse(benjaminiHochberg(ps)[0]);
  // Prioritised: now clears.
  assert(weightedBenjaminiHochberg(ps, [2.0, 0.5, 0.5])[0]);
  // Deprioritised: the borderline one is pushed further out.
  assertFalse(weightedBenjaminiHochberg(ps, [0.5, 1.75, 1.75])[0]);
});

Deno.test("weightedBenjaminiHochberg is defensive about degenerate input", () => {
  assertEquals(weightedBenjaminiHochberg([], []), []);
  // All-zero weights carry no information — fall back rather than divide by 0.
  const ps = [0.001, 0.5];
  assertEquals(weightedBenjaminiHochberg(ps, [0, 0]), benjaminiHochberg(ps));
});

Deno.test("weightedBenjaminiHochberg rejects misaligned weights", () => {
  let threw = false;
  try {
    weightedBenjaminiHochberg([0.1, 0.2], [1]);
  } catch {
    threw = true;
  }
  assert(threw, "a weights/pValues length mismatch must fail loudly, not silently mis-weight");
});

// ─── zero-inflation guard ───────────────────────────────────────────────────

Deno.test("hasVariantContrast ignores continuous features", () => {
  // No zeros at all — the guard has nothing to say about total calories.
  assert(hasVariantContrast([1800, 2200, 1950, 2400]));
});

Deno.test("hasVariantContrast requires real contrast on both sides", () => {
  const zeros = new Array(22).fill(0);
  // Two drinking nights in a month: two distinct values, but nothing to
  // compare. This is the case the plain "at least 2 distinct values" guard
  // let through.
  assertFalse(hasVariantContrast([...zeros, 14, 20]));
  assert(hasVariantContrast([...zeros, 14, 20, 18]));
  assertEquals(MIN_VARIANT_DAYS, 3);
  // And the mirror image: mostly non-zero with too few zero days.
  assertFalse(hasVariantContrast([0, 0, 12, 14, 16, 18, 20, 22]));
});
