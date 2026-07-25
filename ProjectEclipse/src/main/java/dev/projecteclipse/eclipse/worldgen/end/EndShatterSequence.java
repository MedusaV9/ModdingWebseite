package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import dev.projecteclipse.eclipse.worldgen.structure.SkyLauncher;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
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
 *       and every islet is translated by a per-islet vertical offset (−12…+16) as a
 *       budgeted copy-then-clear pass — the exact materialization writer shape
 *       (one chunk per tick, section writes, heightmap re-prime, relight + resend),
 *       just subtractive. The podium islet (r &lt; {@value #CENTER_KEEP_RADIUS}) never
 *       moves, so egg, portal and gathered watchers stay safe. Restart mid-shatter:
 *       the {@link ShatterData} cursor resumes the pass; the cinematic never
 *       resumes.</li>
 *   <li><b>Debris</b> — up to {@value #DEBRIS_CAP} tagged {@code block_display} chunks
 *       tumble off the seams into the void (in-memory animator, TTL-discarded, tag-swept
 *       at boot).</li>
 *   <li><b>End structures</b> — when the pass completes, the three largest outer islets
 *       receive {@link EndCityKit} sites (two towers + one end-ship, real loot + shulkers)
 *       through {@link StructurePendingRegistry}, so they get the standard rift
 *       reveals.</li>
 * </ol>
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
    /** Per-islet vertical offset bounds. */
    private static final int DY_MIN = -12;
    private static final int DY_RANGE = 28; // DY_MIN..DY_MIN+28 = −12..+16
    /** Debris display cap. */
    private static final int DEBRIS_CAP = 120;
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
    /** Crack stingers while the carve pass runs. */
    private static final int CRACK_INTERVAL_TICKS = 48;

    /** Seed-mix salts (local mixer — DiscTerrainFunction.hash is package-private). */
    private static final long SALT_LAYOUT = 91L;
    private static final long SALT_SEAM = 92L;
    private static final long SALT_DEBRIS = 93L;

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
    private static final List<Debris> DEBRIS = new ArrayList<>();

    /** One scheduled CUT-END presentation beat (delayed rumble, crack race, dust curtains). */
    private record Beat(long dueGameTime, Runnable action) {}

    /**
     * Pending presentation beats (server thread only). Purely cosmetic: a restart drops
     * them along with everything else transient — the cinematic never resumes (plan law).
     */
    private static final List<Beat> BEATS = new ArrayList<>();

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
            int seamWidth = 3 + (int) Math.floorMod(mix(this.seed ^ SALT_SEAM, lo, hi), 3L);
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
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeJob = null;
        DEBRIS.clear();
        BEATS.clear();
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (activeJob != null) {
            activeJob.tick();
        }
        if (!BEATS.isEmpty()) {
            tickBeats(server.overworld().getGameTime());
        }
        if (!DEBRIS.isEmpty()) {
            tickDebris();
        }
        if (server.getTickCount() % POLL_TICKS != 0) {
            return;
        }
        ShatterData state = ShatterData.get(server);
        if (state.started() || state.complete() || state.dueGameTime() < 0L) {
            return;
        }
        if (server.overworld().getGameTime() >= state.dueGameTime()) {
            beginShatter(server, state);
        }
    }

    /** Runs every due presentation beat (server thread; a restart simply drops them). */
    private static void tickBeats(long gameTime) {
        Iterator<Beat> iterator = BEATS.iterator();
        while (iterator.hasNext()) {
            Beat beat = iterator.next();
            if (gameTime >= beat.dueGameTime()) {
                iterator.remove();
                beat.action().run();
            }
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
        // (t 0.10 ≈ the same wall-clock instant, preload hold permitting) breaks true
        // silence instead of layering onto a wall of sound. (No sound-STOP mechanism
        // exists anywhere in the mod, so a real audio duck is not achievable — the hold is
        // built by scheduling, not by stopping.)
        BEATS.add(new Beat(now + SILENCE_HOLD_TICKS, () -> {
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
            BEATS.add(new Beat(now + SILENCE_HOLD_TICKS + (long) step * CRACK_RACE_STEP_TICKS, () -> {
                PacketDistributor.sendToPlayersNear(overworld, null, flash.x, flash.y, flash.z,
                        FX_RANGE, new S2CFxEventPayload(FX_RIFT_OPEN, flash, 6.0F, 0.0F));
                overworld.playSound(null, BlockPos.containing(flash),
                        EclipseSounds.EVENT_END_SHATTER_CRACK.get(), SoundSource.HOSTILE, 3.0F, pitch);
            }));
        }

        // CUT-END shot 3 (separation): dust curtains fall from the break faces and the
        // debris chunks start tumbling only when the carve pass is about to bite (beat 0 +
        // CARVE_DELAY_TICKS; the curtains land just ahead of it) — not at beat 0, when the
        // disc is still visibly whole.
        BEATS.add(new Beat(now + SEPARATION_FX_DELAY_TICKS, () -> {
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
            spawnDebris(overworld, layout);
        }));

        // Global orbit show; gather + preload + the C6-healed return come with global().
        Vec3 anchor = Vec3.atCenterOf(center);
        CutsceneService.play(CUTSCENE_ID, List.copyOf(server.getPlayerList().getPlayers()),
                anchor, null, CutsceneService.PlayOptions.global(CUTSCENE_VIEW_DISTANCE));

        activeJob = new Job(overworld, state, CARVE_DELAY_TICKS);
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
        int age;
        /** Dissolve brightness steps fired (brightness snaps → few, coarse, in-motion). */
        int dissolveStage;

        Debris(Display.BlockDisplay display, Vec3 origin, double vx, double vy0, double vz,
                Vector3f spinAxis, double spinRate, double spinPhase, double precessRate,
                float baseScale) {
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
        }

        /** World-space chunk-center of the drift arc at {@code age} ticks (closed form). */
        Vec3 driftAt(int age) {
            return new Vec3(this.origin.x + this.vx * age,
                    this.origin.y + fallAt(age),
                    this.origin.z + this.vz * age);
        }

        /** Fall offset: parabola under gravity-lite, capped at the terminal speed. */
        double fallAt(int age) {
            double tTerm = (DEBRIS_TERMINAL_FALL - this.vy0) / DEBRIS_GRAVITY;
            if (age <= tTerm) {
                return this.vy0 * age + 0.5D * DEBRIS_GRAVITY * age * age;
            }
            return this.vy0 * tTerm + 0.5D * DEBRIS_GRAVITY * tTerm * tTerm
                    + DEBRIS_TERMINAL_FALL * (age - tTerm);
        }
    }

    private static void spawnDebris(ServerLevel level, Layout layout) {
        long seed = layout.seed();
        int reach = DiscProfile.END_DISC_RADIUS;
        int spawned = 0;
        for (int x = -reach; x <= reach && spawned < DEBRIS_CAP; x += 5) {
            for (int z = -reach; z <= reach && spawned < DEBRIS_CAP; z += 5) {
                int bx = DiscProfile.END_DISC_CENTER_X + x;
                int bz = DiscProfile.END_DISC_CENTER_Z + z;
                if (!EndDiscGeometry.footprintContains(bx, bz)
                        || !layout.sample(bx, bz).seam()
                        || to01(mix(seed ^ SALT_DEBRIS, bx, bz)) > 0.45D) {
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
                Debris debris = new Debris(
                        new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level),
                        new Vec3(bx + 0.5D, y, bz + 0.5D),
                        x / dist * 0.10D + jitter * 0.06D,
                        0.06D,
                        z / dist * 0.10D - jitter * 0.06D,
                        axis, spinRate, h3 * Math.PI * 2.0D, precessRate,
                        (float) (0.70D + 0.45D * h2));
                if (!spawnDebrisDisplay(level, debris, block)) {
                    continue;
                }
                DEBRIS.add(debris);
                spawned++;
            }
        }
        EclipseMod.LOGGER.info("EndShatterSequence: {} debris displays drifting", spawned);
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
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(debrisPoseAt(debris, 0));
        return level.addFreshEntity(display);
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
            // shrunk the chunk out by then) or the drift arc sinking into the void fog.
            if (age >= DEBRIS_TTL_TICKS || display.isRemoved()
                    || debris.origin.y + debris.fallAt(age) < 200.0D) {
                display.discard();
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
                Vec3 drift = debris.driftAt(age);
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
     * drift point through the rotation (the SanctumOrbitals T·L·S math).
     */
    private static Transformation debrisPoseAt(Debris debris, int age) {
        float dissolveT = dissolveT(age);
        float scale = debris.baseScale * (1.0F - 0.97F * dissolveT * dissolveT);
        Vector3f axis = new Vector3f(debris.spinAxis)
                .rotateY((float) (debris.precessRate * age));
        Quaternionf rotation = new Quaternionf().rotationAxis(
                (float) (debris.spinPhase + debris.spinRate * age), axis);
        Vec3 drift = debris.driftAt(age);
        Vector3f translation = new Vector3f(
                (float) (drift.x - debris.origin.x),
                (float) (drift.y - debris.origin.y),
                (float) (drift.z - debris.origin.z));
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        translation.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /** Boot sweep of orphaned debris (a crash mid-cinematic persists the displays). */
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

    // --- restart-safe state (materialization SavedData pattern) ---

    /**
     * Shatter lifecycle, persisted as {@code data/eclipse_end_shatter.dat} in the
     * overworld storage. {@code dueGameTime} arms beat 0; {@code cursor} resumes the
     * carve pass at chunk granularity; {@code complete} is terminal.
     */
    public static final class ShatterData extends SavedData {
        public static final String DATA_NAME = "eclipse_end_shatter";

        private static final String TAG_DUE = "dueGameTime";
        private static final String TAG_STARTED = "started";
        private static final String TAG_CURSOR = "cursor";
        private static final String TAG_COMPLETE = "complete";

        private long dueGameTime = -1L;
        private boolean started;
        private long cursor;
        private boolean complete;

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
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putLong(TAG_DUE, this.dueGameTime);
            tag.putBoolean(TAG_STARTED, this.started);
            tag.putLong(TAG_CURSOR, this.cursor);
            tag.putBoolean(TAG_COMPLETE, this.complete);
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
    }
}
