package de.sonic0810.goobymod.entity;

import java.util.EnumMap;
import java.util.Locale;
import java.util.Map;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.component.DyedItemColor;

/**
 * Gooby's three wardrobe slots, in two cooperating representations.
 *
 * <p>The compact wire format ({@link #encode}/{@link #decode}) carries the
 * registry id plus an optional dye RGB (appended after {@code #}) through
 * entity sync. That is all the renderer needs and avoids a custom network
 * payload.</p>
 *
 * <p>A server-side instance of this class additionally keeps the FULL
 * {@link ItemStack} per slot — custom names, enchantments and arbitrary data
 * components — and persists it losslessly to NBT via {@link #save}/
 * {@link #load}. Legacy saves that only stored the wire strings are migrated
 * through {@link #reconcile}, which decodes the wire string into a base stack
 * whenever no matching full stack is known.</p>
 *
 * <p>Slot NBT that fails to parse (typically an accessory from a removed
 * third-party mod) is retained verbatim and re-emitted by {@link #save}, so a
 * world can be opened without the mod and the accessory reappears once the
 * mod is installed again. Equipping something else into such a slot discards
 * the retained tag, mirroring vanilla container semantics.</p>
 */
public final class GoobyWardrobe {
    public static final int DEFAULT_SCARF_COLOR = 0xB8325E;
    /** Ungefaerbtes Halstuch-Orange (Item-Tint-Default, analog Schal-Beere). */
    public static final int DEFAULT_BANDANA_COLOR = 0xC65D34;
    /**
     * Obergrenze fuer synchronisierte Wardrobe-/Sync-Strings. Zentrale
     * Wahrheit fuer Entity UND Event-Handler: ein Encode ueber dieser Grenze
     * wuerde beim Reload durch Truncation + {@link #reconcile} vernichtet,
     * deshalb lehnen alle Equip-/Dye-Pfade solche Stacks fail-closed ab.
     */
    public static final int MAX_SYNCED_KEY_LENGTH = 128;

    /** The three synchronized accessory slots and their NBT keys. */
    public enum Slot {
        HEAD("Head"),
        NECK("Neck"),
        BACK("Back");

        private final String tagKey;

        Slot(String tagKey) {
            this.tagKey = tagKey;
        }

        /** NBT-Schluessel des Slots innerhalb von {@code WardrobeItems}. */
        public String tagKey() {
            return this.tagKey;
        }
    }

    private final Map<Slot, ItemStack> stacks = new EnumMap<>(Slot.class);
    /** Raw slot NBT that failed to parse (missing mod); re-emitted by {@link #save}. */
    private final Map<Slot, CompoundTag> unresolved = new EnumMap<>(Slot.class);

    public GoobyWardrobe() {
        for (Slot slot : Slot.values()) {
            this.stacks.put(slot, ItemStack.EMPTY);
        }
    }

    public ItemStack get(Slot slot) {
        return this.stacks.get(slot);
    }

    public void set(Slot slot, ItemStack stack) {
        this.unresolved.remove(slot);
        this.stacks.put(slot, stack == null || stack.isEmpty() ? ItemStack.EMPTY : stack);
    }

    /**
     * Keeps the authoritative full stack consistent with the synced wire
     * string. A matching encoding keeps the richer stack (components survive);
     * any mismatch — direct wire setters, truncated sync values, legacy saves
     * without full-stack NBT — re-derives the slot from the wire string so a
     * stale full stack can never resurrect or dupe items.
     */
    public void reconcile(Slot slot, String syncedValue) {
        String encoded = syncedValue == null ? "" : syncedValue;
        if (!encode(get(slot)).equals(encoded)) {
            set(slot, decode(encoded));
        }
    }

    /**
     * Full-fidelity NBT: each occupied slot saves its complete stack; slots
     * whose NBT could not be parsed at load time re-emit the preserved tag.
     */
    public CompoundTag save(HolderLookup.Provider registries) {
        CompoundTag tag = new CompoundTag();
        for (Slot slot : Slot.values()) {
            ItemStack stack = get(slot);
            if (!stack.isEmpty()) {
                tag.put(slot.tagKey(), stack.save(registries));
            } else {
                CompoundTag preserved = this.unresolved.get(slot);
                if (preserved != null) {
                    tag.put(slot.tagKey(), preserved.copy());
                }
            }
        }
        return tag;
    }

    public void load(CompoundTag tag, HolderLookup.Provider registries) {
        for (Slot slot : Slot.values()) {
            if (!tag.contains(slot.tagKey(), Tag.TAG_COMPOUND)) {
                set(slot, ItemStack.EMPTY);
                continue;
            }
            CompoundTag stackTag = tag.getCompound(slot.tagKey());
            ItemStack parsed = ItemStack.parse(registries, stackTag).orElse(ItemStack.EMPTY);
            set(slot, parsed);
            if (parsed.isEmpty()) {
                // Fremd-Mod entfernt: rohes NBT konservieren statt vernichten.
                this.unresolved.put(slot, stackTag.copy());
            }
        }
    }

    public static String encode(ItemStack stack) {
        if (stack == null || stack.isEmpty()) {
            return "";
        }
        String id = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        DyedItemColor color = stack.get(DataComponents.DYED_COLOR);
        return color == null ? id : id + "#" + String.format(Locale.ROOT, "%06x", color.rgb() & 0xFFFFFF);
    }

    public static ItemStack decode(String encoded) {
        if (encoded == null || encoded.isEmpty()) {
            return ItemStack.EMPTY;
        }
        int colorSeparator = encoded.lastIndexOf('#');
        String itemId = colorSeparator < 0 ? encoded : encoded.substring(0, colorSeparator);
        ResourceLocation location = ResourceLocation.tryParse(itemId);
        ItemStack stack = location == null ? ItemStack.EMPTY
                : BuiltInRegistries.ITEM.getOptional(location).map(ItemStack::new).orElse(ItemStack.EMPTY);
        if (!stack.isEmpty() && colorSeparator >= 0) {
            try {
                int color = Integer.parseUnsignedInt(encoded.substring(colorSeparator + 1), 16) & 0xFFFFFF;
                stack.set(DataComponents.DYED_COLOR, new DyedItemColor(color, true));
            } catch (NumberFormatException ignored) {
                // A malformed datapack/save color still resolves to the usable base item.
            }
        }
        return stack;
    }

    public static int color(ItemStack stack) {
        return DyedItemColor.getOrDefault(stack, DEFAULT_SCARF_COLOR);
    }
}
