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
// Response (`candidates` is the shortlist size, so a zero-insight run says
// whether the statistics found nothing or the model declined what it saw):
//   200 { surfaced, inserted, candidates, reflections }           — ran
//   200 { surfaced: false, reason: "insufficient_data", reflections } — gated before scoring
//   200 { surfaced: false, reason: "no_qualifying_patterns", candidates, reflections } — nothing survived, or nothing chosen
//   500 { error: "claude_call_failed", detail }                   — with the reason
//   500 { error: "bad_model_output" }                             — model broke contract
//
// Every run also rebuilds the caller's `reflections` — plain descriptions of
// what they logged, which need three days rather than the ten the statistics
// need. They carry no inference and are replaced wholesale each run; see
// reflections.ts for why they are templated rather than written by a model.
//
// Dedupe is by pattern, not wording: already-surfaced pattern_keys are
// filtered out before the model is called, and unique (user_id,
// pattern_key) backstops it — re-runs no-op on conflict.
//
// The run is not amnesiac. Every association it measures — survivor or not —
// is written to pattern_history, and a pattern that has cleared the
// correction in earlier, largely non-overlapping windows carries that into
// this run: a higher confidence tier and a line telling the model how long
// it has held. That memory only ever adds evidence. It never changes which
// hypotheses are tested, their p-values, or what clears the correction.
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
import {
  type Candidate,
  type TestedAssociation,
  MIN_REPLICATION_GAP_DAYS,
  independentPriorWindows,
  renderCandidates,
  scoreAssociations,
} from "./candidates.ts";
import { citation } from "./evidence.ts";
import { type Reflection, buildReflections } from "./reflections.ts";

// Haiku is the right tier now that the model no longer does arithmetic:
// what is left is picking plausible rows out of a scored table and writing
// one hedged sentence each. It is also the cheapest model that supports
// structured outputs, which is what lets us drop the "return ONLY JSON"
// pleading from the prompt.
const ANTHROPIC_MODEL = "claude-haiku-4-5";
const WINDOW_DAYS = 30;
const RECENT_CLAIMS_LIMIT = 15;

/// How far back pattern_history is kept. Long enough to hold several
/// non-overlapping windows (so a long-running pattern can accumulate
/// replication) without growing without bound at ~28 rows per user per day.
/// Pruned inline on every run rather than by a separate cron: it is one
/// indexed range delete on the primary key's leading columns.
const PATTERN_HISTORY_RETENTION_DAYS = 180;

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
      // fiber has been parsed and stored since the macros migration but was
      // never selected here, so the engine could not see it. caffeine and
      // alcohol are new. All three feed evidence-backed pairings.
      .select("eaten_at,eaten_date,eaten_hour,dish_name,voice_transcript,calories_low,calories_high,protein_g_low,protein_g_high,fiber_g_low,fiber_g_high,caffeine_mg_low,caffeine_mg_high,alcohol_g_low,alcohol_g_high")
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

// ─── Pattern history ────────────────────────────────────────────────────────

type HistoryRow = { pattern_key: string; run_date: string };

/// How many earlier, largely non-overlapping runs each pattern already
/// survived. Only survivors count: a pattern that was tested and rejected on
/// some past night is evidence about itself, but not evidence for itself.
async function loadPriorWindows(
  admin: SupabaseClient,
  userId: string,
  runDate: string,
): Promise<Map<string, number>> {
  const { data, error } = await admin
    .from("pattern_history")
    .select("pattern_key,run_date")
    .eq("user_id", userId)
    .eq("survived_fdr", true)
    .lt("run_date", runDate);
  if (error) {
    // History is an enhancement, not a dependency. Without it every pattern
    // reads as a first sighting — exactly how the engine behaved before this
    // table existed — which is a far better failure than skipping the run.
    console.error(`generate-insights: pattern_history read failed — ${error.message}`);
    return new Map();
  }

  const datesByPattern = new Map<string, string[]>();
  for (const row of (data ?? []) as HistoryRow[]) {
    const dates = datesByPattern.get(row.pattern_key);
    if (dates === undefined) datesByPattern.set(row.pattern_key, [row.run_date]);
    else dates.push(row.run_date);
  }

  const out = new Map<string, number>();
  for (const [patternKey, dates] of datesByPattern) {
    out.set(patternKey, independentPriorWindows(dates, runDate, MIN_REPLICATION_GAP_DAYS));
  }
  return out;
}

/// Record what this run measured, then drop what has aged out.
///
/// The upsert overwrites a same-day row rather than ignoring it: an
/// on-demand refresh at 9pm has seen more of the day than the 03:30 cron
/// did, and (user_id, run_date, pattern_key) deliberately treats every run
/// on one date as a single observation.
///
/// Best-effort throughout — failing here costs the engine its memory of
/// tonight, not tonight's insights.
async function recordHistory(
  admin: SupabaseClient,
  userId: string,
  runDate: string,
  tested: TestedAssociation[],
): Promise<void> {
  if (tested.length > 0) {
    const { error } = await admin.from("pattern_history").upsert(
      tested.map((t) => ({
        user_id: userId,
        run_date: runDate,
        pattern_key: t.patternKey,
        feature: t.feature,
        signal: t.signal,
        lag_days: t.lagDays,
        n: t.n,
        rho: t.rho,
        p_value: t.pValue,
        survived_fdr: t.survivedFdr,
      })),
      { onConflict: "user_id,run_date,pattern_key" },
    );
    if (error) {
      console.error(`generate-insights: pattern_history write failed — ${error.message}`);
    }
  }

  const cutoff = new Date();
  cutoff.setUTCDate(cutoff.getUTCDate() - PATTERN_HISTORY_RETENTION_DAYS);
  const { error: pruneErr } = await admin
    .from("pattern_history")
    .delete()
    .eq("user_id", userId)
    .lt("run_date", cutoff.toISOString().slice(0, 10));
  if (pruneErr) {
    console.error(`generate-insights: pattern_history prune failed — ${pruneErr.message}`);
  }
}

// ─── Reflections ────────────────────────────────────────────────────────────

/// Replace this user's reflection set with what the current log supports.
///
/// Replace, not append: a reflection describes the log as it stands and
/// stops being true the moment another meal is added, so the previous set
/// is not history worth keeping the way a surfaced insight is. The delete
/// covers kinds that dropped out — a caffeine reflection must disappear
/// when the afternoon coffees do, and an upsert alone would leave it there
/// forever.
///
/// Best-effort. Reflections are the consolation prize for not having enough
/// data yet; failing to write them must never cost the run its insights.
async function writeReflections(
  admin: SupabaseClient,
  userId: string,
  reflections: Reflection[],
): Promise<void> {
  if (reflections.length > 0) {
    const { error } = await admin.from("reflections").upsert(
      reflections.map((r, i) => ({
        user_id: userId,
        kind: r.kind,
        body: r.body,
        detail: r.detail,
        sort_order: i,
        window_days: WINDOW_DAYS,
        generated_at: new Date().toISOString(),
      })),
      { onConflict: "user_id,kind" },
    );
    if (error) {
      console.error(`generate-insights: reflections write failed — ${error.message}`);
      // Leaving the stale set in place beats deleting it and writing
      // nothing, so give up on the whole operation rather than falling
      // through to the delete below.
      return;
    }
  }

  const keep = reflections.map((r) => r.kind);
  let stale = admin.from("reflections").delete().eq("user_id", userId);
  if (keep.length > 0) stale = stale.not("kind", "in", `(${keep.join(",")})`);
  const { error: delErr } = await stale;
  if (delErr) {
    console.error(`generate-insights: reflections prune failed — ${delErr.message}`);
  }
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
- Never name a statistic in the copy. rho, p-values, and "correlation" are given to you so you can judge strength; the reader gets the comparison, not the coefficient. "n=14" is fine as "14 days".
- Some candidates say they "have held across N separate windows". That means the same pattern passed the same test on largely different stretches of this person's data, weeks apart — it is the strongest evidence you have that something is real rather than a coincidence, so weigh it heavily when choosing what to say. You may reflect it in plain language ("this has kept showing up over the past couple of months"), never as a count of runs, tests, or windows.
- suggested_action: a single gentle, observational next step ("worth watching whether earlier dinners shift this"), or null. Never prescriptive ("eat less X"), never a target, never medical.
- Calories only ever as ranges ("~550–700"), never a bare number.
- An association is not causation, and the copy must never imply it is.
- You will be given claims already shown to this person. Do not repeat or rephrase any of them.
- Set candidate_id to the id of the candidate each insight describes.

Published evidence — how to use it, and its hard limit:
- Some candidate lines carry a "published evidence" note: what the research literature expects for that pairing, how strong that literature is (grade A/B/C), and whether THIS person's data points the same way.
- Use it to judge plausibility. A candidate that matches a grade-A finding is far more likely to be real than a coincidence, and needs less hesitation from you. A candidate with no published evidence is not thereby wrong — most of what a person notices about themselves has never been studied — but it deserves a harder look for whether it is interpretable at all.
- When a candidate points the OPPOSITE way to the literature, say what this person's data says. Do not soften it toward the published result, do not average the two, and do not mention that a disagreement exists. Their body is the subject; the literature is context.
- You must NOT write the science. Do not state mechanisms, do not explain physiology, do not cite, quote, name, or allude to any study, and do not reuse the wording of the evidence note. The app attaches the published context itself, from its own reviewed source table, after you have chosen. Your sentence is about this person and only this person.
- Anything you write that reads as a general nutrition fact rather than an observation about these 30 days is a failure of the task, even when it is true.`;

/// The four evidence columns for one insight row, or empty when there is
/// nothing sound to attach.
///
/// All four or none — `insights_evidence_all_or_nothing` enforces the same
/// rule in the database, because a mechanism without a citation is an
/// unsourced health claim.
///
/// The `corroborated` gate is the substantive decision here. A candidate can
/// carry an evidence row while pointing the opposite way to it; in that case
/// the finding is still surfaced (the person's own data is the subject) but
/// no mechanism is attached, because the only mechanism available explains
/// something that did not happen to them.
function evidenceColumns(c: Candidate): Record<string, string> {
  if (c.evidence === undefined || c.agreement !== "corroborated") return {};
  return {
    mechanism: c.evidence.mechanism,
    evidence_source_id: c.evidence.id,
    evidence_grade: c.evidence.grade,
    evidence_citation: citation(c.evidence),
  };
}

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

/// Why a call failed, not just that it did. This job runs unattended
/// nightly across every active user; "claude_call_failed" with no reason
/// is indistinguishable between a missing key, a rate limit, and a
/// malformed request, and there is no one watching to reproduce it.
type ClaudeResult = { ok: true; text: string } | { ok: false; reason: string };

async function callClaude(userMessage: string): Promise<ClaudeResult> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return { ok: false, reason: "missing_api_key" };
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
        // max_tokens covers thinking AND the response. At 4096 against a
        // 2048 thinking budget, roughly one run in ten spent the remainder
        // deliberating and stopped before emitting any text at all
        // (stop_reason=max_tokens, no text block). Five insights need well
        // under 2000 tokens; the headroom is what keeps a nightly run from
        // failing on a long deliberation.
        max_tokens: 8192,
        // Haiku 4.5 predates adaptive thinking, so this is the older fixed
        // budget form (must be < max_tokens). Modest, but the plausible-vs-
        // spurious call is the whole reason a model is in this loop.
        thinking: { type: "enabled", budget_tokens: 2048 },
        output_config: { format: { type: "json_schema", schema: RESPONSE_SCHEMA } },
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: userMessage }],
      }),
    });
  } catch (e) {
    return { ok: false, reason: `fetch_failed: ${e instanceof Error ? e.message : e}` };
  }
  if (!res.ok) {
    // The error body carries the API's own explanation (rate_limit_error,
    // invalid_request_error and which field, overloaded_error). It never
    // contains the key.
    const body = await res.text().catch(() => "");
    return { ok: false, reason: `http_${res.status}: ${body.slice(0, 400)}` };
  }
  let payload: { content?: { type?: string; text?: string }[]; stop_reason?: string };
  try {
    payload = await res.json();
  } catch {
    return { ok: false, reason: "response_not_json" };
  }
  const text = payload?.content?.find((b) => b?.type === "text")?.text;
  if (typeof text !== "string") {
    // A thinking-only response means the budget swallowed the answer;
    // stop_reason tells us which.
    return { ok: false, reason: `no_text_block (stop_reason=${payload?.stop_reason ?? "?"})` };
  }
  return { ok: true, text };
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

  // Before the gate, and on every run rather than only on gated ones. The
  // statistics need ~10 days of paired data; a description of the log needs
  // 3, and that gap is the whole reason this layer exists. Recomputed even
  // once insights are flowing so the set never goes stale — the client
  // decides whether to show it (see InsightsViewModel).
  const reflections = buildReflections(meals, checkins, health);
  await writeReflections(admin, userId, reflections);

  if (!hasSufficientData(coverage)) {
    return json(200, {
      surfaced: false,
      inserted: 0,
      reason: "insufficient_data",
      reflections: reflections.length,
    });
  }

  const runDate = new Date().toISOString().slice(0, 10);

  // Everything already shown to this person (by pattern rather than by
  // wording — a rephrase of a surfaced finding never reaches the model), and
  // how many earlier windows each pattern has already held across. Two
  // independent reads of this user's own rows.
  const [seen, priorWindows] = await Promise.all([
    admin.from("insights").select("pattern_key").eq("user_id", userId),
    loadPriorWindows(admin, userId, runDate),
  ]);
  const seenPatterns = new Set(
    ((seen.data ?? []) as { pattern_key: string }[]).map((r) => r.pattern_key),
  );

  const { tested, candidates: scored } = scoreAssociations(meals, checkins, health, {
    priorWindows,
  });

  // Recorded before the shortlist is thinned and before the model is called.
  // What this run measured is just as true on a night that surfaces nothing,
  // and the rejections are what a replication rate is measured against.
  await recordHistory(admin, userId, runDate, tested);

  const candidates = scored
    .filter((c) => !seenPatterns.has(c.patternKey))
    // Re-number so the ids the model cites are contiguous.
    .map((c, i) => ({ ...c, id: `c${i + 1}` }));

  // Nothing survived the correction, or everything that did is old news.
  // Either way there is no call to make.
  if (candidates.length === 0) {
    return json(200, {
      surfaced: false,
      inserted: 0,
      reason: "no_qualifying_patterns",
      candidates: 0,
      reflections: reflections.length,
    });
  }

  const { data: prior } = await admin
    .from("insights")
    .select("claim")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(RECENT_CLAIMS_LIMIT);
  const priorClaims = (prior ?? []).map((r: { claim: string }) => r.claim);

  const result = await callClaude(
    buildUserMessage(candidates, lines, coverageSummary(coverage), priorClaims),
  );
  if (!result.ok) {
    console.error(`generate-insights: claude call failed — ${result.reason}`);
    return json(500, { error: "claude_call_failed", detail: result.reason });
  }

  const byId = new Map(candidates.map((c) => [c.id, c]));
  const parsed = extractJson(result.text);
  const insights = parsed === null ? null : validateInsights(parsed, new Set(byId.keys()));
  if (insights === null) return json(500, { error: "bad_model_output" });

  if (insights.length === 0) {
    // Distinct from the branch above: candidates existed, the model judged
    // none of them worth saying. `candidates` separates the two in logs.
    return json(200, {
      surfaced: false,
      inserted: 0,
      reason: "no_qualifying_patterns",
      candidates: candidates.length,
      reflections: reflections.length,
    });
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
          // The other half of what confidence was derived from, recorded for
          // the same reason as support_days: so a tier can be audited.
          support_windows: c.windows,
          claim_norm: normalizeClaim(i.claim),
          model: ANTHROPIC_MODEL,
          // The scientific half of the card, joined here rather than
          // returned by the model. Claude picked the candidate; the
          // mechanism and citation come out of the reviewed table keyed by
          // that candidate, so there is no path by which a citation can be
          // invented — the same guarantee that already covers every number.
          //
          // Attached only when this person's data agrees with the published
          // direction. A contradicting finding still surfaces, but pairing
          // it with a mechanism that explains the opposite of what they
          // experienced would be worse than saying nothing.
          ...evidenceColumns(c),
        };
      }),
      { onConflict: "user_id,pattern_key", ignoreDuplicates: true },
    )
    .select("id");
  if (insErr) return json(500, { error: "insert_failed", detail: insErr.message });

  const inserted = insertedRows?.length ?? 0;
  return json(200, {
    surfaced: inserted > 0,
    inserted,
    candidates: candidates.length,
    reflections: reflections.length,
  });
});
