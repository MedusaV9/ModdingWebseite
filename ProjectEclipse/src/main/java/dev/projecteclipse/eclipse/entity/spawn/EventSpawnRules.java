package dev.projecteclipse.eclipse.entity.spawn;

import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.ambient.DriftLanternEntity;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.worldgen.fog.FogStormSites;
import dev.projecteclipse.eclipse.worldgen.stage.NewRingRegistry;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.Difficulty;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * P6-W6/W56 (plans_v3 §2.8): the event-mob spawner pass — every
 * {@value #CADENCE_TICKS} ticks (offset half a cadence from the legacy
 * {@code EclipseSpawner} so the two passes never stack on the same tick), it tops up each
 * new mob family inside its {@link SpawnGates} area with conservative caps:
 *
 * <ul>
 *   <li><b>Fog storms</b> ({@code SpawnGates.FOG_STORM}, night, day ≥
 *       {@value #FOG_MIN_DAY}): fog_revenant top-up (global cap 2 + online/4, ≤
 *       {@value #REVENANT_SITE_CAP} per site), storm_hound packs of 2–3 (≤
 *       {@value #HOUND_SITE_CAP} per site, landing packs announce themselves with the
 *       private low-howl cue), and from day {@value #COLOSSUS_MIN_DAY} one fog_colossus
 *       per storm AND one global, near the storm center.</li>
 *   <li><b>Fresh glitch rings</b> ({@code SpawnGates.NEW_RING}, day ≥
 *       {@value #GLITCH_MIN_DAY}): the glitched trio, kind-weighted HUSK 45 / HOUND 35 /
 *       TICK 20 (ticks skitter in threes), positions from
 *       {@link NewRingRegistry#sampleFreshPositions}, ≥ {@value #GLITCH_MIN_PLAYER_DIST}
 *       blocks from every player. Night-biased: the combined cap (4 + online/3) halves
 *       during the day. <b>Coexistence:</b> P4's {@code glitch/GlitchSpawnService} also
 *       spawns these ids in fresh rings (chance-driven bursts) — both spawners count the
 *       SAME census, so the live total never exceeds the larger of the two caps; this
 *       pass spawns at most one group per cadence to keep ambient density low
 *       (ownership split documented in {@code docs/plans_v3/wiring/P6-W56_wiring.md}).</li>
 *   <li><b>Pale garden</b> ({@code SpawnGates.PALE_GARDEN}, night, day ≥
 *       {@value #SENTINEL_MIN_DAY}): pale_sentinel, global cap
 *       {@value #SENTINEL_CAP} — the gate is the baked biome, so it simply never fires
 *       until players walk the outer plains ring.</li>
 *   <li><b>Limbo buoy lane</b> (players present in limbo, peaceful-safe — CREATURE):
 *       drift_lantern population maintained in the 6–10 band (topped up toward
 *       {@value #LANTERN_TARGET}, {@value #LANTERN_TOPUP_PER_PASS}/pass, via
 *       {@link DriftLanternEntity#spawnLane}; lanterns never despawn on their own, and
 *       admin-summoned extras above the band are left alone).</li>
 * </ul>
 *
 * <p>Every hostile spawn resolves its entity type from the frozen string id at spawn
 * time ({@link BuiltInRegistries#ENTITY_TYPE}) — an unmerged mob family is a
 * logged-once debug no-op. Mobs spawn NON-persistent with {@code MobSpawnType.NATURAL}
 * (vanilla despawn rules apply; dungeon spawners and storms re-supply). Peaceful
 * difficulty early-outs the hostile passes (the {@code EclipseSpawner} precedent — never
 * spawn-churn against instant despawn).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EventSpawnRules {
    /** Pass cadence (5 s), phase-offset from {@code EclipseSpawner}'s pass by 50 t. */
    public static final int CADENCE_TICKS = 100;

    // --- frozen entity ids (plan §6 / task freeze; registry-lookup only) ---
    public static final String ID_FOG_REVENANT = "eclipse:fog_revenant";
    public static final String ID_STORM_HOUND = "eclipse:storm_hound";
    public static final String ID_FOG_COLOSSUS = "eclipse:fog_colossus";
    public static final String ID_GLITCHED_HUSK = "eclipse:glitched_husk";
    public static final String ID_GLITCHED_HOUND = "eclipse:glitched_hound";
    public static final String ID_GLITCHED_TICK = "eclipse:glitched_tick";
    public static final String ID_PALE_SENTINEL = "eclipse:pale_sentinel";
    public static final String ID_DRIFT_LANTERN = "eclipse:drift_lantern";

    // --- day gates (plan §2.8 table; sentinel matches its bestiary intro day) ---
    public static final int FOG_MIN_DAY = 6;
    public static final int COLOSSUS_MIN_DAY = 9;
    public static final int GLITCH_MIN_DAY = 8;
    public static final int SENTINEL_MIN_DAY = 10;

    // --- caps / densities (deliberately conservative) ---
    /** fog_revenant global cap = {@code REVENANT_CAP_BASE + online / REVENANT_CAP_PER}. */
    public static final int REVENANT_CAP_BASE = 2;
    public static final int REVENANT_CAP_PER = 4;
    public static final int REVENANT_SITE_CAP = 2;
    public static final int HOUND_SITE_CAP = 6;
    /** glitched combined night cap = {@code GLITCH_CAP_BASE + online / 3} (day: half). */
    public static final int GLITCH_CAP_BASE = 4;
    public static final int SENTINEL_CAP = 2;
    public static final int LANTERN_TARGET = 8;
    public static final int LANTERN_TOPUP_PER_PASS = 2;

    // --- placement distances ---
    private static final double STORM_NEAR_MIN = 24.0D;
    private static final double STORM_NEAR_MAX = 48.0D;
    /** Sites farther than radius + this from every player are skipped entirely. */
    private static final double STORM_ACTIVITY_MARGIN = 64.0D;
    private static final double GLITCH_MIN_PLAYER_DIST = 24.0D;
    private static final double GLITCH_MAX_PLAYER_DIST = 64.0D;
    private static final int PLACEMENT_ATTEMPTS = 12;

    // Pack-landing howl (EclipseSpawner.howlAround technique, reimplemented — plan §3 W6).
    private static final double HOWL_RANGE = 64.0D;
    private static final float HOWL_VOLUME = 1.5F;
    private static final float HOWL_PITCH = 0.6F;

    /** Absent entity ids already debug-logged (one line per id per session). */
    private static final Set<String> LOGGED_ABSENT = Collections.synchronizedSet(new HashSet<>());

    private EventSpawnRules() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if ((server.getTickCount() + CADENCE_TICKS / 2) % CADENCE_TICKS != 0) {
            return;
        }
        ServerLevel overworld = server.overworld();
        int day = DayScheduler.getDay(server);
        boolean night = overworld.isNight();
        boolean hostilesAllowed = overworld.getDifficulty() != Difficulty.PEACEFUL
                && overworld.players().stream().anyMatch(player -> !player.isSpectator());
        if (hostilesAllowed) {
            fogStormPass(overworld, day, night);
            newRingPass(overworld, day, night);
            paleGardenPass(overworld, day, night);
        }
        driftLanternPass(server);
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        LOGGED_ABSENT.clear();
    }

    // --- fog storm family ---

    private static void fogStormPass(ServerLevel level, int day, boolean night) {
        if (day < FOG_MIN_DAY || !night) {
            return;
        }
        int online = onlineNonSpectator(level);
        int revenantCap = REVENANT_CAP_BASE + online / REVENANT_CAP_PER;
        int revenantsAlive = count(level, ID_FOG_REVENANT);
        int colossiAlive = count(level, ID_FOG_COLOSSUS);
        for (FogStormSites.Site site : FogStormSites.sites()) {
            if (!site.active() || !playerNearSite(level, site)) {
                continue;
            }
            AABB area = siteArea(level, site);
            // Revenant: one top-up per pass per site, below both site and global caps.
            if (revenantsAlive < revenantCap
                    && countIn(level, ID_FOG_REVENANT, area) < REVENANT_SITE_CAP) {
                BlockPos pos = findStormSpawn(level, site);
                if (pos != null && trySpawn(level, ID_FOG_REVENANT, pos)) {
                    revenantsAlive++;
                }
            }
            // Storm hounds: packs of 2–3, landing with the distant-howl fairness cue.
            int hounds = countIn(level, ID_STORM_HOUND, area);
            if (hounds < HOUND_SITE_CAP) {
                spawnHoundPack(level, site, HOUND_SITE_CAP - hounds);
            }
            // Colossus: the storm's single elite (and only one worldwide).
            if (day >= COLOSSUS_MIN_DAY && colossiAlive < 1
                    && countIn(level, ID_FOG_COLOSSUS, area) < 1) {
                BlockPos pos = findColossusSpawn(level, site);
                if (pos != null && trySpawn(level, ID_FOG_COLOSSUS, pos)) {
                    colossiAlive++;
                    EclipseMod.LOGGER.info("EventSpawnRules: fog_colossus rises at {} (storm {})",
                            pos, site.id());
                }
            }
        }
    }

    private static void spawnHoundPack(ServerLevel level, FogStormSites.Site site, int room) {
        BlockPos packCenter = findStormSpawn(level, site);
        if (packCenter == null) {
            return;
        }
        RandomSource random = level.getRandom();
        int packSize = Math.min(2 + random.nextInt(2), room);
        int spawned = 0;
        for (int i = 0; i < packSize; i++) {
            BlockPos memberPos = surfaceAt(level,
                    packCenter.getX() + random.nextInt(9) - 4,
                    packCenter.getZ() + random.nextInt(9) - 4);
            if (memberPos != null && SpawnGates.FOG_STORM.test(level, memberPos)
                    && trySpawn(level, ID_STORM_HOUND, memberPos)) {
                spawned++;
            }
        }
        if (spawned > 0) {
            howlAround(level, packCenter);
            EclipseMod.LOGGER.info("EventSpawnRules: storm_hound pack of {} near {} (storm {})",
                    spawned, packCenter, site.id());
        }
    }

    /**
     * A gated surface point inside the storm disc whose NEAREST player sits
     * {@value #STORM_NEAR_MIN}–{@value #STORM_NEAR_MAX} blocks away (close enough to
     * matter, never an on-top ambush), or {@code null}.
     */
    @Nullable
    private static BlockPos findStormSpawn(ServerLevel level, FogStormSites.Site site) {
        RandomSource random = level.getRandom();
        for (int attempt = 0; attempt < PLACEMENT_ATTEMPTS; attempt++) {
            double angle = random.nextDouble() * Math.PI * 2.0D;
            double r = site.radius() * Math.sqrt(random.nextDouble()); // area-uniform
            int x = site.x() + Mth.floor(Math.cos(angle) * r);
            int z = site.z() + Mth.floor(Math.sin(angle) * r);
            BlockPos pos = surfaceAt(level, x, z);
            if (pos == null || !SpawnGates.FOG_STORM.test(level, pos)) {
                continue;
            }
            double nearest = nearestPlayerDistance(level, pos);
            if (nearest >= STORM_NEAR_MIN && nearest <= STORM_NEAR_MAX) {
                return pos;
            }
        }
        return null;
    }

    /** Colossus placement: storm center ±8, ≥ {@value #STORM_NEAR_MIN} from every player. */
    @Nullable
    private static BlockPos findColossusSpawn(ServerLevel level, FogStormSites.Site site) {
        RandomSource random = level.getRandom();
        for (int attempt = 0; attempt < PLACEMENT_ATTEMPTS; attempt++) {
            int x = site.x() + random.nextInt(17) - 8;
            int z = site.z() + random.nextInt(17) - 8;
            BlockPos pos = surfaceAt(level, x, z);
            if (pos != null && SpawnGates.FOG_STORM.test(level, pos)
                    && nearestPlayerDistance(level, pos) >= STORM_NEAR_MIN) {
                return pos;
            }
        }
        return null;
    }

    private static boolean playerNearSite(ServerLevel level, FogStormSites.Site site) {
        double range = site.radius() + STORM_ACTIVITY_MARGIN;
        double rangeSq = range * range;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator()) {
                continue;
            }
            double dx = player.getX() - site.x();
            double dz = player.getZ() - site.z();
            if (dx * dx + dz * dz <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    private static AABB siteArea(ServerLevel level, FogStormSites.Site site) {
        return new AABB(site.x() - site.radius(), level.getMinBuildHeight(),
                site.z() - site.radius(), site.x() + site.radius(),
                level.getMaxBuildHeight(), site.z() + site.radius());
    }

    // --- glitched trio (fresh rings) ---

    private static void newRingPass(ServerLevel level, int day, boolean night) {
        if (day < GLITCH_MIN_DAY) {
            return;
        }
        int online = onlineNonSpectator(level);
        int nightCap = GLITCH_CAP_BASE + online / 3;
        int cap = night ? nightCap : Math.max(1, nightCap / 2); // night-biased ×2
        int alive = count(level, ID_GLITCHED_HUSK) + count(level, ID_GLITCHED_HOUND)
                + count(level, ID_GLITCHED_TICK);
        if (alive >= cap) {
            return;
        }
        for (BlockPos pos : NewRingRegistry.sampleFreshPositions(level, 4)) {
            if (!SpawnGates.NEW_RING.test(level, pos)
                    || !playerDistanceOk(level, pos, GLITCH_MIN_PLAYER_DIST, GLITCH_MAX_PLAYER_DIST)) {
                continue;
            }
            String id = weightedGlitchId(level.getRandom());
            int spawned = 0;
            if (ID_GLITCHED_TICK.equals(id)) {
                // Ticks skitter in threes (§2.3), still bounded by the combined cap.
                RandomSource random = level.getRandom();
                for (int i = 0; i < 3 && alive + spawned < cap; i++) {
                    BlockPos tickPos = surfaceAt(level, pos.getX() + random.nextInt(5) - 2,
                            pos.getZ() + random.nextInt(5) - 2);
                    if (tickPos != null && trySpawn(level, ID_GLITCHED_TICK, tickPos)) {
                        spawned++;
                    }
                }
            } else if (trySpawn(level, id, pos)) {
                spawned = 1;
            }
            if (spawned > 0) {
                EclipseMod.LOGGER.info(
                        "EventSpawnRules: {} x{} in fresh ring at {} (combined glitched {}/{}, {})",
                        id, spawned, pos, alive + spawned, cap, night ? "night" : "day");
                break; // at most one group per pass — densities stay conservative
            }
        }
    }

    /** Kind weighting HUSK 45 / HOUND 35 / TICK 20 (plan §2.8). */
    private static String weightedGlitchId(RandomSource random) {
        int roll = random.nextInt(100);
        if (roll < 45) {
            return ID_GLITCHED_HUSK;
        }
        return roll < 80 ? ID_GLITCHED_HOUND : ID_GLITCHED_TICK;
    }

    // --- pale sentinel ---

    private static void paleGardenPass(ServerLevel level, int day, boolean night) {
        if (day < SENTINEL_MIN_DAY || !night || count(level, ID_PALE_SENTINEL) >= SENTINEL_CAP) {
            return;
        }
        ServerPlayer around = randomPlayer(level);
        BlockPos pos = findSurfaceSpawn(level, around, 24.0D, 48.0D, 24.0D);
        if (pos != null && SpawnGates.PALE_GARDEN.test(level, pos)
                && trySpawn(level, ID_PALE_SENTINEL, pos)) {
            EclipseMod.LOGGER.info("EventSpawnRules: pale_sentinel takes root at {}", pos);
        }
    }

    // --- drift lanterns (limbo ambience — CREATURE, peaceful-safe) ---

    private static void driftLanternPass(MinecraftServer server) {
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null
                || limbo.players().stream().noneMatch(player -> !player.isSpectator())) {
            return;
        }
        Optional<EntityType<?>> type = resolve(ID_DRIFT_LANTERN);
        if (type.isEmpty()) {
            return;
        }
        int alive = countType(limbo, type.get());
        if (alive >= LANTERN_TARGET) {
            return;
        }
        int spawned = 0;
        for (int i = 0; i < Math.min(LANTERN_TOPUP_PER_PASS, LANTERN_TARGET - alive); i++) {
            if (DriftLanternEntity.spawnLane(limbo) != null) {
                spawned++;
            }
        }
        if (spawned > 0) {
            EclipseMod.LOGGER.info("EventSpawnRules: {} drift lantern(s) added to the buoy lane ({}/{})",
                    spawned, alive + spawned, LANTERN_TARGET);
        }
    }

    // --- shared helpers (EclipseSpawner semantics, reimplemented per plan §3 W6) ---

    /**
     * The pack-landing cue: one distant low growl per player within
     * {@value #HOWL_RANGE} blocks, audio-placed a few blocks TOWARD the pack (the
     * private-sound-packet technique of {@code EclipseSpawner.howlAround}) so a fresh
     * pack is never a silent ambush.
     */
    private static void howlAround(ServerLevel level, BlockPos packCenter) {
        Vec3 center = Vec3.atCenterOf(packCenter);
        for (ServerPlayer player : level.players()) {
            double dist = player.position().distanceTo(center);
            if (dist > HOWL_RANGE) {
                continue;
            }
            Vec3 toward = dist < 1.0E-4D ? Vec3.ZERO
                    : center.subtract(player.position()).normalize().scale(Math.min(dist, 10.0D));
            Vec3 at = player.position().add(toward);
            player.connection.send(new ClientboundSoundPacket(
                    BuiltInRegistries.SOUND_EVENT.wrapAsHolder(SoundEvents.WOLF_GROWL),
                    SoundSource.HOSTILE, at.x, at.y, at.z, HOWL_VOLUME, HOWL_PITCH,
                    level.getRandom().nextLong()));
        }
    }

    /**
     * A surface point {@code minDist..maxDist} blocks from {@code around} that is also at
     * least {@code minAnyPlayerDist} from EVERY player, or {@code null}.
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
            if (pos != null && playerDistanceOk(level, pos, minAnyPlayerDist, Double.MAX_VALUE)) {
                return pos;
            }
        }
        return null;
    }

    /** The stand-on-surface position of column (x, z), or {@code null} (unloaded/void/liquid). */
    @Nullable
    private static BlockPos surfaceAt(ServerLevel level, int x, int z) {
        if (!level.isLoaded(new BlockPos(x, level.getSeaLevel(), z))) {
            return null;
        }
        int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (y <= level.getMinBuildHeight()) {
            return null; // void column (beyond the disc rim)
        }
        BlockPos pos = new BlockPos(x, y, z);
        if (!level.getBlockState(pos.below()).isSolid() || !level.getFluidState(pos).isEmpty()) {
            return null;
        }
        return pos;
    }

    /** ≥ {@code minEvery} from EVERY player and ≤ {@code maxNearest} from at least one. */
    private static boolean playerDistanceOk(ServerLevel level, BlockPos pos,
            double minEvery, double maxNearest) {
        double minSq = minEvery * minEvery;
        double maxSq = maxNearest >= Double.MAX_VALUE ? Double.MAX_VALUE : maxNearest * maxNearest;
        boolean nearSomeone = false;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator()) {
                continue;
            }
            double distSq = player.distanceToSqr(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D);
            if (distSq < minSq) {
                return false;
            }
            if (distSq <= maxSq) {
                nearSomeone = true;
            }
        }
        return nearSomeone;
    }

    private static double nearestPlayerDistance(ServerLevel level, BlockPos pos) {
        double nearestSq = Double.MAX_VALUE;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator()) {
                continue;
            }
            nearestSq = Math.min(nearestSq,
                    player.distanceToSqr(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D));
        }
        return nearestSq == Double.MAX_VALUE ? Double.MAX_VALUE : Math.sqrt(nearestSq);
    }

    @Nullable
    private static ServerPlayer randomPlayer(ServerLevel level) {
        List<ServerPlayer> players = level.players().stream()
                .filter(player -> !player.isSpectator()).toList();
        return players.isEmpty() ? null
                : players.get(level.getRandom().nextInt(players.size()));
    }

    private static int onlineNonSpectator(ServerLevel level) {
        return (int) level.players().stream().filter(player -> !player.isSpectator()).count();
    }

    /**
     * Soft registry lookup of a frozen id: absent (family not merged yet) → empty with
     * one debug line per id per session, never an error (plan §3 W6 / task hard rule).
     */
    private static Optional<EntityType<?>> resolve(String id) {
        ResourceLocation location = ResourceLocation.tryParse(id);
        Optional<EntityType<?>> type = location == null
                ? Optional.empty() : BuiltInRegistries.ENTITY_TYPE.getOptional(location);
        if (type.isEmpty() && LOGGED_ABSENT.add(id)) {
            EclipseMod.LOGGER.debug("EventSpawnRules: entity id '{}' not registered yet — gate skipped", id);
        }
        return type;
    }

    private static int count(ServerLevel level, String id) {
        Optional<EntityType<?>> type = resolve(id);
        return type.isEmpty() ? 0 : countType(level, type.get());
    }

    private static <T extends Entity> int countType(ServerLevel level, EntityType<T> type) {
        return level.getEntities(type, Entity::isAlive).size();
    }

    private static int countIn(ServerLevel level, String id, AABB area) {
        Optional<EntityType<?>> type = resolve(id);
        return type.isEmpty() ? 0 : countTypeIn(level, type.get(), area);
    }

    private static <T extends Entity> int countTypeIn(ServerLevel level, EntityType<T> type, AABB area) {
        return level.getEntities(type, area, Entity::isAlive).size();
    }

    private static boolean trySpawn(ServerLevel level, String id, BlockPos pos) {
        Optional<EntityType<?>> type = resolve(id);
        return type.isPresent() && spawn(level, type.get(), pos);
    }

    /** Vanilla-consistent placement: rule/obstruction/collision checks, NON-persistent. */
    private static boolean spawn(ServerLevel level, EntityType<?> type, BlockPos pos) {
        Entity created = type.create(level);
        if (!(created instanceof Mob mob)) {
            if (created != null) {
                created.discard();
            }
            return false;
        }
        mob.moveTo(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D,
                level.getRandom().nextFloat() * 360.0F, 0.0F);
        if (!mob.checkSpawnRules(level, MobSpawnType.NATURAL)
                || !mob.checkSpawnObstruction(level)
                || !level.noCollision(mob)) {
            mob.discard();
            return false;
        }
        mob.finalizeSpawn(level, level.getCurrentDifficultyAt(pos), MobSpawnType.NATURAL, null);
        return level.addFreshEntity(mob);
    }
}
