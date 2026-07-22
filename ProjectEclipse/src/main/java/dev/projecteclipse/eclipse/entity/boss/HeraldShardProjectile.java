package dev.projecteclipse.eclipse.entity.boss;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.game.ClientboundAddEntityPacket;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.projectile.ItemSupplier;
import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.entity.projectile.ProjectileUtil;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.gameevent.GameEvent;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;

/**
 * Homing corona shard fired by the Herald's P1/P2 volley ({@code docs/ideas/04_content.md}
 * §2.1) — a {@code ShulkerBullet}-style seeker, but steering smoothly instead of
 * axis-snapping: every tick the velocity eases toward the target's chest at
 * {@value #SPEED} b/t, so it arcs after strafing players yet stays outrunnable.
 *
 * <p>Counterplay: {@link #isPickable()} — one hit from any damage (arrow, snowball,
 * sword swipe) shatters it mid-air ({@link #hurt}). Deals {@value #DAMAGE} magic-projectile
 * damage on impact, breaks on any block. Despawns after {@value #LIFETIME_TICKS} ticks or
 * when the target is gone, so a reset fight never leaves shards circling.</p>
 *
 * <p>Renders as the umbral shard item sprite ({@link ItemSupplier}, fullbright
 * {@code ThrownItemRenderer} registered in {@code client.entity.EclipseEntityRenderers}).</p>
 */
public class HeraldShardProjectile extends Projectile implements ItemSupplier {
    public static final float DAMAGE = 4.0F;
    private static final double SPEED = 0.45D;
    /** Velocity easing per tick toward the desired homing vector (0..1). */
    private static final double STEERING = 0.18D;
    private static final int LIFETIME_TICKS = 200;

    @Nullable
    private Entity target;
    @Nullable
    private UUID targetId;
    private int life;

    public HeraldShardProjectile(EntityType<? extends HeraldShardProjectile> entityType, Level level) {
        super(entityType, level);
        this.noPhysics = true;
    }

    /** Spawns at {@code from} already flying toward {@code target} (slight upward lob). */
    public HeraldShardProjectile(Level level, LivingEntity shooter, Entity target, Vec3 from) {
        this(dev.projecteclipse.eclipse.entity.EclipseEntities.HERALD_SHARD.get(), level);
        this.setOwner(shooter);
        this.moveTo(from.x, from.y, from.z, this.getYRot(), this.getXRot());
        this.target = target;
        this.targetId = target.getUUID();
        this.setDeltaMovement(desiredVelocity());
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {}

    @Override
    public SoundSource getSoundSource() {
        return SoundSource.HOSTILE;
    }

    @Override
    protected void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        if (this.targetId != null) {
            compound.putUUID("Target", this.targetId);
        }
        compound.putInt("Life", this.life);
    }

    @Override
    protected void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.hasUUID("Target")) {
            this.targetId = compound.getUUID("Target");
        }
        this.life = compound.getInt("Life");
    }

    @Override
    public void tick() {
        super.tick();
        if (!this.level().isClientSide) {
            if (this.target == null && this.targetId != null) {
                this.target = ((ServerLevel) this.level()).getEntity(this.targetId);
                if (this.target == null) {
                    this.targetId = null;
                }
            }
            if (++this.life > LIFETIME_TICKS || !hasLiveTarget()) {
                shatter();
                return;
            }
            // Smooth homing: ease the velocity toward the target's chest.
            Vec3 velocity = this.getDeltaMovement();
            Vec3 desired = desiredVelocity();
            this.setDeltaMovement(velocity.add(
                    (desired.x - velocity.x) * STEERING,
                    (desired.y - velocity.y) * STEERING,
                    (desired.z - velocity.z) * STEERING));
            HitResult hitResult = ProjectileUtil.getHitResultOnMoveVector(this, this::canHitEntity);
            if (hitResult.getType() != HitResult.Type.MISS
                    && !net.neoforged.neoforge.event.EventHooks.onProjectileImpact(this, hitResult)) {
                this.hitTargetOrDeflectSelf(hitResult);
            }
        }
        this.checkInsideBlocks();
        Vec3 velocity = this.getDeltaMovement();
        this.setPos(this.getX() + velocity.x, this.getY() + velocity.y, this.getZ() + velocity.z);
        ProjectileUtil.rotateTowardsMovement(this, 0.5F);
        if (this.level().isClientSide) {
            this.level().addParticle(ParticleTypes.END_ROD,
                    this.getX() - velocity.x, this.getY() - velocity.y + 0.15D, this.getZ() - velocity.z,
                    0.0D, 0.0D, 0.0D);
        }
    }

    private boolean hasLiveTarget() {
        return this.target != null && this.target.isAlive()
                && !(this.target instanceof Player player && (player.isSpectator() || player.isCreative()));
    }

    /** Unit vector to the target's chest scaled to {@value #SPEED}; keeps heading when targetless. */
    private Vec3 desiredVelocity() {
        if (this.target == null) {
            return this.getDeltaMovement();
        }
        Vec3 aim = new Vec3(this.target.getX(), this.target.getY(0.5D), this.target.getZ())
                .subtract(this.position());
        return aim.lengthSqr() < 1.0E-4D ? this.getDeltaMovement() : aim.normalize().scale(SPEED);
    }

    @Override
    protected boolean canHitEntity(Entity hit) {
        // Never collide with the Herald that fired it or with sibling shards of the volley.
        return super.canHitEntity(hit) && !(hit instanceof HeraldShardProjectile)
                && !(hit instanceof HeraldEntity) && !hit.noPhysics;
    }

    @Override
    protected void onHitEntity(EntityHitResult result) {
        super.onHitEntity(result);
        Entity owner = this.getOwner();
        DamageSource source = this.damageSources().mobProjectile(this,
                owner instanceof LivingEntity living ? living : null);
        result.getEntity().hurt(source, DAMAGE);
    }

    @Override
    protected void onHitBlock(BlockHitResult result) {
        super.onHitBlock(result);
        this.playSound(SoundEvents.AMETHYST_BLOCK_BREAK, 1.0F, 0.8F);
    }

    @Override
    protected void onHit(HitResult result) {
        super.onHit(result);
        shatter();
    }

    /** Break apart in a small purple burst (impact, timeout, target loss and player hits). */
    private void shatter() {
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.WITCH,
                    this.getX(), this.getY(), this.getZ(), 8, 0.15D, 0.15D, 0.15D, 0.05D);
        }
        this.level().gameEvent(GameEvent.ENTITY_DAMAGE, this.position(), GameEvent.Context.of(this));
        this.discard();
    }

    @Override
    public boolean isPickable() {
        return true; // Shootable down (spec: arrows/melee shatter the shard mid-air).
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (!this.level().isClientSide) {
            this.playSound(SoundEvents.AMETHYST_CLUSTER_BREAK, 1.0F, 1.2F);
            shatter();
        }
        return true;
    }

    @Override
    public boolean shouldRenderAtSqrDistance(double distance) {
        return distance < 16384.0D;
    }

    @Override
    public float getLightLevelDependentMagicValue() {
        return 1.0F; // Fullbright: reads as a glowing ember even at night.
    }

    @Override
    public void recreateFromPacket(ClientboundAddEntityPacket packet) {
        super.recreateFromPacket(packet);
        this.setDeltaMovement(packet.getXa(), packet.getYa(), packet.getZa());
    }

    @Override
    public ItemStack getItem() {
        return new ItemStack(EclipseItems.UMBRAL_SHARD.get());
    }

    /** Client spin for the item renderer (age-based; shard tumbles as it flies). */
    public float spin(float partialTick) {
        return (this.tickCount + partialTick) * 20.0F * Mth.DEG_TO_RAD;
    }
}
