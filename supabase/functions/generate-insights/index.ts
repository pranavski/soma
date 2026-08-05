// generate-insights
//
// The insight engine. Compresses the caller's last 30 days of food logs,
// energy check-ins, and HealthKit daily aggregates, computes every
// food-signal association over that window, keeps the ones that survive a
// permutation test with an FDR correction, and hands that shortlist to
// Claude ONCE to decide which are worth saying and to write the sentence.
//
// TypeScript owns every number. Claude owns judgment and language, and can
// only describe a candidate we handed it — see validateInsights.
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
import { type Candidate, buildCandidates, renderCandidates } from "./candidates.ts";

// Haiku is the right tier now that the model no longer does arithmetic:
// what is left is picking plausible rows out of a scored table and writing
// one hedged sentence each. It is also the cheapest model that supports
// structured outputs, which is what lets us drop the "return ONLY JSON"
// pleading from the prompt.
const ANTHROPIC_MODEL = "claude-haiku-4-5";
const WINDOW_DAYS = 30;
const RECENT_CLAIMS_LIMIT = 15;

/// Schema the response is constrained to. confidence is absent on purpose —
/// it is derived from the candidate's supporting-day count, not claimed.
const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    insights: {
      type: "array",
      items: {
        type: "object",
        properties: {
          candidate_id: { type: "string", description: "id of the candidate this describes, e.g. c3" },
          claim: { type: "string" },
          evidence: { type: "string" },
          suggested_action: { anyOf: [{ type: "string" }, { type: "null" }] },
        },
        required: ["candidate_id", "claim", "evidence", "suggested_action"],
        additionalProperties: false,
      },
    },
  },
  required: ["insights"],
  additionalProperties: false,
} as const;

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

// The statistics are settled before this prompt is built, so the model's job
// is editorial: which of these survived-the-math associations are plausible
// enough to say to a person, and how to say them. The copy contract carries
// the soul of the insight-rules skill — hedged, never prescriptive, never
// medical, calories only as ranges.
const SYSTEM_PROMPT = `You are the insight engine for a food–body journal. You receive a shortlist of statistical associations already computed from one person's last ~30 days, plus the daily digest they were computed from.

Every candidate has already passed a permutation test with a false-discovery-rate correction. The arithmetic is done: n, rho, and the compared group averages are given to you. Do not recompute them, and do not cite any number that is not in the candidate line you are describing.

Your job is judgment and language. For each candidate, decide whether it is worth telling this person about — a real, interpretable pattern in how they eat and how they feel — or whether it is a coincidence dressed up as a finding (spurious pairings, reversed causality, an association nobody could act on or even notice). Then write it.

Select at most ${MAX_INSIGHTS} candidates. Selecting none is a good, honest answer; describing a candidate you do not believe is not.

Rules — non-negotiable:
- claim: one sentence naming the pattern, using the numbers from that candidate's line (e.g. "Energy tends to run lower the day after your latest dinners — 2.2 of 5 across those 7 days against 3.6 on the earlier 9"). NEVER generic nutrition advice. Hedged language only: "tends to", "seems", "is associated with". Never "causes", "makes you", "you should".
- evidence: the supporting observation spelled out — how many days on each side, and both compared averages.
- suggested_action: a single gentle, observational next step ("worth watching whether earlier dinners shift this"), or null. Never prescriptive ("eat less X"), never a target, never medical.
- Calories only ever as ranges ("~550–700"), never a bare number.
- An association is not causation, and the copy must never imply it is.
- You will be given claims already shown to this person. Do not repeat or rephrase any of them.
- Set candidate_id to the id of the candidate each insight describes.`;

function buildUserMessage(
  candidates: Candidate[],
  digestLines: string[],
  coverage: string,
  priorClaims: string[],
): string {
  const blocks: string[] = [
    `Candidate associations (already tested and corrected — these are the only things you may describe):\n${renderCandidates(candidates)}`,
    `Per-metric coverage over the window:\n${coverage}`,
    `Daily digest, for context on whether each candidate is plausible (missing metrics = not synced, NOT zero):\n${digestLines.join("\n")}`,
  ];
  if (priorClaims.length > 0) {
    blocks.push(
      "Already surfaced — do not repeat or rephrase these:\n" +
        priorClaims.map((c) => `- ${c}`).join("\n"),
    );
  }
  blocks.push("Select and write the insights now.");
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
        max_tokens: 4096,
        // Haiku 4.5 predates adaptive thinking, so this is the older fixed
        // budget form (must be < max_tokens). Modest, but the plausible-vs-
        // spurious call is the whole reason a model is in this loop.
        thinking: { type: "enabled", budget_tokens: 2048 },
        output_config: { format: { type: "json_schema", schema: RESPONSE_SCHEMA } },
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

  // Everything already shown to this person, by pattern rather than by
  // wording — a rephrase of a surfaced finding never reaches the model.
  const { data: seenRows } = await admin
    .from("insights")
    .select("pattern_key")
    .eq("user_id", userId);
  const seenPatterns = new Set(
    (seenRows ?? []).map((r: { pattern_key: string }) => r.pattern_key),
  );

  const candidates = buildCandidates(meals, checkins, health)
    .filter((c) => !seenPatterns.has(c.patternKey))
    // Re-number so the ids the model cites are contiguous.
    .map((c, i) => ({ ...c, id: `c${i + 1}` }));

  // Nothing survived the correction, or everything that did is old news.
  // Either way there is no call to make.
  if (candidates.length === 0) {
    return json(200, { surfaced: false, inserted: 0, reason: "no_qualifying_patterns" });
  }

  const { data: prior } = await admin
    .from("insights")
    .select("claim")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(RECENT_CLAIMS_LIMIT);
  const priorClaims = (prior ?? []).map((r: { claim: string }) => r.claim);

  const text = await callClaude(
    buildUserMessage(candidates, lines, coverageSummary(coverage), priorClaims),
  );
  if (text === null) return json(500, { error: "claude_call_failed" });

  const byId = new Map(candidates.map((c) => [c.id, c]));
  const parsed = extractJson(text);
  const insights = parsed === null ? null : validateInsights(parsed, new Set(byId.keys()));
  if (insights === null) return json(500, { error: "bad_model_output" });

  if (insights.length === 0) {
    return json(200, { surfaced: false, inserted: 0, reason: "no_qualifying_patterns" });
  }

  // ignoreDuplicates makes conflicting rows silent no-ops; .select() then
  // returns only the rows actually inserted, which is our "new this run".
  const { data: insertedRows, error: insErr } = await admin
    .from("insights")
    .upsert(
      insights.map((i) => {
        const c = byId.get(i.candidate_id)!;
        return {
          user_id: userId,
          claim: i.claim,
          evidence: i.evidence,
          // Derived from the supporting-day count, not from the model.
          confidence: c.confidence,
          suggested_action: i.suggested_action,
          window_days: WINDOW_DAYS,
          pattern_key: c.patternKey,
          support_days: c.n,
          claim_norm: normalizeClaim(i.claim),
          model: ANTHROPIC_MODEL,
        };
      }),
      { onConflict: "user_id,pattern_key", ignoreDuplicates: true },
    )
    .select("id");
  if (insErr) return json(500, { error: "insert_failed", detail: insErr.message });

  const inserted = insertedRows?.length ?? 0;
  return json(200, { surfaced: inserted > 0, inserted });
});
