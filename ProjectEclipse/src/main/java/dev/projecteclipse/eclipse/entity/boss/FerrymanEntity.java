package dev.projecteclipse.eclipse.entity.boss;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.limbo.ShipLanterns;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.ritual.FinaleRitual;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.LongTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.Component;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The Ferryman — day-14 finale boss on the limbo ghost ship
 * ({@code docs/ideas/04_content.md} §2.2). Summoned by the finale ritual (dragon egg at the
 * altar after dusk on day 14, see {@code ritual/FinaleRitual}) or
 * {@code /eclipse boss ferryman summon}; never spawns naturally, and it refuses to exist
 * outside {@code eclipse:limbo}.
 *
 * <p><b>Fight</b> (server-scripted, no vanilla goals — {@link #tick()} drives everything):
 * {@value #BASE_MAX_HEALTH} HP base scaled ×(1+0.4·(n−1)) for n living players; bossbar
 * WHITE → PURPLE → RED by phase (breaks at exactly 2/3 and 1/3):</p>
 * <ul>
 *   <li><b>P1 Oar</b> (100–66%): melee stalker on the deck. In range it telegraphs a 180°
 *       oar sweep ({@value #SWEEP_TELEGRAPH_TICKS}t raise + TRIDENT_RIPTIDE_3, then
 *       {@value #SWEEP_DAMAGE} dmg + heavy knockback to everyone in the front half-circle);
 *       every {@value #SLAM_INTERVAL_TICKS}t it jumps into a gunwale slam (landing AoE +
 *       an {@code S2CShakePayload} ship tilt for everyone aboard). All fight long, living
 *       players in the limbo water take a void-cold DoT until they climb back out.</li>
 *   <li><b>P2 Crew</b> (≤66%): kneels invulnerable at the stern; the Deckhand crew rises
 *       hostile ({@link DeckhandEntity#riseHostile}) and {@code min(4, ghosts+2)} deck
 *       lanterns blow out ({@link ShipLanterns#extinguish}). LIVING players cut down the
 *       crew; GHOSTS re-light lanterns via the 3 s channel. All four lanterns burning ends
 *       the phase (fallback: no ghosts online AND the risen crew slain force-ends it, so a
 *       ghost-less server can never softlock).</li>
 *   <li><b>P3 The Toll</b> (≤33%): plants the oar; every {@value #SINK_INTERVAL_TICKS}t
 *       (doubled while ≤3 players live — the spec's "sink slows") the water rises one layer
 *       across the deck (air-only {@code setBlock}, tracked for restore). Sweeps keep
 *       coming, alternating with the Lantern Gaze: the lowest-health fighter is marked
 *       ({@code S2CShakePayload.mark} → private purple vignette + private bell) and hunted
 *       for {@value #GAZE_MARK_TICKS}t.</li>
 * </ul>
 *
 * <p><b>Endings</b>: death drops {@code eclipse:ferryman_toll}, restores the ship (water
 * drained, lanterns relit, crew calmed), sets {@code ferrymanDefeated} and hands off to the
 * mass-revive finale ({@link FinaleRitual#beginVictory}) — all from {@link #die}, exactly
 * once; the body then plays a {@value #DEATH_DURATION_TICKS}t scripted collapse
 * ({@link #tickDeath}: oar planted, lantern guttering, upright sink, final toll) before
 * removal. A wipe (every participant dead or banned) is the Eclipse's victory: announce,
 * ship restored, everyone stays a ghost. If no living fighter boards for
 * {@value #RESET_TICKS}t the fight resets the same way (minus the announcement).</p>
 */
public class FerrymanEntity extends Monster {
    public static final float BASE_MAX_HEALTH = 400.0F;
    /** Deck X of the stern anchor (bow is +X): three blocks inboard of the stern cap. */
    public static final int STERN_X = -(GhostShipBuilder.HALF_LENGTH - 3);
    /** Scripted death collapse length (vanilla tips over after 20t; see {@link #tickDeath}). */
    public static final int DEATH_DURATION_TICKS = 70;

    private static final double SCALING_RANGE = 64.0D;
    private static final double FIGHT_RANGE = 64.0D;
    private static final double PARTICIPANT_RANGE = 48.0D;

    // P1 oar sweep + gunwale slam.
    private static final int SWEEP_TELEGRAPH_TICKS = 25;
    private static final int SWEEP_COOLDOWN_TICKS = 70;
    private static final double SWEEP_TRIGGER_RANGE = 4.5D;
    private static final double SWEEP_RANGE = 5.5D;
    private static final float SWEEP_DAMAGE = 10.0F;
    private static final double SWEEP_KNOCKBACK = 1.7D;
    private static final int SLAM_INTERVAL_TICKS = 280;
    private static final double SLAM_RADIUS = 5.5D;
    private static final float SLAM_DAMAGE = 6.0F;
    private static final int SLAM_MAX_AIR_TICKS = 60;
    // Void-cold water DoT (all phases).
    private static final int DOT_INTERVAL_TICKS = 20;
    private static final float DOT_DAMAGE = 2.0F;
    // P2 crew.
    private static final int CREW_CHECK_TICKS = 20;
    // P3 sink + gaze.
    private static final int SINK_INTERVAL_TICKS = 600; // 30 s
    private static final int MAX_SINK_LAYERS = 4;
    private static final int GAZE_INTERVAL_TICKS = 400;
    private static final int GAZE_MARK_TICKS = 300; // 15 s
    // Reset / wipe.
    private static final int RESET_TICKS = 1200; // 60 s without a living fighter aboard
    private static final int WIPE_CHECK_TICKS = 20;
    // P2 kneel: blocked-hit feedback throttle (~2/s).
    private static final int KNEEL_CUE_INTERVAL_TICKS = 10;
    // Death collapse: the lantern flame sputters out by this deathTime, the last bell
    // tolls shortly before the body fades.
    private static final int DEATH_FLAME_OUT_TICKS = 30;
    private static final int DEATH_BELL_TICK = 55;

    /** Current phase 1..3 (synced; drives bossbar color + model poses). */
    private static final EntityDataAccessor<Integer> DATA_PHASE =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.INT);
    /** True while an oar sweep is winding up (client raises the oar overhead). */
    private static final EntityDataAccessor<Boolean> DATA_TELEGRAPH =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);
    /** True while kneeling invulnerable at the stern (P2 crew mechanic). */
    private static final EntityDataAccessor<Boolean> DATA_KNEELING =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);
    /** True while the oar is planted on the deck (P3 idle pose). */
    private static final EntityDataAccessor<Boolean> DATA_PLANTED =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);
    /** True while the Lantern Gaze mark is active (the lantern joins the emissive pass). */
    private static final EntityDataAccessor<Boolean> DATA_GAZING =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);

    private final ServerBossEvent bossEvent = new ServerBossEvent(
            Component.translatable("entity.eclipse.ferryman.bossbar"),
            BossEvent.BossBarColor.WHITE, BossEvent.BossBarOverlay.PROGRESS);

    // --- server fight state (geometry + participants + ship edits persisted in NBT) ---
    @Nullable
    private Vec3 shipCenter;
    private int deckY;
    private int scaledPlayers = 1;
    private int lastPhase = 1;
    private final Set<UUID> participants = new HashSet<>();

    private int sweepCooldown = SWEEP_COOLDOWN_TICKS / 2;
    private int telegraphTimer = -1;
    private int slamTimer = SLAM_INTERVAL_TICKS;
    private boolean slamAirborne;
    private int slamAirTicks;
    private boolean crewActive;
    private int requiredLanterns;
    private boolean sinkSlowedLogged;
    private int sinkTimer = SINK_INTERVAL_TICKS;
    private int sinkLayers;
    private final List<BlockPos> placedWater = new ArrayList<>();
    private int gazeTimer = GAZE_INTERVAL_TICKS / 2;
    private int gazeTicksLeft;
    @Nullable
    private UUID gazeTargetId;
    private int noFighterTicks;
    private int lastKneelCueTick = -KNEEL_CUE_INTERVAL_TICKS;
    /** Players already shown the kneel actionbar hint this crew phase (first hit only). */
    private final Set<UUID> kneelHintShown = new HashSet<>();

    // Client-side smooth animation clock + pose blend weights (raise/kneel/plant).
    private float animAge;
    private float animAgePrev;
    private float raiseLerp;
    private float raiseLerpPrev;
    private float kneelLerp;
    private float kneelLerpPrev;
    private float plantLerp;
    private float plantLerpPrev;

    public FerrymanEntity(EntityType<? extends FerrymanEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
        this.xpReward = 100;
    }

    // --- summoning ---

    /**
     * Spawns the Ferryman at the ghost ship's stern (feet one block above the deck) with
     * the arrival FX, ensures the deck lanterns exist, and snapshots the living-player
     * scaling. {@code limbo} must be the Limbo dimension — the ship geometry (deck height,
     * bounds) is derived from {@link GhostShipBuilder}.
     */
    public static FerrymanEntity summon(ServerLevel limbo) {
        FerrymanEntity ferryman = dev.projecteclipse.eclipse.entity.EclipseEntities.FERRYMAN.get().create(limbo);
        if (ferryman == null) {
            throw new IllegalStateException("Ferryman entity type failed to instantiate");
        }
        ShipLanterns.ensurePlaced(limbo);
        DeckhandEntity.reseatFallen(limbo); // The crew returns for every crossing (P2 fodder).
        int deck = GhostShipBuilder.waterlineY(limbo) + 3;
        double x = STERN_X + 0.5D;
        double z = 0.5D;
        ferryman.moveTo(x, deck + 1, z, 90.0F, 0.0F); // faces the bow (+X)
        ferryman.initFight(limbo, new Vec3(0.5D, deck, 0.5D), deck);
        limbo.addFreshEntity(ferryman);
        PacketDistributor.sendToPlayersNear(limbo, null, x, deck + 1, z, 96.0D,
                new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, ferryman.position()));
        limbo.playSound(null, ferryman.blockPosition(), SoundEvents.END_PORTAL_SPAWN, SoundSource.HOSTILE, 1.0F, 0.5F);
        limbo.playSound(null, ferryman.blockPosition(), EclipseSounds.BOSS_FERRYMAN_AMBIENT.get(),
                SoundSource.HOSTILE, 1.2F, 1.0F);
        limbo.sendParticles(ParticleTypes.SOUL, x, deck + 2.0D, z, 80, 1.0D, 1.4D, 1.0D, 0.04D);
        EclipseMod.LOGGER.info("Ferryman summoned at the stern ({}, {}, {}) — scaled for {} player(s): {} HP; bossbar {} created",
                x, deck + 1, z, ferryman.scaledPlayers, ferryman.getMaxHealth(), ferryman.bossEvent.getId());
        return ferryman;
    }

    /** Pins the ship geometry and applies the living-player scaling (spec §2.2). */
    private void initFight(ServerLevel limbo, Vec3 center, int deck) {
        this.shipCenter = center;
        this.deckY = deck;
        long living = limbo.getServer().getPlayerList().getPlayers().stream()
                .filter(player -> !player.isSpectator() && player.isAlive())
                .filter(player -> !BanService.isBanned(player))
                .filter(player -> player.level() != limbo
                        || player.position().distanceTo(center) <= SCALING_RANGE)
                .count();
        this.scaledPlayers = (int) Math.max(1L, living);
        double maxHealth = BASE_MAX_HEALTH * (1.0D + 0.4D * (this.scaledPlayers - 1));
        this.getAttribute(Attributes.MAX_HEALTH).setBaseValue(maxHealth);
        this.setHealth((float) maxHealth);
    }

    /** Lazy geometry init for plain {@code /summon eclipse:ferryman} in limbo. */
    private void ensureFightInitialized(ServerLevel level) {
        if (this.shipCenter != null) {
            return;
        }
        int deck = GhostShipBuilder.waterlineY(level) + 3;
        initFight(level, new Vec3(0.5D, deck, 0.5D), deck);
        EclipseMod.LOGGER.info("Ferryman ship geometry auto-pinned (deck y={}, {} player(s), {} HP); bossbar {} created",
                deck, this.scaledPlayers, this.getMaxHealth(), this.bossEvent.getId());
    }

    // --- synced state accessors ---

    public int getPhase() {
        return this.entityData.get(DATA_PHASE);
    }

    protected void setPhase(int phase) {
        this.entityData.set(DATA_PHASE, Mth.clamp(phase, 1, 3));
    }

    public boolean isTelegraphing() {
        return this.entityData.get(DATA_TELEGRAPH);
    }

    protected void setTelegraphing(boolean telegraphing) {
        this.entityData.set(DATA_TELEGRAPH, telegraphing);
    }

    public boolean isKneeling() {
        return this.entityData.get(DATA_KNEELING);
    }

    protected void setKneeling(boolean kneeling) {
        this.entityData.set(DATA_KNEELING, kneeling);
    }

    public boolean isPlanted() {
        return this.entityData.get(DATA_PLANTED);
    }

    protected void setPlanted(boolean planted) {
        this.entityData.set(DATA_PLANTED, planted);
    }

    public boolean isGazing() {
        return this.entityData.get(DATA_GAZING);
    }

    protected void setGazing(boolean gazing) {
        this.entityData.set(DATA_GAZING, gazing);
    }

    // --- ticking ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            tickClientAnim();
        } else if (this.isAlive() && this.level() instanceof ServerLevel serverLevel) {
            if (!serverLevel.dimension().equals(LimboDimension.LIMBO)) {
                // The Ferryman exists only on the ghost ship.
                EclipseMod.LOGGER.warn("Ferryman discarded: spawned outside {}",
                        LimboDimension.LIMBO.location());
                this.discard();
                return;
            }
            ensureFightInitialized(serverLevel);
            this.bossEvent.setProgress(this.getHealth() / this.getMaxHealth());
            updatePhase(serverLevel);
            tickFight(serverLevel);
        }
    }

    /** Phase = health fraction: breaks at exactly 2/3 and 1/3 (bossbar WHITE→PURPLE→RED). */
    private void updatePhase(ServerLevel level) {
        float fraction = this.getHealth() / this.getMaxHealth();
        int phase = fraction > 2.0F / 3.0F ? 1 : fraction > 1.0F / 3.0F ? 2 : 3;
        if (phase == this.lastPhase) {
            return;
        }
        EclipseMod.LOGGER.info("Ferryman phase {} -> {} at {}/{} HP", this.lastPhase, phase,
                String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()),
                String.format(java.util.Locale.ROOT, "%.1f", this.getMaxHealth()));
        int previous = this.lastPhase;
        this.lastPhase = phase;
        setPhase(phase);
        applyBossbarColor(phase);
        level.playSound(null, this.blockPosition(), SoundEvents.WITHER_SPAWN, SoundSource.HOSTILE,
                1.0F, phase == 2 ? 1.1F : 0.6F);
        onPhaseChanged(level, previous, phase);
    }

    /** Phase-break bookkeeping: crew start/stop, oar plant, sink/gaze timers. */
    protected void onPhaseChanged(ServerLevel level, int previousPhase, int newPhase) {
        setTelegraphing(false);
        this.telegraphTimer = -1;
        if (this.crewActive && newPhase != 2) {
            endCrewPhase(level, "phase moved on");
        }
        if (newPhase == 2 && !this.crewActive) {
            startCrewPhase(level);
        }
        setPlanted(newPhase >= 3);
        if (newPhase == 3) {
            this.sinkTimer = SINK_INTERVAL_TICKS;
            this.gazeTimer = GAZE_INTERVAL_TICKS / 2;
            level.playSound(null, this.blockPosition(), EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                    SoundSource.HOSTILE, 1.2F, 0.8F);
            EclipseMod.LOGGER.info("Ferryman P3 The Toll: oar planted — the ship begins to sink "
                    + "(1 layer per {}t, doubled while <=3 players live)", SINK_INTERVAL_TICKS);
        }
    }

    /** Per-tick fight script (server side, limbo only, geometry pinned). */
    protected void tickFight(ServerLevel level) {
        List<ServerPlayer> fighters = livingFighters(level);
        updateParticipants(fighters);
        if (this.tickCount % WIPE_CHECK_TICKS == 0 && checkWipe(level)) {
            return;
        }
        if (tickReset(level, fighters)) {
            return;
        }
        if (this.tickCount % DOT_INTERVAL_TICKS == 0) {
            tickWaterDot(level, fighters);
        }
        if (this.crewActive) {
            tickCrewPhase(level);
            return; // Kneeling: no movement script, no attacks.
        }
        ServerPlayer target = currentTarget(level, fighters);
        if (this.slamAirborne) {
            tickSlamAirborne(level, fighters);
        } else {
            tickMovement(target);
            tickSweep(level, fighters, target);
            if (getPhase() == 1) {
                tickSlamWindup(target);
            }
        }
        if (getPhase() == 3) {
            tickSink(level, fighters);
            tickGaze(level, fighters);
        }
    }

    // --- movement (gravity-free deck stalker) ---

    private void tickMovement(@Nullable ServerPlayer target) {
        double hoverY = this.deckY + 1.0D;
        Vec3 velocity = new Vec3(0.0D, (hoverY - this.getY()) * 0.15D, 0.0D);
        if (target != null && this.telegraphTimer < 0) {
            Vec3 to = target.position().subtract(this.position());
            double dist = Math.sqrt(to.x * to.x + to.z * to.z);
            if (dist > 2.5D) {
                double speed = getPhase() >= 3 ? 0.22D : 0.16D;
                velocity = velocity.add(to.x / dist * speed, 0.0D, to.z / dist * speed);
            }
        }
        this.setDeltaMovement(velocity);
        if (target != null) {
            faceTowards(target.position());
        }
    }

    // --- P1/P3 oar sweep ---

    private void tickSweep(ServerLevel level, List<ServerPlayer> fighters, @Nullable ServerPlayer target) {
        if (this.telegraphTimer < 0) {
            if (this.sweepCooldown > 0) {
                this.sweepCooldown--;
                return;
            }
            if (target == null || target.position().distanceTo(this.position()) > SWEEP_TRIGGER_RANGE) {
                return;
            }
            this.telegraphTimer = SWEEP_TELEGRAPH_TICKS;
            setTelegraphing(true);
            level.playSound(null, this.blockPosition(), SoundEvents.TRIDENT_RIPTIDE_3.value(),
                    SoundSource.HOSTILE, 1.2F, 0.8F);
            EclipseMod.LOGGER.info("Ferryman sweep telegraph: oar raised ({}t windup)", SWEEP_TELEGRAPH_TICKS);
            return;
        }
        if (--this.telegraphTimer >= 0) {
            return;
        }
        setTelegraphing(false);
        this.sweepCooldown = SWEEP_COOLDOWN_TICKS;
        doSweep(level, fighters);
    }

    /** 180° arc in front of the boss: {@value #SWEEP_DAMAGE} dmg + heavy outward knockback. */
    private void doSweep(ServerLevel level, List<ServerPlayer> fighters) {
        Vec3 forward = Vec3.directionFromRotation(0.0F, this.getYRot());
        int hits = 0;
        for (ServerPlayer player : fighters) {
            Vec3 to = player.position().subtract(this.position());
            double dist = to.length();
            if (dist > SWEEP_RANGE || Math.abs(player.getY() - (this.deckY + 1.0D)) > 4.0D) {
                continue;
            }
            Vec3 flat = new Vec3(to.x, 0.0D, to.z);
            if (flat.lengthSqr() > 1.0E-4D && flat.normalize().dot(forward) < 0.0D) {
                continue; // Behind the boss: the sweep is a front half-circle.
            }
            player.hurt(this.damageSources().mobAttack(this), SWEEP_DAMAGE);
            Vec3 away = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : forward;
            player.setDeltaMovement(away.scale(SWEEP_KNOCKBACK).add(0.0D, 0.55D, 0.0D));
            player.hurtMarked = true; // sync the launch to the client (SoftBorder pattern)
            hits++;
        }
        level.playSound(null, this.blockPosition(), SoundEvents.PLAYER_ATTACK_SWEEP,
                SoundSource.HOSTILE, 1.4F, 0.6F);
        Vec3 front = this.position().add(Vec3.directionFromRotation(0.0F, this.getYRot()).scale(2.5D));
        level.sendParticles(ParticleTypes.SWEEP_ATTACK, front.x, this.deckY + 2.0D, front.z,
                6, 1.2D, 0.4D, 1.2D, 0.0D);
        EclipseMod.LOGGER.info("Ferryman oar sweep hit {} player(s) for {} + knockback", hits, SWEEP_DAMAGE);
    }

    // --- P1 gunwale slam ---

    private void tickSlamWindup(@Nullable ServerPlayer target) {
        if (--this.slamTimer > 0 || target == null
                || target.position().distanceTo(this.position()) > 9.0D) {
            return;
        }
        this.slamTimer = SLAM_INTERVAL_TICKS;
        this.slamAirborne = true;
        this.slamAirTicks = 0;
        Vec3 to = target.position().subtract(this.position());
        double dist = Math.max(1.0D, Math.sqrt(to.x * to.x + to.z * to.z));
        this.setDeltaMovement(to.x / dist * 0.3D, 0.95D, to.z / dist * 0.3D);
        this.level().playSound(null, this.blockPosition(), SoundEvents.TRIDENT_THROW.value(),
                SoundSource.HOSTILE, 1.4F, 0.5F);
        EclipseMod.LOGGER.info("Ferryman gunwale slam: airborne toward {}", target.getScoreboardName());
    }

    /** Manual gravity while airborne; landing = AoE + the S2CShakePayload ship tilt. */
    private void tickSlamAirborne(ServerLevel level, List<ServerPlayer> fighters) {
        this.slamAirTicks++;
        this.setDeltaMovement(this.getDeltaMovement().add(0.0D, -0.08D, 0.0D));
        boolean landed = this.slamAirTicks > 4
                && (this.onGround() || this.getY() <= this.deckY + 1.05D);
        if (!landed && this.slamAirTicks < SLAM_MAX_AIR_TICKS) {
            return;
        }
        this.slamAirborne = false;
        this.setDeltaMovement(Vec3.ZERO);
        int hits = 0;
        for (ServerPlayer player : fighters) {
            Vec3 to = player.position().subtract(this.position());
            if (Math.sqrt(to.x * to.x + to.z * to.z) <= SLAM_RADIUS
                    && Math.abs(player.getY() - (this.deckY + 1.0D)) <= 4.0D) {
                player.hurt(this.damageSources().mobAttack(this), SLAM_DAMAGE);
                player.setDeltaMovement(player.getDeltaMovement().add(0.0D, 0.45D, 0.0D));
                player.hurtMarked = true;
                hits++;
            }
        }
        // The whole ship tilts: every player aboard (ghosts included) gets the camera shake.
        PacketDistributor.sendToPlayersNear(level, null, this.getX(), this.getY(), this.getZ(), 96.0D,
                S2CShakePayload.shake(1.1F, 22));
        PacketDistributor.sendToPlayersNear(level, null, this.getX(), this.getY(), this.getZ(), 96.0D,
                new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, this.position()));
        level.playSound(null, this.blockPosition(), SoundEvents.GENERIC_EXPLODE.value(),
                SoundSource.HOSTILE, 1.0F, 0.7F);
        EclipseMod.LOGGER.info("Ferryman gunwale slam landed after {}t: {} player(s) hit, shake payload sent",
                this.slamAirTicks, hits);
    }

    // --- void-cold water DoT (all phases) ---

    private void tickWaterDot(ServerLevel level, List<ServerPlayer> fighters) {
        for (ServerPlayer player : fighters) {
            if (!player.isInWater()) {
                continue;
            }
            player.hurt(this.damageSources().freeze(), DOT_DAMAGE);
            level.sendParticles(ParticleTypes.SNOWFLAKE, player.getX(), player.getY() + 0.8D,
                    player.getZ(), 6, 0.25D, 0.4D, 0.25D, 0.02D);
            if (this.tickCount % 100 == 0) {
                EclipseMod.LOGGER.info("Void-cold water: {} takes {} (overboard/flooded)",
                        player.getScoreboardName(), DOT_DAMAGE);
            }
        }
    }

    // --- P2 crew phase ---

    private void startCrewPhase(ServerLevel level) {
        this.crewActive = true;
        setKneeling(true);
        this.kneelHintShown.clear(); // Each crew phase re-teaches the counter once per player.
        int ghosts = ghostsOnline(level);
        this.requiredLanterns = Math.min(4, ghosts + 2);
        int darkened = ShipLanterns.extinguish(level, this.requiredLanterns);
        int risen = DeckhandEntity.riseHostile(level);
        EclipseMod.LOGGER.info("Ferryman P2 Crew: kneeling invulnerable at the stern — {} deckhand(s) risen, "
                + "{} lantern(s) extinguished (required {}, {} ghost(s) online)",
                risen, darkened, this.requiredLanterns, ghosts);
    }

    private void tickCrewPhase(ServerLevel level) {
        // Drift home to the stern and hold there.
        Vec3 anchor = new Vec3(STERN_X + 0.5D, this.deckY + 1.0D, 0.5D);
        Vec3 toAnchor = anchor.subtract(this.position()).scale(0.08D);
        if (toAnchor.length() > 0.3D) {
            toAnchor = toAnchor.normalize().scale(0.3D);
        }
        this.setDeltaMovement(toAnchor);
        faceTowards(new Vec3(this.shipCenter.x + GhostShipBuilder.HALF_LENGTH, this.deckY + 1.0D, 0.5D));
        if (this.tickCount % CREW_CHECK_TICKS != 0) {
            return;
        }
        if (ShipLanterns.allLit(level)) {
            endCrewPhase(level, "all lanterns burn again");
            return;
        }
        // Softlock guard: with no ghosts online nobody can re-light — the crew IS the phase.
        if (ghostsOnline(level) == 0 && DeckhandEntity.countHostileAlive(level) == 0) {
            ShipLanterns.relightAll(level);
            endCrewPhase(level, "no ghosts online and the risen crew is slain — force-ended");
        }
    }

    private void endCrewPhase(ServerLevel level, String reason) {
        this.crewActive = false;
        setKneeling(false);
        DeckhandEntity.calmCrew(level);
        level.playSound(null, this.blockPosition(), SoundEvents.WITHER_SPAWN, SoundSource.HOSTILE, 1.0F, 0.9F);
        EclipseMod.LOGGER.info("Ferryman P2 Crew ended ({}) — {} lantern(s) burning; the Ferryman rises",
                reason, ShipLanterns.litCount(level));
    }

    /** Kneeling = mechanically invulnerable (the crew phase is the counter, not damage). */
    @Override
    public boolean isInvulnerableTo(DamageSource source) {
        if (isKneeling() && !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return true;
        }
        return super.isInvulnerableTo(source);
    }

    /**
     * Blocked-hit feedback for the P2 kneel: {@link #isInvulnerableTo} makes the kneeling
     * boss mechanically immune, but a silent no-op reads like a bug — so every blocked hit
     * answers with a dull deflect toll + a soul puff at the impact point (throttled to
     * ~2/s), and the FIRST blocked hit per player teaches the counter via the actionbar.
     * {@code /kill} damage still bypasses and falls through to the vanilla path.
     */
    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (!this.level().isClientSide && isKneeling()
                && !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)
                && this.level() instanceof ServerLevel serverLevel) {
            onKneelBlockedHit(serverLevel, source);
            return false; // Same outcome the invulnerability check would produce.
        }
        return super.hurt(source, amount);
    }

    private void onKneelBlockedHit(ServerLevel level, DamageSource source) {
        if (source.getEntity() instanceof ServerPlayer attacker
                && this.kneelHintShown.add(attacker.getUUID())) {
            attacker.displayClientMessage(Component.translatable("message.eclipse.ferryman.kneel"), true);
        }
        if (this.tickCount - this.lastKneelCueTick < KNEEL_CUE_INTERVAL_TICKS) {
            return;
        }
        this.lastKneelCueTick = this.tickCount;
        level.playSound(null, this.blockPosition(), EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                SoundSource.HOSTILE, 0.5F, 0.6F); // Dull, damped — not the full toll.
        Vec3 impact = impactPoint(source);
        level.sendParticles(ParticleTypes.SOUL, impact.x, impact.y, impact.z,
                6, 0.15D, 0.15D, 0.15D, 0.02D);
    }

    /** Approximate impact point: the boss surface facing whatever dealt the blocked hit. */
    private Vec3 impactPoint(DamageSource source) {
        Vec3 center = this.position().add(0.0D, this.getBbHeight() * 0.55D, 0.0D);
        Vec3 from = source.getSourcePosition();
        if (from == null) {
            return center;
        }
        Vec3 toward = from.subtract(center);
        return toward.lengthSqr() < 1.0E-4D ? center : center.add(toward.normalize().scale(0.9D));
    }

    // --- P3 sink ---

    private void tickSink(ServerLevel level, List<ServerPlayer> fighters) {
        boolean slowed = fighters.size() <= 3;
        if (slowed != this.sinkSlowedLogged) {
            this.sinkSlowedLogged = slowed;
            EclipseMod.LOGGER.info("Ferryman sink pace {} ({} living fighter(s) aboard)",
                    slowed ? "SLOWED x2" : "normal", fighters.size());
        }
        // Slowed = half pace: skip every other countdown tick.
        if (slowed && this.tickCount % 2 == 0) {
            return;
        }
        if (--this.sinkTimer > 0) {
            return;
        }
        this.sinkTimer = SINK_INTERVAL_TICKS;
        raiseWaterLayer(level);
    }

    /** One layer of black water across the deck footprint; air-only, tracked for restore. */
    private void raiseWaterLayer(ServerLevel level) {
        if (this.sinkLayers >= MAX_SINK_LAYERS) {
            EclipseMod.LOGGER.info("Ferryman sink: deck already fully awash ({} layers)", this.sinkLayers);
            return;
        }
        this.sinkLayers++;
        int y = this.deckY + this.sinkLayers;
        int placed = 0;
        for (int dx = -GhostShipBuilder.HALF_LENGTH; dx <= GhostShipBuilder.HALF_LENGTH; dx++) {
            int hw = GhostShipBuilder.halfWidthAt(dx);
            for (int dz = -hw; dz <= hw; dz++) {
                BlockPos pos = new BlockPos(dx, y, dz);
                if (level.getBlockState(pos).isAir()) {
                    level.setBlockAndUpdate(pos, Blocks.WATER.defaultBlockState());
                    this.placedWater.add(pos);
                    placed++;
                }
            }
        }
        level.playSound(null, BlockPos.containing(this.shipCenter), SoundEvents.AMBIENT_UNDERWATER_ENTER,
                SoundSource.HOSTILE, 2.0F, 0.6F);
        EclipseMod.LOGGER.info("Ferryman sink: water layer {} of {} at y={} — {} block(s) placed ({} tracked total)",
                this.sinkLayers, MAX_SINK_LAYERS, y, placed, this.placedWater.size());
    }

    // --- P3 Lantern Gaze ---

    private void tickGaze(ServerLevel level, List<ServerPlayer> fighters) {
        if (this.gazeTicksLeft > 0) {
            ServerPlayer marked = this.gazeTargetId != null
                    ? level.getServer().getPlayerList().getPlayer(this.gazeTargetId) : null;
            if (marked == null || !marked.isAlive() || marked.level() != level || BanService.isBanned(marked)) {
                clearGaze("marked player lost");
                return;
            }
            if (--this.gazeTicksLeft <= 0) {
                clearGaze("mark expired");
            }
            return;
        }
        if (--this.gazeTimer > 0 || fighters.isEmpty()) {
            return;
        }
        this.gazeTimer = GAZE_INTERVAL_TICKS;
        ServerPlayer weakest = fighters.get(0);
        for (ServerPlayer player : fighters) {
            if (player.getHealth() < weakest.getHealth()) {
                weakest = player;
            }
        }
        this.gazeTargetId = weakest.getUUID();
        this.gazeTicksLeft = GAZE_MARK_TICKS;
        setGazing(true);
        // Only the marked player gets the vignette + the private bell.
        PacketDistributor.sendToPlayer(weakest, S2CShakePayload.mark(GAZE_MARK_TICKS));
        weakest.connection.send(new ClientboundSoundPacket(
                BuiltInRegistries.SOUND_EVENT.wrapAsHolder(EclipseSounds.BOSS_FERRYMAN_BELL.get()),
                SoundSource.HOSTILE, weakest.getX(), weakest.getY(), weakest.getZ(),
                1.2F, 1.0F, this.random.nextLong()));
        EclipseMod.LOGGER.info("Ferryman Lantern Gaze marks {} ({} HP, lowest aboard) — hunted for {}t",
                weakest.getScoreboardName(),
                String.format(java.util.Locale.ROOT, "%.1f", weakest.getHealth()), GAZE_MARK_TICKS);
    }

    private void clearGaze(String reason) {
        EclipseMod.LOGGER.info("Ferryman Lantern Gaze ended: {}", reason);
        this.gazeTargetId = null;
        this.gazeTicksLeft = 0;
        setGazing(false);
    }

    // --- participants / wipe / reset ---

    private void updateParticipants(List<ServerPlayer> fighters) {
        for (ServerPlayer player : fighters) {
            if (player.position().distanceTo(this.shipCenter) <= PARTICIPANT_RANGE
                    && this.participants.add(player.getUUID())) {
                EclipseMod.LOGGER.info("Ferryman fight: {} boarded ({} participant(s))",
                        player.getScoreboardName(), this.participants.size());
            }
        }
    }

    /**
     * Wipe = the Eclipse's victory: every participant that is still online is dead or a
     * ghost (banned). Announce, keep everyone ghosts, restore the ship and leave.
     */
    private boolean checkWipe(ServerLevel level) {
        if (this.participants.isEmpty()) {
            return false;
        }
        boolean anyOnline = false;
        for (UUID id : this.participants) {
            ServerPlayer player = level.getServer().getPlayerList().getPlayer(id);
            if (player == null) {
                continue;
            }
            anyOnline = true;
            if (player.isAlive() && !player.isSpectator() && !BanService.isBanned(player)) {
                return false; // Someone still stands.
            }
        }
        if (!anyOnline) {
            return false; // Mass logout is not a wipe; the reset timer handles it.
        }
        EclipseMod.LOGGER.info("Ferryman WIPE: all {} participant(s) dead or banned — Eclipse victory, "
                + "everyone stays a ghost", this.participants.size());
        AnnouncementService.announce(level.getServer(),
                "announce.eclipse.ferryman.wipe.title", "announce.eclipse.ferryman.wipe.sub",
                dev.projecteclipse.eclipse.network.S2CAnnouncePayload.STYLE_BOSS);
        restoreShip(level, "wipe");
        this.setHealth(this.getMaxHealth());
        this.discard();
        return true;
    }

    /** No living fighter aboard for 60 s after first contact: heal, restore and despawn. */
    private boolean tickReset(ServerLevel level, List<ServerPlayer> fighters) {
        if (this.participants.isEmpty() || !fighters.isEmpty()) {
            this.noFighterTicks = 0;
            return false;
        }
        if (++this.noFighterTicks < RESET_TICKS) {
            return false;
        }
        EclipseMod.LOGGER.info("Ferryman reset: no living fighter aboard for {} ticks — restoring ship and despawning",
                RESET_TICKS);
        restoreShip(level, "abandoned");
        this.setHealth(this.getMaxHealth());
        this.discard();
        return true;
    }

    /**
     * Drains the sink water, relights the lanterns and calms the crew. The drain sweeps
     * the ENTIRE above-deck footprint (deck+1 .. deck+{@value #MAX_SINK_LAYERS}) rather
     * than just the tracked placements: adjacent placed sources breed new untracked
     * sources (the vanilla infinite-water rule), which would re-flood the deck if only
     * the tracked blocks were removed. Nothing legitimate above the deck is water, so a
     * blanket water→air sweep is safe (waterlogged lanterns are restored by
     * {@link ShipLanterns#relightAll}).
     */
    private void restoreShip(ServerLevel level, String reason) {
        int drained = 0;
        for (int layer = 1; layer <= MAX_SINK_LAYERS; layer++) {
            int y = this.deckY + layer;
            for (int dx = -GhostShipBuilder.HALF_LENGTH; dx <= GhostShipBuilder.HALF_LENGTH; dx++) {
                int hw = GhostShipBuilder.halfWidthAt(dx);
                for (int dz = -hw; dz <= hw; dz++) {
                    BlockPos pos = new BlockPos(dx, y, dz);
                    if (level.getBlockState(pos).is(Blocks.WATER)) { // source AND flowing
                        level.setBlockAndUpdate(pos, Blocks.AIR.defaultBlockState());
                        drained++;
                    }
                }
            }
        }
        this.placedWater.clear();
        this.sinkLayers = 0;
        ShipLanterns.relightAll(level);
        DeckhandEntity.calmCrew(level);
        this.crewActive = false;
        EclipseMod.LOGGER.info("Ferryman ship restored ({}): {} water block(s) drained, lanterns relit, crew calmed",
                reason, drained);
    }

    // --- death / drops / finale handoff ---

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        this.spawnAtLocation(new ItemStack(EclipseItems.FERRYMAN_TOLL.get()));
        EclipseMod.LOGGER.info("Ferryman drop: 1 ferryman_toll at the corpse");
    }

    /**
     * Runs exactly once at the kill (vanilla guards on {@code !this.dead}): drops + XP
     * already fired from {@code super.die()}'s {@code dropAllDeathLoot}, and the ship
     * restore, defeat flag and mass-revive finale ({@link FinaleRitual#beginVictory}) fire
     * here — the scripted {@link #tickDeath} collapse afterwards only delays the body's
     * removal, so none of this can double-run. It also snaps the synced pose flags into
     * the death tableau: oar planted, kneel/telegraph/gaze cleared.
     */
    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (this.level() instanceof ServerLevel serverLevel) {
            // Death tableau for the collapse: he plants the oar and stands for the last toll.
            setTelegraphing(false);
            setKneeling(false);
            setGazing(false);
            setPlanted(true);
            this.noPhysics = true; // The deck no longer holds him: the body sinks through it.
            this.bossEvent.setProgress(0.0F); // The fight tick no longer runs to update it.
            restoreShip(serverLevel, "boss defeated");
            EclipseWorldState state = EclipseWorldState.get(serverLevel.getServer());
            state.setFerrymanDefeated(true);
            PacketDistributor.sendToPlayersNear(serverLevel, null, this.getX(), this.getY(), this.getZ(),
                    96.0D, new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, this.position()));
            EclipseMod.LOGGER.info("Ferryman defeated (source: {}) — ferrymanDefeated set, mass-revive finale starting",
                    damageSource.getMsgId());
            FinaleRitual.beginVictory(serverLevel.getServer());
        }
    }

    /**
     * Scripted ~{@value #DEATH_DURATION_TICKS}t collapse replacing the vanilla 20t
     * sideways tip-over ({@code FerrymanRenderer} suppresses the death flip and
     * {@code FerrymanModel} poses the body off {@code deathTime}): the oar stays planted
     * (synced in {@link #die}), the lantern flame gutters out over the first
     * {@value #DEATH_FLAME_OUT_TICKS}t ({@link #isLanternFlameLit}), the body sinks
     * upright through the deck trailing soul wisps, and one final bell toll + ship shudder
     * land just before the vanilla removal path runs. The finale handoff already fired
     * from {@link #die} — this only delays the body.
     */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: deathTime alone drives the gutter + the model's bow.
        }
        // Upright sink: a slow, steady descent into the deck (noPhysics since die();
        // re-asserted here because the field does not survive a mid-death reload).
        this.noPhysics = true;
        this.setDeltaMovement(0.0D, -0.028D, 0.0D);
        if (this.deathTime % 5 == 0) {
            serverLevel.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 1.5D, this.getZ(),
                    4, 0.35D, 0.6D, 0.35D, 0.01D);
        }
        if (this.deathTime == DEATH_BELL_TICK) {
            // The final toll: one deep bell + a shipwide shudder before the body fades.
            serverLevel.playSound(null, this.blockPosition(), EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                    SoundSource.HOSTILE, 1.6F, 0.5F);
            PacketDistributor.sendToPlayersNear(serverLevel, null, this.getX(), this.getY(), this.getZ(),
                    96.0D, S2CShakePayload.shake(0.8F, 20));
            EclipseMod.LOGGER.info("Ferryman death collapse: final bell tolled at deathTime {}", this.deathTime);
        }
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.isRemoved()) {
            // Vanilla removal path (poof cloud + KILLED removal), just 50t later.
            serverLevel.broadcastEntityEvent(this, (byte) 60);
            this.remove(Entity.RemovalReason.KILLED);
        }
    }

    /** Client pose hook: 0..1 through the scripted death collapse ({@code 0} while alive). */
    public float deathProgress(float partialTick) {
        if (this.deathTime <= 0) {
            return 0.0F;
        }
        return Mth.clamp((this.deathTime + partialTick - 1.0F) / (DEATH_DURATION_TICKS - 1.0F), 0.0F, 1.0F);
    }

    /**
     * Client render hook: whether the lantern flame still burns. During the death collapse
     * it gutters — a 4t on/off sputter for the first {@value #DEATH_FLAME_OUT_TICKS}t, then
     * dead for good ({@code FerrymanRenderer.EmissiveLayer} drops it from the glow pass).
     */
    public boolean isLanternFlameLit() {
        if (this.deathTime <= 0) {
            return true;
        }
        if (this.deathTime >= DEATH_FLAME_OUT_TICKS) {
            return false;
        }
        return (this.deathTime / 4) % 2 == 0;
    }

    // --- test hooks ---

    /**
     * {@code /eclipse boss ferryman phase} support: snaps health into the requested phase's
     * band; {@link #updatePhase} then runs the regular transition (crew, sink, bar color)
     * on the next tick.
     */
    public void forcePhase(int phase) {
        float fraction = switch (Mth.clamp(phase, 1, 3)) {
            case 2 -> 0.60F;
            case 3 -> 0.30F;
            default -> 1.0F;
        };
        this.setHealth(Math.max(1.0F, this.getMaxHealth() * fraction));
        EclipseMod.LOGGER.info("Ferryman phase forced toward {} (health snapped to {}/{})", phase,
                String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()),
                String.format(java.util.Locale.ROOT, "%.1f", this.getMaxHealth()));
    }

    // --- target helpers ---

    /** Living, non-banned, non-spectator players aboard (within 64 of the ship center). */
    private List<ServerPlayer> livingFighters(ServerLevel level) {
        List<ServerPlayer> fighters = new ArrayList<>();
        if (this.shipCenter == null) {
            return fighters;
        }
        for (ServerPlayer player : level.players()) {
            if (player.isAlive() && !player.isSpectator() && !BanService.isBanned(player)
                    && player.position().distanceTo(this.shipCenter) <= FIGHT_RANGE) {
                fighters.add(player);
            }
        }
        return fighters;
    }

    /** The Lantern Gaze mark while active, else the nearest living fighter. */
    @Nullable
    private ServerPlayer currentTarget(ServerLevel level, List<ServerPlayer> fighters) {
        if (this.gazeTicksLeft > 0 && this.gazeTargetId != null) {
            ServerPlayer marked = level.getServer().getPlayerList().getPlayer(this.gazeTargetId);
            if (marked != null && marked.isAlive() && marked.level() == level && !BanService.isBanned(marked)) {
                return marked;
            }
        }
        ServerPlayer nearest = null;
        double best = Double.MAX_VALUE;
        for (ServerPlayer player : fighters) {
            double dist = player.distanceToSqr(this);
            if (dist < best) {
                best = dist;
                nearest = player;
            }
        }
        return nearest;
    }

    /** Online ghosts = banned players (they participate by re-lighting lanterns). */
    private static int ghostsOnline(ServerLevel level) {
        int ghosts = 0;
        for (ServerPlayer player : level.getServer().getPlayerList().getPlayers()) {
            if (BanService.isBanned(player)) {
                ghosts++;
            }
        }
        return ghosts;
    }

    /** WHITE (P1) → PURPLE (P2) → RED (P3) per spec §2.2. */
    private void applyBossbarColor(int phase) {
        this.bossEvent.setColor(switch (phase) {
            case 2 -> BossEvent.BossBarColor.PURPLE;
            case 3 -> BossEvent.BossBarColor.RED;
            default -> BossEvent.BossBarColor.WHITE;
        });
    }

    // --- bossbar (wither pattern + W8 skin payload for every viewer incl. late joiners) ---

    @Override
    public void startSeenByPlayer(ServerPlayer player) {
        super.startSeenByPlayer(player);
        this.bossEvent.addPlayer(player);
        PacketDistributor.sendToPlayer(player,
                new S2CBossbarStylePayload(this.bossEvent.getId(), S2CBossbarStylePayload.THEME_BOSS));
    }

    @Override
    public void stopSeenByPlayer(ServerPlayer player) {
        super.stopSeenByPlayer(player);
        this.bossEvent.removePlayer(player);
    }

    @Override
    public void setCustomName(@Nullable Component name) {
        super.setCustomName(name);
        if (name != null) {
            this.bossEvent.setName(name);
        }
    }

    // --- client animation hooks ---

    /** Advances the smooth clock and eases the raise/kneel/plant pose weights (client only). */
    private void tickClientAnim() {
        this.animAgePrev = this.animAge;
        this.animAge += getPhase() >= 3 ? 1.4F : 1.0F;
        this.raiseLerpPrev = this.raiseLerp;
        this.raiseLerp += ((isTelegraphing() ? 1.0F : 0.0F) - this.raiseLerp) * 0.16F;
        this.kneelLerpPrev = this.kneelLerp;
        this.kneelLerp += ((isKneeling() ? 1.0F : 0.0F) - this.kneelLerp) * 0.08F;
        this.plantLerpPrev = this.plantLerp;
        this.plantLerp += ((isPlanted() ? 1.0F : 0.0F) - this.plantLerp) * 0.08F;
    }

    /** Smooth model animation age (rowing idle, chain swing; advances ×1.4 in P3). */
    public float animAge(float partialTick) {
        return Mth.lerp(partialTick, this.animAgePrev, this.animAge);
    }

    /** 0..1 blend toward the raised-oar telegraph pose. */
    public float raiseAmount(float partialTick) {
        return Mth.lerp(partialTick, this.raiseLerpPrev, this.raiseLerp);
    }

    /** 0..1 blend toward the P2 kneel-at-the-stern pose. */
    public float kneelAmount(float partialTick) {
        return Mth.lerp(partialTick, this.kneelLerpPrev, this.kneelLerp);
    }

    /** 0..1 blend toward the P3 planted-oar pose. */
    public float plantAmount(float partialTick) {
        return Mth.lerp(partialTick, this.plantLerpPrev, this.plantLerp);
    }

    // --- floating-boss chassis ---

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_PHASE, 1);
        builder.define(DATA_TELEGRAPH, false);
        builder.define(DATA_KNEELING, false);
        builder.define(DATA_PLANTED, false);
        builder.define(DATA_GAZING, false);
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public void knockback(double strength, double x, double z) {
        // Anchored: the fight's movement script owns the velocity.
    }

    @Override
    public boolean causeFallDamage(float fallDistance, float multiplier, DamageSource source) {
        return false;
    }

    // Air supply: the ferryman is tagged minecraft:can_breathe_under_water (data tag) so
    // his own P3 sink water cannot drown him mid-fight.

    @Override
    public void checkDespawn() {
        // Never despawns naturally; tickReset() handles abandonment itself.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    public void travel(Vec3 travelVector) {
        // Gravity-free drift: velocity is set directly by the movement script each tick.
        if (this.isControlledByLocalInstance()) {
            this.move(MoverType.SELF, this.getDeltaMovement());
            this.setDeltaMovement(this.getDeltaMovement().scale(0.91D));
        }
    }

    // --- sounds ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return EclipseSounds.BOSS_FERRYMAN_AMBIENT.get();
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.DROWNED_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WARDEN_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.7F;
    }

    // --- persistence ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt("ScaledPlayers", this.scaledPlayers);
        if (this.shipCenter != null) {
            compound.putDouble("ShipX", this.shipCenter.x);
            compound.putDouble("ShipY", this.shipCenter.y);
            compound.putDouble("ShipZ", this.shipCenter.z);
            compound.putInt("DeckY", this.deckY);
        }
        compound.putBoolean("CrewActive", this.crewActive);
        compound.putInt("RequiredLanterns", this.requiredLanterns);
        compound.putInt("SinkLayers", this.sinkLayers);
        compound.putInt("SinkTimer", this.sinkTimer);
        ListTag waterList = new ListTag();
        for (BlockPos pos : this.placedWater) {
            waterList.add(LongTag.valueOf(pos.asLong()));
        }
        compound.put("PlacedWater", waterList);
        ListTag participantList = new ListTag();
        for (UUID id : this.participants) {
            participantList.add(NbtUtils.createUUID(id));
        }
        compound.put("Participants", participantList);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("ScaledPlayers")) {
            this.scaledPlayers = Math.max(1, compound.getInt("ScaledPlayers"));
        }
        if (compound.contains("ShipX")) {
            this.shipCenter = new Vec3(compound.getDouble("ShipX"),
                    compound.getDouble("ShipY"), compound.getDouble("ShipZ"));
            this.deckY = compound.getInt("DeckY");
        }
        this.crewActive = compound.getBoolean("CrewActive");
        this.requiredLanterns = compound.getInt("RequiredLanterns");
        this.sinkLayers = compound.getInt("SinkLayers");
        if (compound.contains("SinkTimer")) {
            this.sinkTimer = Math.max(1, compound.getInt("SinkTimer"));
        }
        for (Tag entry : compound.getList("PlacedWater", Tag.TAG_LONG)) {
            this.placedWater.add(BlockPos.of(((LongTag) entry).getAsLong()));
        }
        for (Tag entry : compound.getList("Participants", Tag.TAG_INT_ARRAY)) {
            this.participants.add(NbtUtils.loadUUID(entry));
        }
        // Re-derive the phase + poses so a reloaded fight resumes cleanly.
        float fraction = this.getMaxHealth() > 0.0F ? this.getHealth() / this.getMaxHealth() : 1.0F;
        this.lastPhase = fraction > 2.0F / 3.0F ? 1 : fraction > 1.0F / 3.0F ? 2 : 3;
        setPhase(this.lastPhase);
        applyBossbarColor(this.lastPhase);
        setKneeling(this.crewActive);
        setPlanted(this.lastPhase >= 3);
        if (this.hasCustomName()) {
            this.bossEvent.setName(this.getDisplayName());
        }
    }

    // --- shared helpers ---

    /** Look helper for the fight: turns body + head toward a target position. */
    protected void faceTowards(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }
}
