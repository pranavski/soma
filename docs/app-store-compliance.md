# Soma — App Store Compliance Map (v1.0 submission)

_Last audited: 2026-07-19, against the App Store Review Guidelines as
updated 2025-11-13 (the "third-party AI" revision of 5.1.2(i)) and the
2025 expanded age-rating system._

This is a living checklist. Statuses:

- `[x]` **Done** — satisfied by current code/design; verify at archive time
- `[ ]` **CODE** — needs a code or Xcode-config change in this repo
- `[ ]` **ASC** — needs an action in App Store Connect (no code)
- `[ ]` **LEGAL** — needs a hosted legal artifact (privacy policy page, etc.)

Repo facts this audit is based on: `Soma.xcodeproj` exists;
`Soma/Soma.entitlements` has SIWA + HealthKit; `Soma/PrivacyInfo.xcprivacy`
exists; purpose strings live in build settings (`GENERATE_INFOPLIST_FILE =
YES`, `INFOPLIST_KEY_*`); account deletion is implemented
(`Soma/Features/Settings/DeleteAccountSheet.swift` +
`supabase/functions/delete-account` with SIWA token revocation); CSV export
exists (`MealExport.swift`); `docs/privacy-policy.md` exists but is not
hosted; **photo logging is live in code** (`TodayView` camera/library chips →
`parse-meal` photo branch → Roboflow + Claude) despite the spec calling it
"deferred to v1.1".

---

## 1. Guideline-by-guideline checklist

### 5.1.1(i) — Privacy policy (required in metadata AND in-app)

Apple requires a privacy policy link in the App Store Connect metadata field
**and inside the app, easily accessible**. It must identify what is
collected, all uses, third parties with access, retention/deletion, and how
to revoke consent.

- [x] Policy text written — `docs/privacy-policy.md` covers meals, HealthKit
  aggregates-only sync, Supabase, Anthropic, deletion, export
- [ ] **LEGAL** — Host the policy at a stable public URL (any static page)
- [ ] **ASC** — Set the Privacy Policy URL in App Store Connect
- [ ] **CODE** — Add a privacy-policy link inside the app. There is currently
  **no** link anywhere in Settings/About (`AboutSheet.swift` has none). A
  `Link` row in `SettingsView`/`AboutSheet` is sufficient
- [ ] **LEGAL** — Fix policy accuracy gaps before hosting:
  - It says Anthropic receives "meal text only". Not true twice over:
    (a) `generate-insights` sends HealthKit-derived correlation stats
    (RHR/HRV deltas, day counts) to Claude for copy generation;
    (b) the photo branch sends meal photos to **Roboflow** and (via the
    photo path) image content into the parse pipeline. The policy never
    mentions photos or Roboflow at all
  - Decide: either gate photo logging OFF for v1.0 (as the deployment
    checklist assumes) or update the policy + nutrition label + AI
    disclosure to cover photos and Roboflow

### 5.1.1 — Consent, purpose strings, data minimization

- [x] All data collection is user-initiated (log a meal, connect Health)
- [x] Purpose strings exist for HealthKit share/update, mic, speech, camera
  (see §4 for text and one required fix)
- [x] App works without HealthKit, without mic/speech (typed path), and
  degrades gracefully on denial (`SpeechCapture` error copy: "You can still
  type") — matches the "provide alternatives" requirement
- [x] Data minimization by design: raw HealthKit samples never leave the
  device; only 4 daily aggregate numbers sync (`HealthKitAggregator`)

### 5.1.1(v) — Account sign-in & deletion

- [x] In-app account deletion implemented (`DeleteAccountSheet` →
  `delete-account` Edge Function), deletes all rows, not just deactivation
- [x] SIWA token revocation via Apple REST API is implemented in
  `delete-account` (required for apps using Sign in with Apple)
- [ ] **ASC** — Revocation only works if the four `APPLE_*` secrets are set
  in Supabase (see `docs/deployment-checklist.md` §2). The function
  *silently skips* revocation without them — App Review has rejected apps
  for non-functional deletion. Set the secrets and run the smoke test
  (checklist §8 step 5) before submitting
- [x] Sign-in is genuinely required (all features are account-based
  server-synced records), so "allow use without login" does not apply —
  but be ready to justify this in Review Notes

### 5.1.1(ix) — Highly regulated fields

Soma is a wellness/lifestyle food journal, not healthcare delivery, so the
"submit via a legal entity, not an individual developer" rule for healthcare
apps should not bite. Risk is low but nonzero because the app touches health
data.

- [ ] **ASC** — In Review Notes, state plainly: Soma is a personal food
  journal with optional read-only Apple Health correlation; it provides no
  diagnosis, treatment, dosing, or medical guidance
- [x] Category is `public.app-category.food-and-drink` (already set in
  build settings) — deliberately not Medical, and not Health & Fitness,
  which lowers 1.4.1 scrutiny. Keep it

### 5.1.2(i) — Data sharing with third parties, **including third-party AI**
_(the November 13, 2025 guideline revision — this is Soma's biggest exposure)_

"You must clearly disclose where personal data will be shared with third
parties, **including with third-party AI**, and obtain **explicit
permission** before doing so." Generic "service providers" language is
insufficient; the provider should be identifiable, and privacy-policy-only
disclosure is the weakest possible position.

Soma sends user data to third-party AI from Edge Functions:
1. **Anthropic (Claude)** — meal text / voice transcripts (`parse-meal`),
   and rule-computed health stats for insight copy (`generate-insights`)
2. **Roboflow** — meal photos, base64, via hosted detection API
   (`parse-meal` photo branch) — *only if photo logging ships in v1.0*

Status:

- [x] Anthropic is named in the privacy policy with purpose and
  no-training note
- [ ] **CODE** — Add an **in-app, pre-first-use disclosure with explicit
  consent**. There is currently no onboarding/consent surface and no
  mention of Claude/Anthropic anywhere in the app UI. Minimum viable:
  a one-time sheet after first sign-in (or before the first meal parse):
  "Soma sends what you say or type about a meal to Anthropic's Claude to
  turn it into a structured entry. Nothing else — no health data, no
  identity — is included. [privacy policy link] — OK / Not now", with
  "Not now" leaving manual/typed logging functional or clearly gating
  parse. Persist the acceptance
- [ ] **CODE or product decision** — `generate-insights` sends
  HealthKit-derived deltas to Claude. Safest fix: use deterministic
  template copy for the four v1 rules and drop the Claude call (the stats
  are already computed rule-side); otherwise the disclosure and privacy
  policy must say health-derived aggregates reach Anthropic, which
  interacts badly with 5.1.3 (below)
- [ ] **CODE or product decision** — Roboflow: either gate the photo path
  off for v1.0, or add it to the disclosure, policy, and nutrition label

### 5.1.2(vi) + 5.1.3(i) — HealthKit data restrictions

HealthKit-sourced data may not be used for advertising, marketing, or
use-based data mining, and may not be disclosed to third parties except to
improve health management (with permission) or for health research.

- [x] No ads, no analytics SDKs, no data brokers, no tracking anywhere in
  the app — satisfied by design
- [x] Raw HealthKit reads stay on-device; server only ever sees 4 daily
  aggregate numbers per day (`health_days` table)
- [ ] **CODE (same item as above)** — the `generate-insights` → Claude call
  transmits HealthKit-*derived* statistics to a third party. It is arguably
  within the "improving health management" exception and carries no user
  identifier, but it contradicts the privacy policy's "meal text only"
  claim and is exactly the pattern the Nov-2025 AI revision targets.
  Recommendation: template copy, no Claude call for insights
- [x] The app discloses which health data types it reads (purpose string
  lists steps, sleep, resting HR, HRV; `HealthKitSheet` in Settings)

### 5.1.3(ii) — No false HealthKit writes; no health data in iCloud

- [x] App never writes to HealthKit (`NSHealthUpdateUsageDescription` says
  so; no write authorization requested)
- [x] No iCloud/CloudKit entitlement in `Soma.entitlements`; health
  aggregates go to Supabase Postgres, not iCloud. Do **not** add CloudKit
  sync for `health_days` later without re-reading this rule

### 5.1.3(iii)/(iv) — Human-subject research

- [x] Not applicable — Soma shows users their own data, performs no
  research, no cohorting, no data aggregation across users. Never describe
  the insight engine as "research" in marketing copy

### 1.4.1 — Physical harm / medical apps

Apps providing health measurements get scrutiny; claims must be backed by
methodology; apps "should remind users to consult a doctor before making
medical decisions."

- [x] By design: no diagnosis, no goals, no calorie targets, calories always
  ranges ("~550–700"), insights hedged and non-prescriptive ("worth
  watching, not a verdict") — this is the single best defense against
  medical classification
- [ ] **CODE** — Add a short "not medical advice" line in a visible spot
  (Insights empty state footer and/or About sheet), e.g.: "Soma shows
  patterns in your own logs. It isn't medical advice — talk to a doctor
  about health decisions." Cheap insurance against a 1.4.1 reading
- [ ] **ASC** — App Store description: never use "track your health,"
  "improve your metabolism," "lose weight," or any outcome claim.
  Describe it as a food journal that shows patterns
- [x] Calorie estimates are presented as explicit ranges with no accuracy
  claim — do not add "accurate calorie counting" language anywhere

### 2.5.1 — APIs used for intended purposes

- [x] HealthKit is used for health/fitness purposes integrating with the
  Health app — compliant
- [x] Only public APIs (SwiftUI, HealthKit, Speech, AVFoundation,
  AuthenticationServices, PhotosUI)

### 4.8 — Login Services

- [x] Compliant by construction: Sign in with Apple is the **only** login.
  The 4.8 obligation (offer a privacy-preserving alternative) triggers only
  when third-party social logins are offered. If Google sign-in is ever
  added, SIWA must remain

### Privacy manifest & required-reason APIs (App Store Connect enforcement since May 2024)

- [x] `Soma/PrivacyInfo.xcprivacy` exists with `NSPrivacyTracking = false`,
  empty tracking domains, four collected data types, four accessed-API
  categories (see §3 for full review)
- [x] Supabase Swift SDK: not on Apple's "SDKs that require a privacy
  manifest and signature" list; supabase-swift ships its own
  `PrivacyInfo.xcprivacy` bundle (verify it's present in the resolved
  package at archive time)
- [ ] **CODE (verify)** — At archive time, generate the **privacy report**
  (Xcode Organizer → archive → Generate Privacy Report) and confirm the
  aggregate manifest matches §2's nutrition-label draft; fix any
  required-reason API findings the report surfaces

### Age rating (2025 system: 4+, 9+, 13+, 16+, 18+)

The expanded questionnaire (mandatory for all submissions since
2026-01-31) added required questions on in-app controls, capabilities, and
**medical or wellness topics**.

- [ ] **ASC** — Complete the updated questionnaire. Expected answers:
  no objectionable content, no user-generated *shared* content (meal logs
  are private to the author), no web browsing, no gambling. For the
  "medical or wellness topics" question answer truthfully (food/wellness
  journaling) — expect a 4+ or possibly 13+ outcome; accept what the
  questionnaire assigns, do not game it
- [x] Nothing in-app requires an elevated rating (no chat, no UGC feed,
  no purchases)

### Voice / microphone / speech

- [x] `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`
  present (build settings)
- [x] Audio is never stored or uploaded — only the transcript is sent to
  `parse-meal`. So the nutrition label needs "Other User Content" (the
  transcript), **not** "Audio Data"
- [ ] **CODE** — **Mismatch:** the purpose string claims "on-device speech
  recognition", but `SpeechCapture.swift` never sets
  `request.requiresOnDeviceRecognition = true`, so iOS may route audio
  through Apple's servers. Pick one:
  - (a) set `requiresOnDeviceRecognition = true` when
    `recognizer.supportsOnDeviceRecognition` (keeps the string honest;
    slightly lower accuracy), or
  - (b) soften the string (drop "on-device") — see §4 draft.
  A purpose string that overstates privacy is a rejection/metadata risk

### Camera / photos (only if photo logging ships in v1.0)

- [x] `NSCameraUsageDescription` present; photo library uses `PhotosPicker`
  (out-of-process — no permission or `NSPhotoLibraryUsageDescription`
  needed, and it matches 5.1.1's "use out-of-process pickers" preference)
- [ ] **Decision required** — Deployment checklist says photo logging is
  deferred to v1.1 and screenshots must not show it, but
  `TodayView`/`TodayViewModel.submitPhoto`/`parse-meal` photo branch are
  live. If it ships: add "Photos or Videos" to the nutrition label +
  manifest, cover photos/Roboflow in the policy and AI disclosure. If
  deferred: feature-flag the chips off. Shipping a hidden-but-reachable
  feature that Review discovers but screenshots deny is its own risk

### Other submission blockers (from repo state)

- [ ] **CODE** — App icon: `Assets.xcassets` appiconset is empty; Xcode
  will refuse to archive for distribution without the 1024pt icon
- [x] iPhone-only, portrait-only, iOS 17+ — set in project
- [ ] **ASC** — Screenshots (iPhone only), subtitle, keywords, support URL
  (required alongside the privacy policy URL)

---

## 2. Privacy Nutrition Label — draft declarations (App Store Connect)

Global answers: **Tracking: NO** for every type (no third-party
ad/broker linkage anywhere). All collected types are **Linked to the
user** (rows are keyed to the Supabase user id). Purpose is **App
Functionality** in every case.

| Data type | Collected? | Linked to user | Tracking | Purpose | What it actually is |
|---|---|---|---|---|---|
| Health & Fitness → **Health** | Yes | Yes | No | App Functionality | Daily aggregates only: steps, sleep minutes, resting HR, HRV (`health_days`). Raw samples never leave device |
| User Content → **Other User Content** | Yes | Yes | No | App Functionality | Meal text/voice transcripts, parsed items, corrections, notes, energy check-ins, feedback |
| User Content → **Photos or Videos** | Only if photo logging ships | Yes | No | App Functionality | Meal photos in private Supabase bucket |
| Identifiers → **User ID** | Yes | Yes | No | App Functionality | Supabase user UUID / app-scoped Apple ID |
| Contact Info → **Email Address** | Yes | Yes | No | App Functionality | From Sign in with Apple, only if user shares it (Hide My Email respected). Declare it: it is stored with the auth record |
| Diagnostics → **Other Diagnostic Data** | Only if actually retained | Yes | No | App Functionality | Currently declared in the manifest; if nothing beyond transient request logs is stored, this can be dropped from both manifest and label |
| User Content → Audio Data | **No** | — | — | — | Audio is processed for transcription and discarded; only the transcript (Other User Content) is stored |
| Usage Data, Location, Browsing, Purchases, Contacts, Search History, Sensitive Info | **No** | — | — | — | Not collected |

Notes:
- The Claude/Roboflow calls do not add label categories by themselves
  (ephemeral server-side processing), but the *stored results* (parsed
  meals, insights) are already covered under Other User Content /
  Health.
- "Email Address" is currently missing from `PrivacyInfo.xcprivacy` —
  add it there too (§3) so the manifest and label agree.

---

## 3. Privacy manifest (`Soma/PrivacyInfo.xcprivacy`) — current vs. required

Current file (verified 2026-07-19):

- `NSPrivacyTracking` = `false`; `NSPrivacyTrackingDomains` = `[]` — correct
- `NSPrivacyCollectedDataTypes`: HealthFitness, OtherUserContent, UserID,
  OtherDiagnosticData — all linked=true, tracking=false, purpose
  AppFunctionality
- `NSPrivacyAccessedAPITypes`: UserDefaults `CA92.1`, FileTimestamp
  `C617.1`, DiskSpace `E174.1`, SystemBootTime `35F9.1` — all valid
  self-access reason codes

Deltas to apply:

1. **Add** `NSPrivacyCollectedDataTypeEmailAddress` (linked=true,
   tracking=false, purpose AppFunctionality) — SIWA email is stored with
   the account when shared.
2. **Add** `NSPrivacyCollectedDataTypePhotosorVideos` (same flags) —
   *only if* photo logging ships in v1.0.
3. **Reconsider** `NSPrivacyCollectedDataTypeOtherDiagnosticData` — if no
   diagnostic data is actually retained server-side, remove it from
   manifest and label rather than over-declaring.
4. At archive time, cross-check against the Xcode privacy report so the
   app manifest + supabase-swift's bundled manifest = the ASC label.

---

## 4. Purpose strings — current text and required fix

Set via `INFOPLIST_KEY_*` build settings (both Debug and Release — keep in
sync). Apple's quality bar: say what is accessed, when, and why, in the
user's language; never overstate.

| Key | Current | Verdict |
|---|---|---|
| `NSHealthShareUsageDescription` | "Soma reads steps, sleep, resting heart rate, and HRV so it can look for gentle correlations with how you're eating and feeling. Reads only — nothing is written back." | Keep. Names the exact types, states the purpose, states read-only |
| `NSHealthUpdateUsageDescription` | "Soma does not write to HealthKit." | Keep (key must exist for some SDK paths; honest) |
| `NSMicrophoneUsageDescription` | "Soma listens only while you tap the speak button, to turn what you say into a meal entry." | Keep |
| `NSSpeechRecognitionUsageDescription` | "Soma uses on-device speech recognition to turn spoken meals into text." | **Fix.** Code does not force on-device recognition. Either set `requiresOnDeviceRecognition` in `SpeechCapture` or replace with: "Soma turns what you say into meal text. Recognition may use Apple's speech service; Soma never stores or uploads the audio." |
| `NSCameraUsageDescription` | "Soma uses the camera only when you snap a meal photo, to turn it into a meal entry." | Keep if photos ship; harmless if the feature is flagged off |

---

## 5. Risks / likely rejection reasons (ranked)

1. **Third-party AI without in-app consent — 5.1.2(i), Nov 2025 text.**
   Meal text goes to Anthropic with no in-app disclosure or permission
   flow; Roboflow isn't disclosed anywhere. This is the exact pattern the
   revision targets and the most probable rejection. Fix: named, explicit,
   pre-first-parse consent sheet + policy accuracy.
2. **Privacy policy inaccuracies.** "Anthropic gets meal text only" is
   contradicted by `generate-insights` (health-derived stats) and the
   photo branch (Roboflow). Reviewers diff app behavior against the
   policy; inaccurate policies fail 5.1.1(i). Fix policy or fix behavior
   (template insight copy; gate photos).
3. **No in-app privacy policy link.** Hard requirement of 5.1.1(i);
   currently absent from Settings/About. One `Link` row fixes it.
4. **Health-derived data reaching a third-party AI — 5.1.3(i) optics.**
   Even de-identified deltas invite the "health data shared with AI"
   reading during review of a HealthKit app. Cheapest de-risk: generate
   insight copy from templates, keep Claude out of the health path
   entirely, and say so proudly in Review Notes.
5. **Non-functional account deletion at review time.** If the `APPLE_*`
   secrets aren't configured, token revocation silently no-ops; reviewers
   do test deletion on SIWA apps (5.1.1(v)). Also blockers of the boring
   kind: missing app icon (cannot archive), unhosted policy URL, and the
   speech purpose-string/on-device mismatch (metadata dishonesty reads
   badly in an otherwise privacy-forward app).

Secondary watch items: 1.4.1 medical framing in App Store copy (keep
"journal/patterns", add the not-medical-advice line); age-rating
questionnaire "medical or wellness" answer; never add CloudKit sync for
`health_days` (5.1.3(ii)); if Google login ever appears, 4.8 re-triggers.

---

## Sources

- [App Review Guidelines — Apple Developer](https://developer.apple.com/app-store/review/guidelines/)
- [Updated App Review Guidelines now available (Nov 13, 2025) — Apple Developer News](https://developer.apple.com/news/?id=ey6d8onl)
- [Apple's new App Review Guidelines clamp down on apps sharing personal data with "third-party AI" — TechCrunch](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai/)
- [App Privacy Details on the App Store — Apple Developer](https://developer.apple.com/app-store/app-privacy-details/)
- [Privacy manifest files — Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Adding a privacy manifest to your app or third-party SDK — Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Offering account deletion in your app — Apple Developer Support](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Account deletion requirement — Apple Developer News](https://developer.apple.com/news/?id=12m75xbj)
- [Updated age ratings in App Store Connect — Apple Developer News](https://developer.apple.com/news/?id=ks775ehf)
- [Age Rating Updates — Upcoming Requirements — Apple Developer](https://developer.apple.com/news/upcoming-requirements/?id=07242025a)
