package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.cutscene.CutscenePaths;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import dev.projecteclipse.eclipse.worldgen.structure.SkyLauncher;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.particles.BlockParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * PLAN-C C13: dragon victory — the End disc SHATTERS into floating islets.
 *
 * <p>Subscribes to {@link EclipseDragonFight.Listener#onDragonVictory} (the seam that
 * fires once after rewards/portal placement) and runs the show
 * {@value #VICTORY_DELAY_TICKS} ticks later:</p>
 * <ol>
 *   <li><b>Beat 0</b> — every overworld player above Y {@value #GRACE_MIN_Y} gets Slow
 *       Falling + a 120 s no-fall-damage grace ({@link SkyLauncher#grantFallGrace} — the
 *       C11 per-player seam; {@code TimedBuffApi} is server-global/config-defined and
 *       wrong for this), a caption announces the grace, and the global
 *       {@code end_shatter} orbit cutscene plays via
 *       {@link CutsceneService.PlayOptions#global} — gather, preload and the C6
 *       {@code validatedReturnPosition}-healed return all come with it. CUT-END staging:
 *       beat 0 itself is a dead-silent hold; the bass rumble + camera shake land
 *       {@value #SILENCE_HOLD_TICKS}t later, the violet rift flashes along the future
 *       seams race outward from the podium ({@value #CRACK_RACE_STEP_TICKS}t apart,
 *       pitch-climbing crack stingers riding each one), and the dust curtains + debris
 *       drop wait for the carve pass at +{@value #SEPARATION_FX_DELAY_TICKS}t.</li>
 *   <li><b>Shatter</b> — a deterministic Voronoi crack pattern (seed-hashed off
 *       {@link FrozenParams#mapSeed()}, the {@code DiscMapData.ECLIPSE_SEED} law)
 *       divides the disc into 6–9 islets. Seam channels (3–5 blocks wide) are cleared
 *       and every islet is translated by a per-islet vertical offset (−24…+28, FIN-3:
 *       the isles pull far apart) as a budgeted copy-then-clear pass — the exact
 *       materialization writer shape (one chunk per tick, section writes, heightmap
 *       re-prime, relight + resend), just subtractive. The podium islet
 *       (r &lt; {@value #CENTER_KEEP_RADIUS}) never moves, so egg, portal and gathered
 *       watchers stay safe (the egg IS the day-14 finale catalyst — removing the middle
 *       islet would softlock the endgame). Restart mid-shatter: the {@link ShatterData}
 *       cursor resumes the pass; the cinematic never resumes.</li>
 *   <li><b>Debris</b> (FIN-2 spectacle) — up to {@value #DEBRIS_HARD_CAP} tagged
 *       {@code block_display} chunks: a dense seam FIELD wave plus fountains VENTING out
 *       of every crack flash and carve stinger, all staggered through a
 *       {@value #DEBRIS_SPAWN_PER_TICK}/t spawn queue with view-range culling
 *       (in-memory animator, TTL-discarded, tag-swept at boot).</li>
 *   <li><b>End structures</b> — when the pass completes, the three largest outer islets
 *       receive {@link EndCityKit} sites (two towers + one end-ship, real loot + shulkers)
 *       through {@link StructurePendingRegistry}, so they get the standard rift
 *       reveals. FIN-2 rides the same completion: endermen rise on the isles (post-fight
 *       by construction).</li>
 * </ol>
 *
 * <h2>F-047 — the crash finale</h2>
 *
 * <p>The archipelago is no longer the end state. {@value #CRASH_DELAY_TICKS} ticks after
 * the carve completes (the loot window for the End-city kits) the sky comes down, in four
 * persisted phases on top of the carve — {@link #PHASE_CRASH_WAIT},
 * {@link #PHASE_CRASH}, {@link #PHASE_CORE}, {@link #PHASE_SKY_BITS}:</p>
 * <ol>
 *   <li><b>Staggered crash</b> — the outer islets fall ONE AT A TIME. Each islet launches
 *       a visible {@link EndIslandCrashFx} fragment cluster towards its ground impact site
 *       while a budgeted {@link RazePass} erases exactly that islet's columns from the sky
 *       (one chunk per tick, section-air fast path). The landing fires explosion particles,
 *       a thud + shake and builds a small REAL end-stone rubble heap on the ground; any
 *       loot block entity the raze still finds up there rides down into that heap instead
 *       of being deleted.</li>
 *   <li><b>The middle island goes too</b> ({@link #PHASE_CORE}) — a final full-band sweep
 *       over the whole disc footprint removes the podium islet with its exit portal and
 *       every sliver the per-islet passes left behind, so the sky is provably empty. The
 *       dragon egg is NOT lost with it: it is the hard-wired day-14 finale catalyst
 *       ({@code FinaleRitual.CATALYST}), so if the egg is still sitting on the pedestal it
 *       is re-seated on the first ground heap.</li>
 *   <li><b>Low remnants</b> ({@link #PHASE_SKY_BITS}) — {@value #SKY_BIT_COUNT} small
 *       clumps hung {@value #SKY_BIT_MIN_RISE}–{@value #SKY_BIT_MIN_RISE}+{@value
 *       #SKY_BIT_RISE_RANGE} blocks over the LOCAL ground and spread far apart across the
 *       map, so reaching them is a short pillar rather than a 300-block tower.</li>
 * </ol>
 *
 * <p>Every phase boundary, the per-islet pass index, both raze cursors and the per-islet
 * "ground heap already built" mask live in {@link ShatterData}, so a restart in the middle
 * of the finale resumes exactly where it stopped (and back-fills any heap whose cosmetic
 * fall was dropped with the restart). Only the cinematic itself never resumes.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndShatterSequence {
    /** Cutscene path id (bundled default {@code assets/eclipse/cutscenes/end_shatter.json}). */
    public static final String CUTSCENE_ID = "end_shatter";
    /** Command tag on every drifting debris display. */
    public static final String DEBRIS_TAG = "eclipse_end_shatter_debris";

    /** Beat-0 delay after the victory listener fires (plan: victory +40 t). */
    private static final int VICTORY_DELAY_TICKS = 40;
    /** The carve pass starts this long after beat 0 (the orbit establishes first). */
    private static final int CARVE_DELAY_TICKS = 60;
    /** Players above this Y when the shatter starts receive the safety grace. */
    private static final int GRACE_MIN_Y = 300;
    /** Slow Falling + no-fall-damage window length (120 s per plan). */
    private static final int GRACE_TICKS = 120 * 20;
    /** Columns closer to the disc center than this always keep islet 0 (podium, egg). */
    private static final int CENTER_KEEP_RADIUS = 14;
    /**
     * Per-islet vertical offset bounds. F-047 ("bewege die End Inseln sehr weit
     * auseinander") widens the FIN-3 band once more, from −24…+28 to −32…+36: paired
     * with the {@value #SEAM_MIN_WIDTH}–{@value #SEAM_MIN_WIDTH}+{@value
     * #SEAM_WIDTH_RANGE}-block seam channels below, no two islets read as one surface
     * any more. Bounds against the overworld's −176..464 build range: the highest block
     * an islet can own is {@code MAX_Y(408) + 36 = 444} and the lowest
     * {@code MIN_Y(340) − 32 = 308}, both well inside existing chunk sections.
     */
    private static final int DY_MIN = -32;
    private static final int DY_RANGE = 68; // DY_MIN..DY_MIN+68 = −32..+36
    /**
     * Seam channel width band (blocks cleared along each Voronoi boundary). F-047 pulls
     * this up from the FIN-3 3–5 to a gap you cannot step across, so the archipelago is
     * genuinely separate islands rather than a cracked slab.
     */
    private static final int SEAM_MIN_WIDTH = 8;
    private static final int SEAM_WIDTH_RANGE = 5; // 8…12
    /**
     * FIN-2 display budget: the seam FIELD scan queues up to {@value #DEBRIS_FIELD_CAP}
     * chunks, every crack-race flash fountains {@value #BURST_PER_CRACK} more OUT of its
     * fissure, and each carve-pass crack stinger vents {@value #CARVE_BURST_PER_CRACK}.
     * {@value #DEBRIS_HARD_CAP} is the absolute live ceiling (queued overflow is
     * dropped, logged), {@value #DEBRIS_SPAWN_PER_TICK}/t is the spawn budget (a
     * staggered wave — never one single-tick spike), every display ships a
     * {@value #DEBRIS_VIEW_RANGE}× view range so distant chunks cull client-side, and
     * the {@value #DEBRIS_TTL_TICKS}t TTL + dissolve bounds the population from above.
     */
    private static final int DEBRIS_FIELD_CAP = 260;
    private static final int BURST_PER_CRACK = 22;
    private static final int CARVE_BURST_PER_CRACK = 8;
    private static final int DEBRIS_HARD_CAP = 420;
    private static final int DEBRIS_SPAWN_PER_TICK = 20;
    private static final float DEBRIS_VIEW_RANGE = 4.0F;
    private static final int DEBRIS_TTL_TICKS = 300;
    /** Debris keyframe cadence — interpolation duration matches (DisplayAnimator law). */
    private static final int DEBRIS_UPDATE_TICKS = 4;
    /** Gravity-lite pull on drifting debris (blocks/tick² — a lazy void-fall, not a drop). */
    private static final double DEBRIS_GRAVITY = -0.003D;
    /** Terminal fall speed: caps the per-window delta so 4 t tweens stay dense enough. */
    private static final double DEBRIS_TERMINAL_FALL = -0.35D;
    /** Last fraction of the TTL spent dissolving (shrink + brightness-down). */
    private static final float DEBRIS_DISSOLVE_FRACTION = 0.20F;
    /** Debris tumble rate range (deg/tick) — fixed axis + fixed signed rate per chunk. */
    private static final double DEBRIS_SPIN_MIN_DEG = 0.6D;
    private static final double DEBRIS_SPIN_MAX_DEG = 1.6D;
    /** Slow precession of each chunk's tumble pole around Y (deg/tick). */
    private static final double DEBRIS_PRECESS_MIN_DEG = 0.08D;
    private static final double DEBRIS_PRECESS_MAX_DEG = 0.20D;
    /**
     * Straggler personality (REPASS-BD): 1–2 chunks (the {@value #STRAGGLER_ORDINAL_A}th
     * and {@value #STRAGGLER_ORDINAL_B}th spawned — the grid scan is deterministic, so
     * replays pick the same columns) CLING to the break face and fall up to
     * {@value #STRAGGLER_LAG_TICKS}t behind the flock, then catch back up. Implemented
     * as a closed-form monotonic time warp on the chunk's motion clock — the dissolve
     * and TTL stay on real age, and the warp is identity again before the dissolve
     * starts, so nothing downstream changes. Cling slope keeps the warped clock ≥ 0.18×
     * real (never reverses — angular momentum stays signed); catch-up peaks at ~1.49×
     * (terminal fall ≈ 2.1 blocks and spin ≈ 9.6° per 4t window — inside the tween law).
     */
    private static final int STRAGGLER_ORDINAL_A = 5;
    private static final int STRAGGLER_ORDINAL_B = 23;
    private static final int STRAGGLER_LAG_TICKS = 26;
    /** Time-warp envelope knees: cling ends / hold ends / caught up (ticks of real age). */
    private static final int STRAGGLER_CLING_END = 48;
    private static final int STRAGGLER_HOLD_END = 96;
    private static final int STRAGGLER_CATCHUP_END = 176;
    /** Crack stingers while the carve pass runs. */
    private static final int CRACK_INTERVAL_TICKS = 48;

    /** Seed-mix salts (local mixer — DiscTerrainFunction.hash is package-private). */
    private static final long SALT_LAYOUT = 91L;
    private static final long SALT_SEAM = 92L;
    private static final long SALT_DEBRIS = 93L;
    private static final long SALT_BURST = 94L;
    private static final long SALT_ENDERMEN = 95L;
    private static final long SALT_RUBBLE = 96L;
    private static final long SALT_IMPACT = 97L;
    private static final long SALT_CRASH = 98L;

    // --- FIN-2/FIN-3 post-fight population ---
    /** Endermen risen per outer islet once the carve completes (post-fight only). */
    private static final int ENDERMEN_PER_ISLET = 3;

    // --- F-047: the crash finale (phases 1…4 below the carve) -----------------------

    /**
     * How long the shattered archipelago stands before it starts falling. This is the
     * LOOT WINDOW: the {@link EndCityKit} sites are enqueued at carve completion and the
     * crash razes the sky afterwards, so players need a real chance to raid them (any
     * chest the raze still finds is rescued into the ground rubble, see
     * {@link RazePass#rescued}). {@code /eclipse-worldgen end crash} skips the wait.
     */
    private static final int CRASH_DELAY_TICKS = 12_000;
    /** Fall length of one islet's visible fragment cluster before its ground impact. */
    private static final int CRASH_FALL_TICKS = 170;
    /**
     * Vertical band the raze passes clear: from below the deepest islet offset to above
     * the tallest caged pillar of a RISEN islet (plus room for the End-city kits).
     * Clamped against the level's build height at use.
     */
    private static final int RAZE_MIN_Y = EndDiscGeometry.MIN_Y + DY_MIN - 8;
    private static final int RAZE_MAX_Y = EndDiscGeometry.MAX_Y + DY_MIN + DY_RANGE + 24;
    /** Impact sites stay this far out from the disc centre (the sanctum cylinder is r 18). */
    private static final int IMPACT_MIN_RADIUS = 44;
    private static final int IMPACT_MAX_RADIUS = DiscProfile.END_DISC_RADIUS - 4;
    /** Impact sites are pushed this much further out than their islet sat. */
    private static final double IMPACT_SPREAD_FACTOR = 1.15D;
    /** One ground rubble heap: horizontal radius {@code MIN}…{@code MIN+RANGE}. */
    private static final int HEAP_MIN_RADIUS = 3;
    private static final int HEAP_RADIUS_RANGE = 2;
    /** Loot block entities rescued out of a falling islet into its ground heap. */
    private static final int HEAP_LOOT_CAP = 8;
    /**
     * F-047 (e) "Bröckel am Himmel, aber niedriger": the handful of remnants left over
     * the map are hung {@value #SKY_BIT_MIN_RISE}…{@value #SKY_BIT_MIN_RISE}+{@value
     * #SKY_BIT_RISE_RANGE} blocks over the LOCAL GROUND (was: 14–30 over the Y-360 lens,
     * i.e. ~300 blocks up) and spread across a {@value #SKY_BIT_MIN_RADIUS}…{@value
     * #SKY_BIT_MIN_RADIUS}+{@value #SKY_BIT_RADIUS_RANGE} ring, one per angular slice —
     * near enough to pillar up to, far enough apart to be separate landmarks.
     */
    private static final int SKY_BIT_COUNT = 7;
    private static final int SKY_BIT_MIN_RISE = 40;
    private static final int SKY_BIT_RISE_RANGE = 20;
    private static final int SKY_BIT_MIN_RADIUS = 110;
    private static final int SKY_BIT_RADIUS_RANGE = 150;
    private static final int SKY_BIT_MIN_SIZE = 3;
    private static final int SKY_BIT_SIZE_RANGE = 3;

    // --- F-047 finale phases (persisted in ShatterData; see the class doc) ---
    /** The Voronoi carve pass — the archipelago forms (legacy behaviour). */
    public static final int PHASE_CARVE = 0;
    /** The archipelago stands; the crash is armed for {@code crashDueGameTime}. */
    public static final int PHASE_CRASH_WAIT = 1;
    /** One islet at a time falls out of the sky and lands as ground rubble. */
    public static final int PHASE_CRASH = 2;
    /** The middle island (podium, portal, egg) and every leftover block are razed. */
    public static final int PHASE_CORE = 3;
    /** The low, far-apart sky remnants are placed. */
    public static final int PHASE_SKY_BITS = 4;
    /** Terminal. */
    public static final int PHASE_DONE = 5;

    private static final long TICK_NANOS = 2_000_000L;
    private static final int POLL_TICKS = 20;
    /** View-distance bump of the global cutscene (the disc is 192 blocks wide). */
    private static final int CUTSCENE_VIEW_DISTANCE = 12;

    private static final ResourceLocation FX_RIFT_OPEN =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_open");
    private static final double FX_RANGE = 256.0D;

    // --- CUT-END presentation timings (camera/FX beats only; the carve flow is untouched) ---

    /** Dead-silence hold after beat 0 before the first crack lands (~1.2 s; JSON t 0.10). */
    private static final int SILENCE_HOLD_TICKS = 24;
    /** Spacing between successive seam flashes of the center-out crack race. */
    private static final int CRACK_RACE_STEP_TICKS = 4;
    /** Dust curtains + debris drop this long after beat 0 (just before the carve pass bites). */
    private static final int SEPARATION_FX_DELAY_TICKS = 58;
    /** Debris ember-trail burst cadence / per-burst sample cap (client BURST budget backstops). */
    private static final int DEBRIS_TRAIL_INTERVAL_TICKS = 40;
    private static final int DEBRIS_TRAIL_SAMPLES = 3;

    /** One-shot dust-curtain emitter reused from the expansion suite ({@code loop=false} JSON). */
    private static final ResourceLocation GROWTH_DUST_WALL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "growth_dust_wall");
    /** One-shot ember burst reused for the debris trails ({@code loop=false} JSON). */
    private static final ResourceLocation SLAM_DEBRIS =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "slam_debris");

    private static final Set<Heightmap.Types> HEIGHTMAPS = EnumSet.of(
            Heightmap.Types.MOTION_BLOCKING,
            Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
            Heightmap.Types.OCEAN_FLOOR,
            Heightmap.Types.WORLD_SURFACE);

    private static final AtomicBoolean BOOTSTRAPPED = new AtomicBoolean();

    @Nullable
    private static Job activeJob;
    /** The live crash/core raze pass (F-047), or {@code null}. Server thread only. */
    @Nullable
    private static RazePass activePass;
    /** Game time the running crash pass's fragment cluster lands at, or −1. */
    private static long impactDueTick = -1L;
    private static final List<Debris> DEBRIS = new ArrayList<>();

    /**
     * UUIDs of debris displays spawned THIS session (StructureFlightFx doctrine): a tagged
     * joiner outside this set is a crash/restart stray and is discarded on chunk load.
     */
    private static final Set<UUID> LIVE_DEBRIS = Collections.synchronizedSet(new HashSet<>());

    /** One prepared debris spawn (FIN-2): parameters only — the entity is born at drain. */
    private record PendingSpawn(Vec3 origin, double vx, double vy0, double vz, Vector3f axis,
            double spinRate, double spinPhase, double precessRate, float scale,
            boolean straggler, Block block) {}

    /**
     * FIN-2 staggered spawn wave (server thread only): field/burst generators QUEUE
     * here and {@link #drainPending} births at most {@value #DEBRIS_SPAWN_PER_TICK}
     * displays per tick under the {@value #DEBRIS_HARD_CAP} live ceiling. Purely
     * cosmetic — a restart drops the queue with the rest of the presentation.
     */
    private static final java.util.ArrayDeque<PendingSpawn> PENDING = new java.util.ArrayDeque<>();

    /** One scheduled CUT-END presentation beat, {@code delayTicks} after beat-clock zero. */
    private record Beat(int delayTicks, Runnable action) {}

    /**
     * Pending presentation beats (server thread only). Purely cosmetic: a restart drops
     * them along with everything else transient — the cinematic never resumes (plan law).
     */
    private static final List<Beat> BEATS = new ArrayList<>();

    /**
     * CUT-END beat-clock zero (game time): −1 until armed. The clock arms on the FIRST
     * client {@code C2SCutsceneReadyPayload} ACK of the shatter cutscene — the instant a
     * watcher's preload hold releases and the flight (whose JSON carries the mirrored
     * sound/shake events) actually starts — so the server crack race never plays behind
     * the client's black hold (EVAL-V6-CUTBD §3.3).
     */
    private static long beatZeroGameTime = -1L;
    /** Timeout-fallback arm deadline (game time); −1 when no arm is pending. */
    private static long beatArmDeadline = -1L;

    private EndShatterSequence() {}

    // --- deterministic layout (EndDiscGeometry snapshot-cache pattern) ---

    /** One column classification: owning islet, seam membership, islet vertical offset. */
    private record Sample(int islet, boolean seam, int dy) {}

    private record Layout(long seed, int count, double[] siteX, double[] siteZ, int[] dy) {

        /** Classifies column (x, z); callers already checked the disc footprint. */
        Sample sample(int x, int z) {
            double cx = x - DiscProfile.END_DISC_CENTER_X;
            double cz = z - DiscProfile.END_DISC_CENTER_Z;
            if (cx * cx + cz * cz < (double) CENTER_KEEP_RADIUS * CENTER_KEEP_RADIUS) {
                return new Sample(0, false, 0);
            }
            int first = 0;
            int second = -1;
            double firstDist = Double.MAX_VALUE;
            double secondDist = Double.MAX_VALUE;
            for (int i = 0; i < this.count; i++) {
                double dx = cx - this.siteX[i];
                double dz = cz - this.siteZ[i];
                double dist = Math.sqrt(dx * dx + dz * dz);
                if (dist < firstDist) {
                    second = first;
                    secondDist = firstDist;
                    first = i;
                    firstDist = dist;
                } else if (dist < secondDist) {
                    second = i;
                    secondDist = dist;
                }
            }
            int lo = Math.min(first, second);
            int hi = Math.max(first, second);
            int seamWidth = SEAM_MIN_WIDTH
                    + (int) Math.floorMod(mix(this.seed ^ SALT_SEAM, lo, hi), SEAM_WIDTH_RANGE);
            boolean seam = secondDist - firstDist < seamWidth;
            return new Sample(first, seam, this.dy[first]);
        }
    }

    private static volatile Layout layout;

    /** The islet layout for the active frozen map seed (rebuilt on save switch). */
    private static Layout layout() {
        long seed = FrozenParams.mapSeed();
        Layout cached = layout;
        if (cached == null || cached.seed() != seed) {
            synchronized (EndShatterSequence.class) {
                cached = layout;
                if (cached == null || cached.seed() != seed) {
                    int count = 6 + (int) Math.floorMod(mix(seed ^ SALT_LAYOUT, 1L, 0L), 4L);
                    double[] siteX = new double[count];
                    double[] siteZ = new double[count];
                    int[] dy = new int[count];
                    // Islet 0 is the podium islet: centered, never offset.
                    for (int i = 1; i < count; i++) {
                        double slice = Math.PI * 2.0D / (count - 1);
                        double angle = slice * (i - 1)
                                + (to01(mix(seed ^ SALT_LAYOUT, i, 7L)) - 0.5D) * slice * 0.6D;
                        double radius = DiscProfile.END_DISC_RADIUS
                                * (0.34D + 0.38D * to01(mix(seed ^ SALT_LAYOUT, i, 8L)));
                        siteX[i] = Math.cos(angle) * radius;
                        siteZ[i] = Math.sin(angle) * radius;
                        dy[i] = DY_MIN + (int) Math.round(
                                to01(mix(seed ^ SALT_LAYOUT, i, 9L)) * DY_RANGE);
                    }
                    cached = new Layout(seed, count, siteX, siteZ, dy);
                    layout = cached;
                }
            }
        }
        return cached;
    }

    /** SplitMix64-style mixer (deterministic across restarts and platforms). */
    private static long mix(long seed, long a, long b) {
        long h = seed ^ (a * 0x9E3779B97F4A7C15L) ^ (b * 0xC2B2AE3D27D4EB4FL);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return h ^ (h >>> 31);
    }

    private static double to01(long h) {
        return (h >>> 11) * 0x1.0p-53D;
    }

    // --- lifecycle wiring ---

    /** Victory-listener + kit-placer bootstrap (once per JVM; observatory guard pattern). */
    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        StructurePendingRegistry.registerAsyncPlacer(EndCityKit.STRUCTURE_ID, EndCityKit::placeSite);
        if (BOOTSTRAPPED.compareAndSet(false, true)) {
            EclipseDragonFight.addListener(EndShatterSequence::onDragonVictory);
            EclipseMod.LOGGER.info("EndShatterSequence registered as dragon-victory listener");
        }
    }

    /** Resume a save interrupted mid-shatter (cursor resumes; the cinematic never does). */
    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onServerStarted(ServerStartedEvent event) {
        ServerLevel overworld = event.getServer().overworld();
        ShatterData state = ShatterData.get(event.getServer());
        sweepDebris(overworld);
        if (state.started() && !state.complete()) {
            activeJob = new Job(overworld, state, 0);
            EclipseMod.LOGGER.info("EndShatterSequence: resuming carve pass at cursor {}",
                    state.cursor());
            return;
        }
        if (!state.complete()) {
            return;
        }
        // F-047 resume: back-fill the ground rubble of every islet whose crash pass had
        // already run (its cosmetic fall died with the restart, its heap must not), then
        // re-arm the phase that was interrupted.
        resumeFinale(overworld, state);
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeJob = null;
        activePass = null;
        impactDueTick = -1L;
        DEBRIS.clear();
        LIVE_DEBRIS.clear();
        PENDING.clear();
        BEATS.clear();
        beatZeroGameTime = -1L;
        beatArmDeadline = -1L;
    }

    /**
     * StructureFlightFx sweep doctrine (EVAL-V6-CUTBD §3, defect 1): the boot AABB sweep
     * only reaches chunks loaded during {@code ServerStartedEvent}; a tagged debris
     * display sleeping in an unloaded chunk is caught HERE, the moment its chunk loads —
     * a tagged joiner we did not spawn this session is a crash/restart stray.
     */
    @SubscribeEvent
    public static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(DEBRIS_TAG)
                && !LIVE_DEBRIS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (activeJob != null) {
            activeJob.tick();
        }
        if (!BEATS.isEmpty()) {
            long gameTime = server.overworld().getGameTime();
            if (beatZeroGameTime < 0L && beatArmDeadline >= 0L && gameTime >= beatArmDeadline) {
                armBeatClock(gameTime, "preload-ready timeout fallback");
            }
            if (beatZeroGameTime >= 0L) {
                tickBeats(gameTime);
            }
        }
        if (!PENDING.isEmpty()) {
            drainPending(server.overworld());
        }
        if (!DEBRIS.isEmpty()) {
            tickDebris();
        }
        if (activePass != null) {
            tickFinalePass(server);
        }
        if (server.getTickCount() % POLL_TICKS != 0) {
            return;
        }
        ShatterData state = ShatterData.get(server);
        if (state.complete()) {
            pollFinale(server, state);
            return;
        }
        if (state.started() || state.dueGameTime() < 0L) {
            return;
        }
        if (server.overworld().getGameTime() >= state.dueGameTime()) {
            beginShatter(server, state);
        }
    }

    // --- F-047 finale driver -------------------------------------------------------

    /**
     * How far above the authored disc geometry the highest islet now sits, or 0 while the
     * disc is still one slab. The {@code SkyLauncher} adds this to its climb target so a
     * launch keeps clearing the archipelago after the carve raised part of it (F-024).
     */
    public static int maxIsletLift(MinecraftServer server) {
        if (!ShatterData.get(server).complete()) {
            return 0;
        }
        int lift = 0;
        for (int dy : layout().dy()) {
            lift = Math.max(lift, dy);
        }
        return lift;
    }

    /** Whether the crash finale has emptied the sky (the {@code SkyLauncher} gate). */
    public static boolean skyCleared(MinecraftServer server) {
        return ShatterData.get(server).phase() >= PHASE_SKY_BITS;
    }

    /** Whether the crash finale has run to its terminal phase. */
    public static boolean finaleDone(MinecraftServer server) {
        return ShatterData.get(server).phase() >= PHASE_DONE;
    }

    /**
     * Command seam ({@code /eclipse-worldgen end crash}): skips the remaining loot window
     * and starts the crash finale now. Refused before the carve completed and after the
     * crash already began, so it can never double-run a pass.
     */
    public static boolean forceCrash(MinecraftServer server) {
        ShatterData state = ShatterData.get(server);
        if (!state.complete() || state.phase() != PHASE_CRASH_WAIT) {
            return false;
        }
        state.setCrashDue(server.overworld().getGameTime());
        return true;
    }

    /** Slow poll (every {@value #POLL_TICKS}t) that advances the finale between passes. */
    private static void pollFinale(MinecraftServer server, ShatterData state) {
        if (activePass != null || state.phase() >= PHASE_DONE) {
            return;
        }
        ServerLevel overworld = server.overworld();
        switch (state.phase()) {
            case PHASE_CARVE -> {
                // Legacy save: the carve finished before F-047 existed — arm the finale.
                state.armCrash(overworld.getGameTime() + CRASH_DELAY_TICKS);
                EclipseMod.LOGGER.info("EndShatterSequence: crash finale armed for game time {}",
                        state.crashDueGameTime());
            }
            case PHASE_CRASH_WAIT -> {
                if (overworld.getGameTime() >= state.crashDueGameTime()) {
                    beginCrash(overworld, state);
                }
            }
            case PHASE_CRASH -> startCrashPass(overworld, state);
            case PHASE_CORE -> startCorePass(overworld, state);
            case PHASE_SKY_BITS -> placeSkyBits(overworld, state);
            default -> { }
        }
    }

    /** Runs the live raze pass and resolves its completion / its cluster's landing. */
    private static void tickFinalePass(MinecraftServer server) {
        RazePass pass = activePass;
        if (pass == null) {
            return;
        }
        ShatterData state = ShatterData.get(server);
        long gameTime = server.overworld().getGameTime();
        if (impactDueTick >= 0L && gameTime >= impactDueTick) {
            impactDueTick = -1L;
            landIslet(server.overworld(), state, state.crashPass());
        }
        if (!pass.tick()) {
            return;
        }
        activePass = null;
        state.setRazeCursor(0L);
        if (state.phase() == PHASE_CRASH) {
            // Safety net: a pass that outlives its (cosmetic) fall still lands its rubble.
            if (impactDueTick >= 0L) {
                impactDueTick = -1L;
                landIslet(server.overworld(), state, state.crashPass());
            }
            state.advanceCrashPass();
            if (state.crashPass() >= crashOrder(layout()).size()) {
                state.setPhase(PHASE_CORE);
            }
            return;
        }
        completeCorePass(server.overworld(), state);
    }

    /** Runs every due presentation beat (server thread; a restart simply drops them). */
    private static void tickBeats(long gameTime) {
        Iterator<Beat> iterator = BEATS.iterator();
        while (iterator.hasNext()) {
            Beat beat = iterator.next();
            if (gameTime >= beatZeroGameTime + beat.delayTicks()) {
                iterator.remove();
                beat.action().run();
            }
        }
    }

    /**
     * Arms the presentation beat clock (idempotent): every beat delay — and the carve
     * start — counts from HERE, the client's flight start, not from the play-payload
     * send. Fired by the first {@code end_shatter} preload-ready ACK (the W-CUTSCENE
     * {@code C2SCutsceneReadyPayload} seam) or the shared preload-timeout fallback.
     */
    private static void armBeatClock(long gameTime, String reason) {
        if (beatZeroGameTime < 0L) {
            beatZeroGameTime = gameTime;
            beatArmDeadline = -1L;
            EclipseMod.LOGGER.info("EndShatterSequence: beat clock armed at game time {} ({})",
                    gameTime, reason);
        }
    }

    /** The {@link EclipseDragonFight.Listener} seam: schedule beat 0 at victory +40 t. */
    private static void onDragonVictory(MinecraftServer server, BlockPos center) {
        ShatterData state = ShatterData.get(server);
        if (state.started() || state.complete()) {
            return;
        }
        state.schedule(server.overworld().getGameTime() + VICTORY_DELAY_TICKS);
        EclipseMod.LOGGER.info("EndShatterSequence scheduled at game time {}", state.dueGameTime());
    }

    // --- beat 0 ---

    private static void beginShatter(MinecraftServer server, ShatterData state) {
        ServerLevel overworld = server.overworld();
        state.markStarted();
        Layout layout = layout();

        // Player safety first: slow fall + 120 s grace for everyone up on the disc band.
        for (ServerPlayer player : overworld.players()) {
            if (player.getY() > GRACE_MIN_Y && !player.isSpectator()) {
                player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                        GRACE_TICKS, 0, false, false, true));
                SkyLauncher.grantFallGrace(player, GRACE_TICKS);
                PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                        "eclipse.caption.end_shatter.grace", 100, S2CCaptionPayload.STYLE_SUBTITLE));
            }
        }
        server.getPlayerList().broadcastSystemMessage(
                Component.translatable("announce.eclipse.end.shatter"), false);

        BlockPos center = new BlockPos(EndConfig.current().centerX(),
                EndDiscGeometry.surfaceYAt(EndConfig.current().centerX(), EndConfig.current().centerZ()),
                EndConfig.current().centerZ());
        long now = overworld.getGameTime();

        // CUT-END shot 1 (dragon-death beat): beat 0 is a DEAD-SILENT hold — only the
        // safety caption stands while the orbit establishes. The rumble, the big shake and
        // the seam flashes all wait out SILENCE_HOLD_TICKS, so the JSON's first crack
        // (t 0.10 ≈ the same wall-clock instant — beat delays and the JSON events now
        // share the preload-release clock, see the ready-ACK arming below) breaks true
        // silence instead of layering onto a wall of sound. (No sound-STOP mechanism
        // exists anywhere in the mod, so a real audio duck is not achievable — the hold is
        // built by scheduling, not by stopping.)
        BEATS.add(new Beat(SILENCE_HOLD_TICKS, () -> {
            overworld.playSound(null, center, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                    SoundSource.HOSTILE, 4.0F, 1.0F);
            for (ServerPlayer player : overworld.players()) {
                player.playNotifySound(EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                        SoundSource.MASTER, 1.2F, 1.0F);
            }
            PacketDistributor.sendToPlayersInDimension(overworld, S2CShakePayload.shake(1.2F, 50));
        }));

        // CUT-END shot 2 (crack propagation): the violet rift flashes along the future
        // seams (podium → each outer islet midpoint) no longer fire as one simultaneous
        // wall — they RACE outward from the podium in seam-midpoint-radius order, one
        // every CRACK_RACE_STEP_TICKS, each carrying a positional crack stinger whose
        // pitch climbs as the race runs: light bleeding up from the fissures, center-out.
        List<Integer> race = new ArrayList<>();
        for (int i = 1; i < layout.count(); i++) {
            race.add(i);
        }
        race.sort(Comparator.comparingDouble(
                islet -> Math.hypot(layout.siteX()[islet], layout.siteZ()[islet])));
        for (int step = 0; step < race.size(); step++) {
            int islet = race.get(step);
            float pitch = 0.85F + 0.06F * step;
            double sx = DiscProfile.END_DISC_CENTER_X + layout.siteX()[islet] * 0.5D;
            double sz = DiscProfile.END_DISC_CENTER_Z + layout.siteZ()[islet] * 0.5D;
            Vec3 flash = new Vec3(sx,
                    EndDiscGeometry.surfaceYAt((int) sx, (int) sz) + 2.0D, sz);
            BEATS.add(new Beat(SILENCE_HOLD_TICKS + step * CRACK_RACE_STEP_TICKS, () -> {
                // PH-IMPROVE-2 (IDEAS-world #6a Option B): the Photon light-bleed shafts
                // land FIRST — the row's leg records the played position so the client's
                // RiftFx.openRift (the FX_RIFT_OPEN one line below, same flash pos)
                // retires its generic EXPANSION_RIFT_GLOW for this tear. Photon-less
                // clients no-op on the cue and keep the full shipped rift stack.
                PacketDistributor.sendToPlayersNear(overworld, null, flash.x, flash.y, flash.z,
                        FX_RANGE, new S2CFxEventPayload(FxCues.CUE_END_CRACK, flash, 0.0F, 0.0F));
                PacketDistributor.sendToPlayersNear(overworld, null, flash.x, flash.y, flash.z,
                        FX_RANGE, new S2CFxEventPayload(FX_RIFT_OPEN, flash, 6.0F, 0.0F));
                overworld.playSound(null, BlockPos.containing(flash),
                        EclipseSounds.EVENT_END_SHATTER_CRACK.get(), SoundSource.HOSTILE, 3.0F, pitch);
                // FIN-2: the freshly-opened fissure VENTS — a fountain of display chunks
                // erupts out of the crack (queued through the global spawn budget).
                queueCrackBurst(flash, BURST_PER_CRACK, mix(layout.seed() ^ SALT_BURST, islet, 0L));
            }));
        }

        // CUT-END shot 3 (separation): dust curtains fall from the break faces and the
        // debris chunks start tumbling only when the carve pass is about to bite (beat 0 +
        // CARVE_DELAY_TICKS; the curtains land just ahead of it) — not at beat 0, when the
        // disc is still visibly whole.
        BEATS.add(new Beat(SEPARATION_FX_DELAY_TICKS, () -> {
            for (int i = 1; i < layout.count(); i++) {
                double sx = DiscProfile.END_DISC_CENTER_X + layout.siteX()[i] * 0.5D;
                double sz = DiscProfile.END_DISC_CENTER_Z + layout.siteZ()[i] * 0.5D;
                Vec3 seam = new Vec3(sx,
                        EndDiscGeometry.surfaceYAt((int) sx, (int) sz) + 1.0D, sz);
                PacketDistributor.sendToPlayersNear(overworld, null, seam.x, seam.y, seam.z,
                        FX_RANGE, new S2CQuasarPayload(GROWTH_DUST_WALL, seam));
            }
            overworld.playSound(null, center, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                    SoundSource.HOSTILE, 3.0F, 0.8F);
            queueFieldDebris(layout);
        }));

        // The carve pass rides the SAME beat clock, so the whole presentation (rumble,
        // crack race, curtains, debris, carve bite) shifts together with the client hold.
        // A mid-shatter restart still resumes the carve immediately via onServerStarted.
        BEATS.add(new Beat(CARVE_DELAY_TICKS, () -> activeJob = new Job(overworld, state, 0)));

        // EVAL-V6-CUTBD §3 defect 3: the beats above are NOT clocked from `now` — the
        // clock arms on the first client preload-ready ACK (W-CUTSCENE's
        // C2SCutsceneReadyPayload seam), so the first crack lands after the black hold
        // releases. Vanilla clients / packet loss fall back to the shared preload
        // timeout; a disabled or missing path never ACKs, so it arms immediately.
        CutscenePath path = CutscenePaths.get(CUTSCENE_ID);
        if (path != null && CutsceneService.isEnabled(server, path)) {
            beatArmDeadline = now + CutsceneService.PRELOAD_TIMEOUT_TICKS;
            CutsceneService.onNextClientReady(CUTSCENE_ID,
                    () -> armBeatClock(overworld.getGameTime(), "client preload-ready ACK"));
        } else {
            armBeatClock(now, "cutscene disabled/absent");
        }

        // Global orbit show; gather + preload + the C6-healed return come with global().
        Vec3 anchor = Vec3.atCenterOf(center);
        CutsceneService.play(CUTSCENE_ID, List.copyOf(server.getPlayerList().getPlayers()),
                anchor, null, CutsceneService.PlayOptions.global(CUTSCENE_VIEW_DISTANCE));

        EclipseMod.LOGGER.info("End disc shatter started: {} islets, seed {}",
                layout.count(), layout.seed());
    }

    // --- debris (C7 animator school: tagged, in-memory driven, TTL-discarded) ---

    /**
     * One tumbling seam chunk. The entity NEVER moves (BD-STRUCT teleport ban): the
     * whole drift lives in the transformation's translation as a closed-form function
     * of {@link #age}, pushed as ONE interpolated keyframe every
     * {@value #DEBRIS_UPDATE_TICKS} ticks — the StructureFlightFx/SanctumOrbitals
     * transport, replacing the old per-tick {@code teleportTo} +
     * {@code teleport_duration} spam (and its per-tick position packets). Tumble is
     * angular-momentum-consistent: ONE fixed tilted axis and one fixed signed rate per
     * chunk, plus a slow precession of the pole around Y — never a re-rolled axis. All
     * parameters seed-mix off the spawn column, so replays shatter identically.
     * REPASS-BD: one or two chunks are STRAGGLERS — they cling to the break face, fall
     * up to {@value #STRAGGLER_LAG_TICKS}t behind, then hurry after the flock (a
     * monotonic closed-form time warp on the motion clock; see {@link #motionAge}).
     */
    private static final class Debris {
        final Display.BlockDisplay display;
        /** Fixed entity anchor (the seam surface point the chunk tore off from). */
        final Vec3 origin;
        /** Launch velocity (blocks/tick); the arc integrates gravity-lite on top. */
        final double vx;
        final double vy0;
        final double vz;
        final Vector3f spinAxis;
        /** Signed tumble rate (rad/tick); the sign never flips mid-flight. */
        final double spinRate;
        final double spinPhase;
        /** Pole precession rate around Y (rad/tick) — slow, per-chunk. */
        final double precessRate;
        final float baseScale;
        /** Straggler chunk: clings, lags {@value #STRAGGLER_LAG_TICKS}t, then catches up. */
        final boolean straggler;
        int age;
        /** Dissolve brightness steps fired (brightness snaps → few, coarse, in-motion). */
        int dissolveStage;

        Debris(Display.BlockDisplay display, Vec3 origin, double vx, double vy0, double vz,
                Vector3f spinAxis, double spinRate, double spinPhase, double precessRate,
                float baseScale, boolean straggler) {
            this.display = display;
            this.origin = origin;
            this.vx = vx;
            this.vy0 = vy0;
            this.vz = vz;
            this.spinAxis = spinAxis;
            this.spinRate = spinRate;
            this.spinPhase = spinPhase;
            this.precessRate = precessRate;
            this.baseScale = baseScale;
            this.straggler = straggler;
        }

        /**
         * The chunk's MOTION clock at real {@code age}: identity for the flock; for a
         * straggler, real age minus the lag envelope (smoothstep in over the cling,
         * hold, smoothstep out over the catch-up — monotonic by construction, identity
         * again past {@value #STRAGGLER_CATCHUP_END}t). Drift, tumble and precession
         * all read this clock; dissolve/TTL stay on real age.
         */
        double motionAge(int age) {
            if (!this.straggler) {
                return age;
            }
            double lag;
            if (age < STRAGGLER_CLING_END) {
                lag = smooth(age / (double) STRAGGLER_CLING_END);
            } else if (age < STRAGGLER_HOLD_END) {
                lag = 1.0D;
            } else if (age < STRAGGLER_CATCHUP_END) {
                lag = 1.0D - smooth((age - STRAGGLER_HOLD_END)
                        / (double) (STRAGGLER_CATCHUP_END - STRAGGLER_HOLD_END));
            } else {
                lag = 0.0D;
            }
            return age - STRAGGLER_LAG_TICKS * lag;
        }

        private static double smooth(double x) {
            return x * x * (3.0D - 2.0D * x);
        }

        /** World-space chunk-center of the drift arc at {@code age} motion ticks (closed form). */
        Vec3 driftAt(double age) {
            return new Vec3(this.origin.x + this.vx * age,
                    this.origin.y + fallAt(age),
                    this.origin.z + this.vz * age);
        }

        /** Fall offset: parabola under gravity-lite, capped at the terminal speed. */
        double fallAt(double age) {
            double tTerm = (DEBRIS_TERMINAL_FALL - this.vy0) / DEBRIS_GRAVITY;
            if (age <= tTerm) {
                return this.vy0 * age + 0.5D * DEBRIS_GRAVITY * age * age;
            }
            return this.vy0 * tTerm + 0.5D * DEBRIS_GRAVITY * tTerm * tTerm
                    + DEBRIS_TERMINAL_FALL * (age - tTerm);
        }
    }

    /**
     * FIN-2 field wave: the seam grid scan (denser than before — stride 4, 80 % accept)
     * QUEUES up to {@value #DEBRIS_FIELD_CAP} tumbling chunks; roughly a third of the
     * columns shed a SECOND smaller shard a few blocks higher with a livelier launch
     * (the "crumble further" read). Nothing spawns here — {@link #drainPending} births
     * the wave {@value #DEBRIS_SPAWN_PER_TICK}/t, so the population climbs as a swelling
     * cloud instead of one single-tick spike.
     */
    private static void queueFieldDebris(Layout layout) {
        long seed = layout.seed();
        int reach = DiscProfile.END_DISC_RADIUS;
        int queued = 0;
        for (int x = -reach; x <= reach && queued < DEBRIS_FIELD_CAP; x += 4) {
            for (int z = -reach; z <= reach && queued < DEBRIS_FIELD_CAP; z += 4) {
                int bx = DiscProfile.END_DISC_CENTER_X + x;
                int bz = DiscProfile.END_DISC_CENTER_Z + z;
                if (!EndDiscGeometry.footprintContains(bx, bz)
                        || !layout.sample(bx, bz).seam()
                        || to01(mix(seed ^ SALT_DEBRIS, bx, bz)) > 0.80D) {
                    continue;
                }
                int y = EndDiscGeometry.surfaceYAt(bx, bz) + 1;
                Block block = to01(mix(seed ^ SALT_DEBRIS, bx, bz + 1)) < 0.2D
                        ? Blocks.OBSIDIAN : Blocks.END_STONE;
                double dist = Math.max(1.0D, Math.sqrt((double) x * x + (double) z * z));
                double jitter = to01(mix(seed ^ SALT_DEBRIS, bx + 1, bz)) - 0.5D;
                // Tumble identity: one fixed tilted axis, one fixed signed rate, one
                // slow precession — all seed-mixed off the spawn column.
                double h1 = to01(mix(seed ^ SALT_DEBRIS, bx, bz + 2));
                double h2 = to01(mix(seed ^ SALT_DEBRIS, bx, bz + 3));
                double h3 = to01(mix(seed ^ SALT_DEBRIS, bx, bz + 4));
                Vector3f axis = new Vector3f(
                        (float) (h1 * 2.0D - 1.0D), 1.0F,
                        (float) (h2 * 2.0D - 1.0D)).normalize();
                double spinRate = Math.toRadians(DEBRIS_SPIN_MIN_DEG
                        + (DEBRIS_SPIN_MAX_DEG - DEBRIS_SPIN_MIN_DEG) * h3)
                        * (jitter < 0.0D ? -1.0D : 1.0D);
                double precessRate = Math.toRadians(DEBRIS_PRECESS_MIN_DEG
                        + (DEBRIS_PRECESS_MAX_DEG - DEBRIS_PRECESS_MIN_DEG) * h1);
                // REPASS-BD stragglers: fixed queue ordinals — the seed-hashed grid scan
                // is deterministic, so the same 1–2 columns straggle on every replay.
                boolean straggler = queued == STRAGGLER_ORDINAL_A || queued == STRAGGLER_ORDINAL_B;
                Vec3 origin = new Vec3(bx + 0.5D, y, bz + 0.5D);
                double vx = x / dist * 0.10D + jitter * 0.06D;
                double vz = z / dist * 0.10D - jitter * 0.06D;
                PENDING.addLast(new PendingSpawn(origin, vx, 0.06D, vz,
                        axis, spinRate, h3 * Math.PI * 2.0D, precessRate,
                        (float) (0.70D + 0.45D * h2), straggler, block));
                queued++;
                // "Crumble chunks further": a second, smaller shard above the break face.
                if (h1 < 0.34D && queued < DEBRIS_FIELD_CAP) {
                    PENDING.addLast(new PendingSpawn(
                            origin.add(jitter * 1.5D, 2.0D + h2 * 3.0D, -jitter * 1.5D),
                            vx * 1.6D, 0.16D, vz * 1.6D,
                            axis, -spinRate, h2 * Math.PI * 2.0D, precessRate,
                            (float) (0.30D + 0.30D * h3), false, block));
                    queued++;
                }
            }
        }
        EclipseMod.LOGGER.info("EndShatterSequence: {} field debris chunk(s) queued (budget {}/t, hard cap {})",
                queued, DEBRIS_SPAWN_PER_TICK, DEBRIS_HARD_CAP);
    }

    /**
     * FIN-2 crack vent: a fountain of small display chunks erupting OUT of one opened
     * fissure — end stone, obsidian, and the odd purpur shard (the buried structures
     * bleeding through). Rising launches (+0.22…+0.52/t) arc over gravity-lite and fall
     * to the void on the shared TTL. Queued, never spawned directly, so the global
     * spawn budget and the hard cap always hold.
     */
    private static void queueCrackBurst(Vec3 flash, int count, long salt) {
        for (int i = 0; i < count; i++) {
            double h1 = to01(mix(salt, i, 1L));
            double h2 = to01(mix(salt, i, 2L));
            double h3 = to01(mix(salt, i, 3L));
            double angle = h1 * Math.PI * 2.0D;
            double speed = 0.06D + h2 * 0.12D;
            Vector3f axis = new Vector3f((float) (h2 * 2.0D - 1.0D), 1.0F,
                    (float) (h3 * 2.0D - 1.0D)).normalize();
            double spinRate = Math.toRadians(DEBRIS_SPIN_MIN_DEG
                    + (DEBRIS_SPIN_MAX_DEG - DEBRIS_SPIN_MIN_DEG) * h3)
                    * (h1 < 0.5D ? -1.0D : 1.0D);
            Block block = h3 < 0.12D ? Blocks.OBSIDIAN
                    : h3 < 0.30D ? Blocks.PURPUR_BLOCK : Blocks.END_STONE;
            PENDING.addLast(new PendingSpawn(
                    flash.add(h2 * 2.0D - 1.0D, 0.0D, h3 * 2.0D - 1.0D),
                    Math.cos(angle) * speed,
                    0.22D + h2 * 0.30D,
                    Math.sin(angle) * speed,
                    axis, spinRate, h1 * Math.PI * 2.0D,
                    Math.toRadians(DEBRIS_PRECESS_MIN_DEG
                            + (DEBRIS_PRECESS_MAX_DEG - DEBRIS_PRECESS_MIN_DEG) * h2),
                    (float) (0.35D + 0.35D * h1), false, block));
        }
    }

    /**
     * Births at most {@value #DEBRIS_SPAWN_PER_TICK} queued spawns per tick. At the
     * {@value #DEBRIS_HARD_CAP} live ceiling the REST of the queue is dropped (logged)
     * — a bounded spectacle beats an unbounded backlog.
     */
    private static void drainPending(ServerLevel level) {
        int spawned = 0;
        while (!PENDING.isEmpty() && spawned < DEBRIS_SPAWN_PER_TICK) {
            if (DEBRIS.size() >= DEBRIS_HARD_CAP) {
                int dropped = PENDING.size();
                PENDING.clear();
                EclipseMod.LOGGER.info("EndShatterSequence: hard cap {} live displays reached — "
                        + "{} queued spawn(s) dropped", DEBRIS_HARD_CAP, dropped);
                return;
            }
            PendingSpawn spec = PENDING.pollFirst();
            Debris debris = new Debris(
                    new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level),
                    spec.origin(), spec.vx(), spec.vy0(), spec.vz(), spec.axis(),
                    spec.spinRate(), spec.spinPhase(), spec.precessRate(), spec.scale(),
                    spec.straggler());
            if (spawnDebrisDisplay(level, debris, spec.block())) {
                DEBRIS.add(debris);
                spawned++;
            }
        }
    }

    /**
     * Finishes spawning one tumbling chunk at its FIXED entity anchor — the drift lives
     * entirely in the transformation, so the entity's light sample and owning chunk
     * never change. Born already posed at t = 0 with interpolation duration 0.
     */
    private static boolean spawnDebrisDisplay(ServerLevel level, Debris debris, Block block) {
        Display.BlockDisplay display = debris.display;
        display.setBlockState(block.defaultBlockState());
        display.moveTo(debris.origin.x, debris.origin.y, debris.origin.z, 0.0F, 0.0F);
        display.addTag(DEBRIS_TAG);
        applyViewRange(display, DEBRIS_VIEW_RANGE); // distance culling — FIN-2 budget law
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(debrisPoseAt(debris, 0));
        // Registered BEFORE addFreshEntity: the join-time stray guard fires inside it.
        LIVE_DEBRIS.add(display.getUUID());
        if (level.addFreshEntity(display)) {
            return true;
        }
        LIVE_DEBRIS.remove(display.getUUID());
        return false;
    }

    /**
     * {@code Display.setViewRange} is private like the brightness setter — same
     * save-data round trip ({@code view_range} is a vanilla display save tag; the
     * CreditsSequence idiom).
     */
    private static void applyViewRange(Display.BlockDisplay display, float range) {
        CompoundTag data = display.saveWithoutId(new CompoundTag());
        data.putFloat("view_range", range);
        display.load(data);
    }

    /** Debris ember-trail clock + rotating sample cursor (CUT-END shot 3 presentation). */
    private static int debrisTrailClock;
    private static int debrisTrailCursor;

    private static void tickDebris() {
        boolean trailBurst = ++debrisTrailClock >= DEBRIS_TRAIL_INTERVAL_TICKS;
        int trailStart = 0;
        if (trailBurst) {
            debrisTrailClock = 0;
            trailStart = debrisTrailCursor % Math.max(1, DEBRIS.size());
            debrisTrailCursor += DEBRIS_TRAIL_SAMPLES;
        }
        int index = 0;
        Iterator<Debris> iterator = DEBRIS.iterator();
        while (iterator.hasNext()) {
            Debris debris = iterator.next();
            Display.BlockDisplay display = debris.display;
            int age = debris.age++;
            // The entity is anchored, so removal keys off the TTL (the dissolve has
            // shrunk the chunk out by then) or the drift arc sinking into the void fog
            // (the VISUAL arc — stragglers ride the warped motion clock).
            if (age >= DEBRIS_TTL_TICKS || display.isRemoved()
                    || debris.origin.y + debris.fallAt(debris.motionAge(age)) < 200.0D) {
                display.discard();
                LIVE_DEBRIS.remove(display.getUUID());
                iterator.remove();
                continue;
            }
            // One batched keyframe pass every DEBRIS_UPDATE_TICKS (all chunks share the
            // separation-beat spawn tick, so every push lands on one server tick). The
            // pushed pose is the one this window ENDS on — the client tween covers the
            // gap between keyframes; nothing is ever teleported.
            if (age % DEBRIS_UPDATE_TICKS == 0) {
                float dissolveT = dissolveT(age);
                if (dissolveT >= 0.67F && debris.dissolveStage < 2) {
                    debris.dissolveStage = 2;
                    DisplayBrightnessFx.set(display, 1, 3);
                } else if (dissolveT >= 0.34F && debris.dissolveStage < 1) {
                    debris.dissolveStage = 1;
                    DisplayBrightnessFx.set(display, 4, 8);
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(DEBRIS_UPDATE_TICKS);
                display.setTransformation(debrisPoseAt(debris, age + DEBRIS_UPDATE_TICKS));
            }
            // CUT-END shot 3: a rotating handful of the tumbling chunks sheds a one-shot
            // ember burst every DEBRIS_TRAIL_INTERVAL_TICKS — the "debris trail" read.
            // The burst rides the DRIFT ARC position (the entity anchor never moves).
            // The client-side BURST budget channel absorbs any excess silently.
            if (trailBurst && index >= trailStart && index < trailStart + DEBRIS_TRAIL_SAMPLES
                    && display.level() instanceof ServerLevel level) {
                Vec3 drift = debris.driftAt(debris.motionAge(age));
                PacketDistributor.sendToPlayersNear(level, null, drift.x, drift.y, drift.z,
                        FX_RANGE, new S2CQuasarPayload(SLAM_DEBRIS, drift));
            }
            index++;
        }
    }

    /** Dissolve progress at {@code age}: 0 until the last 20 % of the TTL, then 0→1. */
    private static float dissolveT(int age) {
        float start = DEBRIS_TTL_TICKS * (1.0F - DEBRIS_DISSOLVE_FRACTION);
        return Mth.clamp((age - start) / (DEBRIS_TTL_TICKS - start), 0.0F, 1.0F);
    }

    /**
     * Absolute debris pose at {@code age} ticks after spawn: outward drift arc (launch
     * velocity + gravity-lite, terminal-capped), tumble about the slowly precessing
     * fixed axis, and the last-20 % dissolve shrink (ease-in, floored at 3 % — a zero
     * scale degenerates). Translation re-centers the scaled {@code [0,1]³} block on the
     * drift point through the rotation (the SanctumOrbitals T·L·S math). Drift, tumble
     * and precession read the (possibly straggler-warped) motion clock; the dissolve
     * reads REAL age, so every chunk fades on the shared TTL beat.
     */
    private static Transformation debrisPoseAt(Debris debris, int age) {
        float dissolveT = dissolveT(age);
        double motionAge = debris.motionAge(age);
        float scale = debris.baseScale * (1.0F - 0.97F * dissolveT * dissolveT);
        Vector3f axis = new Vector3f(debris.spinAxis)
                .rotateY((float) (debris.precessRate * motionAge));
        Quaternionf rotation = new Quaternionf().rotationAxis(
                (float) (debris.spinPhase + debris.spinRate * motionAge), axis);
        Vec3 drift = debris.driftAt(motionAge);
        Vector3f translation = new Vector3f(
                (float) (drift.x - debris.origin.x),
                (float) (drift.y - debris.origin.y),
                (float) (drift.z - debris.origin.z));
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        translation.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /**
     * Boot sweep of orphaned debris (a crash mid-cinematic persists the displays). Only
     * reaches chunks loaded at {@code ServerStartedEvent} — strays in still-unloaded
     * chunks are caught by the {@link #onEntityJoin} guard when their chunk loads.
     */
    private static void sweepDebris(ServerLevel overworld) {
        AABB bounds = new AABB(
                DiscProfile.END_DISC_CENTER_X - DiscProfile.END_DISC_RADIUS - 32,
                200.0D,
                DiscProfile.END_DISC_CENTER_Z - DiscProfile.END_DISC_RADIUS - 32,
                DiscProfile.END_DISC_CENTER_X + DiscProfile.END_DISC_RADIUS + 32,
                overworld.getMaxBuildHeight(),
                DiscProfile.END_DISC_CENTER_Z + DiscProfile.END_DISC_RADIUS + 32);
        List<Entity> orphans = overworld.getEntities((Entity) null, bounds,
                entity -> entity.getTags().contains(DEBRIS_TAG));
        orphans.forEach(Entity::discard);
    }

    // --- the budgeted carve pass (EndDiscService.Job shape, subtractive) ---

    private static final class Job {
        private final ServerLevel level;
        private final ShatterData state;
        private final Layout layout;
        private final List<ChunkPos> chunks;
        private final long totalOperations;
        private long cursor;
        private int startDelay;
        private int crackClock;

        Job(ServerLevel level, ShatterData state, int startDelay) {
            this.level = level;
            this.state = state;
            this.layout = layout();
            this.chunks = discChunks();
            this.totalOperations = (long) this.chunks.size() * 256L;
            this.cursor = Math.min(state.cursor(), this.totalOperations);
            this.startDelay = startDelay;
        }

        void tick() {
            if (this.startDelay > 0) {
                this.startDelay--;
                return;
            }
            if (++this.crackClock >= CRACK_INTERVAL_TICKS) {
                this.crackClock = 0;
                playCrack();
            }
            long started = System.nanoTime();
            int budget = EndConfig.current().blockBudgetPerTick();
            int operations = 0;
            if (this.cursor < this.totalOperations) {
                long chunkIndex = this.cursor / 256L;
                LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(
                        this.level,
                        this.chunks.get((int) chunkIndex).x,
                        this.chunks.get((int) chunkIndex).z);
                while (this.cursor < this.totalOperations
                        && this.cursor / 256L == chunkIndex
                        && operations < budget
                        && System.nanoTime() - started < TICK_NANOS) {
                    shatterColumn(chunk, (int) (this.cursor & 255L));
                    this.cursor++;
                    operations++;
                }
                if (this.cursor / 256L != chunkIndex || this.cursor == this.totalOperations) {
                    Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
                    BudgetedBlockWriter.relightAndResend(this.level, chunk);
                    healBuriedPlayers(chunk);
                    this.state.setCursor(this.cursor);
                }
            }
            if (this.cursor >= this.totalOperations) {
                complete();
            }
        }

        private void playCrack() {
            int i = 1 + (int) Math.floorMod(this.cursor / 256L, Math.max(1L, this.layout.count() - 1L));
            int x = DiscProfile.END_DISC_CENTER_X + (int) this.layout.siteX()[i];
            int z = DiscProfile.END_DISC_CENTER_Z + (int) this.layout.siteZ()[i];
            BlockPos pos = new BlockPos(x, EndDiscGeometry.surfaceYAt(x, z), z);
            this.level.playSound(null, pos, EclipseSounds.EVENT_END_SHATTER_CRACK.get(),
                    SoundSource.HOSTILE, 3.0F, 0.9F + (i % 3) * 0.1F);
            // FIN-2: the carve's cracks keep VENTING through the whole pass — a small
            // budgeted fountain rides every stinger (dropped silently at the hard cap).
            queueCrackBurst(new Vec3(pos.getX() + 0.5D, pos.getY() + 1.0D, pos.getZ() + 0.5D),
                    CARVE_BURST_PER_CRACK, mix(this.layout.seed() ^ SALT_BURST, this.cursor, 17L));
        }

        /** Seam columns clear; islet columns translate by dy (copy-then-clear). */
        private void shatterColumn(LevelChunk chunk, int localIndex) {
            int localX = localIndex & 15;
            int localZ = localIndex >>> 4;
            int x = chunk.getPos().getMinBlockX() + localX;
            int z = chunk.getPos().getMinBlockZ() + localZ;
            if (!EndDiscGeometry.footprintContains(x, z)) {
                return;
            }
            Sample sample = this.layout.sample(x, z);
            int dy = sample.seam() ? 0 : sample.dy();
            if (!sample.seam() && dy == 0) {
                return; // Podium islet (and any zero-offset islet) is untouched.
            }
            int minY = EndDiscGeometry.MIN_Y;
            int maxY = EndDiscGeometry.MAX_Y;
            BlockState[] band = new BlockState[maxY - minY + 1];
            boolean blockEntities = false;
            for (int y = minY; y <= maxY; y++) {
                LevelChunkSection section = chunk.getSection(chunk.getSectionIndex(y));
                band[y - minY] = section.getBlockState(localX, y & 15, localZ);
                blockEntities |= band[y - minY].hasBlockEntity();
            }
            if (blockEntities) {
                shatterBlockEntityColumn(x, z, band, sample.seam(), dy);
                return;
            }
            BlockState air = Blocks.AIR.defaultBlockState();
            int clearMin = minY + Math.min(0, dy);
            int clearMax = maxY + Math.max(0, dy);
            for (int y = clearMin; y <= clearMax; y++) {
                LevelChunkSection section = chunk.getSection(chunk.getSectionIndex(y));
                section.setBlockState(localX, y & 15, localZ, air, false);
            }
            if (!sample.seam()) {
                for (int y = minY; y <= maxY; y++) {
                    BlockState kept = band[y - minY];
                    if (!kept.isAir()) {
                        LevelChunkSection section = chunk.getSection(chunk.getSectionIndex(y + dy));
                        section.setBlockState(localX, (y + dy) & 15, localZ, kept, false);
                    }
                }
            }
            chunk.setUnsaved(true);
        }

        /**
         * The rare mini-city chest columns go through {@code level.setBlock} so block
         * entities detach/attach cleanly, and their saved data (loot table + seed) rides
         * along to the shifted position.
         */
        private void shatterBlockEntityColumn(int x, int z, BlockState[] band, boolean seam, int dy) {
            int minY = EndDiscGeometry.MIN_Y;
            int maxY = EndDiscGeometry.MAX_Y;
            HolderLookup.Provider registries = this.level.registryAccess();
            CompoundTag[] blockEntityData = new CompoundTag[band.length];
            BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
            for (int y = minY; y <= maxY; y++) {
                if (band[y - minY].hasBlockEntity()) {
                    BlockEntity blockEntity = this.level.getBlockEntity(cursor.set(x, y, z));
                    if (blockEntity != null) {
                        blockEntityData[y - minY] = blockEntity.saveWithFullMetadata(registries);
                    }
                }
            }
            BlockState air = Blocks.AIR.defaultBlockState();
            for (int y = minY + Math.min(0, dy); y <= maxY + Math.max(0, dy); y++) {
                this.level.setBlock(cursor.set(x, y, z), air,
                        Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
            }
            if (seam) {
                return;
            }
            for (int y = minY; y <= maxY; y++) {
                BlockState kept = band[y - minY];
                if (kept.isAir()) {
                    continue;
                }
                this.level.setBlock(cursor.set(x, y + dy, z), kept,
                        Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
                CompoundTag data = blockEntityData[y - minY];
                if (data != null) {
                    BlockEntity moved = this.level.getBlockEntity(cursor);
                    if (moved != null) {
                        moved.loadWithComponents(data, registries);
                        moved.setChanged();
                    }
                }
            }
        }

        /** A risen islet must never entomb a bystander — pop them onto the new surface. */
        private void healBuriedPlayers(LevelChunk chunk) {
            ChunkPos pos = chunk.getPos();
            for (ServerPlayer player : this.level.players()) {
                if (player.getBlockX() >> 4 != pos.x || player.getBlockZ() >> 4 != pos.z
                        || player.getY() < EndDiscGeometry.MIN_Y + DY_MIN
                        || player.isSpectator()) {
                    continue;
                }
                BlockPos feet = player.blockPosition();
                if (this.level.getBlockState(feet).isSuffocating(this.level, feet)
                        || this.level.getBlockState(feet.above()).isSuffocating(this.level, feet.above())) {
                    int top = this.level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                            feet.getX(), feet.getZ());
                    player.teleportTo(player.getX(), top + 1.0D, player.getZ());
                    player.fallDistance = 0.0F;
                }
            }
        }

        private void complete() {
            this.state.markComplete();
            this.state.setCursor(this.totalOperations);
            activeJob = null;
            enqueueCityKits(this.level, this.layout);
            // FIN-2 post-fight population: the fight is long over by the time the carve
            // completes — endermen reclaim the isles. (The old low sky-rubble clumps moved
            // to the F-047 PHASE_SKY_BITS, which places them over the GROUND instead.)
            spawnEndermen(this.level, this.layout);
            // F-047: the archipelago is now a stop on the way down. Arm the crash finale
            // one loot window from here; the poll in onServerTick fires it.
            this.state.armCrash(this.level.getGameTime() + CRASH_DELAY_TICKS);
            // CUT-END shot 4 (settle): the carve pass finishing IS the isles coming to
            // rest — a low thud + one soft long shake mark it for anyone on the disc
            // (the low-FREQUENCY rumble shaping lives in the cutscene JSON's shake
            // events; S2CShakePayload carries strength/ticks only).
            BlockPos settleCenter = new BlockPos(EndConfig.current().centerX(),
                    EndDiscGeometry.surfaceYAt(EndConfig.current().centerX(),
                            EndConfig.current().centerZ()),
                    EndConfig.current().centerZ());
            this.level.playSound(null, settleCenter, EclipseSounds.EVENT_RIFT_THUD.get(),
                    SoundSource.HOSTILE, 3.0F, 0.6F);
            PacketDistributor.sendToPlayersInDimension(this.level, S2CShakePayload.shake(0.45F, 45));
            this.level.getServer().getPlayerList().broadcastSystemMessage(
                    Component.translatable("announce.eclipse.end.shatter_isles"), false);
            EclipseMod.LOGGER.info("End disc shatter complete: {} chunks re-carved into {} islets",
                    this.chunks.size(), this.layout.count());
        }
    }

    /** Same chunk set the materialization writer sweeps (footprint + margin). */
    private static List<ChunkPos> discChunks() {
        EndConfig.Snapshot config = EndConfig.current();
        int margin = 8;
        int minChunkX = Math.floorDiv(config.centerX() - config.radius() - margin, 16);
        int maxChunkX = Math.floorDiv(config.centerX() + config.radius() + margin, 16);
        int minChunkZ = Math.floorDiv(config.centerZ() - config.radius() - margin, 16);
        int maxChunkZ = Math.floorDiv(config.centerZ() + config.radius() + margin, 16);
        List<ChunkPos> chunks = new ArrayList<>();
        for (int chunkX = minChunkX; chunkX <= maxChunkX; chunkX++) {
            for (int chunkZ = minChunkZ; chunkZ <= maxChunkZ; chunkZ++) {
                chunks.add(new ChunkPos(chunkX, chunkZ));
            }
        }
        return List.copyOf(chunks);
    }

    // --- end-city kits on the three largest outer islets ---

    /**
     * Ranks outer islets by sampled cell area (pure math, stride 4) and enqueues the
     * two towers + the end-ship on the top three, anchored at each islet's site point
     * on its post-shatter surface. The registry broadcast IS the rift reveal.
     */
    private static void enqueueCityKits(ServerLevel level, Layout layout) {
        int count = layout.count();
        int[] area = new int[count];
        int reach = DiscProfile.END_DISC_RADIUS;
        for (int x = -reach; x <= reach; x += 4) {
            for (int z = -reach; z <= reach; z += 4) {
                int bx = DiscProfile.END_DISC_CENTER_X + x;
                int bz = DiscProfile.END_DISC_CENTER_Z + z;
                if (!EndDiscGeometry.footprintContains(bx, bz)) {
                    continue;
                }
                Sample sample = layout.sample(bx, bz);
                if (!sample.seam()) {
                    area[sample.islet()]++;
                }
            }
        }
        List<Integer> ranked = new ArrayList<>();
        for (int i = 1; i < count; i++) {
            ranked.add(i);
        }
        ranked.sort((a, b) -> Integer.compare(area[b], area[a]));
        String[] siteIds = {EndCityKit.SITE_TOWER_A, EndCityKit.SITE_TOWER_B, EndCityKit.SITE_SHIP};
        int[] footprints = {13, 11, 19};
        for (int rank = 0; rank < Math.min(3, ranked.size()); rank++) {
            int islet = ranked.get(rank);
            int x = DiscProfile.END_DISC_CENTER_X + (int) Math.round(layout.siteX()[islet]);
            int z = DiscProfile.END_DISC_CENTER_Z + (int) Math.round(layout.siteZ()[islet]);
            int y = EndDiscGeometry.surfaceYAt(x, z) + layout.dy()[islet];
            StructurePendingRegistry.enqueue(new PendingSite(siteIds[rank], EndCityKit.STRUCTURE_ID,
                    DiscProfile.OVERWORLD.name(), new BlockPos(x, y, z),
                    KIT_STAGE, footprints[rank], level.getGameTime()));
        }
    }

    /** Stage recorded on the kit rows (the disc window's stage — erase forgets them). */
    private static final int KIT_STAGE = 3;

    // --- FIN-2/FIN-3 post-fight population (runs once from the carve completion) ---

    /**
     * FIN-2: endermen spawn ON the isles — only AFTER the fight, guaranteed by running
     * from the carve completion (the dragon-victory listener started all of this).
     * {@value #ENDERMEN_PER_ISLET} per outer islet, surface-snapped via heightmap;
     * seam/void columns (no floor) are skipped, so a partial islet just gets fewer.
     */
    private static void spawnEndermen(ServerLevel level, Layout layout) {
        long seed = layout.seed() ^ SALT_ENDERMEN;
        int spawned = 0;
        for (int i = 1; i < layout.count(); i++) {
            for (int e = 0; e < ENDERMEN_PER_ISLET; e++) {
                double angle = to01(mix(seed, i, e * 3L)) * Math.PI * 2.0D;
                double dist = 3.0D + to01(mix(seed, i, e * 3L + 1L)) * 12.0D;
                int x = DiscProfile.END_DISC_CENTER_X
                        + (int) Math.round(layout.siteX()[i] + Math.cos(angle) * dist);
                int z = DiscProfile.END_DISC_CENTER_Z
                        + (int) Math.round(layout.siteZ()[i] + Math.sin(angle) * dist);
                int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING, x, z);
                if (y < EndDiscGeometry.MIN_Y + DY_MIN) {
                    continue; // seam/void column — nothing to stand on
                }
                if (EntityType.ENDERMAN.spawn(level, new BlockPos(x, y, z),
                        MobSpawnType.EVENT) != null) {
                    spawned++;
                }
            }
        }
        EclipseMod.LOGGER.info("EndShatterSequence: {} enderman(s) risen on the shattered isles (post-fight)",
                spawned);
    }

    // --- F-047 phase 1: the staggered crash ----------------------------------------

    /** Outer islets in fall order: the far ones let go first, the podium goes last. */
    private static List<Integer> crashOrder(Layout layout) {
        List<Integer> order = new ArrayList<>();
        for (int i = 1; i < layout.count(); i++) {
            order.add(i);
        }
        order.sort(Comparator.comparingDouble(
                islet -> -Math.hypot(layout.siteX()[islet], layout.siteZ()[islet])));
        return order;
    }

    /** Enters {@link #PHASE_CRASH}: one announcement, then the passes run themselves. */
    private static void beginCrash(ServerLevel level, ShatterData state) {
        state.setPhase(PHASE_CRASH);
        state.setCrashPass(0);
        state.setRazeCursor(0L);
        level.getServer().getPlayerList().broadcastSystemMessage(
                Component.translatable("announce.eclipse.end.crash_begins"), false);
        for (ServerPlayer player : level.players()) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.caption.end_crash.begins", 100, S2CCaptionPayload.STYLE_SUBTITLE));
            player.playNotifySound(EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                    SoundSource.MASTER, 1.2F, 0.7F);
        }
        graceSkyPlayers(level);
        PacketDistributor.sendToPlayersInDimension(level, S2CShakePayload.shake(1.0F, 60));
        EclipseMod.LOGGER.info("EndShatterSequence: crash finale started ({} islets to fall)",
                crashOrder(layout()).size());
    }

    /**
     * The crash pulls the floor out from under anyone still on the isles — the beat-0
     * safety net the shatter itself grants, re-stamped at the head of every islet pass so
     * a watcher on the LAST islet is as covered as one on the first.
     */
    private static void graceSkyPlayers(ServerLevel level) {
        for (ServerPlayer player : level.players()) {
            if (player.getY() > GRACE_MIN_Y && !player.isSpectator()) {
                player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                        GRACE_TICKS, 0, false, false, true));
                SkyLauncher.grantFallGrace(player, GRACE_TICKS);
            }
        }
    }

    /** Arms the raze pass of the current islet and launches its visible fall. */
    private static void startCrashPass(ServerLevel level, ShatterData state) {
        graceSkyPlayers(level);
        Layout layout = layout();
        List<Integer> order = crashOrder(layout);
        int pass = state.crashPass();
        if (pass >= order.size()) {
            state.setPhase(PHASE_CORE);
            return;
        }
        int islet = order.get(pass);
        activePass = new RazePass(level, state, islet);
        // The visible cluster: it leaves the islet's sky position and lands on the ground
        // impact site. Purely cosmetic — a restart drops it, the heap still lands.
        BlockPos impact = impactSite(level, layout, islet);
        double sx = DiscProfile.END_DISC_CENTER_X + layout.siteX()[islet];
        double sz = DiscProfile.END_DISC_CENTER_Z + layout.siteZ()[islet];
        Vec3 from = new Vec3(sx,
                EndDiscGeometry.surfaceYAt((int) sx, (int) sz) + layout.dy()[islet] + 2.0D, sz);
        EndIslandCrashFx.crash(level, from, Vec3.atCenterOf(impact), CRASH_FALL_TICKS,
                mix(layout.seed() ^ SALT_CRASH, islet, 0L));
        impactDueTick = level.getGameTime() + CRASH_FALL_TICKS;
        level.playSound(null, BlockPos.containing(from),
                EclipseSounds.EVENT_END_SHATTER_CRACK.get(), SoundSource.HOSTILE, 4.0F, 0.7F);
        PacketDistributor.sendToPlayersNear(level, null, from.x, from.y, from.z, FX_RANGE,
                new S2CFxEventPayload(FxCues.CUE_END_CRACK, from, 0.0F, 0.0F));
        EclipseMod.LOGGER.info("EndShatterSequence: islet {} ({}/{}) falling towards {}",
                islet, pass + 1, order.size(), impact.toShortString());
    }

    /**
     * The landing of islet pass {@code pass}: impact FX plus the REAL ground rubble heap.
     * Idempotent through the persisted impact mask, so a resume can back-fill it silently.
     */
    private static void landIslet(ServerLevel level, ShatterData state, int pass) {
        Layout layout = layout();
        List<Integer> order = crashOrder(layout);
        if (pass < 0 || pass >= order.size() || state.impactDone(pass)) {
            return;
        }
        int islet = order.get(pass);
        BlockPos impact = impactSite(level, layout, islet);
        RazePass live = activePass;
        List<RescuedBlock> loot = live != null && live.islet == islet
                ? live.drainRescued() : List.of();
        int placed = placeGroundHeap(level, impact, layout.seed() ^ SALT_RUBBLE, islet, loot);
        state.markImpactDone(pass);
        // Impact read: dust column, explosion flash, thud + a short local shake.
        level.sendParticles(ParticleTypes.EXPLOSION_EMITTER,
                impact.getX() + 0.5D, impact.getY() + 1.0D, impact.getZ() + 0.5D,
                3, 3.0D, 1.0D, 3.0D, 0.0D);
        level.sendParticles(ParticleTypes.LARGE_SMOKE,
                impact.getX() + 0.5D, impact.getY() + 1.5D, impact.getZ() + 0.5D,
                90, 5.0D, 2.0D, 5.0D, 0.05D);
        level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK,
                        Blocks.END_STONE.defaultBlockState()),
                impact.getX() + 0.5D, impact.getY() + 1.0D, impact.getZ() + 0.5D,
                120, 4.0D, 1.5D, 4.0D, 0.35D);
        level.playSound(null, impact, EclipseSounds.EVENT_RIFT_THUD.get(),
                SoundSource.HOSTILE, 4.0F, 0.5F);
        level.playSound(null, impact, SoundEvents.GENERIC_EXPLODE.value(),
                SoundSource.HOSTILE, 4.0F, 0.6F);
        PacketDistributor.sendToPlayersNear(level, null,
                impact.getX(), impact.getY(), impact.getZ(), FX_RANGE,
                S2CShakePayload.shake(1.4F, 30));
        EclipseMod.LOGGER.info(
                "EndShatterSequence: islet {} hit the ground at {} ({} rubble block(s), {} loot rescued)",
                islet, impact.toShortString(), placed, loot.size());
    }

    /**
     * Ground impact site of one islet: its own bearing, pushed
     * {@value #IMPACT_SPREAD_FACTOR}× further out and clamped into
     * {@value #IMPACT_MIN_RADIUS}…{@value #IMPACT_MAX_RADIUS} so the heaps land under the
     * old island but never inside the sanctum's protected cylinder. Pure except for the
     * heightmap read (the chunk is ticketed first).
     */
    private static BlockPos impactSite(ServerLevel level, Layout layout, int islet) {
        double sx = layout.siteX()[islet];
        double sz = layout.siteZ()[islet];
        double dist = Math.hypot(sx, sz);
        double angle = dist < 1.0E-3D
                ? to01(mix(layout.seed() ^ SALT_IMPACT, islet, 1L)) * Math.PI * 2.0D
                : Math.atan2(sz, sx);
        double reach = Mth.clamp(dist * IMPACT_SPREAD_FACTOR, IMPACT_MIN_RADIUS, IMPACT_MAX_RADIUS);
        int x = DiscProfile.END_DISC_CENTER_X + (int) Math.round(Math.cos(angle) * reach);
        int z = DiscProfile.END_DISC_CENTER_Z + (int) Math.round(Math.sin(angle) * reach);
        BudgetedBlockWriter.loadWithTicket(level, x >> 4, z >> 4);
        return new BlockPos(x, level.getHeight(Heightmap.Types.MOTION_BLOCKING, x, z), z);
    }

    /**
     * F-047 (d): one small REAL end-stone/obsidian heap at an impact site — the "Brocken"
     * left over once the sky is empty. Air-only ellipsoid writes on top of the local
     * surface (so nothing existing is destroyed), skipping the protected sanctum cylinder,
     * with any rescued loot block entity re-seated on the crown.
     */
    private static int placeGroundHeap(ServerLevel level, BlockPos site, long seed, int islet,
            List<RescuedBlock> loot) {
        int radius = HEAP_MIN_RADIUS + (int) (to01(mix(seed, islet, 4L)) * HEAP_RADIUS_RANGE);
        int height = Math.max(2, radius - 1);
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int placed = 0;
        for (int dx = -radius; dx <= radius; dx++) {
            for (int dz = -radius; dz <= radius; dz++) {
                double planar = (double) (dx * dx + dz * dz) / (double) (radius * radius);
                if (planar > 1.0D) {
                    continue;
                }
                int column = (int) Math.round(height * (1.0D - planar)
                        + to01(mix(seed, site.getX() + dx, site.getZ() + dz)) * 1.5D);
                for (int dy = 0; dy <= column; dy++) {
                    cursor.set(site.getX() + dx, site.getY() + dy, site.getZ() + dz);
                    if (SanctumProtection.isProtected(level, cursor)
                            || !level.getBlockState(cursor).isAir()) {
                        continue;
                    }
                    BlockState state = to01(mix(seed, cursor.getX(),
                            (long) cursor.getY() * 31L + cursor.getZ())) < 0.16D
                            ? Blocks.OBSIDIAN.defaultBlockState()
                            : Blocks.END_STONE.defaultBlockState();
                    level.setBlock(cursor, state, Block.UPDATE_ALL);
                    placed++;
                }
            }
        }
        seatRescuedLoot(level, site, height, loot);
        return placed;
    }

    /**
     * Re-seats the loot containers a falling islet was still carrying, in a ring on top of
     * the fresh heap — the End-city caches survive the crash instead of being deleted with
     * the sky. Contents ride along through the saved block-entity NBT.
     */
    private static void seatRescuedLoot(ServerLevel level, BlockPos site, int height,
            List<RescuedBlock> loot) {
        if (loot.isEmpty()) {
            return;
        }
        HolderLookup.Provider registries = level.registryAccess();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int i = 0; i < loot.size(); i++) {
            double angle = i * (Math.PI * 2.0D / loot.size());
            cursor.set(site.getX() + (int) Math.round(Math.cos(angle) * 2.0D),
                    site.getY() + height + 1,
                    site.getZ() + (int) Math.round(Math.sin(angle) * 2.0D));
            if (SanctumProtection.isProtected(level, cursor)) {
                continue;
            }
            RescuedBlock rescued = loot.get(i);
            level.setBlock(cursor, rescued.state(), Block.UPDATE_ALL);
            BlockEntity seated = level.getBlockEntity(cursor);
            if (seated != null && rescued.data() != null) {
                seated.loadWithComponents(rescued.data(), registries);
                seated.setChanged();
            }
        }
    }

    // --- F-047 phase 2: the middle island + the guarantee that the sky is empty ------

    /** Arms the final full-band sweep (podium islet, exit portal, every leftover sliver). */
    private static void startCorePass(ServerLevel level, ShatterData state) {
        // The egg is the hard-wired day-14 catalyst: note whether it is still up there
        // BEFORE the sweep eats it, so the completion can re-seat it on the ground.
        if (!state.eggRescued() && findPodiumEgg(level) != null) {
            state.markEggPending();
        }
        activePass = new RazePass(level, state, RazePass.ALL_ISLETS);
        level.getServer().getPlayerList().broadcastSystemMessage(
                Component.translatable("announce.eclipse.end.crash_core"), false);
        EclipseMod.LOGGER.info("EndShatterSequence: razing the middle island and the last slivers");
    }

    /** Finishes the core sweep: egg rescue, stranded-mob sweep, on to the sky remnants. */
    private static void completeCorePass(ServerLevel level, ShatterData state) {
        if (state.eggPending()) {
            BlockPos heap = firstHeapCrown(level);
            if (heap != null) {
                level.setBlock(heap, Blocks.DRAGON_EGG.defaultBlockState(), Block.UPDATE_ALL);
                level.getServer().getPlayerList().broadcastSystemMessage(
                        Component.translatable("announce.eclipse.end.egg_fell"), false);
                EclipseMod.LOGGER.info("EndShatterSequence: dragon egg re-seated at {} "
                        + "(day-14 finale catalyst — it must survive the crash)", heap.toShortString());
            }
            state.markEggRescued();
        }
        // Shulkers and endermen do not fall; anything still floating in the emptied band
        // would read as "the End is still up there".
        AABB band = new AABB(
                DiscProfile.END_DISC_CENTER_X - DiscProfile.END_DISC_RADIUS - 16, RAZE_MIN_Y,
                DiscProfile.END_DISC_CENTER_Z - DiscProfile.END_DISC_RADIUS - 16,
                DiscProfile.END_DISC_CENTER_X + DiscProfile.END_DISC_RADIUS + 16, RAZE_MAX_Y,
                DiscProfile.END_DISC_CENTER_Z + DiscProfile.END_DISC_RADIUS + 16);
        int swept = 0;
        for (Entity entity : level.getEntities((Entity) null, band,
                candidate -> candidate.getType() == EntityType.SHULKER
                        || candidate.getType() == EntityType.ENDERMAN
                        || candidate.getType() == EntityType.END_CRYSTAL)) {
            entity.discard();
            swept++;
        }
        state.setPhase(PHASE_SKY_BITS);
        EclipseMod.LOGGER.info("EndShatterSequence: middle island gone; {} stranded End entity(s) swept",
                swept);
    }

    /** The dragon-egg block on the podium pedestal, or {@code null} if it is already gone. */
    @Nullable
    private static BlockPos findPodiumEgg(ServerLevel level) {
        int cx = EndConfig.current().centerX();
        int cz = EndConfig.current().centerZ();
        BudgetedBlockWriter.loadWithTicket(level, cx >> 4, cz >> 4);
        int surface = EndDiscGeometry.surfaceYAt(cx, cz);
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dy = 0; dy <= 10; dy++) {
            if (level.getBlockState(cursor.set(cx, surface + dy, cz)).is(Blocks.DRAGON_EGG)) {
                return cursor.immutable();
            }
        }
        return null;
    }

    /** The crown of the first ground heap — where the rescued egg is put back. */
    @Nullable
    private static BlockPos firstHeapCrown(ServerLevel level) {
        Layout layout = layout();
        List<Integer> order = crashOrder(layout);
        if (order.isEmpty()) {
            return null;
        }
        BlockPos site = impactSite(level, layout, order.get(0));
        return new BlockPos(site.getX(),
                level.getHeight(Heightmap.Types.MOTION_BLOCKING, site.getX(), site.getZ()),
                site.getZ());
    }

    // --- F-047 phase 3: the low, far-apart sky remnants ------------------------------

    /**
     * Places one remnant clump per poll tick. Sites sit on one angular slice each (so no
     * two clumps can crowd together) at {@value #SKY_BIT_MIN_RADIUS}…{@value
     * #SKY_BIT_MIN_RADIUS}+{@value #SKY_BIT_RADIUS_RANGE} blocks from the map centre, and
     * only {@value #SKY_BIT_MIN_RISE}–{@value #SKY_BIT_MIN_RISE}+{@value
     * #SKY_BIT_RISE_RANGE} blocks over the LOCAL ground — a short pillar, not a tower.
     */
    private static void placeSkyBits(ServerLevel level, ShatterData state) {
        int index = state.skyBitCursor();
        if (index >= SKY_BIT_COUNT) {
            state.setPhase(PHASE_DONE);
            level.getServer().getPlayerList().broadcastSystemMessage(
                    Component.translatable("announce.eclipse.end.crash_done"), false);
            EclipseMod.LOGGER.info("EndShatterSequence: crash finale complete — "
                    + "sky empty, {} low remnants and {} ground heaps stand",
                    SKY_BIT_COUNT, crashOrder(layout()).size());
            return;
        }
        long seed = layout().seed() ^ SALT_RUBBLE;
        double slice = Math.PI * 2.0D / SKY_BIT_COUNT;
        double angle = slice * index + to01(mix(seed, index, 1L)) * slice * 0.7D;
        double reach = SKY_BIT_MIN_RADIUS + to01(mix(seed, index, 2L)) * SKY_BIT_RADIUS_RANGE;
        int cx = DiscProfile.END_DISC_CENTER_X + (int) Math.round(Math.cos(angle) * reach);
        int cz = DiscProfile.END_DISC_CENTER_Z + (int) Math.round(Math.sin(angle) * reach);
        BudgetedBlockWriter.loadWithTicket(level, cx >> 4, cz >> 4);
        int ground = level.getHeight(Heightmap.Types.MOTION_BLOCKING, cx, cz);
        int cy = ground + SKY_BIT_MIN_RISE + (int) (to01(mix(seed, index, 3L)) * SKY_BIT_RISE_RANGE);
        int rx = SKY_BIT_MIN_SIZE + (int) (to01(mix(seed, index, 4L)) * SKY_BIT_SIZE_RANGE);
        int ry = Math.max(2, rx - 1);
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int placed = 0;
        for (int dx = -rx; dx <= rx; dx++) {
            for (int dy = -ry; dy <= ry; dy++) {
                for (int dz = -rx; dz <= rx; dz++) {
                    double n = (double) (dx * dx) / (rx * rx)
                            + (double) (dy * dy) / (ry * ry)
                            + (double) (dz * dz) / (rx * rx);
                    if (n > 1.0D
                            || !level.getBlockState(cursor.set(cx + dx, cy + dy, cz + dz)).isAir()) {
                        continue;
                    }
                    BlockState blockState =
                            to01(mix(seed, cx + dx, (long) (cy + dy) * 31L + cz + dz)) < 0.12D
                                    ? Blocks.OBSIDIAN.defaultBlockState()
                                    : Blocks.END_STONE.defaultBlockState();
                    level.setBlock(cursor, blockState, Block.UPDATE_CLIENTS);
                    placed++;
                }
            }
        }
        state.advanceSkyBit();
        EclipseMod.LOGGER.info("EndShatterSequence: low sky remnant {}/{} at ({}, {}, {}) — "
                + "{} block(s), {} over ground", index + 1, SKY_BIT_COUNT, cx, cy, cz,
                placed, cy - ground);
    }

    // --- F-047 resume ----------------------------------------------------------------

    /** Re-arms the interrupted finale phase and back-fills any heap whose fall was lost. */
    private static void resumeFinale(ServerLevel level, ShatterData state) {
        EndIslandCrashFx.clearAll();
        int phase = state.phase();
        if (phase >= PHASE_CRASH) {
            List<Integer> order = crashOrder(layout());
            int upTo = phase > PHASE_CRASH ? order.size() : state.crashPass();
            for (int pass = 0; pass < upTo; pass++) {
                landIslet(level, state, pass);
            }
        }
        if (phase == PHASE_CRASH && state.crashPass() < crashOrder(layout()).size()) {
            // The interrupted pass restarts from its persisted chunk cursor; its cosmetic
            // fall is gone, so the landing fires when the pass finishes instead.
            activePass = new RazePass(level, state, crashOrder(layout()).get(state.crashPass()));
            EclipseMod.LOGGER.info("EndShatterSequence: resuming crash pass {} at cursor {}",
                    state.crashPass(), state.razeCursor());
        } else if (phase == PHASE_CORE) {
            activePass = new RazePass(level, state, RazePass.ALL_ISLETS);
            EclipseMod.LOGGER.info("EndShatterSequence: resuming the core raze at cursor {}",
                    state.razeCursor());
        }
    }

    // --- F-047 the budgeted raze pass -------------------------------------------------

    /** One loot container lifted out of a falling islet. */
    private record RescuedBlock(BlockState state, @Nullable CompoundTag data) {}

    /**
     * Clears one islet (or, with {@link #ALL_ISLETS}, everything left) out of the End
     * band. Same budgeted shape as the carve {@link Job} — at most one chunk load per
     * tick, section writes, heightmap re-prime, relight + resend, cursor persisted at
     * chunk boundaries — plus a whole-section air fast path, because most of the
     * 150-block band over the disc is empty by the time this runs.
     */
    private static final class RazePass {
        /** Islet filter meaning "every column in the footprint", used by the core sweep. */
        static final int ALL_ISLETS = -1;

        private final ServerLevel level;
        private final ShatterData state;
        private final Layout layout;
        private final List<ChunkPos> chunks;
        private final long totalOperations;
        final int islet;
        private final int minY;
        private final int maxY;
        private final List<RescuedBlock> rescued = new ArrayList<>();
        private long cursor;

        RazePass(ServerLevel level, ShatterData state, int islet) {
            this.level = level;
            this.state = state;
            this.layout = layout();
            this.chunks = discChunks();
            this.totalOperations = (long) this.chunks.size() * 256L;
            this.islet = islet;
            this.minY = Math.max(level.getMinBuildHeight(), RAZE_MIN_Y);
            this.maxY = Math.min(level.getMaxBuildHeight() - 1, RAZE_MAX_Y);
            this.cursor = Math.min(state.razeCursor(), this.totalOperations);
        }

        /** Runs one tick of the pass; returns {@code true} once it is finished. */
        boolean tick() {
            if (this.cursor >= this.totalOperations) {
                return true;
            }
            long started = System.nanoTime();
            int budget = EndConfig.current().blockBudgetPerTick();
            int operations = 0;
            long chunkIndex = this.cursor / 256L;
            LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(
                    this.level,
                    this.chunks.get((int) chunkIndex).x,
                    this.chunks.get((int) chunkIndex).z);
            while (this.cursor < this.totalOperations
                    && this.cursor / 256L == chunkIndex
                    && operations < budget
                    && System.nanoTime() - started < TICK_NANOS) {
                operations += razeColumn(chunk, (int) (this.cursor & 255L));
                this.cursor++;
                operations++;
            }
            if (this.cursor / 256L != chunkIndex || this.cursor == this.totalOperations) {
                Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
                BudgetedBlockWriter.relightAndResend(this.level, chunk);
                this.state.setRazeCursor(this.cursor);
            }
            return this.cursor >= this.totalOperations;
        }

        /** Clears one column of the band; returns the number of blocks actually removed. */
        private int razeColumn(LevelChunk chunk, int localIndex) {
            int localX = localIndex & 15;
            int localZ = localIndex >>> 4;
            int x = chunk.getPos().getMinBlockX() + localX;
            int z = chunk.getPos().getMinBlockZ() + localZ;
            if (!EndDiscGeometry.footprintContains(x, z)) {
                return 0;
            }
            if (this.islet != ALL_ISLETS && this.layout.sample(x, z).islet() != this.islet) {
                return 0;
            }
            BlockState air = Blocks.AIR.defaultBlockState();
            int removed = 0;
            int sectionIndex = -1;
            LevelChunkSection section = null;
            for (int y = this.minY; y <= this.maxY; y++) {
                int index = chunk.getSectionIndex(y);
                if (index != sectionIndex) {
                    sectionIndex = index;
                    section = chunk.getSection(index);
                    if (section.hasOnlyAir()) {
                        // Skip the rest of an empty section in one step (the band is mostly
                        // air by the time the crash runs — this is the whole budget win).
                        y |= 15;
                        continue;
                    }
                }
                BlockState existing = section.getBlockState(localX, y & 15, localZ);
                if (existing.isAir()) {
                    continue;
                }
                if (existing.hasBlockEntity()) {
                    rescue(x, y, z, existing);
                    this.level.removeBlockEntity(new BlockPos(x, y, z));
                }
                section.setBlockState(localX, y & 15, localZ, air, false);
                removed++;
            }
            if (removed > 0) {
                chunk.setUnsaved(true);
            }
            return removed;
        }

        /** Lifts a loot container's contents out of the sky (capped, first come first served). */
        private void rescue(int x, int y, int z, BlockState existing) {
            if (this.rescued.size() >= HEAP_LOOT_CAP) {
                return;
            }
            BlockEntity blockEntity = this.level.getBlockEntity(new BlockPos(x, y, z));
            this.rescued.add(new RescuedBlock(existing, blockEntity == null
                    ? null : blockEntity.saveWithFullMetadata(this.level.registryAccess())));
        }

        /** Hands the rescued containers to the landing that seats them in the heap. */
        List<RescuedBlock> drainRescued() {
            List<RescuedBlock> copy = List.copyOf(this.rescued);
            this.rescued.clear();
            return copy;
        }
    }

    // --- restart-safe state (materialization SavedData pattern) ---

    /**
     * Shatter lifecycle, persisted as {@code data/eclipse_end_shatter.dat} in the
     * overworld storage. {@code dueGameTime} arms beat 0; {@code cursor} resumes the
     * carve pass at chunk granularity; {@code complete} marks the carve done.
     *
     * <p>Everything from {@code phase} down is the F-047 crash finale. A save written
     * before F-047 simply has none of those tags: it loads as {@link #PHASE_CARVE} with
     * an unarmed crash, which is exactly the state {@link #pollFinale} re-arms from — so
     * an already-shattered legacy world walks into the crash one loot window after its
     * next boot instead of being stuck with a permanent archipelago.</p>
     */
    public static final class ShatterData extends SavedData {
        public static final String DATA_NAME = "eclipse_end_shatter";

        private static final String TAG_DUE = "dueGameTime";
        private static final String TAG_STARTED = "started";
        private static final String TAG_CURSOR = "cursor";
        private static final String TAG_COMPLETE = "complete";
        // --- F-047 ---
        private static final String TAG_PHASE = "phase";
        private static final String TAG_CRASH_DUE = "crashDueGameTime";
        private static final String TAG_CRASH_PASS = "crashPass";
        private static final String TAG_RAZE_CURSOR = "razeCursor";
        private static final String TAG_IMPACT_MASK = "impactMask";
        private static final String TAG_SKY_BIT = "skyBitCursor";
        private static final String TAG_EGG_PENDING = "eggPending";
        private static final String TAG_EGG_RESCUED = "eggRescued";

        private long dueGameTime = -1L;
        private boolean started;
        private long cursor;
        private boolean complete;
        private int phase = PHASE_CARVE;
        private long crashDueGameTime = -1L;
        private int crashPass;
        private long razeCursor;
        /** Bit {@code i} = the landing of crash pass {@code i} already built its heap. */
        private long impactMask;
        private int skyBitCursor;
        private boolean eggPending;
        private boolean eggRescued;

        public ShatterData() {}

        public static ShatterData get(MinecraftServer server) {
            return server.overworld().getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(ShatterData::new, ShatterData::load),
                    DATA_NAME);
        }

        public static ShatterData load(CompoundTag tag, HolderLookup.Provider registries) {
            ShatterData data = new ShatterData();
            data.dueGameTime = tag.contains(TAG_DUE) ? tag.getLong(TAG_DUE) : -1L;
            data.started = tag.getBoolean(TAG_STARTED);
            data.cursor = Math.max(0L, tag.getLong(TAG_CURSOR));
            data.complete = tag.getBoolean(TAG_COMPLETE);
            data.phase = Mth.clamp(tag.getInt(TAG_PHASE), PHASE_CARVE, PHASE_DONE);
            data.crashDueGameTime = tag.contains(TAG_CRASH_DUE)
                    ? tag.getLong(TAG_CRASH_DUE) : -1L;
            data.crashPass = Math.max(0, tag.getInt(TAG_CRASH_PASS));
            data.razeCursor = Math.max(0L, tag.getLong(TAG_RAZE_CURSOR));
            data.impactMask = tag.getLong(TAG_IMPACT_MASK);
            data.skyBitCursor = Math.max(0, tag.getInt(TAG_SKY_BIT));
            data.eggPending = tag.getBoolean(TAG_EGG_PENDING);
            data.eggRescued = tag.getBoolean(TAG_EGG_RESCUED);
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putLong(TAG_DUE, this.dueGameTime);
            tag.putBoolean(TAG_STARTED, this.started);
            tag.putLong(TAG_CURSOR, this.cursor);
            tag.putBoolean(TAG_COMPLETE, this.complete);
            tag.putInt(TAG_PHASE, this.phase);
            tag.putLong(TAG_CRASH_DUE, this.crashDueGameTime);
            tag.putInt(TAG_CRASH_PASS, this.crashPass);
            tag.putLong(TAG_RAZE_CURSOR, this.razeCursor);
            tag.putLong(TAG_IMPACT_MASK, this.impactMask);
            tag.putInt(TAG_SKY_BIT, this.skyBitCursor);
            tag.putBoolean(TAG_EGG_PENDING, this.eggPending);
            tag.putBoolean(TAG_EGG_RESCUED, this.eggRescued);
            return tag;
        }

        public long dueGameTime() {
            return this.dueGameTime;
        }

        public void schedule(long gameTime) {
            if (this.dueGameTime < 0L && !this.started && !this.complete) {
                this.dueGameTime = gameTime;
                setDirty();
            }
        }

        public boolean started() {
            return this.started;
        }

        public void markStarted() {
            if (!this.started) {
                this.started = true;
                setDirty();
            }
        }

        public long cursor() {
            return this.cursor;
        }

        public void setCursor(long cursor) {
            long safe = Math.max(0L, cursor);
            if (safe != this.cursor) {
                this.cursor = safe;
                setDirty();
            }
        }

        public boolean complete() {
            return this.complete;
        }

        public void markComplete() {
            if (!this.complete) {
                this.started = true;
                this.complete = true;
                setDirty();
            }
        }

        // --- F-047 crash finale ---

        /** Current finale phase, one of the {@code PHASE_*} constants. */
        public int phase() {
            return this.phase;
        }

        /** Moves the finale forward; never backwards (a resume must not re-run a phase). */
        public void setPhase(int phase) {
            int safe = Mth.clamp(phase, PHASE_CARVE, PHASE_DONE);
            if (safe > this.phase) {
                this.phase = safe;
                setDirty();
            }
        }

        public long crashDueGameTime() {
            return this.crashDueGameTime;
        }

        /** Arms the loot window once; idempotent, so a re-poll cannot push the crash away. */
        public void armCrash(long gameTime) {
            if (this.phase > PHASE_CARVE) {
                return;
            }
            this.crashDueGameTime = gameTime;
            this.phase = PHASE_CRASH_WAIT;
            setDirty();
        }

        /** Command seam: pulls the armed crash forward (only while it is still waiting). */
        public void setCrashDue(long gameTime) {
            if (this.phase == PHASE_CRASH_WAIT && gameTime < this.crashDueGameTime) {
                this.crashDueGameTime = gameTime;
                setDirty();
            }
        }

        /** Index into {@code crashOrder} of the islet currently falling. */
        public int crashPass() {
            return this.crashPass;
        }

        public void setCrashPass(int pass) {
            int safe = Math.max(0, pass);
            if (safe != this.crashPass) {
                this.crashPass = safe;
                setDirty();
            }
        }

        public void advanceCrashPass() {
            this.crashPass++;
            setDirty();
        }

        /** Chunk-granular cursor of the live {@link RazePass} (survives a restart). */
        public long razeCursor() {
            return this.razeCursor;
        }

        public void setRazeCursor(long cursor) {
            long safe = Math.max(0L, cursor);
            if (safe != this.razeCursor) {
                this.razeCursor = safe;
                setDirty();
            }
        }

        /** Whether crash pass {@code pass} already built its ground heap. */
        public boolean impactDone(int pass) {
            return pass >= 0 && pass < Long.SIZE && (this.impactMask & (1L << pass)) != 0L;
        }

        public void markImpactDone(int pass) {
            if (pass >= 0 && pass < Long.SIZE) {
                this.impactMask |= 1L << pass;
                setDirty();
            }
        }

        /** How many low sky remnants have been placed (one per poll tick). */
        public int skyBitCursor() {
            return this.skyBitCursor;
        }

        public void advanceSkyBit() {
            this.skyBitCursor++;
            setDirty();
        }

        /** The egg was still on the podium when the core sweep started. */
        public boolean eggPending() {
            return this.eggPending;
        }

        public void markEggPending() {
            if (!this.eggPending) {
                this.eggPending = true;
                setDirty();
            }
        }

        /** The egg has been re-seated on the ground (or was already gone). */
        public boolean eggRescued() {
            return this.eggRescued;
        }

        public void markEggRescued() {
            if (!this.eggRescued) {
                this.eggPending = false;
                this.eggRescued = true;
                setDirty();
            }
        }
    }
}
