package dev.projecteclipse.eclipse.contracts;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save contract state ({@code data/eclipse_contracts.dat}, the
 * {@code FirstBloodService.FirstBloodState} / {@code XboxEventState} pattern): lifecycle
 * phase + absolute deadlines (epoch millis from {@code EclipseClock}), the committed
 * hunter/target pair (committed BEFORE the reveal so a crash never re-rolls a different
 * target), pair-cooldown history, the daily roll latch and outcome counters (the analytics
 * substitute — {@code analytics.AnalyticsApi} is a frozen read-only surface, so contract
 * outcomes are tallied here and surfaced by {@code /dev contract status}).
 */
public final class ContractState extends SavedData {
    public static final String DATA_NAME = "eclipse_contracts";

    /** Lifecycle. {@code SCHEDULED} = armed for today, waiting for the window start. */
    public enum Phase {
        IDLE, SCHEDULED, ANNOUNCED, ACTIVE;

        static Phase byName(String name) {
            for (Phase phase : values()) {
                if (phase.name().equalsIgnoreCase(name)) {
                    return phase;
                }
            }
            return IDLE;
        }
    }

    /** Contract flavor. PRANK rounds have no hunter — everyone gets the target treatment. */
    public enum Mode {
        REAL, PRANK;

        static Mode byName(String name) {
            return "PRANK".equalsIgnoreCase(name) ? PRANK : REAL;
        }
    }

    /**
     * Terminal outcomes. {@code WRONG_KILL} is a non-terminal side effect and is only
     * counted, never a phase; {@code TABLES_TURNED} = the target killed the hunter.
     */
    public enum Outcome {
        SUCCESS, EXPIRED, VOIDED, TABLES_TURNED, PRANK_REVEAL
    }

    /** One past pairing, for the same-pair cooldown (IDEA-20 §2). */
    public record PastPair(UUID hunter, UUID target, int day) {}

    private Phase phase = Phase.IDLE;
    private Mode mode = Mode.REAL;
    @Nullable
    private UUID hunter;
    @Nullable
    private UUID target;
    /** Epoch millis at which the omen fires (SCHEDULED) / the window opens (ANNOUNCED). */
    private long windowStartsAtEpochMillis;
    /** Absolute window deadline (ACTIVE). */
    private long endsAtEpochMillis;
    /** Day the running/last contract belongs to. */
    private int contractDay;
    /** Last day the daily odds were rolled (never roll twice for one day). */
    private int rolledForDay = Integer.MIN_VALUE;
    private boolean targetLoggedOut;
    private int ghostHits;

    private final List<PastPair> pairHistory = new ArrayList<>();

    // outcome tallies (analytics substitute)
    private int successCount;
    private int expiredCount;
    private int voidedCount;
    private int tablesTurnedCount;
    private int wrongKillCount;
    private int prankCount;

    public static ContractState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(ContractState::new, ContractState::load));
    }

    public ContractState() {}

    static ContractState load(CompoundTag tag, HolderLookup.Provider registries) {
        ContractState state = new ContractState();
        state.phase = Phase.byName(tag.getString("phase"));
        state.mode = Mode.byName(tag.getString("mode"));
        if (tag.hasUUID("hunter")) {
            state.hunter = tag.getUUID("hunter");
        }
        if (tag.hasUUID("target")) {
            state.target = tag.getUUID("target");
        }
        state.windowStartsAtEpochMillis = tag.getLong("windowStartsAt");
        state.endsAtEpochMillis = tag.getLong("endsAt");
        state.contractDay = tag.getInt("contractDay");
        state.rolledForDay = tag.contains("rolledForDay") ? tag.getInt("rolledForDay") : Integer.MIN_VALUE;
        state.targetLoggedOut = tag.getBoolean("targetLoggedOut");
        state.ghostHits = tag.getInt("ghostHits");
        for (Tag element : tag.getList("pairHistory", Tag.TAG_COMPOUND)) {
            CompoundTag pair = (CompoundTag) element;
            if (pair.hasUUID("hunter") && pair.hasUUID("target")) {
                state.pairHistory.add(new PastPair(pair.getUUID("hunter"), pair.getUUID("target"),
                        pair.getInt("day")));
            }
        }
        state.successCount = tag.getInt("successCount");
        state.expiredCount = tag.getInt("expiredCount");
        state.voidedCount = tag.getInt("voidedCount");
        state.tablesTurnedCount = tag.getInt("tablesTurnedCount");
        state.wrongKillCount = tag.getInt("wrongKillCount");
        state.prankCount = tag.getInt("prankCount");
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putString("phase", phase.name());
        tag.putString("mode", mode.name());
        if (hunter != null) {
            tag.putUUID("hunter", hunter);
        }
        if (target != null) {
            tag.putUUID("target", target);
        }
        tag.putLong("windowStartsAt", windowStartsAtEpochMillis);
        tag.putLong("endsAt", endsAtEpochMillis);
        tag.putInt("contractDay", contractDay);
        tag.putInt("rolledForDay", rolledForDay);
        tag.putBoolean("targetLoggedOut", targetLoggedOut);
        tag.putInt("ghostHits", ghostHits);
        ListTag history = new ListTag();
        for (PastPair pair : pairHistory) {
            CompoundTag entry = new CompoundTag();
            entry.putUUID("hunter", pair.hunter());
            entry.putUUID("target", pair.target());
            entry.putInt("day", pair.day());
            history.add(entry);
        }
        tag.put("pairHistory", history);
        tag.putInt("successCount", successCount);
        tag.putInt("expiredCount", expiredCount);
        tag.putInt("voidedCount", voidedCount);
        tag.putInt("tablesTurnedCount", tablesTurnedCount);
        tag.putInt("wrongKillCount", wrongKillCount);
        tag.putInt("prankCount", prankCount);
        return tag;
    }

    // ------------------------------------------------------------------ accessors

    public Phase phase() {
        return phase;
    }

    public void setPhase(Phase phase) {
        this.phase = phase;
        setDirty();
    }

    public Mode mode() {
        return mode;
    }

    public void setMode(Mode mode) {
        this.mode = mode;
        setDirty();
    }

    @Nullable
    public UUID hunter() {
        return hunter;
    }

    @Nullable
    public UUID target() {
        return target;
    }

    /** Commits the drawn pair (BEFORE the reveal — crash-safe, the AwardService reasoning). */
    public void setPair(@Nullable UUID hunter, @Nullable UUID target) {
        this.hunter = hunter;
        this.target = target;
        setDirty();
    }

    public long windowStartsAtEpochMillis() {
        return windowStartsAtEpochMillis;
    }

    public void setWindowStartsAtEpochMillis(long epochMillis) {
        this.windowStartsAtEpochMillis = epochMillis;
        setDirty();
    }

    public long endsAtEpochMillis() {
        return endsAtEpochMillis;
    }

    public void setEndsAtEpochMillis(long epochMillis) {
        this.endsAtEpochMillis = epochMillis;
        setDirty();
    }

    /** Pause-aware shift: pushes every pending deadline forward (RealtimeDayApi pause). */
    public void shiftDeadlines(long deltaMillis) {
        if (deltaMillis <= 0L) {
            return;
        }
        if (windowStartsAtEpochMillis > 0L) {
            windowStartsAtEpochMillis += deltaMillis;
        }
        if (endsAtEpochMillis > 0L) {
            endsAtEpochMillis += deltaMillis;
        }
        setDirty();
    }

    public int contractDay() {
        return contractDay;
    }

    public void setContractDay(int day) {
        this.contractDay = day;
        setDirty();
    }

    public int rolledForDay() {
        return rolledForDay;
    }

    public void setRolledForDay(int day) {
        this.rolledForDay = day;
        setDirty();
    }

    public boolean targetLoggedOut() {
        return targetLoggedOut;
    }

    public void setTargetLoggedOut(boolean loggedOut) {
        this.targetLoggedOut = loggedOut;
        setDirty();
    }

    public int ghostHits() {
        return ghostHits;
    }

    public void setGhostHits(int hits) {
        this.ghostHits = hits;
        setDirty();
    }

    // ------------------------------------------------------------------ pair cooldown

    /** Whether this hunter→target pairing ran within the last {@code cooldownDays} days. */
    public boolean isPairOnCooldown(UUID hunter, UUID target, int day, int cooldownDays) {
        for (PastPair pair : pairHistory) {
            if (pair.hunter().equals(hunter) && pair.target().equals(target)
                    && day - pair.day() < cooldownDays) {
                return true;
            }
        }
        return false;
    }

    /** Whether {@code uuid} was the target of the previous contract day (no back-to-back). */
    public boolean wasRecentTarget(UUID uuid, int day) {
        for (PastPair pair : pairHistory) {
            if (pair.target().equals(uuid) && day - pair.day() <= 1) {
                return true;
            }
        }
        return false;
    }

    public void recordPair(UUID hunter, UUID target, int day) {
        pairHistory.add(new PastPair(hunter, target, day));
        // Bounded history: entries older than any plausible cooldown window are dropped.
        pairHistory.removeIf(pair -> day - pair.day() > 30);
        setDirty();
    }

    // ------------------------------------------------------------------ tallies

    public void recordOutcome(Outcome outcome) {
        switch (outcome) {
            case SUCCESS -> successCount++;
            case EXPIRED -> expiredCount++;
            case VOIDED -> voidedCount++;
            case TABLES_TURNED -> tablesTurnedCount++;
            case PRANK_REVEAL -> prankCount++;
        }
        setDirty();
    }

    public void recordWrongKill() {
        wrongKillCount++;
        setDirty();
    }

    /** One status line of lifetime tallies (dev status / logs). */
    public String tallyLine() {
        return "success=" + successCount + " expired=" + expiredCount + " voided=" + voidedCount
                + " tablesTurned=" + tablesTurnedCount + " wrongKills=" + wrongKillCount
                + " pranks=" + prankCount;
    }

    /** Clears the running contract (back to IDLE); tallies and history stay. */
    public void clearContract() {
        phase = Phase.IDLE;
        hunter = null;
        target = null;
        windowStartsAtEpochMillis = 0L;
        endsAtEpochMillis = 0L;
        targetLoggedOut = false;
        ghostHits = 0;
        setDirty();
    }
}
