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

### Voice mute — `dev.projecteclipse.eclipse.voice.VoiceMuteApi`

Server-side entry points for the ten-minute first-Overworld-entry mute and the persistent
administrative force-mute:

```java
public static boolean isEntryMuted(ServerPlayer player);
public static void setForceMuted(MinecraftServer server, UUID playerId, boolean muted);
public static boolean isMuted(MinecraftServer server, ServerPlayer player);
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

Loads `config/eclipse/{general,days,milestones,modgate,anticheat}.json`; missing files are created with defaults on first run
(triggered from `FMLCommonSetupEvent`). Getters lazy-load if needed. Parse/IO failures fall back to built-in defaults in memory.

```java
public record General(int graveGraceMinutes, boolean dayAutoAdvance, String dayAutoAdvanceTime) {}
// general.json; defaults: 30, false, "08:00"
public record DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize) {}
public record ItemCost(String item, int count) {}
public record Milestone(int level, List<ItemCost> cost, List<String> rewards) {}
public record ModGate(List<String> gatedNamespaces, Map<String, String> unlockKeys) {}
public record AntiCheat(List<String> blockedModIdSubstrings) {}

public static General general();
public static int graveGraceMinutes();       // non-owners may loot a grave after 1x; it scatters after 3x
public static boolean dayAutoAdvance();      // default false: days advance only via DayScheduler.setDay
public static LocalTime dayAutoAdvanceTime(); // parsed "HH:mm" (server-local); falls back to 08:00
public static List<DayPlan> days();          // 14 entries by default, ordered by day
public static DayPlan day(int day);          // out-of-range days clamp to first/last plan
public static List<Milestone> milestones();  // ordered by level
public static Milestone milestone(int level); // null if not configured
public static ModGate modGate();
public static AntiCheat antiCheat();         // anticheat.json blocklist, see "Anti-cheat"
public static synchronized boolean setNamespaceGated(String namespace, boolean gated); // mutates + persists modgate.json
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
    public static boolean begin(MinecraftServer server); // /eclipse start_event server flow; false if already running
}
```

Timeline (server tick counter): t=0 TILT payload + oar keel-over + `eclipse:event.submerge` to all;
t=100 SUBMERGE + WAVES; t=140 players in Limbo rise out of carved pockets at overworld spawn;
t=150 pockets refill; t=160 EMERGE, `startEventDone=true`, `first_overworld_join` stamped if unset.

Sounds (`EclipseSounds`): `AMBIENT_LIMBO_LOOP` (`eclipse:ambient.limbo_loop`, also the limbo biome's
`ambient_sound`) and `EVENT_SUBMERGE` (`eclipse:event.submerge`); both currently ship tiny silent
placeholder OGGs under `assets/eclipse/sounds/`.

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
| `/eclipse voicemute <player> on\|off` | `VoiceMuteApi.setForceMuted` (persistent administrative mute). |
| `/eclipse tp_limbo [player]` | Teleports you (or the target) to the Limbo ghost-ship platform. |
| `/eclipse reload` | `EclipseConfig.reload()` of all five JSON configs. |
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
- `dev.projecteclipse.eclipse.registry` — `EclipseItems`, `EclipseBlocks`, `EclipseBlockEntities`, `EclipseSounds`, `EclipseParticles`, `EclipseAttachments` (NeoForge attachment types), `EclipseMenus`. Each exposes a `DeferredRegister` and a static `register(IEventBus)`.
- `dev.projecteclipse.eclipse.client.EclipseClient` — client-only `@EventBusSubscriber(Dist.CLIENT)` shell; `client.ClientStateCache` — server-synced state cache (safe on both dists).
- `dev.projecteclipse.eclipse.core.state` / `core.snapshot` / `core.config` / `network` — persistent data core, see "Core APIs".
- `dev.projecteclipse.eclipse.lives` — death economy (`LifecycleEvents`, `BanService`, `InheritanceService`, `GraveBlock`, `GraveBlockEntity`).
- `dev.projecteclipse.eclipse.limbo` — `LimboDimension` (dimension key constant), `GhostShipBuilder`, `OarAnimator`, `StartEventCutscene` (see "Limbo & start event").
- `dev.projecteclipse.eclipse.progression` — `DayScheduler`, `UnlockState`, `BorderController`, `PhaseInventoryLock`, `ModGate` (see "Progression & Mod Gating").
- `dev.projecteclipse.eclipse.ritual` — ritual altar (`AltarBlock`, `AltarBlockEntity`, `BeamEmitter`) + revive ritual (`ReviveRitual`, `ReviveSigilItem`).
- `dev.projecteclipse.eclipse.artifact` — the arm artifact (`ArmArtifactItem`, hotbar slot 8, J/right-click menu; `ArtifactSlotLock` keeps it in place).
- `dev.projecteclipse.eclipse.admin` — `EclipseCommands` (see "Admin commands") + `AntiCheatCheck` (see "Anti-cheat").
- `src/main/templates/META-INF/neoforge.mods.toml` — mod metadata template; `${...}` placeholders are expanded from `gradle.properties` by the `generateModMetadata` task.
- `src/main/resources/META-INF/accesstransformer.cfg` — opens the `Display` entity transformation setters (`setTransformation`, interpolation duration/delay, `BlockDisplay.setBlockState`) for `OarAnimator`; `validateAccessTransformers = true` is enabled in `build.gradle`.

## Known limitations

- **Iris + shaderpacks override the custom sky.** The purple-tinted overworld sky (eclipse sun)
  is rendered by a vanilla-pipeline sky hook; when an Iris shaderpack is active it replaces the
  sky rendering, so only the fog/sky *tint* fallback survives. Running Iris with **no shaderpack
  enabled** keeps the full effect (this is the smoke-tested configuration).
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
