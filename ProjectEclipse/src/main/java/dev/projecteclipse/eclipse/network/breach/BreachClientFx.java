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
