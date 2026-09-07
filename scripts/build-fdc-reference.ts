// Build the committed USDA FoodData Central reference table.
//
//   deno run --allow-net --allow-write scripts/build-fdc-reference.ts
//
// Requires FDC_API_KEY (free, instant, from https://api.data.gov/signup/).
// Falls back to DEMO_KEY, which is rate limited to roughly 30 requests an
// hour — enough for this script, which makes one request per search term.
//
// Output: supabase/functions/_shared/fdc-reference.json, which IS COMMITTED.
// parse-meal reads that file at import time and never calls this API, so
// there is no runtime dependency, no key in the deployed function, no
// latency added to the 10-second logging path, and no new third party for
// the privacy policy to disclose. Re-run this script only to refresh the
// data, and review the diff like any other source change.
//
// ─── Why the list is short and lopsided ─────────────────────────────────────
//
// This is not a general nutrition database — FoodData Central already is
// one, with 300k+ foods, and duplicating it here would be pointless. The
// table exists to anchor the numbers a language model is genuinely bad at
// recalling, which is a narrow set:
//
//   * caffeine in mg. "A coffee" spans ~70-140 mg depending on brew and
//     volume, an espresso is ~63 mg, and green tea is a third of black.
//     These are precise, unintuitive, and the whole caffeine x sleep
//     finding rests on getting them roughly right.
//   * alcohol in g of ethanol. Nobody thinks in grams; the parse has to
//     convert from drinks, and the standard-drink equivalences are exact.
//   * fiber in high-fiber staples, where estimates drift worst (legumes and
//     bran are far higher than intuition suggests).
//
// Calories and protein are deliberately NOT anchored. The model already
// estimates them acceptably, they are shown as wide ranges, and every food
// added here is a food someone has to keep verified.

const API_KEY = Deno.env.get("FDC_API_KEY") ?? "DEMO_KEY";
const OUT = new URL("../supabase/functions/_shared/fdc-reference.json", import.meta.url);

/// Nutrient ids we keep, per 100 g as FDC reports them.
const NUTRIENTS: Record<number, string> = {
  1008: "kcal",
  1003: "protein_g",
  1079: "fiber_g",
  1057: "caffeine_mg",
  1018: "alcohol_g",
};

/// One search term per request. `keep` filters the results down to the
/// entries worth committing — FDC search is fuzzy, and "beer" alone returns
/// non-alcoholic beer and beer-battered fish.
const QUERIES: { term: string; keep: RegExp; limit: number }[] = [
  { term: "coffee brewed", keep: /^Beverages, coffee, brewed/i, limit: 6 },
  { term: "coffee espresso", keep: /espresso/i, limit: 3 },
  { term: "coffee instant", keep: /coffee, instant/i, limit: 3 },
  { term: "tea brewed black", keep: /^Beverages, tea, black|tea, brewed/i, limit: 4 },
  { term: "tea green brewed", keep: /tea, green/i, limit: 3 },
  { term: "energy drink", keep: /energy drink/i, limit: 4 },
  { term: "cola carbonated", keep: /carbonated.*cola|cola,/i, limit: 4 },
  { term: "chocolate dark", keep: /chocolate/i, limit: 4 },
  { term: "beer regular", keep: /^Alcoholic beverage, beer/i, limit: 4 },
  { term: "wine table red", keep: /^Alcoholic beverage, wine/i, limit: 5 },
  { term: "distilled spirits", keep: /distilled/i, limit: 3 },
  { term: "beans black cooked", keep: /beans/i, limit: 4 },
  { term: "lentils cooked", keep: /lentils/i, limit: 3 },
  { term: "chickpeas cooked", keep: /chickpea|garbanzo/i, limit: 3 },
  { term: "bran cereal wheat", keep: /bran/i, limit: 4 },
  { term: "oats rolled dry", keep: /oats/i, limit: 3 },
  { term: "bread whole wheat", keep: /bread, whole/i, limit: 3 },
  { term: "broccoli raw", keep: /broccoli/i, limit: 2 },
  { term: "avocado raw", keep: /avocado/i, limit: 2 },
  { term: "almonds", keep: /almonds/i, limit: 2 },
  { term: "raspberries raw", keep: /raspberries|blackberries/i, limit: 2 },
  { term: "sweet potato cooked", keep: /sweet potato/i, limit: 2 },
];

type Entry = {
  fdc_id: number;
  description: string;
  per_100g: Record<string, number>;
};

async function search(term: string): Promise<unknown[]> {
  const url = new URL("https://api.nal.usda.gov/fdc/v1/foods/search");
  url.searchParams.set("query", term);
  // SR Legacy and Foundation are the curated, lab-analysed datasets. Branded
  // is user-submitted label data and is far noisier.
  url.searchParams.set("dataType", "SR Legacy,Foundation");
  url.searchParams.set("pageSize", "25");
  url.searchParams.set("api_key", API_KEY);

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`FDC search "${term}" failed: ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  return body.foods ?? [];
}

function toEntry(food: Record<string, unknown>): Entry | null {
  const per100g: Record<string, number> = {};
  for (const n of (food.foodNutrients ?? []) as Record<string, unknown>[]) {
    const key = NUTRIENTS[n.nutrientId as number];
    if (key === undefined) continue;
    const value = n.value;
    if (typeof value !== "number") continue;
    per100g[key] = value;
  }
  // An entry with no caffeine, no alcohol and no fiber is not doing the job
  // this table exists for.
  const useful = ["caffeine_mg", "alcohol_g", "fiber_g"].some((k) => (per100g[k] ?? 0) > 0);
  if (!useful) return null;
  return {
    fdc_id: food.fdcId as number,
    description: food.description as string,
    per_100g: per100g,
  };
}

// Resumable. DEMO_KEY allows only ~30 requests an hour, so a full build from
// cold will usually stop partway through with a 429. Losing the work done so
// far would make the table effectively unbuildable without a paid-tier key,
// so previous output is loaded first, new results are merged into it, and a
// rate-limit failure writes what it has rather than throwing it away.
const entries: Entry[] = [];
const seen = new Set<number>();
const doneTerms = new Set<string>();

try {
  const existing = JSON.parse(await Deno.readTextFile(OUT));
  for (const e of existing.entries ?? []) {
    entries.push(e);
    seen.add(e.fdc_id);
  }
  for (const t of existing.completed_terms ?? []) doneTerms.add(t);
  console.error(`resuming: ${entries.length} entries, ${doneTerms.size} terms already done`);
} catch {
  // No previous output — first run.
}

let rateLimited = false;

for (const { term, keep, limit } of QUERIES) {
  if (doneTerms.has(term)) continue;
  let foods: unknown[];
  try {
    foods = await search(term);
  } catch (e) {
    if (String(e).includes("429")) {
      console.error(`\nrate limited at "${term}" — writing partial results, re-run to continue`);
      rateLimited = true;
      break;
    }
    throw e;
  }
  doneTerms.add(term);
  let kept = 0;
  for (const food of foods as Record<string, unknown>[]) {
    if (kept >= limit) break;
    const description = String(food.description ?? "");
    if (!keep.test(description)) continue;
    if (seen.has(food.fdcId as number)) continue;
    const entry = toEntry(food);
    if (entry === null) continue;
    seen.add(entry.fdc_id);
    entries.push(entry);
    kept++;
  }
  console.error(`${term}: kept ${kept}`);
}

entries.sort((a, b) => a.description.localeCompare(b.description));

const payload = {
  source: "USDA FoodData Central (SR Legacy + Foundation Foods), public domain",
  source_url: "https://fdc.nal.usda.gov/",
  generated_by: "scripts/build-fdc-reference.ts",
  generated_at: new Date().toISOString().slice(0, 10),
  units: "per 100 g as consumed; kcal, protein_g, fiber_g, caffeine_mg, alcohol_g",
  // Which search terms have been fetched, so a rate-limited run can resume
  // where it stopped instead of burning its quota re-fetching.
  completed_terms: [...doneTerms].sort(),
  entries,
};

await Deno.writeTextFile(OUT, JSON.stringify(payload, null, 2) + "\n");
console.error(`\nwrote ${entries.length} entries to ${OUT.pathname}`);
if (rateLimited) {
  console.error(
    `INCOMPLETE: ${QUERIES.length - doneTerms.size} terms remaining. ` +
      `Re-run in an hour, or set FDC_API_KEY from https://api.data.gov/signup/`,
  );
}
