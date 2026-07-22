package dev.projecteclipse.eclipse.client.menu;

import java.util.List;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractSliderButton;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.navigation.CommonInputs;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.common.ModConfigSpec;
import org.lwjgl.glfw.GLFW;

/**
 * Live editor for all seven cosmetic values in {@code eclipse-client.toml}. Each themed
 * toggle remains a vanilla {@link AbstractSliderButton}, preserving keyboard focus,
 * narration and mouse handling while snapping its value to on/off. Changes call
 * {@link ModConfigSpec.BooleanValue#set} followed by {@link ModConfigSpec.BooleanValue#save}.
 */
@OnlyIn(Dist.CLIENT)
public final class EclipseSettingsScreen extends Screen {
    private static final int TEXT_COLOR = 0xE8E0F5;
    private static final int ACCENT_COLOR = 0xB98CFF;
    private static final int DIM_COLOR = 0x9A8FB8;
    private static final int PANEL_COLOR = 0xF0140C24;

    private static final List<Option> OPTIONS = List.of(
            new Option("customMenu", "gui.eclipse.settings.option.custom_menu"),
            new Option("showBossbarSkin", "gui.eclipse.settings.option.bossbar"),
            new Option("showSidebar", "gui.eclipse.settings.option.sidebar"),
            new Option("uiSounds", "gui.eclipse.settings.option.ui_sounds"),
            new Option("customCursor", "gui.eclipse.settings.option.cursor"),
            new Option("veilPostFx", "gui.eclipse.settings.option.veil_fx"),
            new Option("reducedFx", "gui.eclipse.settings.option.reduced_fx"));

    private final Screen parent;
    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;

    public EclipseSettingsScreen(Screen parent) {
        super(Component.translatable("gui.eclipse.settings.title"));
        this.parent = parent;
    }

    @Override
    protected void init() {
        panelW = Mth.clamp(this.width - 24, 300, 420);
        panelH = Mth.clamp(this.height - 24, 214, 280);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        int gap = 8;
        int toggleW = (panelW - 30 - gap) / 2;
        int toggleH = 20;
        int firstX = panelX + 15;
        int firstY = panelY + 48;
        for (int i = 0; i < OPTIONS.size(); i++) {
            int column = i / 4;
            int row = i % 4;
            Option option = OPTIONS.get(i);
            addRenderableWidget(new ConfigToggle(firstX + column * (toggleW + gap),
                    firstY + row * 26, toggleW, toggleH, option, read(option.key())));
        }

        int doneW = 120;
        addRenderableWidget(Button.builder(CommonComponents.GUI_DONE, button -> onClose())
                .bounds(panelX + (panelW - doneW) / 2, panelY + panelH - 30, doneW, 20)
                .build(EclipseMenuButton::new));
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        renderTransparentBackground(guiGraphics);
        guiGraphics.fill(panelX, panelY, panelX + panelW, panelY + panelH, PANEL_COLOR);
        guiGraphics.fill(panelX, panelY, panelX + panelW, panelY + 1, 0xFFB98CFF);
        guiGraphics.fill(panelX, panelY + panelH - 1, panelX + panelW, panelY + panelH, 0xFFB98CFF);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, panelY + 12, ACCENT_COLOR);
        guiGraphics.drawCenteredString(this.font, Component.translatable("gui.eclipse.settings.subtitle"),
                this.width / 2, panelY + 27, DIM_COLOR);
        CursorManager.endFrame();
    }

    /**
     * Turning the custom menu off from its own gear returns directly to a fresh vanilla
     * title screen. The Opening-event guard reads the just-saved value and leaves it alone.
     */
    @Override
    public void onClose() {
        if (this.parent instanceof EclipseTitleScreen && !EclipseClientConfig.customMenu()) {
            this.minecraft.setScreen(new TitleScreen());
        } else {
            this.minecraft.setScreen(this.parent);
        }
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

    private static boolean read(String key) {
        return switch (key) {
            case "customMenu" -> EclipseClientConfig.customMenu();
            case "showBossbarSkin" -> EclipseClientConfig.showBossbarSkin();
            case "showSidebar" -> EclipseClientConfig.showSidebar();
            case "uiSounds" -> EclipseClientConfig.uiSounds();
            case "customCursor" -> EclipseClientConfig.customCursor();
            case "veilPostFx" -> EclipseClientConfig.veilPostFx();
            case "reducedFx" -> EclipseClientConfig.reducedFx();
            default -> throw new IllegalArgumentException("Unknown Eclipse client option " + key);
        };
    }

    private static void write(String key, boolean enabled) {
        Object configValue = EclipseClientConfig.SPEC.getValues().valueMap().get(key);
        if (!(configValue instanceof ModConfigSpec.BooleanValue booleanValue)) {
            EclipseMod.LOGGER.error("Missing boolean client-config value {}", key);
            return;
        }
        booleanValue.set(enabled);
        booleanValue.save();
    }

    private record Option(String key, String labelKey) {}

    /**
     * Boolean specialization of vanilla's slider widget. Mouse/keyboard actions snap to
     * two states, while the face uses the same v1 title art and W9 hover/cursor behavior.
     */
    private static final class ConfigToggle extends AbstractSliderButton {
        private static final ResourceLocation FACE = ResourceLocation.fromNamespaceAndPath(
                EclipseMod.MOD_ID, "textures/gui/title/button.png");
        private static final ResourceLocation FACE_HOVERED = ResourceLocation.fromNamespaceAndPath(
                EclipseMod.MOD_ID, "textures/gui/title/button_highlighted.png");
        private static final int FACE_WIDTH = 200;
        private static final int FACE_HEIGHT = 20;

        private final Option option;
        private boolean wasHovered;
        private float glow;
        private long lastFrameMillis;

        ConfigToggle(int x, int y, int width, int height, Option option, boolean initialValue) {
            super(x, y, width, height, Component.empty(), initialValue ? 1.0D : 0.0D);
            this.option = option;
            updateMessage();
        }

        @Override
        public void onClick(double mouseX, double mouseY, int button) {
            setBoolean(value < 0.5D);
        }

        @Override
        public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
            if (CommonInputs.selected(keyCode)) {
                setBoolean(value < 0.5D);
                return true;
            }
            if (keyCode == GLFW.GLFW_KEY_LEFT || keyCode == GLFW.GLFW_KEY_RIGHT) {
                setBoolean(keyCode == GLFW.GLFW_KEY_RIGHT);
                return true;
            }
            return super.keyPressed(keyCode, scanCode, modifiers);
        }

        private void setBoolean(boolean enabled) {
            this.value = enabled ? 1.0D : 0.0D;
            applyValue();
            updateMessage();
        }

        @Override
        protected void updateMessage() {
            Component state = value >= 0.5D ? CommonComponents.OPTION_ON : CommonComponents.OPTION_OFF;
            setMessage(CommonComponents.optionNameValue(Component.translatable(option.labelKey()), state));
        }

        @Override
        protected void applyValue() {
            this.value = value >= 0.5D ? 1.0D : 0.0D;
            EclipseSettingsScreen.write(option.key(), value >= 0.5D);
        }

        @Override
        public void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            boolean hovered = this.active && isHoveredOrFocused();
            if (hovered && !wasHovered) {
                UiSounds.hover();
            }
            wasHovered = hovered;
            advanceGlow(hovered);
            if (hovered) {
                CursorManager.requestPointer();
            }

            RenderSystem.enableBlend();
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, this.alpha);
            guiGraphics.blit(hovered ? FACE_HOVERED : FACE, getX(), getY(), getWidth(), getHeight(),
                    0.0F, 0.0F, FACE_WIDTH, FACE_HEIGHT, FACE_WIDTH, FACE_HEIGHT);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);

            int stateColor = value >= 0.5D ? 0xFFB98CFF : 0xFF453A5E;
            guiGraphics.fill(getX() + getWidth() - 9, getY() + 7,
                    getX() + getWidth() - 3, getY() + 13, stateColor);
            renderScrollingString(guiGraphics, Minecraft.getInstance().font, 10,
                    (this.active ? TEXT_COLOR : 0x8A80A0) | Mth.ceil(this.alpha * 255.0F) << 24);
            if (glow > 0.02F) {
                renderGlow(guiGraphics);
            }
            RenderSystem.disableBlend();
        }

        private void advanceGlow(boolean hovered) {
            long now = System.currentTimeMillis();
            float elapsedTicks = lastFrameMillis == 0L ? 1.0F
                    : Math.min(4.0F, (now - lastFrameMillis) / 50.0F);
            lastFrameMillis = now;
            float target = hovered ? 1.0F : 0.0F;
            float step = 0.25F * elapsedTicks;
            glow = glow < target ? Math.min(target, glow + step) : Math.max(target, glow - step);
        }

        private void renderGlow(GuiGraphics guiGraphics) {
            int color = ((int) (glow * 190.0F) << 24) | 0xB98CFF;
            int x0 = getX() - 1;
            int y0 = getY() - 1;
            int x1 = getX() + width + 1;
            int y1 = getY() + height + 1;
            guiGraphics.fill(x0, y0, x1, y0 + 2, color);
            guiGraphics.fill(x0, y1 - 2, x1, y1, color);
            guiGraphics.fill(x0, y0 + 2, x0 + 2, y1 - 2, color);
            guiGraphics.fill(x1 - 2, y0 + 2, x1, y1 - 2, color);
        }
    }
}
