package dev.projecteclipse.eclipse.ghosts;

import java.util.Optional;
import java.util.UUID;

import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.Level;

/**
 * Logout ghost marker (R12). Frozen entity id {@value #ENTITY_ID} — P6-W12 owns the
 * translucent renderer; this class supplies invulnerable no-AI behavior and synched
 * {@link #DATA_REVEAL_TICKS}. {@link #ownerName} is server-side NBT only (never synched).
 */
public class LogoutGhostEntity extends Mob {
    /** Frozen registry path for P6-W12 renderer contract. */
    public static final String ENTITY_ID = "logout_ghost";

    public static final EntityDataAccessor<Optional<UUID>> DATA_OWNER_UUID =
            SynchedEntityData.defineId(LogoutGhostEntity.class, EntityDataSerializers.OPTIONAL_UUID);
    public static final EntityDataAccessor<Integer> DATA_REVEAL_TICKS =
            SynchedEntityData.defineId(LogoutGhostEntity.class, EntityDataSerializers.INT);

    private static final String TAG_OWNER = "Owner";
    private static final String TAG_OWNER_NAME = "OwnerName";
    private static final String TAG_REVEAL = "RevealTicks";

    /** Server-only display name; travels to clients ONLY via {@code S2CGhostRevealPayload}. */
    private String ownerName = "";

    public LogoutGhostEntity(EntityType<? extends LogoutGhostEntity> type, Level level) {
        super(type, level);
        this.setNoAi(true);
        this.noPhysics = true;
        this.setNoGravity(true);
        this.setInvulnerable(true);
    }

    public static AttributeSupplier.Builder createAttributes() {
        return Mob.createMobAttributes().add(Attributes.MAX_HEALTH, 1.0D);
    }

    @Override
    protected void registerGoals() {
        // No AI — marker only.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_OWNER_UUID, Optional.empty());
        builder.define(DATA_REVEAL_TICKS, 0);
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide()) {
            return;
        }
        int reveal = getRevealTicks();
        if (reveal > 0) {
            setRevealTicks(reveal - 1);
        }
        if (this.tickCount % 100 == 0 && !LogoutGhostService.isValid(this)) {
            this.discard();
        }
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (!this.level().isClientSide()) {
            Entity attacker = source.getEntity();
            LogoutGhostService.onGhostHurt(this, attacker);
        }
        return false;
    }

    @Override
    public void addAdditionalSaveData(CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        getOwnerUuid().ifPresent(uuid -> tag.putUUID(TAG_OWNER, uuid));
        tag.putString(TAG_OWNER_NAME, this.ownerName);
        tag.putInt(TAG_REVEAL, getRevealTicks());
    }

    @Override
    public void readAdditionalSaveData(CompoundTag tag) {
        super.readAdditionalSaveData(tag);
        if (tag.hasUUID(TAG_OWNER)) {
            setOwnerUuid(tag.getUUID(TAG_OWNER));
        }
        if (tag.contains(TAG_OWNER_NAME)) {
            this.ownerName = tag.getString(TAG_OWNER_NAME);
        }
        setRevealTicks(tag.getInt(TAG_REVEAL));
    }

    public Optional<UUID> getOwnerUuid() {
        return this.entityData.get(DATA_OWNER_UUID);
    }

    public void setOwnerUuid(UUID uuid) {
        this.entityData.set(DATA_OWNER_UUID, Optional.of(uuid));
    }

    public String getOwnerName() {
        return this.ownerName;
    }

    public void setOwnerName(String name) {
        this.ownerName = name != null ? name : "";
    }

    public int getRevealTicks() {
        return this.entityData.get(DATA_REVEAL_TICKS);
    }

    public void setRevealTicks(int ticks) {
        this.entityData.set(DATA_REVEAL_TICKS, Math.max(0, ticks));
    }

    /** Spawns a persistent ghost at the player's logout spot. Returns {@code null} when the type is unwired. */
    public static LogoutGhostEntity spawnAt(ServerLevel level, UUID ownerUuid, String ownerName,
            double x, double y, double z, float yRot) {
        if (!GhostEntities.LOGOUT_GHOST.isBound()) {
            return null;
        }
        LogoutGhostEntity ghost = new LogoutGhostEntity(GhostEntities.LOGOUT_GHOST.get(), level);
        ghost.setOwnerUuid(ownerUuid);
        ghost.setOwnerName(ownerName);
        ghost.setPos(x, y, z);
        ghost.setYRot(yRot);
        ghost.setYHeadRot(yRot);
        ghost.setPersistenceRequired();
        level.addFreshEntity(ghost);
        return ghost;
    }
}
