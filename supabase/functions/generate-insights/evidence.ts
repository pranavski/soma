// Published-evidence base for generate-insights.
//
// Pure data + pure functions — no fetch, no Deno.env — so the table can be
// linted in unit tests (see evidence_test.ts) without serving the function.
//
// This module is the third leg of the engine's division of labour:
//
//   candidates.ts  owns every NUMBER about this person.
//   Claude         owns JUDGMENT and the personal sentence.
//   evidence.ts    owns every SCIENTIFIC CLAIM.
//
// Claude never writes, paraphrases, or cites a mechanism. It selects a
// candidate and writes the sentence about the person; index.ts joins the
// `mechanism` and `source` strings below in verbatim. A fabricated citation
// is therefore structurally impossible, exactly as a fabricated number
// already is — the model has no channel through which to invent one.
//
// The table does two other jobs:
//
//   1. It is a PRIOR on the multiple-testing correction (see
//      weightedBenjaminiHochberg in candidates.ts). A pairing the
//      literature already supports draws more of the shared FDR budget;
//      a speculative one draws less. This is what lets us add pairings
//      without taxing the ones that already work.
//   2. It grounds Claude's plausible-vs-spurious call, which was
//      previously unaided judgment.
//
// ─── Rules for adding a row ─────────────────────────────────────────────
//
// Every row here was read out of the source's actual abstract, not a
// search result or a recollection. Three rows that were planned for this
// table did not survive that check and are deliberately absent:
//
//   * protein x workout_minutes — the protein meta-analysis (Zhao 2025)
//     studies chronic SUPPLEMENTATION against athletic performance, and
//     every significant effect came from trials where energy intake was
//     not matched between arms. That is not evidence about one day's
//     protein against that day's training minutes.
//   * eating_window_h / first_meal_hour — the time-restricted-eating
//     meta-analysis (Rovira-Llopis 2023) measured fasting glucose, HbA1c
//     and HOMA-IR. Soma cannot see any of those.
//   * fiber x next-day energy — no source supports it. Fiber's evidence
//     is about sleep DEPTH, not duration or next-day feel.
//
// A pairing with no row is not penalised; it simply carries weight 1.0 and
// has to clear the bar on the person's own data alone. That is the correct
// outcome for an untested hypothesis, and it is why this file must never
// be padded to make the engine look better-read than it is.

import type { FeatureKey, SignalKey } from "./candidates.ts";

/// How much the literature is worth leaning on.
///
///   A — meta-analysis or randomised controlled trial with a direct,
///       quantified effect on a signal Soma actually measures.
///   B — controlled or large-cohort evidence, or an RCT whose endpoint is
///       adjacent to (not identical with) the signal we can see.
///   C — observational or preliminary; direction is plausible and
///       repeatedly reported, magnitude is not settled.
export type EvidenceGrade = "A" | "B" | "C";

export type EvidenceSource = {
  title: string;
  publication: string;
  year: number;
  url: string;
};

export type EvidenceRow = {
  /// Stable id, stored on the insight row so a future feature (meal plans)
  /// can join a surfaced finding back to the science behind it.
  id: string;
  feature: FeatureKey;
  signal: SignalKey;
  /// The lag the literature speaks to. The engine still TESTS both lags —
  /// the person's own data is the subject — but only this one is weighted.
  expectedLag: 0 | 1;
  /// Sign of the association the literature reports, in the raw units of
  /// the feature and signal. "more of the feature goes with more of the
  /// signal" is positive.
  direction: "positive" | "negative";
  grade: EvidenceGrade;
  /// One declarative sentence of general physiology, shown to the reader
  /// verbatim. Never about this person, never an instruction — see the
  /// prescriptive-language lint in evidence_test.ts.
  mechanism: string;
  /// What the source actually measured, quantified. Shown to Claude so it
  /// can weigh strength; never rendered to the reader as-is.
  magnitude: string;
  sources: EvidenceSource[];
};

/// Prior weight by grade, before normalisation.
///
/// These are deliberately modest. Weighted Benjamini-Hochberg controls the
/// false-discovery rate for ANY fixed weights averaging 1, so the ceiling
/// here is not a statistical constraint — it is a humility constraint. A
/// large weight would let a well-published effect surface on this person's
/// data when their data barely supports it, which is precisely the failure
/// the engine exists to avoid. The literature earns a hypothesis a better
/// hearing; it does not get to answer for the person.
export const GRADE_WEIGHT: Record<EvidenceGrade, number> = {
  A: 2.0,
  B: 1.5,
  C: 1.2,
};

/// Weight for a hypothesis with no evidence row. Not a penalty — the
/// normalisation step in candidates.ts is what makes the mean 1, so this
/// is simply "no opinion".
export const UNWEIGHTED = 1.0;

// ─── The table ──────────────────────────────────────────────────────────

export const EVIDENCE: readonly EvidenceRow[] = [
  {
    id: "caffeine_late_x_sleep",
    feature: "caffeine_mg_late",
    signal: "sleep_minutes",
    expectedLag: 0,
    direction: "negative",
    grade: "A",
    mechanism:
      "Caffeine blocks adenosine receptors, and the resulting alertness can persist for many hours; in controlled trials, caffeine taken closer to bedtime shortens total sleep time and lengthens the time it takes to fall asleep.",
    magnitude:
      "Meta-analysis: total sleep time -45 min, sleep efficiency -7%, sleep onset latency +9 min, deep (N3) sleep -11.4 min. RCT (n=23): 400 mg taken 4 h before bed cut total sleep time by 50.6 min (p<.001) and added 14.2 min to sleep onset; 100 mg had no significant effect at any timepoint. The review's modelled cutoff for a 107 mg cup of coffee is 8.8 h before bed.",
    sources: [
      {
        title: "The effect of caffeine on subsequent sleep: A systematic review and meta-analysis",
        publication: "Sleep Medicine Reviews 69:101764",
        year: 2023,
        url: "https://pubmed.ncbi.nlm.nih.gov/36870101/",
      },
      {
        title: "Dose and timing effects of caffeine on subsequent sleep: a randomized clinical crossover trial",
        publication: "Sleep 48(4):zsae230",
        year: 2025,
        url: "https://academic.oup.com/sleep/article/48/4/zsae230/7815486",
      },
    ],
  },
  {
    id: "alcohol_evening_x_resting_hr",
    feature: "alcohol_g_evening",
    signal: "resting_hr_bpm",
    expectedLag: 0,
    direction: "positive",
    grade: "A",
    mechanism:
      "Alcohol raises sympathetic nervous activity while it is being metabolised, which keeps heart rate elevated through the night even when sleep itself looks undisturbed.",
    magnitude:
      "Wearable cohort (n=20,968; 5.1M person-days): +2.8 bpm in females and +2.4 bpm in males per additional drink. Controlled study (n=40, 40-60 g/day over three evenings): nocturnal resting heart rate rose from 63.6 to 66.6 bpm (p<0.001) and returned to baseline afterwards.",
    sources: [
      {
        title: "Real-world effects of alcohol on heart rate, sleep, and physical activity by age and sex",
        publication: "PLOS Digital Health",
        year: 2026,
        url: "https://journals.plos.org/digitalhealth/article?id=10.1371%2Fjournal.pdig.0001284",
      },
      {
        title:
          "The Impact of Alcohol on Sleep Physiology: A Prospective Observational Study on Nocturnal Resting Heart Rate Using Smartwatch Technology",
        publication: "Nutrients",
        year: 2025,
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12073130/",
      },
    ],
  },
  {
    id: "alcohol_evening_x_hrv",
    feature: "alcohol_g_evening",
    signal: "hrv_ms",
    expectedLag: 0,
    direction: "negative",
    grade: "B",
    mechanism:
      "The same shift toward sympathetic dominance that raises overnight heart rate also reduces heart-rate variability, a common marker of how much recovery the night provided.",
    magnitude:
      "Wearable cohort (n=20,968): HRV fell 3.8 ms in females and 3.3 ms in males per additional drink, with larger declines in younger adults (those aged 20-29 showed 3.0 ms more decline than those in their 30s after five excess drinks).",
    sources: [
      {
        title: "Real-world effects of alcohol on heart rate, sleep, and physical activity by age and sex",
        publication: "PLOS Digital Health",
        year: 2026,
        url: "https://journals.plos.org/digitalhealth/article?id=10.1371%2Fjournal.pdig.0001284",
      },
      {
        title: "Dose-related effects of red wine and alcohol on heart rate variability",
        publication: "American Journal of Physiology - Heart and Circulatory Physiology",
        year: 2010,
        url: "https://journals.physiology.org/doi/full/10.1152/ajpheart.00700.2009",
      },
    ],
  },
  {
    id: "alcohol_evening_x_sleep",
    feature: "alcohol_g_evening",
    signal: "sleep_minutes",
    expectedLag: 0,
    direction: "negative",
    grade: "B",
    mechanism:
      "Alcohol shortens the time it takes to fall asleep but fragments the second half of the night as it clears, so total time asleep tends to fall even when getting to sleep felt easier.",
    magnitude:
      "Wearable cohort (n=20,968): sleep duration decreased as alcohol intake rose. Note the smaller controlled study (n=40) found no significant change in objective sleep architecture despite clear cardiac effects and more self-reported awakenings (p<0.001) — the cardiac signal is the more reliable one.",
    sources: [
      {
        title: "Real-world effects of alcohol on heart rate, sleep, and physical activity by age and sex",
        publication: "PLOS Digital Health",
        year: 2026,
        url: "https://journals.plos.org/digitalhealth/article?id=10.1371%2Fjournal.pdig.0001284",
      },
    ],
  },
  {
    id: "alcohol_evening_x_next_day_energy",
    feature: "alcohol_g_evening",
    signal: "energy",
    expectedLag: 1,
    direction: "negative",
    grade: "C",
    mechanism:
      "Disrupted overnight recovery after drinking is commonly followed by a quieter, lower-output next day.",
    magnitude:
      "Wearable cohort (n=20,968): next-day physical activity declined as alcohol intake rose. Physical activity is a proxy here — the cohort did not measure subjective energy, which is why this is graded weakest.",
    sources: [
      {
        title: "Real-world effects of alcohol on heart rate, sleep, and physical activity by age and sex",
        publication: "PLOS Digital Health",
        year: 2026,
        url: "https://journals.plos.org/digitalhealth/article?id=10.1371%2Fjournal.pdig.0001284",
      },
    ],
  },
  {
    id: "fiber_x_sleep",
    feature: "total_fiber_g",
    signal: "sleep_minutes",
    expectedLag: 0,
    direction: "positive",
    grade: "B",
    mechanism:
      "Higher-fiber days have been linked with deeper, less interrupted sleep, while days heavier in saturated fat and sugar track with lighter sleep.",
    magnitude:
      "Randomised crossover inpatient study (n=26): greater fiber intake predicted more slow-wave sleep (p=0.0286) and less stage-1 sleep (p=0.0198). The endpoint was sleep DEPTH, not duration — the association with total time asleep is indirect.",
    sources: [
      {
        title: "Fiber and Saturated Fat Are Associated with Sleep Arousals and Slow Wave Sleep",
        publication: "Journal of Clinical Sleep Medicine 12(1):19-24",
        year: 2016,
        url: "https://pubmed.ncbi.nlm.nih.gov/26156950/",
      },
    ],
  },
  {
    id: "last_meal_hour_x_sleep",
    feature: "last_meal_hour",
    signal: "sleep_minutes",
    expectedLag: 0,
    direction: "negative",
    grade: "C",
    mechanism:
      "Eating close to bedtime asks the digestive system to work during the window the body is settling for sleep, and later last meals are repeatedly reported alongside more broken sleep.",
    magnitude:
      "Systematic scoping review of chrono-nutrition and sleep: observational studies consistently report later eating alongside poorer sleep onset and continuity, but experimental studies that deliberately shift meal times have generally found no short-term effect. The evidence is described by its authors as preliminary.",
    sources: [
      {
        title:
          "Chrono-nutrition and sleep: lessons from the temporal feature of eating patterns in human studies - A systematic scoping review",
        publication: "Sleep Medicine Reviews 76:101953",
        year: 2024,
        url: "https://pubmed.ncbi.nlm.nih.gov/38788519/",
      },
    ],
  },
];

// ─── Lookup ─────────────────────────────────────────────────────────────

const BY_PAIRING = new Map<string, EvidenceRow>(
  EVIDENCE.map((r) => [`${r.feature}_x_${r.signal}`, r]),
);

/// The row covering a (feature, signal) pairing, regardless of lag. Lag is
/// compared separately by `agreementWith` so that a finding at the
/// unexpected lag still gets its context, flagged as unexpected.
export function evidenceFor(feature: FeatureKey, signal: SignalKey): EvidenceRow | undefined {
  return BY_PAIRING.get(`${feature}_x_${signal}`);
}

/// Raw (un-normalised) prior weight for one hypothesis.
///
/// The weight applies ONLY at the lag the literature speaks to. A pairing
/// tested at the other lag is a different hypothesis, and the source has
/// nothing to say about it.
export function priorWeight(feature: FeatureKey, signal: SignalKey, lagDays: 0 | 1): number {
  const row = evidenceFor(feature, signal);
  if (row === undefined || row.expectedLag !== lagDays) return UNWEIGHTED;
  return GRADE_WEIGHT[row.grade];
}

export type Agreement = "corroborated" | "contradicts" | "no_prior";

/// Whether an observed association points the way the literature does.
///
/// Deliberately NOT used to suppress anything. A person's own body is the
/// subject of this app; down-weighting a finding for disagreeing with the
/// literature would be confirmation bias wearing a lab coat. This only
/// tells Claude how much interpretive care the finding needs, and decides
/// whether a mechanism line is appropriate to attach.
export function agreementWith(
  row: EvidenceRow | undefined,
  rho: number,
  lagDays: 0 | 1,
): Agreement {
  if (row === undefined || row.expectedLag !== lagDays) return "no_prior";
  const observed = rho >= 0 ? "positive" : "negative";
  return observed === row.direction ? "corroborated" : "contradicts";
}

/// Human-readable citation, stored on the insight row and shown under the
/// mechanism line. Multiple sources are joined — a claim backed by both a
/// meta-analysis and a cohort should show both.
export function citation(row: EvidenceRow): string {
  return row.sources
    .map((s) => `${s.title}. ${s.publication}, ${s.year}.`)
    .join(" ");
}
