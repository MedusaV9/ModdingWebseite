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

Loads `config/eclipse/{days,milestones,modgate}.json`; missing files are created with defaults on first run
(triggered from `FMLCommonSetupEvent`). Getters lazy-load if needed. Parse/IO failures fall back to built-in defaults in memory.

```java
public record DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize) {}
public record ItemCost(String item, int count) {}
public record Milestone(int level, List<ItemCost> cost, List<String> rewards) {}
public record ModGate(List<String> gatedNamespaces, Map<String, String> unlockKeys) {}

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
// both expose: public static final CustomPacketPayload.Type<...> TYPE;
//              public static final StreamCodec<ByteBuf, ...> STREAM_CODEC;

public final class EclipsePayloads {
    public static void register(IEventBus modEventBus); // wires mod-bus payload registration + game-bus login sync
}
```

## Layout

- `dev.projecteclipse.eclipse.EclipseMod` — mod entry point (`@Mod("eclipse")`); wires all deferred registers.
- `dev.projecteclipse.eclipse.registry` — `EclipseItems`, `EclipseBlocks`, `EclipseBlockEntities`, `EclipseSounds`, `EclipseParticles`, `EclipseAttachments` (NeoForge attachment types), `EclipseMenus`. Each exposes a `DeferredRegister` and a static `register(IEventBus)`.
- `dev.projecteclipse.eclipse.client.EclipseClient` — client-only `@EventBusSubscriber(Dist.CLIENT)` shell; `client.ClientStateCache` — server-synced state cache (safe on both dists).
- `dev.projecteclipse.eclipse.core.state` / `core.snapshot` / `core.config` / `network` — persistent data core, see "Core APIs".
- Placeholder packages for later work: `lives`, `ritual`, `limbo`, `progression`, `anonymity`, `voice`, `artifact`, `admin`.
- `src/main/templates/META-INF/neoforge.mods.toml` — mod metadata template; `${...}` placeholders are expanded from `gradle.properties` by the `generateModMetadata` task.
- `src/main/resources/META-INF/accesstransformer.cfg` — empty (comment-only) AT file; `validateAccessTransformers = true` is enabled in `build.gradle`.
