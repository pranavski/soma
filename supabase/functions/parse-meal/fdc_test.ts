import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  FDC_ENTRIES,
  SERVING_ANCHORS,
  matchAnchors,
  matchFdcEntries,
  renderAnchors,
} from "./fdc.ts";

Deno.test("matches a caffeine anchor from a casual transcript", () => {
  const m = matchAnchors("two coffees and a bagel");
  assertEquals(m.length, 1);
  assertEquals(m[0].nutrient, "caffeine");
  assertEquals(m[0].caffeine_mg, 95);
});

Deno.test("specific caffeine terms beat the generic one", () => {
  // The whole reason this table exists: an espresso has LESS caffeine than a
  // mug of drip coffee, which is the opposite of the intuition. If "coffee"
  // won here, "espresso" would be anchored 50% too high.
  assertEquals(matchAnchors("espresso after lunch")[0].caffeine_mg, 63);
  assertEquals(matchAnchors("a decaf coffee")[0].caffeine_mg, 2);
  assertEquals(matchAnchors("oat flat white")[0].caffeine_mg, 63);
  assertEquals(matchAnchors("green tea")[0].caffeine_mg, 28);
  assertEquals(matchAnchors("chamomile tea before bed")[0].caffeine_mg, 0);
});

Deno.test("matches an alcohol anchor and uses the standard drink", () => {
  for (const t of ["a pint with dinner", "two glasses of red wine", "gin and tonic"]) {
    const m = matchAnchors(t);
    assertEquals(m.length, 1, t);
    assertEquals(m[0].nutrient, "alcohol");
    // All standard drinks are 14 g of ethanol by the NIAAA definition —
    // that equivalence is why this table can be four rows long.
    assertEquals(m[0].alcohol_g, 14, t);
  }
});

Deno.test("matches caffeine and alcohol together, at most one each", () => {
  const m = matchAnchors("espresso martini and a coffee");
  assertEquals(m.length, 2);
  assertEquals(new Set(m.map((a) => a.nutrient)).size, 2);
});

Deno.test("no anchors for an ordinary meal", () => {
  assertEquals(matchAnchors("dal makhani with jeera rice"), []);
  assertEquals(matchAnchors(""), []);
  assertEquals(matchAnchors(null), []);
});

Deno.test("word boundaries prevent substring false positives", () => {
  // "scone" contains no standalone drink word; "teaspoon" must not read as
  // "tea", or every recipe-style transcript picks up 47 mg of caffeine.
  assertEquals(matchAnchors("a scone"), []);
  assertEquals(matchAnchors("a teaspoon of honey"), []);
  assertEquals(matchAnchors("coconut rice"), []);
});

Deno.test("renderAnchors tells the model to multiply, not to copy", () => {
  const text = renderAnchors(matchAnchors("two coffees and a beer"));
  assert(text.includes("95 mg caffeine"));
  assert(text.includes("14 g alcohol"));
  assert(/multiply/i.test(text), "the per-serving figures are useless without the count");
  assertEquals(renderAnchors([]), "");
});

Deno.test("every anchor carries a value and a serving it refers to", () => {
  for (const a of SERVING_ANCHORS) {
    const hasValue = a.caffeine_mg !== undefined || a.alcohol_g !== undefined;
    assert(hasValue, `${a.label} has no value`);
    assert(a.serving.trim().length > 0, `${a.label} has no serving size`);
    // A figure without the serving it belongs to cannot be multiplied, and
    // is how "a coffee" silently becomes "100 g of coffee".
    assert(/\d/.test(a.serving) || /standard drink/.test(a.serving), `${a.label} serving is vague`);
  }
});

Deno.test("the FDC extract is optional, and matching degrades quietly", () => {
  // The extract is generated against a rate-limited public API and ships
  // empty until someone runs the script with a key. Nothing may depend on
  // it being populated — the serving table above carries the anchoring.
  assert(Array.isArray(FDC_ENTRIES));
  assertEquals(matchFdcEntries("coffee", 4).length <= 4, true);
  assertEquals(matchFdcEntries(null), []);
  assertEquals(matchFdcEntries("a"), []);
});
