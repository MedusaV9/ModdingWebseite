package dev.projecteclipse.eclipse.woah.echogrove;

import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.animal.Wolf;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;

/**
 * WOAH-05 — the dog of the {@code dog_fetch} scene (plan §3.3 no. 4).
 *
 * <p>Extends {@link Wolf} (NOT Mob): {@code WolfModel} is generically bound to
 * {@code T extends Wolf}, so riding the vanilla model+animations requires the
 * vanilla class. Everything live about a wolf is disarmed in the constructor —
 * no AI, no physics, no gravity, invulnerable, silent — and every vanilla
 * interaction (taming, feeding, sitting, breeding) is overridden away. The wolf
 * variant system is irrelevant: {@code EchoGhostWolfRenderer} forces its own
 * pale texture.</p>
 *
 * <p>Scene movement comes from {@code EchoSceneService} via {@code setPos}
 * (limb swing falls out of the position delta, tail/head idle animation is
 * driven by {@code WolfModel} itself and not gated on AI).</p>
 */
public class EchoGhostWolfEntity extends Wolf implements EchoActor {
    public static final String ENTITY_ID = "echo_ghost_wolf";

    public static final EntityDataAccessor<Byte> DATA_ACTION =
            SynchedEntityData.defineId(EchoGhostWolfEntity.class, EntityDataSerializers.BYTE);
    public static final EntityDataAccessor<Integer> DATA_FADE =
            SynchedEntityData.defineId(EchoGhostWolfEntity.class, EntityDataSerializers.INT);
    public static final EntityDataAccessor<Float> DATA_GLOW =
            SynchedEntityData.defineId(EchoGhostWolfEntity.class, EntityDataSerializers.FLOAT);

    public EchoGhostWolfEntity(EntityType<? extends EchoGhostWolfEntity> type, Level level) {
        super(type, level);
        this.setNoAi(true);
        this.noPhysics = true;
        this.setNoGravity(true);
        this.setInvulnerable(true);
        this.setSilent(true);
    }

    public static AttributeSupplier.Builder createEchoAttributes() {
        return Wolf.createAttributes();
    }

    @Override
    protected void registerGoals() {
        // No AI — the scene player is the only mover.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    public boolean shouldBeSaved() {
        return false;
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        return false;
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    /** No taming, no feeding, no sit-toggle — the memory does not notice you. */
    @Override
    public InteractionResult mobInteract(Player player, InteractionHand hand) {
        return InteractionResult.PASS;
    }

    @Override
    public boolean isFood(ItemStack stack) {
        return false;
    }

    @Override
    public boolean canMate(net.minecraft.world.entity.animal.Animal other) {
        return false;
    }

    /**
     * {@code WolfModel} keys its sitting pose off this — mapping it onto the scene
     * ACTION means SIT keyframes pose the dog without touching the tame/sit flags.
     */
    @Override
    public boolean isInSittingPose() {
        return echoAction() == EchoActor.ACTION_SIT;
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_ACTION, EchoActor.ACTION_IDLE);
        builder.define(DATA_FADE, 0);
        builder.define(DATA_GLOW, 0.0F);
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
}
