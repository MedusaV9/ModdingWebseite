package dev.projecteclipse.eclipse.entity;

import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server-tick spawner for the v2 custom mobs, keyed off the eclipse day
 * ({@link DayScheduler#getDay}), overworld night time and the night-event state — NOT biome
 * modifiers ({@code docs/ideas/04_content.md} "Shared infra"). Runs every
 * {@value #CADENCE_TICKS} ticks and spawns at most one gazer, one stalker pack, one
 * The Other and the missing sunmotes per pass, so it can never spawn-loop.
 *
 * <p><b>Night events</b>: on nightfall of day 4+ a Pale Night is rolled
 * ({@value #PALE_NIGHT_CHANCE} — the FIRST one is guaranteed, as is day
 * {@value #PALE_NIGHT_FIXED_DAY}); days {@value #UMBRAL_NIGHT_DAY_1} and
 * {@value #UMBRAL_NIGHT_DAY_2} are fixed Umbral Nights (the §6 arc). The event is stored in
 * {@link EclipseWorldState#getActiveNightEvent()} (persists restarts), announced via the W8
 * typewriter/sweep overlay (style {@code unlock}) and cleared at dawn.
 * {@code /eclipse event set <pale|umbral|none>} overrides it live.</p>
 *
 * <p><b>Spawn rules</b> (all overworld, surface, loaded chunks only):</p>
 * <ul>
 *   <li><b>Gazer</b> — nights from day 3: population is topped up to 1 per
 *       ~{@value #GAZER_PLAYERS_PER_MOB} online players (min 1), placed 20–40 blocks from a
 *       random player. (The guaranteed altar-watch gazer during sacrifices is spawned by
 *       {@link GazerEntity#watchSacrifice} from the altar deposit path.)</li>
 *   <li><b>Umbral Stalker</b> — nights from day 5: one pack of 3–4 when below the cap
 *       ({@value #STALKER_CAP}, doubled on Umbral Nights), 24–56 blocks out.</li>
 *   <li><b>The Other</b> — Pale Nights only: 2–3 per event (rolled per event), each
 *       ≥{@value #THE_OTHER_MIN_PLAYER_DISTANCE} blocks from every player.</li>
 *   <li><b>Sunmote</b> — daylight upkeep: one mote per altar level orbits the sanctum altar
 *       (radius {@code 6 + altarLevel}); killed motes respawn next dawn.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseSpawner {
    /** Spawner pass cadence (5 s) — long enough to stay cheap, short enough to feel alive. */
    public static final int CADENCE_TICKS = 100;

    // Night-event schedule (docs/ideas/04_content.md §6 arc).
    public static final int PALE_NIGHT_MIN_DAY = 4;
    public static final int PALE_NIGHT_FIXED_DAY = 12;
    public static final int UMBRAL_NIGHT_DAY_1 = 6;
    public static final int UMBRAL_NIGHT_DAY_2 = 10;
    public static final float PALE_NIGHT_CHANCE = 0.25F;

    // Population rules.
    public static final int GAZER_MIN_DAY = 3;
    public static final int GAZER_PLAYERS_PER_MOB = 4;
    public static final int STALKER_MIN_DAY = 5;
    public static final int STALKER_CAP = 4;
    public static final double THE_OTHER_MIN_PLAYER_DISTANCE = 24.0D;

    private static final int PLACEMENT_ATTEMPTS = 16;

    /** Nightfall/dawn edge detector; {@code null} until the first pass after boot. */
    @Nullable
    private static Boolean wasNight;
    /** The Other budget of the current event instance (2–3, rolled on event start). */
    private static int theOtherBudget;
    private static int theOtherSpawned;
    /** Event instance marker ({@code event + "#" + dayStamp}) the budget belongs to. */
    private static String theOtherEventKey = "";

    private EclipseSpawner() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % CADENCE_TICKS != 0) {
            return;
        }
        ServerLevel overworld = server.overworld();
        boolean night = overworld.isNight();
        if (wasNight == null) {
            // First pass after boot: baseline only, unless we restarted into daylight with a
            // stale (crash-orphaned) night event still active.
            wasNight = night;
            if (!night) {
                clearNightEvent(server);
            }
        } else if (night && !wasNight) {
            scheduleNightEvent(server);
            wasNight = true;
        } else if (!night && wasNight) {
            clearNightEvent(server);
            wasNight = false;
        }

        EclipseWorldState state = EclipseWorldState.get(server);
        int day = DayScheduler.getDay(server);
        if (night) {
            spawnGazers(overworld, day);
            spawnStalkerPack(overworld, state, day);
            spawnTheOther(overworld, state);
        } else {
            maintainSunmotes(overworld, state);
        }
    }

    // --- night events ---

    /** Rolls/fixes the night event on nightfall and announces it (style {@code unlock}). */
    private static void scheduleNightEvent(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        int day = DayScheduler.getDay(server);
        String event = EclipseWorldState.NIGHT_EVENT_NONE;
        if (day == UMBRAL_NIGHT_DAY_1 || day == UMBRAL_NIGHT_DAY_2) {
            event = EclipseWorldState.NIGHT_EVENT_UMBRAL;
        } else if (day >= PALE_NIGHT_MIN_DAY) {
            boolean guaranteed = !state.isFirstPaleNightDone() || day == PALE_NIGHT_FIXED_DAY;
            if (guaranteed || server.overworld().getRandom().nextFloat() < PALE_NIGHT_CHANCE) {
                event = EclipseWorldState.NIGHT_EVENT_PALE;
            }
        }
        if (EclipseWorldState.NIGHT_EVENT_NONE.equals(event)) {
            return;
        }
        state.setActiveNightEvent(event, day);
        if (EclipseWorldState.NIGHT_EVENT_PALE.equals(event)) {
            state.setFirstPaleNightDone(true);
        }
        announceNightEvent(server, event);
        EclipseMod.LOGGER.info("Night event '{}' begins (day {})", event, day);
    }

    private static void clearNightEvent(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        if (!EclipseWorldState.NIGHT_EVENT_NONE.equals(state.getActiveNightEvent())) {
            EclipseMod.LOGGER.info("Night event '{}' ends at dawn", state.getActiveNightEvent());
            state.setActiveNightEvent(EclipseWorldState.NIGHT_EVENT_NONE, state.getNightEventDay());
        }
    }

    /** W8 typewriter/sweep announcement; also used by {@code /eclipse event set}. */
    public static void announceNightEvent(MinecraftServer server, String event) {
        AnnouncementService.announce(server,
                "announce.eclipse.night." + event + ".title",
                "announce.eclipse.night." + event + ".sub",
                S2CAnnouncePayload.STYLE_UNLOCK);
    }

    // --- gazer ---

    private static void spawnGazers(ServerLevel overworld, int day) {
        if (day < GAZER_MIN_DAY) {
            return;
        }
        int players = overworld.players().size();
        if (players == 0) {
            return;
        }
        int target = Math.max(1, players / GAZER_PLAYERS_PER_MOB);
        if (count(overworld, EclipseEntities.GAZER.get()) >= target) {
            return;
        }
        ServerPlayer around = randomPlayer(overworld);
        BlockPos pos = findSurfaceSpawn(overworld, around, 20.0D, 40.0D, 12.0D);
        if (pos != null) {
            spawn(overworld, EclipseEntities.GAZER.get(), pos, false);
        }
    }

    // --- umbral stalker ---

    private static void spawnStalkerPack(ServerLevel overworld, EclipseWorldState state, int day) {
        if (day < STALKER_MIN_DAY || overworld.players().isEmpty()) {
            return;
        }
        boolean umbral = EclipseWorldState.NIGHT_EVENT_UMBRAL.equals(state.getActiveNightEvent());
        int cap = umbral ? STALKER_CAP * 2 : STALKER_CAP;
        int existing = count(overworld, EclipseEntities.UMBRAL_STALKER.get());
        if (existing >= cap) {
            return;
        }
        ServerPlayer around = randomPlayer(overworld);
        BlockPos packCenter = findSurfaceSpawn(overworld, around, 24.0D, 56.0D, 16.0D);
        if (packCenter == null) {
            return;
        }
        RandomSource random = overworld.getRandom();
        int packSize = Math.min(3 + random.nextInt(2), cap - existing);
        int spawned = 0;
        for (int i = 0; i < packSize; i++) {
            // Scatter members around the pack center on the surface.
            int x = packCenter.getX() + random.nextInt(7) - 3;
            int z = packCenter.getZ() + random.nextInt(7) - 3;
            BlockPos memberPos = surfaceAt(overworld, x, z);
            if (memberPos != null && spawn(overworld, EclipseEntities.UMBRAL_STALKER.get(), memberPos, false)) {
                spawned++;
            }
        }
        if (spawned > 0) {
            EclipseMod.LOGGER.info("Umbral stalker pack of {} spawned near {} (cap {}, umbral: {})",
                    spawned, packCenter, cap, umbral);
        }
    }

    // --- the other ---

    private static void spawnTheOther(ServerLevel overworld, EclipseWorldState state) {
        if (!EclipseWorldState.NIGHT_EVENT_PALE.equals(state.getActiveNightEvent())
                || overworld.players().isEmpty()) {
            return;
        }
        // Per-event budget: 2–3, rolled once per event instance (event + day stamp).
        String eventKey = state.getActiveNightEvent() + "#" + state.getNightEventDay()
                + "#" + overworld.getGameTime() / 24000L;
        if (!eventKey.equals(theOtherEventKey)) {
            theOtherEventKey = eventKey;
            theOtherBudget = 2 + overworld.getRandom().nextInt(2);
            theOtherSpawned = 0;
        }
        if (theOtherSpawned >= theOtherBudget
                || count(overworld, EclipseEntities.THE_OTHER.get()) >= theOtherBudget) {
            return;
        }
        ServerPlayer around = randomPlayer(overworld);
        BlockPos pos = findSurfaceSpawn(overworld, around, THE_OTHER_MIN_PLAYER_DISTANCE, 48.0D,
                THE_OTHER_MIN_PLAYER_DISTANCE);
        if (pos != null && spawn(overworld, EclipseEntities.THE_OTHER.get(), pos, false)) {
            theOtherSpawned++;
            EclipseMod.LOGGER.info("The Other {}/{} spawned at {} (Pale Night)",
                    theOtherSpawned, theOtherBudget, pos);
        }
    }

    // --- sunmote ---

    /** Daylight upkeep: one mote per altar level orbits the sanctum altar; dead ones respawn at dawn. */
    private static void maintainSunmotes(ServerLevel overworld, EclipseWorldState state) {
        BlockPos altar = state.getSanctumAltarPos();
        int altarLevel = state.getAltarLevel();
        if (altar == null || altarLevel <= 0 || !overworld.isLoaded(altar)) {
            return;
        }
        int existing = count(overworld, EclipseEntities.SUNMOTE.get());
        for (int i = existing; i < altarLevel; i++) {
            SunmoteEntity mote = EclipseEntities.SUNMOTE.get().create(overworld);
            if (mote == null) {
                return;
            }
            double angle = (Math.PI * 2.0D / altarLevel) * i;
            double radius = 6.0D + altarLevel;
            mote.setOrbit(altar, angle);
            mote.moveTo(altar.getX() + 0.5D + Math.cos(angle) * radius, altar.getY() + 1.5D,
                    altar.getZ() + 0.5D + Math.sin(angle) * radius, 0.0F, 0.0F);
            overworld.addFreshEntity(mote);
            EclipseMod.LOGGER.info("Sunmote {}/{} spawned around the altar at {}", i + 1, altarLevel, altar);
        }
    }

    // --- placement helpers ---

    /**
     * A surface point 'minDist..maxDist' blocks from {@code around} that is also at least
     * {@code minAnyPlayerDist} from EVERY player, or {@code null} when no attempt landed.
     */
    @Nullable
    private static BlockPos findSurfaceSpawn(ServerLevel level, @Nullable ServerPlayer around,
            double minDist, double maxDist, double minAnyPlayerDist) {
        if (around == null) {
            return null;
        }
        RandomSource random = level.getRandom();
        for (int attempt = 0; attempt < PLACEMENT_ATTEMPTS; attempt++) {
            double angle = random.nextDouble() * Math.PI * 2.0D;
            double distance = minDist + random.nextDouble() * (maxDist - minDist);
            int x = Mth.floor(around.getX() + Math.cos(angle) * distance);
            int z = Mth.floor(around.getZ() + Math.sin(angle) * distance);
            BlockPos pos = surfaceAt(level, x, z);
            if (pos == null) {
                continue;
            }
            boolean tooClose = false;
            for (ServerPlayer player : level.players()) {
                if (player.distanceToSqr(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D)
                        < minAnyPlayerDist * minAnyPlayerDist) {
                    tooClose = true;
                    break;
                }
            }
            if (!tooClose) {
                return pos;
            }
        }
        return null;
    }

    /** The stand-on-surface position of column (x, z), or {@code null} (unloaded/void/liquid top). */
    @Nullable
    private static BlockPos surfaceAt(ServerLevel level, int x, int z) {
        if (!level.isLoaded(new BlockPos(x, level.getSeaLevel(), z))) {
            return null;
        }
        int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (y <= level.getMinBuildHeight()) {
            return null; // Void column (beyond the disc rim).
        }
        BlockPos pos = new BlockPos(x, y, z);
        if (!level.getBlockState(pos.below()).isSolid() || !level.getFluidState(pos).isEmpty()) {
            return null;
        }
        return pos;
    }

    private static boolean spawn(ServerLevel level, EntityType<? extends Mob> type, BlockPos pos,
            boolean persistent) {
        Mob mob = type.create(level);
        if (mob == null) {
            return false;
        }
        mob.moveTo(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D,
                level.getRandom().nextFloat() * 360.0F, 0.0F);
        if (persistent) {
            mob.setPersistenceRequired();
        }
        return level.addFreshEntity(mob);
    }

    @Nullable
    private static ServerPlayer randomPlayer(ServerLevel level) {
        List<ServerPlayer> players = level.players().stream()
                .filter(player -> !player.isSpectator()).toList();
        return players.isEmpty() ? null
                : players.get(level.getRandom().nextInt(players.size()));
    }

    private static int count(ServerLevel level, EntityType<?> type) {
        return level.getEntities(type, Entity::isAlive).size();
    }
}
