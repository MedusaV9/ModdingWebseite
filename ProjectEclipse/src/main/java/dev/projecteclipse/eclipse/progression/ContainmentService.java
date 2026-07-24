package dev.projecteclipse.eclipse.progression;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
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
 *
 * <p><b>Anticipation squash (W4-FEEL, IDEA-04 #6):</b> the bounce used to teleport-feel —
 * an instant velocity flip at {@code bounceY}. Now a pre-band telegraphs it (falling fast
 * through the {@value #ANTICIPATION_BAND} blocks above {@code bounceY}: reverse-portal
 * motes streaming below the player + one low warning chime per fall), and the bounce
 * itself squashes: horizontal velocity compresses to {@value #SQUASH_FACTOR} at the flip
 * and releases back to the old 0.4-equivalent {@value #SQUASH_TICKS} ticks later — the
 * arc visibly pinches then springs, readable in third person and for bystanders.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ContainmentService {
    /** P2 registers this Quasar emitter; fallback particles apply until then. */
    public static final ResourceLocation CONTAINMENT_BOUNCE_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "containment_bounce");

    private static final int FALL_IMMUNITY_TICKS = 100;
    private static final int HINT_COLOR = 0xB98CFF;

    /** Anticipation pre-band above {@code bounceY} (blocks) and its fall-speed gate. */
    private static final int ANTICIPATION_BAND = 10;
    private static final double ANTICIPATION_MIN_FALL_SPEED = -0.4D;
    /** Squash: horizontal factor at the flip (was a flat 0.4) + release delay/boost. */
    private static final double SQUASH_FACTOR = 0.25D;
    private static final int SQUASH_TICKS = 3;
    /** Release restores the pre-squash 0.4 horizontal budget: 0.25 × 1.6 = 0.4. */
    private static final double SQUASH_RELEASE_BOOST = 1.6D;

    /** Per-player tick until which fall damage is suppressed after a bounce. */
    private static final Map<UUID, Integer> BOUNCED_UNTIL_TICK = new HashMap<>(); // statics reset on ServerStopped
    /** Players already chimed during the current fall (cleared above the band). */
    private static final Set<UUID> ANTICIPATION_WARNED = new HashSet<>(); // statics reset on ServerStopped
    /** Post-bounce squash countdowns; at zero the horizontal release boost fires. */
    private static final Map<UUID, Integer> SQUASH_RELEASE = new HashMap<>(); // statics reset on ServerStopped

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
        tickSquashRelease(player);
        int bounceY = ProtectionConfig.current().containment().bounceY();
        if (player.getY() >= bounceY) {
            tickAnticipation(player, bounceY);
            return;
        }
        applyBounce(player);
    }

    /**
     * Pre-band telegraph: while falling fast through the {@value #ANTICIPATION_BAND}
     * blocks above the flip, stream a few reverse-portal motes BELOW the player (the
     * field is beneath them) and chime once per fall so the flip lands expected, not
     * teleporty (W4-FEEL, IDEA-04 #6).
     */
    private static void tickAnticipation(ServerPlayer player, int bounceY) {
        UUID uuid = player.getUUID();
        if (player.getY() >= bounceY + ANTICIPATION_BAND) {
            ANTICIPATION_WARNED.remove(uuid); // fall over — the next dive re-arms the chime
            return;
        }
        if (player.getDeltaMovement().y >= ANTICIPATION_MIN_FALL_SPEED) {
            return;
        }
        player.serverLevel().sendParticles(ParticleTypes.REVERSE_PORTAL,
                player.getX(), player.getY() - 1.2D, player.getZ(),
                3, 0.25D, 0.1D, 0.25D, 0.01D);
        if (ANTICIPATION_WARNED.add(uuid)) {
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.5F, 0.6F);
        }
    }

    /** Post-bounce squash countdown: on zero the horizontal arc springs back open. */
    private static void tickSquashRelease(ServerPlayer player) {
        UUID uuid = player.getUUID();
        Integer left = SQUASH_RELEASE.get(uuid);
        if (left == null) {
            return;
        }
        if (left > 1) {
            SQUASH_RELEASE.put(uuid, left - 1);
            return;
        }
        SQUASH_RELEASE.remove(uuid);
        Vec3 motion = player.getDeltaMovement();
        player.setDeltaMovement(motion.x * SQUASH_RELEASE_BOOST, motion.y,
                motion.z * SQUASH_RELEASE_BOOST);
        player.hurtMarked = true;
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
        ANTICIPATION_WARNED.clear();
        SQUASH_RELEASE.clear();
    }

    public static void applyBounce(ServerPlayer player) {
        Vec3 motion = player.getDeltaMovement();
        // Squash: pinch the horizontal arc harder than the old flat 0.4 for SQUASH_TICKS,
        // then tickSquashRelease springs it back open (0.25 × 1.6 = the same 0.4 budget) —
        // the flip reads as compress-then-launch instead of an instant velocity swap.
        player.setDeltaMovement(motion.x * SQUASH_FACTOR, 2.8D, motion.z * SQUASH_FACTOR);
        player.fallDistance = 0.0F;
        player.hurtMarked = true;
        BOUNCED_UNTIL_TICK.put(player.getUUID(), player.server.getTickCount() + FALL_IMMUNITY_TICKS);
        SQUASH_RELEASE.put(player.getUUID(), SQUASH_TICKS);
        ANTICIPATION_WARNED.remove(player.getUUID()); // fall consumed — next dive re-chimes

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
