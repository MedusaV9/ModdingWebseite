# P5 — Dev Tools & `/dev` Handbook, Xbox-360 Tutorial Event, Mod Bundling, Music & Docs

Planner: **P5** (one of six parallel planners). Companion plans in this folder: `P3_ui.md`
(UI/EMI/loading screens), `P4_gameplay.md` (realtime days, buffs, quests, skills, analytics,
voice). P1 (core/worldgen/config), P2 (VFX/shaders), P6 (entities) plans may land separately —
interfaces to them are specified in §4 regardless.

Repo facts: project `/workspace/ProjectEclipse`, branch `cursor/project-eclipse`, package
`dev.projecteclipse.eclipse`, mod id `eclipse`, MC 1.21.1 (DataVersion **3955**), NeoForge
21.1.238, Java 21, Veil 4.3.0 already jar-in-jar via `build.gradle` (`jarJar(implementation(...))`,
line ~129). Current built jar `build/libs/eclipse-2.0.0.jar` = **34,050,142 bytes (~34 MB)**.
Lang: `assets/eclipse/lang/en_us.json` + `de_de.json`, **243 keys each** (all UI strings ship
en+de).

Requirement coverage map (user requirements A1–A13, B14–B16, C17–C21, D22–D24):

| Req | Topic | Design | Worker(s) |
|---|---|---|---|
| A1 | `/dev` + Dev Handbook GUI | §2.1, §2.2 | W1, W2 |
| A2 | `docs/DEV_COMMANDS.md` generated | §2.1 | W1 (exporter), W11 (commit) |
| A3 | Timer commands / scheduler UX | §2.3 | W3 |
| A4 | Timed buff commands | §2.4 | W4 |
| A5 | Quest/goal/unlock/XP/multiplier commands | §2.5 | W4 |
| A6 | Stage tooling fixes (2 bugs) | §1.2, §2.6 | W5 (+P1 interface §4.1) |
| A7 | Block-display placer + Axiom | §2.7 | W6 |
| A8 | Render-distance control | §2.8 | W4 |
| A9 | Voice mute commands | §2.9 | W4 |
| A10 | Spawn adjust tools | §2.10 | W6 |
| A11 | Cutscene replay/revert | §2.11 | W6 |
| A12 | Analytics query commands | §2.5 | W4 |
| A13 | `/dev reload` hot reload | §2.12 | W1 |
| B14 | Xbox event: portal, dimension, world shipping | §2.13 | W7, W9 |
| B15 | Classic blocks | §2.14 | W7 (bake), W8 (registry) |
| B16 | Event flow (timer, death, exit, reward) | §2.13 | W9 |
| C17 | Jar-in-jar bundling + licenses | §2.15 | W10 |
| C18 | Mod checker (allowlist) | §2.16 | W10 |
| C19 | 2–4 new content mods | §2.17 | W10 (config/docs only) |
| C20 | EMI runtime hiding backend | §2.18 | W10/W11 (P3-W11 owns plugin) |
| C21 | Compat test plan | §2.19 | §2.19 checklist (orchestrator) |
| D22 | Music + credits | §2.20 | W11 |
| D23 | Anti-XRay verdict | §2.21 | W12 (optional, deferred) |
| D24 | Aeronautics deeper integration | §2.22 | W10 (gating), P4 (quest content) |

---

## 1. CURRENT-STATE AUDIT

### 1.1 Command inventory & permission audit

Single admin root: `admin/EclipseCommands.java` registers `/eclipse` with
`.requires(source -> source.hasPermission(3))` (line 143) — the **whole tree is permission 3**.
Subcommands (verified from `Commands.literal` calls, lines 142–379):

| `/eclipse` subtree | Function |
|---|---|
| `start_event` | one-shot event start |
| `day set <n>`, `day goals` | day clock + goal listing |
| `event set <n>` | event phase |
| `boss herald summon/kill`, `boss ferryman summon/kill/phase <n>` | boss control |
| `lives set/add`, `altar set`, `ban <p>`, `revive <p>`, `restore <p>` | player state |
| `border set/ring set/fx range` | disc border |
| `modgate lock/unlock <ns>` | toggles namespace gating (writes **global** `config/eclipse/modgate.json` via `EclipseConfig.setNamespaceGated`, line 232→246) |
| `voicemute <p> on/off` | per-player voice force-mute |
| `stage get/set (animate/instant)/rebuild/save/load/revert/status` | StageIO (see §1.2) |
| `stage snapshot save/restore <name>` | PristineSnapshots whole-region backups |
| `schedule next <spec>/list/clear` | PhaseScheduler one-shot wall-clock day advance |
| `freeze on/off`, `invuln on/off` | FreezeService |
| `timeline`, `tp_limbo <p>` | inspection/teleport |
| `cutscene play/abort/list/enable/disable/skip allow-deny/preview/reloadpaths/export/edit (addkeyframe/removekeyframe/set roll/fov)` | cutscene editor/recorder (exists — req A11 builds on it) |
| `goals tick <p> <1..8>`, `goals edit` | manual goal tick + GoalEditorScreen open |
| `shards set/add/pool set`, `supply drop` | economy |
| `reload` | `EclipseConfig.reload()` + `CutscenePaths.reload()` + re-sync day state/milestones/cutscene lib (lines 1312–1324) |
| `status` | status dump |

Other command-adjacent surfaces:

- `devtools/ConfigEditor.java` — server handler for `C2SConfigEditPayload` (goal editor GUI
  saves); **gated at permission 3** inside the handler; writes to
  `FMLPaths.CONFIGDIR.get().resolve("eclipse")` (line 121 — global, see BUG-B).
- `anonymity/CommandBlocker.java` — blocks `msg, tell, w, me, teammsg, tm, list` for players
  below `Commands.LEVEL_GAMEMASTERS` (= **2**); ops ≥2 bypass. A new player-level command
  (e.g. `/xboxleave`) is NOT affected as long as its literal is not in `BLOCKED_COMMANDS`.
- C2S payloads: `C2SConfigEditPayload` (perm 3 in handler), `C2SCutsceneStatePayload`,
  `C2SModlistPayload` (anticheat self-report), `C2SOpenArtifactPayload` (player-level by
  design).

**Audit verdict**: no dev/admin surface below permission 2 exists today; everything is at 3.
Policy for new work: the whole `/dev` tree requires **permission ≥ 2** (`.requires(s ->
s.hasPermission(2))` on the root; destructive leaves may individually require 3 — flagged per
command in §2.1). Documented exception: **`/xboxleave` is permission 0** (player-facing
voluntary exit, only functional inside the Xbox dimensions, §2.13.6). P4 ships reference/smoke
commands under separate roots (`/eclipse-rt`, `/eclipse-buffs`, `/eclipse-quests` — see
`P4_gameplay.md`); P5's `/dev` tree is the *polished* surface and never edits
`EclipseCommands.java` (Brigadier merges separately-registered roots, so no shared file).

### 1.2 StageIO snapshot flow + the two stage bugs, root-caused

Flow (`devtools/StageIO.java`): `save(level, profile, stage)` serializes the stage-*n*
annulus to `<world>/eclipse/stages/<n>.bin` (`nether_<n>.bin` for the nether profile) —
`stagesDir()` = `server.getWorldPath(LevelResource.ROOT).resolve("eclipse/stages")` (line
119), i.e. **already per-save**. `load()` applies a `.bin` and persists the stage as the
dimension's `lastLoadedStage` in `EclipseWorldState` (per-save SavedData
`eclipse_world_state`). `revert()` (line 231) = `load(lastLoadedStage)`, erroring out when
`lastLoaded < 0`. `isApplying(profile)` guards against `RingGrowthService` racing.
`PristineSnapshots` copies whole region-storage dirs to `<world>/eclipse/stage_snapshots/
<name>/` (restore staged for next boot) — also per-save.

**BUG-A (revert impossible)** — root cause: nothing ever snapshots the *live* terrain before
a stage apply. `lastLoadedStage` is only set by a successful `load()`; on a fresh curated
world (or after manual building) the first `stage load`/`stage set` **overwrites terrain with
no backup**, and `revert` correctly reports "none". Fix (§2.6): auto-backup the affected
annulus to a timestamped `.bin` before *any* destructive apply (`load`, `set`, `rebuild`,
ring growth start), with retention.

**BUG-B (state "identical across saves")** — root cause is NOT SavedData. Verified per-save:
`EclipseWorldState` (SavedData), `StageIO` dirs, `PristineSnapshots` dirs. The global bleed
is the **config layer**:

- `core/config/EclipseConfig.java` loads all six files from the *installation-global*
  `FMLPaths.CONFIGDIR/eclipse/` (`general/days/milestones/modgate/anticheat/stages.json`,
  line 259) into `private static volatile` fields (lines 87–93).
- `EclipseConfig.reload()` is called from `EclipseMod` common setup (line 58) — **once per
  JVM** — plus on `/eclipse reload` and after ConfigEditor writes. It is *never* re-run on
  world switch, and there is no per-world overlay.
- Writers make it worse: `ConfigEditor.handleEdit` (line 121) and
  `EclipseConfig.setNamespaceGated` (`/eclipse modgate`) write the **global** files. Editing
  days/milestones/stage radii in world A permanently changes world B (and every future test
  world) — exactly the "same state across saves" symptom, since stage *definitions* (radii,
  triggers) and day plans all come from this layer even though the stage *number* is
  per-save.

Fix ownership: the config layering primitive is **P1's** (`core/config`) — contract in §4.1:
per-world overlay `<world>/eclipse/config/*.json` over global defaults,
`EclipseConfig.reload(MinecraftServer)` re-resolved on every `ServerAboutToStartEvent`,
editors write to the world layer. P5-W5 fixes BUG-A + backup UX regardless (no dependency),
and P5-W4 extends the ConfigEditor file-allowlist (P4 explicitly assigns that to P5,
`P4_gameplay.md` §4) using P1's path helper once it exists.

### 1.3 `run/mods` inventory (verified filenames)

Server pack (`run/mods/`):

| Jar | Version |
|---|---|
| `create-1.21.1-6.0.10.jar` | Create 6.0.10 |
| `createaddition-1.6.0.jar` | Create Crafts & Additions 1.6.0 |
| `create-aeronautics-bundled-1.21.1-1.3.0.jar` | Aeronautics dev bundle (incl. `simulated`, `offroad` namespaces) |
| `FarmersDelight-1.21.1-1.3.2.jar` | Farmer's Delight 1.3.2 |
| `moonlight-neoforge-1.21.1-3.1.1.jar` | Moonlight lib 3.1.1 (Supplementaries dep) |
| `sable-neoforge-1.21.1-2.0.3.jar` | Sable 2.0.3 (jarJars Veil `[4.1.4,)`) |
| `sophisticatedbackpacks-1.21.1-3.25.71.1997.jar` | Sophisticated Backpacks |
| `sophisticatedcore-1.21.1-1.4.77.2173.jar` | Sophisticated Core |
| `supplementaries-neoforge-1.21.1-3.8.3.jar` | Supplementaries 3.8.3 |
| `voicechat-neoforge-1.21.1-2.6.16.jar` | Simple Voice Chat 2.6.16 |

Client-only extras (`run/mods-client/`): `sodium-neoforge-0.8.12+mc1.21.1.jar`,
`iris-neoforge-1.8.14-beta.1+mc1.21.1.jar`. In-jar: Veil 4.3.0 (jarJar; build.gradle
comment documents dedup with Sable's `[4.1.4,)` range — precedent that **nested-jar version
dedup works** in this stack).

### 1.4 ModGate keys & anticheat as configured today

`run/config/eclipse/modgate.json` — 9 gated namespaces → unlock keys: `create→create`,
`simulated→simulated`, `aeronautics→aeronautics`, `sable→sable`,
`farmersdelight→farmersdelight`, `supplementaries→supplementaries`,
`sophisticatedbackpacks→sophisticatedbackpacks`, `createaddition→createaddition`,
`offroad→aeronautics` (shared key). `run/config/eclipse/` also holds `anticheat.json`
(**blocklist** of mod-id substrings: `xray, advancedxray, freecam, freelook, replaymod,
litematica`), `days.json`, `disc_map.json`, `general.json`, `milestones.json`, `stages.json`,
`cutscenes/`. Req C18 needs an **allowlist** mode on top of this (§2.16).

### 1.5 Other infra relevant to P5

- **Payloads**: single registrar `network/EclipsePayloads.java` on
  `RegisterPayloadHandlersEvent`. NeoForge allows any number of additional
  `@EventBusSubscriber` classes listening to the same event → **P5 workers register new
  payloads in their own `*Payloads` classes; nobody edits `EclipsePayloads.java`.**
- **Handbook GUI**: `client/handbook/HandbookScreen` + 7 tabs — style reference for the Dev
  Handbook (P3 owns visual language; §4.3).
- **Cutscene tooling**: `cutscene/` (`CutsceneService`, `CutscenePaths`, `UnlockCinematics`,
  `FreezeService`) + `/eclipse cutscene edit` recorder — replay/revert (A11) builds on it.
- **Voice**: `voice/VoiceMuteApi` today: `isEntryMuted(player)`, `setForceMuted(server,
  uuid, bool)`, `isMuted(server, player)`; P4-B9 adds `setGlobalMuted(server, bool)`.
- **Spawn protection**: `worldgen/structure/SanctumProtection.RADIUS = 16` (static final),
  exempt permission 3 — must become dynamic for A10.
- **GrowthStartListener**: `WorldStageService.addGrowthStartListener(...)` exists (line 88)
  → W5's auto-backup can hook ring growth **without touching WorldStageService**.
- **No gametests yet** (`gametest/` absent; P4-A1 ships the scaffolding; gradle
  `gametestServer` run already configured). No datagen providers yet (resources exclude
  `src/generated/**/.cache` — datagen output dir is anticipated; W8 introduces the first
  real datagen).
- **Dimensions**: datapack dimension precedent `data/eclipse/dimension/limbo.json` (+
  `dimension/LimboDimension.java` helpers) — the Xbox dims follow this pattern.

---

## 2. DESIGNS

### 2.1 `/dev` root, DevCommandRegistry, generated docs (A1, A2, A13)

**Single source of truth**: `devtools/dev/DevCommandRegistry` — a static, insertion-ordered
registry of `DevCommandDoc` records that (a) the Dev Handbook GUI renders, (b)
`docs/DEV_COMMANDS.md` is generated from, (c) `/dev help` chat fallback prints. Every P5
worker that adds a `/dev` subcommand ALSO registers its docs here (acceptance criterion in
every worker package).

```java
public record DevCommandDoc(
    String id,                 // "timer.pause" — stable, dot-separated
    DevCategory category,      // EVENT, TIMER, BUFFS, QUESTS, PLAYERS, STAGE, DISPLAY,
                               // SPAWN, XBOX, MODS, MUSIC, CONFIG, ANALYTICS, CUTSCENE
    String syntax,             // literal syntax: "/dev timer pause"
    String descKey,            // lang key, en+de: "dev.eclipse.doc.timer.pause"
    Danger danger,             // SAFE, CAUTION (yellow), DESTRUCTIVE (red, GUI confirm)
    ClickAction clickAction,   // RUN (fixed commands) or SUGGEST (has arguments)
    int permission             // 2 default; 3 for destructive leaves
) {}
```

`DevCategory` and `Danger` carry lang keys too (`dev.eclipse.category.*`,
`dev.eclipse.danger.*`). Registration API: `DevCommandRegistry.register(DevCommandDoc...)`
called from each command class's static init; `all()` returns the frozen list;
`visibleTo(ServerPlayer)` filters by permission (server-side — clients never see entries
they cannot run).

**Command registration convention (no shared files)**: each worker's command class
subscribes to `RegisterCommandsEvent` itself and calls `dispatcher.register(
Commands.literal("dev").requires(s -> s.hasPermission(2)).then(<its subtree>))`. Brigadier
**merges** same-literal roots across multiple `register` calls — verified pattern; no worker
touches another worker's file or `EclipseCommands.java`.

Root behavior (`devtools/dev/DevRoot.java`, W1):

- `/dev` (bare) → sends `S2CDevHandbookPayload` (entries `visibleTo(player)`) → client opens
  Dev Handbook (§2.2). If the receiving client lacks the screen (vanilla client), falls back
  to the chat listing.
- `/dev help [<category>]` → paginated chat listing (clickable: RUN executes, SUGGEST fills
  chat input) — works headless/RCON.
- `/dev docs export` → writes the generated markdown to `docs/DEV_COMMANDS.md` when run in a
  dev workspace (path resolved relative to `gameDir/../docs` if it exists), else to
  `<gameDir>/eclipse-dev-commands.md`; reports the absolute path. Generator walks
  `DevCommandRegistry.all()` grouped by category + a **Config reference** section (file →
  purpose → reload behavior; §2.12 table) + a **Dev blocks/items** section (Display Wand
  etc.). CI-sync rule: W11 runs the exporter and commits `docs/DEV_COMMANDS.md`; the doc
  header carries `<!-- GENERATED by /dev docs export - do not hand-edit -->`.
- `/dev reload` → §2.12.

Full `/dev` tree (syntax frozen for all workers; argument types in parens):

```
/dev                                         open handbook GUI            [2] W1
/dev help [<category>]                       chat listing                 [2] W1
/dev docs export                             generate DEV_COMMANDS.md     [2] W1
/dev reload                                  hot-reload all configs       [2] W1

/dev timer status|pause|resume|arm|disarm                                 [2] W3
/dev timer add|sub <duration>                (1h30m / 45m / 90s)          [2] W3
/dev timer set <HH:mm> | <yyyy-MM-dd HH:mm> | +<duration>                 [2] W3
/dev timer preset (noon|evening|midnight|plus30m|plus1h|plus2h)           [2] W3

/dev buff start <id> [<minutes>] [<magnitude>]  (suggests buffs.json ids) [2] W4
/dev buff stop (<id>|all) ; /dev buff list                                [2] W4

/dev quest list <player>                                                  [2] W4
/dev quest (complete|revoke) <targets> (main|side|personal) <indexOrId>   [2] W4
/dev quest reroll <player>                                                [2] W4
/dev unlock list ; /dev unlock (grant|revoke) <key>                       [3] W4
/dev xp (grant|set) <targets> <amount>                                    [2] W4
/dev xp multiplier set <player> <factor> ; clear <player>   (secret)      [3] W4
/dev skill grantxp <targets> <amount> ; /dev skill resettree <player>     [2] W4
/dev voice mute <player> (on|off) ; /dev voice muteall (on|off) ; status  [2] W4
/dev viewdistance (set <2..32>|reset|status)                              [2] W4
/dev stats top <metric> [<n>] ; player <player> [<day>] ; keys [<day>]    [2] W4
/dev awards (test [<player>]|dryrun [<day>])                              [2] W4
/dev deathflow revive <player>                                            [2] W4
/dev locale debug                                                         [2] W4

/dev stage backup (list|now [<label>]|restore <id>|prune [<keep>])        [3] W5

/dev display give                                                         [2] W6
/dev display place <block> [<scale>]                                      [2] W6
/dev display list [<radius>] ; remove <id>                                [2] W6
/dev display edit <id> (pos|rot|scale) <x> <y> <z>                        [2] W6
/dev display edit <id> (spin|bobamp|bobperiod|phase) <value>              [2] W6
/dev spawn set (here|<x> <y> <z>) ; radius <blocks> ; preview (on|off) ; info [3] W6
/dev replay (intro|expansion <stage>|finale|list)                         [3] W6

/dev xboxevent start (tu1|tu12|tu14) [<minutes>]                          [2] W9
/dev xboxevent stop [now] ; status                                        [2] W9
/dev xboxevent time (add|sub|set) <duration>                              [2] W9
/dev xboxevent portal (here|remove)                                       [2] W9
/dev xboxevent lockout clear (<player>|all)                               [2] W9
/dev xboxevent reward set <buffId> <minutes>                              [2] W9
/dev xboxevent reset <world>                                              [3] W9
/dev xboxevent bake <world>              (dev-workspace only)             [3] W7

/dev modcheck (status|snapshot|mode (blocklist|allowlist)|test <player>)  [3] W10
/dev music (play <cueId>|stop|list) ; /dev credits                        [2] W11
```

Separate root: `/xboxleave` — **permission 0**, registered by W9, no-op with a polite
message outside the Xbox dimensions. Not in `CommandBlocker.BLOCKED_COMMANDS`, so it passes
the anonymity filter (§1.1).

Note for P3/P4 doc cross-refs: `P3_ui.md` §5.3 asks for `/eclipse timer add|set`,
`/eclipse awards test`, `/eclipse skill grantxp|resettree`, `/eclipse deathflow revive`,
`/eclipse locale debug` — these land as the `/dev` equivalents above (P3/P4 call public
methods; the root literal is P5's choice per user requirement A1). The spool payload
behavior P3 expects is automatic: every boundary mutation broadcasts P4's clock payload.

### 2.2 Dev Handbook GUI data model (A1)

Client screen `devtools/dev/handbook/DevHandbookScreen` (opened only via payload — never
from the player-facing artifact handbook). Data model = the synced `List<DevCommandDoc>`
(wire codec: id, categoryOrdinal, syntax, resolved description **string** (server resolves
lang? NO — send `descKey`, client resolves; both langs ship in the client jar), danger,
clickAction, permission).

- **Payloads** (`devtools/dev/handbook/DevHandbookPayloads`, own registrar): 
  `S2CDevHandbookPayload{entries:List<Entry>, configRef:List<ConfigRefEntry>}` (sent on
  `/dev`); `C2SDevRunCommandPayload{commandLine:String}` — server re-validates permission
  ≥2 AND that `commandLine` matches a registered doc's syntax prefix before executing via
  `server.getCommands()` (never trust the client).
- **Screen**: left rail = categories (14 max) + search box (fuzzy on syntax+description,
  `/` focuses search — screen-local, does NOT conflict with global palette hotkeys since
  this is a Screen, not a global listener); main pane = entry cards: syntax line
  (monospace), description, danger badge (CAUTION yellow / DESTRUCTIVE red), buttons
  `[Ausführen]/[Run]` (RUN + confirm dialog when DESTRUCTIVE) and `[In Chat]/[To chat]`
  (SUGGEST → closes screen, pre-fills chat). Bottom bar: config-reference toggle (renders
  the §2.12 table) and "Docs exportieren" button (runs `/dev docs export`).
- **Style**: reuse the existing handbook visual kit (`EclipseWidget`, `UiSounds`,
  parchment palette) but flat/compact — P3 style tokens per §4.3; no parallax/hero art
  (this is a tool, not a diegetic book).

### 2.3 Timer & scheduler UX (A3)

Current pain: `/eclipse schedule next <spec>` (PhaseScheduler) takes a raw spec, has no
pause, no presets, and feedback is a bare line. P4-B1 **rewrites the engine**
(`progression/realtime/RealtimeDayService`, SavedData `eclipse_realtime`, and turns
`devtools/PhaseScheduler.java` into a thin delegate — P4 owns both files). P5-W3 therefore
builds ONLY the command surface, calling the frozen P4 dev API (`P4_gameplay.md` §2.1):
`arm()/disarm()/pause()/resume()/addMillis(±delta)/setBoundary(isoDateTime|+spec)/status()`;
parsing lives in P4's `RealtimeMath` (`parseSpec` moved out of PhaseScheduler).

Command behaviors (all broadcast P4's `S2CDayClockPayload` automatically via the service, so
P3's sidebar/spool animates without extra work):

- `pause` → freeze (engine stores remaining); feedback `⏸ Tag-Timer pausiert — verbleibend
  4h 12m` / en equivalent. `resume` → `▶ … nächster Tageswechsel: Do 18:00 (in 4h 12m)`.
- `add/sub <duration>` → `RealtimeMath.parseSpec` formats; clamp result ≥ now+5s (engine
  contract); feedback shows old → new boundary.
- `set <HH:mm>` → today-or-tomorrow resolution in the engine's configured zone
  (`realtime.json zone`, default Europe/Berlin); `set <yyyy-MM-dd HH:mm>`; `set +<spec>`.
- `preset` → literal keywords (Brigadier suggestions): `noon`=next 12:00, `evening`=next
  18:00, `midnight`=next 00:00, `plus30m/plus1h/plus2h` relative. (Literals avoid `+`
  parsing issues in Brigadier literals.)
- `status` → multiline: armed/paused, day, boundary absolute + relative, zone, manual
  override flag, catch-up config.
- Every mutation logs at INFO with the acting operator's name (audit trail).

Sequencing: W3 compiles against P4-B1's classes → runs in a wave **after** P4-B1 merges.
Legacy `/eclipse schedule` keeps working verbatim (P4's delegate guarantees it); the Dev
Handbook marks it "legacy — prefer /dev timer".

### 2.4 Timed buff commands (A4)

Thin bridge to P4's frozen `TimedBuffApi` (interface ships in P4-A1 with a no-op holder, so
W4 compiles even before P4-B9 lands): `start(server, id, minutesOverride, magnitudeOverride)
→ boolean`, `stop(server, id)`, `active(server)`, `isActive(id)`. Buff ids come from P4's
`buffs.json` (`double_skill_xp`, `ore_drops`, `shard_drops`, `hunger`, `magnet`,
`glitch_surge`, …) — suggestion provider reads `TimedBuffApi.knownIds()` (small API ask,
§4.4; fallback: suggest active ids only). `/dev buff start doublexp 30m` style: the id
argument is a greedy word matched case-insensitively with alias table
(`doublexp→double_skill_xp`); duration accepts `30m/1h/90s` via `RealtimeMath.parseSpec`.
`list` renders id, remaining (mm:ss), magnitude, source bossbar state. Feedback on `start`
returning false explains the stack rule (`refuse` policy) per P4 §2.16.

### 2.5 Quest/goal, unlock keys, skill XP, secret multiplier, analytics (A5, A12)

All bridges to P4 APIs (frozen in `P4_gameplay.md` §4 "P5 (devtools/commands)"):

- **Quests/goals**: `QuestEngine` completion pipeline + admin entry points. Frozen calls:
  `QuestEngine.complete(...)`; asks (§4.4): `QuestEngine.adminComplete(player|team, kind,
  indexOrId)` and `adminRevoke(...)` (revoke = un-complete + baseline reset). `/dev quest
  list <player>` prints the 3 personal quests + day mains/sides with done flags (data from
  `QuestState`). `reroll` → `QuestEngine` re-draw (exists: "tick/reroll/reload").
- **Unlock keys**: `/dev unlock grant|revoke <key>` — needs an override set consulted by
  `UnlockState` (derived-only today). Ask to P4 (who owns progression state migration in
  wave B): `UnlockOverrides.grant(server, key) / revoke / list` persisted in a P4-owned
  SavedData; `UnlockState.isUnlocked` = derived ∪ granted − revoked. Fallback if P4 defers:
  command maps to existing `EclipseConfig.setNamespaceGated` semantics for mod namespaces
  (with a warning that it is config-global) and errors for day-keys with a pointer to
  `/eclipse day set`. Suggestion provider lists known keys (modgate values + day plan keys).
- **Skill XP**: `SkillsApi` xp add/set → `/dev xp grant|set`, `/dev skill grantxp` (alias
  P3 asked for), `/dev skill resettree` (SkillsApi reset — P3 §5.3 lists it).
- **Secret multiplier**: `SkillsApi.setSecretMultiplier(uuid, f)` — P4 guarantees
  persistence + never-synced/never-logged-at-info; command output goes ONLY to the issuing
  operator (`sendSuccess(…, false)`), value never broadcast; `clear` = set 1.0.
- **Analytics**: `AnalyticsApi.value(day, uuid, key) / top(day, key, n) / keys(day) /
  onlineOrKnownUuids(day)` → `/dev stats top|player|keys`. `/dev awards dryrun` →
  `AwardService.preview` (computes winners without granting); `/dev awards test [<player>]`
  → P3's roulette test sender (P3-W10 exposes the public method; §4.3).
- **Editor allowlist** (P4 hand-off): extend `ConfigEditor`/`GoalEditorScreen`/
  `C2SConfigEditPayload` file-allowlist with `goals.json`, `quests.json`, validated through
  `GoalConfig.validateAndNormalize(JsonElement)` — W4 owns these three files' edits.

### 2.6 Stage tooling fixes (A6) — auto-backup + retention + browser

New `devtools/StageBackups.java` (W5) + edits confined to `devtools/StageIO.java`:

- **Auto-backup**: before ANY destructive apply — entry points instrumented inside
  `StageIO.load()` (before first chunk write) and via
  `WorldStageService.addGrowthStartListener(...)` (ring growth / `stage set animate`;
  listener registration from `StageBackups`, zero edits to WorldStageService) — serialize
  the *current live terrain* of the affected annulus using the existing `save()` serializer
  into `<world>/eclipse/stages/backups/<utc-timestamp>_<profile>_<stage>[_<label>].bin` +
  sidecar `.json` (source command, operator, game day). Guarded by `isApplying` to
  self-suppress during our own restore.
- **Retention**: keep newest N per profile (default 10, `general.json` key
  `stageBackupRetention` — read via existing `EclipseConfig.general()` accessor; key added
  by P1's config work, default constant in W5 code meanwhile), prune post-write.
- **Restore/browse**: `/dev stage backup list` (id = filename stem, age, size, source),
  `now [<label>]` (manual), `restore <id>` (applies via the `load()` machinery with
  auto-backup of the pre-restore state too — restore is itself revertible), `prune`.
- **Fix semantics of `revert`**: unchanged file behavior, but now guaranteed possible:
  every apply path creates a backup, and `/eclipse stage revert`'s error message gains a
  pointer to `/dev stage backup list`. (String change inside StageIO's error line — W5 owns
  the file.)
- **Per-save audit**: §1.2 confirms snapshots/backups are per-save already; W5 adds a
  gametest asserting `stagesDir` resolves under the *active* world root (guards
  regressions); the config-layer leak is P1's (§4.1) — W5 must NOT touch `core/config`.

### 2.7 Block-display placer (A7) + Axiom verdict

`devtools/display/` (W6): place, animate, edit, persist **vanilla `minecraft:block_display`
entities** — no custom entity type, so worlds stay loadable without the mod and any editor
that understands display entities can manipulate them.

- **Data**: animation params stored on the entity itself — NBT-backed attachment
  (`eclipse:display_anim` = `{spinDegPerSec:float, bobAmplitude:float, bobPeriodSec:float,
  phase:float, baseTransform}`) + entity tag `eclipse_display` for discovery. Persisted by
  vanilla entity storage automatically.
- **Animator** `DisplayAnimator`: server tick (every 2t) updates `transformation` with
  interpolation (`transformation_interpolation_duration` = 2t) — same approach as the spawn
  island's existing oar/decoration animator; skips chunks without loaded displays (indexed
  per-level set maintained on load/unload events).
- **Commands + Wand**: `/dev display place <block> [<scale>]` spawns at the operator's
  crosshair block (0.5m offsets); `list [<radius>]` prints clickable ids (id = short hash of
  UUID, teleport + edit suggestions); `edit <id> pos|rot|scale <x y z>` and scalar params;
  `remove <id>`. Dev item **Display Wand** (`devtools/display/DevToolItems`, own
  DeferredRegister; creative-tab hidden, `/dev display give` only; in `#eclipse:emi_hidden`
  via wiring note): left-drag = rotate around hit axis, scroll+sneak = scale, right-click =
  cycle target among nearby displays; all edits round-trip through the same server command
  handlers (C2S payload `C2SDisplayEditPayload`, perm 2 server check).
- **Axiom verdict (researched)**: Axiom on Modrinth is **All Rights Reserved** and its
  1.21.1 builds are **Fabric-only** (NeoForge builds exist only for newer MC). → cannot be
  bundled OR tested on this stack; nothing to break: our displays are vanilla entities, so
  if a NeoForge Axiom appears later it can edit them natively. Documented in DEV_COMMANDS
  ("Axiom: not available for NeoForge 1.21.1; wand + commands are the supported editor").

### 2.8 Render-distance control (A8)

Server-side push of a per-player render distance (W4, coordinated with P2 §4.2 so the two
planners don't ship two competing settings pushers):

- `S2CViewDistancePayload{chunks:int, reset:boolean}` (W4-owned registrar). Client handler:
  if the client config flag `acceptServerViewDistance` (default **true**, in P5's client
  config section, opt-out per user req) is set, store the vanilla option's original value
  once, apply the pushed value, restore on `reset`/disconnect.
- `/dev viewdistance set <2..32>` pushes to all (and to late-joiners via
  `PlayerLoggedInEvent` re-push while active — persisted in `general.json`-adjacent runtime
  state, W4-owned SavedData `eclipse_client_push`); `reset` clears; `status` lists per-player
  ack state (client replies `C2SViewDistanceAckPayload{applied:int}`).
- Server floor: warn the operator when the dedicated server's own `view-distance` <
  pushed value ("Server view-distance is 10 — clients cannot see farther than the server
  sends. Raise server.properties view-distance.").

### 2.9 Voice mute commands (A9)

`/dev voice mute <p> on|off` → existing `VoiceMuteApi.setForceMuted`; `/dev voice muteall
on|off` → P4-B9's `VoiceMuteApi.setGlobalMuted(server, boolean)`; `status` prints global
flag + per-player forced mutes + entry-mute count. Pure bridge (W4); the SVC plugin already
enforces `isMuted` at `MicrophonePacketEvent` (P4 verified) so no packet work here.

### 2.10 Spawn adjust tools (A10)

W6 owns `SanctumProtection.java` (single P5 owner; P4's `protection.json` covers
grave/altar-adjacent rules — coordination checkpoint in §4.4 to keep the two disjoint):

- Make radius dynamic: `SanctumProtection.radius(server)` reads W6-owned SavedData
  `eclipse_spawn_tuning{radiusOverride:int(-1), previewOn:boolean, spawnOverride:BlockPos?}`
  (default preserves current `RADIUS = 16`; `RADIUS_SQ` becomes computed).
- `/dev spawn set here|<x y z>` → sets level shared spawn (`ServerLevel.setDefaultSpawnPos`)
  + records override + confirms with coordinates and a one-time particle burst; `/dev spawn
  radius <blocks>` (1..64) live-applies; `/dev spawn preview on|off` → server particle ring
  (dust, every 10t, only to ops within 128 blocks — cheap); `info` prints spawn pos, radius,
  altar pos, preview state.

### 2.11 Cutscene replay/revert of event sequences (A11)

Existing: full editor/recorder under `/eclipse cutscene …` (§1.1) — already documented in
the handbook by W1's registry import of *existing* commands (the registry also lists legacy
`/eclipse` entries, flagged `legacy:true`, so the Dev Handbook covers the WHOLE admin
surface per req A1). New (W6, `devtools/ReplayService.java`):

- `/dev replay intro` — snapshots the relevant `EclipseWorldState` flags (cutscene-played /
  milestone-seen flags via existing public setters ONLY — no new fields), resets them,
  re-fires the intro sequence through `CutsceneService`/`UnlockCinematics` public entry
  points; on completion offers a clickable "revert flags" (restores the snapshot) so
  testing never permanently mutates progression.
- `/dev replay expansion <stage>` — re-fires the growth cinematic + `S2CQuasarPayload`
  hooks for the given stage WITHOUT moving terrain (dry-visual mode: calls the cinematic
  path, not `WorldStageService.setStage`); the message clarifies "visuals only — terrain
  unchanged (use /eclipse stage set for terrain)". P2's VFX replay hooks: §4.2.
- `/dev replay finale`, `/dev replay list` (available sequence ids from `CutscenePaths`).

### 2.12 `/dev reload` (A13)

W1's `DevReload` executes, in order, with per-line ✔/✖ feedback and exception summaries:

| # | Target | Mechanism |
|---|---|---|
| 1 | Six core configs | `EclipseConfig.reload()` (P1's per-world resolution once landed) |
| 2 | Cutscene paths | `CutscenePaths.reload()` |
| 3 | P4 configs (realtime, goals, quests, skills, buffs, awards, offerings, analytics, protection, glitch, recipegate) | P4's **ReloadHooks bridge** — P4 guarantees `/eclipse reload` reaches all P4 configs; W1 calls the same bridge |
| 4 | P5 configs: `xboxevent.json` (§2.13.7), `music.json` (§2.20), `modgate_ids.json` (§2.22) | each loader self-registers a `Runnable` in W1's tiny `DevReloadRegistry` (additive; P4's bridge stays theirs) |
| 5 | Re-sync clients | day state + milestones + cutscene lib (same calls as `/eclipse reload` lines 1317–1324) + stage payloads + client-push re-broadcast (§2.8) |
| 6 | Loot/fog-storm tables | vanilla `/reload` covers datapack loot; feedback line reminds the operator (`/dev reload` does NOT run `/reload` implicitly — too slow mid-event; explicit hint instead) |

Output ends with `Reload: 5 OK, 0 Fehler` (+ hover for per-file paths). Errors never leave
half-applied state: each loader parses to a temp object first, swaps on success (existing
EclipseConfig pattern).

The generated **config reference** (also a Dev Handbook tab + DEV_COMMANDS.md section)
lists every config file, its layer (global vs per-world once P1 lands), and which reload
step covers it.

### 2.13 Xbox-360 Tutorial World Event (B14, B16) — architecture

#### 2.13.1 World acquisition & conversion (research results, verified in /tmp)

| Source | Findings (verified by download/HEAD July 2026) |
|---|---|
| github.com/Fridtjof-DE/Minecraft-Xbox-360-Tutorial-Worlds | Xbox saves + Java conversions at **1.13.2** (DataVersion 1631); zips TU01-02…TU69 but **TU12-13 missing**; ~4 region files/dim, overworld ~13–14 MB raw; **no LICENSE file** |
| theminecraftarchitect.com/tutorial-worlds (TMA) | All 11 tutorial worlds as **"JE Latest"** zips ≈ 12–13 MB each (TU31 21.5 MB). Downloaded TU12: **DataVersion 3839 = 1.20.6**, modern layout (region+entities+poi), unzipped ~18.9 MB, overworld region dir ~15 MB. Direct links embedded in the site's JS bundle (documented in W7's fetch script) |
| curseforge.com console-edition-tutorial-worlds | mirror of similar conversions; kept as fallback source only |

Pipeline (W7, all OFFLINE — done once per world in the dev workspace, never at player
runtime):

1. Fetch TMA "JE Latest" zip → `/tmp` (script `scripts/xbox_fetch.sh`, documents URLs +
   sha256; **worlds are Mojang-copyrighted content — see §5 R9 for the honest legal note**).
2. Upgrade 3839→3955 with the vanilla 1.21.1 dedicated server: `java -jar server.jar
   --forceUpgrade --nogui` on a copy (single-hop DFU; TMA already did 1.13→1.20.6).
3. **Trim**: keep overworld only (`region/`, `entities/`, `poi/`, `level.dat`); console
   worlds are 864×864 blocks → fit in the 2×2 region grid; drop empty outer chunks
   (chunk purge by inhabited-time=0 AND outside |x|,|z| ≤ 27 chunk radius from spawn —
   done by the baker, step 4).
4. **Bake** (`/dev xboxevent bake <world>` — dev-workspace-only command, W7): rewrites
   region palettes `minecraft:<block>` → `eclipse:classic_<block>` from the frozen mapping
   (§2.14), extracts chest contents to a loot manifest (`<world>_loot.json`: pos → item
   list) and blanks the chest block entities, strips non-decorative entities (keeps
   paintings/item frames), purges empty chunks, rewrites `level.dat` spawn from the
   manifest. Runs inside the mod (uses Minecraft's own NBT/region classes — no external
   tooling), against an extracted dir under `run/xboxbake/`.
5. Zip → `src/main/resources/assets/eclipse/xboxworlds/<world>.zip` + entry in
   `xboxworlds/manifest.json` `{worldId, displayName en/de, spawn:[x,y,z], spawnYaw,
   dataVersion, sha256, sizeBytes}`.

**Worlds shipped (3, per requirement "3 selectable")**: `tu1` (the original 2012 tutorial
— maximum nostalgia), `tu12` (primary target per user; Edinburgh-castle era, 12 music-disc
quest), `tu14` (direct successor build for variety). Size budget: **≈ 8–10 MB zipped each
after trim ≈ 25–30 MB added to the jar** (baseline 34 MB → ~60–65 MB with textures+music;
accepted by requirement "ship in jar", risk R2). Planner has NOT committed any binaries;
W7 commits only after the orchestrator signs off on the measured sizes (gate in W7's
acceptance).

#### 2.13.2 Dimensions & installer

- Three **datapack dimensions** following the `limbo.json` precedent:
  `data/eclipse/dimension/xbox_tu1.json`, `xbox_tu12.json`, `xbox_tu14.json`, all type
  `data/eclipse/dimension_type/xbox_classic.json`: `min_y 0, height 256` (converted worlds
  keep 0–255 sections; avoids empty-section bloat), `natural: true`, `bed_works: false`
  (respawn is intercepted anyway; beds just say "you can't sleep now" — avoids explosion
  edge cases), `has_skylight: true`, fixed overworld effects. Generator: void (flat, air,
  `minecraft:the_void` biome) — real terrain comes from the installed region files, void
  backfills the border.
- **`XboxWorldInstaller`** (W9): at `ServerAboutToStartEvent`, for each manifest world —
  if `<world>/dimensions/eclipse/xbox_<id>/region` is absent OR a reset marker file
  (`eclipse/xbox_reset_<id>`) exists: delete the dimension dir, extract the bundled zip,
  verify sha256, drop the marker. Datapack dimensions load no spawn chunks automatically
  and region files open lazily on first chunk read, so pre-tick extraction is safe; because
  handles are cached once a chunk IS read, we never install/reset while the server runs —
  reset is *staged* (`/dev xboxevent reset` writes the marker + announces "applies on next
  restart").

#### 2.13.3 Event state machine (`xboxevent/XboxEventService`, SavedData `eclipse_xbox_event`)

States: `IDLE → ANNOUNCED → OPEN → CLOSING → IDLE`. Persisted: state, `worldId`,
`endsAtEpochMillis`, `portalPos/portalDim`, `participants:Set<UUID>`,
`lockedOut:Map<UUID, instanceId>`, `instanceId:int` (increments per event → lockouts
auto-scope to one event), `rewardBuffId:String`, `rewardMinutes:int`, entry return anchors
`Map<UUID,(dim,pos,yaw)>`.

- `/dev xboxevent start tu12 [minutes=30]`: validates installed region payload → state
  ANNOUNCED → chat broadcast (en+de, clickable "▶ Zum Portal" coordinates hint), portal
  spawns (§2.13.4) → OPEN. Timer = `endsAt = now + minutes`.
- Tick (10t): countdown broadcast (§2.13.5); at T-5m and T-1m warnings; at 0 → CLOSING:
  every player inside gets the exit sequence (keep inventory, §2.13.6), reward granted to
  `participants` via **`TimedBuffApi.start(server, rewardBuffId, rewardMinutes)`** (P4
  froze the Xbox reward call `start("double_skill_xp", 60)` — our default config matches),
  portal despawns, reset marker staged, state IDLE.
- `/dev xboxevent time add|sub|set <dur>` mutates `endsAt` (clamped ≥ now) and re-syncs;
  `stop [now]` = graceful CLOSING (or immediate); `status` dumps state incl. participants
  and lockouts.

#### 2.13.4 Portal lifecycle (P5 owns placement/lifecycle; P2 owns VFX)

Portal = **marker construct, no custom blocks/entities**: an `interaction` entity (3×4)
plus decorative `block_display` frame pieces (reuses W6's DisplayPlacerService API),
tagged `eclipse_xbox_portal`. Default placement: first valid 5×5 flat spot ring-scanned
8–24 blocks from world spawn (outside the sanctum radius, §2.10); override `/dev xboxevent
portal here`; `portal remove` despawns. Collision: service tick checks player AABB
intersects the interaction box → entry sequence. VFX: fires `XboxRiftHooks.onPortalSpawned
(level, pos)` / `onPortalRemoved` — P2 subscribes (rift shader/particles, §4.2); base
fallback = reverse-portal particles + ambient sound loop so the feature works without P2.

Entry sequence (per player): capture return anchor → send P3's
`S2CPortalFxPayload{style:"eclipse:xbox_glitch", holdTicks:30}` (P3-W11's
`PortalTransitionController` renders glitch→fade-black→fade-in and suppresses the vanilla
dim-change screen; contract §4.3) → teleport to manifest spawn (yaw from manifest) →
`participants.add` → title "Tutorial World (TU12) — 2012" + nostalgic music cue (§2.20).
Players who are `lockedOut` with the current `instanceId` bounce with an explanatory
message instead.

#### 2.13.5 Timer overlay (30:00)

Server-authoritative: `S2CXboxTimerPayload{endsAtEpochMillis:long, serverNowEpochMillis:
long, worldId:String, active:boolean}` sent on entry + on any `time` mutation + every 20s
(drift guard) to players **inside** the dimension only. P3 renders the styled overlay
(mm:ss, pulsing under 1:00 — P3 follow-up worker, §4.3); **fallback shipped by W9** so the
feature is complete standalone: a `ServerBossEvent` countdown bar (PhaseScheduler visual
pattern) shown to inside-players — removed automatically when P3's overlay lands (overlay
sends a client ack capability flag in `C2SXboxAckPayload`; server hides the bossbar for
acked clients).

#### 2.13.6 Death, voluntary exit, lockout, return (B16)

- **Death inside**: `LivingDeathEvent` (player, xbox dims) → **cancel** the death: restore
  health to 1.0, clear fire/effects, run the exit sequence (transition payload → teleport
  to return anchor). NO item drop, NO Eclipse life lost — W9 sets a per-player context flag
  consumed by the lives/death pipeline so P4's death handling skips entirely (interface
  §4.4: one boolean query `XboxEventApi.isProtectedDeath(player)`; P4's handler
  short-circuits when true — P4 signs off on the hook point, `DeathFlowHooks` per P3 §5.3
  already centralizes this flow).
- **Voluntary exit**: every entry posts a persistent chat line with clickable
  `[Verlassen / Leave]` → runs `/xboxleave` (perm 0). Confirmation click-through ("Du
  kannst während DIESES Events nicht zurück — wirklich verlassen? [Ja]") → exit sequence +
  `lockedOut[uuid] = instanceId`.
- **Lockout clear**: `/dev xboxevent lockout clear <player|all>`.
- **Timer end**: everyone inside exits with **full inventory kept** (mined classic blocks
  are the loot, req B15), return anchors restored, reward buff granted to all
  `participants` (including earlier voluntary leavers — they participated), configurable
  via `xboxevent.json` / `/dev xboxevent reward set`.
- Edge cases: logout inside → on next login, if event over/closed, exit sequence runs at
  login (anchor persisted); server crash mid-event → SavedData state resumes CLOSING on
  boot if `endsAt` passed.

#### 2.13.7 `config/eclipse/xboxevent.json` (own loader `XboxEventConfig`, registered in DevReloadRegistry)

```json
{
  "defaultMinutes": 30,
  "reward": { "buffId": "double_skill_xp", "minutes": 60 },
  "portal": { "searchMinRadius": 8, "searchMaxRadius": 24 },
  "announceKeys": true,
  "worlds": ["tu1", "tu12", "tu14"]
}
```

### 2.14 CLASSIC BLOCKS (B15)

**Decision: pre-baked conversion** (user-preferred): the shipped region files already
contain `eclipse:classic_*` palette entries (bake step §2.13.1-4). No runtime mapping, no
chunk rewriting at play time, and mined drops are automatically the classic items.

- **Block list generation** (W7 → W8 hand-off): the baker's palette scan across the three
  trimmed worlds emits `docs/plans_v3/xbox_palette.json` (distinct vanilla ids + counts +
  properties used). Expected ≈ **80–150 ids** (1.2.1-era palette). W8 converts this into
  committed code: `classicblocks/ClassicBlockList.java` (id → shape kind → texture keys) —
  registries freeze before datapacks load, so the list is code, not data. Until W7's scan
  lands, W8 starts from the provisional 120-id list of the 1.2.1 palette (stone/dirt/
  grass/logs×2/planks×2/wool×16/ores/glass/stairs/slabs/doors/rails/crops/leaves/etc.) and
  reconciles — acceptance requires zero unmapped palette entries at bake time (baker fails
  loudly listing gaps).
- **Registration** (`classicblocks/ClassicBlocks` + `ClassicBlockItems`, own
  DeferredRegisters): programmatic loop over `ClassicBlockList`. Shape kinds map to vanilla
  base classes WITHOUT block entities or GUIs: `SIMPLE` (Block), `PILLAR` (RotatedPillar),
  `SLAB/STAIR/FENCE/PANE/LADDER/RAIL(deco, no cart physics needed — plain deco block with
  rail shape)/DOOR/TRAPDOOR` (doors/trapdoors OPEN by right-click — allowed, no GUI),
  `LEAVES` (no decay), `CROP_STATIC` (fixed age visual, no growth), `CHEST_SOLID` (full
  cube chest-look, no container — loot via manifest below), `FLUID_SOLID` (water/lava as
  non-flowing textured blocks — the tutorial worlds' water becomes solid glassy deco;
  swimming not needed inside a 30-min sightseeing event; ALTERNATIVE if P1 objects:
  keep vanilla water in bake mapping exceptions).
  Properties: `strength(0.8f)`, correct sound types, `mineable/pickaxe|axe|shovel` tags
  only. **No recipes reference them and they satisfy no vanilla ingredient**: separate
  namespace ids + never added to any vanilla/common item tag ⇒ nothing to "block" —
  acceptance test proves `classic_oak_planks` fits no crafting recipe.
- **Names**: en `Classic — Oak Planks`, de `Klassisch — Eichenholzbretter` — generated into
  the langdrop by a datagen-time provider from the block list + per-id overrides.
- **Chest loot**: baker blanks chest BEs and records contents in
  `data/eclipse/xboxworlds/<world>_loot.json` (pos → items, incl. the TU12 music discs).
  `ClassicChestBlock` break inside the event dim → `XboxEventService.lootFor(world, pos)`
  spills the recorded stack list (classic-mapped where applicable, vanilla discs stay
  vanilla = playable souvenirs). Outside event dims it drops itself only.
- **Datagen** (first real datagen in repo, W8): `runData` providers for blockstates/models/
  item models for all classic blocks (cube_all/pillar/stairs/slab/door/trapdoor/cross
  templates), lang provider, tag provider. Output committed under `src/generated/resources`
  (gradle already excludes `.cache`).
- **Textures**: bundled under `assets/eclipse/textures/block/classic/…` sourced from
  Modrinth pack **"Minecraft: Classic Edition" — license verified MIT via Modrinth API**.
  W8 must (a) spot-verify the pack is a faithful *recreation* (16×16, author-made) — it is
  distributed as such under MIT; (b) copy only the ~150 needed textures; (c) CREDIT pack +
  author in `CREDITS.md` + in-game credits (§2.20); (d) any texture the pack lacks falls
  back to the repo's existing placeholder-programmer-art generator (documented per-texture
  in the worker's report). Alternative pack "Golden Days" exists but its license must be
  re-verified before use — NOT approved by this plan.
- **Visibility**: classic items sit in `#eclipse:emi_hidden` (P3's always-hidden EMI tag —
  added via W11 integration, §3 shared-files rule) — they are souvenirs with no recipes, so
  hiding avoids EMI spoiler noise; they DO appear in a dedicated creative tab
  `eclipse.classic` (ops/testing convenience; tab registered by W8).

### 2.15 Jar-in-jar bundling verdict per mod + licenses (C17)

License audit (each verified against Modrinth API `license` field and/or the project's
GitHub LICENSE — evidence log Appendix B):

| Mod | License (verified) | jarJar verdict | Notes |
|---|---|---|---|
| EMI | MIT | **BUNDLE** (jarJar) | pin `1.1.22+1.21.1` neoforge (P3-W11 adds the compileOnly API dep — W10 adds the jarJar runtime line; §3 build.gradle sequencing) |
| Mouse Tweaks | BSD-3 | **BUNDLE** | client-only; nested jar keeps its own dist metadata |
| GeckoLib (P6 dep) | MIT | **BUNDLE** | designed for embedding; pin latest 4.x for 1.21.1 (4.9.2 at research time — W10 re-verifies); jarJar dedups if a folder copy also exists |
| Create 6.0.10 | Repo LICENSE **MIT**, but Create 6 art/assets are publicly marked restricted (ARR assets) | **NO — PackBootstrap** | full-jar redistribution redistributes ARR assets; not cleared without author permission |
| Create Crafts & Additions | MIT | NO (external) | depends on Create → travels with it |
| Farmer's Delight | MIT (GitHub LICENSE) | NO (external, could be bundled) | technically bundleable; kept external for pack consistency + jar size; revisit if single-jar becomes hard requirement for it |
| Supplementaries | Custom — public redistribution NOT allowed | **NO — blocker** | explicit no-redistribution |
| Moonlight lib | LGPL w/ added clauses | NO (external) | only needed by Supplementaries |
| Sophisticated Backpacks + Core | ARR | **NO — blocker** | |
| Simple Voice Chat | ARR (custom) | **NO — blocker** | |
| Create Aeronautics bundle (simulated/offroad) | "Simulated Project License" (custom, no redistribution); currently a privately bundled dev build **not on Modrinth CDN** | **NO — blocker**; also not bootstrap-downloadable | stays folder-distributed (server pack); client join without it is blocked by modcheck with a download hint URL from config |
| Sable | PolyForm Shield 1.0.0 | NO (external) | redistribution w/ notice technically permitted, but noncompete terms + mixin-heavy → keep external |
| Sodium / Iris (client extras) | LGPL-3 / LGPL-3 | NO (optional client extras) | never required by modcheck (§2.16 allowlist marks optional) |
| Photon | identity unresolved (SixthSurge shaderpack vs LowDragMC lib) — P2 confirms | NO | if shaderpack: it is not a mod; distribute via `shaderpacks/` folder + Iris config, license permitting (P2 verifies) |
| Axiom | ARR, Fabric-only on 1.21.1 | **N/A** | §2.7 |

**Honest verdict on "ONE jar" (user asked)**: full single-jar bundling is **legally blocked**
by Create (assets), Supplementaries, Sophisticated, Voice Chat, Aeronautics. No technical
trick changes that. Delivered compromise (W10):

1. **jarJar** EMI + Mouse Tweaks + GeckoLib into `eclipse.jar` (all-permissive; adds ~8–12
   MB; `build.gradle` `jarJar(implementation("maven.modrinth:<slug>:<version>"))` with the
   Modrinth maven repo, exactly like the Veil precedent; version-range pins exact).
2. **PackBootstrap** (`bootstrap/PackBootstrap.java`, client): on first launch, if
   configured external mods are missing from `mods/`, show a consent screen (en+de) and
   download the EXACT pinned versions **from Modrinth's official CDN** (urls+sha512 from
   `bootstrap.json` baked into the jar) into `mods/`, then prompt restart. Downloading from
   the official source is distribution by Modrinth, not by us → no license conflict.
   Aeronautics (not on Modrinth) gets a configurable direct URL (event's own hosting,
   authorized by the private-server context) or remains manual. Server never bootstraps
   (dedicated servers keep the curated `run/mods`).
3. Mod-menu appearance: bundled trio shows up as nested deps of Eclipse; externals show
   normally — the "only ours in the menu" wish is only achievable for the jarJar'd subset;
   documented as such (risk R3).

### 2.16 Mod checker — exact-set connection screening (C18)

Existing: `admin/AntiCheatCheck` + `C2SModlistPayload` = **blocklist** substring match +
timeout kick. W10 extends `anticheat.json`:

```json
{
  "modlistMode": "allowlist",
  "blockedModIdSubstrings": ["xray", "..."],
  "allowedMods": { "eclipse": "2.1.0", "create": "*", "minecraft": "*", "neoforge": "*", "...": "*" },
  "requiredMods": ["eclipse", "create", "farmersdelight", "voicechat", "..."],
  "optionalMods": ["sodium", "iris", "emi", "mousetweaks"],
  "downloadHintUrl": "https://…"
}
```

Handler in allowlist mode: `missing = required − reported`, `extra = reported − allowed −
optional`; nonempty → disconnect with a localized, itemized message + `downloadHintUrl`.
Version pins optional (`*` = any). Blocklist substrings still apply in both modes
(belt-and-braces). **`/dev modcheck snapshot`** captures the running server's own modlist
(incl. jarJar'd ids + libraries — this is why snapshot-from-reality beats hand-listing)
into `allowedMods`/`requiredMods` (server-side mods flagged interactively via a follow-up
clickable list are moved to server-only = not required from clients), writes
`anticheat.json`, hot-applies. `mode`, `status`, `test <player>` (dry-run evaluation
printout) complete the surface.

### 2.17 Additional unlockable content mods (C19) — proposal

Verified 1.21.1-NeoForge availability + license via Modrinth API:

| Mod | License | Fit | Proposed gate |
|---|---|---|---|
| End's Delight | MIT | FD addon; late-game End food content | namespace `ends_delight` → key `farmersdelight`-tier, unlock day 12 (End arc) |
| Create Confectionery | MIT | small Create sweets addon | namespace `create_confectionery` → unlock day 4 with Create-early content |
| Create Connected | AGPL-3.0 | QoL Create linkage parts | namespace `createconnected` → unlock day 3 alongside `create`; folder-distributed (AGPL: keep as separate jar = mere aggregation, source link in CREDITS) |
| (optional 4th) Create Goggles | verify at impl | cosmetic | only if verification passes |

Rejected during research (no 1.21.1 NeoForge build or dead slug): Steam 'n' Rails,
Dungeons Delight, My Nether's Delight, Create Railways Navigator, Garnished. Integration =
config only: add namespaces to `modgate.json` + keys into day plans (P4's B3 owns
`days.json` content rebalance — hand-off note §4.4) + PackBootstrap pins + allowlist
entries + README compat rows. **No code work** — W10 ships config/docs; the mods
themselves are NOT committed to `run/mods` by workers (orchestrator installs after
approving the proposal).

### 2.18 EMI runtime hiding — backend hooks (C20)

P3-W11 **owns the EMI plugin** (`client/emi/EclipseEmiPlugin` + `EmiReindexer` reflection
reload — EMI has no official live-hide API, verified emi#494/#1207; P3 §3.12). P5's
share (kept deliberately small to avoid double ownership):

- W10 bundles/pins the exact EMI build P3 codes against (`1.1.22+1.21.1`).
- Dev/admin items (Display Wand, any W-created dev item) → `#eclipse:emi_hidden` additions
  via W11 integration (single owner of that tag file's P5-side edits; P3 seeds it).
- Classic items policy §2.14 (always hidden).
- Server side already re-broadcasts unlock state on day change/reload (`S2CDayStatePayload`)
  — P3's plugin listens to its client cache; no new P5 payload needed. If P3 requests a
  dedicated key-diff payload later, it belongs to P3's ledger (§4.3).

### 2.19 Compat test plan — boot matrix (C21)

Checklist the orchestrator runs after each merged wave (scripted where possible via the
existing RCON headless flow from `AGENTS.md`):

| # | Configuration | Pass criteria |
|---|---|---|
| M1 | Dedicated server, full `run/mods`, fresh world | boots to "Done"; `/eclipse status` OK; no mixin errors in log |
| M2 | Server + `/dev xboxevent start tu12` (RCON) | portal spawns; installer extracted dims at boot; timer bossbar visible in logs (`status`) |
| M3 | Client: eclipse.jar ONLY (jarJar trio inside), vanilla launcher | boots to title; EMI + MouseTweaks + GeckoLib listed as nested; PackBootstrap consent screen appears |
| M4 | Client: full pack, NO sodium/iris | joins M1 server; modcheck passes |
| M5 | Client: full pack + sodium+iris | joins; shaders on; portal transition renders (P2/P3 fallback OK) |
| M6 | Client: full pack minus EMI, minus MouseTweaks | joins (optionalMods); no classloading errors (`isLoaded` guards) |
| M7 | Client with an extra disallowed mod (e.g. litematica) | disconnect with itemized allowlist message |
| M8 | Singleplayer (LAN): world A edit configs → create world B | world B unaffected (validates P1 layering once landed) |
| M9 | `runData` | datagen completes, `git status` clean after regen (idempotent) |
| M10 | GameTest suite (`runGameTestServer`) | all P5 gametests pass (stage backup, xbox state machine, modcheck evaluator) |

### 2.20 Music & credits (D22)

`/workspace/requestssongs.md` requests a **Treblo** API key (AI music generation service,
V3 "Melodia" model; may arrive as secret `TREBLO_API_KEY`). Design works either way:

- **`client/music/MusicManager`** (W11): client-side cue engine. Cues (`MusicCues` enum →
  sound event + trigger): `title` (title-screen override via `Screen` open event +
  `SoundManager` — subtle: must duck vanilla `menu` music by intercepting
  `Minecraft.getMusicManager` situational music; FABLE-level care), `limbo_ambience`
  (dimension enter, loop), `boss_herald`/`boss_ferryman` (P4 fight-state payload listen),
  `expansion_stinger` (growth start payload), `finale`, `xbox_nostalgia` (xbox dims,
  §2.13.4). Category: vanilla `MUSIC` (fixed enum — no custom categories in 1.21.1) +
  client config volume multiplier `eclipseMusicVolume`. Sound events in NEW registrar
  `sounds/EclipseMusicSounds` (own DeferredRegister — `registry/EclipseSounds.java` stays
  untouched/P2-P4 shared). Config `music.json` {cue → enabled, volume, trackId} via
  DevReloadRegistry; `/dev music play|stop|list` for testing.
- **Pipeline A (Treblo key present)**: `scripts/treblo_fetch.py` — reads prompt list (the
  15 briefs from requestssongs.md), calls the API, writes OGG; then
  `scripts/music_normalize.sh` (ffmpeg loudnorm to −16 LUFS, 112 kbps stereo OGG). Credit
  line "Music generated with Treblo (Melodia v3)" per their attribution terms.
- **Pipeline B (no key — royalty-free)**: candidate sources with verified terms:
  **FreePD** (CC0/public domain — bundling OK, credit optional), **Pixabay Music**
  (Pixabay Content License: free commercial use incl. games, no attribution required,
  no standalone resale), **incompetech** (CC-BY 4.0 — bundling OK WITH attribution).
  W11 picks ≤8 tracks, logs each (title, author, source URL, license) in `CREDITS.md`.
- **Credits** (in-game + repo): `CREDITS.md` sections — music, classic textures
  ("Minecraft: Classic Edition" resource pack, MIT, author + Modrinth link), tutorial
  worlds ("worlds by Mojang/4J Studios; Java conversions courtesy of
  theminecraftarchitect.com" + Fridtjof-DE repo), bundled mods + licenses (EMI/Mouse
  Tweaks/GeckoLib/Veil), content mod licenses (AGPL source links). In-game:
  `client/CreditsScreen` (scrollable, parses a bundled credits JSON generated from
  CREDITS.md at build… simpler: bundled `assets/eclipse/credits.json` maintained alongside;
  acceptance checks both list the same entries), opened from the title screen ("Credits"
  button placement coordinated with P3's menu worker §4.3) and via `/dev credits`.

### 2.21 Anti-XRay verdict (D23) — honest assessment

**Do not ship engine-mode-1 style obfuscation.** Reasons: (a) the disc world's ores are
placed by deterministic worldgen from a compiled seed — anyone can regenerate the disc
offline, so packet obfuscation provides weak protection here; (b) chunk-packet rewriting
on NeoForge 1.21.1 has no maintained drop-in and a naive implementation costs significant
per-chunk-send CPU + breaks with sodium client optimizations expectations. Existing
mitigation already in place: anticheat blocklist rejects known xray client mods (§1.4).

**Scoped alternative (OPTIONAL worker W12, default OFF config)**: obfuscate ONLY
diamond/ancient-debris-tier blocks below y=0 in **not-air-adjacent** positions at
chunk-send time (`ChunkWatchEvent.Sent`-adjacent hook: copy section palette, swap hidden
ores → deepslate, send copy; reveal via block-update when a neighbor becomes air). Budget:
touches only sections y<0, palette-level swap ≈ O(hidden ores) per send. Ship only if the
orchestrator wants it after M1-M5 perf baselines; otherwise the verdict stands as
"documented, deliberately not implemented".

### 2.22 Aeronautics deeper integration (D24)

- **ID-level gating extension**: today ModGate gates whole namespaces. Add OPTIONAL
  `config/eclipse/modgate_ids.json` (`{"gatedIds": {"aeronautics:balloon": "aeronautics_civil",
  "aeronautics:engine_*": "aeronautics_industrial"}}`, glob on path) loaded by NEW
  `progression/ModGateIds.java` (W10 — does NOT touch `EclipseConfig.java` (P1's) or the
  `ModGate` namespace fast path; `ModGate.isItemLocked` gains one delegating call, W10 owns
  that single edit — verified no other planner claims `ModGate.java`).
- **Content hooks** (hand-off to P4-B3 who owns `days.json`/`quests.json` content): day 5 =
  `aeronautics_civil` key (balloons), day 8 = `aeronautics_industrial` (engines), side
  quest "First Flight" (fly an airship 100m — trigger via aeronautics stats if exposed,
  else manual goal). P5 provides the keys + gating; quest wiring is P4 content.

---

## 3. WORKER PACKAGES

Conventions (ALL workers):

- **Lang**: no worker edits `assets/eclipse/lang/*.json`. Each drops
  `docs/plans_v3/langdrop/P5-W<i>.json` = `{"en_us": {...}, "de_de": {...}}`, complete for
  every key it introduces. W11 merges into the real lang files (folder already exists;
  P4 uses the same convention).
- **Wiring**: no worker edits `EclipseMod.java` or `network/EclipsePayloads.java`. Needed
  registration lines go into `docs/plans_v3/wiring/P5-W<i>.md`; W11 applies them all in the
  integration pass. Event listeners use `@EventBusSubscriber` (no wiring needed);
  DeferredRegisters DO need a wiring line.
- **Docs registry**: every new `/dev` leaf registers a `DevCommandDoc` (§2.1) — acceptance
  checked via `/dev docs export` diff.
- **Permissions**: root `/dev` at 2; leaves marked [3] in §2.1 add their own `requires`.
- **Strings**: en+de for every player/operator-visible string.
- **No edits ever** to: `admin/EclipseCommands.java`, `core/state/EclipseWorldState.java`,
  `core/config/EclipseConfig.java`, `devtools/PhaseScheduler.java`,
  `registry/EclipseSounds.java`, `worldgen/stage/WorldStageService.java` (P1/P4-owned or
  frozen). Verified against P3/P4 file matrices — zero overlaps.

### P5-W1 — Dev command core: registry, `/dev` root, reload, docs exporter (SOL, M)

**Goal**: §2.1 + §2.12 complete; `/dev`, `/dev help`, `/dev reload`, `/dev docs export`
working; registry pre-seeded with docs for the ENTIRE existing `/eclipse` tree (legacy
entries, §1.1 table) so the handbook is complete from day one.
**Files (new)**: `devtools/dev/DevCommandRegistry.java`, `DevCommandDoc.java`,
`DevCategory.java`, `DevRoot.java`, `DevReload.java`, `DevReloadRegistry.java`,
`DevDocsExporter.java`, `devtools/dev/LegacyCommandDocs.java`; langdrop `P5-W1.json`;
wiring `P5-W1.md`.
**Outline**: records/enums → registry (ordered, freeze after server start) → root command
(`RegisterCommandsEvent` subscriber) → reload orchestration (§2.12 table, temp-parse-swap
feedback) → markdown generator (category sections + config reference + legacy marker) →
legacy docs seeding.
**Acceptance**: `/dev help` paginates and click-runs; `/dev reload` prints ✔ per config and
✖ with message on an intentionally broken JSON (then restores); `/dev docs export` writes
deterministic markdown (two runs = identical bytes); registry rejects duplicate ids;
gametest: registry visibleTo filters perm-3 entries for a perm-2 source.

### P5-W2 — Dev Handbook GUI (FABLE, M) — after W1

**Goal**: §2.2 — searchable, categorized, clickable dev handbook screen.
**Files (new)**: `devtools/dev/handbook/DevHandbookScreen.java`,
`DevHandbookPayloads.java`, `DevHandbookClient.java`; langdrop `P5-W2.json`; wiring
`P5-W2.md`.
**Outline**: payload pair + own registrar → screen (category rail, search, entry cards,
danger badges, RUN confirm dialog for DESTRUCTIVE, SUGGEST chat prefill) → config-ref tab →
server-side revalidation of `C2SDevRunCommandPayload` (§2.2).
**Acceptance**: `/dev` opens GUI; search "buff" filters; clicking RUN on a SAFE entry
executes and toasts the result; DESTRUCTIVE asks; a perm-2 client never receives perm-3
entries (packet inspection in gametest/log); screen usable at 1× GUI scale 1080p and 4×.

### P5-W3 — Timer & scheduler UX commands (SOL, S) — after P4-B1

**Goal**: §2.3 — `/dev timer` suite on `RealtimeDayService`.
**Files (new)**: `devtools/dev/DevTimerCommands.java`; langdrop `P5-W3.json`.
**Outline**: subtree registration → bridge calls (arm/disarm/pause/resume/add/sub/set/
preset/status) → feedback formatting (absolute+relative, zone-aware) → registry docs.
**Acceptance**: pause freezes remaining (verify via two status calls 5s apart); resume
restores boundary; `set 18:30` resolves today/tomorrow correctly across midnight (unit
test with fixed clock); presets suggest; every mutation broadcasts the clock payload (P3
spool animates — log assert); INFO audit line per mutation.

### P5-W4 — P4-bridge commands: buffs, quests, unlocks, XP, voice, viewdistance, stats (SOL, L) — after P4 wave B

**Goal**: §2.4, §2.5, §2.8, §2.9 — the full bridge command set + ConfigEditor allowlist
extension + view-distance push.
**Files (new)**: `devtools/dev/DevBuffCommands.java`, `DevQuestCommands.java`,
`DevPlayerCommands.java` (xp/multiplier/skill/voice/locale/deathflow),
`DevStatsCommands.java`, `DevViewDistance.java` (+payload registrar, SavedData
`eclipse_client_push`); **edits**: `devtools/ConfigEditor.java`,
`devtools/GoalEditorScreen.java`, `network/C2SConfigEditPayload.java` (file-allowlist +
validate hook — assigned to P5 by P4 §4); langdrop `P5-W4.json`; wiring `P5-W4.md`.
**Outline**: per §2.4/2.5 syntax; suggestion providers (buff ids, unlock keys, metrics);
secret-multiplier output discipline (operator-only); view-distance payload + login re-push
+ ack bookkeeping; ConfigEditor: add `goals.json`/`quests.json` via
`GoalConfig.validateAndNormalize`.
**Acceptance**: `/dev buff start doublexp 30m` → P4 bossbar appears, `list` shows
remaining; `stop all` clears; `/dev quest complete` fires P4 completion side effects
(announce) and `revoke` un-completes (gametest w/ mock player); `/dev xp multiplier set`
never appears in other players' chat/logs at INFO; `/dev viewdistance set 6` visibly
reduces a test client's render distance and `reset` restores the user's original;
ConfigEditor rejects an invalid goals.json edit with the validator's message.

### P5-W5 — Stage auto-backup, retention, backup browser (SOL, M)

**Goal**: §2.6 — BUG-A fixed; every destructive stage apply is revertible.
**Files (new)**: `devtools/StageBackups.java`, `devtools/dev/DevStageCommands.java`;
**edits**: `devtools/StageIO.java` (pre-apply hook + revert error hint ONLY); langdrop
`P5-W5.json`.
**Outline**: backup serializer reuse → hook load() + GrowthStartListener → timestamped
files + sidecar → retention prune → commands (list/now/restore/prune) → gametest.
**Acceptance**: gametests — fresh world, `stage load 3` on never-snapshotted terrain
creates `backups/*` BEFORE any block changes (assert file exists when first section
written); restore round-trips a hand-placed marker block; retention keeps exactly N;
`stagesDir` resolves under the active world root; `revert` after a first-ever load now
succeeds (was BUG-A).

### P5-W6 — Display placer, spawn tools, replay commands (SOL, M)

**Goal**: §2.7, §2.10, §2.11.
**Files (new)**: `devtools/display/DisplayPlacerService.java`, `DisplayAnimator.java`,
`DevToolItems.java`, `DevDisplayCommands.java`, `C2SDisplayEditPayload.java` (+registrar),
`devtools/dev/DevSpawnCommands.java`, `devtools/ReplayService.java`,
`DevReplayCommands.java`, SavedData `eclipse_spawn_tuning`; **edits**:
`worldgen/structure/SanctumProtection.java` (dynamic radius §2.10); langdrop `P5-W6.json`;
wiring `P5-W6.md` (DevToolItems register + emi_hidden additions for the wand).
**Outline**: per §2.7/2.10/2.11.
**Acceptance**: placed display survives restart and keeps spinning/bobbing; wand edits
round-trip through server validation; `/dev spawn radius 24` immediately blocks a non-op
break at r=20 (gametest); preview ring particles visible to ops only; `/dev replay intro`
re-plays and the revert click restores flags (state diff asserted); everything documented
in the registry.

### P5-W7 — Xbox world pipeline: fetch, upgrade, trim, bake, manifests (FABLE, L)

**Goal**: §2.13.1 pipeline + §2.14 palette scan; three baked, trimmed world payloads +
manifest + loot manifests + palette report. **Commit gate**: post measured zip sizes in the
PR description; orchestrator approves before the binaries land (target ≤ 30 MB total).
**Files (new)**: `devtools/xbox/XboxWorldBaker.java` (`/dev xboxevent bake`, dev-workspace
guard: refuses outside a gradle run dir), `devtools/xbox/RegionPaletteScanner.java`,
`scripts/xbox_fetch.sh`, `scripts/XBOX_WORLD_PREP.md` (step-by-step incl. `--forceUpgrade`),
`assets/eclipse/xboxworlds/manifest.json` (+ 3 world zips after gate),
`data/eclipse/xboxworlds/tu1_loot.json` etc., `docs/plans_v3/xbox_palette.json`; langdrop
`P5-W7.json`.
**Outline**: fetch script (TMA URLs + sha256, /tmp staging) → vanilla-server upgrade run →
baker: palette remap (fail-loud on unmapped ids), chest-loot extraction + BE blanking,
entity strip (keep paintings/frames), empty-chunk purge, spawn rewrite → scanner report →
zips + manifest.
**Acceptance**: bake of TU12 completes with ZERO unmapped palette entries against W8's
list (or emits the exact gap list for W8); baked world opens in a dev client: terrain
renders as classic blocks at spawn, no console errors within 5 min of flight; loot json
contains the TU12 music-disc chest; re-bake is idempotent (same sha256); zip sizes
reported. DataVersion of shipped worlds == 3955.

### P5-W8 — Classic blocks: registry, datagen, textures, tags (FABLE, L)

**Goal**: §2.14 complete — ~80–150 `eclipse:classic_*` blocks/items, models, lang, tags,
credits, creative tab.
**Files (new)**: `classicblocks/ClassicBlocks.java`, `ClassicBlockItems.java`,
`ClassicBlockList.java`, `ClassicBlockShapes.java`, `ClassicChestBlock.java`,
`ClassicCreativeTab.java`, `datagen/EclipseDataGen.java` + model/lang/tag providers,
textures `assets/eclipse/textures/block/classic/**`, generated resources; langdrop
`P5-W8.json` (incl. all block names en+de); wiring `P5-W8.md` (3 register lines +
emi_hidden additions + CREDITS entry text).
**Outline**: list from provisional 1.2.1 palette → reconcile with W7's
`xbox_palette.json` → registration loop by shape kind → behaviors (no BEs, doors open,
leaves no-decay, chest solid) → datagen providers → texture import from the MIT pack
(per-texture provenance table in PR) → mineable tags only → tab.
**Acceptance**: `runData` idempotent; every list entry has blockstate+model+item model+
en/de name (datagen asserts); `classic_oak_planks` matches NO recipe (gametest crafts all
2×2/3×3 vanilla wood recipes with it → zero matches); door opens without GUI; chest is a
plain solid block outside event dims; textures folder contains ONLY referenced files;
CREDITS text drafted.

### P5-W9 — Xbox event runtime: dimensions, installer, service, portal, flow (FABLE, L) — after W7 (zips) & W8 (blocks); compiles with placeholders before

**Goal**: §2.13.2–2.13.7 + `/xboxleave` — the full event, playable end-to-end with the
bossbar-fallback timer and base portal FX.
**Files (new)**: `xboxevent/XboxEventService.java`, `XboxEventState.java`,
`XboxWorldInstaller.java`, `XboxPortal.java`, `XboxEventConfig.java`,
`XboxEventApi.java` (`isProtectedDeath` etc.), `XboxPayloads.java`
(`S2CXboxTimerPayload`, `C2SXboxAckPayload`), `XboxRiftHooks.java` (P2 hook interface),
`devtools/dev/DevXboxCommands.java`, `XboxLeaveCommand.java`,
`data/eclipse/dimension/xbox_tu{1,12,14}.json`,
`data/eclipse/dimension_type/xbox_classic.json`; langdrop `P5-W9.json`; wiring `P5-W9.md`.
**Outline**: dims/type JSONs → installer (extract-if-absent + reset markers + sha256) →
SavedData state machine → portal spawn/scan/collision → entry/exit sequences
(S2CPortalFxPayload style `eclipse:xbox_glitch`; return anchors) → death intercept →
`/xboxleave` + lockouts → timer + payloads + bossbar fallback → reward via
`TimedBuffApi.start` → dev commands → config.
**Acceptance**: gametests — state machine transitions incl. crash-resume (fake SavedData
with past endsAt boots into CLOSING); lockout blocks re-entry this instance, clears next
instance; death inside restores at anchor with identical inventory/health/Eclipse-lives
(assert vs snapshot); manual E2E on a dev client: start tu12 → walk through portal →
transition plays (no vanilla dim screen) → 30:00 bossbar counts → mine a classic block →
`/xboxleave` → cannot re-enter → `time set 5s` → everyone returned with inventory →
reward buff bar appears. Installer never runs while dimension chunks are loaded.

### P5-W10 — Bundling, PackBootstrap, modcheck allowlist, gatedIds (FABLE, L) — build.gradle AFTER P3-W11 merges

**Goal**: §2.15, §2.16, §2.17 (config/docs), §2.22 (gating extension).
**Files (new)**: `bootstrap/PackBootstrap.java`, `BootstrapScreen.java`,
`assets/eclipse/bootstrap.json` (pins+sha512), `progression/ModGateIds.java`,
`devtools/dev/DevModcheckCommands.java`, `docs/BUNDLING.md` (license table §2.15 verbatim +
verdicts); **edits**: `build.gradle` (jarJar EMI/MouseTweaks/GeckoLib + Modrinth maven —
sole P5 owner; rebase over P3-W11's EMI dep lines), `admin/AntiCheatCheck.java` (allowlist
mode), `progression/ModGate.java` (single delegating call §2.22),
`src/main/resources/META-INF/neoforge.mods.toml` template if nested-jar metadata requires
(document in PR); config: `run/config/eclipse/anticheat.json` (new schema example),
`modgate.json` (+3 namespaces §2.17), `modgate_ids.json` (new); langdrop `P5-W10.json`;
wiring `P5-W10.md`.
**Outline**: jarJar deps (exact pins) → boot verify nested mods load (M3) → PackBootstrap
(consent screen, download+sha512, restart prompt, server-side no-op) → allowlist evaluator
+ snapshot command → ModGateIds glob matcher + ModGate delegation → docs.
**Acceptance**: M3/M6/M7 matrix rows pass locally; `jarJar` build produces one jar whose
nested EMI/MouseTweaks/GeckoLib load on client AND GeckoLib on server; snapshot command
regenerates an allowlist that the running server itself passes; `modgate_ids` gates
`aeronautics:*` test id by key while namespace fast path is unchanged (gametest);
bootstrap skips cleanly when `mods/` already complete; BUNDLING.md lists every §2.15 row.

### P5-W11 — Music, credits, docs commit, integration merge (FABLE, L) — LAST P5 wave

**Goal**: §2.20 + integration duties: merge all langdrops into real lang files, apply all
wiring notes to `EclipseMod.java`, add P5 entries to `#eclipse:emi_hidden`, run
`/dev docs export` and commit `docs/DEV_COMMANDS.md`, `CREDITS.md`.
**Files (new)**: `client/music/MusicManager.java`, `MusicCues.java`,
`sounds/EclipseMusicSounds.java`, `MusicConfig.java`, `client/CreditsScreen.java`,
`scripts/treblo_fetch.py`, `scripts/music_normalize.sh`, `CREDITS.md`,
`assets/eclipse/credits.json`, OGG assets `assets/eclipse/sounds/music/**`,
`sounds.json` additions (music section); **edits (integration-only)**: `EclipseMod.java`
(apply wiring ledgers), `assets/eclipse/lang/en_us.json` + `de_de.json` (merge langdrops),
`data/eclipse/tags/item/emi_hidden.json` (P5 additions; file created by P3-W11 — if not
yet merged, create it identically), `docs/DEV_COMMANDS.md` (generated); langdrop merge
report in PR.
**Outline**: sound registrar + sounds.json → MusicManager cues incl. title override
(FABLE care: duck vanilla menu music, never double-play, respect volume slider) → config +
reload hook → credits screen + title button (coordinate P3 menu worker — if their menu
rework already merged, add via their extension point per §4.3) → pipeline scripts →
track sourcing (A or B per key availability) → integration merge → docs export commit.
**Acceptance**: title theme plays once at menu, stops on world join; limbo/xbox cues
trigger on dimension change and stop on exit; `/dev music play finale` works; volume
multiplier 0 silences all cues; CREDITS.md and credits.json enumerate identical entries
incl. classic-texture pack (MIT) + world sources + every bundled mod; lang files contain
every langdrop key (script-verified: zero missing, zero raw keys on screen in a click-through
of all P5 GUIs); `docs/DEV_COMMANDS.md` regenerates byte-identical.

### P5-W12 — OPTIONAL (deferred): scoped anti-xray (FABLE, M) — only on orchestrator green-light

**Goal**: §2.21 alternative — palette-swap obfuscation of diamond/debris below y0,
config default OFF, perf-budgeted.
**Files (new)**: `antixray/OreObfuscator.java`, `antixray/AntiXrayConfig.java`; langdrop
`P5-W12.json`.
**Acceptance**: with flag on, a spectating client shows deepslate where unexposed diamonds
are until mined adjacent-open (manual + packet test); MSPT delta < 0.5 ms at 10 chunks/s
send rate on the reference world (measured, logged); flag off = zero code in hot path.

### Ownership matrix (conflict proof)

| Shared-risk file | Owner | Everyone else |
|---|---|---|
| `build.gradle` | W10 (jarJar) — sequenced after P3-W11 (EMI dep) | read-only |
| `EclipseMod.java`, `lang/*.json`, `emi_hidden.json`, `docs/DEV_COMMANDS.md` | W11 (integration) | wiring/langdrop notes only |
| `devtools/StageIO.java` | W5 | — |
| `devtools/ConfigEditor.java`, `GoalEditorScreen.java`, `C2SConfigEditPayload.java` | W4 | — |
| `worldgen/structure/SanctumProtection.java` | W6 | — |
| `admin/AntiCheatCheck.java`, `progression/ModGate.java` | W10 | — |
| `admin/EclipseCommands.java`, `EclipseWorldState.java`, `EclipseConfig.java`, `PhaseScheduler.java`, `EclipseSounds.java`, `WorldStageService.java`, `EclipsePayloads.java` | NOBODY in P5 | P1/P4 own per their plans |

Waves: **A** = W1, W5, W6, W7 (+W10 minus build.gradle if P3-W11 unmerged); **B** = W2,
W8, W9, W3 (needs P4-B1), W4 (needs P4 wave B), W10 build.gradle part; **C** = W11
(+W12 if approved). Models: SOL = W1, W3, W4, W5, W6; FABLE = W2, W7, W8, W9, W10, W11,
W12. Sizes: S=W3; M=W1, W2, W5, W6, W12; L=W4, W7, W8, W9, W10, W11.

---

## 4. INTERFACES TO OTHER PLANNERS

### 4.1 P1 (core/config, worldgen)

- **NEEDS from P1 (BUG-B fix, §1.2)**: per-save config layering — `<world>/eclipse/config/
  *.json` overlay over global `config/eclipse/`; `EclipseConfig.reload(MinecraftServer)`
  re-resolved on `ServerAboutToStartEvent`; editors (`ConfigEditor`,
  `setNamespaceGated`, cutscene saves) write the WORLD layer; static caches (incl.
  StageRadii-derived values) reset on server stop. Path helper API P5 consumes:
  `EclipseConfigPaths.worldConfigDir(server)`. P5 fallback if P1 slips: W5's backups still
  fix BUG-A; the leak remains documented in DEV_COMMANDS ("config edits are currently
  GLOBAL across saves — pending P1 layering") + `/dev reload` feedback flags the layer.
- `general.json` key addition `stageBackupRetention` (W5 default 10 in code meanwhile).
- Confirm `FLUID_SOLID` classic-water decision (§2.14) doesn't fight disc worldgen
  assumptions (xbox dims are outside P1's disc pipeline — expected no-op).

### 4.2 P2 (VFX/shaders)

- **Portal rift**: implement against `XboxRiftHooks.onPortalSpawned/Removed(level, pos)`
  (W9 ships interface + no-op base FX). Suggested asset id `eclipse:xbox_rift`.
- **Transition glitch**: P3's `PortalTransitionController` consumes the Veil post id
  (`eclipse:portal_glitch` already in P3's ledger to P2); P5 just sends style
  `eclipse:xbox_glitch` — P2/P3 map style→post pipeline; fallback GlitchText overlay is
  P3's (already planned).
- **Render distance**: P5-W4 owns the `S2CViewDistancePayload` push (§2.8) — P2 must NOT
  ship a second render-distance pusher; if P2 needs settings pushes for shader toggles,
  reuse W4's `eclipse_client_push` channel (extension point documented in the class).
- **Replay hooks**: `/dev replay expansion <stage>` re-fires the growth cinematic path —
  P2's expansion VFX must be re-triggerable without terrain change (idempotent trigger).
- **Photon**: confirm identity/license (§2.15); if shaderpack → P2 documents distribution
  (shaderpacks folder), P5 adds nothing to the jar.

### 4.3 P3 (UI)

- **Dev Handbook style**: W2 requests the flat style tokens (panel background, accent,
  danger colors) — P3 exposes constants class or W2 copies the palette (P3 §2 kit).
  P3 never edits P5 screens.
- **Xbox timer overlay**: NEW ask (not yet in P3_ui.md): render from
  `S2CXboxTimerPayload{endsAtEpochMillis, serverNowEpochMillis, worldId, active}` (clock-
  offset technique identical to their sidebar §2.17). Until then W9's bossbar fallback
  ships; client ack flag hides it when the overlay takes over (§2.13.5).
- **Transition**: P5 sends `S2CPortalFxPayload{style:"eclipse:xbox_glitch", holdTicks:30}`
  — P3-W11 owns the payload class + controller; P5-W9 only invokes
  (compile-time dependency on P3-W11's payload — sequencing or a P5-local duplicate
  payload id is FORBIDDEN; if P3-W11 lands later, W9 temporarily sends nothing and the
  vanilla-screen suppression note moves to known-gaps).
- **P3 §5.3 asks → delivered as**: `/dev timer add|set` (spool auto via P4 payload),
  `/dev awards test` (calls P3-W10's public sender), `/dev skill grantxp|resettree`,
  `/dev deathflow revive` (→ `DeathFlowHooks.onRevived`), `/dev locale debug` — all in W4;
  `eclipse-client.toml`/`eclipse-journey.toml` defaults + EMI pin ship via W10's pack docs.
- **EMI**: split per §2.18 (P3 plugin/tag/reflection; P5 bundle/pin/hidden-entries via
  integration).

### 4.4 P4 (gameplay services) — APIs frozen in `P4_gameplay.md`

Consumed as-is: `RealtimeDayService` dev API (§2.3), `TimedBuffApi` (§2.4; +small ask
`knownIds()` for suggestions), `SkillsApi` (xp add/set, `setSecretMultiplier`),
`AnalyticsApi` (value/top/keys/onlineOrKnownUuids), `AwardService.preview/resolveNow`,
`OfferingService.peek`, `VoiceMuteApi.setGlobalMuted`, `QuestEngine`
(+asks: `adminComplete/adminRevoke(player|team, kind, indexOrId)` — small, on top of their
completion pipeline), unlock-override ask (`UnlockOverrides.grant/revoke/list`, §2.5 —
P4 wave B home; P5 fallback documented), `GoalConfig.validateAndNormalize` (W4 uses in
ConfigEditor extension — assignment TO P5 confirmed by P4 §4), ReloadHooks bridge (W1
calls), `DeathFlowHooks.onRevived` + xbox death short-circuit
(`XboxEventApi.isProtectedDeath(player)` — P4's death pipeline checks it; ONE boolean
call, agreed hook point). Xbox reward call `TimedBuffApi.start(server, "double_skill_xp",
60)` matches P4's frozen example verbatim. Buff `double_skill_xp` must exist in P4-B3's
`buffs.json` (it does, §2.16 of their plan).

### 4.5 P6 (entities/GeckoLib)

- W10 jarJars GeckoLib (pinned; §2.15) — P6 declares it a normal `implementation`
  dependency but must NOT also jarJar it (dedup works, double-declare is noise); P6 pins
  the same version string (single line coordination in their build notes).
- Display placer (§2.7) uses vanilla display entities — no GeckoLib interaction.
- Xbox portal uses interaction+display markers, not custom entities; if P6 later wants a
  fancier portal entity, `XboxPortal` exposes `setPresenceSupplier(...)`.

---

## 5. RISKS & FALLBACKS

| # | Risk | Mitigation / fallback |
|---|---|---|
| R1 | **jarJar with mixin-bearing mods** (EMI ships mixins) misbehaves nested | Precedent: Veil (mixin-heavy) already jarJar'd here, Sable jarJars Veil upstream. Test matrix M3/M6 gates the wave; fallback: drop the offender back to `mods/` folder + PackBootstrap pin — zero API impact |
| R2 | **Jar size** balloons (34→~65 MB w/ 3 worlds+textures+music) | Trim step + budget gate in W7 (orchestrator sign-off before binaries commit); fallback ladder: 2 worlds → 1 world (tu12) → worlds move out of the jar into PackBootstrap-style first-boot download (server-side extract; config URL) |
| R3 | **License blockers** make true single-jar impossible (Create assets/Suppl/SB/SVC/Aeronautics) | Honest verdict §2.15 + PackBootstrap official-CDN downloads + BUNDLING.md table; user informed that mod-menu will still show externals; revisit only with written author permissions |
| R4 | **EMI has no live-hide API** | P3-W11's reflection reload + predicate re-eval (their risk R-1); P5 pins the exact EMI version so reflection targets are stable |
| R5 | **Mojang-content redistribution** (tutorial worlds are Mojang/4J IP; TMA/GitHub conversions are gray-zone) | Private-event context, full credit in CREDITS.md, no standalone re-hosting; fallback mode (R2 ladder) downloads from the original public archives at first boot instead of shipping bytes in our jar; decision documented for the user — this plan does NOT claim legal clearance |
| R6 | **DFU upgrade** 3839→3955 corrupts edge chunks | Single-hop vanilla `--forceUpgrade` is the supported path; bake validates chunk count + spawn area render; fallback: re-convert from Fridtjof 1.13.2 source (two-hop) or hand-fix bad regions (worlds are 2×2 regions — small) |
| R7 | **Region install timing** (files locked once chunks read) | Install/reset ONLY at `ServerAboutToStartEvent` + staged reset markers (§2.13.2); gametest asserts no install while level ticking; singleplayer/LAN verified in M8 |
| R8 | **P4 API sequencing** (W3/W4 compile against P4 classes) | `TimedBuffApi` ships early in P4-A1 (no-op holder); W3/W4 explicitly waved after P4-B1/B-wave; if P4 slips, W3/W4 slip — no stub forks of P4 packages allowed (prevents divergence) |
| R9 | **Treblo key never arrives** | Pipeline B (FreePD/Pixabay/incompetech) is fully specced with verified license terms §2.20; MusicManager is source-agnostic |
| R10 | **build.gradle contention** (P3-W11 EMI lines vs W10 jarJar) | Explicit sequencing: W10's gradle edit lands after P3-W11; single-owner rule per wave in §3 matrix |
| R11 | **Classic texture pack authenticity** (MIT pack must be recreation, not Mojang copies) | W8 per-texture provenance table + fallback to in-repo placeholder generator; pack + author credited either way; Golden Days NOT approved without license re-verification |
| R12 | **ConfigEditor global writes** keep leaking until P1 lands layering | W5/W4 do not block on it; `/dev reload` + DEV_COMMANDS carry a visible warning; M8 matrix row tracks the fix |
| R13 | **Title-music override fights vanilla music manager** | W11 FABLE-scoped; strategy = situational-music interception with single-instance guard; worst case: title cue demoted to one-shot stinger on menu open (config) |
| R14 | **Aeronautics not on Modrinth CDN** → PackBootstrap can't fetch it | Config `downloadHintUrl` + modcheck message; folder distribution for the server pack stays authoritative |

---

## Appendix A — evidence log (research, verified July 2026)

- TMA TU12 "JE Latest" zip: ~12.5 MB, unzips ~18.9 MB, `level.dat DataVersion=3839`
  (1.20.6), modern `region/entities/poi` layout; per-zip HEAD sizes TU1/TU5/TU9/TU14/TU19
  ≈ 12–13 MB, TU31 21.5 MB. Fridtjof-DE GitHub: conversions at DataVersion 1631 (1.13.2),
  TU12-13 absent, no LICENSE.
- Modrinth API license fields: EMI=MIT; Mouse Tweaks=BSD-3-Clause; GeckoLib=MIT;
  Create=custom (repo LICENSE MIT, assets restricted per project statements);
  Supplementaries=custom (no public redistribution); Sophisticated*=ARR; Simple Voice
  Chat=custom/ARR; Sable=PolyForm Shield 1.0.0; Farmer's Delight=MIT (GitHub LICENSE);
  Create Crafts & Additions=MIT; Create Connected=AGPL-3.0; Create Confectionery=MIT;
  End's Delight=MIT; minecraft-classic-edition resourcepack=MIT; Axiom=ARR + no NeoForge
  1.21.1 builds. Aeronautics="Simulated Project License" (custom, no redistribution),
  distributed as a dev bundle only.
- EMI runtime hiding: no public API (issues emi#494, emi#1207) — reflection
  `EmiReloadManager.reload()` per P3 plan.
- Music sources: FreePD=CC0; Pixabay Content License=commercial use incl. games, no
  attribution, no standalone resale; incompetech=CC-BY 4.0 (attribution required).
- Console worlds: 864×864 playable area → 2×2 region grid; TU14 spawn ≈ (97, 72, −106).
- MC 1.21.1 DataVersion 3955; 1.20.6 = 3839.

## Appendix B — langdrop & wiring formats

`docs/plans_v3/langdrop/P5-W1.json`:

```json
{ "en_us": { "dev.eclipse.category.timer": "Timer" },
  "de_de": { "dev.eclipse.category.timer": "Timer" } }
```

`docs/plans_v3/wiring/P5-W6.md`: list of exact lines, e.g.
`EclipseMod ctor: devtools.display.DevToolItems.ITEMS.register(modEventBus);` and
`emi_hidden.json += "eclipse:display_wand"`. W11 applies and checks off each line in its
PR description.
