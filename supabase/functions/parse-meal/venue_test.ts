import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { detectVenues, renderVenueLookup } from "./venue.ts";

const labels = (t: string) => detectVenues(t).map((h) => h.label);

Deno.test("named chains are caught without any preamble", () => {
  assertEquals(labels("chipotle chicken burrito bowl"), ["Chipotle"]);
  assertEquals(labels("big mac and medium fries"), ["McDonald's"]);
  assertEquals(labels("grande oat latte from starbucks"), ["Starbucks"]);
  assertEquals(labels("a clif bar before the gym")[0], "Clif Bar");
});

Deno.test("the from/at pattern generalizes past the seed list", () => {
  // The whole reason the pattern exists: the neighbourhood restaurant that
  // will never be in a seed list is exactly where a menu lookup helps most.
  assertEquals(labels("pad see ew from thai basil kitchen"), ["thai basil kitchen"]);
  assertEquals(labels("dosa at saravana"), ["saravana"]);
  assertEquals(labels("lunch at the cheesecake factory"), ["The Cheesecake Factory"]);
});

Deno.test("home cooking never triggers a lookup", () => {
  // Most of what this app records. Every one of these would otherwise cost
  // seconds on the logging path and buy nothing.
  for (
    const t of [
      "dal makhani with rice",
      "eggs on sourdough",
      "leftover pasta from the fridge",
      "soup i made from scratch",
      "sandwich at work",
      "cereal at home",
      "dinner at mom's",
      "toast at 7",
      "yogurt at 7:30am",
      "a bowl of oats",
    ]
  ) {
    assertEquals(detectVenues(t), [], t);
  }
});

Deno.test("the capture stops at a conjunction", () => {
  // "from panera and a coffee" must not become the venue "panera and a".
  assertEquals(labels("half a sandwich from panera and a coffee"), ["Panera"]);
  assertEquals(labels("noodles from wok box with extra chilli"), ["wok box"]);
});

Deno.test("delivery is a fallback signal, not a competing one", () => {
  // A named place is more useful to search for than the bare fact of a
  // delivery, so the delivery hint only appears when nothing was named.
  assertEquals(labels("butter chicken on swiggy"), ["a delivery / takeout order"]);
  assertEquals(labels("pizza from domino's on swiggy"), ["Domino's"]);
});

Deno.test("the same place named twice yields one hint", () => {
  assertEquals(labels("chipotle bowl from chipotle"), ["Chipotle"]);
});

Deno.test("ingredient senses of chain names don't trigger", () => {
  // "chipotle" is a pepper long before it is a restaurant, and this app's
  // whole point is cooking — the ingredient sense is the common one here.
  assertEquals(detectVenues("chicken with chipotle sauce"), []);
  assertEquals(detectVenues("chipotle mayo on the side"), []);
  assertEquals(detectVenues("a glass of cava"), []);
});

Deno.test("hints are capped so one sentence can't flood the prompt", () => {
  const hints = detectVenues(
    "coffee from starbucks then a big mac from mcdonald's and a whopper from burger king and fries from five guys",
  );
  assert(hints.length <= 3, `expected at most 3 hints, got ${hints.length}`);
});

Deno.test("empty input is inert", () => {
  assertEquals(detectVenues(""), []);
  assertEquals(detectVenues(null), []);
  assertEquals(detectVenues(undefined), []);
  assertEquals(renderVenueLookup([]), "");
});

Deno.test("the rendered block leaves Claude room to skip the search", () => {
  // The gate is deliberately loose, so the prompt carries the judgment. If
  // this instruction ever goes missing, every false positive turns into a
  // wasted search and a fabricated menu number.
  const block = renderVenueLookup(detectVenues("dinner from luigi's place"));
  assertStringIncludes(block, "Search only if this really is a business");
  assertStringIncludes(block, "estimate as usual");
  // With a server tool in play the reply can carry a preamble; the JSON has
  // to be the last thing said or the parse breaks.
  assertStringIncludes(block, "final message must still be the JSON object");
});
