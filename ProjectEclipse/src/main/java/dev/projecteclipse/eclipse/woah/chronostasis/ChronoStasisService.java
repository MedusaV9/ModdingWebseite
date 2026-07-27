package dev.projecteclipse.eclipse.woah.chronostasis;

import java.util.ArrayDeque;
import java.util.List;
import java.util.UUID;
import java.util.function.Predicate;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.progression.LandmarkDiscoveryService;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.woah.chronostasis.ChronoSceneBuilder.PoseParams;
import dev.projecteclipse.eclipse.woah.chronostasis.ChronoSceneBuilder.Prop;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-03 runtime brain (plan §3.2/§3.3): the slowness aura, the Chronosphere
 * interaction pad, the JOLT×5 → DISCHARGE → REWIND statemachine with budget-sliced pose
 * waves, the first-discharge reward and the restart watchdog.
 *
 * <p><b>Tick shape</b> ({@code ExpansionBorderFx.onServerTick} lineage): everything
 * early-outs when no player is within {@value #ACTIVE_RANGE} blocks and the scene is
 * FROZEN with an empty push queue — a static scene costs nothing. Pose waves are
 * enqueued per group and drained at ≤{@value #PUSH_BUDGET_PER_TICK} pushes/tick
 * (StormDebrisFx budget-slicing; poses are stateless functions, so a partially applied
 * wave is only a cosmetic stagger, never drift).</p>
 *
 * <p><b>Statemachine</b> (in-memory; only joltCount/discharges/rewardClaimed persist in
 * {@link ChronoStasisData}):
 * {@code FROZEN --click--> JOLT(60t) --> FROZEN [joltCount++]} and
 * {@code FROZEN --click at joltCount>=5--> DISCHARGE(200t) --> REWIND(60t) --> FROZEN}.
 * A restart mid-DISCHARGE simply boots FROZEN; the first reconcile pass pushes the base
 * pose over whatever half-flown poses were persisted (plan risk §11.4).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ChronoStasisService {
    /** Tag on the {@code minecraft:interaction} pad at the Chronosphere. */
    public static final String PAD_TAG = "eclipse_chrono_sphere_pad";
    /** Server systems sleep unless a player is inside this range of the center. */
    public static final int ACTIVE_RANGE = 96;
    /** Display pose pushes per tick during JOLT/DISCHARGE/REWIND waves (plan §3.5). */
    public static final int PUSH_BUDGET_PER_TICK = 80;

    static final int JOLT_TICKS = 60;
    static final int DISCHARGE_TICKS = 200;
    static final int REWIND_TICKS = 60;
    static final int JOLTS_FOR_DISCHARGE = 5;
    /** Repeat discharges are rate-limited (plan §7: no farm loop) — 5 minutes. */
    static final long DISCHARGE_COOLDOWN_TICKS = 6000L;
    /** Reconcile cadence while players are near (plan §3.1: ~2 min). */
    static final long RECONCILE_INTERVAL_TICKS = 2400L;
    /** Watchdog: a phase stuck longer than this snaps back to FROZEN (plan §3.3). */
    static final int WATCHDOG_TICKS = 600;

    public enum Phase { FROZEN, JOLT, DISCHARGE, REWIND }

    private record PushOp(int index, PoseParams params, int duration) {}

    // --- session state (rebuilt from SavedData + reconcile on every boot) ---
    @Nullable
    private static BlockPos center;
    @Nullable
    private static ChronoSceneBuilder.SceneState scene;
    private static Phase phase = Phase.FROZEN;
    private static int phaseTick;
    @Nullable
    private static UUID triggerPlayer;
    private static long cooldownUntilGameTime;
    private static long nextReconcileGameTime;
    private static boolean bootPoseHealed;
    private static final ArrayDeque<PushOp> PUSH_QUEUE = new ArrayDeque<>();

    private ChronoStasisService() {}

    // ------------------------------------------------------------------ lifecycle

    /** Called by {@link ChronoStasisSite} once the site exists (materialize or restore). */
    public static void onSitePlaced(ServerLevel level, BlockPos siteCenter) {
        center = siteCenter;
        scene = ChronoSceneBuilder.createState(
                ChronoStasisData.get(level.getServer()).sceneSeed());
        phase = Phase.FROZEN;
        phaseTick = 0;
        triggerPlayer = null;
        nextReconcileGameTime = 0L;
        bootPoseHealed = false;
        PUSH_QUEUE.clear();
    }

    /** Stage-rollback teardown: pad discarded, session state cleared. */
    public static void onSiteRemoved(ServerLevel level, BlockPos siteCenter) {
        for (Entity pad : padEntities(level, siteCenter)) {
            pad.discard();
        }
        center = null;
        scene = null;
        phase = Phase.FROZEN;
        PUSH_QUEUE.clear();
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        center = null;
        scene = null;
        phase = Phase.FROZEN;
        phaseTick = 0;
        triggerPlayer = null;
        cooldownUntilGameTime = 0L;
        PUSH_QUEUE.clear();
    }

    // ------------------------------------------------------------------ dev/status accessors

    public static Phase phase() {
        return phase;
    }

    @Nullable
    public static BlockPos center() {
        return center;
    }

    @Nullable
    public static ChronoSceneBuilder.SceneState scene() {
        return scene;
    }

    // ------------------------------------------------------------------ server tick

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        BlockPos siteCenter = center;
        ChronoSceneBuilder.SceneState state = scene;
        if (siteCenter == null || state == null) {
            return;
        }
        ServerLevel level = event.getServer().overworld();
        long gameTime = level.getGameTime();
        boolean playersNear = anyPlayerWithin(level, siteCenter, ACTIVE_RANGE);

        if (!state.reconciled()) {
            // Boot race (SanctumOrbitals lesson): defers itself until entity sections load.
            ChronoSceneBuilder.reconcile(level, state, siteCenter, PoseParams.frozen(gameTime), false);
            if (state.reconciled()) {
                healPad(level, siteCenter);
                nextReconcileGameTime = gameTime + RECONCILE_INTERVAL_TICKS;
                if (!bootPoseHealed) {
                    // Watchdog heal (plan risk §11.4): one base-pose wave fixes any poses
                    // persisted mid-DISCHARGE before the last shutdown.
                    bootPoseHealed = true;
                    enqueueWave(prop -> true, PoseParams.frozen(gameTime), 10);
                }
            }
        } else if (playersNear && gameTime >= nextReconcileGameTime) {
            nextReconcileGameTime = gameTime + RECONCILE_INTERVAL_TICKS;
            ChronoSceneBuilder.reconcile(level, state, siteCenter, PoseParams.frozen(gameTime), false);
            healPad(level, siteCenter);
        }
        if (state.pendingSpawns() > 0) {
            ChronoSceneBuilder.drainSpawns(level, state, siteCenter, PoseParams.frozen(gameTime),
                    ChronoSceneBuilder.SPAWN_BUDGET_PER_TICK);
        }

        // FROZEN with nobody near and nothing queued = truly free (plan §3.5).
        if (!playersNear && phase == Phase.FROZEN && PUSH_QUEUE.isEmpty()) {
            return;
        }

        if (playersNear) {
            tickAura(level, siteCenter, gameTime);
        }
        tickPhase(level, siteCenter, gameTime);
        // The scene's only continuous animation: the Chronosphere rings, 40 t keyframes
        // with LEAD (SanctumOrbitals transport), only with players in 64 blocks.
        if (phase == Phase.FROZEN && gameTime % 40L == 0L && anyPlayerWithin(level, siteCenter, 64)) {
            enqueueWave(ChronoStasisService::isRingProp, PoseParams.frozen(gameTime + 40L), 40);
        }
        drainPushes(state);
    }

    // ------------------------------------------------------------------ slowness aura

    /**
     * Plan §3.2: mobs get seamlessly re-applied Slowness IV + Mining Fatigue II (ambient,
     * particle-free — the effect wears off by itself after leaving); projectiles halve
     * their motion every tick (asymptotic freeze, no no-gravity leak). Players untouched.
     */
    private static void tickAura(ServerLevel level, BlockPos siteCenter, long gameTime) {
        AABB aura = new AABB(siteCenter).inflate(ChronoStasisSite.RADIUS, 20.0D, ChronoStasisSite.RADIUS);
        if (gameTime % 10L == 0L) {
            for (LivingEntity mob : level.getEntitiesOfClass(LivingEntity.class, aura,
                    entity -> !(entity instanceof Player))) {
                mob.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, 40, 4, true, false));
                mob.addEffect(new MobEffectInstance(MobEffects.DIG_SLOWDOWN, 40, 2, true, false));
            }
        }
        for (Projectile projectile : level.getEntitiesOfClass(Projectile.class, aura)) {
            projectile.setDeltaMovement(projectile.getDeltaMovement().scale(0.5D));
        }
    }

    // ------------------------------------------------------------------ interaction

    @SubscribeEvent
    static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getHand() != InteractionHand.MAIN_HAND
                || !(event.getEntity() instanceof ServerPlayer player)
                || player.isSpectator()) {
            return;
        }
        if (!event.getTarget().getTags().contains(PAD_TAG)) {
            return;
        }
        event.setCanceled(true);
        BlockPos siteCenter = center;
        if (siteCenter == null || scene == null || phase != Phase.FROZEN) {
            return; // re-click guard (SkyLauncher.beginCharge shape)
        }
        ServerLevel level = player.serverLevel();
        long gameTime = level.getGameTime();
        Vec3 sphere = ChronoSceneBuilder.sphereCenter(siteCenter);
        level.playSound(null, sphere.x, sphere.y, sphere.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.BLOCKS, 0.9F, 0.5F);
        ChronoStasisData data = ChronoStasisData.get(level.getServer());
        if (data.joltCount() >= JOLTS_FOR_DISCHARGE) {
            if (gameTime < cooldownUntilGameTime) {
                player.displayClientMessage(
                        ServerLang.tr(player, "eclipse.chrono.exhausted"), true);
                return;
            }
            beginDischarge(level, siteCenter, player, gameTime);
        } else {
            beginJolt(level, siteCenter, player, gameTime);
        }
    }

    /** The time-jolt (plan §3.3 JOLT): the whole scene slides 2 scene-ticks and back. */
    private static void beginJolt(ServerLevel level, BlockPos siteCenter, ServerPlayer player,
            long gameTime) {
        ChronoStasisData data = ChronoStasisData.get(level.getServer());
        data.setJoltCount(data.joltCount() + 1);
        phase = Phase.JOLT;
        phaseTick = 0;
        triggerPlayer = player.getUUID();
        Vec3 sphere = ChronoSceneBuilder.sphereCenter(siteCenter);
        // "Chrono woom" layered from existing assets (plan §6 recipe; sounds.json row
        // deferred — see docs/plans_v3/wiring/woah_chrono_sounds.json).
        level.playSound(null, sphere.x, sphere.y, sphere.z, EclipseSounds.EVENT_SUBMERGE.get(),
                SoundSource.AMBIENT, 1.0F, 0.45F);
        level.playSound(null, sphere.x, sphere.y, sphere.z, EclipseSounds.EVENT_BORDER_GLITCH.get(),
                SoundSource.AMBIENT, 0.3F, 0.35F);
        PacketDistributor.sendToPlayersNear(level, null, sphere.x, sphere.y, sphere.z, 128.0D,
                S2CShakePayload.shake(0.18F, 14));
        FxPayloads.sendFxEvent(level, ChronoCues.CUE_CHRONO_JOLT, sphere,
                data.joltCount(), 0.0F, 96.0D);
        player.displayClientMessage(
                ServerLang.tr(player, "eclipse.chrono.jolt_n", data.joltCount(),
                        JOLTS_FOR_DISCHARGE), true);
        enqueueWave(prop -> true, PoseParams.jolt(2.0D, gameTime), 12);
    }

    /** The fifth click (plan §3.3 DISCHARGE): the frozen instant resolves, then rewinds. */
    private static void beginDischarge(ServerLevel level, BlockPos siteCenter, ServerPlayer player,
            long gameTime) {
        phase = Phase.DISCHARGE;
        phaseTick = 0;
        triggerPlayer = player.getUUID();
        cooldownUntilGameTime = gameTime + DISCHARGE_COOLDOWN_TICKS;
        sendCaptionNear(level, siteCenter, "eclipse.caption.chrono.discharge", 70,
                S2CCaptionPayload.STYLE_WHISPER, 128.0D);
    }

    // ------------------------------------------------------------------ statemachine

    private static void tickPhase(ServerLevel level, BlockPos siteCenter, long gameTime) {
        if (phase == Phase.FROZEN) {
            return;
        }
        phaseTick++;
        if (phaseTick > WATCHDOG_TICKS) {
            EclipseMod.LOGGER.warn("ChronoStasisService: {} watchdog fired — snapping to FROZEN", phase);
            phase = Phase.FROZEN;
            PUSH_QUEUE.clear();
            enqueueWave(prop -> true, PoseParams.frozen(gameTime), 10);
            return;
        }
        switch (phase) {
            case JOLT -> {
                if (phaseTick == 40) {
                    // Re-freeze slower than the jolt — reads as viscous settling.
                    enqueueWave(prop -> true, PoseParams.frozen(gameTime + 20L), 20);
                }
                if (phaseTick >= JOLT_TICKS) {
                    phase = Phase.FROZEN;
                }
            }
            case DISCHARGE -> tickDischarge(level, siteCenter, gameTime);
            case REWIND -> {
                if (phaseTick >= REWIND_TICKS) {
                    phase = Phase.FROZEN;
                    ChronoStasisData.get(level.getServer()).setJoltCount(0);
                }
            }
            default -> {}
        }
    }

    private static void tickDischarge(ServerLevel level, BlockPos siteCenter, long gameTime) {
        Vec3 sphere = ChronoSceneBuilder.sphereCenter(siteCenter);
        switch (phaseTick) {
            case 20 -> {
                // The bolt discharges for real: vanilla flash + thunder, displays sink to 0.
                LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(level);
                if (bolt != null) {
                    Vec3 foot = ChronoSceneBuilder.groupAnchor(
                            ChronoSceneBuilder.Group.BOLT, siteCenter);
                    bolt.moveTo(foot.x, foot.y, foot.z);
                    bolt.setVisualOnly(true);
                    level.addFreshEntity(bolt);
                }
                playDischargeLayers(level, sphere);
                enqueueWave(prop -> prop.group() == ChronoSceneBuilder.Group.BOLT,
                        dischargeParams(1.0D, 0.0D, 0.0D, 0.0D, gameTime), 6);
            }
            case 30 -> {
                // The explosion detonates to completion (pose-only; Kulisse law, no explode).
                Vec3 blast = ChronoSceneBuilder.groupAnchor(
                        ChronoSceneBuilder.Group.BLAST, siteCenter);
                FxPayloads.sendFxEvent(level, ChronoCues.CUE_CHRONO_DISCHARGE, blast,
                        1.0F, 0.0F, 128.0D);
                level.playSound(null, blast.x, blast.y, blast.z,
                        EclipseSounds.EVENT_STORM_BURST.get(), SoundSource.AMBIENT, 1.0F, 0.8F);
                PacketDistributor.sendToPlayersNear(level, null, blast.x, blast.y, blast.z, 128.0D,
                        S2CShakePayload.shake(0.35F, 22));
                enqueueWave(prop -> prop.group() == ChronoSceneBuilder.Group.BLAST,
                        dischargeParams(1.0D, 1.0D, 0.0D, 0.0D, gameTime), 30);
            }
            case 40 -> enqueueWave(prop -> prop.group() == ChronoSceneBuilder.Group.TOWER,
                    dischargeParams(1.0D, 1.0D, 1.0D, 0.0D, gameTime), 80);
            case 100, 115 -> {
                // Debris-impact dust puffs (a < 0 = dust variant, see ChronoCues contract).
                Vec3 towerGround = ChronoSceneBuilder.groupAnchor(
                        ChronoSceneBuilder.Group.TOWER, siteCenter).subtract(0.0D, 8.0D, 0.0D);
                Vec3 impact = towerGround.add(phaseTick == 100 ? -3.5D : -6.0D, 0.0D,
                        phaseTick == 100 ? 3.0D : 5.5D);
                FxPayloads.sendFxEvent(level, ChronoCues.CUE_CHRONO_JOLT, impact,
                        -1.0F, 0.0F, 96.0D);
            }
            case 120 -> grantReward(level, siteCenter, sphere);
            default -> {}
        }
        // Sphere rings accelerate through the whole resolution (2-tick→10-tick cadence).
        if (phaseTick % 10 == 0 && phaseTick <= 120) {
            double sphereT = Math.min(1.0D, phaseTick / 120.0D);
            enqueueWave(ChronoStasisService::isRingProp,
                    dischargeParams(1.0D, 1.0D, phaseTick >= 40 ? 1.0D : 0.0D, sphereT, gameTime), 10);
        }
        if (phaseTick >= DISCHARGE_TICKS) {
            phase = Phase.REWIND;
            phaseTick = 0;
            // The actual woah moment: everything visibly rewinds into the base pose.
            enqueueWave(prop -> true, PoseParams.frozen(gameTime + 40L), 40);
            Vec3 rewindSphere = ChronoSceneBuilder.sphereCenter(siteCenter);
            level.playSound(null, rewindSphere.x, rewindSphere.y, rewindSphere.z,
                    EclipseSounds.EVENT_EMERGE.get(), SoundSource.AMBIENT, 0.9F, 0.55F);
        }
    }

    /** Layered "chrono discharge" crack from existing assets (plan §6 recipe). */
    private static void playDischargeLayers(ServerLevel level, Vec3 pos) {
        level.playSound(null, pos.x, pos.y, pos.z, EclipseSounds.UI_HEART_SHATTER.get(),
                SoundSource.AMBIENT, 1.0F, 0.3F);
        level.playSound(null, pos.x, pos.y, pos.z, EclipseSounds.EVENT_SUBMERGE.get(),
                SoundSource.AMBIENT, 0.9F, 0.4F);
        level.playSound(null, pos.x, pos.y, pos.z, EclipseSounds.EVENT_EMERGE.get(),
                SoundSource.AMBIENT, 0.8F, 0.5F);
    }

    /**
     * First-discharge trophy + shards (plan §7). The claim flag is persisted BEFORE the
     * item spawns (plan risk §11.4 — a crash between the two must not re-drop the core).
     */
    private static void grantReward(ServerLevel level, BlockPos siteCenter, Vec3 sphere) {
        ChronoStasisData data = ChronoStasisData.get(level.getServer());
        data.incrementDischarges();
        ServerPlayer player = triggerPlayer == null ? null
                : level.getServer().getPlayerList().getPlayer(triggerPlayer);
        if (!data.rewardClaimed()) {
            data.setRewardClaimed(true);
            ItemEntity core = new ItemEntity(level, sphere.x, sphere.y - 1.5D, sphere.z,
                    new ItemStack(ChronoStasisItems.CHRONO_CORE.get()));
            if (player != null) {
                Vec3 toward = player.position().add(0.0D, 1.0D, 0.0D)
                        .subtract(sphere.x, sphere.y - 1.5D, sphere.z).normalize().scale(0.25D);
                core.setDeltaMovement(toward.x, Math.max(0.1D, toward.y), toward.z);
            }
            level.addFreshEntity(core);
            if (player != null) {
                ShardEconomy.addShards(player, 64, true);
            }
            LandmarkDiscoveryService.discover(level.getServer(), ChronoStasisSite.STRUCTURE_ID);
            EclipseMod.LOGGER.info("ChronoStasisService: first discharge reward granted");
        } else if (player != null) {
            ShardEconomy.addShards(player, 8, true);
        }
    }

    // ------------------------------------------------------------------ push waves

    private static boolean isRingProp(Prop prop) {
        return prop.group() == ChronoSceneBuilder.Group.SPHERE
                && prop.kind() == ChronoSceneBuilder.KIND_SPHERE_RING;
    }

    /** Group-envelope params for discharge waves ({@code sceneTick} pinned to 0). */
    private static PoseParams dischargeParams(double boltT, double blastT, double towerT,
            double sphereT, long gameTime) {
        return new PoseParams(0.0D, boltT, blastT, towerT, sphereT, gameTime);
    }

    private static void enqueueWave(Predicate<Prop> filter, PoseParams params, int duration) {
        ChronoSceneBuilder.SceneState state = scene;
        if (state == null) {
            return;
        }
        List<Prop> props = state.props();
        for (int i = 0; i < props.size(); i++) {
            if (filter.test(props.get(i))) {
                PUSH_QUEUE.add(new PushOp(i, params, duration));
            }
        }
    }

    private static void drainPushes(ChronoSceneBuilder.SceneState state) {
        int budget = PUSH_BUDGET_PER_TICK;
        while (budget > 0 && !PUSH_QUEUE.isEmpty()) {
            PushOp op = PUSH_QUEUE.poll();
            Display.BlockDisplay display = state.display(op.index());
            if (display == null || display.isRemoved()) {
                continue; // reconcile will respawn it at the current base pose
            }
            ChronoSceneBuilder.pushPose(display, state.props().get(op.index()),
                    op.params(), op.duration());
            budget--;
        }
    }

    // ------------------------------------------------------------------ interaction pad

    /** Adopt-one/discard-extras/respawn-missing for the sphere pad (reconcile sidecar). */
    private static void healPad(ServerLevel level, BlockPos siteCenter) {
        List<? extends Entity> pads = padEntities(level, siteCenter);
        if (pads.isEmpty()) {
            spawnPad(level, ChronoSceneBuilder.sphereCenter(siteCenter));
        } else {
            for (int i = 1; i < pads.size(); i++) {
                pads.get(i).discard();
            }
        }
    }

    private static List<? extends Entity> padEntities(ServerLevel level, BlockPos siteCenter) {
        Vec3 sphere = ChronoSceneBuilder.sphereCenter(siteCenter);
        AABB box = new AABB(BlockPos.containing(sphere)).inflate(5.0D, 6.0D, 5.0D);
        return level.getEntities((Entity) null, box,
                entity -> entity.getTags().contains(PAD_TAG));
    }

    /** SkyLauncher.spawnPadInteraction NBT recipe — no public width/height setters. */
    private static void spawnPad(ServerLevel level, Vec3 sphere) {
        CompoundTag nbt = new CompoundTag();
        nbt.putString("id", "minecraft:interaction");
        nbt.putFloat("width", 2.8F);
        nbt.putFloat("height", 2.8F);
        nbt.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(sphere.x));
        pos.add(DoubleTag.valueOf(sphere.y - 1.4D));
        pos.add(DoubleTag.valueOf(sphere.z));
        nbt.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(nbt, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("ChronoStasisService: could not create sphere pad");
            return;
        }
        interaction.addTag(PAD_TAG);
        level.addFreshEntity(interaction);
    }

    // ------------------------------------------------------------------ helpers

    private static boolean anyPlayerWithin(ServerLevel level, BlockPos siteCenter, double range) {
        Vec3 c = Vec3.atCenterOf(siteCenter);
        double rangeSq = range * range;
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(c) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    private static void sendCaptionNear(ServerLevel level, BlockPos siteCenter, String key,
            int ticks, int style, double range) {
        Vec3 c = Vec3.atCenterOf(siteCenter);
        double rangeSq = range * range;
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(c) <= rangeSq) {
                PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(key, ticks, style));
            }
        }
    }

    // ------------------------------------------------------------------ dev hooks

    /** Dev: force a jolt as if clicked (optionally pinning the persisted counter first). */
    public static boolean devJolt(ServerLevel level, ServerPlayer player, int setCountOrNegative) {
        BlockPos siteCenter = center;
        if (siteCenter == null || scene == null || phase != Phase.FROZEN) {
            return false;
        }
        if (setCountOrNegative >= 0) {
            ChronoStasisData.get(level.getServer()).setJoltCount(setCountOrNegative);
        }
        beginJolt(level, siteCenter, player, level.getGameTime());
        return true;
    }

    /** Dev: force DISCHARGE, ignoring joltCount and the repeat cooldown. */
    public static boolean devDischarge(ServerLevel level, ServerPlayer player) {
        BlockPos siteCenter = center;
        if (siteCenter == null || scene == null || phase != Phase.FROZEN) {
            return false;
        }
        cooldownUntilGameTime = 0L;
        beginDischarge(level, siteCenter, player, level.getGameTime());
        return true;
    }

    /** Dev: FROZEN + joltCount 0 + discard all props + deterministic rebuild + fresh pad. */
    public static int devReset(ServerLevel level) {
        BlockPos siteCenter = center;
        ChronoSceneBuilder.SceneState state = scene;
        if (siteCenter == null || state == null) {
            return -1;
        }
        phase = Phase.FROZEN;
        phaseTick = 0;
        PUSH_QUEUE.clear();
        ChronoStasisData data = ChronoStasisData.get(level.getServer());
        data.setJoltCount(0);
        long gameTime = level.getGameTime();
        ChronoSceneBuilder.reconcile(level, state, siteCenter, PoseParams.frozen(gameTime), true);
        healPad(level, siteCenter);
        FxAnchors.set(FxAnchors.CHRONO_CENTER, level, ChronoSceneBuilder.sphereCenter(siteCenter));
        return state.props().size();
    }
}
