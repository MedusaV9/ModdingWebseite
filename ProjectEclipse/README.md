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
public double getBorderSize();                public void setBorderSize(double borderSize);   // default 1000.0
public boolean isStartEventDone();            public void setStartEventDone(boolean done);    // default false
public boolean isGhostShipBuilt();            public void setGhostShipBuilt(boolean built);   // default false
public List<UUID> getOarEntities();           public void setOarEntities(List<UUID> ids);     // ghost ship oar displays

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
        int ringBlocksBudgetMs, boolean cutscenesFreezeDuringUnlocks) {}
// general.json; defaults: 30, false, "08:00", 2, true (JSON: "cutscenes":{"freezeDuringUnlocks"})
public record DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize) {}
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

Default unlock keys per day: 1 `[]`, 2 `[main_inventory]`, 3 `[workbenches, create]` (border 1500),
4 `[armor, simulated]`, 5 `[aeronautics]` (border 2000), 6 `[nether]`, 7 `[enchanting]`,
8 `[ender_chests]` (border 2500), 9 `[brewing]`, 10 `[smithing]`, 11 `[]` (border 3000), 12 `[end]`, 13 `[]`, 14 `[]`.

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
public record S2CCutsceneLibraryPayload(Map<String, String> pathsJson) implements CustomPacketPayload; // id "eclipse:cutscene_library"
// Full camera-path library as raw JSON keyed by path id; sent at login and after
// reloadpaths/editor writes. Client re-parses via cutscene.CutscenePath.parse.
public record S2CCutscenePlayPayload(String id, boolean allowSkip, Optional<Vec3> anchor) implements CustomPacketPayload; // id "eclipse:cutscene_play"
// Start playing a synced path; empty id = STOP sentinel (abort / granted skip). anchor
// overrides the world-anchor origin (e.g. unlock_ring's ring edge).
public record C2SCutsceneStatePayload(String id, State state) implements CustomPacketPayload; // id "eclipse:cutscene_state"
// C2SCutsceneStatePayload.State: enum { STARTED, FINISHED, SKIP_REQUEST, SKIPPED } — playback
// ACKs + skip requests, validated/handled by cutscene.CutsceneService.handleClientState.
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
before `BorderController` centers the border on spawn). The v1 start-event flow is unchanged:
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

public final class BorderController { // @EventBusSubscriber (game bus)
    public static void setBorder(MinecraftServer server, double size, long ms); // lerp; ms <= 0 snaps
}

public final class ModGate {          // @EventBusSubscriber (game bus)
    public static boolean isNamespaceLocked(MinecraftServer server, String namespace);
    public static boolean isItemLocked(MinecraftServer server, ItemStack stack);
    public static boolean isBlockLocked(MinecraftServer server, BlockState state);
}
```

- **DayScheduler** — `setDay` persists the day in `EclipseWorldState`, applies the day plan's
  `borderSize` via `BorderController` (60 s lerp), broadcasts `S2CDayStatePayload` to all players
  and (on an actual change) plays a global bell (`block.bell.use`) to every online player. Days are
  manual-only by default; set `dayAutoAdvance=true` + `dayAutoAdvanceTime="HH:mm"` in
  `config/eclipse/general.json` to advance once per real-world day at that server-local time (the
  last advance's epoch day is persisted under the reserved `EclipseWorldState` milestone-progress
  key `scheduler:last_auto_advance_epoch_day`, so restarts never double-advance).
- **UnlockState** — the unlocked-key set is the union of `unlocks[]` of all day plans `1..currentDay`
  plus `rewards[]` of all altar milestones `1..altarLevel`; cached, auto-invalidates on day/altar
  changes and config reloads.
- **BorderController** — border is always centered on the shared world spawn; on `ServerStartedEvent`
  the size stored in `EclipseWorldState.getBorderSize()` (default **1000**) is re-enforced, so manual
  `/worldborder` edits do not survive a restart. `setBorder` persists the new size.
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
| `/eclipse lives set <player> <n>` | `LivesApi.set` (n ≥ 0, clamped; synced to the client). |
| `/eclipse lives add <player> <n>` | `LivesApi.add` (n may be negative). |
| `/eclipse altar set <level>` | Sets `EclipseWorldState.altarLevel` (≥ 0) + re-syncs day state to all clients. |
| `/eclipse ban <player>` | `BanService.ban`: event-ban to Limbo (snapshot `"ban"` + inheritance + ghost state). |
| `/eclipse revive <player>` | `BanService.unban`: back to the overworld spawn with 1 life. |
| `/eclipse restore <player>` | Lists that player's snapshots (index + timestamp + reason) to the source. |
| `/eclipse restore <player> <index>` | `SnapshotService.restore` of the listed 1-based index (inventory + ender chest). |
| `/eclipse border set <size> [seconds]` | `BorderController.setBorder`; omitted seconds = instant snap. |
| `/eclipse modgate lock\|unlock <namespace>` | `EclipseConfig.setNamespaceGated`: mutates + persists `modgate.json`. |
| `/eclipse stage get` | Committed stage + radius of both disc dimensions, plus live sweep progress. |
| `/eclipse stage set <overworld\|nether> <n> [instant\|animate]` | `WorldStageService.setStage` (default animate); lowering runs the erase sweep. |
| `/eclipse stage rebuild <overworld\|nether> <n>` | Re-stamps stage `n`'s annulus with the committed terrain (repair). |
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
| `/eclipse status` | Dumps day / altar level / border / start-event flag / unlocked keys / banned list / online players' lives — to the source only. |

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

Default 14-day unlock schedule (`config/eclipse/days.json`; `modgate.json` maps each gated
namespace to the key of the same name):

| Day | Unlock keys | Border | Effect |
|---|---|---|---|
| 1 | — | 1000 | Hotbar-only inventory, no armor, no workstations, vanilla-only |
| 2 | `main_inventory` | 1000 | Full 36-slot inventory usable |
| 3 | `workbenches`, `create` | 1500 | Crafting tables + anvils; Create content usable |
| 4 | `armor`, `simulated` | 1500 | Armor + offhand slots; Simulated content usable |
| 5 | `aeronautics` | 2000 | Create: Aeronautics content usable |
| 6 | `nether` | 2000 | Nether travel opens |
| 7 | `enchanting` | 2000 | Enchanting tables |
| 8 | `ender_chests` | 2500 | Ender chests |
| 9 | `brewing` | 2500 | Brewing stands |
| 10 | `smithing` | 2500 | Smithing tables |
| 11 | — | 3000 | Final border expansion |
| 12 | `end` | 3000 | End travel opens |
| 13 | — | 3000 | — |
| 14 | — | 3000 | Finale |

(`sable` has no day entry by default — it unlocks via altar milestone level 4; milestones can also
grant `create`/`simulated`/`aeronautics`/`end` early, see `milestones.json`.)

## Layout

- `dev.projecteclipse.eclipse.EclipseMod` — mod entry point (`@Mod("eclipse")`); wires all deferred registers.
- `dev.projecteclipse.eclipse.registry` — `EclipseItems`, `EclipseBlocks`, `EclipseBlockEntities`, `EclipseSounds`, `EclipseParticles`, `EclipseAttachments` (NeoForge attachment types), `EclipseMenus`, `EclipseWorldgen` (disc chunk generator + biome source codecs). Each exposes a `DeferredRegister` and a static `register(IEventBus)`.
- `dev.projecteclipse.eclipse.worldgen` — deterministic disc world core: `DiscTerrainFunction`, `DiscMapData`, `DiscProfile`, `DiscGeometry`, `StageRadii`, `WorldStageAccess`, `DiscChunkGenerator`, `DiscBiomeSource`, `DiscSpawnPlacement` (see "Disc worldgen").
- `dev.projecteclipse.eclipse.client.EclipseClient` — client-only `@EventBusSubscriber(Dist.CLIENT)` shell; `client.ClientStateCache` — server-synced state cache (safe on both dists).
- `dev.projecteclipse.eclipse.core.state` / `core.snapshot` / `core.config` / `network` — persistent data core, see "Core APIs".
- `dev.projecteclipse.eclipse.lives` — death economy (`LifecycleEvents`, `BanService`, `InheritanceService`, `GraveBlock`, `GraveBlockEntity`).
- `dev.projecteclipse.eclipse.hearts` — LIVES-to-transient-MAX_HEALTH projection and client heart-shatter/low-health HUD overlay.
- `dev.projecteclipse.eclipse.limbo` — `LimboDimension` (dimension key constant), `GhostShipBuilder`, `OarAnimator`, `StartEventCutscene` (see "Limbo & start event").
- `dev.projecteclipse.eclipse.progression` — `DayScheduler`, `UnlockState`, `BorderController`, `PhaseInventoryLock`, `ModGate` (see "Progression & Mod Gating").
- `dev.projecteclipse.eclipse.ritual` — ritual altar (`AltarBlock`, `AltarBlockEntity`, `BeamEmitter`) + revive ritual (`ReviveRitual`, `ReviveSigilItem`).
- `dev.projecteclipse.eclipse.artifact` — the arm artifact (`ArmArtifactItem`, hotbar slot 8, J/right-click menu; `ArtifactSlotLock` keeps it in place).
- `dev.projecteclipse.eclipse.veilfx` — client-only Veil integration: `VeilPostController` (limbo/sun-halo post pipelines, Iris+config hard gate, per-frame uniforms) and `QuasarSpawner` (safe Quasar emitter spawning with vanilla fallback). Assets: `assets/eclipse/pinwheel/` (post pipelines + GLSL) and `assets/eclipse/quasar/emitters/` (8 emitter JSONs).
- `dev.projecteclipse.eclipse.admin` — `EclipseCommands` (see "Admin commands") + `AntiCheatCheck` (see "Anti-cheat").
- `src/main/templates/META-INF/neoforge.mods.toml` — mod metadata template; `${...}` placeholders are expanded from `gradle.properties` by the `generateModMetadata` task.
- `dev.projecteclipse.eclipse.cutscene` / `cutscene.client` — the cutscene engine (see "Cutscene engine"): server path library + orchestration + freeze, and the client camera director/letterbox/input swallow.
- `src/main/resources/META-INF/accesstransformer.cfg` — opens the `Display` entity transformation setters (`setTransformation`, interpolation duration/delay, `BlockDisplay.setBlockState`) for `OarAnimator`, plus `Camera.setPosition(Vec3)`/`Camera.setRotation(yaw, pitch, roll)` for the cutscene `CameraDirector`; `validateAccessTransformers = true` is enabled in `build.gradle`.

## Known limitations

- **Iris + shaderpacks override the custom sky.** The purple-tinted overworld sky (eclipse sun)
  is rendered by a vanilla-pipeline sky hook; when an Iris shaderpack is active it replaces the
  sky rendering, so only the fog/sky *tint* fallback survives. Running Iris with **no shaderpack
  enabled** keeps the full effect (this is the smoke-tested configuration). The v2 Veil post
  pipelines (limbo grade, sun halo) are likewise hard-gated off while a shaderpack is active
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
