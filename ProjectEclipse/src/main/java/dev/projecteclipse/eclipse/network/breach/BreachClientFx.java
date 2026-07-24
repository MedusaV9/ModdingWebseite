package dev.projecteclipse.eclipse.network.breach;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CBreachPayload;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * Client FX consumer for the nether-breach phase payloads (W1.7 seam). Installs itself as
 * the {@link BreachPayloads} phase handler during client setup: QUAKE rumbles the camera,
 * OPEN bursts a dust ring around the crater rim, SETTLED leaves a soft smoke sigh. All
 * spawns go through {@link QuasarSpawner} so the FX budget applies.
 *
 * <p>IDEA-17 (W4-NETHER) glitch-drift phases: DRIFT_DOWN/DRIFT_UP fire one short Veil
 * transition glitch PULSE ({@code EclipseFxState.startTransitionGlitch}, hold from the
 * payload, hard-clamped — the dimension swap at each seam hides inside the pulse while
 * the rest of the ride stays visible), plus a subtle camera-shake pulse and a
 * soul-escape capture sting. DRIFT_END forces the glitch out-ramp and lands the arrival "thud"
 * (placeholder {@code RESPAWN_ANCHOR_DEPLETE} until the wiring sound ask ships a
 * dedicated cue). The orbiting REVERSE_PORTAL ring and ash streaks are server
 * particles from {@code BreachTransferService} — no client tick handler needed.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class BreachClientFx {
    private static final ResourceLocation RIM_DUST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "structure_slam_dust");
    private static final ResourceLocation RIM_SMOKE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_veil");
    /** Beyond this distance the shake fades to zero (blocks). */
    private static final double SHAKE_RANGE = 160.0D;

    private BreachClientFx() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        BreachPayloads.setClientPhaseHandler(BreachClientFx::handle);
    }

    private static void handle(S2CBreachPayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null) {
            return;
        }
        BlockPos center = payload.center();
        Vec3 centerVec = Vec3.atCenterOf(center);
        double distance = minecraft.player.position().distanceTo(centerVec);
        float proximity = (float) Math.max(0.0D, 1.0D - distance / SHAKE_RANGE);
        switch (payload.phase()) {
            case QUAKE -> {
                dev.projecteclipse.eclipse.cutscene.client.CameraDirector
                        .addShakeImpulse(0.35F + 0.45F * proximity, 50);
                minecraft.level.playLocalSound(center, SoundEvents.AMBIENT_CAVE.value(),
                        SoundSource.AMBIENT, 1.4F, 0.55F, false);
            }
            case OPEN -> {
                dev.projecteclipse.eclipse.cutscene.client.CameraDirector
                        .addShakeImpulse(0.6F + 0.6F * proximity, 70);
                spawnRimRing(payload, centerVec, RIM_DUST, 8);
                minecraft.level.playLocalSound(center, SoundEvents.LIGHTNING_BOLT_THUNDER,
                        SoundSource.AMBIENT, 2.0F, 0.6F, false);
            }
            case SETTLED -> spawnRimRing(payload, centerVec, RIM_SMOKE, 5);
            case DRIFT_DOWN, DRIFT_UP -> {
                // One glitch PULSE per payload (capture + each dimension seam — the
                // teleport hides inside the pulse's hold). radius = the server's hold
                // estimate in ticks, clamped hard: the transition envelope also drives
                // FadeAmount, so a long hold would black the screen out instead of
                // letting the player watch the ride.
                int hold = Math.max(6, Math.min(payload.radius(), 18));
                dev.projecteclipse.eclipse.veilfx.EclipseFxState
                        .startTransitionGlitch(5, hold, 18);
                dev.projecteclipse.eclipse.cutscene.client.CameraDirector
                        .addShakeImpulse(0.18F, 24);
                minecraft.level.playLocalSound(minecraft.player.blockPosition(),
                        SoundEvents.SOUL_ESCAPE.value(), SoundSource.AMBIENT, 0.9F, 0.6F, false);
            }
            case DRIFT_END -> {
                // Force a final short out ramp (in 0 = start at full glitch).
                dev.projecteclipse.eclipse.veilfx.EclipseFxState
                        .startTransitionGlitch(0, 0, 12);
                dev.projecteclipse.eclipse.cutscene.client.CameraDirector
                        .addShakeImpulse(0.3F, 18);
                // Arrival thud (wiring sound ask: replace with a dedicated cue).
                minecraft.level.playLocalSound(minecraft.player.blockPosition(),
                        SoundEvents.RESPAWN_ANCHOR_DEPLETE.value(), SoundSource.AMBIENT,
                        0.7F, 0.55F, false);
            }
        }
    }

    private static void spawnRimRing(S2CBreachPayload payload, Vec3 center,
            ResourceLocation emitter, int points) {
        double radius = Math.max(4, payload.radius());
        for (int i = 0; i < points; i++) {
            double angle = (Math.PI * 2.0D / points) * i;
            Vec3 pos = center.add(Math.cos(angle) * radius, 1.0D, Math.sin(angle) * radius);
            QuasarSpawner.spawnOrFallback(emitter, pos);
        }
    }
}
