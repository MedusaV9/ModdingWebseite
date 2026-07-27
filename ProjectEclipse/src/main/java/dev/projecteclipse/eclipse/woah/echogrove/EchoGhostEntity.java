package dev.projecteclipse.eclipse.woah.echogrove;

import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.Level;

/**
 * WOAH-05 scene-actor ghost (plan §3.1) — the {@code ghosts/LogoutGhostEntity}
 * chassis (no-AI, no-physics, no-gravity, invulnerable Mob) extended with the
 * scene player's synced fields: ACTION (keyframe verb), FADE (spawn/despawn
 * alpha window), CHILD (renderer scales 0.72) and GLOW (flood/finale boost).
 *
 * <p>Movement is server-driven: {@code EchoSceneService} samples the Catmull-Rom
 * keyframe curve every tick and calls {@code setPos}/{@code setYRot};
 * {@code LivingEntityRenderer} turns the position delta into limb swing exactly
 * as it does for real players. {@code SWING}/{@code THROW} keyframes additionally
 * trigger {@link #swing} (vanilla broadcasts the arm animation).</p>
 *
 * <p>{@link #shouldBeSaved()} is {@code false} (the SoulWispEntity law): actors
 * never leak onto disk — the scene player respawns them deterministically.</p>
 */
public class EchoGhostEntity extends Mob implements EchoActor {
    public static final String ENTITY_ID = "echo_ghost";

    public static final EntityDataAccessor<Byte> DATA_ACTION =
            SynchedEntityData.defineId(EchoGhostEntity.class, EntityDataSerializers.BYTE);
    public static final EntityDataAccessor<Integer> DATA_FADE =
            SynchedEntityData.defineId(EchoGhostEntity.class, EntityDataSerializers.INT);
    public static final EntityDataAccessor<Boolean> DATA_CHILD =
            SynchedEntityData.defineId(EchoGhostEntity.class, EntityDataSerializers.BOOLEAN);
    public static final EntityDataAccessor<Float> DATA_GLOW =
            SynchedEntityData.defineId(EchoGhostEntity.class, EntityDataSerializers.FLOAT);

    public EchoGhostEntity(EntityType<? extends EchoGhostEntity> type, Level level) {
        super(type, level);
        this.setNoAi(true);
        this.noPhysics = true;
        this.setNoGravity(true);
        this.setInvulnerable(true);
        this.setSilent(true);
    }

    public static AttributeSupplier.Builder createAttributes() {
        return Mob.createMobAttributes().add(Attributes.MAX_HEALTH, 1.0D);
    }

    @Override
    protected void registerGoals() {
        // No AI — the scene player is the only mover.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // LOD despawn is the scene player's job (fade, then discard).
    }

    /** Actors never persist — the scene player rebuilds them deterministically. */
    @Override
    public boolean shouldBeSaved() {
        return false;
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        return false; // A memory cannot be harmed.
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void doPush(net.minecraft.world.entity.Entity entity) {
        // Ghosts never shove the living.
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_ACTION, EchoActor.ACTION_IDLE);
        builder.define(DATA_FADE, 0);
        builder.define(DATA_CHILD, false);
        builder.define(DATA_GLOW, 0.0F);
    }

    @Override
    public void addAdditionalSaveData(CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        // Nothing feature-specific: shouldBeSaved()=false makes this dead code by design.
    }

    @Override
    public void readAdditionalSaveData(CompoundTag tag) {
        super.readAdditionalSaveData(tag);
    }

    // ------------------------------------------------------------------ EchoActor

    @Override
    public byte echoAction() {
        return this.entityData.get(DATA_ACTION);
    }

    @Override
    public void setEchoAction(byte action) {
        if (echoAction() != action) {
            this.entityData.set(DATA_ACTION, action);
        }
    }

    @Override
    public int echoFade() {
        return this.entityData.get(DATA_FADE);
    }

    @Override
    public void setEchoFade(int ticks) {
        this.entityData.set(DATA_FADE, Math.max(0, Math.min(EchoActor.FADE_TICKS, ticks)));
    }

    @Override
    public float echoGlow() {
        return this.entityData.get(DATA_GLOW);
    }

    @Override
    public void setEchoGlow(float glow) {
        this.entityData.set(DATA_GLOW, Math.max(0.0F, Math.min(1.0F, glow)));
    }

    public boolean isChildEcho() {
        return this.entityData.get(DATA_CHILD);
    }

    public void setChildEcho(boolean child) {
        this.entityData.set(DATA_CHILD, child);
    }
}
