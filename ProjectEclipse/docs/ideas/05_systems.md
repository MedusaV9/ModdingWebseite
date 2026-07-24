# Collector #5 — Cutscenes / Custom Border / Dev Tools / Integrations

Event names verified against neoforge-21.1.238-universal.jar: `PlayerTickEvent.Pre/Post`, `EntityTickEvent.Pre/Post`, `ClientTickEvent.Pre/Post`, `MovementInputUpdateEvent`, `ViewportEvent.ComputeCameraAngles/ComputeFov/RenderFog`, `InputEvent.Key/MouseButton.Pre/InteractionKeyMappingTriggered/MouseScrollingEvent`, `RenderGuiEvent.Pre`, `RenderGuiLayerEvent.Pre`, `RegisterGuiLayersEvent`, `RenderLevelStageEvent(+Stage)`, `RenderFrameEvent.Pre`, `EntityTeleportEvent.EnderPearl/ChorusFruit`, `LivingIncomingDamageEvent`, `LivingKnockBackEvent`.

## 1. Cutscene engine — "Director" [MUST, 4]

**Decision: client-side camera override (B), NOT spectate-entity (A).** A = 20Hz server teleports, hitching, spectator input leaks, entity-despawn softlocks. B = path evaluated per render frame (any FPS), true bezier/easing/roll; Sodium/Iris read camera AFTER `Camera#setup` → fog/culling/shadows follow automatically. Veil has NO cinematic camera API (post-processing, Necromancer bone anim, Quasar, Easings only) → build own ~600-line engine, use Veil Easings + post FX for polish. Camera core must run vanilla-client-only (no Veil coupling).

**Implementation**:
- `client/cutscene/CameraDirector` (client singleton): active `CameraPath`, start nanos; position via **Catmull-Rom** (default, keyframes pass through points — ideal for recorder) or cubic bezier; rotation = quaternion slerp of yaw/pitch/roll; per-keyframe easing (linear|easeInOutCubic|easeOutQuint|...).
- **Position override**: mixin `@Inject(method="setup", at=@At("TAIL"))` into `net.minecraft.client.Camera` calling `setPosition`/`setRotation` (protected — widen via accessor). Rotation fallback: `ViewportEvent.ComputeCameraAngles` (supports roll).
- FOV via `ViewportEvent.ComputeFov`.
- Render own body: `options.setCameraType(CameraType.THIRD_PERSON_BACK)` during flight, restore after.
- **Letterbox**: GUI layer (RegisterGuiLayersEvent) — two black bars ease in/out; suppress HUD via RenderGuiLayerEvent.Pre cancels while active.
- **Skip**: ESC/Space → `C2SCutsceneStatePayload(SKIP_REQUEST)`; server checks per-cutscene `allowSkip` && global override. Swallow input: MovementInputUpdateEvent zero-all + InputEvent.MouseButton.Pre/InteractionKeyMappingTriggered cancel.

**Freeze + invuln (server-authoritative) [MUST, 2]**: `FreezeService` w/ `CUTSCENE_LOCK` attachment: PlayerTickEvent.Pre rubber-band (`connection.teleport` if moved >0.1), zero `setDeltaMovement`, cancel PlayerInteractEvent's; cancel LivingIncomingDamageEvent + LivingKnockBackEvent for invuln (do NOT flip abilities.invulnerable — leaks on crash). Client input zeroing = comfort; server = truth. TTL mandatory.

**Server flow**: `CutsceneService.play(id, players)` → per player: freeze, `S2CCutscenePlayPayload(id, allowSkip)`; path library synced at login (`S2CCutsceneLibraryPayload`) + on `/eclipse reload`. Client ACKs STARTED/FINISHED/SKIPPED. Intro rework: keep StartEventCutscene server timeline; at TILT play `intro_submerge` path (limbo); on dimension change chain `intro_rise` (overworld; paths support `anchor: "player"`). Expansion cutscenes: `unlock_ring_N` orbital shots at new ring edge during materialization.

**Camera path JSON** (`config/eclipse/cutscenes/<id>.json`, synced S2C):
```json
{
  "id": "intro_rise", "allowSkip": false, "interpolation": "catmullrom",
  "anchor": "player", "dimension": "minecraft:overworld",
  "letterbox": true, "hideHud": true, "durationTicks": 160,
  "keyframes": [
    { "t": 0.0,  "pos": [0.0, 12.0, -8.0], "yaw": 0, "pitch": 25, "roll": 0, "fov": 70, "easing": "easeOutCubic" },
    { "t": 0.55, "pos": [6.0, 6.0, -6.0],  "yaw": -35, "pitch": 10, "roll": 2, "fov": 62, "easing": "easeInOutCubic" },
    { "t": 1.0,  "pos": [0.0, 1.62, 0.0],  "yaw": 0, "pitch": 0, "roll": 0, "fov": 70, "easing": "easeInCubic" }
  ],
  "events": [ { "t": 0.9, "type": "sound", "id": "eclipse:event.emerge" } ]
}
```
Final keyframe lands at player eye pos for seamless hand-back (recorder auto-appends).

**Dev tools [MUST, 2]**: `/eclipse cutscene edit <id> addkeyframe [t]` captures operator eye pos/yaw/pitch (+set roll|fov); `preview <id>` (operator only, no freeze); `enable|disable <id>` persisted toggle — disabled → skip straight to end-state callbacks (never softlock progression). [NICE, 3]: free-fly record mode sampling flown path.

## 2. Custom circular soft border [MUST, 4]

- **Ring**: circle centered on spawn, `radius = discRadius + 10–15`. Server-authoritative `SoftBorder` (persist center/radius in EclipseWorldState; `S2CBorderPayload(centerX, centerZ, radius)` at login + change).
- **Vanilla border kept as outer fail-safe** at radius+48, warning 0, damage 0. Hide visuals: client mixin cancelling `LevelRenderer#renderWorldBorder` (head-inject return).

**Physics (server, PlayerTickEvent.Post, cheap d² check)**:
1. `d > R−16`: mark near-border (drives client FX flag).
2. `d > R`: impulse `v = normalize(center−pos) * min(1.2, 0.25*(d−R)+0.4)` horizontal + 0.3 Y; `setDeltaMovement(v); hurtMarked = true` (pattern proven in StartEventCutscene.risePlayerAt). Glitch sound + client bounce FX.
3. `d > R+3`: teleport fallback onto clamped point R−2 (raycast ground).

Edge cases: **vehicles** — operate on `getRootVehicle()`; impulse vehicle; if vehicle re-violates 3× in 40t → eject + teleport player alone; check vehicles in EntityTickEvent.Post only w/ player passengers. **Elytra** — `stopFallFlying()` before impulse. **Pearls/chorus** — EntityTeleportEvent.EnderPearl/ChorusFruit: clamp `setTargetX/Z` into R−2 (don't cancel — eats pearls). Clamp TeleportCommand too. Log repeat violators to AntiCheatCheck channel [SHOULD].

**Client FX [MUST geometry+particles 3; SHOULD Veil post 3]**: invisible until `distToCircle < fxRange (5–10)`. Layers: (1) geometry patch — RenderLevelStageEvent AFTER_PARTICLES: curved strip of quads (±25° arc nearest player, tessellated per 2 blocks, height ±12 around player Y) w/ scrolling glitch texture, additive, alpha by `1−dist/fxRange` + per-quad noise flicker (unstable static, not a wall). Purple wisp particles along arc. Must work Sodium+Iris (fallback stage AFTER_TRANSLUCENT_BLOCKS if sorting issues). (2) Veil post — chromatic aberration + horizontal displacement bands, strength = proximity uniform; gate off when Iris pack active.

`BorderController.setBorder` → drives ring radius + failsafe; lerps radius for expansion animation.

## 3. Dev tools suite

**Command tree** (extends /eclipse, perm 3):
```
/eclipse cutscene play <id> [players] | abort [players]
/eclipse cutscene enable|disable <id> | skip allow|deny <id>
/eclipse cutscene edit <id> addkeyframe [t] | removekeyframe <i> | set roll|fov <v>
/eclipse cutscene preview <id> | list | export <id> | reloadpaths
/eclipse stage load <n> | save <n> | revert | status
/eclipse schedule next <ISO8601|+NhNNm> | list | clear
/eclipse freeze <players> on|off        /eclipse invuln <players> on|off
/eclipse goals edit   (GUI)             /eclipse timeline (inspector)
/eclipse border ring set <radius> [seconds] | fx range <blocks>
```

- **Stage step-loader [MUST, 4]**: stage = saved snapshot of ring annulus between stage N−1 and N radii. `save <n>` serializes chunk sections in annulus to `world/eclipse/stages/<n>.bin` (raw palettes + BEs — StructureTemplate chokes at millions of blocks); `load <n>` applies via tick-budgeted writer; persists `currentStage` in EclipseWorldState. `revert` re-applies last-loaded. Workflow: load N → hand-edit → save N → later load N+1.
- **Phase scheduler [MUST, 2]**: `nextPhaseEpochMillis` in EclipseWorldState; ServerTickEvent.Post check (100t cadence) fires setDay(day+1). Countdown: one global ServerBossEvent ("Next phase: 2h 14m", purple, progress = remaining/total), lazy, hidden when idle. `+2h30m` relative; persists (absolute epoch). Supersedes dayAutoAdvance (warn if both).
- **Goal/unlock editor GUI [SHOULD, 4]**: client Screen listing days → editable goals, border, unlocks; `C2SConfigEditPayload` perm-checked (hasPermission(3)) writes days.json/milestones.json + EclipseConfig.reload() + broadcast.
- **Timeline inspector [SHOULD, 2]**: prints day, altar, stage, schedule, ring radius, active cutscenes, per-player freeze/ack, watchdog events.
- **Freeze/invuln toggles [MUST, 1]**: wrappers over FreezeService.

## 4. Mod integration & testing (verified 2026-07)

- **Veil 4.3.0**: available via maven.blamejared.com (`foundry.veil:veil-neoforge-1.21.1:4.3.0`); ImGuiMC from maven.ryanhcode.dev for dev panels. No camera API.
- **Create: Aeronautics — NOW RELEASED** (Modrinth project `oWaK0Q19`, ~2026-04, v1.2.x line, 1.21.1 NeoForge only). Part of "Simulated Project" suite (core mod `simulated` + `aeronautics` + `offroad`). Hard-requires Create + Sable. Young, ~760 open issues — expect churn. Verify its Create version pin vs our 6.0.6 before updating.
- **Sable**: `mc1.21.1-2.0.3-neoforge` (2026-06-17). Rapier (Rust) physics, sub-levels = moving chunk regions. Intrusive; `sable-companion` repo for compat hooks.
- **Lodestone**: 1.8.x on NeoForge 1.21.1 confirmed — overlaps Veil almost entirely → **skip** (fallback only if Veil+Iris forces retreat).

**Dev runtime modlist**:

| Mod | Version | Role | When missing |
|---|---|---|---|
| Veil | 4.3.0 (Gradle dep + jar) | post FX, glitch, easings | ModList guard; geometry/particle fallback |
| ImGuiMC | latest 1.21.1 | Veil dev tooling, DEV ONLY | never shipped |
| Create | 6.0.6 (have) | content, modgate | gate idles |
| Simple Voice Chat | have | voice | no-ops |
| Sodium 0.6.13 + Iris 1.8.12 | have | perf/shader matrix | client-only |
| Sable | 2.0.3 | Aeronautics dep | not referenced |
| Create: Aeronautics (+simulated) | 1.2.x | flying contraptions | test-matrix only |

**Critical integration tests**: (1) Aeronautics airship into custom border — Sable sub-levels aren't vanilla vehicles; getRootVehicle won't see them → detect player-in-sublevel crossing R and teleport PLAYER out (sub-level clamping out of scope, document). (2) Cutscene while riding Sable contraption → abort cutscene if getRootVehicle() != player. (3) Veil post + Iris pack → auto-disable. (4) Border FX under Sodium alone + Sodium+Iris. (5) SVC during freeze.

**Additional libs**: spark profiler [SHOULD] (measure tick budgets). Against Cloth Config (have JSON+reload) and architectury (single-loader).

## 5. Performance & safety

- **Ring expansion [MUST, 3]**: never setBlockAndUpdate in bulk. Queue per-section jobs; each ServerTickEvent.Post drain to **2ms time budget** (nanoTime, config `ringBlocksBudgetMs`). Write `setBlock(pos, state, Block.UPDATE_CLIENTS)` (flag 2); whole sections: swap palettes + resend `ClientboundLevelChunkWithLightPacket`. Cap ~4 relight chunks/tick. Pair with cutscene so materialization is the shot's subject.
- **Cutscene sync**: library at login + reloadpaths (few KB); play payload ~20 bytes; ACKs feed inspector.
- **Watchdog [MUST, 2]**: release freeze at durationTicks+100 regardless of ACK; release on SKIPPED, death, dimension change (except scripted intro), logout; clear stale CUTSCENE_LOCK at login; missing path client-side → ACK FINISHED instantly; `/eclipse cutscene abort` manual. EclipseWorldState never stores freeze → restart always unfreezes.
- **Freeze × SVC**: mic path untouched (desired — shared "whoa"). Positional audio anchors to player bodies (fine, all frozen together). Optional `cutscenes.muteDuringIntro` reusing VoiceMuteApi [NICE, 1].
- **FX budget**: border strip ≤ ~200 quads + ≤30 particles/s only within fxRange; zero elsewhere.

**Priority**: FreezeService → CameraDirector + intro paths → SoftBorder physics → border FX 1 → scheduler → stage loader → cutscene editor commands → Veil FX → goals GUI → Aeronautics matrix.
