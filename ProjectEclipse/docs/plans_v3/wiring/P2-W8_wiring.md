# P2-W8 wiring notes — Rift & portal tech + transition assets

Zero foreign-file edits: no `EclipseMod` / `EclipsePayloads` / `FxPayloads` /
`EclipseCommands` / lang / build changes. Everything self-registers
(`@EventBusSubscriber(Dist.CLIENT)`) or is a static-init pipeline row. No new sounds, no
new textures, no new lang keys (`langdrop/P2-W8.json` is the empty en/de shape — the rift
sound subtitles were W1's).

## What W8 landed

| File | What |
|---|---|
| `veilfx/rift/RiftFx.java` C | Rift registry + lifecycle; FROZEN `openRift`/`closeRift` handlers (already referenced by W1's `FxPayloads` dispatch — signatures verified against that call site) |
| `veilfx/rift/RiftRenderer.java` C | World-space star-tear + portal-surface renderer (`AFTER_PARTICLES`; the documented Sodium fallback swap to `AFTER_TRANSLUCENT_BLOCKS` is one constant) |
| `veilfx/rift/package-info.java` C | Package doc |
| `veilfx/TransitionFx.java` C | FROZEN R13 client API + owns the `eclipse:rift_glitch` pipeline row (TRANSITION priority) |
| `assets/eclipse/pinwheel/post/rift_glitch.json` + `shaders/program/rift_glitch.fsh/.json` C | The transition pass (uniforms frozen: `GlitchAmount, FadeAmount, Time`; uses `eclipse:eclipse_common` helpers, zero textures) |
| `assets/eclipse/quasar/emitters/rift_spark.json` C | Edge crackle loop (rate 3 / count 2) — `RiftFx` walks it along the tear rim every tick |
| `assets/eclipse/quasar/emitters/portal_surface_motes.json` C | Portal suck-in motes loop (rate 4 / count 1), reverse-swirl + inward pull (see deviations) |

## Frozen surface delivered (exact, for consumers)

```java
// veilfx.rift.RiftFx — dispatched by FxPayloads for eclipse:fx/rift_open|close
public static void openRift(Vec3 pos, Vec3 normal, float width, int durationTicks, int style);
public static void closeRift(Vec3 pos);
public static final int STYLE_STRUCTURE = 0;   // = payload b 0
public static final int STYLE_PORTAL = 1;      // = payload b 1

// veilfx.TransitionFx — R13
public static void playPortalEnter(int ticks); // glitch↑ then fade→1; STAYS black until exit
public static void playPortalExit(int ticks);  // fade→0 with glitch tail-off
public static void setLoadingPulse(float p01); // P3's screen: slow world-side glitch breathing
```

- **P5-W9 (xbox portal, THIS wave)**: portal spawn → `FxPayloads.sendFxEvent(level,
  FxPayloads.FX_RIFT_OPEN, portalPos, width, 1f, range)`; despawn → `FX_RIFT_CLOSE` at the
  same pos (close matches the nearest live rift within `max(4, width)` blocks — exact
  coordinates not required). Entry/exit: P3-W11's controller calls
  `TransitionFx.playPortalEnter(18)` / `playPortalExit(24)` — delivered verbatim. For the
  3×4 interaction portal a payload width (`a`) of **4.5–6** reads best; send it at the
  portal's *center* (the tear is centered on `pos`). `durationTicks` is only reachable via
  the direct client call (the payload always passes 0 = stay open) — fine for the portal.
- **P3-W11 (loading screens, next wave)**: drive `setLoadingPulse(p)` per frame while
  "receiving level" (values 0..1; the pulse **expires after 100 ticks without a refresh**
  and MUST be set to 0 when your screen closes). `playPortalEnter/Exit` also usable for
  generic loading fades. Heads-up: the P3 plan text references a pipeline id
  `eclipse:portal_glitch` — that id does not exist; the P2-frozen id is
  **`eclipse:rift_glitch`** (constant `TransitionFx.RIFT_GLITCH_POST`). Don't touch the
  pipeline directly — go through the `TransitionFx` API.
- **P2-W7 (structure rifts, next wave)**: `sendFxEvent(level, FX_RIFT_OPEN, site,
  diagonal * 1.2f, 0f, range)` → 40-tick hold → paste + your slam FX →
  `FX_RIFT_CLOSE` (30-tick collapse is client-side automatic). The open pulse is already
  ≤ 0.5 and distance-scaled per R11 — do NOT add another rift pulse.
- **P2-W9 (storm reveal)**: the reveal's "rift_glitch pulse 0.4" is
  `TransitionFx.glitchPulse(0.4F, 20)` (additive helper below) — no payload needed.
- **W6 (intro)**: the limbo→overworld hop reuses the same pair
  (`playPortalEnter(...)` at the FLIGHT fade, `playPortalExit(...)` after the teleport).

## Behavior contract (TransitionFx)

- `playPortalEnter(t)`: glitch ramps to 1 over the first ~60 % of `t`, fade starts at
  ~35 % and reaches full black at `t`; then a HOLD phase keeps the screen black (glitch
  settles to a 0.25 simmer — invisible behind black, keeps uniforms sane).
- `playPortalExit(t)`: fade releases 1→0 over `t` while the glitch spikes to 0.8 and tails
  off ("glitch tail-off"). Calling exit from an idle state degrades to a pure glitch tail
  (no black flash) — relog-safe.
- **Fail-safes**: the HOLD auto-releases after 1200 ticks (~60 s, logged) if exit never
  arrives; everything resets on logout. Client state survives the dimension change (that
  is the point — the destination stays black until `playPortalExit`).
- **Iris caveat (§7 risk 1)**: like every Veil post pipeline, `eclipse:rift_glitch` is
  gated off under an active Iris shaderpack / `veilPostFx=false`. The API still runs; the
  visible fallback during loading is P3's GUI screen (world-side tear geometry from
  `RiftFx` still renders — it is world-space).
- The frozen `EclipseFxState.startTransitionGlitch/transitionGlitch/transitionFade`
  blackboard is mirrored on every enter/exit (coarse single envelope); the pipeline itself
  is fed from `TransitionFx`'s richer two-curve state. Poll whichever you need.

## Additive helpers beyond the frozen list

- `TransitionFx.glitchPulse(float amplitude, int decayTicks)` — short screen-glitch pop,
  no fade; weaker pops never replace a stronger live one. `RiftFx` feeds it on open/close
  (≤ 0.5, distance-scaled 16→64 blocks); W9's reveal should use `(0.4F, 20)`.
- `TransitionFx.RIFT_GLITCH_POST` — the pipeline id constant.

## Portal orientation gotcha

The FX payload carries no plane normal, so W1's dispatch hard-codes `(0,1,0)`. A PORTAL
rift arriving with a (near-)vertical normal is **stood upright facing the local camera at
open time** (frozen thereafter; +Z with no camera). STRUCTURE rifts keep the up normal —
they open flat in the sky over the build site. If P5 ever needs a server-authored facing,
extend the payload (new field or an `S2CFxEventPayload` sibling id) — do not repurpose
`a`/`b`.

## Deviations from the plan text (visual result identical)

1. **"sucked inward via reverse `veil:vortex`"** — Veil 4.3.0's vortex force is purely
   tangential (verified in the jar: `velocity += normalize(radial × axis) · strength`), so
   a reversed vortex alone cannot suck anything inward. `portal_surface_motes` therefore
   pairs a reverse-axis `veil:vortex` (the reverse swirl) with a `veil:point_attractor`
   (the actual inward pull) + `veil:drag` (terminal velocity). Emitter id, rate 4 / count 1
   and the frozen behavior ("sucked inward, spiraling") are unchanged.
2. **Close sound** — §3.5's frozen sound list has no rift-close event; close plays
   `event.rift_open` at pitch 0.65 (the W7 slam beat stays the sender's job).
3. **Spark placement** — one static emitter JSON cannot scale its shape to a 1.5–48-block
   tear, so `RiftFx` repositions the single `rift_spark` loop emitter to a random rim
   point every client tick (crackle rides the edge at any width; one emitter per rift).
4. `RiftFx.closeRift` tolerance is `max(4, width)` blocks (float-exact matching would be
   fragile across the network round-trip).

## Budgets & lifecycle (for reviewers)

- ≤ 8 concurrent rifts (oldest evicted); ≤ 160 tris per rift (400 frozen cap); d² early-out
  at 256 blocks; zero per-frame heap allocations (static scratch arrays, two sequential
  Tesselator passes — a Tesselator backs one live BufferBuilder at a time).
- Loop emitters charge `FxBudget.Channel.SEQUENCE` once per spawn; budget refusals retry
  every 20 ticks; handles pruned/`remove()`d on close, dimension change and logout
  (`LimboAmbience` pattern). No `veil:light` modules anywhere in W8 — zero FX lights used.
- `eclipse:rift_glitch` idle-skips: its activation predicate is false the moment the
  envelope, pulses and loading pulse are all zero, so the controller removes it from the
  manager (no no-op blits).

## Verification done (no gradle build/run — per worker rules)

- `javac` (release 21, moddev merged jar + Veil 4.3.0 + client library classpath): my 4
  files + the W1 core they depend on compile clean.
- A probe source mirroring the exact `FxPayloads` dispatch expressions and the frozen
  P5/P3/W9 call sites (`openRift(pos, new Vec3(0,1,0), a, 0, (int) b)`, `closeRift(pos)`,
  `playPortalEnter(18)`, `playPortalExit(24)`, `setLoadingPulse(p)`,
  `glitchPulse(0.4F, 20)`) compiles against the produced classes.
- All 4 new JSONs parse; emitter JSONs follow the committed emitter schema; module codec
  keys (`vortex_axis`, `vortex_center`, `local_position`, `range`, `strength`,
  `position`, `strength_by_distance`, `invert_distance_modifier`) verified against the
  Veil 4.3.0 jar's codecs.
