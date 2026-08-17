package de.sonic0810.goobymod.api;

import de.sonic0810.goobymod.entity.FriendshipTier;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyMood;
import java.util.UUID;
import javax.annotation.Nullable;
import net.minecraft.world.item.ItemStack;

/**
 * Stable, read-only view of a Gooby for addons.
 *
 * <p>This interface is frozen for the 5.x line. Addons should prefer it over
 * reaching into {@code GoobyEntity} implementation details.
 */
public interface GoobyAccessor {
    @Nullable
    UUID goobyOwnerId();

    int goobySatisfaction();

    GoobyMood goobyMood();

    GoobyCommand goobyCommand();

    FriendshipTier goobyFriendshipTier(UUID playerId);

    boolean goobyIsBaby();

    boolean goobyIsWild();

    ItemStack goobyHat();

    ItemStack goobyNeckAccessory();

    ItemStack goobyBackAccessory();
}
