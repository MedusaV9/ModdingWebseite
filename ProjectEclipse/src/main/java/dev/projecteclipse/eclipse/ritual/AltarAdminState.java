package dev.projecteclipse.eclipse.ritual;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * ALTARUI operator overrides for the altar, persisted per save
 * ({@code eclipse_altar_admin.dat}, overworld storage — {@link EclipseSavedData} pattern).
 * Toggled exclusively by the {@code /dev altar} tree ({@code devtools.dev.DevAltarCommands}):
 * <ul>
 *   <li><b>Progression lock</b> — while set, milestone deposits at the altar are refused
 *       ({@code AltarBlockEntity#handleMilestoneDeposit}) so the altar can never advance a
 *       stage mid-playtest. Banking shards, offerings, heart sacrifices and the shop stay
 *       untouched — only the LADDER freezes.</li>
 *   <li><b>Disabled shop offers</b> — offer ids ({@code economy.ShardEconomy.Offer#id})
 *       removed from sale. Disabled offers vanish from the browse cycle, the altar panel
 *       payload and the buy path entirely (never shown "greyed": an operator pulling an
 *       offer mid-event should not advertise that it exists).</li>
 * </ul>
 */
public final class AltarAdminState extends SavedData {
    public static final String DATA_NAME = "eclipse_altar_admin";

    private static final String TAG_PROGRESSION_LOCKED = "progressionLocked";
    private static final String TAG_DISABLED_OFFERS = "disabledOffers";

    private boolean progressionLocked = false;
    private final Set<String> disabledOffers = new LinkedHashSet<>();

    public AltarAdminState() {}

    public static AltarAdminState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(AltarAdminState::new, AltarAdminState::load));
    }

    public static AltarAdminState load(CompoundTag tag, HolderLookup.Provider registries) {
        AltarAdminState state = new AltarAdminState();
        state.progressionLocked = tag.getBoolean(TAG_PROGRESSION_LOCKED);
        for (Tag entry : tag.getList(TAG_DISABLED_OFFERS, Tag.TAG_STRING)) {
            state.disabledOffers.add(entry.getAsString());
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_PROGRESSION_LOCKED, this.progressionLocked);
        ListTag list = new ListTag();
        for (String offerId : this.disabledOffers) {
            list.add(StringTag.valueOf(offerId));
        }
        tag.put(TAG_DISABLED_OFFERS, list);
        return tag;
    }

    /** Whether the altar ladder is frozen ({@code /dev altar lock}). */
    public boolean isProgressionLocked() {
        return this.progressionLocked;
    }

    /** Sets the ladder freeze; returns whether anything changed. */
    public boolean setProgressionLocked(boolean locked) {
        if (this.progressionLocked == locked) {
            return false;
        }
        this.progressionLocked = locked;
        setDirty();
        return true;
    }

    /** Whether the given shop offer id is pulled from sale ({@code /dev altar offer disable}). */
    public boolean isOfferDisabled(String offerId) {
        return this.disabledOffers.contains(offerId);
    }

    /** Adds/removes an offer id from the disabled set; returns whether anything changed. */
    public boolean setOfferDisabled(String offerId, boolean disabled) {
        boolean changed = disabled ? this.disabledOffers.add(offerId) : this.disabledOffers.remove(offerId);
        if (changed) {
            setDirty();
        }
        return changed;
    }

    public Set<String> getDisabledOffers() {
        return Collections.unmodifiableSet(this.disabledOffers);
    }
}
