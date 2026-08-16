package de.sonic0810.goobymod.client.config;

import de.sonic0810.goobymod.GoobyClientConfig;
import java.util.Collections;
import java.util.List;
import java.util.function.Consumer;
import java.util.function.IntConsumer;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.ComponentPath;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.ContainerObjectSelectionList;
import net.minecraft.client.gui.components.CycleButton;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.narration.NarratableEntry;
import net.minecraft.client.gui.narration.NarratedElementType;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.client.gui.navigation.FocusNavigationEvent;
import javax.annotation.Nullable;
import net.minecraft.network.chat.Component;

/**
 * Scrollable option list (left side of {@link GoobyConfigScreen}): category
 * headings plus one keyboard-/narrator-friendly widget per setting. All
 * widgets read from and write into the shared {@link GoobyConfigDraft}.
 */
final class GoobyConfigList extends ContainerObjectSelectionList<GoobyConfigList.Entry> {
    private static final int ITEM_HEIGHT = 25;
    private static final int WIDGET_HEIGHT = 20;
    private static final int MAX_ROW_WIDTH = 240;

    private final GoobyConfigDraft draft;

    private CycleButton<Boolean> showHudButton;
    private IntSliderButton hudXSlider;
    private IntSliderButton hudYSlider;
    private CycleButton<Boolean> screenEffectsButton;
    private CycleButton<Boolean> cameraShakeButton;
    private CycleButton<Boolean> reducedMotionButton;
    private CycleButton<Boolean> highContrastButton;

    GoobyConfigList(Minecraft minecraft, int width, int height, int y, GoobyConfigDraft draft) {
        super(minecraft, width, height, y, ITEM_HEIGHT);
        this.draft = draft;

        addEntry(new CategoryEntry(Component.translatable("config.goobymod.hud")));
        this.showHudButton = onOffButton("config.goobymod.hud.show", draft.showCompanionHud,
                value -> draft.showCompanionHud = value);
        addEntry(new WidgetEntry(this.showHudButton));
        this.hudXSlider = offsetSlider("config.goobymod.hud.offsetX", draft.hudOffsetX,
                value -> draft.hudOffsetX = value);
        addEntry(new WidgetEntry(this.hudXSlider));
        this.hudYSlider = offsetSlider("config.goobymod.hud.offsetY", draft.hudOffsetY,
                value -> draft.hudOffsetY = value);
        addEntry(new WidgetEntry(this.hudYSlider));

        addEntry(new CategoryEntry(Component.translatable("config.goobymod.screenFx")));
        this.screenEffectsButton = onOffButton("config.goobymod.screenFx.screenEffects",
                draft.screenEffects, value -> draft.screenEffects = value);
        addEntry(new WidgetEntry(this.screenEffectsButton));
        this.cameraShakeButton = onOffButton("config.goobymod.screenFx.cameraShake",
                draft.cameraShake, value -> draft.cameraShake = value);
        addEntry(new WidgetEntry(this.cameraShakeButton));

        addEntry(new CategoryEntry(Component.translatable("config.goobymod.accessibility")));
        this.reducedMotionButton = onOffButton("config.goobymod.accessibility.reducedMotion",
                draft.reducedMotion, value -> draft.reducedMotion = value);
        addEntry(new WidgetEntry(this.reducedMotionButton));
        this.highContrastButton = onOffButton("config.goobymod.accessibility.highContrastBubbles",
                draft.highContrastBubbles, value -> draft.highContrastBubbles = value);
        addEntry(new WidgetEntry(this.highContrastButton));
    }

    /** Pushes draft values back into every widget, e.g. after Reset Defaults. */
    void syncFromDraft() {
        this.showHudButton.setValue(this.draft.showCompanionHud);
        this.hudXSlider.setIntValue(this.draft.hudOffsetX);
        this.hudYSlider.setIntValue(this.draft.hudOffsetY);
        this.screenEffectsButton.setValue(this.draft.screenEffects);
        this.cameraShakeButton.setValue(this.draft.cameraShake);
        this.reducedMotionButton.setValue(this.draft.reducedMotion);
        this.highContrastButton.setValue(this.draft.highContrastBubbles);
    }

    private CycleButton<Boolean> onOffButton(String key, boolean initialValue,
            Consumer<Boolean> onChange) {
        return CycleButton.onOffBuilder(initialValue)
                .withTooltip(value -> Tooltip.create(Component.translatable(key + ".tooltip")))
                .create(0, 0, getRowWidth(), WIDGET_HEIGHT, Component.translatable(key),
                        (button, value) -> onChange.accept(value));
    }

    private IntSliderButton offsetSlider(String key, int initialValue, IntConsumer onChange) {
        IntSliderButton slider = new IntSliderButton(getRowWidth(), WIDGET_HEIGHT,
                Component.translatable(key), GoobyClientConfig.COMPANION_HUD_OFFSET_MIN,
                GoobyClientConfig.COMPANION_HUD_OFFSET_MAX, initialValue, onChange);
        slider.setTooltip(Tooltip.create(Component.translatable(key + ".tooltip")));
        return slider;
    }

    @Override
    public int getRowWidth() {
        return Math.min(MAX_ROW_WIDTH, getWidth() - 26);
    }

    @Override
    protected int getScrollbarPosition() {
        return getRight() - 10;
    }

    abstract static class Entry extends ContainerObjectSelectionList.Entry<Entry> {
    }

    /** Non-focusable centered heading, narrated when hovered (vanilla pattern). */
    final class CategoryEntry extends Entry {
        private final Component name;
        private final int labelWidth;

        CategoryEntry(Component name) {
            this.name = name;
            this.labelWidth = GoobyConfigList.this.minecraft.font.width(name);
        }

        @Override
        public void render(GuiGraphics graphics, int index, int top, int left, int width,
                int height, int mouseX, int mouseY, boolean hovering, float partialTick) {
            graphics.drawString(GoobyConfigList.this.minecraft.font, this.name,
                    left + width / 2 - this.labelWidth / 2, top + height - 9 - 1, 0xFFFFFF, false);
        }

        @Nullable
        @Override
        public ComponentPath nextFocusPath(FocusNavigationEvent event) {
            return null;
        }

        @Override
        public List<? extends GuiEventListener> children() {
            return Collections.emptyList();
        }

        @Override
        public List<? extends NarratableEntry> narratables() {
            return List.of(new NarratableEntry() {
                @Override
                public NarratableEntry.NarrationPriority narrationPriority() {
                    return NarratableEntry.NarrationPriority.HOVERED;
                }

                @Override
                public void updateNarration(NarrationElementOutput output) {
                    output.add(NarratedElementType.TITLE, CategoryEntry.this.name);
                }
            });
        }
    }

    static final class WidgetEntry extends Entry {
        private final AbstractWidget widget;

        WidgetEntry(AbstractWidget widget) {
            this.widget = widget;
        }

        @Override
        public void render(GuiGraphics graphics, int index, int top, int left, int width,
                int height, int mouseX, int mouseY, boolean hovering, float partialTick) {
            this.widget.setPosition(left, top);
            this.widget.render(graphics, mouseX, mouseY, partialTick);
        }

        @Override
        public List<? extends GuiEventListener> children() {
            return List.of(this.widget);
        }

        @Override
        public List<? extends NarratableEntry> narratables() {
            return List.of(this.widget);
        }
    }
}
