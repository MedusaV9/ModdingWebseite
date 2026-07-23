package dev.projecteclipse.eclipse.cutscene.client;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.cutscene.PathSampler;
import dev.projecteclipse.eclipse.network.C2SCutsceneStatePayload;
import dev.projecteclipse.eclipse.network.S2CCutscenePlayPayload;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import foundry.veil.api.client.util.Easing;
import net.minecraft.client.Camera;
import net.minecraft.client.CameraType;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.ViewportEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The client camera director: evaluates the active {@link CutscenePath} every render frame
 * and overrides the vanilla camera.
 *
 * <p><b>Override technique</b> ({@code docs/ideas/05_systems.md} §1): the primary hook is
 * {@code client.mixin.CameraMixin} — an {@code @Inject} at the TAIL of {@code Camera#setup}
 * calling the AT-widened {@code setPosition(Vec3)}/{@code setRotation(yaw, pitch, roll)}
 * (NeoForge patches roll support into {@code Camera} directly). The
 * {@link ViewportEvent.ComputeCameraAngles} handler applies the same yaw/pitch/roll as a
 * redundancy/fallback if another mixin wins the setup TAIL, and
 * {@link ViewportEvent.ComputeFov} drives the per-keyframe FOV. During a flight the camera
 * type is switched to {@code THIRD_PERSON_BACK} (own body renders in frame) and restored
 * afterwards.</p>
 *
 * <p><b>Path evaluation</b> (P2 R12): position via <b>arc-length reparameterized</b>
 * Catmull-Rom (default) or damped Hermite ({@code "bezier"}) — a {@link PathSampler} with a
 * per-segment {@value PathSampler#LUT_SAMPLES}-sample LUT is built at flight start, so the
 * eased segment progress covers <i>distance</i>, not raw spline parameter, and travel speed
 * never pumps between unevenly spaced keyframes. Orientation: quaternion slerp of
 * per-keyframe yaw/pitch/roll, or — when keyframes carry {@code lookAt} targets ({@code
 * [x,y,z]}, {@code "anchor:<id>"} via {@link FxAnchors}, or {@code "player"}) — a live aim at
 * the (interpolated) target, slerp-smoothed at ≤ {@value #MAX_LOOK_TURN_DEG_PER_SEC}°/s so
 * target hand-offs never whip the camera. Player-anchored paths ({@code anchor:"player"})
 * treat keyframe positions as offsets rotated by the player's yaw at start, and keyframe
 * yaws as relative to it; world-anchored paths use absolute coordinates unless the play
 * payload supplied an anchor origin (e.g. {@code unlock_ring}'s ring edge).</p>
 *
 * <p><b>Path events</b>: {@code sound} (UI one-shot), {@code caption} (routed into
 * {@link CaptionRenderer#enqueue}), {@code fade} ({@link CaptionRenderer#fade}) and
 * {@code shake} (a decaying 2-octave-noise impulse; strength/ticks/freq from the event
 * data) — see the {@link CutscenePath} schema notes.</p>
 *
 * <p><b>Safety</b>: a missing/foreign-dimension path ACKs {@code FINISHED} instantly so the
 * server-side freeze always releases; a disconnect mid-flight stops silently (the server's
 * logout hook + watchdog clean up). Timing is wall-clock ({@code System.nanoTime}), matching
 * the server watchdog's tick budget.</p>
 *
 * <p><b>End-of-flight blend</b>: a NATURALLY completed flight (progress &ge; 1.0) does not
 * hard-snap back to gameplay — the final evaluated shot eases into the live vanilla camera
 * over ~{@value #END_BLEND_TICKS} ticks ({@link #beginEndBlend}). Purely cosmetic client
 * state: the {@code FINISHED} ACK is still sent at progress 1.0 and all cutscene state
 * (letterbox, HUD suppression, camera type) is already cleared when the blend starts.
 * Skips, server {@code STOP}s and disconnects keep the instant snap.</p>
 *
 * <p><b>Shake impulses</b> (W4 contract): each {@code S2CCutscenePayload(SHAKE)} receipt is
 * one ~2 s decaying camera-shake impulse ({@link #addShakeImpulse()}), applied as position +
 * roll noise both during cutscene flights and over the normal gameplay camera (intro fusion
 * rumble). The noise itself is 2-octave value noise (P2 R12) — a slow sway with a faster
 * shudder on top — with a per-impulse frequency multiplier, so path-event shakes can range
 * from a heavy rumble to a sharp rattle.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CameraDirector {
    private static final long TICK_NANOS = 50_000_000L;
    /** One shake impulse: ~2 s quadratic decay. */
    private static final long SHAKE_DURATION_NANOS = 2_000_000_000L;
    private static final float SHAKE_MAX_OFFSET = 0.16F;
    private static final float SHAKE_MAX_ROLL_DEG = 1.1F;
    /** LookAt slerp smoothing cap (P2 R12 frozen: 90°/s). */
    private static final float MAX_LOOK_TURN_DEG_PER_SEC = 90.0F;
    /** A shot evaluated within this window is reused by later same-frame hooks. */
    private static final long SHOT_CACHE_NANOS = 8_000_000L;

    /** Fully evaluated camera state for the current frame. */
    private record Shot(Vec3 pos, float yaw, float pitch, float roll, float fov) {}

    @Nullable
    private static CutscenePath path;
    /** Arc-length sampler for {@link #path} (built at flight start; null in lockstep with path). */
    @Nullable
    private static PathSampler sampler;
    private static boolean allowSkip;
    private static long startNanos;
    /** World origin the keyframes are relative to (player feet, payload anchor, or 0,0,0). */
    private static Vec3 anchorPos = Vec3.ZERO;
    /** Player yaw at start for {@code anchor:"player"} paths; 0 otherwise. */
    private static float anchorYawDeg;
    private static List<CutscenePath.PathEvent> pendingEvents = List.of();
    private static int firedEvents;
    @Nullable
    private static CameraType previousCameraType;

    // --- lookAt smoothing + per-frame shot cache (fresh eval in the camera-setup hook) ---
    /** Last frame's final orientation — the slerp-smoothing anchor for lookAt aims. */
    private static final Quaternionf LAST_ORIENTATION = new Quaternionf();
    private static boolean haveLastOrientation;
    private static long lastFreshNanos;
    @Nullable
    private static Shot cachedShot;
    private static long cachedShotNanos;

    /** One live shake impulse: quadratic decay of {@code strength} over {@code durationNanos}. */
    private record ShakeImpulse(long startNanos, float strength, long durationNanos, float freq) {}

    /** Live shake impulses, oldest first (expired ones are pruned lazily). Main-thread only. */
    private static final ArrayDeque<ShakeImpulse> SHAKE_IMPULSES = new ArrayDeque<>();

    /** End-of-flight blend length (~0.6 s) — natural completions only. */
    private static final int END_BLEND_TICKS = 12;
    private static final long END_BLEND_NANOS = END_BLEND_TICKS * TICK_NANOS;

    /** Final evaluated shot of a naturally completed flight; {@code null} = no blend live. */
    @Nullable
    private static Shot endBlendFrom;
    private static long endBlendStartNanos;

    private CameraDirector() {}

    // --- payload entry points (called from EclipsePayloads on the client main thread) ---

    /** Handles a {@code S2CCutscenePlayPayload}: start a flight, or the STOP sentinel. */
    public static void handlePlay(S2CCutscenePlayPayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        if (payload.isStop()) {
            if (path != null) {
                EclipseMod.LOGGER.info("CameraDirector: server stop for '{}'", path.id());
                stop(minecraft);
            }
            return;
        }
        CutscenePath requested = ClientCutsceneLibrary.get(payload.id());
        if (requested == null || requested.keyframes().size() < 2) {
            EclipseMod.LOGGER.warn("CameraDirector: path '{}' missing/degenerate — ACK FINISHED instantly",
                    payload.id());
            ackFinished(payload.id());
            return;
        }
        if (minecraft.level == null || minecraft.player == null
                || !requested.dimension().equals(minecraft.level.dimension().location().toString())) {
            EclipseMod.LOGGER.info("CameraDirector: '{}' targets dimension {} but we are elsewhere — "
                    + "ACK FINISHED instantly", payload.id(), requested.dimension());
            ackFinished(payload.id());
            return;
        }

        if (path == null) {
            previousCameraType = minecraft.options.getCameraType();
            minecraft.options.setCameraType(CameraType.THIRD_PERSON_BACK);
        }
        path = requested;
        sampler = PathSampler.of(requested);
        endBlendFrom = null; // a new flight overrides any still-running end blend
        haveLastOrientation = false;
        cachedShot = null;
        allowSkip = payload.allowSkip();
        startNanos = System.nanoTime();
        lastFreshNanos = startNanos;
        firedEvents = 0;
        List<CutscenePath.PathEvent> events = new ArrayList<>(requested.events());
        events.sort(java.util.Comparator.comparingDouble(CutscenePath.PathEvent::t));
        pendingEvents = events;
        if (requested.isPlayerAnchored()) {
            anchorPos = minecraft.player.position();
            anchorYawDeg = minecraft.player.getYRot();
        } else {
            anchorPos = payload.anchor().orElse(Vec3.ZERO);
            anchorYawDeg = 0.0F;
        }
        LetterboxLayer.setActive(requested.letterbox(), allowSkip);
        PacketDistributor.sendToServer(
                new C2SCutsceneStatePayload(requested.id(), C2SCutsceneStatePayload.State.STARTED));
        EclipseMod.LOGGER.info("CameraDirector: playing '{}' ({} ticks, anchor {} @ {}, allowSkip {})",
                requested.id(), requested.durationTicks(), requested.anchor(), anchorPos, allowSkip);
    }

    /** One decaying ~2 s shake impulse (W4's {@code SHAKE} phase pulses; path events later). */
    public static void addShakeImpulse() {
        addShakeImpulse(1.0F, (int) (SHAKE_DURATION_NANOS / TICK_NANOS));
    }

    /**
     * One decaying shake impulse of the given {@code strength} over {@code ticks} (W12's
     * {@code S2CShakePayload} — the Ferryman's gunwale slam). Applied whether or not a
     * cutscene flight is active.
     */
    public static void addShakeImpulse(float strength, int ticks) {
        addShakeImpulse(strength, ticks, 1.0F);
    }

    /**
     * Full form (P2 R12 path events): {@code freq} scales the 2-octave noise frequency —
     * &lt; 1 reads as a heavy ground rumble, &gt; 1 as a sharp rattle.
     */
    public static void addShakeImpulse(float strength, int ticks, float freq) {
        SHAKE_IMPULSES.addLast(new ShakeImpulse(System.nanoTime(),
                Math.max(0.0F, strength), Math.max(1, ticks) * TICK_NANOS,
                Mth.clamp(freq, 0.1F, 8.0F)));
    }

    // --- state queries (input swallow + letterbox) ---

    public static boolean isActive() {
        return path != null;
    }

    /** Whether non-whitelisted HUD layers should be cancelled right now. */
    public static boolean isHudSuppressed() {
        CutscenePath active = path;
        return active != null && active.hideHud();
    }

    /** ESC/Space entry point: asks the server to end the flight (it validates allowSkip). */
    public static void requestSkip() {
        CutscenePath active = path;
        if (active == null) {
            return;
        }
        EclipseMod.LOGGER.info("CameraDirector: requesting skip of '{}'", active.id());
        PacketDistributor.sendToServer(
                new C2SCutsceneStatePayload(active.id(), C2SCutsceneStatePayload.State.SKIP_REQUEST));
    }

    // --- camera override hooks ---

    /**
     * Called from {@code CameraMixin} at the TAIL of {@code Camera#setup} every frame.
     * During an end blend the camera at TAIL is the fully set-up live vanilla camera —
     * the blend target — so easing the stored final shot toward it converges onto the
     * exact post-cutscene view with no snap.
     */
    public static void onCameraSetup(Camera camera) {
        Shot shot = evaluateFresh();
        Vec3 shake = shakeOffset();
        if (shot != null) {
            camera.setPosition(shot.pos().add(shake));
            camera.setRotation(shot.yaw(), shot.pitch(), shot.roll() + shakeRoll());
            return;
        }
        Shot from = endBlendFrom;
        float blend = endBlendEased();
        if (from != null && blend >= 0.0F) {
            camera.setPosition(from.pos().lerp(camera.getPosition(), blend).add(shake));
            camera.setRotation(
                    Mth.rotLerp(blend, from.yaw(), camera.getYRot()),
                    Mth.rotLerp(blend, from.pitch(), camera.getXRot()),
                    Mth.rotLerp(blend, from.roll(), 0.0F) + shakeRoll());
            return;
        }
        if (shake.lengthSqr() > 0.0D) {
            camera.setPosition(camera.getPosition().add(shake));
        }
    }

    /**
     * Roll + redundancy for yaw/pitch (fallback if another mixin wins the setup TAIL).
     * The end blend is deliberately NOT applied here: this event fires BEFORE the setup
     * TAIL, so a blend applied in both places would feed the event's already-lerped angles
     * into the mixin's lerp (double-eased rotation). Losing the cosmetic blend in the
     * exotic another-mixin-wins case just means the old snap.
     */
    @SubscribeEvent
    static void onComputeCameraAngles(ViewportEvent.ComputeCameraAngles event) {
        Shot shot = evaluate();
        if (shot != null) {
            event.setYaw(shot.yaw());
            event.setPitch(shot.pitch());
            event.setRoll(shot.roll() + shakeRoll());
        } else if (!SHAKE_IMPULSES.isEmpty()) {
            event.setRoll(event.getRoll() + shakeRoll());
        }
    }

    @SubscribeEvent
    static void onComputeFov(ViewportEvent.ComputeFov event) {
        if (!event.usedConfiguredFov()) {
            return;
        }
        Shot shot = evaluate();
        if (shot != null) {
            event.setFOV(shot.fov());
            return;
        }
        Shot from = endBlendFrom;
        float blend = endBlendEased();
        if (from != null && blend >= 0.0F) {
            event.setFOV(Mth.lerp(blend, from.fov(), (float) event.getFOV()));
        }
    }

    // --- lifecycle ---

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        long now = System.nanoTime();
        while (!SHAKE_IMPULSES.isEmpty()
                && now - SHAKE_IMPULSES.peekFirst().startNanos() >= SHAKE_IMPULSES.peekFirst().durationNanos()) {
            SHAKE_IMPULSES.removeFirst();
        }
        CutscenePath active = path;
        if (active == null) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            // Disconnected mid-flight: stop silently, the server's logout hook cleans up.
            stop(minecraft);
            return;
        }
        double progress = progress(active, now);
        fireEvents(active, progress, minecraft);
        if (progress >= 1.0D) {
            EclipseMod.LOGGER.info("CameraDirector: '{}' finished — ACK FINISHED", active.id());
            ackFinished(active.id());
            beginEndBlend(minecraft);
        }
    }

    /**
     * Ends the flight WITHOUT acking (finish/skip/stop each ack — or not — themselves) and
     * drops any live end blend: skips, server {@code STOP}s and disconnects hard-snap.
     */
    private static void stop(Minecraft minecraft) {
        path = null;
        sampler = null;
        endBlendFrom = null;
        cachedShot = null;
        haveLastOrientation = false;
        pendingEvents = List.of();
        LetterboxLayer.setActive(false, false);
        if (previousCameraType != null) {
            minecraft.options.setCameraType(previousCameraType);
            previousCameraType = null;
        }
    }

    /**
     * NATURAL-completion exit: captures the final evaluated shot, tears the flight down
     * like {@link #stop} (letterbox away, camera type restored — restoring the type FIRST
     * makes the live camera the blend eases toward the REAL post-cutscene view, so the
     * handoff at blend end is seam-free for any previous camera type), then arms the
     * ~{@value #END_BLEND_TICKS}-tick blend consumed by {@link #onCameraSetup}.
     */
    private static void beginEndBlend(Minecraft minecraft) {
        Shot last = evaluate();
        stop(minecraft);
        if (last != null) {
            endBlendFrom = last;
            endBlendStartNanos = System.nanoTime();
        }
    }

    /**
     * Eased (ease-out cubic) end-blend progress in [0, 1], or {@code -1} when no blend is
     * live. Prunes the blend state on expiry, so later hooks the same frame fall through
     * to the untouched vanilla camera (which the blend has converged onto by then).
     */
    private static float endBlendEased() {
        if (endBlendFrom == null) {
            return -1.0F;
        }
        float t = (System.nanoTime() - endBlendStartNanos) / (float) END_BLEND_NANOS;
        if (t >= 1.0F) {
            endBlendFrom = null;
            return -1.0F;
        }
        float inv = 1.0F - Math.max(0.0F, t);
        return 1.0F - inv * inv * inv;
    }

    private static void ackFinished(String id) {
        PacketDistributor.sendToServer(
                new C2SCutsceneStatePayload(id, C2SCutsceneStatePayload.State.FINISHED));
    }

    private static double progress(CutscenePath active, long nowNanos) {
        return (nowNanos - startNanos) / (double) TICK_NANOS / Math.max(1, active.durationTicks());
    }

    /**
     * Fires path events (sorted by t) whose normalized time has been crossed. Types (see
     * {@link CutscenePath}): {@code sound}, {@code caption} (→ {@link CaptionRenderer}),
     * {@code fade}, {@code shake}. Unknown types are ignored (forward-compatible).
     */
    private static void fireEvents(CutscenePath active, double progress, Minecraft minecraft) {
        while (firedEvents < pendingEvents.size() && pendingEvents.get(firedEvents).t() <= progress) {
            CutscenePath.PathEvent pathEvent = pendingEvents.get(firedEvents++);
            switch (pathEvent.type()) {
                case "sound" -> {
                    ResourceLocation sound = ResourceLocation.tryParse(pathEvent.id());
                    if (sound != null) {
                        minecraft.getSoundManager().play(
                                SimpleSoundInstance.forUI(SoundEvent.createVariableRangeEvent(sound), 1.0F));
                    }
                }
                case "caption" -> {
                    // data = "<subtitle|title|whisper>[,durationTicks]"
                    String[] args = split(pathEvent.data());
                    int style = switch (args.length > 0 ? args[0] : "subtitle") {
                        case "title" -> 1;
                        case "whisper" -> 2;
                        default -> 0;
                    };
                    int duration = args.length > 1 ? parseInt(args[1], 80) : 80;
                    CaptionRenderer.enqueue(pathEvent.id(), duration, style);
                }
                case "fade" -> {
                    // data = "<inTicks>,<holdTicks>,<outTicks>[,AARRGGBB hex]"
                    String[] args = split(pathEvent.data());
                    if (args.length >= 3) {
                        int argb = args.length > 3 ? parseHexArgb(args[3]) : 0xFF000000;
                        CaptionRenderer.fade(parseInt(args[0], 10), parseInt(args[1], 10),
                                parseInt(args[2], 10), argb);
                    }
                }
                case "shake" -> {
                    // data = "<strength>[,ticks[,freq]]"
                    String[] args = split(pathEvent.data());
                    float strength = args.length > 0 ? parseFloat(args[0], 1.0F) : 1.0F;
                    int ticks = args.length > 1 ? parseInt(args[1], 40) : 40;
                    float freq = args.length > 2 ? parseFloat(args[2], 1.0F) : 1.0F;
                    addShakeImpulse(strength, ticks, freq);
                }
                default -> EclipseMod.LOGGER.debug("CameraDirector: unknown path event type '{}' in '{}'",
                        pathEvent.type(), active.id());
            }
        }
    }

    private static String[] split(String data) {
        return data.isEmpty() ? new String[0] : data.split("\\s*,\\s*");
    }

    private static int parseInt(String raw, int fallback) {
        try {
            return Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static float parseFloat(String raw, float fallback) {
        try {
            return Float.parseFloat(raw.trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** Parses an AARRGGBB hex color (optionally 0x/#-prefixed); malformed → opaque black. */
    private static int parseHexArgb(String raw) {
        String cleaned = raw.trim();
        if (cleaned.startsWith("#")) {
            cleaned = cleaned.substring(1);
        } else if (cleaned.startsWith("0x") || cleaned.startsWith("0X")) {
            cleaned = cleaned.substring(2);
        }
        try {
            return (int) Long.parseLong(cleaned, 16);
        } catch (NumberFormatException e) {
            return 0xFF000000;
        }
    }

    // --- path evaluation ---

    /** Scratch quats/vector for the per-frame orientation math (zero-alloc, client thread only). */
    private static final Quaternionf ORIENT_FROM = new Quaternionf();
    private static final Quaternionf ORIENT_TO = new Quaternionf();
    private static final Quaternionf ORIENT_RESULT = new Quaternionf();
    private static final Vector3f EULER_SCRATCH = new Vector3f();

    /**
     * The current frame's camera state, or {@code null} when no flight is active. Reuses the
     * last fresh evaluation when it is younger than {@value #SHOT_CACHE_NANOS} ns — the
     * camera-setup hook evaluates fresh once per frame FIRST, so every later hook (angle
     * redundancy, FOV) sees the identical shot and the lookAt turn-rate clamp integrates
     * real frame time exactly once.
     */
    @Nullable
    private static Shot evaluate() {
        if (path == null) {
            return null;
        }
        Shot cached = cachedShot;
        if (cached != null && System.nanoTime() - cachedShotNanos < SHOT_CACHE_NANOS) {
            return cached;
        }
        return evaluateFresh();
    }

    /** Evaluates the path at NOW and refreshes the per-frame cache + smoothing clock. */
    @Nullable
    private static Shot evaluateFresh() {
        CutscenePath active = path;
        PathSampler activeSampler = sampler;
        if (active == null || activeSampler == null) {
            return null;
        }
        long now = System.nanoTime();
        float dtSeconds = Mth.clamp((now - lastFreshNanos) / 1.0e9F, 0.0F, 0.1F);
        lastFreshNanos = now;

        List<CutscenePath.Keyframe> keyframes = active.keyframes();
        double u = Mth.clamp(progress(active, now), 0.0D, 1.0D);
        int segment = 0;
        while (segment < keyframes.size() - 2 && u >= keyframes.get(segment + 1).t()) {
            segment++;
        }
        CutscenePath.Keyframe from = keyframes.get(segment);
        CutscenePath.Keyframe to = keyframes.get(segment + 1);
        double span = to.t() - from.t();
        float local = span <= 0.0D ? 1.0F : (float) Mth.clamp((u - from.t()) / span, 0.0D, 1.0D);
        float eased = easing(from.easing()).ease(local);

        // Arc-length reparameterized position: eased progress covers DISTANCE (R12).
        Vec3 pos = toWorld(activeSampler.position(segment, eased));

        Quaternionf rotation = orientate(from, to, eased, pos, dtSeconds);
        Vector3f euler = rotation.getEulerAnglesYXZ(EULER_SCRATCH);
        float yaw = (float) -Math.toDegrees(euler.y);
        float pitch = (float) Math.toDegrees(euler.x);
        float roll = (float) Math.toDegrees(euler.z);
        float fov = Mth.lerp(eased, from.fov(), to.fov());
        Shot shot = new Shot(pos, yaw, pitch, roll, fov);
        cachedShot = shot;
        cachedShotNanos = now;
        return shot;
    }

    /**
     * Segment orientation: keyed slerp by default; when either keyframe carries a
     * {@code lookAt}, the aim toward the (resolved, interpolated) target replaces or blends
     * with the keyed orientation, and the final result is clamped to
     * {@value #MAX_LOOK_TURN_DEG_PER_SEC}°/s against last frame so target hand-offs and
     * anchor pops can never whip the camera. Returns {@link #ORIENT_RESULT} (scratch).
     */
    private static Quaternionf orientate(CutscenePath.Keyframe from, CutscenePath.Keyframe to,
            float eased, Vec3 cameraPos, float dtSeconds) {
        Vec3 fromTarget = resolveLookTarget(from.lookAt());
        Vec3 toTarget = resolveLookTarget(to.lookAt());
        float rollDeg = Mth.lerp(eased, from.roll(), to.roll());
        boolean lookInvolved = fromTarget != null || toTarget != null;

        if (fromTarget != null && toTarget != null) {
            aimAt(cameraPos, fromTarget.lerp(toTarget, eased), rollDeg, ORIENT_RESULT);
        } else if (fromTarget != null) {
            aimAt(cameraPos, fromTarget, rollDeg, ORIENT_FROM);
            keyedOrientation(to, ORIENT_TO);
            ORIENT_FROM.slerp(ORIENT_TO, eased, ORIENT_RESULT);
        } else if (toTarget != null) {
            keyedOrientation(from, ORIENT_FROM);
            aimAt(cameraPos, toTarget, rollDeg, ORIENT_TO);
            ORIENT_FROM.slerp(ORIENT_TO, eased, ORIENT_RESULT);
        } else {
            keyedOrientation(from, ORIENT_FROM);
            keyedOrientation(to, ORIENT_TO);
            ORIENT_FROM.slerp(ORIENT_TO, eased, ORIENT_RESULT);
        }

        if (lookInvolved && haveLastOrientation && dtSeconds > 0.0F) {
            float maxStepRad = (float) Math.toRadians(MAX_LOOK_TURN_DEG_PER_SEC) * dtSeconds;
            float dot = Math.abs(LAST_ORIENTATION.dot(ORIENT_RESULT));
            float angle = 2.0F * (float) Math.acos(Mth.clamp(dot, -1.0F, 1.0F));
            if (angle > maxStepRad && angle > 1.0e-4F) {
                LAST_ORIENTATION.slerp(ORIENT_RESULT, maxStepRad / angle, ORIENT_RESULT);
            }
        }
        LAST_ORIENTATION.set(ORIENT_RESULT);
        haveLastOrientation = true;
        return ORIENT_RESULT;
    }

    /** Keyframe-local orientation quaternion (anchor yaw baked in — slerp-compatible). */
    private static Quaternionf keyedOrientation(CutscenePath.Keyframe keyframe, Quaternionf dest) {
        return dest.rotationYXZ(
                (float) -Math.toRadians(anchorYawDeg + keyframe.yaw()),
                (float) Math.toRadians(keyframe.pitch()),
                (float) Math.toRadians(keyframe.roll()));
    }

    /** World-space aim quaternion from {@code eye} toward {@code target} (vanilla lookAt angles). */
    private static Quaternionf aimAt(Vec3 eye, Vec3 target, float rollDeg, Quaternionf dest) {
        double dx = target.x - eye.x;
        double dy = target.y - eye.y;
        double dz = target.z - eye.z;
        double horizontal = Math.sqrt(dx * dx + dz * dz);
        float yaw = (float) Math.toDegrees(Mth.atan2(dz, dx)) - 90.0F;
        float pitch = (float) -Math.toDegrees(Mth.atan2(dy, horizontal));
        return dest.rotationYXZ(
                (float) -Math.toRadians(yaw),
                (float) Math.toRadians(pitch),
                (float) Math.toRadians(rollDeg));
    }

    /**
     * Resolves a keyframe's lookAt into a live world position: points share the keyframe
     * coordinate space (anchor transform applied), {@code anchor:<id>} reads the synced
     * {@link FxAnchors} cache, {@code player} tracks the watching player's eyes. {@code null}
     * (no lookAt, unknown anchor, missing player) falls back to the keyed orientation.
     */
    @Nullable
    private static Vec3 resolveLookTarget(@Nullable CutscenePath.LookAt lookAt) {
        if (lookAt == null) {
            return null;
        }
        if (lookAt.hasPoint()) {
            return toWorld(new Vec3(lookAt.x(), lookAt.y(), lookAt.z()));
        }
        if (lookAt.player()) {
            var player = Minecraft.getInstance().player;
            return player != null ? player.getEyePosition() : null;
        }
        if (!lookAt.anchorId().isEmpty()) {
            ResourceLocation id = ResourceLocation.tryParse(lookAt.anchorId());
            return id != null ? FxAnchors.get(id) : null;
        }
        return null;
    }

    /** Keyframe-local position → world (shared transform in {@link PathSampler#toWorld}). */
    private static Vec3 toWorld(Vec3 local) {
        return PathSampler.toWorld(local, anchorPos, anchorYawDeg);
    }

    /** Maps the schema's camelCase easing names onto Veil's {@link Easing}; unknown → linear. */
    private static Easing easing(String name) {
        if (name == null || name.isEmpty() || "linear".equals(name)) {
            return Easing.LINEAR;
        }
        StringBuilder constant = new StringBuilder(name.length() + 6);
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            if (Character.isUpperCase(c)) {
                constant.append('_');
            }
            constant.append(Character.toUpperCase(c));
        }
        try {
            return Easing.valueOf(constant.toString());
        } catch (IllegalArgumentException e) {
            return Easing.LINEAR;
        }
    }

    // --- shake (2-octave value noise per impulse, P2 R12) ---

    /** Base sway frequency in noise cells per second (octave 2 runs at ×2.7). */
    private static final float SHAKE_BASE_FREQ = 9.0F;

    /** Prunes fully decayed impulses from the front (oldest-first ordering). */
    private static void pruneShakes(long now) {
        while (!SHAKE_IMPULSES.isEmpty()
                && now - SHAKE_IMPULSES.peekFirst().startNanos() >= SHAKE_IMPULSES.peekFirst().durationNanos()) {
            SHAKE_IMPULSES.removeFirst();
        }
    }

    /** Quadratic decay envelope of one impulse at {@code now}, or 0 outside its window. */
    private static float envelope(ShakeImpulse impulse, long now) {
        float age = (now - impulse.startNanos()) / (float) impulse.durationNanos();
        if (age < 0.0F || age >= 1.0F) {
            return 0.0F;
        }
        return impulse.strength() * (1.0F - age) * (1.0F - age);
    }

    /** Position noise: per-impulse 2-octave value noise, soft-capped so stacks don't explode. */
    private static Vec3 shakeOffset() {
        if (SHAKE_IMPULSES.isEmpty()) {
            return Vec3.ZERO;
        }
        long now = System.nanoTime();
        pruneShakes(now);
        if (SHAKE_IMPULSES.isEmpty()) {
            return Vec3.ZERO;
        }
        float seconds = (now % 100_000_000_000L) / 1.0e9F;
        float x = 0.0F;
        float y = 0.0F;
        float z = 0.0F;
        for (ShakeImpulse impulse : SHAKE_IMPULSES) {
            float env = envelope(impulse, now);
            if (env <= 0.0F) {
                continue;
            }
            float t = seconds * SHAKE_BASE_FREQ * impulse.freq();
            int seed = (int) (impulse.startNanos() % 65_536L);
            x += env * octaveNoise(t, seed);
            y += env * 0.6F * octaveNoise(t, seed + 13);
            z += env * octaveNoise(t, seed + 29);
        }
        float cap = 1.5F;
        return new Vec3(
                Mth.clamp(x, -cap, cap) * SHAKE_MAX_OFFSET,
                Mth.clamp(y, -cap, cap) * SHAKE_MAX_OFFSET,
                Mth.clamp(z, -cap, cap) * SHAKE_MAX_OFFSET);
    }

    private static float shakeRoll() {
        if (SHAKE_IMPULSES.isEmpty()) {
            return 0.0F;
        }
        long now = System.nanoTime();
        pruneShakes(now);
        float seconds = (now % 100_000_000_000L) / 1.0e9F;
        float roll = 0.0F;
        for (ShakeImpulse impulse : SHAKE_IMPULSES) {
            float env = envelope(impulse, now);
            if (env <= 0.0F) {
                continue;
            }
            roll += env * octaveNoise(seconds * SHAKE_BASE_FREQ * impulse.freq(),
                    (int) (impulse.startNanos() % 65_536L) + 47);
        }
        return Mth.clamp(roll, -1.5F, 1.5F) * SHAKE_MAX_ROLL_DEG;
    }

    /** 2-octave value noise in ~[-1.5, 1.5]: slow sway + a faster, weaker shudder. */
    private static float octaveNoise(float x, int seed) {
        return valueNoise(x, seed) + 0.5F * valueNoise(x * 2.7F, seed + 71);
    }

    /** Smooth 1-D value noise in [-1, 1] (hash lattice + smoothstep; no RNG state). */
    private static float valueNoise(float x, int seed) {
        int cell = Mth.floor(x);
        float f = x - cell;
        float s = f * f * (3.0F - 2.0F * f);
        return Mth.lerp(s, hash(cell, seed), hash(cell + 1, seed)) * 2.0F - 1.0F;
    }

    /** Integer lattice hash → [0, 1]. */
    private static float hash(int i, int seed) {
        int h = i * 374761393 + seed * 668265263;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / (float) 0x7FFFFFFF;
    }
}
