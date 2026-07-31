package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * FX-Wave-13 N10 — <b>End-Statik</b>: near the End rift the image itself starts to fail. A
 * fine chromatic split tears through the frame in crackling bursts and the void bleeds
 * through wherever the picture is dark enough to let it.
 *
 * <p><b>Pipeline</b>: {@code eclipse:end_static}, FEATURE priority, registered with
 * {@link VeilPostController} from static init — the landed {@code UmbralVeinsFx} /
 * {@code GhostGradeFx} pattern (no hook in the controller was needed: {@code register} is
 * the open registration API). Uniforms {@code StaticStrength} / {@code Time} /
 * {@code Detail}; the clock comes from Java because Veil's {@code VeilRenderTime} does not
 * exist in pinwheel post shaders.</p>
 *
 * <p><b>Iris gating</b>: none of its own — {@link VeilPostController} hard-gates every row
 * through {@code EclipseIrisState.postFxAllowed()}. There is no world-space fallback by
 * design: a full-frame signal failure has no world-space analogue, and the disc's own
 * Photon garnish ({@code end_arrival2_rift_ambient}, {@code end_void_wisps}) already tells
 * the rift story in geometry.</p>
 *
 * <h2>The window: proximity to the {@code CUE_RIFT_AMBIENT} anchor</h2>
 * <p>{@code worldgen.end.EndRiftAmbient} re-fires {@code CUE_RIFT_AMBIENT} every 600 t at
 * {@code (centerX + 0.5, surfaceY + }{@value #ANCHOR_HEIGHT}{@code , centerZ + 0.5)} of
 * {@code EndConfig.current()} — and that config's geometry is pinned to the frozen
 * {@link DiscProfile} constants ({@code EndConfig.warnFixedGeometry} overrides any
 * user-supplied centre/surface with the {@code END_DISC_*} defaults). So the client can
 * reconstruct the EXACT same anchor with no packet and no server read; this class derives
 * it from {@link DiscProfile} rather than duplicating a wire field.</p>
 *
 * <p>The cue's own {@code PhotonFxRegistry} row belongs to {@code EndArrivalFxRows} and is
 * deliberately left untouched — a post-processing grade is not a Photon leg, and a second
 * row for the same logical id would be refused by the registry anyway.</p>
 *
 * <p><b>Materialization gate</b>: {@code EndRiftAmbient} only fires once
 * {@code EndFightState.materializationComplete()} is set, which is a server flag the client
 * cannot read — so the {@code SanctumLightfall}/{@code EndVoidWisps} physical-probe trick:
 * the static only runs while the disc-surface block at the centre column
 * ({@link EndDiscGeometry#surfaceYAt}) is loaded AND non-air, which is only ever true once
 * the disc exists. Re-probed on the {@value #PROBE_TICKS}-tick cadence; between probes the
 * proximity ramp still runs, so walking toward the rift is smooth.</p>
 *
 * <p><b>Ramp</b> (INTEGRATION.md §4): strength is a distance ramp — full inside
 * {@value #FULL_DIST} blocks of the anchor, nothing beyond {@value #FADE_DIST} — eased
 * toward its target at {@value #SLEW_PER_TICK}/tick so a chunk-load pop or a lagged
 * teleport can never snap the frame. At exactly 0 the row is dropped from the manager and
 * the shader is a bit-identical passthrough. Idle cost while far from the disc: one squared
 * distance per tick.</p>
 *
 * <p><b>reducedFx</b>: the pass keeps running but is capped at {@value #REDUCED_CEILING}
 * and fed {@code Detail} 0, which makes the shader time-invariant (no burst train, no
 * twinkle, no boiling grain). The rift still reads as a broken signal; nothing flickers.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EndStaticFx {
    public static final ResourceLocation END_STATIC_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "end_static");

    /** The rift ambient anchor floats this far above the disc surface (EndRiftAmbient). */
    private static final double ANCHOR_HEIGHT = 40.0D;
    /** Inside this distance of the rift anchor the static is at full strength (blocks). */
    private static final double FULL_DIST = 56.0D;
    /** …and beyond this one it is gone entirely (blocks). */
    private static final double FADE_DIST = 168.0D;
    private static final double FULL_DIST_SQ = FULL_DIST * FULL_DIST;
    private static final double FADE_DIST_SQ = FADE_DIST * FADE_DIST;
    /** Uniform slew per tick — full fade in/out in ~0.8 s; the frame never pops. */
    private static final float SLEW_PER_TICK = 0.06F;
    /** Below this the fade-out is over: drop the pass entirely (idle-skip, §3.5). */
    private static final float MIN_ACTIVE = 0.002F;
    /** Ceiling under reducedFx — the signal survives, the assault does not. */
    private static final float REDUCED_CEILING = 0.45F;
    /** Disc-materialization probe cadence in ticks (the EndVoidWisps cadence). */
    private static final int PROBE_TICKS = 40;
    /**
     * {@code Time} uniform wrap in ticks (100 s). Deliberately NOT the hour wrap the veins
     * use: every rate in the shader divides 100 s exactly (the crackle's 10 slots/s and
     * {@code gzVoidStars}' 5 s twinkle), so no cycle is ever cut mid-flight at the wrap —
     * the {@code glitch_void} ping-period law.
     */
    private static final int TIME_WRAP_TICKS = 2_000;

    /** True while the disc has been probed and found materialized. */
    private static boolean discPresent;
    /** The eased uniform; pause-frozen clock for the crackle. */
    private static float easedStatic;
    private static int staticTicks;
    private static int probeCountdown;

    static {
        // Feature rows register from static init (the W1 wiring note): the
        // @EventBusSubscriber scan loads this class during client mod construction, well
        // before any world can be joined.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                END_STATIC_POST,
                VeilPostController.PipelinePriority.FEATURE,
                EndStaticFx::wantEndStatic,
                EndStaticFx::feedEndStatic));
    }

    private EndStaticFx() {}

    // ------------------------------------------------------------------ pipeline row

    /** Active while anything is left of the eased ramp. */
    private static boolean wantEndStatic() {
        return Minecraft.getInstance().level != null && easedStatic > MIN_ACTIVE;
    }

    /** Per-frame feeder — no allocations (the {@link VeilPostController} contract). */
    private static void feedEndStatic(PostPipeline pipeline) {
        float partialTick = Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
        pipeline.getUniform("StaticStrength").setFloat(easedStatic);
        // Pause-frozen seconds: the crackle holds still on the pause screen like every other
        // eased FX clock.
        pipeline.getUniform("Time").setFloat(
                (staticTicks % TIME_WRAP_TICKS + partialTick) / 20.0F);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }

    // ------------------------------------------------------------------ state feed

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return; // hold the state, freeze the crackle clock (the eased-FX law)
        }
        staticTicks++;
        if (--probeCountdown <= 0) {
            probeCountdown = PROBE_TICKS;
            discPresent = discMaterialized(level);
        }
        advance(discPresent
                ? riftStrength(minecraft.gameRenderer.getMainCamera().getPosition())
                : 0.0F);
    }

    /** Slews {@link #easedStatic} toward {@code target} — the shared UmbralVeinsFx ease. */
    private static void advance(float target) {
        if (easedStatic < target) {
            easedStatic = Math.min(target, easedStatic + SLEW_PER_TICK);
        } else if (easedStatic > target) {
            easedStatic = Math.max(target, easedStatic - SLEW_PER_TICK);
        }
    }

    /**
     * Target strength from the camera's distance to the {@code CUE_RIFT_AMBIENT} anchor:
     * 1 inside {@value #FULL_DIST} blocks, smoothstepped to 0 at {@value #FADE_DIST}.
     * Standing on the disc centre sits at the anchor height ({@value #ANCHOR_HEIGHT}
     * blocks below it) and is therefore inside the full band; the rim reads about half.
     */
    private static float riftStrength(Vec3 camera) {
        double dx = camera.x - (DiscProfile.END_DISC_CENTER_X + 0.5D);
        double dy = camera.y - (DiscProfile.END_DISC_SURFACE_Y + ANCHOR_HEIGHT);
        double dz = camera.z - (DiscProfile.END_DISC_CENTER_Z + 0.5D);
        double distSq = dx * dx + dy * dy + dz * dz;
        if (distSq >= FADE_DIST_SQ) {
            return 0.0F;
        }
        float ramp = distSq <= FULL_DIST_SQ ? 1.0F
                : 1.0F - Mth.clamp((float) ((Math.sqrt(distSq) - FULL_DIST)
                        / (FADE_DIST - FULL_DIST)), 0.0F, 1.0F);
        ramp = ramp * ramp * (3.0F - 2.0F * ramp);
        return EclipseClientConfig.reducedFx() ? ramp * REDUCED_CEILING : ramp;
    }

    /**
     * Physical probe for the server-side materialization flag: the disc-surface block at the
     * centre column exists only once the disc has been built (the {@code EndVoidWisps} law).
     * An unloaded centre reads as "not there" and is simply re-probed.
     */
    private static boolean discMaterialized(ClientLevel level) {
        BlockPos probe = new BlockPos(DiscProfile.END_DISC_CENTER_X,
                EndDiscGeometry.surfaceYAt(DiscProfile.END_DISC_CENTER_X,
                        DiscProfile.END_DISC_CENTER_Z),
                DiscProfile.END_DISC_CENTER_Z);
        return level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                SectionPos.blockToSectionCoord(probe.getZ()))
                && !level.getBlockState(probe).isAir();
    }

    /** Disconnect/level-change reset — the static never leaks into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    private static void reset() {
        discPresent = false;
        easedStatic = 0.0F;
        probeCountdown = 0;
    }

    /** Dev/QA introspection: the eased {@code StaticStrength} currently on the wire. */
    public static float staticStrength() {
        return easedStatic;
    }
}
