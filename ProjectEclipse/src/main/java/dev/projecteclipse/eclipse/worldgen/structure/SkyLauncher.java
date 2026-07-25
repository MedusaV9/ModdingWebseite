package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.end.EndConfig;
import dev.projecteclipse.eclipse.worldgen.end.EndFightState;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * PLAN-C C11: the wind-altar SKY LAUNCHER — the authored way up to the End disc.
 *
 * <p>The wizard mountain peaks at ≈ Y 280 while the End disc surface hangs at ≈ Y 360
 * ({@link DiscProfile#END_DISC_SURFACE_Y}); before this package players needed scaffold
 * towers or pearl ladders. Two pads close the gap:</p>
 * <ol>
 *   <li><b>Launch pad</b> ({@code eclipse:sky_launcher}) — an 8×8 "wind altar" ring
 *       (polished-deepslate disc, calcite rim, sculk inlays, central amethyst spire,
 *       four chain pylons, a hovering wind-shard display that spins up with the
 *       charge) stamped on a terraced shelf just below the observatory
 *       summit via the two-phase {@link StructurePendingRegistry} (rift reveal, resume,
 *       dedup for free — the {@link WizardObservatory} pattern). Using the pad's
 *       {@code minecraft:interaction} runs a {@value #CHARGE_TICKS}-tick charge-up
 *       (end-rod spiral + rising amethyst chimes), then hurls the player on a computed
 *       ballistic arc toward the near rim of the disc with Slow Falling and a
 *       no-fall-damage grace window.</li>
 *   <li><b>Return pad</b> ({@code eclipse:sky_launcher_return}) — a small purpur ring on
 *       the disc rim facing the mountain; using it grants slow-fall + grace and nudges
 *       the player off the rim toward home (the trip down needs no ballistics).</li>
 * </ol>
 *
 * <p>Both sites enqueue when {@link EndFightState#materializationComplete()} flips —
 * the launcher appears WITH the island (the End disc's {@code final_day} window), and
 * the return pad can only stamp onto disc blocks that actually exist.</p>
 *
 * <p><b>Ballistics</b>: the vertical start speed is solved by simulating vanilla's
 * per-tick integration {@code v' = (v - 0.08) * 0.98} until the arc clears the disc
 * surface + {@value #APEX_CLEARANCE} (drag makes closed forms lie); the horizontal
 * speed uses the air-drag geometric sum ({@code Σ 0.91^n ≈ 11.1}) capped at
 * {@value #MAX_HORIZONTAL_SPEED}. A per-flight tick watch nudges the velocity ONCE if
 * the descent would miss the footprint and drops on landing.</p>
 *
 * <p><b>Fall grace</b>: {@link #grantFallGrace} stamps an expiry game time into the
 * player's persistent data; the {@link LivingIncomingDamageEvent} guard cancels fall
 * damage until it lapses. Deliberately NOT {@code TimedBuffApi} — timed buffs are
 * server-global and config-defined, while this grace is per-player and short. C13's
 * {@code EndShatterSequence} reuses the same seam for its 120 s shatter grace.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SkyLauncher {
    /** Frozen site + structure id of the mountain launch pad. */
    public static final String SITE_ID = "eclipse:sky_launcher";
    /** Site id of the disc-rim return pad (same structure id → same placer, branch on site). */
    public static final String RETURN_SITE_ID = "eclipse:sky_launcher_return";
    /** Command tag on the launch pad's interaction entity. */
    public static final String ENTITY_TAG = "eclipse_sky_launcher";
    /** Command tag on the return pad's interaction entity. */
    public static final String RETURN_ENTITY_TAG = "eclipse_sky_launcher_return";
    /** Command tag on the launch pad's wind-shard display accent (BD-SHIP). */
    public static final String SHARD_TAG = "eclipse_sky_launcher_shard";

    // --- wind shard (BD-SHIP; launch pad only — the authored hero, not the utility ring) ---
    /** Golden angle (radians) — the charge spiral's three-arm phase offsets. */
    private static final float GOLDEN_ANGLE = 2.3999632F;
    /** Shard hover height above the pad floor (clear of the y0+3 amethyst cluster). */
    private static final double SHARD_HOVER = 4.6D;
    private static final float SHARD_SCALE = 0.38F;
    /** Ambient motion: slow yaw, fixed tilt, long sine bob — poses are absolute in game time. */
    private static final double SHARD_YAW_DEG_PER_TICK = 1.4D;
    private static final double SHARD_TILT_DEG = 12.0D;
    private static final double SHARD_BOB_BLOCKS = 0.3D;
    private static final double SHARD_BOB_PERIOD = 160.0D;
    /** Charge spin-up: extra yaw (deg) at progress 1 — capped so 3t windows stay ≤ ~25°. */
    private static final double SHARD_CHARGE_BOOST_DEG = 60.0D;

    /** Stage recorded on the pending rows (mountain is fully inside the stage-3 disc). */
    private static final int STAGE = WizardObservatory.MIN_STAGE;
    /** Full XZ extent of the terraced launch pad (the pending rift is sized from it). */
    public static final int FOOTPRINT = 9;
    private static final int HALF = 4;
    /** Pad center distance from the mountain summit (clears the observatory's 11×11). */
    private static final int PAD_OFFSET = 14;
    /** Return pad radius on the disc (just inside the wobbled rim). */
    private static final double RETURN_PAD_RADIUS = DiscProfile.END_DISC_RADIUS - 12.0D;

    /** Charge-up length before the launch fires. */
    public static final int CHARGE_TICKS = 15;
    /** Slow Falling granted on launch (45 s per plan). */
    private static final int LAUNCH_SLOW_FALL_TICKS = 45 * 20;
    /** Slow Falling granted by the return pad (longer — the drop is ~300 blocks). */
    private static final int RETURN_SLOW_FALL_TICKS = 90 * 20;
    /** No-fall-damage window stamped on launch / return use. */
    private static final int FALL_GRACE_TICKS = 90 * 20;
    /** Landing target ring radius (inside the rim so the wobble can never strand a flight). */
    private static final double TARGET_RING_RADIUS = DiscProfile.END_DISC_RADIUS - 12.0D;
    /** The arc's apex must clear the landing surface by this many blocks. */
    private static final int APEX_CLEARANCE = 8;
    /** Vanilla per-tick vertical integration constants (LivingEntity.travel). */
    private static final double GRAVITY = 0.08D;
    private static final double VERTICAL_DRAG = 0.98D;
    /** Air horizontal displacement sum: Σ 0.91^n = 1 / 0.09 ≈ 11.1 blocks per unit speed. */
    private static final double HORIZONTAL_TRAVEL_FACTOR = 11.1D;
    private static final double MAX_HORIZONTAL_SPEED = 6.0D;
    private static final double MAX_VERTICAL_SPEED = 12.0D;
    /** Flight watch gives up after this long (slow-fall descents are leisurely). */
    private static final int FLIGHT_TIMEOUT_TICKS = 90 * 20;
    /** Persistent-data key of the no-fall-damage expiry game time. */
    private static final String TAG_FALL_GRACE_UNTIL = "eclipseNoFallGraceUntil";

    private static final int ENQUEUE_POLL_TICKS = 20;
    private static final int AMBIENT_TICKS = 20;
    private static final int SELF_HEAL_TICKS = 200;

    private static final AtomicBoolean BOOTSTRAPPED = new AtomicBoolean();
    /** Player UUID → active charge-up. Server thread only. */
    private static final Map<UUID, Charge> CHARGES = new HashMap<>();
    /** Player UUID → active launched flight (overshoot watch). Server thread only. */
    private static final Map<UUID, Flight> FLIGHTS = new HashMap<>();

    private record Charge(BlockPos pad, long launchAtTick) {}

    private static final class Flight {
        final double targetX;
        final double targetZ;
        final long deadlineTick;
        boolean nudged;

        Flight(double targetX, double targetZ, long deadlineTick) {
            this.targetX = targetX;
            this.targetZ = targetZ;
            this.deadlineTick = deadlineTick;
        }
    }

    private SkyLauncher() {}

    // --- lifecycle wiring (WizardObservatory pattern) ---

    /** Registers the shared placer once per JVM boot. */
    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        StructurePendingRegistry.registerAsyncPlacer(SITE_ID, SkyLauncher::placeSite);
        if (BOOTSTRAPPED.compareAndSet(false, true)) {
            EclipseMod.LOGGER.info("SkyLauncher registered (enqueues with End-disc materialization)");
        }
    }

    /** Boot catch-up for saves whose disc completed before this code merged. */
    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onServerStarted(ServerStartedEvent event) {
        maybeEnqueue(event.getServer());
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        CHARGES.clear();
        FLIGHTS.clear();
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % ENQUEUE_POLL_TICKS == 0) {
            maybeEnqueue(server);
        }
        if (!CHARGES.isEmpty()) {
            tickCharges(server);
        }
        if (!FLIGHTS.isEmpty()) {
            tickFlights(server);
        }
        long gameTime = server.overworld().getGameTime();
        if (gameTime % AMBIENT_TICKS == 0L) {
            ambientTick(server.overworld(), gameTime);
        }
    }

    // --- fall grace (shared with C13's EndShatterSequence) ---

    /** Cancels fall damage for {@code ticks}; per-player, restart-safe (persistent data). */
    public static void grantFallGrace(ServerPlayer player, int ticks) {
        player.getPersistentData().putLong(TAG_FALL_GRACE_UNTIL,
                player.serverLevel().getGameTime() + ticks);
    }

    /** The one guard keyed on the grace stamp (plan C13 §4). */
    @SubscribeEvent
    public static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (event.getEntity() instanceof ServerPlayer player
                && event.getSource().is(DamageTypeTags.IS_FALL)
                && player.getPersistentData().getLong(TAG_FALL_GRACE_UNTIL)
                        > player.serverLevel().getGameTime()) {
            event.setCanceled(true);
        }
    }

    // --- pad use ---

    @SubscribeEvent
    public static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getHand() != InteractionHand.MAIN_HAND
                || !(event.getEntity() instanceof ServerPlayer player)
                || player.isSpectator()) {
            return;
        }
        Entity target = event.getTarget();
        if (target.getTags().contains(ENTITY_TAG)) {
            event.setCanceled(true);
            beginCharge(player, target.blockPosition());
        } else if (target.getTags().contains(RETURN_ENTITY_TAG)) {
            event.setCanceled(true);
            returnDescent(player);
        }
    }

    /** Starts (or ignores a re-click during) the 15-tick charge-up. */
    private static void beginCharge(ServerPlayer player, BlockPos pad) {
        if (CHARGES.containsKey(player.getUUID()) || FLIGHTS.containsKey(player.getUUID())) {
            return;
        }
        CHARGES.put(player.getUUID(),
                new Charge(pad, player.server.getTickCount() + CHARGE_TICKS));
        player.serverLevel().playSound(null, pad, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.BLOCKS, 1.0F, 0.6F);
        // PH-WORLD (IDEAS-world #5): Photon charge-helix cue — the client asset is
        // CHARGE_TICKS long, so a walk-off cancel needs no stop wiring (the launch cue
        // simply never follows). The END_ROD spiral in tickCharges stays the baseline.
        FxPayloads.sendFxEvent(player.serverLevel(), FxCues.CUE_SKY_LAUNCH_CHARGE,
                Vec3.atCenterOf(pad), 0.0F, 0.0F, 64.0D);
        player.displayClientMessage(ServerLang.tr(player, "eclipse.sky_launcher.charging"), true);
    }

    /** Charge FX per tick; fires the launch when the timer lapses, cancels on walk-off. */
    private static void tickCharges(MinecraftServer server) {
        long tick = server.getTickCount();
        Iterator<Map.Entry<UUID, Charge>> iterator = CHARGES.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<UUID, Charge> entry = iterator.next();
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            Charge charge = entry.getValue();
            if (player == null || player.isSpectator()
                    || player.position().distanceToSqr(Vec3.atCenterOf(charge.pad())) > 36.0D) {
                iterator.remove();
                continue;
            }
            ServerLevel level = player.serverLevel();
            long remaining = charge.launchAtTick() - tick;
            if (remaining > 0) {
                double progress = 1.0D - (double) remaining / CHARGE_TICKS;
                double angle = progress * Math.PI * 4.0D;
                Vec3 center = Vec3.atCenterOf(charge.pad());
                // BD-SHIP golden-angle spiral: three arms 137.5077° apart (same 3
                // particles/tick budget as the old single dotted line — 3×1, not 1×3).
                for (int arm = 0; arm < 3; arm++) {
                    double armAngle = angle + arm * GOLDEN_ANGLE;
                    level.sendParticles(ParticleTypes.END_ROD,
                            center.x + Math.cos(armAngle) * 1.4D,
                            center.y + progress * 2.5D,
                            center.z + Math.sin(armAngle) * 1.4D,
                            1, 0.1D, 0.08D, 0.1D, 0.01D);
                }
                if (remaining % 3 == 0) {
                    level.playSound(null, charge.pad(), SoundEvents.AMETHYST_BLOCK_CHIME,
                            SoundSource.BLOCKS, 1.0F, 0.6F + (float) progress * 1.2F);
                    // BD-SHIP: the shard whips up with the chimes (3t windows; after the
                    // launch the ambient driver's absolute clock pulls it back — the
                    // recoil settle is free under the stateless-push law).
                    boostWindShard(level, charge.pad(), progress);
                }
                continue;
            }
            iterator.remove();
            launch(player, charge.pad());
        }
    }

    /** Applies the solved ballistic arc, the grace effects and the launch FX. */
    private static void launch(ServerPlayer player, BlockPos pad) {
        EndConfig.Snapshot config = EndConfig.current();
        double fromCenterX = pad.getX() + 0.5D - config.centerX();
        double fromCenterZ = pad.getZ() + 0.5D - config.centerZ();
        double centerDist = Math.sqrt(fromCenterX * fromCenterX + fromCenterZ * fromCenterZ);
        if (centerDist < 1.0E-3D) {
            centerDist = 1.0D;
            fromCenterX = 1.0D;
        }
        // Landing target: the disc ring point nearest the pad (arc "toward centerX/centerZ").
        double targetX = config.centerX() + fromCenterX / centerDist * TARGET_RING_RADIUS;
        double targetZ = config.centerZ() + fromCenterZ / centerDist * TARGET_RING_RADIUS;
        int targetSurface = EndDiscGeometry.surfaceYAt(
                (int) Math.round(targetX), (int) Math.round(targetZ));

        double dx = targetX - player.getX();
        double dz = targetZ - player.getZ();
        double horizontalDist = Math.sqrt(dx * dx + dz * dz);
        double rise = Math.max(targetSurface, player.getY()) + APEX_CLEARANCE - player.getY();
        double vy = solveLaunchVy(rise);
        double vh = Math.min(horizontalDist / HORIZONTAL_TRAVEL_FACTOR, MAX_HORIZONTAL_SPEED);
        Vec3 velocity = horizontalDist < 1.0E-3D
                ? new Vec3(0.0D, vy, 0.0D)
                : new Vec3(dx / horizontalDist * vh, vy, dz / horizontalDist * vh);

        player.setDeltaMovement(velocity);
        player.hurtMarked = true;
        player.fallDistance = 0.0F;
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                LAUNCH_SLOW_FALL_TICKS, 0, false, false, true));
        grantFallGrace(player, FALL_GRACE_TICKS);
        FLIGHTS.put(player.getUUID(), new Flight(targetX, targetZ,
                player.server.getTickCount() + FLIGHT_TIMEOUT_TICKS));

        ServerLevel level = player.serverLevel();
        level.playSound(null, pad, EclipseSounds.EVENT_SKY_LAUNCH.get(),
                SoundSource.PLAYERS, 1.4F, 1.0F);
        level.sendParticles(ParticleTypes.CLOUD, player.getX(), player.getY(), player.getZ(),
                24, 0.6D, 0.2D, 0.6D, 0.12D);
        level.sendParticles(ParticleTypes.END_ROD, player.getX(), player.getY(), player.getZ(),
                16, 0.3D, 0.4D, 0.3D, 0.2D);
        // PH-WORLD (IDEAS-world #5): Photon contrail cue on the ENTITY lane — the client
        // attaches the ara ribbon to the launched player (entity death auto-cleans); the
        // CLOUD/END_ROD bursts above stay the photon-less baseline (Mode.LAYER).
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_SKY_LAUNCH, player, 0.0F, 0.0F, 128.0D);
        PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.8F, 18));
        player.displayClientMessage(ServerLang.tr(player, "eclipse.sky_launcher.launched"), true);
        EclipseMod.LOGGER.info("SkyLauncher: launched {} toward ({}, {}) (vy={}, vh={})",
                player.getGameProfile().getName(), (int) targetX, (int) targetZ, vy, vh);
    }

    /**
     * Smallest start speed whose simulated apex clears {@code rise}. Simulates vanilla's
     * exact per-tick vertical integration — with drag, {@code sqrt(2 g h)} undershoots
     * badly over a 100+ block climb.
     */
    private static double solveLaunchVy(double rise) {
        for (double v0 = 1.0D; v0 <= MAX_VERTICAL_SPEED; v0 += 0.25D) {
            double v = v0;
            double height = 0.0D;
            while (v > 0.0D) {
                height += v;
                v = (v - GRAVITY) * VERTICAL_DRAG;
            }
            if (height >= rise) {
                return v0;
            }
        }
        return MAX_VERTICAL_SPEED;
    }

    /** Mid-flight watch: one overshoot nudge on descent, cleanup on landing/timeout. */
    private static void tickFlights(MinecraftServer server) {
        long tick = server.getTickCount();
        Iterator<Map.Entry<UUID, Flight>> iterator = FLIGHTS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<UUID, Flight> entry = iterator.next();
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            Flight flight = entry.getValue();
            if (player == null || tick > flight.deadlineTick) {
                iterator.remove();
                continue;
            }
            if (player.onGround() || player.isInWater()) {
                player.fallDistance = 0.0F;
                iterator.remove();
                continue;
            }
            if (flight.nudged || player.getDeltaMovement().y >= 0.0D) {
                continue;
            }
            // Descending: nudge once if the current column already left the footprint.
            int bx = player.getBlockX();
            int bz = player.getBlockZ();
            if (!EndDiscGeometry.footprintContains(bx, bz)
                    && player.getY() > DiscProfile.END_DISC_SURFACE_Y - 24) {
                double dx = flight.targetX - player.getX();
                double dz = flight.targetZ - player.getZ();
                double dist = Math.sqrt(dx * dx + dz * dz);
                if (dist > 1.0E-3D) {
                    double vh = Math.min(dist / HORIZONTAL_TRAVEL_FACTOR, MAX_HORIZONTAL_SPEED);
                    Vec3 current = player.getDeltaMovement();
                    player.setDeltaMovement(dx / dist * vh, current.y, dz / dist * vh);
                    player.hurtMarked = true;
                }
                flight.nudged = true;
            }
        }
    }

    /** Return-pad use: slow-fall descent home — no ballistics, just a nudge off the rim. */
    private static void returnDescent(ServerPlayer player) {
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                RETURN_SLOW_FALL_TICKS, 0, false, false, true));
        grantFallGrace(player, FALL_GRACE_TICKS);
        Vec3 homeward = homewardDirection(player);
        player.setDeltaMovement(homeward.x * 1.3D, 0.6D, homeward.z * 1.3D);
        player.hurtMarked = true;
        ServerLevel level = player.serverLevel();
        level.playSound(null, player.blockPosition(), EclipseSounds.EVENT_SKY_LAUNCH.get(),
                SoundSource.PLAYERS, 0.9F, 1.3F);
        level.sendParticles(ParticleTypes.CLOUD, player.getX(), player.getY(), player.getZ(),
                12, 0.4D, 0.2D, 0.4D, 0.08D);
        player.displayClientMessage(ServerLang.tr(player, "eclipse.sky_launcher.descent"), true);
    }

    /** Horizontal unit vector from the player toward the mountain (or off-center fallback). */
    private static Vec3 homewardDirection(ServerPlayer player) {
        DiscMapData.Mountain mountain =
                DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        double dx;
        double dz;
        if (mountain != null) {
            dx = mountain.x() + 0.5D - player.getX();
            dz = mountain.z() + 0.5D - player.getZ();
        } else {
            dx = player.getX() - EndConfig.current().centerX();
            dz = player.getZ() - EndConfig.current().centerZ();
        }
        double length = Math.sqrt(dx * dx + dz * dz);
        return length < 1.0E-3D ? new Vec3(1.0D, 0.0D, 0.0D)
                : new Vec3(dx / length, 0.0D, dz / length);
    }

    // --- enqueue ---

    /** Enqueues both pads once the End disc has fully materialized. */
    private static void maybeEnqueue(MinecraftServer server) {
        if (!EndFightState.get(server).materializationComplete()) {
            return;
        }
        ServerLevel overworld = server.overworld();
        BlockPos launchAnchor = launchPadAnchor();
        if (launchAnchor != null) {
            enqueueIfNeeded(overworld, SITE_ID, launchAnchor, FOOTPRINT);
        }
        enqueueIfNeeded(overworld, RETURN_SITE_ID, returnPadAnchor(), 7);
    }

    private static void enqueueIfNeeded(ServerLevel overworld, String siteId, BlockPos anchor,
            int footprint) {
        if (StructurePendingRegistry.wasPlaced(siteId)) {
            return;
        }
        for (PendingSite pending : StructurePendingRegistry.pending()) {
            if (pending.siteId().equals(siteId)) {
                return;
            }
        }
        StructurePendingRegistry.enqueue(new PendingSite(siteId, SITE_ID,
                DiscProfile.OVERWORLD.name(), anchor, STAGE, footprint,
                overworld.getGameTime()));
    }

    /**
     * Launch pad anchor: {@value #PAD_OFFSET} blocks from the mountain summit toward
     * the disc center, at the LOWEST deterministic surface Y of the pad footprint
     * (SitePrep cuts the slope down to a terraced shelf — the observatory school).
     */
    @Nullable
    private static BlockPos launchPadAnchor() {
        DiscMapData.Mountain mountain =
                DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        if (mountain == null) {
            EclipseMod.LOGGER.warn("SkyLauncher skipped: no mountain authored in disc_map.json");
            return null;
        }
        EndConfig.Snapshot config = EndConfig.current();
        double dx = config.centerX() - mountain.x();
        double dz = config.centerZ() - mountain.z();
        double dist = Math.sqrt(dx * dx + dz * dz);
        int padX = mountain.x() + (dist < 1.0E-3D ? PAD_OFFSET
                : (int) Math.round(dx / dist * PAD_OFFSET));
        int padZ = mountain.z() + (dist < 1.0E-3D ? 0
                : (int) Math.round(dz / dist * PAD_OFFSET));
        int minY = Integer.MAX_VALUE;
        for (int ox = -HALF; ox <= HALF; ox++) {
            for (int oz = -HALF; oz <= HALF; oz++) {
                minY = Math.min(minY, DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD,
                        padX + ox, padZ + oz));
            }
        }
        return new BlockPos(padX, minY, padZ);
    }

    /** Return pad anchor: the disc-rim ring point facing the mountain, on the lens surface. */
    private static BlockPos returnPadAnchor() {
        EndConfig.Snapshot config = EndConfig.current();
        DiscMapData.Mountain mountain =
                DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        double dx = mountain != null ? mountain.x() - config.centerX() : 1.0D;
        double dz = mountain != null ? mountain.z() - config.centerZ() : 0.0D;
        double dist = Math.max(1.0E-3D, Math.sqrt(dx * dx + dz * dz));
        int x = config.centerX() + (int) Math.round(dx / dist * RETURN_PAD_RADIUS);
        int z = config.centerZ() + (int) Math.round(dz / dist * RETURN_PAD_RADIUS);
        return new BlockPos(x, EndDiscGeometry.surfaceYAt(x, z), z);
    }

    // --- placement ---

    private static void placeSite(ServerLevel level, PendingSite site, Runnable onComplete,
            java.util.function.Consumer<Throwable> onFailure) {
        if (RETURN_SITE_ID.equals(site.siteId())) {
            placeReturnPad(level, site, onComplete);
            return;
        }
        BlockPos anchor = site.anchor();
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                anchor.getX() - HALF, anchor.getZ() - HALF,
                anchor.getX() + HALF, anchor.getZ() + HALF, anchor);
        prepared.whenReady(() -> {
            BlockPos surface = new BlockPos(anchor.getX(), prepared.plateauY(), anchor.getZ());
            buildLaunchPad(level, surface);
            SitePrep.touchBounds(prepared, anchor.getX() - HALF, anchor.getZ() - HALF,
                    anchor.getX() + HALF, anchor.getZ() + HALF);
            SitePrep.finish(level, prepared);
            sweepPadEntities(level, surface);
            spawnPadInteraction(level, surface.above(), ENTITY_TAG, 3.4F, 3.0F);
            spawnWindShard(level, surface);
            LauncherData data = LauncherData.get(level.getServer().overworld());
            data.setLaunchPad(surface);
            EclipseMod.LOGGER.info("SkyLauncher wind altar built at {}", surface.toShortString());
            onComplete.run();
        }, onFailure);
    }

    /** Return pad stamps straight onto the disc lens — no SitePrep (no ground terrain). */
    private static void placeReturnPad(ServerLevel level, PendingSite site, Runnable onComplete) {
        BlockPos anchor = site.anchor();
        BudgetedBlockWriter.loadWithTicket(level, anchor.getX() >> 4, anchor.getZ() >> 4);
        int y0 = anchor.getY();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -3; dx <= 3; dx++) {
            for (int dz = -3; dz <= 3; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 > 9) {
                    continue;
                }
                BlockState floor = d2 >= 6 ? Blocks.PURPUR_BLOCK.defaultBlockState()
                        : Blocks.END_STONE_BRICKS.defaultBlockState();
                if (dx == 0 && dz == 0) {
                    floor = Blocks.AMETHYST_BLOCK.defaultBlockState();
                }
                set(level, cursor.set(anchor.getX() + dx, y0, anchor.getZ() + dz), floor);
                for (int dy = 1; dy <= 4; dy++) {
                    set(level, cursor.set(anchor.getX() + dx, y0 + dy, anchor.getZ() + dz),
                            Blocks.AIR.defaultBlockState());
                }
            }
        }
        for (int[] corner : new int[][] {{-2, -2}, {-2, 2}, {2, -2}, {2, 2}}) {
            set(level, cursor.set(anchor.getX() + corner[0], y0 + 1, anchor.getZ() + corner[1]),
                    Blocks.END_ROD.defaultBlockState());
        }
        sweepPadEntities(level, anchor);
        spawnPadInteraction(level, anchor.above(), RETURN_ENTITY_TAG, 3.0F, 3.0F);
        LauncherData data = LauncherData.get(level.getServer().overworld());
        data.setReturnPad(anchor);
        EclipseMod.LOGGER.info("SkyLauncher return pad built at {}", anchor.toShortString());
        onComplete.run();
    }

    /**
     * The wind altar around {@code surface} (ground level y0): polished-deepslate disc
     * with a calcite rim and hashed sculk inlays, a central two-block amethyst spire
     * crowned by a cluster, and four chain pylons with soul lanterns on the diagonals.
     */
    private static void buildLaunchPad(ServerLevel level, BlockPos surface) {
        int y0 = surface.getY();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 > 18) {
                    continue;
                }
                BlockState floor;
                if (d2 >= 13) {
                    floor = Blocks.CALCITE.defaultBlockState();
                } else if (FallbackBuilders.hash01(surface.getX() + dx, y0,
                        surface.getZ() + dz) < 0.18D) {
                    floor = Blocks.SCULK.defaultBlockState();
                } else {
                    floor = Blocks.POLISHED_DEEPSLATE.defaultBlockState();
                }
                set(level, cursor.set(surface.getX() + dx, y0, surface.getZ() + dz), floor);
                for (int dy = 1; dy <= 6; dy++) {
                    set(level, cursor.set(surface.getX() + dx, y0 + dy, surface.getZ() + dz),
                            Blocks.AIR.defaultBlockState());
                }
            }
        }
        // Central amethyst spire (the chime the charge-up plays actually has a source).
        set(level, cursor.set(surface.getX(), y0 + 1, surface.getZ()),
                Blocks.AMETHYST_BLOCK.defaultBlockState());
        set(level, cursor.set(surface.getX(), y0 + 2, surface.getZ()),
                Blocks.AMETHYST_BLOCK.defaultBlockState());
        set(level, cursor.set(surface.getX(), y0 + 3, surface.getZ()),
                Blocks.AMETHYST_CLUSTER.defaultBlockState());
        // Four chain pylons on the diagonals.
        for (int[] corner : new int[][] {{-3, -3}, {-3, 3}, {3, -3}, {3, 3}}) {
            int x = surface.getX() + corner[0];
            int z = surface.getZ() + corner[1];
            set(level, cursor.set(x, y0 + 1, z), Blocks.COBBLED_DEEPSLATE_WALL.defaultBlockState());
            set(level, cursor.set(x, y0 + 2, z), Blocks.CHAIN.defaultBlockState());
            set(level, cursor.set(x, y0 + 3, z), Blocks.CHAIN.defaultBlockState());
            set(level, cursor.set(x, y0 + 4, z), Blocks.SOUL_LANTERN.defaultBlockState());
        }
    }

    /** Silent write; SitePrep.finish() (or the small pad size) handles light/resend. */
    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
    }

    // --- interaction entities (XboxPortal NBT-spawn pattern) ---

    private static void sweepPadEntities(ServerLevel level, BlockPos base) {
        level.getChunk(base);
        List<Entity> pieces = level.getEntities((Entity) null, new AABB(base).inflate(4.0D, 6.0D, 4.0D),
                entity -> entity.getTags().contains(ENTITY_TAG)
                        || entity.getTags().contains(RETURN_ENTITY_TAG)
                        || entity.getTags().contains(SHARD_TAG));
        pieces.forEach(Entity::discard);
    }

    /** Interaction spawned via NBT — vanilla exposes no public width/height setters. */
    private static void spawnPadInteraction(ServerLevel level, BlockPos base, String tag,
            float width, float height) {
        CompoundTag nbt = new CompoundTag();
        nbt.putString("id", "minecraft:interaction");
        nbt.putFloat("width", width);
        nbt.putFloat("height", height);
        nbt.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(base.getX() + 0.5D));
        pos.add(DoubleTag.valueOf(base.getY()));
        pos.add(DoubleTag.valueOf(base.getZ() + 0.5D));
        nbt.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(nbt, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("SkyLauncher: could not create interaction entity at {}", base);
            return;
        }
        interaction.addTag(tag);
        level.addFreshEntity(interaction);
    }

    // --- ambient FX + interaction self-heal ---

    private static void ambientTick(ServerLevel level, long gameTime) {
        LauncherData data = LauncherData.get(level);
        ambientAt(level, data.launchPad(), ENTITY_TAG, gameTime);
        ambientAt(level, data.returnPad(), RETURN_ENTITY_TAG, gameTime);
    }

    private static void ambientAt(ServerLevel level, @Nullable BlockPos pad, String tag,
            long gameTime) {
        if (pad == null || !level.isLoaded(pad)) {
            return;
        }
        Vec3 center = Vec3.atCenterOf(pad.above());
        level.sendParticles(ParticleTypes.END_ROD, center.x, center.y + 0.6D, center.z,
                2, 0.9D, 0.5D, 0.9D, 0.005D);
        if (ENTITY_TAG.equals(tag)) {
            // BD-SHIP wind shard: one 20t interpolated window per ambient stride; the
            // 200t self-heal also covers the shard (a /kill'ed accent heals like a
            // /kill'ed interaction, born mid-pose off the same absolute clock).
            boolean shardAlive = animateWindShard(level, pad, gameTime);
            if (!shardAlive && gameTime % SELF_HEAL_TICKS == 0L) {
                spawnWindShard(level, pad);
                EclipseMod.LOGGER.info("SkyLauncher: re-spawned missing wind shard at {}",
                        pad.toShortString());
            }
        }
        if (gameTime % SELF_HEAL_TICKS == 0L) {
            // A /kill'ed interaction would silently brick the pad — respawn it.
            List<Entity> found = level.getEntities((Entity) null,
                    new AABB(pad).inflate(3.0D, 5.0D, 3.0D),
                    entity -> entity.getTags().contains(tag));
            if (found.isEmpty()) {
                boolean launcher = ENTITY_TAG.equals(tag);
                spawnPadInteraction(level, pad.above(), tag, launcher ? 3.4F : 3.0F, 3.0F);
                EclipseMod.LOGGER.info("SkyLauncher: re-spawned missing {} interaction at {}",
                        launcher ? "launch" : "return", pad.toShortString());
            }
        }
    }

    // --- wind shard accent (BD-SHIP) ---

    /**
     * The wind shard: one small amethyst-block display hovering above the spire cluster,
     * slowly yawing with a fixed tilt and a long sine bob. It persists with the world;
     * every pose is an absolute function of game time (SanctumOrbitals stateless-push
     * law), so a restart or a paused chunk glides back on track on the next push —
     * never a snap.
     */
    private static void spawnWindShard(ServerLevel level, BlockPos pad) {
        Display.BlockDisplay shard = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
        shard.setBlockState(Blocks.AMETHYST_BLOCK.defaultBlockState());
        shard.moveTo(pad.getX() + 0.5D, pad.getY() + SHARD_HOVER, pad.getZ() + 0.5D, 0.0F, 0.0F);
        shard.addTag(SHARD_TAG);
        shard.setTransformationInterpolationDelay(0);
        shard.setTransformationInterpolationDuration(0);
        shard.setTransformation(shardPose(level.getGameTime(), 0.0D));
        level.addFreshEntity(shard);
    }

    /** Ambient 20t window (≈28° of yaw — under the flattening law); returns shard presence. */
    private static boolean animateWindShard(ServerLevel level, BlockPos pad, long gameTime) {
        boolean found = false;
        for (Entity entity : level.getEntities((Entity) null,
                new AABB(pad).inflate(2.0D, 6.0D, 2.0D),
                candidate -> candidate.getTags().contains(SHARD_TAG))) {
            found = true;
            if (entity instanceof Display.BlockDisplay shard) {
                shard.setTransformationInterpolationDelay(0);
                shard.setTransformationInterpolationDuration(AMBIENT_TICKS);
                shard.setTransformation(shardPose(gameTime + AMBIENT_TICKS, 0.0D));
            }
        }
        return found;
    }

    /** Charge-stride 3t window with the capped spin-up boost riding the ambient clock. */
    private static void boostWindShard(ServerLevel level, BlockPos pad, double progress) {
        long gameTime = level.getGameTime();
        for (Entity entity : level.getEntities((Entity) null,
                new AABB(pad).inflate(2.0D, 6.0D, 2.0D),
                candidate -> candidate.getTags().contains(SHARD_TAG))) {
            if (entity instanceof Display.BlockDisplay shard) {
                shard.setTransformationInterpolationDelay(0);
                shard.setTransformationInterpolationDuration(3);
                shard.setTransformation(shardPose(gameTime + 3,
                        SHARD_CHARGE_BOOST_DEG * progress * progress));
            }
        }
    }

    /**
     * Absolute shard pose at {@code gameTime} (+ the charge spin-up's extra yaw):
     * center-pivot so the scaled block spins/bobs around its own center. Double math +
     * {@code IEEEremainder} keep old worlds' large game times from eating float precision.
     */
    private static Transformation shardPose(long gameTime, double boostDegrees) {
        double degrees = SHARD_YAW_DEG_PER_TICK * gameTime + boostDegrees;
        float yaw = (float) Math.toRadians(Math.IEEEremainder(degrees, 360.0D));
        float bob = (float) (SHARD_BOB_BLOCKS
                * Math.sin(gameTime * (Math.PI * 2.0D / SHARD_BOB_PERIOD)));
        Quaternionf rotation = new Quaternionf().rotationY(yaw)
                .rotateZ((float) Math.toRadians(SHARD_TILT_DEG));
        Vector3f half = new Vector3f(SHARD_SCALE * 0.5F, SHARD_SCALE * 0.5F, SHARD_SCALE * 0.5F);
        Vector3f translation = new Vector3f(0.0F, bob, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(SHARD_SCALE, SHARD_SCALE, SHARD_SCALE), new Quaternionf());
    }

    // --- pad anchors (own tiny SavedData; ObservatoryVersionData pattern) ---

    /**
     * Built pad anchors, persisted as {@code data/eclipse_sky_launcher.dat} in the
     * overworld storage (ambient FX + interaction self-heal need the positions after
     * the pending rows are consumed; plans_v3 §2.5 forbids new fields on shared state).
     */
    public static final class LauncherData extends SavedData {
        public static final String DATA_NAME = "eclipse_sky_launcher";

        private static final String TAG_LAUNCH_PAD = "launchPad";
        private static final String TAG_RETURN_PAD = "returnPad";

        @Nullable
        private BlockPos launchPad;
        @Nullable
        private BlockPos returnPad;

        public LauncherData() {}

        public static LauncherData get(ServerLevel overworld) {
            return overworld.getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(LauncherData::new, LauncherData::load),
                    DATA_NAME);
        }

        public static LauncherData load(CompoundTag tag, HolderLookup.Provider registries) {
            LauncherData data = new LauncherData();
            if (tag.contains(TAG_LAUNCH_PAD)) {
                data.launchPad = BlockPos.of(tag.getLong(TAG_LAUNCH_PAD));
            }
            if (tag.contains(TAG_RETURN_PAD)) {
                data.returnPad = BlockPos.of(tag.getLong(TAG_RETURN_PAD));
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            if (this.launchPad != null) {
                tag.putLong(TAG_LAUNCH_PAD, this.launchPad.asLong());
            }
            if (this.returnPad != null) {
                tag.putLong(TAG_RETURN_PAD, this.returnPad.asLong());
            }
            return tag;
        }

        @Nullable
        public BlockPos launchPad() {
            return this.launchPad;
        }

        public void setLaunchPad(@Nullable BlockPos pos) {
            if (!java.util.Objects.equals(this.launchPad, pos)) {
                this.launchPad = pos;
                setDirty();
            }
        }

        @Nullable
        public BlockPos returnPad() {
            return this.returnPad;
        }

        public void setReturnPad(@Nullable BlockPos pos) {
            if (!java.util.Objects.equals(this.returnPad, pos)) {
                this.returnPad = pos;
                setDirty();
            }
        }
    }
}
