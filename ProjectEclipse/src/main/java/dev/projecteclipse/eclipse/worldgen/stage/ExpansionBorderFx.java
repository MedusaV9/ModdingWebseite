package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.border.SoftBorder;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.level.TicketType;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.entity.EntityTypeTest;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * RIFT-FX (user item 4) — the CHUNK-GATED border expansion spectacle. Its gate runs in
 * two phases:
 * <ol>
 *   <li><b>ARM</b> ({@link #armFrontier}, called by {@code ExpansionSequence} when the
 *       FLYOVER starts): <b>raises giant boulders out of the rim</b> — {@value
 *       #RING_BOULDERS} multi-slab {@code BLOCK_DISPLAY} monoliths, {@value #HEIGHT_MIN}–
 *       {@value #HEIGHT_MAX} blocks tall, standing ON the terrain just inside the ring,
 *       clustered around the flyover's growth-front anchor, quaking while the world strains
 *       against its own edge;</li>
 *   <li><b>GROW</b> (the {@link WorldStageService} growth-start listener):
 *       <b>holds the soft border at the OLD ring</b> ({@link SoftBorder#holdGrowthAtCurrent}
 *       — cancelling the classic sweep-coupled lerp), so the border only expands once the
 *       {@link RingGrowthService} sweep has written, lit and resent EVERY chunk of the new
 *       annulus. A commit that arrives without an arm (sequence disabled, operator
 *       {@code /eclipse stage set} on a headless run) raises the rocks right there;</li>
 *   <li><b>RELEASE</b>: on {@link WorldStageService.StageListener terrain completion} (the
 *       "all chunks finished loading" signal — {@code RingGrowthService.complete} fires it
 *       after its relight/resend pass) the border goes in one
 *       {@link ExpansionTiming#BORDER_RELEASE_LERP_MS} surge and the boulders <b>sink back
 *       into the ground</b>.</li>
 * </ol>
 *
 * <p><b>Why the arm has to happen at FLYOVER time</b>: a {@code BLOCK_DISPLAY}'s entity
 * TRACKING range is 10 chunks (160 blocks) — no client is ever sent a rim rock it stands
 * further away from, whatever its {@code view_range}. The only window in which watchers
 * are AT the rim is the flyover gather; {@code CutsceneService} returns them home before
 * it hands control to the growth commit (see {@code ExpansionSequence.beginGrowth}).</p>
 *
 * <h2>Why the v1 boulders were never seen in game</h2>
 * <p>v1 planned its rocks ONCE, synchronously inside the growth-start listener, and only
 * around players whose distance from the ring circle was within 160 blocks
 * ({@code if (Math.abs(playerDistanceFromCenter - heldRadius) > 160.0) continue;}). That
 * filter can never pass at that instant: growth starts from the FLYOVER's completion
 * callback, and {@code CutsceneService.handleClientState} runs its {@code restoreReturn}
 * teleport BEFORE {@code completeSession} fires that callback — so every gathered watcher
 * is already back at their pre-cutscene origin (spawn, the map centre) when the gate opens,
 * and the rim sits at {@code stageRadius + borderOffset} = 162 / 222 / 292 / 372 / 452
 * blocks out. The gate logged "0 boulder(s) planned" every time. Three further defects hid
 * behind that one, so even a watcher who happened to stand at the frontier saw nothing:
 * the hover points sat OUTSIDE the held rim, over the unwritten void annulus (where
 * {@code addFreshEntity} lands an entity in a section no client tracks), the displays kept
 * the vanilla {@code view_range} of 1.0 (drawn only within 64 blocks — v1 called the
 * 2-argument {@code DisplayBrightnessFx.set} and never touched the range), and one scaled
 * cube floating 7–16 blocks above nothing reads as a sky box, not a rock.
 *
 * <h2>v2 placement contract</h2>
 * <p>Ring slots are probed around the HELD rim, pulled {@value #RIM_INSET} blocks INSIDE
 * it so they land on the existing, written terrain; the {@value #RING_BOULDERS} slots
 * nearest to the arm anchor win — the growth-front point the flyover gathers its watchers
 * onto — falling back to the nearest players and then to an even spread. Each slot is
 * resolved lazily, {@value #BOULDERS_PER_TICK} per tick, so its chunk load never spikes a
 * tick: a region ticket is taken, the chunk is loaded (so the display enters a TRACKED
 * entity section), and the monolith is anchored on the {@code MOTION_BLOCKING_NO_LEAVES}
 * surface — walking inward in {@value #GROUND_PROBE_STEP_BLOCKS}-block steps if the column
 * is void. Every display carries an explicit {@value #VIEW_RANGE} view range
 * (= {@value #VIEW_RANGE} × 64 blocks) so it is drawn everywhere inside the 160-block
 * entity-tracking horizon rather than only within 64.
 *
 * <p><b>Caps</b>: {@value #RING_BOULDERS} near boulders per gate ({@value #SHARDS_MIN}–
 * {@value #SHARDS_MAX} slab displays each) plus {@value #FAR_BAND_BOULDERS} far
 * silhouettes ({@value #FAR_SHARDS} slabs each — W13-B3), {@value #BOULDERS_PER_TICK}
 * boulders raised per tick (one under the MSPT guard), pose updates every
 * {@link ExpansionTiming#BOULDER_UPDATE_INTERVAL_TICKS} ticks with matching client
 * interpolation (window doubled while the MSPT guard is tripped), and guaranteed
 * cleanup: sink-and-discard on release,
 * instant discard on gate replacement, a sweep-stopped fallback release, an absolute
 * {@value #GATE_WATCHDOG_TICKS}-tick watchdog, a boot-time sweep of loaded levels, the
 * join-time stray sweep for crash/restart leftovers, and a full clear on server stop.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ExpansionBorderFx {
    /** Tag on every boulder display — strays from a crash are swept on entity load. */
    public static final String ENTITY_TAG = "eclipse_border_boulder";

    // --- placement ---

    /** Ring slots probed around the held rim; the ones nearest to players win. */
    private static final int RING_CANDIDATE_SLOTS = 64;
    /** Monoliths raised per gate (the plan's "8–16 ring positions"). */
    private static final int RING_BOULDERS = 12;
    /** Boulders stand this far INSIDE the terrain rim — outside is still unwritten void. */
    private static final double RIM_INSET = 6.0D;
    /**
     * Inward probe when a slot's column is void (rim taper, crumble hole, water gap, or an
     * operator-set ring sitting well outside the written disc — a live 206-blocks-ring /
     * 150-blocks-disc dev world is what caught the too-short 48-block v2 reach).
     */
    private static final int GROUND_PROBE_STEPS = 16;
    private static final int GROUND_PROBE_STEP_BLOCKS = 8;
    /** Boulders resolved (chunk load + surface probe + spawn) per tick. */
    private static final int BOULDERS_PER_TICK = 2;
    /** Region ticket radius around each boulder (1 → its 3×3 chunk square). */
    private static final int TICKET_RADIUS = 1;
    /** Ticket TTL and refresh cadence — timed tickets self-expire, so cleanup is free. */
    private static final int TICKET_LIFESPAN_TICKS = 600;
    private static final int TICKET_REFRESH_TICKS = 400;

    // --- formation ---

    /** Slab displays per monolith: a broad embedded base up to a narrow tilted crown. */
    private static final int SHARDS_MIN = 3;
    private static final int SHARDS_MAX = 7;
    /**
     * Monolith height range in blocks. F-092 retune (plan §3.4): the rocks now garnish a
     * REAL rim-mountain wall ({@code DiscTerrainFunction} uplift band), so 4–8-block
     * pebbles read wrong — the quake props scale up toward the plan's 12–16 band.
     */
    private static final float HEIGHT_MIN = 6.0F;
    private static final float HEIGHT_MAX = 14.0F;
    /** Girth as a fraction of the height (massy, not spindly). */
    private static final float GIRTH_MIN_FACTOR = 0.55F;
    private static final float GIRTH_MAX_FACTOR = 0.90F;
    /**
     * Explicit display view range: {@code Display.shouldRenderAtSqrDistance} multiplies it
     * by 64, so 8 → 512 blocks — comfortably past the 160-block entity tracking horizon
     * (the vanilla default of 1.0 stopped the rim rocks from ever being drawn).
     */
    private static final float VIEW_RANGE = 8.0F;
    /** Light override: rim rocks must read at night; their anchor is at ground level. */
    private static final int BRIGHTNESS_BLOCK = 5;
    private static final int BRIGHTNESS_SKY = 15;

    // --- animation ---

    private static final int RISE_TICKS = ExpansionTiming.BOULDER_RISE_TICKS;
    private static final int SINK_TICKS = ExpansionTiming.BOULDER_SINK_TICKS;
    private static final int UPDATE_INTERVAL_TICKS = ExpansionTiming.BOULDER_UPDATE_INTERVAL_TICKS;
    private static final int RUMBLE_PERIOD_TICKS = ExpansionTiming.BOULDER_RUMBLE_PERIOD_TICKS;
    /** Quake amplitude (blocks) and angular speed of the per-slab oscillation. */
    private static final float SHAKE_AMPLITUDE = 0.12F;
    private static final float SHAKE_SPEED = 0.45F;
    /**
     * W13-B3 mass law on the quake: the taller (heavier) a monolith, the slower it
     * strains — the heaviest near rock oscillates at this fraction of {@link #SHAKE_SPEED}
     * and heaves out of the ground over up to {@value #MASS_RISE_MAX_FACTOR}× the base
     * {@link ExpansionTiming#BOULDER_RISE_TICKS} (the StormDebrisFx sediment rule:
     * heavy = deep + slow, light = quick + jittery).
     */
    private static final float MASS_SHAKE_SPEED_MIN_FACTOR = 0.62F;
    private static final float MASS_RISE_MAX_FACTOR = 1.5F;

    // --- W13-B3 far silhouette band (the W12 StormDebrisFx FAR-band pattern) ---

    /**
     * Silhouette monoliths raised on the NEXT-nearest ring slots past the near cluster,
     * so the strain reads along the whole horizon instead of stopping at the last prop
     * a watcher stands next to. Copied from StormDebrisFx's FX-Wave-12 FAR band (25%
     * share, half speed, hard size floor) and adapted to the rim: the "share" becomes
     * a fixed count of arc-extension slots, "half speed" the quake tempo, and the size
     * floor a taller height band — horizon-scale standing stones, not pebbles.
     */
    private static final int FAR_BAND_BOULDERS = 10;
    /** Silhouettes are slab-poor: an embedded base plus a crown — 2 displays each. */
    private static final int FAR_SHARDS = 2;
    /** Horizon-scale height band (~×1.7 the near rocks) with a slender standing-stone girth. */
    private static final float FAR_HEIGHT_MIN = 12.0F;
    private static final float FAR_HEIGHT_MAX = 24.0F;
    private static final float FAR_GIRTH_MIN_FACTOR = 0.26F;
    private static final float FAR_GIRTH_MAX_FACTOR = 0.42F;
    /** Mass law, heavy class: silhouettes heave slower and quake at roughly half tempo. */
    private static final float FAR_RISE_FACTOR = 1.6F;
    private static final float FAR_SHAKE_AMPLITUDE_FACTOR = 0.55F;
    private static final float FAR_SHAKE_SPEED_FACTOR = 0.5F;
    /** Darker light override than the near rocks — the far band must READ as silhouette. */
    private static final int FAR_BRIGHTNESS_BLOCK = 1;
    private static final int FAR_BRIGHTNESS_SKY = 11;

    // --- W13-B3 MSPT guard (the shared StormSiege lever) ---

    /**
     * PERF — over {@value #MSPT_DEGRADE_NANOS} ns average tick time the pose-push window
     * doubles (2 t → 4 t) and boulder raising drops to one per tick, recovering below
     * {@value #MSPT_RECOVER_NANOS} ns (hysteresis, checked every
     * {@value #MSPT_CHECK_INTERVAL_TICKS} ticks).
     */
    private static final long MSPT_DEGRADE_NANOS = 45_000_000L;
    private static final long MSPT_RECOVER_NANOS = 38_000_000L;
    private static final int MSPT_CHECK_INTERVAL_TICKS = 20;

    // --- fx ---

    /** FX broadcast radius for shakes/sounds (matches ExpansionSequence.slamFx). */
    private static final double FX_RANGE = 192.0D;
    /** Missed-signal fallback: sweep stopped but no terrain-complete after this many ticks. */
    private static final int SWEEP_STOPPED_GRACE_TICKS = 60;
    /** Absolute gate watchdog — a wedged sweep can never hold the border forever. */
    private static final int GATE_WATCHDOG_TICKS = 24_000; // 20 min; big sweeps take minutes
    /**
     * An ARMED gate whose growth commit never arrives (aborted sequence, disabled path)
     * sinks its rocks after this long — comfortably past the flyover's own watchdog
     * (path duration + preload hold + margin), so a slow client can never cut the show.
     */
    private static final int ARM_TIMEOUT_TICKS = 1_200;

    private static final String CAPTION_HOLD = "eclipse.caption.expansion.frontier_hold";
    private static final String CAPTION_RELEASE = "eclipse.caption.expansion.frontier_open";

    /** Rocky boulder palette (weighted by array position — index² roll, stone-first). */
    private static final BlockState[] BOULDER_BLOCKS = {
            Blocks.STONE.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.TUFF.defaultBlockState(),
            Blocks.ANDESITE.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState()};

    /** Dark-first palette for the far band — silhouettes, not lit props. */
    private static final BlockState[] SILHOUETTE_BLOCKS = {
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState(),
            Blocks.TUFF.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState()};

    /** Keeps a boulder's chunk resident so its display stays in a TRACKED entity section. */
    private static final TicketType<ChunkPos> BOULDER_TICKET = TicketType.create(
            "eclipse_border_boulder", Comparator.comparingLong(ChunkPos::toLong),
            TICKET_LIFESPAN_TICKS);

    /** Live gates by profile; mutations on the server thread only. */
    private static final Map<DiscProfile, Gate> GATES = new HashMap<>();
    /** UUIDs of displays spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());
    private static final AtomicBoolean LISTENERS_REGISTERED = new AtomicBoolean();
    /** True while the shared MSPT guard has all gates on the halved pose cadence. */
    private static boolean msptDegraded;

    private ExpansionBorderFx() {}

    // ------------------------------------------------------------------ wiring

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (!LISTENERS_REGISTERED.compareAndSet(false, true)) {
            return;
        }
        WorldStageService.addGrowthStartListener(ExpansionBorderFx::onStageGrowthStart);
        WorldStageService.addListener(ExpansionBorderFx::onStageTerrainComplete);
        EclipseMod.LOGGER.info("ExpansionBorderFx registered (chunk-gated border expansion)");
    }

    /**
     * ARM: raises the rim monoliths while the expansion's flyover still has its watchers
     * gathered at the frontier (the only window in which a 160-block-tracked display is
     * within reach of anybody). {@code anchor} is the flyover's growth-front point — the
     * boulders cluster around it; {@code null} falls back to player proximity.
     *
     * <p>No border hold is installed here: the stage commit has not run yet, so the ring's
     * persisted target is still the OLD radius and {@link SoftBorder#holdGrowthAtCurrent}
     * would refuse. The hold arrives with the growth-start listener a few hundred ticks
     * later; an arm whose commit never comes self-releases after
     * {@value #ARM_TIMEOUT_TICKS} ticks.</p>
     */
    public static void armFrontier(ServerLevel level, DiscProfile profile, @Nullable Vec3 anchor) {
        Gate live = GATES.get(profile);
        if (live != null && !live.released) {
            return; // already armed (re-entrant sequence beat) — never double the rocks
        }
        double radius = SoftBorder.radius(level.getServer(), profile);
        if (radius <= 0.0D) {
            return; // inactive ring (nether stage 0) — no rim to stand on
        }
        replaceGate(profile, new Gate(level, profile, radius, anchor));
    }

    /** GROW: hold the ring at the old rim; raise the rocks now if nobody armed them. */
    private static void onStageGrowthStart(ServerLevel level, DiscProfile profile, int fromStage,
            int toStage, boolean animate) {
        if (toStage <= fromStage || !animate) {
            return; // erases and instant stamps keep the classic border behavior
        }
        Gate gate = GATES.get(profile);
        if (gate == null || gate.released || gate.level != level) {
            double radius = SoftBorder.radius(level.getServer(), profile);
            if (radius <= 0.0D) {
                return;
            }
            gate = new Gate(level, profile, radius, null);
            replaceGate(profile, gate);
        }
        gate.beginGrowth();
    }

    /** Installs {@code gate}, instantly discarding whatever it supersedes, and opens it. */
    private static void replaceGate(DiscProfile profile, Gate gate) {
        Gate previous = GATES.put(profile, gate);
        if (previous != null) {
            previous.discardBoulders(); // superseded run: old props vanish instantly
        }
        gate.open();
    }

    /** Terrain complete = every chunk written/lit/resent: release the ring, sink the rocks. */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        Gate gate = GATES.get(profile);
        if (gate != null && !gate.released) {
            gate.release("terrain sweep complete");
        } else {
            // Safety: a hold must never outlive its sweep, gate or not.
            SoftBorder.releaseGrowthHold(level.getServer(), profile, 0L);
        }
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: SoftBorder clears its hold in its own stop hook; boulders that
        // made it to disk are swept by the boot/join-time stray checks on the next boot.
        GATES.clear();
        LIVE_DISPLAYS.clear();
        msptDegraded = false;
    }

    /**
     * F-080 shutdown sweep hook: releases every live gate's growth hold and instantly
     * discards its boulder displays NOW — on {@code ServerStoppingEvent}, before the
     * final save and level close. No goodbye FX (the world is going down); the
     * {@code ServerStoppedEvent} handler stays as the idempotent bookkeeping reset.
     * Returns the shard display count dropped.
     */
    public static int forceClearNow(MinecraftServer server) {
        int discarded = 0;
        for (Gate gate : GATES.values()) {
            // A hold must never outlive its sweep — the onStageTerrainComplete safety,
            // pulled forward to the stop path.
            SoftBorder.releaseGrowthHold(server, gate.profile, 0L);
            for (Boulder boulder : gate.boulders) {
                for (Shard shard : boulder.shards) {
                    if (shard.display != null) {
                        discarded++;
                    }
                }
            }
            gate.discardBoulders();
        }
        GATES.clear();
        return discarded;
    }

    /**
     * Boot-time half of the despawn guarantee: any tagged monolith that survived a crash
     * inside an already-resident chunk (spawn chunks, forced chunks) is discarded before
     * the first player can see it. Chunks that load later are covered by
     * {@link #onEntityJoin} — together the two hooks make a leftover rock impossible.
     */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        for (ServerLevel level : event.getServer().getAllLevels()) {
            List<? extends Display.BlockDisplay> strays = level.getEntities(
                    EntityTypeTest.<Entity, Display.BlockDisplay>forClass(Display.BlockDisplay.class),
                    display -> display.getTags().contains(ENTITY_TAG));
            for (Display.BlockDisplay stray : strays) {
                stray.discard();
            }
            if (!strays.isEmpty()) {
                EclipseMod.LOGGER.info("ExpansionBorderFx: swept {} leftover boulder display(s) in {}",
                        strays.size(), level.dimension().location());
            }
        }
    }

    /** OarAnimator sweep doctrine: a tagged display we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(ENTITY_TAG)
                && !LIVE_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (GATES.isEmpty()) {
            return;
        }
        MinecraftServer server = event.getServer();
        tickMsptGuard(server);
        for (DiscProfile profile : GATES.keySet().toArray(new DiscProfile[0])) {
            Gate gate = GATES.get(profile);
            if (gate == null || gate.level.getServer() != server) {
                continue;
            }
            gate.tick();
            if (gate.done) {
                GATES.remove(profile, gate);
            }
        }
    }

    /** The shared W12 MSPT lever: halved pose cadence over 45 ms, recovery below 38 ms. */
    private static void tickMsptGuard(MinecraftServer server) {
        if (server.getTickCount() % MSPT_CHECK_INTERVAL_TICKS != 0) {
            return;
        }
        long avgNanos = server.getAverageTickTimeNanos();
        if (msptDegraded) {
            if (avgNanos < MSPT_RECOVER_NANOS) {
                msptDegraded = false;
                EclipseMod.LOGGER.info(
                        "ExpansionBorderFx: MSPT recovered ({} ms) — full pose cadence",
                        avgNanos / 1_000_000L);
            }
        } else if (avgNanos > MSPT_DEGRADE_NANOS) {
            msptDegraded = true;
            EclipseMod.LOGGER.info(
                    "ExpansionBorderFx: MSPT guard tripped ({} ms > 45 ms) — pose pushes halved",
                    avgNanos / 1_000_000L);
        }
    }

    // ------------------------------------------------------------------ the gate

    /** One slab of a monolith: its own box, tilt, block and quake phase. */
    private static final class Shard {
        final Vector3f offset;
        final Vector3f size;
        final Quaternionf rotation;
        final BlockState state;
        final float phase;
        @Nullable
        Display.BlockDisplay display;

        Shard(Vector3f offset, Vector3f size, Quaternionf rotation, BlockState state, float phase) {
            this.offset = offset;
            this.size = size;
            this.rotation = rotation;
            this.state = state;
            this.phase = phase;
        }
    }

    /**
     * One straining monolith: heave out of the ground → quake → sink → discard.
     * W13-B3: rise duration, quake amplitude and quake tempo are per-boulder now —
     * derived from the mass law (taller = heavier = slower) and the far-band class.
     */
    private static final class Boulder {
        final Vec3 base;
        final float height;
        final List<Shard> shards;
        final boolean silhouette;
        final int riseTicks;
        final float shakeAmplitude;
        final float shakeSpeed;
        int spawnAge = -1;

        Boulder(Vec3 base, float height, List<Shard> shards, boolean silhouette,
                int riseTicks, float shakeAmplitude, float shakeSpeed) {
            this.base = base;
            this.height = height;
            this.shards = shards;
            this.silhouette = silhouette;
            this.riseTicks = riseTicks;
            this.shakeAmplitude = shakeAmplitude;
            this.shakeSpeed = shakeSpeed;
        }
    }

    /** A candidate rim slot, scored by squared distance to the nearest player. */
    private record RimSlot(double angle, double playerDistSq) {}

    private static final class Gate {
        final ServerLevel level;
        final DiscProfile profile;
        /** The ring's own radius — what the border is pinned at; may sit over open void. */
        final double heldRadius;
        /** Where the GROUND ends: the committed stage's outer radius, i.e. the map edge. */
        final double rimRadius;
        final RandomSource random;
        final List<Boulder> boulders = new ArrayList<>(RING_BOULDERS + FAR_BAND_BOULDERS);
        final Deque<Double> pendingAngles = new ArrayDeque<>(RING_BOULDERS);
        /** W13-B3 far band: silhouette slots, raised after the near cluster is up. */
        final Deque<Double> pendingFarAngles = new ArrayDeque<>(FAR_BAND_BOULDERS);

        int age = -1;
        int lastTicketRefreshAge = -1;
        /** One-shot: the plan queue has been fully resolved (logs the raised count once). */
        boolean queueDrained;
        /** Set by {@link #beginGrowth()}: the stage commit landed and the ring is held. */
        boolean growing;
        int growthAge;
        boolean released;
        int releaseAge;
        boolean done;

        Gate(ServerLevel level, DiscProfile profile, double heldRadius, @Nullable Vec3 anchor) {
            this.level = level;
            this.profile = profile;
            this.heldRadius = heldRadius;
            // The monoliths belong on the MAP edge, not on the ring: the soft border sits
            // borderOffset blocks beyond the disc by design, and an operator-set ring can
            // sit far beyond it (dev worlds do). Written terrain stops at the committed
            // stage's outer radius, so that — never the ring — is what we stand on.
            int stageOuter = StageRadii.radius(profile,
                    WorldStageService.stage(level.getServer(), profile));
            this.rimRadius = stageOuter > 0 ? Math.min(heldRadius, stageOuter) : heldRadius;
            this.random = RandomSource.create(level.getGameTime() * 31L + profile.name().hashCode());
            planAngles(anchor);
        }

        /** Arm: the first deep rumble; the rocks come up over the next ticks. */
        void open() {
            Vec3 center = SoftBorder.center(level.getServer());
            for (ServerPlayer player : level.players()) {
                // The frontier CRACKS: a deep drone and a shake at every watcher, so the
                // beat lands even for players who are nowhere near the rim yet.
                PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.32F, 22));
                level.playSound(null, player.getX(), player.getY(), player.getZ(),
                        SoundEvents.AMBIENT_CAVE, SoundSource.AMBIENT, 1.0F, 0.55F);
            }
            if (!pendingAngles.isEmpty()) {
                double angle = pendingAngles.peek();
                level.playSound(null, center.x + Math.cos(angle) * rimRadius, 72.0D,
                        center.z + Math.sin(angle) * rimRadius,
                        EclipseSounds.EVENT_RIFT_DRONE.get(), SoundSource.AMBIENT, 1.0F, 0.6F);
            }
            EclipseMod.LOGGER.info(
                    "ExpansionBorderFx: {} gate ARMED at rim radius {} (ring {}) — {} boulder(s) "
                            + "+ {} far silhouette(s) queued",
                    profile.name(), String.format(java.util.Locale.ROOT, "%.1f", rimRadius),
                    String.format(java.util.Locale.ROOT, "%.1f", heldRadius),
                    pendingAngles.size(), pendingFarAngles.size());
        }

        /**
         * The stage commit landed: pin the ring at the old rim and put the hold caption up.
         * Idempotent — a re-fired growth start (superseded run) must not re-caption.
         */
        void beginGrowth() {
            if (this.growing || this.released) {
                return;
            }
            this.growing = true;
            this.growthAge = Math.max(this.age, 0);
            // false = inactive ring / nothing to grow; the rocks still get their exit via
            // the sweep-stopped fallback below, and releaseGrowthHold stays a no-op.
            SoftBorder.holdGrowthAtCurrent(level.getServer(), profile);
            PacketDistributor.sendToPlayersInDimension(level, new S2CCaptionPayload(
                    CAPTION_HOLD, 60, S2CCaptionPayload.STYLE_WHISPER));
        }

        /**
         * Picks the {@value #RING_BOULDERS} rim slots closest to the watchers. Slots are
         * evenly spaced around the whole ring first (so they can never overlap), then sorted
         * by squared distance to the nearest ATTRACTOR: the flyover's growth-front anchor
         * when the sequence armed us (that is where every gathered watcher is about to
         * stand), otherwise the players themselves. With neither, the ring is filled evenly
         * — the show still has to exist for whoever walks up to the edge.
         *
         * <p>W13-B3: the {@value #FAR_BAND_BOULDERS} NEXT-nearest slots after the near
         * cluster become the far silhouette band, extending the strain along the horizon
         * arc left and right of the watchers. The attractor-less even-spread fallback
         * skips the band — an even ring has no "near cluster" to extend.</p>
         */
        private void planAngles(@Nullable Vec3 anchor) {
            List<Vec3> attractors = new ArrayList<>();
            if (anchor != null) {
                attractors.add(anchor);
            } else {
                for (ServerPlayer player : level.players()) {
                    attractors.add(player.position());
                }
            }
            double ringR = Math.max(24.0D, rimRadius - RIM_INSET);
            if (attractors.isEmpty()) {
                for (int i = 0; i < RING_BOULDERS; i++) {
                    pendingAngles.add(i * (Math.PI * 2.0D / RING_BOULDERS));
                }
                return;
            }
            Vec3 center = SoftBorder.center(level.getServer());
            List<RimSlot> slots = new ArrayList<>(RING_CANDIDATE_SLOTS);
            for (int i = 0; i < RING_CANDIDATE_SLOTS; i++) {
                double angle = i * (Math.PI * 2.0D / RING_CANDIDATE_SLOTS);
                double x = center.x + Math.cos(angle) * ringR;
                double z = center.z + Math.sin(angle) * ringR;
                double nearest = Double.MAX_VALUE;
                for (Vec3 attractor : attractors) {
                    double dx = attractor.x - x;
                    double dz = attractor.z - z;
                    nearest = Math.min(nearest, dx * dx + dz * dz);
                }
                slots.add(new RimSlot(angle, nearest));
            }
            slots.sort(Comparator.comparingDouble(RimSlot::playerDistSq));
            for (int i = 0; i < Math.min(RING_BOULDERS, slots.size()); i++) {
                pendingAngles.add(slots.get(i).angle());
            }
            int farEnd = Math.min(RING_BOULDERS + FAR_BAND_BOULDERS, slots.size());
            for (int i = RING_BOULDERS; i < farEnd; i++) {
                pendingFarAngles.add(slots.get(i).angle());
            }
        }

        void tick() {
            this.age++;
            if (!this.released) {
                // Fallback releases: an arm whose commit never came, the sweep stopping
                // without our listener firing (superseded edge cases), or the absolute
                // watchdog. Only the GROWING gate may be judged by the sweep — before the
                // commit there is no sweep to be running.
                if (!this.growing) {
                    if (this.age > ARM_TIMEOUT_TICKS) {
                        release("armed but no growth commit arrived");
                    }
                } else if (this.age - this.growthAge > SWEEP_STOPPED_GRACE_TICKS
                        && !RingGrowthService.isRunning(profile)) {
                    release("sweep no longer running (fallback)");
                } else if (this.age > GATE_WATCHDOG_TICKS) {
                    release("gate watchdog (border safety beats spectacle)");
                }
            }
            if (!this.released) {
                raiseQueuedBoulders();
                if (this.age > 0 && this.age % RUMBLE_PERIOD_TICKS == 0 && !boulders.isEmpty()) {
                    strainRumble();
                }
                refreshTickets();
            }
            // Push-cadence law: the interpolation duration IS the push interval; under
            // the MSPT guard the window doubles (2 t → 4 t) and the client tween simply
            // spans the longer window — motion stays continuous, packets halve.
            int interval = msptDegraded ? UPDATE_INTERVAL_TICKS * 2 : UPDATE_INTERVAL_TICKS;
            if (this.age % interval == 0) {
                for (Boulder boulder : boulders) {
                    animate(boulder, interval);
                }
            }
            if (this.released && this.age - this.releaseAge > SINK_TICKS + UPDATE_INTERVAL_TICKS * 2) {
                discardBoulders();
                this.done = true;
            }
        }

        /**
         * Resolves and raises up to {@value #BOULDERS_PER_TICK} queued rim slots per tick
         * (one under the MSPT guard). The near cluster drains first — the props the
         * gathered watchers stand among — then the far silhouette band fills the horizon.
         */
        private void raiseQueuedBoulders() {
            int budget = msptDegraded ? 1 : BOULDERS_PER_TICK;
            for (int i = 0; i < budget
                    && !(pendingAngles.isEmpty() && pendingFarAngles.isEmpty()); i++) {
                boolean silhouette = pendingAngles.isEmpty();
                double angle = silhouette ? pendingFarAngles.poll() : pendingAngles.poll();
                Boulder boulder = resolveBoulder(angle, silhouette);
                if (boulder == null) {
                    continue; // void column all the way inward — that stretch of rim stays bare
                }
                boulder.spawnAge = this.age;
                for (Shard shard : boulder.shards) {
                    spawn(boulder, shard);
                }
                boulders.add(boulder);
                raiseFx(boulder);
            }
            if (pendingAngles.isEmpty() && pendingFarAngles.isEmpty() && !this.queueDrained) {
                this.queueDrained = true;
                if (boulders.isEmpty()) {
                    EclipseMod.LOGGER.warn(
                            "ExpansionBorderFx: {} gate found no solid rim column — no boulders raised",
                            profile.name());
                } else {
                    long farCount = boulders.stream().filter(b -> b.silhouette).count();
                    EclipseMod.LOGGER.info("ExpansionBorderFx: {} gate raised {} rim monolith(s) "
                            + "({} far silhouette(s), {} display(s)) at radius ~{}",
                            profile.name(), boulders.size(), farCount,
                            boulders.stream().mapToInt(b -> b.shards.size()).sum(),
                            String.format(java.util.Locale.ROOT, "%.1f", rimRadius - RIM_INSET));
                }
            }
        }

        /**
         * Turns one rim angle into a placed monolith: ticket + chunk load (the display must
         * enter a TRACKED entity section or it is never sent to a client), then the surface
         * probe, walking inward until a solid column is found.
         */
        @Nullable
        private Boulder resolveBoulder(double angle, boolean silhouette) {
            Vec3 center = SoftBorder.center(level.getServer());
            for (int step = 0; step < GROUND_PROBE_STEPS; step++) {
                double r = Math.max(16.0D, rimRadius - RIM_INSET - step * GROUND_PROBE_STEP_BLOCKS);
                int x = Mth.floor(center.x + Math.cos(angle) * r);
                int z = Mth.floor(center.z + Math.sin(angle) * r);
                ChunkPos chunkPos = new ChunkPos(x >> 4, z >> 4);
                level.getChunkSource().addRegionTicket(BOULDER_TICKET, chunkPos, TICKET_RADIUS, chunkPos);
                level.getChunk(chunkPos.x, chunkPos.z);
                int groundY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
                if (groundY > level.getMinBuildHeight()) {
                    Vec3 base = new Vec3(x + 0.5D, groundY, z + 0.5D);
                    return silhouette ? buildSilhouette(base) : buildBoulder(base);
                }
            }
            return null;
        }

        /**
         * Builds one irregular monolith out of {@value #SHARDS_MIN}–{@value #SHARDS_MAX}
         * nested slabs: a wide slab embedded in the ground, progressively narrower ones
         * stacked and jittered above it, each tilted a few degrees so no two faces line up.
         * Sizes are per-axis, so the silhouette never reads as a scaled cube.
         */
        private Boulder buildBoulder(Vec3 base) {
            float height = HEIGHT_MIN + random.nextFloat() * (HEIGHT_MAX - HEIGHT_MIN);
            float girth = height * (GIRTH_MIN_FACTOR
                    + random.nextFloat() * (GIRTH_MAX_FACTOR - GIRTH_MIN_FACTOR));
            int shardCount = SHARDS_MIN + random.nextInt(SHARDS_MAX - SHARDS_MIN + 1);
            List<Shard> shards = new ArrayList<>(shardCount);
            for (int i = 0; i < shardCount; i++) {
                float t = shardCount == 1 ? 0.0F : i / (float) (shardCount - 1);
                float slabHeight = height * (0.30F + 0.28F * (1.0F - t));
                float taper = 1.0F - 0.55F * t;
                float slabWidth = girth * taper * (0.75F + random.nextFloat() * 0.5F);
                float slabDepth = girth * taper * (0.75F + random.nextFloat() * 0.5F);
                float jitter = girth * 0.22F;
                Vector3f offset = new Vector3f(
                        (random.nextFloat() - 0.5F) * jitter,
                        height * (0.12F + 0.78F * t),
                        (random.nextFloat() - 0.5F) * jitter);
                Quaternionf rotation = new Quaternionf()
                        .rotateY((random.nextFloat() - 0.5F) * 1.2F)
                        .rotateX((random.nextFloat() - 0.5F) * 0.30F)
                        .rotateZ((random.nextFloat() - 0.5F) * 0.30F);
                // Index² weighting keeps most slabs plain stone with darker accents mixed in.
                BlockState state = BOULDER_BLOCKS[(int) (random.nextFloat() * random.nextFloat()
                        * BOULDER_BLOCKS.length)];
                shards.add(new Shard(offset, new Vector3f(slabWidth, slabHeight, slabDepth),
                        rotation, state, random.nextFloat() * Mth.TWO_PI));
            }
            // W13-B3 mass law: mass01 from the height band; the heaviest rock strains at
            // 62% tempo and heaves out over ×1.5 the base rise.
            float mass01 = (height - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN);
            int riseTicks = Math.round(RISE_TICKS * Mth.lerp(mass01, 1.0F, MASS_RISE_MAX_FACTOR));
            float shakeSpeed = SHAKE_SPEED * Mth.lerp(mass01, 1.0F, MASS_SHAKE_SPEED_MIN_FACTOR);
            return new Boulder(base, height, shards, false, riseTicks, SHAKE_AMPLITUDE, shakeSpeed);
        }

        /**
         * W13-B3 far-band builder: a horizon-scale standing stone out of {@value
         * #FAR_SHARDS} slabs — a broad embedded base and a slender tilted crown taking
         * most of the height. Dark-first palette, half quake tempo, ×{@value
         * #FAR_RISE_FACTOR} rise: the far band is the heavy class of the mass law and
         * must move like it.
         */
        private Boulder buildSilhouette(Vec3 base) {
            float height = FAR_HEIGHT_MIN + random.nextFloat() * (FAR_HEIGHT_MAX - FAR_HEIGHT_MIN);
            float girth = height * (FAR_GIRTH_MIN_FACTOR
                    + random.nextFloat() * (FAR_GIRTH_MAX_FACTOR - FAR_GIRTH_MIN_FACTOR));
            List<Shard> shards = new ArrayList<>(FAR_SHARDS);
            for (int i = 0; i < FAR_SHARDS; i++) {
                boolean crown = i > 0;
                float slabHeight = crown ? height * 0.82F : height * 0.34F;
                float slabGirth = crown ? girth * 0.72F : girth * 1.35F;
                Vector3f offset = new Vector3f(
                        (random.nextFloat() - 0.5F) * girth * 0.16F,
                        crown ? height * 0.42F : height * 0.05F,
                        (random.nextFloat() - 0.5F) * girth * 0.16F);
                Quaternionf rotation = new Quaternionf()
                        .rotateY((random.nextFloat() - 0.5F) * 1.2F)
                        .rotateX((random.nextFloat() - 0.5F) * (crown ? 0.16F : 0.08F))
                        .rotateZ((random.nextFloat() - 0.5F) * (crown ? 0.16F : 0.08F));
                BlockState state = SILHOUETTE_BLOCKS[(int) (random.nextFloat() * random.nextFloat()
                        * SILHOUETTE_BLOCKS.length)];
                shards.add(new Shard(offset,
                        new Vector3f(slabGirth, slabHeight, slabGirth * (0.85F + random.nextFloat() * 0.3F)),
                        rotation, state, random.nextFloat() * Mth.TWO_PI));
            }
            return new Boulder(base, height, shards, true,
                    Math.round(RISE_TICKS * FAR_RISE_FACTOR),
                    SHAKE_AMPLITUDE * FAR_SHAKE_AMPLITUDE_FACTOR,
                    SHAKE_SPEED * FAR_SHAKE_SPEED_FACTOR);
        }

        private void spawn(Boulder boulder, Shard shard) {
            Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
            display.setBlockState(shard.state);
            display.moveTo(boulder.base.x, boulder.base.y, boulder.base.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(poseOf(boulder, shard, 0));
            // One NBT round-trip for BOTH private setters: a readable dusk-stone brightness
            // (the anchor sits on the ground, the crown does not) and the wide view range
            // without which the rim rocks are simply not drawn past 64 blocks. The far
            // band gets a darker override — it must read as silhouette, not lit prop.
            if (boulder.silhouette) {
                DisplayBrightnessFx.set(display, FAR_BRIGHTNESS_BLOCK, FAR_BRIGHTNESS_SKY, VIEW_RANGE);
            } else {
                DisplayBrightnessFx.set(display, BRIGHTNESS_BLOCK, BRIGHTNESS_SKY, VIEW_RANGE);
            }
            LIVE_DISPLAYS.add(display.getUUID());
            level.addFreshEntity(display);
            shard.display = display;
        }

        private void animate(Boulder boulder, int interval) {
            // Keyframe lead (SanctumOrbitals law): push the pose this interpolation
            // window ENDS on, so the client tween never trails the server.
            int poseAge = this.age - boulder.spawnAge + interval;
            for (Shard shard : boulder.shards) {
                Display.BlockDisplay display = shard.display;
                if (display == null || display.isRemoved()) {
                    continue;
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(interval);
                display.setTransformation(poseOf(boulder, shard, poseAge));
            }
        }

        /**
         * Slab pose at a given age: an eased heave from fully below the surface over the
         * boulder's own rise window, a continuous quake while the frontier is held, and
         * after release an accelerating {@value #SINK_TICKS}-tick sink back under the
         * ground. W13-B3: rise, amplitude and tempo are the boulder's mass-law fields —
         * heavy rocks and the far band strain slower. The entity anchor never moves; all
         * motion lives in the transformation (the DisplayPlacerService law), and the slab
         * box is centred on its offset so the tilt rotates the rock about itself instead
         * of swinging it around a corner.
         */
        private Transformation poseOf(Boulder boulder, Shard shard, int poseAge) {
            float riseT = Mth.clamp(poseAge / (float) boulder.riseTicks, 0.0F, 1.0F);
            float riseEase = 1.0F - (1.0F - riseT) * (1.0F - riseT) * (1.0F - riseT);
            float yOff = -(boulder.height + 1.5F) * (1.0F - riseEase);
            if (this.released) {
                int sinkAge = (boulder.spawnAge + poseAge) - this.releaseAge;
                float sinkT = Mth.clamp(sinkAge / (float) SINK_TICKS, 0.0F, 1.0F);
                yOff -= (boulder.height + 2.5F) * sinkT * sinkT;
            }
            float quake = boulder.shakeAmplitude * riseEase;
            float speed = boulder.shakeSpeed;
            float shakeX = Mth.sin(shard.phase + poseAge * speed) * quake;
            float shakeZ = Mth.cos(shard.phase * 1.7F + poseAge * speed * 0.83F) * quake;
            float shakeY = Mth.sin(shard.phase * 0.6F + poseAge * speed * 1.31F) * quake * 0.45F;
            Quaternionf rotation = new Quaternionf(shard.rotation);
            Vector3f half = new Vector3f(shard.size).mul(0.5F).rotate(rotation);
            Vector3f translation = new Vector3f(
                    shard.offset.x + shakeX - half.x,
                    shard.offset.y + yOff + shakeY - half.y,
                    shard.offset.z + shakeZ - half.z);
            return new Transformation(translation, rotation, new Vector3f(shard.size),
                    new Quaternionf());
        }

        /**
         * A monolith tearing out of the ground: quarry crack, stone slam, local shake.
         * The far band only gets a low distant crack — ten more full slams back-to-back
         * would read as noise, and nobody stands next to a silhouette.
         */
        private void raiseFx(Boulder boulder) {
            Vec3 pos = boulder.base;
            if (boulder.silhouette) {
                level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.DEEPSLATE_BREAK,
                        SoundSource.BLOCKS, 1.6F, 0.34F + random.nextFloat() * 0.08F);
                return;
            }
            PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, FX_RANGE,
                    S2CShakePayload.shake(0.30F, 16));
            level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.DEEPSLATE_BREAK,
                    SoundSource.BLOCKS, 2.6F, 0.42F + random.nextFloat() * 0.12F);
            level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.STONE_PLACE,
                    SoundSource.BLOCKS, 2.4F, 0.48F + random.nextFloat() * 0.10F);
        }

        /** Low strain rumble while the frontier is held, rotated around the raised rocks. */
        private void strainRumble() {
            Boulder anchor = boulders.get((this.age / RUMBLE_PERIOD_TICKS) % boulders.size());
            Vec3 pos = anchor.base;
            PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, FX_RANGE,
                    S2CShakePayload.shake(0.10F, 12));
            level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.AMBIENT_BASALT_DELTAS_LOOP,
                    SoundSource.AMBIENT, 2.2F, 0.5F);
            level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.STONE_BREAK,
                    SoundSource.BLOCKS, 1.4F, 0.4F + random.nextFloat() * 0.1F);
        }

        /** Re-arms the boulder chunk tickets before the timed ones expire under a long sweep. */
        private void refreshTickets() {
            if (boulders.isEmpty() || this.age - this.lastTicketRefreshAge < TICKET_REFRESH_TICKS) {
                return;
            }
            this.lastTicketRefreshAge = this.age;
            for (Boulder boulder : boulders) {
                ChunkPos pos = new ChunkPos(Mth.floor(boulder.base.x) >> 4,
                        Mth.floor(boulder.base.z) >> 4);
                level.getChunkSource().addRegionTicket(BOULDER_TICKET, pos, TICKET_RADIUS, pos);
            }
        }

        /** All chunks are in: the border surges to the new ring and the rocks go home. */
        void release(String reason) {
            if (this.released) {
                return;
            }
            this.released = true;
            this.releaseAge = Math.max(this.age, 0);
            this.pendingAngles.clear(); // never raise new rocks into the goodbye
            this.pendingFarAngles.clear();
            SoftBorder.releaseGrowthHold(level.getServer(), profile,
                    ExpansionTiming.BORDER_RELEASE_LERP_MS);
            PacketDistributor.sendToPlayersInDimension(level, new S2CCaptionPayload(
                    CAPTION_RELEASE, 60, S2CCaptionPayload.STYLE_WHISPER));
            // F-092 recede beat (plan §3.4-4): ONE rim_recede cue per player, anchored at
            // THEIR nearest point of the old rim (leaks nothing — the ring radius is
            // already synced), so the dust curtain lands wherever on the disc they watch
            // the silhouette ring march outward over the release lerp; a low rumble at
            // each watcher carries the beat past FX_RANGE. Overworld only — the nether
            // rim reads as cave wall (no mountains, plan §3.2).
            if (profile == DiscProfile.OVERWORLD) {
                Vec3 center = SoftBorder.center(level.getServer());
                float oldRing = (float) this.heldRadius;
                for (ServerPlayer player : level.players()) {
                    double dx = player.getX() - center.x;
                    double dz = player.getZ() - center.z;
                    double len = Math.sqrt(dx * dx + dz * dz);
                    double nx = len > 1.0E-3D ? dx / len : 1.0D;
                    double nz = len > 1.0E-3D ? dz / len : 0.0D;
                    Vec3 rimPoint = new Vec3(center.x + nx * this.rimRadius,
                            profile.surfaceBaseY(), center.z + nz * this.rimRadius);
                    FxPayloads.sendFxEventTo(player, FxCues.CUE_RIM_RECEDE, rimPoint,
                            oldRing, 0.0F);
                    level.playSound(null, player.getX(), player.getY(), player.getZ(),
                            SoundEvents.AMBIENT_BASALT_DELTAS_LOOP, SoundSource.AMBIENT,
                            1.6F, 0.45F);
                }
            }
            int collapses = 0;
            for (Boulder boulder : boulders) {
                Vec3 pos = boulder.base;
                if (collapses == 0) {
                    PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, FX_RANGE,
                            S2CShakePayload.shake(0.24F, 18));
                    level.playSound(null, pos.x, pos.y, pos.z, EclipseSounds.EVENT_RIFT_THUD.get(),
                            SoundSource.AMBIENT, 0.9F, 0.55F);
                }
                if (collapses++ < 4) {
                    level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.STONE_BREAK,
                            SoundSource.BLOCKS, 2.2F, 0.38F + random.nextFloat() * 0.1F);
                }
            }
            EclipseMod.LOGGER.info("ExpansionBorderFx: {} gate released ({}) — {} boulder(s) sinking",
                    profile.name(), reason, boulders.size());
        }

        void discardBoulders() {
            this.pendingAngles.clear();
            this.pendingFarAngles.clear();
            for (Boulder boulder : boulders) {
                for (Shard shard : boulder.shards) {
                    Display.BlockDisplay display = shard.display;
                    if (display != null) {
                        LIVE_DISPLAYS.remove(display.getUUID());
                        if (!display.isRemoved()) {
                            display.discard();
                        }
                        shard.display = null;
                    }
                }
            }
            boulders.clear();
        }
    }
}
