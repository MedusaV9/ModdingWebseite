package dev.projecteclipse.eclipse.admin;

import java.util.Locale;

import javax.annotation.Nullable;

/**
 * Player actions the W4-TOGGLES dev suite can enable/disable globally and per player
 * ({@link ActionTogglesService}). Chat is deliberately absent — it is already sealed
 * server-wide by {@code anonymity/ChatBlocker}.
 */
public enum ToggleAction {
    /** Block placement ({@code BlockEvent.EntityPlaceEvent}). */
    BUILD,
    /** Block breaking ({@code BlockEvent.BreakEvent}). */
    MINE,
    /** Crafting results (RecipeGate-style {@code ItemCraftedEvent} strip). */
    CRAFT,
    /** Player-vs-player combat (melee + projectile/indirect). */
    PVP,
    /** Movement ({@code FreezeService} move-lock). */
    MOVE,
    /** Right-click use (block, item, entity). */
    INTERACT,
    /** Dropping items ({@code ItemTossEvent}). */
    DROP,
    /** Picking up items ({@code ItemEntityPickupEvent.Pre}). */
    PICKUP;

    /** Stable lowercase id used in commands, NBT and lang keys. */
    public String id() {
        return name().toLowerCase(Locale.ROOT);
    }

    /** Bit for {@link ActionTogglesService}'s lock-free active-restrictions mask. */
    public long bit() {
        return 1L << ordinal();
    }

    /** Action-bar deny hint lang key: {@code message.eclipse.toggle.<id>}. */
    public String denyMessageKey() {
        return "message.eclipse.toggle." + id();
    }

    @Nullable
    public static ToggleAction byId(String id) {
        for (ToggleAction action : values()) {
            if (action.id().equals(id)) {
                return action;
            }
        }
        return null;
    }
}
