package de.sonic0810.goobymod.entity;

import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.resources.ResourceLocation;

/** Permanent, owner-unlocked coat appearances. */
public enum GoobyCoatVariant {
    CLASSIC("classic", "gooby.png"),
    CREAM("cream", "gooby_cream.png"),
    COCOA("cocoa", "gooby_cocoa.png"),
    SPOTTED("spotted", "gooby_spotted.png");

    private final String serializedName;
    private final ResourceLocation texture;

    GoobyCoatVariant(String serializedName, String textureFile) {
        this.serializedName = serializedName;
        this.texture = ResourceLocation.fromNamespaceAndPath(
                GoobyMod.MODID, "textures/entity/" + textureFile);
    }

    public String serializedName() {
        return this.serializedName;
    }

    public String translationKey() {
        return "coat.goobymod." + this.serializedName;
    }

    public ResourceLocation texture() {
        return this.texture;
    }

    public int unlockBit() {
        return 1 << ordinal();
    }

    public static GoobyCoatVariant byId(int id) {
        GoobyCoatVariant[] values = values();
        return id >= 0 && id < values.length ? values[id] : CLASSIC;
    }
}
