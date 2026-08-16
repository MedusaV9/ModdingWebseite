package de.sonic0810.goobymod.block.entity;

import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModBlockEntities;
import java.util.UUID;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Persistent owner lease for a placed Nutella jar.
 *
 * <p>The UUID is deliberately stored on the jar rather than inferred from a
 * local entity scan. A claiming Gooby may be outside the jar chunk (or its
 * chunk may be unloaded) without making the jar look unclaimed.
 */
public final class NutellaJarBlockEntity extends BlockEntity {
    public static final long LEASE_TICKS = 20L * 60L * 15L;

    @Nullable
    private UUID claimingGooby;
    private long leaseExpiry;

    public NutellaJarBlockEntity(BlockPos pos, BlockState state) {
        super(ModBlockEntities.NUTELLA_JAR.get(), pos, state);
    }

    public void claim(UUID goobyId, long now) {
        this.claimingGooby = goobyId;
        this.leaseExpiry = now + LEASE_TICKS;
        setChanged();
    }

    /**
     * Gives a legacy {@code claimed=true} block a conservative grace period.
     * Older worlds had no UUID to migrate, so releasing immediately would
     * reintroduce the chunk-unload double-spawn bug.
     */
    public void ensureLegacyLease(long now) {
        if (this.leaseExpiry <= 0L) {
            this.leaseExpiry = now + LEASE_TICKS;
            setChanged();
        }
    }

    public boolean isExpired(long now) {
        return this.leaseExpiry > 0L && now >= this.leaseExpiry;
    }

    /**
     * Returns true only when an expired lease can safely be released.
     * Loaded entities are looked up by UUID across every server level.
     */
    public boolean mayRelease(ServerLevel level, long now) {
        if (!isExpired(now)) {
            return false;
        }
        Entity claimant = findEntityAcrossServer(level, this.claimingGooby);
        if (claimant instanceof GoobyEntity gooby
                && !gooby.isRemoved()
                && getBlockPos().equals(gooby.getJarTarget())) {
            this.leaseExpiry = now + LEASE_TICKS;
            setChanged();
            return false;
        }
        return true;
    }

    public void clearLease() {
        this.claimingGooby = null;
        this.leaseExpiry = 0L;
        setChanged();
    }

    @Nullable
    public UUID getClaimingGooby() {
        return this.claimingGooby;
    }

    public long getLeaseExpiry() {
        return this.leaseExpiry;
    }

    /** Public for deterministic lease-expiry regression tests. */
    public void setLeaseExpiry(long leaseExpiry) {
        this.leaseExpiry = leaseExpiry;
        setChanged();
    }

    @Nullable
    private static Entity findEntityAcrossServer(ServerLevel origin, @Nullable UUID entityId) {
        if (entityId == null) {
            return null;
        }
        for (ServerLevel level : origin.getServer().getAllLevels()) {
            Entity entity = level.getEntity(entityId);
            if (entity != null) {
                return entity;
            }
        }
        return null;
    }

    @Override
    protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.saveAdditional(tag, registries);
        if (this.claimingGooby != null) {
            tag.putUUID("ClaimingGooby", this.claimingGooby);
        }
        tag.putLong("LeaseExpiry", this.leaseExpiry);
    }

    @Override
    protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.loadAdditional(tag, registries);
        this.claimingGooby = tag.hasUUID("ClaimingGooby") ? tag.getUUID("ClaimingGooby") : null;
        this.leaseExpiry = tag.getLong("LeaseExpiry");
    }
}
