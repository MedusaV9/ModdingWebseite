package dev.projecteclipse.eclipse.worldgen.end;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.boss.enderdragon.EndCrystal;
import net.minecraft.world.entity.boss.enderdragon.EnderDragon;
import net.minecraft.world.entity.boss.enderdragon.phases.EnderDragonPhase;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityTravelToDimensionEvent;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Lightweight overworld controller for the real vanilla {@link EnderDragon}. It does
 * not instantiate the dimension-bound vanilla {@code EndDragonFight}: fight origin,
 * phase watchdog, crystal healing, boss bar and rewards are all managed here.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseDragonFight {
    private static final String DRAGON_MARKER = "eclipseEndDiscDragon";
    private static final int CRYSTAL_SCAN_TICKS = 10;
    private static final int SAVE_TICKS = 20;
    private static final int WATCHDOG_TICKS = 40;
    private static final int LANDING_RETRY_TICKS = 160;
    private static final int ENTITY_TICKET_TICKS = 100;
    private static final int DEATH_ANIMATION_TICKS = 200;
    private static final double BOSS_BAR_RANGE = 192.0D;

    /** P2/P4/analytics seam fired once after rewards and portal placement. */
    @FunctionalInterface
    public interface Listener {
        void onDragonVictory(MinecraftServer server, BlockPos center);
    }

    private static final CopyOnWriteArrayList<Listener> LISTENERS = new CopyOnWriteArrayList<>();

    @Nullable
    private static EnderDragon activeDragon;
    @Nullable
    private static ServerBossEvent bossBar;
    private static int lastCrystalCount = -1;

    private EclipseDragonFight() {}

    public static void addListener(Listener listener) {
        LISTENERS.addIfAbsent(listener);
    }

    /**
     * Starts or reattaches the fight. Safe after any restart and idempotent when the
     * tracked dragon is already active.
     */
    public static void begin(MinecraftServer server) {
        ServerLevel level = server.overworld();
        EndFightState state = EndFightState.get(server);
        if (!EclipseWorldgenState.get(server).endDiscMaterialized()
                || !state.materializationComplete()) {
            return;
        }
        if (state.dragonKilled()) {
            ensureVictoryBlocks(level);
            clearBossBar();
            return;
        }

        loadCrystalChunks(level);
        if (EndConfig.current().crystalRespawn()) {
            EndSpires.respawnMissingCrystals(level, state, EndConfig.current().crystalCount());
        } else {
            EndSpires.livingCrystals(level, state);
        }

        EnderDragon dragon = resolveSavedDragon(level, state);
        if (dragon == null && state.deathStartedGameTime() >= 0L) {
            completeVictory(level, state);
            return;
        }
        if (dragon == null) {
            dragon = spawnDragon(level, state);
        } else {
            configureDragon(dragon);
            activeDragon = dragon;
            state.updateDragon(dragon.getUUID(), dragon.blockPosition(), dragon.getHealth());
        }
        ensureBossBar();
        lastCrystalCount = state.crystalsRemaining();
        EclipseMod.LOGGER.info("Eclipse dragon fight active: dragon {}, {} crystal(s)",
                dragon.getUUID(), state.crystalsRemaining());
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        begin(event.getServer());
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        EndFightState state = EndFightState.get(server);
        if (!EclipseWorldgenState.get(server).endDiscMaterialized()) {
            clearBossBar();
            return;
        }
        if (!state.materializationComplete() || state.dragonKilled()) {
            return;
        }
        tickFight(server.overworld(), state);
    }

    @SubscribeEvent
    public static void onDragonDamage(LivingDamageEvent.Pre event) {
        if (!(event.getEntity() instanceof EnderDragon dragon)
                || !isManaged(dragon)
                || !(dragon.level() instanceof ServerLevel level)) {
            return;
        }
        EndFightState state = EndFightState.get(level.getServer());
        if (!EclipseWorldgenState.get(level.getServer()).endDiscMaterialized()
                || state.crystalsRemaining() <= 0) {
            return;
        }
        // Crystals sustain the dragon at one health; destroying all of them unlocks the kill.
        float maximumDamage = Math.max(0.0F, dragon.getHealth() - 1.0F);
        event.setNewDamage(Math.min(event.getNewDamage(), maximumDamage));
    }

    @SubscribeEvent
    public static void onDragonDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof EnderDragon dragon)
                || !isManaged(dragon)
                || !(dragon.level() instanceof ServerLevel level)) {
            return;
        }
        EndFightState state = EndFightState.get(level.getServer());
        if (!EclipseWorldgenState.get(level.getServer()).endDiscMaterialized()) {
            return;
        }
        state.markDeathStarted(level.getGameTime());
        dragon.setFightOrigin(center());
        dragon.getPhaseManager().setPhase(EnderDragonPhase.DYING);
        if (bossBar != null) {
            bossBar.setProgress(0.0F);
            bossBar.removeAllPlayers();
        }
        EclipseMod.LOGGER.info("Eclipse dragon death animation started at fight origin {}", center());
    }

    /**
     * The lit basin uses real End portal blocks for the visual. Cancel their vanilla
     * overworld→End transition and redirect players to the sanctum spawn instead.
     */
    @SubscribeEvent
    public static void onDimensionTravel(EntityTravelToDimensionEvent event) {
        Entity entity = event.getEntity();
        if (!Level.END.equals(event.getDimension())
                || !(entity.level() instanceof ServerLevel source)
                || !Level.OVERWORLD.equals(source.dimension())
                || !EclipseWorldgenState.get(source.getServer()).endDiscMaterialized()
                || !EndFightState.get(source.getServer()).dragonKilled()
                || !insideExitPortal(entity.blockPosition())) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof ServerPlayer player) {
            BlockPos spawn = source.getSharedSpawnPos();
            player.teleportTo(source,
                    spawn.getX() + 0.5D, spawn.getY() + 0.1D, spawn.getZ() + 0.5D,
                    source.getSharedSpawnAngle(), 0.0F);
            player.fallDistance = 0.0F;
            player.setDeltaMovement(Vec3.ZERO);
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeDragon = null;
        lastCrystalCount = -1;
        clearBossBar();
    }

    private static void tickFight(ServerLevel level, EndFightState state) {
        EnderDragon dragon = resolveLiveDragon(level, state);
        if (dragon == null) {
            if (state.deathStartedGameTime() >= 0L) {
                completeVictory(level, state);
            } else {
                begin(level.getServer());
            }
            return;
        }

        if (dragon.getHealth() <= 0.0F || dragon.dragonDeathTime > 0
                || state.deathStartedGameTime() >= 0L) {
            state.markDeathStarted(level.getGameTime());
            tickDeathSequence(level, state, dragon);
            return;
        }

        long gameTime = level.getGameTime();
        dragon.setFightOrigin(center());
        syncBossBar(level, dragon);

        if (gameTime % CRYSTAL_SCAN_TICKS == 0L) {
            List<EndCrystal> crystals = EndSpires.livingCrystals(level, state);
            for (EndCrystal crystal : crystals) {
                crystal.setBeamTarget(dragon.blockPosition());
            }
            if (!crystals.isEmpty() && dragon.getHealth() < dragon.getMaxHealth()) {
                // Vanilla heals from a nearby selected crystal; this controller-level heal
                // guarantees the authored pillar set remains meaningful across custom phases.
                dragon.heal(1.0F);
            }
            if (lastCrystalCount > 0 && crystals.isEmpty()) {
                level.getServer().getPlayerList().broadcastSystemMessage(
                        Component.translatable("announce.eclipse.end.crystals_destroyed"), false);
                dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
            }
            lastCrystalCount = crystals.size();
        }

        if (gameTime % WATCHDOG_TICKS == 0L) {
            watchdog(dragon, state.crystalsRemaining());
        }
        if (state.crystalsRemaining() == 0
                && gameTime % LANDING_RETRY_TICKS == 0L
                && !dragon.getPhaseManager().getCurrentPhase().isSitting()) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
        }
        if (gameTime % ENTITY_TICKET_TICKS == 0L) {
            loadCrystalChunks(level);
            BudgetedBlockWriter.loadWithTicket(
                    level, dragon.blockPosition().getX() >> 4, dragon.blockPosition().getZ() >> 4);
        }
        if (gameTime % SAVE_TICKS == 0L) {
            state.updateDragon(dragon.getUUID(), dragon.blockPosition(), dragon.getHealth());
        }
    }

    private static void watchdog(EnderDragon dragon, int crystalsRemaining) {
        EndConfig.Snapshot config = EndConfig.current();
        double dx = dragon.getX() - config.centerX();
        double dz = dragon.getZ() - config.centerZ();
        double maxRadius = config.radius() + 72.0D;
        boolean outside = dx * dx + dz * dz > maxRadius * maxRadius
                || dragon.getY() < config.surfaceY() - 24
                || dragon.getY() > config.surfaceY() + 120;
        if (outside) {
            dragon.moveTo(
                    config.centerX() + 0.5D,
                    config.surfaceY() + 48.0D,
                    config.centerZ() + 0.5D,
                    dragon.getYRot(), dragon.getXRot());
            dragon.setDeltaMovement(Vec3.ZERO);
            dragon.getPhaseManager().setPhase(EnderDragonPhase.HOLDING_PATTERN);
            EclipseMod.LOGGER.warn("Eclipse dragon left fight bounds; returned to {}", center());
            return;
        }
        if (!config.simpleDragonAi() || crystalsRemaining <= 0) {
            return;
        }
        var phase = dragon.getPhaseManager().getCurrentPhase().getPhase();
        if (phase != EnderDragonPhase.HOLDING_PATTERN
                && phase != EnderDragonPhase.STRAFE_PLAYER) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.HOLDING_PATTERN);
        }
    }

    private static void tickDeathSequence(
            ServerLevel level, EndFightState state, EnderDragon dragon) {
        clearBossBar();
        dragon.setFightOrigin(center());
        if (dragon.getPhaseManager().getCurrentPhase().getPhase() != EnderDragonPhase.DYING) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.DYING);
        }
        // Keep a broken non-End death path visually centered on the podium.
        if (dragon.position().distanceToSqr(Vec3.atCenterOf(center())) > 48.0D * 48.0D) {
            dragon.moveTo(
                    center().getX() + 0.5D,
                    center().getY() + 12.0D,
                    center().getZ() + 0.5D,
                    dragon.getYRot(), dragon.getXRot());
        }
        state.updateDragon(dragon.getUUID(), dragon.blockPosition(), 0.0F);
        long elapsed = level.getGameTime() - state.deathStartedGameTime();
        boolean timedOut = elapsed >= DEATH_ANIMATION_TICKS + 20L;
        if (timedOut && !dragon.isRemoved()) {
            // A non-End phase implementation can stall because no vanilla
            // EndDragonFight owns it. Never leave an immortal zero-health dragon behind.
            dragon.discard();
        }
        if (dragon.dragonDeathTime >= DEATH_ANIMATION_TICKS - 1
                || dragon.isRemoved()
                || timedOut) {
            completeVictory(level, state);
        }
    }

    private static void loadCrystalChunks(ServerLevel level) {
        for (BlockPos pos : EndSpires.crystalPositions(EndConfig.current().crystalCount())) {
            BudgetedBlockWriter.loadWithTicket(level, pos.getX() >> 4, pos.getZ() >> 4);
        }
    }

    private static EnderDragon spawnDragon(ServerLevel level, EndFightState state) {
        EndConfig.Snapshot config = EndConfig.current();
        EnderDragon dragon = EntityType.ENDER_DRAGON.create(level);
        if (dragon == null) {
            throw new IllegalStateException("Vanilla Ender Dragon entity type failed to instantiate");
        }
        dragon.moveTo(
                config.centerX() + 0.5D,
                config.surfaceY() + 48.0D,
                config.centerZ() + 0.5D,
                level.getRandom().nextFloat() * 360.0F,
                0.0F);
        configureDragon(dragon);
        float restored = state.dragonHealth() > 0.0F
                ? Math.min(state.dragonHealth(), config.dragonHealth())
                : config.dragonHealth();
        dragon.setHealth(restored);
        level.addFreshEntity(dragon);
        activeDragon = dragon;
        state.updateDragon(dragon.getUUID(), dragon.blockPosition(), dragon.getHealth());
        return dragon;
    }

    private static void configureDragon(EnderDragon dragon) {
        EndConfig.Snapshot config = EndConfig.current();
        AttributeInstance maxHealth = dragon.getAttribute(Attributes.MAX_HEALTH);
        if (maxHealth != null) {
            maxHealth.setBaseValue(config.dragonHealth());
        }
        if (dragon.getHealth() > config.dragonHealth()) {
            dragon.setHealth(config.dragonHealth());
        }
        dragon.setFightOrigin(center());
        dragon.setPersistenceRequired();
        dragon.getPersistentData().putBoolean(DRAGON_MARKER, true);
        if (dragon.getPhaseManager().getCurrentPhase().getPhase() == EnderDragonPhase.HOVERING) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.HOLDING_PATTERN);
        }
    }

    @Nullable
    private static EnderDragon resolveSavedDragon(ServerLevel level, EndFightState state) {
        if (state.dragonPos() != null) {
            BudgetedBlockWriter.loadWithTicket(
                    level, state.dragonPos().getX() >> 4, state.dragonPos().getZ() >> 4);
        }
        if (state.dragonId() != null) {
            Entity entity = level.getEntity(state.dragonId());
            if (entity instanceof EnderDragon dragon && isManaged(dragon) && !dragon.isRemoved()) {
                return dragon;
            }
        }
        EndConfig.Snapshot config = EndConfig.current();
        AABB bounds = new AABB(
                config.centerX() - config.radius() - 96,
                config.surfaceY() - 64,
                config.centerZ() - config.radius() - 96,
                config.centerX() + config.radius() + 96,
                config.surfaceY() + 160,
                config.centerZ() + config.radius() + 96);
        List<EnderDragon> found =
                level.getEntitiesOfClass(EnderDragon.class, bounds, EclipseDragonFight::isManaged);
        return found.isEmpty() ? null : found.get(0);
    }

    @Nullable
    private static EnderDragon resolveLiveDragon(ServerLevel level, EndFightState state) {
        if (activeDragon != null && !activeDragon.isRemoved()) {
            return activeDragon;
        }
        EnderDragon resolved = resolveSavedDragon(level, state);
        activeDragon = resolved;
        return resolved;
    }

    private static boolean isManaged(EnderDragon dragon) {
        return dragon.getPersistentData().getBoolean(DRAGON_MARKER);
    }

    private static void ensureBossBar() {
        if (bossBar != null) {
            return;
        }
        bossBar = new ServerBossEvent(
                Component.translatable("boss.eclipse.ender_dragon"),
                BossEvent.BossBarColor.PURPLE,
                BossEvent.BossBarOverlay.PROGRESS);
        bossBar.setDarkenScreen(true);
        bossBar.setPlayBossMusic(true);
        bossBar.setCreateWorldFog(true);
    }

    private static void syncBossBar(ServerLevel level, EnderDragon dragon) {
        ensureBossBar();
        if (bossBar == null) {
            return;
        }
        bossBar.setProgress(Mth.clamp(dragon.getHealth() / dragon.getMaxHealth(), 0.0F, 1.0F));
        Vec3 center = Vec3.atCenterOf(center());
        for (ServerPlayer player : level.players()) {
            boolean eligible = player.isAlive()
                    && !player.isSpectator()
                    && player.position().distanceToSqr(center) <= BOSS_BAR_RANGE * BOSS_BAR_RANGE;
            if (eligible) {
                bossBar.addPlayer(player);
            } else {
                bossBar.removePlayer(player);
            }
        }
        for (ServerPlayer player : List.copyOf(bossBar.getPlayers())) {
            if (player.level() != level) {
                bossBar.removePlayer(player);
            }
        }
    }

    private static void clearBossBar() {
        if (bossBar != null) {
            bossBar.removeAllPlayers();
            bossBar = null;
        }
    }

    private static void completeVictory(ServerLevel level, EndFightState state) {
        if (state.dragonKilled()) {
            return;
        }
        state.setDragonKilled();
        activeDragon = null;
        clearBossBar();
        ensureVictoryBlocks(level);

        EndConfig.Snapshot config = EndConfig.current();
        Vec3 rewardPos = new Vec3(
                config.centerX() + 0.5D,
                EndDiscGeometry.surfaceYAt(config.centerX(), config.centerZ()) + 7.0D,
                config.centerZ() + 0.5D);
        if (config.victoryXp() > 0) {
            ExperienceOrb.award(level, rewardPos, config.victoryXp());
        }
        level.getServer().getPlayerList().broadcastSystemMessage(
                Component.translatable("announce.eclipse.end.victory"), false);
        level.playSound(null, center(), SoundEvents.END_PORTAL_SPAWN,
                SoundSource.HOSTILE, 2.0F, 0.75F);
        PacketDistributor.sendToPlayersInDimension(
                level, S2CShakePayload.shake(1.2F, 40));

        for (Listener listener : LISTENERS) {
            try {
                listener.onDragonVictory(level.getServer(), center());
            } catch (Exception e) {
                EclipseMod.LOGGER.error("End dragon victory listener failed", e);
            }
        }
        EclipseMod.LOGGER.info(
                "Eclipse dragon defeated: {} XP, egg and sanctum portal placed; "
                        + "AnalyticsApi is read-only, so analytics may subscribe through Listener",
                config.victoryXp());
    }

    private static void ensureVictoryBlocks(ServerLevel level) {
        BlockPos center = center();
        int surface = EndDiscGeometry.surfaceYAt(center.getX(), center.getZ());
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                int distanceSq = dx * dx + dz * dz;
                if (distanceSq > 0 && distanceSq <= 4) {
                    level.setBlock(
                            new BlockPos(center.getX() + dx, surface, center.getZ() + dz),
                            Blocks.END_PORTAL.defaultBlockState(),
                            Block.UPDATE_ALL);
                }
            }
        }
        level.setBlock(
                new BlockPos(center.getX(), surface + 5, center.getZ()),
                Blocks.DRAGON_EGG.defaultBlockState(),
                Block.UPDATE_ALL);
    }

    private static boolean insideExitPortal(BlockPos pos) {
        EndConfig.Snapshot config = EndConfig.current();
        int dx = pos.getX() - config.centerX();
        int dz = pos.getZ() - config.centerZ();
        int surface = EndDiscGeometry.surfaceYAt(config.centerX(), config.centerZ());
        return dx * dx + dz * dz <= 9
                && pos.getY() >= surface - 1
                && pos.getY() <= surface + 2;
    }

    private static BlockPos center() {
        EndConfig.Snapshot config = EndConfig.current();
        return new BlockPos(config.centerX(), config.surfaceY(), config.centerZ());
    }
}
