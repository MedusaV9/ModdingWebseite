package dev.projecteclipse.eclipse.client.echo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import dev.projecteclipse.eclipse.woah.echogrove.EchoGroveLayout;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-05 client FX driver (plan §4.1/§4.2): the {@code eclipse:echo_grade}
 * Veil pipeline (GRADE band, registered from static init — the
 * {@code ChronoGradeFx}/{@code LimboAmbience} seam) plus the three WINDOWED
 * Photon loops (ground fog, spores, tree lights) driven through
 * {@link PhotonFxRegistry#ensureLoop}/{@code releaseLoop} on the
 * {@code ObservatoryAmbience} hysteresis schema.
 *
 * <p><b>Grade activation:</b> camera inside {@value #GRADE_FULL_DIST}→
 * {@value #GRADE_EDGE_DIST} blocks of the client-derived grove center
 * ({@link EchoGroveClientState#treeAnchor()} — payload once placed, layout
 * fallback otherwise) AND the physical build probe holds (chunk loaded and
 * {@code waxed_oxidized_copper_bulb} at tree-top — plan §2.2 no. 4). The
 * amount is slewed per tick, never popped.</p>
 *
 * <p><b>Warmth latch:</b> {@link #onFloodCue} is called by
 * {@code EchoPhotonFxRows}' flood leg (a = holdTicks, b = afterglow variant):
 * warmth eases 0→1 over ~20t, holds, then 1→0 over the last ~30t of the
 * window — the cold hollow turns golden exactly while the overlay pool is
 * grown. {@code AfterglowFloor} (0.18 once {@code finaleDone}) keeps the
 * post-finale grove permanently a touch warmer (plan §7.4).</p>
 *
 * <p><b>Music:</b> the music-box motif is server-sequenced from note-block
 * sounds ({@code MemoryFloodService} fallback, plan §6.1) — this class plays
 * no audio until {@code music/echo_music_box.ogg} ships; the latch hook is
 * where that playback will live.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EchoGroveFx {
    public static final ResourceLocation ECHO_GRADE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "echo_grade");

    /** Full grade inside this camera distance… */
    private static final double GRADE_FULL_DIST = 70.0D;
    /** …fading to zero here (plan §4.1: "Distanz-Hysterese 70→90"). */
    private static final double GRADE_EDGE_DIST = 90.0D;
    /** Per-tick slew toward the distance target (~90% in 12 ticks — the chrono ease). */
    private static final float AMOUNT_EASE = 0.18F;
    private static final float SNAP = 0.004F;
    /** Warmth ease rates: rise over ~20t, decay over ~30t (plan §3.5 timeline). */
    private static final float WARMTH_RISE = 1.0F / 20.0F;
    private static final float WARMTH_FALL = 1.0F / 30.0F;
    /** Warmth starts falling this many ticks before the flood window ends. */
    private static final int WARMTH_TAIL = 30;
    /** Post-finale permanent warmth floor (plan §7.4). */
    private static final float AFTERGLOW_FLOOR = 0.18F;

    /** Loop window: materialize/release hysteresis around the grove (plan §4.2). */
    private static final double LOOP_MATERIALIZE_DIST = 80.0D;
    private static final double LOOP_RELEASE_DIST = 100.0D;
    /** Probe / refused-spawn retry cadence (plan §4.2: 20t). */
    private static final int RETRY_TICKS = 20;
    /** Grade clock wrap (~1 h — the chrono_grade wrap pattern). */
    private static final int TIME_WRAP_TICKS = 72_000;

    private static float previousAmount;
    private static float amount;
    private static float previousWarmth;
    private static float warmth;
    /** Remaining flood-window ticks (< 0 = no flood latched). */
    private static int floodTicksLeft = -1;
    private static boolean loopsOpen;
    private static int retryCountdown;
    private static boolean probeOk;
    private static int probeCountdown;
    private static int clockTicks;

    static {
        VeilPostController.register(new VeilPostController.PipelineSpec(
                ECHO_GRADE_POST,
                VeilPostController.PipelinePriority.GRADE,
                EchoGroveFx::wantGrade,
                EchoGroveFx::feedGrade));
    }

    private EchoGroveFx() {}

    // ------------------------------------------------------------------ cue latch

    /**
     * {@code CUE_ECHO_FLOOD} latch ({@code EchoPhotonFxRows} custom leg):
     * {@code a} = hold ticks (160 normal / 600 finale), {@code b} = 1 for the
     * warmer afterglow variant. Also the future seam for the real
     * {@code music.echo_music_box} track (plan §6.1).
     */
    public static void onFloodCue(float a, float b) {
        floodTicksLeft = Math.max(80, (int) a);
    }

    /** Warmth right now (0..1) — read by {@code MemoryOrbRenderer} for its tint. */
    public static float warmth(float partialTick) {
        return Mth.lerp(partialTick, previousWarmth, warmth);
    }

    /** Eased grade amount (dev/QA introspection + renderer reads). */
    public static float amount(float partialTick) {
        return Mth.lerp(partialTick, previousAmount, amount);
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        previousAmount = amount;
        previousWarmth = warmth;
        if (level == null || level.dimension() != Level.OVERWORLD) {
            resetEase();
            closeLoops(false);
            return;
        }
        if (!minecraft.isPaused()) {
            clockTicks++;
            tickWarmth();
        }

        Vec3 anchor = EchoGroveClientState.treeAnchor();
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);

        // Physical build probe on a cadence (the ObservatoryAmbience law): the grade
        // and the loops both die instantly when the grove is erased or not yet built.
        if (--probeCountdown <= 0) {
            probeOk = probeBlockPresent(level);
            probeCountdown = RETRY_TICKS;
        }

        // Grade amount: 1 inside FULL, 0 at EDGE, slewed — never pops.
        float target = probeOk
                ? (float) Mth.clamp((GRADE_EDGE_DIST - Math.sqrt(distSq))
                        / (GRADE_EDGE_DIST - GRADE_FULL_DIST), 0.0D, 1.0D)
                : 0.0F;
        amount = amount + (target - amount) * AMOUNT_EASE;
        if (Math.abs(target - amount) < SNAP) {
            amount = target;
        }

        // Windowed loops (plan §4.2 #1–#3): 80/100 hysteresis, 20t retry cadence,
        // wholesale release on reducedFx (grade itself stays: world_grade convention).
        if (EclipseClientConfig.reducedFx() || !probeOk
                || distSq > square(loopsOpen ? LOOP_RELEASE_DIST : LOOP_MATERIALIZE_DIST)) {
            closeLoops(true);
            return;
        }
        if (minecraft.isPaused() || --retryCountdown > 0) {
            return;
        }
        loopsOpen = true;
        BlockPos tree = EchoGroveClientState.treeCenter();
        Vec3 floor = new Vec3(tree.getX() + 0.5D, tree.getY() + 0.6D, tree.getZ() + 0.5D);
        boolean fog = PhotonFxRegistry.ensureLoop(EchoPhotonFxRows.LOOP_GROUND_FOG, floor);
        boolean spores = PhotonFxRegistry.ensureLoop(EchoPhotonFxRows.LOOP_SPORES,
                floor.add(0.0D, 5.0D, 0.0D));
        boolean lights = PhotonFxRegistry.ensureLoop(EchoPhotonFxRows.LOOP_TREE_LIGHTS,
                floor.add(0.0D, EchoGroveLayout.TREE_HEIGHT * 0.5D, 0.0D));
        retryCountdown = fog && spores && lights ? 1 : RETRY_TICKS;
    }

    private static void tickWarmth() {
        float target;
        if (floodTicksLeft >= 0) {
            floodTicksLeft--;
            target = floodTicksLeft > WARMTH_TAIL ? 1.0F : 0.0F;
        } else {
            target = 0.0F;
        }
        float rate = target > warmth ? WARMTH_RISE : WARMTH_FALL;
        warmth = Mth.clamp(warmth + Math.signum(target - warmth) * rate, 0.0F, 1.0F);
        if (Math.abs(target - warmth) < rate) {
            warmth = target;
        }
    }

    /** Chunk loaded AND the tree-top copper bulb present (plan §2.2 no. 4). */
    private static boolean probeBlockPresent(ClientLevel level) {
        BlockPos probe = EchoGroveLayout.probePos(
                EchoGroveClientState.placed() ? EchoGroveClientState.treeCenter() : null);
        return level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                        SectionPos.blockToSectionCoord(probe.getZ()))
                && level.getBlockState(probe).is(Blocks.WAXED_OXIDIZED_COPPER_BULB);
    }

    // ------------------------------------------------------------------ grade row

    private static boolean wantGrade() {
        // Deliberately NOT reducedFx-gated (world_grade convention): the Detail
        // uniform carries the gate; the grade itself is the grove's identity.
        return Minecraft.getInstance().level != null && amount > 0.01F;
    }

    /** Allocation-free per-frame feeder (VeilPostController contract). */
    private static void feedGrade(PostPipeline pipeline) {
        float partialTick = Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
        pipeline.getUniform("Amount").setFloat(amount(partialTick));
        pipeline.getUniform("Warmth").setFloat(warmth(partialTick));
        pipeline.getUniform("AfterglowFloor").setFloat(
                EchoGroveClientState.finaleDone() ? AFTERGLOW_FLOOR : 0.0F);
        pipeline.getUniform("Time").setFloat(
                (clockTicks % TIME_WRAP_TICKS + partialTick) / 20.0F);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }

    // ------------------------------------------------------------------ teardown

    private static void closeLoops(boolean graceful) {
        if (loopsOpen) {
            PhotonFxRegistry.releaseLoop(EchoPhotonFxRows.LOOP_GROUND_FOG, graceful);
            PhotonFxRegistry.releaseLoop(EchoPhotonFxRows.LOOP_SPORES, graceful);
            PhotonFxRegistry.releaseLoop(EchoPhotonFxRows.LOOP_TREE_LIGHTS, graceful);
        }
        loopsOpen = false;
        retryCountdown = 0;
    }

    private static void resetEase() {
        amount = 0.0F;
        warmth = 0.0F;
        floodTicksLeft = -1;
        probeOk = false;
        probeCountdown = 0;
    }

    private static double square(double d) {
        return d * d;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        resetEase();
        previousAmount = 0.0F;
        previousWarmth = 0.0F;
        closeLoops(false);
    }
}
