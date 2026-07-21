// generate-insights
//
// Weekly job (per user): computes the four rules in insight-rules,
// picks at most one finding, asks Claude to write the hedged copy,
// inserts a row into `insights`. Skips silently if nothing qualifies.
//
// Invocation:
//   - Scheduled (cron) with a shared secret in the Authorization header.
//   - Body: { user_id: uuid, week_start: 'YYYY-MM-DD' }
//   - For batch runs the SQL scheduler POSTs once per active user.
//
// Secrets required:
//   ANTHROPIC_API_KEY
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (auto-injected)
//   INSIGHTS_CRON_SECRET                     (set via `supabase secrets set`)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const ANTHROPIC_MODEL = "claude-sonnet-4-6";
const LOOKBACK_DAYS = 28;
const LATE_HOUR = 21; // "after 21:00" per insight-rules

type RuleId =
  | "late_eat_energy"
  | "repeat_dish_energy"
  | "steps_sleep"
  | "late_eat_overnight";

type Tier = 0 | 1 | 2;

type Finding = {
  rule_id: RuleId;
  tier: Tier;
  stat: Record<string, unknown>;
  effect: number; // normalized within-rule effect size, for ranking
};

type Meal = {
  eaten_at: string;
  eaten_date: string | null;
  eaten_hour: number | null;
  dish_name: string | null;
};
type Checkin = { check_date: string; energy: number };
type HealthDay = {
  day: string;
  steps: number | null;
  sleep_minutes: number | null;
  resting_hr_bpm: number | null;
  hrv_ms: number | null;
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// ─── Date helpers ───────────────────────────────────────────────────────────

// Local day/hour of the meal, as observed by the user. The client records
// eaten_date/eaten_hour in its own timezone at log time — eaten_at is
// timestamptz, which Postgres normalizes to UTC, so deriving locality from
// it is wrong for any non-UTC user. The eaten_at fallback (UTC) only
// applies to legacy rows written before the local columns existed.
function dayOfMeal(m: Meal): string {
  return m.eaten_date ?? m.eaten_at.slice(0, 10);
}

function hourOfMeal(m: Meal): number {
  if (m.eaten_hour !== null && m.eaten_hour !== undefined) return m.eaten_hour;
  const match = m.eaten_at.match(/T(\d{2}):/);
  return match ? Number(match[1]) : 0;
}

function nextDay(day: string): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

function windowStartISO(weekStart: string, lookbackDays: number): string {
  const d = new Date(`${weekStart}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - lookbackDays);
  return d.toISOString();
}

// ─── Data pulls (service role — RLS bypassed) ───────────────────────────────

async function loadWindow(admin: SupabaseClient, userId: string, weekStart: string) {
  const startISO = windowStartISO(weekStart, LOOKBACK_DAYS);
  const [meals, checkins, health] = await Promise.all([
    admin.from("meals")
      .select("eaten_at,eaten_date,eaten_hour,dish_name")
      .eq("user_id", userId)
      .gte("eaten_at", startISO)
      .lt("eaten_at", `${weekStart}T23:59:59Z`)
      .order("eaten_at", { ascending: true }),
    admin.from("daily_checkins")
      .select("check_date,energy")
      .eq("user_id", userId)
      .gte("check_date", startISO.slice(0, 10))
      .lte("check_date", weekStart),
    admin.from("health_days")
      .select("day,steps,sleep_minutes,resting_hr_bpm,hrv_ms")
      .eq("user_id", userId)
      .gte("day", startISO.slice(0, 10))
      .lte("day", weekStart),
  ]);
  return {
    meals: (meals.data ?? []) as Meal[],
    checkins: (checkins.data ?? []) as Checkin[],
    health: (health.data ?? []) as HealthDay[],
  };
}

// ─── Tier detection ─────────────────────────────────────────────────────────

function detectTier(health: HealthDay[]): Tier {
  if (health.length === 0) return 0;
  const hasBasic = health.some(h => h.steps !== null && h.sleep_minutes !== null);
  const hasCardio = health.some(h => h.resting_hr_bpm !== null || h.hrv_ms !== null);
  if (hasBasic && hasCardio) return 2;
  if (hasBasic) return 1;
  return 0;
}

// ─── Small stats ────────────────────────────────────────────────────────────

function mean(xs: number[]): number {
  return xs.length === 0 ? NaN : xs.reduce((a, b) => a + b, 0) / xs.length;
}

// Spearman rank correlation. NaN if fewer than 3 pairs.
function spearman(xs: number[], ys: number[]): number {
  if (xs.length !== ys.length || xs.length < 3) return NaN;
  const rank = (arr: number[]): number[] => {
    const sorted = arr.map((v, i) => [v, i] as [number, number])
      .sort((a, b) => a[0] - b[0]);
    const ranks = new Array(arr.length).fill(0);
    let i = 0;
    while (i < sorted.length) {
      let j = i;
      while (j + 1 < sorted.length && sorted[j + 1][0] === sorted[i][0]) j++;
      const avg = (i + j) / 2 + 1; // 1-based average rank
      for (let k = i; k <= j; k++) ranks[sorted[k][1]] = avg;
      i = j + 1;
    }
    return ranks;
  };
  const rx = rank(xs);
  const ry = rank(ys);
  const n = xs.length;
  const mx = mean(rx);
  const my = mean(ry);
  let num = 0, dx = 0, dy = 0;
  for (let i = 0; i < n; i++) {
    num += (rx[i] - mx) * (ry[i] - my);
    dx  += (rx[i] - mx) ** 2;
    dy  += (ry[i] - my) ** 2;
  }
  const denom = Math.sqrt(dx * dy);
  return denom === 0 ? NaN : num / denom;
}

// ─── Rule 1: late-evening eating × next-day energy ─────────────────────────
// Tier 0 · min 5/5 · surface |Δ| ≥ 0.6
function ruleLateEatEnergy(meals: Meal[], checkins: Checkin[]): Finding | null {
  // Set of "late days" — days on which the user had at least one meal
  // eaten after 21:00 local. The comparison is next-day energy.
  const lateDays = new Set<string>();
  const anyMealDays = new Set<string>();
  for (const m of meals) {
    const day = dayOfMeal(m);
    anyMealDays.add(day);
    if (hourOfMeal(m) >= LATE_HOUR) lateDays.add(day);
  }
  const energyByDay = new Map<string, number>();
  for (const c of checkins) energyByDay.set(c.check_date, c.energy);

  const lateNextEnergy: number[] = [];
  const notLateNextEnergy: number[] = [];
  for (const day of anyMealDays) {
    const next = nextDay(day);
    const e = energyByDay.get(next);
    if (e === undefined) continue;
    if (lateDays.has(day)) lateNextEnergy.push(e);
    else notLateNextEnergy.push(e);
  }

  if (lateNextEnergy.length < 5 || notLateNextEnergy.length < 5) return null;
  const mLate = mean(lateNextEnergy);
  const mNot  = mean(notLateNextEnergy);
  const delta = mLate - mNot;
  if (Math.abs(delta) < 0.6) return null;

  return {
    rule_id: "late_eat_energy",
    tier: 0,
    stat: {
      delta,
      n_late: lateNextEnergy.length,
      n_not_late: notLateNextEnergy.length,
      mean_energy_after_late: mLate,
      mean_energy_after_not_late: mNot,
    },
    effect: Math.abs(delta) / 5, // normalize to the 0–5 scale
  };
}

// ─── Rule 2: repeat-dish × next-day energy ─────────────────────────────────
// Tier 0 · dish eaten ≥ 3 · cohort ≥ 5 · surface |Δ| ≥ 0.7
function ruleRepeatDishEnergy(meals: Meal[], checkins: Checkin[]): Finding | null {
  const energyByDay = new Map<string, number>();
  for (const c of checkins) energyByDay.set(c.check_date, c.energy);

  const daysByDish = new Map<string, Set<string>>();
  const allDishDays = new Set<string>();
  for (const m of meals) {
    if (!m.dish_name) continue;
    const day = dayOfMeal(m);
    allDishDays.add(day);
    const name = m.dish_name.trim().toLowerCase();
    if (!name) continue;
    if (!daysByDish.has(name)) daysByDish.set(name, new Set());
    daysByDish.get(name)!.add(day);
  }

  let best: Finding | null = null;

  for (const [dish, days] of daysByDish) {
    if (days.size < 3) continue;
    const dishNextEnergy: number[] = [];
    const cohortNextEnergy: number[] = [];
    for (const day of allDishDays) {
      const e = energyByDay.get(nextDay(day));
      if (e === undefined) continue;
      if (days.has(day)) dishNextEnergy.push(e);
      else cohortNextEnergy.push(e);
    }
    if (dishNextEnergy.length < 3 || cohortNextEnergy.length < 5) continue;

    const mDish = mean(dishNextEnergy);
    const mCohort = mean(cohortNextEnergy);
    const delta = mDish - mCohort;
    if (Math.abs(delta) < 0.7) continue;

    const effect = Math.abs(delta) / 5;
    if (!best || effect > best.effect) {
      best = {
        rule_id: "repeat_dish_energy",
        tier: 0,
        stat: {
          dish,
          delta,
          n_dish: dishNextEnergy.length,
          n_cohort: cohortNextEnergy.length,
          mean_energy_after_dish: mDish,
          mean_energy_after_cohort: mCohort,
        },
        effect,
      };
    }
  }
  return best;
}

// ─── Rule 3: step count × sleep duration ──────────────────────────────────
// Tier 1 · ≥ 10 paired days · surface |ρ| ≥ 0.35
function ruleStepsSleep(health: HealthDay[]): Finding | null {
  const pairs: [number, number][] = [];
  for (const h of health) {
    if (h.steps !== null && h.sleep_minutes !== null) {
      pairs.push([h.steps, h.sleep_minutes]);
    }
  }
  if (pairs.length < 10) return null;
  const rho = spearman(pairs.map(p => p[0]), pairs.map(p => p[1]));
  if (!Number.isFinite(rho) || Math.abs(rho) < 0.35) return null;
  return {
    rule_id: "steps_sleep",
    tier: 1,
    stat: {
      rho,
      n_pairs: pairs.length,
    },
    effect: Math.abs(rho), // already in [0,1]
  };
}

// ─── Rule 4: late eating × overnight RHR / HRV ────────────────────────────
// Tier 2 · 5/5 · surface RHR Δ ≥ 2 bpm OR HRV Δ ≥ 4 ms
function ruleLateEatOvernight(meals: Meal[], health: HealthDay[]): Finding | null {
  const lateDays = new Set<string>();
  const anyMealDays = new Set<string>();
  for (const m of meals) {
    const day = dayOfMeal(m);
    anyMealDays.add(day);
    if (hourOfMeal(m) >= LATE_HOUR) lateDays.add(day);
  }
  const rhrByDay = new Map<string, number>();
  const hrvByDay = new Map<string, number>();
  for (const h of health) {
    if (h.resting_hr_bpm !== null) rhrByDay.set(h.day, h.resting_hr_bpm);
    if (h.hrv_ms !== null)         hrvByDay.set(h.day, h.hrv_ms);
  }

  const collect = (map: Map<string, number>) => {
    const late: number[] = [];
    const notLate: number[] = [];
    for (const day of anyMealDays) {
      const v = map.get(day);
      if (v === undefined) continue;
      if (lateDays.has(day)) late.push(v);
      else notLate.push(v);
    }
    return { late, notLate };
  };

  const rhr = collect(rhrByDay);
  const hrv = collect(hrvByDay);

  const rhrOk = rhr.late.length >= 5 && rhr.notLate.length >= 5;
  const hrvOk = hrv.late.length >= 5 && hrv.notLate.length >= 5;
  if (!rhrOk && !hrvOk) return null;

  const rhrDelta = rhrOk ? mean(rhr.late) - mean(rhr.notLate) : 0;
  const hrvDelta = hrvOk ? mean(hrv.late) - mean(hrv.notLate) : 0;

  const rhrSurface = rhrOk && Math.abs(rhrDelta) >= 2;
  const hrvSurface = hrvOk && Math.abs(hrvDelta) >= 4;
  if (!rhrSurface && !hrvSurface) return null;

  // Effect: normalize each signal against its threshold and keep the max.
  const effect = Math.max(
    rhrSurface ? Math.abs(rhrDelta) / 10 : 0,
    hrvSurface ? Math.abs(hrvDelta) / 20 : 0,
  );

  return {
    rule_id: "late_eat_overnight",
    tier: 2,
    stat: {
      rhr_delta: rhrDelta,
      hrv_delta: hrvDelta,
      n_late_rhr: rhr.late.length,
      n_not_late_rhr: rhr.notLate.length,
      n_late_hrv: hrv.late.length,
      n_not_late_hrv: hrv.notLate.length,
      surfaced: rhrSurface ? "rhr" : "hrv",
    },
    effect,
  };
}

// ─── Claude copy ───────────────────────────────────────────────────────────

async function generateCopy(finding: Finding): Promise<string | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return null;

  const system = `You write ONE sentence for a weekly food-body insight.

Contract — non-negotiable:
- Exactly one sentence. ≤ 22 words.
- Hedged: use "tends to", "seems", "is associated with", or "worth watching, not a verdict".
- Never prescriptive. Never medical. Never "you should", "makes you", "causes".
- Mention both sides of the comparison (e.g. "late dinners vs. earlier ones").
- Never a bare calorie number — use a range or omit.
- Return only the sentence. No preamble, no quotes, no markdown.`;

  const user = `Rule: ${finding.rule_id}
Computed stats (do not invent numbers): ${JSON.stringify(finding.stat)}

Write the one sentence.`;

  let res: Response;
  try {
    res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: 200,
        system,
        messages: [{ role: "user", content: user }],
      }),
    });
  } catch {
    return null;
  }
  if (!res.ok) return null;
  let payload: { content?: { type?: string; text?: string }[] };
  try {
    payload = await res.json();
  } catch {
    return null;
  }
  const text = payload?.content?.find(b => b?.type === "text")?.text;
  if (typeof text !== "string") return null;
  const trimmed = text.trim().replace(/^["']|["']$/g, "").replace(/\s+/g, " ");
  const words = trimmed.split(" ").length;
  if (trimmed.length === 0 || words > 30) return null;
  return trimmed;
}

// ─── Entrypoint ────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const cronSecret = Deno.env.get("INSIGHTS_CRON_SECRET");
  const auth = req.headers.get("Authorization") ?? "";
  if (!cronSecret || auth !== `Bearer ${cronSecret}`) {
    return json(401, { error: "unauthorized" });
  }

  let body: { user_id?: string; week_start?: string };
  try { body = await req.json(); }
  catch { return json(400, { error: "invalid_json" }); }
  if (!body.user_id || !body.week_start) {
    return json(400, { error: "missing_user_id_or_week_start" });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { meals, checkins, health } = await loadWindow(admin, body.user_id, body.week_start);
  const tier = detectTier(health);

  // Compute every rule the user qualifies for.
  const candidates: Finding[] = [];
  const r1 = ruleLateEatEnergy(meals, checkins);
  if (r1) candidates.push(r1);
  const r2 = ruleRepeatDishEnergy(meals, checkins);
  if (r2) candidates.push(r2);
  if (tier >= 1) {
    const r3 = ruleStepsSleep(health);
    if (r3) candidates.push(r3);
  }
  if (tier >= 2) {
    const r4 = ruleLateEatOvernight(meals, health);
    if (r4) candidates.push(r4);
  }

  candidates.sort((a, b) => b.effect - a.effect);

  // Never-repeat the most recent prior insight for this user.
  const { data: prior } = await admin
    .from("insights")
    .select("rule_id")
    .eq("user_id", body.user_id)
    .order("week_start", { ascending: false })
    .limit(1)
    .maybeSingle();
  const filtered = prior
    ? candidates.filter(c => c.rule_id !== prior.rule_id)
    : candidates;

  if (filtered.length === 0) return json(200, { surfaced: false, tier });

  const chosen = filtered[0];
  const copy = await generateCopy(chosen);
  if (!copy) return json(500, { error: "copy_generation_failed" });

  // Idempotent per (user, week): a re-fired cron run is a graceful no-op
  // rather than a unique-violation 500.
  const { error: insErr } = await admin.from("insights").upsert(
    {
      user_id: body.user_id,
      week_start: body.week_start,
      rule_id: chosen.rule_id,
      tier: chosen.tier,
      lookback_days: LOOKBACK_DAYS,
      stat: chosen.stat,
      copy,
      model: ANTHROPIC_MODEL,
    },
    { onConflict: "user_id,week_start", ignoreDuplicates: true },
  );
  if (insErr) return json(500, { error: "insert_failed", detail: insErr.message });

  return json(200, { surfaced: true, rule_id: chosen.rule_id, tier });
});
