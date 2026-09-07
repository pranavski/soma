# Soma — App Store Connect copy (v1.0)

Paste-ready text for every free-text field in App Store Connect, written to
the constraints in `docs/app-store-compliance.md`: no outcome claims, no
"track your health", no "science-backed", no journal names, calories only
ever as ranges, and nothing about photo logging. If you edit, keep those.

## App information

| Field | Value |
|---|---|
| Name | Soma |
| Subtitle (30) | a food and body notebook |
| Primary category | Food & Drink |
| Secondary category | (none) |
| Bundle ID | com.pranavsurampudi.soma |
| Privacy Policy URL | https://pranavski.github.io/soma/privacy/ (once Pages is live; must resolve before submission) |
| Support URL | https://pranavski.github.io/soma/ (same site; the page lists the support email) |
| Support email | pranav.surampudi@gmail.com |
| Copyright | 2026 Pranav Surampudi |
| Age rating | Complete the questionnaire truthfully; see below |

## Promotional text (170)

Log a meal in ten seconds by saying it out loud. Connect Apple Health if you like. Soma keeps the record and points out patterns worth a second look.

## Description (4000)

Soma is a notebook for people who cook and want to notice how food and the body move together.

Say what you ate. "Eggs on sourdough, black coffee." Soma writes it down as a meal with an estimated calorie range, never a single number, because nobody knows a plate to the calorie. Correct it if it's wrong. Repeat it with one tap tomorrow.

If you connect Apple Health, Soma reads daily totals only: steps, sleep, resting heart rate, heart rate variability, weight, active energy and workout minutes. It never writes to Health. The raw readings never leave your phone.

Once a night, when there is enough to go on, Soma looks across your last month for associations between what you logged and how the days went, and tells you the ones that held up, in one hedged sentence each. Worth watching, not a verdict. No goals, no streaks, no calorie targets, no diet.

What Soma is not: it is not medical advice, it does not diagnose, and it does not tell you what to eat. It shows you your own record and what stands out in it. Talk to a clinician for anything that matters.

Privacy, plainly:
• Sign in with Apple. Hide My Email works.
• Meal text and the nightly summary go to Claude, an AI model made by Anthropic, only after you agree in the app. You can say no and keep logging.
• No ads, no tracking, no analytics SDKs, nothing sold.
• Export everything as a spreadsheet, or delete your account and all of its data, from inside the app.

iPhone only. Requires iOS 17.

## Keywords (100)

food diary,meal log,voice food log,food journal,apple health,sleep,notebook,cooking,eating log,hrv

## What's New (v1.0)

First release.

## App Review notes

Soma is a personal food journal with optional, read-only Apple Health correlation. It provides no diagnosis, treatment, dosing or medical guidance; every calorie is a range and every insight is hedged and non-prescriptive. Category is Food & Drink on purpose.

Sign-in: Sign in with Apple is the only login, and it is required because every record is a server-synced row owned by the account. There is no demo account for that reason. Any Apple ID works, including Hide My Email.

Third-party AI: after sign-in the app shows a one-time consent sheet naming Claude (Anthropic). Only with consent does meal text go to Claude for parsing, and only with consent does a nightly server job send a de-identified digest (meals, energy check-ins, and the seven daily Apple Health totals) to Claude to select and phrase insights. Consent is stored with the account and checked server-side; a declined user's data is never sent. Declining keeps the app usable: meals save as typed and can be filled in by hand.

HealthKit: read-only, seven types, all named in the purpose string. Raw samples are aggregated on device; only daily totals sync. Background delivery runs the same on-device rollup. Nothing is written to Health, and there is no iCloud entitlement.

Insights need about ten days of paired meal and health data, so a fresh account shows "keep logging" on the Noticed tab. To see the feature: [attach a 30–60 s screen recording of the Noticed tab on a seeded account]. Pull-to-refresh on that tab runs the engine on demand; a second pull within ten minutes is rate-limited with a friendly message, not an error.

Account deletion: kitchen (Settings) → delete account. It removes every row and revokes the Sign in with Apple token.

Contact for review questions: pranav.surampudi@gmail.com

## Age rating questionnaire — expected answers

- Violence, sexual content, profanity, horror, gambling, contests: none.
- Unrestricted web access: no.
- User-generated content shared with others: no (meal logs are private to the author; the only shared data is anonymous dish-name aliases with no author).
- Medical or treatment information / wellness topics: yes, wellness. Describe as a food and body journal that shows the user their own patterns; no diagnosis or treatment.
- Alcohol, tobacco, drug use or references: infrequent/mild, if the form asks (users can log a glass of wine; the app estimates alcohol grams as a range and never encourages it).
- Parental controls, in-app purchases, messaging, loot boxes: none.

Accept whatever rating the form assigns.

## Privacy nutrition label

All "linked to you", none used for tracking, all purpose "App Functionality".

| Category | Type | Why |
|---|---|---|
| Health & Fitness | Health | daily totals in `health_days` |
| User Content | Other User Content | meal text, parsed items, corrections, notes, check-ins, feedback |
| Identifiers | User ID | Supabase user id / app-scoped Apple id |
| Contact Info | Email Address | from Sign in with Apple when shared |
| Diagnostics | Other Diagnostic Data | app and iOS version on feedback rows |

Not collected: audio, photos, location, usage data, purchases, contacts, browsing, search history, sensitive info.

## Screenshots (iPhone 6.9" and 6.5", portrait)

Order and caption. Captions are optional; if used, keep them to these.

1. Noticed tab with two or three insight cards on a seeded account. Caption: "patterns in your own record, hedged."
2. Today with a few meals and calorie ranges visible. Caption: "say it, it's written."
3. Capture sheet mid-dictation. Caption: "ten seconds, by voice or by hand."
4. Today with the compare-yesterday overlay. Caption: "yesterday, laid over today."
5. HealthKit sheet showing the seven daily totals. Caption: "daily totals only. readings stay on your phone."
6. The consent sheet. Caption: "you decide what goes to Claude."

Do not include: the sign-in screen, the delete-account sheet, anything that reads as a goal or a target.
