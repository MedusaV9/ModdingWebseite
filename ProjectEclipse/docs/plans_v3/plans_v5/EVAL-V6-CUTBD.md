# EVAL-V6-CUTBD — cutscene + block-display precision

## Verdict

**Overall: 8.0/10.** The asset bookkeeping is unusually strong: all nine edited cutscene
documents parse, all authored keyframe times are strictly increasing, every FOV is finite and
sensible, all caption keys exist in both locales, all event types/sounds resolve, and every
pre-v6 bundled hash is in `LEGACY_DEFAULT_HASHES`. The display work mostly uses the claimed
lead-keyframe interpolation correctly and is packet-bounded.

Precision falls short at three choreography seams: the BD-SHIP morph sampler erases CUT-END's
per-piece launch stagger, END shatter's server beats are not clocked from the client's preload
release, and the expansion flyover cannot guarantee a radial front crossing because its offsets
are not rotated to the selected front angle. There is also one concrete restart leak: END debris
has only a loaded-chunk boot query and no join-time stray guard.

## Method

- Read the actual parser and consumers: `CutscenePath.parse`, `CameraDirector.fireEvents`,
  easing mapping, preload clock, and `FxAnchors`.
- Replayed the parser's structural accesses over every bundled path, then additionally required
  strict authored `t` order/range, finite `1 <= fov < 180`, valid lookAt shapes, valid event data,
  and caption parity in `en_us`/`de_de`.
- The `v6 wave B` commit is `8b18a23c...`; its parent is `8c2bfca6...`. Because this evaluation
  forbids git commands, commit/tree/blob objects were read directly from `.git/objects`, and the
  parent blobs were SHA-256 hashed byte-for-byte.
- This is a source/asset precision audit only; no Gradle or runtime client was used.

## 1. Cutscene schema, localization, and event resolution

`CutscenePath.parse` requires an object, numeric `t`, a `pos` array with at least three numeric
entries, and parseable optional scalar fields (`CutscenePath.java:181-225`). It sorts keyframes
after parsing (`CutscenePath.java:200`); `CameraDirector` separately sorts events
(`CameraDirector.java:203-207`). Therefore malformed author order would not crash, but was still
graded as a precision failure. None failed.

| path | keyframes | FOV range | events | captions en+de | event names/data | result |
|---|---:|---:|---:|---|---|---|
| `intro_v3_ship` | 6 | 62–70 | 5 | pass | pass | PASS |
| `intro_v3_flight` | 6 | 62–78 | 8 | pass | pass | PASS |
| `intro_v3_reveal` | 5 | 55–60 | 4 | pass | pass | PASS |
| `expansion_skyward` | 7 | 60–85 | 6 | pass | pass | PASS |
| `expansion_flyover` | 7 | 70–80 | 4 | pass | pass | PASS |
| `unlock_ring` | 6 | 54–70 | 5 | pass | pass | PASS |
| `end_shatter` | 8 | 60–79 | 18 | pass | pass | PASS |
| `finale_return` | 5 | 60–70 | 6 | pass | pass | PASS |
| `credits_helm` | 4 | 58–66 | 3 | pass | pass | PASS |

Details:

- All keyframe and event times are in `[0,1]`; keyframes are strictly increasing as authored.
- Every lookAt is absent, `player`, a numeric three-vector, or
  `anchor:eclipse:altar_center`. The latter resolves to `FxAnchors.ALTAR_CENTER`
  (`FxAnchors.java:38-40`; `CameraDirector.java:738-740`).
- Every event type is one of the four implemented cases: `sound`, `caption`, `fade`, `shake`
  (`CameraDirector.java:509-549`). Fade colors, including `#59EFE8FF`, parse through the
  prefix-tolerant AARRGGBB parser (`CameraDirector.java:574-585`).
- Every `eclipse:` sound appears in `sounds.json`; the four referenced `minecraft:` sounds are
  vanilla event ids. No event silently falls through the unknown-type branch.
- All fourteen distinct cutscene caption ids occur in both locale files
  (`en_us.json:1253-1293`, `de_de.json:1253-1293`).

## 2. Default-refresh hashes

The raw tree diff between `8c2bfca6...` and `8b18a23c...` shows exactly these nine edited
cutscene JSONs. Every parent-blob hash is present under the matching id in
`CutscenePaths.LEGACY_DEFAULT_HASHES` (`CutscenePaths.java:87-121`).

| id | SHA-256 of pre-edit blob | ledger |
|---|---|---|
| `intro_v3_ship` | `02da214a113afcd21ac34f75fe8368400909b927d95463d696e15ef297d59ac7` | match |
| `intro_v3_flight` | `f7188ad86c759a9b58e1d4f93af4020214a02d09d05ebe43428b7921951e1ee6` | match |
| `intro_v3_reveal` | `4ec430af2c612ab8d2519a86d26547b667a7573cda0e09be16815765255eecca` | match |
| `expansion_skyward` | `ffe1fbd4a8c534061a1638b4b83439d079f8858e656e2ee5caee80dc9d2370ea` | match |
| `expansion_flyover` | `5be44de155998abf24cdb33af989f27c752232d903181fc630b2f97a94edce2a` | match |
| `unlock_ring` | `e118ac2b32e0e1ff3d89f8e14261ccd57102e9c48cbd064925f20ec8a0f8506e` | match |
| `end_shatter` | `dfe571268d427b708554b573d47ad3414aa8b7831b80ddf7dcc25bf314c226e1` | match |
| `finale_return` | `0bcf7ed27add164030fb20d78c14b2c8a66064d46b7ea373034b2d506e176dfe` | match |
| `credits_helm` | `d1534925895f730513eda34d6ee070dcc795c97828727be764926581490576df` | match |

**Result: PASS, no stale-default upgrade hole.**

## 3. Display interpolation, lifecycle, and packet sanity

| family | interpolation transport | tag / restart handling | peak transform pushes | verdict |
|---|---|---|---:|---|
| structure delivery | duration 2, target `age+2` (`StructureFlightFx.java:516-536`) | tag + live UUID join guard (`StructureFlightFx.java:272-280`) | up to ~800/s/client for 80 airborne pieces | pass; high but short and capped |
| END debris | duration 4, target `age+4` (`EndShatterSequence.java:618-633`) | tag, but loaded-only boot query and no join guard | up to ~600/s/client for 120 pieces | **restart fail** |
| ferry morph | duration 8, target window end (`ArenaFight.java:583-601`) | tag + limbo boot sweep (`ArenaFight.java:839-844,963-971`) | roughly 7 pushes/piece over 60t | interpolation pass; **stagger fail** |
| arena ghost helm + lanterns | duration 20, target `gameTime+20` (`ArenaBuilder.java:441-447`) | sweep-then-spawn + join guard (`ArenaFight.java:839-856,943-953`) | 5/s/client total | pass |
| altar assembly stones | delayed duration 18, then duration 6 snap (`AltarDoor.java:317-331`) | recorded-door repair, tag sweep, late-join guard (`AltarDoor.java:228-256`; `ArenaFight.java:943-953`) | 30 transform pushes + 15 snap-light updates | pass |
| wind shard | duration 20 / charge duration 3, both lead-targeted (`SkyLauncher.java:764-789`) | persistent; placement sweep + self-heal (`SkyLauncher.java:671-677,719-727`) | 1/s idle, ~6.7/s charging | pass with overwrite caveat |
| credits wheel | duration 4, target `t+4` (`CreditsSequence.java:867-882`) | tag + live UUID join guard (`CreditsSequence.java:288-305`) | 5/s/client | pass |
| credits flyers + shadows | duration 2, target progress `+2t` (`CreditsSequence.java:1033-1055`) | same tag/join guard; explicit discard | at most ~360/s/client for 36 displays, 7s | pass; bounded burst |

The claimed lead-keyframe law is genuinely implemented in delivery, debris, accents, shard,
wheel, and flyers. There are no per-tick display teleports in those families. The PH-RIFT
growth rider intentionally uses entity `moveTo` every tick because it is an invisible executor
anchor, not a rendered display animation (`ExpansionSequence.java:775-815`); that is outside the
block-display visual interpolation claim.

### Defects

1. **HIGH — orphaned END debris can survive a restart.**
   `sweepDebris` queries one large AABB but does not force-load its many disc chunks
   (`EndShatterSequence.java:680-691`). `onServerStopped` clears the only live list
   (`EndShatterSequence.java:313-317`), and unlike delivery/credits/arena there is no
   `EntityJoinLevelEvent` guard for `DEBRIS_TAG`. A debris entity in an unloaded chunk during
   `ServerStartedEvent` can load later as a static, immortal leftover.

2. **HIGH — BD-SHIP collapses CUT-END's morph launch stagger.**
   `pushMorphKeyframe` computes progress from `windowEnd`, then applies the whole 8t
   interpolation with delay zero (`ArenaFight.java:583-601`). At the first t=2 push,
   `windowEnd=10`; every deck launch is in t=2..9, so every deck piece immediately begins
   moving at t=2. At the t=10 push, every remaining mast begins moving, even though computed
   mast launches extend through t=17. The intended 0–8/6–16 per-piece stagger becomes
   essentially two cohorts. The arc/roll math and CUT-END's whiteout still coexist, but the
   timing claim does not.

3. **MEDIUM — END shatter uses two unsynchronized clocks.**
   The server schedules rumble/crack/separation beats from `now` before starting the global
   cutscene (`EndShatterSequence.java:389-455`). A world-anchored client resets its camera/event
   clock only when preload releases (`CameraDirector.java:254-265`). A slow preload therefore
   plays the server crack race and debris behind the black hold while JSON sound/shake events
   start later. This directly weakens the advertised silence → first-crack cliff.

4. **MEDIUM — growth-front crossing is angle-dependent, not guaranteed.**
   `resolveGrowthFront` leads only the anchor radius (`ExpansionSequence.java:1015-1033`), while
   flyover keyframe offsets are fixed world X/Z values (`expansion_flyover.json:12-18`).
   At the lowest keyframe the `[2,30]` horizontal offset projects anywhere from about −30 to
   +30 blocks along the radial direction depending on watcher angle. The same lead cannot make
   the real front pass beneath the camera at t≈0.5 for every play. This limitation is admitted
   in the team log, but it remains a precision miss against the beat claim.

5. **MEDIUM — the credits wheel caption does not land on the grip settle.**
   `credits_helm` fires the wheel caption at path t=0.72 (`credits_helm.json:20-21`). With the
   shot starting at run t=40 and lasting 140t, that is run t≈141. The grip begins at run t=148
   (`CreditsSequence.java:142-147,503-508`): about seven ticks later even with zero preload.
   Since the shot is world-anchored, preload can shift the client caption further relative to
   the server-run wheel clock.

6. **LOW — ambient shard updates can overwrite charge updates on the same tick.**
   Charge updates execute before the 20t ambient update (`SkyLauncher.java:217-230`). When a
   3t charge stride coincides with an ambient boundary, the boost target set at
   `SkyLauncher.java:318-324` is immediately replaced by the boost-free 20t target at
   `SkyLauncher.java:719-724,764-789`. Interpolation prevents a hard snap, but the intended
   monotonic spin-up briefly drops toward idle.

## 4. Cross-team collision checks

### `ArenaFight` — CUT-END + BD-SHIP

**Partially coherent.** The same 60t stage, whiteout at t=25, escalating shakes, veil gust,
tag sweep, and final cleanup remain intact (`ArenaFight.java:525-562,652-689`). BD-SHIP's
piecewise arc/roll windows also stay below its stated angular threshold. However, defect 2
means BD-SHIP did not preserve CUT-END's launch timing despite recomputing the launch values.
This is a real cross-team semantic collision, not merely stale prose.

### `ExpansionSequence` — CUT-EXPANSION + PH-RIFT

**Coherent.** `scheduleSkywardPunch` is armed only with SKYWARD and has run/supersession guards
(`ExpansionSequence.java:385-437`). The PH-RIFT rider is not spawned until `beginGrowth`, after
the flyover callback; early terrain completion bypasses it, normal completion discards it, and
abort/stop/join paths clean it (`ExpansionSequence.java:493-535,750-845,966-969`). The two
features occupy different phases and state fields. The flyover angle limitation above affects
shot accuracy, not coexistence with the rider.

## 5. Three weakest beats

1. **END silence/crack race.** Its emotional cut depends on one exact shared instant, but the
   server crack race starts before the client preload clock. Under the condition preload was
   designed to handle, the first crack can happen under cover and the JSON mirror arrives late.
2. **Ferry transform.** The underlying motion is richer, but the supposed per-piece launch
   pattern is flattened into deck-at-t2 and mast-at-t10 cohorts. That is visibly less precise
   than the CUT-END schedule it claims to preserve.
3. **Growth-wave flyover.** The camera has strong authored altitude/FOV craft, but a fixed-axis
   spline cannot consistently cross a radial wave selected from arbitrary watcher angles. The
   hero action is therefore world-orientation-dependent.

## Team scores

| team | score | precision judgment |
|---|---:|---|
| CUT-INTRO | **9.6/10** | All three paths, hashes, captions, sounds, FOV/easing/lookAt shapes pass; no material defect found. |
| CUT-EXPANSION | **7.9/10** | Schema/hash work and PH-RIFT coexistence are clean; flyover front sync is not geometrically invariant, and punch timing remains server-clock approximate. |
| CUT-END | **7.5/10** | Paths/hashes and beat ordering are careful, but the signature crack timing is not tied to preload release; its morph stagger is not preserved downstream. |
| CUT-CREDITS | **8.6/10** | Strong lifecycle and bounded display choreography; wheel-caption sync is arithmetically wrong and remains clock-domain-sensitive. |
| BD-STRUCT | **7.8/10** | Excellent lead transport and ~4× debris packet reduction; missing late-load debris cleanup is a material restart-safety hole. |
| BD-SHIP | **7.4/10** | Most families have correct lead, tags, sweeps, and sane rates; morph staggering is functionally lost and shard drivers can overwrite each other. |

## Bottom line

No cutscene JSON or default-refresh hash blocks shipment. The release blockers for precision are
the END-debris late-load cleanup and the ferry morph launch sampler. The END beat clock and
flyover orientation need an engine-level/shared-clock follow-up if their logs are to claim exact
sync rather than best-effort staging.
