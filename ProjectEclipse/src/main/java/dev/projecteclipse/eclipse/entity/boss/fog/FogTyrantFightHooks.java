package dev.projecteclipse.eclipse.entity.boss.fog;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;

/**
 * F-082 death hook for the Fog Tyrant fight (deliberately a tiny family-owned sibling,
 * NEVER in {@code lives/} — {@code LifecycleEvents} keeps owning graves/hearts): when a
 * player dies, every live tyrant nearby is offered the death and flags its
 * {@code participantDied} wipe gate itself IF the victim was enrolled
 * ({@link FogTyrantEntity#noteParticipantDeath}). Flag-only — grave placement
 * ({@code LifecycleEvents.onLivingDrops}) and the ship theater ({@code DeathFlowHooks})
 * run exactly as before.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogTyrantFightHooks {
    /**
     * Death-position → tyrant scan radius. Generous on purpose (arena r=16, leash 18,
     * reset ring 24, storm-step wander): an enrolled participant dying anywhere near
     * the fight must arm the wipe gate; enrollment itself is the real filter.
     */
    private static final double DEATH_SCAN_RANGE = 64.0D;

    private FogTyrantFightHooks() {}

    @SubscribeEvent
    static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !(player.level() instanceof ServerLevel level)) {
            return;
        }
        for (FogTyrantEntity tyrant : level.getEntitiesOfClass(FogTyrantEntity.class,
                player.getBoundingBox().inflate(DEATH_SCAN_RANGE), FogTyrantEntity::isAlive)) {
            tyrant.noteParticipantDeath(player.getUUID());
        }
    }
}
