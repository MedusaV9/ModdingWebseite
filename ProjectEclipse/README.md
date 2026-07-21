# Project: Eclipse (Eclipse-Core)

A NeoForge server-event mod for Minecraft.

- **Mod id**: `eclipse` | **Display name**: Eclipse-Core
- **Package root**: `dev.projecteclipse.eclipse`
- **Minecraft**: 1.21.1
- **NeoForge**: 21.1.238
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

Note: if you pipe `runServer` output through another process (e.g. `| tee log`), console
input such as `stop` is not forwarded to the server; stop it with Ctrl-C instead.

## Core APIs

Stable public surface of the persistent data core. Later workers should depend on exactly these signatures.

### Attachments — `dev.projecteclipse.eclipse.registry.EclipseAttachments`

Player data attachments (all persisted, all `copyOnDeath()`):

```java
public static final DeferredRegister<AttachmentType<?>> ATTACHMENTS;
public static final Supplier<AttachmentType<Integer>> LIVES;               // "eclipse:lives", default 5, Codec.INT
public static final Supplier<AttachmentType<Long>>    FIRST_OVERWORLD_JOIN; // "eclipse:first_overworld_join", default 0L (= never), Codec.LONG
public static final Supplier<AttachmentType<Boolean>> BANNED;              // "eclipse:banned", default false, Codec.BOOL
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

public Set<UUID> getBanned();                 public boolean isBanned(UUID playerId);
public void addBanned(UUID playerId);         public void removeBanned(UUID playerId);

public Map<String, Long> getMilestoneProgress();
public long getMilestoneProgress(String key);                 // 0 if absent
public void setMilestoneProgress(String key, long value);
public long addMilestoneProgress(String key, long delta);     // returns new value

public Set<UUID> getForceVoiceMuted();        public boolean isForceVoiceMuted(UUID playerId); // for the voice worker
public void addForceVoiceMuted(UUID playerId); public void removeForceVoiceMuted(UUID playerId);
```

### Lives — `dev.projecteclipse.eclipse.core.state.LivesApi`

Server-side only. Values are clamped to `>= 0`; `set`/`add` sync the new value to the owning client via `S2CLivesPayload`.

```java
public static int get(ServerPlayer player);
public static int set(ServerPlayer player, int lives);   // returns the applied (clamped) value
public static int add(ServerPlayer player, int delta);   // delta may be negative; returns the new value
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

### Config — `dev.projecteclipse.eclipse.core.config.EclipseConfig`

Loads `config/eclipse/{general,days,milestones,modgate}.json`; missing files are created with defaults on first run
(triggered from `FMLCommonSetupEvent`). Getters lazy-load if needed. Parse/IO failures fall back to built-in defaults in memory.

```java
public record General(int graveGraceMinutes) {}   // general.json; default 30
public record DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize) {}
public record ItemCost(String item, int count) {}
public record Milestone(int level, List<ItemCost> cost, List<String> rewards) {}
public record ModGate(List<String> gatedNamespaces, Map<String, String> unlockKeys) {}

public static General general();
public static int graveGraceMinutes();       // non-owners may loot a grave after 1x; it scatters after 3x
public static List<DayPlan> days();          // 14 entries by default, ordered by day
public static DayPlan day(int day);          // out-of-range days clamp to first/last plan
public static List<Milestone> milestones();  // ordered by level
public static Milestone milestone(int level); // null if not configured
public static ModGate modGate();
public static synchronized void reload();
```

Default unlock keys per day: 1 `[]`, 2 `[main_inventory]`, 3 `[workbenches, create]` (border 1500),
4 `[armor, simulated]`, 5 `[aeronautics]` (border 2000), 6 `[nether]`, 7 `[enchanting]`,
8 `[ender_chests]` (border 2500), 9 `[brewing]`, 10 `[smithing]`, 11 `[]` (border 3000), 12 `[end]`, 13 `[]`, 14 `[]`.

### Networking — `dev.projecteclipse.eclipse.network`

Registrar version `"1"`, registered via `RegisterPayloadHandlersEvent` (mod bus). Both payloads are `playToClient`
and are sent automatically on `PlayerLoggedInEvent`. Client handlers write to
`dev.projecteclipse.eclipse.client.ClientStateCache` (`public static volatile int lives / day / altarLevel`).

```java
public record S2CLivesPayload(int lives) implements CustomPacketPayload;        // id "eclipse:lives"
public record S2CDayStatePayload(int day, int altarLevel) implements CustomPacketPayload; // id "eclipse:day_state"
public record S2CCutscenePayload(Phase phase) implements CustomPacketPayload;   // id "eclipse:cutscene"
// S2CCutscenePayload.Phase: enum { TILT, SUBMERGE, WAVES, EMERGE }; client handler writes
// ClientStateCache.cutscenePhase (volatile, null until the start event runs).
// all expose: public static final CustomPacketPayload.Type<...> TYPE;
//             public static final StreamCodec<ByteBuf, ...> STREAM_CODEC;

public final class EclipsePayloads {
    public static void register(IEventBus modEventBus); // wires mod-bus payload registration + game-bus login sync
}
```

### Death economy — `dev.projecteclipse.eclipse.lives`

`LifecycleEvents` (`@EventBusSubscriber`, game bus) drives deaths: snapshot `"death"` first, killer gets +1 / victim
-1 life (PvE: victim -1 only), a global thunder cue plays to every online player at their own position
(no chat — `showDeathMessages` is forced to `false` on `ServerStartedEvent`), player drops are diverted into a
`eclipse:grave` block, and at 0 lives the victim is banned. `PlayerRespawnEvent` re-applies the limbo ghost state
for banned players (a corpse cannot be teleported at death time).

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
    public static void begin(MinecraftServer server); // /start_event server flow; command wiring is the admin worker's job
}
```

Timeline (server tick counter): t=0 TILT payload + oar keel-over + `eclipse:event.submerge` to all;
t=100 SUBMERGE + WAVES; t=140 players in Limbo rise out of carved pockets at overworld spawn;
t=150 pockets refill; t=160 EMERGE, `startEventDone=true`, `first_overworld_join` stamped if unset.

Sounds (`EclipseSounds`): `AMBIENT_LIMBO_LOOP` (`eclipse:ambient.limbo_loop`, also the limbo biome's
`ambient_sound`) and `EVENT_SUBMERGE` (`eclipse:event.submerge`); both currently ship tiny silent
placeholder OGGs under `assets/eclipse/sounds/`.

## Layout

- `dev.projecteclipse.eclipse.EclipseMod` — mod entry point (`@Mod("eclipse")`); wires all deferred registers.
- `dev.projecteclipse.eclipse.registry` — `EclipseItems`, `EclipseBlocks`, `EclipseBlockEntities`, `EclipseSounds`, `EclipseParticles`, `EclipseAttachments` (NeoForge attachment types), `EclipseMenus`. Each exposes a `DeferredRegister` and a static `register(IEventBus)`.
- `dev.projecteclipse.eclipse.client.EclipseClient` — client-only `@EventBusSubscriber(Dist.CLIENT)` shell; `client.ClientStateCache` — server-synced state cache (safe on both dists).
- `dev.projecteclipse.eclipse.core.state` / `core.snapshot` / `core.config` / `network` — persistent data core, see "Core APIs".
- `dev.projecteclipse.eclipse.lives` — death economy (`LifecycleEvents`, `BanService`, `InheritanceService`, `GraveBlock`, `GraveBlockEntity`).
- `dev.projecteclipse.eclipse.limbo` — `LimboDimension` (dimension key constant), `GhostShipBuilder`, `OarAnimator`, `StartEventCutscene` (see "Limbo & start event").
- Placeholder packages for later work: `ritual`, `progression`, `anonymity`, `voice`, `artifact`, `admin`.
- `src/main/templates/META-INF/neoforge.mods.toml` — mod metadata template; `${...}` placeholders are expanded from `gradle.properties` by the `generateModMetadata` task.
- `src/main/resources/META-INF/accesstransformer.cfg` — opens the `Display` entity transformation setters (`setTransformation`, interpolation duration/delay, `BlockDisplay.setBlockState`) for `OarAnimator`; `validateAccessTransformers = true` is enabled in `build.gradle`.
