# Soma Privacy Policy

_Last updated: July 8, 2026_

Soma is a food–body record. You log meals in about ten seconds, optionally
connect Apple Health, and Soma looks for honest, hedged correlations in your
own data. This policy explains exactly what data Soma handles, where it goes,
and how to get it out or delete it.

Soma is built around three commitments:

1. **Your raw health data never leaves your phone.** Only small daily
   summaries sync.
2. **Your data is yours.** You can export everything as a CSV or delete your
   account — and all of its data — at any time, from inside the app.
3. **No advertising, no tracking, no selling.** Soma has no ads, no
   third-party analytics SDKs, and never sells or shares your data for
   marketing.

---

## What we collect and why

### Account

When you sign in with Apple, we receive a stable, app-scoped identifier
(and, if you choose to share it, your email address — Apple's "Hide My
Email" works fine). This identifier links your meals and summaries to your
account. We use it for nothing else.

### Meal logs

When you log a meal — by voice, typing, or repeating a past meal — we store:

- what you said or typed (the transcript or text)
- the parsed result: dish name, estimated calorie and macro **ranges**
  (Soma never claims single-number precision), cuisine, and time eaten
- any corrections you make to a parse
- optional notes

Meal logs are stored in our database (hosted on Supabase) and are protected
by row-level security: only your signed-in account can read or write your
rows.

### Apple Health (HealthKit) — optional, read-only

If you connect Apple Health, Soma reads steps, sleep, resting heart rate,
and heart rate variability — read-only, never writing anything back.

**Raw HealthKit samples are processed entirely on your device and never
leave it.** Soma computes one summary per day (total steps, sleep minutes,
average resting heart rate, average HRV) and syncs only those four daily
numbers. That's the whole of what our servers ever see from Apple Health.

You can disconnect at any time in iOS Settings → Privacy & Security →
Health. Health data is never used for advertising and never shared with
third parties beyond the processing described below.

### Energy check-ins

If you record a daily energy level (a simple 0–5), it's stored alongside
your daily summary and used only by the insight engine.

## How meal parsing works (AI processing)

When you log a meal by voice or text, the transcript is sent from our
server to Anthropic's Claude API to be parsed into a structured meal
(dish name, calorie and macro ranges). Two things to know:

- The request goes **server-to-server** from our backend; the app never
  talks to Anthropic directly, and no API credentials live on your phone.
- We send only the meal text needed for parsing — no health data, no
  account identifiers beyond what's technically required.

Anthropic processes this data as a service provider under its commercial
terms and does not use it to train models.

## Weekly insights

Once a week, our server looks at your last ~28 days of meals, energy
check-ins, and daily health summaries to see whether any of a small set of
pre-defined correlations holds (for example: "late dinners tend to precede
lower-energy mornings"). Insights are:

- computed from **your data only**,
- always hedged ("worth watching, not a verdict"), and
- never medical advice, never prescriptive, never a diet plan.

## The one piece of shared data: dish-name aliases

When you correct a dish name (say, "chole" → "chana masala"), Soma may
record that **name-to-name mapping** in a shared table so the next person
who types "chole" gets a better parse. This is the only cross-user data in
Soma, and it is deliberately minimal:

- it contains only dish names and an optional cuisine tag,
- it carries **no user identifier, no macros, no health data, and no link
  back to you or your meals**.

## Where your data lives

Your data is stored with Supabase (our database and backend host),
encrypted in transit (TLS) and at rest. Access is enforced per-account with
row-level security. Our service providers are:

| Provider  | What they do              | What they see                                  |
|-----------|---------------------------|------------------------------------------------|
| Apple     | Sign in with Apple        | Authentication only                             |
| Supabase  | Database, auth, functions | Your account ID, meal logs, daily summaries     |
| Anthropic | Meal-text parsing         | Meal text only, transiently, no model training  |

No other third parties receive your data. We do not use advertising or
analytics SDKs.

## Export

Settings → export gives you a CSV of every meal you've logged — timestamps,
dish names, ranges, transcripts, notes — generated on demand and handed to
the standard iOS share sheet. No request forms, no waiting.

## Deletion

Settings → delete account permanently deletes your account and **all** of
its data: meals, corrections, daily health summaries, energy check-ins, and
insights. If you complete the Sign in with Apple prompt during deletion, we
also revoke Soma's sign-in token with Apple. Deletion is immediate and
irreversible; shared dish-name aliases contain nothing linkable to you and
are unaffected.

## What Soma doesn't do

- No advertising, no ad identifiers, no tracking across apps or websites.
- No selling or renting data. Ever.
- No calorie targets, goals, or medical advice — Soma is a record and a
  set of gentle observations, not a health product making claims.

## Children

Soma is not directed at children under 13 (or the equivalent minimum age in
your region) and we do not knowingly collect their data.

## Changes

If this policy changes materially, we'll update this page and the "last
updated" date, and note the change in the app's release notes.

## Contact

Questions or requests: **pranav.surampudi@gmail.com**
