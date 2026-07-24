package dev.projecteclipse.eclipse.worldgen.stage;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * C7 — STRUCTURE DELIVERY: the "flying assembly" beat of the expansion spectacle. When a
 * pending structure site is about to place, pieces of the incoming structure fly OUT of
 * the sky rift as {@code BLOCK_DISPLAY} entities, arc along a ballistic Bezier to target
 * cells across the footprint (overshoot-hover, then a damped settle), and only THEN does
 * the real set-block pass run — the displays are swept the moment the registry reports
 * {@link StructurePendingRegistry.Phase#PLACED}.
 *
 * <p><b>Determinism law (frozen)</b>: the real placement remains the sole authority. This
 * class never writes a block; it only delays the placer invocation by the flight length
 * (comfortably inside {@code ExpansionSequence}'s 1200-tick beat timeout) and is skipped
 * entirely when nobody is close enough to see it — {@link #begin} then returns
 * {@code false} and the registry places immediately, byte-identical to pre-C7 behavior.
 * A watchdog force-completes any flight that overstays so a placement can never be lost
 * behind visuals.</p>
 *
 * <p><b>Beats</b> (user item 16): on delivery start the sky tear is re-opened with the
 * server-computed adaptive width ({@link StructurePendingRegistry#revealRiftWidth}) — the
 * surge visibly convulses the tear — plus rift-groan drone and a shake pulse; every
 * launched batch gets a whoosh at the rift mouth; each landing gets a bass thud + a small
 * rate-limited shake; 3 scripted lightning strikes hit the footprint rim at 30/55/85 % of
 * the flight window ({@code FX_LIGHTNING_STRIKE}, the intro-storm renderer); when the last
 * piece settles the tear snaps shut, a resolve chord plays and the placer runs — the big
 * PLACED slam (shockwave + 0.4 shake) stays {@code ExpansionSequence}'s. The final-slam /
 * rift-open pulses of the sequence are untouched; this class only adds the in-between.</p>
 *
 * <p><b>Piece sampling</b>: the placer has not run yet, so the structure's real blocks are
 * unknowable at launch time. Pieces sample a per-{@code structureId} palette of that
 * structure's most visible (surface-first) materials, weighted toward the primary
 * material — visually truthful, and pure candy by construction. Cavity sites (anchor well
 * below the surface: trial chambers, ancient city, crypts) get PLUNGING pieces that punch
 * into the ground on arrival instead of resting on it.</p>
 *
 * <p><b>Budgets</b>: at most {@code flight_fx.max_displays} displays per delivery (config
 * {@code config/eclipse/dungeons.json}, optional section, default {@value #DEFAULT_MAX_DISPLAYS});
 * launches staggered in batches of {@value #BATCH_SIZE} every {@value #BATCH_STAGGER_TICKS}
 * ticks; transformations update every {@value #UPDATE_INTERVAL_TICKS} ticks with matching
 * client interpolation (the {@code devtools/display/DisplayAnimator} pattern); the flight
 * holds the registry's one-placement-per-interval slot so deliveries never stack.</p>
 *
 * <p><b>Restart safety</b>: displays are tagged {@value #ENTITY_TAG} and tracked in a
 * live-UUID set; any tagged display that joins a level WITHOUT being tracked (i.e. it was
 * persisted by a crash/stop mid-flight) is discarded on load — the
 * {@code OarAnimator.sweepStrayDisplays} doctrine. The pending SavedData row survives the
 * restart untouched, so the registry's auto-delay re-places the site normally (the flight
 * never replays for it: cinematics skip to the end state).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StructureFlightFx {
    /** Tag on every flight display — strays from a crash are swept on entity load. */
    public static final String ENTITY_TAG = "eclipse_flight_display";

    /** Default per-delivery display cap ({@code flight_fx.max_displays} overrides). */
    private static final int DEFAULT_MAX_DISPLAYS = 80;
    /** Transformation update cadence; interpolation duration matches (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 2;
    /** Pieces per launch batch and the stagger between batches (spawn-cost smoothing). */
    private static final int BATCH_SIZE = 8;
    private static final int BATCH_STAGGER_TICKS = 6;
    /** Per-piece flight length range (plan: "30–60 t"). */
    private static final int MIN_FLIGHT_TICKS = 30;
    private static final int MAX_FLIGHT_TICKS = 60;
    /** Damped-settle length after the hover overshoot. */
    private static final int SETTLE_TICKS = 6;
    /** Arc overshoot: pieces decelerate into a hover this far above the resting cell. */
    private static final float HOVER_OVERSHOOT = 0.35F;
    /** Display scale: slightly over 1 so a settled piece encloses the real block (no z-fight). */
    private static final float PIECE_SCALE = 1.02F;
    /**
     * Rift-mouth altitude above the site surface. Mirrors the (private)
     * {@code ExpansionSequence.SKY_RIFT_HEIGHT} so the delivery surge re-opens the beat's
     * tear in place instead of tearing a second hole beside it.
     */
    private static final int RIFT_MOUTH_HEIGHT = 26;
    /** A delivery only plays when at least one player is this close to the site anchor. */
    private static final double VIEWER_RANGE = 224.0D;
    /** FX broadcast radius for shakes/sounds (matches ExpansionSequence.slamFx). */
    private static final double FX_RANGE = 192.0D;
    /** Minimum ticks between landing thud/shake beats (a landing hail must not strobe). */
    private static final int LANDING_FX_COOLDOWN_TICKS = 4;
    /** Cavity sites (anchor this far under the surface) get plunging pieces. */
    private static final int CAVITY_DEPTH = 8;
    /** Big deliveries (footprint ≥ this) announce themselves with a whisper caption. */
    private static final int CAPTION_FOOTPRINT = 64;
    /** Hard lifetime cap — a wedged flight force-places and cleans up (placement > candy). */
    private static final int WATCHDOG_TICKS = 400;
    /** Landed displays are swept this long after completion even if PLACED never fires. */
    private static final int DISCARD_FALLBACK_TICKS = 600;
    /** Flight-window fractions of the scripted rim lightning strikes. */
    private static final float[] LIGHTNING_AT = {0.30F, 0.55F, 0.85F};
    /** Flight-window fractions of the mid-flight shake pulses (0 % fires in begin()). */
    private static final float[] SHAKE_AT = {0.40F, 0.80F};

    /** Deliveries that make no sense as flying masonry (weather / self-sequenced sites). */
    private static final Set<String> EXCLUDED_STRUCTURES = Set.of(
            "eclipse:fog_storm", "eclipse:stronghold_emergence");

    /** structureId → visible-material palette, primary material first (index² weighting). */
    private static final Map<String, List<BlockState>> PALETTES = buildPalettes();
    private static final List<BlockState> FALLBACK_PALETTE = List.of(
            Blocks.STONE_BRICKS.defaultBlockState(), Blocks.CRACKED_STONE_BRICKS.defaultBlockState(),
            Blocks.COBBLESTONE.defaultBlockState(), Blocks.OAK_PLANKS.defaultBlockState());

    /** Live flights by siteId; mutations on the server thread only. */
    private static final Map<String, Flight> FLIGHTS = new HashMap<>();
    /** Sites already delivered this boot — a failed-placement retry never replays the show. */
    private static final Set<String> PLAYED = new HashSet<>();
    /** UUIDs of displays spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());
    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private static volatile boolean configLoaded;
    private static boolean configEnabled = true;
    private static int configMaxDisplays = DEFAULT_MAX_DISPLAYS;

    private StructureFlightFx() {}

    // ------------------------------------------------------------------ registry seam

    /**
     * Whether {@code siteId}'s delivery flight is currently airborne. The registry treats
     * such a site as handled — placement resumes from the flight's completion callback.
     */
    public static boolean isDeliveryInFlight(String siteId) {
        Flight flight = FLIGHTS.get(siteId);
        return flight != null && !flight.completed;
    }

    /**
     * Starts the delivery flight for {@code site} and returns {@code true}, or returns
     * {@code false} when the show should be skipped (disabled, excluded structure, no
     * viewer within {@value #VIEWER_RANGE} blocks, or already played this boot) — the
     * caller then places immediately. {@code onComplete} runs on the server thread once
     * every piece has landed; it is the caller's re-entry into the real placement.
     */
    public static boolean begin(ServerLevel level, PendingSite site, Runnable onComplete) {
        loadConfig();
        if (!configEnabled || site.footprint() <= 0
                || EXCLUDED_STRUCTURES.contains(site.structureId())
                || PLAYED.contains(site.siteId()) || FLIGHTS.containsKey(site.siteId())) {
            return false;
        }
        BlockPos anchor = site.anchor();
        if (level.getNearestPlayer(anchor.getX() + 0.5D, anchor.getY(), anchor.getZ() + 0.5D,
                VIEWER_RANGE, false) == null) {
            return false; // nobody would see it: place immediately, zero delay
        }
        PLAYED.add(site.siteId());
        Flight flight = new Flight(level, site, onComplete);
        FLIGHTS.put(site.siteId(), flight);
        flight.open();
        EclipseMod.LOGGER.info("StructureFlightFx: delivery of {} ({}) — {} piece(s), window {} t, mouth {}",
                site.siteId(), site.structureId(), flight.pieces.size(), flight.windowTicks,
                flight.mouth);
        return true;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        configLoaded = false;
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            // PLACED = the real blocks landed: sweep the visual pieces of that site.
            StructurePendingRegistry.addListener((level, site, phase) -> {
                if (phase == StructurePendingRegistry.Phase.PLACED) {
                    Flight flight = FLIGHTS.remove(site.siteId());
                    if (flight != null) {
                        flight.discardDisplays();
                    }
                }
            });
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: pending SavedData rows survive; orphaned displays that made it
        // to disk are swept by the join-time stray check on next boot.
        FLIGHTS.clear();
        PLAYED.clear();
        LIVE_DISPLAYS.clear();
        configLoaded = false;
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
        if (FLIGHTS.isEmpty()) {
            return;
        }
        MinecraftServer server = event.getServer();
        for (Flight flight : List.copyOf(FLIGHTS.values())) {
            if (flight.level.getServer() != server) {
                continue;
            }
            flight.tick();
            if (flight.done) {
                FLIGHTS.remove(flight.site.siteId(), flight);
            }
        }
    }

    // ------------------------------------------------------------------ the flight

    /** One piece of flying structure: launch → Bezier arc → hover overshoot → settle. */
    private static final class Piece {
        final Vec3 launch;
        final Vec3 control;
        /** World-space block-center of the resting cell (or the plunge entry point). */
        final Vec3 target;
        /** Entity anchor: the resting cell's column center at cell Y (grid-exact settle). */
        final Vec3 entityPos;
        final BlockState state;
        final int launchTick;
        final int flightTicks;
        final float spinTurns;
        final Vector3f spinAxis;
        final boolean plunge;

        @Nullable
        Display.BlockDisplay display;
        boolean landed;
        boolean settled;

        Piece(Vec3 launch, Vec3 control, Vec3 target, Vec3 entityPos, BlockState state,
                int launchTick, int flightTicks, float spinTurns, Vector3f spinAxis, boolean plunge) {
            this.launch = launch;
            this.control = control;
            this.target = target;
            this.entityPos = entityPos;
            this.state = state;
            this.launchTick = launchTick;
            this.flightTicks = flightTicks;
            this.spinTurns = spinTurns;
            this.spinAxis = spinAxis;
            this.plunge = plunge;
        }
    }

    private static final class Flight {
        final ServerLevel level;
        final PendingSite site;
        final Runnable onComplete;
        final Vec3 mouth;
        final Vec3 surfaceCenter;
        final List<Piece> pieces;
        /** Age (ticks since open) at which the last piece has fully settled. */
        final int windowTicks;
        final boolean[] shakeFired = new boolean[SHAKE_AT.length];
        final boolean[] lightningFired = new boolean[LIGHTNING_AT.length];

        int age = -1;
        int lastLandingFxAge = -LANDING_FX_COOLDOWN_TICKS;
        boolean completed;
        int completedAge;
        boolean done;

        Flight(ServerLevel level, PendingSite site, Runnable onComplete) {
            this.level = level;
            this.site = site;
            this.onComplete = onComplete;
            this.surfaceCenter = surfaceCenterOf(level, site.anchor());
            this.mouth = new Vec3(this.surfaceCenter.x,
                    Math.max(this.surfaceCenter.y, site.anchor().getY()) + RIFT_MOUTH_HEIGHT,
                    this.surfaceCenter.z);
            this.pieces = buildPieces(level, site, this.mouth, this.surfaceCenter);
            int lastSettle = 0;
            for (Piece piece : this.pieces) {
                lastSettle = Math.max(lastSettle, piece.launchTick + piece.flightTicks + SETTLE_TICKS);
            }
            this.windowTicks = Math.max(1, lastSettle);
        }

        /** Delivery start: adaptive-width tear surge + drone + opening shake (the 0 % pulse). */
        void open() {
            float width = StructurePendingRegistry.revealRiftWidth(site.footprint());
            // Re-opening on top of the beat's tear REPLACES it (RiftFx double-send law) —
            // the tear visibly convulses and takes the server-computed adaptive width.
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, mouth, width, 0.0F, -1.0D);
            level.playSound(null, mouth.x, mouth.y, mouth.z, EclipseSounds.EVENT_RIFT_DRONE.get(),
                    SoundSource.BLOCKS, 1.0F, 1.0F);
            PacketDistributor.sendToPlayersNear(level, null, mouth.x, mouth.y, mouth.z, FX_RANGE,
                    S2CShakePayload.shake(0.25F, 14));
            if (site.footprint() >= CAPTION_FOOTPRINT) {
                PacketDistributor.sendToPlayersInDimension(level, new S2CCaptionPayload(
                        "eclipse.caption.expansion.delivery", 60, S2CCaptionPayload.STYLE_WHISPER));
            }
        }

        void tick() {
            this.age++;
            if (this.completed) {
                // Waiting for PLACED to sweep the displays; fall back after a while so a
                // failed placement can never leave ghost masonry behind.
                if (this.age - this.completedAge > DISCARD_FALLBACK_TICKS) {
                    discardDisplays();
                    this.done = true;
                }
                return;
            }
            if (this.age > WATCHDOG_TICKS) {
                EclipseMod.LOGGER.warn("StructureFlightFx: delivery of {} overstayed its watchdog — forcing placement",
                        site.siteId());
                discardDisplays();
                FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, mouth, 0.0F, 0.0F, -1.0D);
                this.done = true;
                this.onComplete.run();
                return;
            }
            fireWindowBeats();
            boolean launchedBatch = false;
            boolean allSettled = true;
            for (Piece piece : this.pieces) {
                if (this.age < piece.launchTick) {
                    allSettled = false;
                    continue;
                }
                if (piece.display == null && !piece.settled) {
                    spawn(piece);
                    launchedBatch = true;
                }
                if (!piece.settled) {
                    allSettled = false;
                    if (this.age % UPDATE_INTERVAL_TICKS == 0) {
                        animate(piece);
                    }
                }
            }
            if (launchedBatch) {
                level.playSound(null, mouth.x, mouth.y, mouth.z, EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                        SoundSource.BLOCKS, 0.9F, 0.85F + level.random.nextFloat() * 0.3F);
            }
            if (allSettled) {
                complete();
            }
        }

        /** Mid-flight shake pulses + scripted rim lightning at fixed window fractions. */
        private void fireWindowBeats() {
            for (int i = 0; i < SHAKE_AT.length; i++) {
                if (!this.shakeFired[i] && this.age >= (int) (SHAKE_AT[i] * this.windowTicks)) {
                    this.shakeFired[i] = true;
                    PacketDistributor.sendToPlayersNear(level, null, mouth.x, mouth.y, mouth.z,
                            FX_RANGE, S2CShakePayload.shake(0.2F + 0.08F * i, 12 + 2 * i));
                }
            }
            for (int i = 0; i < LIGHTNING_AT.length; i++) {
                if (!this.lightningFired[i] && this.age >= (int) (LIGHTNING_AT[i] * this.windowTicks)) {
                    this.lightningFired[i] = true;
                    double angle = ((site.siteId().hashCode() & 0xFFFF) / 65536.0D + i / (double) LIGHTNING_AT.length)
                            * Math.PI * 2.0D;
                    double radius = Math.max(4.0D, site.footprint() * 0.5D);
                    double x = surfaceCenter.x + Math.cos(angle) * radius;
                    double z = surfaceCenter.z + Math.sin(angle) * radius;
                    level.getChunk(Mth.floor(x) >> 4, Mth.floor(z) >> 4);
                    int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                            Mth.floor(x), Mth.floor(z));
                    Vec3 rim = new Vec3(x, Math.max(y, level.getMinBuildHeight() + 1), z);
                    FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, rim, 0.85F, 0.0F, -1.0D);
                    level.playSound(null, rim.x, rim.y, rim.z, EclipseSounds.EVENT_LIGHTNING_CLOSE.get(),
                            SoundSource.WEATHER, 0.9F, 0.9F + level.random.nextFloat() * 0.2F);
                }
            }
        }

        private void spawn(Piece piece) {
            Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
            display.setBlockState(piece.state);
            display.moveTo(piece.entityPos.x, piece.entityPos.y, piece.entityPos.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(poseAt(piece, 0.0F, 0.0F));
            LIVE_DISPLAYS.add(display.getUUID());
            level.addFreshEntity(display);
            piece.display = display;
        }

        private void animate(Piece piece) {
            Display.BlockDisplay display = piece.display;
            if (display == null || display.isRemoved()) {
                piece.settled = true; // chunk vanished under it: give up on this piece only
                return;
            }
            int pieceAge = this.age - piece.launchTick;
            if (pieceAge >= piece.flightTicks + SETTLE_TICKS) {
                if (piece.plunge) {
                    // Cavity delivery: the piece punches into the ground and is gone.
                    display.discard();
                    LIVE_DISPLAYS.remove(display.getUUID());
                    piece.display = null;
                } else {
                    display.setTransformationInterpolationDelay(0);
                    display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                    display.setTransformation(poseAt(piece, 1.0F, 1.0F));
                }
                piece.settled = true;
                return;
            }
            float flightT = Mth.clamp(pieceAge / (float) piece.flightTicks, 0.0F, 1.0F);
            float settleT = pieceAge <= piece.flightTicks ? 0.0F
                    : (pieceAge - piece.flightTicks) / (float) SETTLE_TICKS;
            if (flightT >= 1.0F && !piece.landed) {
                piece.landed = true;
                landingFx(piece);
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
            display.setTransformation(poseAt(piece, flightT, settleT));
        }

        /** Bass thud + small shake per landing, rate-limited so a hail cannot strobe. */
        private void landingFx(Piece piece) {
            if (this.age - this.lastLandingFxAge < LANDING_FX_COOLDOWN_TICKS) {
                return;
            }
            this.lastLandingFxAge = this.age;
            level.playSound(null, piece.target.x, piece.target.y, piece.target.z,
                    EclipseSounds.EVENT_RIFT_THUD.get(), SoundSource.BLOCKS,
                    0.7F, 0.5F + level.random.nextFloat() * 0.25F);
            PacketDistributor.sendToPlayersNear(level, null, piece.target.x, piece.target.y,
                    piece.target.z, FX_RANGE, S2CShakePayload.shake(0.12F, 8));
        }

        /** All pieces down: tear snaps shut, resolve chord, and the REAL placement runs. */
        private void complete() {
            this.completed = true;
            this.completedAge = this.age;
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, mouth, 0.0F, 0.0F, -1.0D);
            level.playSound(null, surfaceCenter.x, surfaceCenter.y, surfaceCenter.z,
                    EclipseSounds.EVENT_RIFT_RESOLVE.get(), SoundSource.BLOCKS, 1.0F, 1.0F);
            this.onComplete.run();
        }

        void discardDisplays() {
            for (Piece piece : this.pieces) {
                Display.BlockDisplay display = piece.display;
                if (display != null) {
                    LIVE_DISPLAYS.remove(display.getUUID());
                    if (!display.isRemoved()) {
                        display.discard();
                    }
                    piece.display = null;
                }
            }
        }
    }

    // ------------------------------------------------------------------ pose math

    /**
     * Piece pose for flight parameter {@code flightT} (0 = rift mouth, 1 = hover above the
     * cell) and {@code settleT} (0 = hovering, 1 = grid-exact rest). The entity itself
     * never moves — the world-space motion lives entirely in the transformation's
     * translation, the proven {@code DisplayPlacerService.applyAnimation} pattern (block
     * local space is {@code [0,1]³}; rotate the half-extent and translate back so spin
     * stays centered on the piece).
     */
    private static Transformation poseAt(Piece piece, float flightT, float settleT) {
        Vec3 center;
        Quaternionf rotation;
        if (settleT > 0.0F) {
            // Damped settle: drop out of the hover overshoot, dip a hair below the rest
            // height, ease back — the "overshoot-settle" read. Spin has fully damped out.
            float inv = 1.0F - settleT;
            float yOff = HOVER_OVERSHOOT * inv * inv
                    - 0.07F * Mth.sin((float) Math.PI * settleT);
            center = piece.target.add(0.0D, yOff, 0.0D);
            rotation = new Quaternionf();
        } else {
            // Ballistic Bezier, ease-out: pieces burst from the tear and decelerate into
            // the hover. Spin is N full turns on an eased curve — angular velocity decays
            // to zero (damping) and the final orientation is exactly grid-aligned.
            float eased = 1.0F - (1.0F - flightT) * (1.0F - flightT) * (1.0F - flightT);
            double u = 1.0D - eased;
            Vec3 hover = piece.target.add(0.0D, HOVER_OVERSHOOT, 0.0D);
            center = piece.launch.scale(u * u)
                    .add(piece.control.scale(2.0D * u * eased))
                    .add(hover.scale(eased * eased));
            float spinEased = 1.0F - (1.0F - flightT) * (1.0F - flightT);
            rotation = new Quaternionf().rotationAxis(
                    piece.spinTurns * Mth.TWO_PI * spinEased, piece.spinAxis);
        }
        float half = PIECE_SCALE * 0.5F;
        Vector3f corner = new Vector3f(-half, -half, -half).rotate(rotation);
        Vector3f translation = new Vector3f(
                (float) (center.x - piece.entityPos.x) + corner.x,
                (float) (center.y - piece.entityPos.y) + corner.y,
                (float) (center.z - piece.entityPos.z) + corner.z);
        return new Transformation(translation, rotation,
                new Vector3f(PIECE_SCALE, PIECE_SCALE, PIECE_SCALE), new Quaternionf());
    }

    // ------------------------------------------------------------------ piece planning

    /**
     * Plans the delivery: piece count scales with the footprint (capped by config),
     * landing cells are seeded-deterministically scattered over the footprint disc at
     * surface height, palettes are keyed by structureId. Deterministic per site — every
     * restartless replay of the same site looks identical on all clients.
     */
    private static List<Piece> buildPieces(ServerLevel level, PendingSite site, Vec3 mouth,
            Vec3 surfaceCenter) {
        RandomSource random = RandomSource.create(site.siteId().hashCode() * 31L + site.stage());
        int count = Math.min(Math.max(configMaxDisplays, 1),
                Math.max(10, (int) (site.footprint() * 1.25F)));
        boolean cavity = site.anchor().getY() < surfaceCenter.y - CAVITY_DEPTH;
        List<BlockState> palette = PALETTES.getOrDefault(site.structureId(), FALLBACK_PALETTE);
        float mouthScatter = Math.min(48.0F, StructurePendingRegistry.revealRiftWidth(site.footprint())) * 0.25F;
        double halfFootprint = Math.max(2.0D, site.footprint() * 0.5D * 0.85D);

        List<Piece> pieces = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            double angle = random.nextDouble() * Math.PI * 2.0D;
            double radius = Math.sqrt(random.nextDouble()) * halfFootprint;
            int x = Mth.floor(surfaceCenter.x + Math.cos(angle) * radius);
            int z = Mth.floor(surfaceCenter.z + Math.sin(angle) * radius);
            level.getChunk(x >> 4, z >> 4); // terrain phase already wrote these chunks
            int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
            if (y <= level.getMinBuildHeight()) {
                y = Mth.floor(surfaceCenter.y);
            }
            Vec3 entityPos = new Vec3(x + 0.5D, y, z + 0.5D);
            Vec3 target = new Vec3(x + 0.5D, y + PIECE_SCALE * 0.5D, z + 0.5D);
            Vec3 launch = mouth.add((random.nextDouble() - 0.5D) * mouthScatter * 2.0D,
                    -random.nextDouble() * 1.5D,
                    (random.nextDouble() - 0.5D) * mouthScatter * 2.0D);
            Vec3 control = launch.add(target).scale(0.5D)
                    .add((random.nextDouble() - 0.5D) * 8.0D,
                            6.0D + random.nextDouble() * 8.0D,
                            (random.nextDouble() - 0.5D) * 8.0D);
            // Surface-first weighting: index² biases hard toward the primary material.
            BlockState state = palette.get((int) (random.nextFloat() * random.nextFloat() * palette.size()));
            int launchTick = (i / BATCH_SIZE) * BATCH_STAGGER_TICKS;
            int flightTicks = MIN_FLIGHT_TICKS + random.nextInt(MAX_FLIGHT_TICKS - MIN_FLIGHT_TICKS + 1);
            float spinTurns = (1 + random.nextInt(2)) * (random.nextBoolean() ? 1.0F : -1.0F);
            Vector3f spinAxis = new Vector3f(random.nextFloat() - 0.5F, random.nextFloat() - 0.5F,
                    random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            pieces.add(new Piece(launch, control, target, entityPos, state, launchTick,
                    flightTicks, spinTurns, spinAxis, cavity));
        }
        return pieces;
    }

    /** Surface-snapped site center (mirror of ExpansionSequence.surfaceCenterOf). */
    private static Vec3 surfaceCenterOf(ServerLevel level, BlockPos anchor) {
        int x = anchor.getX();
        int z = anchor.getZ();
        level.getChunk(x >> 4, z >> 4);
        int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (surfaceY <= level.getMinBuildHeight()) {
            surfaceY = Math.max(anchor.getY(), level.getSeaLevel());
        }
        return new Vec3(x + 0.5D, surfaceY, z + 0.5D);
    }

    /** Curated "most visible blocks" per structure id (see class doc — surface-first). */
    private static Map<String, List<BlockState>> buildPalettes() {
        Map<String, List<BlockState>> palettes = new HashMap<>();
        palettes.put("minecraft:mansion", List.of(
                Blocks.DARK_OAK_PLANKS.defaultBlockState(), Blocks.DARK_OAK_LOG.defaultBlockState(),
                Blocks.COBBLESTONE.defaultBlockState(), Blocks.BIRCH_PLANKS.defaultBlockState()));
        palettes.put("minecraft:trial_chambers", List.of(
                Blocks.TUFF_BRICKS.defaultBlockState(), Blocks.POLISHED_TUFF.defaultBlockState(),
                Blocks.CHISELED_TUFF.defaultBlockState(), Blocks.COPPER_BLOCK.defaultBlockState()));
        palettes.put("minecraft:ancient_city", List.of(
                Blocks.DEEPSLATE_BRICKS.defaultBlockState(), Blocks.DEEPSLATE_TILES.defaultBlockState(),
                Blocks.DARK_OAK_PLANKS.defaultBlockState(), Blocks.SCULK.defaultBlockState()));
        palettes.put("minecraft:pillager_outpost", List.of(
                Blocks.DARK_OAK_PLANKS.defaultBlockState(), Blocks.DARK_OAK_LOG.defaultBlockState(),
                Blocks.COBBLESTONE.defaultBlockState()));
        palettes.put("minecraft:bastion_remnant", List.of(
                Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState(), Blocks.BLACKSTONE.defaultBlockState(),
                Blocks.GILDED_BLACKSTONE.defaultBlockState()));
        palettes.put("eclipse:desert_temple", List.of(
                Blocks.SANDSTONE.defaultBlockState(), Blocks.CUT_SANDSTONE.defaultBlockState(),
                Blocks.CHISELED_SANDSTONE.defaultBlockState()));
        palettes.put("eclipse:jungle_temple", List.of(
                Blocks.COBBLESTONE.defaultBlockState(), Blocks.MOSSY_COBBLESTONE.defaultBlockState(),
                Blocks.CHISELED_STONE_BRICKS.defaultBlockState()));
        palettes.put("eclipse:village_plains", List.of(
                Blocks.OAK_PLANKS.defaultBlockState(), Blocks.OAK_LOG.defaultBlockState(),
                Blocks.COBBLESTONE.defaultBlockState(), Blocks.WHITE_WOOL.defaultBlockState()));
        palettes.put("eclipse:hanging_court", List.of(
                Blocks.NETHER_BRICKS.defaultBlockState(), Blocks.CHISELED_NETHER_BRICKS.defaultBlockState(),
                Blocks.BASALT.defaultBlockState()));
        palettes.put("eclipse:fortress_core", List.of(
                Blocks.NETHER_BRICKS.defaultBlockState(), Blocks.RED_NETHER_BRICKS.defaultBlockState(),
                Blocks.CHISELED_NETHER_BRICKS.defaultBlockState()));
        palettes.put("eclipse:mineshaft", List.of(
                Blocks.OAK_PLANKS.defaultBlockState(), Blocks.OAK_FENCE.defaultBlockState(),
                Blocks.RAIL.defaultBlockState(), Blocks.COBWEB.defaultBlockState()));
        palettes.put("eclipse:monster_room", List.of(
                Blocks.MOSSY_COBBLESTONE.defaultBlockState(), Blocks.COBBLESTONE.defaultBlockState()));
        palettes.put("eclipse:collapsed_vault", List.of(
                Blocks.STONE_BRICKS.defaultBlockState(), Blocks.CRACKED_STONE_BRICKS.defaultBlockState(),
                Blocks.IRON_BARS.defaultBlockState()));
        palettes.put("eclipse:umbral_warrens", List.of(
                Blocks.DEEPSLATE_BRICKS.defaultBlockState(), Blocks.SCULK.defaultBlockState(),
                Blocks.DEEPSLATE_TILES.defaultBlockState()));
        palettes.put("eclipse:flooded_crypt", List.of(
                Blocks.PRISMARINE_BRICKS.defaultBlockState(), Blocks.DARK_PRISMARINE.defaultBlockState(),
                Blocks.STONE_BRICKS.defaultBlockState()));
        palettes.put("eclipse:glitch_reliquary", List.of(
                Blocks.PURPUR_BLOCK.defaultBlockState(), Blocks.OBSIDIAN.defaultBlockState(),
                Blocks.CRYING_OBSIDIAN.defaultBlockState()));
        palettes.put("eclipse:wizard_observatory", List.of(
                Blocks.STONE_BRICKS.defaultBlockState(), Blocks.AMETHYST_BLOCK.defaultBlockState(),
                Blocks.COPPER_BLOCK.defaultBlockState()));
        return Map.copyOf(palettes);
    }

    // ------------------------------------------------------------------ config

    /**
     * Optional {@code flight_fx} section of {@code config/eclipse/dungeons.json}
     * ({@code {"enabled": true, "max_displays": 80}}). Parsed here rather than in
     * {@code DungeonSpawners} — that file's parser stays owned by its package; a missing
     * section (the default) leaves the defaults untouched and writes nothing.
     */
    private static void loadConfig() {
        if (configLoaded) {
            return;
        }
        configLoaded = true;
        configEnabled = true;
        configMaxDisplays = DEFAULT_MAX_DISPLAYS;
        Path file = FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("dungeons.json");
        if (!Files.isRegularFile(file)) {
            return;
        }
        try {
            JsonObject root = JsonParser.parseString(
                    Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            if (root.has("flight_fx") && root.get("flight_fx").isJsonObject()) {
                JsonObject flightFx = root.getAsJsonObject("flight_fx");
                if (flightFx.has("enabled")) {
                    configEnabled = flightFx.get("enabled").getAsBoolean();
                }
                if (flightFx.has("max_displays")) {
                    configMaxDisplays = Math.max(1, Math.min(200, flightFx.get("max_displays").getAsInt()));
                }
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("StructureFlightFx: could not read flight_fx config; using defaults", e);
        }
    }
}
