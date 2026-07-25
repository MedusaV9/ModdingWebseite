package dev.projecteclipse.eclipse.veilfx;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * D12 — optional bridge to the <b>Photon</b> VFX mod (Modrinth {@code photon-editor},
 * Low Drag MC): when the {@code photon} mod is installed on the client, flagship moments
 * get an EXTRA editor-authored Photon effect layered over the existing Quasar visuals;
 * without Photon (or without the effect assets) every call is a silent no-op and the
 * shipped Quasar/vanilla path is exactly what it was before this class existed.
 *
 * <p><b>Deliberately reflection-based, no compile-time dependency.</b> The Modrinth maven
 * coordinate {@code maven.modrinth:photon-editor:mc1.21.1-2.1.5-neoforge} verifiably
 * resolves (pom + jar HTTP 200, checked 2026-07), but this repo's build must stay buildable
 * with zero new remote dependencies, so every touched API point is reflected against
 * signatures verified from the published 2.1.5 jar (javap — see
 * {@code docs/plans_v3/plans_v5/photon/API.md}):</p>
 * <ul>
 *   <li>{@code FXHelper.getFX(ResourceLocation)} — loads/caches an {@code FX} from
 *       {@code assets/<ns>/fx/<path>.fx} (compressed-NBT files, authored in Photon's
 *       in-game editor or via {@code tools/photon/fxlib.py});</li>
 *   <li>{@code new BlockEffectExecutor(FX, Level, BlockPos)} + {@code start()} — plays the
 *       effect anchored at a block position (block center + offset);</li>
 *   <li>{@code new EntityEffectExecutor(FX, Level, Entity, AutoRotate)} + {@code start()}
 *       — attaches the effect to an entity (eye position + offset, auto-cleanup on death);</li>
 *   <li>{@code FXEffectExecutor.setOffset(Vector3f)/setRotation(Quaternionf)/
 *       setScale(Vector3f)/setDelay(int)/setAllowMulti(boolean)/getRuntime()} — shared
 *       executor knobs (inherited by both executor kinds);</li>
 *   <li>{@code FXRuntime.isAlive()} + {@code FXRuntime.destroy(boolean force)} — live
 *       playback introspection and the loop stop path ({@code force=false} = graceful
 *       fade-out, {@code true} = instant kill).</li>
 * </ul>
 *
 * <p><b>Guards</b> (all must pass, in order): {@code ModList.get().isLoaded("photon")}
 * (checked once, the mod set is frozen after load), the {@code photonFx} client toggle,
 * NOT {@code reducedFx}, reflection handles resolved. A reflection failure disables the
 * bridge for the session (one WARN); a missing {@code .fx} asset skips that effect id for
 * the session (one INFO). Photon draws through its own renderer (not Veil/Quasar), so
 * spawns are NOT charged to {@link FxBudget} — instead the bridge enforces its own hard
 * ceiling of {@value #MAX_LIVE_EXECUTORS} live Photon executors (one-shots count until
 * their runtime dies): spawns beyond it are refused (return {@code false}/{@code null}).</p>
 *
 * <p><b>Lifecycle cache:</b> every executor started through the bridge is tracked and
 * swept once per client tick — dead runtime → forgotten; dead/removed entity or a level
 * change (Photon's own mixins clear the particle engine on level swap) → destroyed and
 * forgotten; logout → everything force-destroyed. Loops (looping {@code .fx} assets played
 * via {@link #spawnLoop}) MUST be held as a {@link LoopHandle} and stopped with
 * {@link #stopLoop} — see the WINDOWED-loop law in
 * {@code docs/plans_v3/plans_v5/photon/INTEGRATION.md} §4.</p>
 *
 * <p>Effect ids consumed by the two shipped seams (drop-in
 * {@code assets/eclipse/fx/<id>.fx}): {@link #ALTAR_LEVELUP} and
 * {@link #EXPANSION_RIFT_GLOW}. Table-driven cues live in {@link PhotonFxRegistry}.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class PhotonBridge {
    /** Extra glow/burst for the altar milestone level-up moment. */
    public static final ResourceLocation ALTAR_LEVELUP = fx("altar_levelup");
    /** Extra glow for expansion (structure-drop) rift tears. */
    public static final ResourceLocation EXPANSION_RIFT_GLOW = fx("expansion_rift_glow");

    /** {@code EntityEffectExecutor.AutoRotate} ordinals (enum order verified via javap). */
    public static final int AUTO_ROTATE_NONE = 0;
    public static final int AUTO_ROTATE_FORWARD = 1;
    public static final int AUTO_ROTATE_LOOK = 2;
    public static final int AUTO_ROTATE_XROT = 3;

    /**
     * Hard budget: max concurrently-live Photon executors started through the bridge.
     * Photon bypasses {@link FxBudget} (own render pipeline), so this is the only ceiling;
     * spawns beyond it are refused outright (never queued).
     */
    public static final int MAX_LIVE_EXECUTORS = 24;

    private static final int UNRESOLVED = 0;
    private static final int READY = 1;
    private static final int DISABLED = 2;

    private static volatile int state = UNRESOLVED;
    private static Method getFxMethod;
    private static Constructor<?> blockExecutorCtor;
    private static Method blockStartMethod;
    private static Constructor<?> entityExecutorCtor;
    private static Method entityStartMethod;
    private static Object[] autoRotateConstants;
    private static Method setOffsetMethod;
    private static Method setRotationMethod;
    private static Method setScaleMethod;
    private static Method setDelayMethod;
    private static Method setAllowMultiMethod;
    private static Method getRuntimeMethod;
    private static Method runtimeIsAliveMethod;
    private static Method runtimeDestroyMethod;

    /** Effect ids whose {@code .fx} asset failed to load — skipped for the session. */
    private static final Set<ResourceLocation> MISSING_FX = new HashSet<>();

    /** Every live executor started through the bridge (client main thread only). */
    private static final List<Tracked> LIVE = new ArrayList<>();
    /** Budget refusals this session (dev/QA introspection via {@code /dev photon status}). */
    private static int refusedCount;

    private PhotonBridge() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    // ------------------------------------------------------------------ options

    /**
     * Optional executor knobs, applied (via reflection) before {@code start()} on BOTH
     * executor kinds. All fields optional; start from {@link #DEFAULT} and use the
     * {@code with*} copies.
     *
     * @param offset      extra local offset in blocks (block executors anchor at block
     *                    center + offset; entity executors at eye position + offset)
     * @param rotationDeg XYZ euler degrees (converted to a JOML quaternion like Photon's
     *                    own {@code IFXEffectExecutor} default)
     * @param scale       per-axis scale multiplier
     * @param delayTicks  ticks before emission starts
     * @param allowMulti  {@code true} = allow stacking the same fx id on the same anchor
     *                    while a previous runtime is alive (Photon default dedups silently)
     */
    public record SpawnOptions(@Nullable Vector3f offset, @Nullable Vector3f rotationDeg,
            @Nullable Vector3f scale, int delayTicks, boolean allowMulti) {
        public static final SpawnOptions DEFAULT = new SpawnOptions(null, null, null, 0, false);

        public SpawnOptions withOffset(double x, double y, double z) {
            return new SpawnOptions(new Vector3f((float) x, (float) y, (float) z),
                    rotationDeg, scale, delayTicks, allowMulti);
        }

        public SpawnOptions withRotationDeg(double xDeg, double yDeg, double zDeg) {
            return new SpawnOptions(offset, new Vector3f((float) xDeg, (float) yDeg, (float) zDeg),
                    scale, delayTicks, allowMulti);
        }

        public SpawnOptions withScale(double x, double y, double z) {
            return new SpawnOptions(offset, rotationDeg,
                    new Vector3f((float) x, (float) y, (float) z), delayTicks, allowMulti);
        }

        public SpawnOptions withDelay(int ticks) {
            return new SpawnOptions(offset, rotationDeg, scale, ticks, allowMulti);
        }

        public SpawnOptions withAllowMulti(boolean allow) {
            return new SpawnOptions(offset, rotationDeg, scale, delayTicks, allow);
        }
    }

    /**
     * Opaque handle to a looping Photon effect started via {@link #spawnLoop}; hold it and
     * call {@link #stopLoop} (or rely on the per-tick sweep for death/level-change cleanup).
     */
    public static final class LoopHandle {
        private final Tracked tracked;

        private LoopHandle(Tracked tracked) {
            this.tracked = tracked;
        }

        /** Whether the loop's runtime is still alive (false after stop/sweep/kill). */
        public boolean alive() {
            return LIVE.contains(tracked) && runtimeAlive(tracked.executor);
        }
    }

    /** One live executor started through the bridge. */
    private static final class Tracked {
        final Object executor;
        final ResourceLocation fxId;
        final Level level;
        @Nullable
        final Entity entity;
        final boolean loop;

        Tracked(Object executor, ResourceLocation fxId, Level level, @Nullable Entity entity,
                boolean loop) {
            this.executor = executor;
            this.fxId = fxId;
            this.level = level;
            this.entity = entity;
            this.loop = loop;
        }
    }

    // ------------------------------------------------------------------ availability

    /** Whether the Photon layer may run right now (mod present + toggles). Cheap. */
    public static boolean available() {
        return state != DISABLED
                && ModList.get().isLoaded("photon")
                && EclipseClientConfig.photonFx()
                && !EclipseClientConfig.reducedFx();
    }

    /**
     * {@code S2CQuasarPayload} seam (called from {@code EclipsePayloads.handleQuasar} on the
     * client main thread): layers the Photon enhancement over cues that have one. Always
     * returns without consuming the payload — the Quasar path still runs.
     */
    public static void enhanceQuasarCue(ResourceLocation emitterId, Vec3 pos) {
        if (S2CQuasarPayload.ALTAR_LEVELUP_RING.equals(emitterId)) {
            spawn(ALTAR_LEVELUP, pos);
        }
    }

    // ------------------------------------------------------------------ one-shot spawns

    /**
     * Plays the Photon effect {@code fxId} anchored at {@code pos}'s block position
     * (frozen D12 behavior: plays at block center, no exact sub-block anchoring).
     * @return {@code true} only when a Photon effect actually started (or an identical one
     *         is already live at this anchor — Photon's own dedup); every failure path
     *         (photon absent, toggles off, missing asset, reflection breakage, executor
     *         budget) is a no-op returning {@code false}.
     */
    public static boolean spawn(ResourceLocation fxId, Vec3 pos) {
        return startExecutor(fxId, pos, null, 0, SpawnOptions.DEFAULT, false, false) != START_FAILED;
    }

    /**
     * Like {@link #spawn(ResourceLocation, Vec3)} but with exact sub-block anchoring (the
     * executor's block-center anchor is corrected to {@code pos} before any
     * {@code options.offset}) plus the full {@link SpawnOptions} knob set.
     */
    public static boolean spawn(ResourceLocation fxId, Vec3 pos, SpawnOptions options) {
        return startExecutor(fxId, pos, null, 0, options, true, false) != START_FAILED;
    }

    /**
     * Attaches the Photon effect {@code fxId} to {@code entity} (played at the entity's eye
     * position + offset every frame; Photon auto-destroys it when the entity dies).
     *
     * @param autoRotateOrdinal one of {@link #AUTO_ROTATE_NONE} / {@link #AUTO_ROTATE_FORWARD}
     *                          / {@link #AUTO_ROTATE_LOOK} / {@link #AUTO_ROTATE_XROT}
     * @param offset            extra local offset in blocks, or {@code null}
     * @return {@code true} iff the effect started (same failure semantics as {@link #spawn})
     */
    public static boolean spawnOnEntity(ResourceLocation fxId, Entity entity,
            int autoRotateOrdinal, @Nullable Vec3 offset) {
        SpawnOptions options = offset == null ? SpawnOptions.DEFAULT
                : SpawnOptions.DEFAULT.withOffset(offset.x, offset.y, offset.z);
        return spawnOnEntity(fxId, entity, autoRotateOrdinal, options);
    }

    /** {@link #spawnOnEntity(ResourceLocation, Entity, int, Vec3)} with the full knob set. */
    public static boolean spawnOnEntity(ResourceLocation fxId, Entity entity,
            int autoRotateOrdinal, SpawnOptions options) {
        return startExecutor(fxId, null, entity, autoRotateOrdinal, options, false, false)
                != START_FAILED;
    }

    // ------------------------------------------------------------------ loops

    /**
     * Plays a looping {@code .fx} asset anchored at {@code pos} (exact sub-block anchor) and
     * returns a handle for {@link #stopLoop}. Loops are WINDOWED-only by law (INTEGRATION.md
     * §4): the caller MUST own a hysteresis window (SanctumLightfall pattern) and stop the
     * loop when the window closes — the per-tick sweep only covers death/level-change.
     *
     * @return the handle, or {@code null} when the spawn was refused (any guard, budget, or
     *         Photon's same-anchor dedup — a loop we did not create cannot be managed)
     */
    @Nullable
    public static LoopHandle spawnLoop(ResourceLocation fxId, Vec3 pos) {
        Tracked tracked = startExecutor(fxId, pos, null, 0,
                SpawnOptions.DEFAULT.withAllowMulti(true), true, true);
        return tracked == null || tracked == START_FAILED ? null : new LoopHandle(tracked);
    }

    /** Entity-attached variant of {@link #spawnLoop(ResourceLocation, Vec3)}. */
    @Nullable
    public static LoopHandle spawnLoop(ResourceLocation fxId, Entity entity, int autoRotateOrdinal) {
        Tracked tracked = startExecutor(fxId, null, entity, autoRotateOrdinal,
                SpawnOptions.DEFAULT.withAllowMulti(true), false, true);
        return tracked == null || tracked == START_FAILED ? null : new LoopHandle(tracked);
    }

    /**
     * Stops a loop started with {@link #spawnLoop}: {@code graceful=true} lets emitters stop
     * and live particles fade naturally ({@code FXRuntime.destroy(false)});
     * {@code graceful=false} kills everything instantly ({@code destroy(true)}). Idempotent.
     */
    public static void stopLoop(@Nullable LoopHandle handle, boolean graceful) {
        if (handle == null) {
            return;
        }
        if (LIVE.remove(handle.tracked)) {
            destroyQuietly(handle.tracked, !graceful);
        }
    }

    // ------------------------------------------------------------------ spawn core

    /** Sentinel distinguishing "refused/failed" from "dedup no-op success" (null). */
    private static final Tracked START_FAILED =
            new Tracked(new Object(), ResourceLocation.withDefaultNamespace("failed"), null, null, false);

    /**
     * Shared spawn path. Anchors at {@code pos} (block executor) when {@code entity} is
     * null, else attaches to {@code entity}. @return the tracked entry, {@code null} for a
     * Photon same-anchor dedup no-op (effect already playing), or {@link #START_FAILED}.
     */
    @Nullable
    private static Tracked startExecutor(ResourceLocation fxId, @Nullable Vec3 pos,
            @Nullable Entity entity, int autoRotateOrdinal, SpawnOptions options,
            boolean exactAnchor, boolean loop) {
        if (!available() || MISSING_FX.contains(fxId)) {
            return START_FAILED;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || !resolve()) {
            return START_FAILED;
        }
        sweep();
        if (LIVE.size() >= MAX_LIVE_EXECUTORS) {
            refusedCount++;
            EclipseMod.LOGGER.debug("Photon spawn {} refused: {} live executors (cap {})",
                    fxId, LIVE.size(), MAX_LIVE_EXECUTORS);
            return START_FAILED;
        }
        try {
            Object fxObject = getFxMethod.invoke(null, fxId);
            if (fxObject == null) {
                missing(fxId);
                return START_FAILED;
            }
            Object executor;
            Method start;
            if (entity != null) {
                int ordinal = autoRotateOrdinal >= 0 && autoRotateOrdinal < autoRotateConstants.length
                        ? autoRotateOrdinal : AUTO_ROTATE_NONE;
                executor = entityExecutorCtor.newInstance(fxObject, entity.level(), entity,
                        autoRotateConstants[ordinal]);
                start = entityStartMethod;
            } else {
                executor = blockExecutorCtor.newInstance(fxObject, level, BlockPos.containing(pos));
                start = blockStartMethod;
            }
            applyOptions(executor, pos, options, exactAnchor && entity == null);
            start.invoke(executor);
            if (getRuntimeMethod.invoke(executor) == null) {
                // start() dedup'd silently (allowMulti=false + identical live effect at
                // this anchor): the cue is visually satisfied but we own no runtime.
                return null;
            }
            Tracked tracked = new Tracked(executor, fxId,
                    entity != null ? entity.level() : level, entity, loop);
            LIVE.add(tracked);
            return tracked;
        } catch (Throwable t) {
            // Asset-load failures surface here as InvocationTargetExceptions; executor
            // breakage would too. Either way: skip the id for the session, one WARN.
            if (MISSING_FX.add(fxId)) {
                EclipseMod.LOGGER.warn("Photon effect {} failed; skipping it for this session", fxId, t);
            }
            return START_FAILED;
        }
    }

    /** Applies {@link SpawnOptions} through the shared {@code FXEffectExecutor} setters. */
    private static void applyOptions(Object executor, @Nullable Vec3 pos, SpawnOptions options,
            boolean exactAnchor) throws Exception {
        Vector3f offset = null;
        if (exactAnchor && pos != null) {
            // The block executor plays at BlockPos + 0.5 — correct back to the exact Vec3.
            BlockPos bp = BlockPos.containing(pos);
            offset = new Vector3f((float) (pos.x - (bp.getX() + 0.5D)),
                    (float) (pos.y - (bp.getY() + 0.5D)),
                    (float) (pos.z - (bp.getZ() + 0.5D)));
        }
        if (options.offset() != null) {
            offset = offset == null ? new Vector3f(options.offset()) : offset.add(options.offset());
        }
        if (offset != null) {
            setOffsetMethod.invoke(executor, offset);
        }
        if (options.rotationDeg() != null) {
            Vector3f r = options.rotationDeg();
            setRotationMethod.invoke(executor, new Quaternionf().rotationXYZ(
                    (float) Math.toRadians(r.x), (float) Math.toRadians(r.y),
                    (float) Math.toRadians(r.z)));
        }
        if (options.scale() != null) {
            setScaleMethod.invoke(executor, new Vector3f(options.scale()));
        }
        if (options.delayTicks() > 0) {
            setDelayMethod.invoke(executor, options.delayTicks());
        }
        if (options.allowMulti()) {
            setAllowMultiMethod.invoke(executor, true);
        }
    }

    // ------------------------------------------------------------------ sweep / lifecycle

    /**
     * Per-tick sweep of the live-executor cache: dead runtime → forget; dead/removed entity
     * or anchor level no longer the current client level → destroy (force) + forget.
     */
    static void sweep() {
        if (LIVE.isEmpty()) {
            return;
        }
        ClientLevel current = Minecraft.getInstance().level;
        for (int i = LIVE.size() - 1; i >= 0; i--) {
            Tracked tracked = LIVE.get(i);
            if (!runtimeAlive(tracked.executor)) {
                LIVE.remove(i);
                continue;
            }
            boolean deadEntity = tracked.entity != null
                    && (!tracked.entity.isAlive() || tracked.entity.isRemoved());
            boolean leftDimension = current == null || tracked.level != current
                    || (tracked.entity != null && tracked.entity.level() != current);
            if (deadEntity || leftDimension) {
                LIVE.remove(i);
                destroyQuietly(tracked, true);
            }
        }
    }

    /** Force-destroys and forgets every tracked executor (logout / disconnect reset). */
    static void destroyAll() {
        for (Tracked tracked : LIVE) {
            destroyQuietly(tracked, true);
        }
        LIVE.clear();
    }

    private static boolean runtimeAlive(Object executor) {
        try {
            Object runtime = getRuntimeMethod.invoke(executor);
            return runtime != null && Boolean.TRUE.equals(runtimeIsAliveMethod.invoke(runtime));
        } catch (Throwable t) {
            return false;
        }
    }

    private static void destroyQuietly(Tracked tracked, boolean force) {
        try {
            Object runtime = getRuntimeMethod.invoke(tracked.executor);
            if (runtime != null) {
                runtimeDestroyMethod.invoke(runtime, force);
            }
        } catch (Throwable t) {
            // Teardown-order safe: Photon may have freed its state already — dropping the
            // reference is the part that matters (QuasarSpawner.clearAttached pattern).
        }
    }

    /** Client tick sweep + disconnect reset (kept as an inner class so PhotonBridge itself
     *  never registers event handlers when the mod list lacks photon — sweeps no-op fast). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Sweep {
        private Sweep() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            sweep();
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            destroyAll();
        }
    }

    // ------------------------------------------------------------------ dev/QA introspection

    /** Live executors currently tracked by the bridge (after the last sweep). */
    public static int liveExecutors() {
        return LIVE.size();
    }

    /** How many of the live executors are loops started via {@link #spawnLoop}. */
    public static int liveLoops() {
        int loops = 0;
        for (Tracked tracked : LIVE) {
            if (tracked.loop) {
                loops++;
            }
        }
        return loops;
    }

    /** Executor-budget refusals this session. */
    public static int refusedCount() {
        return refusedCount;
    }

    /** Immutable snapshot of the session's missing/broken fx ids. */
    public static Set<ResourceLocation> missingFxIds() {
        return Set.copyOf(MISSING_FX);
    }

    /** Human-readable reflection state: UNRESOLVED / READY / DISABLED. */
    public static String stateName() {
        return switch (state) {
            case READY -> "READY";
            case DISABLED -> "DISABLED";
            default -> "UNRESOLVED";
        };
    }

    // ------------------------------------------------------------------ reflection

    /** Lazily resolves the reflection handles once. @return {@code true} when READY. */
    private static boolean resolve() {
        if (state == READY) {
            return true;
        }
        if (state == DISABLED) {
            return false;
        }
        synchronized (PhotonBridge.class) {
            if (state != UNRESOLVED) {
                return state == READY;
            }
            try {
                Class<?> fxHelper = Class.forName("com.lowdragmc.photon.client.fx.FXHelper");
                Class<?> fxClass = Class.forName("com.lowdragmc.photon.client.fx.FX");
                Class<?> executorBase = Class.forName("com.lowdragmc.photon.client.fx.FXEffectExecutor");
                Class<?> blockExecutor = Class.forName("com.lowdragmc.photon.client.fx.BlockEffectExecutor");
                Class<?> entityExecutor = Class.forName("com.lowdragmc.photon.client.fx.EntityEffectExecutor");
                Class<?> autoRotate = Class.forName("com.lowdragmc.photon.client.fx.EntityEffectExecutor$AutoRotate");
                Class<?> runtime = Class.forName("com.lowdragmc.photon.client.fx.FXRuntime");
                getFxMethod = fxHelper.getMethod("getFX", ResourceLocation.class);
                blockExecutorCtor = blockExecutor.getConstructor(fxClass, Level.class, BlockPos.class);
                blockStartMethod = blockExecutor.getMethod("start");
                entityExecutorCtor = entityExecutor.getConstructor(fxClass, Level.class, Entity.class, autoRotate);
                entityStartMethod = entityExecutor.getMethod("start");
                autoRotateConstants = autoRotate.getEnumConstants();
                setOffsetMethod = executorBase.getMethod("setOffset", Vector3f.class);
                setRotationMethod = executorBase.getMethod("setRotation", Quaternionf.class);
                setScaleMethod = executorBase.getMethod("setScale", Vector3f.class);
                setDelayMethod = executorBase.getMethod("setDelay", int.class);
                setAllowMultiMethod = executorBase.getMethod("setAllowMulti", boolean.class);
                getRuntimeMethod = executorBase.getMethod("getRuntime");
                runtimeIsAliveMethod = runtime.getMethod("isAlive");
                runtimeDestroyMethod = runtime.getMethod("destroy", boolean.class);
                if (autoRotateConstants == null || autoRotateConstants.length < 4) {
                    throw new IllegalStateException("AutoRotate enum shape changed: "
                            + java.util.Arrays.toString(autoRotateConstants));
                }
                state = READY;
                EclipseMod.LOGGER.info("Photon detected — flagship-effect enhancement layer active");
                return true;
            } catch (Throwable t) {
                disable(t);
                return false;
            }
        }
    }

    private static void missing(ResourceLocation fxId) {
        if (MISSING_FX.add(fxId)) {
            EclipseMod.LOGGER.info(
                    "Photon is loaded but assets/{}/fx/{}.fx is absent — cue stays Quasar-only "
                            + "(author it via tools/photon/fxlib.py or Photon's editor, see docs/BUNDLING.md)",
                    fxId.getNamespace(), fxId.getPath());
        }
    }

    private static void disable(Throwable t) {
        if (state != DISABLED) {
            state = DISABLED;
            EclipseMod.LOGGER.warn(
                    "Photon bridge disabled for this session (API mismatch or load failure)", t);
        }
    }
}
