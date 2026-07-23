package dev.projecteclipse.eclipse.client;

import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.hud.AnnouncementOverlay;
import dev.projecteclipse.eclipse.client.hud.DayTimerLayer;
import dev.projecteclipse.eclipse.client.hud.MarkVignetteOverlay;
import dev.projecteclipse.eclipse.client.hud.SidebarPanel;
import dev.projecteclipse.eclipse.cutscene.client.CaptionRenderer;
import dev.projecteclipse.eclipse.cutscene.client.LetterboxLayer;
import dev.projecteclipse.eclipse.hearts.client.HeartBurstOverlay;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Registers Eclipse GUI layers on the client mod bus. This file also owns the cutscene
 * HUD-suppression whitelist (P2 §6.2): sibling planners must NOT add their own whitelist
 * edits elsewhere — new overlays that have to stay visible during {@code hideHud} cutscenes
 * are added to the single {@code setHudWhitelist} call below.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseGuiLayers {
    private EclipseGuiLayers() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAbove(VanillaGuiLayers.PLAYER_HEALTH,
                HeartBurstOverlay.LAYER_ID, HeartBurstOverlay::render);
        // W8 sidebar panel: renders from ClientStateCache, suppresses the vanilla sidebar
        // while on (see SidebarPanel). Deliberately NOT whitelisted below — cutscene HUD
        // suppression is supposed to hide it.
        event.registerAbove(VanillaGuiLayers.SCOREBOARD_SIDEBAR,
                SidebarPanel.LAYER_ID, SidebarPanel::render);
        // W8 announcements: typewriter line + client-local bossbar sweep. Above the boss
        // overlay so the sweep stacks with real bars. Whitelisted below (P2 §1.7 fix).
        event.registerAbove(VanillaGuiLayers.BOSS_OVERLAY,
                AnnouncementOverlay.LAYER_ID, AnnouncementOverlay::render);
        // P3-W6 day timer: top-center countdown under the bossbar stack. MUST render below
        // (= before) the announcement layer: the timer reserves its row via
        // BossbarSkin.reserveOverlayRow so the announcement sweep stacks under it.
        // Deliberately NOT letterbox-whitelisted (§3.6 — cutscene HUD suppression hides it).
        event.registerBelow(AnnouncementOverlay.LAYER_ID,
                DayTimerLayer.LAYER_ID, DayTimerLayer::render);
        // W12 Lantern Gaze mark: purple hunt vignette under the crosshair-level HUD,
        // deliberately NOT letterbox-whitelisted (cutscenes suppress it).
        event.registerBelow(VanillaGuiLayers.CROSSHAIR,
                MarkVignetteOverlay.LAYER_ID, MarkVignetteOverlay::render);
        event.registerAboveAll(WaveOverlay.LAYER_ID, WaveOverlay::render);
        event.registerAboveAll(LetterboxLayer.LAYER_ID, LetterboxLayer::render);
        // P2-W2 cinematic captions + screen fades: registered AFTER the letterbox so text
        // draws on top of the bars (subtitles rest just above the bottom bar).
        event.registerAboveAll(CaptionRenderer.LAYER_ID, CaptionRenderer::render);
        // Cutscene HUD suppression must never cancel these: the letterbox itself, the
        // mid-death heart burst, the v1 wave overlay (renders through the intro flight),
        // the announcement overlay (P2 §1.7 — cutscene subtitles were delivered as
        // announcements and suppression cancelled the layer, so the text never drew) and
        // the P2-W2 caption layer (cinematic captions immune by construction).
        LetterboxLayer.setHudWhitelist(Set.of(
                LetterboxLayer.LAYER_ID, HeartBurstOverlay.LAYER_ID, WaveOverlay.LAYER_ID,
                AnnouncementOverlay.LAYER_ID, CaptionRenderer.LAYER_ID));
    }
}
