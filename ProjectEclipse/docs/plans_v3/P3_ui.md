# P3 — UI/UX Suite Plan (plans_v3)

Planner P3 of 6. Scope: handbook rework, localization (en+de), sidebar v2, bossbar v3,
custom death screen + ship respawn flow, main menu v2 ("Reise beginnen"), day-timer UI,
skill-tree GUI, daily-awards roulette, custom loading screens, EMI gating, settings
consolidation, anti-clutter. Target: NeoForge 21.1.238 / MC 1.21.1 / Veil 4.3.0, mod id
`eclipse`, package `dev.projecteclipse.eclipse`.

Sibling planners: P2 (FX/shaders/assets), P4 (lives/skills/awards/analytics/timeline
engine), P5 (modpack/EMI bundling/dev commands/config distribution), P6 (limbo ship +
door). Interfaces in §5.

**Hard rules for every worker package (from the orchestrator):**

1. NEVER edit `admin/EclipseCommands.java`. New client commands get their own
   registration class. Server command surfaces are requested from P5 (§5.3).
2. NEVER edit `assets/eclipse/lang/en_us.json` / `de_de.json` directly. Every worker
   ships its keys as `docs/plans_v3/langdrop/P3_W<n>.json` in the format described in
   §7.4; the integrator merges them centrally. ALL new strings must exist in BOTH
   languages.
3. NEVER edit `EclipseMod.java`, `network/EclipsePayloads.java`,
   `client/EclipseGuiLayers.java`, `client/EclipseKeyMappings.java` or
   `client/ClientStateCache.java`. These are shared hubs. Instead each worker ships
   self-registering classes (`@EventBusSubscriber` on the mod bus for
   `RegisterPayloadHandlersEvent` / `RegisterGuiLayersEvent` / `RegisterKeyMappingsEvent`
   — multiple subscribers are legal and avoid all file conflicts) and keeps its own
   client cache class instead of adding fields to `ClientStateCache`. Anything that
   truly must land in a hub file is listed in the worker's **Integration ledger** and is
   applied by the integrator, exactly like the existing `EclipseMod.java` convention.
4. Respect the existing client-config framework: `EclipseClientConfig`
   (`ModConfigSpec`, type CLIENT). Only W3 edits that file; every new key + getter is
   frozen in §7.1 so other workers can code against the getters in parallel.
5. All animation honors `EclipseClientConfig.reducedFx()`. All new HUD layers honor
   `minecraft.options.hideGui` (F1). All new screens call `CursorManager.endFrame()`
   per frame and `CursorManager.reset()` in `removed()`.
6. Merge order: **wave 1** = W3 (config platform) + W4 (localization core). **wave 2** =
   everything else (parallel). **wave 3** = integrator applies ledgers + langdrop merge.
   Workers in wave 2 code against the frozen APIs in §7 and may stub-compile locally.

---

## 1. CURRENT-STATE AUDIT

### 1.1 What exists (read during audit)

| Area | Files | State |
|---|---|---|
| Handbook | `client/handbook/HandbookScreen.java` (+`tabs/` Status, Timeline, Rules, Rewards, Bestiary, Map; `EclipseWidget`, `UiSounds`, `CursorManager`, `GlitchText`) | Full-screen 90%x85% "book spread" with parchment textures, painterly hero art, mouse parallax (bg 8px / hero 4px), fold/shear page-turn, spine tab tongues, page dots, GLFW cursors. Opened via J (`ArtifactKeyHandler`) or artifact right-click (`S2COpenArtifactPayload` → `ArtifactScreenOpener`). |
| Artifact | `artifact/ArmArtifactItem.java`, `artifact/ArtifactSlotLock.java` | Pinned to **hotbar slot 8** by a 20-tick server sweep + toss-cancel + container-menu purge; `use()` (held right-click) asks the server to push fresh state + open payload. |
| HUD | `client/hud/SidebarPanel.java`, `BossbarSkin.java`, `AnnouncementOverlay.java`, `TypewriterLine.java`, `MarkVignetteOverlay.java`, `hearts/client/HeartBurstOverlay.java`, `client/WaveOverlay.java` | Sidebar: right-anchored 110px nine-slice panel (hearts/day/altar/**online count**/goal ticks), slide-in on content change. Bossbar: 3 themed frames (day/goal/boss), lerped fill, scroll overlay, edge-glow flash, NOTCHED_6 phase ticks, minimal-strip fallback. Announcements: typewriter + client-local sweep bar. Heart burst + low-heart pulse + hardcoded warden heartbeat at 1–2 lives. |
| Menu | `client/menu/EclipseTitleScreen.java`, `TitleScreenSwap.java`, `EclipseSettingsScreen.java`, `EclipseMenuButton.java`, `OptionsThemer.java`, `ClientMenuExtensions.java` | Custom title (slow panorama, 3 cloud layers, wisps, flare) with vanilla SP/MP/Options/Quit buttons + gear → `EclipseSettingsScreen` (7 boolean toggles). Swap via `ScreenEvent.Opening`. `IConfigScreenFactory` registered (Mods screen path). Options screen themed via events. |
| Config | `core/config/EclipseClientConfig.java` (7 booleans: customMenu, showBossbarSkin, showSidebar, uiSounds, customCursor, veilPostFx, reducedFx), `core/config/EclipseConfig.java` (server JSONs: `days.json` goals/title/subtitle as **single-language baked literals**) | Client TOML `eclipse-client.toml`. `EclipseSettingsScreen.write` resolves values via `SPEC.getValues().valueMap()` (flat, no sections). |
| Death/lives | `lives/LifecycleEvents.java`, `BanService.java`, `hearts/HeartsService.java`, `limbo/*` | Death → snapshot, -1 heart, grave, thunder cue, deferred heart-burst on respawn; 0 hearts → event-ban → adventure-mode ghost teleported to limbo ghost ship. **Death screen itself is vanilla.** |
| i18n | `assets/eclipse/lang/en_us.json` + `de_de.json` (245 lines each, full parity) | Announce/goal/etc. payloads carry translation keys (`S2CAnnouncePayload`), but `days.json` goals/titles/subtitles are baked server-side literals (English only), and there is at least one hardcoded English literal in client code (B14). |
| Locks | `progression/PhaseInventoryLock.java` (sweeps main-inv slots 9–35 to hotbar while `main_inventory` locked; exempts artifact only in armor/offhand loop), `progression/ModGate.java` + `UnlockState.java` (server-only namespace gating) | No client-side knowledge of unlock keys today (relevant for EMI). |
| Devtools | `devtools/client/GoalEditorScreen.java` | Day grid + up to 8 goal `EditBox`es (single language) + unlocks + legacy border field; saves `days.json` via `C2SConfigEditPayload`. |
| Tab list | `client/TabListHider.java` | TAB_LIST layer cancelled, SocialInteractions blocked → **the TAB key is currently free** for the sidebar-expand feature. |

### 1.2 Concrete bugs found (fix targets; each is assigned to a worker in §4)

- **B1 (CRITICAL, user-reported): settings unreachable with `customMenu=false`.**
  `EclipseSettingsScreen` is opened from exactly three places: the gear on
  `EclipseTitleScreen` (gone when the custom title is off), the Status-tab button inside
  the handbook (in-game only), and NeoForge's Mods screen (`ClientMenuExtensions`
  `IConfigScreenFactory` — obscure, and the Mods button is removed in modpack mode per
  R6). There is **no pause-menu entry and no vanilla-title gear**. Toggling
  `customMenu` off from the title screen leaves no discoverable way back. → W3.
- **B2: `book_spread.png` is stretched to an arbitrary percentage-derived rect**
  (90% x 85% of any window), so the art distorts at every aspect ratio ≠ its own; part
  of why the handbook "looks horrible". → W1 (rework removes stretched art entirely).
- **B3: handbook tab tongues hit-test vs. render transform mismatch.** `TabButton`s are
  `addWidget`-ed (raw screen-space input) but rendered inside the book unfold/scale
  pose (`renderTabTongues` under `pushPose/scale`), and the tongue additionally mutates
  its own X during render (`setX(restX - slide)`), so hitboxes lag the visuals by a
  frame and are offset during the unfold. → W1 (new rail is rendered untransformed).
- **B4: `StatusTab` settings button is a phantom widget.** Created in `onInit()` but
  never `addWidget`-ed: no keyboard focus, no narration, click routed manually AFTER
  `super.mouseClicked` (screen widgets win), and it plays the vanilla button "click"
  while the rest of the handbook uses `UiSounds` — inconsistent audio. → W1/W2 (new tab
  API exposes real widgets; unified sounds).
- **B5: `TimelineTab.onShown()` centers without the section gap.** The initial
  `scrollX` uses `currentIndex * NODE_SPACING` and ignores `SECTION_GAP`, so when the
  newest reached node is a milestone the view is off by 64px. Also `maxScroll()` adds
  `SECTION_GAP` even when no milestone entries exist (dead scroll zone). → W2.
- **B6: `StatusTab.tick()` only runs while Status is the active tab** (the screen ticks
  only `tabs.get(activeTab)`), so the altar level-up sting/pulse is silently missed if
  the level changes while another tab is open, then never fires (lastAltarLevel is
  re-seeded in `onShown`). → W1 (tick all tabs; tabs decide themselves what to do when
  hidden) / W2 (Status logic).
- **B7: `RewardsTab` scrolls with no scrollbar** while `RulesTab` draws one —
  inconsistent affordance; users don't discover the milestone list scrolls. → W2.
- **B8: handbook close key check uses `matches(keyCode, scanCode)` only** — if the user
  rebinds the menu key to a mouse button, the handbook can't be closed with it
  (`keyPressed` never sees mouse buttons). → W1 (also handle `mouseClicked` against
  `OPEN_MENU.matchesMouse`).
- **B9: hint line can collide with the book at small windows.** `renderHint` clamps to
  `height - 10`, which overlaps the page-dot row once the small-window fallback sets
  `bookH = height`. → W1 (rework drops the outer hint entirely; hints move inside the
  panel footer).
- **B10: sidebar shows an online-player-count row** (`sidebar.eclipse.online`) — the
  boss explicitly wants it gone (it also partially undermines the anonymity theme).
  `StatusTab` shows a second online count ("souls awake"). → W5 (sidebar), W2 (status
  page keeps or drops per R3 — drop, see §3.3).
- **B11: sidebar has no position/scale/overflow settings** — hardcoded right anchor,
  110px, ellipsis/2-line-wrap behavior; and the slide-in replays on every goal tick
  because the content hash includes `doneCount`. → W5.
- **B12: heartbeat loop is unconditional** (gated only by `reducedFx` and lives 1–2) —
  no user opt-out as demanded by R12 (`heartbeatSound`). `HeartBurstOverlay` also plays
  it via raw `SoundEvents.WARDEN_HEARTBEAT`, bypassing `UiSounds`' volume gate (correct
  per its javadoc — it is a gameplay warning — but it must respect the new dedicated
  toggle). → W3 (config key) + W5 (consume in overlay — file owned by W5? No:
  `HeartBurstOverlay` is owned by W7, see §4; the heartbeat gate moves with it).
- **B13: `EclipseSettingsScreen.write` resolves keys via the flat `valueMap()`** — this
  breaks the moment the config gains sections (journey block etc.). → W3 (settings v2
  uses typed accessors, not string reflection).
- **B14: hardcoded English literal in `AnnouncementOverlay.resolve`:**
  `Component.literal("Seal broken: " + …)` for unknown unlock keys — invisible to
  de_de. → W4 (new key `announce.eclipse.unlock.key.generic` with `%s`).
- **B15: `days.json` goals/title/subtitle are single-language baked strings** sent to
  every client verbatim (`S2CDayStatePayload`, `S2CGoalProgressPayload`), so German
  players read English goals. `GoalEditorScreen` edits only one language. → W4 + P4
  interface (§5.1) — dual-language schema.
- **B16: `PhaseInventoryLock.sweepMainInventory` clears slots 9–35 with NO artifact
  exemption** (only the armor/offhand loop exempts it). Today irrelevant (artifact
  lives in hotbar slot 8); FATAL for R1's slot-17 pinning on day 1 while
  `main_inventory` is locked — the two sweeps would fight at 1Hz. → W1 (exemption
  line; W1 owns this edit, listed in its ledger).
- **B17: grave captures the artifact on death.** `LifecycleEvents.onLivingDrops` copies
  ALL drops into the grave; the sweep then mints a fresh artifact, leaving a junk copy
  in the grave that gets purged only when a looter picks it up. → W1 (high-priority
  `LivingDropsEvent` filter in the artifact package strips artifact stacks before the
  grave forms).
- **B18: vanilla "click" plink leaks through themed UI** — `EclipseMenuButton` and the
  settings toggles inherit vanilla `playDownSound`; handbook tongues override it but
  buttons don't. Unify on `UiSounds`. → W1 (widget kit), W3 (settings widgets).
- **B19: `WaveOverlay` and cutscene letterbox render under F1 (intended); every OTHER
  overlay checks `hideGui` — verified OK** (SidebarPanel ✓, AnnouncementOverlay ✓,
  HeartBurstOverlay ✓, BossbarSkin ✓, MarkVignetteOverlay ✓). New layers must keep this
  invariant (checklist item in every worker's acceptance criteria). → all.
- **B20: `TimelineTab` mouse-wheel scroll and drag both dismiss the hint but a
  click-without-drag swallows the click silently** (returns true for any in-rect press)
  — harmless today, but the reworked tabs must only consume clicks they use. → W2.

---

## 2. GLOBAL DESIGN SYSTEM — "Quiet Eclipse"

The user verdict on the current handbook: *"looks horrible and tries too hard."* The v3
design system replaces painterly parchment + parallax + fold animations with a flat,
elegant, crisp panel language. **One panel, one accent, generous whitespace, tiny
purposeful motion.** All P3 screens (handbook, settings, death screen, skill tree,
roulette frame, loading screen text blocks) share it.

### 2.1 Palette (frozen constants — `EclipseUiTheme`, owned by W1)

| Token | Value | Use |
|---|---|---|
| `PANEL` | `0xF2120B1E` | Panel fill (95% near-black aubergine) |
| `PANEL_RAISED` | `0xF21A1128` | Cards/rows on top of PANEL |
| `HAIRLINE` | `0xFF2E2347` | 1px borders, dividers |
| `ACCENT` | `0xFFB98CFF` | THE purple. Active states, headers, progress |
| `ACCENT_DEEP` | `0xFF7B4FD0` | Pressed states, timer end-phase |
| `TEXT` | `0xFFEDE7F8` | Primary text |
| `DIM` | `0xFF9A8FB8` | Secondary text, captions |
| `GOOD` | `0xFF9AF0B0` | Done ticks |
| `DANGER` | `0xFFE86078` | Hearts lost, destructive |
| `VEIL` | `0xB8060310` | Full-screen backdrop dim behind panels |

Helpers frozen in `EclipseUiTheme`: `drawPanel(gui,x,y,w,h)` (fill + hairline + 1px
accent top edge), `drawHairline`, `drawHeader(gui,font,title,x,y,w)`, `ellipsize`,
`withAlpha`. No texture dependencies — the entire system renders from `fill`/`text`,
so it can never distort (fixes B2 class of problems). Decorative textures are allowed
only as OPT-IN drop-ins later (P2), never structural.

### 2.2 Typography & spacing

- Vanilla font only. Scale 1.0 for body, 2.0 max for the single hero number per page
  (day counter, level). Never 3x (current Status tab uses 3x — too loud).
- Baseline grid: 12px rows, 4px gaps, 12px panel padding, 16px section gaps.
- Headers: `ACCENT`, plain (no ✦ ornaments); subheaders `DIM`.
- All text ellipsized or wrapped through the frozen helpers — never scissor-chopped.

### 2.3 Motion & sound

- Open/close: 5-tick fade+4px rise of the panel (no unfold, no shear). `reducedFx` →
  instant.
- Tab switch: 4-tick crossfade + 6px horizontal slide of content only. Keep
  `UiSounds.pageTurn()` (it's liked) at 0.9 volume; tongue click keeps `UiSounds.tab()`.
- Hover: keep `EclipseWidget` glow + `UiSounds.hover()` blips (edge-triggered), glow
  reduced to 1px ring.
- Every interactive widget uses `UiSounds` (B18): `UiSounds.click()` (new, soft) on
  press. New sound events (W1 registers, P2 supplies OGGs; procedural fallback = reuse
  `ui.tab` pitched down): `ui.click`, `ui.toggle`, `ui.slider`, `ui.error_glitch`,
  `ui.roulette_tick`, `ui.roulette_win`, `ui.level_up`, `ui.skill_buy`, `ui.timer_zero`,
  `ui.door_open`, `ui.ghost_burst`. (Registered via a self-subscribing
  `client/EclipseUiSoundEvents`? No — sounds must be in the `EclipseSounds`
  DeferredRegister → **integration-ledger lines**, see W1 ledger.)

---

## 3. DESIGN PER REQUIREMENT

### 3.1 R1 — Handbook rework ("Das Logbuch" / simple, elegant)

**Layout** — one centered panel, `min(0.86*w, 560) x min(0.86*h, 320)` logical px,
clamped ≥ 96x72 content. Left icon rail (24px) inside the panel, header row, content
area, footer hint row. No page dots, no outer hint, no left "hero" page — content gets
the full width (the current split wastes half the screen on art).

```
┌──────────────────────────────────────────────────────────────┐
│▌☼│  STATUS                                    Tag 4  ❤❤❤♡♡  │  ← header: tab title left, glance right
│ ⌛│  ────────────────────────────────────────────────────────  │  ← hairline
│ §│                                                            │
│ ✚│   [ active tab content, full width ]                       │
│ ⛃│                                                            │
│ ✦│                                                            │
│ ◈│                                                            │
│ ⚙│  ────────────────────────────────────────────────────────  │
│  │  1–8 Seiten · J schließt                                   │  ← footer, DIM
└──────────────────────────────────────────────────────────────┘
```

- Rail: 8 tabs top-aligned, 16px icons, active = 2px accent bar on the left edge +
  icon tinted `ACCENT` + tooltip label; rendered OUTSIDE any animated transform
  (fixes B3). Tab order/ids: `status`, `timeline`, `rules`, `revival` (NEW),
  `rewards`, `bestiary`, `map`, `settings` (NEW). Number keys 1–8, ←/→/PgUp/PgDn
  cycle; tabs get first shot at `keyPressed` (frozen API §7.2) so future text fields
  aren't hijacked by the 1–8 hotkeys.
- All tabs re-skinned to Quiet Eclipse (W2): Status (day number 2x, heart row, altar
  ring → slim horizontal progress bar, goals with tick draw-in — draw-in kept, it's
  good), Timeline (same spine interaction, flat nodes, B5 fixes), Rules (flat panel,
  scrollbar), Rewards (rows + scrollbar, B7), Bestiary (flat cards), Map (kept —
  it's already vector-drawn; recolor + legend spacing).
- **Revival tab (NEW)**: renders the revive chain as real item icons with arrows:

```
  WIEDERBELEBUNG
  ──────────────
  ❤❤  ──(Herz-Extraktor)──▶  ▦▦▦▦        2 Herzen ▶ 4 Fragmente
  ▦▦▦▦ + Wiederbelebungs-Siegel  ──▶  Altar-Ritual
  Der Wiederbelebte erwacht mit ❤ 1 auf dem Schiff, die Tür öffnet sich.
```

  Item ids from P4 (§5.1); fallback to existing `eclipse:heart_fragment` +
  `eclipse:revive_sigil` icons until P4's extractor lands. Text fully key-driven.
- **Settings tab (NEW)**: embeds W3's `SettingsPanel` (§3.4) — ALL player-facing
  settings live there (single source of truth, also mounted in the standalone screen).
- **Open flow / slot 17**: the artifact moves from hotbar slot 8 to **inventory slot
  17** (`Inventory` main-storage index 17 = top row rightmost in the inventory GUI).
  - `ArtifactSlotLock.ARTIFACT_SLOT` 8 → 17; sweep/toss/purge logic unchanged
    otherwise (it already handles occupant relocation + dedupe + carried-stack guard).
  - `PhaseInventoryLock.sweepMainInventory` gets an artifact exemption for slot 17
    (B16) — while `main_inventory` is sealed the artifact is the ONE permitted
    storage-slot item (thematically: the artifact IS the seal).
  - **Right-click opens**: `ArmArtifactItem` overrides
    `overrideOtherStackedOnMe(stack, slot, action, player, access)` — with
    `ClickAction.SECONDARY` (any carried stack incl. empty, the bundle pattern):
    client side → close container + open `HandbookScreen` (deferred one tick via
    `minecraft.execute` so the container close packet goes out first) + send
    `C2SOpenArtifactPayload` for the refresh; returns `true` for BOTH click actions
    (`PRIMARY` too), which also makes the stack un-pickable by mouse = visual pinning
    with zero menu mixins. Held right-click (`use()`) keeps working as a fallback (the
    item can still end up in the hotbar transiently before the sweep).
  - Slot-17 lock affordance: a small padlock + accent frame drawn over slot 17 in
    `InventoryScreen` via `ContainerScreenEvent.Render.Foreground` (no mixin), and a
    tooltip line "Rechtsklick: Logbuch öffnen".
  - J keybind unchanged; grave exclusion per B17.

### 3.2 R2 — Localization system (en+de, `/lang` + `/sprache`)

**Principles**: keys + args over the wire wherever possible (already mostly true);
server-baked text (goals, roulette lines, editor-authored strings) carries BOTH
languages in config and the server picks per player; client override switches only
Eclipse-rendered strings, instantly, without touching the global game language.

**Client side — `client/lang/EclipseLang` (W4):**

- `locale()`: `langOverride` config (`"auto" | "en_us" | "de_de"`); `auto` resolves via
  `minecraft.options.languageCode` (startsWith "de" → de_de, else en_us).
- `tr(String key, Object... args) → Component` and `trString(...)`: when the effective
  locale equals the game language → plain `Component.translatable` (vanilla path,
  resource-pack friendly). Otherwise resolve from an internal table: at client init +
  on resource reload (`RegisterClientReloadListenersEvent`), parse
  `assets/*/lang/en_us.json` and `de_de.json` from ALL packs for keys starting with
  known Eclipse prefixes (`gui.eclipse.`, `announce.eclipse.`, `sidebar.eclipse.`,
  `message.eclipse.`, `bestiary.eclipse.`, `ritual.eclipse.`, `shop.eclipse.`,
  `commands.eclipse.`, `subtitles.eclipse.`, `key.eclipse.`, `item.eclipse.`,
  `block.eclipse.`, `entity.eclipse.`) into two maps; format with vanilla-%s semantics.
  Fallback chain: chosen-locale map → en_us map → global `Component.translatable`.
- `generation()`: int bumped on every override change or reload — HUD caches
  (sidebar rows, wrapped-line caches, handbook static text) include it in their cache
  keys → instant refresh without restarts.
- **Every P3 screen/HUD renders eclipse strings through `EclipseLang.tr`** (frozen API
  §7.2; mechanical adoption is part of each worker's outline).

**Commands — `client/lang/LangClientCommands` (W4, new class, game-bus
`RegisterClientCommandsEvent`):**

```
/lang            → shows current (auto/en/de) + usage
/lang en|de|auto → set override
/sprache …       → alias, German feedback
```

Execution: set+save `langOverride` → `EclipseLang.reload()` (bump generation) → if
`minecraft.screen` is an Eclipse screen, `screen.resize(minecraft, w, h)` (re-runs
`init()` with fresh strings) → send `C2SLocalePayload` → confirmation line (localized,
obviously).

**Server side — `lang/LangService` (W4):**

- `locale(ServerPlayer)`: explicit override (from `C2SLocalePayload`, kept in a
  session map + `eclipse:locale_override` attachment for persistence — attachment
  registered via ledger line in `EclipseAttachments`) → else
  `player.clientInformation().language()` (vanilla already syncs it) → normalized
  `"en"`/`"de"`.
- `pick(Localized text, ServerPlayer)` for baked strings.
- On `C2SLocalePayload` receipt: re-send the locale-sensitive payloads to that player
  (`EclipsePayloads.sendArtifactState(player,false)` + goal progress + timeline) so
  cached server-baked lines flip language instantly. (These senders are public today —
  no hub edit.)

**Dual-language config schema (`Localized`)** — owned by W4 as a shared record
`core/config/Localized.java` `{String en; String de; String pick(String locale)}`
(missing `de` falls back to `en`); `days.json` accepts both legacy strings and
`{"en":…,"de":…}` objects for `goals[]`, `title`, `subtitle`. The `EclipseConfig`
parser change itself is **P4-owned** (their engine file) — exact schema + parse rules
handed over in §5.1. `GoalEditorScreen` (W4 owns this file) gains an EN and a DE
`EditBox` per goal + per title/subtitle and writes the object form.

**Literal audit (W4 fixes, all files it owns):** B14 generic unlock line; sweep all
`Component.literal` uses in client UI code for words (audit list: `AnnouncementOverlay`
"Seal broken", `RewardsTab` raw-key fallback is acceptable (identifier), `SidebarPanel`
"❤ N" acceptable (symbol+number), `StatusTab` "+N"/"x/y" acceptable). New keys:
`announce.eclipse.unlock.key.generic` = "Seal broken: %s" / "Siegel gebrochen: %s".

### 3.3 R3 — Sidebar/scoreboard v2

- **Remove the online row** (B10) — and remove the matching "souls awake" line from the
  Status tab (consistency; anonymity).
- Settings (all in §7.1): `sidebarSide` LEFT/RIGHT, `sidebarScale` 0.6–1.4,
  `showSidebar` on/off (exists), `sidebarOverflow` ELLIPSIS/MARQUEE.
- MARQUEE mode: single-line rows; rows wider than the panel scroll horizontally
  (24px/s, 1.5s end-pauses, scissored, phase-offset per row so they don't sync);
  ELLIPSIS mode = current behavior minus the 2-line goal wrap (single line + "…").
  Marquee is wall-clock driven — does NOT re-trigger the slide-in (decouple the slide
  hash from tick states, B11).
- Rendering scaled via pose scale around the anchored edge; LEFT mode mirrors anchor +
  slide direction.
- **TAB-hold expansion**: while `minecraft.options.keyPlayerList.isDown()` (TAB is free
  — B-audit `TabListHider`) and no screen is open, the panel animates (8 ticks,
  ease-out cubic; `reducedFx` snaps) from its edge anchor to a centered 220px-wide
  detail card with MORE content: full un-truncated goal lines, day + timer mirror
  (from W6 cache), hearts, altar level + next milestone cost summary, skill level + XP
  (from W9 cache), border radius/world stage. Release → animate back. While expanded,
  the vanilla scoreboard stays suppressed; the marquee pauses (everything fits).

```
 edge (normal)                     TAB held (expanded, centered)
┌───────────┐              ┌──────────────────────────────────┐
│ ❤ 3   Tag 4│              │            TAG 4 · 02:14:09      │
│ ⛏ Altar 2  │              │  ❤❤❤♡♡      Altar 2 → 3 (◆ 8/12) │
│ Ziele 1/3  │     ⇒        │  ── Heutige Ziele ──────────────  │
│ ☑ Goal A…  │              │  ☑ Goal A (full text, wrapped)   │
│ ☐ Goal B…  │              │  ☐ Goal B (full text)            │
│ ☐ Goal C…  │              │  ☐ Goal C (full text)            │
└───────────┘              │  ── Du ─────────────────────────  │
                           │  Level 7 · 340/500 XP · Stufe 12  │
                           └──────────────────────────────────┘
```

- Polish: 1px hairline + accent top edge (drop the nine-slice texture), row icons kept,
  done-goal rows get a short 6-tick green tick sweep when they flip (reuse draw-in).

### 3.4 R12/B1 — Settings platform (consolidated, reachable everywhere)

**`SettingsPanel`** (W3): a self-contained widget composite (not a Screen) rendering
sectioned settings with themed toggle/slider/enum-cycle/keybind-hint widgets. Sections
and rows (every row = config key from §7.1):

```
ANZEIGE      : customTitle · sidebar an/aus · Seite L/R · Größe ──○── · Überlauf [Ellipse|Lauftext]
               bossbar skin an/aus · Stil [Ornat|Schlicht] · timer an/aus · eigene Ladebildschirme
EFFEKTE      : reducedFx · veilPostFx · custom cursor · Level-Up-Feiern
AUDIO        : UI-Sounds an/aus · UI-Lautstärke ──○── · Herzschlag-Sound
BENACHRICHT. : Skill-Prozzen im Chat · (Roulette nicht abschaltbar — Event-Moment)
SPRACHE      : [Auto|English|Deutsch]  (= /lang)
SERVER       : Server-Renderdistanz erlauben (Opt-out)
```

Mount points (all W3): 1) handbook Settings tab (thin `SettingsTab extends
HandbookTab` wrapper); 2) `EclipseSettingsScreen` v2 (panel + Done, keeps
`IConfigScreenFactory` path); 3) **pause menu**: `ScreenEvent.Init.Post` on
`PauseScreen` injects an `EclipseMenuButton` ("Eclipse…", 98x20) directly under the
vanilla Options button (shift the lower vanilla buttons is NOT allowed — instead place
it in the free column right of "Options…" mirroring "Open to LAN"-slot geometry; if
occupied, place below the button grid); 4) **vanilla title screen**: when
`customMenu=false`, `ScreenEvent.Init.Post` on `TitleScreen` injects a 20x20 gear
bottom-right (`gui.eclipse.settings.open` tooltip) → `EclipseSettingsScreen`. Fixes B1
twice over. Writes go through typed `ModConfigSpec` accessors (B13), `.save()` on
flip, all live-read consumers pick changes up next frame (existing pattern).

### 3.5 R4 — Bossbar v3

Keep the surgical `CustomizeGuiOverlayEvent.BossEventProgress` approach (W6 owns
`BossbarSkin.java`). Juice upgrades, all `reducedFx`-gated and working for all 3
themes + both `bossbarStyle` variants (ORNATE = full frame, SLIM = frameless rounded
strip; `showBossbarSkin=false` keeps the minimal strip):

- **Entrance/exit**: first sighting of a bar UUID → 8-tick drop-in (y -6→0, alpha
  0→1, fill wipes L→R); `BarState` tracked bars that stop rendering → 6-tick fade-out
  ghost (state machine keyed on `lastSeenMillis`, drawn from a `RenderGuiEvent.Post`
  pass for bars no longer event-driven).
- **Animated fill**: replace single tinted `fill.png` with a 4-frame animated fill
  sheet (`fill_anim.png`, 512x128, 8 ticks/frame) + the existing scroll overlay on
  top; P2 asset (procedural fallback: current fill + second scroll layer at 0.5x
  speed, additive).
- **Edge glow**: existing leading-edge glow kept + a 1px outer frame glow that
  breathes (sin, 3s) while a `boss`-theme bar is on screen.
- **Damage flash**: progress DROP > 0.5% → fill flashes white 3 ticks + 2px shake of
  the frame (progress RISE keeps the current soft glow flash). Already-lerped display
  keeps the sweep smooth.
- **Phase ticks**: generalize NOTCHED_6/10/12/20 → tick marks at each notch fraction
  (currently only NOTCHED_6 hardcoded at thirds).
- Name line: keep, but move into the frame band (drawn 1px inside the top edge, DIM →
  TEXT on change) so stacked bars read tighter.

### 3.6 R7 — Day-timer UI

New HUD layer `client/hud/DayTimerLayer` (W6), registered above `BOSS_OVERLAY` (below
announcements), top-center under the bossbar stack (`BossbarSkin.nextFreeBarY()`
aware). Data: `S2CDayTimerPayload` (§7.3) from P4's real-world-day engine — client
never computes the deadline itself, only renders `targetEpochMillis - now` with a
±drift correction from `serverNowMillis`.

- Rendering: `HH:MM:SS` (or `DD:HH:MM` above 48h) in 1.5x digits, color lerps
  `TEXT → ACCENT → ACCENT_DEEP` over the final configurable window (server sends
  `warnMillis`; default last 60 min), plus a thin progress underline (day fraction).
- Final 10s: digits pulse-scale 1.0→1.12 per second; at 00:00:00 → 3 blinks
  (alpha 1/0.2) + `ui.timer_zero` sting; then holds "00:00:00" DIM until the server
  flips the day (the expansion sequence is server-driven; the timer must NOT trigger
  anything itself).
- **Spool animation**: on payload with `spool=true` (dev `/eclipse timer add …`, P5
  surface), displayed time eases to the new remaining time over
  `clamp(|delta|·0.02, 0.4s, 1.5s)` with per-digit odometer roll (each digit column
  slides vertically); `reducedFx` snaps.
- `showDayTimer` config on/off; hidden under F1; hidden while a cutscene letterbox is
  active (not letterbox-whitelisted, consistent with sidebar).

### 3.7 R5 — Death screen, ghost state, ship respawn flow

**Screen-flow (client states; `client/death/DeathFlowController` state machine, W7):**

```
            LivingDeath (server, P4/existing)
                     │  S2CDeathStatePayload {heartsRemaining, ghost, lostHeartIndex, causeKey, holdTicks}
                     ▼
   vanilla DeathScreen opening ──ScreenEvent.Opening──▶ EclipseDeathScreen (swap, TitleScreenSwap pattern)
                     │
        ┌────────────┴─────────────┐
        │ heartsRemaining ≥ 1      │ ghost (== 0)
        ▼                          ▼
   [DEATH_NORMAL]             [DEATH_GHOST]
   veil + heart row           veil + LAST heart shatters big,
   (lost one shatters),       ghost-hearts row fades in,
   flavor line (causeKey),    flavor: "Die Tür bleibt zu …",
   button "Erwachen"          button "Als Geist erwachen"
   enabled after holdTicks    enabled after holdTicks
        │ click → C2SRespawnReadyPayload → server respawns player (vanilla respawn;
        │          respawn anchor = limbo ship berth, P6-owned placement)
        ▼
   [SHIP_WAKE]  (in world, on the ship)
   existing S2CHeartBurstPayload plays the hotbar heart burst (already wired on respawn)
        │                          │ ghost
        ▼                          ▼
   S2CShipDoorPayload{OPENING}  door stays CLOSED; GhostHudController active:
   → walk through door plane    vanilla PLAYER_HEALTH cancelled, 5 translucent
   (P6 teleports to real         cracked ghost hearts drawn, DIM "GEIST" tag,
   respawn point)                waits …
        ▼                          │ P4 revive → S2CRevivedPayload{heartsRestored}
   [RETURNED] normal HUD          ▼
                              ghost hearts BURST upward above the hotbar
                              (particle-ish 12-tick anim + ui.ghost_burst),
                              real heart row returns, S2CShipDoorPayload{OPENING},
                              door light floods (P2/P6), walk through → [RETURNED]
```

**`EclipseDeathScreen` design** (no vanilla score/title):

```
┌──────────────────────────────────────────────┐
│                (world, dimmed VEIL,           │
│                 slow purple pulse)            │
│                                               │
│                DU BIST GEFALLEN               │  ← ACCENT, 2x
│         »von den Wellen verschlungen«         │  ← causeKey flavor, DIM
│                                               │
│              ❤ ❤ 💔 ♡ ♡                       │  ← remaining hearts; lost one plays
│           Verbleibende Herzen: 2              │     the 12-tick shatter (reuse sheet)
│                                               │
│            ┌───────────────────┐              │
│            │     ERWACHEN      │              │  ← EclipseMenuButton, disabled+
│            └───────────────────┘              │     countdown ring for holdTicks
│      Du erwachst auf dem Schiff der Toten     │
└──────────────────────────────────────────────┘
```

- ESC does nothing (like vanilla death screen w/o quit? vanilla allows title-menu exit
  — keep a small DIM "Hauptmenü" bottom-left for parity/safety).
- Swap guard: only swap exact `net.minecraft.client.gui.screens.DeathScreen`; respect
  `customDeathScreen` config killswitch; if `S2CDeathStatePayload` never arrived
  (vanilla server / desync) render from `ClientStateCache.lives` fallback; NEVER block
  respawn — a 15s failsafe enables the button regardless.
- Ghost HUD (`GhostHudController` + `GhostHeartsLayer`, W7): active while
  `lives <= 0` && banned-dim (limbo); cancels `VanillaGuiLayers.PLAYER_HEALTH` via
  `RenderGuiLayerEvent.Pre` (SidebarPanel precedent); F1-safe; heartbeat sound
  suppressed for ghosts (already the case — keep; B12 toggle also consumed here).
- Server pieces P3 owns: none beyond payload handlers — respawn-anchor-at-ship and
  door mechanics are P4/P6 (§5.1/§5.4). W7 registers the payloads + client handlers
  and hands P4/P6 the exact send-points list.

### 3.8 R6 — Main menu v2 ("Reise beginnen")

W8 owns `EclipseTitleScreen` + a new `client/menu/JourneyController`.

- **Config**: separate file `eclipse-journey.toml` (own `ModConfigSpec`, registered
  `Type.CLIENT` with explicit filename — ships with the modpack, P5 distributes;
  §7.1b): `serverHost`, `serverPort`, `activationIso` (ISO-8601 with zone, e.g.
  `2026-08-01T18:00:00+02:00`), `modpackMode`, `devUnlock`.
- **Button layout (modpack mode)**: `REISE BEGINNEN` (primary, 200x20, accent pulse
  1.5s), under it `Optionen…` + gear, `Beenden`. Singleplayer/Multiplayer/Realms/Mods
  hidden when `modpackMode=true` — reappear when `devUnlock=true` OR the cached
  op-flag is set: server sends `S2COpStatusPayload{opLevel}` on login; client persists
  `opLevel>=2` to `config/eclipse-journey-state.json` (plain json, written by
  `JourneyController`) since the title screen renders pre-connection.
- **Before activation instant**: clicking fires the **glitch error theater** —
  sequence of 2–3 fake modal error panels (Quiet Eclipse panels with `GlitchText`
  titles + `ui.error_glitch`), e.g. `FEHLER 0xECL1PSE — Verbindung verweigert: Die
  Sonne ist noch wach.` then a shaking button + a DIM countdown line `Öffnet in
  3T 14h 02m` (localized). Pure client theater; button re-arms. `reducedFx` → plain
  disabled tooltip.
- **After activation**: `ConnectScreen.startConnecting(parent, minecraft,
  ServerAddress.parseString(host+":"+port), new ServerData(name, addr,
  ServerData.Type.OTHER), false, null)` (1.21.1 signature — the trailing param is the
  `TransferState`, null for a fresh connect; verify against mappings at impl time).
  Failures land on vanilla DisconnectedScreen whose "back" returns to the title —
  acceptable.
- **customMenu=false path**: W3's vanilla-title gear (§3.4) + pause entry make
  settings reachable; `JourneyController` does NOT inject "Reise beginnen" into the
  vanilla title (modpack ships customMenu=true; vanilla title is the escape hatch).
- Clock source risk (§6): activation uses LOCAL clock — document that the modpack
  gate is soft (server whitelist/P5 is the hard gate).

### 3.9 R8 — Skill tree GUI + XP HUD (P4 backend)

W9 owns `client/skills/**`. Data contract §7.3 (`S2CSkillTreePayload`,
`S2CXpPayload`, `C2SSkillPurchasePayload`, `S2CSkillResultPayload`,
`S2CProcMessagePayload`). Server truth; client never predicts purchases (buttons lock
while a purchase is in flight; `S2CSkillResultPayload` resolves).

**SkillTreeScreen** (reachable: inventory button via `ScreenEvent.Init.Post` on
`InventoryScreen` — small artifact-iconed `EclipseMenuButton` next to the recipe-book
button, repositioned on recipe-book toggle; handbook Status tab link; keybind K via
self-registering `SkillKeyMappings`):

```
┌────────────────────────────────────────────────────────────┐
│  FÄHIGKEITEN            Level 7 ── 340/500 XP ── ◇ 2 Punkte │
│ ───────────────────────────────────────────────────────────│
│        (pannable/zoomable canvas, drag = grab cursor)      │
│                       ┌──┐                                 │
│              ┌──┐  ═══│⛏ │═══  ┌──┐        ═ owned (accent  │
│      ┌──┐ ═══│⚔ │     └──┘     │🌾│          glow line)     │
│      │◈ │    └──┘    ╌╌╌┌──┐   └──┘        ╌ available     │
│      └──┘            ╌╌╌│🏹│               (dim pulse)      │
│      root               └──┘   🔒          🔒 locked (dark, │
│                                              silhouette)    │
│ ───────────────────────────────────────────────────────────│
│  ⛏ Doppelter Abbau I — 25% Chance auf doppelte Drops.      │
│  Kosten: ◇ 1        [ KAUFEN ]                             │
└────────────────────────────────────────────────────────────┘
```

- Nodes: 24px item-icon tiles (`iconItem` id), states LOCKED (dark + 🔒), AVAILABLE
  (hairline + slow 2s pulse), OWNED (accent fill + glow). Connections: 2px lines,
  owned = accent, else hairline; lines draw-in animate 6 ticks when a node unlocks.
- **Purchase animation**: on success — node flashes white 2t, glow ring expands 8t,
  connected lines re-draw-in, `ui.skill_buy`; cheap screen-space sparks (no Veil dep;
  P2 may upgrade via `eclipse:skill_burst` Quasar hook, optional).
- **Level-up celebration (client-local, `levelUpCelebrations` config)**: on
  `S2CXpPayload.level` increase while in-world: hotbar-area burst — "LEVEL 8" rises
  above the XP bar (16t), gold/purple spark fan, `ui.level_up`; NEVER a screen, never
  blocks input; suppressed in cutscenes + F1.
- **`CustomXpBarLayer`**: slim 2px bar 2px above the vanilla XP bar (custom XP is a
  separate track; vanilla bar untouched — P4 confirms placement §5.1), accent fill
  with 6-tick eased fill-on-gain + leading spark; level numeral right-aligned above,
  always visible (config `showCustomXpBar`); F1-safe; hidden when HUD hidden/cutscene.
- **Proc chat lines**: server sends `S2CProcMessagePayload{msgKey,argsJson,category}`;
  client renders to chat via `EclipseLang.tr(msgKey,…)` + appends
  ` [aus]`/`[off]` suffix styled DIM with `ClickEvent.RUN_COMMAND
  "/eclipse-ui procs off"` (client command, W9's `SkillClientCommands`; RUN_COMMAND
  executes client commands under NeoForge; fallback risk §6 → SUGGEST_COMMAND).
  `procMessages=false` (or category-muted) drops them client-side before chat.

### 3.10 R9 — Daily-awards roulette (P4 analytics/winner logic)

W10 owns `client/awards/**`. Payload `S2CAwardsPayload` (§7.3) carries up to 3 reveals
(server pre-picks winners; all strings server-localized per recipient via
LangService). Overlay (NOT a Screen — a `registerAboveAll` layer so gameplay continues
behind a dim veil; input NOT captured; ESC not needed; auto-plays):

```
   phase/reveal (≈7s each, 3 sequential):
   ────────────────────────────────────────────
   │            TAGES-EHRUNGEN · TAG 4         │
   │   »Meiste Schafe getötet«                 │  category line
   │                                           │
   │   ◇ ◇ ▣ ▣ [▣] ▣ ▣ ◇ ◇                     │  head strip: 24px player heads
   │        ─────┬─────                        │  scrolling, ease-out over 4s,
   │             ▼ (accent frame + glow)       │  ui.roulette_tick per head pass
   │                                           │  (pitch falls as it slows)
   │        ⟨Spielername⟩                      │  winner name (server-provided,
   │   hat gestern am meisten Schafe           │  anonymity-safe)
   │   getötet (26)                            │  statLine
   │   belohnt mit ✦ 3 Umbral-Splittern        │  rewardLine + purple glitch
   │                                           │  flourish (P2 asset eclipse:award_glitch)
   ────────────────────────────────────────────
```

- Heads: `PlayerFaceRenderer` from connection player-info skin when available, else
  default skin from UUID (anonymity suite may strip skins — server decides which
  UUIDs/names to expose; the payload's `displayName` is authoritative, §5.1).
- Timing: strip spins 4s (60→4 heads/s, ease-out quart), lands on `winnerIndex`,
  0.5s hold, `ui.roulette_win` + glitch flourish, text typewriters in (reuse
  `TypewriterLine` pattern, not the class), 2s hold, crossfade to next category.
  Skippable per-reveal fast-forward on sneak key (accessibility); `reducedFx` →
  no spin, direct reveal cards.
- Queueing: if another overlay/cutscene is active, hold in a queue (cap 3 payloads);
  F1 hides; pause freezes.

### 3.11 R10 — Custom loading screens

W11 owns `client/loading/**`. Swap via `ScreenEvent.Opening` (NO mixins needed —
`TitleScreenSwap` precedent): exact-class match on `ReceivingLevelScreen` (world join
+ every dimension change) and `LevelLoadingScreen` (SP spawn-chunk load) →
`EclipseLoadingScreen`.

- **Safety first**: `EclipseLoadingScreen extends ReceivingLevelScreen` is NOT
  possible cleanly (private `levelReceived` supplier) → replicate: our screen wraps
  the ORIGINAL screen instance as a hidden delegate, forwards `tick()` (vanilla close
  logic lives there and calls `minecraft.setScreen` itself), never forwards `render`.
  Belt+braces: our own hard failsafe — if the delegate hasn't closed us after 60s,
  `onClose()`. Killswitch `customLoadingScreens=false`. If ANY other mod already
  replaced the screen (class != exact vanilla), do nothing.
- Visuals: VEIL background, slow-breathing eclipse ring (code-drawn arcs + P2 optional
  art `textures/gui/loading/ring.png`), rotating flavor lines
  (`gui.eclipse.loading.tip.N`, localized), subtle progress shimmer. No fake progress
  bars (we don't know progress).
- **Portal glitch transition** (xbox-event portal): `S2CPortalFxPayload` (§7.3, sent
  by P6/P2's portal server code just before the teleport): client
  `PortalTransitionController` renders (above all) glitch overlay 10t (P2 shader via
  `VeilPostController` id `eclipse:portal_glitch`, fallback = `GlitchText`-style
  screen-space rectangles) → fade-to-black 5t → the dimension-change
  `EclipseLoadingScreen` shows pure black variant → fade-in-from-black 15t after
  level receipt. Controller is defensive: any missed phase times out (90s cap) and
  never blocks input longer than the loading screen itself.

### 3.12 R11 — EMI gating

W11 (same worker as loading — both are "swap/hide vanilla surfaces safely" plumbing).

- Client unlock knowledge: `S2CUnlockedKeysPayload{keys[], lockedNamespaces[]}`
  broadcast on login + every unlock change (server sender: small
  `progression/UnlockSync.java` hooking the existing unlock recompute — W11 owns it;
  P4 notified §5.1 since they touch `UnlockState`). Cached in
  `client/progression/ClientUnlockCache` (own class, not `ClientStateCache`).
- `client/emi/EclipseEmiPlugin` (`@EmiEntrypoint`, EMI API compileOnly dep — W11 adds
  `dev.emi:emi-neoforge:1.1.22+1.21.1:api` compileOnly + localRuntime to
  `build.gradle`, its ledger): `register(EmiRegistry)` calls
  `registry.removeEmiStacks(pred)` with a predicate that consults
  `ClientUnlockCache.isNamespaceLocked(ns)` LIVE (predicates are stored as
  invalidators and re-evaluated on each EMI reload) + always-hidden set = item tag
  `#eclipse:emi_hidden` (new data file; seed with `eclipse:grave` + dev/admin items;
  P4/P5 extend). Recipes: EMI's default invalidator removes recipes whose
  inputs/outputs are hidden → recipe viewer only shows unlocked content for free;
  additionally `registry.removeRecipes` by namespace for belt+braces.
- **Runtime re-index**: EMI has NO official live-hide API (verified: emi#494, open
  emi#1207). On unlock-payload diff → trigger an EMI reload via
  `dev.emi.emi.runtime.EmiReloadManager.reload()` through reflection, guarded
  (only when EMI loaded, try/catch, log-once). Reload is async on EMI's worker
  thread (~1–3s) — acceptable at day-change cadence. Fallbacks §6.
- Guard everything behind `ModList.get().isLoaded("emi")`; zero hard dependency.

### 3.13 R13 — Anti-clutter verification

Existing layers verified (B19). Every new layer/overlay ships with: `hideGui` check,
cutscene-letterbox suppression (default: NOT whitelisted), pause-freeze behavior, and
a line item in its worker's acceptance criteria. Screens (death, skill tree, handbook)
are exempt from F1 by definition; the roulette overlay + timer + XP bar + ghost hearts
all hide under F1.

---

## 4. WORKER PACKAGES

11 packages. **File ownership is exclusive** — no two workers touch the same file.
"Ledger" = integration lines applied centrally at merge (hub files, lang, sounds
registry, gradle). Every worker: (a) drops
`docs/plans_v3/langdrop/P3_W<n>.json` with ALL its new keys in en+de; (b) never edits
lang JSONs / `EclipseCommands.java` / hub files; (c) adds `hideGui` + `reducedFx` +
cursor-lifecycle compliance where applicable; (d) uses `EclipseLang.tr` for
user-facing strings and `EclipseUiTheme` for colors.

---

### P3-W1 — Handbook frame v3 + widget kit + slot-17 artifact (L, FABLE)

**Goal**: replace the book-spread frame with the Quiet Eclipse panel + icon rail;
freeze the tab API; unify widget sounds; move the artifact to inventory slot 17 with
right-click-to-open + pinning.

**Files owned**:
- `client/handbook/HandbookScreen.java` (rewrite: panel layout, rail, header glance,
  footer, crossfade tab switch, tick-all-tabs (B6), key/mouse close parity (B8),
  tab-first `keyPressed` routing, widget add/remove on tab switch (B4))
- `client/handbook/EclipseUiTheme.java` (NEW — §2.1 constants + helpers)
- `client/handbook/EclipseWidget.java` (glow → 1px ring; `UiSounds.click()` default
  press sound)
- `client/handbook/UiSounds.java` (add `click/toggle/slider/error/levelUp/skillBuy/
  rouletteTick/rouletteWin/timerZero/ghostBurst` helpers, all `uiSounds`-gated and
  scaled by `uiSoundVolume` — getter from §7.1)
- `client/handbook/HandbookTab.java` (API additions §7.2: `widgets()`, `keyPressed`,
  theme constants delegate to `EclipseUiTheme`)
- `client/handbook/CursorManager.java`, `GlitchText.java` (unchanged; owned to prevent
  drift)
- `artifact/ArmArtifactItem.java` (`overrideOtherStackedOnMe` open+pin, tooltip line)
- `artifact/ArtifactSlotLock.java` (`ARTIFACT_SLOT = 17`; javadoc update)
- `artifact/ArtifactDropGuard.java` (NEW — HIGH-priority `LivingDropsEvent` strip,
  B17)
- `progression/PhaseInventoryLock.java` (slot-17/artifact exemption in
  `sweepMainInventory`, B16 — sole P3 owner of this file)
- `client/ArtifactKeyHandler.java`, `client/ArtifactScreenOpener.java` (unchanged
  behavior; small: mouse-bound close support hook)
- `client/handbook/InventorySlotDecor.java` (NEW — slot-17 padlock/accent overlay via
  `ContainerScreenEvent.Render.Foreground`)

**Outline**: build `EclipseUiTheme` → rewrite screen layout math (fixed clamps §3.1)
→ rail widgets rendered untransformed (B3) → crossfade switcher → tab widget
lifecycle → artifact slot move + open flow + guards → sounds pass.
**Ledger**: `EclipseSounds` lines for new `ui.*` events + `sounds.json` entries
(placeholder oggs may alias existing `ui.tab`/`ui.unlock_sting` until P2 delivers);
tab-list line adding `new RevivalTab(), new SettingsTab()` once W2/W3 land;
`AGENTS/README` note re: slot 17.
**Acceptance**: handbook opens via J, artifact right-click in inventory (empty + full
cursor), never from another screen interrupt; artifact immovable by mouse
(pickup/swap/drop/toss/container-stash all rejected or reverted ≤1s), survives death
without grave duplication, exists exactly once after login/respawn/inventory-full
grant (occupant relocated); day-1 sealed inventory leaves slot 17 alone; panel
renders crisp at 320x240 gui-scale-4 and 3840-wide ultrawide; no stretched art
anywhere; ESC/J/1-8/arrows all work; system cursor always restored on close.

---

### P3-W2 — Handbook content tabs v3 (L, FABLE)

**Goal**: rework all six existing tabs to Quiet Eclipse + add the Revival tab; fix
B5/B7/B20; drop the Status online count (§3.3).

**Files owned**: `client/handbook/tabs/StatusTab.java`, `TimelineTab.java`,
`RulesTab.java`, `RewardsTab.java`, `BestiaryTab.java`, `MapTab.java`,
`RevivalTab.java` (NEW), `tabs/package-info.java`.

**Outline**: Status (2x day numeral, heart row, slim altar progress bar + label,
goals with kept tick draw-in, settings link removed — Settings is a tab now); Timeline
(flat 10px nodes, kept drag/inertia + hint, B5 gap fixes, milestone divider as
hairline+label); Rules (flat, scrollbar kept); Rewards (rows + scrollbar B7, item
icons kept); Bestiary (flat cards, silhouette + GlitchText kept); Map (recolor to
theme tokens, legend spacing); Revival (§3.1 chain layout, item ids per §5.1 with
fragment/sigil fallback). All strings via `EclipseLang.tr`; all scroll containers get
the shared scrollbar helper (add to `EclipseUiTheme`? NO — W1 owns that file; W2 adds
`tabs/TabScrollbar.java` helper it owns).
**Acceptance**: every tab readable at min content size; no text scissor-chop; scroll
affordances visible whenever scrollable; timeline centers correctly with/without
milestones; tick draw-in + altar sting fire even when the level changed while another
tab was active (B6 pairing with W1); de_de renders without overflow (longest German
strings tested).

---

### P3-W3 — Settings platform + reachability fix (L, FABLE)

**Goal**: consolidated `SettingsPanel`, settings v2 screen, handbook Settings tab,
pause-menu + vanilla-title entry points (B1), full §7.1 config expansion.

**Files owned**:
- `core/config/EclipseClientConfig.java` (ALL new keys/getters §7.1 — exclusive owner)
- `client/menu/EclipseSettingsScreen.java` (v2: hosts SettingsPanel; typed accessors,
  B13/B18)
- `client/menu/SettingsPanel.java` (NEW — §3.4 composite; widgets:
  `ThemedToggle`, `ThemedSlider`, `ThemedEnumCycle` as nested classes)
- `client/menu/PauseMenuHook.java` (NEW — pause button injection)
- `client/menu/VanillaTitleGear.java` (NEW — gear on vanilla title when
  `customMenu=false`)
- `client/handbook/tabs/SettingsTab.java` (NEW — thin HandbookTab hosting the panel;
  lives in tabs/ but owned by W3, W2 must not touch)
- `client/menu/ClientMenuExtensions.java`, `client/menu/OptionsThemer.java` (owned,
  unchanged unless factory needs the new screen ctor)

**Outline**: config keys first (frozen names §7.1, wave-1 merge) → widget trio with
`UiSounds.toggle/slider` → panel sections → mounts. Language row calls the same code
path as `/lang` (W4's `EclipseLang.setOverride` — compile-time dep, wave-1 partner).
**Acceptance**: every §7.1 key changeable from pause menu, title (custom AND vanilla),
handbook tab, Mods screen; values persist in `eclipse-client.toml`; toggling
`customMenu` off from ANY mount leaves settings reachable (B1 dead); sliders honor
drag + keyboard; no vanilla click plink anywhere in themed UI.

---

### P3-W4 — Localization core (M, SOL)

**Goal**: `/lang` + `/sprache`, `EclipseLang` resolver with instant reload, server
`LangService`, dual-language goal schema + editor fields, literal audit (B14/B15).

**Files owned**:
- `client/lang/EclipseLang.java` (NEW — §3.2 resolver + generation counter + reload
  listener)
- `client/lang/LangClientCommands.java` (NEW — `RegisterClientCommandsEvent`)
- `lang/LangService.java` (NEW, server) · `core/config/Localized.java` (NEW record)
- `network/C2SLocalePayload.java` + `network/LangPayloads.java` (NEW self-registering
  registrar class)
- `client/hud/AnnouncementOverlay.java` (B14 fix + `EclipseLang` adoption — sole owner)
- `devtools/client/GoalEditorScreen.java` (EN+DE boxes per goal/title/subtitle;
  object-form serialization §3.2)

**Outline**: resolver + prefix table → commands → C2S payload + server locale map +
attachment ledger line → re-send hooks (existing public senders) → editor fields →
literal sweep. Hand P4 the `days.json` schema + `DayPlan` migration note (§5.1).
**Ledger**: `EclipseAttachments` line (`locale_override`, String, persisted);
`announce.eclipse.unlock.key.generic` en+de in langdrop.
**Acceptance**: `/lang de` on an en_us client flips every Eclipse UI string that
frame (handbook open → strings swap after resize-reinit; sidebar/timer/announcements
next frame) with zero screen flicker and no global language change; `/sprache auto`
returns to detection; server-baked goals arrive in the chosen language ≤1s after the
command (re-send verified); relog keeps the override; dedicated server boots (no
client classes touched server-side).

---

### P3-W5 — Sidebar v2 + TAB expansion (L, FABLE)

**Goal**: §3.3 — online row gone, side/scale/overflow settings, marquee mode,
TAB-hold expanded card, polish.

**Files owned**: `client/hud/SidebarPanel.java` (rewrite),
`client/hud/SidebarExpanded.java` (NEW — expanded card renderer + 8-tick morph),
`client/hud/MarqueeText.java` (NEW — reusable scissored scroller).

**Outline**: strip online row → theme pass (hairline panel; drop nine-slice) →
config-driven anchor/scale/overflow → marquee (wall-clock, per-row phase, pauses) →
TAB detection (`keyPlayerList.isDown()`, no screen open) → morph animation edge↔center
→ expanded content pulls from `ClientStateCache` + W6 timer cache + W9 skill cache
(compile-time getters, null-safe when absent).
**Acceptance**: no online count anywhere in the panel; LEFT/RIGHT + scale 0.6–1.4
render correctly incl. slide direction; ELLIPSIS never wraps two lines; MARQUEE
scrolls long goals with end-pauses and never re-triggers the slide; TAB hold/release
morphs smoothly (snaps under reducedFx), shows full goal text + stats, releases
cleanly even if a screen opens mid-hold; vanilla scoreboard suppression + F1 + config
off all still work.

---

### P3-W6 — Bossbar v3 + day-timer HUD (L, FABLE)

**Goal**: §3.5 bossbar juice + §3.6 timer layer with spool animation.

**Files owned**: `client/hud/BossbarSkin.java` (rewrite per §3.5),
`client/hud/DayTimerLayer.java` (NEW), `client/hud/DayTimerCache.java` (NEW — synced
timer state, exposes `remainingMillis()` for W5's expanded card),
`network/S2CDayTimerPayload.java` + `network/TimerPayloads.java` (NEW registrar).

**Outline**: bossbar entrance/exit state machine → animated fill (P2 sheet w/
procedural fallback) → damage flash + generalized notches + frame breathing → SLIM
style variant → timer payload/cache → renderer (color lerp, underline, blink,
odometer spool) → stacking below `nextFreeBarY()`.
**Ledger**: GUI-layer registration lines (self-registered — none needed); P5 dev
command request (`/eclipse timer …`) §5.3; P2 asset request §5.2.
**Acceptance**: all three themes + SLIM + minimal strip render with entrance/exit
anims and correct phase ticks (NOTCHED_6/10/12/20); damage flash on Herald hits;
timer counts down against server epoch (client clock skew ±5min tolerated via
serverNow delta), shifts to purple inside warn window, blinks + stings at zero
exactly once, spools smoothly on dev add/reduce both directions; F1/cutscene hide
both elements; `showDayTimer=false` + `showBossbarSkin=false` fallbacks intact
(revive countdown never invisible).

---

### P3-W7 — Death screen, ghost HUD, ship-respawn client flow (L, FABLE)

**Goal**: §3.7 — vanilla death screen replaced, ghost hearts state, door-gated
return, revive celebration; server hook points minimal + handed to P4/P6.

**Files owned**:
- `client/death/EclipseDeathScreen.java`, `client/death/DeathScreenSwap.java` (NEW —
  Opening-event swap + killswitch + failsafe)
- `client/death/DeathFlowController.java` (NEW — §3.7 state machine)
- `client/death/GhostHudController.java` + `client/death/GhostHeartsLayer.java` (NEW —
  PLAYER_HEALTH cancel + ghost hearts + revive burst anim)
- `hearts/client/HeartBurstOverlay.java` (owned: consume `heartbeatSound` config
  (B12); expose the shatter-frame draw helper for the death screen's big heart)
- `network/S2CDeathStatePayload.java`, `S2CRevivedPayload.java`,
  `C2SRespawnReadyPayload.java`, `S2CShipDoorPayload.java` +
  `network/DeathFlowPayloads.java` (NEW registrar; server handlers delegate to
  P4-owned services via the frozen interface §5.1 — until P4 lands, handlers respawn
  via vanilla `player.respawn()` behind a TODO-interface)
- `lives/DeathFlowHooks.java` (NEW, server — the ONLY server file: sends
  `S2CDeathStatePayload` from `LivingDeathEvent` (HIGH priority, after
  `LifecycleEvents` decrements — ordering documented), sends `S2CRevivedPayload` from
  a public `onRevived(ServerPlayer)` that P4's revive ritual calls; does NOT touch
  `LifecycleEvents.java`/`BanService.java`)

**Outline**: payloads → swap + screen (§3.7 wireframe; big shatter reuses burst
sheet) → hold-timer + failsafe → ghost layer + vanilla-health cancel → revive burst
(12-tick shards fountain above hotbar + `ui.ghost_burst`) → door-state text gating
("Die Tür öffnet sich…" while OPENING) → controller edge cases (relog on death
screen, instant-respawn gamerule, `customDeathScreen=false`).
**Acceptance**: normal death → custom screen with correct remaining hearts + shatter
+ gated button → respawn lands on ship (with P6 stub: overworld anchor) and hotbar
burst plays; ghost death → ghost variant, vanilla hearts replaced by 5 cracked ghost
hearts, door text stays closed; simulated revive (`DeathFlowHooks.onRevived` via P5
dev command) → ghost hearts burst, real hearts return, door text flips; vanilla
screen restored by killswitch; NEVER stuck: button force-enables at 15s, screen
closable to title, relog mid-screen re-enters cleanly (pending-heart-loss replay
already exists server-side).

---

### P3-W8 — Main menu v2 / Journey (L, FABLE)

**Goal**: §3.8 — Reise beginnen with date-gate + glitch errors + direct connect,
modpack button removal, OP/dev unlock, journey config file.

**Files owned**: `client/menu/EclipseTitleScreen.java` (rewrite button block; visuals
kept), `client/menu/JourneyController.java` (NEW — config read, state json, gate
logic, ConnectScreen call), `client/menu/GlitchErrorTheater.java` (NEW — fake error
panels), `core/config/EclipseJourneyConfig.java` (NEW — own spec, file
`eclipse-journey.toml`), `network/S2COpStatusPayload.java` +
`network/JourneyPayloads.java` (NEW registrar + tiny server login sender reading
`player.server.getProfilePermissions(...)`), `client/menu/TitleScreenSwap.java`
(owned, unchanged).

**Outline**: journey spec + state json → button layout matrix (modpackMode x
devUnlock x cachedOp) → countdown/gate → glitch theater (2–3 randomized fake errors,
localized, `ui.error_glitch`, shake; reducedFx tooltip path) → ConnectScreen wiring +
disconnect-return path → op payload + cache write.
**Ledger**: `EclipseMod` line `EclipseJourneyConfig.register(modContainer)` (CLIENT
dist guard); P5 note: ship `eclipse-journey.toml` in the pack (§5.3).
**Acceptance**: with a future `activationIso` clicking produces the error theater and
never connects; flipping system clock past the instant (or dev `devUnlock=true`)
connects directly to a local test server (verified with the repo's run server);
modpackMode hides SP/MP/Realms/Mods on the custom title; after joining as op once,
buttons reappear on next boot; `activationIso` empty → button hidden; vanilla title
untouched; bad host/port lands on vanilla disconnect screen and back-returns to
title.

---

### P3-W9 — Skill tree GUI + XP HUD + proc toggle (L, FABLE)

**Goal**: §3.9 — full client suite against P4's frozen payloads.

**Files owned**: `client/skills/SkillTreeScreen.java`, `SkillTreeCanvas.java`,
`SkillClientCache.java` (exposes `level()/xp()` for W5), `CustomXpBarLayer.java`,
`LevelUpCelebration.java`, `SkillClientCommands.java` (`/eclipse-ui procs on|off`),
`SkillKeyMappings.java` (NEW self-registering, default K),
`InventoryButtonHook.java` (NEW — inventory screen button),
`network/S2CSkillTreePayload.java`, `S2CXpPayload.java`, `S2CSkillResultPayload.java`,
`C2SSkillPurchasePayload.java`, `S2CProcMessagePayload.java` +
`network/SkillPayloads.java` (registrar; server handlers delegate to P4 interface —
stub validates + echoes success for dev testing until P4 lands, clearly marked).

**Outline**: payloads + cache → canvas (pan/zoom 0.75–1.5, grab cursor, culling) →
node/line renderer + states → detail footer + purchase flow (in-flight lock) →
purchase/level-up anims + sounds → XP bar layer + always-on level → proc chat render
+ click-off + config gate → inventory button (recipe-book reposition handling) →
keybind + handbook link (Status tab link is W2's file — instead: handbook opens via
rail? NO — link lives in SkillTreeScreen's ESC-return only; the handbook-side button
is one ledger line in W2's StatusTab applied at merge).
**Acceptance**: with the dev-stub server handlers: tree renders a 12-node test
payload, purchase animates + persists across reopen, XP gain fills with easing +
level-up celebration fires once per level, bar + level visible in normal play and
hidden under F1/cutscene, proc line appears in chat with working `[aus]` click →
`procMessages=false` → no further lines; zoom/pan clamped; 100-node payload renders
>60fps (culling verified with debug counter).

---

### P3-W10 — Daily-awards roulette overlay (M, FABLE)

**Goal**: §3.10 — 3-reveal roulette with sounds + glitch flourish.

**Files owned**: `client/awards/AwardsOverlay.java` (layer + queue + phase machine),
`client/awards/RouletteStrip.java` (head strip physics/render),
`network/S2CAwardsPayload.java` + `network/AwardsPayloads.java` (registrar; dev-stub
server sender for testing via P5 command §5.3).

**Outline**: payload/queue → strip (deterministic landing on winnerIndex: precompute
total travel = N loops + offset, ease-out quart; ticks per head-pass with falling
pitch) → reveal card typewriter + flourish hook (`eclipse:award_glitch` Quasar/post id
via existing `QuasarSpawner.spawnOrFallback` screen-anchored? Quasar is world-space →
flourish = P2 post flash + client fallback: 6 GlitchText rectangles + accent flash) →
3-reveal sequencing + skip + reducedFx path → cutscene/F1/pause interplay.
**Acceptance**: test payload (3 categories, 12 fake candidates) plays 3 sequential
reveals landing exactly on the sent winners with slowdown ticks and win sting;
heads fall back to default skins when player-info is absent; overlay never captures
input, hides under F1, queues behind an active cutscene, survives payload spam
(cap 3); de_de lines fit the card (server-localized strings).

---

### P3-W11 — Loading screens + EMI gate (M, SOL)

**Goal**: §3.11 + §3.12 — safe loading-screen replacement, portal transition
controller, EMI hidden-index plugin + unlock sync.

**Files owned**: `client/loading/EclipseLoadingScreen.java`,
`client/loading/LoadingScreenSwap.java`, `client/loading/PortalTransitionController.java`,
`network/S2CPortalFxPayload.java`, `network/S2CUnlockedKeysPayload.java` +
`network/GatePayloads.java` (registrar), `progression/UnlockSync.java` (NEW server
sender on login + unlock recompute), `client/progression/ClientUnlockCache.java`,
`client/emi/EclipseEmiPlugin.java`, `client/emi/EmiReindexer.java` (reflection
trigger), `src/main/resources/data/eclipse/tags/item/emi_hidden.json` (NEW),
`build.gradle` (EMI dep lines — sole owner).

**Outline**: swap + delegate-tick wrapper + 60s failsafe + killswitch → visuals +
tips → portal payload/controller (defensive timeouts) → unlock payload/cache/sender →
EMI plugin (predicate invalidators + namespace recipe removal + hidden tag) →
reflection reindex on diff → `isLoaded("emi")` guards everywhere.
**Acceptance**: server join, nether portal, limbo teleport and SP world load all show
the eclipse screen and ALWAYS reach gameplay (delegate close verified; failsafe
tested by stalling); killswitch restores vanilla; with EMI installed
(localRuntime): locked namespaces' items absent from index + recipes unresolvable,
dev items in `#eclipse:emi_hidden` never visible, unlocking `create` mid-session
re-indexes within ~5s (or logs the documented fallback once); without EMI in the
mods folder the client boots clean (no classloading of EMI types).

---

## 5. INTERFACES TO SIBLING PLANNERS

### 5.1 P4 (lives/skills/awards/analytics/timeline engine)

| Contract | Direction | Detail |
|---|---|---|
| `Localized` goal schema | P3→P4 | `days.json` `goals[]`/`title`/`subtitle` accept `{"en","de"}` objects (legacy string = en). P4 migrates `EclipseConfig.DayPlan` to `List<Localized>` + per-player localized sends (`S2CDayStatePayload`/`S2CGoalProgressPayload` become per-player, using W4's `LangService.pick`). `Localized` record + parse helper provided by W4. |
| `LangService.locale(player)` | P4 uses | For ALL server-baked player-facing text (goal ticks, award lines, revive messages). |
| Death flow | P4 implements | Respawn anchor = limbo ship berth for every death (not just bans); call `DeathFlowHooks.onRevived(player)` from the revive ritual; keep sending `S2CLivesPayload` + existing heart-burst on respawn. `S2CDeathStatePayload` send stays in W7's `DeathFlowHooks` (reads `LivesApi` after decrement — event-priority ordering documented in that file). |
| Heart-extraction recipe items | P4→P3 | Item ids + counts for the Revival tab (current plan: extractor item, 2 hearts → 4 `eclipse:heart_fragment`, revive grants 1 heart). W2 renders whatever ids P4 publishes in `docs/plans_v3/P4_*` (fallback icons wired). |
| Skill backend | P4 implements | Server side of `S2CSkillTreePayload` (node graph JSON: id, iconItem, x, y, parents, cost, state, nameKey/descKey OR Localized), `S2CXpPayload`, `C2SSkillPurchasePayload` validation, `S2CSkillResultPayload`, `S2CProcMessagePayload` (respect per-player locale for baked args). W9's registrar exposes handler seams (`SkillPayloads.SERVER_HANDLER` swap point). |
| Awards payload | P4 implements | Fill `S2CAwardsPayload` (§7.3) from analytics; strings pre-localized per recipient; anonymity policy for `displayName`/UUID decided by P4 (P3 renders verbatim + default-skin fallback). |
| Day timer | P4 implements | Send `S2CDayTimerPayload` on login/day-change/schedule-change/dev-spool; `targetEpochMillis` from the real-world-day engine (`DayScheduler`/`PhaseScheduler` successor). |
| Unlock recompute hook | P4 aware | W11's `UnlockSync` re-broadcasts `S2CUnlockedKeysPayload` after `UnlockState` changes (day/milestone/boss); if P4 refactors `UnlockState`, keep a change-notification call. |

### 5.2 P2 (FX assets / shaders)

Asset requests (all with committed procedural fallbacks so P3 never blocks):
`textures/gui/bossbar/fill_anim.png` (512x128, 4 frames) + SLIM frame variants;
`eclipse:award_glitch` post flash + `ui.roulette_*`, `ui.level_up`, `ui.skill_buy`,
`ui.error_glitch`, `ui.timer_zero`, `ui.door_open`, `ui.ghost_burst`, `ui.click/
toggle/slider` OGGs; `eclipse:portal_glitch` Veil post pipeline (id consumed via
existing `VeilPostController`); `textures/gui/loading/ring.png` (optional); door
light-bloom effect behind the P6 door (world-side, P2/P6).

### 5.3 P5 (modpack / EMI bundling / dev commands / config distribution)

- Bundle EMI `1.1.22+1.21.1` (neoforge) in the pack; W11 adds the gradle API dep.
- Ship `eclipse-client.toml` + `eclipse-journey.toml` defaults in the modpack config
  overrides; document `journey.activationIso` + host/port as THE event switch.
- Dev command surfaces requested (in `EclipseCommands`, P5-owned — P3 never edits):
  `/eclipse timer add|set …` (→ re-send timer payload w/ spool), `/eclipse awards
  test`, `/eclipse skill grantxp|resettree`, `/eclipse deathflow revive <player>`
  (→ `DeathFlowHooks.onRevived`), `/eclipse locale debug`. Each maps to a public
  method in a P3-owned class listed above.
- Server is the hard gate for pre-launch joins (whitelist) — journey date gate is
  client theater only.

### 5.4 P6 (limbo ship + door)

- P6 sends `S2CShipDoorPayload{doorId, state: CLOSED|OPENING|OPEN, ghostGate}` on
  state change + on login for players in limbo; W7 only renders text/audio cues from
  it. Door physical open/close, respawn berth placement, walk-through teleport
  trigger region = P6. Purple light behind the door = P2/P6.
- Agreement: door NEVER opens for `ghost=true` players until `onRevived` fired
  (server-side check is P6's; the client only mirrors state).

---

## 6. RISKS & FALLBACKS

| # | Risk | Mitigation / fallback |
|---|---|---|
| R-1 | **EMI runtime re-index** uses internal `EmiReloadManager.reload()` (no public API; emi#494/#1207 confirm). Version bumps may break reflection. | Reflection isolated in `EmiReindexer` with try/catch + log-once; predicates re-evaluate on ANY EMI reload, so worst case content appears after the player's next resource reload/relog — a one-line localized toast ("Neue Inhalte freigeschaltet — Index aktualisiert sich…") covers the gap. Pin the EMI version in the pack (P5). |
| R-2 | **ConnectScreen quirks**: signature drift (`TransferState` param), SRV records, IPv6, connect-while-panorama GL state. | Exact-call verified at impl (mappings); use `ServerAddress.parseString` (handles SRV/port); wrap in try/catch → themed error panel instead of crash; connect only from the render thread via button callback. |
| R-3 | **Slot-17 pinning edge cases**: inventory-full grant, death drops, sealed main inventory day 1, container stashes, mods with extra slots (curios-like; current pack has none — sophisticated backpacks adds no player slot). | Existing sweep already relocates/dedupes; W1 adds drop-guard (B17) + PhaseInventoryLock exemption (B16); sweep remains the 1s-backstop for ANY exotic path (creative clone, other-mod moves). Acceptance tests enumerate each case. If a future pack adds curios, the sweep still self-heals (id-scan is inventory-wide); document in AGENTS notes. |
| R-4 | **Death-screen swap** vs. other mods / edge flows (bed explosion instant re-death, `doImmediateRespawn`, relog on screen). | Exact-class swap only; killswitch config; 15s force-enable; controller re-derives state from `ClientStateCache.lives` when payload missing; immediate-respawn rule → screen skipped entirely (server respawns without screen — flow tolerates). |
| R-5 | **Loading-screen replacement breaking world entry** (delegate never closes, other mods swapping too). | Delegate-tick wrapper (vanilla logic untouched), 60s failsafe close, exact-class guard, killswitch; never replace an already-replaced screen. |
| R-6 | **Marquee/odometer perf** on low-end (per-frame scissors + text). | Wall-clock math only (no allocations per frame), row cache keyed on content+generation, marquee capped at 6 rows, `reducedFx` disables both. |
| R-7 | **`/lang` override vs. resource packs** (custom packs overriding eclipse keys are read at reload). | Resolver parses lang from the FULL pack stack via ResourceManager (not just the mod jar) on every reload — pack overrides win, parity with vanilla. |
| R-8 | **RUN_COMMAND click on client commands** may be blocked by signed-command handling on some setups. | Fallback to `SUGGEST_COMMAND` (pre-fills chat) behind a try; the settings toggle remains the primary path. |
| R-9 | **TAB key conflicts** (players rebind playerlist; voicechat overlaps). | Uses `keyPlayerList` binding itself (whatever it is), not raw TAB; expansion only when no screen + not in chat. |
| R-10 | **Anonymity vs. roulette heads/names.** | Server (P4) decides exposure; payload is the single source; client renders default skins/anon names when withheld. |
| R-11 | **Op-status caching** for menu unlock leaks admin UI on shared PCs. | Cache stores only a boolean; `devUnlock=false` + cache-clear button in settings SERVER section; buttons appear, permissions still enforced server-side. |
| R-12 | **Clock skew** for timer + journey gate. | Timer renders off `serverNow` delta; journey gate is cosmetic (R-2/P5 note); both tolerate ±5min. |
| R-13 | **Config file conflicts** — many workers, one `eclipse-client.toml`. | Single owner (W3) + frozen key table §7.1; journey keys isolated in their own file (W8). |

---

## 7. FROZEN CONTRACTS (appendices)

### 7.1 `eclipse-client.toml` — full key table (W3 owns; getters frozen)

Existing: `customMenu`, `showBossbarSkin`, `showSidebar`, `uiSounds`, `customCursor`,
`veilPostFx`, `reducedFx` (unchanged semantics).

| New key | Type/range | Default | Getter | Consumer |
|---|---|---|---|---|
| `uiSoundVolume` | double 0.0–1.0 | 1.0 | `uiSoundVolume()` | W1 UiSounds |
| `heartbeatSound` | bool | true | `heartbeatSound()` | W7 HeartBurstOverlay |
| `sidebarSide` | enum LEFT/RIGHT | RIGHT | `sidebarSide()` | W5 |
| `sidebarScale` | double 0.6–1.4 | 1.0 | `sidebarScale()` | W5 |
| `sidebarOverflow` | enum ELLIPSIS/MARQUEE | ELLIPSIS | `sidebarOverflow()` | W5 |
| `bossbarStyle` | enum ORNATE/SLIM | ORNATE | `bossbarStyle()` | W6 |
| `showDayTimer` | bool | true | `showDayTimer()` | W6 |
| `customDeathScreen` | bool | true | `customDeathScreen()` | W7 |
| `customLoadingScreens` | bool | true | `customLoadingScreens()` | W11 |
| `procMessages` | bool | true | `procMessages()` | W9 |
| `showCustomXpBar` | bool | true | `showCustomXpBar()` | W9 |
| `levelUpCelebrations` | bool | true | `levelUpCelebrations()` | W9 |
| `allowServerRenderDistance` | bool | true | `allowServerRenderDistance()` | P2/P4 backend (client flag read server-side? no — client applies pushes; P2/P4 consume getter) |
| `langOverride` | string auto/en_us/de_de | "auto" | `langOverride()` / setter used by W4 | W4 |

**7.1b `eclipse-journey.toml` (W8 owns)**: `serverHost`(""), `serverPort`(25565),
`activationIso`(""), `modpackMode`(false), `devUnlock`(false). State file
`config/eclipse-journey-state.json` `{ "opGranted": bool }`.

### 7.2 Frozen client APIs

- `HandbookTab` (W1): current members unchanged PLUS
  `public List<AbstractWidget> widgets() { return List.of(); }` (screen adds/removes
  on tab switch, renders + routes input incl. focus/narration) and
  `public boolean keyPressed(int, int, int) { return false; }` (consulted BEFORE the
  1–8/arrow hotkeys).
- `EclipseUiTheme` (W1): constants + `drawPanel/drawHairline/drawHeader/ellipsize/
  withAlpha` (§2.1).
- `EclipseLang` (W4): `static Component tr(String key, Object... args)`,
  `static String trString(...)`, `static String locale()`, `static int generation()`,
  `static void setOverride(String)`, `static void reload()`.
- `SettingsPanel` (W3): `new SettingsPanel(int x, int y, int w, int h)` +
  `render/mouseClicked/mouseDragged/mouseReleased/mouseScrolled/keyPressed/widgets()`.
- Caches: `DayTimerCache.remainingMillis()/warnMillis()` (W6);
  `SkillClientCache.level()/xp()/xpForNext()` (W9); `ClientUnlockCache
  .isNamespaceLocked(String)/isKeyUnlocked(String)` (W11).

### 7.3 Payload table (name · direction · fields · registrar owner)

| Payload | Dir | Fields | Owner |
|---|---|---|---|
| `C2SLocalePayload` | C2S | `locale:String`, `explicit:boolean` | W4 |
| `S2CDayTimerPayload` | S2C | `targetEpochMillis:long`, `serverNowMillis:long`, `warnMillis:long`, `running:boolean`, `spool:boolean` | W6 |
| `S2CDeathStatePayload` | S2C | `heartsRemaining:int`, `ghost:boolean`, `lostHeartIndex:int`, `causeKey:String`, `holdTicks:int` | W7 |
| `C2SRespawnReadyPayload` | C2S | — | W7 |
| `S2CRevivedPayload` | S2C | `heartsRestored:int` | W7 |
| `S2CShipDoorPayload` | S2C | `doorId:String`, `state:byte(0 closed/1 opening/2 open)`, `ghostGate:boolean` | W7 (sender P6) |
| `S2COpStatusPayload` | S2C | `opLevel:int` | W8 |
| `S2CSkillTreePayload` | S2C | `treeJson:String` (nodes: id, iconItem, x, y, parents[], cost, state, nameKey, descKey), `points:int` | W9 (server P4) |
| `S2CXpPayload` | S2C | `xp:long`, `level:int`, `xpForNext:long`, `deltaXp:long` | W9 (server P4) |
| `C2SSkillPurchasePayload` | C2S | `nodeId:String` | W9 |
| `S2CSkillResultPayload` | S2C | `nodeId:String`, `success:boolean`, `points:int` | W9 (server P4) |
| `S2CProcMessagePayload` | S2C | `msgKey:String`, `argsJson:String`, `category:String` | W9 (server P4) |
| `S2CAwardsPayload` | S2C | `day:int`, `reveals:List<{categoryLine:String, candidates:List<{uuid:UUID,name:String}>, winnerIndex:int, statLine:String, rewardLine:String}>` | W10 (server P4) |
| `S2CUnlockedKeysPayload` | S2C | `keys:List<String>`, `lockedNamespaces:List<String>` | W11 |
| `S2CPortalFxPayload` | S2C | `style:String`, `holdTicks:int` | W11 (sender P6/P2) |

All payloads: record + `TYPE` + `STREAM_CODEC` (existing house style), registered by
the owner's self-subscribing `*Payloads` registrar class on registrar version `"2"`.

### 7.4 Lang namespaces + langdrop format

New key prefixes per worker: W1 `gui.eclipse.handbook.*` (frame/footer),
`item.eclipse.arm_artifact.*`; W2 `gui.eclipse.handbook.{status,timeline,rules,
revival,rewards,bestiary,map}.*`; W3 `gui.eclipse.settings.*`, `gui.eclipse.pause.*`;
W4 `commands.eclipse.lang.*`, `announce.eclipse.unlock.key.generic`; W5
`sidebar.eclipse.*`; W6 `gui.eclipse.timer.*`; W7 `gui.eclipse.death.*`,
`gui.eclipse.ghost.*`; W8 `gui.eclipse.journey.*` (incl. `journey.error.1..5`); W9
`gui.eclipse.skills.*`, `commands.eclipse.procs.*`; W10 `gui.eclipse.awards.*`; W11
`gui.eclipse.loading.tip.1..8`, `gui.eclipse.emi.*`. New subtitles:
`subtitles.eclipse.ui.*` for every new sound.

Langdrop file format (`docs/plans_v3/langdrop/P3_W<n>.json`):

```json
{ "en_us": { "gui.eclipse.timer.zero": "The day ends" },
  "de_de": { "gui.eclipse.timer.zero": "Der Tag endet" } }
```

Integrator merges alphabetically into both lang files; collisions are build errors.
