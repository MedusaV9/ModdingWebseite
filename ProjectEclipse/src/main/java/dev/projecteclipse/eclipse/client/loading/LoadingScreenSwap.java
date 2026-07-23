package dev.projecteclipse.eclipse.client.loading;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.gui.screens.LevelLoadingScreen;
import net.minecraft.client.gui.screens.ReceivingLevelScreen;
import net.minecraft.client.gui.screens.Screen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;
import net.neoforged.fml.common.EventBusSubscriber;

/**
 * Replaces the vanilla loading screens with {@link EclipseLoadingScreen} via
 * {@link ScreenEvent.Opening} — no mixins, the {@code TitleScreenSwap} precedent (P3 §3.11):
 * <ul>
 *   <li>{@link ReceivingLevelScreen} (world join + every dimension change, incl. the screens
 *       NeoForge's {@code DimensionTransitionScreenManager} creates through its default
 *       factory) → {@link EclipseLoadingScreen.Variant#RECEIVING},</li>
 *   <li>{@link LevelLoadingScreen} (SP spawn-chunk load) →
 *       {@link EclipseLoadingScreen.Variant#PREPARING}.</li>
 * </ul>
 *
 * <p>Guards: killswitch {@code customLoadingScreens=false} (read at every opening — takes
 * effect immediately, no restart); an opening {@link EclipseLoadingScreen} is left alone (no
 * recursion — it IS a {@code ReceivingLevelScreen} subclass, so the exact-class checks below
 * would skip it anyway); only the EXACT vanilla classes are swapped — if another mod already
 * substituted its own subclass or replacement, we do nothing (plan risk R-5). The replaced
 * vanilla instance is handed to {@link EclipseLoadingScreen} as its hidden close-logic
 * delegate.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LoadingScreenSwap {
    private LoadingScreenSwap() {}

    @SubscribeEvent
    static void onScreenOpening(ScreenEvent.Opening event) {
        if (!EclipseClientConfig.customLoadingScreens()) {
            return;
        }
        // Respect earlier handlers' replacements by checking the effective new screen.
        Screen opening = event.getNewScreen();
        if (opening == null || opening instanceof EclipseLoadingScreen) {
            return;
        }
        if (opening.getClass() == ReceivingLevelScreen.class) {
            event.setNewScreen(new EclipseLoadingScreen(opening, EclipseLoadingScreen.Variant.RECEIVING));
        } else if (opening.getClass() == LevelLoadingScreen.class) {
            event.setNewScreen(new EclipseLoadingScreen(opening, EclipseLoadingScreen.Variant.PREPARING));
        }
    }
}
