package dev.projecteclipse.eclipse.stormfx;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.veilfx.StormNearfieldFxRows;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * F-034 LOD-handover window manager + F-033 stage-2 shockwave trigger. Owns the three
 * near-field WINDOWED loop rows registered by {@link StormNearfieldFxRows}
 * ({@code storm_nearfield_wisps} / {@code storm_ground_scud} / {@code storm_updraft_motes},
 * authored by {@code tools/photon/storm_nearfield_fx.py}) on <b>the nearest eligible
 * sphere storm only</b> (the {@code StormPhotonFx} nearest-storm law — the two managers
 * resolve the same storm, so the shared Channel-B variables never fight).
 *
 * <p><b>The handover contract (F-034):</b> beyond {@link StormVolumeFx#VOLUME_RANGE}
 * (~250 blocks shell distance) ONLY the simple Veil wall renders — no volumetric, no
 * near-field. Approaching through the 250→150 transition zone the volumetric raymarcher
 * fades in ({@code StormVolumeFx.STRENGTH_FADE_START}) and this manager fades the three
 * Photon near-field loops in <b>on the same ramp</b>: the loops attach (at zero emission)
 * when the shell distance drops under {@value #ATTACH_RANGE} and their live emission
 * rates ride {@code 1 - smoothstep(150, 250, shellDist)} × storm visibility (Channel A —
 * the {@code StormPhotonFx} live-tuner pattern, pristine rates snapshotted from an
 * isolated {@code FXHelper.getFX(loc, false)} copy and restored on release). Release at
 * {@value #RELEASE_RANGE} (hysteresis), on DISSIPATE/EXPLODE (graceful — the burst takes
 * over), on {@code reducedFx} (force) and on logout/respawn.</p>
 *
 * <p><b>F-033 stage 2:</b> watches every tracked storm for the burst release moment
 * (EXPLODE progress crossing {@code StormWallRenderer.EXPLODE_IMPLODE_FRAC} — the same
 * beat {@code StormFxClient.tickBurstBeats} fires the release boom on) and dispatches
 * {@code FxCues.CUE_STORM_BURST_SHOCKWAVE} ONCE per burst with {@code a} = the live
 * {@code radius / 24} executor scale (the row's custom leg forwards it through
 * {@code SpawnOptions.withScale}). Latched per storm id — keepalives never re-fire.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
final class StormNearfieldFx {
    /** Attach when the shell distance drops under the volumetric's own far edge. */
    private static final float ATTACH_RANGE = StormVolumeFx.VOLUME_RANGE;
    /** Full-intensity edge of the handover ramp (the volumetric's full-strength gate). */
    private static final float FULL_RANGE = StormVolumeFx.STRENGTH_FADE_START;
    /** Release beyond attach + 20 (hysteresis — the StormPhotonFx window law). */
    private static final float RELEASE_RANGE = ATTACH_RANGE + 20.0F;
    /** Minimum shell visibility for the suite (crown-halo gate). */
    private static final float MIN_VIS = 0.2F;
    /** Refused-spawn retry cadence (executor budget backoff, crown pattern). */
    private static final int RETRY_TICKS = 40;
    /** Re-anchor epsilon²: a moved center releases + re-ensures (crown pattern). */
    private static final double REANCHOR_EPSILON_SQ = 0.25D;
    /** The shockwave asset's authored reference radius (StormRegistry.DEFAULT_RADIUS). */
    private static final float SHOCKWAVE_REF_RADIUS = 24.0F;

    /** The three loop rows, indexed wisps/scud/updraft. */
    private static final ResourceLocation[] LOOP_CUES = {
            FxCues.CUE_STORM_NEARFIELD_WISPS, FxCues.CUE_STORM_GROUND_SCUD,
            FxCues.CUE_STORM_UPDRAFT_MOTES};
    /** Photon asset ids per loop (the tuner resolves emitters off the shared FX cache). */
    private static final ResourceLocation[] LOOP_FX = {
            StormNearfieldFxRows.FX_STORM_NEARFIELD_WISPS,
            StormNearfieldFxRows.FX_STORM_GROUND_SCUD,
            StormNearfieldFxRows.FX_STORM_UPDRAFT_MOTES};
    private static final int LOOP_COUNT = 3;

    /**
     * Frozen Channel-A contract with {@code tools/photon/storm_nearfield_fx.py
     * BASE_RATES}: tuned emitter names and their authored per-tick emission rates.
     */
    private static final String[][] TUNED_EMITTERS = {
            {"wisp_racers", "wisp_veils", "rain_curtain"},
            {"scud_shreds", "scud_grit"},
            {"updraft_motes", "updraft_glints"}};
    private static final float[][] TUNED_BASE_RATES = {
            {0.07F, 0.10F, 0.30F},
            {0.35F, 0.9F},
            {0.65F, 0.2F}};

    // ------------------------------------------------------------------ window state
    /** Managed storm id; {@code -1} = no window (nearest-sphere-only law). */
    private static int managedId = -1;
    /** Anchor the loops were ensured at (storm base center). */
    private static Vec3 anchor;
    /** Whether each loop is currently ensured through the registry lane. */
    private static final boolean[] LIVE = new boolean[LOOP_COUNT];
    /** Earliest tick each loop may retry after a refused (budget) spawn. */
    private static final int[] NEXT_RETRY = new int[LOOP_COUNT];
    /** Last emission-rate scale written per loop ({@code -1} = never written). */
    private static final float[] LAST_SCALE = {-1.0F, -1.0F, -1.0F};
    /** Storm ids whose burst shockwave already fired (cleared with the storm). */
    private static final Set<Integer> FIRED_BURSTS = new HashSet<>();

    private StormNearfieldFx() {}

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            releaseAll(true);
            FIRED_BURSTS.clear();
            return;
        }
        if (minecraft.isPaused()) {
            return; // StormFxClient.ticks() frozen — window and backoffs hold
        }
        tickBurstShockwave(); // independent of the loop window (bridge guards inside)
        if (!PhotonBridge.available()) {
            releaseAll(EclipseClientConfig.reducedFx());
            return;
        }
        StormFxClient.ClientStorm storm = resolveManagedStorm(minecraft);
        if (storm == null) {
            releaseAll(false);
            return;
        }
        int now = StormFxClient.ticks();
        Vec3 center = storm.center;
        if (managedId != storm.id) {
            releaseLoops(false);
            managedId = storm.id;
        } else if (anchor != null && anchor.distanceToSqr(center) > REANCHOR_EPSILON_SQ) {
            releaseLoops(false); // re-anchor = release + re-ensure (crown rule)
        }

        // Channel B: shared pusher (single last-value cache) — fresh BEFORE any ensure.
        // B8: eclStormSpin rides along (the parallax clock — see stormSpinAngle()).
        StormPhotonFx.pushExprVars(storm.radius, storm.height,
                StormPhotonFx.stormSpinAngle());

        ensureLoops(center, now);
        tuneLoops(storm, minecraft);
    }

    /**
     * F-033 stage 2: fire the shockwave row once per storm burst, at the release moment
     * (the pinch lets go — {@code EXPLODE_IMPLODE_FRAC}), scaled to the live radius.
     * Runs over ALL tracked storms, not just the managed window: a burst 300 blocks out
     * still shows its ring (the row's Photon leg guards range/budget internally).
     */
    private static void tickBurstShockwave() {
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        if (!FIRED_BURSTS.isEmpty()) {
            FIRED_BURSTS.removeIf(id -> {
                for (int i = 0; i < storms.size(); i++) {
                    if (storms.get(i).id == id) {
                        return false;
                    }
                }
                return true; // storm gone — forget the latch
            });
        }
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            if (storm.state != S2CStormStatePayload.STATE_EXPLODE
                    || storm.type != S2CStormStatePayload.TYPE_SPHERE
                    || storm.explodeProgress(1.0F) < StormWallRenderer.EXPLODE_IMPLODE_FRAC
                    || !FIRED_BURSTS.add(storm.id)) {
                continue;
            }
            PhotonFxRegistry.dispatch(FxCues.CUE_STORM_BURST_SHOCKWAVE,
                    new Vec3(storm.center.x, storm.center.y, storm.center.z),
                    storm.radius / SHOCKWAVE_REF_RADIUS, 0.0F);
        }
    }

    /**
     * Nearest eligible sphere storm with hysteresis (the {@code StormPhotonFx} law): the
     * managed storm is kept while it passes its own wider gate, so overlapping storms
     * never thrash the window.
     */
    private static StormFxClient.ClientStorm resolveManagedStorm(Minecraft minecraft) {
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        if (storms.isEmpty()) {
            return null;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        StormFxClient.ClientStorm best = null;
        double bestDist = Double.MAX_VALUE;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            if (storm.type != S2CStormStatePayload.TYPE_SPHERE
                    || (storm.state != S2CStormStatePayload.STATE_ACTIVE
                            && storm.state != S2CStormStatePayload.STATE_SPAWN)
                    || storm.visibility(1.0F) <= MIN_VIS) {
                continue; // DISSIPATE/EXPLODE fail here → graceful release below
            }
            double shellDist = shellDist(camera, storm);
            float range = storm.id == managedId ? RELEASE_RANGE : ATTACH_RANGE;
            if (shellDist >= range) {
                continue;
            }
            if (storm.id == managedId) {
                return storm;
            }
            if (shellDist < bestDist) {
                bestDist = shellDist;
                best = storm;
            }
        }
        return best;
    }

    private static double shellDist(Vec3 camera, StormFxClient.ClientStorm storm) {
        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        return Math.abs(Math.sqrt(dx * dx + dz * dz) - storm.radius);
    }

    // ------------------------------------------------------------------ loops

    private static void ensureLoops(Vec3 center, int now) {
        for (int i = 0; i < LOOP_COUNT; i++) {
            if (!LIVE[i] && now < NEXT_RETRY[i]) {
                continue;
            }
            boolean live = PhotonFxRegistry.ensureLoop(LOOP_CUES[i], center);
            if (live && !LIVE[i]) {
                anchor = center;
                LAST_SCALE[i] = -1.0F;
                Tuner.attach(i);
            } else if (!live) {
                NEXT_RETRY[i] = now + RETRY_TICKS; // budget backoff (crown cadence)
            }
            LIVE[i] = live;
        }
    }

    /**
     * Channel-A handover blend: {@code scale = handover ease × storm visibility}, where
     * the handover rides the volumetric's own 250→150 ramp — at the far edge the loops
     * idle at zero emission, at {@value #FULL_RANGE} they run the authored rates. Only
     * re-written when the scale moved &gt; 0.03 (no per-tick NumberFunction churn).
     */
    private static void tuneLoops(StormFxClient.ClientStorm storm, Minecraft minecraft) {
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        float handover = 1.0F - smoothstep(FULL_RANGE, ATTACH_RANGE,
                (float) shellDist(camera, storm));
        float scale = Mth.clamp(handover * storm.visibility(1.0F), 0.0F, 1.0F);
        for (int i = 0; i < LOOP_COUNT; i++) {
            if (LIVE[i] && Math.abs(scale - LAST_SCALE[i]) > 0.03F) {
                if (Tuner.apply(i, scale)) {
                    LAST_SCALE[i] = scale;
                }
            }
        }
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }

    // ------------------------------------------------------------------ release

    /** Closes the three loop windows; {@code force} skips the graceful particle fade. */
    private static void releaseLoops(boolean force) {
        for (int i = 0; i < LOOP_COUNT; i++) {
            if (LIVE[i]) {
                Tuner.restore(i); // un-pollute the shared cached ParticleConfig
                PhotonFxRegistry.releaseLoop(LOOP_CUES[i], !force);
            }
            LIVE[i] = false;
            NEXT_RETRY[i] = 0;
            LAST_SCALE[i] = -1.0F;
        }
        anchor = null;
    }

    private static void releaseAll(boolean force) {
        if (managedId != -1 || anchor != null || LIVE[0] || LIVE[1] || LIVE[2]) {
            releaseLoops(force);
            managedId = -1;
        }
    }

    /** Disconnect/respawn hygiene: no window survives the warp (StormPhotonFx pattern). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        releaseAll(true);
        FIRED_BURSTS.clear();
    }

    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        releaseAll(true);
        FIRED_BURSTS.clear();
    }

    // ------------------------------------------------------------------ Channel A (tuner)

    /**
     * Live emission-rate injection on the SHARED cached {@code ParticleConfig}s — the
     * {@code StormPhotonFx.Tuner} pattern verbatim (PHOTON-ADVANCED-2 §1 Channel A),
     * keyed to this suite's loops. Pristine rate {@code NumberFunction}s come from an
     * ISOLATED {@code FXHelper.getFX(loc, false)} copy at attach and are written back on
     * release, so the mutation never leaks into future spawns. Fail-soft: the first
     * reflective surprise disables tuning for the session — loops keep authored rates.
     *
     * <p><b>F-103 respawn hygiene — NIEMALS {@code FX.createInternalRuntime()} auf dem
     * geteilten Cache:</b> emitters resolve straight off the flat
     * {@code FX.getFxData().objects()} list (name match), NOT through a throwaway
     * {@code FXRuntime}. An internal runtime {@code setScene()}s + re-parents the CACHED
     * template objects, and because {@code FXObject.copy(false)} (the
     * {@code createRuntime()} spawn path) copies the live transform parent, every later
     * spawn copy then grafts itself into that stale internal scene — colliding the
     * authored asset UUIDs there and flooding "Duplicate fx runtime object id … is
     * replaced" on every subsequent attach (root cause of the F-102 duplicate storm,
     * see docs/plans_v3/session_0730/FX_RESPAWN_HYGIENE_REPORT.md).</p>
     */
    private static final class Tuner {
        private static final int UNRESOLVED = 0;
        private static final int READY = 1;
        private static final int DISABLED = 2;
        private static int state = UNRESOLVED;
        private static Method getFxCached;             // FXHelper.getFX(ResourceLocation)
        private static Method getFxIsolated;           // FXHelper.getFX(ResourceLocation, boolean)
        private static Method getFxData;               // FX.getFxData()
        private static Method fxDataObjects;           // FXData.objects()
        private static Method getObjectName;           // IFXObject.getName()
        private static Class<?> particleEmitterClass;
        private static Field configField;              // ParticleEmitter.config
        private static Field emissionField;            // ParticleConfig.emission
        private static Method setEmissionRate;         // EmissionSetting.setEmissionRate(NF)
        private static Method getEmissionRate;
        private static Method nfConstant;              // NumberFunction.constant(Number)

        /** Per loop slot: tuned EmissionSettings + their pristine rate NumberFunctions. */
        private static final Object[][] EMISSIONS = new Object[LOOP_COUNT][];
        private static final Object[][] PRISTINE = new Object[LOOP_COUNT][];

        private Tuner() {}

        private static boolean resolve() {
            if (state != UNRESOLVED) {
                return state == READY;
            }
            try {
                Class<?> fxHelper = Class.forName("com.lowdragmc.photon.client.fx.FXHelper");
                Class<?> fxClass = Class.forName("com.lowdragmc.photon.client.fx.FX");
                Class<?> fxObject = Class.forName(
                        "com.lowdragmc.photon.client.gameobject.IFXObject");
                particleEmitterClass = Class.forName(
                        "com.lowdragmc.photon.client.gameobject.emitter.particle.ParticleEmitter");
                Class<?> numberFunction = Class.forName(
                        "com.lowdragmc.photon.client.gameobject.emitter.data.number.NumberFunction");
                getFxCached = fxHelper.getMethod("getFX", ResourceLocation.class);
                getFxIsolated = fxHelper.getMethod("getFX", ResourceLocation.class, boolean.class);
                getFxData = fxClass.getMethod("getFxData");
                fxDataObjects = getFxData.getReturnType().getMethod("objects");
                getObjectName = fxObject.getMethod("getName");
                configField = accessible(particleEmitterClass, "config");
                emissionField = accessible(configField.getType(), "emission");
                Class<?> emissionSetting = emissionField.getType();
                setEmissionRate = emissionSetting.getMethod("setEmissionRate", numberFunction);
                getEmissionRate = emissionSetting.getMethod("getEmissionRate");
                nfConstant = numberFunction.getMethod("constant", Number.class);
                state = READY;
                return true;
            } catch (Throwable t) {
                disable(t);
                return false;
            }
        }

        private static Field accessible(Class<?> owner, String name) throws Exception {
            try {
                return owner.getField(name);
            } catch (NoSuchFieldException e) {
                Field field = owner.getDeclaredField(name);
                field.setAccessible(true);
                return field;
            }
        }

        /** Resolves the tuned emitters of loop {@code slot} (call after ensure succeeds). */
        static void attach(int slot) {
            if (state == DISABLED || EMISSIONS[slot] != null || !resolve()) {
                return;
            }
            try {
                String[] names = TUNED_EMITTERS[slot];
                // Read-only resolution off the FX assets — no FXRuntime, no setScene, the
                // cached templates stay scene-less/parent-less (respawn-hygiene law above).
                Object cachedFx = getFxCached.invoke(null, LOOP_FX[slot]);
                Object pristineFx = getFxIsolated.invoke(null, LOOP_FX[slot], false);
                Object[] emissions = new Object[names.length];
                Object[] pristine = new Object[names.length];
                for (int i = 0; i < names.length; i++) {
                    emissions[i] = emissionOf(cachedFx, names[i]);
                    pristine[i] = getEmissionRate.invoke(emissionOf(pristineFx, names[i]));
                }
                EMISSIONS[slot] = emissions;
                PRISTINE[slot] = pristine;
            } catch (Throwable t) {
                disable(t);
            }
        }

        /** Finds the named ParticleEmitter on {@code fx}'s flat object list (no runtime). */
        private static Object emissionOf(Object fx, String name) throws Exception {
            for (Object candidate : (List<?>) fxDataObjects.invoke(getFxData.invoke(fx))) {
                if (particleEmitterClass.isInstance(candidate)
                        && name.equals(getObjectName.invoke(candidate))) {
                    return emissionField.get(configField.get(candidate));
                }
            }
            throw new IllegalStateException("tuned emitter missing: " + name);
        }

        /** Writes {@code constant(base * scale)} into every tuned emitter of the loop. */
        static boolean apply(int slot, float scale) {
            Object[] emissions = EMISSIONS[slot];
            if (state != READY || emissions == null) {
                return state != READY; // "handled" when broken: stop re-trying every tick
            }
            try {
                float[] bases = TUNED_BASE_RATES[slot];
                for (int i = 0; i < emissions.length; i++) {
                    setEmissionRate.invoke(emissions[i],
                            nfConstant.invoke(null, bases[i] * scale));
                }
                return true;
            } catch (Throwable t) {
                disable(t);
                return true;
            }
        }

        /** Writes the pristine authored rates back into the shared cached config. */
        static void restore(int slot) {
            Object[] emissions = EMISSIONS[slot];
            Object[] pristine = PRISTINE[slot];
            EMISSIONS[slot] = null;
            PRISTINE[slot] = null;
            if (state != READY || emissions == null) {
                return;
            }
            try {
                for (int i = 0; i < emissions.length; i++) {
                    setEmissionRate.invoke(emissions[i],
                            pristine[i] != null ? pristine[i]
                                    : nfConstant.invoke(null, TUNED_BASE_RATES[slot][i]));
                }
            } catch (Throwable t) {
                disable(t);
            }
        }

        private static void disable(Throwable t) {
            if (state != DISABLED) {
                state = DISABLED;
                EclipseMod.LOGGER.debug(
                        "Photon nearfield live-tuner disabled for the session — loops keep authored rates", t);
            }
        }
    }
}
