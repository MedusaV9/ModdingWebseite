package dev.projecteclipse.eclipse.cutscene.client;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.network.C2SCutsceneStatePayload;
import dev.projecteclipse.eclipse.network.S2CCutscenePlayPayload;
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
 * <p><b>Path evaluation</b>: position via uniform Catmull-Rom (default) or segment-local
 * cubic Hermite with damped tangents ({@code "bezier"}); orientation via quaternion slerp of
 * per-keyframe yaw/pitch/roll; segment progress shaped by the leaving keyframe's easing
 * (Veil's {@link Easing}). Player-anchored paths ({@code anchor:"player"}) treat keyframe
 * positions as offsets rotated by the player's yaw at start, and keyframe yaws as relative
 * to it; world-anchored paths use absolute coordinates unless the play payload supplied an
 * anchor origin (e.g. {@code unlock_ring}'s ring edge).</p>
 *
 * <p><b>Safety</b>: a missing/foreign-dimension path ACKs {@code FINISHED} instantly so the
 * server-side freeze always releases; a disconnect mid-flight stops silently (the server's
 * logout hook + watchdog clean up). Timing is wall-clock ({@code System.nanoTime}), matching
 * the server watchdog's tick budget.</p>
 *
 * <p><b>Shake impulses</b> (W4 contract): each {@code S2CCutscenePayload(SHAKE)} receipt is
 * one ~2 s decaying camera-shake impulse ({@link #addShakeImpulse()}), applied as position +
 * roll noise both during cutscene flights and over the normal gameplay camera (intro fusion
 * rumble).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CameraDirector {
    private static final long TICK_NANOS = 50_000_000L;
    /** One shake impulse: ~2 s quadratic decay. */
    private static final long SHAKE_DURATION_NANOS = 2_000_000_000L;
    private static final float SHAKE_MAX_OFFSET = 0.16F;
    private static final float SHAKE_MAX_ROLL_DEG = 1.1F;

    /** Fully evaluated camera state for the current frame. */
    private record Shot(Vec3 pos, float yaw, float pitch, float roll, float fov) {}

    @Nullable
    private static CutscenePath path;
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
    /** One live shake impulse: quadratic decay of {@code strength} over {@code durationNanos}. */
    private record ShakeImpulse(long startNanos, float strength, long durationNanos) {}

    /** Live shake impulses, oldest first (expired ones are pruned lazily). Main-thread only. */
    private static final ArrayDeque<ShakeImpulse> SHAKE_IMPULSES = new ArrayDeque<>();

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
        allowSkip = payload.allowSkip();
        startNanos = System.nanoTime();
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
        SHAKE_IMPULSES.addLast(new ShakeImpulse(System.nanoTime(),
                Math.max(0.0F, strength), Math.max(1, ticks) * TICK_NANOS));
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

    /** Called from {@code CameraMixin} at the TAIL of {@code Camera#setup} every frame. */
    public static void onCameraSetup(Camera camera) {
        Shot shot = evaluate();
        Vec3 shake = shakeOffset();
        if (shot != null) {
            camera.setPosition(shot.pos().add(shake));
            camera.setRotation(shot.yaw(), shot.pitch(), shot.roll() + shakeRoll());
        } else if (shake.lengthSqr() > 0.0D) {
            camera.setPosition(camera.getPosition().add(shake));
        }
    }

    /** Roll + redundancy for yaw/pitch (fallback if another mixin wins the setup TAIL). */
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
            stop(minecraft);
        }
    }

    /** Ends the flight WITHOUT acking (finish/skip/stop each ack — or not — themselves). */
    private static void stop(Minecraft minecraft) {
        path = null;
        pendingEvents = List.of();
        LetterboxLayer.setActive(false, false);
        if (previousCameraType != null) {
            minecraft.options.setCameraType(previousCameraType);
            previousCameraType = null;
        }
    }

    private static void ackFinished(String id) {
        PacketDistributor.sendToServer(
                new C2SCutsceneStatePayload(id, C2SCutsceneStatePayload.State.FINISHED));
    }

    private static double progress(CutscenePath active, long nowNanos) {
        return (nowNanos - startNanos) / (double) TICK_NANOS / Math.max(1, active.durationTicks());
    }

    /** Fires path events (sorted by t) whose normalized time has been crossed. */
    private static void fireEvents(CutscenePath active, double progress, Minecraft minecraft) {
        while (firedEvents < pendingEvents.size() && pendingEvents.get(firedEvents).t() <= progress) {
            CutscenePath.PathEvent pathEvent = pendingEvents.get(firedEvents++);
            if ("sound".equals(pathEvent.type())) {
                ResourceLocation sound = ResourceLocation.tryParse(pathEvent.id());
                if (sound != null) {
                    minecraft.getSoundManager().play(
                            SimpleSoundInstance.forUI(SoundEvent.createVariableRangeEvent(sound), 1.0F));
                }
            } else {
                EclipseMod.LOGGER.debug("CameraDirector: unknown path event type '{}' in '{}'",
                        pathEvent.type(), active.id());
            }
        }
    }

    // --- path evaluation ---

    /** The current frame's camera state, or {@code null} when no flight is active. */
    @Nullable
    private static Shot evaluate() {
        CutscenePath active = path;
        if (active == null) {
            return null;
        }
        List<CutscenePath.Keyframe> keyframes = active.keyframes();
        double u = Mth.clamp(progress(active, System.nanoTime()), 0.0D, 1.0D);
        int segment = 0;
        while (segment < keyframes.size() - 2 && u >= keyframes.get(segment + 1).t()) {
            segment++;
        }
        CutscenePath.Keyframe from = keyframes.get(segment);
        CutscenePath.Keyframe to = keyframes.get(segment + 1);
        double span = to.t() - from.t();
        float local = span <= 0.0D ? 1.0F : (float) Mth.clamp((u - from.t()) / span, 0.0D, 1.0D);
        float eased = easing(from.easing()).ease(local);

        Vec3 pos = CutscenePath.INTERPOLATION_BEZIER.equals(active.interpolation())
                ? bezierPosition(keyframes, segment, eased)
                : catmullRomPosition(keyframes, segment, eased);

        Quaternionf rotation = orientation(from).slerp(orientation(to), eased, new Quaternionf());
        Vector3f euler = rotation.getEulerAnglesYXZ(new Vector3f());
        float yaw = (float) -Math.toDegrees(euler.y);
        float pitch = (float) Math.toDegrees(euler.x);
        float roll = (float) Math.toDegrees(euler.z);
        float fov = Mth.lerp(eased, from.fov(), to.fov());
        return new Shot(toWorld(pos), yaw, pitch, roll, fov);
    }

    /** Keyframe-local orientation quaternion (anchor yaw baked in — slerp-compatible). */
    private static Quaternionf orientation(CutscenePath.Keyframe keyframe) {
        return new Quaternionf().rotationYXZ(
                (float) -Math.toRadians(anchorYawDeg + keyframe.yaw()),
                (float) Math.toRadians(keyframe.pitch()),
                (float) Math.toRadians(keyframe.roll()));
    }

    /** Keyframe-local position → world: rotate by the anchor yaw, then translate. */
    private static Vec3 toWorld(Vec3 local) {
        if (anchorYawDeg != 0.0F) {
            Vector3f rotated = new Vector3f((float) local.x, (float) local.y, (float) local.z)
                    .rotateY((float) -Math.toRadians(anchorYawDeg));
            return anchorPos.add(rotated.x, rotated.y, rotated.z);
        }
        return anchorPos.add(local);
    }

    /** Uniform Catmull-Rom through the keyframe positions (clamped end tangents). */
    private static Vec3 catmullRomPosition(List<CutscenePath.Keyframe> keyframes, int segment, float t) {
        Vec3 p0 = pos(keyframes, segment - 1);
        Vec3 p1 = pos(keyframes, segment);
        Vec3 p2 = pos(keyframes, segment + 1);
        Vec3 p3 = pos(keyframes, segment + 2);
        return new Vec3(
                catmullRom(t, p0.x, p1.x, p2.x, p3.x),
                catmullRom(t, p0.y, p1.y, p2.y, p3.y),
                catmullRom(t, p0.z, p1.z, p2.z, p3.z));
    }

    /** Double-precision {@code Mth.catmullrom} (float would jitter at large world coordinates). */
    private static double catmullRom(double t, double p0, double p1, double p2, double p3) {
        return 0.5D * (2.0D * p1 + (p2 - p0) * t
                + (2.0D * p0 - 5.0D * p1 + 4.0D * p2 - p3) * t * t
                + (3.0D * p1 - p0 - 3.0D * p2 + p3) * t * t * t);
    }

    /**
     * Segment-local cubic Hermite with damped tangents (half Catmull-Rom): flows less than
     * Catmull-Rom and settles into every keyframe — the {@code "bezier"} mode of the schema.
     */
    private static Vec3 bezierPosition(List<CutscenePath.Keyframe> keyframes, int segment, float t) {
        Vec3 p0 = pos(keyframes, segment - 1);
        Vec3 p1 = pos(keyframes, segment);
        Vec3 p2 = pos(keyframes, segment + 1);
        Vec3 p3 = pos(keyframes, segment + 2);
        Vec3 m1 = p2.subtract(p0).scale(0.25D);
        Vec3 m2 = p3.subtract(p1).scale(0.25D);
        double t2 = t * t;
        double t3 = t2 * t;
        double h1 = 2.0D * t3 - 3.0D * t2 + 1.0D;
        double h2 = t3 - 2.0D * t2 + t;
        double h3 = -2.0D * t3 + 3.0D * t2;
        double h4 = t3 - t2;
        return p1.scale(h1).add(m1.scale(h2)).add(p2.scale(h3)).add(m2.scale(h4));
    }

    private static Vec3 pos(List<CutscenePath.Keyframe> keyframes, int index) {
        CutscenePath.Keyframe keyframe = keyframes.get(Mth.clamp(index, 0, keyframes.size() - 1));
        return new Vec3(keyframe.x(), keyframe.y(), keyframe.z());
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

    // --- shake ---

    /** Sum of live impulse envelopes (quadratic decay), soft-capped so stacks don't explode. */
    private static float shakeAmplitude() {
        if (SHAKE_IMPULSES.isEmpty()) {
            return 0.0F;
        }
        long now = System.nanoTime();
        // Prune fully decayed impulses from the front (oldest first ordering).
        while (!SHAKE_IMPULSES.isEmpty()
                && now - SHAKE_IMPULSES.peekFirst().startNanos() >= SHAKE_IMPULSES.peekFirst().durationNanos()) {
            SHAKE_IMPULSES.removeFirst();
        }
        float total = 0.0F;
        for (ShakeImpulse impulse : SHAKE_IMPULSES) {
            float age = (now - impulse.startNanos()) / (float) impulse.durationNanos();
            if (age >= 0.0F && age < 1.0F) {
                total += impulse.strength() * (1.0F - age) * (1.0F - age);
            }
        }
        return Math.min(1.5F, total);
    }

    /** Small position noise (multi-frequency sines — cheap, no RNG state). */
    private static Vec3 shakeOffset() {
        float amplitude = shakeAmplitude();
        if (amplitude <= 0.0F) {
            return Vec3.ZERO;
        }
        double seconds = (System.nanoTime() % 100_000_000_000L) / 1.0e9D;
        return new Vec3(
                amplitude * SHAKE_MAX_OFFSET * Math.sin(seconds * 83.0D),
                amplitude * SHAKE_MAX_OFFSET * 0.6D * Math.sin(seconds * 97.0D + 1.7D),
                amplitude * SHAKE_MAX_OFFSET * Math.cos(seconds * 89.0D + 0.6D));
    }

    private static float shakeRoll() {
        float amplitude = shakeAmplitude();
        if (amplitude <= 0.0F) {
            return 0.0F;
        }
        double seconds = (System.nanoTime() % 100_000_000_000L) / 1.0e9D;
        return amplitude * SHAKE_MAX_ROLL_DEG * (float) Math.sin(seconds * 71.0D + 0.3D);
    }
}
