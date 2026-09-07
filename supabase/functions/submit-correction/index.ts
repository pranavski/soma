// submit-correction
//
// Receives a confirmed correction from the meal-detail "not quite right?"
// sheet, writes it to `meal_corrections` (owner-scoped, RLS-enforced),
// updates the community-shared `dish_aliases` table with the newly
// learned (canonical, alias) pair, and rewrites the meal row and its
// `meal_items` so the correction is what the person sees from then on.
//
// Contract (request):
//   {
//     meal_id: uuid | null,
//     original_ai_guess: { dish_name?, cuisine?, ... } | null,
//     corrected_meal: {
//       dish_name: string,
//       cuisine: Cuisine,
//       calories_low: int,
//       calories_high: int,
//       items?: [{ name: string, quantity?: string | null }]
//     },
//     photo_url?: string | null
//   }
// Contract (success 200): { id: uuid }
//
// Key design decisions:
//   * We revalidate EVERY field server-side. Never trust the client — the
//     original_ai_guess especially, since it's just a hint to
//     dish_aliases (was-mis-guessed-as).
//   * dish_aliases is written with the SERVICE ROLE and only from this
//     function. Clients cannot write to it directly (RLS blocks all).
//   * We store only benign name-mapping data across users (canonical
//     name + alias + cuisine + counts). No user IDs, no macros, no
//     photos. This is the ONLY cross-user leak surface — keep it tight.
//   * Aliases are only recorded when the correction actually renames the
//     dish. If the user just fixed a component list, we archive the
//     correction but don't touch dish_aliases.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

type Cuisine =
  | "south_asian" | "east_asian" | "southeast_asian" | "middle_eastern"
  | "mediterranean" | "african" | "latin_american" | "caribbean"
  | "western" | "other";

const CUISINE_VALUES: Cuisine[] = [
  "south_asian", "east_asian", "southeast_asian", "middle_eastern",
  "mediterranean", "african", "latin_american", "caribbean",
  "western", "other",
];

type Item = { name: string; quantity: string | null };

type CorrectedMeal = {
  dish_name: string;
  cuisine: Cuisine;
  calories_low: number;
  calories_high: number;
  items: Item[];
};

type Request = {
  meal_id?: string | null;
  original_ai_guess?: unknown;
  corrected_meal: unknown;
  photo_url?: string | null;
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isCuisine(x: unknown): x is Cuisine {
  return typeof x === "string" && (CUISINE_VALUES as string[]).includes(x);
}

function normalizeName(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, " ");
}

// Strict revalidation of the client-supplied corrected_meal. Anything the
// client sends that doesn't match this shape is a 400 — better a hard
// bounce than to poison the retrieval store with garbage.
function parseCorrectedMeal(x: unknown): CorrectedMeal | null {
  if (!x || typeof x !== "object") return null;
  const o = x as Record<string, unknown>;
  const dish = typeof o.dish_name === "string" ? o.dish_name.trim() : "";
  if (dish.length === 0 || dish.length > 120) return null;
  if (!isCuisine(o.cuisine)) return null;
  if (!Number.isInteger(o.calories_low) || !Number.isInteger(o.calories_high)) return null;
  const lo = o.calories_low as number;
  const hi = o.calories_high as number;
  if (lo <= 0 || hi < lo || hi > 10_000) return null;

  const rawItems = Array.isArray(o.items) ? o.items : [];
  const items: Item[] = [];
  for (const raw of rawItems) {
    if (!raw || typeof raw !== "object") continue;
    const it = raw as Record<string, unknown>;
    const name = typeof it.name === "string" ? it.name.trim() : "";
    if (!name) continue;
    const qty = typeof it.quantity === "string" ? it.quantity.trim() : null;
    items.push({ name: name.slice(0, 80), quantity: qty && qty.length > 0 ? qty.slice(0, 40) : null });
    if (items.length >= 12) break;
  }

  return {
    dish_name: dish.slice(0, 120),
    cuisine: o.cuisine as Cuisine,
    calories_low: lo,
    calories_high: hi,
    items,
  };
}

// original_ai_guess is stored as-is (jsonb) but we only trust a small
// subset of it downstream — the dish_name for alias-learning.
function parseOriginal(x: unknown): { dish_name?: string; cuisine?: string } | null {
  if (!x || typeof x !== "object") return null;
  const o = x as Record<string, unknown>;
  const out: { dish_name?: string; cuisine?: string } = {};
  if (typeof o.dish_name === "string") out.dish_name = o.dish_name.slice(0, 200);
  if (isCuisine(o.cuisine)) out.cuisine = o.cuisine;
  return out;
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "missing_bearer" });

  let body: Request;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const corrected = parseCorrectedMeal(body.corrected_meal);
  if (!corrected) return json(400, { error: "invalid_corrected_meal" });

  const original = parseOriginal(body.original_ai_guess);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // JWT verification via user-scoped client. We only extract user_id — all
  // writes happen through the service-role client below so we can also
  // upsert into dish_aliases (which is read-only for authenticated).
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return json(401, { error: "unauthorized" });
  const userId = userData.user.id;

  // If a meal_id is provided, verify the caller owns it before archiving.
  // Prevents authenticated users from stapling corrections onto other
  // users' rows (which would leak dish_name back through the meal-detail
  // read path if they later queried by meal_id).
  let mealId: string | null = null;
  if (typeof body.meal_id === "string" && body.meal_id.length > 0) {
    const { data: meal } = await userClient
      .from("meals")
      .select("id")
      .eq("id", body.meal_id)
      .maybeSingle();
    if (!meal) return json(404, { error: "meal_not_found_or_forbidden" });
    mealId = body.meal_id;
  }

  const admin = createClient(supabaseUrl, serviceKey);

  // 1) Archive the correction. RLS on meal_corrections is owner-only for
  //    select/insert; we pass the user_id explicitly since we're using
  //    the service role.
  const { data: inserted, error: insErr } = await admin
    .from("meal_corrections")
    .insert({
      user_id: userId,
      meal_id: mealId,
      original_ai_guess: original,
      corrected_meal: corrected,
      photo_url: typeof body.photo_url === "string" ? body.photo_url : null,
      cuisine: corrected.cuisine,
    })
    .select("id")
    .single();
  if (insErr || !inserted) return json(500, { error: "insert_failed" });

  // 2) If the correction actually renamed the dish, teach the community
  //    the alias. `original.dish_name → corrected.dish_name` is the
  //    learned mapping. We upsert on (lower(canonical), lower(alias)).
  if (
    original?.dish_name &&
    normalizeName(original.dish_name) !== normalizeName(corrected.dish_name)
  ) {
    const canonical = normalizeName(corrected.dish_name);
    const alias = normalizeName(original.dish_name);

    // Fetch existing row (if any) so we can bump sample_count. Postgres
    // `on conflict do update set sample_count = sample_count + 1` would
    // be cleaner, but the JS client's upsert doesn't expose the SET
    // expression; two round-trips is fine at this volume.
    const { data: existing } = await admin
      .from("dish_aliases")
      .select("id,sample_count,confidence")
      .ilike("canonical_name", canonical)
      .ilike("alias", alias)
      .maybeSingle();

    if (existing) {
      const newCount = (existing.sample_count as number) + 1;
      // Confidence saturates towards 1 as more users confirm the same
      // mapping. 1 - 1/(n+1) is monotonic, bounded, and reaches 0.9 by n=9.
      const newConfidence = 1 - 1 / (newCount + 1);
      await admin
        .from("dish_aliases")
        .update({ sample_count: newCount, confidence: newConfidence })
        .eq("id", existing.id);
    } else {
      await admin.from("dish_aliases").insert({
        canonical_name: canonical,
        alias,
        cuisine: corrected.cuisine,
        confidence: 0.5,
        sample_count: 1,
      });
    }
  }

  // 3) Best-effort update of the meal row itself so the user immediately
  //    sees their correction reflected. Failure here doesn't fail the
  //    request — the correction is safely archived either way.
  if (mealId) {
    await admin
      .from("meals")
      .update({
        dish_name: corrected.dish_name,
        cuisine: corrected.cuisine,
        calories_low: corrected.calories_low,
        calories_high: corrected.calories_high,
        parse_status: "manual",
        parsed_at: new Date().toISOString(),
      })
      .eq("id", mealId)
      .eq("user_id", userId);

    // 4) The components too. The sheet pre-fills "what was in it" from
    //    meal_items and lets the person add and remove — if the edited list
    //    only ever lands in the archive, reopening the sheet shows Claude's
    //    original list again and the edit looks lost. Replace wholesale:
    //    the corrected list is the whole truth of what was in the meal.
    //    Per-item macro ranges are not carried (the sheet doesn't edit
    //    them), so the replaced rows have name, quantity and position only.
    const { error: clearErr } = await admin
      .from("meal_items")
      .delete()
      .eq("meal_id", mealId)
      .eq("user_id", userId);
    if (clearErr) {
      console.error(`submit-correction: meal_items clear failed — ${clearErr.message}`);
    } else if (corrected.items.length > 0) {
      const { error: itemsErr } = await admin.from("meal_items").insert(
        corrected.items.map((it, i) => ({
          meal_id: mealId,
          user_id: userId,
          name: it.name,
          quantity: it.quantity,
          position: i,
        })),
      );
      if (itemsErr) {
        console.error(`submit-correction: meal_items write failed — ${itemsErr.message}`);
      }
    }
  }

  return json(200, { id: inserted.id });
});
