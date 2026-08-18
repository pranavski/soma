// parse-meal
//
// Takes a meal row id + either a photo path or a voice transcript,
// asks Claude to extract structured items + dish name + calorie range,
// writes the result back into `meals` and `meal_items`.
//
// Photo branch: the image (private `meal-photos` bucket, path
// `<user_id>/<meal_id>.<ext>`) is downloaded with the service role and
// run through a hosted object-detection model (Roboflow). The detected
// labels are rendered as a transcript-shaped input and fed to the SAME
// Claude step as voice — detection augments the existing reasoning layer,
// it does not replace it. Raw detections persist to `meals.detections`
// for auditing and threshold tuning. Any detection failure (missing
// config, download error, timeout, zero confident labels) lands on the
// same 422 fallback as a Claude failure — the row flips to 'failed' and
// the client's manual-correction path takes over.
//
// Contract (request):
//   { meal_id: uuid, photo_path?: string, voice_transcript?: string }
// Contract (success 200):
//   { dish_name, cuisine, calories_low, calories_high, items: [{name, quantity}], ... }
// Contract (Claude/detection failure 422):
//   { fallback: { dish_name: null, cuisine: null, calories_low: null, ... } }
//
// Retrieval-augmented: before calling Claude, we fetch this user's last ~20
// confirmed corrections and the top ~50 global dish_aliases across all
// cuisines and inject them into the prompt as grounding. This is not a
// fine-tune — it's cheap, per-call retrieval that keeps corrections local
// to the user (via RLS on meal_corrections) while sharing benign
// canonical-name → alias mappings across the community (dish_aliases).
//
// Secrets required (set via `supabase secrets set ...`):
//   ANTHROPIC_API_KEY
//   ROBOFLOW_API_KEY              (photo branch)
//   ROBOFLOW_MODEL_ID             (photo branch, e.g. "food-detection-xxxx/1")
//   ROBOFLOW_ENDPOINT             (optional, default https://serverless.roboflow.com)
//   ROBOFLOW_MIN_CONFIDENCE       (optional, default 0.4)
//   SUPABASE_URL                  (auto-injected)
//   SUPABASE_ANON_KEY             (auto-injected)
//   SUPABASE_SERVICE_ROLE_KEY     (auto-injected)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  type RoboflowPrediction,
  detectionTranscript,
  parsePredictions,
  summarizeDetections,
} from "./detection.ts";
import { matchAnchors, matchFdcEntries, renderAnchors } from "./fdc.ts";

const ANTHROPIC_MODEL = "claude-sonnet-4-6";

type ParseRequest = {
  meal_id: string;
  photo_path?: string | null;
  voice_transcript?: string | null;
};

type MacroRange = {
  protein_g_low: number;
  protein_g_high: number;
  carbs_g_low: number;
  carbs_g_high: number;
  fat_g_low: number;
  fat_g_high: number;
  fiber_g_low: number;
  fiber_g_high: number;
};

/// Caffeine and alcohol sit outside MacroRange deliberately. They are not
/// macronutrients, they are anchored against a reference table rather than
/// estimated freehand (see fdc.ts), and the insight engine reads them
/// through time windows the macros have no equivalent of.
type StimulantRange = {
  caffeine_mg_low: number;
  caffeine_mg_high: number;
  alcohol_g_low: number;
  alcohol_g_high: number;
};

type Cuisine =
  | "south_asian"
  | "east_asian"
  | "southeast_asian"
  | "middle_eastern"
  | "mediterranean"
  | "african"
  | "latin_american"
  | "caribbean"
  | "western"
  | "other";

const CUISINE_VALUES: Cuisine[] = [
  "south_asian",
  "east_asian",
  "southeast_asian",
  "middle_eastern",
  "mediterranean",
  "african",
  "latin_american",
  "caribbean",
  "western",
  "other",
];

type ParsedItem = { name: string; quantity: string | null } & Partial<MacroRange>;

type ParsedMeal = {
  dish_name: string;
  cuisine: Cuisine;
  calories_low: number;
  calories_high: number;
  items: ParsedItem[];
} & MacroRange & StimulantRange;

const FALLBACK = {
  fallback: {
    dish_name: null,
    cuisine: null,
    calories_low: null,
    calories_high: null,
    protein_g_low: null,
    protein_g_high: null,
    carbs_g_low: null,
    carbs_g_high: null,
    fat_g_low: null,
    fat_g_high: null,
    fiber_g_low: null,
    fiber_g_high: null,
    caffeine_mg_low: null,
    caffeine_mg_high: null,
    alcohol_g_low: null,
    alcohol_g_high: null,
    items: [] as ParsedItem[],
  },
};

// Strict JSON contract — see docs/food-body-record-mvp-spec.md §parse-meal.
// Calorie ranges, never bare numbers. Ranges must honor uncertainty.
//
// The ethnic-cuisine block is deliberately long — the model was defaulting
// to Western interpretations and mis-labelling South Asian dishes as
// "curry" or "stew". The named seed list plus few-shot examples pushes it
// to recognize dishes by their native names first and infer components.
const SYSTEM_PROMPT = `You parse short, casual food descriptions into a strict JSON object.

Return EXACTLY this JSON shape, with no prose, no markdown, no code fences:
{
  "dish_name": string,
  "cuisine": "south_asian" | "east_asian" | "southeast_asian" | "middle_eastern" | "mediterranean" | "african" | "latin_american" | "caribbean" | "western" | "other",
  "calories_low": integer,
  "calories_high": integer,
  "protein_g_low": integer, "protein_g_high": integer,
  "carbs_g_low":   integer, "carbs_g_high":   integer,
  "fat_g_low":     integer, "fat_g_high":     integer,
  "fiber_g_low":   integer, "fiber_g_high":   integer,
  "caffeine_mg_low": integer, "caffeine_mg_high": integer,
  "alcohol_g_low":   integer, "alcohol_g_high":   integer,
  "items": [{
    "name": string, "quantity": string | null,
    "protein_g_low": integer, "protein_g_high": integer,
    "carbs_g_low":   integer, "carbs_g_high":   integer,
    "fat_g_low":     integer, "fat_g_high":     integer,
    "fiber_g_low":   integer, "fiber_g_high":   integer
  }, ...]
}

Rules:
- dish_name: short lowercase natural label using the dish's native name where possible (e.g. "dal makhani with jeera rice", "pho bo", "shakshuka"), no trailing punctuation. Do NOT translate ethnic names into generic English ("curry", "stew", "rice bowl") when a specific name exists.
- cuisine: one of the enum values above. Use "western" only when the dish is clearly European or American in origin. When unsure between two, pick the one that best matches the dish's native name.
- calories_low / calories_high: integer kcal estimate for the WHOLE meal. calories_high > calories_low. Range must honor uncertainty — span at least ~25% of the midpoint (e.g. 520–680, not 600–610).
- protein/carbs/fat/fiber _g_low/_high: integer gram estimates for the WHOLE meal, same ~25%-of-midpoint uncertainty rule. high >= low. Use 0/0 only when the nutrient is genuinely absent.
- caffeine_mg_low / caffeine_mg_high: integer milligrams of caffeine in the WHOLE meal. alcohol_g_low / alcohol_g_high: integer grams of pure ethanol in the WHOLE meal. Use 0/0 — not a guess — when the meal plainly contains neither, which is most meals. When reference values are supplied below, base these on them and multiply by the number of servings described; do not estimate from memory. These two ranges may be tighter than 25% of the midpoint, because a standard serving is a known quantity.
- items: 1–6 short component names with per-item macro ranges. quantity is a short string like "1 cup" or "2 slices", or null if unstated. Item macros should roughly sum to meal totals.
- If the input is vague, still produce your best guess. Do NOT refuse.

Ethnic-cuisine recognition — READ CAREFULLY:
Recognize dishes from South Asian, East Asian, Southeast Asian, Middle Eastern, Mediterranean, African, Latin American, and Caribbean cuisines by their native names. When the input names or describes such a dish, infer the standard components (rice, lentils, vegetables, dairy, oil, spices) even when explicit ingredients are omitted.

Non-exhaustive seed list — treat as known dishes, not unknowns:
- South Asian: dal makhani, dal tadka, chana masala, rajma, kadhi, sambhar, rasam, biryani (veg/chicken/mutton), pulao, jeera rice, dosa (plain/masala), idli, vada, uttapam, upma, poha, paratha, roti, chapati, naan, palak paneer, paneer tikka, paneer bhurji, matar paneer, kadhai paneer, shahi paneer, malai kofta, bhindi masala, aloo gobi, aloo baingan, baingan bharta, chole (bhature/kulche), pav bhaji, misal pav, vada pav, khichdi, dhokla, thepla, khaman, medu vada, korma, vindaloo, tandoori (chicken/paneer), tikka, kebab, kathi roll, samosa, pakora, kachori, gulab jamun, rasgulla, kheer, halwa, lassi, chaat, pani puri, bhel puri, dahi puri, sev puri.
- East Asian: pho, banh mi (also SE Asian), ramen (shoyu/miso/tonkotsu/shio), udon, soba, donburi, katsu, karaage, onigiri, okonomiyaki, takoyaki, sushi, sashimi, nigiri, temaki, chirashi, bibimbap, bulgogi, kimchi jjigae, sundubu jjigae, japchae, tteokbokki, mapo tofu, kung pao, mala hotpot, xiao long bao, char siu, congee, dim sum, jian bing, hot pot.
- Southeast Asian: pad thai, pad see ew, tom yum, tom kha, som tam, green/red/massaman curry, khao pad, laksa, nasi goreng, nasi lemak, mee goreng, satay, rendang, gado gado, bun cha, bun bo hue, com tam.
- Middle Eastern: shawarma, kebab, kofta, kibbeh, mezze, hummus, baba ganoush, tabbouleh, fattoush, mansaf, mujadara, koshari (also African), falafel, shakshuka, muhammara, labneh, mansaf.
- Mediterranean: moussaka, souvlaki, spanakopita, dolma, tzatziki, paella (also western-adjacent), gyros.
- African: injera + tibs / wat / doro wat / shiro / kitfo, jollof rice, egusi, fufu, suya, bobotie, bunny chow.
- Latin American: tacos (al pastor/carnitas/pescado), tamales, pupusas, arepas, empanadas, ceviche, feijoada, mole, chilaquiles, pozole, birria, lomo saltado.
- Caribbean: jerk chicken, roti, curry goat, ackee and saltfish, pelau, escovitch fish, doubles.

Few-shot examples (native-name inputs → correct JSON output shape and cuisine tag):

Input: "dal makhani with rice"
Output cues: dish_name "dal makhani with rice", cuisine "south_asian", items include black lentils, tomato, cream/butter, basmati rice. Cal range ~520–700 for a normal portion.

Input: "chicken biryani"
Output cues: dish_name "chicken biryani", cuisine "south_asian", items include basmati rice, marinated chicken, whole spices, fried onions, yogurt. Cal range ~650–900.

Input: "masala dosa with sambar"
Output cues: dish_name "masala dosa with sambar", cuisine "south_asian", items include rice-lentil crepe, spiced potato, sambar (lentil-vegetable stew), coconut chutney. Cal range ~450–650.

Input: "pho bo"
Output cues: dish_name "pho bo", cuisine "southeast_asian", items include rice noodles, beef broth, brisket/rare beef, herbs. Cal range ~450–650.

Input: "shakshuka"
Output cues: dish_name "shakshuka", cuisine "middle_eastern", items include eggs, tomato, bell pepper, olive oil, spices. Cal range ~350–550.

Input: "chana masala"
Output cues: dish_name "chana masala", cuisine "south_asian", items include chickpeas, tomato, onion, ginger-garlic, spices. Cal range ~380–540.

Do not include the example text in your output — only the JSON object for the actual input.`;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const MACRO_KEYS = [
  "protein_g_low", "protein_g_high",
  "carbs_g_low",   "carbs_g_high",
  "fat_g_low",     "fat_g_high",
  "fiber_g_low",   "fiber_g_high",
] as const;

function isMacroRangeOk(o: Record<string, unknown>, itemLevel: boolean): boolean {
  for (const k of MACRO_KEYS) {
    const v = o[k];
    if (itemLevel && v === undefined) continue; // items may omit macros
    if (!Number.isInteger(v)) return false;
    if ((v as number) < 0) return false;
  }
  const pairs: [string, string][] = [
    ["protein_g_low", "protein_g_high"],
    ["carbs_g_low", "carbs_g_high"],
    ["fat_g_low", "fat_g_high"],
    ["fiber_g_low", "fiber_g_high"],
  ];
  for (const [lo, hi] of pairs) {
    if (o[lo] === undefined && itemLevel) continue;
    if ((o[hi] as number) < (o[lo] as number)) return false;
  }
  return true;
}

/// Caffeine and alcohol are meal-level only — a per-item breakdown would be
/// noise, since these come from one identifiable component or none.
///
/// Unlike the macros these are required and must be non-negative: "no
/// caffeine" has to be an explicit 0, not an omission. The insight engine
/// distinguishes a parsed zero from an unparsed null (see the anyParsed
/// guard in candidates.ts), and letting the model omit the field would make
/// every meal it forgot look like an unparsed one.
function isStimulantRangeOk(o: Record<string, unknown>): boolean {
  const pairs: [string, string][] = [
    ["caffeine_mg_low", "caffeine_mg_high"],
    ["alcohol_g_low", "alcohol_g_high"],
  ];
  for (const [lo, hi] of pairs) {
    if (!Number.isInteger(o[lo]) || !Number.isInteger(o[hi])) return false;
    if ((o[lo] as number) < 0) return false;
    if ((o[hi] as number) < (o[lo] as number)) return false;
  }
  return true;
}

function isCuisine(x: unknown): x is Cuisine {
  return typeof x === "string" && (CUISINE_VALUES as string[]).includes(x);
}

function isParsedMeal(x: unknown): x is ParsedMeal {
  if (!x || typeof x !== "object") return false;
  const o = x as Record<string, unknown>;
  if (typeof o.dish_name !== "string" || o.dish_name.length === 0) return false;
  if (!isCuisine(o.cuisine)) return false;
  if (!Number.isInteger(o.calories_low) || !Number.isInteger(o.calories_high)) return false;
  const lo = o.calories_low as number;
  const hi = o.calories_high as number;
  if (lo <= 0 || hi <= lo) return false;
  if (!isMacroRangeOk(o, false)) return false;
  if (!isStimulantRangeOk(o)) return false;
  if (!Array.isArray(o.items)) return false;
  for (const it of o.items as unknown[]) {
    if (!it || typeof it !== "object") return false;
    const i = it as Record<string, unknown>;
    if (typeof i.name !== "string" || i.name.length === 0) return false;
    if (i.quantity !== null && typeof i.quantity !== "string") return false;
    if (!isMacroRangeOk(i, true)) return false;
  }
  return true;
}

// Retrieval context — user's own recent corrections + community aliases.
// We hand-format as plain text lists because Claude is much better at
// following prose-style grounding than nested JSON injected into a system
// prompt. Both queries are bounded and cached-friendly (RLS on the first
// filters by user; the second is a small table read).
type UserCorrection = {
  original_ai_guess: { dish_name?: string; cuisine?: string } | null;
  corrected_meal: {
    dish_name?: string;
    cuisine?: string;
    items?: Array<{ name?: string }>;
  } | null;
  cuisine: string | null;
};

type Alias = {
  canonical_name: string;
  alias: string;
  cuisine: string | null;
  sample_count: number;
};

async function fetchRetrievalContext(
  admin: SupabaseClient,
  userId: string,
): Promise<{ userLines: string[]; aliasLines: string[] }> {
  const userLines: string[] = [];
  const aliasLines: string[] = [];

  try {
    const { data: corrections } = await admin
      .from("meal_corrections")
      .select("original_ai_guess,corrected_meal,cuisine")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(20);

    for (const raw of (corrections ?? []) as UserCorrection[]) {
      const corrected = raw.corrected_meal ?? {};
      const original = raw.original_ai_guess ?? {};
      const dish = (corrected.dish_name ?? "").trim();
      if (!dish) continue;
      const cuisine = corrected.cuisine ?? raw.cuisine ?? "";
      const wasWrong = original.dish_name && original.dish_name !== dish;
      const comps = (corrected.items ?? [])
        .map((i) => (i?.name ?? "").trim())
        .filter((s) => s.length > 0)
        .slice(0, 4)
        .join(", ");
      const parts = [`- "${dish}"`];
      if (cuisine) parts.push(`(${cuisine})`);
      if (comps) parts.push(`— usually: ${comps}`);
      if (wasWrong) parts.push(`(was mis-guessed as "${original.dish_name}")`);
      userLines.push(parts.join(" "));
    }
  } catch {
    // Table may not exist yet on cold envs — proceed without user context.
  }

  try {
    const { data: aliases } = await admin
      .from("dish_aliases")
      .select("canonical_name,alias,cuisine,sample_count")
      .order("sample_count", { ascending: false })
      .limit(50);

    for (const a of (aliases ?? []) as Alias[]) {
      if (!a.canonical_name || !a.alias) continue;
      const parts = [`- "${a.alias}" → "${a.canonical_name}"`];
      if (a.cuisine) parts.push(`(${a.cuisine})`);
      aliasLines.push(parts.join(" "));
    }
  } catch {
    // ditto
  }

  return { userLines, aliasLines };
}

function buildUserMessage(
  transcript: string,
  ctx: { userLines: string[]; aliasLines: string[] },
): string {
  const blocks: string[] = [];
  if (ctx.userLines.length > 0) {
    blocks.push(
      "Known dishes this user has logged and confirmed (prefer matching one of these when the input is close):\n" +
        ctx.userLines.join("\n"),
    );
  }
  if (ctx.aliasLines.length > 0) {
    blocks.push(
      "Community-learned aliases (when the input matches an alias, use the canonical name):\n" +
        ctx.aliasLines.join("\n"),
    );
  }
  // Reference values for any caffeinated or alcoholic item named in the
  // transcript. Matched here, before the single Claude call, rather than
  // against the parsed item names — those do not exist yet, and looking them
  // up afterwards would cost a second round trip on the logging path.
  const anchorBlock = renderAnchors(matchAnchors(transcript));
  if (anchorBlock.length > 0) blocks.push(anchorBlock);

  // Supplementary per-100g composition, when the committed FDC extract has
  // anything relevant. Absent by default — see fdc.ts.
  const fdcMatches = matchFdcEntries(transcript);
  if (fdcMatches.length > 0) {
    blocks.push(
      "USDA FoodData Central composition per 100 g, for reference:\n" +
        fdcMatches.map((e) =>
          `- ${e.description}: ` +
          Object.entries(e.per_100g).map(([k, v]) => `${k} ${v}`).join(", ")
        ).join("\n"),
    );
  }

  blocks.push(`Input: ${transcript}`);
  return blocks.join("\n\n");
}

async function callClaude(
  transcript: string,
  ctx: { userLines: string[]; aliasLines: string[] },
): Promise<ParsedMeal | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return null;
  const userMessage = buildUserMessage(transcript, ctx);
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
        max_tokens: 1024,
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
  if (typeof text !== "string") return null;
  // Strip accidental ``` fences without growing surface area.
  const cleaned = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    return null;
  }
  return isParsedMeal(parsed) ? parsed : null;
}

// Roboflow hosted-API detection. Model + endpoint stay in env so the
// model can be swapped without a code change.
type RoboflowConfig = {
  apiKey: string;
  modelId: string;
  endpoint: string;
  minConfidence: number;
};

function roboflowConfig(): RoboflowConfig | null {
  const apiKey = Deno.env.get("ROBOFLOW_API_KEY");
  const modelId = Deno.env.get("ROBOFLOW_MODEL_ID");
  if (!apiKey || !modelId) return null;
  const endpoint = (Deno.env.get("ROBOFLOW_ENDPOINT") ?? "https://serverless.roboflow.com")
    .replace(/\/+$/, "");
  const raw = Number(Deno.env.get("ROBOFLOW_MIN_CONFIDENCE") ?? "0.4");
  const minConfidence = Number.isFinite(raw) && raw >= 0 && raw <= 1 ? raw : 0.4;
  return { apiKey, modelId, endpoint, minConfidence };
}

const ROBOFLOW_TIMEOUT_MS = 15_000;
const ROBOFLOW_RETRY_DELAY_MS = 1_000;

/// One retry on timeout / network error / 5xx; 4xx fails immediately
/// (bad model id or key won't fix itself on a second attempt).
async function callRoboflow(
  cfg: RoboflowConfig,
  imageBase64: string,
): Promise<RoboflowPrediction[] | null> {
  const url = `${cfg.endpoint}/${cfg.modelId}?api_key=${encodeURIComponent(cfg.apiKey)}`;
  for (let attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) {
      await new Promise((resolve) => setTimeout(resolve, ROBOFLOW_RETRY_DELAY_MS));
    }
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), ROBOFLOW_TIMEOUT_MS);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: imageBase64,
        signal: ctrl.signal,
      });
      if (res.status >= 500) continue;
      if (!res.ok) return null;
      let payload: unknown;
      try {
        payload = await res.json();
      } catch {
        return null;
      }
      return parsePredictions(payload);
    } catch {
      // timeout or network error — fall through to the retry
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "missing_bearer" });

  let body: ParseRequest;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!body.meal_id) return json(400, { error: "missing_meal_id" });
  const hasPhoto = typeof body.photo_path === "string" && body.photo_path.length > 0;
  const hasVoice = typeof body.voice_transcript === "string" && body.voice_transcript.length > 0;
  if (hasPhoto === hasVoice) {
    return json(400, { error: "exactly_one_of_photo_path_or_voice_transcript" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Caller-scoped client: verifies the JWT and enforces ownership via RLS.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: meal, error: ownErr } = await userClient
    .from("meals")
    .select("id,user_id")
    .eq("id", body.meal_id)
    .maybeSingle();
  if (ownErr || !meal) return json(404, { error: "meal_not_found_or_forbidden" });

  const admin = createClient(supabaseUrl, serviceKey);

  let parsed: ParsedMeal | null = null;
  // Raw detector output — persisted even when the parse fails, so bad
  // parses can be audited against what the model actually saw.
  let detectionRecord: Record<string, unknown> | null = null;

  if (hasVoice) {
    const ctx = await fetchRetrievalContext(admin, meal.user_id);
    parsed = await callClaude(body.voice_transcript!, ctx);
  } else {
    // The path layout is <user_id>/<meal_id>.<ext>; a path outside the
    // caller's own folder is an attempt to parse someone else's object.
    const path = body.photo_path!;
    if (!path.startsWith(`${meal.user_id}/`)) {
      return json(403, { error: "photo_path_not_owned" });
    }
    const cfg = roboflowConfig();
    if (cfg) {
      const { data: file } = await admin.storage.from("meal-photos").download(path);
      if (file) {
        const b64 = encodeBase64(new Uint8Array(await file.arrayBuffer()));
        const predictions = await callRoboflow(cfg, b64);
        if (predictions) {
          detectionRecord = {
            model_id: cfg.modelId,
            min_confidence: cfg.minConfidence,
            predictions,
            detected_at: new Date().toISOString(),
          };
          const items = summarizeDetections(predictions, cfg.minConfidence);
          if (items.length > 0) {
            const ctx = await fetchRetrievalContext(admin, meal.user_id);
            parsed = await callClaude(detectionTranscript(items), ctx);
          }
        }
      }
    }
  }

  if (!parsed) {
    await admin
      .from("meals")
      .update({
        parse_status: "failed",
        parsed_at: new Date().toISOString(),
        ...(detectionRecord ? { detections: detectionRecord } : {}),
      })
      .eq("id", meal.id);
    return json(422, FALLBACK);
  }

  // Success path — service-role write of the parsed result.
  await admin
    .from("meals")
    .update({
      dish_name: parsed.dish_name,
      cuisine: parsed.cuisine,
      calories_low: parsed.calories_low,
      calories_high: parsed.calories_high,
      protein_g_low: parsed.protein_g_low,
      protein_g_high: parsed.protein_g_high,
      carbs_g_low: parsed.carbs_g_low,
      carbs_g_high: parsed.carbs_g_high,
      fat_g_low: parsed.fat_g_low,
      fat_g_high: parsed.fat_g_high,
      fiber_g_low: parsed.fiber_g_low,
      fiber_g_high: parsed.fiber_g_high,
      caffeine_mg_low: parsed.caffeine_mg_low,
      caffeine_mg_high: parsed.caffeine_mg_high,
      alcohol_g_low: parsed.alcohol_g_low,
      alcohol_g_high: parsed.alcohol_g_high,
      parse_status: "parsed",
      parsed_at: new Date().toISOString(),
      ...(detectionRecord ? { detections: detectionRecord } : {}),
    })
    .eq("id", meal.id);
  if (parsed.items.length > 0) {
    await admin.from("meal_items").insert(
      parsed.items.map((it, i) => ({
        meal_id: meal.id,
        user_id: meal.user_id,
        name: it.name,
        quantity: it.quantity,
        position: i,
        protein_g_low: it.protein_g_low ?? null,
        protein_g_high: it.protein_g_high ?? null,
        carbs_g_low: it.carbs_g_low ?? null,
        carbs_g_high: it.carbs_g_high ?? null,
        fat_g_low: it.fat_g_low ?? null,
        fat_g_high: it.fat_g_high ?? null,
        fiber_g_low: it.fiber_g_low ?? null,
        fiber_g_high: it.fiber_g_high ?? null,
      })),
    );
  }
  return json(200, parsed);
});
