# EVAL-V6-PHOTON — precision audit

**Score: 7.6 / 10**

Audit scope: the Photon specifications and five IDEA files, all `tools/photon/*.py`,
`PhotonBridge`, `PhotonFxRegistry`, the eight content registrars plus the PH-CORE reference
registrar, Photon client controllers, FX payloads, replay seams, distribution tooling, and
every shipped `.fx` below `src/main/resources/assets/eclipse/fx/`. This was a read-only
static audit except for this report and the requested Python validator/dump commands. No
Gradle or Git command was run.

## 1. Asset and format validation

Command:

```text
python3 tools/photon/fxlib.py validate \
  src/main/resources/assets/eclipse/fx/*.fx \
  src/main/resources/assets/eclipse/fx/*/*.fx
```

**PASS: 68/68 files**, including the 58 root assets and 10 `fx/boss/` assets. There were
no validator errors.

Five independent dumps were checked against `FX_FORMAT.md`:

| Asset | Schema evidence checked | Result |
|---|---|---|
| `hound_dash_trail.fx` | gzip compound root; `fxData.fxObjects`; `ara_trail_emitter`; `data.version` Int 2; transform UUID; `curve` with `min/max/lower/upper/xAxis/yAxis/lockControlPoint/curves`; `gradient.gradientColor` | PASS |
| `credits_strike_beam.fx` | two `beam_emitter` objects and one `particle_emitter`; per-emitter version 2; beam `end/width/emitRate/raycast/color`; constant, random-constant, curve and gradient NF shapes; cone shape | PASS |
| `template_burst.fx` | `particle_emitter` version 2; exact NF3 list shapes; constant/random-constant/curve/gradient wrappers; sphere shape; renderer ROM list | PASS |
| `award_star_shower.fx` | version 2 emitters; mesh shape `{type,meshData.modelLocation}`; Model renderer with block-atlas material; collision sub-emitter with constant probability | PASS |
| `expansion_rift_glow.fx` | top-level `empty` correctly has no emitter version; flat UUID-linked hierarchy; child particle emitters have version 2; circle/sphere shapes and constant/random/curve/gradient wrappers | PASS |

The sampled bytes agree with `FX_FORMAT.md:28-58`, `FX_FORMAT.md:96-117`,
`FX_FORMAT.md:122-174`, and `FX_FORMAT.md:217-250`.

### Validator precision defect

`fxlib.py`'s success is useful but not a full schema proof. `_validate_nf_wrappers` only
checks whether a `{type,data}` discriminator is known; it does not validate the required
data members or NBT tag shapes for constant/random/curve/gradient, and it does not enforce
three elements for NF3 (`tools/photon/fxlib.py:1183-1197`). Beam, trail, and ara-trail
configs receive only the generic config/version check; detailed config validation is
limited to particle emitters (`tools/photon/fxlib.py:1148-1155`). Child lists are not
cross-checked against parent links (`tools/photon/fxlib.py:1156-1161`). Therefore malformed
NF data or non-particle config can still print `OK`, despite `validate_file` describing
itself as a full structural check (`tools/photon/fxlib.py:1200-1213`). The five manual
dumps mitigate this for the sample, not for every field in all 68 files.

## 2. Reflection and graceful degradation

### Exact 2.1.5 signatures

**PASS.** Every reflected class, member name, and parameter list in
`PhotonBridge.resolve()` matches `API.md`:

| Bridge member | API evidence | Result |
|---|---|---|
| `FXHelper.getFX(ResourceLocation)` | `API.md:16-30` | exact |
| `BlockEffectExecutor(FX, Level, BlockPos)`; `start()` | `API.md:62-78` | exact |
| `EntityEffectExecutor(FX, Level, Entity, AutoRotate)`; `start()` | `API.md:80-92` | exact |
| `setOffset(Vector3f)` | `API.md:44-54` | exact |
| `setRotation(Quaternionf)` | `API.md:44-54` | exact |
| `setScale(Vector3f)` | `API.md:44-54` | exact |
| `setDelay(int)` | `API.md:44-54` | exact |
| `setAllowMulti(boolean)` | `API.md:44-54` | exact |
| `getRuntime()` | `API.md:44-54` | exact |
| `FXRuntime.isAlive()` | `API.md:94-105` | exact |
| `FXRuntime.destroy(boolean)` | `API.md:94-105` | exact |

The implementation points are `PhotonBridge.java:706-726`.

### Failure scenarios

- **Photon absent:** `available()` returns false before resolution; every public spawn path
  converges on `startExecutor` and returns failure without touching Photon
  (`PhotonBridge.java:284-289`, `PhotonBridge.java:476-485`).
- **LDLib2 absent:** NeoForge normally rejects the required dependency before game start.
  If linkage reaches the bridge anyway, `Class.forName`/member resolution throws, is caught,
  and sets session state to `DISABLED` (`PhotonBridge.java:693-738`, `PhotonBridge.java:750-755`).
- **Wrong Photon version:** missing/renamed classes or signatures disable the bridge once.
  Invocation-time failures are caught and session-skip only the affected FX id
  (`PhotonBridge.java:522-528`). Quasar/vanilla legs continue.
- **Missing/corrupt asset:** null load or invocation failure becomes a no-op and a session
  skip (`PhotonBridge.java:493-497`, `PhotonBridge.java:522-528`).

### Wrong-version weakness

The four public `AUTO_ROTATE_*` values are hard-coded ordinals
(`PhotonBridge.java:155-159`). Resolution checks only that the enum has at least four
members, not that the names/order are exactly `NONE, FORWARD, LOOK, XROT`
(`PhotonBridge.java:718`, `PhotonBridge.java:727-730`). A future but link-compatible Photon
version that inserts or reorders constants would reach `READY` and silently orient entity
effects incorrectly instead of degrading. Resolve and verify the four enum names, or use
`Enum.valueOf` by verified name.

## 3. Registry, fallbacks, and budget

The prompt's “8 registrar classes” is the eight content registrars. Including the
`PhotonFxRows` PH-CORE smoke/reference registrar, there are **9 registrars and 27 rows**:

| Registrar | Rows |
|---|---:|
| `PhotonFxRows` | 2 |
| `EventsPhotonFxRows` | 3 |
| `BossPhotonFxRows` | 4 |
| `AltarPhotonFxRows` | 1 |
| `WorldPhotonFxRows` | 5 |
| `MobPhotonFxRows` | 4 |
| `WandPhotonFxRows` | 3 |
| `PlayerFxPhotonRows` | 1 |
| `HeraldFerrymanFxRows` | 4 |

**PASS: no duplicate logical cue id.** All 27 ids are unique. Runtime registration is also
collision-safe: `putIfAbsent` makes the first row win and warns on a duplicate
(`PhotonFxRegistry.java:120-131`).

**PASS: null fallbacks are documented.** There are 19 null-fallback rows. Each is identified
as pre-existing vanilla/Quasar baseline or pure garnish by its registrar documentation:
the template loop, all event rows, warden laser, altar corona, all world rows, all mob rows,
all wand rows, and heart theft. The eight non-null rows are the template burst, three boss
rows, and four Herald/Ferryman rows.

**PASS: the 24-executor hard cap covers all bridge-created executors.** Block one-shots,
entity one-shots, direct loops, registry loops, and `ensureAttachedFx` all converge on
`startExecutor`; it sweeps and refuses at `LIVE.size() >= 24` before construction
(`PhotonBridge.java:476-520`). Custom multi-executor legs remain safe because each leg
enters the same gate independently.

Minor accounting defect: the Herald shard ribbon's local six-entity guard says to skip
when six are already alive, but uses `>` rather than `>=`
(`HeraldFerrymanFxRows.java:49-53`, `HeraldFerrymanFxRows.java:123-128`). It can admit a
seventh entity executor. The global 24 cap still holds.

## 4. Payloads and replay parity

### Codec and registration

**PASS.** `S2CFxEntityEventPayload` writes and reads the same seven wire values in the same
order: id, entity id, x, y, z, a, b (`S2CFxEntityEventPayload.java:35-51`). The record is
reconstructed correctly.

**PASS: no double-registration residue.** `S2CFxEventPayload` and
`S2CFxEntityEventPayload` each have one unique type id and exactly one `playToClient`
registration (`S2CFxEventPayload.java:20-30`,
`S2CFxEntityEventPayload.java:32-51`, `FxPayloads.java:67-79`). Repository-wide searches
found no second registration or duplicate `"fx/entity_event"` id.

### Replay parity

- **Intro BURST: PASS.** Live and replay both send `FX_SHOCKWAVE(1.0, 50)`, which enters
  the same `INTRO_BURST_RING` client seam (`IntroSequence.java:565-570`,
  `IntroSequence.java:874-881`, `FxPayloads.java:139-148`).
- **Credits LIGHTNING: PASS.** Live and replay both pair each lightning payload with
  `CUE_CREDITS_STRIKE`, preserving intensity (`CreditsSequence.java:626-636`,
  `CreditsSequence.java:1344-1365`).
- **Expansion STRUCTURES: PASS.** Live and replay both send `CUE_STRUCTURE_SLAM` with a
  footprint (`ExpansionSequence.java:686-690`, `ExpansionSequence.java:1168-1179`).
- **Credits burst: FAIL.** Live `beatBurst` sends `FX_SHOCKWAVE(1.0, 50)`, the confetti cue,
  and the white flash (`CreditsSequence.java:672-683`). The `CORRECTION` replay sends the
  flash and confetti cue but omits `FX_SHOCKWAVE` (`CreditsSequence.java:1387-1394`).
  Consequently replay loses both the base shockwave and the Photon
  `INTRO_BURST_RING` enhancement, contradicting the method's “like the live beats” replay
  contract (`CreditsSequence.java:1311-1314`).

## 5. Loop discipline

Compliant controllers:

- `AltarCoronaIdle`, `BreachAmbience`, and `EndVoidWisps` have materialize/release distance
  bands, retry cadence, immediate `reducedFx` close, dimension gate, and logout release.
- `StormFxClient` has an attach/release shell-distance band, availability kill, retry
  cadence, and resource teardown.
- `RiftFx` uses the rift lifetime as its event window, explicitly kills on `reducedFx`,
  and disposes on close, dimension change, and logout.
- `PhotonMobFx` and the player attached-loop controllers use range/state/event windows,
  explicit guard-chain kills, and bridge level/entity cleanup. `WandAuraClient` and
  `PhotonMobFx` also have true distance hysteresis.

### Growth-rider lifecycle defect

`ExpansionSequence.ClientHooks.tickRiderRibbon` does not test
`PhotonBridge.available()` or `reducedFx` before returning an already-live handle
(`ExpansionSequence.java:1456-1470`). Turning `reducedFx` on therefore leaves the looping
growth ribbon alive until the server releases the rider or the entity disappears, violating
the unconditional force-kill law in `INTEGRATION.md:285-297`.

The same controller does not clear `growthRiderId` on dimension change. The Clone handler
only clears the new-land state, while logout alone releases the rider
(`ExpansionSequence.java:1534-1545`). After the bridge sweeps the old handle, the controller
continues looking up the old numeric entity id in the new level and can attach the ribbon
to an unrelated entity that reused that id (`ExpansionSequence.java:1466-1480`). It must
close the logical window on dimension/player clone, not only rely on bridge executor cleanup.

## 6. Client/server distribution and side isolation

**PASS.** There are no compile-time imports or references to
`com.lowdragmc.photon.*` outside the string-based reflection in `PhotonBridge`. The bridge,
registry, registrars, and controllers are client-dist marked. Common senders reference only
`FxCues` and payload helpers. The one common entity client seam is inside an
`isClientSide` branch and lazily resolves an Eclipse client registrar, never an upstream
Photon class (`HeraldShardProjectile.java:133-145`).

**PASS.** `fetch_dev_mods.py` places pinned Photon 2.1.5 and LDLib2 2.2.29 jars in both
`run/mods-client` and `run/mods`, matching the non-optional network-channel verdict
(`tools/modpack/fetch_dev_mods.py:40-53`).

### Documentation drift defect

`INTEGRATION.md` is internally contradictory and no longer precise enough to be an
as-built guide:

- it describes “current two hardcoded seams,” says `PhotonBridge` is the only touching
  class, and lists only the block-executor reflection (`INTEGRATION.md:3-22`);
- it says the dedicated-server set does not include Photon/LDLib2
  (`INTEGRATION.md:53-60`), while the current fetch script installs both;
- its later shipped-note correctly documents the expanded registry, entity executor,
  loops, and 24 cap (`INTEGRATION.md:121-139`);
- its risk/workflow still says no `.fx` assets ship and treats `altar_levelup` as future
  (`INTEGRATION.md:305-313`, `INTEGRATION.md:323-349`), although 68 assets are present.

`API.md` likewise says the bridge has only “all three reflected points”
(`API.md:166-175`), although its earlier core-class sections do accurately document the
additional signatures now used. These contradictions do not break runtime behavior, but
they materially reduce the integration's precision and make review against the alleged
source of truth error-prone.

## 7. Defects ranked

1. **High — growth-rider loop violates accessibility and dimension cleanup.**
   `ExpansionSequence.java:1456-1480`, `ExpansionSequence.java:1534-1545`.
2. **Medium — as-built integration documentation is stale and self-contradictory.**
   `INTEGRATION.md:3-22`, `INTEGRATION.md:53-60`, `INTEGRATION.md:305-349`;
   `API.md:166-175`.
3. **Medium — credits burst replay omits the giant shockwave and therefore the Photon HDR
   ring.** `CreditsSequence.java:672-683`, `CreditsSequence.java:1387-1394`.
4. **Medium — `fxlib.py validate` does not validate NumberFunction payload shapes or
   non-particle emitter configs despite presenting a full structural check.**
   `tools/photon/fxlib.py:1148-1213`.
5. **Low/medium — AutoRotate compatibility is ordinal-only; a reordered compatible enum
   silently misorients effects rather than disabling the bridge.**
   `PhotonBridge.java:155-159`, `PhotonBridge.java:718-730`.
6. **Low — Herald ribbon's local six-entity guard admits a seventh.**
   `HeraldFerrymanFxRows.java:49-53`, `HeraldFerrymanFxRows.java:123-128`.

## 8. Verdict

The shipped core is stronger than the score might suggest: all assets validate, the sampled
NBT is schema-accurate, current 2.1.5 reflection is exact and fail-soft, registry collisions
are absent, the global 24 cap is centralized, payload encoding/registration is clean, and
server distribution is correct. The score is held down by one real loop-lifecycle bug, one
visible replay-parity omission, a validator whose coverage is shallower than its contract,
and substantial source-of-truth documentation drift.
