package dev.projecteclipse.eclipse.progression.realtime;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Persistent anchor of the real-time day engine (R1), stored per save as
 * {@code data/eclipse_realtime.dat} in overworld storage. This generalizes the W14
 * one-shot {@code nextPhaseEpochMillis} pair into a re-arming schedule: after every
 * advance the next boundary is derived and persisted here, so a 14-day arc needs zero
 * re-scheduling and survives restarts/downtime (catch-up reads this anchor).
 *
 * <p>All times are UTC epoch millis. Only {@link RealtimeDayService} mutates this state;
 * everything else reads through the service/API.</p>
 */
public final class RealtimeState extends SavedData {
    public static final String DATA_NAME = "eclipse_realtime";

    private static final String TAG_ARMED = "armed";
    private static final String TAG_PAUSED = "paused";
    private static final String TAG_BOUNDARY = "boundaryEpochMillis";
    private static final String TAG_PREV_BOUNDARY = "prevBoundaryEpochMillis";
    private static final String TAG_PAUSE_REMAINING = "pauseRemainingMillis";
    private static final String TAG_LAST_ADVANCE_EPOCH_DAY = "lastAdvanceEpochDay";
    private static final String TAG_MANUAL_OVERRIDE = "manualOverride";
    private static final String TAG_ARMED_BY_SCHEDULE_ONLY = "armedBySchedule";
    private static final String TAG_AUTO_ARM_DONE = "autoArmDone";

    private boolean armed = false;
    private boolean paused = false;
    /** Next advance instant (epoch millis); {@code 0} while disarmed. */
    private long boundaryEpochMillis = 0L;
    /** Progress origin for the countdown bar / client spool (the previous boundary or arm instant). */
    private long prevBoundaryEpochMillis = 0L;
    /** Remaining millis frozen while paused; {@code 0} while running. */
    private long pauseRemainingMillis = 0L;
    /**
     * Zone-local epoch day of the last schedule-derived advance — the monotonic guard
     * against a backwards wall-clock jump (NTP) re-firing the same calendar slot.
     * {@code -1} = never advanced. Manual-override fires bypass the guard but still
     * stamp this (dev intent is explicit; the regular cadence stays deduped).
     */
    private long lastAdvanceEpochDay = -1L;
    /** A one-shot explicit boundary ({@code /eclipse schedule next} or {@code /eclipse-rt set|add}) is active. */
    private boolean manualOverride = false;
    /**
     * The engine was armed ONLY by a legacy one-shot schedule; {@code /eclipse schedule clear}
     * then disarms fully (verbatim W14 semantics) instead of reverting to the daily cadence.
     */
    private boolean armedByScheduleOnly = false;
    /** {@code autoArmOnStartEvent} already consumed (or superseded by an explicit arm/disarm). */
    private boolean autoArmDone = false;

    public RealtimeState() {}

    public static RealtimeState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(RealtimeState::new, RealtimeState::load));
    }

    public static RealtimeState load(CompoundTag tag, HolderLookup.Provider registries) {
        RealtimeState state = new RealtimeState();
        state.armed = tag.getBoolean(TAG_ARMED);
        state.paused = tag.getBoolean(TAG_PAUSED);
        state.boundaryEpochMillis = tag.getLong(TAG_BOUNDARY);
        state.prevBoundaryEpochMillis = tag.getLong(TAG_PREV_BOUNDARY);
        state.pauseRemainingMillis = tag.getLong(TAG_PAUSE_REMAINING);
        state.lastAdvanceEpochDay = tag.contains(TAG_LAST_ADVANCE_EPOCH_DAY)
                ? tag.getLong(TAG_LAST_ADVANCE_EPOCH_DAY) : -1L;
        state.manualOverride = tag.getBoolean(TAG_MANUAL_OVERRIDE);
        state.armedByScheduleOnly = tag.getBoolean(TAG_ARMED_BY_SCHEDULE_ONLY);
        state.autoArmDone = tag.getBoolean(TAG_AUTO_ARM_DONE);
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_ARMED, this.armed);
        tag.putBoolean(TAG_PAUSED, this.paused);
        tag.putLong(TAG_BOUNDARY, this.boundaryEpochMillis);
        tag.putLong(TAG_PREV_BOUNDARY, this.prevBoundaryEpochMillis);
        tag.putLong(TAG_PAUSE_REMAINING, this.pauseRemainingMillis);
        tag.putLong(TAG_LAST_ADVANCE_EPOCH_DAY, this.lastAdvanceEpochDay);
        tag.putBoolean(TAG_MANUAL_OVERRIDE, this.manualOverride);
        tag.putBoolean(TAG_ARMED_BY_SCHEDULE_ONLY, this.armedByScheduleOnly);
        tag.putBoolean(TAG_AUTO_ARM_DONE, this.autoArmDone);
        return tag;
    }

    public boolean isArmed() {
        return this.armed;
    }

    public void setArmed(boolean armed) {
        this.armed = armed;
        setDirty();
    }

    public boolean isPaused() {
        return this.paused;
    }

    public void setPaused(boolean paused) {
        this.paused = paused;
        setDirty();
    }

    public long getBoundaryEpochMillis() {
        return this.boundaryEpochMillis;
    }

    public void setBoundaryEpochMillis(long epochMillis) {
        this.boundaryEpochMillis = epochMillis;
        setDirty();
    }

    public long getPrevBoundaryEpochMillis() {
        return this.prevBoundaryEpochMillis;
    }

    public void setPrevBoundaryEpochMillis(long epochMillis) {
        this.prevBoundaryEpochMillis = epochMillis;
        setDirty();
    }

    public long getPauseRemainingMillis() {
        return this.pauseRemainingMillis;
    }

    public void setPauseRemainingMillis(long millis) {
        this.pauseRemainingMillis = millis;
        setDirty();
    }

    public long getLastAdvanceEpochDay() {
        return this.lastAdvanceEpochDay;
    }

    public void setLastAdvanceEpochDay(long epochDay) {
        this.lastAdvanceEpochDay = epochDay;
        setDirty();
    }

    public boolean isManualOverride() {
        return this.manualOverride;
    }

    public void setManualOverride(boolean manualOverride) {
        this.manualOverride = manualOverride;
        setDirty();
    }

    public boolean isArmedByScheduleOnly() {
        return this.armedByScheduleOnly;
    }

    public void setArmedByScheduleOnly(boolean armedByScheduleOnly) {
        this.armedByScheduleOnly = armedByScheduleOnly;
        setDirty();
    }

    public boolean isAutoArmDone() {
        return this.autoArmDone;
    }

    public void setAutoArmDone(boolean autoArmDone) {
        this.autoArmDone = autoArmDone;
        setDirty();
    }
}
