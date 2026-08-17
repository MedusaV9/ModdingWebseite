package de.sonic0810.goobymod.entity;

import de.sonic0810.goobymod.block.GoobyCouchBlock;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModEntities;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityDimensions;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * Unsichtbarer, nicht persistierter Sitz-Marker fuer die Gooby-Woll-Couch.
 * Der Spieler reitet dieses Entity; sobald niemand mehr sitzt oder die Couch
 * verschwindet, raeumt sich der Sitz im naechsten Tick selbst ab. Bewusst
 * {@code noSave}/{@code noSummon}: nach einem Weltreload steht der Spieler
 * einfach auf — es bleiben nie verwaiste Marker in der Welt zurueck.
 */
public class CouchSeatEntity extends Entity {
    public CouchSeatEntity(EntityType<? extends CouchSeatEntity> type, Level level) {
        super(type, level);
        this.noPhysics = true;
    }

    /**
     * Serverautoritativer Hinsetz-Pfad: prueft Couch + Belegung atomar im
     * Server-Thread und spawnt genau EINEN Sitz. Rueckgabe {@code false},
     * wenn die Couch fehlt, schon besetzt ist oder das Aufsitzen scheitert.
     */
    public static boolean seatPlayer(ServerLevel level, BlockPos couchPos, Player player) {
        BlockState state = level.getBlockState(couchPos);
        if (!state.is(ModBlocks.GOOBY_COUCH.get()) || isSeatOccupied(level, couchPos)) {
            return false;
        }
        CouchSeatEntity seat = ModEntities.COUCH_SEAT.get().create(level);
        if (seat == null) {
            return false;
        }
        Direction facing = state.getValue(HorizontalDirectionalBlock.FACING);
        Vec3 anchor = GoobyCouchBlock.seatAnchor(couchPos);
        seat.moveTo(anchor.x, anchor.y, anchor.z, facing.toYRot(), 0.0F);
        if (!level.addFreshEntity(seat)) {
            return false;
        }
        if (!player.startRiding(seat, true)) {
            seat.discard();
            return false;
        }
        return true;
    }

    /** Sitzt bereits jemand auf der Couch an dieser Position? */
    public static boolean isSeatOccupied(Level level, BlockPos couchPos) {
        return !level.getEntitiesOfClass(CouchSeatEntity.class, new AABB(couchPos),
                Entity::isVehicle).isEmpty();
    }

    @Override
    public void tick() {
        super.tick();
        if (!level().isClientSide
                && (!isVehicle() || !level().getBlockState(blockPosition()).is(ModBlocks.GOOBY_COUCH.get()))) {
            ejectPassengers();
            discard();
        }
    }

    @Override
    protected Vec3 getPassengerAttachmentPoint(Entity entity, EntityDimensions dimensions, float partialTick) {
        return new Vec3(0.0, 0.24, 0.0);
    }

    /** Absteigen: bevorzugt vor die Couch-Front, sonst sicher oben auf das Kissen. */
    @Override
    public Vec3 getDismountLocationForPassenger(LivingEntity passenger) {
        BlockState state = level().getBlockState(blockPosition());
        if (state.is(ModBlocks.GOOBY_COUCH.get())) {
            Direction facing = state.getValue(HorizontalDirectionalBlock.FACING);
            BlockPos front = blockPosition().relative(facing);
            if (level().getBlockState(front).getCollisionShape(level(), front).isEmpty()) {
                return Vec3.atBottomCenterOf(front);
            }
        }
        return Vec3.atBottomCenterOf(blockPosition()).add(0.0, GoobyCouchBlock.CUSHION_TOP, 0.0);
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
    }

    @Override
    protected void readAdditionalSaveData(CompoundTag tag) {
    }

    @Override
    protected void addAdditionalSaveData(CompoundTag tag) {
    }
}
