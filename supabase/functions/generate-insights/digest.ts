// Digest helpers for generate-insights.
//
// Pure functions only — no fetch, no Deno.env — so they can be unit-tested
// (see digest_test.ts) without serving the function. Data loading and the
// Claude call stay in index.ts.
//
// The digest is the whole trick: 30 days of meals + check-ins + HealthKit
// aggregates compressed into one line per day, compact enough to hand to
// Claude in a single message, explicit enough that every claim it makes
// can cite a real number.

export type MealRow = {
  eaten_at: string;
  eaten_date: string | null;
  eaten_hour: number | null;
  dish_name: string | null;
  voice_transcript: string | null;
  calories_low: number | null;
  calories_high: number | null;
  protein_g_low: number | null;
  protein_g_high: number | null;
};

export type CheckinRow = { check_date: string; energy: number };

export type HealthDayRow = {
  day: string;
  steps: number | null;
  sleep_minutes: number | null;
  resting_hr_bpm: number | null;
  hrv_ms: number | null;
  weight_kg: number | null;
  active_energy_kcal: number | null;
  workout_minutes: number | null;
};

export type Coverage = {
  totalDays: number; // days in the window with ANY signal
  mealDays: number;
  energyDays: number;
  stepsDays: number;
  sleepDays: number;
  rhrDays: number;
  hrvDays: number;
  weightDays: number;
  activeEnergyDays: number;
  workoutDays: number;
};

export type ParsedInsight = {
  claim: string;
  evidence: string;
  confidence: "low" | "medium" | "high";
  suggested_action: string | null;
};

export const MAX_INSIGHTS = 5;
export const MIN_MEAL_DAYS = 7;
export const MIN_BODY_DAYS = 7;

// ─── Day / hour locality ────────────────────────────────────────────────────
// eaten_date/eaten_hour are recorded client-side in the user's timezone;
// eaten_at (timestamptz, normalized to UTC) is only a legacy fallback.

export function dayOfMeal(m: MealRow): string {
  return m.eaten_date ?? m.eaten_at.slice(0, 10);
}

export function hourOfMeal(m: MealRow): number {
  if (m.eaten_hour !== null && m.eaten_hour !== undefined) return m.eaten_hour;
  const match = m.eaten_at.match(/T(\d{2}):/);
  return match ? Number(match[1]) : 0;
}

// ─── Formatting ─────────────────────────────────────────────────────────────

function fmtSleep(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, "0")}m`;
}

function mealLabel(m: MealRow): string {
  const label = (m.dish_name ?? m.voice_transcript ?? "unlabeled meal").trim();
  const notes: string[] = [];
  if (m.calories_low !== null && m.calories_high !== null) {
    notes.push(`~${m.calories_low}-${m.calories_high}kcal`);
  }
  if (m.protein_g_low !== null && m.protein_g_high !== null) {
    notes.push(`~${m.protein_g_low}-${m.protein_g_high}g prot`);
  }
  const hh = String(hourOfMeal(m)).padStart(2, "0");
  return notes.length > 0 ? `${hh}h ${label} (${notes.join(", ")})` : `${hh}h ${label}`;
}

// ─── Digest ─────────────────────────────────────────────────────────────────

/// One line per day that has any signal, ascending by date. Missing metrics
/// are omitted from the line rather than rendered as zeros — the model must
/// not mistake "didn't sync" for "didn't move".
export function buildDigest(
  meals: MealRow[],
  checkins: CheckinRow[],
  health: HealthDayRow[],
): { lines: string[]; coverage: Coverage } {
  const mealsByDay = new Map<string, MealRow[]>();
  for (const m of meals) {
    const day = dayOfMeal(m);
    if (!mealsByDay.has(day)) mealsByDay.set(day, []);
    mealsByDay.get(day)!.push(m);
  }
  const energyByDay = new Map<string, number>();
  for (const c of checkins) energyByDay.set(c.check_date, c.energy);
  const healthByDay = new Map<string, HealthDayRow>();
  for (const h of health) healthByDay.set(h.day, h);

  const days = [...new Set([
    ...mealsByDay.keys(),
    ...energyByDay.keys(),
    ...healthByDay.keys(),
  ])].sort();

  const coverage: Coverage = {
    totalDays: days.length,
    mealDays: 0, energyDays: 0, stepsDays: 0, sleepDays: 0,
    rhrDays: 0, hrvDays: 0, weightDays: 0, activeEnergyDays: 0, workoutDays: 0,
  };

  const lines: string[] = [];
  for (const day of days) {
    const parts: string[] = [day];
    const h = healthByDay.get(day);
    if (h?.weight_kg != null)          { parts.push(`wt ${Number(h.weight_kg).toFixed(1)}kg`); coverage.weightDays++; }
    if (h?.sleep_minutes != null)      { parts.push(`sleep ${fmtSleep(h.sleep_minutes)}`);     coverage.sleepDays++; }
    if (h?.steps != null)              { parts.push(`steps ${h.steps}`);                       coverage.stepsDays++; }
    if (h?.active_energy_kcal != null) { parts.push(`actE ${h.active_energy_kcal}kcal`);       coverage.activeEnergyDays++; }
    if (h?.workout_minutes != null)    { parts.push(`workout ${h.workout_minutes}m`);          coverage.workoutDays++; }
    if (h?.resting_hr_bpm != null)     { parts.push(`RHR ${Number(h.resting_hr_bpm)}`);        coverage.rhrDays++; }
    if (h?.hrv_ms != null)             { parts.push(`HRV ${Number(h.hrv_ms)}ms`);              coverage.hrvDays++; }
    const energy = energyByDay.get(day);
    if (energy !== undefined)          { parts.push(`energy ${energy}/5`);                     coverage.energyDays++; }
    const dayMeals = mealsByDay.get(day);
    if (dayMeals && dayMeals.length > 0) {
      const sorted = [...dayMeals].sort((a, b) => hourOfMeal(a) - hourOfMeal(b));
      parts.push(`meals: ${sorted.map(mealLabel).join(", ")}`);
      coverage.mealDays++;
    }
    lines.push(parts.join(" | "));
  }
  return { lines, coverage };
}

/// Food–body correlations need both halves: enough days with meals AND
/// enough days with some body signal (energy check-in counts — it's the
/// tier-0 body signal). Below either bar we don't call Claude at all.
export function hasSufficientData(c: Coverage): boolean {
  const bodyDays = Math.max(
    c.energyDays, c.stepsDays, c.sleepDays, c.rhrDays,
    c.hrvDays, c.weightDays, c.activeEnergyDays, c.workoutDays,
  );
  return c.mealDays >= MIN_MEAL_DAYS && bodyDays >= MIN_BODY_DAYS;
}

/// Per-metric day counts, rendered for the prompt so the model knows what
/// it can and cannot claim (e.g. 3 days of weight is not a weight trend).
export function coverageSummary(c: Coverage): string {
  return [
    `days with any data: ${c.totalDays}`,
    `days with meals logged: ${c.mealDays}`,
    `days with energy check-in (1-5 self-report): ${c.energyDays}`,
    `days with steps: ${c.stepsDays}`,
    `days with sleep: ${c.sleepDays}`,
    `days with resting HR: ${c.rhrDays}`,
    `days with HRV: ${c.hrvDays}`,
    `days with weight: ${c.weightDays}`,
    `days with active energy: ${c.activeEnergyDays}`,
    `days with workouts: ${c.workoutDays}`,
  ].join("\n");
}

// ─── Claim normalization / dedupe key ───────────────────────────────────────

/// Storage-layer dedupe key: lowercase, alphanumerics only, single spaces.
/// unique (user_id, claim_norm) makes re-runs idempotent even when the
/// prompt-level "already surfaced" list fails to stop a rephrase-free repeat.
export function normalizeClaim(claim: string): string {
  return claim
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

// ─── Model-output validation ────────────────────────────────────────────────

/// Strip accidental ``` fences and parse. Returns null on any malformation.
export function extractJson(text: string): unknown | null {
  const cleaned = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  try {
    return JSON.parse(cleaned);
  } catch {
    return null;
  }
}

const CONFIDENCE_VALUES = ["low", "medium", "high"] as const;

/// Strict shape check on the model's output. Accepts at most MAX_INSIGHTS;
/// anything structurally off (wrong enum, empty strings, non-array) rejects
/// the WHOLE payload — a partially-trustworthy insights run is worse than
/// no run, and the nightly cron will simply try again.
export function validateInsights(x: unknown): ParsedInsight[] | null {
  if (!Array.isArray(x)) return null;
  if (x.length > MAX_INSIGHTS) return null;
  const out: ParsedInsight[] = [];
  for (const item of x) {
    if (!item || typeof item !== "object") return null;
    const o = item as Record<string, unknown>;
    if (typeof o.claim !== "string" || o.claim.trim().length === 0) return null;
    if (typeof o.evidence !== "string" || o.evidence.trim().length === 0) return null;
    if (typeof o.confidence !== "string" ||
        !(CONFIDENCE_VALUES as readonly string[]).includes(o.confidence)) return null;
    if (o.suggested_action !== null && o.suggested_action !== undefined &&
        typeof o.suggested_action !== "string") return null;
    const action = typeof o.suggested_action === "string" ? o.suggested_action.trim() : "";
    out.push({
      claim: o.claim.trim(),
      evidence: o.evidence.trim(),
      confidence: o.confidence as ParsedInsight["confidence"],
      suggested_action: action.length > 0 ? action : null,
    });
  }
  return out;
}
