package dev.projecteclipse.eclipse.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import dev.projecteclipse.eclipse.entity.boss.rift.RiftWardenEntity;
import dev.projecteclipse.eclipse.entity.fog.FogColossusEntity;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Hit-stop "punch" impulse (W4-FEEL, IDEA-02 #3): a 2-tick, low-strength camera impulse
 * ({@code S2CShakePayload.shake(0.12F, 2)}) sent to the ATTACKER when their melee hit
 * connects on a heavyweight — {@link FogColossusEntity}, {@link FogTyrantEntity} or
 * {@link RiftWardenEntity}. The client {@code CameraDirector} impulse stack renders it as
 * a sharp micro-rattle that reads as hit-stop weight WITHOUT pausing the tick loop (safe
 * in multiplayer); {@code reducedFx} clients drop shake impulses in the director, so the
 * gate lives client-side where it belongs.
 *
 * <p>Guards: direct melee only ({@code getDirectEntity() == attacker} — projectiles and
 * AoE stay flat), damage actually applied ({@code getNewDamage() > 0} — fully-absorbed
 * hits don't punch), attacker is a real player. Listener shape mirrors
 * {@code analytics/AnalyticsService.onLivingDamagePost}. Stateless — nothing to reset.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HitStopService {
    /** Small + short + high-frequency = weight, not wobble (IDEA-02 #3 spec values). */
    private static final float PUNCH_STRENGTH = 0.12F;
    private static final int PUNCH_TICKS = 2;

    private HitStopService() {}

    @SubscribeEvent
    static void onLivingDamagePost(LivingDamageEvent.Post event) {
        LivingEntity victim = event.getEntity();
        if (victim.level().isClientSide() || event.getNewDamage() <= 0.0F) {
            return;
        }
        if (!(victim instanceof FogColossusEntity)
                && !(victim instanceof FogTyrantEntity)
                && !(victim instanceof RiftWardenEntity)) {
            return;
        }
        if (!(event.getSource().getEntity() instanceof ServerPlayer attacker)
                || event.getSource().getDirectEntity() != attacker) {
            return; // melee connects only — arrows/tridents/AoE stay flat
        }
        PacketDistributor.sendToPlayer(attacker, S2CShakePayload.shake(PUNCH_STRENGTH, PUNCH_TICKS));
    }
}
