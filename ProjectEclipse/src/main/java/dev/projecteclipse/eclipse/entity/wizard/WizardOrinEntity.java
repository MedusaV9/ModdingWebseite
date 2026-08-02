package dev.projecteclipse.eclipse.entity.wizard;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
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
import net.minecraft.world.BossEvent;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MoveTowardsRestrictionGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Orin the Sun-Reader / Orin der Sonnenleser — the hermit astronomer of the mountain
 * observatory (W4-WIZARD; {@code docs/plans_v3/ideas_wave4/IDEA-19_wand.md} §3): a
 * NEUTRAL named NPC ({@code eclipse:wizard_orin}, id FROZEN) who gates the veil-wand
 * catalyst behind combat — WANDFIX-5 retired the fetch-quest hand-over, the sun-core
 * is now only ever TAKEN.
 *
 * <p><b>Neutral hermit</b>: wanders his observatory (leashed via
 * {@link #restrictTo(BlockPos, int)} + {@link MoveTowardsRestrictionGoal}), gazes at the
 * sky (the {@code idle} sky-gaze loop), watches players who come close
 * ({@link LookAtPlayerGoal} + a pitched-villager greeting hum, once per player per
 * ~minute), and trades nothing.</p>
 *
 * <p><b>Dialogue</b>: right-click cycles four localized eclipse riddles
 * ({@code dialogue.eclipse.wizard_orin.1..4}, per-player rotation) as an "Orin:" chat
 * caption. Every fourth line is the combat challenge hint ({@code challenge_hint}) until
 * the player has taken a core from him, then the victory acknowledgement
 * ({@code challenge_taken}; ledger in {@link WizardData}, re-openable via
 * {@code /dev wizard resetquest}).</p>
 *
 * <p><b>The fight</b> (WANDFIX-5; scripted in {@link #tick()}, Herald house pattern in
 * miniature — no target goals, he only ever answers his attacker): damage from a player
 * provokes him and raises a plain yellow bossbar. Three moves, each quoting one wand path
 * (IDEA-19 §2 C: "the boss teaches the player what the wand can become"):</p>
 * <ul>
 *   <li><b>star_call</b> (Sternenfall): {@value #STAR_CALL_TELEGRAPH_TICKS}t rooted raise
 *       telegraph (rising chimes + zone sparkles), then {@value #STAR_CALL_BOLTS} sky-bolts
 *       (frozen {@code FX_LIGHTNING_STRIKE} ribbons) over the locked zone,
 *       {@value #STAR_CALL_DAMAGE} dmg near each impact.</li>
 *   <li><b>sun_flare</b> (Glutpfad): punishes melee crowding — {@value
 *       #SUN_FLARE_TELEGRAPH_TICKS}t rooted gather (inrushing flame ring), then a radiant
 *       nova: {@value #SUN_FLARE_DAMAGE} dmg + knockback + a short searing burn within
 *       {@value #SUN_FLARE_RADIUS} blocks.</li>
 *   <li><b>veil_step</b> (Risspfad): an attacker closing to melee is answered with a short
 *       blink to safe ground inside his summit leash (collision-checked candidates,
 *       {@value #VEIL_STEP_COOLDOWN_TICKS}t cooldown).</li>
 * </ul>
 *
 * <p><b>Unveiled</b> at ≤50% health: one bark ({@code unveil}), then faster cooldowns,
 * shorter telegraphs and denser bolt showers. Leaving the summit (or dying) calms him;
 * he heals to full like the Herald's arena reset. On death he drops exactly ONE catalyst
 * ({@link #dropCustomDeathLoot}), the killer is recorded in the {@link WizardData} ledger
 * (so the dialogue can acknowledge the victor), and {@link WizardService} respawns him at
 * his hut the next overworld day.</p>
 */
public class WizardOrinEntity extends EclipseGeoMob {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "wizard_orin";

    public static final String ANIM_STAR_CALL = "star_call";
    /**
     * MB2: dedicated sun_flare gather→nova sheet (1.4 s; nova beat at 0.8 s = the
     * {@value #SUN_FLARE_TELEGRAPH_TICKS}t telegraph release) — the raise pose used to be
     * shared with star_call, which mis-sold the inrushing-flame gather as a sky-raise.
     */
    public static final String ANIM_SUN_FLARE = "sun_flare";
    /**
     * MB2: veil_step arrival re-materialize (0.55 s riss-stretch snap) — triggered right
     * after {@link #teleportTo}; GeckoLib syncs to tracking clients, so the one-shot plays
     * at the destination (the blink itself is instantaneous, only the landing is animated).
     */
    public static final String ANIM_VEIL_STEP = "veil_step";
    public static final String ANIM_HURT = "hurt";
    /** MOB-AMBIENT v2 hospitality one-shots: hat-tip greeting + ledger-lean dialogue. */
    public static final String ANIM_GREET = "greet";
    public static final String ANIM_TRADE = "trade";

    /** Scripted sit-down-fade death length ({@code animation.wizard_orin.death} = 2.0 s). */
    public static final int DEATH_DURATION_TICKS = 40;

    /** How far from home Orin will wander (restriction radius, blocks). */
    public static final int HOME_RADIUS = 10;

    // --- star_call (Sternenfall quote): telegraph → sky-bolt shower over a locked zone ---
    private static final int STAR_CALL_COOLDOWN_TICKS = 120;
    private static final int STAR_CALL_COOLDOWN_UNVEILED = 90;
    private static final int STAR_CALL_TELEGRAPH_TICKS = 25;
    private static final int STAR_CALL_TELEGRAPH_UNVEILED = 18;
    private static final int STAR_CALL_BOLTS = 10;
    private static final int STAR_CALL_BOLTS_UNVEILED = 14;
    private static final int STAR_CALL_BOLT_INTERVAL = 5;
    private static final double STAR_CALL_ZONE_RADIUS = 4.0D;
    private static final double STAR_CALL_HIT_RADIUS = 2.2D;
    private static final float STAR_CALL_DAMAGE = 6.0F;
    // --- sun_flare (Glut quote): rooted gather → radiant melee-punish nova ---
    private static final int SUN_FLARE_COOLDOWN_TICKS = 160;
    private static final int SUN_FLARE_COOLDOWN_UNVEILED = 110;
    private static final int SUN_FLARE_TELEGRAPH_TICKS = 15;
    private static final double SUN_FLARE_RADIUS = 4.5D;
    private static final float SUN_FLARE_DAMAGE = 7.0F;
    private static final int SUN_FLARE_FIRE_TICKS = 60;
    private static final float SUN_FLARE_KNOCKBACK = 1.1F;
    // --- veil_step (Riss quote): melee-pressure escape blink inside the summit leash ---
    private static final int VEIL_STEP_COOLDOWN_TICKS = 100;
    private static final double VEIL_STEP_TRIGGER_RANGE = 3.5D;
    private static final double VEIL_STEP_MIN_DIST = 5.0D;
    private static final double VEIL_STEP_MAX_DIST = 9.0D;
    private static final int VEIL_STEP_ATTEMPTS = 12;
    /** Health fraction at which the one-time "unveil" phase shift fires. */
    private static final float UNVEIL_FRACTION = 0.5F;
    /** Provocation memory: calm down after this long without being hurt again. */
    private static final int PROVOKED_TICKS = 600;
    private static final double GREET_RANGE = 6.0D;
    private static final int GREET_COOLDOWN_TICKS = 1200;
    private static final int DIALOGUE_LINES = 4;

    /** True while the star_call raise telegraph runs (hat star + staff tip flare cue). */
    private static final EntityDataAccessor<Boolean> DATA_CASTING =
            SynchedEntityData.defineId(WizardOrinEntity.class, EntityDataSerializers.BOOLEAN);

    // --- transient server state (deliberately NOT persisted: a restart calms him) ---
    @Nullable
    private UUID provokedBy;
    private int provokedTicks;
    private int castCooldown = 60;
    private int telegraphTimer = -1;
    private int boltsLeft;
    private int boltTimer;
    @Nullable
    private Vec3 starZone;
    private int flareTelegraph = -1;
    private int flareCooldown = 40;
    private int veilCooldown;
    private boolean unveiled;
    private final Map<UUID, Integer> dialogueCursor = new HashMap<>();
    private final Map<UUID, Long> greetedAt = new HashMap<>();

    /** WANDFIX-5 mini-boss bar: plain yellow, only visible while he is provoked. */
    private final ServerBossEvent bossEvent = new ServerBossEvent(
            Component.translatable("name.eclipse.wizard_orin"),
            BossEvent.BossBarColor.YELLOW, BossEvent.BossBarOverlay.PROGRESS);

    public WizardOrinEntity(EntityType<? extends WizardOrinEntity> entityType, Level level) {
        super(entityType, level);
        this.setPersistenceRequired();
        this.bossEvent.setVisible(false);
    }

    /**
     * WANDFIX-5 combat statblock: a real gate fight now that the core is combat-only —
     * 160 HP / armor 6 sits deliberately at roughly half a solo Herald (300 HP), tuned
     * for an iron-to-diamond-kit player. Still no melee: all pressure is scripted casts.
     */
    public static AttributeSupplier.Builder createAttributes() {
        return createMobAttributes()
                .add(Attributes.MAX_HEALTH, 160.0D)
                .add(Attributes.ARMOR, 6.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.3D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 0.8D)
                .add(Attributes.FOLLOW_RANGE, 48.0D);
    }

    /** Applies the NPC dressing every spawner path shares (service spawn + /summon). */
    public void initAsNpc(BlockPos home) {
        this.setCustomName(Component.translatable("name.eclipse.wizard_orin"));
        this.setCustomNameVisible(true); // NameTagHider only hides PLAYER tags — safe.
        this.restrictTo(home, HOME_RADIUS);
        this.setPersistenceRequired();
    }

    // --- GeckoLib wiring (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(ANIM_STAR_CALL, EclipseGeoAnimations.once(GEO_ID, ANIM_STAR_CALL));
        action.triggerableAnim(ANIM_SUN_FLARE, EclipseGeoAnimations.once(GEO_ID, ANIM_SUN_FLARE));
        action.triggerableAnim(ANIM_VEIL_STEP, EclipseGeoAnimations.once(GEO_ID, ANIM_VEIL_STEP));
        action.triggerableAnim(ANIM_HURT, EclipseGeoAnimations.once(GEO_ID, ANIM_HURT));
        action.triggerableAnim(ANIM_GREET, EclipseGeoAnimations.once(GEO_ID, ANIM_GREET));
        action.triggerableAnim(ANIM_TRADE, EclipseGeoAnimations.once(GEO_ID, ANIM_TRADE));
    }

    /**
     * POLISH2 contract-v2 blend-in (EVAL2-C H-3): {@code greet}/{@code trade} snap 66°
     * on {@code arm_left.rotx} out of {@code idle} — fired on EVERY player approach and
     * every trade, right in front of the player's camera — so both get 3 t; {@code hurt}
     * is a flinch whose damage precedes the trigger (follow-through class) → 2 t.
     * MUST stay hard: {@code sun_flare} (nova beat at 0.8 s is frame-exact against the
     * {@value #SUN_FLARE_TELEGRAPH_TICKS} t telegraph timer), {@code veil_step} (the
     * riss-rematerialize snap IS the point — glitch class), {@code star_call} (the
     * {@code glow_staff_crystal} bone is a Molang continuous rotation — spin hazard,
     * cultist-runes precedent) and {@code death} (scripted
     * {@value #DEATH_DURATION_TICKS} t sit-down-fade window == clip length).
     */
    @Override
    protected int actionTransitionTicks(String animName) {
        return switch (animName) {
            case ANIM_GREET, ANIM_TRADE -> 3;
            case ANIM_HURT -> 2;
            default -> 0;
        };
    }

    // --- AI (gentle observatory life; combat is scripted in tick()) ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(3, new MoveTowardsRestrictionGoal(this, 1.0D));
        this.goalSelector.addGoal(4, new WaterAvoidingRandomStrollGoal(this, 0.6D));
        this.goalSelector.addGoal(5, new LookAtPlayerGoal(this, Player.class, 8.0F, 0.08F));
        this.goalSelector.addGoal(6, new RandomLookAroundGoal(this));
        // No target goals: he never hunts. star_call answers his attacker from tick().
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_CASTING, false);
    }

    public boolean isCasting() {
        return this.entityData.get(DATA_CASTING);
    }

    private void setCasting(boolean casting) {
        this.entityData.set(DATA_CASTING, casting);
    }

    // --- ticking (greeting + the scripted three-move fight) ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        tickGreeting(serverLevel);
        tickProvocation(serverLevel);
        tickCombat(serverLevel);
        this.bossEvent.setVisible(isProvoked());
        if (isProvoked()) {
            this.bossEvent.setProgress(this.getHealth() / this.getMaxHealth());
        }
    }

    /** A small "hmm?" hum for players stepping close — once per player per minute. */
    private void tickGreeting(ServerLevel level) {
        if (this.tickCount % 10 != 0 || isProvoked()) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || !player.isAlive()
                    || player.distanceToSqr(this) > GREET_RANGE * GREET_RANGE) {
                continue;
            }
            long last = this.greetedAt.getOrDefault(player.getUUID(), Long.MIN_VALUE);
            if (level.getGameTime() - last < GREET_COOLDOWN_TICKS) {
                continue;
            }
            this.greetedAt.put(player.getUUID(), level.getGameTime());
            this.getLookControl().setLookAt(player, 30.0F, 30.0F);
            triggerAction(ANIM_GREET); // MOB-AMBIENT v2: hat-tip salute with the free hand.
            // Vanilla aliases (no sounds.json edits): a low villager hum + a star chime.
            level.playSound(null, this.blockPosition(), SoundEvents.VILLAGER_AMBIENT,
                    SoundSource.NEUTRAL, 0.8F, 0.78F);
            level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.NEUTRAL, 0.6F, 1.4F);
        }
    }

    /** Provocation memory: forget an attacker who is gone/dead/quiet, and heal up. */
    private void tickProvocation(ServerLevel level) {
        if (this.provokedBy == null) {
            return;
        }
        ServerPlayer attacker = resolveAttacker(level);
        boolean gone = attacker == null || !attacker.isAlive() || attacker.isSpectator()
                || attacker.distanceToSqr(this) > 48.0D * 48.0D;
        if (gone || --this.provokedTicks <= 0) {
            EclipseMod.LOGGER.info("Orin calms down (attacker {})", gone ? "gone" : "quiet");
            this.provokedBy = null;
            this.telegraphTimer = -1;
            this.boltsLeft = 0;
            this.starZone = null;
            this.flareTelegraph = -1;
            this.flareCooldown = 40;
            this.veilCooldown = 0;
            this.unveiled = false;
            setCasting(false);
            this.setHealth(this.getMaxHealth()); // The mountain mends its keeper.
        }
    }

    private boolean isProvoked() {
        return this.provokedBy != null;
    }

    @Nullable
    private ServerPlayer resolveAttacker(ServerLevel level) {
        return this.provokedBy == null ? null
                : level.getServer().getPlayerList().getPlayer(this.provokedBy);
    }

    /**
     * The scripted WANDFIX-5 fight loop, priority-ordered: finish a running bolt shower →
     * run a rooted telegraph (sun_flare, then star_call) → veil-step away from melee
     * pressure → choose the next move (sun_flare if crowded, else star_call on cooldown).
     * Every damaging move keeps a visible rooted telegraph — the fairness contract every
     * boss in the mod honors.
     */
    private void tickCombat(ServerLevel level) {
        if (this.flareCooldown > 0) {
            this.flareCooldown--;
        }
        if (this.veilCooldown > 0) {
            this.veilCooldown--;
        }
        // Release phase: rain the remaining bolts over the locked zone.
        if (this.boltsLeft > 0) {
            if (--this.boltTimer <= 0) {
                this.boltTimer = STAR_CALL_BOLT_INTERVAL;
                this.boltsLeft--;
                dropStarBolt(level);
            }
            return;
        }
        ServerPlayer attacker = resolveAttacker(level);
        if (attacker == null) {
            return;
        }
        maybeUnveil(level, attacker);
        // sun_flare telegraph: rooted gather, flames rushing inward onto the caster.
        if (this.flareTelegraph >= 0) {
            this.getNavigation().stop();
            this.getLookControl().setLookAt(attacker, 30.0F, 30.0F);
            if (this.flareTelegraph % 3 == 0) {
                double ring = SUN_FLARE_RADIUS * this.flareTelegraph / SUN_FLARE_TELEGRAPH_TICKS;
                level.sendParticles(ParticleTypes.FLAME, this.getX(), this.getY() + 1.0D,
                        this.getZ(), 10, Math.max(0.3D, ring * 0.5D), 0.3D,
                        Math.max(0.3D, ring * 0.5D), 0.02D);
            }
            if (--this.flareTelegraph < 0) {
                setCasting(false);
                releaseSunFlare(level);
            }
            return;
        }
        // star_call telegraph: rooted raise, zone sparkles where the stars will land.
        if (this.telegraphTimer >= 0) {
            int telegraphTicks = unveiled ? STAR_CALL_TELEGRAPH_UNVEILED : STAR_CALL_TELEGRAPH_TICKS;
            this.getNavigation().stop();
            this.getLookControl().setLookAt(attacker, 30.0F, 30.0F);
            if (this.starZone != null && this.telegraphTimer % 5 == 0) {
                int elapsed = telegraphTicks - this.telegraphTimer;
                float pitch = 0.9F + elapsed / (float) telegraphTicks * 0.8F;
                level.playSound(null, BlockPos.containing(this.starZone),
                        SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.NEUTRAL, 1.2F, pitch);
                level.sendParticles(ParticleTypes.END_ROD, this.starZone.x,
                        this.starZone.y + 0.4D, this.starZone.z,
                        6, STAR_CALL_ZONE_RADIUS * 0.5D, 0.2D, STAR_CALL_ZONE_RADIUS * 0.5D, 0.01D);
            }
            if (--this.telegraphTimer < 0) {
                setCasting(false);
                this.boltsLeft = unveiled ? STAR_CALL_BOLTS_UNVEILED : STAR_CALL_BOLTS;
                this.boltTimer = 1;
                EclipseMod.LOGGER.info("Orin star_call released: {} bolts over ({})",
                        this.boltsLeft, this.starZone == null ? "?" : this.starZone.toString());
            }
            return;
        }
        // veil_step: melee crowding between casts is answered with a short blink away.
        tryVeilStep(level, attacker);
        // sun_flare beats star_call whenever the attacker sits in nova range.
        if (this.flareCooldown <= 0
                && this.distanceToSqr(attacker) <= SUN_FLARE_RADIUS * SUN_FLARE_RADIUS) {
            startSunFlare(level);
            return;
        }
        if (--this.castCooldown > 0) {
            return;
        }
        // Wind up a new shower on the attacker's current ground position.
        this.castCooldown = unveiled ? STAR_CALL_COOLDOWN_UNVEILED : STAR_CALL_COOLDOWN_TICKS;
        this.telegraphTimer = unveiled ? STAR_CALL_TELEGRAPH_UNVEILED : STAR_CALL_TELEGRAPH_TICKS;
        this.starZone = attacker.position();
        setCasting(true);
        triggerAction(ANIM_STAR_CALL);
        // MB2 §7.3 / POLISH1: the star_call Photon partner rides the SAME tick as the
        // anim trigger so the client column starts with the raise. a = seconds to the
        // release beat (the WizardFxRows leg picks the _fast asset off it), b = shower
        // seconds; both mirror the telegraph/bolt constants below.
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WIZARD_STAR_CALL, this,
                unveiled ? 0.95F : 1.30F,
                (unveiled ? STAR_CALL_BOLTS_UNVEILED : STAR_CALL_BOLTS) * 0.25F,
                64.0D);
        this.getNavigation().stop();
        level.playSound(null, this.blockPosition(), SoundEvents.EVOKER_PREPARE_SUMMON,
                SoundSource.NEUTRAL, 0.9F, 1.5F);
        EclipseMod.LOGGER.info("Orin star_call telegraphed: {}t over ({}, {}, {})",
                this.telegraphTimer,
                String.format(java.util.Locale.ROOT, "%.1f", this.starZone.x),
                String.format(java.util.Locale.ROOT, "%.1f", this.starZone.y),
                String.format(java.util.Locale.ROOT, "%.1f", this.starZone.z));
    }

    /**
     * The one-time ≤{@value #UNVEIL_FRACTION} phase shift: one bark, a resonant flash,
     * and every cooldown window tightens (the constants' {@code _UNVEILED} variants).
     */
    private void maybeUnveil(ServerLevel level, ServerPlayer attacker) {
        if (this.unveiled || this.getHealth() > this.getMaxHealth() * UNVEIL_FRACTION) {
            return;
        }
        this.unveiled = true;
        say(attacker, Component.translatable("dialogue.eclipse.wizard_orin.unveil"));
        this.castCooldown = Math.min(this.castCooldown, 20);
        this.flareCooldown = Math.min(this.flareCooldown, 40);
        level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.NEUTRAL, 1.4F, 0.9F);
        level.sendParticles(ParticleTypes.END_ROD, this.getX(), this.getY() + 1.2D, this.getZ(),
                30, 0.6D, 0.9D, 0.6D, 0.1D);
        EclipseMod.LOGGER.info("Orin unveiled at {}/{} HP — cooldowns tightened",
                String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()), this.getMaxHealth());
    }

    /** sun_flare wind-up: dedicated gather anim (nova beat 0.8 s = the 16t release). */
    private void startSunFlare(ServerLevel level) {
        this.flareTelegraph = SUN_FLARE_TELEGRAPH_TICKS;
        this.flareCooldown = unveiled ? SUN_FLARE_COOLDOWN_UNVEILED : SUN_FLARE_COOLDOWN_TICKS;
        setCasting(true);
        triggerAction(ANIM_SUN_FLARE);
        this.getNavigation().stop();
        level.playSound(null, this.blockPosition(), SoundEvents.EVOKER_PREPARE_ATTACK,
                SoundSource.NEUTRAL, 0.9F, 0.8F);
        EclipseMod.LOGGER.info("Orin sun_flare telegraphed: {}t", SUN_FLARE_TELEGRAPH_TICKS);
    }

    /** sun_flare payoff: radiant nova — damage + knockback + a short searing burn. */
    private void releaseSunFlare(ServerLevel level) {
        level.playSound(null, this.blockPosition(), SoundEvents.FIRECHARGE_USE,
                SoundSource.NEUTRAL, 1.0F, 0.8F);
        level.sendParticles(ParticleTypes.FLAME, this.getX(), this.getY() + 1.0D, this.getZ(),
                40, SUN_FLARE_RADIUS * 0.5D, 0.6D, SUN_FLARE_RADIUS * 0.5D, 0.12D);
        level.sendParticles(ParticleTypes.LAVA, this.getX(), this.getY() + 0.5D, this.getZ(),
                8, 0.5D, 0.3D, 0.5D, 0.0D);
        int hit = 0;
        for (LivingEntity target : level.getEntitiesOfClass(LivingEntity.class,
                this.getBoundingBox().inflate(SUN_FLARE_RADIUS),
                entity -> entity != this && entity.isAlive())) {
            target.hurt(level.damageSources().indirectMagic(this, this), SUN_FLARE_DAMAGE);
            target.knockback(SUN_FLARE_KNOCKBACK,
                    this.getX() - target.getX(), this.getZ() - target.getZ());
            target.setRemainingFireTicks(Math.max(target.getRemainingFireTicks(), SUN_FLARE_FIRE_TICKS));
            hit++;
        }
        EclipseMod.LOGGER.info("Orin sun_flare released: {} target(s) seared", hit);
    }

    /**
     * veil_step: when the attacker closes to {@value #VEIL_STEP_TRIGGER_RANGE} between
     * casts, blink {@value #VEIL_STEP_MIN_DIST}–{@value #VEIL_STEP_MAX_DIST} blocks to
     * collision-checked ground near his leash (the wand's own blink candidate pattern,
     * {@code WandPowers.findBlinkTarget}). No damage — pure repositioning.
     */
    private void tryVeilStep(ServerLevel level, ServerPlayer attacker) {
        if (this.veilCooldown > 0
                || this.distanceToSqr(attacker) > VEIL_STEP_TRIGGER_RANGE * VEIL_STEP_TRIGGER_RANGE) {
            return;
        }
        Vec3 from = this.position();
        for (int attempt = 0; attempt < VEIL_STEP_ATTEMPTS; attempt++) {
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double dist = VEIL_STEP_MIN_DIST
                    + this.random.nextDouble() * (VEIL_STEP_MAX_DIST - VEIL_STEP_MIN_DIST);
            double x = from.x + Math.cos(angle) * dist;
            double z = from.z + Math.sin(angle) * dist;
            if (this.hasRestriction() && !this.getRestrictCenter().closerToCenterThan(
                    new Vec3(x, this.getRestrictCenter().getY(), z), HOME_RADIUS + 4.0D)) {
                continue; // Never blink off his own summit leash.
            }
            for (int dy = 3; dy >= -4; dy--) {
                Vec3 feet = new Vec3(x, from.y + dy, z);
                AABB box = this.getBoundingBox().move(feet.subtract(from));
                if (!level.noCollision(this, box)
                        || level.getBlockState(BlockPos.containing(feet).below()).isAir()) {
                    continue;
                }
                level.sendParticles(ParticleTypes.REVERSE_PORTAL, from.x, from.y + 1.0D, from.z,
                        16, 0.3D, 0.7D, 0.3D, 0.05D);
                this.teleportTo(feet.x, feet.y, feet.z);
                this.resetFallDistance();
                this.veilCooldown = VEIL_STEP_COOLDOWN_TICKS;
                // MB2: arrival re-materialize (riss-stretch snap) — after the teleport so
                // tracking clients play the one-shot at the destination, not the origin.
                triggerAction(ANIM_VEIL_STEP);
                level.sendParticles(ParticleTypes.REVERSE_PORTAL, feet.x, feet.y + 1.0D, feet.z,
                        16, 0.3D, 0.7D, 0.3D, 0.05D);
                level.playSound(null, BlockPos.containing(feet), SoundEvents.ENDERMAN_TELEPORT,
                        SoundSource.NEUTRAL, 0.8F, 1.3F);
                this.getLookControl().setLookAt(attacker, 30.0F, 30.0F);
                EclipseMod.LOGGER.info("Orin veil_step: {} -> {}",
                        from.toString(), feet.toString());
                return;
            }
        }
    }

    /** One falling star: a thin sky ribbon (frozen FX payload) + burst + zone damage. */
    private void dropStarBolt(ServerLevel level) {
        if (this.starZone == null) {
            this.boltsLeft = 0;
            return;
        }
        double angle = this.random.nextDouble() * Math.PI * 2.0D;
        double radius = this.random.nextDouble() * STAR_CALL_ZONE_RADIUS;
        Vec3 impact = new Vec3(this.starZone.x + Math.cos(angle) * radius,
                this.starZone.y, this.starZone.z + Math.sin(angle) * radius);
        // Visual: a low-intensity veil-lightning ribbon reads as a falling star
        // (IDEA-19 §2 C tier 4 — the exact trick the Sternenfall wand path will use).
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.25F, 0.0F, 96.0D);
        level.sendParticles(ParticleTypes.END_ROD, impact.x, impact.y + 0.3D, impact.z,
                10, 0.3D, 0.4D, 0.3D, 0.08D);
        level.sendParticles(ParticleTypes.FIREWORK, impact.x, impact.y + 0.2D, impact.z,
                6, 0.25D, 0.2D, 0.25D, 0.05D);
        level.playSound(null, BlockPos.containing(impact), SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.NEUTRAL, 1.0F, 1.6F);
        for (LivingEntity target : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(BlockPos.containing(impact)).inflate(STAR_CALL_HIT_RADIUS),
                entity -> entity != this && entity.isAlive())) {
            target.hurt(level.damageSources().indirectMagic(this, this), STAR_CALL_DAMAGE);
        }
    }

    // --- interaction (dialogue; WANDFIX-5 removed the fetch-quest turn-in for good) ---

    @Override
    protected InteractionResult mobInteract(Player player, InteractionHand hand) {
        if (hand != InteractionHand.MAIN_HAND || !this.isAlive()) {
            return super.mobInteract(player, hand);
        }
        if (this.level().isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(player instanceof ServerPlayer serverPlayer)
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return InteractionResult.CONSUME;
        }
        if (isProvoked()) {
            say(serverPlayer, Component.translatable("dialogue.eclipse.wizard_orin.provoked"));
            return InteractionResult.CONSUME;
        }
        speakLine(serverLevel, serverPlayer);
        return InteractionResult.CONSUME;
    }

    /**
     * Rotates the four riddles per player; every fourth line is the combat challenge
     * hint (WANDFIX-5 — the core is won, never traded), or the victory acknowledgement
     * once the {@link WizardData} ledger says this player already took one.
     */
    private void speakLine(ServerLevel level, ServerPlayer player) {
        WizardData data = WizardData.get(level.getServer().overworld());
        int cursor = this.dialogueCursor.merge(player.getUUID(), 1, Integer::sum) - 1;
        boolean earned = data.hasCatalyst(player.getUUID());
        Component line;
        if (cursor % DIALOGUE_LINES == DIALOGUE_LINES - 1) {
            line = Component.translatable(earned
                    ? "dialogue.eclipse.wizard_orin.challenge_taken"
                    : "dialogue.eclipse.wizard_orin.challenge_hint");
        } else {
            line = Component.translatable("dialogue.eclipse.wizard_orin." + (cursor % DIALOGUE_LINES + 1));
        }
        say(player, line);
        this.getLookControl().setLookAt(player, 30.0F, 30.0F);
        // MB2 verified: Orin has NO container menu (WANDFIX-5 — "trades nothing"); THIS
        // dialogue exchange is his "Handel", and this tick is the open moment: caption,
        // trade sound and the GeckoLib trigger all flush in the same packet batch, so the
        // ledger-lean lands exactly with the caption on every tracking client.
        triggerAction(ANIM_TRADE); // MOB-AMBIENT v2: ledger-lean toward the listener.
        level.playSound(null, this.blockPosition(), SoundEvents.VILLAGER_TRADE,
                SoundSource.NEUTRAL, 0.7F, 0.75F);
    }

    /**
     * "Orin: <line>" chat caption (gold name, per the NPC caption convention). Baked through
     * {@link ServerLang#resolve} so the dialogue follows the player's effective MOD locale —
     * a raw translatable would resolve with the client's vanilla language instead.
     */
    private void say(ServerPlayer player, Component line) {
        player.sendSystemMessage(ServerLang.resolve(player, Component.empty()
                .append(Component.translatable("name.eclipse.wizard_orin")
                        .withStyle(ChatFormatting.GOLD))
                .append(Component.literal(": ").withStyle(ChatFormatting.GOLD))
                .append(line.copy().withStyle(ChatFormatting.YELLOW))));
    }

    // --- combat hooks (provocation + flinch) ---

    @Override
    public boolean hurt(DamageSource source, float amount) {
        boolean hurt = super.hurt(source, amount);
        if (hurt && !this.level().isClientSide && this.isAlive()) {
            if (source.getEntity() instanceof ServerPlayer attacker && !attacker.isSpectator()) {
                boolean fresh = this.provokedBy == null;
                this.provokedBy = attacker.getUUID();
                this.provokedTicks = PROVOKED_TICKS;
                if (fresh) {
                    this.castCooldown = Math.min(this.castCooldown, 30); // Answer promptly.
                    say(attacker, Component.translatable("dialogue.eclipse.wizard_orin.provoked"));
                    EclipseMod.LOGGER.info("Orin provoked by {}", attacker.getScoreboardName());
                }
            }
            if (this.telegraphTimer < 0 && this.flareTelegraph < 0 && this.boltsLeft == 0) {
                // Flinch, unless mid-raise OR mid-shower (the cast/conducting reads through
                // — the retimed 3.6 s star_call keeps the staff up while the bolts rain).
                triggerAction(ANIM_HURT);
            }
        }
        return hurt;
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            setCasting(false);
            this.bossEvent.setVisible(false);
            this.bossEvent.removeAllPlayers();
            triggerAction(EclipseGeoAnimations.ANIM_DEATH); // Sit-down-fade, held.
            if (this.level() instanceof ServerLevel serverLevel) {
                WizardService.onWizardDied(serverLevel, this);
                // WANDFIX-5 victory ledger: remember who took a core in combat so the
                // dialogue acknowledges the victor (challenge_taken). Same once-per-player
                // semantics as before; /dev wizard resetquest still re-opens it.
                if (damageSource.getEntity() instanceof ServerPlayer killer) {
                    WizardData.get(serverLevel.getServer().overworld())
                            .grantCatalyst(killer.getUUID());
                }
            }
            EclipseMod.LOGGER.info("Orin died ({}) — catalyst drop + next-day respawn scheduled",
                    damageSource.getMsgId());
        }
    }

    /** Scripted 40 t sit-down-fade, then the poof (Ferryman/Rift-Warden precedent). */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        if (this.deathTime % 5 == 0) {
            serverLevel.sendParticles(ParticleTypes.END_ROD,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 3, 0.3D, 0.5D, 0.3D, 0.02D);
        }
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.isRemoved()) {
            serverLevel.sendParticles(ParticleTypes.FIREWORK,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 20, 0.4D, 0.8D, 0.4D, 0.08D);
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /**
     * The guaranteed take-path drop: exactly ONE catalyst at the corpse, independent of
     * loot tables, kill credit and looting (IDEA-19 §3 "1× catalyst guaranteed on death").
     */
    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        if (!WizardEntities.WIZARD_CATALYST.isBound()) {
            EclipseMod.LOGGER.warn("Orin death drop skipped: eclipse:wizard_catalyst not registered "
                    + "(apply docs/plans_v3/wiring/W4-WIZARD_wiring.md)");
            return;
        }
        ItemEntity drop = this.spawnAtLocation(new ItemStack(WizardEntities.WIZARD_CATALYST.get()));
        if (drop != null) {
            drop.setUnlimitedLifetime(); // Never let the summit wind despawn the gate item.
            // MB2 re-coupling: the NEWFX-A5 handover FX (shard indraw + fuse flash +
            // star-trail drop, row in ProgressionPhotonFxRows) was orphaned when WANDFIX-5
            // retired tryQuestTurnIn. The take-path IS the handover now — fire the cue on
            // the corpse drop, entity lane on Orin (the 40t sit-down-fade keeps him
            // tracked; untracked clients degrade to the payload's position anchor).
            FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WIZARD_CATALYST, this,
                    0.0F, 0.0F, 64.0D);
        }
    }

    // --- bossbar bookkeeping (Herald pattern; the bar itself only shows while provoked) ---

    @Override
    public void startSeenByPlayer(ServerPlayer player) {
        super.startSeenByPlayer(player);
        this.bossEvent.addPlayer(player);
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

    // --- chassis ---

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // The hermit keeps his watch.
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void doPush(Entity entity) {
        // Never shoves guests around the observatory.
    }

    @Override
    public boolean isInvulnerableTo(DamageSource source) {
        // Environmental deaths would strand the catalyst loop in a lava crack; players
        // (and /kill) remain the only ways to take him down.
        if (source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return false;
        }
        if (source.getEntity() instanceof Player) {
            return super.isInvulnerableTo(source);
        }
        return true;
    }

    // --- sounds (villager family pitched down — the wiring doc lists the aliases) ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return isProvoked() ? null : SoundEvents.VILLAGER_AMBIENT;
    }

    @Override
    public float getVoicePitch() {
        return 0.78F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.VILLAGER_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.VILLAGER_DEATH;
    }

    // --- persistence (home restriction survives restarts) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        if (this.hasRestriction()) {
            compound.putLong("HomePos", this.getRestrictCenter().asLong());
        }
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("HomePos")) {
            this.restrictTo(BlockPos.of(compound.getLong("HomePos")), HOME_RADIUS);
        }
    }
}
