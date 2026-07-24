package dev.projecteclipse.eclipse.glitch;

import java.util.List;
import java.util.Optional;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.worldgen.stage.GrowthPacing;
import dev.projecteclipse.eclipse.worldgen.stage.NewRingRegistry;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Difficulty;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobSpawnType;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Interval spawner for glitched mobs on freshly expanded terrain. Entity types are resolved
 * from string ids at spawn time; missing P6 registrations are a silent no-op.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GlitchSpawnService {
    private GlitchSpawnService() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        GlitchConfig.Data config = GlitchConfig.get();
        if (!config.enabled() || config.spawnIntervalTicks() <= 0
                || server.getTickCount() % config.spawnIntervalTicks() != 0) {
            return;
        }

        int day = DayScheduler.getDay(server);
        float buffMultiplier = TimedBuffApi.Holder.get().multiplier(server, "glitch_spawn");
        for (ServerLevel level : server.getAllLevels()) {
            spawnPass(level, day, config, buffMultiplier);
        }
    }

    private static void spawnPass(ServerLevel level, int day, GlitchConfig.Data config,
            float buffMultiplier) {
        if (level.players().stream().noneMatch(player -> !player.isSpectator())
                || level.getDifficulty() == Difficulty.PEACEFUL) {
            return;
        }

        int alive = countAlive(level, config.entityIds());
        if (!shouldAttemptSpawn(config.enabled(), config.minDay(), day, config.nightOnly(),
                level.isNight(), alive, config.maxAlive(), 0.0D, 1.0D, 1.0F)) {
            return;
        }

        List<BlockPos> positions = NewRingRegistry.sampleFreshPositions(
                level, config.spawnAttemptsPerInterval());
        for (BlockPos pos : positions) {
            if (alive >= config.maxAlive()) {
                break;
            }
            double roll = level.getRandom().nextDouble();
            if (!shouldAttemptSpawn(config.enabled(), config.minDay(), day, config.nightOnly(),
                    level.isNight(), alive, config.maxAlive(), roll,
                    config.spawnChancePerSample(), buffMultiplier)) {
                continue;
            }
            if (!isWithinConfiguredFreshWindow(
                    NewRingRegistry.freshness(level, pos),
                    GrowthPacing.glitchFreshTicks(),
                    config.freshRingWindowTicks())) {
                continue;
            }
            if (!isPlayerDistanceValid(level, pos,
                    config.minPlayerDistance(), config.maxPlayerDistance())) {
                continue;
            }
            if (config.entityIds().isEmpty()) {
                return;
            }

            String id = config.entityIds().get(level.getRandom().nextInt(config.entityIds().size()));
            Optional<EntityType<?>> type = resolveEntityType(id);
            if (type.isPresent() && spawn(level, type.get(), pos)) {
                alive++;
            }
        }
    }

    /**
     * Pure spawn decision for gametests. The timed-buff multiplier affects chance only and is
     * clamped to one, so a surge cannot bypass the day/night/cap gates.
     */
    public static boolean shouldAttemptSpawn(boolean enabled, int minDay, int currentDay,
            boolean nightOnly, boolean isNight, int alive, int maxAlive,
            double roll, double baseChance, float buffMultiplier) {
        if (!enabled || currentDay < minDay || (nightOnly && !isNight)
                || maxAlive <= 0 || alive >= maxAlive) {
            return false;
        }
        double effectiveChance = Math.max(0.0D,
                Math.min(1.0D, baseChance * Math.max(0.0F, buffMultiplier)));
        return roll < effectiveChance;
    }

    /**
     * Narrows the window exposed by {@link NewRingRegistry}. The effective freshness is the
     * smaller of {@code glitch.json freshRingWindowTicks} and
     * {@code worldgen_tuning.json glitch.freshTicks}; this package never revives a row already
     * considered stale by the worldgen registry.
     */
    public static boolean isWithinConfiguredFreshWindow(double freshness,
            int registryFreshTicks, int configuredFreshTicks) {
        if (freshness <= 0.0D || registryFreshTicks <= 0 || configuredFreshTicks <= 0) {
            return false;
        }
        double ageTicks = (1.0D - Math.min(1.0D, freshness)) * registryFreshTicks;
        return ageTicks < Math.min(registryFreshTicks, configuredFreshTicks);
    }

    /** Soft registry lookup; malformed or not-yet-registered P6 ids are intentionally silent. */
    public static Optional<EntityType<?>> resolveEntityType(String id) {
        ResourceLocation location = ResourceLocation.tryParse(id);
        return location == null
                ? Optional.empty()
                : BuiltInRegistries.ENTITY_TYPE.getOptional(location);
    }

    private static boolean isPlayerDistanceValid(ServerLevel level, BlockPos pos,
            double minDistance, double maxDistance) {
        double minSq = minDistance * minDistance;
        double maxSq = maxDistance * maxDistance;
        boolean nearAPlayer = false;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator()) {
                continue;
            }
            double distanceSq = player.distanceToSqr(
                    pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D);
            if (distanceSq < minSq) {
                return false;
            }
            if (distanceSq <= maxSq) {
                nearAPlayer = true;
            }
        }
        return nearAPlayer;
    }

    private static int countAlive(ServerLevel level, List<String> ids) {
        int count = 0;
        for (String id : ids) {
            Optional<EntityType<?>> type = resolveEntityType(id);
            if (type.isPresent()) {
                count += countAlive(level, type.get());
            }
        }
        return count;
    }

    private static <T extends Entity> int countAlive(ServerLevel level, EntityType<T> type) {
        return level.getEntities(type, Entity::isAlive).size();
    }

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
