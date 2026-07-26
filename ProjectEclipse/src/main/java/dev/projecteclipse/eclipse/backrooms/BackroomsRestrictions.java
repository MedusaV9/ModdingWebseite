package dev.projecteclipse.eclipse.backrooms;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.protection.DevMode;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.level.BlockEvent;

/**
 * Backrooms interaction lockdown (user decree): inside {@code eclipse:backrooms} players
 * can neither BREAK nor PLACE blocks, and wand casting is refused — the maze is a
 * no-clip space, not a build site. The {@code SanctumProtection} event pattern:
 *
 * <ul>
 *   <li>{@link BlockEvent.BreakEvent} / {@link BlockEvent.EntityPlaceEvent} cancels for
 *       every non-exempt actor in the dimension (the event-driven flicker and maze stamp
 *       write via {@code Level.setBlock} directly, so they are unaffected);</li>
 *   <li>{@link #blocksCast} is the wand guard consulted by the
 *       {@code network.wand.WandPayloads} C2S entry point BEFORE dispatching into
 *       {@code WandPowers} — casting dies at the network boundary, the owned wand
 *       package stays untouched;</li>
 *   <li>{@link DevMode#isExempt} is the single bypass (PROGFIX #5 law — ops and creative
 *       players obey restrictions unless {@code /devmode} is toggled on);</li>
 *   <li>feedback is a muffled chime ONLY — the backrooms send nothing to chat.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BackroomsRestrictions {

    private BackroomsRestrictions() {}

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !BackroomsDimension.isBackrooms(level.dimension())) {
            return;
        }
        Player player = event.getPlayer();
        if (DevMode.isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        hint(player);
    }

    @SubscribeEvent
    public static void onBlockPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !BackroomsDimension.isBackrooms(level.dimension())) {
            return;
        }
        Entity entity = event.getEntity();
        if (entity instanceof Player player && DevMode.isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof Player player) {
            hint(player);
        }
    }

    /**
     * Wand-cast guard for the backrooms, called by {@code WandPayloads.handleCast} before
     * it dispatches into {@code WandPowers}. Returns {@code true} when the cast must be
     * swallowed (player inside the backrooms and not devmode-exempt) — the refusal chime
     * fires here so the entry point stays a one-line check.
     */
    public static boolean blocksCast(ServerPlayer player) {
        if (!BackroomsDimension.isInBackrooms(player) || DevMode.isExempt(player)) {
            return false;
        }
        hint(player);
        return true;
    }

    /** Sound-only refusal (never chat/actionbar — the user decree silences these events). */
    private static void hint(@Nullable Player player) {
        if (player instanceof ServerPlayer serverPlayer) {
            serverPlayer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.BLOCKS, 0.7F, 0.5F);
        }
    }
}
