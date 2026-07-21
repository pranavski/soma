// deno test supabase/functions/parse-meal/detection_test.ts

import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  detectionTranscript,
  parsePredictions,
  summarizeDetections,
} from "./detection.ts";

Deno.test("parsePredictions accepts the hosted-API shape", () => {
  const preds = parsePredictions({
    predictions: [
      { class: "rice", confidence: 0.91, x: 10, y: 20, width: 100, height: 80 },
      { class: "dal", confidence: 0.84 },
    ],
    image: { width: 640, height: 480 },
  });
  assertEquals(preds?.length, 2);
  assertEquals(preds?.[0].class, "rice");
  assertEquals(preds?.[1].width, undefined);
});

Deno.test("parsePredictions accepts an empty predictions array", () => {
  assertEquals(parsePredictions({ predictions: [] }), []);
});

Deno.test("parsePredictions rejects malformed payloads", () => {
  assertStrictEquals(parsePredictions(null), null);
  assertStrictEquals(parsePredictions("nope"), null);
  assertStrictEquals(parsePredictions({}), null);
  assertStrictEquals(parsePredictions({ predictions: "rice" }), null);
  assertStrictEquals(
    parsePredictions({ predictions: [{ class: "", confidence: 0.9 }] }),
    null,
  );
  assertStrictEquals(
    parsePredictions({ predictions: [{ class: "rice", confidence: "high" }] }),
    null,
  );
});

Deno.test("summarizeDetections filters below the confidence threshold", () => {
  const items = summarizeDetections(
    [
      { class: "rice", confidence: 0.91 },
      { class: "mystery", confidence: 0.39 },
    ],
    0.4,
  );
  assertEquals(items.map((i) => i.label), ["rice"]);
});

Deno.test("summarizeDetections merges duplicates and keeps max confidence", () => {
  const items = summarizeDetections(
    [
      { class: "roti", confidence: 0.62 },
      { class: "Roti", confidence: 0.78 },
      { class: "dal_makhani", confidence: 0.84 },
    ],
    0.4,
  );
  assertEquals(items.length, 2);
  // sorted by confidence desc
  assertEquals(items[0], { label: "dal makhani", count: 1, confidence: 0.84 });
  assertEquals(items[1], { label: "roti", count: 2, confidence: 0.78 });
});

Deno.test("summarizeDetections returns empty when nothing clears the bar", () => {
  const items = summarizeDetections([{ class: "rice", confidence: 0.2 }], 0.4);
  assertEquals(items, []);
});

Deno.test("detectionTranscript renders counts and percentages", () => {
  const text = detectionTranscript([
    { label: "roti", count: 2, confidence: 0.78 },
    { label: "dal makhani", count: 1, confidence: 0.845 },
  ]);
  assertEquals(
    text.startsWith(
      "meal photo — an object-detection model identified: 2× roti (78% confident), dal makhani (85% confident).",
    ),
    true,
  );
});
