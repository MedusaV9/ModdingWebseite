package dev.projecteclipse.eclipse.economy;

import java.util.Optional;

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
 * Compass of the Watcher (spec §4, 8 shards): the needle points at the NEAREST OTHER
 * PLAYER. {@link #inventoryTick} writes that player's {@link GlobalPos} into the vanilla
 * {@code minecraft:lodestone_tracker} component every {@value #UPDATE_INTERVAL_TICKS}
 * ticks; the stack sync carries it to the client, where the vanilla-style {@code angle}
 * item property (registered in {@code client.EclipseClient}) turns it into a needle frame.
 * It NEVER says who it points at — paranoia is the product.
 *
 * <p>{@code tracked} is always {@code false} so vanilla's lodestone-POI validation
 * (which would clear a target without a lodestone block) never touches the component.
 * With no other player in the dimension the target is cleared and the needle spins.</p>
 */
public class WatcherCompassItem extends Item {
    private static final int UPDATE_INTERVAL_TICKS = 40;

    public WatcherCompassItem(Properties properties) {
        super(properties);
    }

    @Override
    public void inventoryTick(ItemStack stack, Level level, Entity entity, int slotId, boolean isSelected) {
        if (!(level instanceof ServerLevel serverLevel) || !(entity instanceof ServerPlayer holder)
                || serverLevel.getGameTime() % UPDATE_INTERVAL_TICKS != 0L) {
            return;
        }
        ServerPlayer nearest = null;
        double nearestDistanceSq = Double.MAX_VALUE;
        for (ServerPlayer candidate : serverLevel.players()) {
            if (candidate == holder || candidate.isSpectator()) {
                continue;
            }
            double distanceSq = candidate.distanceToSqr(holder);
            if (distanceSq < nearestDistanceSq) {
                nearestDistanceSq = distanceSq;
                nearest = candidate;
            }
        }
        Optional<GlobalPos> target = nearest == null
                ? Optional.empty()
                : Optional.of(GlobalPos.of(serverLevel.dimension(), nearest.blockPosition()));
        stack.set(DataComponents.LODESTONE_TRACKER, new LodestoneTracker(target, false));
    }
}
