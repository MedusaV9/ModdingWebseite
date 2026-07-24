package dev.projecteclipse.eclipse.entity.boss.fog;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
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
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.RawAnimation;

/**
 * The Fog Tyrant / Der Nebeltyrann — the fog storms' apex boss
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4, worker P6-W11/WB-TYRANT): a
 * 4-block crowned storm monarch with a purple NOTCHED boss bar and the Herald/Rift-Warden
 * house fight chassis (scripted {@link #tick()}, no vanilla goals; arena self-pin;
 * participant tracking; outside-ring damage deflect; wipe/reset; scripted death;
 * {@code LOGGER.info} breadcrumbs on every transition).
 *
 * <p><b>Fight</b> — three phases split at 60% and 25% HP:</p>
 * <ul>
 *   <li><b>P1 "Court"</b> (100–60%): stalks the nearest participant with
 *       {@value #MELEE_RANGE}-range cleaver swings ({@code attack}, 9 dmg); every
 *       {@value #LANCE_CADENCE_TICKS}t a <b>fog-lance volley</b> — a
 *       {@value #LANCE_TELEGRAPH_TICKS}t rooted raise ({@code lance_volley} anim) during
 *       which the {@value #LANCE_COUNT} locked lance LINES glitter with electric warning
 *       trails (sidestep to dodge), then the lances fire down the exact trails
 *       ({@value #LANCE_DAMAGE} dmg, one hit per player, blocks stop them); every
 *       {@value #HOWL_INTERVAL_TICKS}t a <b>hound howl</b> tops the pack back up to
 *       {@value #HOUND_PACK} storm hounds (by-id registry lookup
 *       {@code eclipse:storm_hound}, tagged {@value #ADD_TAG}); every
 *       {@value #STEP_INTERVAL_TICKS}t a <b>storm-step</b> — a short teleport to the
 *       target's flank wrapped in fog bursts, with a gathering fog column at the
 *       destination during the {@value #STEP_OUT_TICKS}t vanish (fairness cue).</li>
 *   <li><b>P2 "Storm crown"</b> (≤60%): adds <b>crown lightning</b> every
 *       {@value #LIGHTNING_INTERVAL_TICKS}t — up to {@value #LIGHTNING_MARKS} player
 *       positions are marked with {@value #LIGHTNING_TELEGRAPH_TICKS}t (1.5 s) spark
 *       telegraph rings, then visual-only {@link LightningBolt}s strike (8 dmg inside
 *       r={@value #LIGHTNING_RADIUS} of the ring, no fire grief — move off the ring);
 *       <b>blind squall</b> every {@value #SQUALL_INTERVAL_TICKS}t — a
 *       {@value #SQUALL_WINDUP_TICKS}t rising sonic-charge audio cue while the crown
 *       collapses inward, then an arena-wide pulse: Blindness 3 s + 4 dmg to everyone
 *       with LINE OF SIGHT to the tyrant (duck behind cover to dodge); and slow
 *       <b>enrage stacking</b> — every {@value #ENRAGE_INTERVAL_TICKS}t one stack (max
 *       {@value #ENRAGE_MAX_STACKS}): −6% special cooldowns and +4% speed each.</li>
 *   <li><b>P3 "Desperation"</b> (≤25%): a one-time <b>colossus call</b> (1
 *       {@code eclipse:fog_colossus} by-id, if none lives nearby) and the desperation
 *       barrage — volleys accelerate to {@value #LANCE_CADENCE_P3_TICKS}t with
 *       {@value #LANCE_COUNT_P3} lances, storm-steps to {@value #STEP_INTERVAL_P3_TICKS}t.</li>
 * </ul>
 *
 * <p>Only ONE rooted telegraph runs at a time (lance raise, squall windup, storm-step
 * vanish) with a {@value #SPECIAL_GAP_TICKS}t gap between special starts — players are
 * never stun-chained, and every attack has a readable dodge. Lance raycasts are budgeted:
 * one block-clip per lance at lock time, reused by both the warning trail and the hit
 * sweep.</p>
 *
 * <p><b>Scaling</b> (snapshotted at summon): HP = {@value #BASE_MAX_HEALTH}·(1+0.4·(n−1))
 * for n living players within {@value #SCALING_RANGE} blocks. <b>Wipe/reset</b> (Herald
 * rules): no player within {@value #RESET_RANGE} blocks for {@value #RESET_TICKS}t →
 * heal to full, despawn every {@value #ADD_TAG}-tagged hound/colossus add and despawn
 * ship-shape ({@link FogBankMarker} re-arms the lair). <b>Death</b>:
 * {@value #DEATH_DURATION_TICKS}t scripted storm-burst — the crown falls first (anim),
 * the chest core gutters (synced {@code CORE_LIT} flag, Ferryman lantern pattern),
 * the body collapses, final thunderclap + camera shake. Drops: loot table
 * {@code eclipse:entities/fog_tyrant} (guaranteed umbral shards + the
 * {@code eclipse:replant} storm enchantment book + a storm trophy) plus 1
 * {@code storm_heart} by P4-registry lookup (fallback 6 umbral shards) and 3 umbral
 * shards at each participant's feet (Herald pattern).</p>
 *
 * <p><b>Placement seam:</b> NOT a spawner mob — P1's mature-storm flow marks the lair via
 * {@link FogBankMarker#markLair} (proximity-triggered summon) or calls
 * {@link #summonAt(ServerLevel, BlockPos)} directly (documented in
 * {@code docs/plans_v3/wiring/WB-TYRANT_wiring.md}); the fight self-pins its
 * r={@value FogTyrantArena#ARENA_RADIUS} arena at the summon point, so plain
 * {@code /summon eclipse:fog_tyrant} works anywhere in the open.</p>
 */
public class FogTyrantEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "fog_tyrant";
    public static final String ANIM_STRIDE = "stride";
    public static final String ANIM_LANCE_VOLLEY = "lance_volley";
    public static final String ANIM_STEP_OUT = "storm_step_out";
    public static final String ANIM_STEP_IN = "storm_step_in";
    public static final String ANIM_CROWN_CALL = "crown_call";
    public static final String ANIM_SQUALL = "squall";
    public static final String ANIM_ENRAGE = "enrage";

    public static final float BASE_MAX_HEALTH = 350.0F;
    /** Scripted death storm-burst length (vanilla tips over after 20t; see {@link #tickDeath}). */
    public static final int DEATH_DURATION_TICKS = 70;
    /** Command tag stamped on every summoned add so reset hygiene can find them. */
    public static final String ADD_TAG = "eclipse_tyrant_add";

    private static final double SCALING_RANGE = 32.0D;
    // Fog-lance volley (P1+; P3 = desperation barrage).
    private static final int LANCE_CADENCE_TICKS = 140;
    private static final int LANCE_CADENCE_P3_TICKS = 70;
    private static final int LANCE_TELEGRAPH_TICKS = 25;
    private static final int LANCE_COUNT = 3;
    private static final int LANCE_COUNT_P3 = 5;
    private static final double LANCE_RANGE = 24.0D;
    private static final double LANCE_HALF_WIDTH = 1.2D;
    private static final float LANCE_DAMAGE = 7.0F;
    // Hound howl (P1+).
    private static final int HOWL_INTERVAL_TICKS = 500;
    private static final int HOUND_PACK = 2;
    // Storm-step (P1+; faster in P3).
    private static final int STEP_INTERVAL_TICKS = 220;
    private static final int STEP_INTERVAL_P3_TICKS = 120;
    private static final int STEP_OUT_TICKS = 10;
    private static final double STEP_FLANK_BLOCKS = 6.0D;
    // Crown lightning (P2+).
    private static final int LIGHTNING_INTERVAL_TICKS = 160;
    private static final int LIGHTNING_TELEGRAPH_TICKS = 30; // 1.5 s ring per the brief
    private static final int LIGHTNING_MARKS = 2;
    private static final double LIGHTNING_RADIUS = 2.5D;
    private static final float LIGHTNING_DAMAGE = 8.0F;
    // Blind squall (P2+).
    private static final int SQUALL_INTERVAL_TICKS = 300;
    private static final int SQUALL_WINDUP_TICKS = 30;
    private static final int SQUALL_BLIND_TICKS = 60; // 3 s
    private static final float SQUALL_DAMAGE = 4.0F;
    // Enrage stacking (P2+).
    private static final int ENRAGE_INTERVAL_TICKS = 400;
    private static final int ENRAGE_MAX_STACKS = 5;
    private static final double ENRAGE_SPEED_PER_STACK = 0.04D;
    private static final double ENRAGE_COOLDOWN_PER_STACK = 0.06D;
    private static final ResourceLocation ENRAGE_SPEED_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "tyrant_enrage_speed");
    // Melee + chassis.
    private static final double MELEE_RANGE = 3.6D;
    private static final int MELEE_COOLDOWN_TICKS = 30;
    private static final int SPECIAL_GAP_TICKS = 20;
    private static final int RESET_TICKS = 1200; // 60 s (Herald wipe rules)
    private static final double RESET_RANGE = 24.0D;
    private static final int DEFLECT_CUE_INTERVAL_TICKS = 20;
    private static final double SUMMON_DEDUP_RANGE = 64.0D;
    /** W4 loot ceremony: first participant payout keyframe of the death storm-burst. */
    private static final int DEATH_PAYOUT_START_TICK = 20;
    private static final double ADD_CLEANUP_RANGE = 64.0D;
    /** Death-anim keyframe where the chest core gutters out (crown already fallen). */
    private static final int DEATH_CORE_GUTTER_TICK = 32;
    private static final int DEATH_THUNDERCLAP_TICK = 60;

    /** Current phase 1..3 (synced; lets the renderer/model react if it ever wants to). */
    private static final EntityDataAccessor<Integer> DATA_PHASE =
            SynchedEntityData.defineId(FogTyrantEntity.class, EntityDataSerializers.INT);
    /** True while a rooted telegraph holds (lance raise / squall windup). */
    private static final EntityDataAccessor<Boolean> DATA_TELEGRAPH =
            SynchedEntityData.defineId(FogTyrantEntity.class, EntityDataSerializers.BOOLEAN);
    /** Chest storm-core lit flag (gutters during the death collapse — Ferryman pattern). */
    private static final EntityDataAccessor<Boolean> DATA_CORE_LIT =
            SynchedEntityData.defineId(FogTyrantEntity.class, EntityDataSerializers.BOOLEAN);
    /** Enrage stacks 0..5 (synced for future renderer/P2 flourish hooks). */
    private static final EntityDataAccessor<Integer> DATA_ENRAGE_STACKS =
            SynchedEntityData.defineId(FogTyrantEntity.class, EntityDataSerializers.INT);

    /** One locked fog lance: origin eye, unit direction, pre-clipped travel distance. */
    private record Lance(Vec3 origin, Vec3 direction, double distance) {}

    private final ServerBossEvent bossEvent = new ServerBossEvent(
            Component.translatable("entity.eclipse.fog_tyrant.bossbar"),
            BossEvent.BossBarColor.PURPLE, BossEvent.BossBarOverlay.NOTCHED_20);

    // --- server fight state (arena + participants persisted in NBT) ---
    @Nullable
    private FogTyrantArena arena;
    private int scaledPlayers = 1;
    private final Set<UUID> participants = new HashSet<>();

    private int lanceTimer = LANCE_CADENCE_TICKS;
    private int lanceTelegraphTimer = -1;
    private final List<Lance> lockedLances = new ArrayList<>();
    private int howlTimer = HOWL_INTERVAL_TICKS / 2;
    private int stepTimer = STEP_INTERVAL_TICKS;
    private int stepOutTimer = -1;
    @Nullable
    private Vec3 stepDest;
    @Nullable
    private UUID stepTargetId;
    private int lightningTimer = LIGHTNING_INTERVAL_TICKS;
    private int lightningTelegraphTimer = -1;
    private final List<Vec3> lightningMarks = new ArrayList<>();
    private int squallTimer = SQUALL_INTERVAL_TICKS;
    private int squallWindupTimer = -1;
    private int enrageTimer = ENRAGE_INTERVAL_TICKS;
    private int specialGapTimer;
    private int meleeCooldown;
    private int fightTicks;
    private int noPlayerTicks;
    private int lastPhase = 1;
    private int lastDeflectCueTick = -DEFLECT_CUE_INTERVAL_TICKS;
    private boolean colossusCalled;
    private boolean warnedHoundUnbound;
    private boolean warnedColossusUnbound;
    // W4 loot ceremony (transient — die() runs exactly once, so a restart mid-collapse
    // loses only the staggering, never the guaranteed corpse drops).
    private final ArrayDeque<UUID> deathPayoutQueue = new ArrayDeque<>();
    private int deathPayoutInterval = 12;
    private int deathPayoutIndex;

    public FogTyrantEntity(EntityType<? extends FogTyrantEntity> entityType, Level level) {
        super(entityType, level);
        this.setPersistenceRequired();
        this.noCulling = true;
        this.xpReward = 50;
    }

    /** Spec §2.4: 350 HP base, dmg 9, slow (0.2) but relentless, fire-immune, unshovable. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, BASE_MAX_HEALTH)
                .add(Attributes.ATTACK_DAMAGE, 9.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.2D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.FOLLOW_RANGE, 64.0D)
                .add(Attributes.STEP_HEIGHT, 1.1D);
    }

    // --- summoning (the P1 mature-storm seam; FogBankMarker routes here too) ---

    /**
     * Places the tyrant at the storm center with arrival FX and pins the fight there —
     * the single call P1's mature-storm flow (or {@link FogBankMarker}) makes. Works in
     * any open area ≥ ~34×34; the ring self-pins at {@code center}. Dedup guard: a live
     * tyrant within {@value #SUMMON_DEDUP_RANGE} blocks is returned instead of stacking
     * a second apex (storm re-triggers stay safe).
     */
    public static FogTyrantEntity summonAt(ServerLevel level, BlockPos center) {
        List<FogTyrantEntity> existing = level.getEntitiesOfClass(FogTyrantEntity.class,
                new AABB(center).inflate(SUMMON_DEDUP_RANGE), FogTyrantEntity::isAlive);
        if (!existing.isEmpty()) {
            EclipseMod.LOGGER.info("Fog Tyrant summon skipped: a live tyrant already reigns within {} blocks of {}",
                    (int) SUMMON_DEDUP_RANGE, center.toShortString());
            return existing.get(0);
        }
        FogTyrantEntity tyrant = FogBossEntities.FOG_TYRANT.get().create(level);
        if (tyrant == null) {
            throw new IllegalStateException("Fog Tyrant entity type failed to instantiate");
        }
        double x = center.getX() + 0.5D;
        double z = center.getZ() + 0.5D;
        tyrant.moveTo(x, center.getY(), z, level.getRandom().nextFloat() * 360.0F, 0.0F);
        tyrant.initFight(level, new Vec3(x, center.getY(), z), center.getY());
        level.addFreshEntity(tyrant);
        // Arrival: the storm condenses — the tyrant raises its own fog banks around the ring.
        tyrant.fogBurstFx(level, new Vec3(x, center.getY() + 1.0D, z), 50);
        for (int i = 0; i < 4; i++) {
            double angle = i * Mth.HALF_PI + 0.6D;
            tyrant.fogBurstFx(level, new Vec3(
                    x + Math.cos(angle) * FogBankMarker.BANK_RING_RADIUS, center.getY() + 0.5D,
                    z + Math.sin(angle) * FogBankMarker.BANK_RING_RADIUS), 20);
        }
        level.playSound(null, center, SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.HOSTILE, 1.4F, 0.6F);
        level.playSound(null, center, SoundEvents.WARDEN_ROAR, SoundSource.HOSTILE, 1.6F, 0.5F);
        // W4 intro title card: the name decodes in over the arrival FX (BossIntroOverlay).
        dev.projecteclipse.eclipse.network.boss.BossPayloads.sendIntro(level, tyrant.position(),
                "entity.eclipse.fog_tyrant", "announce.eclipse.boss.intro.fog_tyrant");
        EclipseMod.LOGGER.info("Fog Tyrant summoned at {} — scaled for {} player(s): {} HP; bossbar {} created",
                center.toShortString(), tyrant.scaledPlayers, tyrant.getMaxHealth(), tyrant.bossEvent.getId());
        return tyrant;
    }

    /** Pins the arena and applies the summon-time player-count scaling (spec §2.4). */
    private void initFight(ServerLevel level, Vec3 center, int groundY) {
        this.arena = new FogTyrantArena(center, groundY);
        long nearby = level.players().stream()
                .filter(player -> !player.isSpectator() && player.isAlive())
                .filter(player -> player.position().distanceTo(center) <= SCALING_RANGE)
                .count();
        this.scaledPlayers = (int) Math.max(1L, nearby);
        double maxHealth = BASE_MAX_HEALTH * (1.0D + 0.4D * (this.scaledPlayers - 1));
        this.getAttribute(Attributes.MAX_HEALTH).setBaseValue(maxHealth);
        this.setHealth((float) maxHealth);
    }

    /** Lazy arena init for plain {@code /summon eclipse:fog_tyrant} (acceptance path). */
    private void ensureFightInitialized(ServerLevel level) {
        if (this.arena != null) {
            return;
        }
        initFight(level, this.position(), this.blockPosition().getY());
        EclipseMod.LOGGER.info("Fog Tyrant arena auto-pinned at ({}, {}, {}) — {} player(s), {} HP; bossbar {} created",
                String.format(Locale.ROOT, "%.1f", this.getX()), this.blockPosition().getY(),
                String.format(Locale.ROOT, "%.1f", this.getZ()),
                this.scaledPlayers, this.getMaxHealth(), this.bossEvent.getId());
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    /** The monarch glides — the sheet names the locomotion loop {@code stride}, not walk. */
    @Override
    protected RawAnimation walkAnim() {
        return EclipseGeoAnimations.loop(GEO_ID, ANIM_STRIDE);
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK));
        action.triggerableAnim(ANIM_LANCE_VOLLEY, EclipseGeoAnimations.once(GEO_ID, ANIM_LANCE_VOLLEY));
        action.triggerableAnim(ANIM_STEP_OUT, EclipseGeoAnimations.hold(GEO_ID, ANIM_STEP_OUT));
        action.triggerableAnim(ANIM_STEP_IN, EclipseGeoAnimations.once(GEO_ID, ANIM_STEP_IN));
        action.triggerableAnim(ANIM_CROWN_CALL, EclipseGeoAnimations.once(GEO_ID, ANIM_CROWN_CALL));
        action.triggerableAnim(ANIM_SQUALL, EclipseGeoAnimations.once(GEO_ID, ANIM_SQUALL));
        action.triggerableAnim(ANIM_ENRAGE, EclipseGeoAnimations.once(GEO_ID, ANIM_ENRAGE));
        // W4 IDEA-16 #3 death slow-mo: the held death anim eases toward ~0.2x speed over
        // the first ~8 death ticks (Herald tickClientAnim pattern, Geo-boss flavor;
        // client-side render illusion — server ticks untouched).
        action.setAnimationSpeedHandler(tyrant -> this.deathTime > 0
                ? Math.max(0.2D, 1.0D - this.deathTime * 0.1D) : 1.0D);
    }

    // --- synced state accessors ---

    public int getPhase() {
        return this.entityData.get(DATA_PHASE);
    }

    private void setPhase(int phase) {
        this.entityData.set(DATA_PHASE, Mth.clamp(phase, 1, 3));
    }

    public boolean isTelegraphing() {
        return this.entityData.get(DATA_TELEGRAPH);
    }

    private void setTelegraphing(boolean telegraphing) {
        this.entityData.set(DATA_TELEGRAPH, telegraphing);
    }

    /** Whether the chest storm-core still burns (false only during the death gutter). */
    public boolean isCoreLit() {
        return this.entityData.get(DATA_CORE_LIT);
    }

    private void setCoreLit(boolean lit) {
        this.entityData.set(DATA_CORE_LIT, lit);
    }

    public int getEnrageStacks() {
        return this.entityData.get(DATA_ENRAGE_STACKS);
    }

    // --- fight ticking (house pattern: everything scripted, no vanilla goals) ---

    @Override
    protected void registerGoals() {
        // Deliberately empty: the boss script in tick() owns targeting and movement.
    }

    @Override
    public void tick() {
        super.tick();
        if (!this.level().isClientSide && this.isAlive()
                && this.level() instanceof ServerLevel serverLevel) {
            ensureFightInitialized(serverLevel);
            tickFight(serverLevel);
        }
    }

    private void tickFight(ServerLevel level) {
        this.bossEvent.setProgress(this.getHealth() / this.getMaxHealth());
        this.fightTicks++;
        updatePhase(level);
        updateParticipants(level);
        if (tickReset(level)) {
            return;
        }
        tickArenaLock(level);
        if (this.meleeCooldown > 0) {
            this.meleeCooldown--;
        }
        if (this.specialGapTimer > 0) {
            this.specialGapTimer--;
        }
        // Ground-marked telegraphs tick regardless of what the body is doing.
        tickCrownLightningMarks(level);
        // Rooted windows — exactly one at a time; nothing else acts while one holds.
        if (this.stepOutTimer >= 0) {
            tickStormStepVanish(level);
            return;
        }
        if (this.lanceTelegraphTimer >= 0) {
            tickLanceTelegraph(level);
            return;
        }
        if (this.squallWindupTimer >= 0) {
            tickSquallWindup(level);
            return;
        }
        // Special starts (one per SPECIAL_GAP window, cooldown-scaled by enrage).
        maybeStartLanceVolley(level);
        maybeStartSquall(level);
        maybeStartCrownLightning(level);
        maybeStartStormStep(level);
        tickHoundHowl(level);
        tickColossusCall(level);
        tickEnrage(level);
        tickStalkAndCleave(level);
    }

    /**
     * Phase = HP fraction vs the 60%/25% breaks; one transition per call (Herald
     * pattern — {@link #hurt} loops it so burst damage can cross two breaks cleanly).
     */
    private boolean updatePhase(ServerLevel level) {
        float fraction = this.getHealth() / this.getMaxHealth();
        int target = fraction > 0.6F ? 1 : fraction > 0.25F ? 2 : 3;
        if (target == this.lastPhase) {
            return false;
        }
        int phase = this.lastPhase + (target > this.lastPhase ? 1 : -1);
        EclipseMod.LOGGER.info("Fog Tyrant phase {} -> {} at {}/{} HP", this.lastPhase, phase,
                String.format(Locale.ROOT, "%.1f", this.getHealth()),
                String.format(Locale.ROOT, "%.1f", this.getMaxHealth()));
        this.lastPhase = phase;
        setPhase(phase);
        clearTelegraphs();
        // The transition roar: thunder + shake + a crown nova (W8 sendFx pattern: payload + particles).
        level.playSound(null, this.blockPosition(), SoundEvents.WARDEN_ROAR, SoundSource.HOSTILE,
                1.6F, phase >= 3 ? 0.45F : 0.6F);
        level.playSound(null, this.blockPosition(), SoundEvents.WITHER_SPAWN, SoundSource.HOSTILE,
                0.7F, phase >= 3 ? 1.4F : 1.0F);
        PacketDistributor.sendToPlayersNear(level, null, this.getX(), this.getY(), this.getZ(), 32.0D,
                S2CShakePayload.shake(phase >= 3 ? 0.7F : 0.5F, phase >= 3 ? 15 : 12));
        level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                this.getX(), this.getY() + 3.4D, this.getZ(), 40, 1.2D, 0.8D, 1.2D, 0.15D);
        fogBurstFx(level, this.position().add(0.0D, 0.5D, 0.0D), 30);
        if (phase == 2) {
            triggerAction(ANIM_CROWN_CALL); // The crown awakens.
            this.lightningTimer = Math.min(this.lightningTimer, 60);
            this.squallTimer = Math.min(this.squallTimer, 140);
        } else if (phase == 3) {
            triggerAction(ANIM_ENRAGE); // Desperation.
            this.lanceTimer = Math.min(this.lanceTimer, scaledCooldown(LANCE_CADENCE_P3_TICKS));
            this.stepTimer = Math.min(this.stepTimer, scaledCooldown(STEP_INTERVAL_P3_TICKS));
        }
        return true;
    }

    /** Everyone entering the combat ring joins the fight (and stays enrolled for drops). */
    private void updateParticipants(ServerLevel level) {
        if (this.arena == null) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && this.arena.isInside(player.position())
                    && this.participants.add(player.getUUID())) {
                EclipseMod.LOGGER.info("Fog Tyrant fight: {} entered the arena ({} participant(s))",
                        player.getScoreboardName(), this.participants.size());
            }
        }
    }

    /**
     * Abandon-reset (Herald wipe rules): no players within {@value #RESET_RANGE} blocks
     * for {@value #RESET_TICKS}t → heal to full, despawn tagged adds, despawn ship-shape
     * (the {@link FogBankMarker} lair re-arms for the next approach).
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
        EclipseMod.LOGGER.info("Fog Tyrant reset: no players within {} blocks for {} ticks — healing, "
                + "cleaning up adds and despawning", RESET_RANGE, RESET_TICKS);
        discardTaggedAdds(level);
        this.setHealth(this.getMaxHealth());
        this.discard();
        return true;
    }

    /**
     * Leash + wall: inward impulse past r=18 and the fog-wall ring segment. The synced
     * phase feeds {@link FogTyrantArena#particleWall} as its severity, so P2 thickens the
     * wall and P3 adds the visual-only ring lightning (W4 IDEA-16 #2).
     */
    private void tickArenaLock(ServerLevel level) {
        if (this.arena == null) {
            return;
        }
        for (ServerPlayer player : livingParticipants(level)) {
            this.arena.impulseInward(player, this.tickCount);
            if (this.tickCount % 8 == 0) {
                this.arena.particleWall(level, player, getPhase());
            }
        }
    }

    // --- movement + cleaver melee ---

    /** Slow relentless stalker: path to the nearest participant, cleave inside range. */
    private void tickStalkAndCleave(ServerLevel level) {
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
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // Condensed-fog cleaver swing.
            this.level().playSound(null, this.blockPosition(), SoundEvents.PLAYER_ATTACK_SWEEP,
                    SoundSource.HOSTILE, 1.2F, 0.5F);
        }
        return hurt;
    }

    // --- fog-lance volleys (P1+; the P3 desperation barrage) ---

    /** Enrage-scaled cooldown (−6% per stack, floored at 40% of base). */
    private int scaledCooldown(int base) {
        double factor = Math.max(0.4D, 1.0D - ENRAGE_COOLDOWN_PER_STACK * getEnrageStacks());
        return (int) Math.round(base * factor);
    }

    private void maybeStartLanceVolley(ServerLevel level) {
        if (--this.lanceTimer > 0 || this.specialGapTimer > 0) {
            return;
        }
        List<ServerPlayer> targets = livingParticipants(level);
        if (targets.isEmpty()) {
            this.lanceTimer = 40;
            return;
        }
        // Lock the lance lines NOW — the warning trails show exactly where death travels.
        this.lockedLances.clear();
        Collections.shuffle(targets, new java.util.Random(this.random.nextLong()));
        int count = getPhase() >= 3 ? LANCE_COUNT_P3 : LANCE_COUNT;
        Vec3 eye = this.getEyePosition();
        for (int i = 0; i < count; i++) {
            ServerPlayer target = targets.get(i % targets.size());
            Vec3 aim = new Vec3(target.getX(), target.getY(0.5D), target.getZ()).subtract(eye);
            if (aim.lengthSqr() < 1.0E-4D) {
                continue;
            }
            // Extra lances beyond the target count fan out so the barrage reads as a spread.
            Vec3 direction = aim.normalize();
            if (i >= targets.size()) {
                direction = direction.yRot((this.random.nextFloat() - 0.5F) * 0.5F);
            }
            // ONE block-clip per lance, reused by trail + hit sweep (perf budget).
            Vec3 reach = eye.add(direction.scale(LANCE_RANGE));
            Vec3 hitPos = level.clip(new ClipContext(eye, reach,
                    ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, this)).getLocation();
            this.lockedLances.add(new Lance(eye, direction, Math.max(2.0D, hitPos.distanceTo(eye))));
        }
        if (this.lockedLances.isEmpty()) {
            this.lanceTimer = 40;
            return;
        }
        this.lanceTelegraphTimer = LANCE_TELEGRAPH_TICKS;
        this.specialGapTimer = SPECIAL_GAP_TICKS;
        setTelegraphing(true);
        triggerAction(ANIM_LANCE_VOLLEY);
        this.getNavigation().stop();
        level.playSound(null, this.blockPosition(), SoundEvents.BEACON_POWER_SELECT,
                SoundSource.HOSTILE, 1.2F, 0.6F);
        level.playSound(null, this.blockPosition(), SoundEvents.WARDEN_SONIC_CHARGE,
                SoundSource.HOSTILE, 0.8F, 1.6F);
        EclipseMod.LOGGER.info("Fog Tyrant lance volley telegraphed: {} lance(s), {}t warning trails",
                this.lockedLances.size(), LANCE_TELEGRAPH_TICKS);
    }

    /** Rooted raise: electric warning trails glitter down every locked line. */
    private void tickLanceTelegraph(ServerLevel level) {
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        if (this.lanceTelegraphTimer % 3 == 0) {
            for (Lance lance : this.lockedLances) {
                for (double d = 2.0D; d <= lance.distance(); d += 1.5D) {
                    Vec3 p = lance.origin().add(lance.direction().scale(d));
                    level.sendParticles(ParticleTypes.ELECTRIC_SPARK, p.x, p.y, p.z,
                            1, 0.06D, 0.06D, 0.06D, 0.0D);
                }
            }
        }
        if (--this.lanceTelegraphTimer >= 0) {
            return;
        }
        setTelegraphing(false);
        this.lanceTimer = scaledCooldown(getPhase() >= 3 ? LANCE_CADENCE_P3_TICKS : LANCE_CADENCE_TICKS);
        releaseLances(level);
    }

    /** Fire down the locked trails: one hit per player, blocks already clipped the reach. */
    private void releaseLances(ServerLevel level) {
        List<ServerPlayer> candidates = livingParticipants(level);
        Set<UUID> struck = new HashSet<>();
        int hits = 0;
        for (Lance lance : this.lockedLances) {
            // Firing FX: a sonic lance down the trail, stamped every 4 blocks.
            for (double d = 2.0D; d <= lance.distance(); d += 4.0D) {
                Vec3 p = lance.origin().add(lance.direction().scale(d));
                level.sendParticles(ParticleTypes.SONIC_BOOM, p.x, p.y, p.z, 1, 0.0D, 0.0D, 0.0D, 0.0D);
                level.sendParticles(ParticleTypes.CLOUD, p.x, p.y, p.z, 2, 0.3D, 0.3D, 0.3D, 0.01D);
            }
            for (ServerPlayer player : candidates) {
                if (struck.contains(player.getUUID())) {
                    continue; // Fair: a fanned barrage never multi-hits one player.
                }
                Vec3 toChest = new Vec3(player.getX(), player.getY(0.5D), player.getZ())
                        .subtract(lance.origin());
                double along = toChest.dot(lance.direction());
                if (along < 0.0D || along > lance.distance()) {
                    continue;
                }
                double offLine = toChest.subtract(lance.direction().scale(along)).length();
                if (offLine > LANCE_HALF_WIDTH) {
                    continue;
                }
                if (player.hurt(this.damageSources().mobAttack(this), LANCE_DAMAGE)) {
                    player.setDeltaMovement(player.getDeltaMovement()
                            .add(lance.direction().x * 0.3D, 0.15D, lance.direction().z * 0.3D));
                    player.hurtMarked = true; // SoftBorder/Ferryman velocity sync.
                    struck.add(player.getUUID());
                    hits++;
                }
            }
        }
        level.playSound(null, this.blockPosition(), SoundEvents.TRIDENT_RIPTIDE_3.value(),
                SoundSource.HOSTILE, 1.4F, 0.6F);
        EclipseMod.LOGGER.info("Fog Tyrant lance volley released: {} lance(s), {} hit(s)",
                this.lockedLances.size(), hits);
        this.lockedLances.clear();
    }

    // --- storm-step (short flank teleport wrapped in fog bursts) ---

    private void maybeStartStormStep(ServerLevel level) {
        if (--this.stepTimer > 0 || this.specialGapTimer > 0) {
            return;
        }
        List<ServerPlayer> targets = livingParticipants(level);
        if (targets.isEmpty() || this.arena == null) {
            this.stepTimer = 60;
            return;
        }
        ServerPlayer target = targets.get(this.random.nextInt(targets.size()));
        Vec3 dest = findStepDestination(level, target);
        if (dest == null) {
            this.stepTimer = 80;
            EclipseMod.LOGGER.info("Fog Tyrant storm-step skipped: no clear flank beside {}",
                    target.getScoreboardName());
            return;
        }
        this.stepDest = dest;
        this.stepTargetId = target.getUUID();
        this.stepOutTimer = STEP_OUT_TICKS;
        this.specialGapTimer = SPECIAL_GAP_TICKS;
        triggerAction(ANIM_STEP_OUT);
        this.getNavigation().stop();
        fogBurstFx(level, this.position().add(0.0D, 1.5D, 0.0D), 30);
        level.playSound(null, this.blockPosition(), SoundEvents.ELDER_GUARDIAN_CURSE,
                SoundSource.HOSTILE, 0.9F, 1.4F);
        EclipseMod.LOGGER.info("Fog Tyrant storm-step: vanishing for {}t towards ({}, {}, {})",
                STEP_OUT_TICKS, String.format(Locale.ROOT, "%.1f", dest.x),
                String.format(Locale.ROOT, "%.1f", dest.y), String.format(Locale.ROOT, "%.1f", dest.z));
    }

    /**
     * A flank point {@value #STEP_FLANK_BLOCKS} blocks to a random side of the target
     * (perpendicular to their view), clamped inside the ring, snapped to the floor and
     * collision-checked — falls back to 4 then 3 blocks out, or null (skip).
     */
    @Nullable
    private Vec3 findStepDestination(ServerLevel level, ServerPlayer target) {
        Vec3 view = target.getViewVector(1.0F).multiply(1.0D, 0.0D, 1.0D);
        if (view.lengthSqr() < 1.0E-4D) {
            view = new Vec3(1.0D, 0.0D, 0.0D);
        }
        Vec3 side = view.normalize().yRot(this.random.nextBoolean() ? Mth.HALF_PI : -Mth.HALF_PI);
        for (double distance : new double[] {STEP_FLANK_BLOCKS, 4.0D, 3.0D}) {
            Vec3 raw = target.position().add(side.scale(distance));
            Vec3 clamped = this.arena != null ? this.arena.clampInside(raw, 2.5D) : raw;
            Vec3 dest = snapToFloor(level, clamped);
            AABB box = this.getDimensions(this.getPose()).makeBoundingBox(dest);
            if (level.noCollision(this, box)) {
                return dest;
            }
        }
        return null;
    }

    /** Mid-vanish: rooted inside the fog fold; a fog column gathers at the destination. */
    private void tickStormStepVanish(ServerLevel level) {
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        Vec3 dest = this.stepDest;
        if (dest != null && this.stepOutTimer % 2 == 0) {
            // Fairness cue: the arrival fog gathers where the tyrant will reappear.
            level.sendParticles(ParticleTypes.CAMPFIRE_SIGNAL_SMOKE,
                    dest.x, dest.y + 0.4D, dest.z, 3, 0.5D, 0.2D, 0.5D, 0.01D);
        }
        if (--this.stepOutTimer >= 0) {
            return;
        }
        executeStormStep(level);
    }

    /** Reappear in the fog burst on the target's flank, already facing them. */
    private void executeStormStep(ServerLevel level) {
        Vec3 dest = this.stepDest;
        this.stepDest = null;
        this.stepTimer = scaledCooldown(getPhase() >= 3 ? STEP_INTERVAL_P3_TICKS : STEP_INTERVAL_TICKS);
        if (dest == null) {
            return;
        }
        this.teleportTo(dest.x, dest.y, dest.z);
        triggerAction(ANIM_STEP_IN);
        fogBurstFx(level, dest.add(0.0D, 1.5D, 0.0D), 40);
        level.playSound(null, BlockPos.containing(dest), SoundEvents.ELDER_GUARDIAN_CURSE,
                SoundSource.HOSTILE, 1.0F, 0.8F);
        ServerPlayer marked = this.stepTargetId != null
                ? level.getServer().getPlayerList().getPlayer(this.stepTargetId) : null;
        this.stepTargetId = null;
        if (marked != null && marked.isAlive() && !marked.isSpectator()) {
            faceTowards(marked.position());
        }
        EclipseMod.LOGGER.info("Fog Tyrant storm-stepped to ({}, {}, {})",
                String.format(Locale.ROOT, "%.1f", dest.x),
                String.format(Locale.ROOT, "%.1f", dest.y),
                String.format(Locale.ROOT, "%.1f", dest.z));
    }

    // --- crown lightning (P2+: 1.5 s telegraph rings, visual-only bolts, no fire) ---

    private void maybeStartCrownLightning(ServerLevel level) {
        if (getPhase() < 2 || this.lightningTelegraphTimer >= 0
                || --this.lightningTimer > 0 || this.specialGapTimer > 0) {
            return;
        }
        List<ServerPlayer> targets = livingParticipants(level);
        if (targets.isEmpty()) {
            this.lightningTimer = 60;
            return;
        }
        Collections.shuffle(targets, new java.util.Random(this.random.nextLong()));
        this.lightningMarks.clear();
        for (int i = 0; i < Math.min(LIGHTNING_MARKS, targets.size()); i++) {
            this.lightningMarks.add(snapToFloor(level, targets.get(i).position()));
        }
        this.lightningTelegraphTimer = LIGHTNING_TELEGRAPH_TICKS;
        this.lightningTimer = scaledCooldown(LIGHTNING_INTERVAL_TICKS);
        this.specialGapTimer = SPECIAL_GAP_TICKS;
        triggerAction(ANIM_CROWN_CALL); // The crown rises; the marks charge on the ground.
        level.playSound(null, this.blockPosition(), SoundEvents.BEACON_POWER_SELECT,
                SoundSource.HOSTILE, 1.0F, 1.3F);
        EclipseMod.LOGGER.info("Fog Tyrant crown lightning: {} mark(s) charging for {}t",
                this.lightningMarks.size(), LIGHTNING_TELEGRAPH_TICKS);
    }

    /** The marks are world-anchored — they charge and strike even while the boss moves. */
    private void tickCrownLightningMarks(ServerLevel level) {
        if (this.lightningTelegraphTimer < 0) {
            return;
        }
        if (this.lightningTelegraphTimer % 2 == 0) {
            for (Vec3 mark : this.lightningMarks) {
                for (int i = 0; i < 12; i++) {
                    double angle = (Math.PI * 2.0D / 12.0D) * i;
                    level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                            mark.x + Math.cos(angle) * LIGHTNING_RADIUS, mark.y + 0.15D,
                            mark.z + Math.sin(angle) * LIGHTNING_RADIUS,
                            1, 0.02D, 0.05D, 0.02D, 0.0D);
                }
            }
        }
        if (this.lightningTelegraphTimer % 10 == 0) {
            int elapsed = LIGHTNING_TELEGRAPH_TICKS - this.lightningTelegraphTimer;
            float pitch = 0.7F + elapsed / (float) LIGHTNING_TELEGRAPH_TICKS * 0.9F; // Rising.
            for (Vec3 mark : this.lightningMarks) {
                level.playSound(null, BlockPos.containing(mark), SoundEvents.AMETHYST_BLOCK_RESONATE,
                        SoundSource.HOSTILE, 1.3F, pitch);
            }
        }
        if (--this.lightningTelegraphTimer >= 0) {
            return;
        }
        releaseCrownLightning(level);
    }

    /** Visual-only bolts + manual r=2.5 damage — precise and zero fire grief (plan §2.4). */
    private void releaseCrownLightning(ServerLevel level) {
        int hits = 0;
        for (Vec3 mark : this.lightningMarks) {
            LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(level);
            if (bolt != null) {
                bolt.moveTo(mark.x, mark.y, mark.z);
                bolt.setVisualOnly(true);
                level.addFreshEntity(bolt);
            }
            for (ServerPlayer player : livingParticipants(level)) {
                double dx = player.getX() - mark.x;
                double dz = player.getZ() - mark.z;
                if (Math.sqrt(dx * dx + dz * dz) <= LIGHTNING_RADIUS
                        && Math.abs(player.getY() - mark.y) <= 4.0D
                        && player.hurt(this.damageSources().mobAttack(this), LIGHTNING_DAMAGE)) {
                    hits++;
                }
            }
        }
        this.lightningMarks.clear();
        EclipseMod.LOGGER.info("Fog Tyrant crown lightning struck: {} hit(s) (r={})", hits, LIGHTNING_RADIUS);
    }

    // --- blind squall (P2+: arena-wide LOS-checked blindness pulse, audio-cued) ---

    private void maybeStartSquall(ServerLevel level) {
        if (getPhase() < 2 || --this.squallTimer > 0 || this.specialGapTimer > 0) {
            return;
        }
        if (livingParticipants(level).isEmpty()) {
            this.squallTimer = 60;
            return;
        }
        this.squallWindupTimer = SQUALL_WINDUP_TICKS;
        this.squallTimer = scaledCooldown(SQUALL_INTERVAL_TICKS);
        this.specialGapTimer = SPECIAL_GAP_TICKS;
        setTelegraphing(true);
        triggerAction(ANIM_SQUALL);
        this.getNavigation().stop();
        // THE audio cue (the brief says dodge by ear): a warden sonic charge, unmistakable.
        level.playSound(null, this.blockPosition(), SoundEvents.WARDEN_SONIC_CHARGE,
                SoundSource.HOSTILE, 1.6F, 0.8F);
        EclipseMod.LOGGER.info("Fog Tyrant blind squall winding up for {}t — break line of sight!",
                SQUALL_WINDUP_TICKS);
    }

    private void tickSquallWindup(ServerLevel level) {
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        // The crown collapses inward while the storm inhales.
        if (this.squallWindupTimer % 3 == 0) {
            level.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + 3.4D, this.getZ(), 5, 0.9D, 0.5D, 0.9D, 0.02D);
        }
        if (this.squallWindupTimer % 10 == 0) {
            int elapsed = SQUALL_WINDUP_TICKS - this.squallWindupTimer;
            level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.HOSTILE, 1.2F, 0.6F + elapsed / (float) SQUALL_WINDUP_TICKS);
        }
        if (--this.squallWindupTimer >= 0) {
            return;
        }
        setTelegraphing(false);
        releaseSquall(level);
    }

    /** The pulse: everyone in the arena WITH line of sight eats Blindness 3 s + 4 dmg. */
    private void releaseSquall(ServerLevel level) {
        int blinded = 0;
        int covered = 0;
        for (ServerPlayer player : livingParticipants(level)) {
            if (!this.hasLineOfSight(player)) {
                covered++;
                continue; // Behind cover — the squall howls past them.
            }
            if (player.hurt(this.damageSources().mobAttack(this), SQUALL_DAMAGE)) {
                player.addEffect(new MobEffectInstance(MobEffects.BLINDNESS, SQUALL_BLIND_TICKS, 0), this);
                blinded++;
            }
        }
        // Expanding fog ring: three radii stamped outward from the crown.
        for (double radius : new double[] {3.0D, 7.0D, 12.0D}) {
            int count = (int) (radius * 5.0D);
            for (int i = 0; i < count; i++) {
                double angle = (Math.PI * 2.0D / count) * i;
                level.sendParticles(ParticleTypes.CLOUD,
                        this.getX() + Math.cos(angle) * radius, this.getY() + 1.2D,
                        this.getZ() + Math.sin(angle) * radius, 1, 0.1D, 0.25D, 0.1D, 0.02D);
            }
        }
        level.playSound(null, this.blockPosition(), SoundEvents.WARDEN_SONIC_BOOM,
                SoundSource.HOSTILE, 1.2F, 0.7F);
        level.playSound(null, this.blockPosition(), SoundEvents.ELDER_GUARDIAN_CURSE,
                SoundSource.HOSTILE, 1.2F, 0.6F);
        EclipseMod.LOGGER.info("Fog Tyrant blind squall released: {} blinded, {} safe behind cover",
                blinded, covered);
    }

    // --- enrage stacking (P2+: slow, capped, cooldowns tighten + speed creeps up) ---

    private void tickEnrage(ServerLevel level) {
        if (getPhase() < 2 || getEnrageStacks() >= ENRAGE_MAX_STACKS || --this.enrageTimer > 0) {
            return;
        }
        this.enrageTimer = ENRAGE_INTERVAL_TICKS;
        int stacks = getEnrageStacks() + 1;
        this.entityData.set(DATA_ENRAGE_STACKS, stacks);
        applyEnrageSpeed(stacks);
        triggerAction(ANIM_ENRAGE);
        level.playSound(null, this.blockPosition(), SoundEvents.RAVAGER_ROAR,
                SoundSource.HOSTILE, 1.4F, 0.5F - stacks * 0.03F);
        level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                this.getX(), this.getY() + 2.4D, this.getZ(), 25, 1.0D, 1.2D, 1.0D, 0.12D);
        EclipseMod.LOGGER.info("Fog Tyrant enrage stack {}/{}: cooldowns x{}, speed +{}%",
                stacks, ENRAGE_MAX_STACKS,
                String.format(Locale.ROOT, "%.2f", Math.max(0.4D, 1.0D - ENRAGE_COOLDOWN_PER_STACK * stacks)),
                (int) (ENRAGE_SPEED_PER_STACK * stacks * 100.0D));
    }

    /** Transient speed modifier — reapplied on load from the persisted stack count. */
    private void applyEnrageSpeed(int stacks) {
        AttributeInstance speed = this.getAttribute(Attributes.MOVEMENT_SPEED);
        if (speed != null && stacks > 0) {
            speed.addOrUpdateTransientModifier(new AttributeModifier(ENRAGE_SPEED_ID,
                    ENRAGE_SPEED_PER_STACK * stacks, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
        }
    }

    // --- adds (by-id lookups: zero compile-time coupling to the W7/W8 registrars) ---

    /** Hound howl: tops the tyrant's pack back up to {@value #HOUND_PACK} storm hounds. */
    private void tickHoundHowl(ServerLevel level) {
        if (--this.howlTimer > 0 || this.arena == null) {
            return;
        }
        this.howlTimer = HOWL_INTERVAL_TICKS;
        EntityType<?> houndType = BuiltInRegistries.ENTITY_TYPE.getOptional(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_hound")).orElse(null);
        if (houndType == null) {
            if (!this.warnedHoundUnbound) {
                this.warnedHoundUnbound = true;
                EclipseMod.LOGGER.warn("Fog Tyrant hound howl skipped: eclipse:storm_hound not registered "
                        + "(FogEntities wiring line missing — see docs/plans_v3/wiring/WB-TYRANT_wiring.md)");
            }
            return;
        }
        long alive = level.getEntities(this, this.getBoundingBox().inflate(FogTyrantArena.ARENA_RADIUS + 16.0D),
                e -> e.isAlive() && e.getTags().contains(ADD_TAG) && e.getType() == houndType).size();
        int wanted = HOUND_PACK - (int) alive;
        if (wanted <= 0) {
            return;
        }
        triggerAction(ANIM_CROWN_CALL); // The crown streams fog outward — the pack answers.
        level.playSound(null, this.blockPosition(), SoundEvents.WOLF_HOWL, SoundSource.HOSTILE, 1.6F, 0.6F);
        int spawned = 0;
        for (int i = 0; i < wanted; i++) {
            if (spawnTaggedAdd(level, houndType)) {
                spawned++;
            }
        }
        EclipseMod.LOGGER.info("Fog Tyrant hound howl: summoned {} storm hound(s) ({} already hunting)",
                spawned, alive);
    }

    /** P3 opener, once per fight: one colossus answers if none already lives nearby. */
    private void tickColossusCall(ServerLevel level) {
        if (getPhase() < 3 || this.colossusCalled || this.arena == null) {
            return;
        }
        this.colossusCalled = true;
        EntityType<?> colossusType = BuiltInRegistries.ENTITY_TYPE.getOptional(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fog_colossus")).orElse(null);
        if (colossusType == null) {
            if (!this.warnedColossusUnbound) {
                this.warnedColossusUnbound = true;
                EclipseMod.LOGGER.warn("Fog Tyrant colossus call skipped: eclipse:fog_colossus not registered "
                        + "(FogEliteEntities wiring line missing — see docs/plans_v3/wiring/WB-TYRANT_wiring.md)");
            }
            return;
        }
        boolean present = !level.getEntities(this, this.getBoundingBox().inflate(48.0D),
                e -> e.isAlive() && e.getType() == colossusType).isEmpty();
        if (present) {
            EclipseMod.LOGGER.info("Fog Tyrant colossus call skipped: a colossus already stands the storm");
            return;
        }
        triggerAction(ANIM_CROWN_CALL);
        level.playSound(null, this.blockPosition(), SoundEvents.RAVAGER_ROAR, SoundSource.HOSTILE, 1.8F, 0.4F);
        if (spawnTaggedAdd(level, colossusType)) {
            EclipseMod.LOGGER.info("Fog Tyrant P3: colossus called to the storm");
        }
    }

    /** Spawns one tagged add at the ring edge on solid footing; false when it misfires. */
    private boolean spawnTaggedAdd(ServerLevel level, EntityType<?> type) {
        if (this.arena == null) {
            return false;
        }
        double angle = this.random.nextDouble() * Math.PI * 2.0D;
        double radius = FogTyrantArena.ARENA_RADIUS - 3.0D;
        Vec3 pos = snapToFloor(level, new Vec3(
                this.arena.center().x + Math.cos(angle) * radius,
                this.arena.groundY() + 1.0D,
                this.arena.center().z + Math.sin(angle) * radius));
        Entity add = type.create(level);
        if (add == null) {
            return false;
        }
        add.moveTo(pos.x, pos.y, pos.z, this.random.nextFloat() * 360.0F, 0.0F);
        add.addTag(ADD_TAG); // Reset hygiene: discardTaggedAdds finds exactly these.
        if (!level.addFreshEntity(add)) {
            return false;
        }
        fogBurstFx(level, pos.add(0.0D, 0.8D, 0.0D), 15);
        return true;
    }

    /** Reset hygiene: no leftover hounds/colossi when the fight abandons (plan wipe rules). */
    private void discardTaggedAdds(ServerLevel level) {
        int removed = 0;
        for (Entity entity : level.getEntities(this, this.getBoundingBox().inflate(ADD_CLEANUP_RANGE),
                e -> e.getTags().contains(ADD_TAG))) {
            entity.discard();
            removed++;
        }
        if (removed > 0) {
            EclipseMod.LOGGER.info("Fog Tyrant reset: discarded {} leftover tagged add(s)", removed);
        }
    }

    // --- participant helpers (Herald pattern) ---

    private List<ServerPlayer> livingParticipants(ServerLevel level) {
        List<ServerPlayer> alive = new ArrayList<>();
        for (UUID id : this.participants) {
            ServerPlayer player = level.getServer().getPlayerList().getPlayer(id);
            if (player != null && player.isAlive() && !player.isSpectator() && player.level() == level
                    && this.arena != null
                    && this.arena.horizontalDistance(player.position()) <= FogTyrantArena.IMPULSE_RADIUS + 12.0D) {
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

    // --- arena integrity ---

    /**
     * Outside-ring damage deflects outright (Herald pattern — no sniping the monarch
     * from beyond the storm wall). After damage lands, the phase recomputes until stable
     * so a burst crossing 60%/25% still fires this tick's phase opener.
     */
    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (!this.level().isClientSide && this.isAlive() && this.arena != null
                && !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)
                && isFromOutsideArena(source)) {
            if (source.getEntity() instanceof ServerPlayer attacker) {
                playDeflectCue(attacker);
            }
            return false;
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
        return entity != null && this.arena != null
                && this.arena.horizontalDistance(entity.position()) > FogTyrantArena.ARENA_RADIUS;
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
        serverLevel.sendParticles(ParticleTypes.CLOUD, this.getX(), this.getY() + 2.2D, this.getZ(),
                10, 0.8D, 1.0D, 0.8D, 0.05D);
        EclipseMod.LOGGER.info("Fog Tyrant deflected outside-arena damage from {} ({} blocks out)",
                attacker.getScoreboardName(), this.arena == null ? "?" : String.format(
                        Locale.ROOT, "%.1f", this.arena.horizontalDistance(attacker.position())));
    }

    // --- death (70t storm-burst: crown falls, core gutters, thunderclap collapse) ---

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            setTelegraphing(false); // No stuck glow/root state on the wreck.
            clearTelegraphs();
            this.bossEvent.removeAllPlayers(); // No bar lingering at 0% through the collapse.
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
            // W4 IDEA-16 #3: queue the award ceremony (one shard payout per participant on
            // tickDeath keyframes) and start the long soft slow-mo drift shake at the kill.
            this.deathPayoutQueue.clear();
            this.deathPayoutQueue.addAll(this.participants);
            this.deathPayoutInterval = Mth.clamp(
                    (DEATH_THUNDERCLAP_TICK - DEATH_PAYOUT_START_TICK - 5)
                            / Math.max(1, this.deathPayoutQueue.size()), 3, 12);
            if (this.level() instanceof ServerLevel serverLevel) {
                PacketDistributor.sendToPlayersNear(serverLevel, null, this.getX(), this.getY(),
                        this.getZ(), 64.0D, S2CShakePayload.shake(0.15F, 40));
            }
            EclipseMod.LOGGER.info("Fog Tyrant defeated (source: {}) — starting the {}t storm-burst",
                    damageSource.getMsgId(), DEATH_DURATION_TICKS);
        }
    }

    /** Interrupt hygiene: kills every pending telegraph (phase breaks + death). */
    private void clearTelegraphs() {
        setTelegraphing(false);
        this.lanceTelegraphTimer = -1;
        this.lockedLances.clear();
        this.squallWindupTimer = -1;
        this.lightningTelegraphTimer = -1;
        this.lightningMarks.clear();
        this.stepOutTimer = -1;
        this.stepDest = null;
        this.stepTargetId = null;
    }

    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        // The monarch plants where it dies while the storm unravels around it.
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        if (this.deathTime < DEATH_CORE_GUTTER_TICK && this.deathTime % 4 == 0) {
            // The falling crown sheds its light (anim drops the shards in this window).
            serverLevel.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                    this.getX(), this.getY() + 3.4D, this.getZ(), 6, 0.7D, 0.5D, 0.7D, 0.04D);
        }
        if (this.deathTime == DEATH_CORE_GUTTER_TICK) {
            setCoreLit(false); // Ferryman lantern pattern: the chest core gutters out.
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + 2.0D, this.getZ(), 30, 0.6D, 0.8D, 0.6D, 0.02D);
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.ELDER_GUARDIAN_CURSE,
                    SoundSource.HOSTILE, 1.0F, 0.5F);
            EclipseMod.LOGGER.info("Fog Tyrant death: storm core guttered at t={}", this.deathTime);
        }
        if (this.deathTime > DEATH_CORE_GUTTER_TICK && this.deathTime % 5 == 0) {
            // The crown fog disperses upward as the body sags (plan §2.4 death read).
            serverLevel.sendParticles(ParticleTypes.CLOUD,
                    this.getX(), this.getY() + 2.6D, this.getZ(), 6, 0.8D, 0.4D, 0.8D, 0.06D);
        }
        tickPayoutCeremony(serverLevel);
        if (this.deathTime == DEATH_THUNDERCLAP_TICK) {
            PacketDistributor.sendToPlayersNear(serverLevel, null, this.getX(), this.getY(), this.getZ(),
                    64.0D, S2CShakePayload.shake(0.8F, 18));
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.LIGHTNING_BOLT_THUNDER,
                    SoundSource.HOSTILE, 1.6F, 0.5F);
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.WARDEN_SONIC_BOOM,
                    SoundSource.HOSTILE, 0.8F, 1.2F);
            fogBurstFx(serverLevel, this.position().add(0.0D, 1.5D, 0.0D), 60);
            EclipseMod.LOGGER.info("Fog Tyrant death thunderclap at t={}", this.deathTime);
        }
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /**
     * W4 IDEA-16 #3 loot ceremony (Herald pattern): one participant is rewarded per
     * keyframe — 3 umbral shards at their feet with a HEART_BURST quasar and a rising
     * amethyst chime — so the storm-burst doubles as the award sequence. Any remainder
     * drains at the thunderclap, so an oversized roster can never lose payouts to the
     * body removal. Eligibility matches the old {@code dropCustomDeathLoot} dump.
     */
    private void tickPayoutCeremony(ServerLevel level) {
        if (this.deathPayoutQueue.isEmpty() || this.deathTime < DEATH_PAYOUT_START_TICK) {
            return;
        }
        boolean drainAll = this.deathTime >= DEATH_THUNDERCLAP_TICK;
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
                new ItemStack(EclipseItems.UMBRAL_SHARD.get(), 3));
        PacketDistributor.sendToPlayersNear(level, null, player.getX(), player.getY(), player.getZ(),
                64.0D, new S2CQuasarPayload(S2CQuasarPayload.HEART_BURST, player.position()));
        level.playSound(null, player.blockPosition(), SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.2F, 0.8F + 0.15F * ++this.deathPayoutIndex);
        EclipseMod.LOGGER.info("Fog Tyrant ceremony payout: 3 umbral shards to {} (deathTime {})",
                player.getScoreboardName(), this.deathTime);
    }

    /**
     * Drops beyond the loot table: 1 {@code storm_heart} by P4-registry lookup (fallback
     * 6 umbral shards while P4 hasn't landed it, plan §2.4). The per-participant shard
     * payouts moved into {@code tickDeath} keyframes (W4 IDEA-16 #3 award ceremony —
     * everyone who braved the storm still gets paid, just staggered; see
     * {@code tickPayoutCeremony}).
     */
    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        BuiltInRegistries.ITEM.getOptional(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_heart"))
                .ifPresentOrElse(
                        item -> this.spawnAtLocation(new ItemStack(item)),
                        () -> {
                            this.spawnAtLocation(new ItemStack(EclipseItems.UMBRAL_SHARD.get(), 6));
                            EclipseMod.LOGGER.info("Fog Tyrant drop: eclipse:storm_heart not registered yet "
                                    + "(P4) — dropped the 6-umbral-shard fallback");
                        });
        EclipseMod.LOGGER.info("Fog Tyrant drops: storm heart (or fallback) at the corpse; {} participant "
                + "payout(s) queued for the storm-burst ceremony", this.participants.size());
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
     * band and resolves transitions immediately (fires the P2/P3 openers on the way down).
     */
    public void forcePhase(int phase) {
        float fraction = phase >= 3 ? 0.2F : phase == 2 ? 0.45F : 0.9F;
        this.setHealth(this.getMaxHealth() * fraction);
        if (this.level() instanceof ServerLevel serverLevel) {
            while (updatePhase(serverLevel)) {
                // Resolve to the forced phase now.
            }
        }
    }

    // --- boss chassis ---

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_PHASE, 1);
        builder.define(DATA_TELEGRAPH, false);
        builder.define(DATA_CORE_LIT, true);
        builder.define(DATA_ENRAGE_STACKS, 0);
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

    // --- sounds (a storm given a throne: warden family dragged into the fog) ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.WARDEN_AMBIENT;
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.WARDEN_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WARDEN_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.55F;
    }

    @Override
    protected float getSoundVolume() {
        return 1.6F;
    }

    @Override
    protected void playStepSound(BlockPos pos, BlockState state) {
        this.playSound(SoundEvents.WARDEN_STEP, 0.6F, 0.6F); // The monarch's tread.
    }

    // --- persistence (Ferryman NBT pattern: restart resumes phase + arena + roster) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt("ScaledPlayers", this.scaledPlayers);
        compound.putBoolean("ColossusCalled", this.colossusCalled);
        compound.putInt("EnrageStacks", getEnrageStacks());
        compound.putInt("FightTicks", this.fightTicks);
        if (this.arena != null) {
            this.arena.save(compound);
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
        this.colossusCalled = compound.getBoolean("ColossusCalled");
        this.fightTicks = compound.getInt("FightTicks");
        int stacks = Mth.clamp(compound.getInt("EnrageStacks"), 0, ENRAGE_MAX_STACKS);
        this.entityData.set(DATA_ENRAGE_STACKS, stacks);
        applyEnrageSpeed(stacks); // Transient modifier must be rebuilt after load.
        this.arena = FogTyrantArena.load(compound);
        for (Tag entry : compound.getList("Participants", Tag.TAG_INT_ARRAY)) {
            this.participants.add(NbtUtils.loadUUID(entry));
        }
        // Re-derive the phase so a reloaded fight resumes cleanly; a reload never
        // re-calls the colossus (ColossusCalled persisted) and never sticks a telegraph.
        float fraction = this.getMaxHealth() > 0.0F ? this.getHealth() / this.getMaxHealth() : 1.0F;
        this.lastPhase = fraction > 0.6F ? 1 : fraction > 0.25F ? 2 : 3;
        setPhase(this.lastPhase);
        clearTelegraphs();
        setCoreLit(true);
        if (this.hasCustomName()) {
            this.bossEvent.setName(this.getDisplayName());
        }
        EclipseMod.LOGGER.info("Fog Tyrant reloaded: phase {} at {}/{} HP, {} participant(s), "
                + "{} enrage stack(s), colossus called: {}",
                this.lastPhase, String.format(Locale.ROOT, "%.1f", this.getHealth()),
                String.format(Locale.ROOT, "%.1f", this.getMaxHealth()),
                this.participants.size(), stacks, this.colossusCalled);
    }

    // --- helpers ---

    /**
     * Fog burst FX — the single swap point for P2's {@code eclipse:fog_bank} emitter
     * (plan §4.2 isolation rule): vanilla cloud/smoke stand-in until then.
     */
    private void fogBurstFx(ServerLevel level, Vec3 pos, int strength) {
        level.sendParticles(ParticleTypes.CLOUD, pos.x, pos.y, pos.z,
                strength, 0.8D, 0.9D, 0.8D, 0.06D);
        level.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE, pos.x, pos.y + 0.3D, pos.z,
                Math.max(2, strength / 4), 0.6D, 0.5D, 0.6D, 0.01D);
    }

    /** Walks down from 2 above the sample point to the first solid floor (max 12). */
    private Vec3 snapToFloor(ServerLevel level, Vec3 pos) {
        BlockPos.MutableBlockPos cursor = BlockPos.containing(pos.x, pos.y + 2.0D, pos.z).mutable();
        for (int i = 0; i < 12; i++) {
            BlockPos below = cursor.below();
            if (!level.getBlockState(below).getCollisionShape(level, below).isEmpty()) {
                return new Vec3(pos.x, cursor.getY(), pos.z);
            }
            cursor.move(Direction.DOWN);
        }
        return pos; // No floor found: keep the sample height (open-storm contract).
    }

    /** Look helper for the fight script: turns body + head toward a target position. */
    private void faceTowards(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }
}
