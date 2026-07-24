package dev.projecteclipse.eclipse.worldgen.nether;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.S2CBreachPayload;
import dev.projecteclipse.eclipse.network.S2CBreachPayload.Phase;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
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
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-authoritative seamless transfer joining the overworld crater to the real Nether
 * dimension — since IDEA-17 (W4-NETHER) a supernatural GLITCH-DRIFT in both directions.
 * Players are the guaranteed transport scope (boats and pets deliberately stay behind;
 * the player is dismounted at capture). Neither direction ever shows a vanilla transition
 * screen (the dimension swap hides inside a client glitch pulse) or deals fall damage.
 *
 * <p><b>Descent</b>: survival players falling into the funnel are captured at the breach
 * lip and drift down at ~{@value #DRIFT_SPEED} blocks/tick with hashed one-tick
 * stutter-skips (the fall visibly "skips frames"). At the funnel throat they hand off
 * 1:1 — same (x, z), no 8:1 mapping divide, the nether disc is now the same size — to
 * just above the nether roof shell, pass seamlessly through {@link BreachBuilder}'s
 * ceiling bore, ease across the open cavern and settle onto the arrival funnel floor.
 * A long Slow Falling effect rides along purely as a safety net (kicks, lag,
 * dismounts); the drift controller normally overrides it every tick.</p>
 *
 * <p><b>Return</b>: the soul-updraft column now reaches the roof and TRACTORS players
 * up at +{@value #ASCENT_SPEED}/tick. At the ceiling they pull through into the
 * overworld chimney, ride the same tractor up past the crater lip and are arced onto
 * the rim beside the return pad; the old {@code returnPad()} teleport remains only as
 * the timeout fallback.</p>
 *
 * <p>Creative players bypass capture and keep the legacy behavior (free fall +
 * teleport / updraft boost). Aborted drifts (leaving the shaft, timeouts) release the
 * player with generous Slow Falling — never stranded, never damaged. This class also
 * still owns the breach-specific pearl/elytra wall guards, the Nether hard clamp at
 * stage radius + {@value #NETHER_BORDER_MARGIN}, and cancellation of vanilla Nether
 * portal creation.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BreachTransferService {
    private static final double DESCENT_RADIUS = 6.25D;
    private static final double UPDRAFT_RADIUS = 1.6D;
    /** Legacy updraft cap (creative fallback path only since IDEA-17). */
    private static final int UPDRAFT_HEIGHT = 22;
    /** Legacy updraft boost (creative fallback path only since IDEA-17). */
    private static final double UPDRAFT_STRENGTH = 0.42D;
    private static final int TRANSFER_COOLDOWN_TICKS = 80;
    private static final int DESCENT_SLOW_FALL_TICKS = 160;
    private static final int RETURN_SLOW_FALL_TICKS = 80;
    private static final int NETHER_BORDER_MARGIN = 16;

    // --- IDEA-17 glitch-drift tuning ---

    /** Controlled descent speed in the scenic shaft segments (~2 blocks/s). */
    private static final double DRIFT_SPEED = -0.10D;
    /** Descent speed across the long open cavern between roof bore and floor approach. */
    private static final double DRIFT_CAVERN_SPEED = -0.34D;
    /** Final floor-approach speed (the landing reads gentle, supernatural). */
    private static final double DRIFT_LANDING_SPEED = -0.15D;
    /** Per-tick easing step between descent speed targets. */
    private static final double DRIFT_EASE = 0.02D;
    /** Constant tractor speed of the return ride (user constant: +0.18/tick). */
    private static final double ASCENT_SPEED = 0.18D;
    /** Horizontal pull towards the shaft centerline per block of offset. */
    private static final double DRIFT_CENTER_PULL = 0.10D;
    /** Lateral jolt applied on a stutter tick (the "skip" reads sideways too). */
    private static final double DRIFT_JOLT = 0.12D;
    /** Chance of a one-tick stutter-skip per {@value #DRIFT_STUTTER_WINDOW}-tick window. */
    private static final double DRIFT_STUTTER_CHANCE = 0.25D;
    private static final int DRIFT_STUTTER_WINDOW = 7;
    /** Capture engages this far below the crater lip plane. */
    private static final int DESCENT_CAPTURE_DEPTH = 4;
    /** Depth below the lip of the descent dimension seam (inside the dark funnel throat). */
    private static final int DESCENT_HANDOFF_DEPTH = 36;
    /** The return pull-through re-enters the overworld chimney this far below the lip. */
    private static final int ASCENT_REENTRY_DEPTH = 36;
    /** Hard per-drift timeout; the abort path takes over beyond this. */
    private static final int DRIFT_TIMEOUT_TICKS = 900;
    /** Leaving the descent shaft line by more than this aborts the drift. */
    private static final double DRIFT_ESCAPE_RADIUS = 10.0D;
    /** Leaving the updraft tractor line by more than this aborts the ascent. */
    private static final double ASCENT_ESCAPE_RADIUS = 6.0D;
    /** Safety-net Slow Falling that outlives any drift leg (abort/kick/lag cover). */
    private static final int DRIFT_SAFETY_SLOW_FALL_TICKS = 600;
    /** Client glitch pulse hold sent with DRIFT payloads (capture + each seam). */
    private static final int DRIFT_PULSE_HOLD_TICKS = 12;
    /** Fallback ceiling body Y when the arrival column is unavailable (roof lens ~230). */
    private static final int CEILING_FALLBACK_Y = 230;

    private static final Map<UUID, Long> TRANSFER_COOLDOWN = new HashMap<>();
    /** Per-player drift controller state; lifecycle mirrors {@link #TRANSFER_COOLDOWN}. */
    private static final Map<UUID, DriftState> DRIFTING = new HashMap<>();

    private enum DriftPhase {
        DESCENT_OVERWORLD,
        DESCENT_NETHER,
        ASCENT_NETHER,
        ASCENT_OVERWORLD
    }

    private static final class DriftState {
        DriftPhase phase;
        int ticks;
        double vy = DRIFT_SPEED;
        double anchorX;
        double anchorZ;
        int netherCeilingY = CEILING_FALLBACK_Y;
        int netherFloorY;

        DriftState(DriftPhase phase) {
            this.phase = phase;
        }
    }

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
        DriftState drift = DRIFTING.get(player.getUUID());
        if (drift != null) {
            switch (drift.phase) {
                case DESCENT_OVERWORLD -> tickDriftDescentOverworld(player, overworld, drift, now);
                case ASCENT_OVERWORLD -> tickDriftAscentOverworld(player, overworld, drift, now);
                default -> releaseStaleDrift(player); // died/teleported mid-drift elsewhere
            }
            return;
        }

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

        // Glitch-drift capture at the breach lip (players only; creative bypasses and
        // keeps the legacy free-fall + teleport below).
        if (!player.isCreative()
                && player.getY() <= BreachGeometry.lipY() - DESCENT_CAPTURE_DEPTH
                && player.getY() > transferY
                && distSq <= DESCENT_RADIUS * DESCENT_RADIUS
                && cooldownExpired(player, now)) {
            captureDescent(player, now);
            return;
        }

        if (player.getY() <= transferY && distSq <= DESCENT_RADIUS * DESCENT_RADIUS
                && cooldownExpired(player, now)) {
            descend(player, overworld, now);
        }
    }

    // --- glitch-drift: descent ---

    private static void captureDescent(ServerPlayer player, long now) {
        if (player.isPassenger()) {
            player.stopRiding(); // guaranteed scope is players; vehicles/pets do not cross
        }
        player.stopFallFlying();
        DriftState drift = new DriftState(DriftPhase.DESCENT_OVERWORLD);
        drift.anchorX = BreachGeometry.centerX() + 0.5D;
        drift.anchorZ = BreachGeometry.centerZ() + 0.5D;
        DRIFTING.put(player.getUUID(), drift);
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                DRIFT_SAFETY_SLOW_FALL_TICKS, 0, false, false));
        sendDriftPhase(player, Phase.DRIFT_DOWN, BreachBuilder.breachCenter());
        EclipseMod.LOGGER.debug("Breach drift capture: {} at y={}",
                player.getScoreboardName(), player.getY());
    }

    private static void tickDriftDescentOverworld(ServerPlayer player, ServerLevel overworld,
            DriftState drift, long now) {
        drift.ticks++;
        double dx = player.getX() - drift.anchorX;
        double dz = player.getZ() - drift.anchorZ;
        if (dx * dx + dz * dz > DRIFT_ESCAPE_RADIUS * DRIFT_ESCAPE_RADIUS
                || drift.ticks > DRIFT_TIMEOUT_TICKS) {
            releaseDrift(player, now, "left the descent shaft");
            return;
        }
        applyDriftVelocity(player, dx, dz, DRIFT_SPEED, now);
        driftFx(overworld, player, drift, false);
        if (player.getY() <= BreachGeometry.lipY() - DESCENT_HANDOFF_DEPTH) {
            handoffDescent(player, overworld, drift, now);
        }
    }

    /**
     * Descent dimension seam: 1:1 handoff (the 8:1 mapping divide of the old descent is
     * deleted — same x/z, clamped ±2 into the ceiling bore) from the funnel throat to
     * just above the nether roof shell. The client glitch pulse sent here hides the
     * teleport; the drift continues seamlessly down through the bore.
     */
    private static void handoffDescent(ServerPlayer player, ServerLevel overworld,
            DriftState drift, long now) {
        ServerLevel nether = overworld.getServer().getLevel(Level.NETHER);
        if (nether == null) {
            releaseDrift(player, now, "nether unavailable");
            return;
        }
        BlockPos arrival = BreachBuilder.arrivalCenter();
        double localX = Mth.clamp(player.getX() - (BreachGeometry.centerX() + 0.5D), -2.0D, 2.0D);
        double localZ = Mth.clamp(player.getZ() - (BreachGeometry.centerZ() + 0.5D), -2.0D, 2.0D);
        double targetX = arrival.getX() + 0.5D + localX;
        double targetZ = arrival.getZ() + 0.5D + localZ;
        double targetY = nether.getMaxBuildHeight() + 2.0D;
        BudgetedBlockWriter.loadWithTicket(nether, Mth.floor(targetX) >> 4, Mth.floor(targetZ) >> 4);

        drift.anchorX = arrival.getX() + 0.5D;
        drift.anchorZ = arrival.getZ() + 0.5D;
        drift.netherFloorY = arrival.getY();
        drift.netherCeilingY = netherCeilingY(arrival.getX(), arrival.getZ());
        drift.vy = DRIFT_SPEED;
        drift.phase = DriftPhase.DESCENT_NETHER;

        sendDriftPhase(player, Phase.DRIFT_DOWN, arrival); // seam pulse hides the swap
        player.teleportTo(nether, targetX, targetY, targetZ, player.getYRot(), player.getXRot());
        player.setDeltaMovement(0.0D, DRIFT_SPEED, 0.0D);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                DRIFT_SAFETY_SLOW_FALL_TICKS, 0, false, false));
        // FIX-3 seam: the first survived breach crossing advances the team beat.
        dev.projecteclipse.eclipse.progression.goals.QuestApi.completeTeamBeat(
                overworld.getServer(), "crossing_survived");
        nether.sendParticles(ParticleTypes.ASH, targetX, targetY - 2.0D, targetZ,
                12, 0.8D, 1.2D, 0.8D, 0.02D);
        EclipseMod.LOGGER.debug("Breach drift handoff: {} -> Nether ceiling bore ({}, {}, {})",
                player.getScoreboardName(), targetX, targetY, targetZ);
    }

    private static void tickDriftDescentNether(ServerPlayer player, ServerLevel nether,
            DriftState drift, long now) {
        drift.ticks++;
        double dx = player.getX() - drift.anchorX;
        double dz = player.getZ() - drift.anchorZ;
        if (dx * dx + dz * dz > DRIFT_ESCAPE_RADIUS * DRIFT_ESCAPE_RADIUS
                || drift.ticks > DRIFT_TIMEOUT_TICKS) {
            releaseDrift(player, now, "left the nether descent line");
            return;
        }
        // Speed profile: scenic −0.10 through the roof bore, an eased glide across the
        // open cavern, and a gentle final approach to the funnel floor.
        double target;
        if (player.getY() > drift.netherCeilingY - 8) {
            target = DRIFT_SPEED;
        } else if (player.getY() > drift.netherFloorY + 20) {
            target = DRIFT_CAVERN_SPEED;
        } else {
            target = DRIFT_LANDING_SPEED;
        }
        drift.vy = approach(drift.vy, target, DRIFT_EASE);
        applyDriftVelocity(player, dx, dz, drift.vy, now);
        driftFx(nether, player, drift, false);
        if (player.onGround()) {
            finishDrift(player, nether, now, "descent landed");
        }
    }

    private static void tickNether(ServerPlayer player, ServerLevel nether, long now) {
        if (!player.isCreative()) {
            clampNetherBorder(player, nether);
        }

        DriftState drift = DRIFTING.get(player.getUUID());
        if (drift != null) {
            switch (drift.phase) {
                case DESCENT_NETHER -> tickDriftDescentNether(player, nether, drift, now);
                case ASCENT_NETHER -> tickDriftAscentNether(player, nether, drift, now);
                default -> releaseStaleDrift(player);
            }
            return;
        }

        BlockPos updraft = BreachBuilder.updraftCenter();
        double dx = player.getX() - (updraft.getX() + 0.5D);
        double dz = player.getZ() - (updraft.getZ() + 0.5D);
        int ceilingY = netherCeilingY(updraft.getX(), updraft.getZ());
        // IDEA-17: the updraft column now reaches the roof shell, not just +22 blocks.
        boolean inColumn = dx * dx + dz * dz <= UPDRAFT_RADIUS * UPDRAFT_RADIUS
                && player.getY() >= updraft.getY() + 0.5D
                && player.getY() <= ceilingY;
        if (!inColumn) {
            return;
        }

        if (player.isFallFlying()) {
            player.stopFallFlying();
        }
        if (!player.isCreative() && cooldownExpired(player, now)) {
            captureAscent(player, updraft, ceilingY, now);
            return;
        }
        // Legacy fallback (creative, or cooldown still running): additive soul boost and
        // the historic pad teleport at the old column cap.
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

    // --- glitch-drift: return ---

    private static void captureAscent(ServerPlayer player, BlockPos updraft, int ceilingY, long now) {
        if (player.isPassenger()) {
            player.stopRiding();
        }
        DriftState drift = new DriftState(DriftPhase.ASCENT_NETHER);
        drift.anchorX = updraft.getX() + 0.5D;
        drift.anchorZ = updraft.getZ() + 0.5D;
        drift.netherCeilingY = ceilingY;
        DRIFTING.put(player.getUUID(), drift);
        sendDriftPhase(player, Phase.DRIFT_UP, updraft);
        EclipseMod.LOGGER.debug("Breach drift tractor: {} at y={} (ceiling {})",
                player.getScoreboardName(), player.getY(), ceilingY);
    }

    private static void tickDriftAscentNether(ServerPlayer player, ServerLevel nether,
            DriftState drift, long now) {
        drift.ticks++;
        double dx = player.getX() - drift.anchorX;
        double dz = player.getZ() - drift.anchorZ;
        if (dx * dx + dz * dz > ASCENT_ESCAPE_RADIUS * ASCENT_ESCAPE_RADIUS
                || drift.ticks > DRIFT_TIMEOUT_TICKS) {
            releaseDrift(player, now, "left the updraft tractor");
            return;
        }
        applyDriftVelocity(player, dx, dz, ASCENT_SPEED, now);
        driftFx(nether, player, drift, true);
        if (player.getY() >= drift.netherCeilingY - 2.0D) {
            pullThroughCeiling(player, nether, drift, now);
        }
    }

    /**
     * Return dimension seam: at the roof the tractor pulls the player through into the
     * overworld chimney (below the lip) and the same upward drift continues — one
     * unbroken pull from the nether floor to the overworld surface.
     */
    private static void pullThroughCeiling(ServerPlayer player, ServerLevel nether,
            DriftState drift, long now) {
        ServerLevel overworld = nether.getServer().getLevel(Level.OVERWORLD);
        if (overworld == null) {
            releaseDrift(player, now, "overworld unavailable");
            return;
        }
        double targetX = BreachGeometry.centerX() + 0.5D;
        double targetZ = BreachGeometry.centerZ() + 0.5D;
        double targetY = BreachGeometry.lipY() - ASCENT_REENTRY_DEPTH;
        BudgetedBlockWriter.loadWithTicket(overworld,
                BreachGeometry.centerX() >> 4, BreachGeometry.centerZ() >> 4);

        drift.anchorX = targetX;
        drift.anchorZ = targetZ;
        drift.phase = DriftPhase.ASCENT_OVERWORLD;

        sendDriftPhase(player, Phase.DRIFT_UP, BreachBuilder.breachCenter()); // seam pulse
        player.teleportTo(overworld, targetX, targetY, targetZ, player.getYRot(), player.getXRot());
        player.setDeltaMovement(0.0D, ASCENT_SPEED, 0.0D);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                DRIFT_SAFETY_SLOW_FALL_TICKS, 0, false, false));
        EclipseMod.LOGGER.debug("Breach drift pull-through: {} -> overworld chimney y={}",
                player.getScoreboardName(), targetY);
    }

    private static void tickDriftAscentOverworld(ServerPlayer player, ServerLevel overworld,
            DriftState drift, long now) {
        drift.ticks++;
        double dx = player.getX() - drift.anchorX;
        double dz = player.getZ() - drift.anchorZ;
        if (drift.ticks > DRIFT_TIMEOUT_TICKS) {
            fallbackReturnPad(player, overworld, now); // never stranded
            return;
        }
        double outer = BreachGeometry.CRATER_RADIUS + 30.0D;
        if (dx * dx + dz * dz > outer * outer) {
            releaseDrift(player, now, "cleared the crater");
            return;
        }
        if (player.getY() < BreachGeometry.lipY() + 1.0D) {
            applyDriftVelocity(player, dx, dz, ASCENT_SPEED, now);
        } else {
            // Final gentle arc: carried over the rim towards the return pad.
            BlockPos pad = BreachBuilder.returnPad();
            double px = pad.getX() + 0.5D - player.getX();
            double pz = pad.getZ() + 0.5D - player.getZ();
            double dist = Math.max(0.001D, Math.hypot(px, pz));
            double vy = player.getY() < BreachGeometry.lipY() + 4.0D ? 0.12D : -0.045D;
            player.setDeltaMovement(px / dist * 0.28D, vy, pz / dist * 0.28D);
            player.fallDistance = 0.0F;
            player.hurtMarked = true;
            if (player.onGround()) {
                finishDrift(player, overworld, now, "ascent deposited on the rim");
                return;
            }
        }
        driftFx(overworld, player, drift, true);
    }

    /** Timeout fallback of the final arc: the historic return-pad teleport. */
    private static void fallbackReturnPad(ServerPlayer player, ServerLevel overworld, long now) {
        DRIFTING.remove(player.getUUID());
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
        sendDriftPhase(player, Phase.DRIFT_END, pad);
        EclipseMod.LOGGER.debug("Breach drift timeout: {} sent to the return pad",
                player.getScoreboardName());
    }

    // --- glitch-drift: shared plumbing ---

    /**
     * One controller tick: velocity-clamped drift with the hashed one-tick stutter-skip
     * (Y hold + lateral jolt) that makes the ride read glitchy. {@code hurtMarked}
     * syncs the velocity to the client (the proven risePlayerAt pattern); zeroed fall
     * distance guarantees no fall damage in any direction.
     */
    private static void applyDriftVelocity(ServerPlayer player, double dx, double dz,
            double vy, long now) {
        if (player.isFallFlying()) {
            player.stopFallFlying();
        }
        double appliedVy = vy;
        double joltX = 0.0D;
        double joltZ = 0.0D;
        if (Math.floorMod(now, DRIFT_STUTTER_WINDOW) == 0) {
            long h = driftHash(player, now / DRIFT_STUTTER_WINDOW);
            if (to01(h) < DRIFT_STUTTER_CHANCE) {
                appliedVy = 0.0D; // the fall/rise "skips a frame"
                joltX = (((h >>> 16) & 1L) == 0L ? -1.0D : 1.0D) * DRIFT_JOLT;
                joltZ = (((h >>> 17) & 1L) == 0L ? -1.0D : 1.0D) * DRIFT_JOLT;
            }
        }
        player.setDeltaMovement(-dx * DRIFT_CENTER_PULL + joltX, appliedVy,
                -dz * DRIFT_CENTER_PULL + joltZ);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
    }

    /**
     * Per-drift ambience: an orbiting REVERSE_PORTAL ring (angle keyed to the drift
     * tick), a WHITE_ASH/soul streak as a motion cue (above on descent, below on
     * ascent), sculk crackle with hashed dropouts, and subtle camera-shake pulses via
     * the existing {@link S2CShakePayload}.
     */
    private static void driftFx(ServerLevel level, ServerPlayer player, DriftState drift,
            boolean ascending) {
        if (drift.ticks % 4 == 0) {
            double angle = drift.ticks * 0.3D;
            for (int i = 0; i < 6; i++) {
                double a = angle + i * (Math.PI / 3.0D);
                level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        player.getX() + Math.cos(a) * 1.1D,
                        player.getY() + 0.9D + Math.sin(a * 0.7D) * 0.4D,
                        player.getZ() + Math.sin(a) * 1.1D,
                        1, 0.0D, 0.0D, 0.0D, 0.0D);
            }
            level.sendParticles(ParticleTypes.WHITE_ASH,
                    player.getX(), player.getY() + (ascending ? -1.6D : 2.4D), player.getZ(),
                    3, 0.5D, 0.4D, 0.5D, 0.01D);
            level.sendParticles(ParticleTypes.SOUL,
                    player.getX(), player.getY() + (ascending ? -0.8D : 1.6D), player.getZ(),
                    1, 0.3D, 0.3D, 0.3D, 0.005D);
        }
        if (drift.ticks % 20 == 10) {
            long h = driftHash(player, 0x51CC + drift.ticks);
            if (to01(h) < 0.7D) { // ~30 % hard dropouts sell the glitch
                level.playSound(null, player.blockPosition(),
                        SoundEvents.SCULK_CLICKING, SoundSource.AMBIENT,
                        0.5F, 0.7F + (float) to01(h >>> 8) * 0.6F);
            }
        }
        if (drift.ticks % 40 == 20) {
            PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.12F, 16));
        }
    }

    /** Normal drift completion: cooldown, end pulse (client out-ramp + thud), burst FX. */
    private static void finishDrift(ServerPlayer player, ServerLevel level, long now, String what) {
        DRIFTING.remove(player.getUUID());
        TRANSFER_COOLDOWN.put(player.getUUID(), now + TRANSFER_COOLDOWN_TICKS);
        sendDriftPhase(player, Phase.DRIFT_END, player.blockPosition());
        level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                player.getX(), player.getY() + 0.6D, player.getZ(),
                24, 0.8D, 0.5D, 0.8D, 0.05D);
        level.sendParticles(ParticleTypes.ASH,
                player.getX(), player.getY() + 1.0D, player.getZ(),
                12, 1.0D, 0.8D, 1.0D, 0.02D);
        level.playSound(null, player.blockPosition(), SoundEvents.SOUL_ESCAPE.value(),
                SoundSource.AMBIENT, 0.8F, 0.55F);
        EclipseMod.LOGGER.debug("Breach drift finished ({}): {}", what, player.getScoreboardName());
    }

    /** Abort path: release with generous Slow Falling — never stranded, never damaged. */
    private static void releaseDrift(ServerPlayer player, long now, String reason) {
        DRIFTING.remove(player.getUUID());
        TRANSFER_COOLDOWN.put(player.getUUID(), now + TRANSFER_COOLDOWN_TICKS);
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                DRIFT_SAFETY_SLOW_FALL_TICKS, 0, false, false));
        sendDriftPhase(player, Phase.DRIFT_END, player.blockPosition());
        EclipseMod.LOGGER.debug("Breach drift released ({}): {}", reason, player.getScoreboardName());
    }

    /** A drift state observed in the wrong dimension (death/tp mid-drift): quiet cleanup. */
    private static void releaseStaleDrift(ServerPlayer player) {
        DRIFTING.remove(player.getUUID());
        sendDriftPhase(player, Phase.DRIFT_END, player.blockPosition());
    }

    private static void sendDriftPhase(ServerPlayer player, Phase phase, BlockPos anchor) {
        PacketDistributor.sendToPlayer(player,
                new S2CBreachPayload(phase, anchor, DRIFT_PULSE_HOLD_TICKS));
    }

    /**
     * Lowest SOLID roof block above (x, z) — the ceiling the updraft tractors towards.
     * Deliberately {@code ceilingBottomY} (needle tips included), NOT the lens base:
     * a stalactite hanging over the updraft column would otherwise block the rise
     * before the pull-through trigger at {@code ceiling − 2} could fire.
     */
    private static int netherCeilingY(int x, int z) {
        DiscTerrainFunction.DiscColumn column = DiscTerrainFunction.column(
                DiscProfile.NETHER, x, z, WorldStageAccess.stage(DiscProfile.NETHER));
        return column.inside() && column.ceilingBottomY() != Integer.MAX_VALUE
                ? column.ceilingBottomY() : CEILING_FALLBACK_Y;
    }

    /** Map-seed-keyed per-player hash (deterministic stutters per existing conventions). */
    private static long driftHash(ServerPlayer player, long domain) {
        long h = FrozenParams.mapSeed() ^ player.getUUID().getLeastSignificantBits();
        h ^= domain * 0x9E3779B97F4A7C15L;
        h ^= h >>> 30;
        h *= 0xBF58476D1CE4E5B9L;
        h ^= h >>> 27;
        h *= 0x94D049BB133111EBL;
        return h ^ (h >>> 31);
    }

    private static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }

    private static double approach(double value, double target, double step) {
        if (value < target) {
            return Math.min(target, value + step);
        }
        return Math.max(target, value - step);
    }

    // --- legacy paths (creative bypass + drift-abort fallback) ---

    /**
     * Legacy instant descent, kept for creative players and drift-released stragglers
     * reaching the deep shaft: 1:1 target (IDEA-17 — the 8:1 divide is deleted), safe
     * fall vector, Slow Falling arrival above the chimney.
     */
    private static void descend(ServerPlayer player, ServerLevel overworld, long now) {
        ServerLevel nether = overworld.getServer().getLevel(Level.NETHER);
        if (nether == null) {
            return;
        }
        BlockPos arrival = BreachBuilder.arrivalCenter();
        double localX = Mth.clamp(
                player.getX() - (BreachGeometry.centerX() + 0.5D), -2.0D, 2.0D);
        double localZ = Mth.clamp(
                player.getZ() - (BreachGeometry.centerZ() + 0.5D), -2.0D, 2.0D);
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
        player.setDeltaMovement(fall.x, Math.max(fall.y, -0.35D), fall.z);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                DESCENT_SLOW_FALL_TICKS, 0, false, false));
        TRANSFER_COOLDOWN.put(player.getUUID(), now + TRANSFER_COOLDOWN_TICKS);
        // FIX-3 seam: the first survived breach crossing advances the team beat.
        dev.projecteclipse.eclipse.progression.goals.QuestApi.completeTeamBeat(
                overworld.getServer(), "crossing_survived");

        overworld.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                originX, BreachGeometry.lipY(), originZ,
                18, 1.2D, 0.8D, 1.2D, 0.035D);
        nether.sendParticles(ParticleTypes.ASH,
                targetX, targetY, targetZ, 28, 1.0D, 1.5D, 1.0D, 0.025D);
        nether.playSound(null, BlockPos.containing(targetX, targetY, targetZ),
                SoundEvents.SOUL_ESCAPE.value(), SoundSource.AMBIENT, 0.9F, 0.75F);
        EclipseMod.LOGGER.debug("Breach descent (legacy): {} -> Nether ({}, {}, {})",
                player.getScoreboardName(), targetX, targetY, targetZ);
    }

    /** Legacy instant return (creative fallback path only since IDEA-17). */
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
        EclipseMod.LOGGER.debug("Breach ascent (legacy): {} -> overworld return pad {}",
                player.getScoreboardName(), pad.toShortString());
    }

    /**
     * Last-resort hard clamp at the plan's stage radius + 16. The existing SoftBorder is
     * normally stricter; this guard remains local to the breach transport contract.
     * IDEA-17 note: with the 1:1 radii both this clamp and SoftBorder read the same
     * frozen {@code StageRadii} table, so no divide/rescale is needed anywhere.
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
        DRIFTING.remove(event.getEntity().getUUID());
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        TRANSFER_COOLDOWN.clear();
        DRIFTING.clear();
    }

    private static boolean isBreachUsable(MinecraftServer server) {
        return EclipseWorldgenState.get(server).breachOpen() || BreachBuilder.isOpening(server);
    }

    private static boolean cooldownExpired(ServerPlayer player, long now) {
        return now >= TRANSFER_COOLDOWN.getOrDefault(player.getUUID(), Long.MIN_VALUE);
    }
}
