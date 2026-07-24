package dev.projecteclipse.eclipse.entity.wizard;

import java.util.HashSet;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Wizard family SavedData ({@code data/eclipse_wizard.dat} in the OVERWORLD data storage
 * — deliberately its own file, NOT a new field on the cross-planner shared
 * {@code EclipseWorldState}; same §2.5 rule the ghost ship's {@code ShipVersionData}
 * follows). One instance carries:
 *
 * <ul>
 *   <li>{@link #isEnabled()} — the {@code /dev wizard enable|disable} switch. Disabling
 *       despawns Orin and blocks the respawn service; the observatory stays.</li>
 *   <li>{@link #hasCatalyst(UUID)} — the once-per-player fetch-quest ledger (IDEA-19
 *       §3 "one-catalyst-per-player quest flag"). Recorded BEFORE the item is handed
 *       over, so a mid-hand-over crash can never dupe a catalyst.</li>
 *   <li>{@link #wizardUuid()} — the live Orin entity, so restarts re-attach instead of
 *       stacking a second hermit (Deckhand bug-4a lesson).</li>
 *   <li>{@link #homePos()} — Orin's spawn point inside the observatory (stamped by
 *       {@code WizardObservatory} when the build completes).</li>
 *   <li>{@link #lastDeathDay()} — the overworld day Orin last died; the respawn
 *       service waits for the NEXT day ("respawns next day at his hut").</li>
 * </ul>
 */
public final class WizardData extends SavedData {
    public static final String DATA_NAME = "eclipse_wizard";

    private static final String TAG_ENABLED = "enabled";
    private static final String TAG_GRANTED = "catalystGranted";
    private static final String TAG_WIZARD = "wizardUuid";
    private static final String TAG_HOME = "homePos";
    private static final String TAG_DEATH_DAY = "lastDeathDay";

    private boolean enabled = true;
    private final Set<UUID> catalystGranted = new HashSet<>();
    @Nullable
    private UUID wizardUuid;
    @Nullable
    private BlockPos homePos;
    private long lastDeathDay = -1L;

    public WizardData() {}

    /** The wizard data of the given server's OVERWORLD (single instance per save). */
    public static WizardData get(ServerLevel overworld) {
        return overworld.getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(WizardData::new, WizardData::load), DATA_NAME);
    }

    public static WizardData load(CompoundTag tag, HolderLookup.Provider registries) {
        WizardData data = new WizardData();
        data.enabled = !tag.contains(TAG_ENABLED) || tag.getBoolean(TAG_ENABLED);
        for (Tag entry : tag.getList(TAG_GRANTED, Tag.TAG_INT_ARRAY)) {
            data.catalystGranted.add(NbtUtils.loadUUID(entry));
        }
        if (tag.hasUUID(TAG_WIZARD)) {
            data.wizardUuid = tag.getUUID(TAG_WIZARD);
        }
        if (tag.contains(TAG_HOME)) {
            data.homePos = BlockPos.of(tag.getLong(TAG_HOME));
        }
        data.lastDeathDay = tag.contains(TAG_DEATH_DAY) ? tag.getLong(TAG_DEATH_DAY) : -1L;
        return data;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_ENABLED, this.enabled);
        ListTag granted = new ListTag();
        for (UUID id : this.catalystGranted) {
            granted.add(NbtUtils.createUUID(id));
        }
        tag.put(TAG_GRANTED, granted);
        if (this.wizardUuid != null) {
            tag.putUUID(TAG_WIZARD, this.wizardUuid);
        }
        if (this.homePos != null) {
            tag.putLong(TAG_HOME, this.homePos.asLong());
        }
        tag.putLong(TAG_DEATH_DAY, this.lastDeathDay);
        return tag;
    }

    // --- enable/disable ---

    public boolean isEnabled() {
        return this.enabled;
    }

    public void setEnabled(boolean enabled) {
        if (this.enabled != enabled) {
            this.enabled = enabled;
            setDirty();
        }
    }

    // --- once-per-player catalyst ledger ---

    public boolean hasCatalyst(UUID player) {
        return this.catalystGranted.contains(player);
    }

    /** Records a grant; returns false (no-op) if the player was already granted. */
    public boolean grantCatalyst(UUID player) {
        if (!this.catalystGranted.add(player)) {
            return false;
        }
        setDirty();
        return true;
    }

    /** {@code /dev wizard resetquest} — forgets a player's grant so they may re-earn. */
    public boolean resetCatalyst(UUID player) {
        if (!this.catalystGranted.remove(player)) {
            return false;
        }
        setDirty();
        return true;
    }

    // --- live entity + home bookkeeping ---

    @Nullable
    public UUID wizardUuid() {
        return this.wizardUuid;
    }

    public void setWizardUuid(@Nullable UUID uuid) {
        if (!Objects.equals(this.wizardUuid, uuid)) {
            this.wizardUuid = uuid;
            setDirty();
        }
    }

    @Nullable
    public BlockPos homePos() {
        return this.homePos;
    }

    public void setHomePos(@Nullable BlockPos pos) {
        if (!Objects.equals(this.homePos, pos)) {
            this.homePos = pos;
            setDirty();
        }
    }

    public long lastDeathDay() {
        return this.lastDeathDay;
    }

    public void setLastDeathDay(long day) {
        if (this.lastDeathDay != day) {
            this.lastDeathDay = day;
            setDirty();
        }
    }
}
