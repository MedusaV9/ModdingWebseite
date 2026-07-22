package dev.projecteclipse.eclipse.entity;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.Level;

/**
 * Sunmote — the altar swarm wisp ({@code docs/ideas/04_content.md} §1.5). A tiny fullbright
 * two-cube spark orbiting the sanctum altar; {@link EclipseSpawner} maintains one per altar
 * level (radius {@code 6 + altarLevel}) and respawns killed motes at the next dawn.
 *
 * <p>The orbit is position-driven in {@link #tick()} (no physics, no gravity): angle
 * advances {@value #ORBIT_STEP} rad/tick around the persisted anchor with a slow sine bob.
 * Killable — drops one glowstone dust. Chimes softly every ~200 ticks.</p>
 */
public class SunmoteEntity extends Mob {
    /** Orbit angle advance per tick (spec: {@code angle += 0.02}). */
    public static final double ORBIT_STEP = 0.02D;

    private static final String TAG_ANCHOR = "orbitAnchor";
    private static final String TAG_ANGLE = "orbitAngle";

    @Nullable
    private BlockPos anchor;
    private double angle;

    public SunmoteEntity(EntityType<? extends SunmoteEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noPhysics = true;
        this.angle = this.random.nextDouble() * Math.PI * 2.0D;
    }

    /** Pins the orbit center + starting angle; called by the spawner right after creation. */
    public void setOrbit(BlockPos anchor, double startAngle) {
        this.anchor = anchor;
        this.angle = startAngle;
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()) {
            return;
        }
        if (this.anchor == null) {
            // Summoned ad hoc (e.g. /summon): orbit the sanctum altar if known, else the spawn point.
            BlockPos sanctum = this.level() instanceof ServerLevel serverLevel
                    ? EclipseWorldState.get(serverLevel.getServer()).getSanctumAltarPos()
                    : null;
            this.anchor = sanctum != null && sanctum.closerToCenterThan(this.position(), 48.0D)
                    ? sanctum : this.blockPosition();
        }
        int altarLevel = this.level() instanceof ServerLevel serverLevel
                ? EclipseWorldState.get(serverLevel.getServer()).getAltarLevel() : 0;
        double radius = 6.0D + altarLevel;
        this.angle += ORBIT_STEP;
        double x = this.anchor.getX() + 0.5D + Math.cos(this.angle) * radius;
        double z = this.anchor.getZ() + 0.5D + Math.sin(this.angle) * radius;
        double y = this.anchor.getY() + 1.5D + Mth.sin((float) (this.tickCount * 0.05F)) * 0.6D;
        this.setDeltaMovement(x - this.getX(), y - this.getY(), z - this.getZ());
        this.setPos(x, y, z);
    }

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        this.spawnAtLocation(new ItemStack(Items.GLOWSTONE_DUST));
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.AMETHYST_BLOCK_CHIME;
    }

    @Override
    public int getAmbientSoundInterval() {
        return 200;
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // Maintained by the spawner; never despawns on its own.
    }

    @Override
    public void addAdditionalSaveData(CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        if (this.anchor != null) {
            tag.put(TAG_ANCHOR, NbtUtils.writeBlockPos(this.anchor));
        }
        tag.putDouble(TAG_ANGLE, this.angle);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag tag) {
        super.readAdditionalSaveData(tag);
        NbtUtils.readBlockPos(tag, TAG_ANCHOR).ifPresent(pos -> this.anchor = pos);
        if (tag.contains(TAG_ANGLE)) {
            this.angle = tag.getDouble(TAG_ANGLE);
        }
    }
}
