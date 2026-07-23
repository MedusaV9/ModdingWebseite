package dev.projecteclipse.eclipse.cutscene.client;

import org.lwjgl.glfw.GLFW;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.player.Input;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.InputEvent;
import net.neoforged.neoforge.client.event.MovementInputUpdateEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Client-side input swallow while a cutscene flight is active (comfort only — the
 * server-side {@code FreezeService} is the authority):
 * <ul>
 *   <li>{@link MovementInputUpdateEvent} — zero all movement impulses/jump/sneak;</li>
 *   <li>{@link InputEvent.MouseButton.Pre} + {@link InputEvent.InteractionKeyMappingTriggered}
 *       — cancel clicks and attack/use/pick triggers; mouse buttons pass through while ANY
 *       screen is open (the death screen's Respawn button must stay clickable);</li>
 *   <li>ESC/Space — converted into a {@code SKIP_REQUEST} (the server validates
 *       {@code allowSkip}), but only from focused, screen-less gameplay: space typed into
 *       chat and the focus-loss auto-pause are NOT skips. The pause screen a focused ESC
 *       would open is suppressed for the duration; other screens (chat, death screen) stay
 *       allowed.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CutsceneInput {
    private CutsceneInput() {}

    @SubscribeEvent
    static void onMovementInputUpdate(MovementInputUpdateEvent event) {
        if (!CameraDirector.isActive()) {
            return;
        }
        Input input = event.getInput();
        input.forwardImpulse = 0.0F;
        input.leftImpulse = 0.0F;
        input.up = false;
        input.down = false;
        input.left = false;
        input.right = false;
        input.jumping = false;
        input.shiftKeyDown = false;
    }

    @SubscribeEvent
    static void onMouseButton(InputEvent.MouseButton.Pre event) {
        // Only swallow gameplay clicks: with a screen open the click belongs to the
        // screen — cancelling would block e.g. the death screen's Respawn button.
        if (CameraDirector.isActive() && Minecraft.getInstance().screen == null) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    static void onInteractionKeyMapping(InputEvent.InteractionKeyMappingTriggered event) {
        if (CameraDirector.isActive()) {
            event.setSwingHand(false);
            event.setCanceled(true);
        }
    }

    /**
     * Space presses become skip requests (movement is already zeroed above). Key events
     * also fire with a screen open — space typed into chat must not skip the scene.
     */
    @SubscribeEvent
    static void onKey(InputEvent.Key event) {
        if (CameraDirector.isActive() && event.getAction() == GLFW.GLFW_PRESS
                && event.getKey() == GLFW.GLFW_KEY_SPACE
                && isFocusedGameplay()) {
            CameraDirector.requestSkip();
        }
    }

    /**
     * ESC's pause screen is suppressed mid-flight and converted into a skip request (ESC is
     * intercepted here rather than in {@link #onKey} so it fires exactly once per press).
     * Only a focused, screen-less open counts as that ESC: the focus-loss auto-pause
     * ({@code GameRenderer} pauses while {@code !isWindowActive()}) opens the very same
     * PauseScreen, and alt-tabbing must not silently skip the scene — unfocused opens fall
     * through to the regular pause.
     */
    @SubscribeEvent
    static void onScreenOpening(ScreenEvent.Opening event) {
        if (CameraDirector.isActive() && event.getNewScreen() instanceof PauseScreen
                && isFocusedGameplay()) {
            event.setCanceled(true);
            CameraDirector.requestSkip();
        }
    }

    /** Focused, screen-less gameplay — the only state where a skip press is deliberate. */
    private static boolean isFocusedGameplay() {
        Minecraft minecraft = Minecraft.getInstance();
        return minecraft.screen == null && minecraft.isWindowActive();
    }
}
