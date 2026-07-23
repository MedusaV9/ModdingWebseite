# P2-W2 wiring notes — Cutscene engine v2 (paths, captions, global teleport, view distance, replay, dev commands)

Zero `EclipseMod` / `EclipsePayloads` / `FxPayloads` / `EclipseCommands` / `DevRoot` edits.
Everything self-registers (`@EventBusSubscriber`, own MOD-bus payload registrar `fxdev1`,
own `RegisterCommandsEvent` subscriber for `/eclipsefx`, `DevCommandRegistry.register`
from static init). The only shared file touched is `client/EclipseGuiLayers.java`
(explicitly in the W2 file list).

## Frozen entry points W1 already calls — now implemented

| Payload | Implementation |
|---|---|
| `eclipse:fx/view_distance` | `cutscene.client.ViewDistanceClient.handle(S2CViewDistancePayload)` — raises `options.renderDistance` iff `EclipseClientConfig.cinematicViewDistance()` (default ON), only upward; `chunks == 0` restores; crash marker `config/eclipse-viewdistance-restore.json` (WaveOverlay volume pattern); logout restores. |
| `eclipse:fx/screen_fade` | `cutscene.client.CaptionRenderer.fade(in, hold, out, argb)` — fullscreen fade, usable outside cutscenes. |
| `eclipse:fx/caption` | `cutscene.client.CaptionRenderer.enqueue(langKey, durationTicks, style)` — styles 0 SUBTITLE / 1 TITLE / 2 WHISPER per `S2CCaptionPayload` constants. |

## The invisible-subtitle fix (§1.7)

`EclipseGuiLayers` now whitelists `AnnouncementOverlay.LAYER_ID` **and** the new
`CaptionRenderer.LAYER_ID` (`eclipse:cutscene_captions`, registered above all) in
`LetterboxLayer.setHudWhitelist`. Deviation from the R12 wording "drawn inside the
LetterboxLayer render": captions are an **own whitelisted layer** instead of a draw call
inside `LetterboxLayer.render` — identical suppression-immunity, cleaner ownership
(captions/fades also work with letterbox off, e.g. payload-driven fades outside
cutscenes). `LetterboxLayer.barPx(guiHeight)` is public for anyone needing the current
bar height (captions position off it).

**If you add a new overlay that must render during cutscene HUD suppression, add its
`LAYER_ID` to the whitelist in `EclipseGuiLayers` — that whitelist is THE list.**

## New engine surface siblings consume

### Cutscene schema (`CutscenePath`, additive — old JSONs parse unchanged)

- Keyframe `lookAt`: `[x,y,z]` (keyframe coordinate space) | `"anchor:<id>"`
  (`FxAnchors`, e.g. `"anchor:eclipse:altar_center"`) | `"player"`. Aim is slerp-smoothed,
  ≤ 90°/s.
- Event `data` field, new event types fired by the client director:
  - `caption` — `id` = lang key, `data` = `"<subtitle|title|whisper>[,durationTicks]"`
  - `fade` — `data` = `"<in>,<hold>,<out>[,AARRGGBB]"`
  - `shake` — `data` = `"<strength>[,ticks[,freq]]"` (2-octave noise; freq ≈ 1 rumble, ≥ 2.5 rattle)
- `params.dynamicAnchor` (see resolvers below). `CutscenePath.dynamicAnchor()` accessor.
- Java compat: `Keyframe`/`PathEvent` keep their old constructors (frozen
  `EclipseCommands` editor keeps compiling); new fields are trailing record components.
- Positions are arc-length reparameterized (`cutscene.PathSampler`, 64-sample LUT per
  segment) — **eased segment progress covers distance**. For constant cruise speed make
  keyframe `t` spans proportional to segment length and use `"linear"` easing mid-flight
  (see the reshot `finale_return.json` as the reference shot).

### Global plays (W6 intro / W7 expansion — this is your entry point)

```java
CutsceneService.play(id, players, anchorOrNull, onAllFinished,
        CutsceneService.PlayOptions.global(12));          // gather + viewdist 12 + return
CutsceneService.PlayOptions.globalOneWay(12);             // gather, NO return (intro FLIGHT)
CutsceneService.PlayOptions.LOCAL;                        // v1 behaviour (default overloads)
```

- GLOBAL_TELEPORT gathers players **> 128 blocks away or in another dimension** to a ring
  around the play anchor (or the world-anchored keyframe centroid) in the **path's
  `dimension`**, behind a black `S2CScreenFadePayload`; vehicles are dismounted; freeze
  anchors at the gathered spot. Player-anchored paths are never gathered (warn log).
- `returnAfter` restore runs on ACK/skip/abort/watchdog; logout mid-cutscene restores
  same-dimension positions **before vanilla saves** and persists cross-dimension returns
  in `data/eclipse_pending_returns.dat` (applied at next login). First snapshot wins
  across chained global plays — chain freely, players return to their true origin.
- `PlayOptions.viewDistance > 0` drives `cutscene.ViewDistanceService` (server
  `PlayerList.setViewDistance(min(12, current+4))` + client push; refcounted; watchdog +
  server-stop restore). The bump releases when the whole watcher group completes.
- `FreezeService.transport(player, level, pos, yRot, xRot)` — cross-dimension-safe
  scripted teleport that never drops/never fights an active freeze lock (re-anchors it at
  the destination). W6: use this for the limbo→overworld hop instead of raw `teleportTo`.

### Bundled-defaults refresh (`CutscenePaths`) — W6/W7 READ THIS before your reshoots

`config/eclipse/cutscenes/*.json` used to be copied from the bundled assets only when
missing, which pinned every existing install to cutscene v1 forever. `CutscenePaths.reload()`
now keeps a manifest (`config/eclipse/cutscene_defaults_manifest.json`, id → SHA-256 of the
default it last installed) and on every reload:

- config file missing → install bundled default (unchanged behaviour);
- file byte-identical to the previously installed default, bundled asset changed →
  **auto-upgrade in place** (operator never edited it);
- file edited by the operator → kept, WARN explains "delete + reload to adopt the new default";
- file predates the manifest → upgraded only when byte-identical to a hash in
  `CutscenePaths.LEGACY_DEFAULT_HASHES` (known old shipped defaults), otherwise warn-only.

**W6/W7**: when you replace `intro_submerge`/`intro_rise`/`unlock_ring`, append the SHA-256
of the version you replaced to `LEGACY_DEFAULT_HASHES` (git: `git show <old>:...json |
sha256sum`) so existing installs pick up your reshoot too. W2 already registered the v1
`finale_return` hash. Deleting a bundled id from `DEFAULT_IDS` (W6 deletes the intro pair)
stops installation/refresh; stale config copies of deleted ids are left alone by design —
mention the manual cleanup in your wiring notes.

### Dynamic anchors (W7)

```java
CutsceneService.registerDynamicAnchor("growth_front",
        (server, players) -> /* nearest point of the new ring band, or null */);
```
Resolved at play time when the caller passes no explicit anchor and the path JSON has
`params.dynamicAnchor = "growth_front"` (your `expansion_flyover.json`).

### Sequence replays — the API P5-W6 aliases (§6.4)

```java
public interface SequenceReplayable {                       // cutscene/SequenceReplayable.java
    String sequenceId();                                    // "intro" (W6), "expansion" (W7)
    List<String> phaseIds();                                // timeline order, UPPER_CASE
    boolean replay(MinecraftServer server, String phaseId, Collection<ServerPlayer> players);
}
SequenceReplayable.Registry.register(instance);             // static init / common setup
SequenceReplayable.Registry.byId(id) / .ids();
```
Contract is **FX-only** (no block writes, no state commits, no teleports) — enforced in
review via this single entry point. `/eclipsefx sequence <id> <phase>` already routes
through the registry; P5-W6 aliases `/dev` commands onto `Registry.byId(...)` the same way.

## Dev commands (`/eclipsefx`, permission 3)

`cutscene/dev/FxDevCommands` + docs in `DevCommandRegistry` (category CUTSCENE, ids
`fx.*`, descKeys `dev.eclipse.doc.fx.*` — in the langdrop). Leaves: `post <id> on|off|clear`,
`post list`, `uniform <pipeline> <name> <float>`, `emitter <id> [x y z]`,
`cutscene play|stop|preview <id>` (**play = GLOBAL_TELEPORT for everyone + viewdist 12 —
the W2 acceptance path**; preview = arc-length particle trace, uneven spacing would expose
a reparam bug), `sequence <id> <phase>`, `storm add [r h wall|vortex]|remove|bolt [i]`,
`rift <x y z> <width>` / `rift close`, `supplybeam test` (toggle), `sun debug`,
`viewdist <2..32|reset>`, `caption <style> <key> [ticks]`.

Client-only actions travel over ONE new dev payload (`cutscene/dev/FxDevPayloads`,
own registrar version `fxdev1`, id `eclipse:fxdev/action`, registered `.optional()`)
into `cutscene/dev/FxDevClient` (Veil overrides via `VeilPostController.setEnabled/
clearOverride`, uniform overrides via an own `preVeilPostProcessing` hook, emitter spawns
via `QuasarSpawner`, sun-debug HUD cross on `RenderGuiEvent.Post`).

- **W1 nice-to-have**: `VeilPostController` has no "list registered rows" accessor, so
  `post list` probes a hardcoded known-id set via `isActive`. If W1 adds
  `registeredPipelines()`, `FxDevClient.KNOWN_PIPELINES` can be deleted.
- Uniform overrides note: a uniform ALSO fed per-frame by the pipeline's own feeder may be
  overwritten depending on hook order — fine for debug knobs, documented in the command
  feedback.

## Deviations from the W2 file list

- **+3 files** (all inside `cutscene/**` which W2 owns): `cutscene/dev/FxDevPayloads.java`
  and `cutscene/dev/FxDevClient.java` (needed because half the R12 dev leaves poke
  client-only systems and `network/fx/FxPayloads.java` is frozen/foreign), plus
  `cutscene/dev/package-info.java` (repo convention).
- Langdrop file named `P2-W2.json` (repo convention `P<n>-W<n>.json`), not the plan's
  `P2W2.json`.
- `PendingReturns` is a nested SavedData inside `CutsceneService` (no extra file) —
  new world data id `eclipse_pending_returns`.

## Integration notes for the orchestrator (W11)

- Merge `docs/plans_v3/langdrop/P2-W2.json` into the src lang JSONs (4 caption/demo keys +
  13 dev-doc keys, en+de).
- Sandbox javac of the full W2 closure passes. Two UNRELATED tree observations at check
  time (not W2's): `limbo/GhostShipBuilder` imports `limbo.door.RespawnDoorApi/
  ShipVersionData` which do not exist yet (P6 seam — stubs used for the check), and the
  untracked in-progress `worldgen/FrozenParams.java` (P1) has a transient
  lambda-capture error at line 320.
- `finale_return.json` was reshot: 240 ticks, lookAt player throughout, opens on a black
  fade, subtitle + whisper captions (keys in the langdrop), settle shake, decelerating
  hand-off into first person. Timing consumers unaffected (completion still flows through
  the group callback).
- Existing dev worlds pick the reshoot up automatically on next boot IF their config copy
  is the untouched v1 default — look for `Refreshed bundled cutscene path ... finale_return`
  in the log. A hand-edited copy is kept (WARN in log); delete
  `config/eclipse/cutscenes/finale_return.json` and `/eclipse cutscene reload` (or restart)
  to adopt the reshoot.
