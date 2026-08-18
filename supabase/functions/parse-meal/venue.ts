// Menu-lookup gate for parse-meal.
//
// Pure functions + static data — no fetch, no Deno.env — so this can be
// unit-tested (see venue_test.ts) without serving the function.
//
// ─── What this is for ───────────────────────────────────────────────────────
//
// "chana masala" is a dish. The model knows roughly what goes into one, every
// kitchen makes it differently, and a wide calorie range is the honest answer.
//
// "a chipotle chicken burrito bowl" is a product. The operator publishes exact
// figures, the portion is standardized to the gram, and a freehand guess is
// both wrong and needlessly wide — the same failure mode that made caffeine
// worth anchoring (see fdc.ts). The difference is that a restaurant menu can't
// live in a committed table: there are millions of them and they change.
//
// So for meals that name a business or a packaged brand, parse-meal hands
// Claude the web_search server tool and lets it read the published menu
// instead of recalling it.
//
// ─── Why this is a gate and not just "always on" ────────────────────────────
//
// Search costs seconds on a logging path that promises ten of them, and about
// a cent a query. It buys nothing at all for food someone cooked, which is
// most of what this app records. So the tool is only OFFERED when the
// transcript names something lookup-shaped; Claude then decides whether to
// actually use it.
//
// That split matters for reading the rules below. This module is a COST
// filter, deliberately loose — a false positive here costs one offered tool
// the model will usually decline. The CORRECTNESS filter is the prompt, which
// tells Claude to skip the search when the match wasn't really a business.
// Tightening these patterns until they're never wrong would mean missing the
// long tail of local restaurants, which is where a lookup helps most.
//
// Matching runs on the RAW TRANSCRIPT, before the single Claude call, for the
// same reason the FDC anchors do: parsed item names do not exist yet at the
// point the prompt is built.
//
// Casing is NOT a usable signal. Dictated transcripts and typed input both
// arrive with proper nouns uncapitalized often enough that a capital-letter
// rule would miss more than it caught, so everything here matches lowercase.

export type VenueKind =
  /// A named chain from the seed list below.
  | "chain"
  /// A packaged product sold under a brand.
  | "packaged"
  /// Ordered in rather than cooked — strong signal even when the place is
  /// never named, because "the usual from the thai place" is still a menu.
  | "delivery"
  /// Caught by the "from X" / "at X" pattern rather than by name. The long
  /// tail: every restaurant that will never be in a seed list.
  | "named_place";

export type VenueHint = {
  kind: VenueKind;
  /// What matched, phrased for the prompt.
  label: string;
};

type SeedVenue = {
  label: string;
  kind: Exclude<VenueKind, "named_place">;
  /// Word-boundary pattern matched against the lowercased transcript.
  pattern: RegExp;
};

/// Chains and packaged brands that publish nutrition, and that people name
/// without any "from"/"at" preamble — "big mac", "grande latte", "a clif bar".
///
/// This list is a convenience, not the mechanism: the `from X` / `at X`
/// patterns below are what actually generalize. Entries earn their place by
/// being said bare, so the seed list is weighted toward the handful of chains
/// whose menu items have become common nouns.
const SEED_VENUES: readonly SeedVenue[] = [
  // ── Burgers, chicken, fries ──
  { label: "McDonald's", kind: "chain", pattern: /\b(mcdonald'?s?|mcdo|big macs?|mcnuggets?|mcmuffins?|mcflurr(y|ies)|quarter pounders?)\b/ },
  { label: "Burger King", kind: "chain", pattern: /\b(burger king|whoppers?)\b/ },
  { label: "Wendy's", kind: "chain", pattern: /\bwendy'?s\b/ },
  { label: "Five Guys", kind: "chain", pattern: /\bfive guys\b/ },
  { label: "Shake Shack", kind: "chain", pattern: /\b(shake shack|shackburgers?)\b/ },
  { label: "In-N-Out", kind: "chain", pattern: /\b(in.?n.?out|animal style)\b/ },
  { label: "KFC", kind: "chain", pattern: /\b(kfc|kentucky fried)\b/ },
  { label: "Popeyes", kind: "chain", pattern: /\bpopeyes?\b/ },
  { label: "Chick-fil-A", kind: "chain", pattern: /\bchick.?fil.?a\b/ },
  { label: "Raising Cane's", kind: "chain", pattern: /\braising cane'?s\b/ },
  { label: "Nando's", kind: "chain", pattern: /\bnando'?s\b/ },

  // ── Coffee ──
  { label: "Starbucks", kind: "chain", pattern: /\b(starbucks|frappuccinos?)\b/ },
  { label: "Dunkin'", kind: "chain", pattern: /\bdunkin'?( donuts)?\b/ },
  { label: "Tim Hortons", kind: "chain", pattern: /\btim hortons?\b/ },
  { label: "Costa Coffee", kind: "chain", pattern: /\bcosta( coffee)?\b/ },
  { label: "Pret A Manger", kind: "chain", pattern: /\bpret( a manger)?\b/ },
  { label: "Blue Bottle", kind: "chain", pattern: /\bblue bottle\b/ },

  // ── Bowls, wraps, sandwiches, salads ──
  { label: "Chipotle", kind: "chain", pattern: /\bchipotle('?s)?\b(?!\s+(pepper|chili|chilli|sauce|mayo|powder|aioli))/ },
  { label: "Qdoba", kind: "chain", pattern: /\bqdoba\b/ },
  // "a glass of cava" is Spanish sparkling wine, and this app records drinks.
  { label: "Cava", kind: "chain", pattern: /(?<!\bof\s)\bcava\b(?!\s+(wine|sparkling|brut))/ },
  { label: "Sweetgreen", kind: "chain", pattern: /\bsweet ?green\b/ },
  { label: "Subway", kind: "chain", pattern: /\bsubway\b(?!\s+(ride|station|home|to))/ },
  { label: "Jimmy John's", kind: "chain", pattern: /\bjimmy john'?s\b/ },
  { label: "Jersey Mike's", kind: "chain", pattern: /\bjersey mike'?s\b/ },
  { label: "Panera", kind: "chain", pattern: /\bpanera( bread)?\b/ },
  { label: "Greggs", kind: "chain", pattern: /\bgreggs\b/ },
  { label: "Itsu", kind: "chain", pattern: /\bitsu\b/ },
  { label: "Wagamama", kind: "chain", pattern: /\bwagamama\b/ },
  { label: "Leon", kind: "chain", pattern: /\bleon\b(?!\s+(said|says))/ },

  // ── Pizza ──
  { label: "Domino's", kind: "chain", pattern: /\bdomino'?s\b/ },
  { label: "Pizza Hut", kind: "chain", pattern: /\bpizza hut\b/ },
  { label: "Papa John's", kind: "chain", pattern: /\bpapa john'?s\b/ },
  { label: "Little Caesars", kind: "chain", pattern: /\blittle caesar'?s?\b/ },
  { label: "Pizza Express", kind: "chain", pattern: /\bpizza express\b/ },

  // ── Tacos and the rest of the drive-thru ──
  { label: "Taco Bell", kind: "chain", pattern: /\btaco bell|crunchwraps?\b/ },
  { label: "Del Taco", kind: "chain", pattern: /\bdel taco\b/ },
  { label: "Panda Express", kind: "chain", pattern: /\bpanda express\b/ },
  { label: "Wingstop", kind: "chain", pattern: /\bwing ?stop\b/ },
  { label: "Arby's", kind: "chain", pattern: /\barby'?s\b/ },
  { label: "Sonic", kind: "chain", pattern: /\bsonic( drive.?in)?\b/ },
  { label: "Dairy Queen", kind: "chain", pattern: /\b(dairy queen|blizzards?)\b/ },
  { label: "Jack in the Box", kind: "chain", pattern: /\bjack in the box\b/ },

  // ── Sit-down chains ──
  { label: "Olive Garden", kind: "chain", pattern: /\bolive garden\b/ },
  { label: "The Cheesecake Factory", kind: "chain", pattern: /\bcheesecake factory\b/ },
  { label: "Applebee's", kind: "chain", pattern: /\bapplebee'?s\b/ },
  { label: "Chili's", kind: "chain", pattern: /\bchili'?s\b(?!\s+(sauce|powder))/ },
  { label: "IHOP", kind: "chain", pattern: /\bihop\b/ },
  { label: "Denny's", kind: "chain", pattern: /\bdenny'?s\b/ },
  { label: "Waffle House", kind: "chain", pattern: /\bwaffle house\b/ },
  { label: "Dishoom", kind: "chain", pattern: /\bdishoom\b/ },
  { label: "Barbeque Nation", kind: "chain", pattern: /\bbarbeque nation\b/ },
  { label: "Saravana Bhavan", kind: "chain", pattern: /\bsaravana bhavan\b/ },
  { label: "Haldiram's", kind: "chain", pattern: /\bhaldiram'?s?\b/ },
  { label: "Wow! Momo", kind: "chain", pattern: /\bwow ?momos?\b/ },

  // ── Groceries whose prepared food people log by brand ──
  { label: "Trader Joe's", kind: "chain", pattern: /\btrader joe'?s\b/ },
  { label: "Whole Foods", kind: "chain", pattern: /\bwhole foods\b/ },
  { label: "Marks & Spencer", kind: "chain", pattern: /\b(marks (and|&) spencer|m&s)\b/ },

  // ── Packaged, where the label is the whole answer ──
  { label: "Clif Bar", kind: "packaged", pattern: /\bclif( bars?)?\b/ },
  { label: "RXBAR", kind: "packaged", pattern: /\brx ?bars?\b/ },
  { label: "Quest", kind: "packaged", pattern: /\bquest (bars?|protein)\b/ },
  { label: "KIND", kind: "packaged", pattern: /\bkind bars?\b/ },
  { label: "Huel", kind: "packaged", pattern: /\bhuel\b/ },
  { label: "Soylent", kind: "packaged", pattern: /\bsoylent\b/ },
  { label: "Oatly", kind: "packaged", pattern: /\boatly\b/ },
  { label: "Amy's Kitchen", kind: "packaged", pattern: /\bamy'?s (kitchen|burritos?|bowls?)\b/ },
  { label: "Beyond Meat", kind: "packaged", pattern: /\bbeyond (meat|burgers?|sausages?)\b/ },
  { label: "Impossible Foods", kind: "packaged", pattern: /\bimpossible (burgers?|patt(y|ies)|meat)\b/ },
  { label: "Maggi", kind: "packaged", pattern: /\bmaggi\b/ },
  { label: "Ben & Jerry's", kind: "packaged", pattern: /\bben (and|&) jerry'?s\b/ },
  { label: "Halo Top", kind: "packaged", pattern: /\bhalo top\b/ },
];

/// Ordered in rather than cooked. Worth a lookup even with no name attached:
/// the model can still ask what a standard portion of the named dish runs at
/// a restaurant rather than at home, and people usually name the place in the
/// same breath.
const DELIVERY: readonly SeedVenue[] = [
  { label: "a delivery / takeout order", kind: "delivery", pattern: /\b(doordash|uber ?eats|grubhub|postmates|seamless|deliveroo|just ?eat|swiggy|zomato|foodpanda|takeaway|take ?out|delivered|drive.?thr(u|ough))\b/ },
];

/// Places that are not businesses. "at work", "from the fridge", "at 7" —
/// each of these otherwise trips the `from X` / `at X` patterns, and each is
/// common enough in real meal logs to be worth naming.
///
/// This list only has to cover the frequent cases. Anything that slips
/// through is offered to a model that has been told to skip the search when
/// the match isn't a business.
const NOT_A_VENUE = new Set([
  "home", "house", "work", "office", "desk", "school", "college", "uni",
  "university", "gym", "hospital", "hotel", "airport", "plane", "train",
  "car", "mall", "food court", "cafeteria", "canteen", "dorm", "camp",
  "mom", "moms", "mom's", "mum", "mums", "mum's", "dad", "dads", "dad's",
  "grandma", "grandmas", "grandma's", "nana", "parents", "parents'",
  "friend", "friends", "friend's", "friends'", "neighbour", "neighbor",
  "fridge", "freezer", "pantry", "cupboard", "counter", "garden", "yard",
  "scratch", "leftovers", "yesterday", "earlier", "lunch", "dinner",
  "breakfast", "brunch", "supper", "snack", "midnight", "noon", "morning",
  "afternoon", "evening", "night", "tonight", "today", "the party",
  "the wedding", "a party", "a wedding", "the market", "farmers market",
  "farmer's market", "the store", "the shop", "the supermarket", "a can",
  "a packet", "a box", "a jar", "a bag", "a tin", "the freezer",
]);

/// Words that end a venue name rather than continue it.
const PHRASE_BREAK = /^(and|with|for|on|in|at|from|then|plus|but|so|because|while|after|before|around|about|to)$/;

/// `from X` / `at X`, the pattern that generalizes past any seed list.
///
/// Captures up to three words so "at the cheesecake factory" and "from thai
/// basil kitchen" both survive, and stops at a conjunction so "from panera
/// and a coffee" doesn't swallow the coffee.
const PLACE_PATTERN =
  /\b(?:from|at)\s+(?:the\s+)?([a-z0-9][a-z0-9'’&.\-]*(?:\s+[a-z0-9'’&.\-]+){0,2})/g;

/// At most this many hints reach the prompt. More than a few is a sign the
/// pattern over-matched, and a long list would just dilute the instruction.
const MAX_HINTS = 3;

function normalize(phrase: string): string {
  return phrase.replace(/[’]/g, "'").replace(/\s+/g, " ").trim();
}

/// Trim the captured phrase back to the part that could plausibly be a name:
/// stop at a conjunction, drop a purely numeric head ("at 7", "at 7:30").
function trimToName(phrase: string): string | null {
  const words = normalize(phrase).split(" ");
  const kept: string[] = [];
  for (const w of words) {
    if (PHRASE_BREAK.test(w)) break;
    kept.push(w);
  }
  if (kept.length === 0) return null;
  if (/^[\d:.]+([ap]m)?$/.test(kept[0])) return null;
  return kept.join(" ");
}

/// Is this captured phrase a business, or a kitchen / a time of day?
///
/// Checks the whole phrase and its head word, so both "the fridge" and
/// "fridge downstairs" are rejected.
function isPlausibleVenue(name: string): boolean {
  if (NOT_A_VENUE.has(name)) return false;
  const head = name.split(" ")[0];
  if (NOT_A_VENUE.has(head)) return false;
  // A bare single letter or digit run is noise, not a restaurant.
  if (name.length < 3) return false;
  return true;
}

/// Collapse a label to the form two spellings of the same place share, so
/// the seed entry "The Cheesecake Factory" and the phrase "cheesecake
/// factory" caught by `at X` are recognized as one venue.
function dedupeKey(label: string): string {
  return label
    .toLowerCase()
    .replace(/^the\s+/, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/// Venue hints for a transcript, most specific first.
///
/// Seed matches lead because a named chain is the strongest signal available;
/// pattern matches follow because they are the guesses. A pattern match that
/// merely restates a seed match ("chipotle bowl from chipotle", "lunch at the
/// cheesecake factory") is dropped rather than listed twice.
export function detectVenues(transcript: string | null | undefined): VenueHint[] {
  if (!transcript) return [];
  const text = normalize(transcript.toLowerCase());
  if (text.length === 0) return [];

  const out: VenueHint[] = [];
  const seen: string[] = [];

  const push = (hint: VenueHint) => {
    const key = dedupeKey(hint.label);
    // Seeds are distinct from each other, so exact-match is enough for them.
    // A guessed phrase also loses to any seed it overlaps: "cheesecake
    // factory" adds nothing next to "The Cheesecake Factory".
    const clashes = hint.kind === "named_place"
      ? seen.some((k) => k === key || k.includes(key) || key.includes(k))
      : seen.includes(key);
    if (clashes) return;
    seen.push(key);
    out.push(hint);
  };

  for (const v of SEED_VENUES) {
    if (v.pattern.test(text)) push({ kind: v.kind, label: v.label });
  }

  // The `from X` / `at X` phrases, before the delivery catch-all: a named
  // place is more useful to search for than the bare fact of a delivery.
  PLACE_PATTERN.lastIndex = 0;
  for (const m of text.matchAll(PLACE_PATTERN)) {
    const name = trimToName(m[1]);
    if (!name || !isPlausibleVenue(name)) continue;
    push({ kind: "named_place", label: name });
  }

  if (out.length === 0) {
    for (const v of DELIVERY) {
      if (v.pattern.test(text)) push({ kind: v.kind, label: v.label });
    }
  }

  return out.slice(0, MAX_HINTS);
}

/// The menu-lookup block for the prompt, or "" when nothing matched.
///
/// Three things this has to get right, in order of how badly they fail:
///
/// 1. Claude must be free NOT to search. The gate is loose on purpose (see
///    the header), so the prompt carries the judgment: no business, no
///    search, and no apology about it either.
/// 2. The output contract still holds. With a server tool in play the reply
///    can contain a preamble before the search and the answer after it, so
///    the JSON has to be the last thing said.
/// 3. A published figure earns a tighter range, not a bare number. Copy the
///    reasoning the stimulant anchors already use: the uncertainty rule
///    exists because home portions vary, and a standardized menu item is
///    exactly the case where that stops being true.
export function renderVenueLookup(hints: VenueHint[]): string {
  if (hints.length === 0) return "";

  const lines = hints.map((h) => {
    switch (h.kind) {
      case "chain":
        return `- ${h.label} — a chain that publishes nutrition for its menu`;
      case "packaged":
        return `- ${h.label} — a packaged brand with a nutrition label`;
      case "delivery":
        return `- ${h.label} — restaurant portions, not home cooking`;
      case "named_place":
        return `- "${h.label}" — possibly a restaurant this person ate at`;
    }
  });

  return [
    "This meal may name a business or brand whose figures are published. You have",
    "a web_search tool; use it to read what they publish rather than recalling it:",
    ...lines,
    "",
    "- Search only if this really is a business or packaged product with published",
    "  nutrition. Plenty of these guesses are wrong — a person, a home, a generic",
    "  place. When it is wrong, skip the search and estimate as usual. Do not",
    "  mention the search, or its absence, anywhere in your output.",
    "- Search for the specific item at the size described, and prefer the operator's",
    "  own menu or nutrition page over aggregators and copies of it.",
    "- When you find published figures, base calories and macros on them for the",
    "  size described. These ranges may then be tighter than the 25%-of-midpoint",
    "  rule, for the same reason the reference servings above may be: a menu item",
    "  is a standardized quantity, and widening a known number is not honesty.",
    "- When you cannot find the item, estimate as usual at the normal range width.",
    "  A wide honest guess beats a narrow one borrowed from a different dish.",
    "- Keep the operator's name in dish_name when the person named it (\"chipotle",
    "  chicken burrito bowl\"), so the same order reads the same way next time.",
    "- Your final message must still be the JSON object and nothing else.",
  ].join("\n");
}
