import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type CheckinRow,
  type Coverage,
  type HealthDayRow,
  type MealRow,
  buildDigest,
  extractJson,
  hasSufficientData,
  normalizeClaim,
  validateInsights,
} from "./digest.ts";

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

// ─── buildDigest ────────────────────────────────────────────────────────────

Deno.test("buildDigest renders a full day line with all metrics", () => {
  const meals = [
    meal({ dish_name: "greek yogurt + berries", eaten_hour: 8, calories_low: 220, calories_high: 320, protein_g_low: 18, protein_g_high: 24 }),
    meal({ dish_name: "pizza", eaten_hour: 21 }),
  ];
  const checkins: CheckinRow[] = [{ check_date: "2026-07-18", energy: 3 }];
  const health = [healthDay({
    steps: 9102, sleep_minutes: 410, resting_hr_bpm: 61, hrv_ms: 44,
    weight_kg: 78.4, active_energy_kcal: 520, workout_minutes: 35,
  })];

  const { lines, coverage } = buildDigest(meals, checkins, health);
  assertEquals(lines.length, 1);
  assertEquals(
    lines[0],
    "2026-07-18 | wt 78.4kg | sleep 6h50m | steps 9102 | actE 520kcal | workout 35m | RHR 61 | HRV 44ms | energy 3/5 | " +
      "meals: 08h greek yogurt + berries (~220-320kcal, ~18-24g prot), 21h pizza",
  );
  assertEquals(coverage.totalDays, 1);
  assertEquals(coverage.mealDays, 1);
  assertEquals(coverage.energyDays, 1);
  assertEquals(coverage.weightDays, 1);
  assertEquals(coverage.workoutDays, 1);
});

Deno.test("buildDigest omits missing metrics instead of rendering zeros", () => {
  const health = [healthDay({ day: "2026-07-17", steps: 4200 })];
  const { lines, coverage } = buildDigest([], [], health);
  assertEquals(lines, ["2026-07-17 | steps 4200"]);
  assertEquals(coverage.sleepDays, 0);
  assertEquals(coverage.stepsDays, 1);
  assertEquals(coverage.mealDays, 0);
});

Deno.test("buildDigest sorts days ascending and meals by hour", () => {
  const meals = [
    meal({ eaten_date: "2026-07-18", eaten_hour: 21, dish_name: "late ramen" }),
    meal({ eaten_date: "2026-07-18", eaten_hour: 7, dish_name: "oats" }),
    meal({ eaten_date: "2026-07-16", eaten_hour: 12, dish_name: "salad" }),
  ];
  const { lines } = buildDigest(meals, [], []);
  assertEquals(lines.length, 2);
  assert(lines[0].startsWith("2026-07-16"));
  assert(lines[1].includes("07h oats, 21h late ramen"));
});

Deno.test("buildDigest falls back to voice transcript, then eaten_at locality", () => {
  const legacy = meal({
    eaten_date: null,
    eaten_hour: null,
    eaten_at: "2026-07-15T21:40:00Z",
    voice_transcript: "leftover dal and rice",
  });
  const { lines } = buildDigest([legacy], [], []);
  assertEquals(lines, ["2026-07-15 | meals: 21h leftover dal and rice"]);
});

// ─── hasSufficientData ──────────────────────────────────────────────────────

function coverage(over: Partial<Coverage>): Coverage {
  return {
    totalDays: 0, mealDays: 0, energyDays: 0, stepsDays: 0, sleepDays: 0,
    rhrDays: 0, hrvDays: 0, weightDays: 0, activeEnergyDays: 0, workoutDays: 0,
    ...over,
  };
}

Deno.test("hasSufficientData requires 7 meal days AND 7 body-signal days", () => {
  assert(hasSufficientData(coverage({ mealDays: 7, energyDays: 7 })));
  assert(hasSufficientData(coverage({ mealDays: 12, sleepDays: 9 })));
  assertFalse(hasSufficientData(coverage({ mealDays: 6, energyDays: 20 })));
  assertFalse(hasSufficientData(coverage({ mealDays: 20, energyDays: 6 })));
  assertFalse(hasSufficientData(coverage({ mealDays: 20 })));
});

Deno.test("hasSufficientData takes the best single body metric, not the sum", () => {
  // 4+4 across two metrics is not 8 days of one reliable signal.
  assertFalse(hasSufficientData(coverage({ mealDays: 10, stepsDays: 4, sleepDays: 4 })));
  assert(hasSufficientData(coverage({ mealDays: 10, stepsDays: 4, sleepDays: 7 })));
});

// ─── normalizeClaim ─────────────────────────────────────────────────────────

Deno.test("normalizeClaim lowercases, strips punctuation, collapses whitespace", () => {
  assertEquals(
    normalizeClaim("Energy dips to 2/5 tend to follow sub-20g-protein mornings!"),
    "energy dips to 2 5 tend to follow sub 20g protein mornings",
  );
  assertEquals(normalizeClaim("  A   —  B  "), "a b");
});

// ─── extractJson ────────────────────────────────────────────────────────────

Deno.test("extractJson strips code fences and parses", () => {
  assertEquals(extractJson('```json\n[{"a":1}]\n```'), [{ a: 1 }]);
  assertEquals(extractJson("[]"), []);
  assertEquals(extractJson("not json"), null);
});

// ─── validateInsights ───────────────────────────────────────────────────────

const validInsight = {
  candidate_id: "c1",
  claim: "Sleep under 6h tends to precede 2/5 energy days — 5 of 7 such days.",
  evidence: "mean energy 2.1/5 after the 7 short-sleep nights vs 3.5/5 after the 11 longer ones",
  suggested_action: null,
};

const ids = new Set(["c1", "c2", "c3", "c4", "c5", "c6"]);

Deno.test("validateInsights accepts a valid array and normalizes suggested_action", () => {
  const out = validateInsights([
    validInsight,
    { ...validInsight, candidate_id: "c2", suggested_action: "  worth watching  " },
    { ...validInsight, candidate_id: "c3", suggested_action: "" },
  ], ids);
  assert(out !== null);
  assertEquals(out.length, 3);
  assertEquals(out[0].suggested_action, null);
  assertEquals(out[1].suggested_action, "worth watching");
  assertEquals(out[2].suggested_action, null); // empty string → null
});

Deno.test("validateInsights unwraps the schema's { insights: [...] } envelope", () => {
  const out = validateInsights({ insights: [validInsight] }, ids);
  assert(out !== null);
  assertEquals(out.length, 1);
  assertEquals(out[0].candidate_id, "c1");
});

Deno.test("validateInsights rejects a claim citing a candidate we never sent", () => {
  // The whole point of candidate ids: an invented finding has no id to cite.
  assertEquals(validateInsights([{ ...validInsight, candidate_id: "c99" }], ids), null);
  assertEquals(validateInsights([{ ...validInsight, candidate_id: "" }], ids), null);
  assertEquals(validateInsights([validInsight], new Set<string>()), null);
});

Deno.test("validateInsights rejects two claims about the same candidate", () => {
  assertEquals(
    validateInsights([validInsight, { ...validInsight, claim: "restated" }], ids),
    null,
  );
});

Deno.test("validateInsights rejects structural violations wholesale", () => {
  assertEquals(validateInsights({ claim: "not an array" }, ids), null);
  assertEquals(validateInsights([{ ...validInsight, claim: "" }], ids), null);
  assertEquals(validateInsights([{ ...validInsight, evidence: 42 }], ids), null);
  assertEquals(validateInsights([validInsight, "rogue string"], ids), null);
  const six = Array.from({ length: 6 }, (_, i) => ({ ...validInsight, candidate_id: `c${i + 1}` }));
  assertEquals(validateInsights(six, ids), null);
});

Deno.test("validateInsights accepts an empty array (nothing worth surfacing)", () => {
  assertEquals(validateInsights([], ids), []);
  assertEquals(validateInsights({ insights: [] }, ids), []);
});
