package dev.projecteclipse.eclipse.lives;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.registry.EclipseBlockEntities;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Containers;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Stores a dead player's drops, the owner UUID and the creation game time.
 * The owner may loot anytime; other players only after {@code graveGraceMinutes}
 * (see {@link EclipseConfig#graveGraceMinutes()}); after 3x the grace period the
 * grave scatters its contents into the world and removes itself.
 */
public class GraveBlockEntity extends BlockEntity {
    private static final String TAG_ITEMS = "items";
    private static final String TAG_OWNER = "owner";
    private static final String TAG_CREATED = "created_game_time";

    private final List<ItemStack> items = new ArrayList<>();
    private UUID ownerUuid;
    private long createdGameTime;

    public GraveBlockEntity(BlockPos pos, BlockState state) {
        super(EclipseBlockEntities.GRAVE.get(), pos, state);
    }

    /** Sets the stored drops (copied), owner and creation game time. Call right after placing the grave. */
    public void initialize(UUID ownerUuid, long createdGameTime, List<ItemStack> drops) {
        this.items.clear();
        for (ItemStack stack : drops) {
            if (stack != null && !stack.isEmpty()) {
                this.items.add(stack.copy());
            }
        }
        this.ownerUuid = ownerUuid;
        this.createdGameTime = createdGameTime;
        setChanged();
    }

    /** The UUID of the player this grave belongs to; may be {@code null} for legacy/badly-initialized graves. */
    public UUID getOwnerUuid() {
        return ownerUuid;
    }

    /** Game time ({@code level.getGameTime()}) at which the grave was created. */
    public long getCreatedGameTime() {
        return createdGameTime;
    }

    /** Unmodifiable view of the stored drops. */
    public List<ItemStack> getStoredItems() {
        return Collections.unmodifiableList(items);
    }

    /** Whether the given player owns this grave. Graves without an owner are open to everyone. */
    public boolean isOwner(Player player) {
        return player != null && (ownerUuid == null || ownerUuid.equals(player.getUUID()));
    }

    /** Whether the grace period (1x {@code graveGraceMinutes}) has elapsed, opening the grave to everyone. */
    public boolean isGraceElapsed() {
        return level != null && level.getGameTime() - createdGameTime >= graceTicks();
    }

    /** Whether the given player may open this grave now (owner anytime, others after the grace period). */
    public boolean canOpen(Player player) {
        return isOwner(player) || isGraceElapsed();
    }

    /** Removes and returns all stored drops (leaves the block in place; callers decide its fate). */
    public List<ItemStack> removeAllItems() {
        List<ItemStack> removed = new ArrayList<>(items);
        items.clear();
        setChanged();
        return removed;
    }

    /** Gives all stored drops to the player (overflow drops at their feet) and removes the grave block. */
    public void giveTo(ServerPlayer player) {
        if (player == null || level == null) {
            return;
        }
        for (ItemStack stack : removeAllItems()) {
            if (!player.getInventory().add(stack) && !stack.isEmpty()) {
                player.drop(stack, false);
            }
        }
        level.removeBlock(worldPosition, false);
    }

    /** Scatters all stored drops into the world and removes the grave block. */
    public void scatter() {
        if (level == null) {
            return;
        }
        for (ItemStack stack : removeAllItems()) {
            Containers.dropItemStack(level, worldPosition.getX() + 0.5D, worldPosition.getY() + 0.5D,
                    worldPosition.getZ() + 0.5D, stack);
        }
        level.removeBlock(worldPosition, false);
    }

    /** Server tick: scatters and self-removes once 3x the grace period has passed. */
    public static void serverTick(Level level, BlockPos pos, BlockState state, GraveBlockEntity grave) {
        // Cheap check, but no need to evaluate it more than once a second.
        if (level.getGameTime() % 20L != 0L) {
            return;
        }
        if (level.getGameTime() - grave.createdGameTime >= 3L * graceTicks()) {
            grave.scatter();
        }
    }

    private static long graceTicks() {
        return EclipseConfig.graveGraceMinutes() * 60L * 20L;
    }

    @Override
    protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.saveAdditional(tag, registries);
        ListTag list = new ListTag();
        for (ItemStack stack : items) {
            if (!stack.isEmpty()) {
                list.add(stack.save(registries));
            }
        }
        tag.put(TAG_ITEMS, list);
        if (ownerUuid != null) {
            tag.putUUID(TAG_OWNER, ownerUuid);
        }
        tag.putLong(TAG_CREATED, createdGameTime);
    }

    @Override
    protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.loadAdditional(tag, registries);
        items.clear();
        for (Tag element : tag.getList(TAG_ITEMS, Tag.TAG_COMPOUND)) {
            ItemStack stack = ItemStack.parseOptional(registries, (CompoundTag) element);
            if (!stack.isEmpty()) {
                items.add(stack);
            }
        }
        ownerUuid = tag.hasUUID(TAG_OWNER) ? tag.getUUID(TAG_OWNER) : null;
        createdGameTime = tag.getLong(TAG_CREATED);
    }
}
