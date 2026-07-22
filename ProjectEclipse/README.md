# Project: Eclipse (Eclipse-Core)

A NeoForge server-event mod for Minecraft.

- **Mod id**: `eclipse` | **Display name**: Eclipse-Core
- **Package root**: `dev.projecteclipse.eclipse`
- **Minecraft**: 1.21.1
- **NeoForge**: 21.1.238
- **Veil**: 4.3.0 (REQUIRED runtime dependency; embedded jar-in-jar, repo `maven.blamejared.com`)
- **ModDevGradle**: 2.0.142 (Gradle wrapper 9.2.1, Java 21, Mojmap + Parchment 2024.11.17)
- **Template**: [NeoForgeMDKs/MDK-1.21.1-ModDevGradle](https://github.com/NeoForgeMDKs/MDK-1.21.1-ModDevGradle)

## Build & run

There is no system Gradle; always use the wrapper from this directory:

```bash
./gradlew build        # compile + jar (output: build/libs/eclipse-<version>.jar)
./gradlew runClient    # launch a dev client
./gradlew runServer    # launch a dev dedicated server (--nogui is preconfigured)
./gradlew runData      # run data generators (output: src/generated/resources)
```

For `runServer`, accept the EULA first: create `run/eula.txt` containing `eula=true`.

v2 REQUIRES A FRESH WORLD: the overworld dimension type was raised to `min_y: -176, height: 512`
for the floating-disc world, which makes v1 saves incompatible. Delete `run/world` before the
first `runServer`/`runClient` after upgrading — this is expected, not a bug.

Note: if you pipe `runServer` output through another process (e.g. `| tee log`), console
input such as `stop` is not forwarded to the server; stop it with Ctrl-C instead.

To test the optional Simple Voice Chat integration, drop
`voicechat-neoforge-1.21.1-2.6.16.jar` into `run/mods/` before starting `./gradlew runServer`.
The Voice Chat API is compile-only; Eclipse still builds and runs when that mod is absent.

## Anonymity — what is blocked and how

Eclipse-Core is **required on every client as well as the server**. The server enforces all
text-input restrictions, while mandatory client-side handlers remove identity-bearing visuals.

| Surface | Enforcement |
|---|---|
| Player chat | `ServerChatEvent` is cancelled before broadcast. |
| Join/leave announcements | A focused `PlayerList#broadcastSystemMessage` mixin drops only `multiplayer.player.joined`, `multiplayer.player.joined.renamed`, and `multiplayer.player.left`. |
| Tab list | The client cancels the `VanillaGuiLayers.TAB_LIST` GUI layer. Player-info packets are deliberately retained so remote players still render. |
| Player name tags | The client forces `RenderNameTagEvent` to `TriState.FALSE` for every player. |
| Player skins | A client mixin makes every `AbstractClientPlayer`, including the local player in third person, use `assets/eclipse/textures/entity/uniform_skin.png` with the wide model and no cape or elytra. |
| Anvil names | Non-empty names that differ from the left input's current name are cancelled; repairs that keep the current name remain available. |
| Signs | Placing any sign and interacting with an existing sign are cancelled on the server. |
| Books | Server use of writable and written books is cancelled. |

## Core APIs

Stable public surface of the persistent data core. Later workers should depend on exactly these signatures.

### Attachments — `dev.projecteclipse.eclipse.registry.EclipseAttachments`

Player data attachments (persisted + `copyOnDeath()` unless noted):

```java
public static final DeferredRegister<AttachmentType<?>> ATTACHMENTS;
public static final Supplier<AttachmentType<Integer>> LIVES;               // permanent hearts; "eclipse:lives", default 5, Codec.INT
public static final Supplier<AttachmentType<Long>>    FIRST_OVERWORLD_JOIN; // "eclipse:first_overworld_join", default 0L (= never), Codec.LONG
public static final Supplier<AttachmentType<Boolean>> BANNED;              // "eclipse:banned", default false, Codec.BOOL
public static final Supplier<AttachmentType<Integer>> SHARDS;              // "eclipse:shards" — personal umbral-shard bank (W13), default 0
public static final Supplier<AttachmentType<Integer>> GOAL_PROGRESS;       // "eclipse:goal_progress" — (day << 8) | goal bitmask (W13);
                                                                           // ONLY progression.GoalTracker writes it (stale days read as 0)
public static final Supplier<AttachmentType<CutsceneLock>> CUTSCENE_LOCK;  // "eclipse:cutscene_lock" — TRANSIENT (not serialized,
                                                                           // no copyOnDeath): restart/relog/death always unfreezes.
                                                                           // Only cutscene.FreezeService touches it.
public static void register(IEventBus modEventBus);
```

### World state — `dev.projecteclipse.eclipse.core.state.EclipseWorldState extends SavedData`

Global event state, stored in the overworld's data storage as `data/eclipse_world_state.dat`.
Every mutator calls `setDirty()`; collection getters return unmodifiable views.

```java
public static final String DATA_NAME = "eclipse_world_state";
public static EclipseWorldState get(MinecraftServer server);
public static EclipseWorldState load(CompoundTag tag, HolderLookup.Provider registries);
public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries); // @Override

public int getDay();                          public void setDay(int day);                    // default 1
public int getAltarLevel();                   public void setAltarLevel(int altarLevel);      // default 0
public double getBorderSize();                public void setBorderSize(double borderSize);   // since W7: the vanilla FAILSAFE diameter (ring+48, doubled)
public double getBorderCenterX();             public double getBorderCenterZ();               // soft ring center (world spawn; re-pinned each start)
public void setBorderCenter(double x, double z);
public double getSoftBorderRadius(DiscProfile profile);        // -1 = derive from stage at startup; 0 = ring inactive
public void setSoftBorderRadius(DiscProfile profile, double radius);
public double getBorderFxRange();             public void setBorderFxRange(double blocks);    // <= 0 = use general.json borderFxRange
public boolean isStartEventDone();            public void setStartEventDone(boolean done);    // default false
public boolean isGhostShipBuilt();            public void setGhostShipBuilt(boolean built);   // default false
public List<UUID> getOarEntities();           public void setOarEntities(List<UUID> ids);     // ghost ship oar displays
public List<UUID> getDeckhandEntities();      public void setDeckhandEntities(List<UUID> ids);// ghost ship rowing crew (W10)

public static final String NIGHT_EVENT_NONE = "none";   // night events (W10) — see entity.EclipseSpawner
public static final String NIGHT_EVENT_PALE = "pale";
public static final String NIGHT_EVENT_UMBRAL = "umbral";
public String getActiveNightEvent();          // "none"|"pale"|"umbral" (anything else loads as none)
public int getNightEventDay();                // eclipse-day stamp of the current event, 0 = never
public void setActiveNightEvent(String event, int dayStamp);
public boolean isFirstPaleNightDone();        public void setFirstPaleNightDone(boolean done); // day-4 guarantee latch

public boolean isHeraldDefeated();            public void setHeraldDefeated(boolean defeated); // W11 day-7 boss kill flag; UnlockState unions key "herald_slain" while set
public boolean isFerrymanDefeated();          public void setFerrymanDefeated(boolean defeated); // W12 day-14 finale kill flag (set before the mass-revive finale runs)

public int getWorldStage(DiscProfile profile);                 // committed world stage, default 0
public void setWorldStage(DiscProfile profile, int stage);     // ONLY WorldStageService.setStage may call this
public boolean hasGrowthCursor();                              // a ring sweep was mid-flight at last save
public String getGrowthDimension();                            // "overworld"/"nether", "" = none
public int getGrowthFromStage();                               // stage the interrupted sweep started from
public long getGrowthCursor();                                 // next column index of the sweep ordering
public void setGrowthCursor(String dim, int fromStage, long columnIndex);
public void clearGrowthCursor();

public Set<UUID> getBanned();                 public boolean isBanned(UUID playerId);
public void addBanned(UUID playerId);         public void removeBanned(UUID playerId);

public Map<String, Long> getMilestoneProgress();
public long getMilestoneProgress(String key);                 // 0 if absent
public void setMilestoneProgress(String key, long value);
public long addMilestoneProgress(String key, long delta);     // returns new value

public int getShardPool();                    // W13 team umbral-shard pool (pooled shop purchases)
public int addShardPool(int delta);           // clamped at >= 0; returns the new value
public void setShardPool(int value);
public List<GlobalPos> getGravePositions(UUID owner);         // W13: the owner's live graves (unmodifiable)
public void addGravePosition(UUID owner, GlobalPos pos);      // called where LifecycleEvents places a grave
public void removeGravePosition(UUID owner, GlobalPos pos);   // called from GraveBlock.onRemove (loot/scatter/break)

public Set<UUID> getForceVoiceMuted();        public boolean isForceVoiceMuted(UUID playerId); // for the voice worker
public void addForceVoiceMuted(UUID playerId); public void removeForceVoiceMuted(UUID playerId);

public Set<String> getDisabledCutscenes();    public boolean isCutsceneDisabled(String pathId); // runtime cutscene toggle
public boolean setCutsceneDisabled(String pathId, boolean disabled);   // behind /eclipse cutscene enable|disable
```

### Voice mute — `dev.projecteclipse.eclipse.voice.VoiceMuteApi`

Server-side entry points for the ten-minute first-Overworld-entry mute and the persistent
administrative force-mute:

```java
public static boolean isEntryMuted(ServerPlayer player);
public static void setForceMuted(MinecraftServer server, UUID playerId, boolean muted);
public static boolean isMuted(MinecraftServer server, ServerPlayer player);
```

### Lives — `dev.projecteclipse.eclipse.core.state.LivesApi`

Server-side only. The legacy `eclipse:lives` name/signatures are stable, but the value now means
the player's permanent **heart count**. Values are clamped to `>= 0`; `set`/`add` immediately call
`HeartsService.apply`, then sync the new value to the owning client via `S2CLivesPayload`.

```java
public static int get(ServerPlayer player);
public static int set(ServerPlayer player, int lives);   // returns the applied (clamped) value
public static int add(ServerPlayer player, int delta);   // delta may be negative; returns the new value
```

### Hearts — `dev.projecteclipse.eclipse.hearts.HeartsService`

`apply(ServerPlayer)` is the single projection from `LivesApi` to real max health. It installs an
`eclipse:hearts` **transient** `Attributes.MAX_HEALTH` `ADD_VALUE` modifier worth
`hearts * 2 - 20`, clamps current health to the new maximum (minimum 1 HP while alive), and is
reapplied on login, clone and respawn. Five starting hearts therefore mean 10 HP. The modifier is
never serialized, so relogs and respawns cannot double-apply it.

```java
public static final int MIN_HEARTS = 0;
public static final int MAX_HEARTS = 7; // permanent-upgrade cap; W13 Vitae Shard consumes this
public static void apply(ServerPlayer player);
```

### Snapshots — `dev.projecteclipse.eclipse.core.snapshot.SnapshotService`

Pretty-printed JSON snapshots at `<worldFolder>/eclipse/snapshots/<playerUuid>/<epochMillis>.json`
(items encoded with `ItemStack.OPTIONAL_CODEC` + `RegistryOps.create(JsonOps.INSTANCE, ...)`).
JSON keys: `player`, `player_name`, `reason`, `timestamp`, `dimension`, `position{x,y,z}`, `lives`, `day`,
`main[36]`, `armor[4]`, `offhand[1]`, `ender_chest[27]`. All IO errors are logged, never thrown.

```java
public static void snapshot(ServerPlayer player, String reason);
public static List<Path> list(UUID playerId);                        // uses ServerLifecycleHooks.getCurrentServer(); sorted oldest-first
public static List<Path> list(MinecraftServer server, UUID playerId); // explicit-server overload, sorted oldest-first
public static boolean restore(ServerPlayer player, Path snapshotFile); // clears + re-applies inventory & ender chest only
```

### Client config — `dev.projecteclipse.eclipse.core.config.EclipseClientConfig`

Cosmetic client toggles in `eclipse-client.toml` (NeoForge `ModConfigSpec`, type CLIENT, registered
in the `EclipseMod` constructor). All getters are static, safe on both dists and before config
load (they fall back to the defaults):

```java
public static boolean customMenu();      // default true — custom Eclipse title screen
public static boolean showBossbarSkin(); // default true — themed boss bar frames
public static boolean showSidebar();     // default true — Eclipse sidebar panel
public static boolean uiSounds();        // default true — UI hover/page sounds
public static boolean customCursor();    // default true — themed GLFW cursors
public static boolean veilPostFx();      // default true — Veil post pipelines (auto-off under a shaderpack)
public static boolean reducedFx();       // default false — reduce shake/particles/pulses
```

### Config — `dev.projecteclipse.eclipse.core.config.EclipseConfig`

Loads `config/eclipse/{general,days,milestones,modgate,anticheat,stages}.json`; missing files are created with defaults on first run
(triggered from `FMLCommonSetupEvent`). Getters lazy-load if needed. Parse/IO failures fall back to built-in defaults in memory.

```java
public record General(int graveGraceMinutes, boolean dayAutoAdvance, String dayAutoAdvanceTime,
        int ringBlocksBudgetMs, boolean cutscenesFreezeDuringUnlocks, int borderOffset, int borderFxRange) {}
// general.json; defaults: 30, false, "08:00", 2, true, 12, 8 (JSON: "cutscenes":{"freezeDuringUnlocks"})
public record DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize) {}
// DayPlan.borderSize is DEPRECATED since W7 (still parsed; ignored with a one-time warning —
// the soft border follows the world stage instead).
public record ItemCost(String item, int count) {}
public record Milestone(int level, List<ItemCost> cost, List<String> rewards) {}
public record ModGate(List<String> gatedNamespaces, Map<String, String> unlockKeys) {}
public record AntiCheat(List<String> blockedModIdSubstrings) {}
public record StageEntry(int stage, int radius, String trigger, List<String> structures,
        Map<String, Integer> oreBudget) {}
// stages.json; per-dimension world stage timeline, see "World stages"

public static General general();
public static int graveGraceMinutes();       // non-owners may loot a grave after 1x; it scatters after 3x
public static boolean dayAutoAdvance();      // default false: days advance only via DayScheduler.setDay
public static LocalTime dayAutoAdvanceTime(); // parsed "HH:mm" (server-local); falls back to 08:00
public static int ringBlocksBudgetMs();      // per-tick nanoTime budget of the ring-growth sweep (default 2, min 1)
public static boolean freezeDuringUnlocks(); // animated ring growth freezes players + plays unlock_ring (default true)
public static int borderOffset();            // soft ring sits this far outside the stage radius (default 12)
public static int borderFxRange();           // default border FX visibility band in blocks (default 8, min 1)
public static List<DayPlan> days();          // 14 entries by default, ordered by day
public static DayPlan day(int day);          // out-of-range days clamp to first/last plan
public static List<Milestone> milestones();  // ordered by level
public static Milestone milestone(int level); // null if not configured
public static ModGate modGate();
public static AntiCheat antiCheat();         // anticheat.json blocklist, see "Anti-cheat"
public static List<StageEntry> stages(String dim); // "overworld"/"nether", ordered by stage (stage 0 implicit)
public static StageEntry stage(String dim, int stage); // null if not configured
public static synchronized boolean setNamespaceGated(String namespace, boolean gated); // mutates + persists modgate.json
public static synchronized void reload();    // also re-publishes stages.json radii into StageRadii
```

Default unlock keys per day (v2 arc since W13): 1 `[]`, 2 `[nether, main_inventory]`,
3 `[workbenches, create]`, 4 `[armor, farmersdelight, simulated]`, 5 `[aeronautics, supplementaries]`,
6 `[]`, 7 `[enchanting]` (boss-locked — see below), 8 `[ender_chests, sophisticatedbackpacks, sable]`,
9 `[brewing, createaddition]`, 10 `[smithing]`, 11 `[]`, 12 `[end]`, 13 `[]`, 14 `[]`.
Default milestone costs: L1 16 iron, L2 16 gold, L3 8 diamonds, **L4 1 `eclipse:herald_core` +
16 ender pearls**, L5 2 netherite ingots. NOTE: defaults only apply to configs written fresh —
a pre-W13 `config/eclipse/{days,milestones,modgate}.json` keeps the v1 arc until deleted.

### Networking — `dev.projecteclipse.eclipse.network`

Registrar version `"2"` (v2 payload family), registered via `RegisterPayloadHandlersEvent`
(mod bus). Lives/day-state payloads are sent automatically on `PlayerLoggedInEvent`. Client handlers
write to `dev.projecteclipse.eclipse.client.ClientStateCache` (`public static volatile int lives / day / altarLevel`).

```java
public record S2CLivesPayload(int lives) implements CustomPacketPayload;        // id "eclipse:lives"
public record S2CDayStatePayload(int day, int altarLevel) implements CustomPacketPayload; // id "eclipse:day_state"
public record S2CCutscenePayload(Phase phase) implements CustomPacketPayload;   // id "eclipse:cutscene"
// S2CCutscenePayload.Phase: enum { TILT, SUBMERGE, WAVES, EMERGE, SHAKE }; client handler writes
// ClientStateCache.cutscenePhase (volatile, null until the start event runs). SHAKE is pulsed
// repeatedly by FusionSequence during the intro fusion — treat each receipt as one ~2 s
// camera-shake impulse, not a latched phase.
public record S2CHeartBurstPayload(int heartIndex) implements CustomPacketPayload; // id "eclipse:heart_burst"
// Sent after a death-loss respawn; heartIndex is the first now-missing zero-based heart.
public record S2CQuasarPayload(ResourceLocation emitterId, Vec3 pos) implements CustomPacketPayload; // id "eclipse:quasar"
// S2CQuasarPayload: spawns a one-shot Quasar particle emitter client-side via
// veilfx.QuasarSpawner.spawnOrFallback (vanilla END_ROD/PORTAL burst if Quasar fails).
// Well-known emitter id constants live on the payload class: ALTAR_BEAM, ARM_WISPS,
// MAP_EXPAND_MATERIALIZE, BORDER_GLITCH, BOSS_SLAM, HEART_BURST, LIMBO_MOTES, CUTSCENE_VEIL.
public record S2CStagePayload(String dim, int stage, int radius, boolean animating) implements CustomPacketPayload; // id "eclipse:stage"
// Committed world stage of one disc dimension ("overworld"/"nether"); sent per-dimension on
// login and broadcast on every stage commit / sweep completion. Client handler writes
// ClientStateCache.stage*/stageRadius*/stageAnimating* (volatile).
public record S2CBorderPayload(String dim, double centerX, double centerZ, float fromRadius,
        float toRadius, int lerpTicks, float fxRange) implements CustomPacketPayload; // id "eclipse:border"
// Soft-border ring of one disc dimension; sent per-dimension on login and broadcast on every
// ring/FX-range change. The client animates fromRadius -> toRadius over lerpTicks locally
// (one packet per change); toRadius <= 0 = ring inactive. Client handler writes
// ClientStateCache.border* (volatile); ClientStateCache.currentBorderRadius derives the
// animated radius.
public record S2CCutsceneLibraryPayload(Map<String, String> pathsJson) implements CustomPacketPayload; // id "eclipse:cutscene_library"
// Full camera-path library as raw JSON keyed by path id; sent at login and after
// reloadpaths/editor writes. Client re-parses via cutscene.CutscenePath.parse.
public record S2CCutscenePlayPayload(String id, boolean allowSkip, Optional<Vec3> anchor) implements CustomPacketPayload; // id "eclipse:cutscene_play"
// Start playing a synced path; empty id = STOP sentinel (abort / granted skip). anchor
// overrides the world-anchor origin (e.g. unlock_ring's ring edge).
public record S2CBossbarStylePayload(UUID id, String theme) implements CustomPacketPayload;    // id "eclipse:bossbar_style"
// Tags one server bossbar (its BossEvent UUID) with an Eclipse skin theme — THEME_DAY /
// THEME_GOAL / THEME_BOSS constants on the payload class. client.hud.BossbarSkin cancels +
// redraws exactly the tagged bars; every untagged bar renders vanilla. Send it when creating
// a themed ServerBossEvent AND to late joiners that get addPlayer'd onto a running bar (see
// ritual.ReviveRitual for the pattern). W11/W12 boss bars + W14's schedule countdown reuse this.
public record S2CGoalProgressPayload(List<String> goalLines, List<Boolean> done) implements CustomPacketPayload; // id "eclipse:goal_progress"
// The receiving player's personal goal tick list (sidebar rows). Since W13 the flags are
// REAL: currentFor(ServerPlayer) reads the player's eclipse:goal_progress bitmask via
// progression.GoalTracker.mask. Sent at login, re-sent to the player on every tick
// (GoalTracker.complete) and rebroadcast to everyone when the event day changes.
public record S2CAnnouncePayload(String titleKey, String subtitleKey, String style) implements CustomPacketPayload; // id "eclipse:announce"
// One announcement (STYLE_DAY/STYLE_UNLOCK/STYLE_GOAL/STYLE_BOSS constants): the client
// plays a typewriter line above the hotbar (then posts it to chat once) + a client-local
// themed bossbar sweep showing the title. Both keys are lang keys (client-side i18n);
// empty subtitleKey = type the title. Fired by timeline.AnnouncementService.
public record S2CTimelinePayload(List<TimelineEntry> entries) implements CustomPacketPayload; // id "eclipse:timeline"
// Full ANONYMIZED event timeline (timeline.TimelineEntry: id, unlockDay, titleKey, icon,
// hidden, reached) — hidden/future entries carry empty titleKey + TimelineEntry.NO_ICON, so
// upcoming content cannot be datamined. Sent at login + day/altar changes by
// timeline.TimelineService; cached in ClientStateCache.timeline (W9 handbook reads it).
public record S2CMilestonesPayload(List<Entry> entries) implements CustomPacketPayload; // id "eclipse:milestones"
// S2CMilestonesPayload.Entry(int level, List<Cost> costs, List<String> rewards),
// Cost(String item, int count): the altar milestone ladder from milestones.json. Sent at
// login and re-broadcast by /eclipse reload; cached in ClientStateCache.milestones. The
// handbook Rewards tab renders costs as item icons; Status derives the ring max level.
// NOT anonymized (milestone announcements already name them). Factory: current().
public record C2SCutsceneStatePayload(String id, State state) implements CustomPacketPayload; // id "eclipse:cutscene_state"
// C2SCutsceneStatePayload.State: enum { STARTED, FINISHED, SKIP_REQUEST, SKIPPED } — playback
// ACKs + skip requests, validated/handled by cutscene.CutsceneService.handleClientState.
public record S2COpenGoalEditorPayload(String daysJson) implements CustomPacketPayload; // id "eclipse:open_goal_editor"
// Opens the W14 goal editor GUI (devtools.client.GoalEditorScreen) with the server's CURRENT
// days.json as raw JSON. Sent by /eclipse goals edit via devtools.ConfigEditor.openFor.
public record C2SConfigEditPayload(String fileName, String json) implements CustomPacketPayload; // id "eclipse:config_edit"
// UNTRUSTED goal-editor write-back. devtools.ConfigEditor.handleEdit requires
// hasPermissions(3), allowlists days.json|milestones.json, rejects > MAX_JSON_BYTES (64 KB)
// and re-validates + normalizes against the EclipseConfig schema before writing + reload.
// all expose: public static final CustomPacketPayload.Type<...> TYPE;
//             public static final StreamCodec<ByteBuf, ...> STREAM_CODEC;

public final class EclipsePayloads {
    public static void register(IEventBus modEventBus); // wires mod-bus payload registration + game-bus login sync
}
```

### Cutscene engine — `dev.projecteclipse.eclipse.cutscene`

Server-authoritative camera cutscenes (`docs/ideas/05_systems.md` §1): the server owns who is
watching what plus the freeze; the client owns the camera flight and ACKs
`STARTED/FINISHED/SKIPPED` back. Camera paths live in `config/eclipse/cutscenes/<id>.json`
(schema: `id, enabled, allowSkip, interpolation catmullrom|bezier, anchor world|player,
dimension, letterbox, hideHud, durationTicks, keyframes[t,pos,yaw,pitch,roll,fov,easing],
events[t,type,id], params`). Four bundled defaults are copied out of the jar on first run:
`intro_submerge` (limbo flyaround), `intro_rise` (overworld, anchor `player`), `unlock_ring`
(orbital template, anchor `world`, per-play anchor = ring edge), `finale_return` (reverse
intro, W12).

```java
public final class CutscenePaths {                       // path library (server)
    public static void reload();                         // re-scan config dir, copy bundled defaults first
    @Nullable public static CutscenePath get(String id);
    public static Collection<CutscenePath> all();        // file order
    public static Map<String, String> rawJsonById();     // library-sync payload body
    public static boolean save(CutscenePath path);       // editor writes; caller re-syncs clients
}

public final class CutsceneService {                     // orchestration (server, game bus)
    public static final int WATCHDOG_MARGIN_TICKS = 100; // freeze TTL & session deadline = durationTicks + 100
    public static int play(String id, Collection<ServerPlayer> players);
    public static int play(String id, Collection<ServerPlayer> players, @Nullable Vec3 anchor,
            @Nullable Runnable onAllFinished);           // callback runs once all watchers ACK/watchdog/logout;
                                                         // missing/disabled path or zero players -> runs instantly
    public static boolean preview(String id, ServerPlayer player); // play payload only, NO freeze
    public static int abort(Collection<ServerPlayer> players);     // unfreeze + client STOP sentinel
    @Nullable public static String activePathId(ServerPlayer player);
    public static boolean isEnabled(MinecraftServer server, CutscenePath path); // JSON flag && !world disabled set
    public static void syncLibraryTo(ServerPlayer player);         // sent automatically at login
    public static void syncLibraryToAll(MinecraftServer server);
    public static void handleClientState(C2SCutsceneStatePayload payload, ServerPlayer player);
}

public final class FreezeService {                       // server-authoritative freeze + invuln (game bus)
    public static void freeze(ServerPlayer player, int ttlTicks);  // W7 border physics + W14 commands call these
    public static void freeze(ServerPlayer player, int ttlTicks, boolean survivesDimensionChange, int graceTicks);
    public static void unfreeze(ServerPlayer player);
    public static boolean isFrozen(ServerPlayer player);
    public static void reanchorWithGrace(ServerPlayer player, int graceTicks); // after scripted teleports/launches
    public static List<String> recentWatchdogEvents();   // ring buffer of forced releases (W14 inspector)
}
```

Freeze mechanics: transient `CUTSCENE_LOCK` attachment; `PlayerTickEvent.Pre` rubber-bands to
the anchor (`connection.teleport` beyond 0.1 blocks) and zeroes `setDeltaMovement`; all
cancellable `PlayerInteractEvent`s are cancelled; invulnerability = cancelling
`LivingIncomingDamageEvent` + `LivingKnockBackEvent` (never `abilities.invulnerable`).
Watchdog: mandatory TTL per lock; released at TTL, death, dimension change (kept for
`intro_*` paths — the anchor then re-follows the player for a grace window), logout; stale
locks cleared at login. `SKIP_REQUEST` is granted only if the path's `allowSkip` is true and
the path is not disabled; disabled paths (JSON `enabled:false` or the persisted
`disabledCutscenes` world-state set) complete instantly server-side so timelines never
softlock.

Client side (`cutscene.client`, all `Dist.CLIENT`): `ClientCutsceneLibrary` caches the synced
path JSON; `CameraDirector` evaluates the active path per render frame — position via
Catmull-Rom (default) or damped-tangent cubic Hermite (`"bezier"`), orientation via
quaternion slerp of yaw/pitch/roll, per-keyframe Veil `Easing`, FOV via
`ViewportEvent.ComputeFov` — and overrides the camera through `client.mixin.CameraMixin`
(`@Inject` at `Camera#setup` TAIL calling the AT-widened `setPosition(Vec3)` /
`setRotation(yaw, pitch, roll)`; `ViewportEvent.ComputeCameraAngles` re-applies
yaw/pitch/roll as fallback). During a flight the camera type switches to
`THIRD_PERSON_BACK` (own body in frame) and is restored after. `LetterboxLayer` (GUI layer
above all) eases cinematic bars in/out, shows the SPACE skip hint when allowed, and cancels
all non-whitelisted HUD layers via `RenderGuiLayerEvent.Pre` while `hideHud` is active
(whitelist: letterbox, heart burst, wave overlay — wired in `EclipseGuiLayers`).
`CutsceneInput` zeroes movement (`MovementInputUpdateEvent`), cancels clicks/interactions,
and turns ESC (pause-screen suppression) / Space into `SKIP_REQUEST`s. Paths targeting a
different dimension than the client's ACK `FINISHED` instantly. `CameraDirector.addShakeImpulse()`
is the W4 `SHAKE` contract: one ~2 s decaying position+roll noise impulse per receipt,
applied during flights and over the normal gameplay camera alike.

`UnlockCinematics` wires the engine into ring growth: on every ANIMATED stage raise
(`WorldStageService.addGrowthStartListener`) each player in the growing dimension is frozen
and shown `unlock_ring`, per-player anchored at the old ring-edge point nearest to them; the
`StageListener` completion callback aborts flights that outlive the sweep. Skipped for
instant stamps, erases, the `intro_fusion` stage (the start event owns that shot), and when
`cutscenes.freezeDuringUnlocks` in `general.json` is `false`.

### HUD suite — `dev.projecteclipse.eclipse.client.hud`

Worker 8's client HUD layer (all classes `Dist.CLIENT`, driven by payloads + `ClientStateCache`):

- **`BossbarSkin`** — surgical skinning of OUR bossbars via the cancellable per-bar
  `CustomizeGuiOverlayEvent.BossEventProgress`. A bar is "ours" when its UUID was tagged by
  `S2CBossbarStylePayload` (themes `day`/`goal`/`boss`), with a translation-key safety net for
  `ritual.eclipse.*` names (revive countdown). Tagged bars get a themed 512x64 frame
  (192x15 logical over a 182x7 fill window), a lerped fill (0.05/frame), a scrolling energy
  overlay and a leading-edge glow that flashes on progress change; `setIncrement(+10)`
  reserves the taller frame. `showBossbarSkin=false` degrades to a minimal 4px strip — a
  revive countdown is never fully hidden. Untagged (foreign) bars render 100% vanilla.
  `BossbarSkin.drawThemedBar(...)` is the shared renderer; `nextFreeBarY()` reports the next
  free bar slot so client-local temp bars can stack below real ones.
- **`SidebarPanel`** — right-anchored 110px status panel (hearts, day, altar level, online
  count, personal goal ticks from `S2CGoalProgressPayload`) rendered purely from
  `ClientStateCache` — vanilla scoreboard DATA is untouched and stays free for ops; only the
  `SCOREBOARD_SIDEBAR` layer render is cancelled while the panel is on. 60% black nine-slice
  backdrop (`textures/gui/sidebar/panel.png` + five 24x24 icons), re-slides in from the right
  on any content change (skipped under `reducedFx`), honors `showSidebar` live (off = vanilla
  sidebar returns). Hidden during cutscene HUD suppression by design (not whitelisted).
- **`AnnouncementOverlay` + `TypewriterLine`** — client half of `S2CAnnouncePayload`: a
  typewriter line above the hotbar (1 char/tick, `eclipse:ui.typewriter` tick every 2 chars,
  finished line posted to chat once) plus a simultaneous client-local bossbar sweep reusing
  `BossbarSkin.drawThemedBar` (fill 0→1 over 30t with a bright leading edge, holds 60t
  showing the title, fades 20t; stacks below real bars via `nextFreeBarY()`). Styles map
  `day`→day, `boss`→boss, `goal`/`unlock`→goal skins. Announcements queue (cap 8) so unlock
  bursts play sequentially. No `BossEvent` is created — the sweep is pure overlay.

### Handbook 2.0 — `dev.projecteclipse.eclipse.client.handbook`

"The Ledger of the Drowned" (`docs/ideas/03_ui_ux.md` §B) replaced the v1 176x166 artifact
popup. Both v1 open paths are preserved and now open the handbook: the `key.eclipse.menu`
keybind (J, `ArtifactKeyHandler`) and the artifact right-click / `S2COpenArtifactPayload`
(`ArtifactScreenOpener`). `client.ArtifactScreen` remains as a deprecated thin alias
(`extends HandbookScreen`); the v1 `client.RulesScreen` was DELETED — its content (the
`gui.eclipse.artifact.rules.line1..10` lang keys, kept verbatim) became the Rules tab.

- **`HandbookScreen`** — percentage-derived layout (book spread 90%w x 85%h over a
  full-bleed vignette, no fixed-size box): parchment tab tongues on the far-left spine
  (active tongue slides out 6px + glows), left page = ledger/tab title + divider + hero
  art, right page = the active tab, bottom = page dots + key hint. Keys: 1–6 jump to a
  tab, arrows/PgUp/PgDn turn pages, J or ESC closes. Renders live from `ClientStateCache`.
  Opening plays a book-unfold (scaleY 0.9→1 + fade, 8t ease-out cubic); tab switches play
  a 6t page-turn (old page shears + x-compresses into the spine hinge, new page unfolds
  back out, `ui.page_turn` sound); the backdrop parchment texture parallax-drifts 8px
  opposite the mouse and the hero art 4px (scissored). All skipped by `reducedFx`.
- **Tabs** (`handbook.tabs`, one class each, base `HandbookTab`): **Status** (big day
  counter, heart row, altar progress ring — 256x256 `icons/altar_ring.png` + code-drawn
  arc, pulses on level-up —, goal list with animated tick draw-in, online count from the
  client tab-list info), **Timeline** (horizontal drag spine of
  `ClientStateCache.timeline`; inertial scroll, current node pulses, hidden entries =
  locked node + `GlitchText` "???"), **Rules** (scrollable parchment), **Rewards**
  (milestone ladder from `ClientStateCache.milestones`, costs via
  `guiGraphics.renderItem`), **Bestiary** (six creature cards, client-side data table —
  see below), **Map** (concentric ring diagram from `worldgen.StageRadii` +
  `DiscGeometry`, current stage highlighted, animated soft-border circle, stage-gated
  landmark markers).
- **Bestiary data contract (W10–W12)**: `BestiaryTab.CREATURES` hardcodes id + intro day
  (deckhand 1, gazer 3, the_other 4, umbral_stalker 5, herald 7, ferryman 14; lang keys
  `bestiary.eclipse.<id>.name/.lore`). Cards unlock client-side once
  `ClientStateCache.day >= introDay`; locked cards render a code-drawn silhouette +
  glitch text and never leak the intro day. Keep intro days in sync with spawn rules.
- **`GlitchText`** — redacted text helper: chars re-rolled every 3 ticks (150 ms wall-clock
  buckets, per-slot salt); static `?`s under `reducedFx`.
- **`EclipseWidget`** — shared base widget: hover edge-detect (one `UiSounds.hover()`
  blip on the false→true flip, never per-frame) + 2px purple glow border fading in over
  ~4t + a `CursorManager.requestPointer()` per hovered frame; W15's menu/settings widgets
  should extend it.
- **`UiSounds`** — `SimpleSoundInstance.forUI` helpers over the four W9 sound events
  (`ui.hover`, `ui.page_turn`, `ui.tab`, `ui.unlock_sting` in `EclipseSounds` +
  `sounds.json`; only the latter two have subtitles to avoid caption spam), all gated by
  the `uiSounds` client config. The unlock sting fires from the Status tab on an altar
  level-up while the book is open.
- **`CursorManager`** — GLFW cursor lifecycle (risk R12): themed 32x32 PNGs
  (`textures/gui/cursor/{arrow,hand,grab}.png`, hotspots (0,0)/(8,0)/(16,16)) via
  `glfwCreateCursor`, guarded `glfwCreateStandardCursor` fallback (0 → system cursor
  stays). Widgets/tabs `requestPointer()`/`requestGrab()` during render; the screen calls
  `endFrame()` once per frame (strongest request wins, swap only on change) and MUST call
  `reset()` from `removed()`. Pointers are cached and destroyed + lazily recreated on
  resource reload (F3+T); everything no-ops off the render thread and behind the
  `customCursor` client config. W15 screens follow the same request/endFrame/reset
  pattern.

### Timeline + announcements (server) — `dev.projecteclipse.eclipse.timeline`

- **`TimelineService`** — builds the anonymized `TimelineEntry` list from `days.json` (one
  node per day) + `milestones.json` (one node per altar milestone, ids 1001+, `unlockDay=0`):
  reached entries carry a title lang key (`announce.eclipse.day.N.title` /
  `announce.eclipse.milestone.N`) + icon; FUTURE entries are sent `hidden` with empty
  titleKey + `TimelineEntry.NO_ICON` (server-side anonymization — no datamining). Synced via
  `S2CTimelinePayload` at login (`EclipsePayloads`) and on day/altar changes; each send is
  logged ("Timeline payload sent...").
- **`AnnouncementService`** — fires `S2CAnnouncePayload` on: day advance
  (`DayScheduler.setDay` calls `onDayChanged`, augmenting the bell), NEW unlock keys (the
  `UnlockState.unlockedKeys` set is snapshotted + diffed after day/altar changes; per-key
  lang line `announce.eclipse.unlock.key.<key>`), altar milestone level-ups (polled every
  20t — catches both `AltarBlockEntity` and `/eclipse altar set`), and finished stage-GROW
  sweeps (`WorldStageService` listener). Every send is logged ("Announce payload sent...").
  Goal completion is NOT wired (v1 tracks no goals): W13 calls `announceGoalCompleted`.

### Custom mobs & spawner — `dev.projecteclipse.eclipse.entity` (W10)

Five custom mobs with hand-coded cube models (`client/entity/*Model`, layer definitions
registered by `client/entity/EclipseEntityRenderers`), procedural animations and
programmer-art skins (regenerate: `java scripts/placeholder_gen/EntitySkinPlaceholder.java`;
UV layouts documented per mob in `docs/uv/<mob>.md`). Registered in
`entity.EclipseEntities` (`DeferredRegister<EntityType<?>>` + attributes).

| Mob (`eclipse:` id) | Category | Behavior | Spawning | Drops |
|---|---|---|---|---|
| `the_other` | MONSTER | Doppelganger in the uniform skin (vanilla humanoid geometry). MimicWalk: paths to the nearest player, stops at 5 blocks and stares; attacks only at ≤3 blocks or on retaliation (180° head snap in 2t on aggro). Dawn: soul-escape + wisp burst, gone. | Pale Nights only, 2–3 per event, ≥24 blocks from every player, surface | 1–2 umbral shards |
| `gazer` | CREATURE | Never moves or attacks. Vanishes when stared at dead-center for 40t (wisp puff + private cave-mood sting); teleports every 200–400t into the nearest player's peripheral FOV. Unkillable — damage = vanish. 12-block whisper loop. | Overworld nights day 3+, 1 per ~4 players; 1 guaranteed near the altar during sacrifices (`GazerEntity.watchSacrifice`, hooked from `AltarBlockEntity`) | — |
| `umbral_stalker` | MONSTER | Wolf-like pack hunter: leap + melee(1.3, persistent), retaliation alerts the pack, hunts players on sight. Flees at dawn and dissolves after ~5 s. | Packs of 3–4 at night day 5+ (cap 4; **8 on Umbral Nights**), 24–56 blocks out | 0–2 umbral shards, 20% heart fragment |
| `deckhand` | CREATURE | Mute rowing crew of the Limbo ghost ship; look-at goal only, invulnerable, unpushable, discards outside Limbo. Rowing anim synced to the 30t oar cadence. | 8 seated once at the oar benches by `GhostShipBuilder` → `DeckhandEntity.ensureCrew` (UUIDs persist in `EclipseWorldState.getDeckhandEntities()`) | — |
| `sunmote` | CREATURE | Fullbright 2-cube wisp orbiting the sanctum altar (radius `6+altarLevel`, position-driven in `tick()`); chimes every ~200t. | Daylight upkeep by the spawner: one per altar level; killed motes respawn next dawn | 1 glowstone dust |

**`entity.EclipseSpawner`** (game bus, `ServerTickEvent.Post`, one pass per 100t): applies
the table above — overworld, surface, loaded chunks, per-pass caps (never spawn-loops).
It also schedules the **night events**: on nightfall of day 4+ it rolls a **Pale Night**
(25%; the first is guaranteed, as is day 12), and days 6/10 are fixed **Umbral Nights**;
events persist in `EclipseWorldState.getActiveNightEvent()`, are announced via the W8
typewriter/sweep (style `unlock`, lang keys `announce.eclipse.night.<event>.*`) and clear
at dawn. Override live with `/eclipse event set <pale|umbral|none>`.

Sanctum note: `worldgen.structure.SanctumProtection` suppresses non-`eclipse`-namespace
hostile spawns near the altar — all of these mobs are exempt by namespace.

### Herald boss — `dev.projecteclipse.eclipse.entity.boss` (W11)

The day-7 boss (`eclipse:herald`, spec `docs/ideas/04_content.md` §2.1): a 26-cube floating
godhead (`client/entity/HeraldModel`, 128×128 skin, UV in `docs/uv/herald.md`; emissive
inner eye + telegraph-glowing corona shards via the Gazer skipDraw pattern in
`HeraldRenderer`). Never spawns naturally.

- **Summon**: craft a **Herald's Lure** (`eclipse:heralds_lure`, 4 umbral shards around
  1 heart fragment, `data/eclipse/recipe/heralds_lure.json`) and **sneak-use it on the
  altar after dusk** (`ritual/HeraldsLureItem`; non-sneak deposits hint at the sneak).
  Spawns 12 above the altar with an altar-beam arrival. Admin path:
  `/eclipse boss herald summon` (plain `/summon eclipse:herald` also works — the arena
  auto-pins to the spawn point).
- **Bossbar**: PURPLE `NOTCHED_6` `ServerBossEvent` named "☀ The Herald"
  (`entity.eclipse.herald.bossbar`), themed `boss` via `S2CBossbarStylePayload` in
  `startSeenByPlayer` (late joiners included).
- **Fight** (300 HP base; HP ×(1+0.35·(n−1)) for n players within 48 at summon; phase
  breaks at exactly 2/3 and 1/3 = bar notches): **P1 Volley** — hovers 8–12 over the dais
  on a strafe orbit; every 60t a telegraph (shards glow + `boss.herald_telegraph` +
  BEACON_POWER_SELECT, 20t −2t/extra player, floor 12) then 3 homing
  `eclipse:herald_shard` projectiles (4 dmg, `isPickable` — shoot or swat them down);
  every 200t summons 2 Umbral Stalkers (cap 2+n). **P2 Gaze** (≤66%) — volley slows to
  90t; locks one player (ONLY they hear WARDEN_HEARTBEAT), 40t charge with an end-rod
  wisp beam, then 8 dmg + Darkness 5 s **unless a sanctum pillar breaks line of sight at
  the fire moment**. **P3 Collapse** (≤33%) — descends to +3, pulls players 0.08/t inward,
  expanding SOUL_FIRE_FLAME damage rings every 80t (+0.4/t, 6 dmg, jump over them); corona
  shards detach as HP drops and crash as `boss_slam` Quasar AoE (6 dmg, r 2.5).
- **Arena lock**: r=15 around the altar; participants (anyone who enters) are pushed back
  in with the SoftBorder impulse formula + a reverse-portal particle wall. No players
  within 40 blocks for 60 s → full heal + despawn (re-summon with another lure).
- **Drops**: 1 `eclipse:herald_core` (REQUIRED for altar L4 — the default `milestones.json`
  L4 cost is 1 core + 16 ender pearls since W13) at the corpse + 3 umbral shards at EACH
  participant's feet. On first kill:
  `EclipseWorldState.setHeraldDefeated(true)` (→ derived unlock key `herald_slain`) + a
  boss-styled announce.

### Ferryman finale boss — `dev.projecteclipse.eclipse.entity.boss` (W12)

The day-14 finale (`eclipse:ferryman`, spec §2.2): an 18-cube floating robed skeleton
(`client/entity/FerrymanModel`, 128×128 skin, UV in `docs/uv/ferryman.md`; emissive eye
slit + lantern flame, lantern housing joins the glow only while the Gaze mark is live).
Arena = the limbo ghost ship; refuses to exist outside `eclipse:limbo`. Never spawns
naturally.

- **Finale ritual** (`ritual/FinaleRitual`): sneak-use a **dragon egg** on the altar on
  day 14+ after dusk (vanilla item → `RightClickBlock` hook, egg never places). Consumes
  the egg, teleports every LIVING player onto the deck (ghost stragglers pulled aboard),
  plays `intro_submerge` and summons the boss at the stern 100t later. Admin path:
  `/eclipse boss ferryman summon` (direct, no cutscene).
- **Bossbar**: "☠ The Ferryman", themed `boss`, color tracks the phase
  WHITE → PURPLE → RED (breaks at exactly 2/3 and 1/3 HP; base 400, ×(1+0.4·(n−1))).
- **Fight**: **P1 Oar** — deck stalker; telegraphed 180° oar sweep (25t raise +
  TRIDENT_RIPTIDE_3, then 10 dmg + heavy knockback) and a periodic gunwale jump-slam
  (landing AoE + `S2CShakePayload` camera tilt for everyone aboard). Limbo water deals a
  void-cold DoT to living players all fight. **P2 Crew** (≤66%) — kneels invulnerable at
  the stern; Deckhands rise hostile (`DeckhandEntity.riseHostile`), `min(4, ghosts+2)`
  deck lanterns blow out (`limbo/ShipLanterns`, soul campfires; LIT is the lantern state).
  LIVING players cut down the crew, GHOSTS re-light lanterns via a 3 s right-click channel
  (living players are refused); all four burning ends the phase (no ghosts online + crew
  slain force-ends it). **P3 The Toll** (≤33%) — plants the oar; the deck floods one water
  layer per 30 s (air-only `setBlock`, tracked + drained on any fight end; pace halves at
  ≤3 living), sweeps alternate with the **Lantern Gaze**: lowest-health fighter gets a
  private purple vignette (`S2CShakePayload.mark`) + private bell and is hunted 15 s.
- **Endings**: death drops 1 `eclipse:ferryman_toll` (deliberately OUTSIDE the W13 shard
  shop — it stays a one-of-a-kind victory trophy; nothing consumes it), sets
  `ferrymanDefeated`, restores the ship and starts `FinaleRitual.beginVictory`: "THE
  CROSSING ENDS" announce, every banned player revived via `BanService.unban` staggered
  10t apart (offline ghosts cleared for revive-on-login), then everyone still in limbo is
  teleported home and `finale_return` plays for all online players. A wipe (every
  participant dead/banned) is the Eclipse's victory: announce, ship restored, everyone
  stays a ghost. Abandoned for 60 s → silent reset (full heal + despawn + restore).

### Shard economy & rewards — `dev.projecteclipse.eclipse.economy` (W13)

The umbral-shard reward economy (spec `docs/ideas/04_content.md` §4). All feedback is
action-bar + sounds — never chat.

- **Shard shop UX** (`ShardEconomy`, at the sanctum altar): (1) **bank** — sneak-right-click
  the altar with umbral shards (`UmbralShardItem#useOn`); the WHOLE stack is deposited,
  crediting the player's persisted `eclipse:shards` attachment AND the team pool
  (`EclipseWorldState.shardPool`) simultaneously. (2) **browse** — sneak while *looking at*
  the altar (6-block `Level.clip` ray) and the offer list cycles on the action bar every
  20t. (3) **buy** — sneak-punch (left-click) the altar to buy the offer currently shown;
  the event is cancelled so the altar never takes damage. Personal rewards deduct only the
  personal balance; the pooled Supply Beacon deducts only the pool. Right-clicking the
  altar with shards while NOT a milestone cost shows a "sneak to bank" hint instead of
  "wrong item". Offers: Grave Dowser 4 · Compass of the Watcher 8 · Vitae Shard 12 ·
  Umbral Pick 12 · Umbral Blade 16 · Team Supply Beacon 24 (pooled).
- **`compass_of_watcher`** — `inventoryTick` (every 40t, server side) writes the nearest
  OTHER non-spectator player's `GlobalPos` into the vanilla `minecraft:lodestone_tracker`
  component (`tracked=false` so it never breaks when the "lodestone" is missing). Never
  reveals WHO it points at. Same-dimension targets only; no target = component cleared
  (needle wobbles).
- **`grave_dowser`** — same component trick pointed at the holder's nearest OWN grave from
  `EclipseWorldState.gravePositions` (appended where `LifecycleEvents` places a grave,
  removed in `GraveBlock.onRemove` — loot/scatter/break all pass through it).
- **Both compasses** render through 32 generated needle frames (`angle` predicate item
  models, `CompassItemPropertyFunction` registered per item in `client/EclipseClient` —
  separate instances so the wobble states don't interfere).
- **`vitae_shard`** — consumable, 32t use (TOOT_HORN pose), TOTEM_USE sound + totem
  particles, `LivesApi.add(player, +1)` capped at `HeartsService.MAX_HEARTS` (7); refuses
  to start when already at cap.
- **Umbral tools** (`UmbralTier`: diamond-grade, 2500 durability, NOT repairable —
  empty repair ingredient): `umbral_pick` gets +50% break speed under open night sky
  (`PlayerEvent.BreakSpeed`); `umbral_blade` drinks +1 heart on player kill on top of the
  regular PvP heart transfer, still capped at 7 (`lives.LifecycleEvents` kill path).
- **Team Supply Beacon** (`SupplyBeacon.drop`) — spends 24 pooled shards: a barrel
  `FallingBlockEntity` (with `blockData` carrying the `eclipse:supply_crate` loot table)
  falls from the sky 50–100 blocks from the altar at a random angle; an END_ROD particle
  column + `ALTAR_BEAM` Quasar burst marks the site for ~2 min. Coordinates are NEVER
  announced — the beam is the only hint. Loot: `data/eclipse/loot_table/supply_crate.json`
  (iron/gold/bread/arrows/obsidian/pearls/XP bottles + 1–3 bonus shards).
- **Placeholder art**: `scripts/placeholder_gen/EconomyIconPlaceholder.java` regenerates
  all 16×16 icons + the 2×32 compass needle frames + the frame model JSONs.

### Death economy — `dev.projecteclipse.eclipse.lives`

`LifecycleEvents` (`@EventBusSubscriber`, game bus) drives deaths: snapshot `"death"` first, killer gets +1 / victim
-1 heart (PvE: victim -1 only), a global thunder cue plays to every online player at their own position
(no chat — `showDeathMessages` is forced to `false` on `ServerStartedEvent`), player drops are diverted into a
`eclipse:grave` block, and at 0 hearts the victim is banned. `PlayerRespawnEvent` re-applies the limbo ghost state
for banned players (a corpse cannot be teleported at death time), sends `S2CHeartBurstPayload`, and triggers the
`eclipse:heart_burst` Quasar emitter at the respawned player. The client shatter layer is registered above (not
instead of) vanilla `PLAYER_HEALTH`; low-health heartbeat/vignette effects honor `reducedFx`.

```java
public final class BanService {
    public static final String GHOST_TEAM_NAME = "eclipse_ghosts";
    public static void ban(ServerPlayer player);            // attachment+world state, snapshot "ban", inheritance, ghost state
    public static void unban(ServerPlayer player);          // reverses ban, LivesApi.set(player, 1), overworld spawn
    public static void applyLimboState(ServerPlayer player); // adventure, ghost team, glowing+slow falling, tp eclipse:limbo (fallback overworld spawn)
    public static boolean isBanned(ServerPlayer player);
}

public final class InheritanceService {
    public static void inherit(ServerPlayer player);                          // empty ender chest -> spawn chests
    public static void depositAtSpawn(ServerLevel level, List<ItemStack> stacks); // 9x9 chest search, places chests, drops leftovers
}

public class GraveBlockEntity extends BlockEntity {          // type eclipse:grave (block in EclipseBlocks.GRAVE)
    public void initialize(UUID ownerUuid, long createdGameTime, List<ItemStack> drops);
    public UUID getOwnerUuid();       public long getCreatedGameTime();
    public List<ItemStack> getStoredItems();                 // unmodifiable view
    public boolean isOwner(Player player);                   // ownerless graves are open to everyone
    public boolean isGraceElapsed();  public boolean canOpen(Player player);
    public List<ItemStack> removeAllItems();                 // drains the BE, leaves the block
    public void giveTo(ServerPlayer player);                 // hand over contents + remove block
    public void scatter();                                   // drop contents into the world + remove block
    public static void serverTick(Level level, BlockPos pos, BlockState state, GraveBlockEntity grave);
}
```

`dev.projecteclipse.eclipse.limbo.LimboDimension.LIMBO` is the `ResourceKey<Level>` for `eclipse:limbo`.
The dimension is defined by datapack JSON in the jar (`data/eclipse/dimension{,_type}/limbo.json`,
`data/eclipse/worldgen/biome/limbo.json`): a flat barrier-floored ocean (top water block y=48),
fixed twilight time, purple/dark fog. Grave textures are 16x16 placeholders at
`assets/eclipse/textures/block/grave{,_side}.png`.

### Limbo & start event — `dev.projecteclipse.eclipse.limbo`

`GhostShipBuilder` builds the dark-oak ghost ship (~39x9, deck y=51) + spawn platform procedurally on
`ServerStartedEvent`, once (guarded by `EclipseWorldState.isGhostShipBuilt()`). `OarAnimator` owns the
eight `minecraft:block_display` oars (stripped dark oak logs): spawned once, UUIDs persisted via
`EclipseWorldState.getOarEntities()` and re-attached by UUID on restart; a `LevelTickEvent.Post` loop
re-poses them every 30 ticks (±25° about Z, mirrored per side) with client-side interpolation. The
`Display` transformation setters are opened in `META-INF/accesstransformer.cfg`.

```java
public final class StartEventCutscene {
    public static boolean begin(MinecraftServer server); // /eclipse start_event server flow; false if already running
}
```

Timeline (server tick counter): t=0 TILT payload + oar keel-over + `eclipse:event.submerge` to all
+ `CutsceneService.play("intro_submerge", all)` (camera flight + freeze; limbo-scoped);
t=100 SUBMERGE + WAVES; t=140 players in Limbo rise out of carved pockets at overworld spawn,
then `intro_rise` (anchor `player`) chains for exactly those players with a freeze grace
re-anchor covering the launch; t=150 pockets refill; t=160 EMERGE, `startEventDone=true`,
`first_overworld_join` stamped if unset, intro fusion starts (the `intro_rise` flight keeps
running into the fusion rumble). The v1 wave overlay renders through the flights (whitelisted
from HUD suppression).

Sounds (`EclipseSounds`): `AMBIENT_LIMBO_LOOP` (`eclipse:ambient.limbo_loop`, also the limbo biome's
`ambient_sound`), `EVENT_SUBMERGE` (`eclipse:event.submerge`), `EVENT_EMERGE`
(`eclipse:event.emerge`, cutscene-path end cue — currently the submerge OGG re-pitched in
`sounds.json`), and the heart HUD's `UI_HEART_SHATTER` (`eclipse:ui.heart_shatter`); all
currently ship tiny silent placeholder OGGs under `assets/eclipse/sounds/`.

### Disc worldgen — `dev.projecteclipse.eclipse.worldgen`

v2 replaces vanilla overworld/nether generation with deterministic floating discs
(`data/minecraft/dimension/{overworld,the_nether}.json` set `"generator": {"type": "eclipse:disc",
"profile": "overworld"|"nether"}`; codecs registered in `registry/EclipseWorldgen` as
`eclipse:disc` / `eclipse:disc_sectors`). The limbo dimension is untouched.

One pure terrain function feeds everything — the chunk generator for never-generated chunks and
(worker 4) the runtime ring-growth sweep for already-generated ones, so their output is
byte-identical. ALL noise is seeded from `DiscMapData.ECLIPSE_SEED`, never the world seed.

```java
// THE terrain function. Pure in (profile, x, y, z, stage).
public static BlockState DiscTerrainFunction.stateAt(DiscProfile profile, int x, int y, int z, int stage);
// Hot-loop form (identical output): one column precompute + per-Y lookup.
public static DiscColumn  DiscTerrainFunction.column(DiscProfile profile, int x, int z, int stage);
public static BlockState  DiscTerrainFunction.stateInColumn(DiscColumn col, int y);
public static int         DiscTerrainFunction.surfaceY(DiscProfile profile, int x, int z);
public static final int   DiscTerrainFunction.RIM_REWRITE_MARGIN; // ring sweep rewrite band, see javadoc

public static BlockPos DiscGeometry.playerDiscCenter(int index);  // 8 player discs r=24 on ring r=170
public static int      DiscGeometry.mainDiscRadius(int stage);    // 96 / 225 / 300 / 360 / 420 / 480
public static int      StageRadii.radius(DiscProfile p, int stage); // stages.json overrides via EclipseConfig
public static int      WorldStageAccess.stage(DiscProfile p);     // committed stage seam, default 0;
public static void     WorldStageAccess.setStage(DiscProfile p, int stage); // WorldStageService drives this
```

Stage radii: overworld stage 0 = main disc r=96 + eight player discs r=24 on ring r=170, stages
1–5 = 225/300/360/420/480; nether stages 1–3 = 80/120/160 (stage 0 = no nether disc yet). The
lens underside normalises against the FINAL radius so interior columns never change when a stage
grows; only the rim taper band is stage-dependent. `fillFromNoise` reads the stage per chunk via
`WorldStageAccess` (volatile static — safe on worldgen threads, no server lookup).

Map control data is authored JSON, not painted PNGs: `config/eclipse/disc_map.json` (defaults
written by code on first use, like `EclipseConfig`) holds the angular biome sector wedges, the
mountain (center/peak/stronghold cavity), the nether lava moat, landmarks, rivers and whisper
wells. An optional grayscale 1024x1024 PNG at `config/eclipse/disc_heightmap.png` overrides the
procedural overworld surface (`surfaceY = 40 + red`, 1px = 1 block, centered on 0,0) via
`DiscMapData.loadHeightmapOverride`. `DiscBiomeSource` resolves the same wedges to real biome
holders, so blocks and biomes always agree.

Spawn: `DiscSpawnPlacement` pins the overworld spawn to `(0, surfaceY(0,0)+1, 0)` — the flat pad
the terrain carves at the origin for the altar + sanctum — on every server start (HIGH priority,
before `SoftBorder` pins the ring center to the spawn). The v1 start-event flow is unchanged:
`StartEventCutscene` still teleports players from limbo to the shared spawn.

### World stages — `dev.projecteclipse.eclipse.worldgen.stage`

The disc grows ring-by-ring at runtime. `WorldStageService.setStage` is the ONLY way a stage
commits; order of operations: persist in `EclipseWorldState` → publish into the
`WorldStageAccess` chunkgen seam → broadcast `S2CStagePayload` → kick the `RingGrowthService`
sweep. Radii/triggers/structures come from `config/eclipse/stages.json` (defaults: overworld
stages 1–5 = r 225/300/360/420/480 triggered by intro_fusion / milestone:2..4 / final_day;
nether stages 1–3 = r 80/120/160 on day:2/10/12); `EclipseConfig` pushes the radii into
`StageRadii` on every (re)load.

```java
public final class WorldStageService { // @EventBusSubscriber (game bus)
    @FunctionalInterface public interface StageListener {
        void onStageTerrainComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage);
    }
    public static void addListener(StageListener listener); // W5 structure stamping subscribes here
    public static boolean setStage(MinecraftServer server, ResourceKey<Level> dim, int stage, boolean animate);
    public static boolean rebuildStage(MinecraftServer server, ResourceKey<Level> dim, int stage); // repair re-stamp
    public static int stage(MinecraftServer server, DiscProfile profile);   // committed stage
    public static int maxStage(DiscProfile profile);                        // highest configured stage
    public static DiscProfile profileOf(ResourceKey<Level> dim);            // null for non-disc dims
    public static ResourceKey<Level> dimensionOf(DiscProfile profile);
    public static void syncStagesTo(ServerPlayer player);                   // login payload sync
}

public final class RingGrowthService { // @EventBusSubscriber (game bus)
    public static boolean isRunning(DiscProfile profile);
    public static boolean isRunningIntroFusion(); // the animated overworld 0 -> 1 sweep
    public static String progressLine(DiscProfile profile); // null when idle
}

public final class FusionSequence { // @EventBusSubscriber (game bus)
    // Starts the intro fusion (overworld 0 -> 1, animated) once per world; no-op when the
    // stage is already >= 1 or stages.json changed stage 1's trigger. Called automatically
    // when StartEventCutscene finishes (startEventDone flips true); W6 cinematics may call
    // it directly instead — it is idempotent.
    public static boolean maybeStartIntroFusion(MinecraftServer server);
}
```

The sweep rewrites every column of the annulus `min(r0,r1) − RIM_REWRITE_MARGIN … max(r0,r1) +
RIM_NOISE_AMP` with `DiscTerrainFunction` output at the committed stage (byte-identical to
chunkgen; transitions touching overworld stage 0 automatically span the void gap and the eight
player discs). GROW orders columns radius-then-angle (an angular wave), ERASE outer-radius-first
(the disc crumbles inward); lowering a stage is the same sweep — the terrain function simply
returns air beyond the smaller radius. Writes go straight into chunk sections (no neighbor
updates); a finished chunk gets heightmaps re-primed, light fully rebuilt through the
`ThreadedLevelLightEngine` task queue (≤ 4 chunk relights/tick) and a
`ClientboundLevelChunkWithLightPacket` resend. Loaded chunks are rewritten live,
generated-but-unloaded chunks (found via async region reads) are ticket-loaded and rewritten,
never-generated chunks are skipped (chunkgen covers them at the committed stage). Animated
sweeps drain a `ringBlocksBudgetMs` (2 ms) nanoTime budget per tick and skip ticks while
MSPT > 40; instant mode uses a 25 ms budget. The growth cursor persists every ~100 columns, so
a restart resumes mid-animation (`ServerStartedEvent`). The persisted stages are re-published
into the chunkgen seam on `LevelEvent.Load` of the overworld — before any spawn chunk generates.

**Intro fusion** (`FusionSequence`): the overworld 0 → 1 sweep orders columns by distance to
the nearest pre-existing disc edge (main r=96 rim or any player-disc rim) instead of by radius,
so land bridges grow from every disc simultaneously and race toward each other (~60–90 s, paced
towards ~1500 ticks). While it runs, all players get a low-pitched thunder rumble plus one
`S2CCutscenePayload(SHAKE)` impulse every 2 s. It is triggered automatically when the
start-event cutscene completes, guarded to run once (committed stage must still be 0).

**Stage snapshots (W14 dev tooling — `dev.projecteclipse.eclipse.devtools.StageIO`)**: a
"stage" can also be SAVED as a snapshot of the ring annulus between stage N−1 and N radii
(band `radius(N−1) − RIM_REWRITE_MARGIN .. radius(N) + RIM_NOISE_AMP`, the exact band a
sweep rewrites). `/eclipse stage save <n>` writes `<world>/eclipse/stages/<n>.bin` —
gzip NBT holding, per intersecting chunk, the raw section palettes (`PalettedContainer.codecRW`,
identical to vanilla region NBT, lifted verbatim for unloaded chunks) plus the chunk's block
entity NBT list. `load <n>` re-applies it with a tick-budgeted writer that reuses the sweep's
relight/resend machinery (extracted into `worldgen.stage.BudgetedBlockWriter`); `revert`
re-applies the last-loaded snapshot (persisted per dimension). Workflow: `load N` →
hand-edit terrain → `save N` → later `load N+1`. Additionally
`devtools.PristineSnapshots` backs up whole region dirs (`/eclipse stage snapshot`,
restore-on-restart via marker file).

**Triggers** (`stages.json` `trigger` field, evaluated per dimension, raise-only):
`intro_fusion` — fired by the cutscene hook above; `day:N` — evaluated by
`DayScheduler.setDay` after each day change (cumulative, so day jumps catch up; nether gets
its first disc at day 2, before the portal unlock); `final_day` — same evaluation, fires at
day ≥ 12; `milestone:N` — `WorldStageService` polls the altar level every second and raises
matching stages on any altar-level change (catches the altar ritual and `/eclipse altar set`
alike). All trigger sweeps are animated. Triggers never lower a stage — erasing terrain is
always a manual `/eclipse stage set` decision.

### Structures — `dev.projecteclipse.eclipse.worldgen.structure`

`StructureStamper` registers a `WorldStageService.StageListener`: when a stage's terrain
work completes (grown, never erased), the `structures[]` of every crossed stage are stamped
at their `disc_map.json` landmark positions. Vanilla structures are generated
programmatically like `/place structure` (`Structure.generate(...)` with the fixed
`ECLIPSE_SEED`, then `StructureStart.placeInChunk` per chunk, then start + references booked
into the chunk structure data): `eclipse:desert_temple` → `minecraft:desert_pyramid`,
`eclipse:jungle_temple` → `minecraft:jungle_pyramid`, `eclipse:village_plains` →
`minecraft:village_plains` (a coarse-dirt plaza is flattened first). If vanilla generation
fails twice, a compact procedural `FallbackBuilders` stand-in is built instead — a listed
structure never silently misses; the log states which path ran. `eclipse:fortress_core`
(nether N1 keep + caged blaze spawner) and the §F flavor landmarks (watcher statues on
stage-1 completion, sundial plaza whose basalt shadow line `DayScheduler.setDay` repositions)
are always procedural. `eclipse:stronghold_emergence` (stage 5) runs the paced finale:
global quake, a tick-budgeted fissure trench down the mountainside, an `eclipse:altar_beam`
Quasar burst, then `minecraft:stronghold` with EVERY piece translated so the portal room
sits centered in the sealed mountain-core cavity — end portal frames forced eye-less. A
start-up self-check re-runs the emergence if stage 5 is committed but the cavity holds no
portal frame. `/locate structure` (and eyes of ender) resolve through
`DiscChunkGenerator.findNearestMapStructure`, which maps the vanilla ids (`desert_pyramid`,
`jungle_pyramid`, `village_plains`, `stronghold`, `fortress`) to their fixed landmark sites
once the landmark's stage is committed — the vanilla placement-driven lookup can never hit
because `createStructures` is disabled.

`AltarSanctumBuilder` builds the "Sanctum of the Occluded Sun" once per world on
`ServerStartedEvent` (guard: `EclipseWorldState.isSanctumBuilt()`), centering on a
pre-existing v1 altar block if an admin already placed one near spawn (never overwritten);
otherwise `EclipseBlocks.ALTAR` is placed at (0, ground+4, 0). The world spawn is re-pinned
onto the south approach path every start (the pad center is the dais). `SanctumProtection`
(game bus) cancels block break/place, strips explosion block damage and suppresses
non-eclipse hostile spawns within r=16 of the altar; ops (permission ≥ 3) are exempt.

```java
public final class AltarSanctumBuilder { // W11: pillars are Herald LOS cover
    public static final int PILLAR_RING_RADIUS = 9;        // 8 pillars, every 45° from +X
    public static final int[] PILLAR_SHAFT_HEIGHTS = {4, 6, 7, 5, 6, 4, 7, 5};
    public static BlockPos pillarBaseCorner(BlockPos altarPos, int index); // NW corner of 2×2 base
    public static List<BlockPos> pillarBases(BlockPos altarPos);           // all 8, index order
    public static int pillarTopY(BlockPos altarPos, int index);            // highest shaft block
}
public final class SanctumProtection {
    public static boolean isProtected(Level level, BlockPos pos); // r=16 around the altar
}
// EclipseWorldState: isSanctumBuilt(), getSanctumAltarPos() (null until built), setSanctumBuilt(pos)
```

## Progression & Mod Gating

All progression enforcement lives in `dev.projecteclipse.eclipse.progression` and is fully
server-authoritative. Everything is *derived* from `EclipseWorldState` (day/altar level) +
`EclipseConfig`, so every lock is reversible: unlock a key and the enforcement simply stops;
lower the day and it re-applies. Blocked actions show a brief action-bar hint — never chat.

```java
public final class DayScheduler {   // @EventBusSubscriber (game bus)
    public static int getDay(MinecraftServer server);
    public static void setDay(MinecraftServer server, int day); // clamps to >= 1; admin-command entry point
}

public final class UnlockState {
    public static boolean isUnlocked(MinecraftServer server, String key);
    public static Set<String> unlockedKeys(MinecraftServer server); // unmodifiable
}

public final class BorderController { // vanilla FAILSAFE border owner (since W7)
    public static void setBorder(MinecraftServer server, double size, long ms); // legacy: ring radius = size/2
    public static void applyFailsafe(MinecraftServer server, double ringRadius, long ms); // SoftBorder only
}

public final class SoftBorder {       // border.SoftBorder — @EventBusSubscriber (game bus)
    public static double radius(MinecraftServer server, DiscProfile profile);  // animated; <= 0 = inactive
    public static Vec3 center(MinecraftServer server);
    public static double fxRange(MinecraftServer server);
    public static void setRing(MinecraftServer server, DiscProfile profile, double radius, long ms);
    public static void setFxRange(MinecraftServer server, double blocks);
    public static void onStageCommit(MinecraftServer server, DiscProfile profile, int stage, boolean animate);
    public static void syncTo(ServerPlayer player);                            // login S2CBorderPayload
    public static int stageOuterRadius(DiscProfile profile, int stage);        // stage-0 overworld = player-disc ring
}

public final class ModGate {          // @EventBusSubscriber (game bus)
    public static boolean isNamespaceLocked(MinecraftServer server, String namespace);
    public static boolean isItemLocked(MinecraftServer server, ItemStack stack);
    public static boolean isBlockLocked(MinecraftServer server, BlockState state);
}
```

- **DayScheduler** — `setDay` persists the day in `EclipseWorldState`, broadcasts
  `S2CDayStatePayload` to all players and (on an actual change) plays a global bell
  (`block.bell.use`) to every online player. Since W7 the day plan's `borderSize` is IGNORED
  (one-time deprecation warning) — the soft border follows the world stage via the `day:N`
  stage triggers instead. Days are manual-only by default; set `dayAutoAdvance=true` +
  `dayAutoAdvanceTime="HH:mm"` in `config/eclipse/general.json` to advance once per real-world
  day at that server-local time (the last advance's epoch day is persisted under the reserved
  `EclipseWorldState` milestone-progress key `scheduler:last_auto_advance_epoch_day`, so
  restarts never double-advance). A W14 `devtools.PhaseScheduler` schedule
  (`/eclipse schedule next …`, persisted as `nextPhaseEpochMillis`) SUPERSEDES auto-advance
  while set — the guard in `DayScheduler.onServerTick` skips it with a one-time warning.
- **UnlockState** — the unlocked-key set is the union of `unlocks[]` of all day plans `1..currentDay`
  plus `rewards[]` of all altar milestones `1..altarLevel`; cached, auto-invalidates on day/altar
  changes and config reloads. **Boss gate (W13)**: the `enchanting` key from a day plan is unioned
  only while `EclipseWorldState.isHeraldDefeated()` — day 7 lists it, but it activates only once
  the Herald falls. Milestone `rewards[]` are NOT filtered (an admin milestone can still grant it).
- **GoalTracker (W13)** — per-player daily goal ticking behind `S2CGoalProgressPayload`.
  `complete(player, index)` stamps bit `index` of the `eclipse:goal_progress` attachment
  (`(day << 8) | mask` — a stored day mismatch reads as 0, so day changes self-reset), re-sends
  the player's sidebar payload, and fires the global `GOAL COMPLETE` announce the first time each
  (day, goal) pair is completed by anyone (deduped via the reserved milestone-progress key
  `goal_announced:<day>:<index>`; the raw goal line is passed as the subtitle "key" — unknown keys
  render literally). Auto-detected on the default arc: day 1 goal 3 (altar 4-block proximity poll),
  day 2 goal 1 (nether dimension change), day 7 goal 2 (herald flag, credited to all online),
  day 9 goal 3 (shard pool ≥ 24), day 11 goal 1 (all online players ≥ 4 hearts). Everything else
  is admin-marked: `/eclipse goals tick <player> <index>`. Detectors match by (day, index), so a
  rewritten `days.json` degrades them to manual goals — never a crash.
- **SoftBorder + BorderController (since W7)** — the playable boundary is a CIRCULAR soft border
  (`border.SoftBorder`), one ring per disc dimension, centered on the world spawn (disc origin)
  and following the committed world stage: `ring = stageOuterRadius + borderOffset` (general.json,
  default 12; overworld stage 0 uses the player-disc ring footprint r 194, nether stage 0 = ring
  inactive). Animated stage commits tick-lerp the radius (area-proportional) alongside the
  `RingGrowthService` sweep (~75 s pacing, snapping when the sweep finishes early). Physics
  (server, d² checks; spectators/frozen players skipped): `d > R` applies the inward impulse
  `normalize(center−pos)·min(1.2, 0.25·(d−R)+0.4)` + 0.3 Y (`hurtMarked` velocity sync, elytra
  stopped first, glitch sound + `BORDER_GLITCH` Quasar burst); `d > R+3` teleports onto the
  clamped point at `R−2` with an inward heightmap ground search. Ridden vehicles are impulsed as
  a whole (`getRootVehicle`, scanned in `EntityTickEvent.Post` only when carrying players) and
  eject their players after 3 violations in 40 ticks; ender pearls / chorus fruit / `/tp` targets
  are clamped into `R−2` via `setTargetX/Z` (never cancelled; operators bypass the `/tp` clamp).
  Repeat violators (>5 pushbacks/min) are logged on the anti-cheat channel. The VANILLA border is
  only a hidden failsafe at `ring + 48` (warning 0, damage 0), re-enforced on `ServerStartedEvent`
  by `SoftBorder` via `BorderController.applyFailsafe`, and hidden client-side by the
  `LevelRendererMixin` cancel of `LevelRenderer#renderWorldBorder`. **Known limit (W16 /
  Aeronautics & Sable)**: sub-level airships are not vanilla vehicles — a player standing inside
  one that crosses the ring reads as an un-mounted player moving without ground and is caught by
  the generic `d > R+3` teleport fallback (the ship itself is NOT pushed back).
- **Border client FX (`border.client.BorderFxRenderer`)** — the ring is INVISIBLE until the camera
  is within `fxRange` (server-synced, default 8) of the circle; a single d² early-out per
  frame/tick keeps it zero-cost while far. Three layers: (1) geometry —
  `RenderLevelStageEvent` AFTER_PARTICLES draws a curved strip of quads over ±25° of arc nearest
  the camera (tessellated every ~2 blocks, ±12 blocks around player Y, ≤200 quads — the arc
  narrows on huge rings), textured with the scrolling procedural static
  `textures/environment/border_glitch.png` (`scripts/placeholder_gen/BorderGlitchPlaceholder`),
  additive blend, depth-write off, `alpha = (1 − dist/fxRange) · per-quad noise flicker`;
  (2) particles — throttled `BORDER_GLITCH` Quasar bursts along the visible arc (≥3 ticks apart,
  doubled under `reducedFx`, chance-scaled by proximity); (3) post — the per-tick proximity feeds
  `VeilPostController.setBorderProximity`, driving the `eclipse:border_glitch` pipeline
  (chromatic aberration + horizontal displacement bands + violet edge wash via `Proximity`/`Time`
  uniforms; hard-gated like all Veil post FX). If depth-sorting artifacts appear under Sodium,
  switch the render stage to AFTER_TRANSLUCENT_BLOCKS (comment in the renderer).
- **PhaseInventoryLock** — SURVIVAL/ADVENTURE players only. Every 20 ticks: while `main_inventory`
  is locked, stacks in slots 9–35 are moved to free hotbar slots (or dropped); while `armor` is
  locked, armor slots 36–39 + offhand 40 are cleared the same way — except `eclipse:arm_artifact`
  (resolved via `BuiltInRegistries.ITEM` by id, null-guarded; no compile-time reference).
  Right-clicks are cancelled on: crafting table + anvils (`workbenches`), smithing table
  (`smithing`), enchanting table (`enchanting`), brewing stand (`brewing`), ender chest
  (`ender_chests`). `EntityTravelToDimensionEvent` is cancelled for players heading to the Nether
  (`nether`) or the End (`end`) while locked.
- **ModGate** — reads `EclipseConfig.modGate()` (`gatedNamespaces` + `unlockKeys`, namespace →
  unlock key, defaulting to the namespace itself). While a namespace is locked, for any item/block
  whose registry-id namespace matches: `RightClickBlock`, `RightClickItem`,
  `BlockEvent.EntityPlaceEvent` and `ItemEntityPickupEvent.Pre` are cancelled, and
  `PlayerEvent.ItemCraftedEvent` shrinks the crafted stack to 0. Every 100 ticks a sweep removes
  gated stacks from online SURVIVAL/ADVENTURE inventories and deposits them at spawn via
  `InheritanceService.depositAtSpawn` — items are never destroyed. Matching is **pure namespace
  string comparison**: zero compile-time dependency on Create/Simulated/Aeronautics/Sable.

## Admin commands — `/eclipse`

Registered by `dev.projecteclipse.eclipse.admin.EclipseCommands` on `RegisterCommandsEvent`;
the whole tree requires **permission level 3**. Every subcommand replies only to the command
source (`sendSuccess`/`sendFailure`) — nothing is ever broadcast to player chat.

| Command | Effect |
|---|---|
| `/eclipse start_event` | Runs `StartEventCutscene.begin` (fails if a run is already in progress). |
| `/eclipse day set <1-14>` | `DayScheduler.setDay`: persists the day, applies the plan border, syncs clients. |
| `/eclipse day goals` | Prints the current day's configured goals. |
| `/eclipse goals tick <player> <1-8>` | `GoalTracker.complete` (1-based index, matching the sidebar): ticks the goal for that player, announces the first completion. |
| `/eclipse shards set <player> <n>` \| `add <player> <n>` | Personal shard balance dev tool (`ShardEconomy.setShards`/`addShards`; add may be negative, clamped ≥ 0). |
| `/eclipse shards pool set <n>` | Sets the team shard pool (`EclipseWorldState.setShardPool`). |
| `/eclipse supply drop` | Fires `SupplyBeacon.drop` immediately (free — no pool deduction; the paid path is the shop). |
| `/eclipse event set <pale\|umbral\|none>` | Overrides the active night event (`EclipseWorldState.setActiveNightEvent`); pale/umbral also fire the announcement sweep. |
| `/eclipse boss herald summon` | Summons the Herald over the sanctum altar (or the source position if no sanctum) with the full arrival sequence + scaling. |
| `/eclipse boss herald kill` | Kills every live Herald through the regular death path (drops + `heraldDefeated` flag + announce). |
| `/eclipse boss ferryman summon` | Summons the Ferryman at the limbo ghost ship's stern (scaling + arrival FX; no ritual cutscene). Fails if one is already afloat. |
| `/eclipse boss ferryman kill` | Kills every live Ferryman through the regular death path (toll drop + `ferrymanDefeated` + mass-revive finale). |
| `/eclipse boss ferryman phase <1-3>` | Snaps the live Ferryman's health into that phase's band; the regular transition (crew/sink/bar color) runs next tick. |
| `/eclipse lives set <player> <n>` | `LivesApi.set` (n ≥ 0, clamped; synced to the client). |
| `/eclipse lives add <player> <n>` | `LivesApi.add` (n may be negative). |
| `/eclipse altar set <level>` | Sets `EclipseWorldState.altarLevel` (≥ 0) + re-syncs day state to all clients. |
| `/eclipse ban <player>` | `BanService.ban`: event-ban to Limbo (snapshot `"ban"` + inheritance + ghost state). |
| `/eclipse revive <player>` | `BanService.unban`: back to the overworld spawn with 1 life. |
| `/eclipse restore <player>` | Lists that player's snapshots (index + timestamp + reason) to the source. |
| `/eclipse restore <player> <index>` | `SnapshotService.restore` of the listed 1-based index (inventory + ender chest). |
| `/eclipse border set <size> [seconds]` | Legacy, repointed: overworld ring radius = `size/2` via `SoftBorder.setRing`; omitted seconds = instant snap. |
| `/eclipse border ring set <radius> [seconds]` | `SoftBorder.setRing` on the overworld ring (vanilla failsafe follows at +48). |
| `/eclipse border fx range <blocks>` | `SoftBorder.setFxRange`: persists + re-syncs the client FX visibility band. |
| `/eclipse modgate lock\|unlock <namespace>` | `EclipseConfig.setNamespaceGated`: mutates + persists `modgate.json`. |
| `/eclipse stage get` | Committed stage + radius of both disc dimensions, plus live sweep progress. |
| `/eclipse stage set <overworld\|nether> <n> [instant\|animate]` | `WorldStageService.setStage` (default animate); lowering runs the erase sweep. |
| `/eclipse stage rebuild <overworld\|nether> <n>` | Re-stamps stage `n`'s annulus with the committed terrain (repair). |
| `/eclipse stage save <n>` | `devtools.StageIO`: serializes the stage-`n` annulus (all intersecting chunks — live sections or region NBT; never-generated skipped) to `<world>/eclipse/stages/<n>.bin` (`nether_<n>.bin` when run from the nether). Synchronous. |
| `/eclipse stage load <n>` | Applies a saved `.bin` back onto the world via a tick-budgeted writer (25 ms/tick, ≤4 chunks/tick, relight + resend per chunk); persists `lastLoadedStage` for revert. Committed stage is NOT touched. |
| `/eclipse stage revert` | Re-applies the source dimension's last-loaded snapshot (`EclipseWorldState.lastLoadedStage`). |
| `/eclipse stage status` | Committed stage + last-loaded snapshot + in-flight snapshot/sweep jobs + saved `.bin` files, per disc dimension. |
| `/eclipse stage snapshot save\|restore <name>` | `devtools.PristineSnapshots`: flushes all chunks and copies `region/ entities/ poi/` (+ nether `DIM-1/…`) to `<world>/eclipse/stage_snapshots/<name>/`; `restore` stages a marker consumed at the next boot's `ServerAboutToStartEvent` — requires a restart. |
| `/eclipse schedule next <ISO8601\|+NhNNm>` | `devtools.PhaseScheduler`: schedules the next day advance at an absolute wall-clock instant (persisted, restart-safe). Accepts `+2h30m`/`+45m`/`+90s` or server-local `2026-08-01T18:00`. Shows the purple "Next phase: …" countdown bossbar (W8 `day` skin); supersedes `dayAutoAdvance` while set. |
| `/eclipse schedule list` | Prints the schedule target + remaining (and whether it supersedes `dayAutoAdvance`). |
| `/eclipse schedule clear` | Cancels the schedule and removes the countdown bar. |
| `/eclipse freeze <players> on [seconds]\|off` | `FreezeService.freeze/unfreeze`: full movement lock + invulnerability (rubber-band), watchdog TTL default 300 s. |
| `/eclipse invuln <players> on [seconds]\|off` | `FreezeService.setInvulnerable/clearInvulnerable`: damage + knockback immunity WITHOUT the movement lock (never flips `abilities.invulnerable`), TTL default 300 s. |
| `/eclipse timeline` | `devtools.TimelineInspector`: source-only dump — day/altar, phase schedule, per-dim stage/ring/border/sweep, night event + boss flags, per-player freeze/invuln/cutscene-ACK, `FreezeService` watchdog ring buffer. |
| `/eclipse goals edit` | `devtools.ConfigEditor.openFor`: opens the client goal editor GUI (`S2COpenGoalEditorPayload` with the current `days.json`); Save sends `C2SConfigEditPayload` — perm-3-checked, schema-validated write + `EclipseConfig.reload()` + day-state/milestone/goal re-sync. |
| `/eclipse voicemute <player> on\|off` | `VoiceMuteApi.setForceMuted` (persistent administrative mute). |
| `/eclipse tp_limbo [player]` | Teleports you (or the target) to the Limbo ghost-ship platform. |
| `/eclipse cutscene play <id> [players]` | `CutsceneService.play` for the targets (default: everyone online). |
| `/eclipse cutscene abort [players]` | Aborts active sessions + unfreezes (default: everyone online). |
| `/eclipse cutscene list` | Every loaded path: duration, keyframes, anchor, interpolation, skip/disable flags. |
| `/eclipse cutscene enable\|disable <id>` | `EclipseWorldState.setCutsceneDisabled` (disabled plays complete instantly). |
| `/eclipse cutscene skip allow\|deny <id>` | Persists `allowSkip` into the path JSON + re-syncs the library. |
| `/eclipse cutscene preview <id>` | Plays the shot for YOU only — no freeze, Space skips (editor loop). |
| `/eclipse cutscene edit <id> addkeyframe [t]` | Appends your eye pos/yaw/pitch as a keyframe (auto `t` = last + 0.1). |
| `/eclipse cutscene edit <id> removekeyframe <i>` | Deletes keyframe `i` (a path keeps ≥ 2 keyframes). |
| `/eclipse cutscene edit <id> set roll\|fov <v>` | Mutates the LAST keyframe's roll (±180°) or fov (10–140). |
| `/eclipse cutscene export <id>` | Prints the path's pretty JSON to the source (copy-paste for assets). |
| `/eclipse cutscene reloadpaths` | Re-reads `config/eclipse/cutscenes/` only + re-syncs all clients. |
| `/eclipse reload` | `EclipseConfig.reload()` of all six JSON configs (re-applies `stages.json` radii) + cutscene path library re-read/re-sync. |
| `/eclipse status` | Dumps day / altar level / night event / team shard pool + threshold / soft-border rings + failsafe / start-event flag / unlocked keys / banned list / online players' lives — to the source only. |

## Anti-cheat — `dev.projecteclipse.eclipse.admin.AntiCheatCheck`

`config/eclipse/anticheat.json` holds a config-maintained list of **mod-id substrings**
(defaults: `xray`, `advancedxray`, `freecam`, `freelook`, `replaymod`, `litematica`; matching is
case-insensitive substring against every loaded mod id).

- **Local check** — on `FMLClientSetupEvent` the client scans its own `ModList`; any match throws
  a `RuntimeException` during setup (forced crash — an honest-client deterrent).
- **Network check** — on `ClientPlayerNetworkEvent.LoggingIn` the client sends its sorted mod-id
  list as `C2SModlistPayload` (`eclipse:modlist`, `playToServer`). The server disconnects the
  player if any reported id matches the blocklist, and a `ServerTickEvent.Post` watchdog
  disconnects any player who has not delivered the payload within ~30 s of logging in
  (mandatory-mod enforcement — vanilla clients without Eclipse-Core cannot stay connected).

**Honesty caveat:** this only stops *honest* clients. A modified client can lie about its mod
list, rename mod ids, or strip the check entirely. It is a deterrent, not a security boundary.
A server-side anti-xray (engine-level ore obfuscation) is the recommended follow-up and is out
of scope for v1.

## Server pack (external mods)

**Veil 4.3.0 is a REQUIRED dependency** (`neoforge.mods.toml`: modId `veil`, versionRange
`[4.3.0,)`, ordering AFTER, side BOTH). It is LGPL-3.0 and embedded **jar-in-jar** from
`foundry.veil:veil-neoforge-1.21.1:4.3.0` (repo `https://maven.blamejared.com`) with the open
range `[4.3.0,)`, so a newer Veil supplied by another mod (Sable jar-in-jars Veil `[4.1.4,)`)
deduplicates to the highest version. Veil powers the v2 post pipelines (limbo grade, sun halo),
the Quasar particle systems and easing; the Iris "shaderpack active" gate uses Veil's first-party
`foundry.veil.api.compat.IrisCompat` via the `client/sky/EclipseIrisState` wrapper (the v1
reflection bridge is gone).

The event server additionally runs the following published mods **alongside** `eclipse` in the
server's `mods/` folder (NOT jar-in-jar / bundled inside Eclipse-Core):

| Mod | Version | Jar | Gated namespace |
|---|---|---|---|
| Create | 6.0.10 | `create-1.21.1-6.0.10-280.jar` | `create` |
| Create: Aeronautics | 1.3.0 | bundled jar (includes Simulated) | `aeronautics`, `simulated` |
| Sable | 2.0.3 | `sable-2.0.3.jar` | `sable` |
| Simple Voice Chat | 2.6.16 | `voicechat-neoforge-1.21.1-2.6.16.jar` | — (not gated; used by the voice worker) |

Planned v2 additions (`modgate.json` already gates the namespaces since W13; W16 downloads +
gate-tests the jars, spec §5): Farmer's Delight 1.21.1-1.3.2 (`farmersdelight`), Supplementaries
3.8.3 (`supplementaries`, + Moonlight Lib NOT gated), Sophisticated Backpacks 3.25.71
(`sophisticatedbackpacks`, + Sophisticated Core NOT gated), Create: Crafts & Additions 1.6.0
(`createaddition`).

Recommended client-side additions (performance/shaders; smoke-tested with Eclipse-Core):

| Mod | Version | Jar |
|---|---|---|
| Sodium | 0.6.13 | `sodium-neoforge-0.6.13+mc1.21.1.jar` |
| Iris | 1.8.12 | `iris-neoforge-1.8.12+mc1.21.1.jar` |

**Why not jar-in-jar?** Two reasons. First, licensing: the assets of these mods are
All-Rights-Reserved, so redistributing them inside the Eclipse-Core jar is not permitted —
installing the official jars alongside is. Second, mechanics: a jar-in-jar mod cannot be disabled
at the loader level (FML offers no per-nested-jar toggle, and "unlocking on day N" would require
swapping jars and restarting). Runtime gating by registry namespace is the correct mechanism: the
mods are always *loaded*, but their content is unusable until the matching unlock key is granted
by the day scheduler or an altar milestone. `neoforge.mods.toml` declares all four as
`type="optional"`, `ordering="AFTER"` dependencies, so Eclipse-Core loads with or without them and
after them when present.

Default 14-day unlock schedule (`config/eclipse/days.json`, the v2 arc since W13;
`modgate.json` maps each gated namespace to the key of the same name). The legacy `days.json`
`borderSize` is still written (1000–3000) but DEPRECATED and ignored since W7 — the circular
soft border follows the world-stage timeline (`stages.json`) instead.

| Day | Theme | Unlock keys | Effect |
|---|---|---|---|
| 1 | First Light | — | Hotbar-only inventory, no armor, no workstations, vanilla-only |
| 2 | The Burning Door | `nether`, `main_inventory` | Nether travel opens EARLY + full 36-slot inventory |
| 3 | Machines in the Dark | `workbenches`, `create` | Crafting tables + anvils; Create content usable |
| 4 | The Feast | `armor`, `farmersdelight`, `simulated` | Armor + offhand slots; Farmer's Delight + Simulated usable |
| 5 | Skyward | `aeronautics`, `supplementaries` | Create: Aeronautics + Supplementaries usable |
| 6 | Fortress | — | Herald prep day (fortress, blaze rods, lure) |
| 7 | BOSS: The Herald | `enchanting` (boss-locked) | Enchanting activates only once the Herald falls (`UnlockState` gate) |
| 8 | The Hoard | `ender_chests`, `sophisticatedbackpacks`, `sable` | Ender chests + backpacks; Sable also via milestone L4 |
| 9 | Alchemy & Voltage | `brewing`, `createaddition` | Brewing stands; Create electricity tier |
| 10 | Deep Ruin | `smithing` | Smithing tables |
| 11 | The Weakest Link | — | Economy/revive day |
| 12 | Stronghold | `end` | End travel opens; final expansion + stronghold emergence |
| 13 | The Dragon | — | Dragon day; egg = finale catalyst |
| 14 | BOSS: The Ferryman | — | Finale |

(`sable` also unlocks via altar milestone level 4; milestones can grant
`create`/`simulated`/`aeronautics`/`end` early, see `milestones.json`. Milestone costs since W13:
L1 16 iron, L2 16 gold, L3 8 diamonds, L4 1 `eclipse:herald_core` + 16 ender pearls, L5 2
netherite ingots. The gated-namespace list in `modgate.json` additionally carries
`farmersdelight`, `supplementaries`, `sophisticatedbackpacks` and `createaddition` — their
LIBRARIES `sophisticatedcore` and `moonlight` are deliberately NOT gated. W16 downloads the jars.)

## Layout

- `dev.projecteclipse.eclipse.EclipseMod` — mod entry point (`@Mod("eclipse")`); wires all deferred registers.
- `dev.projecteclipse.eclipse.registry` — `EclipseItems`, `EclipseBlocks`, `EclipseBlockEntities`, `EclipseSounds`, `EclipseParticles`, `EclipseAttachments` (NeoForge attachment types), `EclipseMenus`, `EclipseWorldgen` (disc chunk generator + biome source codecs). Each exposes a `DeferredRegister` and a static `register(IEventBus)`.
- `dev.projecteclipse.eclipse.worldgen` — deterministic disc world core: `DiscTerrainFunction`, `DiscMapData`, `DiscProfile`, `DiscGeometry`, `StageRadii`, `WorldStageAccess`, `DiscChunkGenerator`, `DiscBiomeSource`, `DiscSpawnPlacement` (see "Disc worldgen").
- `dev.projecteclipse.eclipse.client.EclipseClient` — client-only `@EventBusSubscriber(Dist.CLIENT)` shell; `client.ClientStateCache` — server-synced state cache (safe on both dists).
- `dev.projecteclipse.eclipse.client.handbook` — Handbook 2.0 ("Ledger of the Drowned", see "Handbook 2.0"): `HandbookScreen` + `tabs/*`, `GlitchText`, `EclipseWidget`; opened via J / artifact right-click.
- `dev.projecteclipse.eclipse.core.state` / `core.snapshot` / `core.config` / `network` — persistent data core, see "Core APIs".
- `dev.projecteclipse.eclipse.lives` — death economy (`LifecycleEvents`, `BanService`, `InheritanceService`, `GraveBlock`, `GraveBlockEntity`).
- `dev.projecteclipse.eclipse.hearts` — LIVES-to-transient-MAX_HEALTH projection and client heart-shatter/low-health HUD overlay.
- `dev.projecteclipse.eclipse.limbo` — `LimboDimension` (dimension key constant), `GhostShipBuilder`, `OarAnimator`, `StartEventCutscene` (see "Limbo & start event").
- `dev.projecteclipse.eclipse.progression` — `DayScheduler`, `UnlockState`, `GoalTracker` (W13 per-player goal ticking), `BorderController` (vanilla failsafe owner), `PhaseInventoryLock`, `ModGate` (see "Progression & Mod Gating").
- `dev.projecteclipse.eclipse.economy` — W13 umbral-shard economy: `ShardEconomy` (altar shard shop), `WatcherCompassItem`, `GraveDowserItem`, `VitaeShardItem`, `UmbralShardItem` (sneak-deposit hook), `UmbralTier`, `SupplyBeacon` (see "Shard economy & rewards").
- `dev.projecteclipse.eclipse.border` — `SoftBorder` (circular soft worldborder: ring state + physics + teleport clamps); `border.client.BorderFxRenderer` (glitch strip geometry, Quasar arcs, Veil post proximity feed); the vanilla border visual is cancelled by `client.mixin.LevelRendererMixin`.
- `dev.projecteclipse.eclipse.ritual` — ritual altar (`AltarBlock`, `AltarBlockEntity`, `BeamEmitter`) + revive ritual (`ReviveRitual`, `ReviveSigilItem`).
- `dev.projecteclipse.eclipse.entity` / `client.entity` — W10 custom mobs (`EclipseEntities` registry, the five mob classes, `EclipseSpawner` day/event spawner + night events) and their hand-coded models/renderers (`EclipseEntityRenderers`), see "Custom mobs & spawner".
- `dev.projecteclipse.eclipse.artifact` — the arm artifact (`ArmArtifactItem`, hotbar slot 8, J/right-click menu; `ArtifactSlotLock` keeps it in place).
- `dev.projecteclipse.eclipse.veilfx` — client-only Veil integration: `VeilPostController` (limbo/sun-halo/border-glitch post pipelines, Iris+config hard gate, per-frame uniforms) and `QuasarSpawner` (safe Quasar emitter spawning with vanilla fallback). Assets: `assets/eclipse/pinwheel/` (post pipelines + GLSL) and `assets/eclipse/quasar/emitters/` (8 emitter JSONs).
- `dev.projecteclipse.eclipse.admin` — `EclipseCommands` (see "Admin commands") + `AntiCheatCheck` (see "Anti-cheat").
- `dev.projecteclipse.eclipse.devtools` — W14 operator tooling: `StageIO` (stage annulus snapshots, `<world>/eclipse/stages/<n>.bin`), `PristineSnapshots` (whole-region backups + restore-on-restart marker), `PhaseScheduler` (wall-clock day advance + countdown bossbar), `TimelineInspector` (`/eclipse timeline`), `ConfigEditor` (perm-checked goal-editor writes); `devtools.client.GoalEditorScreen` is the client GUI.
- `src/main/templates/META-INF/neoforge.mods.toml` — mod metadata template; `${...}` placeholders are expanded from `gradle.properties` by the `generateModMetadata` task.
- `dev.projecteclipse.eclipse.cutscene` / `cutscene.client` — the cutscene engine (see "Cutscene engine"): server path library + orchestration + freeze, and the client camera director/letterbox/input swallow.
- `src/main/resources/META-INF/accesstransformer.cfg` — opens the `Display` entity transformation setters (`setTransformation`, interpolation duration/delay, `BlockDisplay.setBlockState`) for `OarAnimator`, plus `Camera.setPosition(Vec3)`/`Camera.setRotation(yaw, pitch, roll)` for the cutscene `CameraDirector`; `validateAccessTransformers = true` is enabled in `build.gradle`.

## Known limitations

- **Iris + shaderpacks override the custom sky.** The purple-tinted overworld sky (eclipse sun)
  is rendered by a vanilla-pipeline sky hook; when an Iris shaderpack is active it replaces the
  sky rendering, so only the fog/sky *tint* fallback survives. Running Iris with **no shaderpack
  enabled** keeps the full effect (this is the smoke-tested configuration). The v2 Veil post
  pipelines (limbo grade, sun halo, border glitch) are likewise hard-gated off while a shaderpack
  is active
  (Veil post FX bypass the Iris pipeline and break under a pack); Quasar particles stay on.
- **EMI/recipe viewers show gated recipes.** ModGate blocks crafting/placement/pickup at runtime
  but does not hide recipes from EMI/JEI-style viewers — there is no runtime recipe-hiding hook
  for "unlocks on day N" semantics. Players can *see* Create recipes on day 1; they still cannot
  craft or use the results.
- **Anti-cheat is an honest-client deterrent only** — see the honesty caveat under "Anti-cheat".
  Server-side anti-xray is the recommended follow-up for v2.
- **Create: Aeronautics is not jar-in-jar'd** (nor are Create/Sable/Voice Chat) — licensing forbids
  redistribution and FML cannot toggle nested jars at runtime; see "Why not jar-in-jar?".
- **Textures/sounds are placeholder programmer-art** — grave/altar/artifact textures, the uniform
  skin, and the two OGG sound events are minimal placeholders pending final art.
