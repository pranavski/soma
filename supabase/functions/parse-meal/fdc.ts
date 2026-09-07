// Nutrition anchors for parse-meal.
//
// Pure functions + static data — no fetch, no Deno.env — so this can be
// unit-tested (see fdc_test.ts) without serving the function.
//
// ─── What this is for ───────────────────────────────────────────────────────
//
// parse-meal asks Claude to estimate a meal's nutrition from a casual
// description. For calories and macros that works: the estimates are shown
// as wide ranges, and nobody is misled by "~550-700 kcal".
//
// Caffeine and alcohol are different. They feed the two best-evidenced
// findings the insight engine can produce (caffeine x sleep, alcohol x
// resting HR / HRV), the numbers are unintuitive, and they are exactly the
// kind of specific quantity a language model recalls unreliably — an
// espresso has LESS caffeine than a mug of drip coffee, which is the
// opposite of what "strong" suggests. A drifting caffeine estimate does not
// just make one meal wrong; it adds noise to the feature the correlation is
// computed over, and the finding quietly stops surfacing.
//
// So the transcript is matched against a table of standard servings before
// the model is called, and any hits are injected into the prompt as
// authoritative anchors. The model still does the parsing and still returns
// ranges — it is being given the reference values, not overruled.
//
// Matching happens on the RAW TRANSCRIPT rather than on parsed item names,
// which is what keeps this to a single Claude call: parsed items do not
// exist yet at the point the prompt is built.

import fdcReference from "../_shared/fdc-reference.json" with { type: "json" };

// ─── Standard servings ──────────────────────────────────────────────────────

export type Anchor = {
  /// What a person would say.
  label: string;
  /// Word-boundary pattern matched against the lowercased transcript.
  pattern: RegExp;
  caffeine_mg?: number;
  alcohol_g?: number;
  /// The serving the figures describe, spelled out for the prompt.
  serving: string;
};

/// Caffeine per standard serving.
///
/// Values are the USDA FoodData Central figures for these beverages at their
/// conventional serving sizes, consistent with the FDA's consumer guidance
/// that an 8 oz cup of coffee runs roughly 80-100 mg.
///
/// Order matters: the first match wins per nutrient, so more specific terms
/// ("decaf", "espresso") must precede the generic ones ("coffee").
const CAFFEINE: Anchor[] = [
  { label: "decaf coffee", pattern: /\bdecaf\w*\b/, caffeine_mg: 2, serving: "8 fl oz (240 ml) cup" },
  { label: "espresso", pattern: /\b(espressos?|ristrettos?)\b/, caffeine_mg: 63, serving: "1 shot (30 ml)" },
  // Espresso-based drinks are one or two shots plus milk; the caffeine comes
  // from the shots, not the volume, which is the intuition this corrects.
  { label: "latte / cappuccino / flat white", pattern: /\b(lattes?|cappuccinos?|flat whites?|macchiatos?|cortados?|americanos?)\b/, caffeine_mg: 63, serving: "1 shot (30 ml) of espresso; 2 if a double is described" },
  { label: "instant coffee", pattern: /\binstant coffees?\b/, caffeine_mg: 62, serving: "8 fl oz (240 ml) cup" },
  { label: "cold brew", pattern: /\bcold brews?\b/, caffeine_mg: 155, serving: "12 fl oz (355 ml)" },
  { label: "brewed coffee", pattern: /\bcoffees?\b|\bfilter coffees?\b/, caffeine_mg: 95, serving: "8 fl oz (240 ml) cup" },
  { label: "matcha", pattern: /\bmatchas?\b/, caffeine_mg: 70, serving: "8 fl oz (240 ml) prepared" },
  { label: "green tea", pattern: /\bgreen teas?\b/, caffeine_mg: 28, serving: "8 fl oz (240 ml) cup" },
  { label: "herbal tea", pattern: /\b(herbal|chamomile|rooibos|peppermint) teas?\b/, caffeine_mg: 0, serving: "8 fl oz (240 ml) cup" },
  { label: "black tea", pattern: /\b(black teas?|chai|earl grey|english breakfast)\b|\bteas?\b/, caffeine_mg: 47, serving: "8 fl oz (240 ml) cup" },
  { label: "energy drink", pattern: /\b(energy drinks?|red bull|monster|celsius)\b/, caffeine_mg: 80, serving: "8.4 fl oz (250 ml) can" },
  { label: "cola", pattern: /\b(colas?|coke|pepsi)\b/, caffeine_mg: 34, serving: "12 fl oz (355 ml) can" },
  { label: "dark chocolate", pattern: /\bdark chocolate\b/, caffeine_mg: 12, serving: "1 oz (28 g)" },
];

/// Alcohol per standard serving.
///
/// All four of these are one US standard drink — 14 g of pure ethanol — by
/// the NIAAA definition. That equivalence is the entire reason this table
/// can be short: the serving sizes differ precisely so the dose does not.
const ALCOHOL: Anchor[] = [
  { label: "beer", pattern: /\b(beers?|lagers?|ales?|ipas?|pints?|stouts?|pilsners?)\b/, alcohol_g: 14, serving: "12 fl oz (355 ml) at ~5% ABV = 1 standard drink" },
  { label: "wine", pattern: /\b(wines?|prosecco|champagne|ros(e|é) wine|sangria)\b/, alcohol_g: 14, serving: "5 fl oz (150 ml) at ~12% ABV = 1 standard drink" },
  { label: "spirits", pattern: /\b(whisk(e)?y|vodka|gins?|rum|tequila|bourbon|scotch|brandy|cognac)\b/, alcohol_g: 14, serving: "1.5 fl oz (44 ml) at 40% ABV = 1 standard drink" },
  { label: "cocktail", pattern: /\b(cocktails?|martinis?|margaritas?|negronis?|old fashioned|mojitos?|spritz|highballs?)\b/, alcohol_g: 14, serving: "1 standard cocktail = 1 standard drink; more if it names several spirits" },
];

export const SERVING_ANCHORS: readonly Anchor[] = [...CAFFEINE, ...ALCOHOL];

// ─── Matching ───────────────────────────────────────────────────────────────

export type MatchedAnchor = Anchor & { nutrient: "caffeine" | "alcohol" };

/// Anchors whose terms appear in the transcript.
///
/// At most one caffeine anchor and one alcohol anchor are returned. Two
/// caffeine lines would be worse than none: given both "espresso 63 mg" and
/// "brewed coffee 95 mg" for the phrase "espresso", the model has to pick,
/// and the specific term is always the right answer. Ordering in the tables
/// above encodes that precedence.
export function matchAnchors(transcript: string | null | undefined): MatchedAnchor[] {
  if (!transcript) return [];
  const text = transcript.toLowerCase();
  const out: MatchedAnchor[] = [];

  const caffeine = CAFFEINE.find((a) => a.pattern.test(text));
  if (caffeine) out.push({ ...caffeine, nutrient: "caffeine" });

  const alcohol = ALCOHOL.find((a) => a.pattern.test(text));
  if (alcohol) out.push({ ...alcohol, nutrient: "alcohol" });

  return out;
}

/// The anchor block for the prompt, or "" when nothing matched.
///
/// Deliberately phrased as reference values for a single serving, with the
/// count left to the model — "two coffees and a beer" needs 190 mg and 14 g,
/// and multiplying is the one arithmetic step that has to happen against the
/// actual transcript.
export function renderAnchors(matched: MatchedAnchor[]): string {
  if (matched.length === 0) return "";
  const lines = matched.map((a) => {
    const value = a.nutrient === "caffeine"
      ? `${a.caffeine_mg} mg caffeine`
      : `${a.alcohol_g} g alcohol`;
    return `- ${a.label}: ${value} per ${a.serving}`;
  });
  return [
    "USDA/NIAAA reference values for items mentioned in this meal. Use these as the",
    "basis for caffeine_mg and alcohol_g rather than estimating from memory, and",
    "multiply by how many servings the description actually implies:",
    ...lines,
  ].join("\n");
}

// ─── FoodData Central per-100g table ────────────────────────────────────────

export type FdcEntry = {
  fdc_id: number;
  description: string;
  per_100g: Record<string, number>;
};

/// The committed FDC extract, built by scripts/build-fdc-reference.ts.
///
/// May legitimately be empty: the file is generated against a rate-limited
/// public API and the serving table above carries the anchoring on its own.
/// Treat this as supplementary detail, never as a required input.
export const FDC_ENTRIES: readonly FdcEntry[] = (fdcReference.entries ?? []) as FdcEntry[];

/// Per-100g rows whose description shares a meaningful word with the
/// transcript. Used only to enrich the anchor block when the extract is
/// populated.
export function matchFdcEntries(
  transcript: string | null | undefined,
  limit = 4,
): FdcEntry[] {
  if (!transcript || FDC_ENTRIES.length === 0) return [];
  const words = new Set(
    transcript.toLowerCase().split(/[^a-z]+/).filter((w) => w.length >= 4),
  );
  if (words.size === 0) return [];

  const scored = FDC_ENTRIES.map((e) => {
    const terms = e.description.toLowerCase().split(/[^a-z]+/);
    let score = 0;
    for (const t of terms) if (words.has(t)) score++;
    return { e, score };
  }).filter((s) => s.score > 0);

  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((s) => s.e);
}
