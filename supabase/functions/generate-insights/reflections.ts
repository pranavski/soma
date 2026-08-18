// Reflections — what the app can honestly say in the first few days.
//
// The insight engine needs roughly ten days of paired data before it can
// find anything. That is not a threshold anyone chose; it falls out of the
// mathematics. With n paired days the smallest two-tailed p-value a
// permutation test can report is 2/n!, and below n≈7 that number sits above
// the Benjamini-Hochberg threshold no matter how strong the underlying
// relationship is. Swept over synthetic windows, detection of a planted,
// perfectly deterministic effect is 0% at 3-7 logged days and only passes
// the false-positive rate around day 10. Lowering MIN_MEAL_DAYS would not
// make findings arrive sooner; it would make the first thing a new user
// ever reads a false positive.
//
// So the answer to "give me something before day ten" is not weaker
// statistics. It is a different kind of statement.
//
// A reflection describes the record. It never relates a food feature to a
// body signal — that is what an insight does, and doing it without the
// correction is precisely the fabrication the engine exists to prevent.
// "Your last meal has landed between 18:00 and 22:00" needs no inference to
// be true; it is arithmetic over what the person typed. That is why it is
// safe on day three, and also why it must never be dressed up as a finding.
//
// Two deliberate consequences of that:
//
//   1. NO MODEL CALL. The copy is templated here, from numbers computed
//      here. There is no selection judgment to delegate — a description is
//      either accurate or it is a bug — and a model handed thin data and
//      asked to be interesting reaches for exactly the causal language this
//      layer must not contain. Templates are duller and cannot hallucinate.
//
//   2. They are a SNAPSHOT, not a feed. An insight is a finding about a
//      window and stays true; a reflection is a description of the current
//      log and is wrong the moment another meal is added. Each run replaces
//      the previous set wholesale (see index.ts), and unlike insights there
//      is no never-repeat rule — repeating is the point.

import {
  type CheckinRow,
  type HealthDayRow,
  type MealRow,
  dayOfMeal,
  fmtSleep,
  hourOfMeal,
} from "./digest.ts";
import {
  EVENING_ALCOHOL_HOUR,
  LATE_CAFFEINE_HOUR,
  buildDaySignals,
} from "./candidates.ts";

// ─── Tunables ───────────────────────────────────────────────────────────────

/// Days with at least one logged meal before there is anything worth
/// describing. Two days is a pair of anecdotes; three is the first point at
/// which "between X and Y" and "typically Z" are different statements.
export const MIN_REFLECTION_DAYS = 3;

/// Days a single body signal needs before its spread is worth reporting.
/// Same reasoning, applied per signal rather than across them — two nights
/// of sleep data is not a sleep range.
export const MIN_SIGNAL_DAYS = 3;

/// How many reflections a run surfaces. Three is enough to feel like the
/// app is paying attention and few enough that none of them is filler; the
/// group cap below matters more than this number.
export const MAX_REFLECTIONS = 3;

// ─── Shape ──────────────────────────────────────────────────────────────────

export type ReflectionKind =
  | "repeat_dish"
  | "meal_timing"
  | "calorie_range"
  | "meal_rhythm"
  | "protein_range"
  | "late_caffeine"
  | "sleep_range"
  | "energy_range"
  | "evening_alcohol"
  | "steps_range";

/// At most one reflection per group reaches the feed. Without this the top
/// three by priority are routinely three facts about nutrition, which reads
/// as the app having noticed one thing about you rather than several.
type ReflectionGroup = "repetition" | "timing" | "nutrition" | "cadence" | "stimulant" | "body";

export type Reflection = {
  kind: ReflectionKind;
  group: ReflectionGroup;
  /// The observation, as one sentence. Descriptive only.
  body: string;
  /// The counts underneath it — how many days, and what the middle looked
  /// like. Kept separate so the UI can set it quieter than the observation,
  /// the same division the insight card makes between claim and evidence.
  detail: string;
  /// Fixed, not data-dependent: what a person is most likely to find worth
  /// reading about their own log. Ties break on the order of ReflectionKind.
  priority: number;
};

const PRIORITY: Record<ReflectionKind, number> = {
  repeat_dish: 12,
  meal_timing: 10,
  calorie_range: 9,
  meal_rhythm: 8,
  protein_range: 7,
  late_caffeine: 6,
  sleep_range: 5,
  energy_range: 5,
  evening_alcohol: 4,
  steps_range: 3,
};

const GROUP: Record<ReflectionKind, ReflectionGroup> = {
  repeat_dish: "repetition",
  meal_timing: "timing",
  calorie_range: "nutrition",
  meal_rhythm: "cadence",
  protein_range: "nutrition",
  late_caffeine: "stimulant",
  sleep_range: "body",
  energy_range: "body",
  evening_alcohol: "stimulant",
  steps_range: "body",
};

function make(kind: ReflectionKind, body: string, detail: string): Reflection {
  return { kind, group: GROUP[kind], body, detail, priority: PRIORITY[kind] };
}

// ─── Formatting ─────────────────────────────────────────────────────────────

function fmtHour(h: number): string {
  return `${String(Math.round(h)).padStart(2, "0")}:00`;
}

function group3(n: number): string {
  return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/// Calories are always a range in user-facing copy, never a bare number —
/// see the hard rules. Rounded outward to the nearest 50 so the printed
/// range never claims more precision than a parsed estimate has.
function fmtKcalRange(lo: number, hi: number): string {
  return `~${group3(Math.floor(lo / 50) * 50)}–${group3(Math.ceil(hi / 50) * 50)}`;
}

function plural(n: number, one: string, many: string): string {
  return n === 1 ? one : many;
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid];
}

// ─── Per-day helpers ────────────────────────────────────────────────────────

function mealsByDay(meals: MealRow[]): Map<string, MealRow[]> {
  const out = new Map<string, MealRow[]>();
  for (const m of meals) {
    const day = dayOfMeal(m);
    if (!out.has(day)) out.set(day, []);
    out.get(day)!.push(m);
  }
  return out;
}

/// Per-day low/high totals for a nutrient, kept as the interval the parser
/// actually produced rather than collapsed to a midpoint the way
/// buildDayFeatures does.
///
/// The correlation engine wants one number per day because Spearman does;
/// copy wants the interval, because printing a midpoint as though it were a
/// measurement is the exact thing the calories-are-always-ranges rule
/// exists to stop. Same all-or-nothing condition as buildDayFeatures: a day
/// with any unparsed meal is omitted, since a partial sum reads as a real
/// low day.
function dayRangeTotals(
  byDay: Map<string, MealRow[]>,
  pick: (m: MealRow) => [number | null, number | null],
): { low: number; high: number }[] {
  const out: { low: number; high: number }[] = [];
  for (const dayMeals of byDay.values()) {
    if (!dayMeals.every((m) => pick(m)[0] !== null && pick(m)[1] !== null)) continue;
    let low = 0;
    let high = 0;
    for (const m of dayMeals) {
      const [lo, hi] = pick(m);
      low += lo!;
      high += hi!;
    }
    out.push({ low, high });
  }
  return out;
}

/// Values of one body signal across the window, in day order.
function signalSeries(
  signals: Map<string, { [k: string]: number | undefined }>,
  key: string,
): number[] {
  const out: number[] = [];
  for (const day of [...signals.keys()].sort()) {
    const v = signals.get(day)![key];
    if (v !== undefined) out.push(v);
  }
  return out;
}

// ─── The reflections ────────────────────────────────────────────────────────

function repeatDish(byDay: Map<string, MealRow[]>): Reflection | null {
  // Counted in DAYS, not meals: a coffee logged twice on one morning is one
  // day of coffee, not two, and "what you come back to" is about returning
  // on a different day.
  const daysByDish = new Map<string, { label: string; days: Set<string> }>();
  for (const [day, dayMeals] of byDay) {
    for (const m of dayMeals) {
      const raw = (m.dish_name ?? "").trim().replace(/\s+/g, " ");
      if (raw.length === 0) continue;
      const key = raw.toLowerCase();
      if (!daysByDish.has(key)) daysByDish.set(key, { label: raw, days: new Set() });
      daysByDish.get(key)!.days.add(day);
    }
  }
  const ranked = [...daysByDish.values()]
    .map((d) => ({ label: d.label, days: d.days.size }))
    // Alphabetical tiebreak so a run is reproducible when two dishes tie.
    .sort((a, b) => b.days - a.days || a.label.localeCompare(b.label));

  const top = ranked[0];
  if (top === undefined || top.days < 2) return null;

  const totalDays = byDay.size;
  // Ties are the common case for someone with a fixed breakfast: naming one
  // of two dishes that both appear every day as "what you've come back to
  // most" is simply false. Say both.
  const tied = ranked.filter((d) => d.days === top.days);
  const body = tied.length === 1
    ? `${top.label} is what you've come back to most.`
    : tied.length === 2
    ? `${tied[0].label} and ${tied[1].label} are what you've come back to most.`
    : `${tied[0].label}, ${tied[1].label} and ${tied.length - 2} other ${plural(tied.length - 2, "dish", "dishes")} have been on the most days.`;

  const runnerUp = ranked.find((d) => d.days < top.days);
  const detail = runnerUp !== undefined && runnerUp.days > 1
    ? `on ${top.days} of your ${totalDays} logged days; ${runnerUp.label} on ${runnerUp.days}.`
    : `on ${top.days} of your ${totalDays} logged days.`;

  return make("repeat_dish", body, detail);
}

function mealTiming(byDay: Map<string, MealRow[]>): Reflection | null {
  const firsts: number[] = [];
  const lasts: number[] = [];
  for (const dayMeals of byDay.values()) {
    const hours = dayMeals.map(hourOfMeal);
    firsts.push(Math.min(...hours));
    lasts.push(Math.max(...hours));
  }
  if (lasts.length < MIN_REFLECTION_DAYS) return null;

  const lo = Math.min(...lasts);
  const hi = Math.max(...lasts);
  const windowH = Math.round(median(lasts) - median(firsts));

  // A fixed dinner hour is the more interesting observation, and phrasing it
  // as a range ("between 19:00 and 19:00") would read as a bug.
  const body = lo === hi
    ? `Your last meal has landed at ${fmtHour(lo)} every day you've logged.`
    : `Your last meal has landed between ${fmtHour(lo)} and ${fmtHour(hi)}.`;

  const detail = windowH > 0
    ? `across ${byDay.size} days; first plate to last runs about ${windowH} ${plural(windowH, "hour", "hours")}.`
    : `across ${byDay.size} days.`;

  return make("meal_timing", body, detail);
}

function mealRhythm(byDay: Map<string, MealRow[]>): Reflection | null {
  const counts = [...byDay.values()].map((m) => m.length);
  if (counts.length < MIN_REFLECTION_DAYS) return null;
  const mid = Math.round(median(counts));
  const lo = Math.min(...counts);
  const hi = Math.max(...counts);
  const detail = lo === hi
    ? `${counts.length} days, all the same.`
    : `between ${lo} and ${hi} across ${counts.length} days.`;
  return make(
    "meal_rhythm",
    `You've been logging about ${mid} ${plural(mid, "meal", "meals")} a day.`,
    detail,
  );
}

function calorieRange(byDay: Map<string, MealRow[]>): Reflection | null {
  const totals = dayRangeTotals(byDay, (m) => [m.calories_low, m.calories_high]);
  if (totals.length < MIN_REFLECTION_DAYS) return null;
  const lo = Math.min(...totals.map((t) => t.low));
  const hi = Math.max(...totals.map((t) => t.high));
  return make(
    "calorie_range",
    `Your fully-logged days have totalled somewhere around ${fmtKcalRange(lo, hi)}.`,
    `${totals.length} of your ${byDay.size} days had every meal parsed — the rest aren't counted here.`,
  );
}

function proteinRange(byDay: Map<string, MealRow[]>): Reflection | null {
  const totals = dayRangeTotals(byDay, (m) => [m.protein_g_low, m.protein_g_high]);
  if (totals.length < MIN_REFLECTION_DAYS) return null;
  const lo = Math.min(...totals.map((t) => t.low));
  const hi = Math.max(...totals.map((t) => t.high));
  return make(
    "protein_range",
    `Protein has come in around ${Math.floor(lo / 5) * 5}–${Math.ceil(hi / 5) * 5}g on the days everything got parsed.`,
    `${totals.length} ${plural(totals.length, "day", "days")} with a full read.`,
  );
}

function lateCaffeine(byDay: Map<string, MealRow[]>): Reflection | null {
  let daysWith = 0;
  let latestHour = 0;
  for (const dayMeals of byDay.values()) {
    const late = dayMeals.filter(
      (m) => hourOfMeal(m) >= LATE_CAFFEINE_HOUR && (m.caffeine_mg_high ?? 0) > 0,
    );
    if (late.length === 0) continue;
    daysWith++;
    latestHour = Math.max(latestHour, ...late.map(hourOfMeal));
  }
  if (daysWith === 0) return null;
  return make(
    "late_caffeine",
    `Caffeine has shown up after 2pm on ${daysWith} of your ${byDay.size} logged days.`,
    `the latest was around ${fmtHour(latestHour)}.`,
  );
}

function eveningAlcohol(byDay: Map<string, MealRow[]>): Reflection | null {
  let daysWith = 0;
  for (const dayMeals of byDay.values()) {
    const hasDrink = dayMeals.some(
      (m) => hourOfMeal(m) >= EVENING_ALCOHOL_HOUR && (m.alcohol_g_high ?? 0) > 0,
    );
    if (hasDrink) daysWith++;
  }
  if (daysWith === 0) return null;
  // Flatly factual, and nothing more. This is the one reflection where a
  // stray adverb would read as a judgement about the person.
  return make(
    "evening_alcohol",
    `${daysWith} of your ${byDay.size} logged evenings included a drink.`,
    `noted, not weighed.`,
  );
}

function sleepRange(signals: Map<string, Record<string, number | undefined>>): Reflection | null {
  const xs = signalSeries(signals, "sleep_minutes");
  if (xs.length < MIN_SIGNAL_DAYS) return null;
  return make(
    "sleep_range",
    `Sleep has run between ${fmtSleep(Math.min(...xs))} and ${fmtSleep(Math.max(...xs))}.`,
    `${xs.length} nights recorded; the middle of them sits near ${fmtSleep(Math.round(median(xs)))}.`,
  );
}

function stepsRange(signals: Map<string, Record<string, number | undefined>>): Reflection | null {
  const xs = signalSeries(signals, "steps");
  if (xs.length < MIN_SIGNAL_DAYS) return null;
  return make(
    "steps_range",
    `Steps have ranged from ${group3(Math.min(...xs))} to ${group3(Math.max(...xs))} a day.`,
    `${xs.length} days recorded; typically around ${group3(median(xs))}.`,
  );
}

function energyRange(signals: Map<string, Record<string, number | undefined>>): Reflection | null {
  const xs = signalSeries(signals, "energy");
  if (xs.length < MIN_SIGNAL_DAYS) return null;
  const lo = Math.min(...xs);
  const hi = Math.max(...xs);
  const body = lo === hi
    ? `You've marked your energy at ${lo} of 5 every time so far.`
    : `Your energy notes have sat between ${lo} and ${hi} out of 5.`;
  return make(
    "energy_range",
    body,
    `${xs.length} check-${plural(xs.length, "in", "ins")}; typically ${median(xs)} of 5.`,
  );
}

// ─── Entry point ────────────────────────────────────────────────────────────

/// Every reflection this log supports, best first — before the cap and the
/// group rule thin it down.
///
/// Separate from buildReflections because the interesting properties are
/// properties of all of them, not of the three that happen to fit: the copy
/// constraints have to hold for every sentence this module can emit, or
/// they hold only until someone changes a priority number.
export function candidateReflections(
  meals: MealRow[],
  checkins: CheckinRow[],
  health: HealthDayRow[],
): Reflection[] {
  const byDay = mealsByDay(meals);
  if (byDay.size < MIN_REFLECTION_DAYS) return [];

  const signals = buildDaySignals(checkins, health) as Map<
    string,
    Record<string, number | undefined>
  >;

  const all = [
    repeatDish(byDay),
    mealTiming(byDay),
    calorieRange(byDay),
    mealRhythm(byDay),
    proteinRange(byDay),
    lateCaffeine(byDay),
    eveningAlcohol(byDay),
    sleepRange(signals),
    stepsRange(signals),
    energyRange(signals),
  ].filter((r): r is Reflection => r !== null);

  const kindOrder = Object.keys(PRIORITY) as ReflectionKind[];
  all.sort((a, b) =>
    b.priority - a.priority || kindOrder.indexOf(a.kind) - kindOrder.indexOf(b.kind)
  );
  return all;
}

/// What actually reaches the feed: the best MAX_REFLECTIONS, at most one
/// per group.
///
/// Returns [] below MIN_REFLECTION_DAYS — and callers should treat [] as
/// "say nothing", never as a prompt to pad. The one thing worse than an
/// empty Insights screen on day two is a full one.
export function buildReflections(
  meals: MealRow[],
  checkins: CheckinRow[],
  health: HealthDayRow[],
): Reflection[] {
  const picked: Reflection[] = [];
  const usedGroups = new Set<ReflectionGroup>();
  for (const r of candidateReflections(meals, checkins, health)) {
    if (picked.length >= MAX_REFLECTIONS) break;
    if (usedGroups.has(r.group)) continue;
    usedGroups.add(r.group);
    picked.push(r);
  }
  return picked;
}
