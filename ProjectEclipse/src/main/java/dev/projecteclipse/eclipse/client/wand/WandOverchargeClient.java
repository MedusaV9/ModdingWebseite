package dev.projecteclipse.eclipse.client.wand;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandConfig;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * FX-Wave-13 N5 — <b>Wand-Overcharge-Bögen</b>: while the Veilladung of the held wand is
 * FULL, small lightning arcs whip around the casting hand and smear backwards when the
 * player runs. It is the "you may cast anything, right now" reward signal (census §6 row
 * N5) — a permanent-presence effect, so the assets are deliberately tiny.
 *
 * <p><b>Assets</b> (authored by {@code tools/photon/wand_overcharge_fx.py}, one per path so
 * the arc colour IS the path identity — the {@code WandAuraClient} idle-aura convention):
 * {@code eclipse:wand_overcharge_riss} / {@code _glut} / {@code _stern}. Each is a
 * LOCAL-space asset with a negative {@code inheritVelocity} multiply, i.e. the bolts lag the
 * caster's travel and whip back onto the hand when they stop.</p>
 *
 * <p><b>The window</b> (INTEGRATION.md §4 WINDOWED-loop law, entity flavour):</p>
 * <ul>
 *   <li><b>Open</b>: the wand is at {@code charge == chargeMax} (the mandate's 100 %).</li>
 *   <li><b>Close</b>: charge drops below {@value #OFF_FRACTION} of the max. The band exists
 *       because held regen tops the wand up continuously — without it a wand sitting at the
 *       cap would strobe the arcs off and on with every regen tick.</li>
 *   <li><b>Per-holder gate</b>: a wand in either hand (main hand wins — the
 *       {@code WandPowers.findHeldWand} order), a path chosen, and the holder IS the
 *       soulbound owner (a stolen wand shows nothing — it will not cast for the thief
 *       either).</li>
 *   <li><b>Hard gates</b>: {@link PhotonBridge#available()} (photon present + {@code photonFx}
 *       + NOT {@code reducedFx} — a {@code reducedFx} flip force-kills the arcs on the next
 *       tick) and the {@code wandAuras} client toggle, which already owns the wand's other
 *       hand FX.</li>
 * </ul>
 *
 * <p><b>Why the LOCAL player only.</b> Charge is a synced {@code WAND_CHARGE} component, so
 * a bystander can read any holder's raw charge — but the MAX is per-player (wand-tree regen
 * perks fold into it) and only ever synced for oneself through
 * {@link ClientWandProgress#chargeMax}. Judging a remote player's wand "full" against the
 * local max would light arcs on a half-charged wand; there is no per-stack max component to
 * fix that without new wire. Since N5 is defined as the WIELDER's reward signal, the window
 * is simply restricted to {@code Minecraft.player}, which also pins the budget at exactly
 * one executor of ≤ 28 cull-boxed particles.</p>
 *
 * <p><b>Anchor — and the trap underneath it.</b> Photon's {@code EntityEffectExecutor}
 * places the effect at {@code entity.getEyePosition() + executor.offset} with the offset in
 * WORLD AXES, and {@link PhotonBridge#AUTO_ROTATE_LOOK} rotates only the effect ROOT — it
 * does NOT rotate the spawn offset (jar-verified in
 * {@code EntityEffectExecutor.updateFXObjectFrame}; the landed
 * {@code WandFx2PhotonRows} muzzle leg says the same thing when it builds its hand point as
 * "a world-axis offset off the eye"). A constant spawn offset is therefore a fixed COMPASS
 * direction: it sits at the hand facing one way and swings to the wrong side of the body on
 * a turn — and in first person it lands BEHIND the camera, where nothing renders at all.
 * A persistent loop cannot re-spawn on every yaw change, so this row passes NO offset and
 * the hand point is baked into the emitters' local positions
 * ({@code wand_overcharge_fx.HAND_LOCAL}); Photon's own root rotation then carries it
 * through every turn, in every camera mode, for free.</p>
 *
 * <p><b>Fallback:</b> none by design — pure additive garnish. Photon-less or
 * {@code reducedFx} clients keep the charge pips as the full-charge signal (the HUD is the
 * functional readout; this is the flourish).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WandOverchargeClient {
    private static final ResourceLocation OVERCHARGE_RISS = fx("wand_overcharge_riss");
    private static final ResourceLocation OVERCHARGE_GLUT = fx("wand_overcharge_glut");
    private static final ResourceLocation OVERCHARGE_STERN = fx("wand_overcharge_stern");

    /** Keepalive cadence in ticks (a live loop makes the re-ensure a silent no-op). */
    private static final int ENSURE_CADENCE = 20;
    /** The window closes below this share of the max charge (hysteresis; ON is at 100 %). */
    private static final float OFF_FRACTION = 0.95F;

    /** The live loop's asset, or {@code null} while the window is closed. */
    @Nullable
    private static ResourceLocation liveFx;
    /** Which player the live loop is attached to (a respawn hands us a NEW LocalPlayer). */
    @Nullable
    private static UUID liveHolder;
    /** Hysteresis latch: true while the charge counts as full. */
    private static boolean overcharged;
    private static int cadence;

    private WandOverchargeClient() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (minecraft.level == null || player == null) {
            forget(); // executors died with the level (bridge sweep / logout reset)
            return;
        }
        if (!PhotonBridge.available() || !EclipseClientConfig.wandAuras()) {
            // Global gate slammed (reducedFx flip, photonFx off, toggle off): kill the arcs
            // NOW — reducedFx must not have to wait out a graceful fade.
            stop(player, true);
            overcharged = false;
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        // A respawn/dimension change replaces the LocalPlayer; the old executor went with
        // it, so drop the bookkeeping instead of stopping a loop on a dead entity.
        if (liveHolder != null && !liveHolder.equals(player.getUUID())) {
            forget();
        }

        ResourceLocation want = overchargeFx(player);
        if (want == null) {
            stop(player, false); // graceful: the last bolts finish their whip
            return;
        }
        if (liveFx != null && !liveFx.equals(want)) {
            // The path locked in (or changed): the asset IS the path colour, so the old
            // loop has to retire before the new one starts.
            PhotonBridge.stopAttachedFx(liveFx, player, false);
            forget();
        }
        if (liveFx == null) {
            liveFx = want;
            liveHolder = player.getUUID();
            cadence = 0;
            PhotonBridge.ensureAttachedFx(want, player, PhotonBridge.AUTO_ROTATE_LOOK, null);
        } else if (++cadence >= ENSURE_CADENCE) {
            cadence = 0;
            // Keepalive: a no-op while the runtime lives, self-healing after an untrack or
            // a refused spawn (executor budget) on the opening tick.
            PhotonBridge.ensureAttachedFx(want, player, PhotonBridge.AUTO_ROTATE_LOOK, null);
        }
    }

    /**
     * The overcharge asset for the local player's held wand, or {@code null} when the
     * window is shut: no owned pathed wand in hand, or the charge is not (still) full.
     */
    @Nullable
    private static ResourceLocation overchargeFx(LocalPlayer player) {
        ItemStack stack = heldWand(player);
        if (stack == null) {
            overcharged = false; // wand put away — the latch must not survive it
            return null;
        }
        UUID owner = stack.get(WandItems.WAND_OWNER.get());
        if (owner == null || !owner.equals(player.getUUID())) {
            overcharged = false;
            return null;
        }
        if (!chargeFull(stack)) {
            return null;
        }
        return switch (WandSoulbind.pathOf(stack)) {
            case RISS -> OVERCHARGE_RISS;
            case GLUT -> OVERCHARGE_GLUT;
            case STERN -> OVERCHARGE_STERN;
            default -> null; // pathless wand: no identity colour to arc in
        };
    }

    /**
     * The hysteresis latch itself: opens at exactly 100 % of the max, closes under
     * {@value #OFF_FRACTION}. The max is the WANDFIX-4 ladder — the synced per-player value
     * (wand-branch perks folded in, REAL on dedicated servers) with the local config as the
     * pre-sync fallback, exactly like {@code WandChargeHud} reads it.
     */
    private static boolean chargeFull(ItemStack stack) {
        int max = Math.max(1, ClientWandProgress.synced
                ? ClientWandProgress.chargeMax : WandConfig.get().charge().max());
        int charge = Mth.clamp(stack.getOrDefault(WandItems.WAND_CHARGE.get(), 0), 0, max);
        float fraction = charge / (float) max;
        overcharged = overcharged ? fraction >= OFF_FRACTION : fraction >= 1.0F;
        return overcharged;
    }

    /** The wand in either hand (main hand wins — mirrors {@code WandPowers.findHeldWand}). */
    @Nullable
    private static ItemStack heldWand(LocalPlayer player) {
        ItemStack main = player.getMainHandItem();
        if (main.getItem() instanceof EclipseWandItem) {
            return main;
        }
        ItemStack off = player.getOffhandItem();
        return off.getItem() instanceof EclipseWandItem ? off : null;
    }

    /** Stops the live loop ({@code force=true} = instant kill, the reducedFx path). */
    private static void stop(LocalPlayer player, boolean force) {
        if (liveFx != null) {
            PhotonBridge.stopAttachedFx(liveFx, player, force);
        }
        forget();
    }

    /** Drops the bookkeeping without touching Photon (the executor is already gone). */
    private static void forget() {
        liveFx = null;
        liveHolder = null;
        cadence = 0;
    }

    /** Disconnect reset — the bridge force-destroys the executors; drop the bookkeeping. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        forget();
        overcharged = false;
    }

    /** Dev/QA introspection: the asset currently arcing, or {@code null} while idle. */
    @Nullable
    public static ResourceLocation liveOvercharge() {
        return liveFx;
    }

    /** Dev/QA introspection: whether the hysteresis latch currently reads "full". */
    public static boolean isOvercharged() {
        return overcharged;
    }
}
