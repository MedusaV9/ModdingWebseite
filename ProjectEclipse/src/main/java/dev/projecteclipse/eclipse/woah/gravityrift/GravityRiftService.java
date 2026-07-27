package dev.projecteclipse.eclipse.woah.gravityrift;

import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.AttackEntityEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-02 lifecycle + gameplay tick owner (plan §3): stage-4 enqueue via the
 * {@code WorldStageService} listener (the {@code ChronoStasisSite} school — the landmark
 * row is frozen in {@code DiscMapDefaults}, this class only reads it), the low-G zone
 * attribute pass, the {@value GravityRiftZone#PULSE_PERIOD_TICKS}-tick gravitational
 * pulse on its stateless absolute raster, the heart-hit
 * {@value GravityRiftZone#INVERT_TOTAL_TICKS}-tick inversion, item/XP updrift, the
 * buried-sentinel self-heal and the payload sync.
 *
 * <p><b>Verified low-G law (plan §3.2)</b>: transient attribute modifiers on entry,
 * removed on exit — {@code GRAVITY ×0.30} ({@code ADD_MULTIPLIED_TOTAL −0.70}),
 * {@code JUMP_STRENGTH ×1.35} ({@code +0.35}), {@code SAFE_FALL_DISTANCE +20},
 * {@code FALL_DAMAGE_MULTIPLIER ×0.40} ({@code −0.60}). Jump apex under those numbers
 * ≈ 6.7 blocks — the parkour's +5/+6 rises are floaty sprint jumps, the two +7/long
 * hero gaps need the pulse launch (apex ≈ 17 blocks at launch vy 0.9). Membership is
 * re-derived every {@value #ZONE_PASS_TICKS} t from {@code getModifier(id) != null}
 * vs. {@link GravityRiftZone#inZone} — respawn/logout wipe transient modifiers, so
 * there is no session set to leak (the {@code ContractModifierService} idempotence
 * law).</p>
 *
 * <p><b>Server tick budget (plan §3.7)</b>: with no player within
 * {@value #ACTIVE_RADIUS} blocks of the anchor (cached, re-checked every
 * {@value #ACTIVE_CHECK_TICKS} t) everything early-outs except one long comparison
 * (the inversion-end broadcast, which must fire even with everyone far away).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GravityRiftService {
    /** Tag on the heart's {@code minecraft:interaction} hitbox. */
    public static final String HEART_TAG = "eclipse_gravity_heart";

    /** Attribute modifier ids (one per attribute — addOrUpdate keeps them idempotent). */
    private static final ResourceLocation LOW_G_GRAVITY_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "woah_gravity_low_g");
    private static final ResourceLocation LOW_G_JUMP_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "woah_gravity_jump");
    private static final ResourceLocation LOW_G_SAFE_FALL_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "woah_gravity_safe_fall");
    private static final ResourceLocation LOW_G_FALL_DAMAGE_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "woah_gravity_fall_damage");

    /** GRAVITY ×0.30 → g = 0.024 blocks/t² (the "moon jump" base). */
    private static final double GRAVITY_MULTIPLIER = -0.70D;
    /** JUMP_STRENGTH ×1.35 → v₀ = 0.567 (jump apex ≈ 6.7 blocks under low-G). */
    private static final double JUMP_MULTIPLIER = 0.35D;
    private static final double SAFE_FALL_BONUS = 20.0D;
    private static final double FALL_DAMAGE_MULTIPLIER = -0.60D;

    /** Pulse launch impulse (vy; apex ≈ 17 blocks under zone gravity — the hero gaps). */
    private static final double PULSE_LAUNCH_VY = 0.9D;
    /** Item/XP updrift terminal vy and per-pass acceleration. */
    private static final double DRIFT_MAX_VY = 0.06D;
    private static final double DRIFT_ACCEL = 0.05D;
    /** Drift ceiling above the crater floor (items hover, never rocket out the top). */
    private static final double DRIFT_CEILING = 24.0D;

    /** Zone membership + inversion-levitation pass cadence. */
    private static final int ZONE_PASS_TICKS = 5;
    /** Item/XP drift pass cadence. */
    private static final int DRIFT_PASS_TICKS = 5;
    /** Activity gate radius + its cache cadence (plan §3.7). */
    private static final int ACTIVE_RADIUS = 128;
    private static final int ACTIVE_CHECK_TICKS = 20;
    /** Self-heal cadence (sentinel probe + heart hitbox respawn). */
    private static final int SELF_HEAL_TICKS = 200;

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    /** Cached plan-§3.7 activity gate. */
    private static boolean playersNear;
    private static long nextActiveCheck = Long.MIN_VALUE;
    /** Guards the direct self-heal re-materialize (never two carves in flight). */
    private static boolean healInFlight;
    /** The last gameTime an inversion-end broadcast fired for (dedup). */
    private static long resolvedInvertEnd = Long.MIN_VALUE;

    private GravityRiftService() {}

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(GravityRiftService::onStageTerrainComplete);
            EclipseMod.LOGGER.info("GravityRift registered as world-stage listener (stage {})",
                    GravityRiftZone.STAGE);
        }
        StructurePendingRegistry.registerAsyncPlacer(GravityRiftZone.STRUCTURE_ID,
                (level, pending, complete, failure) ->
                        GravityRiftBuilder.materialize(level, complete, failure));
    }

    /** Boot catch-up: an already-built rift re-arms its hitbox; a missed stage enqueues. */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onServerStarted(ServerStartedEvent event) {
        ServerLevel overworld = event.getServer().overworld();
        GravityRiftState state = GravityRiftState.get(event.getServer());
        if (state.built() && state.anchor() != null) {
            EclipseMod.LOGGER.info("GravityRift: restored built site at {}",
                    state.anchor().toShortString());
            return; // heart hitbox re-arms via the self-heal pass once a player is near
        }
        if (WorldStageService.stage(event.getServer(), DiscProfile.OVERWORLD)
                >= GravityRiftZone.STAGE) {
            enqueueIfNeeded(overworld);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        playersNear = false;
        nextActiveCheck = Long.MIN_VALUE;
        healInFlight = false;
        resolvedInvertEnd = Long.MIN_VALUE;
    }

    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile != DiscProfile.OVERWORLD || toStage <= fromStage) {
            return; // the rift is permanent — no rollback teardown (plan §2.3)
        }
        if (GravityRiftZone.STAGE > toStage || GravityRiftZone.STAGE <= fromStage) {
            return;
        }
        enqueueIfNeeded(level);
    }

    /** Dedup'd enqueue — also the {@code /dev woah gravity build} entry point. */
    public static void enqueueIfNeeded(ServerLevel overworld) {
        if (StructurePendingRegistry.wasPlaced(GravityRiftZone.STRUCTURE_ID)) {
            return;
        }
        for (PendingSite pending : StructurePendingRegistry.pending()) {
            if (pending.siteId().equals(GravityRiftZone.STRUCTURE_ID)) {
                return;
            }
        }
        BlockPos center = GravityRiftZone.surfaceCenter(overworld);
        StructurePendingRegistry.enqueue(new PendingSite(GravityRiftZone.STRUCTURE_ID,
                GravityRiftZone.STRUCTURE_ID, DiscProfile.OVERWORLD.name(), center,
                GravityRiftZone.STAGE, (int) Math.ceil(GravityRiftZone.RIM_OUTER_RADIUS) * 2,
                overworld.getGameTime()));
    }

    /** Builder hand-off after the carve: heart hitbox + payload broadcast. */
    static void onSiteBuilt(ServerLevel level, BlockPos anchor) {
        spawnHeartInteraction(level, anchor);
        GravityRiftPayloads.syncAll(level);
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        ServerLevel overworld = server.overworld();
        GravityRiftState state = GravityRiftState.get(server);
        BlockPos anchor = state.anchor();
        if (!state.built() || anchor == null) {
            return;
        }
        long gameTime = overworld.getGameTime();
        // The one always-on check: the inversion-end broadcast must fire even with
        // everyone far away (a logged-in far player still renders the lens ramp).
        long invertUntil = state.invertUntilGameTime();
        if (invertUntil != 0L && gameTime >= invertUntil && resolvedInvertEnd != invertUntil) {
            resolvedInvertEnd = invertUntil;
            state.setInvertUntilGameTime(0L);
            Vec3 heart = heartCenter(anchor);
            FxPayloads.sendFxEvent(overworld, GravityRiftCues.CUE_GRAVITY_RESOLVE, heart,
                    0.0F, 0.0F, 128.0D);
            overworld.playSound(null, heart.x, heart.y, heart.z,
                    EclipseSounds.EVENT_RIFT_RESOLVE.get(), SoundSource.AMBIENT, 1.0F, 1.0F);
            GravityRiftPayloads.syncAll(overworld);
        }
        if (gameTime >= nextActiveCheck) {
            nextActiveCheck = gameTime + ACTIVE_CHECK_TICKS;
            playersNear = anyPlayerNear(overworld, anchor);
        }
        if (!playersNear) {
            return;
        }
        if (gameTime % ZONE_PASS_TICKS == 0L) {
            zonePass(overworld, state, anchor, gameTime);
        }
        tickPulse(overworld, state, anchor, gameTime);
        if (gameTime % DRIFT_PASS_TICKS == 0L) {
            driftPass(overworld, anchor);
        }
        if (gameTime % SELF_HEAL_TICKS == 0L) {
            selfHeal(overworld, state, anchor);
        }
    }

    // ------------------------------------------------------------------ low-G zone (§3.2)

    /**
     * Re-derives zone membership for every overworld player: modifiers on for players
     * inside the cylinder, off for carriers outside it. During the inversion's active
     * window, in-zone players additionally carry a short self-expiring Levitation
     * (vanilla's own "gravity points up" — fully client-predicted, no motion packets).
     */
    private static void zonePass(ServerLevel overworld, GravityRiftState state, BlockPos anchor,
            long gameTime) {
        long invertUntil = state.invertUntilGameTime();
        long invertStart = invertUntil - GravityRiftZone.INVERT_TOTAL_TICKS;
        boolean invertActive = invertUntil != 0L && gameTime >= invertStart
                && gameTime < invertStart + GravityRiftZone.INVERT_ACTIVE_TICKS;
        boolean invertGlide = invertUntil != 0L && !invertActive && gameTime < invertUntil;
        for (ServerPlayer player : overworld.players()) {
            boolean inZone = !player.isSpectator()
                    && GravityRiftZone.inZone(anchor, player.getX(), player.getY(), player.getZ());
            applyLowG(player, inZone);
            if (inZone && invertActive) {
                // +5 t overlap over the pass cadence — expires by itself at window end.
                player.addEffect(new MobEffectInstance(MobEffects.LEVITATION,
                        ZONE_PASS_TICKS + 5, 0, false, false, true));
                player.fallDistance = 0.0F;
            } else if (inZone && invertGlide) {
                player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                        ZONE_PASS_TICKS + 15, 0, false, false, true));
            }
        }
    }

    /** Idempotent per-player modifier toggle (the ContractModifierService recipe). */
    private static void applyLowG(ServerPlayer player, boolean inZone) {
        AttributeInstance gravity = player.getAttribute(Attributes.GRAVITY);
        AttributeInstance jump = player.getAttribute(Attributes.JUMP_STRENGTH);
        AttributeInstance safeFall = player.getAttribute(Attributes.SAFE_FALL_DISTANCE);
        AttributeInstance fallDamage = player.getAttribute(Attributes.FALL_DAMAGE_MULTIPLIER);
        if (gravity == null || jump == null || safeFall == null || fallDamage == null) {
            return;
        }
        boolean carrying = gravity.getModifier(LOW_G_GRAVITY_ID) != null;
        if (inZone && !carrying) {
            gravity.addOrUpdateTransientModifier(new AttributeModifier(LOW_G_GRAVITY_ID,
                    GRAVITY_MULTIPLIER, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
            jump.addOrUpdateTransientModifier(new AttributeModifier(LOW_G_JUMP_ID,
                    JUMP_MULTIPLIER, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
            safeFall.addOrUpdateTransientModifier(new AttributeModifier(LOW_G_SAFE_FALL_ID,
                    SAFE_FALL_BONUS, AttributeModifier.Operation.ADD_VALUE));
            fallDamage.addOrUpdateTransientModifier(new AttributeModifier(LOW_G_FALL_DAMAGE_ID,
                    FALL_DAMAGE_MULTIPLIER, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
        } else if (!inZone && carrying) {
            gravity.removeModifier(LOW_G_GRAVITY_ID);
            jump.removeModifier(LOW_G_JUMP_ID);
            safeFall.removeModifier(LOW_G_SAFE_FALL_ID);
            fallDamage.removeModifier(LOW_G_FALL_DAMAGE_ID);
        }
    }

    // ------------------------------------------------------------------ pulse (§3.1)

    /**
     * The 45 s beat on its absolute raster: at {@code phase == PERIOD − TELEGRAPH} the
     * staged pulse cue + drone telegraph fire (the asset ramps into the beat); at
     * {@code phase == 0} everything loose in the zone launches. Stateless — a restart
     * lands exactly on the same raster, and the client lens/FX compute the identical
     * phase locally from the synced anchor.
     */
    private static void tickPulse(ServerLevel overworld, GravityRiftState state, BlockPos anchor,
            long gameTime) {
        int offset = GravityRiftZone.pulsePhaseOffset(anchor);
        long phase = Math.floorMod(gameTime - offset, (long) GravityRiftZone.PULSE_PERIOD_TICKS);
        Vec3 heart = heartCenter(anchor);
        if (phase == GravityRiftZone.PULSE_PERIOD_TICKS - GravityRiftZone.PULSE_TELEGRAPH_TICKS) {
            FxPayloads.sendFxEvent(overworld, GravityRiftCues.CUE_GRAVITY_PULSE, heart,
                    0.0F, 0.0F, 256.0D);
            overworld.playSound(null, heart.x, heart.y, heart.z,
                    EclipseSounds.EVENT_RIFT_DRONE.get(), SoundSource.AMBIENT, 1.2F, 0.8F);
            return;
        }
        if (phase != 0L) {
            return;
        }
        // The launch beat. Suppressed during an inversion (levitation already owns
        // vertical motion; a stacked launch would fling players out the zone top).
        overworld.playSound(null, heart.x, heart.y, heart.z,
                EclipseSounds.EVENT_RIFT_THUD.get(), SoundSource.AMBIENT, 1.4F, 0.9F);
        if (state.invertUntilGameTime() != 0L && gameTime < state.invertUntilGameTime()) {
            return;
        }
        for (ServerPlayer player : overworld.players()) {
            if (player.isSpectator()
                    || !GravityRiftZone.inZone(anchor, player.getX(), player.getY(), player.getZ())) {
                continue;
            }
            Vec3 motion = player.getDeltaMovement();
            player.setDeltaMovement(motion.x, Math.max(motion.y, PULSE_LAUNCH_VY), motion.z);
            player.hurtMarked = true; // client-authoritative motion needs the resync flag
            player.fallDistance = 0.0F;
            PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.35F, 14));
        }
        AABB zone = zoneBox(anchor);
        for (ItemEntity item : overworld.getEntitiesOfClass(ItemEntity.class, zone)) {
            item.setDeltaMovement(item.getDeltaMovement().add(0.0D, 0.45D, 0.0D));
            item.hasImpulse = true;
        }
        for (ExperienceOrb orb : overworld.getEntitiesOfClass(ExperienceOrb.class, zone)) {
            orb.setDeltaMovement(orb.getDeltaMovement().add(0.0D, 0.45D, 0.0D));
            orb.hasImpulse = true;
        }
    }

    // ------------------------------------------------------------------ item/XP drift (§3.2)

    /**
     * Loose items and XP orbs inside the zone drift UPWARD (gravity cancel + gentle
     * lift toward {@value #DRIFT_MAX_VY}), capped {@value #DRIFT_CEILING} blocks over
     * the floor so drops hover reachably instead of escaping the bowl. A deterministic
     * per-entity swirl keeps the cloud alive without RandomSource.
     */
    private static void driftPass(ServerLevel overworld, BlockPos anchor) {
        AABB zone = zoneBox(anchor);
        double ceiling = anchor.getY() + DRIFT_CEILING;
        for (ItemEntity item : overworld.getEntitiesOfClass(ItemEntity.class, zone)) {
            driftEntity(item, anchor, ceiling);
        }
        for (ExperienceOrb orb : overworld.getEntitiesOfClass(ExperienceOrb.class, zone)) {
            driftEntity(orb, anchor, ceiling);
        }
    }

    private static void driftEntity(Entity entity, BlockPos anchor, double ceiling) {
        if (entity.onGround() && entity.getY() < anchor.getY() + 1.5D) {
            return; // bowl-floor litter stays walkable loot, only airborne drops drift
        }
        Vec3 motion = entity.getDeltaMovement();
        double lift = entity.getY() < ceiling ? DRIFT_ACCEL : 0.0D;
        double vy = Math.min(motion.y + lift, entity.getY() < ceiling ? DRIFT_MAX_VY : 0.0D);
        double swirlAngle = (entity.getId() * 0.7853D)
                + entity.level().getGameTime() * 0.015D;
        entity.setDeltaMovement(
                motion.x * 0.92D + Math.cos(swirlAngle) * 0.004D,
                vy,
                motion.z * 0.92D + Math.sin(swirlAngle) * 0.004D);
        entity.hasImpulse = true;
        entity.fallDistance = 0.0F;
    }

    // ------------------------------------------------------------------ heart hit (§3.3)

    /** Attack (left click) on the heart hitbox = inversion trigger; cancel = no damage. */
    @SubscribeEvent
    static void onAttackEntity(AttackEntityEvent event) {
        if (event.getEntity() instanceof ServerPlayer player && !player.isSpectator()
                && event.getTarget().getTags().contains(HEART_TAG)) {
            event.setCanceled(true);
            tryInvert(player);
        }
    }

    /** Use (right click) on the heart = same trigger (accessibility). */
    @SubscribeEvent
    static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getHand() == InteractionHand.MAIN_HAND
                && event.getEntity() instanceof ServerPlayer player && !player.isSpectator()
                && event.getTarget().getTags().contains(HEART_TAG)) {
            event.setCanceled(true);
            tryInvert(player);
        }
    }

    /**
     * The 10 s inversion (plan §3.3): {@value GravityRiftZone#INVERT_ACTIVE_TICKS} t of
     * upward-pointing gravity for everyone in the zone, then a slow-fall glide back
     * until {@value GravityRiftZone#INVERT_TOTAL_TICKS} t. One start per
     * {@value GravityRiftZone#INVERT_COOLDOWN_TICKS}-tick cooldown; a cooldown hit
     * plays the dud fizzle so the heart never feels dead.
     */
    public static void tryInvert(ServerPlayer player) {
        ServerLevel level = player.serverLevel();
        GravityRiftState state = GravityRiftState.get(player.server);
        BlockPos anchor = state.anchor();
        if (!state.built() || anchor == null) {
            return;
        }
        long gameTime = level.getGameTime();
        Vec3 heart = heartCenter(anchor);
        boolean running = state.invertUntilGameTime() != 0L
                && gameTime < state.invertUntilGameTime();
        boolean cooling = state.lastInvertGameTime() != 0L
                && gameTime - state.lastInvertGameTime() < GravityRiftZone.INVERT_COOLDOWN_TICKS;
        if (running || cooling) {
            FxPayloads.sendFxEvent(level, GravityRiftCues.CUE_GRAVITY_INVERT, heart,
                    0.0F, 0.0F, 32.0D);
            level.playSound(null, heart.x, heart.y, heart.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.AMBIENT, 0.6F, 1.4F);
            return;
        }
        state.setLastInvertGameTime(gameTime);
        state.setInvertUntilGameTime(gameTime + GravityRiftZone.INVERT_TOTAL_TICKS);
        resolvedInvertEnd = Long.MIN_VALUE;
        FxPayloads.sendFxEvent(level, GravityRiftCues.CUE_GRAVITY_INVERT, heart,
                1.0F, 0.0F, 128.0D);
        level.playSound(null, heart.x, heart.y, heart.z,
                EclipseSounds.EVENT_STORM_SHATTER.get(), SoundSource.AMBIENT, 1.2F, 0.7F);
        sendCaptionNear(level, heart, "eclipse.caption.gravity.invert", 70,
                S2CCaptionPayload.STYLE_WHISPER, 128.0D);
        PacketDistributor.sendToPlayersNear(level, null, heart.x, heart.y, heart.z, 96.0D,
                S2CShakePayload.shake(0.5F, 20));
        GravityRiftPayloads.syncAll(level);
        EclipseMod.LOGGER.info("GravityRift: inversion started by {} (until t{})",
                player.getGameProfile().getName(), gameTime + GravityRiftZone.INVERT_TOTAL_TICKS);
    }

    // ------------------------------------------------------------------ self-heal (§3.5)

    /**
     * Sentinel probe + hitbox respawn (the SkyLauncher "a /kill'ed interaction would
     * silently brick the pad" doctrine). A missing sentinel (grief/explosion under the
     * pedestal) re-runs the whole idempotent materialize directly on the builder —
     * bypassing the pending registry, whose dedup would refuse a second same-id row.
     */
    private static void selfHeal(ServerLevel level, GravityRiftState state, BlockPos anchor) {
        if (!level.isLoaded(anchor)) {
            return;
        }
        if (!GravityRiftBuilder.isBuiltSentinel(level, anchor)) {
            if (!healInFlight) {
                healInFlight = true;
                EclipseMod.LOGGER.info("GravityRift self-heal: sentinel missing — re-materializing");
                GravityRiftBuilder.materialize(level, () -> healInFlight = false, error -> {
                    healInFlight = false;
                    EclipseMod.LOGGER.error("GravityRift self-heal failed", error);
                });
            }
            return;
        }
        Vec3 heart = heartCenter(anchor);
        List<Entity> hitboxes = level.getEntities((Entity) null,
                new AABB(heart, heart).inflate(6.0D),
                entity -> entity.getTags().contains(HEART_TAG));
        if (hitboxes.isEmpty()) {
            spawnHeartInteraction(level, anchor);
            EclipseMod.LOGGER.info("GravityRift self-heal: respawned heart hitbox");
        } else {
            for (int i = 1; i < hitboxes.size(); i++) {
                hitboxes.get(i).discard(); // duplicates from a crash between spawn + save
            }
        }
    }

    /**
     * The heart's {@code minecraft:interaction} hitbox — NBT spawn (vanilla has no
     * public width/height setters; the {@code SkyLauncher.spawnPadInteraction}
     * precedent). 3.4 wide covers both counter-rotating cage shells.
     */
    private static void spawnHeartInteraction(ServerLevel level, BlockPos anchor) {
        Vec3 heart = heartCenter(anchor);
        List<Entity> existing = level.getEntities((Entity) null,
                new AABB(heart, heart).inflate(6.0D),
                entity -> entity.getTags().contains(HEART_TAG));
        if (!existing.isEmpty()) {
            return;
        }
        CompoundTag nbt = new CompoundTag();
        nbt.putString("id", "minecraft:interaction");
        nbt.putFloat("width", 3.4F);
        nbt.putFloat("height", 3.4F);
        nbt.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(heart.x));
        pos.add(DoubleTag.valueOf(heart.y - 1.7D));
        pos.add(DoubleTag.valueOf(heart.z));
        nbt.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(nbt, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("GravityRift: could not create heart interaction at {}", heart);
            return;
        }
        interaction.addTag(HEART_TAG);
        level.addFreshEntity(interaction);
    }

    // ------------------------------------------------------------------ helpers

    /** Heart center in world space (pedestal top + hover; the FX/interaction anchor). */
    public static Vec3 heartCenter(BlockPos anchor) {
        return new Vec3(anchor.getX() + 0.5D, anchor.getY() + GravityRiftZone.HEART_HEIGHT,
                anchor.getZ() + 0.5D);
    }

    private static AABB zoneBox(BlockPos anchor) {
        return new AABB(
                anchor.getX() + 0.5D - GravityRiftZone.ZONE_RADIUS,
                anchor.getY() - GravityRiftZone.ZONE_BELOW,
                anchor.getZ() + 0.5D - GravityRiftZone.ZONE_RADIUS,
                anchor.getX() + 0.5D + GravityRiftZone.ZONE_RADIUS,
                anchor.getY() + GravityRiftZone.ZONE_ABOVE,
                anchor.getZ() + 0.5D + GravityRiftZone.ZONE_RADIUS);
    }

    private static boolean anyPlayerNear(ServerLevel overworld, BlockPos anchor) {
        double rangeSq = (double) ACTIVE_RADIUS * ACTIVE_RADIUS;
        for (ServerPlayer player : overworld.players()) {
            if (!player.isSpectator() && player.distanceToSqr(
                    anchor.getX() + 0.5D, anchor.getY(), anchor.getZ() + 0.5D) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    private static void sendCaptionNear(ServerLevel level, Vec3 center, String key, int ticks,
            int style, double range) {
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceTo(center) <= range) {
                PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(key, ticks, style));
            }
        }
    }

    // ------------------------------------------------------------------ dev support (§9)

    /** {@code /dev woah gravity status} server-side snapshot. */
    public static String devStatus(ServerLevel level) {
        GravityRiftState state = GravityRiftState.get(level.getServer());
        if (!state.built()) {
            boolean pending = StructurePendingRegistry.pending().stream()
                    .anyMatch(site -> site.siteId().equals(GravityRiftZone.STRUCTURE_ID));
            return "not built (pending=" + pending + ", stage="
                    + WorldStageService.stage(level.getServer(), DiscProfile.OVERWORLD)
                    + "/" + GravityRiftZone.STAGE + ")";
        }
        BlockPos anchor = state.anchor();
        long gameTime = level.getGameTime();
        int offset = GravityRiftZone.pulsePhaseOffset(anchor);
        long phase = Math.floorMod(gameTime - offset, (long) GravityRiftZone.PULSE_PERIOD_TICKS);
        long invertLeft = Math.max(0L, state.invertUntilGameTime() - gameTime);
        long cooldownLeft = state.lastInvertGameTime() == 0L ? 0L
                : Math.max(0L, state.lastInvertGameTime()
                        + GravityRiftZone.INVERT_COOLDOWN_TICKS - gameTime);
        int lowG = 0;
        for (ServerPlayer player : level.players()) {
            AttributeInstance gravity = player.getAttribute(Attributes.GRAVITY);
            if (gravity != null && gravity.getModifier(LOW_G_GRAVITY_ID) != null) {
                lowG++;
            }
        }
        return "built v" + state.builtVersion()
                + " anchor=" + anchor.toShortString()
                + " sentinel=" + GravityRiftBuilder.isBuiltSentinel(level, anchor)
                + " pulseIn=" + (GravityRiftZone.PULSE_PERIOD_TICKS - phase) + "t"
                + " invertLeft=" + invertLeft + "t"
                + " cooldownLeft=" + cooldownLeft + "t"
                + " lowGPlayers=" + lowG
                + " playersNear=" + playersNear;
    }

    /** {@code /dev woah gravity pulse}: skips the raster — full telegraph + beat NOW. */
    public static void devPulse(ServerLevel level) {
        GravityRiftState state = GravityRiftState.get(level.getServer());
        BlockPos anchor = state.anchor();
        if (!state.built() || anchor == null) {
            return;
        }
        Vec3 heart = heartCenter(anchor);
        FxPayloads.sendFxEvent(level, GravityRiftCues.CUE_GRAVITY_PULSE, heart, 0.0F, 0.0F, 256.0D);
        level.playSound(null, heart.x, heart.y, heart.z, EclipseSounds.EVENT_RIFT_THUD.get(),
                SoundSource.AMBIENT, 1.4F, 0.9F);
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator()
                    || !GravityRiftZone.inZone(anchor, player.getX(), player.getY(), player.getZ())) {
                continue;
            }
            Vec3 motion = player.getDeltaMovement();
            player.setDeltaMovement(motion.x, Math.max(motion.y, PULSE_LAUNCH_VY), motion.z);
            player.hurtMarked = true;
            player.fallDistance = 0.0F;
            PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.35F, 14));
        }
    }

    /** {@code /dev woah gravity invert}: clears the cooldown, then triggers normally. */
    public static void devInvert(ServerPlayer player) {
        GravityRiftState state = GravityRiftState.get(player.server);
        state.setLastInvertGameTime(0L);
        state.setInvertUntilGameTime(0L);
        tryInvert(player);
    }
}
