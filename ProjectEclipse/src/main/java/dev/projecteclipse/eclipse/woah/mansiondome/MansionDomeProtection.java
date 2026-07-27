package dev.projecteclipse.eclipse.woah.mansiondome;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.protection.DevMode;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.level.ExplosionEvent;

/**
 * WOAH-01 §3.4 — no-build shield over the mansion while the dome stands (the
 * {@code protection.LandmarkProtection} pattern, deliberately a sibling file: that class
 * does not know the mansion, so there are never double-cancels). While
 * {@link MansionDomeState#shieldUp()} (ACTIVE or COLLAPSING):
 *
 * <ul>
 *   <li>break AND place are cancelled in the cylinder {@code r = shellRadius} around the
 *       centre, Y band {@code groundY − 8 … roofY + 24} (§8 decision: BOTH are locked —
 *       place-only freedom would let block-pots hollow out the protection; the roof is
 *       reachable through the mansion's own stairs);</li>
 *   <li>explosions lose every affected block inside the cylinder;</li>
 *   <li>devmode players are exempt (PROGFIX #5 — ops obey until {@code /devmode}).</li>
 * </ul>
 *
 * <p>From DESTROYED on, the mansion belongs to the players — zero checks (the state read
 * is one SavedData map lookup; the cylinder math only runs while the shield is up).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MansionDomeProtection {
    /** Extra protected depth below the plateau seat (undermining guard). */
    private static final int BELOW_GROUND_PAD = 8;
    /** Extra protected height above the roof (no towering over the shield to pot blocks). */
    private static final int ABOVE_ROOF_PAD = 24;

    private MansionDomeProtection() {}

    /** Whether the shield currently locks this position. */
    public static boolean isProtected(ServerLevel level, BlockPos pos) {
        MansionDomeState state = MansionDomeState.get(level.getServer());
        if (!state.shieldUp() || level.dimension() != state.dimension()) {
            return false;
        }
        if (pos.getY() < state.groundY() - BELOW_GROUND_PAD
                || pos.getY() > state.roofY() + ABOVE_ROOF_PAD) {
            return false;
        }
        long dx = pos.getX() - state.centre().getX();
        long dz = pos.getZ() - state.centre().getZ();
        long radius = (long) Math.ceil(state.shellRadius());
        return dx * dx + dz * dz <= radius * radius;
    }

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !isProtected(level, event.getPos())) {
            return;
        }
        Player player = event.getPlayer();
        if (isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        hint(player);
    }

    @SubscribeEvent
    public static void onBlockPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !isProtected(level, event.getPos())) {
            return;
        }
        Entity entity = event.getEntity();
        if (entity instanceof Player player && isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof Player player) {
            hint(player);
        }
    }

    /** Explosions may still hurt entities, but never reshape the shielded mansion. */
    @SubscribeEvent
    public static void onExplosionDetonate(ExplosionEvent.Detonate event) {
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        MansionDomeState state = MansionDomeState.get(level.getServer());
        if (!state.shieldUp() || level.dimension() != state.dimension()) {
            return; // Cheap early-out: no per-block scan while no shield stands.
        }
        event.getAffectedBlocks().removeIf(pos -> isProtected(level, pos));
    }

    /** PROGFIX #5: only devmode players bypass — ops obey the shield by default. */
    private static boolean isExempt(@Nullable Player player) {
        return DevMode.isExempt(player);
    }

    /** Polite deny: action bar + a muffled chime, never chat (silent-event law). */
    private static void hint(@Nullable Player player) {
        if (player instanceof ServerPlayer serverPlayer) {
            serverPlayer.displayClientMessage(
                    ServerLang.tr(serverPlayer, "message.eclipse.dome_protected"), true);
            serverPlayer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.BLOCKS, 0.7F, 0.7F);
        }
    }
}
