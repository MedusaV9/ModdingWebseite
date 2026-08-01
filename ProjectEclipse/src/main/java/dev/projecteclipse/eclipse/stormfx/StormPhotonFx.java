package dev.projecteclipse.eclipse.stormfx;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
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
 * STORM 2.0 W-C (PLAN-STORM2 §W-C): the PHOTON suite window manager. Owns the three
 * per-storm WINDOWED loops ({@code eclipse:storm_debris_belt}, {@code storm_cloud_belt},
 * {@code storm_skirt_dust} — authored by {@code tools/photon/build_storm_fx.py}) plus the
 * transient {@code storm_vein_bolt} one-shot, attached to <b>the nearest eligible sphere
 * storm only</b> (hard budget: crown 1 [StormFxClient] + belts 1 + clumps 1 + skirt 1 = 4
 * standing, +1 transient vein = 5 of {@link PhotonBridge#MAX_LIVE_EXECUTORS}).
 *
 * <p><b>C1 window law</b> (crown-halo {@code LoopHandle} pattern): attach inside
 * {@value #ATTACH_RANGE} shell distance, keep until {@value #RELEASE_RANGE} (hysteresis by
 * construction: the managed storm is only swapped after it fails its own gates), release on
 * DISSIPATE/EXPLODE/removal/{@code available()} false; refused spawns back off
 * {@value #RETRY_TICKS} ticks per loop. {@code reducedFx} flips
 * {@link PhotonBridge#available()} false and this manager <b>force-kills</b> (non-graceful)
 * every handle the same tick. {@code LoggingOut}/{@code Clone} force-release everything.
 * All clocks run on {@link StormFxClient#ticks()} (pause-frozen). Photon-less/reduced
 * clients keep the exact W-A/W-B frame — zero Quasar fallback emitters (LAYER law).</p>
 *
 * <p><b>Radius adaptation</b> (PHOTON-ADVANCED-2 §1 Channel B): {@code spawnLoop} exposes
 * no {@code SpawnOptions}, so the ring shapes are authored as {@code function} shapes over
 * the global expression variables {@code eclStormR}/{@code eclStormH}/{@code eclStormSpin}
 * (the last one is the STORM-MASS B8 parallax clock, {@link #stormSpinAngle()}); this
 * manager writes all three via {@code expr.Variable.make(name).setValue(...)} before every
 * spawn and refreshes them per tick (resize payloads re-shape the belts live, no respawn).
 * Fail-soft: if the {@code expr} reflection breaks, loops still run at the authored
 * dev-fallback ring (and {@code eclStormSpin} rests at 0 — bands simply stop orbiting).</p>
 *
 * <p><b>Live intensity tuning</b> (PHOTON-ADVANCED-2 §1 Channel A): emission rates scale
 * every tick with storm visibility x camera-distance falloff x gust swell by writing
 * {@code NumberFunction.constant(base * scale)} into each named emitter's shared
 * {@code ParticleConfig.emission}. Shared-config caveat honored: only ONE instance of each
 * id ever lives (nearest-storm law), pristine rate {@code NumberFunction}s are snapshotted
 * from an isolated {@code FXHelper.getFX(loc, false)} copy at attach and written back on
 * release, so the mutation never leaks into future spawns. {@link #TUNED_BASE_RATES} is
 * the frozen contract with {@code build_storm_fx.BASE_RATES} — keep them in sync.</p>
 *
 * <p><b>C3 vein trigger</b> (W-B §3 frozen contract): polls
 * {@link StormWeatherFx#innerFlashSerial()}; on a fresh serial belonging to the managed
 * storm ({@code innerFlashAmount > 0}) it fires one {@code storm_vein_bolt} at the flash
 * cell — {@code center + (cos/sin(bearing) * 0.92r * cos(lat * PI/2), lat * h)}, the W-B
 * light-anchor formula — yawed so the fx local +Z points radially out of the storm
 * ({@code allowMulti}, life ~8 t, at most one live per flash cadence).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
final class StormPhotonFx {
    /** C1 window: attach inside this shell distance, release beyond +20 (hysteresis). */
    private static final float ATTACH_RANGE = 160.0F;
    private static final float RELEASE_RANGE = ATTACH_RANGE + 20.0F;
    /** Refused-spawn (executor budget) retry cadence — the crown-halo backoff. */
    private static final int RETRY_TICKS = 40;
    /** Minimum shell visibility for the suite (crown-halo gate). */
    private static final float MIN_VIS = 0.2F;
    /** Vein anchor radius fraction — the W-B {@code LIGHT_RADIUS_FRAC} formula. */
    private static final float VEIN_RADIUS_FRAC = 0.92F;
    /** Re-anchor epsilon²: a moved center releases + respawns (crown pattern). */
    private static final double REANCHOR_EPSILON_SQ = 0.25D;

    /** The three standing loops, indexed LOOP_DEBRIS/CLOUD/SKIRT. */
    private static final ResourceLocation[] LOOP_IDS = {
            fx("storm_debris_belt"), fx("storm_cloud_belt"), fx("storm_skirt_dust")};
    private static final ResourceLocation VEIN_BOLT = fx("storm_vein_bolt");
    private static final int LOOP_COUNT = 3;

    /**
     * Frozen Channel-A contract with {@code tools/photon/build_storm_fx.py BASE_RATES}:
     * tuned emitter names and their authored emission rates, per loop.
     */
    private static final String[][] TUNED_EMITTERS = {
            {"belt_low", "belt_mid", "belt_high"},
            {"band_low", "band_mid", "band_high", "shred_racers"},
            {"skirt_motes", "skirt_haze"}};
    private static final float[][] TUNED_BASE_RATES = {
            {0.04F, 0.04F, 0.04F},
            {2.0F, 2.0F, 2.0F, 0.5F},
            {0.7F, 0.06F}};

    // ------------------------------------------------------------------ window state
    /** Managed storm id; {@code -1} = no window (nearest-sphere-only law). */
    private static int managedId = -1;
    /** Anchor the loops were spawned at (storm base center). */
    private static Vec3 anchor;
    private static final PhotonBridge.LoopHandle[] LOOPS =
            new PhotonBridge.LoopHandle[LOOP_COUNT];
    /** Earliest tick each loop may retry after a refused (budget) spawn. */
    private static final int[] NEXT_RETRY = new int[LOOP_COUNT];
    /** Last emission-rate scale written per loop ({@code -1} = never written). */
    private static final float[] LAST_SCALE = {-1.0F, -1.0F, -1.0F};
    /** Last consumed W-B flash serial (latched on attach — never fires stale flashes). */
    private static int lastFlashSerial = StormWeatherFx.innerFlashSerial();

    private StormPhotonFx() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    /**
     * Channel-B pusher shared with {@link StormNearfieldFx} (F-034): ONE last-value
     * cache for the global {@code eclStormR}/{@code eclStormH}/{@code eclStormSpin}
     * expression variables, so the two managers never fight over redundant writes.
     * Both windows resolve the same nearest sphere storm, so the values agree whenever
     * both are open.
     */
    static void pushExprVars(float radius, float height, float spin) {
        ExprVars.push(radius, height, spin);
    }

    /**
     * STORM-MASS B8: the shared parallax clock — a continuous orbit angle (radians)
     * on the volume's mid-strata RIM rate: {@code ROT_SPEED 0.10 × stratum 1.0 ×
     * (1.4 − 0.7·1.0) = 0.07 rad/s} (storm_volume.fsh), on the same pause-safe tick
     * clock as the {@code Time} uniform, PLUS the B7 churn clock ×1.6 exactly like the
     * shader's {@code spinT} — bands stay synced through a siege escalation and every
     * angle stays continuous. Sign law (jar-verified): the shader rotates its SAMPLING
     * by +spin, so world features turn by −spin in atan2(z,x); Photon's AngularVelocity
     * ({@code rotateY(orbital·0.05)/tick} ⇒ orbital is rad/s) also turns θ by −orbital.
     * The generated assets therefore use {@code bearing − eclStormSpin} spawn terms
     * with POSITIVE orbital rates 0.07 (rim) / 0.14 (upper strata) — the only two
     * rates (Photon has no differential rotation; one band = one angular rate).
     */
    static float stormSpinAngle() {
        return (StormFxClient.ticks() / 20.0F
                + 1.6F * StormVolumeFx.churnTimeSeconds()) * 0.07F;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            releaseAll(true); // bridge sweep force-kills too; this clears local state
            return;
        }
        if (minecraft.isPaused()) {
            return; // StormFxClient.ticks() frozen — windows and backoffs hold
        }
        if (!PhotonBridge.available()) {
            // reducedFx (or photon toggle/mod loss) kills the suite wholesale — the §5
            // ladder: tiers < 2 render the pure W-A/W-B geometry frame.
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
            releaseAll(false);
            managedId = storm.id;
            lastFlashSerial = StormWeatherFx.innerFlashSerial(); // never fire stale
        } else if (anchor != null && anchor.distanceToSqr(center) > REANCHOR_EPSILON_SQ) {
            // Re-anchoring a live loop is unsupported (crown rule) — release + respawn.
            releaseLoops(false);
        }

        // Channel B: keep the belt geometry variables fresh BEFORE any spawn this tick
        // (a resize payload re-shapes newly emitted particles live, no respawn needed).
        // B8: eclStormSpin rides along — new spawns land in the volume's rotating frame.
        ExprVars.push(storm.radius, storm.height, stormSpinAngle());

        ensureLoops(center, now);
        tuneLoops(storm, minecraft);
        tickVein(storm, center);
    }

    /**
     * Nearest eligible sphere storm, with hysteresis: the currently managed storm is kept
     * while it passes its own (wider) gates even if another storm edges closer — windows
     * only migrate after a release, so two overlapping storms never thrash the executors.
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
                continue;
            }
            double shellDist = shellDist(camera, storm);
            float range = storm.id == managedId ? RELEASE_RANGE : ATTACH_RANGE;
            if (shellDist >= range) {
                continue;
            }
            if (storm.id == managedId) {
                return storm; // hysteresis: hold the managed storm while it qualifies
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

    // ------------------------------------------------------------------ loops (C1)

    private static void ensureLoops(Vec3 center, int now) {
        for (int i = 0; i < LOOP_COUNT; i++) {
            PhotonBridge.LoopHandle handle = LOOPS[i];
            if (handle != null && !handle.alive()) {
                LOOPS[i] = null; // bridge sweep (level change) already reaped it
                handle = null;
            }
            if (handle != null || now < NEXT_RETRY[i]) {
                continue;
            }
            LOOPS[i] = PhotonBridge.spawnLoop(LOOP_IDS[i], center);
            if (LOOPS[i] == null) {
                NEXT_RETRY[i] = now + RETRY_TICKS; // budget backoff (crown cadence)
            } else {
                anchor = center;
                LAST_SCALE[i] = -1.0F;
                Tuner.attach(i);
            }
        }
    }

    /**
     * Channel-A live tune: {@code scale = visibility x distance falloff x gust swell},
     * written as {@code constant(base * scale)} into each tuned emitter. Only re-written
     * when the scale moved > 0.03 (no per-tick NumberFunction churn).
     */
    private static void tuneLoops(StormFxClient.ClientStorm storm, Minecraft minecraft) {
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        float vis = storm.visibility(1.0F);
        float near = Mth.clamp((ATTACH_RANGE - (float) shellDist(camera, storm))
                / (ATTACH_RANGE - 48.0F), 0.0F, 1.0F);
        float dist = 0.35F + 0.65F * near * near * (3.0F - 2.0F * near); // eased 0.35..1
        float gust = 1.0F + 0.3F * Mth.clamp(StormInteriorFx.gustAmount(), 0.0F, 1.0F);
        float scale = Mth.clamp(vis * dist * gust, 0.0F, 1.5F);
        for (int i = 0; i < LOOP_COUNT; i++) {
            if (LOOPS[i] != null && Math.abs(scale - LAST_SCALE[i]) > 0.03F) {
                if (Tuner.apply(i, scale)) {
                    LAST_SCALE[i] = scale;
                }
            }
        }
    }

    // ------------------------------------------------------------------ vein (C3)

    private static void tickVein(StormFxClient.ClientStorm storm, Vec3 center) {
        int serial = StormWeatherFx.innerFlashSerial();
        if (serial == lastFlashSerial) {
            return;
        }
        lastFlashSerial = serial; // latch even when skipped — serials never replay
        if (StormWeatherFx.innerFlashAmount(storm.id) <= 0.01F) {
            return; // the fresh flash belongs to a different (unmanaged) storm
        }
        double bearing = StormWeatherFx.innerFlashBearing(storm.id);
        float lat = StormWeatherFx.innerFlashLat(storm.id);
        double horiz = storm.radius * VEIN_RADIUS_FRAC * Math.cos(lat * (Math.PI / 2.0D));
        Vec3 pos = new Vec3(center.x + Math.cos(bearing) * horiz,
                center.y + lat * storm.height,
                center.z + Math.sin(bearing) * horiz);
        // Yaw so fx local +Z points radially OUT of the storm: the vein's zig plane
        // (local X/Y) lies tangent to the wall. One-shot, stacking-safe (allowMulti).
        PhotonBridge.spawn(VEIN_BOLT, pos, PhotonBridge.SpawnOptions.DEFAULT
                .withAllowMulti(true)
                .withRotationDeg(0.0D, 90.0D - Math.toDegrees(bearing), 0.0D));
    }

    // ------------------------------------------------------------------ release

    /** Stops the three loops; {@code force} skips the graceful particle fade. */
    private static void releaseLoops(boolean force) {
        for (int i = 0; i < LOOP_COUNT; i++) {
            PhotonBridge.LoopHandle handle = LOOPS[i];
            LOOPS[i] = null;
            NEXT_RETRY[i] = 0;
            LAST_SCALE[i] = -1.0F;
            if (handle != null) {
                Tuner.restore(i); // un-pollute the shared cached ParticleConfig
                PhotonBridge.stopLoop(handle, !force);
            }
        }
        anchor = null;
    }

    private static void releaseAll(boolean force) {
        if (managedId != -1 || anchor != null || LOOPS[0] != null || LOOPS[1] != null
                || LOOPS[2] != null) {
            releaseLoops(force);
            managedId = -1;
        }
    }

    /** Disconnect/respawn hygiene: no window survives the warp (W-B pattern). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        releaseAll(true);
    }

    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        releaseAll(true);
    }

    // ------------------------------------------------------------------ Channel B (expr)

    /**
     * Global expression variables driving the authored {@code function} ring shapes
     * (PHOTON-ADVANCED-2 §1 Channel B): {@code expr.Variable.make(name)} is a process-wide
     * registry, so one write reaches every live emitter. Fail-soft: any reflective
     * surprise disables the pusher for the session and the assets fall back to their
     * authored {@code max(var, floor)} dev ring — never a crash, never a missing effect.
     */
    private static final class ExprVars {
        private static final int UNRESOLVED = 0;
        private static final int READY = 1;
        private static final int DISABLED = 2;
        private static int state = UNRESOLVED;
        private static Method setValue;
        private static Object varRadius;
        private static Object varHeight;
        private static Object varSpin;
        private static float lastRadius = Float.NaN;
        private static float lastHeight = Float.NaN;
        private static float lastSpin = Float.NaN;

        private ExprVars() {}

        static void push(float radius, float height, float spin) {
            // The spin clock advances every unpaused tick, so this effectively writes
            // per tick (three reflective setValue calls — negligible); the last-value
            // cache still de-duplicates the paused/idle case.
            if (state == DISABLED
                    || (radius == lastRadius && height == lastHeight && spin == lastSpin)) {
                return;
            }
            try {
                if (state == UNRESOLVED) {
                    Class<?> variable = Class.forName("expr.Variable");
                    Method make = variable.getMethod("make", String.class);
                    setValue = variable.getMethod("setValue", double.class);
                    varRadius = make.invoke(null, "eclStormR");
                    varHeight = make.invoke(null, "eclStormH");
                    varSpin = make.invoke(null, "eclStormSpin");
                    state = READY;
                }
                setValue.invoke(varRadius, (double) radius);
                setValue.invoke(varHeight, (double) height);
                setValue.invoke(varSpin, (double) spin);
                lastRadius = radius;
                lastHeight = height;
                lastSpin = spin;
            } catch (Throwable t) {
                state = DISABLED;
                EclipseMod.LOGGER.debug(
                        "Photon expr variables unavailable — storm belts keep the authored ring", t);
            }
        }
    }

    // ------------------------------------------------------------------ Channel A (tuner)

    /**
     * Live emission-rate injection on the SHARED cached {@code ParticleConfig}s
     * (PHOTON-ADVANCED-2 §1 Channel A). Per managed loop: resolve the named emitters'
     * {@code EmissionSetting}s once from the cached {@code FXHelper.getFX(loc)} (the same
     * object identity every {@code PhotonBridge} runtime shallow-copies from), snapshot the
     * pristine rate {@code NumberFunction}s from an ISOLATED {@code FXHelper.getFX(loc,
     * false)} copy, then write {@code constant(base * scale)} live and the pristine object
     * back on release. Fail-soft: first reflective surprise disables tuning for the
     * session — loops keep their authored rates.
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

        /** Resolves the tuned emitters of loop {@code slot} (call after a spawn succeeds). */
        static void attach(int slot) {
            if (state == DISABLED || EMISSIONS[slot] != null || !resolve()) {
                return;
            }
            try {
                String[] names = TUNED_EMITTERS[slot];
                // Read-only resolution off the FX assets — no FXRuntime, no setScene, the
                // cached templates stay scene-less/parent-less (respawn-hygiene law above).
                Object cachedFx = getFxCached.invoke(null, LOOP_IDS[slot]);
                // The doc-mandated isolation: pristine rates come from a FRESH uncached FX
                // so restore() can never bake a previously tuned value back in.
                Object pristineFx = getFxIsolated.invoke(null, LOOP_IDS[slot], false);
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
                        "Photon storm live-tuner disabled for the session — loops keep authored rates", t);
            }
        }
    }
}
