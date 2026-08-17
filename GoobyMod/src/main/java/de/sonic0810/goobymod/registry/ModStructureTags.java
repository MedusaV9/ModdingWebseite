package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.level.levelgen.structure.Structure;

public final class ModStructureTags {
    public static final TagKey<Structure> GOOBY_TREASURE_CACHES = TagKey.create(
            Registries.STRUCTURE,
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "gooby_treasure_caches"));

    private ModStructureTags() {
    }
}
