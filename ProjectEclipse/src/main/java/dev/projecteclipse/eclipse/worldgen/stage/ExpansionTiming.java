package dev.projecteclipse.eclipse.worldgen.stage;

/**
 * MAP-EXPANSION TIMING — the single place every duration of the border/map expansion
 * sequence is declared (user ask: "mach das Map Erweitern schneller", with the duration
 * constants clearly named and in ONE spot). Nothing here holds state; the owners read
 * these constants at class-init time:
 *
 * <ul>
 *   <li>{@link GrowthPacing} seeds its {@code worldgen_tuning.json} defaults from the
 *       {@code SWEEP_*} block (operators can still override per save — the file
 *       self-migrates when {@link GrowthPacing#CONFIG_VERSION} moves);</li>
 *   <li>{@link RingGrowthService} takes its per-tick throughput caps from the same
 *       block;</li>
 *   <li>{@code border.SoftBorder} takes the ring lerp length, {@link ExpansionBorderFx}
 *       the gate/boulder beats, {@code sequence.ExpansionSequence} the structure-beat
 *       spacing.</li>
 * </ul>
 *
 * <p><b>v2 speed pass</b> ("mach das Map Erweitern schneller"). The terrain sweep is what
 * the wall clock is actually spent on, and it is throughput-bound, not target-bound: the
 * old defaults paced it toward 1500 ticks AND starved it with a 2 ms/tick column budget, a
 * 5-rings-per-pulse wavefront cap and a single on-disk chunk load per tick. Measured on one
 * dedicated server, same world snapshot restored before each run, same
 * {@code /eclipse stage set overworld 3} commit (162725 columns, 696 chunks, band r
 * 186..288):</p>
 * <pre>
 *   old SWEEP_* defaults   141.6 s   1149 columns/s   535 wave pulses
 *   new SWEEP_* defaults    60.7 s   2681 columns/s   219 wave pulses
 *   ------------------------------------------------------------------
 *                          ×2.33 faster (43 % of the old duration)
 * </pre>
 *
 * <p>The cutscene legs around the sweep are authored path lengths and are deliberately NOT
 * shortened (skyward 100 t, flyover 220 t). The structure beats below are owned here too,
 * but note that {@link #STRUCTURE_RIFT_HOLD_TICKS} was afterwards raised again on purpose —
 * the speed pass had cut the sky tears down to a flicker.</p>
 *
 * <p>The sweep target is an upper bound on SPEED, not a promise: the per-tick millisecond
 * budget and the MSPT&nbsp;&gt;&nbsp;40 skip guard still throttle a struggling server, so
 * shortening the target can never turn into a TPS cliff — it only stops the sweep from
 * idling below its budget.</p>
 */
public final class ExpansionTiming {

    private ExpansionTiming() {}

    // ------------------------------------------------------------------ terrain sweep

    /** Ticks an animated {@link RingGrowthService} sweep paces toward (was 1500 = 75 s). */
    public static final int SWEEP_TARGET_TICKS = 500;

    /** Ticks a rewritten chunk's relight/resend lags behind its covering wave pulse (was 10). */
    public static final int SWEEP_REVEAL_DELAY_TICKS = 4;

    /**
     * Max 1-block rings the visible wavefront may advance per 5-tick wave pulse (was 5,
     * i.e. exactly ONE ring per tick — the hard cap that kept wide bands crawling even
     * when the column budget had room to spare).
     */
    public static final int SWEEP_RINGS_PER_PULSE = 20;

    /** Ring advance between rumble pulses; scaled down with the faster front (was 25). */
    public static final int SWEEP_SHAKE_EVERY_RINGS = 12;

    /** Client column-rise animation hint carried by every wave payload (was 30). */
    public static final int SWEEP_COLUMN_RISE_TICKS = 18;

    /**
     * Floor (ms) of the animated sweep's per-tick nano budget. {@code general.json}'s
     * {@code ringBlocksBudgetMs} may raise it but no longer starve the shortened target
     * — the legacy default of 2 ms cannot feed {@link #SWEEP_TARGET_TICKS}.
     */
    public static final int SWEEP_MIN_BUDGET_MS = 5;

    /** Chunk finishes (pipeline replay + relight + resend) per tick (was 4). */
    public static final int SWEEP_CHUNK_FINISHES_PER_TICK = 8;

    /** Per-tick nano budget of the chunk-finish loop in animated mode (was 12 ms). */
    public static final long SWEEP_FINISH_BUDGET_NANOS = 16_000_000L;

    /**
     * Chunks the animated sweep may sync-load from disk per tick — the "chunk preload"
     * budget the user asked to raise (was 1, which single-file-throttled every sweep
     * over terrain nobody had visited).
     */
    public static final int SWEEP_CHUNK_LOADS_PER_TICK = 4;

    /** Same budget for instant stamps (no animation to pace, so it may pull harder). */
    public static final int SWEEP_CHUNK_LOADS_PER_TICK_INSTANT = 8;

    // ------------------------------------------------------------------ soft border ring

    /** Sweep-coupled ring lerp length; matches {@link #SWEEP_TARGET_TICKS} (was 1500). */
    public static final int BORDER_GROWTH_LERP_TICKS = SWEEP_TARGET_TICKS;

    /**
     * Release surge: the gate-held ring expands to the new radius over this (was 2.5 s).
     * F-092 stretched it to 10 s: the client border radius drives the rim-mountain
     * silhouette ring, so this IS the visible "mountains slowly recede" glide every
     * player on the map watches at release ("langsam zurückweichen").
     */
    public static final long BORDER_RELEASE_LERP_MS = 10_000L;

    // ------------------------------------------------------------------ boulder gate

    /** Rim monoliths heave out of the ground over this many ticks. */
    public static final int BOULDER_RISE_TICKS = 18;

    /** …and sink back into it over this many on release, then discard. */
    public static final int BOULDER_SINK_TICKS = 16;

    /** Pose cadence; the client interpolation duration matches (DisplayAnimator law). */
    public static final int BOULDER_UPDATE_INTERVAL_TICKS = 2;

    /** Cadence of the low strain rumble while the frontier is held. */
    public static final int BOULDER_RUMBLE_PERIOD_TICKS = 60;

    // ------------------------------------------------------------------ structure beats

    /** Establishing gap between the STRUCTURES caption and the first tear (was 20). */
    public static final int STRUCTURES_ESTABLISH_TICKS = 20;

    /**
     * Sky-rift hold between tear-open and the placement trigger. The v2 speed pass cut
     * this to 22 t (~1 s) and the tear read as a flicker; the user asked for the rifts to
     * stay open "several seconds", so it is back up to 5 s. This is the establishing hold
     * only — the tear then stays open for the whole delivery flight on top of it.
     */
    public static final int STRUCTURE_RIFT_HOLD_TICKS = 100;

    /**
     * How long the tear lingers after its structure has slammed down, before the close
     * animation starts (was 8 t, i.e. the tear vanished with the dust).
     */
    public static final int STRUCTURE_RIFT_LINGER_TICKS = 40;

    /** Spacing between consecutive structure beats (was 50). */
    public static final int STRUCTURE_BEAT_SPACING_TICKS = 30;

    /**
     * Chunk-warm budget in front of the flyover's gather teleport. The gather itself is
     * cutscene infrastructure; warming its destination first is what keeps the vanilla
     * "Downloading terrain" screen (pure black in 1.21.1) from outlasting the transition.
     */
    public static final int FLYOVER_WARM_TIMEOUT_TICKS = 40;

    // ------------------------------------------------------------------ map pregen (F-091)

    /** Auto-start the full-map pregen on boot while the start event is pending (§2.4). */
    public static final boolean PREGEN_AUTO_START = true;

    /** Concurrent FULL-status chunk targets a {@code MapPregenService} job keeps in flight. */
    public static final int PREGEN_MAX_IN_FLIGHT = 12;

    /** New chunk requests a pregen job issues per tick. */
    public static final int PREGEN_ISSUES_PER_TICK = 4;

    /** Pregen issues nothing while the server is above this many ms/tick (sweep doctrine). */
    public static final int PREGEN_MSPT_GUARD_MS = 40;
}
