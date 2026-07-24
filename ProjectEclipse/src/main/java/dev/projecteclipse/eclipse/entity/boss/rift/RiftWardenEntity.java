package dev.projecteclipse.eclipse.entity.boss.rift;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.dungeon.DungeonEntities;
import dev.projecteclipse.eclipse.entity.dungeon.ShadowBoltProjectile;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.Component;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.minecraft.world.Containers;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;
import software.bernie.geckolib.animation.AnimationController;

/**
 * The Rift Warden / Der Risswächter — the Collapsed Vault gauntlet's mini-boss
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4, worker P6-W10/W910): a 3-block
 * vertically-split knight — polished obsidian armor on the left, a boiling void tear
 * where the right half should be — with a purple PROGRESS boss bar and the Herald's
 * house fight chassis (scripted {@link #tick()}, no vanilla goals; arena self-pin;
 * participant tracking; outside-ring damage deflect; wipe/reset; scripted death;
 * {@code LOGGER.info} breadcrumbs on every transition).
 *
 * <p><b>Fight</b> — two phases split at 50% HP:</p>
 * <ul>
 *   <li><b>P1 "Blades"</b> (100–50%): stalks the nearest participant on the ground,
 *       {@value #MELEE_RANGE}-range blade sweeps ({@code attack} anim, 7 dmg); every
 *       {@value #P1_VOLLEY_CADENCE}t a <b>shadow volley</b> — {@value #VOLLEY_TELEGRAPH_TICKS}t
 *       rooted raise ({@code volley} anim + synced telegraph flag + rising tell) then
 *       {@value #VOLLEY_BOLTS} homing-lite {@link ShadowBoltProjectile}s spread across the
 *       participants; every {@value #BLINK_INTERVAL}t a <b>Rift Step</b>: the destination
 *       (8 blocks behind the marked player, clamped inside the ring) chimes rising
 *       amethyst for {@value #BLINK_CHIME_TICKS}t (fairness cue — the sound sits AT the
 *       destination), then {@code blink_out} + reverse-portal implosion,
 *       {@value #BLINK_OUT_TICKS}t of vanish, reappear with {@code blink_in} + burst and
 *       an immediate single sweep if someone hugs the arrival point.</li>
 *   <li><b>P2 "Rifts"</b> (≤50%): entry summons <b>2 Eclipse Cultists</b> at the ring edge
 *       (by-id registry lookup {@code eclipse:eclipse_cultist} — skipped with a warning
 *       while the dungeon registrar is unwired; {@code summon} anim); volleys accelerate
 *       to {@value #P2_VOLLEY_CADENCE}t and each release leaves a
 *       {@value #STAGGER_TICKS}t <b>weakpoint stagger</b> ({@code stagger} anim, rooted,
 *       ×{@value #STAGGER_DAMAGE_FACTOR} damage taken) — the punish window.</li>
 * </ul>
 *
 * <p><b>Scaling</b> (snapshotted at summon): HP = {@value #BASE_MAX_HEALTH}·(1+0.35·(n−1))
 * for n living players within {@value #SCALING_RANGE} blocks. <b>Soft enrage</b>: after
 * {@value #SOFT_ENRAGE_TICKS}t the volley cadence shortens 25%. <b>Wipe/reset</b>: no
 * player within {@value #RESET_RANGE} blocks for {@value #RESET_TICKS}t → heal to full,
 * despawn any leftover cultist adds and despawn (P1's vault can re-trigger the summon).
 * <b>Death</b>: {@value #DEATH_DURATION_TICKS}t scripted implosion (blades plant, the
 * rift half swallows the body; upright via the renderer) ending in a camera shake + soul
 * burst. Drops: loot table {@code eclipse:entities/rift_warden} (guaranteed umbral shards
 * + the Replant book + trophy) plus 1 {@code rift_core} by P4-registry lookup (fallback
 * 4 umbral shards) and 2 umbral shards at each participant's feet (Herald pattern).</p>
 *
 * <p><b>Placement seam:</b> NOT a spawner mob — P1's vault boss room calls
 * {@link #summonAt(ServerLevel, BlockPos)} (documented in
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md}); the fight self-pins its
 * r={@value RiftAnchor#ARENA_RADIUS} arena at the summon point, so plain
 * {@code /summon eclipse:rift_warden} works anywhere with a ≥ 20×20 flat floor.</p>
 */
public class RiftWardenEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "rift_warden";
    public static final String ANIM_VOLLEY = "volley";
    public static final String ANIM_BLINK_OUT = "blink_out";
    public static final String ANIM_BLINK_IN = "blink_in";
    public static final String ANIM_SUMMON = "summon";
    public static final String ANIM_STAGGER = "stagger";

    public static final float BASE_MAX_HEALTH = 200.0F;
    /** Scripted death implosion length (vanilla tips over after 20t; see {@link #tickDeath}). */
    public static final int DEATH_DURATION_TICKS = 60;

    private static final double SCALING_RANGE = 32.0D;
    private static final int P1_VOLLEY_CADENCE = 120;
    private static final int P2_VOLLEY_CADENCE = 70;
    private static final int VOLLEY_TELEGRAPH_TICKS = 20;
    private static final int VOLLEY_BOLTS = 5;
    private static final int BLINK_INTERVAL = 200;
    private static final int BLINK_CHIME_TICKS = 15;
    private static final int BLINK_OUT_TICKS = 10;
    private static final double BLINK_BEHIND_BLOCKS = 8.0D;
    private static final int STAGGER_TICKS = 40;
    private static final float STAGGER_DAMAGE_FACTOR = 1.5F;
    private static final int SUMMONED_CULTISTS = 2;
    /** Soft enrage after 6 min of fight time: volley cadence −25% (plan §2.4). */
    private static final int SOFT_ENRAGE_TICKS = 6 * 60 * 20;
    private static final double MELEE_RANGE = 3.2D;
    private static final int MELEE_COOLDOWN_TICKS = 30;
    private static final int RESET_TICKS = 1200; // 60 s
    private static final double RESET_RANGE = 24.0D;
    private static final int DEFLECT_CUE_INTERVAL_TICKS = 20;
    private static final double SUMMON_DEDUP_RANGE = 64.0D;
    /** W4 loot ceremony: first participant payout keyframe of the death implosion. */
    private static final int DEATH_PAYOUT_START_TICK = 15;

    /** Current phase 1..2 (synced; lets the renderer/model react if it ever wants to). */
    private static final EntityDataAccessor<Integer> DATA_PHASE =
            SynchedEntityData.defineId(RiftWardenEntity.class, EntityDataSerializers.INT);
    /** True while a volley is winding up (rift half flares emissive on the glowmask). */
    private static final EntityDataAccessor<Boolean> DATA_TELEGRAPH =
            SynchedEntityData.defineId(RiftWardenEntity.class, EntityDataSerializers.BOOLEAN);
    /** True during the post-volley weakpoint window (P2 punish opening). */
    private static final EntityDataAccessor<Boolean> DATA_STAGGERED =
            SynchedEntityData.defineId(RiftWardenEntity.class, EntityDataSerializers.BOOLEAN);

    private final ServerBossEvent bossEvent = new ServerBossEvent(
            Component.translatable("entity.eclipse.rift_warden.bossbar"),
            BossEvent.BossBarColor.PURPLE, BossEvent.BossBarOverlay.PROGRESS);

    // --- server fight state (arena + participants persisted in NBT) ---
    @Nullable
    private RiftAnchor anchor;
    private int scaledPlayers = 1;
    private final Set<UUID> participants = new HashSet<>();

    private int volleyTimer = P1_VOLLEY_CADENCE;
    private int telegraphTimer = -1;
    private int blinkCooldown = BLINK_INTERVAL;
    private int chimeTimer = -1;
    private int blinkOutTimer = -1;
    @Nullable
    private Vec3 blinkDest;
    @Nullable
    private UUID blinkTargetId;
    private int staggerTimer = -1;
    private int meleeCooldown;
    private int fightTicks;
    private int noPlayerTicks;
    private int lastPhase = 1;
    private int lastDeflectCueTick = -DEFLECT_CUE_INTERVAL_TICKS;
    private boolean addsSummoned;
    private boolean warnedBoltUnbound;
    // W4 loot ceremony (transient — die() runs exactly once, so a restart mid-implosion
    // loses only the staggering, never the guaranteed corpse drops).
    private final ArrayDeque<UUID> deathPayoutQueue = new ArrayDeque<>();
    private int deathPayoutInterval = 12;
    private int deathPayoutIndex;

    // Client-side stagger slump ease (W4 IDEA-16 DATA_STAGGERED flourish; renderer-only
    // weakpoint language — see tickClientAnim / staggerSlump).
    private float staggerSlump;
    private float staggerSlumpPrev;

    public RiftWardenEntity(EntityType<? extends RiftWardenEntity> entityType, Level level) {
        super(entityType, level);
        this.setPersistenceRequired();
        this.noCulling = true;
        this.xpReward = 30;
    }

    /** Spec §2.4: 200 HP base, dmg 7 (blade), armor 4, KB resist 1.0. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, BASE_MAX_HEALTH)
                .add(Attributes.ATTACK_DAMAGE, 7.0D)
                .add(Attributes.ARMOR, 4.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.3D)
                .add(Attributes.FOLLOW_RANGE, 48.0D);
    }

    // --- summoning (the P1 vault boss-room seam) ---

    /**
     * Places the warden at the arena center with arrival FX and pins the fight there —
     * the single call P1's Collapsed Vault boss room makes (wiring doc seam). The room
     * should be ≥ 20×20×8 with a flat floor; the ring self-pins at {@code center}. Dedup
     * guard: a live warden within {@value #SUMMON_DEDUP_RANGE} blocks is returned instead
     * of stacking a second boss (vault re-triggers stay safe).
     */
    public static RiftWardenEntity summonAt(ServerLevel level, BlockPos center) {
        List<RiftWardenEntity> existing = level.getEntitiesOfClass(RiftWardenEntity.class,
                new AABB(center).inflate(SUMMON_DEDUP_RANGE), RiftWardenEntity::isAlive);
        if (!existing.isEmpty()) {
            EclipseMod.LOGGER.info("Rift Warden summon skipped: a live warden already fights within {} blocks of {}",
                    (int) SUMMON_DEDUP_RANGE, center.toShortString());
            return existing.get(0);
        }
        RiftWardenEntity warden = RiftEntities.RIFT_WARDEN.get().create(level);
        if (warden == null) {
            throw new IllegalStateException("Rift Warden entity type failed to instantiate");
        }
        double x = center.getX() + 0.5D;
        double z = center.getZ() + 0.5D;
        warden.moveTo(x, center.getY(), z, level.getRandom().nextFloat() * 360.0F, 0.0F);
        warden.initFight(level, new Vec3(x, center.getY(), z), center.getY());
        level.addFreshEntity(warden);
        // Arrival: a rift tears open — implosion particles, chime chord, deep teleport boom.
        level.sendParticles(ParticleTypes.REVERSE_PORTAL, x, center.getY() + 1.5D, z,
                60, 0.8D, 1.4D, 0.8D, 0.1D);
        level.playSound(null, center, SoundEvents.ENDERMAN_TELEPORT, SoundSource.HOSTILE, 1.2F, 0.4F);
        level.playSound(null, center, SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.HOSTILE, 1.5F, 0.5F);
        // W4 intro title card: the name decodes in over the arrival FX (BossIntroOverlay).
        dev.projecteclipse.eclipse.network.boss.BossPayloads.sendIntro(level, warden.position(),
                "entity.eclipse.rift_warden", "announce.eclipse.boss.intro.rift_warden");
        EclipseMod.LOGGER.info("Rift Warden summoned at {} — scaled for {} player(s): {} HP; bossbar {} created",
                center.toShortString(), warden.scaledPlayers, warden.getMaxHealth(), warden.bossEvent.getId());
        return warden;
    }

    /** Pins the arena and applies the summon-time player-count scaling (spec §2.4). */
    private void initFight(ServerLevel level, Vec3 center, int groundY) {
        this.anchor = new RiftAnchor(center, groundY);
        long nearby = level.players().stream()
                .filter(player -> !player.isSpectator() && player.isAlive())
                .filter(player -> player.position().distanceTo(center) <= SCALING_RANGE)
                .count();
        this.scaledPlayers = (int) Math.max(1L, nearby);
        double maxHealth = BASE_MAX_HEALTH * (1.0D + 0.35D * (this.scaledPlayers - 1));
        this.getAttribute(Attributes.MAX_HEALTH).setBaseValue(maxHealth);
        this.setHealth((float) maxHealth);
    }

    /** Lazy arena init for plain {@code /summon eclipse:rift_warden} (acceptance path). */
    private void ensureFightInitialized(ServerLevel level) {
        if (this.anchor != null) {
            return;
        }
        initFight(level, this.position(), this.blockPosition().getY());
        EclipseMod.LOGGER.info("Rift Warden arena auto-pinned at ({}, {}, {}) — {} player(s), {} HP; bossbar {} created",
                String.format(java.util.Locale.ROOT, "%.1f", this.getX()), this.blockPosition().getY(),
                String.format(java.util.Locale.ROOT, "%.1f", this.getZ()),
                this.scaledPlayers, this.getMaxHealth(), this.bossEvent.getId());
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK));
        action.triggerableAnim(ANIM_VOLLEY, EclipseGeoAnimations.once(GEO_ID, ANIM_VOLLEY));
        action.triggerableAnim(ANIM_BLINK_OUT, EclipseGeoAnimations.once(GEO_ID, ANIM_BLINK_OUT));
        action.triggerableAnim(ANIM_BLINK_IN, EclipseGeoAnimations.once(GEO_ID, ANIM_BLINK_IN));
        action.triggerableAnim(ANIM_SUMMON, EclipseGeoAnimations.once(GEO_ID, ANIM_SUMMON));
        action.triggerableAnim(ANIM_STAGGER, EclipseGeoAnimations.once(GEO_ID, ANIM_STAGGER));
        // W4 IDEA-16 #3 death slow-mo: the held death anim eases toward ~0.2x speed over
        // the first ~8 death ticks (Herald tickClientAnim pattern, Geo-boss flavor;
        // client-side render illusion — server ticks untouched).
        action.setAnimationSpeedHandler(warden -> this.deathTime > 0
                ? Math.max(0.2D, 1.0D - this.deathTime * 0.1D) : 1.0D);
    }

    // --- synced state accessors ---

    public int getPhase() {
        return this.entityData.get(DATA_PHASE);
    }

    private void setPhase(int phase) {
        this.entityData.set(DATA_PHASE, Mth.clamp(phase, 1, 2));
    }

    public boolean isTelegraphing() {
        return this.entityData.get(DATA_TELEGRAPH);
    }

    private void setTelegraphing(boolean telegraphing) {
        this.entityData.set(DATA_TELEGRAPH, telegraphing);
    }

    public boolean isStaggered() {
        return this.entityData.get(DATA_STAGGERED);
    }

    private void setStaggered(boolean staggered) {
        this.entityData.set(DATA_STAGGERED, staggered);
    }

    // --- fight ticking (house pattern: everything scripted, no vanilla goals) ---

    @Override
    protected void registerGoals() {
        // Deliberately empty: the boss script in tick() owns targeting and movement.
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            tickClientAnim();
        } else if (this.isAlive() && this.level() instanceof ServerLevel serverLevel) {
            ensureFightInitialized(serverLevel);
            tickFight(serverLevel);
        }
    }

    /**
     * Eases the stagger slump toward its synced target (client only, Herald
     * {@code tickClientAnim} pattern) — the renderer reads {@link #staggerSlump} to sag
     * the knight while the weakpoint window is open (W4 IDEA-16 {@code DATA_STAGGERED}
     * flourish). Fast sag-in (the stumble), slower recovery (the weary straighten-up).
     */
    private void tickClientAnim() {
        this.staggerSlumpPrev = this.staggerSlump;
        float target = isStaggered() && this.deathTime <= 0 ? 1.0F : 0.0F;
        this.staggerSlump += (target - this.staggerSlump)
                * (target > this.staggerSlump ? 0.28F : 0.10F);
    }

    /** Smooth 0..1 weakpoint slump for the renderer (client-side visual only). */
    public float staggerSlump(float partialTick) {
        return Mth.lerp(partialTick, this.staggerSlumpPrev, this.staggerSlump);
    }

    private void tickFight(ServerLevel level) {
        this.bossEvent.setProgress(this.getHealth() / this.getMaxHealth());
        this.fightTicks++;
        if (this.fightTicks == SOFT_ENRAGE_TICKS) {
            EclipseMod.LOGGER.info("Rift Warden soft enrage after {}t: volley cadence -25%", SOFT_ENRAGE_TICKS);
        }
        updatePhase(level);
        updateParticipants(level);
        if (tickReset(level)) {
            return;
        }
        tickArenaLock(level);
        if (this.meleeCooldown > 0) {
            this.meleeCooldown--;
        }
        if (this.staggerTimer >= 0) {
            tickStagger(level);
            return; // Weakpoint open: rooted, no attacks, eat damage.
        }
        tickBlink(level);
        if (this.blinkOutTimer >= 0) {
            // Mid-vanish: hold still inside the collapsing rift, nothing else acts.
            this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
            return;
        }
        tickVolley(level);
        if (this.telegraphTimer < 0) {
            tickStalkAndSweep(level); // Rooted while raising a volley.
        } else {
            this.getNavigation().stop();
        }
    }

    /** Phase = HP fraction vs the 50% break; one transition per call (Herald pattern). */
    private boolean updatePhase(ServerLevel level) {
        float fraction = this.getHealth() / this.getMaxHealth();
        int target = fraction > 0.5F ? 1 : 2;
        if (target == this.lastPhase) {
            return false;
        }
        int phase = this.lastPhase + (target > this.lastPhase ? 1 : -1);
        EclipseMod.LOGGER.info("Rift Warden phase {} -> {} at {}/{} HP", this.lastPhase, phase,
                String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()),
                String.format(java.util.Locale.ROOT, "%.1f", this.getMaxHealth()));
        this.lastPhase = phase;
        setPhase(phase);
        setTelegraphing(false);
        this.telegraphTimer = -1;
        level.playSound(null, this.blockPosition(), SoundEvents.WITHER_SPAWN, SoundSource.HOSTILE,
                0.8F, phase == 2 ? 1.3F : 0.8F);
        if (phase == 2) {
            summonCultistAdds(level);
            // Faster pressure immediately: don't let a long P1 timer straddle the break.
            this.volleyTimer = Math.min(this.volleyTimer, currentVolleyCadence());
        }
        return true;
    }

    /** Everyone entering the combat ring joins the fight (and stays enrolled for drops). */
    private void updateParticipants(ServerLevel level) {
        if (this.anchor == null) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && this.anchor.isInside(player.position())
                    && this.participants.add(player.getUUID())) {
                EclipseMod.LOGGER.info("Rift Warden fight: {} entered the arena ({} participant(s))",
                        player.getScoreboardName(), this.participants.size());
            }
        }
    }

    /**
     * Abandon-reset (plan wipe rules): no players within {@value #RESET_RANGE} blocks for
     * {@value #RESET_TICKS}t → heal to full, clean up cultist adds, despawn ship-shape.
     */
    private boolean tickReset(ServerLevel level) {
        boolean anyoneNear = level.players().stream().anyMatch(player ->
                !player.isSpectator() && player.isAlive()
                        && player.position().distanceTo(this.position()) <= RESET_RANGE);
        if (anyoneNear) {
            this.noPlayerTicks = 0;
            return false;
        }
        if (++this.noPlayerTicks < RESET_TICKS) {
            return false;
        }
        EclipseMod.LOGGER.info("Rift Warden reset: no players within {} blocks for {} ticks — healing, "
                + "cleaning up adds and despawning", RESET_RANGE, RESET_TICKS);
        discardCultistAdds(level);
        this.setHealth(this.getMaxHealth());
        this.discard();
        return true;
    }

    /**
     * Leash + wall: inward impulse past r=14 and the reverse-portal ring segment. The
     * synced phase feeds {@link RiftAnchor#particleWall} so P2 shows the torn-rift wall
     * (W4 IDEA-16 #2, visual-only).
     */
    private void tickArenaLock(ServerLevel level) {
        if (this.anchor == null) {
            return;
        }
        for (ServerPlayer player : livingParticipants(level)) {
            this.anchor.impulseInward(player, this.tickCount);
            if (this.tickCount % 8 == 0) {
                this.anchor.particleWall(level, player, getPhase());
            }
        }
    }

    // --- P1/P2 movement + blade sweep ---

    /** Ground stalker: path to the nearest participant, sweep inside blade range. */
    private void tickStalkAndSweep(ServerLevel level) {
        ServerPlayer target = nearestParticipant(level);
        if (target == null) {
            this.getNavigation().stop();
            return;
        }
        this.getLookControl().setLookAt(target, 30.0F, 30.0F);
        double dist = this.distanceTo(target);
        if (dist <= MELEE_RANGE) {
            this.getNavigation().stop();
            faceTowards(target.position());
            if (this.meleeCooldown <= 0) {
                this.meleeCooldown = MELEE_COOLDOWN_TICKS;
                doHurtTarget(target);
            }
        } else if (this.tickCount % 5 == 0) {
            this.getNavigation().moveTo(target, 1.0D);
        }
    }

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // Single rift-blade sweep.
            this.level().playSound(null, this.blockPosition(), SoundEvents.PLAYER_ATTACK_SWEEP,
                    SoundSource.HOSTILE, 1.0F, 0.6F);
        }
        return hurt;
    }

    // --- shadow volleys ---

    /** Effective volley cadence: phase base, −25% after the 6-minute soft enrage. */
    private int currentVolleyCadence() {
        int base = getPhase() >= 2 ? P2_VOLLEY_CADENCE : P1_VOLLEY_CADENCE;
        return this.fightTicks >= SOFT_ENRAGE_TICKS ? base * 3 / 4 : base;
    }

    private void tickVolley(ServerLevel level) {
        if (this.telegraphTimer < 0) {
            if (--this.volleyTimer > 0) {
                return;
            }
            this.telegraphTimer = VOLLEY_TELEGRAPH_TICKS;
            setTelegraphing(true);
            triggerAction(ANIM_VOLLEY);
            this.getNavigation().stop();
            level.playSound(null, this.blockPosition(), SoundEvents.BEACON_POWER_SELECT,
                    SoundSource.HOSTILE, 1.0F, 0.7F);
            level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.HOSTILE, 1.2F, 0.6F);
            return;
        }
        // Rift half boils while the raise holds.
        if (this.telegraphTimer % 4 == 0) {
            level.sendParticles(ParticleTypes.WITCH,
                    this.getX(), this.getY() + 2.0D, this.getZ(), 4, 0.5D, 0.7D, 0.5D, 0.02D);
        }
        if (--this.telegraphTimer >= 0) {
            return;
        }
        setTelegraphing(false);
        this.volleyTimer = currentVolleyCadence();
        releaseVolley(level);
        if (getPhase() >= 2) {
            beginStagger(level); // The weakpoint opens right after every P2 release.
        }
    }

    /** {@value #VOLLEY_BOLTS} homing-lite bolts spread across the shuffled participants. */
    private void releaseVolley(ServerLevel level) {
        if (!DungeonEntities.SHADOW_BOLT.isBound()) {
            if (!this.warnedBoltUnbound) {
                this.warnedBoltUnbound = true;
                EclipseMod.LOGGER.warn("Rift Warden volley skipped: eclipse:shadow_bolt not registered "
                        + "(DungeonEntities wiring line missing — see docs/plans_v3/wiring/P6-W910_wiring.md)");
            }
            return;
        }
        List<ServerPlayer> targets = livingParticipants(level);
        if (targets.isEmpty()) {
            EclipseMod.LOGGER.info("Rift Warden volley fizzled: no living participants in the arena");
            return;
        }
        Collections.shuffle(targets, new java.util.Random(this.random.nextLong()));
        Vec3 eye = this.getEyePosition();
        for (int i = 0; i < VOLLEY_BOLTS; i++) {
            ServerPlayer target = targets.get(i % targets.size());
            Vec3 aim = new Vec3(target.getX(), target.getY(0.5D), target.getZ()).subtract(eye);
            if (aim.lengthSqr() < 1.0E-4D) {
                continue;
            }
            // Slight per-bolt yaw scatter so a multi-bolt burst reads as a fan, not a beam.
            Vec3 direction = aim.normalize().yRot((this.random.nextFloat() - 0.5F) * 0.35F);
            level.addFreshEntity(new ShadowBoltProjectile(level, this, direction, target));
        }
        level.playSound(null, this.blockPosition(), SoundEvents.SHULKER_SHOOT, SoundSource.HOSTILE, 1.0F, 0.5F);
        EclipseMod.LOGGER.info("Rift Warden volley: fired {} shadow bolt(s) at {} target(s)",
                VOLLEY_BOLTS, Math.min(VOLLEY_BOLTS, targets.size()));
    }

    // --- P2 weakpoint stagger ---

    private void beginStagger(ServerLevel level) {
        this.staggerTimer = STAGGER_TICKS;
        setStaggered(true);
        triggerAction(ANIM_STAGGER);
        this.getNavigation().stop();
        level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.HOSTILE, 1.2F, 0.5F);
        EclipseMod.LOGGER.info("Rift Warden weakpoint OPEN for {}t (x{} damage taken)",
                STAGGER_TICKS, STAGGER_DAMAGE_FACTOR);
    }

    private void tickStagger(ServerLevel level) {
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        if (this.staggerTimer % 5 == 0) {
            // The exposed void core sparks — the visual "hit me now".
            level.sendParticles(ParticleTypes.END_ROD,
                    this.getX(), this.getY() + 1.6D, this.getZ(), 3, 0.4D, 0.5D, 0.4D, 0.02D);
        }
        if (--this.staggerTimer < 0) {
            setStaggered(false);
            EclipseMod.LOGGER.info("Rift Warden weakpoint closed");
        }
    }

    // --- rift step (blink telegraphed by rising chimes AT the destination) ---

    private void tickBlink(ServerLevel level) {
        if (this.chimeTimer >= 0) {
            tickChimeTelegraph(level);
            return;
        }
        if (this.blinkOutTimer >= 0) {
            if (--this.blinkOutTimer < 0) {
                executeBlink(level);
            }
            return;
        }
        if (--this.blinkCooldown > 0 || this.telegraphTimer >= 0) {
            return; // Never blink out of a volley raise: one telegraph at a time.
        }
        List<ServerPlayer> targets = livingParticipants(level);
        if (targets.isEmpty() || this.anchor == null) {
            this.blinkCooldown = 60;
            return;
        }
        ServerPlayer target = targets.get(this.random.nextInt(targets.size()));
        Vec3 dest = findBlinkDestination(level, target);
        if (dest == null) {
            this.blinkCooldown = 80;
            EclipseMod.LOGGER.info("Rift Warden rift-step skipped: no clear destination behind {}",
                    target.getScoreboardName());
            return;
        }
        this.blinkDest = dest;
        this.blinkTargetId = target.getUUID();
        this.chimeTimer = BLINK_CHIME_TICKS;
        EclipseMod.LOGGER.info("Rift Warden rift-step telegraphed: {}t of chimes at ({}, {}, {}) behind {}",
                BLINK_CHIME_TICKS, String.format(java.util.Locale.ROOT, "%.1f", dest.x),
                String.format(java.util.Locale.ROOT, "%.1f", dest.y),
                String.format(java.util.Locale.ROOT, "%.1f", dest.z), target.getScoreboardName());
    }

    /**
     * The destination {@value #BLINK_BEHIND_BLOCKS} blocks behind the marked player
     * (opposite their view), clamped inside the ring, snapped to the floor and
     * collision-checked — falls back to 4 then 2 blocks behind, or null (skip) if the
     * room blocks all three.
     */
    @Nullable
    private Vec3 findBlinkDestination(ServerLevel level, ServerPlayer target) {
        Vec3 back = target.getViewVector(1.0F).multiply(1.0D, 0.0D, 1.0D);
        if (back.lengthSqr() < 1.0E-4D) {
            back = new Vec3(1.0D, 0.0D, 0.0D); // Looking straight down: any side works.
        }
        back = back.normalize().scale(-1.0D);
        for (double distance : new double[] {BLINK_BEHIND_BLOCKS, 4.0D, 2.0D}) {
            Vec3 raw = target.position().add(back.scale(distance));
            Vec3 clamped = this.anchor != null ? this.anchor.clampInside(raw, 1.5D) : raw;
            Vec3 dest = snapToFloor(level, clamped);
            AABB box = this.getDimensions(this.getPose()).makeBoundingBox(dest);
            if (level.noCollision(this, box)) {
                return dest;
            }
        }
        return null;
    }

    /** Walks down from 2 above the sample point to the first solid floor (max 10). */
    private Vec3 snapToFloor(ServerLevel level, Vec3 pos) {
        BlockPos.MutableBlockPos cursor = BlockPos.containing(pos.x, pos.y + 2.0D, pos.z).mutable();
        for (int i = 0; i < 10; i++) {
            BlockPos below = cursor.below();
            if (!level.getBlockState(below).getCollisionShape(level, below).isEmpty()) {
                return new Vec3(pos.x, cursor.getY(), pos.z);
            }
            cursor.move(Direction.DOWN);
        }
        return pos; // No floor found: keep the target's height (flat-room contract).
    }

    /** Fairness cue: rising amethyst chimes + a portal shimmer AT the destination point. */
    private void tickChimeTelegraph(ServerLevel level) {
        Vec3 dest = this.blinkDest;
        if (dest == null) {
            this.chimeTimer = -1;
            return;
        }
        int elapsed = BLINK_CHIME_TICKS - this.chimeTimer;
        if (this.chimeTimer % 5 == 0) {
            float pitch = 0.8F + elapsed / (float) BLINK_CHIME_TICKS * 0.9F; // Rising scale.
            level.playSound(null, BlockPos.containing(dest), SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.HOSTILE, 1.4F, pitch);
        }
        level.sendParticles(ParticleTypes.REVERSE_PORTAL, dest.x, dest.y + 1.0D, dest.z,
                3, 0.3D, 0.8D, 0.3D, 0.02D);
        if (--this.chimeTimer < 0) {
            // Vanish: collapse into the rift half where it stands.
            this.blinkOutTimer = BLINK_OUT_TICKS;
            triggerAction(ANIM_BLINK_OUT);
            this.getNavigation().stop();
            level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                    this.getX(), this.getY() + 1.5D, this.getZ(), 30, 0.5D, 1.2D, 0.5D, 0.08D);
            level.playSound(null, this.blockPosition(), SoundEvents.ENDERMAN_TELEPORT,
                    SoundSource.HOSTILE, 1.0F, 0.5F);
        }
    }

    /** Reappear at the chimed destination + immediate single sweep on arrival-huggers. */
    private void executeBlink(ServerLevel level) {
        Vec3 dest = this.blinkDest;
        this.blinkDest = null;
        this.blinkCooldown = BLINK_INTERVAL;
        if (dest == null) {
            return;
        }
        this.teleportTo(dest.x, dest.y, dest.z);
        triggerAction(ANIM_BLINK_IN);
        level.sendParticles(ParticleTypes.REVERSE_PORTAL, dest.x, dest.y + 1.5D, dest.z,
                40, 0.6D, 1.4D, 0.6D, 0.1D);
        level.sendParticles(ParticleTypes.WITCH, dest.x, dest.y + 2.2D, dest.z,
                12, 0.5D, 0.6D, 0.5D, 0.03D);
        level.playSound(null, BlockPos.containing(dest), SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.HOSTILE, 1.2F, 0.45F);
        ServerPlayer marked = this.blinkTargetId != null
                ? level.getServer().getPlayerList().getPlayer(this.blinkTargetId) : null;
        this.blinkTargetId = null;
        if (marked != null && marked.isAlive() && !marked.isSpectator()) {
            faceTowards(marked.position());
            if (this.distanceTo(marked) <= MELEE_RANGE + 1.0D) {
                this.meleeCooldown = MELEE_COOLDOWN_TICKS;
                doHurtTarget(marked); // The blink-behind punish sweep (plan §2.4).
            }
        }
        EclipseMod.LOGGER.info("Rift Warden rift-stepped to ({}, {}, {})",
                String.format(java.util.Locale.ROOT, "%.1f", dest.x),
                String.format(java.util.Locale.ROOT, "%.1f", dest.y),
                String.format(java.util.Locale.ROOT, "%.1f", dest.z));
    }

    // --- P2 adds (by-id lookup: zero compile-time coupling to the registrar wiring) ---

    /** Summons {@value #SUMMONED_CULTISTS} cultists at the ring edge, once per fight. */
    private void summonCultistAdds(ServerLevel level) {
        if (this.addsSummoned || this.anchor == null) {
            return;
        }
        this.addsSummoned = true;
        EntityType<?> cultistType = BuiltInRegistries.ENTITY_TYPE.getOptional(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "eclipse_cultist")).orElse(null);
        if (cultistType == null) {
            EclipseMod.LOGGER.warn("Rift Warden P2 adds skipped: eclipse:eclipse_cultist not registered "
                    + "(DungeonEntities wiring line missing — see docs/plans_v3/wiring/P6-W910_wiring.md)");
            return;
        }
        triggerAction(ANIM_SUMMON);
        int spawned = 0;
        for (int i = 0; i < SUMMONED_CULTISTS; i++) {
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double radius = RiftAnchor.ARENA_RADIUS - 3.0D;
            Vec3 pos = snapToFloor(level, new Vec3(
                    this.anchor.center().x + Math.cos(angle) * radius,
                    this.anchor.groundY() + 1.0D,
                    this.anchor.center().z + Math.sin(angle) * radius));
            Entity cultist = cultistType.create(level);
            if (cultist == null) {
                continue;
            }
            cultist.moveTo(pos.x, pos.y, pos.z, this.random.nextFloat() * 360.0F, 0.0F);
            if (level.addFreshEntity(cultist)) {
                level.sendParticles(ParticleTypes.SOUL, pos.x, pos.y + 0.8D, pos.z,
                        12, 0.3D, 0.4D, 0.3D, 0.02D);
                spawned++;
            }
        }
        level.playSound(null, this.blockPosition(), SoundEvents.EVOKER_PREPARE_SUMMON,
                SoundSource.HOSTILE, 1.2F, 0.7F);
        EclipseMod.LOGGER.info("Rift Warden P2: summoned {} eclipse cultist add(s) at the ring edge", spawned);
    }

    /** Reset hygiene: no leftover adds when the fight abandons (plan acceptance #4). */
    private void discardCultistAdds(ServerLevel level) {
        ResourceLocation cultistId = ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "eclipse_cultist");
        int removed = 0;
        for (Entity entity : level.getEntities(this, this.getBoundingBox().inflate(SCALING_RANGE),
                e -> EntityType.getKey(e.getType()).equals(cultistId))) {
            entity.discard();
            removed++;
        }
        if (removed > 0) {
            EclipseMod.LOGGER.info("Rift Warden reset: discarded {} leftover cultist add(s)", removed);
        }
    }

    // --- participant helpers (Herald pattern) ---

    private List<ServerPlayer> livingParticipants(ServerLevel level) {
        List<ServerPlayer> alive = new ArrayList<>();
        for (UUID id : this.participants) {
            ServerPlayer player = level.getServer().getPlayerList().getPlayer(id);
            if (player != null && player.isAlive() && !player.isSpectator() && player.level() == level
                    && this.anchor != null
                    && this.anchor.horizontalDistance(player.position()) <= RiftAnchor.IMPULSE_RADIUS + 12.0D) {
                alive.add(player);
            }
        }
        return alive;
    }

    @Nullable
    private ServerPlayer nearestParticipant(ServerLevel level) {
        ServerPlayer nearest = null;
        double best = Double.MAX_VALUE;
        for (ServerPlayer player : livingParticipants(level)) {
            double dist = player.distanceToSqr(this);
            if (dist < best) {
                best = dist;
                nearest = player;
            }
        }
        return nearest;
    }

    // --- arena integrity + weakpoint multiplier ---

    /**
     * Outside-ring damage deflects outright (Herald pattern — no doorway archery in a
     * dungeon corridor); during the P2 weakpoint the amount is multiplied by
     * {@value #STAGGER_DAMAGE_FACTOR}. After damage lands, the phase recomputes until
     * stable so a burst crossing 50% still triggers the P2 opener this tick.
     */
    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (!this.level().isClientSide && this.isAlive() && this.anchor != null
                && !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)
                && isFromOutsideArena(source)) {
            if (source.getEntity() instanceof ServerPlayer attacker) {
                playDeflectCue(attacker);
            }
            return false;
        }
        if (!this.level().isClientSide && isStaggered()
                && !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            amount *= STAGGER_DAMAGE_FACTOR;
        }
        boolean hurt = super.hurt(source, amount);
        if (hurt && !this.level().isClientSide && this.isAlive()
                && this.level() instanceof ServerLevel serverLevel) {
            while (updatePhase(serverLevel)) {
                // One transition per call: loop until the phase matches the health fraction.
            }
        }
        return hurt;
    }

    private boolean isFromOutsideArena(DamageSource source) {
        return isOutsideArena(source.getEntity()) || isOutsideArena(source.getDirectEntity());
    }

    private boolean isOutsideArena(@Nullable Entity entity) {
        return entity != null && this.anchor != null
                && this.anchor.horizontalDistance(entity.position()) > RiftAnchor.ARENA_RADIUS;
    }

    /** Audible/visible "that did nothing" cue for a deflected outside-arena hit (~1/s). */
    private void playDeflectCue(ServerPlayer attacker) {
        if (this.tickCount - this.lastDeflectCueTick < DEFLECT_CUE_INTERVAL_TICKS
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        this.lastDeflectCueTick = this.tickCount;
        serverLevel.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.HOSTILE, 1.0F, 1.4F);
        serverLevel.sendParticles(ParticleTypes.CRIT, this.getX(), this.getY() + 1.8D, this.getZ(),
                10, 0.6D, 0.8D, 0.6D, 0.15D);
        EclipseMod.LOGGER.info("Rift Warden deflected outside-arena damage from {} ({} blocks out)",
                attacker.getScoreboardName(), this.anchor == null ? "?" : String.format(
                        java.util.Locale.ROOT, "%.1f", this.anchor.horizontalDistance(attacker.position())));
    }

    // --- death (60t implosion: blades plant, the rift half swallows the body) ---

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            setTelegraphing(false); // No stuck glow pass on the wreck.
            setStaggered(false);
            this.bossEvent.removeAllPlayers(); // No bar lingering at 0% through the collapse.
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
            // W4 IDEA-16 #3: queue the award ceremony (one shard payout per participant on
            // tickDeath keyframes) and start the long soft slow-mo drift shake at the kill.
            this.deathPayoutQueue.clear();
            this.deathPayoutQueue.addAll(this.participants);
            this.deathPayoutInterval = Mth.clamp(
                    (DEATH_DURATION_TICKS - DEATH_PAYOUT_START_TICK - 10)
                            / Math.max(1, this.deathPayoutQueue.size()), 3, 12);
            if (this.level() instanceof ServerLevel serverLevel) {
                PacketDistributor.sendToPlayersNear(serverLevel, null, this.getX(), this.getY(),
                        this.getZ(), 64.0D, S2CShakePayload.shake(0.15F, 40));
            }
            EclipseMod.LOGGER.info("Rift Warden defeated (source: {}) — starting the {}t implosion",
                    damageSource.getMsgId(), DEATH_DURATION_TICKS);
        }
    }

    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death_implode anim plays; deathTime is cosmetic.
        }
        // Blades plant: the wreck stays put while the rift half feeds on it.
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        if (this.deathTime % 4 == 0) {
            serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                    this.getX(), this.getY() + 1.5D, this.getZ(), 10, 0.5D, 1.0D, 0.5D, 0.06D);
        }
        if (this.deathTime % 10 == 0) {
            float pitch = 1.2F - this.deathTime / (float) DEATH_DURATION_TICKS * 0.7F; // Falling.
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.HOSTILE, 1.0F, pitch);
        }
        tickPayoutCeremony(serverLevel);
        if (this.deathTime == DEATH_DURATION_TICKS - 1) {
            implode(serverLevel);
        }
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /**
     * W4 IDEA-16 #3 loot ceremony (Herald pattern): one participant is rewarded per
     * keyframe — 2 umbral shards at their feet with a HEART_BURST quasar and a rising
     * amethyst chime — so the implosion doubles as the award sequence. Any remainder
     * drains just before the final implode, so an oversized roster can never lose payouts
     * to the body removal. Eligibility matches the old {@code dropCustomDeathLoot} dump.
     */
    private void tickPayoutCeremony(ServerLevel level) {
        if (this.deathPayoutQueue.isEmpty() || this.deathTime < DEATH_PAYOUT_START_TICK) {
            return;
        }
        boolean drainAll = this.deathTime >= DEATH_DURATION_TICKS - 2;
        if (!drainAll && (this.deathTime - DEATH_PAYOUT_START_TICK) % this.deathPayoutInterval != 0) {
            return;
        }
        do {
            payoutParticipant(level, this.deathPayoutQueue.poll());
        } while (drainAll && !this.deathPayoutQueue.isEmpty());
    }

    private void payoutParticipant(ServerLevel level, UUID id) {
        ServerPlayer player = level.getServer().getPlayerList().getPlayer(id);
        if (player == null || !player.isAlive() || player.level() != level) {
            return;
        }
        Containers.dropItemStack(level, player.getX(), player.getY() + 0.2D, player.getZ(),
                new ItemStack(EclipseItems.UMBRAL_SHARD.get(), 2));
        PacketDistributor.sendToPlayersNear(level, null, player.getX(), player.getY(), player.getZ(),
                64.0D, new S2CQuasarPayload(S2CQuasarPayload.HEART_BURST, player.position()));
        level.playSound(null, player.blockPosition(), SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.2F, 0.8F + 0.15F * ++this.deathPayoutIndex);
        EclipseMod.LOGGER.info("Rift Warden ceremony payout: 2 umbral shards to {} (deathTime {})",
                player.getScoreboardName(), this.deathTime);
    }

    /** The end of the collapse: the rift swallows the body — shake + soul burst. */
    private void implode(ServerLevel level) {
        PacketDistributor.sendToPlayersNear(level, null, this.getX(), this.getY(), this.getZ(), 64.0D,
                S2CShakePayload.shake(0.8F, 18));
        level.sendParticles(ParticleTypes.SOUL, this.getX(), this.getY() + 1.5D, this.getZ(),
                40, 0.8D, 1.2D, 0.8D, 0.1D);
        level.sendParticles(ParticleTypes.REVERSE_PORTAL, this.getX(), this.getY() + 1.5D, this.getZ(),
                60, 0.4D, 1.0D, 0.4D, 0.25D);
        level.playSound(null, this.blockPosition(), SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.HOSTILE, 1.5F, 0.3F);
        level.playSound(null, this.blockPosition(), SoundEvents.WARDEN_SONIC_BOOM,
                SoundSource.HOSTILE, 0.6F, 1.5F);
        EclipseMod.LOGGER.info("Rift Warden death implosion complete after {}t", this.deathTime);
    }

    /**
     * Drops beyond the loot table: 1 {@code rift_core} by P4-registry lookup (fallback 4
     * umbral shards while P4 hasn't landed it). The per-participant shard payouts moved
     * into {@code tickDeath} keyframes (W4 IDEA-16 #3 award ceremony — everyone who
     * stepped in the ring still gets paid, just staggered; see {@code tickPayoutCeremony}).
     */
    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        BuiltInRegistries.ITEM.getOptional(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_core"))
                .ifPresentOrElse(
                        item -> this.spawnAtLocation(new ItemStack(item)),
                        () -> {
                            this.spawnAtLocation(new ItemStack(EclipseItems.UMBRAL_SHARD.get(), 4));
                            EclipseMod.LOGGER.info("Rift Warden drop: eclipse:rift_core not registered yet "
                                    + "(P4) — dropped the 4-umbral-shard fallback");
                        });
        EclipseMod.LOGGER.info("Rift Warden drops: rift core (or fallback) at the corpse; {} participant "
                + "payout(s) queued for the implosion ceremony", this.participants.size());
    }

    // --- bossbar (wither pattern + boss-theme skin payload for every viewer) ---

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

    // --- test hook ---

    /**
     * Dev/test hook (house pattern): snaps health to the middle of the requested phase's
     * band and resolves transitions immediately. Works from any command that can call
     * into the entity (or via {@code /data} health edits, which route through the same
     * {@link #updatePhase} on the next hurt/tick).
     */
    public void forcePhase(int phase) {
        float fraction = phase >= 2 ? 0.45F : 0.9F;
        this.setHealth(this.getMaxHealth() * fraction);
        if (this.level() instanceof ServerLevel serverLevel) {
            while (updatePhase(serverLevel)) {
                // Resolve to the forced phase now (fires the P2 opener when crossing down).
            }
        }
    }

    // --- boss chassis ---

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_PHASE, 1);
        builder.define(DATA_TELEGRAPH, false);
        builder.define(DATA_STAGGERED, false);
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public void checkDespawn() {
        // Never despawns naturally; tickReset() handles the abandon-despawn itself.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    // --- sounds (a hollow void knight: enderman family pitched into the abyss) ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.ENDERMAN_AMBIENT;
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.NETHERITE_BLOCK_HIT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.ENDERMAN_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.5F;
    }

    // --- persistence (Ferryman NBT pattern: restart resumes phase + arena + roster) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt("ScaledPlayers", this.scaledPlayers);
        compound.putBoolean("AddsSummoned", this.addsSummoned);
        compound.putInt("FightTicks", this.fightTicks);
        if (this.anchor != null) {
            this.anchor.save(compound);
        }
        ListTag list = new ListTag();
        for (UUID id : this.participants) {
            list.add(NbtUtils.createUUID(id));
        }
        compound.put("Participants", list);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("ScaledPlayers")) {
            this.scaledPlayers = Math.max(1, compound.getInt("ScaledPlayers"));
        }
        this.addsSummoned = compound.getBoolean("AddsSummoned");
        this.fightTicks = compound.getInt("FightTicks");
        this.anchor = RiftAnchor.load(compound);
        for (Tag entry : compound.getList("Participants", Tag.TAG_INT_ARRAY)) {
            this.participants.add(NbtUtils.loadUUID(entry));
        }
        // Re-derive the phase so a reloaded fight resumes cleanly; a reload never
        // re-summons adds (AddsSummoned persisted) and never sticks a telegraph glow.
        float fraction = this.getMaxHealth() > 0.0F ? this.getHealth() / this.getMaxHealth() : 1.0F;
        this.lastPhase = fraction > 0.5F ? 1 : 2;
        setPhase(this.lastPhase);
        setTelegraphing(false);
        setStaggered(false);
        if (this.hasCustomName()) {
            this.bossEvent.setName(this.getDisplayName());
        }
        EclipseMod.LOGGER.info("Rift Warden reloaded: phase {} at {}/{} HP, {} participant(s), adds summoned: {}",
                this.lastPhase, String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()),
                String.format(java.util.Locale.ROOT, "%.1f", this.getMaxHealth()),
                this.participants.size(), this.addsSummoned);
    }

    // --- helpers ---

    /** Look helper for the fight script: turns body + head toward a target position. */
    private void faceTowards(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }
}
