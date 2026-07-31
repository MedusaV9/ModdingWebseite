package dev.projecteclipse.eclipse.backrooms;

import java.util.EnumSet;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.glitch.GlitchedHuskEntity;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
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
 *   <li><b>The notice→sprint chain</b> (MB5, census §5): the moment the pacing turns
 *       into a MUTUAL stare, the thing notices you — head snap at 0.10 s, then
 *       {@value #NOTICE_TICKS} t of a genuinely frozen body ({@link NoticeFreezeGoal}
 *       claims MOVE+LOOK so the stare cannot ice-skate) — and the sprint is what comes
 *       out the other side. {@link #isNoticing()} is synced so B5/B2 can hang their
 *       flicker and audio cues on the beat.</li>
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
     * The full-body "notice" freeze — head snap at 0.10 s, then a held stare. Fired
     * once per engagement, primarily on the {@link PaceGoal} STARE EDGE (the tick the
     * corridor pacing turns into a mutual stare), with target acquisition as the
     * fallback for players it never got to pace.
     */
    public static final String ANIM_NOTICE = "notice";
    /**
     * Length of the {@code notice} one-shot in ticks — {@code animation_length} 1.05 s
     * exactly ({@code scripts/geckolib_gen/mobs/backrooms_wanderer.py} {@code NOTICE}).
     * Also the length of the server-side freeze, so the planted legs never slide, and
     * the window B5/B2 schedule their cues inside (see the cue table in
     * {@code docs/plans_v3/session_0730/MB5_WANDERER_REPORT.md} §3).
     */
    public static final int NOTICE_TICKS = 21;
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
    /**
     * Fully disengaged (no target AND nobody being paced) for this long re-arms the
     * notice. Once per LIFE would mean a Wanderer you shook off in level 0 can never
     * scare you again; once per ENGAGEMENT keeps the beat rare without retiring it.
     */
    private static final int NOTICE_REARM_TICKS = 200;

    /** Synced to clients so B2's shroud and B5's dread can read the stare. */
    private static final EntityDataAccessor<Boolean> DATA_NOTICING =
            SynchedEntityData.defineId(GlitchedWandererEntity.class, EntityDataSerializers.BOOLEAN);

    /** The player the pace goal is currently stalking (server-side, transient). */
    @Nullable
    private Player pacedPlayer;

    /** Cached {@code animation.glitched_wanderer.sprint} loop (client-side). */
    @Nullable
    private RawAnimation cachedSprintAnim;

    /** Latch: one notice per engagement (cleared by {@link #NOTICE_REARM_TICKS}). */
    private boolean noticed;
    /** Server-side countdown of the freeze window; {@code > 0} means "staring". */
    private int noticeTicksLeft;
    /** Who the freeze is staring at — the head keeps tracking them while planted. */
    @Nullable
    private Player noticeStareTarget;
    /** Ticks with neither a target nor a paced player (the re-arm clock). */
    private int disengagedTicks;

    public GlitchedWandererEntity(EntityType<? extends GlitchedWandererEntity> entityType, Level level) {
        super(entityType, level);
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_NOTICING, false);
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
     * Suppresses the stutter-blink for the duration of the freeze. The {@code action}
     * controller holds exactly ONE one-shot at a time, so a blink landing inside the
     * window would replace {@code notice} mid-stare — and leave the mob standing in an
     * idle pose that the server is still holding rigid. The base class re-reads this
     * every {@code aiStep}, and the controller registration (which gates the trigger on
     * {@code > 0}) runs while the counter is zero, so the blink trigger stays registered.
     */
    @Override
    protected int blinkCooldownMinTicks() {
        return this.noticeTicksLeft > 0 ? -1 : super.blinkCooldownMinTicks();
    }

    /**
     * Fallback notice trigger: a player that walked straight into the 3-block crowding
     * range (or was picked up by {@code HurtByTargetGoal} through some other mob) never
     * went through the pace-and-stare edge, so acquisition is the only beat left.
     *
     * <p>Gated on {@code hurtTime == 0}: if YOU opened the fight, you get the husk's
     * normal lunge, not a free second of a mob standing still being hit.</p>
     */
    @Override
    public void setTarget(@Nullable LivingEntity target) {
        if (target instanceof Player watcher && this.getTarget() == null && this.hurtTime == 0) {
            beginNotice(watcher);
        }
        super.setTarget(target);
    }

    /**
     * Is the {@code notice} freeze running right now? Synced to clients — this is the
     * hook B5's dread curve and B2's shroud read to put their flicker/audio cues on the
     * stare (cue table: {@code MB5_WANDERER_REPORT} §3).
     */
    public boolean isNoticing() {
        return this.entityData.get(DATA_NOTICING);
    }

    /** Opens the freeze window and fires the one-shot (server-side, once per engagement). */
    private void beginNotice(@Nullable Player watcher) {
        if (this.noticed || this.noticeTicksLeft > 0 || this.level().isClientSide
                || !this.isAlive()) {
            return;
        }
        this.noticed = true;
        this.noticeTicksLeft = NOTICE_TICKS;
        this.noticeStareTarget = watcher;
        this.entityData.set(DATA_NOTICING, true);
        // The goal selector only re-evaluates next tick; kill the path NOW so the very
        // first frame of the snap is already standing still.
        this.getNavigation().stop();
        triggerAction(ANIM_NOTICE);
    }

    private void endNotice() {
        this.noticeTicksLeft = 0;
        this.noticeStareTarget = null;
        if (this.entityData.get(DATA_NOTICING)) {
            this.entityData.set(DATA_NOTICING, false);
        }
    }

    /** Freeze countdown + the once-per-ENGAGEMENT re-arm clock (server-side, every tick). */
    private void tickNotice() {
        if (this.noticeTicksLeft > 0 && --this.noticeTicksLeft == 0) {
            endNotice();
        }
        if (this.getTarget() == null && this.pacedPlayer == null) {
            if (this.noticed && ++this.disengagedTicks >= NOTICE_REARM_TICKS) {
                this.noticed = false;
                this.disengagedTicks = 0;
            }
        } else {
            this.disengagedTicks = 0;
        }
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
        // Above melee AND pace: while the thing is staring at you, it is doing nothing else.
        this.goalSelector.addGoal(1, new NoticeFreezeGoal(this));
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
        if (this.level().isClientSide) {
            return;
        }
        if (!this.isAlive()) {
            endNotice(); // A death anim mid-stare must not leave the flag stuck on.
            return;
        }
        tickNotice(); // Every tick — the freeze is 21 t, the gaze check is a 5 t sampler.
        if (this.tickCount % GAZE_CHECK_INTERVAL_TICKS != 0) {
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

    /**
     * The player currently being paced ({@code null} outside a stalk).
     *
     * <p>Reports the stare target for the duration of the notice freeze. B5's
     * {@code BackroomsDread.isHunting} keys off exactly this accessor, and the freeze
     * preempts {@link PaceGoal} — whose {@code stop()} clears the backing field. Without
     * the fallback the dread channel would see "not hunting" for
     * {@value #NOTICE_TICKS} t and fire {@code endPursuit}'s all-clear thud on the
     * scariest tick of the encounter, then restart the heartbeat from zero afterwards.
     * The internal stalk-burst read below deliberately uses the FIELD instead: a frozen
     * Wanderer must not be accelerating.</p>
     */
    @Nullable
    public Player pacedPlayer() {
        return this.noticeTicksLeft > 0 && this.noticeStareTarget != null
                ? this.noticeStareTarget : this.pacedPlayer;
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
                // THE STARE EDGE: pacing has just become a mutual stare. This — not the
                // 3-block aggro range — is where the notice belongs; the whole point of
                // the beat is that it happens across the corridor, while you still have
                // room to run. No-ops after the first one (the `noticed` latch).
                this.mob.beginNotice(this.followed);
            }
        }
    }

    /**
     * The freeze half of the notice→sprint chain. The one-shot alone is not enough: the
     * {@code action} controller overrides the bones, but the ENTITY keeps pathing, so a
     * "frozen" Wanderer with planted legs would glide down the corridor. Claiming
     * MOVE+LOOK for {@value GlitchedWandererEntity#NOTICE_TICKS} t preempts both
     * {@link PaceGoal} and the melee goal, and zeroing horizontal velocity kills the
     * residual slide that {@code getNavigation().stop()} alone leaves behind (friction
     * needs several ticks to bleed off — exactly the ticks the snap plays in).
     *
     * <p>Deliberately uninterruptible (only death ends it early, via
     * {@link #endNotice()}): at 1.05 s it is shorter than a vanilla shield-disable, and
     * a stare you can flinch out of is not a stare.</p>
     */
    static class NoticeFreezeGoal extends Goal {
        private final GlitchedWandererEntity mob;

        NoticeFreezeGoal(GlitchedWandererEntity mob) {
            this.mob = mob;
            this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK));
        }

        @Override
        public boolean canUse() {
            return this.mob.noticeTicksLeft > 0;
        }

        @Override
        public boolean canContinueToUse() {
            return this.mob.noticeTicksLeft > 0;
        }

        @Override
        public boolean requiresUpdateEveryTick() {
            return true;
        }

        @Override
        public void start() {
            this.mob.getNavigation().stop();
        }

        @Override
        public void tick() {
            this.mob.getNavigation().stop();
            // Y is left alone so gravity still applies — a hovering stare is a bug. And
            // `hurtTime` gates the whole clamp so the freeze never eats a KNOCKBACK: a
            // hit still throws it, it just refuses to walk.
            if (this.mob.hurtTime == 0) {
                this.mob.setDeltaMovement(this.mob.getDeltaMovement().multiply(0.0D, 1.0D, 0.0D));
            }
            Player stare = this.mob.noticeStareTarget;
            if (stare != null && stare.isAlive()) {
                // The body is nailed down; the head is the only thing still tracking you.
                this.mob.getLookControl().setLookAt(stare, 30.0F, 30.0F);
            }
        }
    }
}
