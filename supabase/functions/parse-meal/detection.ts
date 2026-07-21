// Detection helpers for parse-meal's photo branch.
//
// Pure functions only — no fetch, no Deno.env — so they can be unit-tested
// (see detection_test.ts) without serving the function. The network call
// to Roboflow stays in index.ts.

export type RoboflowPrediction = {
  class: string;
  confidence: number;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
};

export type DetectedItem = {
  label: string;
  count: number;
  confidence: number; // highest confidence among merged duplicates
};

/// Shape-validate the Roboflow response payload. Returns the predictions
/// array (possibly empty) or null when the payload doesn't match the
/// hosted-API contract — callers treat null as a detection failure.
export function parsePredictions(payload: unknown): RoboflowPrediction[] | null {
  if (!payload || typeof payload !== "object") return null;
  const preds = (payload as Record<string, unknown>).predictions;
  if (!Array.isArray(preds)) return null;
  const out: RoboflowPrediction[] = [];
  for (const p of preds) {
    if (!p || typeof p !== "object") return null;
    const o = p as Record<string, unknown>;
    if (typeof o.class !== "string" || o.class.length === 0) return null;
    if (typeof o.confidence !== "number" || Number.isNaN(o.confidence)) return null;
    out.push({
      class: o.class,
      confidence: o.confidence,
      x: typeof o.x === "number" ? o.x : undefined,
      y: typeof o.y === "number" ? o.y : undefined,
      width: typeof o.width === "number" ? o.width : undefined,
      height: typeof o.height === "number" ? o.height : undefined,
    });
  }
  return out;
}

/// Filter below-threshold predictions, merge duplicates of the same label
/// into a count, and order by confidence (highest first). Empty result
/// means "nothing confidently detected" — the caller falls back rather
/// than sending Claude an empty list to hallucinate from.
export function summarizeDetections(
  predictions: RoboflowPrediction[],
  minConfidence: number,
): DetectedItem[] {
  const byLabel = new Map<string, DetectedItem>();
  for (const p of predictions) {
    if (p.confidence < minConfidence) continue;
    const label = p.class.trim().toLowerCase().replace(/[_-]+/g, " ");
    if (label.length === 0) continue;
    const existing = byLabel.get(label);
    if (existing) {
      existing.count += 1;
      existing.confidence = Math.max(existing.confidence, p.confidence);
    } else {
      byLabel.set(label, { label, count: 1, confidence: p.confidence });
    }
  }
  return [...byLabel.values()].sort((a, b) => b.confidence - a.confidence);
}

/// Render detections as the transcript-shaped input the existing Claude
/// prompt already understands. Confidence rides along as a percentage so
/// the model can weigh shaky labels instead of treating them as fact.
export function detectionTranscript(items: DetectedItem[]): string {
  const parts = items.map((it) => {
    const count = it.count > 1 ? `${it.count}× ` : "";
    return `${count}${it.label} (${Math.round(it.confidence * 100)}% confident)`;
  });
  return (
    `meal photo — an object-detection model identified: ${parts.join(", ")}. ` +
    "The labels come from computer vision and may be generic; combine them " +
    "into the most likely single dish and infer standard components."
  );
}
