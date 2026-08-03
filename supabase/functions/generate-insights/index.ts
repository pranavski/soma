// generate-insights
//
// The insight engine. Compresses the caller's last 30 days of food logs,
// energy check-ins, and HealthKit daily aggregates into a per-day digest,
// hands it to Claude ONCE, and stores the returned correlations as
// individual insight rows. TypeScript compresses; Claude reasons.
//
// Invocation — two auth paths:
//   1. Cron/batch: Authorization matches INSIGHTS_CRON_SECRET,
//      body { user_id: uuid }. (Legacy week_start is ignored.)
//   2. On-demand: Authorization is a user JWT, body {} — generates for
//      the caller. This is what the iOS pull-to-refresh hits.
//
// Response:
//   200 { surfaced: boolean, inserted: number }            — ran
//   200 { surfaced: false, reason: "insufficient_data" }   — gated, no Claude call
//   500 { error: "bad_model_output" }                      — model broke contract
//
// Dedupe is two-layered: the prompt carries the user's recent claims as
// "do not repeat", and unique (user_id, claim_norm) in Postgres backstops
// it — re-runs are inserts that silently no-op on conflict.
//
// Secrets required:
//   ANTHROPIC_API_KEY
//   INSIGHTS_CRON_SECRET                       (set via `supabase secrets set`)
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (auto-injected)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  type CheckinRow,
  type HealthDayRow,
  type MealRow,
  MAX_INSIGHTS,
  buildDigest,
  coverageSummary,
  extractJson,
  hasSufficientData,
  normalizeClaim,
  validateInsights,
} from "./digest.ts";

const ANTHROPIC_MODEL = "claude-sonnet-4-6";
const WINDOW_DAYS = 30;
const RECENT_CLAIMS_LIMIT = 15;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// ─── Data window ────────────────────────────────────────────────────────────

async function loadWindow(admin: SupabaseClient, userId: string) {
  const start = new Date();
  start.setUTCDate(start.getUTCDate() - WINDOW_DAYS);
  const startISO = start.toISOString();
  const startDay = startISO.slice(0, 10);

  const [meals, checkins, health] = await Promise.all([
    admin.from("meals")
      .select("eaten_at,eaten_date,eaten_hour,dish_name,voice_transcript,calories_low,calories_high,protein_g_low,protein_g_high")
      .eq("user_id", userId)
      .gte("eaten_at", startISO)
      .order("eaten_at", { ascending: true }),
    admin.from("daily_checkins")
      .select("check_date,energy")
      .eq("user_id", userId)
      .gte("check_date", startDay),
    admin.from("health_days")
      .select("day,steps,sleep_minutes,resting_hr_bpm,hrv_ms,weight_kg,active_energy_kcal,workout_minutes")
      .eq("user_id", userId)
      .gte("day", startDay),
  ]);
  return {
    meals: (meals.data ?? []) as MealRow[],
    checkins: (checkins.data ?? []) as CheckinRow[],
    health: (health.data ?? []) as HealthDayRow[],
  };
}

// ─── Claude ─────────────────────────────────────────────────────────────────

// The copy contract carries the soul of the old insight-rules skill —
// hedged, never prescriptive, never medical, calories only as ranges —
// but the finding itself now comes from the model, so the prompt also has
// to police evidence discipline: real numbers, real day counts, n >= 4.
const SYSTEM_PROMPT = `You are the insight engine for a food–body journal. You receive a per-day digest of one person's last ~30 days (meals with rough calorie/protein ranges, a 1–5 energy self-report, and daily HealthKit aggregates) plus per-metric coverage counts.

Find correlations and patterns in THIS person's data. Return ONLY a JSON array — no prose, no markdown, no code fences — of at most ${MAX_INSIGHTS} objects, each EXACTLY:
{
  "claim": string,
  "evidence": string,
  "confidence": "low" | "medium" | "high",
  "suggested_action": string | null
}

Rules — non-negotiable:
- claim: one sentence naming a specific pattern in the data with real numbers from the digest (e.g. "Energy dips to 2/5 tend to follow sub-20g-protein mornings — 5 of the 6 such days"). NEVER generic nutrition advice. Hedged language only: "tends to", "seems", "is associated with". Never "causes", "makes you", "you should".
- evidence: the supporting observation spelled out — which days, how many, the compared values (e.g. "mean energy 2.2/5 after the 6 low-protein mornings vs 3.6/5 after the 9 higher-protein ones").
- confidence: high only for a consistent pattern with n ≥ 8 supporting days; medium for n ≥ 6; low otherwise.
- A pattern needs at least 4 supporting days to be claimed at all. Fewer than 4 → do not include it.
- Respect the coverage counts: never claim a trend in a metric with fewer than 4 days of data. Never treat a missing metric on a day as zero — missing means not synced.
- suggested_action: a single gentle, observational next step ("worth watching whether earlier dinners shift this"), or null. Never prescriptive ("eat less X"), never a target, never medical.
- Calories only ever as ranges ("~550–700"), never a bare number.
- You will be given claims already shown to this person. Do not repeat or rephrase any of them — only genuinely new patterns.
- If nothing meets the bar, return []. An empty array is a good answer; an invented pattern is not.`;

function buildUserMessage(
  digestLines: string[],
  coverage: string,
  priorClaims: string[],
): string {
  const blocks: string[] = [
    `Per-metric coverage over the window:\n${coverage}`,
    `Daily digest (missing metrics = not synced, NOT zero):\n${digestLines.join("\n")}`,
  ];
  if (priorClaims.length > 0) {
    blocks.push(
      "Already surfaced — do not repeat or rephrase these:\n" +
        priorClaims.map((c) => `- ${c}`).join("\n"),
    );
  }
  blocks.push("Return the JSON array now.");
  return blocks.join("\n\n");
}

async function callClaude(userMessage: string): Promise<string | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return null;
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
        max_tokens: 2000,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: userMessage }],
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
  const text = payload?.content?.find((b) => b?.type === "text")?.text;
  return typeof text === "string" ? text : null;
}

// ─── Auth ───────────────────────────────────────────────────────────────────

/// Resolve the target user from one of the two auth paths. Returns null
/// when neither path authenticates.
async function resolveUser(
  req: Request,
  body: { user_id?: string },
  supabaseUrl: string,
  anonKey: string,
): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;

  const cronSecret = Deno.env.get("INSIGHTS_CRON_SECRET");
  if (cronSecret && auth === `Bearer ${cronSecret}`) {
    return body.user_id ?? null;
  }

  // User-JWT path: let Supabase verify the token.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data?.user?.id) return null;
  return data.user.id;
}

// ─── Entrypoint ─────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: { user_id?: string } = {};
  try {
    const raw = await req.text();
    if (raw.trim().length > 0) body = JSON.parse(raw);
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const userId = await resolveUser(req, body, supabaseUrl, anonKey);
  if (!userId) return json(401, { error: "unauthorized" });

  const admin = createClient(supabaseUrl, serviceKey);

  const { meals, checkins, health } = await loadWindow(admin, userId);
  const { lines, coverage } = buildDigest(meals, checkins, health);

  if (!hasSufficientData(coverage)) {
    return json(200, { surfaced: false, inserted: 0, reason: "insufficient_data" });
  }

  const { data: prior } = await admin
    .from("insights")
    .select("claim")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(RECENT_CLAIMS_LIMIT);
  const priorClaims = (prior ?? []).map((r: { claim: string }) => r.claim);

  const text = await callClaude(
    buildUserMessage(lines, coverageSummary(coverage), priorClaims),
  );
  if (text === null) return json(500, { error: "claude_call_failed" });

  const parsed = extractJson(text);
  const insights = parsed === null ? null : validateInsights(parsed);
  if (insights === null) return json(500, { error: "bad_model_output" });

  if (insights.length === 0) {
    return json(200, { surfaced: false, inserted: 0, reason: "no_qualifying_patterns" });
  }

  // ignoreDuplicates makes conflicting rows silent no-ops; .select() then
  // returns only the rows actually inserted, which is our "new this run".
  const { data: insertedRows, error: insErr } = await admin
    .from("insights")
    .upsert(
      insights.map((i) => ({
        user_id: userId,
        claim: i.claim,
        evidence: i.evidence,
        confidence: i.confidence,
        suggested_action: i.suggested_action,
        window_days: WINDOW_DAYS,
        claim_norm: normalizeClaim(i.claim),
        model: ANTHROPIC_MODEL,
      })),
      { onConflict: "user_id,claim_norm", ignoreDuplicates: true },
    )
    .select("id");
  if (insErr) return json(500, { error: "insert_failed", detail: insErr.message });

  const inserted = insertedRows?.length ?? 0;
  return json(200, { surfaced: inserted > 0, inserted });
});
