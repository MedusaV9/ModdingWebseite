package dev.projecteclipse.eclipse.woah.mansiondome.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import dev.projecteclipse.eclipse.woah.mansiondome.DomeCues;
import dev.projecteclipse.eclipse.woah.mansiondome.MansionDomePayloads.S2CMansionDomePayload;
import dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeService;
import dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeState;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-01 §4.1 — client state hub of the mansion dome. Holds the last
 * {@link S2CMansionDomePayload} snapshot (dimension-gated — the login sync reaches every
 * dimension), eases {@code visibility} 0→1 on arm ({@code GlitchZoneFx} ease law) and
 * exposes the shared reads for {@link DomeShellRenderer} / {@link DomeBeamRenderer}.
 *
 * <p><b>Post row:</b> registers {@code eclipse:dome_shell} in the static init
 * ({@code StormVolumeFx} seam) at FEATURE priority — the outside garnish composites over
 * the grades and survives eviction against them; the INSIDE effect ({@code glitch_dome})
 * runs as TRANSITION through the automatic {@code GlitchZoneFx} row. Inside/outside are
 * mutually exclusive ({@link #shellPostStrength}), so this feature never adds more than
 * one concurrent fullscreen pass. Under {@code reducedFx} the pass stays off entirely
 * (motion-FX law) — the opaque CPU shell keeps covering.</p>
 *
 * <p><b>Loop windows (WINDOWED law, INTEGRATION.md §4):</b> the two Photon loops
 * ({@code dome_device_idle}, {@code dome_beam_base}) and the
 * {@code ambient.storm_dome_drone} shield hum open when the camera is inside
 * {@value #LOOP_MATERIALIZE_DIST} blocks of the device while ACTIVE and release at
 * {@value #LOOP_RELEASE_DIST} (hysteresis), on {@code reducedFx} (Photon only — the hum
 * is not motion FX), on dimension mismatch and on logout — the {@code SanctumLightfall}
 * pattern via {@link PhotonFxRegistry#ensureLoop}/{@link PhotonFxRegistry#releaseLoop}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
@OnlyIn(Dist.CLIENT)
public final class MansionDomeClient {
    public static final ResourceLocation DOME_SHELL_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "dome_shell");

    /** Camera is "inside" once this far under the shell radius (plan §4.1). */
    private static final double INSIDE_MARGIN = 1.5D;
    /** dome_shell strength ramp: 1 → 0 over this shell-distance band (plan §4.3b/§9). */
    private static final float POST_FADE_START = 450.0F;
    private static final float POST_FADE_END = 600.0F;
    /** Arm fade-in: visibility eases 0→1 over ~2 s (mirrors the server zone fade-in). */
    private static final float EASE_RATE = 0.10F;
    private static final float SNAP = 0.004F;
    /** Photon/hum window band around the device (hysteresis so the edge never flickers). */
    private static final double LOOP_MATERIALIZE_DIST = 48.0D;
    private static final double LOOP_RELEASE_DIST = 56.0D;
    /** Shell hard-off beat: the server shatter takes over at t30 (§5). */
    public static final int COLLAPSE_SHATTER_TICK = MansionDomeService.T_SHATTER;
    /** Beam top-down collapse runs t30 → t50 (§4.5). */
    public static final int COLLAPSE_BEAM_END_TICK = MansionDomeService.T_SHATTER + 20;

    // ------------------------------------------------------------------ synced snapshot
    private static byte status = MansionDomeState.STATUS_UNARMED;
    @Nullable
    private static ResourceLocation dimension;
    private static Vec3 centre = Vec3.ZERO;
    private static float shellRadius;
    private static BlockPos devicePos = BlockPos.ZERO;
    private static long collapseStartGameTime;

    // ------------------------------------------------------------------ eased client state
    private static float prevVisibility;
    private static float visibility;
    private static boolean inside;
    /** Pause-safe tick clock for the {@code Time} uniform (storm_volume convention). */
    private static int ticks;
    private static boolean loopsOpen;
    @Nullable
    private static DomeDroneSound drone;

    static {
        // Feature-owned registration (StormVolumeFx static-init seam).
        VeilPostController.register(new VeilPostController.PipelineSpec(
                DOME_SHELL_POST,
                VeilPostController.PipelinePriority.FEATURE,
                () -> shellPostStrength(partialTick()) > 0.01F,
                MansionDomeClient::feedShell));
    }

    private MansionDomeClient() {}

    // ------------------------------------------------------------------ payload entry

    /** FROZEN dispatch target of {@code eclipse:woah_dome/state} (client main thread). */
    public static void handle(S2CMansionDomePayload payload) {
        status = payload.status();
        dimension = payload.dimension();
        centre = Vec3.atCenterOf(payload.centre());
        shellRadius = payload.shellRadius();
        devicePos = payload.devicePos();
        collapseStartGameTime = payload.collapseStartGameTime();
        if (status == MansionDomeState.STATUS_UNARMED
                || status == MansionDomeState.STATUS_DESTROYED) {
            prevVisibility = 0.0F;
            visibility = 0.0F;
        }
    }

    // ------------------------------------------------------------------ renderer reads

    /** The dome exists in the CLIENT's current dimension (all visuals gate on this). */
    static boolean presentHere() {
        ClientLevel level = Minecraft.getInstance().level;
        return level != null && dimension != null
                && level.dimension().location().equals(dimension)
                && (status == MansionDomeState.STATUS_ACTIVE
                        || status == MansionDomeState.STATUS_COLLAPSING);
    }

    static byte status() {
        return status;
    }

    static Vec3 centre() {
        return centre;
    }

    static float shellRadius() {
        return shellRadius;
    }

    static BlockPos devicePos() {
        return devicePos;
    }

    /** Frame-smooth arm fade (0..1); collapse-beat cuts are handled by the renderers. */
    static float visibility(float partialTick) {
        return Mth.lerp(partialTick, prevVisibility, visibility);
    }

    /** Camera inside the bubble (shell + interior film swap, dome_shell off). */
    static boolean inside() {
        return inside;
    }

    /**
     * Ticks since the destruction sequence's t0, frame-smooth; {@code -1} while not
     * COLLAPSING. Drives the beam flicker/collapse and the shell pulse acceleration.
     */
    static float collapseElapsed(float partialTick) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || status != MansionDomeState.STATUS_COLLAPSING
                || collapseStartGameTime <= 0L) {
            return -1.0F;
        }
        return Math.max(0.0F,
                level.getGameTime() - collapseStartGameTime + partialTick);
    }

    /** Shared tick clock (pause-safe) for shader time + flicker hashes. */
    static float timeSeconds(float partialTick) {
        return (ticks + partialTick) / 20.0F;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            resetTransient();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        ticks++;
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        boolean present = presentHere();
        inside = present && camera.distanceTo(centre) < shellRadius - INSIDE_MARGIN;

        prevVisibility = visibility;
        float target = present ? 1.0F : 0.0F;
        float next = visibility + (target - visibility) * EASE_RATE;
        visibility = Math.abs(target - next) < SNAP ? target : next;

        tickLoopWindow(camera, present);
        tickDrone(minecraft, camera, present);
    }

    /** The 48-block Photon loop window at the device (SanctumLightfall hysteresis). */
    private static void tickLoopWindow(Vec3 camera, boolean present) {
        boolean wantOpen = present && status == MansionDomeState.STATUS_ACTIVE
                && !EclipseClientConfig.reducedFx();
        if (wantOpen) {
            double distSq = camera.distanceToSqr(Vec3.atCenterOf(devicePos));
            double band = loopsOpen ? LOOP_RELEASE_DIST : LOOP_MATERIALIZE_DIST;
            wantOpen = distSq <= band * band;
        }
        if (wantOpen) {
            loopsOpen = true;
            // Idle motes around the core (~1.5 above the stand), updraft at the antenna
            // top — the beam origin (devicePos.y + 2.4, §4.5).
            Vec3 base = Vec3.atCenterOf(devicePos);
            PhotonFxRegistry.ensureLoop(DomeCues.CUE_DOME_DEVICE_IDLE, base.add(0.0D, 1.0D, 0.0D));
            PhotonFxRegistry.ensureLoop(DomeCues.CUE_DOME_BEAM_BASE, base.add(0.0D, 1.9D, 0.0D));
        } else if (loopsOpen) {
            loopsOpen = false;
            PhotonFxRegistry.releaseLoop(DomeCues.CUE_DOME_DEVICE_IDLE, true);
            PhotonFxRegistry.releaseLoop(DomeCues.CUE_DOME_BEAM_BASE, true);
        }
    }

    /**
     * Shield-drone loop near the hull ({@code ambient.storm_dome_drone}, §6): positional,
     * anchored on the nearest shell point to the camera each tick, volume tied to hull
     * proximity × visibility. Not motion FX, so it plays under {@code reducedFx} too.
     */
    private static void tickDrone(Minecraft minecraft, Vec3 camera, boolean present) {
        boolean want = present && visibility > 0.05F
                && Math.abs(camera.distanceTo(centre) - shellRadius) < DomeDroneSound.AUDIBLE_DIST;
        if (want) {
            if (drone == null || drone.isStopped()) {
                drone = new DomeDroneSound();
                minecraft.getSoundManager().play(drone);
            }
        } else if (drone != null) {
            drone.end();
            drone = null;
        }
    }

    // ------------------------------------------------------------------ dome_shell post

    /**
     * Outside-garnish strength: 0 inside (mutual exclusivity with {@code glitch_dome}),
     * 0 under {@code reducedFx}, distance ramp 1→0 over the
     * {@value #POST_FADE_START}→{@value #POST_FADE_END} shell-distance band, and a
     * subtle accelerating pulse during the collapse (t0–t30; the CPU shell mirrors it).
     */
    private static float shellPostStrength(float partialTick) {
        if (!presentHere() || inside || EclipseClientConfig.reducedFx()) {
            return 0.0F;
        }
        float elapsed = collapseElapsed(partialTick);
        if (elapsed >= COLLAPSE_SHATTER_TICK) {
            return 0.0F; // Shatter beat: the shard show owns the screen from here.
        }
        Vec3 camera = Minecraft.getInstance().gameRenderer.getMainCamera().getPosition();
        float shellDist = (float) Math.abs(camera.distanceTo(centre) - shellRadius);
        float strength = (1.0F - smoothstep(POST_FADE_START, POST_FADE_END, shellDist))
                * visibility(partialTick);
        if (elapsed >= 0.0F) {
            float urgency = elapsed / COLLAPSE_SHATTER_TICK;
            strength *= 1.0F + 0.25F * urgency
                    * Mth.sin(timeSeconds(partialTick) * (8.0F + 24.0F * urgency));
        }
        return Mth.clamp(strength, 0.0F, 1.0F);
    }

    /** Per-frame uniform feeder (render thread, zero allocations). */
    private static void feedShell(PostPipeline pipeline) {
        float partialTick = partialTick();
        float strength = shellPostStrength(partialTick);
        pipeline.getUniform("Strength").setFloat(strength);
        if (strength <= 0.0F) {
            return; // No-op frame around activation edges (StormVolumeFx pattern).
        }
        // VolCenter law: camera-relative subtraction in doubles, floats only at the end.
        Vec3 camera = Minecraft.getInstance().gameRenderer.getMainCamera().getPosition();
        pipeline.getUniform("DomeCenter").setVector(
                (float) (centre.x - camera.x),
                (float) (centre.y - camera.y),
                (float) (centre.z - camera.z));
        pipeline.getUniform("DomeRadius").setFloat(shellRadius);
        pipeline.getUniform("Time").setFloat(timeSeconds(partialTick));
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }

    // ------------------------------------------------------------------ housekeeping

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        resetTransient();
        // Full reset: the next server sends a fresh login snapshot.
        status = MansionDomeState.STATUS_UNARMED;
        dimension = null;
        centre = Vec3.ZERO;
        shellRadius = 0.0F;
        devicePos = BlockPos.ZERO;
        collapseStartGameTime = 0L;
    }

    /**
     * Respawn/dimension change: drop windows + easing but KEEP the snapshot — the server
     * re-sends it on {@code PlayerChangedDimensionEvent}, and the dimension gate keeps
     * all visuals off while it does not match.
     */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        resetTransient();
    }

    private static void resetTransient() {
        prevVisibility = 0.0F;
        visibility = 0.0F;
        inside = false;
        if (loopsOpen) {
            loopsOpen = false;
            PhotonFxRegistry.releaseLoop(DomeCues.CUE_DOME_DEVICE_IDLE, false);
            PhotonFxRegistry.releaseLoop(DomeCues.CUE_DOME_BEAM_BASE, false);
        }
        if (drone != null) {
            drone.end();
            drone = null;
        }
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }

    /**
     * The shield hum: follows the nearest hull point to the camera, volume ramps in over
     * the last {@value #AUDIBLE_DIST} blocks to the shell surface (the BeamHumSound
     * chassis, position derived instead of fixed).
     */
    private static final class DomeDroneSound extends AbstractTickableSoundInstance {
        static final float AUDIBLE_DIST = 48.0F;
        private static final float MAX_VOLUME = 0.85F;

        private DomeDroneSound() {
            super(EclipseSounds.AMBIENT_STORM_DOME_DRONE.get(), SoundSource.AMBIENT,
                    SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
        }

        @Override
        public void tick() {
            if (!presentHere()) {
                stop();
                return;
            }
            Vec3 camera = Minecraft.getInstance().gameRenderer.getMainCamera().getPosition();
            Vec3 toCamera = camera.subtract(centre);
            double dist = toCamera.length();
            // Nearest hull point (camera direction × radius; centre fallback underneath).
            Vec3 anchor = dist > 1.0E-3D
                    ? centre.add(toCamera.scale(shellRadius / dist))
                    : centre.add(0.0D, shellRadius, 0.0D);
            this.x = anchor.x;
            this.y = anchor.y;
            this.z = anchor.z;
            float shellDist = (float) Math.abs(dist - shellRadius);
            this.volume = MAX_VOLUME * visibility
                    * Mth.clamp(1.0F - shellDist / AUDIBLE_DIST, 0.0F, 1.0F);
        }

        /** External stop (window close/disconnect — BeamHumSound.end pattern). */
        void end() {
            this.stop();
        }
    }
}
