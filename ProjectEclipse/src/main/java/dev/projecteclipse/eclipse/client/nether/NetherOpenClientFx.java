package dev.projecteclipse.eclipse.client.nether;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.network.nether.NetherOpenPayloads;
import dev.projecteclipse.eclipse.network.nether.S2CNetherOpenPayload;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.NetherOpenPhotonFxRows;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import net.minecraft.client.Minecraft;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client presentation of the day-2 nether-opening beats ({@code S2CNetherOpenPayload}).
 * Installs itself as the {@code NetherOpenPayloads} handler during client setup:
 *
 * <ul>
 *   <li>{@code OMEN} — the {@code nether_omen_ash} one-shot (F-102: its silhouette is now
 *       the dark VEIL CONE) on the still-closed surface, plus the F-102 mid-omen BEAT: the
 *       asset bakes a ground-shock poff at asset-t {@value #OMEN_BEAT_AT}
 *       ({@code veil_slump}) and {@link Beats} kicks the camera on the SAME client tick,
 *       so phase 1 lands one fühlbarer Einschlag instead of 12 s of drone.</li>
 *   <li>{@code TREMOR} — {@value #FISSURE_STAMPS} {@code nether_quake_fissure} stamps in a
 *       star around the mouth. Each stamp is placed and YAWED from the crater center, so
 *       one authored crack asset covers the whole star; the angles are derived from the
 *       crater coordinates, so every client draws the SAME cracks. F-102: plus ONE
 *       {@code nether_tremor_waves} carpet over the whole footprint (popping Kiesel +
 *       boiling ground-dust heave — the phase-wide silhouette the fissures alone never
 *       gave). The per-slam dust RINGS ride the {@code nether_tremor_slam} cue lane from
 *       {@code sequence.NetherUpheavalFx} instead (they must land on the hop-wave
 *       landing tick, which only the server knows) — {@link #tremorSlamKick} is that
 *       row's camera half.</li>
 *   <li>{@code RUPTURE} — the {@code nether_eruption} one-shot plus one hard shake hit on
 *       top of the rumble train (the pulse train alone cannot land a single-tick punch).
 *       F-102: plus the {@value #SPOKE_STAMPS}-spoke Riss-Glut-Speichen star
 *       ({@code nether_rupture_spoke}, one authored radial line yawed per spoke — the
 *       fissure-star trick at ground level, rotated a half-step against it so the two
 *       stars interleave instead of overdrawing).</li>
 *   <li>{@code AFTERMATH} — hands the anchor to {@link NetherPitPlume} (fast-tracks its
 *       probe so the permanent cloud is up within a tick of the show ending).</li>
 *   <li>{@code RUMBLE} — the ground-rumble pulse train: the payload's intensity times THIS
 *       client's distance falloff, fed to {@link CameraDirector} as a low-frequency
 *       impulse. One broadcast, a proximity-correct shake for every player.</li>
 * </ul>
 *
 * <p>FX-12: every phase also drives the {@code eclipse:world_grade} heat feed
 * ({@link EclipseFxState#setNetherHeat}) — an ember lean plus sky shimmer that climbs
 * through OMEN/TREMOR, spikes on RUPTURE and releases over AFTERMATH, each target scaled
 * by the same {@link #proximity} falloff the rumble uses.</p>
 *
 * <p>Every Photon spawn rides {@link PhotonBridge}'s full guard chain (photon absent,
 * {@code reducedFx}, missing asset, executor budget ⇒ silent no-op): the photon-less read of
 * the whole sequence is the server's own particle/sound stack, which every client gets.
 * The camera kicks ({@link Beats}, {@link #tremorSlamKick}) deliberately fire OUTSIDE that
 * chain — a reduced/photon-less client still gets the beat FEEL, exactly like the shipped
 * RUMBLE train.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class NetherOpenClientFx {
    /** Fissure stamps laid around the mouth in phase 2. */
    private static final int FISSURE_STAMPS = 5;
    /** Ring radius the stamps sit on, as a fraction of the crater mouth radius. */
    private static final double FISSURE_RING_FRACTION = 0.72D;
    /** F-102 rupture Speichen-Stern: stamps of the ONE authored radial ember spoke. */
    private static final int SPOKE_STAMPS = 6;
    /**
     * Beyond this distance the rumble fades to zero (blocks). The falloff is raised to
     * {@value #SHAKE_FALLOFF_EXPONENT}, so the shake is only really FELT inside ~60 blocks
     * (the user's ask) while distant players still get a hint that something is wrong.
     */
    private static final double SHAKE_RANGE = 120.0D;
    private static final double SHAKE_FALLOFF_EXPONENT = 1.8D;
    /** Rumble impulse length — slightly longer than the pulse cadence, so they overlap. */
    private static final int RUMBLE_IMPULSE_TICKS = 26;
    /** Shake frequency: below 1 reads as a heavy ground rumble (CameraDirector doc). */
    private static final float RUMBLE_FREQUENCY = 0.55F;
    /** The rupture punch on top of the train. */
    private static final float RUPTURE_HIT_STRENGTH = 1.3F;
    private static final int RUPTURE_HIT_TICKS = 55;
    private static final float RUPTURE_HIT_FREQUENCY = 1.4F;
    /** The omen/eruption anchors sit this far above the lip plane. */
    private static final double SURFACE_LIFT = 0.5D;

    // --- F-102 Einschlag-Beats (one per phase; TREMOR's ride the slam cue) ---
    /**
     * OMEN-local tick of the mid-omen ground-shock beat. MUST equal the
     * {@code veil_slump} burst tick baked into {@code nether_omen_ash}
     * ({@code tools/photon/nether_open_fx.py OMEN_BEAT_TICK}) — the poff and the camera
     * kick are two halves of ONE beat and drift apart if these disagree.
     */
    private static final int OMEN_BEAT_AT = 120;
    /** The omen beat: a single soft body hit, clearly above the 0.10–0.32 omen drone. */
    private static final float OMEN_BEAT_STRENGTH = 0.55F;
    private static final int OMEN_BEAT_TICKS = 20;
    private static final float OMEN_BEAT_FREQUENCY = 1.1F;
    /**
     * Tremor slam kick band: {@code MIN + SPAN × pressure} before the proximity scale.
     * Frequency 1.7 = a sharp RATTLE riding on the 0.55-frequency rumble bed — the two
     * shakes read as different events (impact vs. ground) even when they overlap.
     */
    private static final float SLAM_KICK_MIN = 0.35F;
    private static final float SLAM_KICK_SPAN = 0.55F;
    private static final int SLAM_KICK_TICKS = 14;
    private static final float SLAM_KICK_FREQUENCY = 1.7F;

    /**
     * FX-12 "Glutgrad": the {@code eclipse:world_grade} heat feed per phase — the desert
     * warms through the omen and the quake, spikes when the pit tears open and bleeds off
     * over the aftermath. Each target is scaled by THIS client's {@link #proximity} share,
     * so the grade is a local pressure (the rumble law), not a server-wide screen filter.
     */
    private static final float HEAT_OMEN = 0.25F;
    private static final int HEAT_OMEN_RAMP = 120;
    private static final float HEAT_TREMOR = 0.45F;
    private static final int HEAT_TREMOR_RAMP = 120;
    private static final float HEAT_RUPTURE = 0.8F;
    private static final int HEAT_RUPTURE_RAMP = 10;
    /** The release always runs to a hard 0 — a stale heat lean must never survive the show. */
    private static final int HEAT_RELEASE_RAMP = 200;

    private NetherOpenClientFx() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        NetherOpenPayloads.setClientHandler(NetherOpenClientFx::handle);
    }

    private static void handle(S2CNetherOpenPayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            return;
        }
        Vec3 center = new Vec3(payload.center().getX() + 0.5D,
                payload.center().getY() + SURFACE_LIFT, payload.center().getZ() + 0.5D);
        switch (payload.phase()) {
            case OMEN -> {
                PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_OMEN_ASH, center);
                Beats.armOmenBeat(center);
                heat(minecraft, center, HEAT_OMEN, HEAT_OMEN_RAMP);
            }
            case TREMOR -> {
                // F-102 quake carpet: ONE asset owns the footprint-wide silhouette
                // (popping Kiesel + dust heave) so the crack stamps stop carrying phase 2
                // alone. Same anchor as the fissure star's center.
                PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_TREMOR_WAVES, center);
                stampFissures(center);
                heat(minecraft, center, HEAT_TREMOR, HEAT_TREMOR_RAMP);
            }
            case RUPTURE -> {
                PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_ERUPTION, center);
                stampRuptureSpokes(center);
                CameraDirector.addShakeImpulse(
                        RUPTURE_HIT_STRENGTH * proximity(minecraft, center),
                        RUPTURE_HIT_TICKS, RUPTURE_HIT_FREQUENCY);
                heat(minecraft, center, HEAT_RUPTURE, HEAT_RUPTURE_RAMP);
            }
            case AFTERMATH -> {
                NetherPitPlume.onOpened();
                EclipseFxState.setNetherHeat(0.0F, HEAT_RELEASE_RAMP);
            }
            case RUMBLE -> {
                float strength = payload.intensity() * proximity(minecraft, center);
                if (strength > 0.001F) {
                    CameraDirector.addShakeImpulse(strength, RUMBLE_IMPULSE_TICKS,
                            RUMBLE_FREQUENCY);
                }
            }
        }
    }

    /**
     * Camera half of the F-102 {@code nether_tremor_slam} cue row
     * ({@code veilfx.NetherOpenPhotonFxRows.tremorSlamLeg}): one short, sharp,
     * proximity-scaled rattle the tick a hop wave slams back into the ground. Fired
     * BEFORE (and independent of) the Photon ring stamp, so reduced/photon-less clients
     * keep the beat feel. Client main thread (the registry dispatch contract).
     *
     * @param pos      the slam cue anchor (crater lip center)
     * @param pressure the server's quake pressure 0..1 at the landing tick (payload a)
     */
    public static void tremorSlamKick(Vec3 pos, float pressure) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            return;
        }
        float strength = (SLAM_KICK_MIN + SLAM_KICK_SPAN * Mth.clamp(pressure, 0.0F, 1.0F))
                * proximity(minecraft, pos);
        if (strength > 0.001F) {
            CameraDirector.addShakeImpulse(strength, SLAM_KICK_TICKS, SLAM_KICK_FREQUENCY);
        }
    }

    /**
     * Lays the crack star. The stamps are a pure function of the crater coordinates (no
     * randomness, no extra sync), so the cracks are in the same places for everybody, and
     * each one is rotated to point outward from the mouth.
     */
    private static void stampFissures(Vec3 center) {
        double ringRadius = BreachGeometry.CRATER_RADIUS * FISSURE_RING_FRACTION;
        double phase = starPhase();
        for (int i = 0; i < FISSURE_STAMPS; i++) {
            double angle = phase + i * (Math.PI * 2.0D / FISSURE_STAMPS);
            Vec3 at = center.add(Math.cos(angle) * ringRadius, 0.0D, Math.sin(angle) * ringRadius);
            // The authored crack runs along local X; yaw it onto the radial bearing. Photon
            // yaw grows clockwise from +X, hence the negated angle.
            PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_QUAKE_FISSURE, at,
                    PhotonBridge.SpawnOptions.DEFAULT.withRotationDeg(
                            0.0D, -angle * Mth.RAD_TO_DEG, 0.0D));
        }
    }

    /**
     * F-102: lays the rupture Speichen-Stern — {@value #SPOKE_STAMPS} stamps of the ONE
     * authored radial ember line ({@code nether_rupture_spoke}, local +X 3..15), all
     * anchored at the crater CENTER and yawed outward (the fissure-star trick; the spoke
     * asset carries the radial offset itself). Rotated half a spoke step against the
     * fissure star: the phase-2 crack particles are long dead by RUPTURE (stamped at
     * t=240, ≤140 t life), so this is not about overdraw — it makes the rupture star
     * NEW ground geometry (fresh lines tearing where none glowed before) instead of the
     * same cracks re-igniting. allowMulti: all six share one anchor within one tick —
     * Photon's same-anchor dedup would keep exactly one spoke and silently eat the star.
     */
    private static void stampRuptureSpokes(Vec3 center) {
        double phase = starPhase() + Math.PI / SPOKE_STAMPS;
        for (int i = 0; i < SPOKE_STAMPS; i++) {
            double angle = phase + i * (Math.PI * 2.0D / SPOKE_STAMPS);
            PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_RUPTURE_SPOKE, center,
                    PhotonBridge.SpawnOptions.DEFAULT
                            .withRotationDeg(0.0D, -angle * Mth.RAD_TO_DEG, 0.0D)
                            .withAllowMulti(true));
        }
    }

    /** Deterministic star rotation shared by fissures and spokes (same on every client). */
    private static double starPhase() {
        return ((BreachGeometry.centerX() * 31L + BreachGeometry.centerZ()) % 360)
                * Mth.DEG_TO_RAD;
    }

    /** Ramps the world-grade heat to this client's proximity-scaled share of {@code target}. */
    private static void heat(Minecraft minecraft, Vec3 center, float target, int rampTicks) {
        EclipseFxState.setNetherHeat(target * proximity(minecraft, center), rampTicks);
    }

    /** This client's share of a beat: 1 at the rim of the pit, 0 past {@link #SHAKE_RANGE}. */
    private static float proximity(Minecraft minecraft, Vec3 center) {
        double distance = minecraft.gameRenderer.getMainCamera().getPosition().distanceTo(center);
        double linear = Math.max(0.0D, 1.0D - distance / SHAKE_RANGE);
        return (float) Math.pow(linear, SHAKE_FALLOFF_EXPONENT);
    }

    // ------------------------------------------------------------------ F-102 beat clock

    /**
     * The client-tick half of the mid-omen beat (GAME-bus nested class — the outer class
     * lives on the MOD bus for {@code FMLClientSetupEvent}; the {@code SmallCueFxRows.
     * SanctumConfession} nesting precedent). The {@code veil_slump} poff is BAKED into
     * the omen asset at asset-t {@value #OMEN_BEAT_AT} (a burst inside the one-shot —
     * per-phase wire beats stay off the table, F-102 rule), so the matching camera kick
     * is client-scheduled from the OMEN payload tick: both halves start from the same
     * tick and meet {@value #OMEN_BEAT_AT} ticks later. Pause freezes the countdown
     * (Photon's sim freezes with the level, so the halves stay in step); logout clears
     * it. A {@code /dev nether stop} inside the 6 s window leaves one soft orphan kick —
     * dev-only, strength {@value #OMEN_BEAT_STRENGTH}, accepted.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Beats {
        /** Ticks until the omen kick fires; ≤ 0 = disarmed. Client main thread only. */
        private static int omenCountdown;
        /** The beat anchor (crater lip center) the proximity scale is taken against. */
        private static Vec3 omenAnchor = Vec3.ZERO;

        private Beats() {}

        /** Arms the omen beat clock (called from the OMEN payload, client main thread). */
        static void armOmenBeat(Vec3 center) {
            omenCountdown = OMEN_BEAT_AT;
            omenAnchor = center;
        }

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            if (omenCountdown <= 0) {
                return;
            }
            Minecraft minecraft = Minecraft.getInstance();
            if (minecraft.level == null || minecraft.player == null) {
                omenCountdown = 0; // world gone: the show is gone too
                return;
            }
            if (minecraft.isPaused()) {
                return; // freeze with the level — the baked poff freezes too
            }
            if (--omenCountdown == 0) {
                CameraDirector.addShakeImpulse(
                        OMEN_BEAT_STRENGTH * proximity(minecraft, omenAnchor),
                        OMEN_BEAT_TICKS, OMEN_BEAT_FREQUENCY);
            }
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            omenCountdown = 0;
        }
    }
}
