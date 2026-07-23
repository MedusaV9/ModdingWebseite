package dev.projecteclipse.eclipse.worldgen.nether;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityTeleportEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server-authoritative seamless transfer joining the overworld crater to the real Nether
 * dimension. Players are the guaranteed transport scope (boats and pets deliberately stay
 * behind; the player is dismounted before crossing).
 *
 * <p>The descent keeps the player's local offset at Minecraft's 8:1 Overworld→Nether scale,
 * preserves a safely clamped fall vector, and grants eight seconds of Slow Falling. The
 * reverse route is a soul updraft inside the arrival chimney. This class also owns the
 * breach-specific pearl/elytra wall guards, the Nether hard clamp at stage radius + 16, and
 * cancellation of vanilla Nether portal creation.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BreachTransferService {
    private static final double DESCENT_RADIUS = 6.25D;
    private static final double UPDRAFT_RADIUS = 1.6D;
    private static final int UPDRAFT_HEIGHT = 22;
    private static final double UPDRAFT_STRENGTH = 0.42D;
    private static final int TRANSFER_COOLDOWN_TICKS = 80;
    private static final int DESCENT_SLOW_FALL_TICKS = 160;
    private static final int RETURN_SLOW_FALL_TICKS = 80;
    private static final int NETHER_BORDER_MARGIN = 16;

    private static final Map<UUID, Long> TRANSFER_COOLDOWN = new HashMap<>();

    private BreachTransferService() {}

    @SubscribeEvent
    public static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !(player.level() instanceof ServerLevel level)
                || player.isSpectator()) {
            return;
        }
        MinecraftServer server = level.getServer();
        if (!isBreachUsable(server)) {
            return;
        }
        long now = server.getTickCount();
        if (level.dimension() == Level.OVERWORLD) {
            tickOverworld(player, level, now);
        } else if (level.dimension() == Level.NETHER) {
            tickNether(player, level, now);
        }
    }

    private static void tickOverworld(ServerPlayer player, ServerLevel overworld, long now) {
        double dx = player.getX() - (BreachGeometry.centerX() + 0.5D);
        double dz = player.getZ() - (BreachGeometry.centerZ() + 0.5D);
        double distSq = dx * dx + dz * dz;
        int stage = WorldStageAccess.stage(DiscProfile.OVERWORLD);
        int transferY = DiscTerrainFunction.column(DiscProfile.OVERWORLD,
                BreachGeometry.centerX(), BreachGeometry.centerZ(), stage).groundBottomY() - 16;

        // Elytra cannot skim through the funnel shell below the visible crater flare.
        if (player.getY() < BreachGeometry.lipY() - 8
                && player.getY() > transferY
                && distSq <= (double) (BreachGeometry.CRATER_RADIUS + 2)
                        * (BreachGeometry.CRATER_RADIUS + 2)
                && distSq > DESCENT_RADIUS * DESCENT_RADIUS) {
            if (player.isFallFlying()) {
                player.stopFallFlying();
            }
            double dist = Math.max(0.001D, Math.sqrt(distSq));
            player.setDeltaMovement(-dx / dist * 0.18D,
                    Math.min(player.getDeltaMovement().y, -0.08D),
                    -dz / dist * 0.18D);
            player.hurtMarked = true;
        }

        if (player.getY() <= transferY && distSq <= DESCENT_RADIUS * DESCENT_RADIUS
                && cooldownExpired(player, now)) {
            descend(player, overworld, now);
        }
    }

    private static void descend(ServerPlayer player, ServerLevel overworld, long now) {
        ServerLevel nether = overworld.getServer().getLevel(Level.NETHER);
        if (nether == null) {
            return;
        }
        BlockPos arrival = BreachBuilder.arrivalCenter();
        double localX = Mth.clamp(
                (player.getX() - (BreachGeometry.centerX() + 0.5D)) / 8.0D, -2.0D, 2.0D);
        double localZ = Mth.clamp(
                (player.getZ() - (BreachGeometry.centerZ() + 0.5D)) / 8.0D, -2.0D, 2.0D);
        double targetX = arrival.getX() + 0.5D + localX;
        double targetZ = arrival.getZ() + 0.5D + localZ;
        double targetY = arrival.getY() + UPDRAFT_HEIGHT - 2.0D;
        BudgetedBlockWriter.loadWithTicket(nether, Mth.floor(targetX) >> 4, Mth.floor(targetZ) >> 4);

        double originX = player.getX();
        double originZ = player.getZ();
        Vec3 fall = player.getDeltaMovement();
        if (player.isPassenger()) {
            player.stopRiding(); // guaranteed scope is players; vehicles/pets do not cross
        }
        player.stopFallFlying();
        player.teleportTo(nether, targetX, targetY, targetZ, player.getYRot(), player.getXRot());
        player.setDeltaMovement(fall.x / 8.0D, Math.max(fall.y, -0.35D), fall.z / 8.0D);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                DESCENT_SLOW_FALL_TICKS, 0, false, false));
        TRANSFER_COOLDOWN.put(player.getUUID(), now + TRANSFER_COOLDOWN_TICKS);

        overworld.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                originX, BreachGeometry.lipY(), originZ,
                18, 1.2D, 0.8D, 1.2D, 0.035D);
        nether.sendParticles(ParticleTypes.ASH,
                targetX, targetY, targetZ, 28, 1.0D, 1.5D, 1.0D, 0.025D);
        nether.playSound(null, BlockPos.containing(targetX, targetY, targetZ),
                SoundEvents.SOUL_ESCAPE.value(), SoundSource.AMBIENT, 0.9F, 0.75F);
        EclipseMod.LOGGER.debug("Breach descent: {} -> Nether ({}, {}, {})",
                player.getScoreboardName(), targetX, targetY, targetZ);
    }

    private static void tickNether(ServerPlayer player, ServerLevel nether, long now) {
        if (!player.isCreative()) {
            clampNetherBorder(player, nether);
        }

        BlockPos updraft = BreachBuilder.updraftCenter();
        double dx = player.getX() - (updraft.getX() + 0.5D);
        double dz = player.getZ() - (updraft.getZ() + 0.5D);
        boolean inColumn = dx * dx + dz * dz <= UPDRAFT_RADIUS * UPDRAFT_RADIUS
                && player.getY() >= updraft.getY() + 0.5D
                && player.getY() <= updraft.getY() + UPDRAFT_HEIGHT + 3.0D;
        if (!inColumn) {
            return;
        }

        if (player.isFallFlying()) {
            player.stopFallFlying();
        }
        Vec3 motion = player.getDeltaMovement();
        player.setDeltaMovement(motion.x - dx * 0.06D,
                Math.max(motion.y, UPDRAFT_STRENGTH),
                motion.z - dz * 0.06D);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        if (player.getY() >= updraft.getY() + UPDRAFT_HEIGHT
                && cooldownExpired(player, now)) {
            ascend(player, now);
        }
    }

    private static void ascend(ServerPlayer player, long now) {
        ServerLevel overworld = player.server.getLevel(Level.OVERWORLD);
        if (overworld == null) {
            return;
        }
        BlockPos pad = BreachBuilder.returnPad();
        BudgetedBlockWriter.loadWithTicket(overworld, pad.getX() >> 4, pad.getZ() >> 4);
        player.teleportTo(overworld, pad.getX() + 0.5D, pad.getY() + 6.0D, pad.getZ() + 0.5D,
                player.getYRot(), player.getXRot());
        player.setDeltaMovement(0.0D, -0.08D, 0.0D);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                RETURN_SLOW_FALL_TICKS, 0, false, false));
        TRANSFER_COOLDOWN.put(player.getUUID(), now + TRANSFER_COOLDOWN_TICKS);
        overworld.sendParticles(ParticleTypes.SOUL_FIRE_FLAME,
                pad.getX() + 0.5D, pad.getY() + 2.0D, pad.getZ() + 0.5D,
                30, 1.2D, 2.0D, 1.2D, 0.04D);
        overworld.playSound(null, pad, SoundEvents.SOUL_ESCAPE.value(),
                SoundSource.AMBIENT, 0.9F, 1.25F);
        EclipseMod.LOGGER.debug("Breach ascent: {} -> overworld return pad {}",
                player.getScoreboardName(), pad.toShortString());
    }

    /**
     * Last-resort hard clamp at the plan's stage radius + 16. The existing SoftBorder is
     * normally stricter; this guard remains local to the breach transport contract.
     */
    private static void clampNetherBorder(ServerPlayer player, ServerLevel nether) {
        int stage = WorldStageService.stage(nether.getServer(), DiscProfile.NETHER);
        double stageRadius = StageRadii.radius(DiscProfile.NETHER, stage);
        double hardRadius = stageRadius + NETHER_BORDER_MARGIN;
        double distSq = player.getX() * player.getX() + player.getZ() * player.getZ();
        if (distSq <= hardRadius * hardRadius) {
            return;
        }
        double dist = Math.sqrt(distSq);
        double safeRadius = Math.max(2.0D, stageRadius - 4.0D);
        double x = player.getX() / dist * safeRadius;
        double z = player.getZ() / dist * safeRadius;
        int blockX = Mth.floor(x);
        int blockZ = Mth.floor(z);
        BudgetedBlockWriter.loadWithTicket(nether, blockX >> 4, blockZ >> 4);
        int y = DiscTerrainFunction.surfaceY(DiscProfile.NETHER, blockX, blockZ) + 1;
        player.stopFallFlying();
        player.teleportTo(nether, x, y, z, player.getYRot(), player.getXRot());
        player.setDeltaMovement(Vec3.ZERO);
        player.fallDistance = 0.0F;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING, 60, 0, false, false));
        EclipseMod.LOGGER.debug("Breach hard-clamped {} inside Nether radius {}",
                player.getScoreboardName(), safeRadius);
    }

    @SubscribeEvent
    public static void onEnderPearl(EntityTeleportEvent.EnderPearl event) {
        ServerPlayer player = event.getPlayer();
        if (!(player.level() instanceof ServerLevel level)
                || !isBreachUsable(level.getServer())) {
            return;
        }
        if (level.dimension() == Level.NETHER) {
            int stage = WorldStageService.stage(level.getServer(), DiscProfile.NETHER);
            clampTargetToRadius(event,
                    StageRadii.radius(DiscProfile.NETHER, stage) + NETHER_BORDER_MARGIN);
            return;
        }
        if (level.dimension() != Level.OVERWORLD
                || event.getTargetY() >= BreachGeometry.lipY() - 8) {
            return;
        }
        double dx = event.getTargetX() - (BreachGeometry.centerX() + 0.5D);
        double dz = event.getTargetZ() - (BreachGeometry.centerZ() + 0.5D);
        double distSq = dx * dx + dz * dz;
        double outer = BreachGeometry.CRATER_RADIUS + 2.0D;
        if (distSq <= outer * outer && distSq > DESCENT_RADIUS * DESCENT_RADIUS) {
            double scale = (DESCENT_RADIUS - 0.5D) / Math.sqrt(distSq);
            event.setTargetX(BreachGeometry.centerX() + 0.5D + dx * scale);
            event.setTargetZ(BreachGeometry.centerZ() + 0.5D + dz * scale);
        }
    }

    private static void clampTargetToRadius(EntityTeleportEvent event, double radius) {
        double dx = event.getTargetX();
        double dz = event.getTargetZ();
        double distSq = dx * dx + dz * dz;
        if (distSq <= radius * radius) {
            return;
        }
        double scale = radius / Math.sqrt(distSq);
        event.setTargetX(dx * scale);
        event.setTargetZ(dz * scale);
    }

    /** Eclipse progression has no vanilla Nether portals: the breach is the only route. */
    @SubscribeEvent
    public static void onPortalSpawn(BlockEvent.PortalSpawnEvent event) {
        event.setCanceled(true);
    }

    /** Persistent low-cost baseline FX; P2 layers the cinematic smoke/quake over this. */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % 10 != 0 || !isBreachUsable(server)) {
            return;
        }
        ServerLevel overworld = server.overworld();
        BlockPos center = BreachBuilder.breachCenter();
        double angle = server.getTickCount() * 0.11D;
        for (int i = 0; i < 2; i++) {
            double a = angle + i * Math.PI;
            double x = center.getX() + 0.5D + Math.cos(a) * BreachGeometry.CRATER_RADIUS;
            double z = center.getZ() + 0.5D + Math.sin(a) * BreachGeometry.CRATER_RADIUS;
            overworld.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                    x, center.getY() + 0.8D, z, 2, 0.35D, 0.15D, 0.35D, 0.01D);
        }
        ServerLevel nether = server.getLevel(Level.NETHER);
        if (nether != null) {
            BlockPos updraft = BreachBuilder.updraftCenter();
            nether.sendParticles(ParticleTypes.SOUL_FIRE_FLAME,
                    updraft.getX() + 0.5D, updraft.getY() + 1.2D, updraft.getZ() + 0.5D,
                    5, 0.35D, 1.0D, 0.35D, 0.035D);
            nether.sendParticles(ParticleTypes.ASH,
                    updraft.getX() + 0.5D, updraft.getY() + 8.0D, updraft.getZ() + 0.5D,
                    4, 1.5D, 5.0D, 1.5D, 0.01D);
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        TRANSFER_COOLDOWN.remove(event.getEntity().getUUID());
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        TRANSFER_COOLDOWN.clear();
    }

    private static boolean isBreachUsable(MinecraftServer server) {
        return EclipseWorldgenState.get(server).breachOpen() || BreachBuilder.isOpening(server);
    }

    private static boolean cooldownExpired(ServerPlayer player, long now) {
        return now >= TRANSFER_COOLDOWN.getOrDefault(player.getUUID(), Long.MIN_VALUE);
    }
}
