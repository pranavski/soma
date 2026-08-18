import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type CheckinRow, type HealthDayRow, type MealRow } from "./digest.ts";
import {
  MAX_REFLECTIONS,
  MIN_REFLECTION_DAYS,
  buildReflections,
  candidateReflections,
} from "./reflections.ts";

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

function day(n: number): string {
  const d = new Date("2026-07-01T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/// `days` days of ordinary logging: breakfast, lunch, dinner, everything
/// parsed. The default shape the individual tests perturb.
function plainDays(days: number, over: (i: number) => Partial<MealRow>[] = () => []): MealRow[] {
  const meals: MealRow[] = [];
  for (let i = 0; i < days; i++) {
    const d = day(i);
    meals.push(meal({
      eaten_date: d, eaten_hour: 8, dish_name: "oats",
      calories_low: 300, calories_high: 400, protein_g_low: 10, protein_g_high: 15,
    }));
    meals.push(meal({
      eaten_date: d, eaten_hour: 13, dish_name: `lunch ${i}`,
      calories_low: 500, calories_high: 700, protein_g_low: 25, protein_g_high: 35,
    }));
    meals.push(meal({
      eaten_date: d, eaten_hour: 19 + (i % 3), dish_name: `dinner ${i}`,
      calories_low: 600, calories_high: 800, protein_g_low: 30, protein_g_high: 40,
    }));
    for (const extra of over(i)) meals.push(meal({ eaten_date: d, ...extra }));
  }
  return meals;
}

// ─── The floor ──────────────────────────────────────────────────────────────

Deno.test("says nothing below MIN_REFLECTION_DAYS", () => {
  for (let days = 0; days < MIN_REFLECTION_DAYS; days++) {
    assertEquals(candidateReflections(plainDays(days), [], []), []);
  }
  assert(buildReflections(plainDays(MIN_REFLECTION_DAYS), [], []).length > 0);
});

Deno.test("body signals alone are not enough — reflections describe the log", () => {
  // Someone who connected HealthKit but has not logged a meal has nothing
  // to reflect on yet; the app is a food-body record, not a step counter.
  const health = [0, 1, 2, 3, 4].map((i) => healthDay({ day: day(i), steps: 8000 + i }));
  assertEquals(buildReflections([], [], health), []);
});

// ─── Selection ──────────────────────────────────────────────────────────────

Deno.test("caps at MAX_REFLECTIONS with at most one per group", () => {
  // A window rich enough that every reflection could fire.
  const meals = plainDays(6, () => [
    { eaten_hour: 15, dish_name: "coffee", caffeine_mg_low: 90, caffeine_mg_high: 120, calories_low: 5, calories_high: 20, protein_g_low: 0, protein_g_high: 1 },
    { eaten_hour: 20, dish_name: "wine", alcohol_g_low: 10, alcohol_g_high: 20, calories_low: 120, calories_high: 160, protein_g_low: 0, protein_g_high: 1 },
  ]);
  const checkins: CheckinRow[] = [0, 1, 2, 3, 4, 5].map((i) => ({ check_date: day(i), energy: 3 + (i % 2) }));
  const health = [0, 1, 2, 3, 4, 5].map((i) => healthDay({
    day: day(i), steps: 6000 + i * 500, sleep_minutes: 400 + i * 10,
  }));

  const out = buildReflections(meals, checkins, health);
  assertEquals(out.length, MAX_REFLECTIONS);
  assertEquals(new Set(out.map((r) => r.group)).size, out.length);
});

Deno.test("selection is deterministic across identical runs", () => {
  const meals = plainDays(5);
  const a = buildReflections(meals, [], []);
  const b = buildReflections(meals, [], []);
  assertEquals(a, b);
});

// ─── The honesty constraint ─────────────────────────────────────────────────

Deno.test("no reflection relates a food feature to a body signal", () => {
  // The line that separates this layer from the insight engine. A
  // reflection describes one thing; the moment it puts a meal and a body
  // signal in the same sentence it is making an uncorrected claim.
  const meals = plainDays(8, () => [
    { eaten_hour: 16, dish_name: "coffee", caffeine_mg_low: 90, caffeine_mg_high: 120, calories_low: 5, calories_high: 20, protein_g_low: 0, protein_g_high: 1 },
  ]);
  const checkins: CheckinRow[] = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => ({ check_date: day(i), energy: 3 }));
  const health = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => healthDay({
    day: day(i), steps: 7000, sleep_minutes: 420,
  }));

  // Every kind, not just the three that surfaced — the group cap must not
  // be what is keeping a causal sentence off the screen.
  const banned = [
    /\bafter\b.*\benergy\b/i,
    /\bcause|makes you|leads to|because of|thanks to\b/i,
    /\bshould\b/i,
    /\bcorrelat/i,
    /\bwhen you\b/i,
  ];
  for (const r of candidateReflections(meals, checkins, health)) {
    const text = `${r.body} ${r.detail}`;
    for (const pattern of banned) {
      assertFalse(pattern.test(text), `"${text}" matched ${pattern}`);
    }
  }
});

Deno.test("calorie totals are always printed as a range", () => {
  // The hard rule, and the reason dayRangeTotals keeps low/high instead of
  // reusing buildDayFeatures' midpoints. Three identical days would collapse
  // to a single number under a midpoint sum.
  const meals: MealRow[] = [];
  for (let i = 0; i < 4; i++) {
    meals.push(meal({
      eaten_date: day(i), eaten_hour: 8, dish_name: "oats",
      calories_low: 400, calories_high: 600,
    }));
  }
  const r = candidateReflections(meals, [], []).find((x) => x.kind === "calorie_range");
  assert(r !== undefined, "expected a calorie reflection");
  assert(/~\d[\d,]*–\d[\d,]*/.test(r.body), `not a range: ${r.body}`);
  assertFalse(/~400–400|~600–600/.test(r.body));
});

Deno.test("a day with any unparsed meal is left out of the nutrition totals", () => {
  // Same all-or-nothing rule as buildDayFeatures: a partial sum reads as a
  // genuine low day. Four days logged, one of them with an unparsed meal.
  const meals: MealRow[] = [];
  for (let i = 0; i < 4; i++) {
    meals.push(meal({
      eaten_date: day(i), eaten_hour: 8, dish_name: "oats",
      calories_low: 400, calories_high: 600,
    }));
  }
  meals.push(meal({ eaten_date: day(0), eaten_hour: 19, dish_name: "leftovers" }));

  const r = candidateReflections(meals, [], []).find((x) => x.kind === "calorie_range");
  assert(r !== undefined);
  assert(r.detail.includes("3 of your 4 days"), r.detail);
});

// ─── Individual observations ────────────────────────────────────────────────

Deno.test("repeat dish counts days, not meals", () => {
  const meals: MealRow[] = [
    // Coffee twice on one day is one day of coffee.
    meal({ eaten_date: day(0), eaten_hour: 8, dish_name: "coffee" }),
    meal({ eaten_date: day(0), eaten_hour: 10, dish_name: "coffee" }),
    meal({ eaten_date: day(0), eaten_hour: 19, dish_name: "dal" }),
    meal({ eaten_date: day(1), eaten_hour: 19, dish_name: "dal" }),
    meal({ eaten_date: day(2), eaten_hour: 19, dish_name: "Dal" }),
  ];
  const r = candidateReflections(meals, [], []).find((x) => x.kind === "repeat_dish");
  assert(r !== undefined);
  assert(r.body.toLowerCase().startsWith("dal"), r.body);
  assert(r.detail.includes("3 of your 3"), r.detail);
});

Deno.test("no repeat reflection when nothing repeats", () => {
  const meals = [0, 1, 2].map((i) =>
    meal({ eaten_date: day(i), eaten_hour: 19, dish_name: `one-off ${i}` })
  );
  assertFalse(candidateReflections(meals, [], []).some((r) => r.kind === "repeat_dish"));
});

Deno.test("a fixed last-meal hour reads as consistency, not a range", () => {
  const meals = [0, 1, 2, 3].map((i) => meal({ eaten_date: day(i), eaten_hour: 19 }));
  const r = candidateReflections(meals, [], []).find((x) => x.kind === "meal_timing");
  assert(r !== undefined);
  assert(r.body.includes("19:00"), r.body);
  assertFalse(r.body.includes("between"), r.body);
});

Deno.test("caffeine reflection only counts intake after the late cutoff", () => {
  // A morning-only coffee drinker gets no late-caffeine reflection, and the
  // cutoff must match the feature the engine tests (LATE_CAFFEINE_HOUR).
  const morning = [0, 1, 2, 3].map((i) =>
    meal({
      eaten_date: day(i), eaten_hour: 8, dish_name: "coffee",
      caffeine_mg_low: 90, caffeine_mg_high: 120,
    })
  );
  assertFalse(candidateReflections(morning, [], []).some((r) => r.kind === "late_caffeine"));

  const afternoon = morning.map((m, i) =>
    i < 2 ? { ...m, eaten_hour: 16 } : m
  );
  const r = candidateReflections(afternoon, [], []).find((x) => x.kind === "late_caffeine");
  assert(r !== undefined);
  assert(r.body.includes("2 of your 4"), r.body);
  assert(r.detail.includes("16:00"), r.detail);
});

Deno.test("body-signal reflections need their own days, not the union", () => {
  // Two nights of sleep plus two days of steps is not four days of anything
  // — the same reasoning as the max() in hasSufficientData.
  const meals = plainDays(4);
  const health = [
    healthDay({ day: day(0), sleep_minutes: 400 }),
    healthDay({ day: day(1), sleep_minutes: 430 }),
    healthDay({ day: day(2), steps: 8000 }),
    healthDay({ day: day(3), steps: 9000 }),
  ];
  const kinds = candidateReflections(meals, [], health).map((r) => r.kind);
  assertFalse(kinds.includes("sleep_range"));
  assertFalse(kinds.includes("steps_range"));
});

Deno.test("a signal with enough days does surface", () => {
  const meals = plainDays(4);
  const health = [0, 1, 2].map((i) => healthDay({ day: day(i), sleep_minutes: 380 + i * 30 }));
  const r = candidateReflections(meals, [], health).find((x) => x.kind === "sleep_range");
  assert(r !== undefined);
  assert(r.body.includes("6h20m") && r.body.includes("7h20m"), r.body);
});

Deno.test("a tie names both dishes rather than picking one", () => {
  // The common case for a fixed breakfast: calling one of two everyday
  // dishes "what you've come back to most" is just false.
  const meals: MealRow[] = [];
  for (let i = 0; i < 4; i++) {
    meals.push(meal({ eaten_date: day(i), eaten_hour: 8, dish_name: "oats" }));
    meals.push(meal({ eaten_date: day(i), eaten_hour: 13, dish_name: "soup" }));
    if (i < 2) meals.push(meal({ eaten_date: day(i), eaten_hour: 19, dish_name: "dal" }));
  }
  const r = candidateReflections(meals, [], []).find((x) => x.kind === "repeat_dish");
  assert(r !== undefined);
  assert(r.body.includes("oats") && r.body.includes("soup"), r.body);
  // The runner-up in the detail must be a genuine runner-up, not a tie.
  assert(r.detail.includes("dal on 2"), r.detail);
});
