package dev.projecteclipse.eclipse.progression;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.protection.ProtectionConfig;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageTypes;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Day-1 (configurable) overworld underside containment: players who fall below {@code bounceY}
 * are bounced upward without fall damage and trigger the containment FX payload.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ContainmentService {
    /** P2 registers this Quasar emitter; fallback particles apply until then. */
    public static final ResourceLocation CONTAINMENT_BOUNCE_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "containment_bounce");

    private static final int FALL_IMMUNITY_TICKS = 100;
    private static final int HINT_COLOR = 0xB98CFF;

    /** Per-player tick until which fall damage is suppressed after a bounce. */
    private static final Map<UUID, Integer> BOUNCED_UNTIL_TICK = new HashMap<>(); // statics reset on ServerStopped

    private ContainmentService() {}

    public static boolean isContainmentActive(int day) {
        return ProtectionConfig.current().containment().containmentDays().contains(day);
    }

    public static boolean hasFallImmunity(ServerPlayer player) {
        Integer until = BOUNCED_UNTIL_TICK.get(player.getUUID());
        return until != null && player.server.getTickCount() < until;
    }

    @SubscribeEvent
    public static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || player.level().isClientSide()) {
            return;
        }
        if (!player.isAlive() || player.isSpectator()) {
            return;
        }
        if (player.level().dimension() != Level.OVERWORLD) {
            return;
        }
        GameType mode = player.gameMode.getGameModeForPlayer();
        if (mode != GameType.SURVIVAL && mode != GameType.ADVENTURE) {
            return;
        }
        int day = DayScheduler.getDay(player.server);
        if (!isContainmentActive(day)) {
            return;
        }
        int bounceY = ProtectionConfig.current().containment().bounceY();
        if (player.getY() >= bounceY) {
            return;
        }
        applyBounce(player);
    }

    @SubscribeEvent
    public static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (!event.getSource().is(DamageTypes.FALL)) {
            return;
        }
        if (hasFallImmunity(player)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        BOUNCED_UNTIL_TICK.clear();
    }

    public static void applyBounce(ServerPlayer player) {
        Vec3 motion = player.getDeltaMovement();
        player.setDeltaMovement(motion.x * 0.4D, 2.8D, motion.z * 0.4D);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        BOUNCED_UNTIL_TICK.put(player.getUUID(), player.server.getTickCount() + FALL_IMMUNITY_TICKS);

        player.displayClientMessage(Component.translatable("message.eclipse.containment.bounce").withColor(HINT_COLOR), true);
        player.playNotifySound(SoundEvents.AMETHYST_CLUSTER_BREAK, SoundSource.PLAYERS, 0.6F, 1.35F);

        ServerLevel level = player.serverLevel();
        level.sendParticles(ParticleTypes.REVERSE_PORTAL, player.getX(), player.getY(), player.getZ(),
                8, 0.35D, 0.15D, 0.35D, 0.02D);

        PacketDistributor.sendToPlayer(player,
                new S2CQuasarPayload(CONTAINMENT_BOUNCE_EMITTER, player.position()));
    }

    /** Test hook: clears immunity map. */
    public static void clearImmunityForTests() {
        BOUNCED_UNTIL_TICK.clear();
    }
}
