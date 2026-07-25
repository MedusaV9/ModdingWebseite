package dev.projecteclipse.eclipse.client.skills;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PlayerFxPhotonRows;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-SOCIAL (IDEAS-player #7): the prestige ribbon-orbit window controller — a
 * silk-thin violet ara ribbon (plus tier extras) orbiting the feet of a reborn player,
 * tier-scaling with rebirth count via {@link PlayerFxPhotonRows#REBIRTH_AURA_TIERS}
 * (three separate assets — 1/2/3 ribbons at phase offsets, tier 3 gold-tinted; ids
 * differ per tier so Photon's per-entity dedup never blocks an upgrade).
 *
 * <p><b>v1 scope is the LOCAL player only</b> (doc trigger note): other players' rebirth
 * counts are not synced today, so this reads best in F5. The keepsake baseline is
 * untouched either way — {@code RebirthAuraService}'s 3-point WITCH ring is spawned
 * server-side with vanilla particles and keeps running for EVERYONE (Mode.LAYER in
 * spirit: on Photon clients the ring reads as sparks off the ribbon; photon-less
 * clients keep exactly today's look).</p>
 *
 * <p><b>Gates</b>, re-checked every {@value #ENSURE_CADENCE_TICKS}t (WINDOWED-only law,
 * INTEGRATION.md §4): the rebirth sync arrived ({@code ClientRebirthState.synced}),
 * {@code count >= 1}, the {@code /skills aura on|off} keepsake toggle
 * ({@code auraEnabled} rides {@code S2CRebirthStatePayload} — the doc's "the aura-off
 * toggle must also gate the Photon leg"), and the bridge guard chain
 * ({@code PhotonBridge.available()} — {@code reducedFx} closes it, and this controller
 * then FORCE-kills the live ribbon rather than letting the executor outlive the
 * accessibility toggle). A tier upgrade (new rebirth) gracefully retires the old tier's
 * ribbon before ensuring the new id.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RebirthAuraFxClient {
    /** Eye-relative anchor (doc: {@code (0, -1.45, 0)} — eye to feet). */
    private static final Vec3 OFFSET = new Vec3(0.0D, -1.45D, 0.0D);
    /** Ensure cadence in ticks (the §0 ensure-law band: 20–40t). */
    private static final int ENSURE_CADENCE_TICKS = 20;

    private static int tickCounter;
    /** The tier asset currently ensured on the local player, or {@code null}. */
    @Nullable
    private static ResourceLocation liveTierFx;

    private RebirthAuraFxClient() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (++tickCounter % ENSURE_CADENCE_TICKS != 0) {
            return;
        }
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null) {
            liveTierFx = null; // level gone: the bridge sweep already killed the leg
            return;
        }
        boolean wantAura = ClientRebirthState.synced && ClientRebirthState.count >= 1
                && ClientRebirthState.auraEnabled;
        if (!wantAura || !PhotonBridge.available()) {
            if (liveTierFx != null) {
                // Graceful on the keepsake toggle; force when the guard chain closed
                // (reducedFx is an accessibility kill switch — no lingering fade).
                PhotonBridge.stopAttachedFx(liveTierFx, player, !PhotonBridge.available());
                liveTierFx = null;
            }
            return;
        }
        int tier = Math.min(ClientRebirthState.count, PlayerFxPhotonRows.REBIRTH_AURA_TIERS.length);
        ResourceLocation tierFx = PlayerFxPhotonRows.REBIRTH_AURA_TIERS[tier - 1];
        if (liveTierFx != null && !liveTierFx.equals(tierFx)) {
            PhotonBridge.stopAttachedFx(liveTierFx, player, false); // tier upgrade handoff
        }
        liveTierFx = PhotonBridge.ensureAttachedFx(tierFx, player,
                PhotonBridge.AUTO_ROTATE_NONE, OFFSET) ? tierFx : null;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        liveTierFx = null; // PhotonBridge.destroyAll tears the executor down
    }
}
