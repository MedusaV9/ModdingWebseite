package dev.projecteclipse.eclipse.client.skills;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.screens.inventory.InventoryScreen;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * The inventory entry point to the skill tree (WB-SKILLS): a small 16x16 "✦" button
 * injected into the survival {@link InventoryScreen} via {@link ScreenEvent.Init.Post}
 * (game bus, no mixins — the {@code PauseMenuHook} pattern), sitting directly above the
 * pinned slot-17 artifact ({@code ArtifactSlotLock.ARTIFACT_SLOT}, top-row rightmost:
 * container-relative x 152, y 84) in the empty strip below the crafting-result slot.
 *
 * <p><b>Recipe-book safe:</b> toggling the recipe book re-centers the container
 * ({@code leftPos} changes WITHOUT a screen re-init), so the widget re-anchors itself from
 * {@code getGuiLeft()/getGuiTop()} at the start of every rendered frame instead of
 * trusting its init-time position (at most one frame of lag, unclickable during it —
 * harmless). Creative inventory deliberately excluded (different class, scrolled grid).
 * Dedupe guard: skipped when any {@code gui.eclipse.skills.*}-labelled widget is already
 * present, so a mixed merge window can't double-inject.</p>
 *
 * <p>Click closes the container first ({@code closeContainer()} returns any carried stack
 * server-side and clears the screen), then opens {@link SkillTreeScreen} — the tree
 * renders instantly from {@link ClientStateCache}, no server round-trip needed.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class InventorySkillButton {
    /** Container-relative anchor: same column as the slot-17 artifact, above its frame. */
    private static final int REL_X = 152;
    private static final int REL_Y = 62;
    private static final int SIZE = 16;

    private InventorySkillButton() {}

    @SubscribeEvent
    static void onScreenInit(ScreenEvent.Init.Post event) {
        if (!(event.getScreen() instanceof InventoryScreen screen)) {
            return;
        }
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof AbstractWidget widget
                    && widget.getMessage().getContents() instanceof TranslatableContents contents
                    && contents.getKey().startsWith("gui.eclipse.skills.")) {
                return; // dedupe guard — another Eclipse injector already added the entry
            }
        }
        event.addListener(new Widget(screen));
    }

    /** The 16x16 glyph button; face is theme-flat, hover ring comes from the base class. */
    @OnlyIn(Dist.CLIENT)
    private static final class Widget extends EclipseWidget {
        private final InventoryScreen screen;

        Widget(InventoryScreen screen) {
            super(screen.getGuiLeft() + REL_X, screen.getGuiTop() + REL_Y, SIZE, SIZE,
                    EclipseLang.tr("gui.eclipse.skills.open"));
            this.screen = screen;
            setTooltip(Tooltip.create(EclipseLang.tr("gui.eclipse.skills.open_tip",
                    SkillKeybind.OPEN_SKILLS.getTranslatedKeyMessage())));
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            Minecraft minecraft = Minecraft.getInstance();
            if (minecraft.player != null) {
                minecraft.player.closeContainer();
                minecraft.setScreen(new SkillTreeScreen());
            }
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            // Recipe-book reposition: re-anchor from the live container origin every frame.
            setX(screen.getGuiLeft() + REL_X);
            setY(screen.getGuiTop() + REL_Y);

            guiGraphics.fill(getX(), getY(), getX() + SIZE, getY() + SIZE, EclipseUiTheme.PANEL);
            int border = isHoveredOrFocused() ? EclipseUiTheme.ACCENT_DEEP : EclipseUiTheme.HAIRLINE;
            guiGraphics.fill(getX(), getY(), getX() + SIZE, getY() + 1, border);
            guiGraphics.fill(getX(), getY() + SIZE - 1, getX() + SIZE, getY() + SIZE, border);
            guiGraphics.fill(getX(), getY() + 1, getX() + 1, getY() + SIZE - 1, border);
            guiGraphics.fill(getX() + SIZE - 1, getY() + 1, getX() + SIZE, getY() + SIZE - 1, border);

            // Unspent-points nudge: the glyph brightens to full accent while points wait.
            int glyphColor = ClientStateCache.skillUnspent > 0 ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM;
            guiGraphics.drawCenteredString(Minecraft.getInstance().font, "✦",
                    getX() + SIZE / 2, getY() + (SIZE - 8) / 2 + 1, glyphColor);
        }
    }
}
