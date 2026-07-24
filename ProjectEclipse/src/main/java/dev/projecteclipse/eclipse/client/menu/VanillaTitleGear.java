package dev.projecteclipse.eclipse.client.menu;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * The permanent vanilla-title settings entry ({@code docs/plans_v3/P3_ui.md} §3.4, R12 —
 * replaces the title half of the interim {@code SettingsReachability} B1 hotfix): while
 * {@code customMenu=false} the custom Eclipse title screen (with its own gear) is not
 * swapped in, so this hook puts a 20x20 gear bottom-right on the VANILLA title screen,
 * opening {@link EclipseSettingsScreen}. Settings therefore stay reachable with
 * customMenu on AND off — and re-enabling it from that very screen returns through a
 * vanilla title that {@link TitleScreenSwap} immediately swaps back to the custom one.
 *
 * <p>Exact-class guard (same rule as {@link TitleScreenSwap}): modded title screens that
 * subclass {@link TitleScreen} keep their own layout and are left alone. The dedupe guard
 * (any {@code gui.eclipse.*}-labelled widget already present) is kept from the interim
 * fix so mixed merge windows can never double the gear.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class VanillaTitleGear {
    private static final ResourceLocation GEAR = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/title/gear.png");
    private static final int GEAR_SIZE = 20;
    private static final int GEAR_TEXTURE_SIZE = 48;

    private VanillaTitleGear() {}

    @SubscribeEvent
    static void onScreenInit(ScreenEvent.Init.Post event) {
        Screen screen = event.getScreen();
        if (screen.getClass() != TitleScreen.class || EclipseClientConfig.customMenu()) {
            return;
        }
        if (hasEclipseWidget(event)) {
            return; // another Eclipse injector already provided the entry (dedupe guard)
        }
        // Bottom-right, lifted above the copyright line (height-10) and NeoForge brand lines.
        int x = screen.width - GEAR_SIZE - 4;
        int y = screen.height - GEAR_SIZE - 24;
        event.addListener(Button.builder(EclipseLang.tr("gui.eclipse.settings.title"),
                        button -> Minecraft.getInstance().setScreen(new EclipseSettingsScreen(screen)))
                .bounds(x, y, GEAR_SIZE, GEAR_SIZE)
                .tooltip(Tooltip.create(EclipseLang.tr("gui.eclipse.settings.open")))
                .build(builder -> new EclipseMenuButton(builder, GEAR, GEAR_TEXTURE_SIZE, GEAR_TEXTURE_SIZE)));
    }

    /**
     * True when any widget already carries a {@code gui.eclipse.*} label or is an Eclipse
     * button (labels resolved through {@code EclipseLang.tr} are literals on the override
     * path, so the key check alone would no longer see them — M-1).
     */
    private static boolean hasEclipseWidget(ScreenEvent.Init.Post event) {
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof EclipseMenuButton) {
                return true;
            }
            if (listener instanceof AbstractWidget widget
                    && widget.getMessage().getContents() instanceof TranslatableContents contents
                    && contents.getKey().startsWith("gui.eclipse.")) {
                return true;
            }
        }
        return false;
    }
}
