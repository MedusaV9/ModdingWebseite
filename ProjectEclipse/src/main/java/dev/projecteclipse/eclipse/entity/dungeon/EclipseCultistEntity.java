package dev.projecteclipse.eclipse.entity.dungeon;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Eclipse Cultist / Eklipsen-Kultist — the dungeon spawner caster
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3, worker P6-W10/W910): a
 * kneeling-height robed figure in the eclipsed-player charcoal (deep hood, wide sleeves,
 * three rune pages orbiting the left hand, ritual knife) that kites to the 8–14 band and
 * casts 3-bolt {@link ShadowBoltProjectile} fans through {@link RangedShadowBoltGoal};
 * crowded within 2 blocks it answers with a panic knife swipe.
 *
 * <p>Spawner-friendly by design (spec: "no persistence quirks"): plain MONSTER despawn
 * rules, 20 HP / 3 dmg / 0.3 speed, so the Collapsed Vault and Umbral Warrens spawners
 * ({@code DungeonSpawners} arrays) can re-supply rooms indefinitely. Also the Rift
 * Warden's phase-2 summon (by-id registry lookup — no compile-time coupling from the boss
 * package). Death is a scripted {@value #DEATH_ANIM_TICKS}t kneel-forward collapse (hood
 * empties, cloth flat). Drops via loot table {@code eclipse:entities/eclipse_cultist}
 * (candles/ink/lapis + rare umbral shard) plus a 10% {@code cultist_sigil} P4-registry
 * lookup (skipped while P4 hasn't landed it).</p>
 */
public class EclipseCultistEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "eclipse_cultist";
    /** 20t cast raise (runes flare, arms up) fired by {@link RangedShadowBoltGoal}. */
    public static final String ANIM_CAST = "cast";
    /** Scripted death window (sheet: 30t kneel forward, hood empties). */
    public static final int DEATH_ANIM_TICKS = 30;

    private static final float SIGIL_DROP_CHANCE = 0.10F;

    public EclipseCultistEntity(EntityType<? extends EclipseCultistEntity> entityType, Level level) {
        super(entityType, level);
        this.xpReward = 5;
    }

    /** Spec §2.3: 20 HP, dmg 3, speed 0.3 — a glass cannon that dies to two good hits. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 20.0D)
                .add(Attributes.ATTACK_DAMAGE, 3.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.3D)
                .add(Attributes.FOLLOW_RANGE, 24.0D);
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
        action.triggerableAnim(ANIM_CAST, EclipseGeoAnimations.once(GEO_ID, ANIM_CAST));
    }

    // --- AI (caster kit; the ranged goal owns kiting, casting and the panic swipe) ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new RangedShadowBoltGoal(this));
        this.goalSelector.addGoal(6, new WaterAvoidingRandomStrollGoal(this, 0.8D));
        this.goalSelector.addGoal(7, new LookAtPlayerGoal(this, Player.class, 8.0F));
        this.goalSelector.addGoal(8, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    // --- combat ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // Panic knife swipe.
            this.level().playSound(null, this.blockPosition(), SoundEvents.PLAYER_ATTACK_SWEEP,
                    SoundSource.HOSTILE, 0.8F, 1.4F);
        }
        return hurt;
    }

    // --- death (scripted kneel-forward collapse; renderer suppresses the vanilla flip) ---

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
        }
    }

    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime % 6 == 0) {
            serverLevel.sendParticles(ParticleTypes.WITCH,
                    this.getX(), this.getY() + 0.8D, this.getZ(), 5, 0.3D, 0.4D, 0.3D, 0.02D);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.sendParticles(ParticleTypes.SOUL,
                    this.getX(), this.getY() + 0.6D, this.getZ(), 10, 0.3D, 0.3D, 0.3D, 0.03D);
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /** P4 economy hook: 10% cultist_sigil by registry lookup, skipped while unregistered. */
    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        if (this.random.nextFloat() >= SIGIL_DROP_CHANCE) {
            return;
        }
        net.minecraft.core.registries.BuiltInRegistries.ITEM.getOptional(
                        net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cultist_sigil"))
                .ifPresentOrElse(
                        item -> this.spawnAtLocation(new net.minecraft.world.item.ItemStack(item)),
                        () -> EclipseMod.LOGGER.debug(
                                "Eclipse Cultist drop: eclipse:cultist_sigil not registered yet (P4) — skipped"));
    }

    // --- sounds (a low murmured chant; evoker family pitched down) ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.EVOKER_AMBIENT;
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.EVOKER_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.EVOKER_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.7F + this.random.nextFloat() * 0.1F;
    }
}
