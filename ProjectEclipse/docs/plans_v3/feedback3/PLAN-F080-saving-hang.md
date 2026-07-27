# PLAN F-080 — "Hängt für immer im SAVING State" (world quit / server stop hang)

> **User report (F-080):** _"Wenn man die Welt verlässt oder den Server stoppen will bleibt es
> für immer im SAVING State statt richtig zu beenden."_ — Leaving a world or stopping the
> server hangs forever in the SAVING state instead of shutting down.
>
> **Status:** read-only investigation done (no code changed). This plan lists every finding,
> ranks root-cause candidates, gives the exact fix per candidate and a verification recipe.
> All paths below are relative to `ProjectEclipse/` unless absolute.

---

## 1. Runtime evidence (from `run/logs/` + `run/crash-reports/`, read-only)

The dev run dir already contains multiple captured occurrences. Two distinct shutdown
behaviors exist:

### 1a. Singleplayer world quit — hangs 5-of-5 sessions, always at the same spot

Sessions `2026-07-25-4`, `2026-07-26-14`, `-16`, `-28`, `-29`, `-31`, `-32`, `-33.log.gz`:
every singleplayer quit follows this exact pattern and then the log **ends forever**:

```
[Server thread] Stopping server
[Server thread] Stopping singleplayer server as player logged out
[Server thread] Saving worlds
[Server thread] Saving chunks for level ... (×17 — overworld, nether, end + 14 eclipse dims)
[Server thread] ThreadedAnvilChunkStorage: All dimensions are saved      ← save COMPLETES
[Server thread/DEBUG] [voicechat/ClientPlayerStateManager] Sent own state to server: disabled=true   (×16–19, 1–2 ms apart)
<nothing, ever — no ServerStoppedEvent, no return to title, session dead>
```

Key deductions:

- The hang is **after `saveAllChunks` succeeded** — i.e. inside the per-level
  `ServerLevel.close()` loop of `MinecraftServer.stopServer()` (chunk-map flush /
  POI+IO-worker `.join()` / `PersistentEntitySectionManager.close()` entity flush), **before**
  `ServerStoppedEvent`. In the healthy dedicated stops (see 1b) the very next log lines are
  Create's per-level unload + our own `ServerStoppedEvent` debug lines
  ("EclipseClock supplier reset…", "EclipseSignals listener lists cleared") — those NEVER
  appear in any singleplayer quit.
- The Simple-Voice-Chat client-state spam on the **Server thread** (SVC short-circuits local
  S2C→client handling onto the sender thread in singleplayer) is the last sign of life. Its
  count (16–19) matches the dimension count (~17) suspiciously well — something per-level in
  the close loop is still pumping packets at the local player.
- In `2026-07-26-16.log.gz` a *second* JVM boots 2.5 s later into the same rolled file — the
  first (hung) client still held `latest.log`; the dev worked around by killing the PID
  (matches `AGENTS.md` §"Stopping lingering game instances").

### 1b. Dedicated `runServer` stop — Java-side shutdown completes, but…

Stops at 00:03:47, 00:10:57, 00:20:42 on 2026-07-27 (`2026-07-27-6/-7/-8.log.gz` +
`debug-4/-5.log.gz`): the full sequence completes in ~150 ms — save, level close (Create
unload spaces), **all our `ServerStoppedEvent` handlers**, `Unloading configs type SERVER`,
ending with `Thread RCON Listener stopped`. That line is the last thing a dedicated stop
ever prints even when healthy, so "console sits there after the Saving lines" is *invisible*
in-log; the hang (if any) is the **JVM not exiting** (non-daemon thread) — see RC-4/RC-5.

### 1c. The mid-run wedge that the disabled watchdog now hides

`run/crash-reports/crash-2026-07-27_06.04.04-server.txt`: `ServerHangWatchdog` killed a
dedicated server whose **Server thread was RUNNABLE inside
`ServerEntity.sendChanges` → `ChunkMap.tick`** with an absurd "tick took 2988006912 s"
(stale `nextTickTime` ⇒ the thread had been wedged a very long time). `run/server.properties`
now ships **`max-tick-time=-1`** (watchdog disabled) — so the same wedge today would make
`/stop` (which only sets a flag; `stopServer()` runs after the current tick *finishes*)
hang forever with the last visible lines being save/console output. The full thread dump in
that crash also proves: **every custom thread in the process is daemon** (voicechat, ldlib
ConfigSaver, JNA, etc.) except vanilla `Server thread` + `RCON Listener`.

---

## 2. Findings census (everything checked, with locations, ranked)

### Suspicious (ranked by likelihood of causing/aggravating F-080)

| # | Finding | Location | Why it can block shutdown |
|---|---------|----------|---------------------------|
| S1 | **All display-swarm/FX services clean up on `ServerStoppedEvent` — which never fires while `close()` hangs, and is *after* the final save anyway.** Thousands of Display entities (credits formation/black-hole acts, EndArrival 220-display helix, storm debris swarms, dome shards, border boulders, rift orbitals…) are still alive through `saveAllChunks` + `ServerLevel.close()`; entity flush across **17 dimensions** is exactly the phase the singleplayer hang dies in. Entities parked in chunks whose *timed* tickets expired sit in never-fully-loaded entity sections — the classic `PersistentEntitySectionManager.close()` busy-wait. | `sequence/endarrival/EndArrivalDebrisFx.java:211`, `sequence/StormDebrisFx.java:252`, `sequence/NetherUpheavalFx.java:225`, `woah/mansiondome/DomeShatterFx.java:160`, `worldgen/stage/ExpansionBorderFx.java:300`, `worldgen/stage/StructureFlightFx.java:362`, `ferryman/finale/DayRiftOrbits.java:193`, `ritual/CreditsSequence.java:527`, `woah/gravityrift/GravityRiftOrbitals.java:132`, `worldgen/end/EndIslandCrashFx.java:174`, `stormfx/StormSiege.java:219`, `worldgen/end/EndShatterSequence.java:520` (all `onServerStopped`) | Server thread `.join()`s the chunk/POI/entity flush per level in `stopServer()`; a section that cannot finish loading/saving never drains → silent forever-hang **after** "All dimensions are saved" — matching 1a exactly. |
| S2 | **`RingGrowthService.onServerStopping` drains up to 64 chunk "finishes" synchronously at stop** — each `finishChunk` does a **sync chunk load** (`chunkFor(chunkKey, true)`, line 1219) plus `BudgetedBlockWriter.ensureNeighborsLoaded` (3×3 sync loads, line 1257) plus a full decoration replay + relight. Worst case ≈ 64×9 sync loads with worldgen at shutdown; on a loaded box this looks like a multi-minute "SAVING" hang, and if the gen pipeline wedges the `managedBlock` wait is unbounded. | `worldgen/stage/RingGrowthService.java:293–336` (`MAX_SHUTDOWN_FINISHES`, `onServerStopping`), `:1339–1359` (`drainFinishQueue`), `:1218–1239` (`finishChunk`) | Runs on the server thread inside `stopServer()` *before* "Saving players"; sync chunk generation during shutdown is the textbook "waits on a condition while ticks are stopped" pattern the report hints at. Bounded in theory, unbounded if generation stalls. |
| S3 | **Vanilla tick watchdog disabled (`max-tick-time=-1`)** — converts any mid-tick wedge (evidence 1c: `ServerEntity.sendChanges`, plausibly display-rider chains and/or Sable's `ServerEntity` mixins) into a forever-hang on `/stop`/quit, because `stopServer()` only runs once the wedged tick returns. | `run/server.properties` (`max-tick-time=-1`); wedge stack: `crash-2026-07-27_06.04.04-server.txt` | `/stop`, `halt()`, and the SP quit all wait for the current tick to finish. Nothing kills the wedge anymore. |
| S4 | **RCON enabled + external RCON tooling.** `enable-rcon=true`, `rcon.password=eclipsedev`; `tools/rcon/rcon.py` drives the dev server. Vanilla only stops the *listener* on exit (`Thread RCON Listener stopped` — the literal last log line of every dedicated stop); an open/half-closed RCON **client** connection leaves a non-daemon `RCON Client` thread blocked in socket read → JVM never exits → console "hangs after the saving lines" (dedicated-only variant). | `run/server.properties`; `tools/rcon/rcon.py`; log tails in 1b | Non-daemon vanilla thread outliving `stopServer()`. Known vanilla behavior class (MC-112484 family). |
| S5 | **Third-party interplay during SP quit**: Simple Voice Chat 2.6.16's local-channel state ping-pong on the Server thread is the last thing alive in every hung quit (1a); Sable 2.0.3 mixins sit in chunk/entity serialization (`plot.serialization.ChunkMapMixin`, `server_entities_tick`, sub-level saving "Saving sub-levels…") and its own UDP channel closes mid-stop. Either can wedge the close loop in ways our code merely amplifies. | `run/mods/voicechat-neoforge-1.21.1-2.6.16.jar`, `run/mods/sable-neoforge-1.21.1-2.0.3.jar` | Not our code, but the pack ships them; must be isolated (A/B) before blaming only Eclipse code. |
| S6 | **`ArenaFight` force-loads pit chunks and never un-forces them on stop.** `forcePitChunks(arena, true)` (`setChunkForced`, line 891); `onServerStopping` (lines 1003–1014) resets stages but does NOT call `forcePitChunks(arena, false)`. Forced chunks persist in the `ForcedChunks` saved data → `eclipse:ferryman_arena` keeps ticking forced chunks on every subsequent boot. | `ferryman/ArenaFight.java:887–894`, `:1003–1014` | Not a direct stop-blocker (forced chunks still save/close), but it keeps a whole dimension's chunk system permanently busy across restarts — extra flush work in every future stop, and a leak regardless. |
| S7 | **Dev tools that block the server thread on chunk IO**: `StageIO` does `chunkMap.read(pos).join()` (line 428); `PristineSnapshots` calls `level.getChunkSource().save(true)` (line 57). If the IO worker is already draining/closed these `join()`s never return. | `devtools/StageIO.java:428`, `devtools/PristineSnapshots.java:25,57` | Only reachable via dev commands, so not the reported repro — but the same hazard class; worth guarding. |

### Checked and cleared (no shutdown risk found)

- **Thread pools / timers / shutdown hooks:** the mod creates exactly ONE executor —
  `skin/SkinService.java:58–61`, single-thread, **`setDaemon(true)`**, named
  `eclipse-skin-io`. No other `Executors.*`, `new Thread`, `Timer`,
  `ScheduledExecutorService`, or `Runtime.addShutdownHook` anywhere in `src/`.
  `skin/SkinHttp.java:36–39` uses the JDK `HttpClient` (daemon worker/selector threads,
  10 s connect+response timeouts, byte caps) — cannot pin the JVM.
- **Chunk tickets:** every custom `TicketType` is **timed/self-expiring**:
  `worldgen/stage/ChunkPreload.java:45` (400 t), `cutscene/CutsceneService.java:108` (300 t),
  `worldgen/stage/ExpansionBorderFx.java:210` (lifespan const),
  `worldgen/stage/BudgetedBlockWriter.java:36–49` (200/600 t),
  `woah/resonance/ResonanceFieldBuilder.java:96` (600 t). No permanent tickets, no
  un-removed `addRegionTicket`. (`removeTicketsOnClosing` would strip them at stop anyway.)
- **`ServerStoppingEvent` handlers** (only three exist): `RingGrowthService:313` (= S2),
  `ferryman/ArenaFight.java:1005` (clears transient state, bounded),
  `progression/goals/QuestDetectors.java:397` (sets a boolean). No waits/loops besides S2.
- **SavedData:** ~59 implementations, all follow "mutators mark dirty, disk writes happen on
  autosave" (e.g. `core/state/EclipseWorldState.java`, `analytics/AnalyticsState.java:29`);
  no blocking I/O or network in any `save()`; no per-tick `setDirty` storms found. All saves
  demonstrably completed in every hung session (1a — "All dimensions are saved").
- **Mixins:** the 4 server-relevant mixins are harmless to shutdown
  (`anonymity/mixin/MinecraftServerMixin` — status-ping player-sample strip;
  `PlayerListMixin` — join/leave message filter; `ServerGamePacketListenerImplMixin` — book
  edit / tab-complete blocks; `NaturalSpawnerMixin` — spawn tuning).
- **`CompletableFuture` usage:** only `completedFuture` returns in the two chunk generators
  (`worldgen/DiscChunkGenerator.java:131`, `backrooms/BackroomsChunkGenerator.java:88`).
- **Sync loads at arm time only:** `woah/mansiondome/MansionDomeService.java:255`
  (`probeHeight` sync-load, one-off at arm; commit `94658ee`) — not on the stop path.
- **`EclipseClock`** (`core/time/EclipseClock.java`) is an app-level epoch supplier for P4
  realtime systems; it does NOT touch `Util.timeSource`/tick timing — not the source of the
  bogus watchdog number in 1c.
- **PhotonBridge** (`veilfx/PhotonBridge.java`) is client-only, reflection-based, no threads.

---

## 3. Root-cause candidates & exact fixes (ranked)

### RC-1 — `ServerLevel.close()` never drains on singleplayer quit (top candidate; matches 1a)

**Hypothesis:** with ~17 dimensions and live FX display swarms, one level's chunk-map/POI/
entity flush cannot complete (pending entity section / IO-worker `.join()`), amplified or
triggered by S5's third-party serialization hooks. All Eclipse FX teardown currently runs
on `ServerStoppedEvent` — too late to help and unreachable while `close()` hangs.

**Fix (code, mod-side):**
1. Add `core/EclipseShutdownSweep` subscribed to **`ServerStoppingEvent`** (fires before
   "Saving players") that force-clears every live swarm using each service's existing
   force-clear/watchdog path, and logs one line per service with the discard count:
   `StormDebrisFx`, `EndArrivalDebrisFx`, `NetherUpheavalFx`, `DomeShatterFx`,
   `EndIslandCrashFx`, `StormSiege`, `ExpansionBorderFx` (gate release + boulder discard),
   `StructureFlightFx` (force-place pending deliveries — the code comment at
   `StructurePendingRegistry.java:361` already promises this is safe), `DayRiftOrbits`,
   `GravityRiftOrbitals`, `CreditsSequence` (abort acts, discard formation/black-hole
   displays), `EchoScenes`/`MemoryFloodService`, `DomeEmitter` strays. Keep the existing
   `ServerStoppedEvent` handlers as the static-reset layer (unchanged semantics for
   singleplayer world-swap hygiene).
2. This also shrinks the save itself (fewer thousands of Display entities serialized into
   17 dimensions on every quit).

**Fix (diagnostic, MUST land first):** reproduce per §4.1 and capture
`jcmd <pid> Thread.print` at the hang. The Server-thread frame pins the exact member
(`PersistentEntitySectionManager.close`, `ChunkMap.flushWorker().join`,
`PoiManager` write, a Sable mixin frame, or an SVC lock). Do not skip this — RC-1's code
fix is high-value regardless, but the dump decides whether RC-5 escalation is needed.

### RC-2 — shutdown drain in `RingGrowthService` sync-generates chunks (dedicated + SP, mid-sweep stops)

**Fix (code):** in `Job.drainFinishQueue(int)` (`RingGrowthService.java:1339`):
- never sync-load at stop: only finish chunks whose `LevelChunk` is already resident
  (`level.getChunkSource().getChunkNow(...) != null`); skip `ensureNeighborsLoaded` for the
  rest and let the **existing cursor-rollback** (lines 1348–1358) re-finish them on resume —
  the mechanism is already implemented and documented for exactly this case;
- add a wall-clock budget (e.g. 2000 ms) to the drain loop as a second bound;
- keep `MAX_SHUTDOWN_FINISHES` as the count bound.

### RC-3 — watchdog disabled hides mid-tick wedges (`/stop` then "never finishes")

**Fix (config + follow-up):**
- set `max-tick-time=60000` in `run/server.properties` (dev) and document in README that
  production must not ship `-1`;
- separate ticket: investigate the 1c wedge (`ServerEntity.sendChanges` — audit display
  rider/passenger chains created by `StructureFlightFx` growth riders and
  `DayRiftOrbits`, and re-test without Sable's `entity_rotations_and_riding` mixins).

### RC-4 — RCON client threads pin the dedicated JVM after a clean stop

**Fix (tooling + verification):**
- audit `tools/rcon/rcon.py` to guarantee the socket is closed (context-manager) even on
  exceptions/timeouts;
- verification recipe §4.2 explicitly tests `/stop` issued via RCON (session open at stop)
  vs. stop with no RCON session; if a lingering non-daemon `RCON Client` thread shows up in
  the exit-hang dump, add a `ServerStoppedEvent` handler that closes lingering RCON client
  sockets via the `RconThread` accessor (small, server-dist-only), or accept + document
  "always stop with the wrapper's PID kill" for dev.

### RC-5 — third-party isolation (SVC / Sable)

**Fix (procedure, no code):** on a COPY of the affected save, A/B the SP quit:
(a) full pack (baseline hang), (b) minus `voicechat-neoforge-1.21.1-2.6.16.jar`,
(c) minus `sable-neoforge-1.21.1-2.0.3.jar`, (d) minus both. Whichever removal unhangs the
quit gets version-bumped (SVC has 2.6.x updates) or reported upstream with the §4 thread
dump. Eclipse-side, RC-1's stopping-sweep still lands (defense in depth + smaller saves).

### RC-6 — small hygiene fixes (bundle with RC-1 PR)

- `ArenaFight.onServerStopping` (line 1005): also `forcePitChunks(arena, false)` when the
  arena level is available (S6).
- Guard `StageIO.java:428` / `PristineSnapshots.java:57` behind an `isRunning()` check so
  dev commands cannot block a stopping server (S7).

---

## 4. Verification recipe

> ⚠️ Do NOT run these while the machine is busy (a 4K render was occupying the CPU during
> this investigation). All commands from `ProjectEclipse/`; conventions per `AGENTS.md`
> (kill only by specific PID, never blanket-kill).

### 4.1 Reproduce the singleplayer hang (baseline, pre-fix)

1. `./gradlew runClient` (VM desktop; llvmpipe is slow — allow long waits).
2. Enter the existing dev world (or any world with a few eclipse dimensions visited).
3. Quit to title. **Expected bug:** stuck forever on the saving screen; log tail =
   `All dimensions are saved` + voicechat state spam (compare §1a).
4. `ps -eo pid,args | grep devlaunch.Main` → `jcmd <pid> Thread.print > /tmp/f080_sp.txt`.
   Archive the dump; identify the Server-thread frame. Then `kill <pid>`.

### 4.2 Reproduce the dedicated variant (baseline)

1. Ensure `run/eula.txt` (`eula=true`), `run/mods-client/` jars NOT in `run/mods/`.
2. `./gradlew runServer` (boots in seconds).
3. Mid-sweep case: `python3 tools/rcon/rcon.py "eclipse stage set overworld <n+1> animate"`,
   wait until ring growth logs progress, then `python3 tools/rcon/rcon.py "stop"`.
4. Watch: log must reach `Thread RCON Listener stopped` AND the Gradle task must return /
   the `devlaunch.Main` PID must disappear within ~30 s. If the PID survives:
   `jcmd <pid> Thread.print > /tmp/f080_ded.txt` — check for non-daemon `RCON Client`
   threads (RC-4) or a stuck Server thread (RC-2).
5. Repeat once stopping WITHOUT any RCON session open (stop via a short-lived rcon call is
   fine; the point is no *lingering* connection).

### 4.3 Confirm the fixes

1. Land RC-1 sweep + RC-2 drain bounds + RC-6; rebuild (`./gradlew build`).
2. §4.1 again: the quit must reach the title screen (seconds); log must now show the
   stopping-sweep discard lines, then Create unload + `EclipseClock supplier reset…`.
3. §4.2 again incl. the mid-sweep stop: clean JVM exit; next boot must log the ring-growth
   cursor resume (`WorldStageService.onServerStarted`) and re-finish rolled-back chunks.
4. Active-FX stress: start a storm siege + ferryman fight, `/eclipse start_event` mid-intro,
   then quit/stop — clean exit each time; next boot shows no stray tagged displays (the
   join-time stray guards should stay silent).
5. RC-5 A/B only if §4.1's dump blames a third-party frame.

### Done criteria

- SP quit returns to title in < 10 s on the dev VM, 5/5 attempts.
- Dedicated `runServer` JVM exits < 30 s after `/stop`, with and without prior RCON use,
  including mid-ring-growth stops.
- Thread dumps archived in the PR for the pre-fix baseline and (if any) remaining waits.
