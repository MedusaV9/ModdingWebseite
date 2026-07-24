package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * FFIX-A / POLISH C-1..C-3 — THE CENTER-STAGE TOKEN: a tiny mutual-exclusion arbiter for
 * the hero moments that all anchor on the screen's upper-center band
 * ({@code guiHeight/3} / {@code h/4}): {@code LevelUpOverlay},
 * {@code RewardMaterializeOverlay}, the day-number card inside
 * {@code AnnouncementOverlay}, {@code BossIntroOverlay} and the {@code AwardsOverlay}
 * roulette veil. Each tick driver consults {@link #tryClaim} at its queue-start seam
 * (exactly like the existing {@code CameraDirector.isHudSuppressed()} deferrals) and
 * keeps its pending entry queued while another moment owns the stage — simultaneous hero
 * moments now serialize instead of stacking.
 *
 * <p><b>Contract:</b> {@link #tryClaim} succeeds when the stage is free OR the same id
 * already owns it (re-claiming renews the lease). Owners {@link #release} explicitly when
 * their animation ends; the tick-counted lease is only a failsafe so a crashed/skipped
 * owner can never deadlock the stage. Client tick thread only; state clears on level
 * unload. Deliberately NOT consulted by cutscene machinery — the letterbox suppression
 * layer stays the outer gate, this token only arbitrates between the overlays
 * themselves.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CenterStageArbiter {
    /** Failsafe cap: no lease may outlive this many ticks whatever a claimant passes. */
    private static final int MAX_LEASE_TICKS = 1600;

    // Client tick thread only.
    private static String owner;
    private static int leaseTicks;

    private CenterStageArbiter() {}

    /**
     * Claims the center stage for {@code ticks} (renewing when {@code id} already owns
     * it). Returns {@code false} while another id holds the stage — the caller should
     * keep its moment queued and retry next tick.
     */
    public static boolean tryClaim(String id, int ticks) {
        if (owner != null && !owner.equals(id)) {
            return false;
        }
        owner = id;
        leaseTicks = Math.min(Math.max(1, ticks), MAX_LEASE_TICKS);
        return true;
    }

    /** Releases the stage if {@code id} owns it (a stranger's release is a no-op). */
    public static void release(String id) {
        if (owner != null && owner.equals(id)) {
            owner = null;
            leaseTicks = 0;
        }
    }

    /** Whether no hero moment currently owns the center stage. */
    public static boolean isFree() {
        return owner == null;
    }

    /** Lease countdown failsafe; explicit {@link #release} is the normal path. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            owner = null;
            leaseTicks = 0;
            return;
        }
        if (minecraft.isPaused()) {
            return; // every claimant freezes while paused — the lease must freeze with them
        }
        if (owner != null && --leaseTicks <= 0) {
            owner = null;
        }
    }
}
