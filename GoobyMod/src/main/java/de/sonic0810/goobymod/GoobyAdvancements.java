package de.sonic0810.goobymod;

import net.minecraft.advancements.AdvancementHolder;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;

/**
 * Code-vergebene Advancements (Kriterium "granted" mit impossible-Trigger).
 * "tame_gooby" laeuft NICHT hierueber, sondern ueber den echten Vanilla-Trigger
 * minecraft:tame_animal (TamableAnimal#tame feuert ihn).
 */
public final class GoobyAdvancements {
    public static final String ROOT = "root";
    public static final String BEST_FRIENDS = "best_friends";
    public static final String WHISTLE_COMMAND = "whistle_command";
    public static final String GOOBY_RIDE = "gooby_ride";
    public static final String GIFT_RECEIVED = "gift_received";
    public static final String HAT_FASHION = "hat_fashion";
    public static final String SNUGGLE_TIME = "snuggle_time";
    public static final String FIRST_TRICK = "first_trick";
    public static final String ALL_TRICKS_MASTERED = "all_tricks_mastered";
    public static final String GOOBY_FAMILY = "gooby_family";
    public static final String FULL_OUTFIT = "full_outfit";
    public static final String EXPLORER_OUTFIT = "explorer_outfit";
    public static final String FOUND_BURROW = "found_burrow";
    public static final String GROUP_NAP = "group_nap";
    public static final String TREASURE_MAP_COMPLETE = "treasure_map_complete";
    public static final String SATCHEL_FULL = "satchel_full";
    public static final String FIRST_FETCH = "first_fetch";

    public static void grant(ServerPlayer player, String path) {
        AdvancementHolder holder = player.server.getAdvancements()
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, path));
        if (holder != null) {
            player.getAdvancements().award(holder, "granted");
        }
    }

    private GoobyAdvancements() {
    }
}
