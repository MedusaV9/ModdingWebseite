package dev.projecteclipse.eclipse.woah.gravityrift;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * WOAH-02 persistence (plan §3.1): own tiny SavedData in overworld storage
 * ({@code data/eclipse_gravity_rift.dat}) — the {@code ChronoStasisData} /
 * {@code WizardObservatory.ObservatoryVersionData} ownership law (own file instead of a
 * field on a shared schema).
 *
 * <p>Deliberately NO persisted pulse timer: pulse beats live on the absolute raster
 * {@code gameTime % PULSE_PERIOD == phaseOffset(anchor)} (stateless-push law), so the
 * server beat, the display pose function and the client FX are synchronous by
 * construction and restart-safe.</p>
 */
public final class GravityRiftState extends SavedData {
    static final String DATA_NAME = "eclipse_gravity_rift";

    public static final int VERSION_NONE = 0;
    /** The current crater + islands build. Bump to force a re-carve on old saves. */
    public static final int VERSION_V1 = 1;

    private int builtVersion = VERSION_NONE;
    /** Resolved crater-floor center (surfaceY − MAX_DEPTH at the landmark). */
    @Nullable
    private BlockPos anchor;
    /** Game time the current inversion ends (0 = none active). */
    private long invertUntilGameTime;
    /** Game time the last inversion STARTED (cooldown base). */
    private long lastInvertGameTime;
    private boolean lootChestPlaced;

    public GravityRiftState() {}

    static GravityRiftState load(CompoundTag tag, HolderLookup.Provider registries) {
        GravityRiftState state = new GravityRiftState();
        state.builtVersion = tag.getInt("builtVersion");
        if (tag.contains("anchor")) {
            state.anchor = BlockPos.of(tag.getLong("anchor"));
        }
        state.invertUntilGameTime = tag.getLong("invertUntil");
        state.lastInvertGameTime = tag.getLong("lastInvert");
        state.lootChestPlaced = tag.getBoolean("lootChestPlaced");
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putInt("builtVersion", this.builtVersion);
        if (this.anchor != null) {
            tag.putLong("anchor", this.anchor.asLong());
        }
        tag.putLong("invertUntil", this.invertUntilGameTime);
        tag.putLong("lastInvert", this.lastInvertGameTime);
        tag.putBoolean("lootChestPlaced", this.lootChestPlaced);
        return tag;
    }

    public static GravityRiftState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(GravityRiftState::new, GravityRiftState::load));
    }

    public boolean built() {
        return this.builtVersion >= VERSION_V1 && this.anchor != null;
    }

    public int builtVersion() {
        return this.builtVersion;
    }

    public void setBuiltVersion(int version) {
        if (this.builtVersion != version) {
            this.builtVersion = version;
            setDirty();
        }
    }

    @Nullable
    public BlockPos anchor() {
        return this.anchor;
    }

    public void setAnchor(@Nullable BlockPos anchor) {
        if (!java.util.Objects.equals(this.anchor, anchor)) {
            this.anchor = anchor;
            setDirty();
        }
    }

    public long invertUntilGameTime() {
        return this.invertUntilGameTime;
    }

    public void setInvertUntilGameTime(long gameTime) {
        if (this.invertUntilGameTime != gameTime) {
            this.invertUntilGameTime = gameTime;
            setDirty();
        }
    }

    public long lastInvertGameTime() {
        return this.lastInvertGameTime;
    }

    public void setLastInvertGameTime(long gameTime) {
        if (this.lastInvertGameTime != gameTime) {
            this.lastInvertGameTime = gameTime;
            setDirty();
        }
    }

    public boolean lootChestPlaced() {
        return this.lootChestPlaced;
    }

    public void setLootChestPlaced(boolean placed) {
        if (this.lootChestPlaced != placed) {
            this.lootChestPlaced = placed;
            setDirty();
        }
    }
}
