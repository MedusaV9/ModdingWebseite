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
import dev.projecteclipse.eclipse.worldgen.structure.StructureBlockSampler;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.BlockParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Block;
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
 * rate-limited shake; lightning rolls over the footprint rim for the whole window (one
 * strike every {@value #LIGHTNING_INTERVAL_TICKS} ticks, each with its own distance-banded
 * crack/thunder — see {@link Flight#lightningSound}); when the last
 * piece settles the tear snaps shut, a resolve chord plays and the placer runs — the big
 * PLACED slam (shockwave + 0.4 shake) stays {@code ExpansionSequence}'s. The final-slam /
 * rift-open pulses of the sequence are untouched; this class only adds the in-between.</p>
 *
 * <p><b>Piece sampling (RIFT-FX rework)</b>: pieces are now the structure's ACTUAL
 * blocks. {@code StructureBlockSampler} dry-runs the site's deterministic vanilla
 * placement against a capturing level proxy and returns the topmost visible state of
 * each column at its final world cell — the delivery flies those exact states to those
 * exact cells (bottom-up, so walls assemble under roofs), holds the assembled preview
 * in place while the real placer runs, and sweeps it the moment the registry reports
 * {@link StructurePendingRegistry.Phase#PLACED} — the block displays track the real
 * placement 1:1 and vanish exactly when the game finishes placing. Sites without a
 * sampleable vanilla start (custom underground placers, failed dry run) fall back to
 * the legacy per-{@code structureId} palette scatter. Buried sample cells (and every
 * palette piece of a cavity site) get PLUNGING pieces that punch into the ground on
 * arrival instead of resting on it.</p>
 *
 * <p><b>Swirl phase (BD-STORM)</b>: between the arc and the settle every surface piece
 * dwells {@value #MIN_HOVER_TICKS}–{@value #MAX_HOVER_TICKS} ticks over its cell, riding
 * one closed orbit with a yaw wobble and a bob before snapping down — the "fall out of the
 * rift, float and swirl, then snap into place" read. The swirl terms all vanish at both
 * ends of the dwell, so it splices between the two existing phases without a pop and
 * {@code hoverTicks == 0} (every plunging cavity piece) is exactly the old motion.</p>
 *
 * <p><b>Craft pass (BD-STRUCT)</b>: keyframes lead by one update interval so the client
 * tween covers between poses (never trails); launches stagger in CENTER-OUT SPIRAL order
 * over the footprint; pieces emerge small and full-bright from the tear
 * ({@link DisplayBrightnessFx} ramp — stepped toward ambient mid-flight, cleared on
 * landing), grow into a ×{@value #SCALE_OVERSHOOT} hover overshoot that settles to ×1.0,
 * and land with a bottom-anchored 2-tick y-squash instead of dipping into the grid; the
 * landing thud/shake fires when the contact keyframe's interpolation ENDS, not at the
 * send tick. REPASS-BD: ore/crystal-bearing pieces hold a warmer block-light through the
 * mid-flight step (material-aware glow), and every touchdown kicks block-crumb dust
 * scaled by the material's mass (the thud/shake stay rate-limited; the dust never is).</p>
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

    /**
     * Default per-delivery display cap ({@code flight_fx.max_displays} overrides).
     * RIFT-FX: raised 80 → 140 (user: "MORE block displays"). BD-STORM: raised again
     * 140 → 640 (user: "VIEL mehr Block Displays, viel viel mehr") — with real sampled
     * blocks every display lands on a real cell, so the density directly reads as the
     * build materializing rather than as a sparse hail. See
     * {@link #HARD_MAX_DISPLAYS} for the ceiling this may never cross.
     */
    private static final int DEFAULT_MAX_DISPLAYS = 640;
    /**
     * Absolute per-delivery display ceiling, config included. Each display is one tracked
     * entity with a transformation packet every {@value #UPDATE_INTERVAL_TICKS} ticks, so
     * this is the number that bounds the delivery's bandwidth and entity-tracker cost —
     * raise it only together with a measurement.
     */
    private static final int HARD_MAX_DISPLAYS = 800;
    /** Transformation update cadence; interpolation duration matches (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 2;
    /**
     * Pieces per launch batch and the stagger between batches (spawn-cost smoothing).
     * BD-STORM: with up to {@value #HARD_MAX_DISPLAYS} pieces the old 8-per-6-ticks
     * cadence would have taken 600 ticks just to LAUNCH; the batches are wider and
     * tighter so a full-cap delivery still finishes launching inside ~60 ticks while
     * never spawning more than {@value #BATCH_SIZE} entities in a single tick.
     */
    private static final int BATCH_SIZE = 28;
    private static final int BATCH_STAGGER_TICKS = 2;
    /** Per-piece flight length range (plan: "30–60 t"). */
    private static final int MIN_FLIGHT_TICKS = 30;
    private static final int MAX_FLIGHT_TICKS = 60;
    /**
     * Per-piece hover dwell between the arc and the settle: the piece hangs over its cell
     * and swirls (BD-STORM — user: the pieces should "fall out of the rifts, float/swirl
     * briefly, then snap into place"). Zero restores the pre-BD-STORM instant settle.
     */
    private static final int MIN_HOVER_TICKS = 10;
    private static final int MAX_HOVER_TICKS = 26;
    /**
     * Hover swirl shape: the piece rides one full closed orbit of
     * {@value #HOVER_SWIRL_BLOCKS} blocks around its cell while yawing up to
     * ±{@value #HOVER_SWIRL_RADIANS} rad and bobbing ±{@value #HOVER_BOB_BLOCKS} blocks.
     * All three terms are exactly zero at hover start AND hover end, so the hover splices
     * into the arc's hover-overshoot pose and out into the settle without a pop.
     */
    private static final float HOVER_SWIRL_RADIANS = 0.55F;
    private static final float HOVER_BOB_BLOCKS = 0.18F;
    private static final double HOVER_SWIRL_BLOCKS = 0.30D;
    /** Damped-settle length after the hover overshoot. */
    private static final int SETTLE_TICKS = 6;
    /** Arc overshoot: pieces decelerate into a hover this far above the resting cell. */
    private static final float HOVER_OVERSHOOT = 0.35F;
    /** Display scale: slightly over 1 so a settled piece encloses the real block (no z-fight). */
    private static final float PIECE_SCALE = 1.02F;
    /** Scale craft: pieces emerge small from the tear and grow into the hover overshoot. */
    private static final float SCALE_EXIT = 0.85F;
    /** Overshoot-settle scale read: hover holds ×1.06, the settle eases it back to ×1.0. */
    private static final float SCALE_OVERSHOOT = 1.06F;
    /**
     * Settle fraction at which the dropping piece first meets its grid cell (where
     * {@code HOVER_OVERSHOOT·(1−s)² − 0.07·sin(πs)} crosses zero, ≈ 0.58). Ground
     * contact: the height offset clamps to 0 there and the remaining "dip" energy is
     * spent as a ~2-tick y-squash instead of sinking into the cell; the landing
     * thud/shake seam is scheduled for the END of the keyframe window that crosses it.
     */
    private static final float CONTACT_SETTLE_T = 0.58F;
    /** Landing squash floor: y-scale dips to this at contact, recovering by rest. */
    private static final float SQUASH_Y = 0.94F;
    /** Flight fraction at which the rift-exit full-bright steps down toward ambient. */
    private static final float GLOW_MID_FLIGHT_T = 0.55F;
    /**
     * Material-aware glow (REPASS-BD): ore/crystal-bearing pieces keep this much BLOCK
     * light through the mid-flight step (warm lightmap tone — embedded metal holding the
     * rift's heat) while plain masonry drops to {@value #GLOW_MID_BLOCK_PLAIN}. Same ≤ 3
     * brightness round-trips per piece — only the stepped-to value differs.
     */
    private static final int GLOW_MID_BLOCK_WARM = 13;
    private static final int GLOW_MID_BLOCK_PLAIN = 8;
    /** Landing dust particle count bounds — scaled by the piece material's mass. */
    private static final int DUST_MIN = 4;
    private static final int DUST_MAX = 14;
    /**
     * Launch-order spiral pitch (blocks of radius per full turn): pieces launch in
     * center-out order with an angular sweep inside each annulus — the delivery reads as
     * one deliberate outward spiral instead of a random hail.
     */
    private static final double SPIRAL_TURN_BLOCKS = 3.0D;
    /**
     * Rift-mouth altitude above the site surface. Mirrors the (private)
     * {@code ExpansionSequence.SKY_RIFT_HEIGHT} so the delivery surge re-opens the beat's
     * tear in place instead of tearing a second hole beside it. RIFT-FX: raised 26 → 44
     * with the sequence's constant (user: "rifts should spawn further up").
     */
    private static final int RIFT_MOUTH_HEIGHT = 44;
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
    /**
     * Rim lightning cadence (BD-STORM). The old fixed 3-strike script became a rolling
     * storm: strikes start at {@value #LIGHTNING_START_T} of the window and repeat every
     * {@value #LIGHTNING_INTERVAL_TICKS} ticks until the last piece settles, up to
     * {@value #LIGHTNING_MAX_STRIKES} of them. Every single one is sounded — see
     * {@link Flight#strikeRimLightning}.
     */
    private static final float LIGHTNING_START_T = 0.12F;
    private static final int LIGHTNING_INTERVAL_TICKS = 22;
    private static final int LIGHTNING_MAX_STRIKES = 14;
    /**
     * Lightning audio falloff bands. Inside {@value #LIGHTNING_CLOSE_RANGE} blocks a
     * player gets the dry {@code LIGHTNING_BOLT_IMPACT} crack plus a camera crack; out to
     * {@value #LIGHTNING_AUDIBLE_RANGE} they get {@code LIGHTNING_BOLT_THUNDER} rolled off
     * by distance (vanilla's own positional attenuation caps out at volume·16 blocks,
     * which is far too short for a 224-block delivery, hence the per-player pick).
     */
    private static final double LIGHTNING_CLOSE_RANGE = 48.0D;
    private static final double LIGHTNING_AUDIBLE_RANGE = 220.0D;
    /** Rim sweep step of successive strikes — never repeats a spot within the window. */
    private static final double GOLDEN_ANGLE = Math.PI * (3.0D - Math.sqrt(5.0D));
    /** Flight-window fractions of the mid-flight shake pulses (0 % fires in begin()). */
    private static final float[] SHAKE_AT = {0.40F, 0.80F};

    /** Deliveries that make no sense as flying masonry (weather / self-sequenced sites). */
    private static final Set<String> EXCLUDED_STRUCTURES = Set.of(
            "eclipse:fog_storm", "eclipse:stronghold_emergence");

    /**
     * Palette blocks that read as ore/crystal-bearing but emit no light of their own —
     * they glow WARM through the flight ({@link #GLOW_MID_BLOCK_WARM}). Blocks with a
     * real light emission (crying obsidian, sculk) qualify via {@code getLightEmission}
     * without being listed.
     */
    private static final Set<Block> ORE_GLOW_BLOCKS = Set.of(
            Blocks.COPPER_BLOCK, Blocks.GILDED_BLACKSTONE, Blocks.AMETHYST_BLOCK);

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
        /** Assigned after the center-out spiral sort of {@link #buildPieces}. */
        int launchTick;
        final int flightTicks;
        /** Hover dwell between arc and settle (BD-STORM swirl); 0 = settle immediately. */
        final int hoverTicks;
        /** Starting angle of the closed hover orbit — decorrelates neighbouring pieces. */
        final float hoverPhase;
        final float spinTurns;
        final Vector3f spinAxis;
        final boolean plunge;
        /** Ore/crystal-bearing material: holds a warmer block-light through the flight. */
        final boolean warmGlow;

        @Nullable
        Display.BlockDisplay display;
        boolean landed;
        boolean settled;
        /** Brightness ramp stage: 0 = rift-exit full-bright, 1 = mid-flight, 2 = cleared. */
        int glowStage;
        /** Flight age at which the contact keyframe's interpolation ENDS (−1 = unarmed). */
        int fxDueAge = -1;

        Piece(Vec3 launch, Vec3 control, Vec3 target, Vec3 entityPos, BlockState state,
                int flightTicks, int hoverTicks, float hoverPhase, float spinTurns,
                Vector3f spinAxis, boolean plunge) {
            this.launch = launch;
            this.control = control;
            this.target = target;
            this.entityPos = entityPos;
            this.state = state;
            this.flightTicks = flightTicks;
            this.hoverTicks = hoverTicks;
            this.hoverPhase = hoverPhase;
            this.spinTurns = spinTurns;
            this.spinAxis = spinAxis;
            this.plunge = plunge;
            this.warmGlow = state.getLightEmission() > 0 || ORE_GLOW_BLOCKS.contains(state.getBlock());
        }

        /** Ticks from launch to full rest: ballistic arc + hover swirl + damped settle. */
        int totalTicks() {
            return this.flightTicks + this.hoverTicks + SETTLE_TICKS;
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
        /** Rolling-storm cursor: strikes so far and the age the next one is due at. */
        int strikesFired;
        int nextStrikeAge;

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
                lastSettle = Math.max(lastSettle, piece.launchTick + piece.totalTicks());
            }
            this.windowTicks = Math.max(1, lastSettle);
            this.nextStrikeAge = (int) (LIGHTNING_START_T * this.windowTicks);
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
                // Landing seam: the thud/shake/brightness-clear fire when the contact
                // keyframe's interpolation ENDS on the client — never at the send tick.
                if (piece.fxDueAge >= 0 && this.age >= piece.fxDueAge) {
                    piece.fxDueAge = -1;
                    landingDust(piece); // per piece — the thud/shake below rate-limit
                    landingFx(piece);
                    if (piece.glowStage < 2 && piece.display != null && !piece.display.isRemoved()) {
                        DisplayBrightnessFx.clear(piece.display);
                    }
                    piece.glowStage = 2;
                }
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

        /** Mid-flight shake pulses + the rolling rim lightning storm over the window. */
        private void fireWindowBeats() {
            for (int i = 0; i < SHAKE_AT.length; i++) {
                if (!this.shakeFired[i] && this.age >= (int) (SHAKE_AT[i] * this.windowTicks)) {
                    this.shakeFired[i] = true;
                    PacketDistributor.sendToPlayersNear(level, null, mouth.x, mouth.y, mouth.z,
                            FX_RANGE, S2CShakePayload.shake(0.2F + 0.08F * i, 12 + 2 * i));
                }
            }
            if (this.strikesFired >= LIGHTNING_MAX_STRIKES || this.age < this.nextStrikeAge) {
                return;
            }
            strikeRimLightning(this.strikesFired);
            this.strikesFired++;
            this.nextStrikeAge = this.age + LIGHTNING_INTERVAL_TICKS;
        }

        /**
         * One rim strike: the FX ribbon, the world crack, and — the point of BD-STORM —
         * audio for EVERY strike rather than a single sting on three scripted beats. The
         * impact position walks the footprint rim on a golden-angle sweep seeded from the
         * site id, so strikes never stack and every replay of a site is identical.
         */
        private void strikeRimLightning(int index) {
            double angle = ((site.siteId().hashCode() & 0xFFFF) / 65536.0D) * Math.PI * 2.0D
                    + index * GOLDEN_ANGLE;
            double radius = Math.max(4.0D, site.footprint() * 0.5D);
            double x = surfaceCenter.x + Math.cos(angle) * radius;
            double z = surfaceCenter.z + Math.sin(angle) * radius;
            level.getChunk(Mth.floor(x) >> 4, Mth.floor(z) >> 4);
            int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                    Mth.floor(x), Mth.floor(z));
            Vec3 rim = new Vec3(x, Math.max(y, level.getMinBuildHeight() + 1), z);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, rim, 0.85F, 0.0F, -1.0D);
            lightningSound(rim);
        }

        /**
         * Distance-banded strike audio (user: "the lightning that strikes should have
         * sounds"). {@code level.playSound} covers listeners inside vanilla's positional
         * range with the dry impact crack layered over the modded sting; everyone else in
         * the dimension out to {@value #LIGHTNING_AUDIBLE_RANGE} blocks gets rolling
         * thunder attenuated by distance, so a delivery is audible across the disc without
         * being deafening at the rim. Close listeners also get a short camera crack.
         */
        private void lightningSound(Vec3 rim) {
            float pitch = 0.9F + level.random.nextFloat() * 0.2F;
            level.playSound(null, rim.x, rim.y, rim.z, EclipseSounds.EVENT_LIGHTNING_CLOSE.get(),
                    SoundSource.WEATHER, 0.9F, pitch);
            level.playSound(null, rim.x, rim.y, rim.z, SoundEvents.LIGHTNING_BOLT_IMPACT,
                    SoundSource.WEATHER, 1.0F, pitch);
            for (ServerPlayer player : level.players()) {
                double distance = player.position().distanceTo(rim);
                if (distance > LIGHTNING_AUDIBLE_RANGE) {
                    continue;
                }
                if (distance <= LIGHTNING_CLOSE_RANGE) {
                    PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.18F, 8));
                    continue; // the positional crack above already carries this listener
                }
                float falloff = (float) (1.0D - (distance - LIGHTNING_CLOSE_RANGE)
                        / (LIGHTNING_AUDIBLE_RANGE - LIGHTNING_CLOSE_RANGE));
                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                        Mth.clamp(0.15F + 0.75F * falloff, 0.0F, 1.0F),
                        0.55F + 0.25F * falloff);
            }
        }

        private void spawn(Piece piece) {
            Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
            display.setBlockState(piece.state);
            display.moveTo(piece.entityPos.x, piece.entityPos.y, piece.entityPos.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(poseAt(piece, 0.0F, 0.0F, 0.0F));
            // Brightness ramp stage 0: white-hot out of the luminous tear. The display
            // samples light at its GROUND entity anchor otherwise — sky pieces would
            // render ground-dim without the override. Steps down mid-flight, cleared on
            // landing (see tick()).
            DisplayBrightnessFx.set(display, 15, 15);
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
            if (pieceAge >= piece.totalTicks()) {
                if (piece.plunge) {
                    // Cavity delivery: the piece punches into the ground and is gone.
                    display.discard();
                    LIVE_DISPLAYS.remove(display.getUUID());
                    piece.display = null;
                } else {
                    display.setTransformationInterpolationDelay(0);
                    display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                    display.setTransformation(poseAt(piece, 1.0F, 1.0F, 1.0F));
                }
                piece.settled = true;
                return;
            }
            // Keyframe lead (the SanctumOrbitals transport law): the pushed pose is the
            // one this interpolation window ENDS on, so the client tween covers the gap
            // between keyframes instead of trailing one interval behind the server.
            int targetAge = Math.min(pieceAge + UPDATE_INTERVAL_TICKS, piece.totalTicks());
            // Three consecutive phases share one age axis: [0, flight) arc,
            // [flight, flight+hover) swirl, the remainder the damped settle.
            int settleStart = piece.flightTicks + piece.hoverTicks;
            float flightT = Mth.clamp(targetAge / (float) piece.flightTicks, 0.0F, 1.0F);
            float hoverT = piece.hoverTicks <= 0 || targetAge <= piece.flightTicks ? 0.0F
                    : Mth.clamp((targetAge - piece.flightTicks) / (float) piece.hoverTicks,
                            0.0F, 1.0F);
            float settleT = targetAge <= settleStart ? 0.0F
                    : (targetAge - settleStart) / (float) SETTLE_TICKS;
            if (piece.glowStage == 0 && flightT >= GLOW_MID_FLIGHT_T) {
                // Cooling: still sky-lit; plain masonry sheds its block glow while
                // ore/crystal-bearing pieces stay warm (material-aware, REPASS-BD).
                piece.glowStage = 1;
                DisplayBrightnessFx.set(display,
                        piece.warmGlow ? GLOW_MID_BLOCK_WARM : GLOW_MID_BLOCK_PLAIN, 15);
            }
            if (!piece.landed && settleT >= CONTACT_SETTLE_T) {
                // This window crosses ground contact — schedule the thud/shake seam for
                // the moment the interpolation ENDS (the visual touchdown), not now.
                piece.landed = true;
                piece.fxDueAge = this.age + UPDATE_INTERVAL_TICKS;
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
            display.setTransformation(poseAt(piece, flightT, hoverT, settleT));
        }

        /**
         * Block-crumb dust at the visual touchdown, scaled by the piece material's mass
         * (explosion resistance as the proxy: wool barely puffs, deepslate kicks a real
         * spray). Fires per landing — unlike the thud/shake it never rate-limits, the
         * per-piece dust IS the read that each piece really hit its own cell.
         */
        private void landingDust(Piece piece) {
            int count = Mth.clamp(
                    DUST_MIN + (int) piece.state.getBlock().getExplosionResistance(),
                    DUST_MIN, DUST_MAX);
            level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, piece.state),
                    piece.target.x, piece.entityPos.y + 0.1D, piece.target.z,
                    count, 0.45D, 0.08D, 0.45D, 0.06D);
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
     * cell), {@code hoverT} (0 → 1 across the swirl dwell) and {@code settleT} (0 =
     * hovering, 1 = grid-exact rest). The entity itself never moves — the world-space
     * motion lives entirely in the transformation's translation, the proven
     * {@code DisplayPlacerService.applyAnimation} pattern (block local space is
     * {@code [0,1]³}; rotate the half-extent and translate back so spin stays centered on
     * the piece).
     *
     * <p><b>Scale craft</b> (BD-STRUCT): pieces emerge at ×{@value #SCALE_EXIT} and grow
     * into the hover at ×{@value #SCALE_OVERSHOOT} on the flight ease; the settle eases
     * that overshoot back to ×1.0. Ground contact ({@code settleT ≥}
     * {@value #CONTACT_SETTLE_T}) clamps the height offset to zero — the piece never
     * sinks into its cell — and spends the residual drop as a ~2-tick y-squash to
     * {@value #SQUASH_Y} (with a half-strength x/z counter-bulge), anchored at the piece
     * BOTTOM so the base stays glued to the grid while the top compresses. The rest pose
     * is exactly uniform {@value #PIECE_SCALE}, byte-identical to pre-craft.</p>
     *
     * <p><b>Hover swirl</b> (BD-STORM): between arc and settle the piece rides one closed
     * orbit around its cell with a yaw wobble and a vertical bob. Every hover term is a
     * function that vanishes at {@code hoverT ∈ {0, 1}}, so the swirl inherits the arc's
     * end pose and hands the settle exactly the pose it used to start from — the phase is
     * purely additive and {@code hoverTicks == 0} reproduces the old two-phase motion.</p>
     */
    private static Transformation poseAt(Piece piece, float flightT, float hoverT, float settleT) {
        Vec3 center;
        Quaternionf rotation;
        float scaleXz;
        float scaleY;
        if (settleT <= 0.0F && hoverT > 0.0F && hoverT < 1.0F) {
            // Swirl dwell: one full revolution of radius HOVER_SWIRL_BLOCKS about the
            // hover point (the (cos θ − cos θ₀) form closes the loop exactly), a single
            // bob cycle, and a yaw that returns to grid-aligned before the settle.
            double theta = piece.hoverPhase + Mth.TWO_PI * hoverT;
            double swirlX = HOVER_SWIRL_BLOCKS * (Math.cos(theta) - Math.cos(piece.hoverPhase));
            double swirlZ = HOVER_SWIRL_BLOCKS * (Math.sin(theta) - Math.sin(piece.hoverPhase));
            float wave = Mth.sin(Mth.TWO_PI * hoverT);
            center = new Vec3(piece.target.x + swirlX,
                    piece.target.y + HOVER_OVERSHOOT + HOVER_BOB_BLOCKS * wave,
                    piece.target.z + swirlZ);
            rotation = new Quaternionf().rotationY(
                    HOVER_SWIRL_RADIANS * wave * Math.signum(piece.spinTurns));
            scaleXz = PIECE_SCALE * SCALE_OVERSHOOT;
            scaleY = scaleXz;
        } else if (settleT > 0.0F) {
            // Damped settle: drop out of the hover overshoot toward the rest height.
            // Spin has fully damped out (integer turns land grid-aligned).
            float inv = 1.0F - settleT;
            float yOff;
            if (piece.plunge) {
                // Cavity delivery: accelerating monotonic descent THROUGH the surface —
                // the piece is a full block deep when the settle ends and discards.
                yOff = HOVER_OVERSHOOT * inv * inv - 0.9F * settleT * settleT;
            } else {
                yOff = HOVER_OVERSHOOT * inv * inv
                        - 0.07F * Mth.sin((float) Math.PI * settleT);
                if (yOff < 0.0F) {
                    yOff = 0.0F; // contact: dip becomes squash, never grid intersection
                }
            }
            float base = PIECE_SCALE * (1.0F + (SCALE_OVERSHOOT - 1.0F) * inv * inv);
            // Cavity pieces PUNCH INTO the ground (deep dip, no squash) — they discard
            // at settle end; surface pieces spend the dip energy as the landing squash.
            float squash = piece.plunge ? 0.0F : Mth.sin((float) Math.PI
                    * Mth.clamp((settleT - CONTACT_SETTLE_T) / (1.0F - CONTACT_SETTLE_T), 0.0F, 1.0F));
            scaleY = base * (1.0F - (1.0F - SQUASH_Y) * squash);
            scaleXz = base * (1.0F + 0.5F * (1.0F - SQUASH_Y) * squash);
            // Bottom-anchored: center rides at yOff + half the (squashed) height above
            // the cell floor, so the base never lifts while the top compresses.
            center = new Vec3(piece.target.x,
                    piece.entityPos.y + yOff + scaleY * 0.5D, piece.target.z);
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
            float grow = PIECE_SCALE * (SCALE_EXIT + (SCALE_OVERSHOOT - SCALE_EXIT) * eased);
            scaleXz = grow;
            scaleY = grow;
        }
        Vector3f corner = new Vector3f(-scaleXz * 0.5F, -scaleY * 0.5F, -scaleXz * 0.5F)
                .rotate(rotation);
        Vector3f translation = new Vector3f(
                (float) (center.x - piece.entityPos.x) + corner.x,
                (float) (center.y - piece.entityPos.y) + corner.y,
                (float) (center.z - piece.entityPos.z) + corner.z);
        return new Transformation(translation, rotation,
                new Vector3f(scaleXz, scaleY, scaleXz), new Quaternionf());
    }

    // ------------------------------------------------------------------ piece planning

    /**
     * Plans the delivery. RIFT-FX: the primary path dry-runs the real placement via
     * {@link StructureBlockSampler} and flies the structure's ACTUAL blocks to their
     * exact resting cells (bottom-up spiral launch order — walls assemble under roofs);
     * the legacy palette scatter below remains the fallback for sites without a
     * sampleable vanilla start. Deterministic per site either way — every restartless
     * replay of the same site looks identical on all clients.
     */
    private static List<Piece> buildPieces(ServerLevel level, PendingSite site, Vec3 mouth,
            Vec3 surfaceCenter) {
        RandomSource random = RandomSource.create(site.siteId().hashCode() * 31L + site.stage());
        // Single choke point for the entity budget: nothing downstream may exceed it,
        // whatever the config says (BD-STORM raised the default close to the ceiling).
        int budget = Mth.clamp(configMaxDisplays, 1, HARD_MAX_DISPLAYS);
        List<StructureBlockSampler.Sample> samples =
                StructureBlockSampler.sampleVisible(level, site, budget);
        if (!samples.isEmpty()) {
            return buildSampledPieces(level, site, mouth, random, samples);
        }
        // The palette fallback scatters over the footprint rather than over real cells,
        // so it scales with area — 3× the old 1.25 density to match the sampled look.
        int count = Math.min(budget, Math.max(10, (int) (site.footprint() * 3.75F)));
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
            int flightTicks = MIN_FLIGHT_TICKS + random.nextInt(MAX_FLIGHT_TICKS - MIN_FLIGHT_TICKS + 1);
            float spinTurns = (1 + random.nextInt(2)) * (random.nextBoolean() ? 1.0F : -1.0F);
            Vector3f spinAxis = new Vector3f(random.nextFloat() - 0.5F, random.nextFloat() - 0.5F,
                    random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            pieces.add(new Piece(launch, control, target, entityPos, state,
                    flightTicks, hoverTicksOf(random, cavity), random.nextFloat() * Mth.TWO_PI,
                    spinTurns, spinAxis, cavity));
        }
        // Launch stagger: center-out SPIRAL order (BD-STRUCT — never a random hail).
        // Sort key = landing radius plus a fractional-turn angle term, so batches sweep
        // one revolution per SPIRAL_TURN_BLOCKS of radius growth: the footprint fills
        // as a single deliberate outward spiral. Pure function of the deterministic
        // targets and a stable sort — replays stay identical on every client.
        pieces.sort((a, b) -> Double.compare(
                spiralKey(a, surfaceCenter), spiralKey(b, surfaceCenter)));
        for (int i = 0; i < pieces.size(); i++) {
            pieces.get(i).launchTick = (i / BATCH_SIZE) * BATCH_STAGGER_TICKS;
        }
        return pieces;
    }

    /**
     * RIFT-FX sampled-block path: one piece per captured sample, flying the EXACT state
     * to the EXACT resting cell of the future structure. Buried cells (a sample more
     * than {@value #CAVITY_DEPTH} blocks under the current surface — cavity structures,
     * cellars) become plunging pieces that punch into the ground at their column instead
     * of hovering inside solid terrain. Launch order is bottom-up by
     * {@value #Y_BAND_BLOCKS}-block height bands with the center-out spiral inside each
     * band, so the build visibly assembles foundation-first.
     */
    private static List<Piece> buildSampledPieces(ServerLevel level, PendingSite site, Vec3 mouth,
            RandomSource random, List<StructureBlockSampler.Sample> samples) {
        float mouthScatter = Math.min(48.0F,
                StructurePendingRegistry.revealRiftWidth(site.footprint())) * 0.25F;
        List<Piece> pieces = new ArrayList<>(samples.size());
        double minY = Double.MAX_VALUE;
        for (StructureBlockSampler.Sample sample : samples) {
            int x = sample.pos().getX();
            int z = sample.pos().getZ();
            level.getChunk(x >> 4, z >> 4); // the sampler force-loaded these already
            int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
            boolean plunge = sample.pos().getY() < surfaceY - CAVITY_DEPTH;
            int cellY = plunge ? surfaceY : sample.pos().getY();
            Vec3 entityPos = new Vec3(x + 0.5D, cellY, z + 0.5D);
            Vec3 target = new Vec3(x + 0.5D, cellY + PIECE_SCALE * 0.5D, z + 0.5D);
            Vec3 launch = mouth.add((random.nextDouble() - 0.5D) * mouthScatter * 2.0D,
                    -random.nextDouble() * 1.5D,
                    (random.nextDouble() - 0.5D) * mouthScatter * 2.0D);
            Vec3 control = launch.add(target).scale(0.5D)
                    .add((random.nextDouble() - 0.5D) * 8.0D,
                            6.0D + random.nextDouble() * 8.0D,
                            (random.nextDouble() - 0.5D) * 8.0D);
            int flightTicks = MIN_FLIGHT_TICKS + random.nextInt(MAX_FLIGHT_TICKS - MIN_FLIGHT_TICKS + 1);
            float spinTurns = (1 + random.nextInt(2)) * (random.nextBoolean() ? 1.0F : -1.0F);
            Vector3f spinAxis = new Vector3f(random.nextFloat() - 0.5F, random.nextFloat() - 0.5F,
                    random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            pieces.add(new Piece(launch, control, target, entityPos, sample.state(),
                    flightTicks, hoverTicksOf(random, plunge), random.nextFloat() * Mth.TWO_PI,
                    spinTurns, spinAxis, plunge));
            minY = Math.min(minY, target.y);
        }
        // Bottom-up assembly: height bands launch in order, spiraling inside each band —
        // the structure grows out of its foundation instead of raining down at random.
        Vec3 center = new Vec3(mouth.x, 0.0D, mouth.z);
        double baseY = minY;
        pieces.sort((a, b) -> Double.compare(
                sampledLaunchKey(a, center, baseY), sampledLaunchKey(b, center, baseY)));
        for (int i = 0; i < pieces.size(); i++) {
            pieces.get(i).launchTick = (i / BATCH_SIZE) * BATCH_STAGGER_TICKS;
        }
        return pieces;
    }

    /**
     * Hover dwell of one piece. Plunging (cavity) pieces skip the swirl entirely — they
     * are meant to punch straight through the surface, and a hover inside solid terrain
     * would read as a piece stuck in the ground.
     */
    private static int hoverTicksOf(RandomSource random, boolean plunge) {
        return plunge ? 0
                : MIN_HOVER_TICKS + random.nextInt(MAX_HOVER_TICKS - MIN_HOVER_TICKS + 1);
    }

    /** Height of one bottom-up launch band of the sampled-block delivery (blocks). */
    private static final int Y_BAND_BLOCKS = 4;
    /** Spiral keys stay well under this, so bands can never interleave. */
    private static final double Y_BAND_KEY_STRIDE = 10_000.0D;

    /** Bottom-up band + in-band spiral ordering key of a sampled piece (see above). */
    private static double sampledLaunchKey(Piece piece, Vec3 center, double minY) {
        int band = (int) ((piece.target.y - minY) / Y_BAND_BLOCKS);
        return band * Y_BAND_KEY_STRIDE + spiralKey(piece, center);
    }

    /** Center-out spiral ordering key of a piece's landing cell (see buildPieces). */
    private static double spiralKey(Piece piece, Vec3 surfaceCenter) {
        double dx = piece.target.x - surfaceCenter.x;
        double dz = piece.target.z - surfaceCenter.z;
        double radius = Math.sqrt(dx * dx + dz * dz);
        double turn = (Math.atan2(dz, dx) / (Math.PI * 2.0D)) + 0.5D; // 0..1 around
        return radius + turn * SPIRAL_TURN_BLOCKS;
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
                    // RIFT-FX: ceiling raised 200 → 300 alongside the sampled-block rework.
                    // BD-STORM: the ceiling IS HARD_MAX_DISPLAYS now — the old literal 300
                    // sat below the new default and would have clamped it back down.
                    configMaxDisplays = Math.max(1,
                            Math.min(HARD_MAX_DISPLAYS, flightFx.get("max_displays").getAsInt()));
                }
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("StructureFlightFx: could not read flight_fx config; using defaults", e);
        }
    }
}
