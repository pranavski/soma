// Tests for the published-evidence base.
//
// These are mostly lints rather than behaviour tests, and that is the
// point. evidence.ts is the one file in the engine whose contents reach the
// reader as assertions about science, so the invariants that keep it
// trustworthy have to be enforced mechanically — a reviewer will not catch
// a citation quietly drifting into advice, or a row pointing at a pairing
// the engine stopped testing two refactors ago.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PAIRINGS } from "./candidates.ts";
import {
  EVIDENCE,
  GRADE_WEIGHT,
  UNWEIGHTED,
  agreementWith,
  citation,
  evidenceFor,
  priorWeight,
} from "./evidence.ts";

const pairingKeys = new Set(PAIRINGS.map(([f, s]) => `${f}_x_${s}`));

Deno.test("every evidence row describes a pairing the engine actually tests", () => {
  for (const row of EVIDENCE) {
    assert(
      pairingKeys.has(`${row.feature}_x_${row.signal}`),
      `${row.id} cites ${row.feature} x ${row.signal}, which is not in PAIRINGS — ` +
        "the row would weight a hypothesis that is never tested",
    );
  }
});

Deno.test("evidence ids are unique", () => {
  const ids = EVIDENCE.map((r) => r.id);
  assertEquals(new Set(ids).size, ids.length);
});

Deno.test("one row per pairing", () => {
  // evidenceFor keys on the pairing, so a second row for the same pairing
  // would be silently unreachable.
  const keys = EVIDENCE.map((r) => `${r.feature}_x_${r.signal}`);
  assertEquals(new Set(keys).size, keys.length);
});

Deno.test("every row carries a checkable citation", () => {
  for (const row of EVIDENCE) {
    assert(row.sources.length > 0, `${row.id} has no source`);
    for (const s of row.sources) {
      assert(s.title.trim().length > 0, `${row.id} source has no title`);
      assert(s.publication.trim().length > 0, `${row.id} source has no publication`);
      assert(s.year >= 1990 && s.year <= 2030, `${row.id} source year ${s.year} is implausible`);
      assert(s.url.startsWith("https://"), `${row.id} source url is not https`);
    }
    assert(row.magnitude.trim().length > 0, `${row.id} states no magnitude`);
  }
});

// The lint that keeps the science from becoming advice.
//
// Soma's hard rules say insights are never prescriptive and never medical.
// The mechanism sentence is the one piece of reader-facing copy that does
// not pass through the model's copy contract — it is shipped verbatim from
// this table — so it needs its own guard. A mechanism describes physiology
// in general; the moment it addresses the reader or tells them what to do,
// it has become the thing the app promises not to be.
const PRESCRIPTIVE = [
  /\byou\b/i,
  /\byour\b/i,
  /\bshould\b/i,
  /\bmust\b/i,
  /\bavoid\b/i,
  /\blimit\b/i,
  /\bcut back\b/i,
  /\baim for\b/i,
  /\btry to\b/i,
  /\bmake sure\b/i,
  /\brecommend/i,
  /\badvis(e|ed|ing|able)\b/i,
  /\bbest to\b/i,
];

Deno.test("no mechanism addresses the reader or tells them what to do", () => {
  for (const row of EVIDENCE) {
    for (const pattern of PRESCRIPTIVE) {
      assert(
        !pattern.test(row.mechanism),
        `${row.id} mechanism matches ${pattern} — it reads as advice, not physiology:\n  ${row.mechanism}`,
      );
    }
  }
});

Deno.test("no mechanism asserts causation outright", () => {
  // "causes" / "will" turn an association into a verdict. The engine's whole
  // copy contract rests on not doing that, and a citation makes the
  // overreach more convincing, not less.
  for (const row of EVIDENCE) {
    assert(!/\bcauses\b/i.test(row.mechanism), `${row.id} mechanism claims causation`);
    assert(!/\bwill\b/i.test(row.mechanism), `${row.id} mechanism predicts rather than describes`);
  }
});

Deno.test("grade weights are ordered A > B > C and all exceed no-evidence", () => {
  assert(GRADE_WEIGHT.A > GRADE_WEIGHT.B);
  assert(GRADE_WEIGHT.B > GRADE_WEIGHT.C);
  assert(GRADE_WEIGHT.C > UNWEIGHTED);
});

Deno.test("grade weights stay modest", () => {
  // Weighted BH controls the FDR for any fixed weights, so this bound is
  // about humility rather than validity: a large weight would let a
  // well-published effect surface on data that barely supports it, which is
  // the failure the engine exists to prevent.
  for (const [grade, w] of Object.entries(GRADE_WEIGHT)) {
    assert(w <= 2.5, `grade ${grade} weight ${w} lets the literature answer for the person`);
  }
});

Deno.test("priorWeight applies only at the lag the literature speaks to", () => {
  const row = EVIDENCE.find((r) => r.id === "alcohol_evening_x_next_day_energy")!;
  assertEquals(row.expectedLag, 1);
  assertEquals(priorWeight(row.feature, row.signal, 1), GRADE_WEIGHT[row.grade]);
  // Same pairing, other lag: a different hypothesis, and the source says
  // nothing about it.
  assertEquals(priorWeight(row.feature, row.signal, 0), UNWEIGHTED);
});

Deno.test("priorWeight is neutral for pairings with no row", () => {
  assertEquals(priorWeight("meal_count", "energy", 0), UNWEIGHTED);
  assertEquals(priorWeight("meal_count", "energy", 1), UNWEIGHTED);
});

Deno.test("agreementWith reads the sign against the expected direction", () => {
  const caffeine = evidenceFor("caffeine_mg_late", "sleep_minutes")!;
  assertEquals(caffeine.direction, "negative");
  // More late caffeine, less sleep — what the literature reports.
  assertEquals(agreementWith(caffeine, -0.6, 0), "corroborated");
  // The opposite. Still surfaced, just flagged.
  assertEquals(agreementWith(caffeine, 0.6, 0), "contradicts");
  // Right pairing, wrong lag — the source has no opinion.
  assertEquals(agreementWith(caffeine, -0.6, 1), "no_prior");
  assertEquals(agreementWith(undefined, -0.6, 0), "no_prior");
});

Deno.test("agreement is never used to hide a disagreeing finding", () => {
  // Guards the intent of agreementWith: it returns a label, and there is no
  // code path in which "contradicts" means "drop". If this ever becomes a
  // filter, the engine has started telling people what the literature says
  // instead of what their own data says.
  const caffeine = evidenceFor("caffeine_mg_late", "sleep_minutes")!;
  const labels = [
    agreementWith(caffeine, 0.9, 0),
    agreementWith(caffeine, -0.9, 0),
  ];
  assertEquals(new Set(labels).size, 2, "both directions must produce a usable label");
});

Deno.test("citation renders every source", () => {
  const row = evidenceFor("caffeine_mg_late", "sleep_minutes")!;
  const text = citation(row);
  for (const s of row.sources) {
    assert(text.includes(s.title), "citation omits a source title");
    assert(text.includes(String(s.year)), "citation omits a source year");
  }
});

Deno.test("the table stays small enough to have been read end to end", () => {
  // Not a style rule. Every row here is a claim someone has to have checked
  // against an abstract; a table that grows faster than it can be audited is
  // how citation theater gets in.
  assert(EVIDENCE.length <= 25, "evidence table has outgrown hand-verification");
});
