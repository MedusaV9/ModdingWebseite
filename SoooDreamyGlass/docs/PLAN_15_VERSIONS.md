# SoooDreamy — 15-Version Roadmap to a Highly Polished Couples App

**Plan author:** senior mobile app architect / product & polish planner (analysis-only pass, 2026-08-11)
**App author credit (constraint):** every shipped version carries "made by Sonic0810" (DE: „made by Sonic0810" — the credit is a proper name and stays untranslated).
**Scope:** `SoooDreamy/` (iOS SwiftUI app + Node self-hosted server) inside the repo at `/home/ubuntu/work/soodreamy`.

---

## 1. Current-State Assessment (what is actually in this repo)

### 1.1 Repo layout — two unrelated products share one repository

| Path | What it really is | Relevance to this plan |
|---|---|---|
| `src/`, `index.html`, `package.json` (repo root) | **BAPBAP Modding fan site** — Vite + React 19 + TS + Tailwind v4, HashRouter, oxlint. It is NOT a couples-app web client. It already credits Sonic0810 (`src/data/links.ts`, `src/components/Footer.tsx` → github.com/Sonic0810). | Out of scope for couples-app features. It is only relevant as (a) proof of the Sonic0810 authorship convention and (b) a reminder that CI/branch hygiene must not break it. |
| `SoooDreamy/server/` | Node ≥ 20 self-hosted couple server, **only dependency `ws`**, JSON-file storage, REST + WebSocket, v4.0.0. **225 E2E/security/adversarial tests** across 43 files (`node --test`). | Primary Linux-verifiable surface. |
| `SoooDreamy/ios/` | SwiftUI iOS 17+ app, **195 Swift files**, XcodeGen (`project.yml`, MARKETING_VERSION 4.0.0, build 26), widget extension (8 widgets, 3 Live Activities, 2 iOS-18 controls), procedural app icons (9 variants, `scripts/GenerateIcon.swift`, **zero binary assets in repo**). | The shippable product. Cannot be built on Linux. |
| `SoooDreamy/ios/Package.swift` + `LogicTests/` | SwiftPM manifest that cherry-picks ~40 Foundation-only sources (content packs, game reducers, LevelMath, CommitReveal, HapticPatternKit, OfflineOutbox, L10n tables…) so **`swift test` runs on Linux** — 31 test files, ~170 tests at 3.0 time, more added in 4.0. | Second Linux-verifiable surface. |
| `SoooDreamy/docs/` | `API.md` (534 lines), `CHANGELOG.md`, `CREDITS.md`, `EVAL-3.0.md` (independent evaluation with a prioritized P0/P1/P2 fix queue), `ideen/` (3 idea-lens docs, ~107 scored ideas). | Source for the bug register and the idea backlog below. |
| `.github/workflows/sooodreamy.yml` | 4 jobs: server tests (ubuntu), Swift logic tests (`swift:6.0` container on ubuntu), **unsigned IPA on `macos-15`** (XcodeGen → `xcodebuild CODE_SIGNING_ALLOWED=NO` → zip `Payload` → `.ipa` artifact), rolling prerelease `sooodreamy-latest`. | The IPA pipeline already exists and has produced green builds. |

### 1.2 Feature maturity

This is **not** a greenfield app. Version 4.0.0 already ships: pairing (code + QR, multi-server), chat (letters, sealed "open when…" letters, voice notes, reactions, photo bubbles, edit/delete, pins), daily question with streak + journal, couple Wordle + duel, 16 server-authoritative games (Battleship with commit-reveal, Kniffel, Pictionary, Connect Four, Photo Memory, Quiz Duel, Stadt-Land-Fluss, Two Truths, Movie Roulette, …), daily quests, tournaments/seasons, replay viewer, rituals (audio check-in, time capsules, need button, goals, week plan, energy light, monthly magazine), gallery/videos, E2E-encrypted Spicy Vault, haptic studio + haptic duet, relationship level + 20 badges, delight engine, 8 widgets + Live Activities + iOS-18 controls, app lock, iCloud fallback, DE/EN in-app localization (~1,650 keys across 7 tables enforced by a static usage scan test).

### 1.3 Quality state

- Server suite green at **225/225** (4.0). Logic tests green at **161/161** at 3.0; 4.0 added outbox/cold-cache/FIFO tests (not yet executed on this VM — no Swift toolchain installed here; AGENTS.md documents installing Swift 6 from swift.org or using the `swift:6.0` container).
- Last verified green macOS CI runs produced the unsigned IPA (documented in `EVAL-3.0.md`); later runs were blocked **only** by a GitHub billing limit on a private mirror — not a code failure.
- `EVAL-3.0.md` graded 3.0 between 5.5 and 7.8 per area; version 4.0 closed the P0 contract items (server authority, seed injection, widget snapshot fields, needs digest, FIFO ceremony queue, capsule unlock timing, movie-match → weekplan CTA via `Content/MovieNightLogic.swift`). Verified-still-open items are in the bug register (§8).

### 1.4 What is missing relative to this task's constraints

| Constraint | Current state |
|---|---|
| "made by Sonic0810" in the app | **Absent.** `AboutSheet` (`Features/Settings/SettingsView.swift`) says only "Built with 💜 — for the two of you." |
| Top-level `versions/` folder with numbered artifacts | **Does not exist.** |
| Top-level `PATCHNOTES.md` updated per version | **Does not exist** (only `SoooDreamy/docs/CHANGELOG.md`, German-leaning). |
| DE+EN user manual ("Handbuch") | **Does not exist.** |
| CI builds on the current working branch | **Broken:** the workflow's `push.branches` filter lists three old branches; the current branch is not matched. `workflow_dispatch` works as a manual fallback. |

---

## 2. The Shipping Reality: How the .ipa Gets Built (no Mac on this side)

### 2.1 Hard facts

- The shippable artifact is an **iOS `.ipa`**; producing it requires Xcode on macOS. **A Linux machine can never produce it.** Nothing in this plan pretends otherwise.
- There is **no signing identity** in this project (`DEVELOPMENT_TEAM: ""` in `project.yml`). All release lanes below assume none exists unless a paid Apple Developer secret is added later.

### 2.2 The three verification/build lanes

**Lane A — Linux (this environment, every commit):**
1. `cd SoooDreamy/server && npm ci && npm test` — 225+ E2E tests, no DB needed.
2. `swift test --package-path SoooDreamy/ios` — pure-logic suite (game reducers, content packs, L10n parity, LevelMath, CommitReveal, outbox, …). Requires the Swift 6 toolchain (swift.org tarball) or `docker run swift:6.0`; **not currently installed on this VM** — installing it is step 0 of v1.
3. `swiftc -parse` over all 195 Swift files — syntax gate before every push (per AGENTS.md).
4. Manual browser QA on Linux via the **Dev Cockpit** (a dev-only static web harness served by the Node server, added in v2 — see below). The root Vite site is *not* a couples-app client and is not part of this loop.

**Lane B — macOS GitHub Actions runner (per push, free):**
- **Public repo = free macOS runners.** GitHub-hosted standard runners are free on public repositories (the 10× macOS minute multiplier only applies to private-repo minute billing). The 3.0-era "billing limit" failures happened on a **private** mirror (`CustomServerPrivate`); on the public repo this class of failure disappears. Action item (v1): keep SoooDreamy work on the public repo, fix the workflow branch filter, and prefer `paths:`-scoped triggers over a hardcoded branch list.
- **Unsigned device build (the shipped artifact):** `xcodegen generate` → `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO …` → zip `Payload/` → `SoooDreamy-unsigned-<version>.ipa`. **This is acceptable and is the plan of record**: AltStore / SideStore / Sideloadly re-sign the IPA with the user's free Apple ID at install time. Honest limits (already documented in `SoooDreamy/README.md`, must stay in the Handbuch): free-Apple-ID 7-day resign cycle and 3-app cap; `aps-environment` (remote push) and iCloud entitlements are stripped by free profiles (the app detects this and degrades); App Groups (widgets) survive when the sideload tool co-signs them.
- **Simulator lane (verification without any Mac):** a second CI job builds `-sdk iphonesimulator`, boots a simulator with `xcrun simctl`, launches the app against a server started on the runner, and captures a **screenshot suite** (and, from v5 onward, runs a small XCUITest smoke). This is how UI changes get visually verified every version with zero human Macs. Simulator caveats are documented per feature (no CoreHaptics, no camera; those need the sideload checklist).
- **Optional signed lane (dormant):** an `exportOptionsPlist`-based archive job that activates only if `APPLE_CERT_P12`/`APPLE_PROFILE` secrets ever appear. Not required for any of the 15 versions.

**Lane C — Real device (optional, never a release blocker):**
- Each version's PATCHNOTES lists a 5–10-minute **sideload checklist** for the couple (haptics, widgets after re-sign, Live Activities, camera/mic flows). Results are recorded honestly as `device-verified: yes/no` per version. Features whose acceptance criteria would *require* a device (e.g. haptic feel) always have a simulator- or logic-level proxy criterion as the gate.

### 2.3 Per-version artifact policy (`versions/` + PATCHNOTES + Handbuch)

Every version vNN ships a folder:

```
versions/
  v01-4.1.0/
    SoooDreamy-unsigned-4.1.0.ipa    ← downloaded from the green CI run
    SHA256SUMS                       ← checksums of every file in the folder
    BUILD.md                         ← exact recipe: commit SHA, CI run URL,
                                        xcodegen/xcodebuild commands, how to
                                        rebuild on any Mac or fork CI
    PATCHNOTES.de.md / PATCHNOTES.en.md  ← this version's excerpt
    verification/
      server-tests.txt  logic-tests.txt  screenshots/  (simulator suite)
    web/                             ← only where a web artifact exists
                                        (Dev Cockpit build, v2+)
```

- **If CI cannot run** (outage, or work happens on a fork without Actions): the folder ships everything except the `.ipa`, `BUILD.md` is the authoritative recipe, and the `.ipa` is backfilled by the next green run. A version is still "shipped" in the documented-recipe sense — this is the explicit fallback the constraints allow.
- **Repo-size honesty:** unsigned IPAs are ~3–6 MB; 15 of them ≈ 50–90 MB of git history. That is tolerable but noted; if it becomes a problem, switch `versions/**/*.ipa` to Git LFS (documented in `BUILD.md`, never silently). The SoooDreamy-subtree "no binary assets" policy applies to *app source assets* (icons/sounds stay procedural); `versions/` is an explicit, quarantined exception for release artifacts and verification screenshots.
- Top-level **`PATCHNOTES.md`**: reverse-chronological, one section per version, **DE first then EN** in the same file, subsections *Neu / Features*, *Behoben / Fixed*, *Feinschliff / Polish*, *Ehrliche Grenzen / Honest limits*.
- **Handbuch:** `docs/HANDBUCH.de.md` + `docs/MANUAL.en.md`, chapter per tab (Home, Chat, Spiele/Play, Wir/Us, Einstellungen/Settings) plus Setup (server + sideload), Troubleshooting, FAQ. Started in v1, feature-complete in v9, final in v15. Illustrations are SVG/Mermaid in-repo; real screenshots live in `versions/*/verification/screenshots/` and are linked, keeping the source tree binary-free.

---

## 3. Global Definition of "Shippable" (applies to every version)

A version may be tagged and placed in `versions/` only when **all** of the following hold:

1. Server suite green (count never decreases; new features add tests).
2. Swift logic suite green on Linux (count never decreases).
3. `swiftc -parse` clean on all Swift files.
4. macOS CI: unsigned IPA job green **and** simulator screenshot suite captured (or the documented-recipe fallback of §2.3 is invoked and stated in PATCHNOTES).
5. `PATCHNOTES.md` updated (DE+EN), Handbuch updated for every user-visible change (DE+EN).
6. Version numbers bumped in lockstep: `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`), `server/package.json`, About sheet, PATCHNOTES.
7. **L10n gate:** the static `L10nUsageTests` scan passes; zero hardcoded user-facing strings in new code; DE and EN both reviewed in context (DE strings are ~20–30 % longer — layout must not truncate).
8. **Polish rubric gate (§4) passed for every screen the version touched.**
9. "made by Sonic0810" visible in About + PATCHNOTES footer + Handbuch title page (from v1 onward).

## 4. The Strict Polish Rubric (scored 0–10 per touched screen; gate = every dimension ≥ 8, R5 and R9 = 10)

| # | Dimension | What 10/10 means (checkable) |
|---|---|---|
| R1 | Visual consistency | Only Liquid-Glass design tokens (`UI/Theme.swift`, `LayoutMetrics`); 4-pt spacing grid; no ad-hoc colors/fonts; identical corner radii per component class. |
| R2 | Motion | Micro-interactions 150–450 ms with standard curves; nothing blocks input > 500 ms; `prefers-reduced-motion`/Reduce Motion honored everywhere (already a pattern in `useReveal`/SeasonEffects — must be universal). |
| R3 | Haptics & sound | Every intentional action has a mapped haptic intensity; sounds respect per-category volume settings; silence during quiet hours (v6+); no haptic/sound spam (rate-limited by the Delight engine). |
| R4 | State completeness | Every screen has designed loading / empty / error / offline / stale states; retry is always one tap; no spinner without timeout+message. |
| R5 | Localization (DE+EN) — **must be 10** | All strings through L10n tables; DE fits without truncation at Dynamic Type XL; dates/numbers via `Locale`-aware formatters; shared-content strings (chat shares, patchnotes) exist in both languages. |
| R6 | Accessibility | VoiceOver labels + traits on all interactive elements; 44-pt minimum targets; Dynamic Type up to XXL without clipping; contrast ≥ 4.5:1 for text. |
| R7 | Performance | 60 fps scroll on the touched screens (simulator Instruments proxy + code review of per-frame allocations); cold start < 2.5 s to dashboard with warm cache; gallery memory bounded by downsampling (pattern from `CGImageSourceCreateThumbnailAtIndex` applied universally). |
| R8 | Resilience | Kill the network mid-flow → no data loss, idempotent retry (outbox pattern); server restart mid-session → client resyncs without user action; all new writes covered by an adversarial server test. |
| R9 | Honesty — **must be 10** | UI never claims something undelivered (the 3.0 lesson); every sideload-gated capability (push, iCloud, haptics-on-simulator) is labeled in-context; PATCHNOTES "Ehrliche Grenzen" filled per version. |
| R10 | Coherence | New features are wired end-to-end: emits app-events → XP/badges where sensible → widget snapshot where sensible → Handbuch section exists → discovery surface (What's-New) mentions it. |

Rubric audits are recorded per version in `versions/vNN-*/verification/rubric.md` with a score table per touched screen.

---

## 5. The 15 Versions

Marketing-version mapping: roadmap **v1–v9 → 4.1.0–4.9.0**, **v10 → 5.0.0**, **v11–v14 → 5.1.0–5.4.0**, **v15 → 6.0.0**. Build number increments every version (27…41).

---

### v1 (4.1.0) — „Fundament & Autorenschaft" / "Foundation & Authorship"

The release machine itself becomes a product: constraints land, CI is fixed, doc/test debt from EVAL-3.0 is closed. No new couple-facing features — this version buys trust in every later one.

**(a) Features**
- `versions/` folder scheme + `PATCHNOTES.md` (top level, DE+EN) + Handbuch skeleton (`docs/HANDBUCH.de.md`, `docs/MANUAL.en.md`: Setup, Pairing, Sideload guide, honest-limits chapter).
- **"made by Sonic0810"** in the About sheet (`Features/Settings/SettingsView.swift` `AboutSheet`), in `SoooDreamy/README.md`, PATCHNOTES footer, Handbuch title pages. New L10n keys `settings.credit` (value identical in DE/EN).
- CI overhaul (`.github/workflows/sooodreamy.yml`): replace the stale branch list with `paths:`-filtered triggers on all `cursor/**` + `main`; add a version-tag job (`sooodreamy-vNN` tag per release) and name artifacts `SoooDreamy-unsigned-<version>.ipa`; add the **simulator build + screenshot** job (Lane B).
- Linux dev-environment recipe: pin the Swift 6 toolchain install into AGENTS.md §Cloud (this VM currently has **no** `swift` binary — that is a real gap in the loop today).

**(b) Bug fixes**
- `LogicTests/L10nTests.swift`: table-parity test still omits `RitualsL10n` and `PlatformL10n` (verified absent) — add them, as EVAL-3.0 P2 demanded.
- `docs/API.md` drift: add a **contract test** that diffs documented event names/error codes against `server/src/events.js` exports (EVAL found `still_sealed` vs `still_locked`, `goal_completed` vs `goal_reached`, phantom `daymemo_streak`). Fix the doc, keep the test.
- Workflow branch filter (see above) — today a push on the current branch builds **nothing**.

**(c) Polish/UX** — About sheet gets version + build + server version + credit in one glass card; PATCHNOTES rendered in-app later (v2) so copy style is set now: warm, honest, both languages.

**(d) Assets** — none binary. SVG wordmark "made by Sonic0810" for Handbuch title pages (inline SVG).

**(e) DE+EN localization** — ~10 new keys (credit, about labels); PATCHNOTES + Handbuch templates in both languages; define the bilingual writing style guide (informal „ihr/du", warm tone; EN mirror).

**(f) Acceptance criteria**
- A push to the working branch triggers all 4+1 CI jobs; green run produces `SoooDreamy-unsigned-4.1.0.ipa` + simulator screenshots; `versions/v01-4.1.0/` populated per §2.3.
- `swift test` runs green **on this Linux VM** after the documented toolchain install.
- API contract test fails if a doc/event mismatch is reintroduced (prove by mutation once).
- About sheet screenshot (simulator) shows the credit in DE and EN.
- **Rubric gate:** touched screens = About/Settings only; R1–R10 ≥ 8, R5/R9 = 10.

---

### v2 (4.2.0) — „Klarheit: Dashboard & Entdeckung" / "Clarity: Dashboard & Discovery"

Fixes the two loudest EVAL-3.0 UX findings: a ~23-card fixed-order dashboard and zero discovery for existing couples.

**(a) Features**
- **Dashboard priority engine**: sections get scores (urgency: open need > unopened capsule > your-turn games > today's rituals > evergreen); top 4 render expanded, the rest collapse into themed groups („Rituale", „Spiele", „Momente") with badge counts. Local **edit mode**: reorder, hide, pin (persisted per device; backlog idea C-23).
- **„Neu in dieser Version"** discovery: a What's-New sheet generated from PATCHNOTES keys, shown once per version to *existing* couples (the Erste-Woche quest stays for new couples), each entry deep-links to the feature. Doubles as the in-app patchnotes browser.
- **Dev Cockpit** (Lane A tooling, not in the IPA): a static two-pane HTML page served by the Node server under `/dev/cockpit` (dev flag only) that drives two paired members via the REST/WS API — send touches, answer dailies, make game moves, watch WS events. This is the "web build" artifact for versions whose IPA lane is unavailable, and the Linux manual-QA surface for every later version.

**(b) Bug fixes**
- Ceremony FIFO queue (added in 4.0, `Core/FIFOQueue.swift`): audit the RootView presentation path so a level-up + badge + icon-gift burst presents strictly sequentially; add logic tests for ordering/coalescing.
- Dashboard flashback card reset on server switch (regression guard test — an old fix worth pinning).

**(c) Polish/UX** — collapse/expand animations ≤ 300 ms; skeleton loaders for dashboard cards; empty-dashboard state for brand-new couples; badge counts use tabular numerals.

**(d) Assets** — none; cockpit is dependency-free hand-written HTML/CSS/JS (matches server's zero-dependency ethos).

**(e) DE+EN** — ~40 keys (section titles, edit mode, What's-New UI); What's-New content strings per version come from the PATCHNOTES source of truth in both languages.

**(f) Acceptance**
- Simulator screenshots: default dashboard ≤ 6 expanded blocks above the fold on iPhone 16; edit mode reorder persists across relaunch.
- What's-New appears exactly once per version per device (logic test on the version-gate).
- Cockpit: a scripted two-member flow (pair → touch → daily → game move) runs on Linux with only Node — recorded as `verification/cockpit-smoke.txt`.
- Server suite ≥ 225 + new tests; logic suite grows (queue tests).
- **Rubric:** dashboard + What's-New screens; R1–R10 ≥ 8, R5/R9 = 10.

---

### v3 (4.3.0) — „Ehrliche Spiele-Politur" / "Honest Game Polish: Replay, Seasons, Shell"

Closes the remaining EVAL-3.0 game findings and unifies the 16 game UIs.

**(a) Features**
- **Replay 2.0 — the real state-film**: per-game replay adapters run the pure reducers (`Content/*Logic.swift`) to move index N and render actual boards/dice/grids (Battleship, Kniffel, Connect Four, Stadt-Land-Fluss, Two Truths first; Pictionary replays strokes). Until a game has an adapter its replay is explicitly labeled „Zugprotokoll"/"move log" (R9).
- **Season completeness**: tournament ingestion covers *all* finished games (server-side aggregated endpoint with pagination instead of the client's last-100 window) **and** merges the separate Wordle-duel history into season points; UI copy scoped to exactly what counts.
- **Unified game shell**: one lobby/waiting/rematch/score-header component family so all 16 games share identical affordances (join banner, turn indicator, forfeit, share-result).

**(b) Bug fixes**
- `Features/Games/ReplayView.swift` + `Content/ReplayLogic.swift`: current player renders a localized event list, not game state (verified — no reducer call in the view). This is the P1 „Replay ist ein Eventlog" item.
- `Features/Games/TournamentView.swift`: last-100/`result.scores`-only/no-Wordle season derivation (EVAL P1).
- Kill lingering game-session state on server switch (regression tests around `GamesCoordinator`).

**(c) Polish** — winner-row shimmer normalized across games; consistent rematch haptic; replay scrubber with turn markers and the ⭐ turning-point chip; spectator mode gets a „live" pulse.

**(d) Assets** — none binary; board-rendering styles derive from existing Theme tokens.

**(e) DE+EN** — ~60 keys (replay controls, season copy, shell states). GamesL10n is already the largest table (~486 entries) — split it per game if the file exceeds ~600 keys (maintainability, not user-visible).

**(f) Acceptance**
- Logic tests: replay adapter for each covered game reproduces the final state of 3 recorded fixtures move-by-move (pure Swift, Linux).
- Server test: season aggregate endpoint returns identical totals to a brute-force recomputation over a 250-game fixture including Wordle.
- Simulator: replay of a finished Kniffel shows dice, not text lines (screenshot).
- **Rubric:** all game screens touched by the shell get audited; R9 = 10 (no "film" claim without an adapter).

---

### v4 (4.4.0) — „Filmabend 2.0" / "Movie Night 2.0"

Movie night graduates from a roulette minigame to a full couple ritual (explicit focus area of this roadmap).

**(a) Features**
- **Movie-Night-Hub** (Play tab): plan (roulette match or manual pick → week-plan slot via the existing `MovieNightLogic` path), prepare (snack roulette — seeded, silly, shareable), watch (a Live-Activity countdown → „Los!" phase reusing the Date-Night activity plumbing), and **afterwards: the rating ritual** — both rate 1–5 hearts + one-line review, reveal only when both rated (daily-question anti-spoiler semantics, server-enforced).
- **Unser Filmregal / Our Movie Shelf**: persistent history of watched movies with both ratings, poster-less procedural „spine" cards, filters (loved by both / vetoed / rewatch list), share-to-chat.
- **Custom decks**: couples build their own roulette decks (watchlist import by typing titles; streaming-provider chips as plain text labels — no third-party API dependency, honest and offline-friendly).

**(b) Bug fixes**
- `Features/Rituals/WeekplanView.swift` movie-suggestion banner: verify the 7-day `suggestionMaxAgeDays` window against dst/timezone edges (logic tests exist in `MovieNightLogicTests` — extend for week-crossing matches).
- Movie roulette deck exhaustion state (currently ends abruptly when both swipe through 60 titles with no match — add a designed „no match" ending with rematch/expand-deck options).

**(c) Polish** — match overlay celebration through the Delight engine at `.medium`; shelf cards get the glass-medal treatment; rating reveal is a two-card flip.

**(d) Assets** — none binary: procedural spine-card gradients seeded by title hash; snack roulette content pack (text, DE+EN, ~40 entries); +40 curated movie titles per language in `MovieRouletteData`.

**(e) DE+EN** — ~70 keys; movie titles remain language-specific curated lists (existing pattern); Handbuch chapter „Filmabend".

**(f) Acceptance**
- Server tests: rating reveal withheld until both rated (adversarial: partner cannot fetch other's rating early); shelf persistence + eviction cap.
- Logic tests: snack roulette determinism (same seed → same snack on both phones); deck-merge dedupe.
- Cockpit flow on Linux: two members complete plan → rate → reveal.
- Simulator screenshots: hub, shelf, rating reveal (DE + EN both captured).
- **Rubric:** hub/shelf/rating screens; R10 requires: match emits event → XP → shelf entry → What's-New mention → Handbuch section.

---

### v5 (4.5.0) — „Quests & Gemeinsame Momente" / "Daily Quests 2.0 & Shared Moments"

**(a) Features**
- **Quest auto-detection**: quests complete themselves from real app events where possible („Schickt euch heute ein Foto" auto-checks on photo upload) — server derives completion from validated events (extends the 4.0 authority work in `server/src/gamification.js`), manual check stays for real-world quests.
- **Quest chains & weekly arcs**: 7-day themed arcs (e.g. „Woche der kleinen Aufmerksamkeiten") with a final co-op reward ceremony; deterministic per couple+week (extends `DailyQuestsLogic`).
- **Shared Moments timeline**: one unified, filterable feed in the Wir tab merging photos, videos, canvas exports, milestones, capsule openings, big game wins, magazine issues — month headers, search, jump-to-date; entries deep-link to their source feature. (Foundation: the existing app-event log.)
- XCUITest smoke suite lands in CI (Lane B): launch → pair (stub server on runner) → dashboard renders → each tab opens.

**(b) Bug fixes**
- Duplicate `quest_done` idempotency: 4.0 hardened events server-side — add the missing *client* debounce and a server idempotency-key test per quest+day (EVAL P0 lineage).
- Moments/Events list: recurring yearly events around Feb-29 and timezone-shift boundaries (add SharedDates logic tests).

**(c) Polish** — timeline uses stable scroll anchoring (no jump when older pages load — the chat already solved this; reuse); quest cards celebrate via Delight `.small` only (no spam), arcs via `.epic` once.

**(d) Assets** — quest content pack expansion +30 quests, +4 weekly arcs (text DE+EN).

**(e) DE+EN** — ~80 keys (timeline filters, arc names, quest text); Handbuch chapters „Tagesquests", „Momente".

**(f) Acceptance**
- Server: auto-completion fires only from validated events (adversarial test: forged event rejected); arc reward exactly once.
- Logic: arc determinism (couple+week seeded), timeline merge ordering is total and stable.
- XCUITest smoke green in CI — this becomes a §3 gate from now on.
- **Rubric:** quest + timeline screens; R7 audited on the timeline with a 1,000-entry fixture.

---

### v6 (4.6.0) — „Mitteilungen & Haptik" / "Notifications & Haptics Done Right"

**(a) Features**
- **In-app notification center**: unified inbox (touches, needs, letters, quest/goal events, game turns) with read state, grouped by day — the app-open digest grows into a browsable center; badge counts unify across tabs.
- **Quiet hours & per-category reminders**: local-notification scheduling with couple-aware defaults (daily question, streak guard, capsule unlock day, week-plan slots, coupon expiry) all under one settings screen with per-category toggles + time pickers; everything honestly labeled „lokal — App muss regelmäßig geöffnet werden" where BGAppRefresh is the only refresher.
- **Haptik expansion**: 4 new synthesized patterns (presets), haptic „transcript" bubbles in chat (a received vibe renders its waveform), pattern preview in the notification-sound picker.

**(b) Bug fixes**
- `UI/SeasonEffectsView.swift`: **no Low-Power-Mode / scenePhase gating exists anywhere** (verified: zero `isLowPowerModeEnabled` hits in the codebase) — pause particles + 3D heart animation in Low Power Mode and when scene is inactive; add device-density tiers (EVAL P2).
- Notification-permission funnel: request at first meaningful moment (first streak at risk), not at launch; recover gracefully when denied (settings deep-link card).

**(c) Polish** — notification sounds rendered by the Sound Engine into cached files at first use (keeps the no-bundled-audio policy); all haptic intensities re-tuned against a documented mapping table (R3); Delight engine gets global rate-limiting.

**(d) Assets** — none binary in repo (sounds synthesized on device/build); waveform rendering is pure SwiftUI.

**(e) DE+EN** — ~60 keys (center, categories, quiet hours); Handbuch chapter „Mitteilungen & Haptik" including the honest push-limitations table.

**(f) Acceptance**
- Logic tests: scheduling math (quiet-hour clamping, next-fire-date across DST); haptic pattern → AHAP conversion for the 4 new presets.
- Server: digest categories complete (a need-only digest is non-empty — regression pin on the 4.0 fix).
- Simulator: notification center screenshots; Low-Power gate verified via simulator's low-power toggle where available, else via injected flag + unit test.
- Device checklist (optional): haptic feel pass for the 4 patterns.
- **Rubric:** R3 = 10 required on all touched surfaces this version.

---

### v7 (4.7.0) — „Widgets & Controls 3.0"

**(a) Features**
- **Complete the iOS-18 control family** (EVAL P2, verified still 2 controls in `Widgets/ControlWidgets.swift`): add „Denk an dich" toggle control and „Date-Night starten" control; Action-Button recipes documented in the Handbuch.
- **Polaroid filmstrip, honestly**: multi-photo filmstrip (last 3 favorites), date-stamp corner, „Passbildautomat" 4-frame strip — closing the gap where filmstrip framed one photo.
- **Widget freshness**: every widget shows a subtle staleness indicator when its snapshot is older than its natural cadence (R9 for widgets); StandBy night mode tuning (red-shifted palette).
- Widget-Studio presets: 3 curated looks per widget, one-tap apply.

**(b) Bug fixes**
- Widget deep-links audit (every widget/LA tap lands on the exact feature screen, including cold start — XCUITest coverage).
- App-Group snapshot version migration test (old snapshot blob + new fields → no widget crash; pin the 4.0 decode-tolerance).

**(c) Polish** — consistent padding/typography across all 8 widgets at all sizes (single `WidgetTheme` audit); lock-screen widgets re-hinted for vibrant rendering mode.

**(d) Assets** — none binary; filmstrip frames drawn in SwiftUI.

**(e) DE+EN** — ~35 keys (controls, presets, staleness labels); widget preview strings both languages (WText table).

**(f) Acceptance**
- Simulator: widget gallery screenshots (all widgets × sizes × DE/EN — scripted via `simctl`); controls visible on iOS 18 sim, absent on iOS 17 sim.
- Logic: filmstrip photo-selection determinism; staleness thresholds.
- Device checklist: widget re-sign behavior after sideload (App Groups) re-verified, documented in Handbuch.
- **Rubric:** all widget surfaces; R9 = 10 (staleness honesty).

---

### v8 (4.8.0) — „Aussprache & Rücksicht" / "Repair & Consideration" (the missing relationship depth)

The two unbuilt top-10 relationship ideas, built with the care they demand.

**(a) Features**
- **Aussprache-Modus (repair conversations)**: a guided, structured flow — each partner states feelings in timed, uninterrupted turns (mirror prompts: „Was ich gehört habe ist…"), cool-down timer option, ends with a small shared agreement note saved privately to both. Server enforces turn structure like a game (reuses the authoritative move relay); content pack of prompts written carefully in DE+EN. Explicitly framed as a tool, not therapy (R9 disclaimer).
- **Rücksicht-Radar (strictly opt-in)**: private cycle/pain/energy considerations a partner *chooses* to share as gentle hints („heute besonders lieb sein 💜") — E2E-encrypted at rest via the Vault crypto path, granular sharing levels, one-tap pause, no gamification/XP linkage whatsoever (deliberate R10 exception, documented).
- **„3 gute Dinge"** evening gratitude micro-ritual (backlog A-11): 3 one-liners each, reveal-when-both, feeds the monthly magazine.

**(b) Bug fixes**
- Magazine share/export (EVAL gap): monthly issue exportable as a rendered image set to chat/photos.
- Capsule countdown tick: verify the 4.0 unlock-time refresh also updates the *list* view badges live.

**(c) Polish** — Aussprache uses a deliberately calmer visual mode (reduced particles, muted palette, no celebration sounds); radar hints appear as soft dashboard whispers, never modals.

**(d) Assets** — prompt content packs (text): 30 Aussprache prompts, 20 radar hint templates, 25 gratitude prompts — all DE+EN.

**(e) DE+EN** — ~90 keys; tone review by a native-quality pass in both languages is mandatory here (sensitive copy). Handbuch chapter with explicit privacy explanation of the radar (what the server can/cannot see).

**(f) Acceptance**
- Server: turn-structure enforcement adversarial tests; radar payloads verifiably ciphertext-only on the server (test asserts no plaintext markers); pause/revoke immediately effective.
- Logic: prompt-pack integrity, gratitude reveal semantics.
- Cockpit: full Aussprache session between two members on Linux.
- **Rubric:** R9 = 10 with the added privacy-honesty checklist; R3 (calm mode) verified.

---

### v9 (4.9.0) — „Sprache & Zugänglichkeit" / "Localization & Accessibility Deep Pass"

**(a) Features**
- **Handbuch v1 complete** (DE+EN): every existing feature documented with per-chapter troubleshooting; in-app „?" buttons deep-link to Handbuch anchors (rendered in a sheet from bundled markdown).
- **Formatter sweep**: every date/number/duration through `Locale`-aware formatters (audit + logic tests for de_DE vs en_US rendering); relative-time strings unified.
- **Plural rules**: introduce a minimal plural-aware `L10n.t(count:)` (DE/EN both need one/other) and migrate the ~50 count-bearing strings.

**(b) Bug fixes**
- Whatever the audit finds — budgeted: DE truncation at Dynamic Type XL on dense screens (stats, game shells); VoiceOver order on the dashboard (grouped sections must read as groups); missing labels on icon-only buttons (sweep).

**(c) Polish** — full VoiceOver walkthrough of the 5 tabs recorded (simulator accessibility inspector logs archived in `verification/`); contrast fixes; keyboard-avoidance audit in all composers.

**(d) Assets** — Handbuch SVG diagrams (pairing flow, server setup, sideload flow).

**(e) DE+EN** — this *is* the version: full-table review pass; string freeze 48 h before tag; L10n parity tests extended to plural variants.

**(f) Acceptance**
- Zero hardcoded strings verified by extending the static scan to `Text("` literals allowlist.
- Dynamic-Type-XL screenshot suite (DE) with zero truncations on the 12 densest screens.
- Handbuch: every Features/ view file maps to a Handbuch anchor (checked by a doc-coverage script — a docs test, not app code).
- **Rubric:** R5/R6 = 10 app-wide (not just touched screens) — this version's whole point.

---

### v10 (5.0.0) — „Saisonkalender & Feste" / "Season Calendar & Celebrations"

The 5.0 headline: time-based delight, done with the existing determinism discipline.

**(a) Features**
- **Türchen-Kalender engine** (backlog B-33): generic countdown calendars — Advent, birthday week, anniversary week, „100 Tage bis…" — each door opens a small payload (prompt, mini-quest, letter slot a partner pre-filled, tiny game challenge). Server holds doors locked until their date (capsule semantics reused); either partner can author a calendar for the other.
- **Seasonal event frames** (B-34): Valentine's/Halloween/NYE limited-time frames — seasonal quests, one seasonal badge each, seasonal widget skins (C-21) auto-suggested, never auto-applied.
- **Jahrestags-Feuerwerk** (C-29): anniversary-day full celebration sequence + exclusive gold icon day (existing seasonal-icon plumbing).

**(b) Bug fixes**
- `SeasonLogic` hemisphere handling (southern-hemisphere couples get autumn in April — add a setting + logic tests).
- Widget seasonal-skin snapshot growth: cap and migrate App-Group storage.

**(c) Polish** — door-opening ceremony choreographed once, reused (FIFO-queued); calendar authoring flow gets templates so creating 24 doors is 5 minutes, not 30.

**(d) Assets** — none binary: seasonal particles/frames procedural; content packs for door payload templates (DE+EN, ~60 items); +1 icon variant (gold anniversary — `GenerateIcon.swift` variant, rendered in CI like the other 9).

**(e) DE+EN** — ~100 keys; calendar/eventframe names; Handbuch chapter with an authoring guide.

**(f) Acceptance**
- Server: door-lock adversarial tests (cannot open early, author cannot read recipient's opened-state notes, deletion rights); calendar CRUD.
- Logic: door date math across DST/timezones/leap years; hemisphere setting.
- Cockpit: author → recipient opens a door on Linux.
- Simulator screenshots: calendar, door ceremony, seasonal frame (DE+EN).
- **Rubric:** R2 (ceremony motion) and R10 (doors → events → XP → magazine) at 10.

---

### v11 (5.1.0) — „Spiele-Offensive II" / "Games Wave II"

Three new games chosen from the scored backlog for async-friendliness (the sideload reality's strongest class) and low asset weight.

**(a) Features**
- **Wortkette-Blitz** (B-5): async word-chain with server-validated chaining rules, daily rounds.
- **Galgenraten: Unser Wort** (B-6): hangman where the setter commits the word (commit-reveal — the fairness plumbing exists), lovely fail-forgiveness.
- **Paar-Bingo** (B-18): weekly 4×4 bingo of relationship micro-actions, auto-checked from real app events (reuses v5 quest-detection), bingo ceremony on both phones.
- **Game tutorials**: 3-step interactive intro per game (all 19 games get one, template-driven), plus a practice/solo mode where the reducer allows it.

**(b) Bug fixes**
- Cross-game audit items surfaced by the unified shell in v3 (turn-notification consistency, forfeit edge cases) — budgeted fix list.
- Emoji-riddle live mode reconnection mid-round (known fragile class; add adversarial server test).

**(c) Polish** — Play-hub information architecture regrouped (Daily / Live together / Async / Party) with the „Du bist dran!" row always on top.

**(d) Assets** — word lists: chain-dictionary DE/EN (validated packs), hangman word pack (DE+EN, ~200 each), bingo action pack (~60, DE+EN). All text, all schema-tested.

**(e) DE+EN** — ~120 keys (3 games + tutorials); GamesL10n split per game lands here if not done in v3.

**(f) Acceptance**
- Logic: full reducer test suites for all 3 new games (move validation, determinism, end conditions) — the Battleship/Kniffel test standard.
- Server: authority tests (registered types, payload normalization, no client-chosen seeds) for all 3; bingo auto-check only from validated events.
- Cockpit: complete an async round of each new game on Linux.
- **Rubric:** game screens; tutorial flow R4 (skippable, resumable) at 10.

---

### v12 (5.2.0) — „Leistung & Verlässlichkeit" / "Performance & Reliability"

A deliberately feature-light version; the couple should only notice that everything feels faster and nothing ever gets lost.

**(a) Features**
- **Offline-first widening**: the 4.0 chat outbox pattern extends to reactions, daily answers, quest checks, ratings (idempotent client IDs everywhere).
- **Server storage compaction**: JSON-store segmenting + startup compaction + media-folder quota reporting; `GET /api/health` gains storage stats; documented migration (data preserved — the update-path promise).
- **Startup budget**: cold-start instrumentation (os_signpost), warm-cache dashboard target < 2.5 s; lazy-load heavy tabs.

**(b) Bug fixes**
- WS reconnect storm hardening (backoff + jitter audit in `SocketClient`); gallery memory audit — apply thumbnail decoding downsampling to every remaining image path (video poster frames, magazine covers).
- Long-couple fixtures: run the whole server suite against a 2-year, 10k-message fixture; fix whatever paginates/aggregates poorly.

**(c) Polish** — perceptible-latency pass: optimistic UI for every sub-300 ms action; skeletons standardized; haptic-on-success only after server ack where truth matters (R9).

**(d) Assets** — none.

**(e) DE+EN** — ~15 keys (storage stats, health screens).

**(f) Acceptance**
- Load test script (Node, in `server/test/`): 2 couples × 10k events × parallel WS — p95 REST < 50 ms locally; documented.
- Outbox adversarial tests: kill-mid-flight for every widened type → exactly-once visible result.
- Simulator startup timing captured 5× in CI, median < 2.5 s (report archived).
- Compaction: fixture store shrinks and round-trips losslessly (byte-diff of logical content).
- **Rubric:** R7/R8 = 10 app-wide; regression screenshots prove no visual change.

---

### v13 (5.3.0) — „Eure Farben" / "Personalization & Delight"

**(a) Features**
- **Paar-Farbschema** (C-13): couple accent palette derived from both partners' chosen colors, applied across theme tokens (gradients, chat bubbles, widgets); presets + custom.
- **Kosenamen-System** (C-17): pet names used throughout copy (grammar-safe templating in both languages — L10n templating extended).
- **Monogramm & Wachssiegel** (C-18): procedural couple monogram used on letters, magazine covers, calendar doors.
- **Chat-Sende-Effekte** (C-30): 5 send effects (hearts burst, snow, sparkle trail…), sparingly rate-limited; **Sticker-Werkstatt** (C-22): procedural sticker shapes from canvas doodles (no ML subject-lift promises — honest scope).
- **Geheime Gesten** (C-28): 3 easter eggs (long-press heart 10 s, anniversary-date typed in chat, konami-swipe on About → credits animation featuring "made by Sonic0810").

**(b) Bug fixes** — theme-token audit fallout: any screen with hardcoded pink/purple gets migrated (R1 sweep finishes what v2 started).

**(c) Polish** — dark/light parity check for all custom palettes; contrast auto-guard (palette picker refuses combos < 4.5:1 — R6 by construction).

**(d) Assets** — none binary (monogram/stickers/effects all drawn); sticker shape pack is code.

**(e) DE+EN** — ~70 keys; Kosenamen templating rules documented per language (DE cases/gender handled by template forms, never string concatenation).

**(f) Acceptance**
- Logic: palette derivation determinism + contrast guard; monogram renderer snapshot (SVG-string comparison — Linux-testable).
- Simulator: same screen in 3 palettes × DE/EN screenshot matrix.
- Server: pet names/palette sync as couple profile fields with tests.
- **Rubric:** R1 = 10 app-wide (token audit complete), R5 templating = 10.

---

### v14 (5.4.0) — „Der große Feinschliff" / "The Great Polish Wave" (fix-only)

Nothing new. Every screen is audited against §4; this version exists so v15 can be an integration release, not a cleanup.

**(a) Features** — none (explicitly). The only "feature" is the **screenshot regression suite**: CI captures a canonical screenshot set (≈ 60 screens × DE/EN) every push, diffed against the v14 baseline going forward.

**(b) Bug fixes** — the entire remaining register: every open EVAL-3.0 P2 (controls scope was closed in v7, low-power in v6, replay in v3 — verify all), every rubric audit finding from v2–v13 that was deferred, the UserFeedback.md inbox (currently empty — re-read at execution time), plus a fresh independent-review pass in the EVAL-3.0 style over v4–v13 features.

**(c) Polish** — copywriting tone pass over all ~2,300+ L10n keys (consistency: du/ihr, Oxford-comma-free EN, emoji discipline); micro-animation timing normalization; empty/error/loading state inventory — a spreadsheet of every screen × state with a screenshot proving each exists.

**(d) Assets** — none.

**(e) DE+EN** — the tone pass *is* the work; string freeze after it.

**(f) Acceptance**
- The state-inventory has zero gaps (every screen × 5 states designed).
- Independent review (fresh-eyes agent or human, EVAL format) scores **≥ 8.0 in every category** — the same bar 3.0 failed.
- Screenshot suite baseline committed under `versions/v14-5.4.0/verification/`.
- Server + logic suites at their historical maximum, all green.
- **Rubric:** R1–R10 ≥ 8 for *every* screen in the app, recorded in one master `rubric.md`.

---

### v15 (6.0.0) — „Für euch zwei" / "For the Two of You" (release candidate)

**(a) Features**
- **Integration finale**: end-to-end wiring audit — every feature's events → XP/badges → widgets → magazine → year review → Handbuch → What's-New verified by a traceability matrix (R10 as a shipping document).
- **Umzugs-Assistent** (C-35): guided full-couple migration (old server → new server; new phone honesty about re-pairing) built on the encrypted `.sooodreamy` export.
- **Handbuch final** (DE+EN): full troubleshooting decision trees, sideload guide with per-tool walkthroughs (AltStore/SideStore/Sideloadly), server-hosting guide (Docker/Tailscale/HTTPS proxy), printable PDF build recipe (pandoc, documented — output placed in `versions/v15/`).
- **App-Store-readiness dossier** (dormant until signing exists): privacy nutrition labels content, encryption-export answers (`ITSAppUsesNonExemptEncryption` already false-declared — re-verify against Vault/E2E claims), review-notes draft, screenshot set — so a paid Apple account is the *only* missing ingredient.

**(b) Bug fixes** — RC bar: only regressions and P0/P1; two-week (calendar-free: two full verification cycles) freeze discipline — every fix re-runs the full Lane A+B pipeline.

**(c) Polish** — final About/credits ceremony (the easter-egg credits from v13 become the polished „Über uns" story: made by Sonic0810, built for the two of you).

**(d) Assets** — Handbuch PDF (generated, placed in `versions/`, not in source tree).

**(e) DE+EN** — freeze; only fixes.

**(f) Acceptance**
- Traceability matrix complete: no feature ships un-wired, un-documented, or un-discoverable.
- Full `versions/` archive audit: v01–v15 each contain IPA (or the documented recipe fallback with backfill note), SHA256SUMS, patchnotes, verification evidence.
- Migration assistant round-trip test (server A → export → server B → byte-equal logical content) in the server suite.
- Final independent eval ≥ 8.5 average, no category < 8.
- **Rubric:** full-app audit repeated post-freeze; R9 = 10 with the dossier's claims cross-checked against code.

---

## 6. Per-Version Verification Story (Mac-free summary)

| Step | Where | What | Blocking? |
|---|---|---|---|
| 1 | Linux | `npm test` (server), `swift test` (logic), `swiftc -parse`, oxlint/tsc if root site touched | Yes |
| 2 | Linux | Dev-Cockpit manual flow for the version's API-visible features (recorded transcript) | Yes (v2+) |
| 3 | macOS CI | Unsigned IPA build + package + checksum | Yes (recipe fallback allowed per §2.3) |
| 4 | macOS CI | Simulator boot + XCUITest smoke (v5+) + screenshot suite (DE/EN) | Yes |
| 5 | macOS CI | Screenshot diff vs baseline (v14+) | Yes |
| 6 | Real iPhone | Sideload checklist (haptics/widgets/LA/camera) | **No** — recorded honestly as device-verified yes/no |

The only human-Mac scenario in 15 versions: none. The only real-device scenarios are optional confidence checks whose absence is disclosed, never hidden.

## 7. Prioritized Idea Backlog (beyond the 15 versions / substitution pool)

Drawn from `SoooDreamy/docs/ideen/` (scored there) minus what the roadmap absorbs. Use as substitutions if a planned item stalls:

1. **Fortsetzungsgeschichte** (B-14) — async co-written story, pure relay, S effort.
2. **Insider-Wörterbuch** (A-32) — couple dictionary of inside jokes; feeds magazine.
3. **Fernbeziehungs-Dashboard** (A-13) — timezone-aware duo clock + visit countdown stages (A-26).
4. **Rezept-Box & Koch-Abende** (A-25/B-30) — recipe roulette cousin of Movie Night.
5. **Spotlight-Integration** (C-5) + **App Shortcuts 2.0** (C-4) — platform reach, no entitlements needed.
6. **Dynamic-Island „Herz-Pingpong"** (C-10) — delight, needs LA budget care.
7. **Foto-Schiebepuzzle-Duell** (B-20) / **Galerie-Quiz** (B-21) — reuse owned photos.
8. **Einschlaf-Herzschlag** (A-27) — haptic loop at bedtime; pairs with quiet hours (v6).
9. **Wochen-Retro zu zweit** (A-29) — lightweight weekly review ritual.
10. **Lock-Screen-Wallpaper-Generator** (C-24) — procedural, on-brand.
11. **Schach/Dame/Backgammon** (B-9/3/4) — classic async boards on the proven relay (bigger reducers, save for a Games Wave III).
12. **iPad-Zweitgerät-Layout** (C-11) — spectator mode already hints at it.

## 8. Most Important Current Bugs / Risks (file + why)

**Verified-open code issues (fix in the version noted):**
1. `.github/workflows/sooodreamy.yml` — branch filter omits the current working branch; pushes build nothing. Highest-leverage single fix in the plan (v1).
2. `SoooDreamy/ios/LogicTests/L10nTests.swift` — parity test omits `RitualsL10n`/`PlatformL10n`; a regression in ~320 keys would pass CI (v1).
3. `SoooDreamy/docs/API.md` vs `server/src/events.js` — documented names drift from code (`still_sealed`/`still_locked`, `goal_completed`/`goal_reached`, phantom `daymemo_streak`); no contract test pins them (v1).
4. `SoooDreamy/ios/SoooDreamy/Features/Games/ReplayView.swift` (+ `Content/ReplayLogic.swift`) — replay renders a localized move log, not reducer state; product copy overclaims „Partie als Film" (v3, R9).
5. `SoooDreamy/ios/SoooDreamy/UI/SeasonEffectsView.swift` — 20 Hz particle timeline with zero Low-Power-Mode or scenePhase gating anywhere in the codebase; battery drain + promised-but-missing gates (v6).
6. `SoooDreamy/ios/SoooDreamy/Features/Home/DashboardView.swift` — ~23 stacked cards in fixed order, no collapse/priority; discovery of new features for existing couples doesn't exist (`QuestCard` gates on new couples only) (v2).
7. `SoooDreamy/ios/Widgets/ControlWidgets.swift` — 2 of 3 specified iOS-18 controls (missing Thinking-of-you, Date-Night) (v7).
8. `SoooDreamy/ios/SoooDreamy/Features/Games/TournamentView.swift` — season derives from the last 100 relay sessions with `result.scores` only and excludes Wordle history; „über ALLE Spiele" is false (v3).
9. `SoooDreamy/ios/Widgets/PhotoWidget.swift` — „Filmstrip" frames a single photo; idea promised multi-photo/date-stamp (v7).

**Structural/process risks:**
10. **Two products, one repo** (root BAPBAP site vs `SoooDreamy/`): CI triggers, AGENTS.md instructions and branch conventions interleave; a site change can burn macOS minutes and vice versa. Mitigate with strict `paths:` filters (v1) — splitting repos is out of scope per constraints.
11. **No Swift toolchain on the Linux dev VM today** (`swift: command not found`) — the advertised Linux logic-test loop is currently broken *in this environment*; install per AGENTS.md is v1 step 0.
12. `SoooDreamy/server/src/store.js` — JSON-file storage with append-heavy growth (messages, events, media dirs); fine for a couple, but 15 versions of features multiply event volume — compaction/quotas are scheduled (v12), and until then media caps must be respected in every new feature.
13. **Push expectations** (`server/src/apns.js`, README §Push) — the honest `deliveryAvailable:false` gate is correct, but every notification-adjacent feature (v6, v10 calendars) must repeat the honesty in-context or user trust erodes (standing R9 requirement).
14. **IPA-in-git growth** — bounded (~90 MB over 15 versions) but monitored; Git-LFS escape hatch documented (§2.3).
15. **Free-Apple-ID sideload friction** (7-day expiry) — not fixable in-repo; the Handbuch must set expectations and recommend SideStore auto-refresh; a paid account remains the only cure (v15 dossier keeps that path ready).

## 9. Consolidated Asset List (all procedural/text — repo stays binary-free outside `versions/`)

| Asset | Version | Form |
|---|---|---|
| "made by Sonic0810" wordmark for Handbuch/About | v1 | Inline SVG / styled text |
| Handbuch diagrams (pairing, server, sideload) | v1/v9 | SVG or Mermaid |
| Dev Cockpit | v2 | Hand-written HTML/CSS/JS (no deps) |
| Snack-roulette pack (~40), +80 movie titles | v4 | Text, DE+EN |
| Quest packs +30, weekly arcs ×4 | v5 | Text, DE+EN |
| 4 haptic presets + notification sounds | v6 | Code (AHAP timelines, synthesized audio) |
| Filmstrip/passport widget frames | v7 | SwiftUI drawing |
| Aussprache (30), radar hints (20), gratitude (25) packs | v8 | Text, DE+EN, tone-reviewed |
| Calendar door templates (~60), seasonal frames | v10 | Text + procedural particles |
| Gold anniversary icon variant | v10 | `GenerateIcon.swift` variant (CI-rendered) |
| Word-chain dict, hangman (~200×2), bingo (~60) packs | v11 | Text, DE+EN, schema-tested |
| Sticker shape pack, send effects, monogram renderer | v13 | SwiftUI code |
| Screenshot regression baseline (~120 images) | v14 | Binary — quarantined in `versions/` |
| Handbuch PDF | v15 | Generated artifact in `versions/` |

## 10. Version Title Index

| # | Version | Title (DE / EN) |
|---|---|---|
| v1 | 4.1.0 | Fundament & Autorenschaft / Foundation & Authorship |
| v2 | 4.2.0 | Klarheit: Dashboard & Entdeckung / Clarity: Dashboard & Discovery |
| v3 | 4.3.0 | Ehrliche Spiele-Politur / Honest Game Polish |
| v4 | 4.4.0 | Filmabend 2.0 / Movie Night 2.0 |
| v5 | 4.5.0 | Quests & Gemeinsame Momente / Daily Quests 2.0 & Shared Moments |
| v6 | 4.6.0 | Mitteilungen & Haptik / Notifications & Haptics Done Right |
| v7 | 4.7.0 | Widgets & Controls 3.0 |
| v8 | 4.8.0 | Aussprache & Rücksicht / Repair & Consideration |
| v9 | 4.9.0 | Sprache & Zugänglichkeit / Localization & Accessibility |
| v10 | 5.0.0 | Saisonkalender & Feste / Season Calendar & Celebrations |
| v11 | 5.1.0 | Spiele-Offensive II / Games Wave II |
| v12 | 5.2.0 | Leistung & Verlässlichkeit / Performance & Reliability |
| v13 | 5.3.0 | Eure Farben / Personalization & Delight |
| v14 | 5.4.0 | Der große Feinschliff / The Great Polish Wave |
| v15 | 6.0.0 | Für euch zwei / For the Two of You (RC) |

---

*Plan written 2026-08-11. Analysis-only pass: no code, git state, or build artifacts were modified. SoooDreamy — made by Sonic0810.*
