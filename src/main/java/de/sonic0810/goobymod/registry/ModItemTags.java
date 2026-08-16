package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.ItemTags;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;

public final class ModItemTags {
    /** Datapacks may extend this tag to add wearable Gooby hats. */
    public static final TagKey<Item> GOOBY_HATS = ItemTags.create(
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "gooby_hats"));

    private ModItemTags() {
    }
}
