# EVAL-V6-RACES — v6 shared-file race audit

Date: 2026-07-25  
Scope: current tree plus the last eight commits ending at `a3f60b6c2b50`; static/read-only audit (no Gradle and no Git command invocation).

## Verdict

**PASS WITH RESIDUE / ONE INTEGRATION GAP.** No destructive lost update, duplicate payload lane, duplicate cue/row, malformed JSON, cutscene hash loss, GUI-layer collision, or registrar duplication was found. The one functional integration gap is three `sounds.json` aliases that never received matching `SoundEvent` registrations; their callers therefore remain on fallbacks. One genuine pre-existing `SEAM` (wand-config sync) is also still open. The other `SEAM` comments are completed-work residue.

## Findings

### F1 — Medium: three sound aliases are not registered

`sounds.json` has 82 unique valid rows, while the three sound registrars define 79 unique event ids. Every registered event has a JSON row, but these rows are orphans:

- `event.boss_down` — `src/main/resources/assets/eclipse/sounds.json:173`; `BossDownSting` explicitly says the `EclipseSounds` registration is still expected and falls back until it lands (`src/main/java/dev/projecteclipse/eclipse/drama/BossDownSting.java:37-42`, `85-92`, `105-107`).
- `ui.chime` — `src/main/resources/assets/eclipse/sounds.json:656`; `UiSounds.chime()` performs a registry lookup and otherwise uses the vanilla amethyst fallback (`src/main/java/dev/projecteclipse/eclipse/client/handbook/UiSounds.java:206-209`, `219-226`).
- `ui.stamp` — `src/main/resources/assets/eclipse/sounds.json:790`; `UiSounds.stamp()` documents and exercises the same not-yet-registered fallback (`src/main/java/dev/projecteclipse/eclipse/client/handbook/UiSounds.java:188-203`).

`EclipseSounds` ends its alias list at `UI_TOGGLE_SETTLE` (`src/main/java/dev/projecteclipse/eclipse/registry/EclipseSounds.java:347-381`), so a JSON resource-pack row alone cannot make any of these ids discoverable through `BuiltInRegistries.SOUND_EVENT`.

### F2 — Medium: the wand-progress synchronization seam is genuinely open

`WandProgressPanel` still reads local `WandConfig` values and says dedicated-server clients see authored defaults until `S2CWandProgressPayload` exists (`src/main/java/dev/projecteclipse/eclipse/client/wand/WandProgressPanel.java:47-50`). No such payload or cache exists anywhere else under `src/`. This can make displayed costs/cooldowns disagree with server-customized configuration; it is not v6 merge damage, but it is the only unresolved `// SEAM(...)` contract.

### F3 — Low: the entity-lane seam marker is stale after successful convergence

`S2CFxEntityEventPayload` still says the `CUE_GLUT_SPRUNG` cast-time send must be wired (`src/main/java/dev/projecteclipse/eclipse/network/fx/S2CFxEntityEventPayload.java:23-27`), but it is already wired at `src/main/java/dev/projecteclipse/eclipse/wand/WandPowers.java:655`. This is harmless documentation residue from the two entity-lane workers.

### F4 — Low: both rebirth seam markers describe already-completed work

- `ClientRebirthState` still says its payload handler “must call” `update` (`src/main/java/dev/projecteclipse/eclipse/client/skills/ClientRebirthState.java:12-17`), while the call is live at `src/main/java/dev/projecteclipse/eclipse/network/EclipsePayloads.java:339-347`.
- `SkillTreeScreen` labels the rebirth request as a seam (`src/main/java/dev/projecteclipse/eclipse/client/skills/SkillTreeScreen.java:724-729`), but the same block already sends the payload at line 729 and the server handler is live at `src/main/java/dev/projecteclipse/eclipse/network/EclipsePayloads.java:350-354`.

### F5 — Low: `FxCues` still claims there is no new payload type

The class contract says every cue uses the existing position payload and “no new payload type” (`src/main/java/dev/projecteclipse/eclipse/network/fx/FxCues.java:7-13`), while the same file correctly documents entity-lane cues later (`src/main/java/dev/projecteclipse/eclipse/network/fx/FxCues.java:100-110`, `180-186`, `227-238`). The runtime implementation is coherent; only the top-level contract missed the entity-lane update.

### F6 — Info: one obsolete langdrop key remains unmerged

All 123 langdrop fragments parse. Their keys are merged except `gui.eclipse.journey.settings_entry` in both locales (`docs/plans_v3/langdrop/P3-W8.json:7`, `23`). The key has no source/resource consumer, and the current title screen explicitly removed that entry (`src/main/java/dev/projecteclipse/eclipse/client/menu/EclipseTitleScreen.java:53-54`, `160-161`), so this looks like stale staging content rather than a lost translation.

## Focus-file integrity checks

### `network/fx/FxPayloads.java` and entity payload

- Exactly one `S2CFxEntityEventPayload` source file exists.
- Exactly one registration exists at `src/main/java/dev/projecteclipse/eclipse/network/fx/FxPayloads.java:72`.
- Exactly one handler exists at `src/main/java/dev/projecteclipse/eclipse/network/fx/FxPayloads.java:225-234`.
- Exactly one send helper exists at `src/main/java/dev/projecteclipse/eclipse/network/fx/FxPayloads.java:112-122`.
- The codec writes and reads the same seven wire fields in the same order: id, entity id, x/y/z, a, b (`src/main/java/dev/projecteclipse/eclipse/network/fx/S2CFxEntityEventPayload.java:29-51`).
- Comparing photon-core commit `dec682954383` to content commit `a3f60b6c2b50` found no removed `FxPayloads` methods; only `sendFxEntityEvent` and `handleFxEntityEvent` were added.

### `network/fx/FxCues.java`

- 28 cue constants, 28 unique Java names, and 28 unique wire paths.
- 27 cues have exactly one `PhotonFxRegistry` row. `CUE_GROWTH_RIDER` is the sole no-row cue by design and has its dedicated dispatch branch at `src/main/java/dev/projecteclipse/eclipse/network/fx/FxPayloads.java:195-200`.
- Every cue has live references outside its declaration; no dead constant was found.
- The two PH-CORE template constants survived the content wave; 26 constants were added and none removed.

### `veilfx/PhotonBridge.java`

- Photon-core’s public/private method set survived the content wave with no removals. The additions were `ensureAttachedFx`, `stopAttachedFx`, `liveEntityExecutors`, and the nearest-player helper.
- All 13 direct `ResourceLocation` constants are unique, referenced, and have matching `assets/eclipse/fx/<path>.fx` files (`src/main/java/dev/projecteclipse/eclipse/veilfx/PhotonBridge.java:87-153`).
- The core reflection handles and lifecycle/budget methods remain singular; no duplicate spawn/loop/sweep implementation was found.

### `cutscene/CutscenePaths.java`

- `Map.ofEntries` syntax is coherent and contains 11 unique keys (`src/main/java/dev/projecteclipse/eclipse/cutscene/CutscenePaths.java:80-130`).
- All nine cutscene assets changed in v6 wave B; each immediate-parent SHA-256 is present under the correct id: the three intro paths, `unlock_ring`, both expansion paths, `finale_return`, `credits_helm`, and `end_shatter`.
- `DEFAULT_IDS` contains exactly the nine bundled JSON assets (`src/main/java/dev/projecteclipse/eclipse/cutscene/CutscenePaths.java:63-66` and `src/main/resources/assets/eclipse/cutscenes/`).

### Sounds, GUI layers, and registrars

- `sounds.json` is valid and duplicate-key-free. There are no missing JSON rows for registered sound events and no cross-registrar id collisions. See F1 for the three reverse-direction orphans.
- `EclipseGuiLayers` has ten unique registrations. Ordering is coherent: wave → letterbox → jumpscare → captions for the `registerAboveAll` stack, leaving captions topmost (`src/main/java/dev/projecteclipse/eclipse/client/EclipseGuiLayers.java:61-69`); day/xbox timers share an anchor but are explicitly mutually exclusive (`50-56`).
- `EclipseMod` has 28 unique registrar calls and no duplicate target (`src/main/java/dev/projecteclipse/eclipse/EclipseMod.java:36-64`). The separate music and backrooms sound registrars are both present (`58`, `62`).

## Resource and residue sweeps

- `en_us.json`: 2,142 keys; `de_de.json`: 2,142 keys; exact key-set parity, no duplicate keys.
- All 65 `assets/eclipse/quasar/emitters/**/*.json` files parse and have no duplicate keys.
- Broader safety sweep: all 360 `src/main/resources/**/*.json` files parse and have no duplicate keys.
- No conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) exist under `src/`.
- `SEAM` audit: four actual `// SEAM(...)` comments — one genuinely open (F2), three stale/completed (F3/F4). Other matches (`riss_seam_scar`, worldgen seam constants) are domain terminology, not integration markers.

## History race assessment

Across the last eight commits, focus-file edits were concentrated and additive:

- `09d1d49b918a`: original Photon bridge and altar FX branch.
- `af458db56a3d`: `sounds.json` update only.
- `101fbe21705a`, `8c2bfca6fe45`, `e9ae3998b6ac`: no focus-file changes.
- `8b18a23c8c16`: cutscene hash-table migration plus all nine prior hashes.
- `dec682954383`: PH-CORE cue/registry/bridge base.
- `a3f60b6c2b50`: 26 cue constants, 11 direct bridge constants, and the entity lane; structural comparison found no removed core method or constant.

The current contents of all eight requested focus files are byte-identical to the `a3f60b6c2b50` tree, so no later uncommitted overwrite is present in those files.
