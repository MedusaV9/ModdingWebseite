package dev.projecteclipse.eclipse.backrooms;

import java.util.EnumSet;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.glitch.GlitchedHuskEntity;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.RandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.animation.RawAnimation;

/**
 * The <b>Wanderer</b> — the Backrooms texture-variant of {@link GlitchedHuskEntity}
 * (IDEAS-backrooms_finale §A3.1): same GeckoLib geo/anim shape under geoId
 * {@value #GEO_ID} with ONE new mono-yellow "wet paint" texture sheet, re-tuned from
 * shambler to <i>stalker</i>:
 *
 * <ul>
 *   <li><b>Corridor pacing</b>: while nothing has aggroed it, {@link PaceGoal} (the
 *       {@code TheOtherEntity.MimicWalkGoal} clone) walks toward the nearest player at
 *       corridor pace and STOPS at {@value #STARE_RANGE} blocks to stare.</li>
 *   <li><b>Unseen burst IS the stalking</b>: the husk's gaze-keyed speed modifier is
 *       extended to the <i>paced</i> player (not just a combat target) — every time you
 *       look away it closes distance at +50% speed with a static tell, and freezes back
 *       to a stare when you turn around. The inherited husk burst still covers the
 *       combat-target case.</li>
 *   <li><b>Melee only when crowded</b>: the unprovoked target selector requires
 *       ≤ {@value #ATTACK_TRIGGER_RANGE} blocks ({@code TheOtherEntity.ATTACK_TRIGGER_RANGE}
 *       -style predicate); {@code FOLLOW_RANGE} {@value #DETECTION_RANGE} — the user decree
 *       caps detection at 20 blocks (no cross-map stalking).</li>
 *   <li><b>Glitch blink / corrupted voice</b>: inherited (200–280 t blink cadence,
 *       {@code ZOMBIE_AMBIENT} through the unstable 0.6–1.4 voice pitch).</li>
 * </ul>
 *
 * <p>Spawned exclusively by {@code BackroomsEventService}'s budgeted pass — no natural
 * spawning. {@link #isSeenBy} exposes the protected gaze test for
 * {@code BackroomsScare}'s lookaway condition.</p>
 */
public class GlitchedWandererEntity extends GlitchedHuskEntity {
    /** Frozen asset triple id: geo/anim copies + the 4 python-recolored texture sheets. */
    public static final String GEO_ID = "glitched_wanderer";
    /**
     * Wanderer-only {@code base} loop (MOB-GLITCH): the flailing burst-sprint played
     * while a gaze-burst speed modifier is live (see {@link #handleBaseState}).
     */
    public static final String ANIM_SPRINT = "sprint";
    /**
     * REPASS-MOB personality one-shot: the full-body "notice" freeze fired on the FIRST
     * target acquisition (the Storm Hound howl / Fog Colossus roar {@code setTarget}
     * pattern — cosmetic only, not persisted, no AI/balance effect).
     */
    public static final String ANIM_NOTICE = "notice";
    /** Players closer than this may be attacked unprovoked (IDEAS §A3.1). */
    public static final double ATTACK_TRIGGER_RANGE = 3.0D;
    /** {@link PaceGoal} stops and stares at this distance (IDEAS §A3.1: 12). */
    public static final double STARE_RANGE = 12.0D;
    /** User decree: backrooms mobs only notice players within 20 blocks. */
    public static final double DETECTION_RANGE = 20.0D;
    /** Pursuit keeps a small hysteresis over {@link #DETECTION_RANGE} (no goal thrash). */
    private static final double PURSUIT_DROP_RANGE = 24.0D;
    /** Pace speed modifier — corridor-walking pace over the 0.27 base. */
    private static final double PACE_SPEED = 0.85D;

    private static final ResourceLocation STALK_SPEED_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glitched_wanderer_stalk_burst");
    /** Mirrors the husk's +0.5 multiply-total unseen burst, keyed off the PACED player. */
    private static final AttributeModifier STALK_SPEED = new AttributeModifier(
            STALK_SPEED_ID, 0.5D, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL);
    private static final int GAZE_CHECK_INTERVAL_TICKS = 5;

    /** The player the pace goal is currently stalking (server-side, transient). */
    @Nullable
    private Player pacedPlayer;

    /** Cached {@code animation.glitched_wanderer.sprint} loop (client-side). */
    @Nullable
    private RawAnimation cachedSprintAnim;

    /** One notice freeze per life (transient, like the Storm Hound's {@code howled}). */
    private boolean noticed;

    public GlitchedWandererEntity(EntityType<? extends GlitchedWandererEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Husk stats with the decree-capped detection range ({@value #DETECTION_RANGE}). */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 30.0D)
                .add(Attributes.ATTACK_DAMAGE, 5.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.27D)
                .add(Attributes.FOLLOW_RANGE, DETECTION_RANGE);
    }

    @Override
    public String geoId() {
        return GEO_ID;
    }

    /**
     * Presentation only (MOB-GLITCH): while a gaze-keyed burst modifier is live and
     * the mob is moving, the {@code base} controller plays the {@code sprint} flail
     * instead of the corridor {@code walk}. Runs client-side off the SYNCED
     * {@code MOVEMENT_SPEED} modifiers (the attribute is syncable, so both the stalk
     * and the inherited husk unseen-burst ids arrive with the attribute packet) — no
     * AI/balance change, and if the modifier ever fails to sync the walk plays.
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        if (state.isMoving() && hasGazeBurst()) {
            if (this.cachedSprintAnim == null) {
                this.cachedSprintAnim = EclipseGeoAnimations.loop(geoId(), ANIM_SPRINT);
            }
            return state.setAndContinue(this.cachedSprintAnim);
        }
        return super.handleBaseState(state);
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death + attack + glitch_blink
        action.triggerableAnim(ANIM_NOTICE, EclipseGeoAnimations.once(GEO_ID, ANIM_NOTICE));
    }

    /**
     * Notice freeze on the FIRST target acquisition (Storm Hound howl pattern): the
     * stalker locks up head-to-toe for a beat before it comes for you. Cosmetic only —
     * the target set itself is untouched.
     */
    @Override
    public void setTarget(@Nullable LivingEntity target) {
        if (target != null && this.getTarget() == null && !this.noticed
                && !this.level().isClientSide && this.isAlive()) {
            this.noticed = true;
            triggerAction(ANIM_NOTICE);
        }
        super.setTarget(target);
    }

    /** Is either gaze-burst speed modifier (stalk or inherited husk unseen) live? */
    private boolean hasGazeBurst() {
        AttributeInstance speed = this.getAttribute(Attributes.MOVEMENT_SPEED);
        return speed != null
                && (speed.hasModifier(STALK_SPEED_ID) || speed.hasModifier(UNSEEN_SPEED_ID));
    }

    // --- AI: pace-and-stare replaces the husk's always-hostile targeting ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.1D, false));
        this.goalSelector.addGoal(3, new PaceGoal(this));
        this.goalSelector.addGoal(6, new RandomStrollGoal(this, 0.8D, 120));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        // Unprovoked aggression only against players that get too close (crowding rule).
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, 10, true, false,
                target -> target.distanceToSqr(this) <= ATTACK_TRIGGER_RANGE * ATTACK_TRIGGER_RANGE));
    }

    /**
     * Stalk burst: while PACING (no combat target), the unseen-speed modifier keys off
     * the paced player's gaze — "it's closer every time you turn around". The inherited
     * husk burst (combat target) runs in {@code super.aiStep()}; the two modifiers are
     * mutually exclusive by construction (paced ⇒ target == null).
     */
    @Override
    public void aiStep() {
        super.aiStep();
        if (this.level().isClientSide || !this.isAlive()
                || this.tickCount % GAZE_CHECK_INTERVAL_TICKS != 0) {
            return;
        }
        AttributeInstance speed = this.getAttribute(Attributes.MOVEMENT_SPEED);
        if (speed == null) {
            return;
        }
        Player paced = this.pacedPlayer;
        boolean unseen = this.getTarget() == null && paced != null && paced.isAlive()
                && !paced.isSpectator() && !isLookedAtBy(paced);
        boolean bursting = speed.hasModifier(STALK_SPEED_ID);
        if (unseen && !bursting) {
            speed.addTransientModifier(STALK_SPEED);
            if (this.level() instanceof ServerLevel serverLevel) {
                serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        this.getX(), this.getY() + 1.0D, this.getZ(), 6, 0.25D, 0.4D, 0.25D, 0.02D);
            }
        } else if (!unseen && bursting) {
            speed.removeModifier(STALK_SPEED_ID);
        }
    }

    /** Public gaze test for {@code BackroomsScare} (lookaway condition, IDEAS §A4). */
    public boolean isSeenBy(Player player) {
        return isLookedAtBy(player);
    }

    /** The player currently being paced ({@code null} outside a stalk). */
    @Nullable
    public Player pacedPlayer() {
        return pacedPlayer;
    }

    /**
     * The stalking goal ({@code TheOtherEntity.MimicWalkGoal} clone, IDEAS §A3.1): paths
     * toward the nearest player at corridor pace ({@value #PACE_SPEED} modifier — the
     * gaze burst does the closing), stops at {@value #STARE_RANGE} blocks and stares.
     * Yields to combat (runs only while no target is set).
     */
    static class PaceGoal extends Goal {
        private final GlitchedWandererEntity mob;
        @Nullable
        private Player followed;

        PaceGoal(GlitchedWandererEntity mob) {
            this.mob = mob;
            this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK));
        }

        @Override
        public boolean canUse() {
            if (this.mob.getTarget() != null) {
                return false;
            }
            this.followed = this.mob.level().getNearestPlayer(this.mob, DETECTION_RANGE);
            return this.followed != null && !this.followed.isSpectator();
        }

        @Override
        public boolean canContinueToUse() {
            return this.mob.getTarget() == null && this.followed != null && this.followed.isAlive()
                    && !this.followed.isSpectator()
                    && this.mob.distanceToSqr(this.followed) < PURSUIT_DROP_RANGE * PURSUIT_DROP_RANGE;
        }

        @Override
        public void start() {
            this.mob.pacedPlayer = this.followed;
        }

        @Override
        public void stop() {
            this.followed = null;
            this.mob.pacedPlayer = null;
            this.mob.getNavigation().stop();
        }

        @Override
        public boolean requiresUpdateEveryTick() {
            return true;
        }

        @Override
        public void tick() {
            if (this.followed == null) {
                return;
            }
            this.mob.pacedPlayer = this.followed;
            this.mob.getLookControl().setLookAt(this.followed, 30.0F, 30.0F);
            if (this.mob.distanceToSqr(this.followed) > STARE_RANGE * STARE_RANGE) {
                this.mob.getNavigation().moveTo(this.followed, PACE_SPEED);
            } else if (!this.mob.isSeenBy(this.followed)) {
                // Unseen inside stare range: keep creeping — the scare setup distance.
                this.mob.getNavigation().moveTo(this.followed, PACE_SPEED);
            } else {
                this.mob.getNavigation().stop(); // Seen. Stand still. Stare.
            }
        }
    }
}
