# P2-W4 wiring notes — Border v2 (localized glitch patches) + altar aberration

Zero `EclipseMod` / `EclipsePayloads` / `EclipseCommands` / `FxPayloads` edits. Both features
self-register: `border/client/BorderFxRenderer` (rewritten) and the new
`client/AltarAberration` are `@EventBusSubscriber(Dist.CLIENT)` classes whose static init
calls `VeilPostController.register(...)` (the W1 pattern — a feature row replaces the
backward-compat row regardless of class-load order).

## What W4 landed

- **Border v2 (R6)** — `border/client/BorderFxRenderer.java` rewritten:
  - The ±25°/±12-block **arc strip is gone** (that was the "long stripe" read). Replacement:
    5–9 small quad clusters (quads 2–4 blocks, random offsets/rotations/UV-jitter, additive
    `border_glitch.png`) pinned to the ring only within **±8° of the player's bearing**,
    further clamped to **±20 blocks of arc** on huge rings, at near-eye heights, re-seeded
    every 6–10 ticks → blocky "datamosh popping", never a wall. ≤ 54 quads (§3.5 cap 240),
    d² early-out, zero per-frame heap allocations (primitive seed arrays + scalar math).
  - Post `eclipse:border_glitch` v2 row (FEATURE): uniforms `Proximity, Time, GlitchDir,
    Seed` (§3.3 frozen). Strength curve `Proximity^1.5` lives in the shader; `GlitchDir` =
    NDC position of the nearest ring point, projected per frame through
    `SunTracker.worldToNdc` (the W1-sanctioned helper — no `veil:camera` use); the shader
    masks RGB tear (≤ ~14 px), coarse+fine `efxBlockOffset` row displacement and the
    `Proximity > 0.85` 2-frame invert pops to a lens around that point. When the ring point
    is behind the camera the lens parks just off the screen edge on the border's side.
  - **Nether variant hooks**: same renderer + pipeline. World patches tint red-shifted in
    the nether; the post shader reads the palette from the `Seed` uniform — **Seed ≥ 1000 =
    nether** (`postSeed = seed + 1000`), documented in the shader header. Ring geometry
    needs nothing new: `S2CBorderPayload` already syncs the `DiscProfile.NETHER` ring and
    `ClientStateCache.currentBorderRadius(true, now)` animates it.
  - Emitters: `border_glitch.json` strengthened (count 3→6, bigger/faster sprites, punchier
    alpha stutter); NEW `border_shard.json` (max_lifetime 3 / rate 1 / count 6, blocky
    0.4–1.4 sprites sampling `border_glitch.png`) popped at cluster positions on re-seed.
    All spawns charge `FxBudget.Channel.BURST`; refusals drop silently per W1 law.
- **Altar aberration (R9)** — NEW `client/AltarAberration.java` + `eclipse:altar_aberration`
  pipeline (FEATURE, single frozen uniform `Aberration`):
  - Zone: `Aberration = clamp(1 − dist/zoneRadius, 0, 1)² · 0.85`, slewed over 10 ticks,
    published to `EclipseFxState.setAltarAberration` each tick. Center =
    `FxAnchors eclipse:altar_center` (3D distance — correct around the P6-W4 floating
    sanctum), fallback = world spawn XZ (`ClientStateCache.borderCenter*`, horizontal
    distance) until the anchor syncs. Zone radius = synced stage-0 spawn disc
    (`min(ClientStateCache.stageRadiusOverworld, DiscGeometry.MAIN_DISC_RADIUS)`, floor 24)
    so later stage growth never widens the zone. Overworld only.
  - Shader: radial RGB split from screen center (≤ ~10 px), 0.3 Hz breathing (baked into
    the fed value CPU-side so the shader keeps the ONE frozen uniform), ~1% barrel
    distortion easing in above 0.6.

## Hub-file edit (sanctioned) + notes for W1

- **Deleted the deprecated `VeilPostController.setBorderProximity(float)` shim** — the
  P2-W1 wiring doc explicitly sanctions this ("delete it in your PR once nothing references
  it"). `BorderFxRenderer` now feeds `EclipseFxState.setBorderProximity` directly; a repo
  grep shows zero remaining callers. No other W1-file lines touched.
- The controller's backward-compat `eclipse:border_glitch` row (`wantBorderGlitch` /
  `feedBorderGlitch`) is now **dead at runtime** — W4's `register(...)` replaces it from
  `BorderFxRenderer`'s static init. Left in place (W1-owned never-overwrite path, and it
  still backs the `registerDefault` mechanism W3 uses); W1 may fold it away in a cleanup
  wave whenever convenient.

## Sibling contracts consumed / provided

- **P4/P6 (frozen §6.3/§6.5)**: whoever places the altar must call
  `FxAnchors.set(FxAnchors.ALTAR_CENTER, level, pos)` (P6-W4's sanctum flip or P4's intro
  flow). Until that lands, the spawn-XZ fallback keeps the gradient working on today's
  spawn-origin sanctum; the anchor makes the vertical falloff correct once the island
  floats. No code change needed on our side when it lands.
- **W2 dev commands**: `/eclipsefx post eclipse:border_glitch|eclipse:altar_aberration
  on|off` needs nothing extra — both rows respect `VeilPostController.setEnabled` /
  `clearOverride` overrides (predicates are only consulted when no override is set).
- **Mutual FEATURE throttle (R9)**: when BOTH border and altar signal simultaneously
  (geometrically near-impossible: the zone ends at the spawn disc, the ring sits outside),
  only the stronger pipeline activates — border wins ties. The comparison metrics
  (`Proximity^1.5` vs `Aberration · 0.85`) are duplicated one-liners in both classes,
  cross-referenced with "keep in sync" comments. Net effect: the pair can never spend 2 of
  the 3 concurrent post slots.
- **SoftBorder (server)**: NOT touched. All required data (center, from/to radius, lerp
  ticks, fxRange, per-profile nether ring) already syncs via `S2CBorderPayload`; no new
  server-side proximity data was needed.
- `network/S2CQuasarPayload.java` is frozen, so the client-local `border_shard` emitter id
  is a private constant in `BorderFxRenderer` (it is never server-sent; server pushback
  cues keep using `S2CQuasarPayload.BORDER_GLITCH`).

## Langdrop

`docs/plans_v3/langdrop/P2-W4.json` — **0 keys** (border/aberration are purely visual; no
user-visible strings). File ships the standard `{"en_us": {}, "de_de": {}}` shape for the
merge tool.
