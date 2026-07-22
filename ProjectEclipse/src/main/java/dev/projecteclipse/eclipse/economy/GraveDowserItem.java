package dev.projecteclipse.eclipse.economy;

import java.util.Optional;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.GlobalPos;
import net.minecraft.core.component.DataComponents;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.component.LodestoneTracker;
import net.minecraft.world.level.Level;

/**
 * Grave Dowser (spec §4, 4 shards): same {@code lodestone_tracker} trick as
 * {@link WatcherCompassItem}, but the needle points at the holder's nearest OWN grave,
 * read from {@link EclipseWorldState#getGravePositions}. Same-dimension graves win;
 * with none in this dimension the needle spins (the vanilla compass property renders
 * cross-dimension targets as a random spin anyway).
 */
public class GraveDowserItem extends Item {
    private static final int UPDATE_INTERVAL_TICKS = 40;

    public GraveDowserItem(Properties properties) {
        super(properties);
    }

    @Override
    public void inventoryTick(ItemStack stack, Level level, Entity entity, int slotId, boolean isSelected) {
        if (!(level instanceof ServerLevel serverLevel) || !(entity instanceof ServerPlayer holder)
                || serverLevel.getGameTime() % UPDATE_INTERVAL_TICKS != 0L) {
            return;
        }
        GlobalPos nearest = null;
        double nearestDistanceSq = Double.MAX_VALUE;
        for (GlobalPos grave : EclipseWorldState.get(serverLevel.getServer()).getGravePositions(holder.getUUID())) {
            if (!grave.dimension().equals(serverLevel.dimension())) {
                continue;
            }
            double distanceSq = grave.pos().distToCenterSqr(holder.position());
            if (distanceSq < nearestDistanceSq) {
                nearestDistanceSq = distanceSq;
                nearest = grave;
            }
        }
        stack.set(DataComponents.LODESTONE_TRACKER, new LodestoneTracker(Optional.ofNullable(nearest), false));
    }
}
