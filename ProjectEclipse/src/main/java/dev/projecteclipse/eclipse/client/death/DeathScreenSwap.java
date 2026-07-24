package dev.projecteclipse.eclipse.client.death;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.gui.screens.DeathScreen;
import net.minecraft.client.gui.screens.Screen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Replaces the vanilla death screen with {@link EclipseDeathScreen} via
 * {@link ScreenEvent.Opening} — the {@code TitleScreenSwap} pattern (P3 §3.7). Guards:
 * only the exact vanilla {@link DeathScreen} class is swapped (another mod's subclass or
 * replacement is respected), an opening {@link EclipseDeathScreen} is left alone (no
 * recursion), and the {@code customDeathScreen} config is read at every opening — saving
 * {@code false} restores the full vanilla death flow immediately, no restart needed
 * (kill-switch, §3.7).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DeathScreenSwap {
    private DeathScreenSwap() {}

    @SubscribeEvent
    static void onScreenOpening(ScreenEvent.Opening event) {
        if (!EclipseClientConfig.customDeathScreen()) {
            return;
        }
        Screen opening = event.getNewScreen();
        if (opening instanceof EclipseDeathScreen) {
            return;
        }
        if (opening != null && opening.getClass() == DeathScreen.class) {
            event.setNewScreen(new EclipseDeathScreen());
        }
    }
}
