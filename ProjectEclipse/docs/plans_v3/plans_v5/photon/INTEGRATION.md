# Photon — safe integration architecture (PHOTON-EXPLORE-3, 2026-07)

Scope: how the optional **Photon** VFX mod (Modrinth `photon-editor`, KilaBash / Low Drag
MC) is wired into Eclipse today, whether the client-optional distribution is actually safe,
and the registry architecture (`PhotonFxRegistry` over the existing `FxPayloads` S2C lane)
that now carries every cue beyond the two original D12 seams (§3 SHIPPED note; V6-FIXWIRE
doc refresh). All jar evidence below was re-verified
by unpacking `run/mods-client/photon-neoforge-1.21.1-2.1.5.jar` and
`ldlib2-neoforge-1.21.1-2.2.29.jar` (extracted to `/tmp/photon_jar3`) and by reading the
NeoForge 21.1.238 sources in `build/moddev/artifacts/neoforge-21.1.238-sources.jar`.
Companion docs: `docs/BUNDLING.md` §"Photon (optional VFX layer)" (license/identity
verdict), `docs/plans_v3/plans_v5/PLAN-D_systems.md` §D12 (original adoption plan),
`docs/plans_v3/plans_v5/AUDIT-recent.md` D12 row (shipped state).

---

## 1. Current trigger flow (shipped, D12)

`veilfx/PhotonBridge` is the ONLY class that touches Photon — pure reflection, zero
compile-time or Gradle dependency, `@OnlyIn(Dist.CLIENT)`. Reflected API (signatures
re-verified with `javap` against the 2.1.5 jar, see §"API surface" below):
`FXHelper.getFX(ResourceLocation)`; the two executor kinds
`new BlockEffectExecutor(FX, Level, BlockPos)` and
`new EntityEffectExecutor(FX, Level, Entity, AutoRotate)` (both → `start()`); the
`SpawnOptions` setters `setOffset(Vector3f)` / `setRotation(Quaternionf)` /
`setScale(Vector3f)` / `setDelay(int)` / `setAllowMulti(boolean)`; and the loop/sweep
surface `getRuntime()` → `FXRuntime.isAlive()` / `FXRuntime.destroy(boolean)` —
thirteen resolved member handles plus the NAME-resolved `AutoRotate` constant table
(fourteen `resolve()` fields total; EVAL-V6-PHOTON §2 verified the surface exact).

Guard chain (`PhotonBridge.available()` + `resolve()`), all must pass:

1. session `state != DISABLED` (any reflection breakage disables for the session, one WARN);
2. `ModList.get().isLoaded("photon")`;
3. `EclipseClientConfig.photonFx()` (client toggle, default true);
4. `!EclipseClientConfig.reducedFx()` (accessibility/perf kill switch);
5. lazily-resolved reflection handles (`Class.forName com.lowdragmc.photon.client.fx.*`);
6. per-id `MISSING_FX` set: a null/failed `.fx` load skips that id for the session
   (one INFO/WARN).

The two ORIGINAL D12 seams — every LATER cue goes through `PhotonFxRegistry` rows
instead (§3). The `enhanceQuasarCue` seam has since evolved: it now returns a boolean
("the Quasar leg is SUPERSEDED by a live Photon replacement"), and
`EclipsePayloads.handleQuasar` skips `QuasarSpawner.spawnOrFallback` when it answers
true (PHOTON-QUALITY §6 retirements, REPLACE semantics — the Quasar leg re-enters
automatically whenever the Photon leg did not play). `handleQuasar` also gates the
enhancement through `WorldStageArbiter.gateCue` (V7-SIGCOMP §6.1: a DEMOTED cue sheds
only the Photon hero layer; the Quasar baseline still runs). The seam's current
emitter-id branches: `ALTAR_LEVELUP_RING` (LAYER — spawns `eclipse:altar_levelup`,
never supersedes), `wand_soulbind_flash` (REPLACE — the 4-emitter Photon flash
supersedes the Quasar flash when it plays; PH-PLAYER #1), and the two suppression
probes `stern_komet_core` / `riss_schlag_maw` (no spawn of their own — they answer
true while the `WandPhotonFxRows` Photon executors for the same power are live near
the cue, via `PhotonBridge.hasLiveFx`).

| Cue | Server sender | Client path | Photon layer |
|---|---|---|---|
| Altar milestone level-up | `ritual/AltarBlockEntity.completeMilestone` sends `S2CQuasarPayload(ALTAR_LEVELUP_RING)` to players in beam range (world-wide at L5) | `EclipsePayloads.handleQuasar` → `PhotonBridge.enhanceQuasarCue(emitterId, pos)` → `QuasarSpawner.spawnOrFallback` (skipped iff the enhancement superseded the cue — never for the altar ring) | `enhanceQuasarCue` matches `ALTAR_LEVELUP_RING` → `spawn(eclipse:altar_levelup)`, returns false (deliberate LAYER) |
| Expansion rift tear | `worldgen/structure/StructurePendingRegistry` sends `S2CStructureRiftPayload`; other senders reach the same tear via `FxPayloads` `FX_RIFT_OPEN` (`ExpansionSequence`, `StructureFlightFx`, portals, wand, dev commands) | `EclipsePayloads.handleStructureRift` / `FxPayloads.handleFxEvent(FX_RIFT_OPEN)` → `RiftFx.openRift(...)` | `RiftFx.openRift` calls `PhotonBridge.spawn(eclipse:expansion_rift_glow, pos)` on every tear open |

Notes on the flow as-built:

- The altar ceremony script (`client/drama/AltarCeremonyFx`, dispatched by `FxPayloads`
  `FX_ALTAR_LEVELUP`) spawns a SECOND `altar_levelup_ring` echo directly via
  `QuasarSpawner.spawn(...)` — deliberately NOT through `PhotonBridge`, so one level-up
  fires exactly one Photon layer (the server's own ring send), never two.
- Photon spawns are NOT charged to `FxBudget` (Photon renders through its own
  pipeline/mixins, not Veil/Quasar) — `reducedFx` is the budget-equivalent gate.
- Server code never references Photon in any form; the wire protocol carries only
  Eclipse-logical ids (`eclipse:altar_levelup_ring`, rift payloads). Identical bytes on
  the wire whether or not the client has Photon.

## 2. Distribution & dist-safety verdict

Where the jars sit: BOTH `run/mods-client/` (dev-client extras next to iris/sodium) AND
`run/mods` (dedicated server), fetched best-effort by
`tools/modpack/fetch_dev_mods.py` (the `OPTIONAL` table carries a `MODS_CLIENT` and a
`MODS` row for each of photon/ldlib2 — PH-CORE adopted Verdict C's option 1 below); a
fetch miss never fails the script. `AntiCheatCheck.defaults()` +
`assets/eclipse/bootstrap.json` list `photon`/`ldlib2`/`kilagraph` as `"*"` allowlisted
**optional** rows (verified — they are in the `optional` list, NOT in `required`).

`neoforge.mods.toml` facts (unpacked from the shipped jars):

- **photon 2.1.5**: no `clientSideOnly` marker → the mod container WILL construct on a
  dedicated server. Deps: `neoforge [21.0.0-alpha,)` `side=CLIENT`, `minecraft 1.21.1`
  `side=CLIENT`, `ldlib2 [2.2.24,)` `type=required` **`side=BOTH`**. Feature
  `openGLVersion=[3.2,)` — features are side-aware (skipped on a dedicated server, per
  the toml's own comment). Mixin config `photon.mixins.json`: **all 4 mixins are in the
  `"client"` array** (`MinecraftMixin`, `ParticleEngineMixin`, 2 accessors), the common
  `"mixins"` array is empty → zero bytecode patching on a server. The jar ships
  server-aware classes (`PhotonCommonProxy`, `ServerCommands`, `PhotonNetworking`) —
  server-side load is a supported upstream configuration (that is how `/photon fx`
  commands broadcast effects).
- **ldlib2 2.2.29**: no `clientSideOnly` either; `neoforge [21.1.216,)` `side=BOTH`
  (satisfied — we build against 21.1.238), optional `jei` row. Its
  `ldlib2.mixins.json` DOES have common-side mixins (`BlockEntityMixin`,
  `WorldLoaderMixin`, `ReloadableServerResourcesMixin`, kjs/emi hooks behind its
  `LDLib2MixinPlugin` presence checks) → a server install of the pair carries real
  (if modest) server-side bytecode changes from LDLib2, not from Photon.

**Verdict A — our server does not require them: CONFIRMED.** Nothing server-side
references Photon (the one bridge class is `@OnlyIn(Dist.CLIENT)` and reflection-only),
the anticheat `required` list excludes all three ids, and the allowlist rows mean a
Photon-equipped client passes the modcheck.

**Verdict B — they CAN load on a dedicated server: YES** (photon = inert there, all
mixins client-array, GL feature skipped; must be installed together with ldlib2 because
of the `side=BOTH` required dep). Not free (LDLib2 common mixins + GPL "external
install only" policy from BUNDLING.md), but crash-safe.

**Verdict C — the real constraint is the NETWORK, not the dist marker.** Verified from
bytecode + NeoForge sources:

- `PhotonNetworking.registerPayloads` registers **4 `playToClient` payloads with NO
  `.optional()`**; `ldlib2` `LDLNetworking` registers **6 payloads (1 `playToClient`,
  5 `playBidirectional`), also none optional** (checked every `PayloadRegistrar` call in
  both jars).
- NeoForge 21.1.238 `NetworkComponentNegotiator.negotiate` (called from
  `NetworkRegistry.initializeNeoForgeConnection`) **fails the handshake in BOTH
  directions for non-optional channels**: "If the client has none optional components
  that are not present on the server, then negotiation fails" — the server disconnects
  the client with `multiplayer.disconnect.incompatible`.
- Consequence: **a client running Photon+LDLib2 cannot join our dedicated server while
  the server lacks them.** The negotiation happens in the CONFIGURATION phase, i.e.
  BEFORE our `C2SModlistPayload` modcheck ever runs — the anticheat allowlist rows
  cannot rescue the join; they only matter once a join is possible.
- This is a static-analysis finding (runtime confirmation needs a GL client + dedicated
  server pair — same blocker BUNDLING.md records for the Veil-conflict test). Until
  falsified, treat "Photon on clients that join the shared server" as requiring one of:
  1. **Install photon+ldlib2 on the dedicated server too** (safe per Verdict B; keeps
     the external-install GPL policy — the operator installs, we never redistribute);
  2. keep Photon a **singleplayer/dev-client-only** extra (works today unchanged);
  3. upstream PR marking Photon's and LDLib2's channels `.optional()` (the correct
     long-term fix; both are pure client-render features for our use case).

So: "client-optional" is accurate for LOADING but currently NOT for JOINING a
photon-less server. Recommendation: adopt (1) as the operator default in
`overrides/MANUAL_INSTALL.md` guidance when Photon-equipped clients are expected, and
pursue (3).

## 3. Target architecture — `PhotonFxRegistry` over the `FxPayloads` lane

> **SHIPPED (PH-CORE, 2026-07).** The design below is live with these deltas:
> `network/fx/FxCues` + `veilfx/PhotonFxRegistry` + the `FxPayloads.handleFxEvent` tail
> branch exist; the table is NOT a static `Map.of` — content workers self-register rows
> via **`PhotonFxRegistry.registerRow(new Row(logicalId, photonFx, quasarEmitter,
> channel, mode, loop))`** from their own client-only registrar class (reference
> pattern: `veilfx/PhotonFxRows`, which registers the two smoke-test rows
> `FxCues.CUE_TEMPLATE_BURST` / `CUE_TEMPLATE_LOOP` for `eclipse:template_burst` /
> `eclipse:template_loop`, generated by `tools/photon/fxlib.py templates`). The `Entry`
> record became `Row` and grew a `loop` flag (WINDOWED-only law, §4), an optional
> custom `PhotonLeg` (multi-part choreography / entity-lane anchoring; its boolean
> return drives REPLACE re-entry), and the payload's free `(a, b)` cue parameters —
> `dispatch(id, pos, a, b)` plus a `dispatchEntity(id, entity, pos, a, b)` lane fed by
> `S2CFxEntityEventPayload`. `dispatchInternal` also consults `WorldStageArbiter.gateCue`
> (V7-SIGCOMP §6.1: a DEMOTED S-class cue plays only its Quasar sketch; rows without a
> Quasar leg keep the Photon leg — the baseline law outranks demotion). Duplicate logical
> ids are refused with a WARN (first registration wins). Both `Mode`s are live:
> most rows are LAYER; the ferry lantern-swarm/kneel-corona rows ship REPLACE
> (PHOTON-QUALITY §6 retirements). `PhotonBridge` also gained the
> §3.5 entity executor (`spawnOnEntity`), `SpawnOptions`
> (offset/rotation/scale/delay/allowMulti on both executor kinds),
> `spawnLoop`/`stopLoop` (handle + `getRuntime().destroy(force)`),
> `ensureAttachedFx`/`stopAttachedFx` (windowed entity-loop keepalive),
> `hasLiveFx(fxId, pos, range)` (the §1 retirement suppression probe), a per-tick sweep
> of every live executor (dead runtime → forget; dead entity / level change → destroy)
> and a hard budget of `MAX_LIVE_EXECUTORS = 24` live Photon executors (spawns beyond
> it are refused). Dev smoke tests: `/dev photon status` and
> `/dev photon test <fxId> [pos]` (client-targeted over the `FxDevPayloads` lane).

Goal: stop growing hardcoded seams (`enhanceQuasarCue`'s if-chain, per-call-site
`PhotonBridge.spawn`) and make "server fires a logical cue → client resolves to
Photon-if-loaded else Quasar" a table lookup. No new payload type, no registrar bump,
no protocol change — the existing `S2CFxEventPayload` (`eclipse:fx/*` ids, registrar
group `"fx1"`) already carries `(id, pos, a, b)`.

### New classes

```
network/fx/FxCues.java                      (common; server-referenceable id constants)
veilfx/PhotonFxRegistry.java                (@OnlyIn(Dist.CLIENT))
```

**`FxCues`** — plain holder of frozen logical cue ids so server code never touches
client classes (repo rule): `public static final ResourceLocation CUE_<NAME> =
fx("cue/<name>")`. Reusing the `eclipse:fx/` prefix keeps the FxPayloads collision-free
namespace law; the extra `cue/` segment keeps them visually distinct from the
handler-dispatched `fx/*` ids.

**`PhotonFxRegistry`** — the client-side resolution table:

```java
@OnlyIn(Dist.CLIENT)
public final class PhotonFxRegistry {
    public enum Mode { LAYER, REPLACE }   // LAYER = photon on top of quasar (D12 law);
                                          // REPLACE = photon instead of quasar, quasar
                                          //           runs iff photon spawn fails
    public record Entry(
            ResourceLocation photonFx,        // assets/eclipse/fx/<path>.fx
            @Nullable ResourceLocation quasarEmitter, // assets/eclipse/quasar/emitters/…
            FxBudget.Channel channel,         // charged for the QUASAR side only
            Mode mode) {}

    private static final Map<ResourceLocation, Entry> TABLE = Map.of(
            FxCues.CUE_ALTAR_LEVELUP, new Entry(PhotonBridge.ALTAR_LEVELUP,
                    S2CQuasarPayload.ALTAR_LEVELUP_RING, FxBudget.Channel.BURST, Mode.LAYER),
            FxCues.CUE_EXPANSION_RIFT_GLOW, new Entry(PhotonBridge.EXPANSION_RIFT_GLOW,
                    null, FxBudget.Channel.BURST, Mode.LAYER)
            /* future cues: one row each */);

    /** @return true iff the id was a registered cue (consumed). */
    public static boolean dispatch(ResourceLocation id, Vec3 pos) {
        Entry entry = TABLE.get(id);
        if (entry == null) return false;
        boolean photonPlayed = PhotonBridge.spawn(entry.photonFx(), pos); // full guard chain inside
        if (entry.quasarEmitter() != null
                && (entry.mode() == Mode.LAYER || !photonPlayed)) {
            QuasarSpawner.spawnOrFallback(entry.quasarEmitter(), pos, entry.channel());
        }
        return true;
    }
}
```

### Flow (end to end)

```
server system code
  └─ FxPayloads.sendFxEvent(level, FxCues.CUE_X, pos, a, b, range)     // existing helper
       └─ S2CFxEventPayload over registrar "fx1"                        // unchanged wire
            └─ FxPayloads.handleFxEvent (client main thread)
                 ├─ existing FX_* if-chain (unchanged, first)
                 └─ NEW tail branch, before the unknown-id debug log:
                    if (PhotonFxRegistry.dispatch(id, payload.pos())) return;
                 └─ else: existing LOGGER.debug("Unknown FX event id …")
```

Design laws carried over (do not renegotiate):

1. **Server is photon-blind.** Only `FxCues` ids cross the wire; a vanilla-ish or
   photon-less client renders the Quasar/vanilla row, a Photon client renders the
   enhanced one. Zero payload/protocol difference → no version bump, resync-safe.
2. **Every failure degrades, never drops silently below today.** `PhotonBridge.spawn`
   already returns `false` on every failure path; `Mode.REPLACE` uses that return to
   re-enter the Quasar path, and `QuasarSpawner.spawnOrFallback` keeps its own vanilla
   END_ROD/PORTAL burst for unknown/broken emitters. A `FxBudget` refusal on the Quasar
   side stays a deliberate silent drop (budget law, P2 §3.5).
3. **Budget accounting:** Photon spawns stay un-charged (own renderer); the registry
   charges only the Quasar leg via the entry's channel. `reducedFx` disables the Photon
   leg wholesale inside `available()`; `Mode.REPLACE` rows therefore automatically fall
   back to Quasar under `reducedFx` — which is exactly the reduced experience.
4. **Migration of the two shipped seams (optional, mechanical):**
   `PhotonBridge.enhanceQuasarCue`'s if-chain can collapse into a registry row keyed by
   the EXISTING `S2CQuasarPayload.ALTAR_LEVELUP_RING` id (call
   `PhotonFxRegistry.dispatchQuasarEnhancement(emitterId, pos)` from
   `EclipsePayloads.handleQuasar` — Photon leg only, since the Quasar leg is the payload
   itself); `RiftFx.openRift`'s direct `PhotonBridge.spawn` may stay (it is not
   payload-driven — client-locally triggered from several payload shapes). Both keep
   their frozen behavior; the registry is additive.
5. **New reflected executors** (e.g. `EntityEffectExecutor(FX, Level, Entity,
   AutoRotate)` — present in the 2.1.5 jar) get added to `PhotonBridge` the same way:
   one `resolve()` handle + one typed `spawnOnEntity(...)`; the registry `Entry` grows
   an anchor kind only when a cue actually needs it. Do not build it speculatively.

### API surface (re-verified against 2.1.5, `javap`)

```
com.lowdragmc.photon.client.fx.FXHelper
    public static FX getFX(ResourceLocation)            // cached; loads assets/<ns>/fx/<path>.fx
    public static FX getFX(ResourceLocation, boolean)
    public static int clearCache()
    public static final String FX_PATH = "fx/"          // load template: fx/<path>.fx
com.lowdragmc.photon.client.fx.BlockEffectExecutor extends FXEffectExecutor
    public BlockEffectExecutor(FX, Level, BlockPos); public void start()
com.lowdragmc.photon.client.fx.EntityEffectExecutor extends FXEffectExecutor
    public EntityEffectExecutor(FX, Level, Entity, AutoRotate); public void start()
```

## 4. Performance & interaction rules (Iris/Sodium client stack)

Our `run/mods-client` stack is exactly iris 1.8.14-beta.1 + sodium 0.8.12 + photon 2.1.5
+ ldlib2 2.2.29. Findings from the jars:

- **Iris: deliberate compat, not a conflict.** Photon ships
  `com.lowdragmc.photon.core.mixins.iris.ExtendedShaderAccessor` in its client mixin
  list, and `PhotonMixinPlugin` gates the whole `…mixins.iris` package on an
  `IS_IRIS_LOAD` flag (inherited from ldlib2's `MixinPluginShared`, which probes
  `iris`/`oculus`/`sodium`/`jei`/`emi`/`kjs` presence). So the Iris hook only applies
  when Iris is installed — Photon's HDR/bloom pipeline knows about Iris's extended
  shaders. `neoforge.mods.toml` declares NO iris/sodium dependency rows → no load-order
  constraints; all compat is runtime-detected.
- **Sodium:** photon has zero sodium-targeting mixins; ldlib2 only carries the
  `IS_SODIUM_LOAD` probe for its own decisions. Photon's particle hook is a plain
  `ParticleEngineMixin` + accessor (vanilla class) — the same low-risk surface our
  Quasar stack already tolerates.
- **Veil overlap (the real watch item):** Photon 2.x and Veil 4.3.0 both hook
  render/shader pipelines (Photon via its own `MinecraftMixin`/shader assets, ldlib2 via
  `shader.*` mixins on `GameRenderer`/`ProgramManager`). BUNDLING.md records this as the
  open risk with the pre-authorized fallback: flip `photonFx=false` default if in-game
  testing shows conflicts. Still not runtime-tested (needs a GL client). Note Veil post
  FX are already auto-disabled while an Iris shaderpack is active (`veilPostFx` comment
  in `EclipseClientConfig`), while Quasar particles and Photon both keep rendering under
  Iris — so the triple overlap (Veil post + Iris + Photon) cannot occur; the pairs to
  test are (Veil post + Photon, no shaderpack) and (Iris pack + Photon).
- **`reducedFx` integration (already law, keep it):** `PhotonBridge.available()`
  hard-fails on `reducedFx` — Photon is a flagship-moment garnish, and since its spawns
  bypass `FxBudget`, the throttles are `reducedFx` plus the bridge's own hard ceiling
  (`PhotonBridge.MAX_LIVE_EXECUTORS = 24` live executors; spawns beyond it are refused
  outright and counted for `/dev photon status`). Registry rule: never register a
  high-frequency cue (ore procs, footstep-grade spam) with a Photon leg;
  Photon rows are reserved for SEQUENCE-grade one-shots (altar ceremony, rift opens,
  finale beats) and WINDOWED loops (next rule) — the edge-glide trail is the sanctioned
  loop shape, not a counter-example: `GlideTrailFx` drives it as an event-windowed
  entity loop (`ensureAttachedFx` between the `FX_GLIDE_START`/`STOP` edges, REPLACE
  over the Quasar loop), never as a payload-fired row. If a future cue needs rate
  control, gate its send server-side (like the existing beam-range send) — do not add a
  finer client-side Photon budget until a real problem is measured.
- **Loop-law amendment (PH-CORE): looping Photon effects are allowed, WINDOWED-only.**
  A loop row (`Row.loop = true`) is NEVER payload-fired — `PhotonFxRegistry.dispatch`
  consumes it with a one-time WARN and plays nothing. The only sanctioned driver is a
  client-tick controller owning a **hysteresis window in the `SanctumLightfall` pattern**:
  a materialize/release distance band (release strictly larger than materialize so the
  boundary never flickers), a retry cadence for refused spawns (~40 ticks), handle
  pruning every tick, and unconditional release on `reducedFx`, dimension change and
  logout. While the window is open the controller calls
  `PhotonFxRegistry.ensureLoop(logicalId, pos)` (idempotent; re-spawns pruned legs;
  LAYER rows run Photon+Quasar together, REPLACE rows keep a Quasar stand-in only while
  the Photon leg is down); when it closes, `releaseLoop(logicalId, graceful)`. Loops
  built directly on the bridge use `PhotonBridge.spawnLoop(...)` → hold the returned
  `LoopHandle` → `stopLoop(handle, graceful)` (`graceful=true` = `destroy(false)` fade).
  Loop assets MUST ship a renderer cull box and a modest `maxParticles` (see
  `eclipse:template_loop`, the reference loop authored by `tools/photon/fxlib.py`).
  Every loop counts against the 24-executor bridge budget for its whole lifetime — keep
  concurrent loop windows rare (landmark-grade, like the lightfall).
- **Event-dimension amendment (PH-IMPROVE-2, the IDEAS-events #10 sign-off):
  player-scoped ambient loops are allowed inside EVENT dimensions.** A windowed entity
  loop may ride the LOCAL player (the `DriftCocoon` D2 shape: `ensureAttachedFx` on the
  client tick, released on dimension exit / `Clone` / logout / `reducedFx`) when ALL of
  the following hold: the window is presence in an event dimension (a world that exists
  only during an event — the `eclipse:xbox_*` tutorial worlds; never the overworld or
  another persistent dim), at most ONE such loop per client, the asset is GPU-instanced
  (`useGPUInstance:1b`) with `maxParticles ≤ 256` and NO physics modules, and it is
  never payload-fired. First (and currently only) occupant:
  `eclipse:era_dust_motes` driven by `client/xbox/EraDustMotes`. Everything outside
  this exact shape remains governed by the WINDOWED loop law above.
- **GL floor:** `features.photon openGLVersion=[3.2,)` — irrelevant on our stack (Veil
  requires modern GL anyway), skipped on servers.

## 5. Risk table — what breaks when Photon is absent/mismatched

| Scenario | What happens | Bridge degradation | Action needed |
|---|---|---|---|
| Photon not installed (default) | `available()` false via `isLoaded` | Silent no-op; Quasar/vanilla path bit-identical to pre-D12 | none |
| Photon installed, ldlib2 missing | NeoForge dependency error at LOAD (photon requires `ldlib2 [2.2.24,)`) — loader screen, game never reaches the bridge | n/a (loader-level, user install error) | operator installs the pair (fetch script already does) |
| Photon 2.2.x installed (adds required KilaGraph) | Loads fine with kilagraph present; if the `com.lowdragmc.photon.client.fx` API moved/renamed, `resolve()` throws → `state=DISABLED`, one WARN | Session-long no-op, Quasar unchanged | anticheat rows already `"*"` incl. `kilagraph`; re-`javap` the new jar before blessing it in `fetch_dev_mods.py` |
| Photon loaded, `.fx` asset absent (the exception — the full authored fleet ships in `assets/eclipse/fx/`, incl. `boss/`) | `getFX` returns null → per-id INFO, id added to `MISSING_FX` | That cue stays Quasar-only for the session | author + ship the asset (§6) |
| `.fx` asset corrupt / executor throws | `InvocationTargetException` caught in `spawn` → per-id WARN, id skipped | That cue Quasar-only | re-export from the editor |
| `reducedFx=true` or `photonFx=false` | `available()` false | Intentional no-op | none (user choice) |
| Photon+LDLib2 on the DEDICATED SERVER | Loads (Verdict B): photon inert (client-array mixins skipped, GL feature side-aware), ldlib2 applies its common mixins; `/photon` commands appear | Bridge untouched (server never classloads it) | acceptable; required if Photon-equipped clients must join (next row) |
| Client HAS photon+ldlib2, server does NOT | **NeoForge channel negotiation fails** (both mods register non-optional payloads; verified vs 21.1.238 negotiator) → client disconnected before our modcheck | Bridge never runs; player cannot join at all | install pair on server, or keep Photon off multiplayer clients, or upstream `.optional()` PR (§2 Verdict C) |
| Version drift client↔server (e.g. server 2.1.5, client 2.2.0) | Channels match by id+version string; a payload VERSION mismatch fails negotiation the same way | Same as above | keep server+client pinned to the same photon build via `mods_manifest.json` |

Degradation invariant to preserve in review: **no code path may make Photon absence
worse than pre-D12 behavior** — every new call site goes through
`PhotonBridge.spawn`/`PhotonFxRegistry.dispatch`, never through raw reflection.

## 6. Authoring workflow — `fxlib` (house standard) / editor → repo

Photon effects are DATA: compressed-NBT `.fx` files loaded by `FXHelper.getFX` from
`assets/<namespace>/fx/<path>.fx` (`FX_PATH = "fx/"`, template `fx/<path>.fx` —
verified from the jar constant pool). **Every committed asset is authored
PROGRAMMATICALLY** with `tools/photon/fxlib.py` (schema + builder + validator, see
`FX_FORMAT.md`) from a committed generator script (`gen_*.py`, `*_fx.py`,
`fx_*.py` in `tools/photon/`) — the scripts are the source of truth; Photon's in-game
Unity-style editor is the secondary path for visual iteration/preview.

Workflow for a new effect (worked example: `eclipse:altar_levelup`, which SHIPS as
`src/main/resources/assets/eclipse/fx/altar_levelup.fx`):

1. **Author (house standard):** add a builder to the owning generator script (or a new
   one; copy an existing `BUILDERS` table) using the `fxlib` emitter/curve/material
   helpers, then run the script — `FxBuilder.write` round-trip-validates every byte it
   emits. Alternatively iterate visually first: launch the dev client
   (`run/mods-client` already carries photon+ldlib2 via
   `tools/modpack/fetch_dev_mods.py`), open the editor via `/photon_editor fx_editor`,
   build the effect in-world against the real cue (trigger with the existing dev
   commands, e.g. `/dev photon test <fxId>`), then port the result into a builder —
   the committed generator MUST reproduce the shipped bytes.
2. **Validate + lint:** `python3 tools/photon/fxlib.py validate --lint <file.fx>` —
   structural validation plus the 15 PHOTON-QUALITY §5.2 lint rules (no paths = the
   whole tree, grandfathered via `tools/photon/lint_baseline.txt`; NEW error/warn
   findings fail). `fxlib.py selfcheck` runs the same full-tree lint.
3. **Commit the `.fxproj` sibling (binary-diff law, FX_FORMAT.md §7.1):** `.fx` is a
   binary blob — every committed `.fx` carries an uncompressed-NBT
   `<name>.fxproj` project sibling for reviewable diffs and editor round-trips.
   Generator scripts write it via `FxBuilder.write_fxproj`; for an existing tree use
   `python3 tools/photon/fxlib.py write_fxproj --missing`.
4. **Place — two sanctioned destinations:**
   - **Repo-shipped (recommended):** `src/main/resources/assets/eclipse/fx/<id>.fx`
     (e.g. `altar_levelup.fx`, `expansion_rift_glow.fx`). It rides inside the Eclipse
     jar like any asset; `.fx` files authored by us are OUR data (GPL applies to
     Photon's CODE — shipping our own effect data does not pull GPL into the ARR jar,
     consistent with the BUNDLING.md "never jarJar the mod itself" line).
   - **Resource pack (drop-in):** `assets/eclipse/fx/<id>.fx` inside any enabled pack —
     the path Photon's resource-reload sees is identical. Useful for server operators
     iterating without a mod update (this is the option today's `PhotonBridge` javadoc
     and BUNDLING.md describe).
5. **Id contract:** the file name must match the logical id path the bridge/registry
   uses (`eclipse:altar_levelup` → `fx/altar_levelup.fx`). New effects = new constant in
   `PhotonBridge` (or a `PhotonFxRegistry` row) + the asset; nothing else.
6. **Verify:** join a world with Photon installed and trigger the cue; success is the
   absence of the one-time INFO `Photon is loaded but assets/eclipse/fx/<id>.fx is
   absent` and the effect visibly playing with (LAYER) or instead of (REPLACE) the
   Quasar cue. A WARN `Photon effect <id> failed` means a bad blob — regenerate.
7. **Do NOT commit third-party `.fx` files** ripped from other packs/mods (license), and
   do not add Photon to `required` anywhere — the whole design premise is optionality.
