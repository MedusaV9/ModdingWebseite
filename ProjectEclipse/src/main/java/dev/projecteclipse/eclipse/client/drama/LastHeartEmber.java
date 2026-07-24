package dev.projecteclipse.eclipse.client.drama;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Ember of the last heart (FIX-5, IDEAS-A #5): OTHER players at exactly 1 permanent heart
 * passively emit a faint drifting wisp trail — no announcement, no HUD, teammates just
 * <i>notice</i> someone burning low, and because names are hidden, protecting "the ember"
 * becomes a wordless ritual.
 *
 * <p><b>How lives are read without a new packet:</b> {@code S2CLivesPayload} only syncs a
 * player's own count, but {@code HeartsService.apply} projects hearts onto the MAX_HEALTH
 * attribute ({@code hearts × 2 − 20}), and living-entity attribute updates are vanilla-synced
 * to every tracking client. A remote player whose synced max health is exactly 2.0 (one
 * heart) is therefore "the ember"; 0-heart ghosts clamp to max health 1.0 and are excluded
 * by the same band check.</p>
 *
 * <p><b>FX discipline:</b> {@link QuasarSpawner#ensureAttached} with the existing
 * {@code eclipse:door_glow_motes} loop (the subtlest idle-mote emitter in the repo — rate
 * 6 / count 1 / size 0.09) on the {@link FxBudget.Channel#AMBIENT} channel: budget-refused
 * spawns retry next scan, tier 0 ({@code reducedFx} + post FX off) disables the channel
 * outright, and entity-attached emitters die with their entity, so the only bookkeeping
 * needed is detaching when a player heals, ghosts out or leaves range.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LastHeartEmber {
    /** The subtlest looping mote emitter shipped (vs. the brighter one-shot supply_spark). */
    private static final ResourceLocation EMBER_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "door_glow_motes");

    /** Trail range around the camera (blocks) — roughly the readable-silhouette band. */
    private static final double RANGE = 48.0D;
    private static final double RANGE_SQ = RANGE * RANGE;
    /** Eligibility scan cadence; keeping a live loop between scans costs nothing. */
    private static final int SCAN_INTERVAL_TICKS = 10;
    /** One synced heart = max health 2.0; the band excludes ghosts (clamped to 1.0). */
    private static final float ONE_HEART_MIN_HEALTH = 1.5F;
    private static final float ONE_HEART_MAX_HEALTH = 2.5F;

    /** Entity ids currently wearing an ember (for detach-on-heal bookkeeping). */
    private static final Set<Integer> EMBERS = new HashSet<>();

    private static int scanCountdown;

    private LastHeartEmber() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            EMBERS.clear(); // QuasarSpawner clears the attached emitters on logout itself
            return;
        }
        if (minecraft.isPaused() || --scanCountdown > 0) {
            return;
        }
        scanCountdown = SCAN_INTERVAL_TICKS;

        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        Set<Integer> seen = new HashSet<>();
        for (AbstractClientPlayer player : level.players()) {
            seen.add(player.getId());
            if (isEmber(minecraft, camera, player)) {
                // AMBIENT charge applies only on creation; refusals simply retry next scan.
                if (QuasarSpawner.ensureAttached(EMBER_EMITTER, player, FxBudget.Channel.AMBIENT)) {
                    EMBERS.add(player.getId());
                }
            } else if (EMBERS.remove(player.getId())) {
                QuasarSpawner.removeAttached(EMBER_EMITTER, player);
            }
        }
        // Players who despawned client-side: their attached emitters died with the entity —
        // just drop the stale ids so a recycled entity id can never skip a detach.
        Iterator<Integer> it = EMBERS.iterator();
        while (it.hasNext()) {
            if (!seen.contains(it.next())) {
                it.remove();
            }
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        EMBERS.clear();
    }

    /** Other players only, alive, visible, in range, and at exactly one synced heart. */
    private static boolean isEmber(Minecraft minecraft, Vec3 camera, AbstractClientPlayer player) {
        if (player == minecraft.player || !player.isAlive()
                || player.isSpectator() || player.isInvisible()) {
            return false;
        }
        if (player.position().distanceToSqr(camera) > RANGE_SQ) {
            return false;
        }
        float maxHealth = player.getMaxHealth();
        return maxHealth > ONE_HEART_MIN_HEALTH && maxHealth < ONE_HEART_MAX_HEALTH;
    }
}
