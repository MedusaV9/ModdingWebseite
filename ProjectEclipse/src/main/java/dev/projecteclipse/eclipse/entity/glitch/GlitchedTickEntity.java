package dev.projecteclipse.eclipse.entity.glitch;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.world.DifficultyInstance;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.SpawnGroupData;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.RandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.ServerLevelAccessor;
import net.minecraft.world.level.block.state.BlockState;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Glitched Tick / Glitch-Zecke — the 0.5-block shard-mite of the fresh map rings
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3 "glitched", kind TICK). Boils
 * out of unstable ground in threes (see {@link #finalizeSpawn}); each is nothing, the
 * swarm is the threat. 12 HP / 3 dmg / speed 0.42; loot:
 * {@code eclipse:entities/glitched_tick} (a corrupted circuit scrap) + 1–2
 * {@code glitch_shard} from the shared {@code GlitchDrops} tag hook.
 *
 * <p><b>Latch</b> (sheet: "latches for tick damage"): a landed bite clamps the mite on
 * for up to {@value #LATCH_TICKS} t — while its victim stays within
 * {@value #LATCH_RANGE} blocks it re-bites for {@value #LATCH_DAMAGE} every
 * {@value #LATCH_BITE_INTERVAL_TICKS} t (the {@code latch} one-shot re-clamps with each
 * bite, the core glow flaring). The clamp breaks when the victim lands ANY hit back on
 * the mite (it pops off with a hop) or puts distance between them — swat it or
 * sprint.</p>
 *
 * <p>No blink: ticks are pure swarm pressure ({@code blinkCooldownMinTicks} stays
 * -1).</p>
 */
public class GlitchedTickEntity extends GlitchedMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "glitched_tick";
    /** Extra triggerable on the {@code action} controller (the clamp one-shot). */
    public static final String ANIM_LATCH = "latch";
    /** Scripted death window (anim file: 1.0 s flip-and-still). */
    public static final int DEATH_ANIM_TICKS = 20;
    /** Latch parameters: 5 s clamp, re-bite every 1 s while adjacent. */
    private static final int LATCH_TICKS = 100;
    private static final int LATCH_BITE_INTERVAL_TICKS = 20;
    private static final float LATCH_DAMAGE = 1.0F;
    private static final double LATCH_RANGE = 2.0D;
    /** Fresh-ring spawns arrive in threes (W6 bestiary: "boil out ... in threes"). */
    private static final int NATURAL_GROUP_EXTRAS = 2;

    private int latchTicksLeft;

    public GlitchedTickEntity(EntityType<? extends GlitchedTickEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Spec §2.3 kind stats: TICK 12 HP / 3 dmg / 0.42. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 12.0D)
                .add(Attributes.ATTACK_DAMAGE, 3.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.42D)
                .add(Attributes.FOLLOW_RANGE, 24.0D);
    }

    // --- GeckoLib / kind knobs ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected int deathAnimTicks() {
        return DEATH_ANIM_TICKS;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death + attack (no blink for ticks)
        action.triggerableAnim(ANIM_LATCH, EclipseGeoAnimations.once(GEO_ID, ANIM_LATCH));
    }

    // --- AI ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.3D, true));
        this.goalSelector.addGoal(6, new RandomStrollGoal(this, 1.0D, 60));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    /** A landed bite starts (or refreshes) the clamp. */
    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide && target instanceof LivingEntity) {
            boolean freshLatch = this.latchTicksLeft <= 0;
            this.latchTicksLeft = LATCH_TICKS;
            if (freshLatch) {
                triggerAction(ANIM_LATCH);
                this.playSound(SoundEvents.SPIDER_AMBIENT, 0.5F, 1.8F);
            }
        }
        return hurt;
    }

    /** Latched tick damage: re-bite every second while clamped and adjacent. */
    @Override
    public void aiStep() {
        super.aiStep();
        if (this.level().isClientSide || this.latchTicksLeft <= 0 || !this.isAlive()) {
            return;
        }
        this.latchTicksLeft--;
        LivingEntity target = this.getTarget();
        if (target == null || !target.isAlive() || this.distanceTo(target) > LATCH_RANGE) {
            this.latchTicksLeft = 0; // Shaken off by distance.
            return;
        }
        if (this.latchTicksLeft % LATCH_BITE_INTERVAL_TICKS == 0
                && target.hurt(this.damageSources().mobAttack(this), LATCH_DAMAGE)) {
            triggerAction(ANIM_LATCH); // Re-clamp: hunch + core flare per bite.
            this.playSound(SoundEvents.SILVERFISH_STEP, 0.4F, 1.6F);
        }
    }

    /** Any hit from the clamped victim pops the mite off with a defensive hop. */
    @Override
    public boolean hurt(DamageSource source, float amount) {
        boolean hurt = super.hurt(source, amount);
        if (hurt && !this.level().isClientSide && this.latchTicksLeft > 0
                && source.getEntity() != null && source.getEntity() == this.getTarget()) {
            this.latchTicksLeft = 0;
            Entity attacker = source.getEntity();
            double dx = this.getX() - attacker.getX();
            double dz = this.getZ() - attacker.getZ();
            double norm = Math.max(0.01D, Mth.length(dx, dz));
            this.setDeltaMovement(this.getDeltaMovement()
                    .add(dx / norm * 0.35D, 0.3D, dz / norm * 0.35D));
            this.hurtMarked = true;
        }
        return hurt;
    }

    /**
     * Natural fresh-ring spawns arrive as a swarm of three: the spawn-service mob rolls
     * {@value #NATURAL_GROUP_EXTRAS} REINFORCEMENT companions beside it (REINFORCEMENT
     * spawns skip this hook, so no recursion; spawner/summon spawns stay single so
     * dungeon traps and admins keep exact counts).
     */
    @Override
    @Nullable
    public SpawnGroupData finalizeSpawn(ServerLevelAccessor level, DifficultyInstance difficulty,
            MobSpawnType spawnType, @Nullable SpawnGroupData spawnGroupData) {
        SpawnGroupData data = super.finalizeSpawn(level, difficulty, spawnType, spawnGroupData);
        if (spawnType == MobSpawnType.NATURAL && level instanceof ServerLevel serverLevel) {
            for (int i = 0; i < NATURAL_GROUP_EXTRAS; i++) {
                Entity companion = this.getType().create(serverLevel);
                if (companion instanceof Mob mob) {
                    mob.moveTo(this.getX() + (this.random.nextDouble() - 0.5D) * 2.0D, this.getY(),
                            this.getZ() + (this.random.nextDouble() - 0.5D) * 2.0D,
                            this.random.nextFloat() * 360.0F, 0.0F);
                    mob.finalizeSpawn(serverLevel, difficulty, MobSpawnType.REINFORCEMENT, null);
                    serverLevel.addFreshEntity(mob);
                }
            }
        }
        return data;
    }

    // --- presentation ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.SILVERFISH_AMBIENT; // Chittering static.
    }

    @Override
    public float getVoicePitch() {
        return 1.2F + this.random.nextFloat() * 0.5F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.SILVERFISH_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.SILVERFISH_DEATH;
    }

    @Override
    protected void playStepSound(BlockPos pos, BlockState state) {
        this.playSound(SoundEvents.SILVERFISH_STEP, 0.25F, 1.4F);
    }
}
