package dev.projecteclipse.eclipse.client.nether;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.network.nether.NetherOpenPayloads;
import dev.projecteclipse.eclipse.network.nether.S2CNetherOpenPayload;
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

/**
 * Client presentation of the day-2 nether-opening beats ({@code S2CNetherOpenPayload}).
 * Installs itself as the {@code NetherOpenPayloads} handler during client setup:
 *
 * <ul>
 *   <li>{@code OMEN} — the {@code nether_omen_ash} one-shot on the still-closed surface.</li>
 *   <li>{@code TREMOR} — {@value #FISSURE_STAMPS} {@code nether_quake_fissure} stamps in a
 *       star around the mouth. Each stamp is placed and YAWED from the crater center, so
 *       one authored crack asset covers the whole star; the angles are derived from the
 *       crater coordinates, so every client draws the SAME cracks.</li>
 *   <li>{@code RUPTURE} — the {@code nether_eruption} one-shot plus one hard shake hit on
 *       top of the rumble train (the pulse train alone cannot land a single-tick punch).</li>
 *   <li>{@code AFTERMATH} — hands the anchor to {@link NetherPitPlume} (fast-tracks its
 *       probe so the permanent cloud is up within a tick of the show ending).</li>
 *   <li>{@code RUMBLE} — the ground-rumble pulse train: the payload's intensity times THIS
 *       client's distance falloff, fed to {@link CameraDirector} as a low-frequency
 *       impulse. One broadcast, a proximity-correct shake for every player.</li>
 * </ul>
 *
 * <p>Every Photon spawn rides {@link PhotonBridge}'s full guard chain (photon absent,
 * {@code reducedFx}, missing asset, executor budget ⇒ silent no-op): the photon-less read of
 * the whole sequence is the server's own particle/sound stack, which every client gets.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class NetherOpenClientFx {
    /** Fissure stamps laid around the mouth in phase 2. */
    private static final int FISSURE_STAMPS = 5;
    /** Ring radius the stamps sit on, as a fraction of the crater mouth radius. */
    private static final double FISSURE_RING_FRACTION = 0.72D;
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
            case OMEN -> PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_OMEN_ASH, center);
            case TREMOR -> stampFissures(center);
            case RUPTURE -> {
                PhotonBridge.spawn(NetherOpenPhotonFxRows.FX_NETHER_ERUPTION, center);
                CameraDirector.addShakeImpulse(
                        RUPTURE_HIT_STRENGTH * proximity(minecraft, center),
                        RUPTURE_HIT_TICKS, RUPTURE_HIT_FREQUENCY);
            }
            case AFTERMATH -> NetherPitPlume.onOpened();
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
     * Lays the crack star. The stamps are a pure function of the crater coordinates (no
     * randomness, no extra sync), so the cracks are in the same places for everybody, and
     * each one is rotated to point outward from the mouth.
     */
    private static void stampFissures(Vec3 center) {
        double ringRadius = BreachGeometry.CRATER_RADIUS * FISSURE_RING_FRACTION;
        double phase = ((BreachGeometry.centerX() * 31L + BreachGeometry.centerZ()) % 360)
                * Mth.DEG_TO_RAD;
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

    /** This client's share of a beat: 1 at the rim of the pit, 0 past {@link #SHAKE_RANGE}. */
    private static float proximity(Minecraft minecraft, Vec3 center) {
        double distance = minecraft.gameRenderer.getMainCamera().getPosition().distanceTo(center);
        double linear = Math.max(0.0D, 1.0D - distance / SHAKE_RANGE);
        return (float) Math.pow(linear, SHAKE_FALLOFF_EXPONENT);
    }
}
