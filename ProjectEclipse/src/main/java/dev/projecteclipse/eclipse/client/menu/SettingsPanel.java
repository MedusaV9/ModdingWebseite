package dev.projecteclipse.eclipse.client.menu;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;
import java.util.function.DoubleConsumer;
import java.util.function.DoubleSupplier;
import java.util.function.Function;
import java.util.function.Supplier;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.C2SLocalePayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractContainerWidget;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.narration.NarratedElementType;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.client.gui.navigation.CommonInputs;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.common.ModConfigSpec;
import net.neoforged.neoforge.network.PacketDistributor;
import org.lwjgl.glfw.GLFW;

/**
 * The consolidated Eclipse settings list ({@code docs/plans_v3/P3_ui.md} §3.4, R12) — a
 * self-contained Quiet-Eclipse widget composite, NOT a screen. Every player-facing
 * {@code eclipse-client.toml} key (§7.1) is rendered as a themed row, grouped into the §3.4
 * sections (Anzeige / Effekte / Audio / Benachrichtigungen / Sprache / Server). The same
 * panel is mounted by {@code EclipseSettingsScreen} v2 (standalone: pause menu, title gear,
 * Mods screen) and by the handbook's {@code SettingsTab} — single source of truth.
 *
 * <p><b>Writes (B13)</b>: every row holds the typed {@link ModConfigSpec.ConfigValue} handle
 * from {@link EclipseClientConfig} and applies changes via {@code set()} + {@code save()} —
 * never through {@code SPEC.getValues().valueMap()} string lookups, so config sections can be
 * introduced later without breaking the UI. {@code set()} refreshes the cached value, which
 * makes every change apply live (consumers read the static getters per frame); {@code save()}
 * persists the TOML. Slider drags {@code set()} per detent and {@code save()} once on
 * release, so a drag does not spam disk writes.</p>
 *
 * <p><b>Sounds (B18)</b>: rows extend {@link EclipseWidget} (hover blip + 1px accent ring +
 * pointer cursor) and press through {@link UiSounds#toggle()} / {@link UiSounds#slider()} —
 * no vanilla button plink anywhere.</p>
 *
 * <p><b>Input/focus</b>: the panel is one {@link AbstractContainerWidget}; hosts mount it via
 * {@link #widgets()} ({@code addRenderableWidget}) and vanilla routing provides mouse, focus
 * traversal and key dispatch to the internal rows. Content taller than the viewport scrolls
 * (wheel, scrollbar drag, and auto-scroll to the focused row); rows render inside a scissor,
 * so nothing bleeds outside the content rect. Frozen §7.2 surface:
 * constructor {@code (x, y, w, h)} + {@code render/mouseClicked/mouseDragged/mouseReleased/
 * mouseScrolled/keyPressed/widgets()}.</p>
 *
 * <p>The language row runs the same code path as {@code /lang} (W4):
 * {@link EclipseLang#setOverride} (which persists through {@code LangConfigBridge} into the
 * {@code langOverride} key) plus a {@link C2SLocalePayload} when connected — deferred one
 * task so the resulting screen re-init never mutates widget lists mid-click.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class SettingsPanel extends AbstractContainerWidget {
    private static final int ROW_HEIGHT = 18;
    private static final int ROW_GAP = 4;
    /** drawHeader block: 12px title/hairline + GAP, plus breathing room above. */
    private static final int SECTION_TOP_GAP = 6;
    private static final int SCROLLBAR_LANE = 6;
    private static final int SCROLL_STEP = 24;

    private static final String OPTION_PREFIX = "gui.eclipse.settings.option.";

    private final Font font = Minecraft.getInstance().font;
    private final List<Row> rows = new ArrayList<>();
    private final List<SectionHeader> headers = new ArrayList<>();
    private final int contentHeight;

    private double scroll;
    private boolean scrollbarDragging;

    public SettingsPanel(int x, int y, int width, int height) {
        super(x, y, Math.max(140, width), Math.max(48, height), EclipseLang.tr("gui.eclipse.settings.title"));
        this.contentHeight = buildRows();
        layout();
    }

    // ---------------------------------------------------------------- content

    /** Builds all §3.4 sections/rows; returns the total content height in panel-space px. */
    private int buildRows() {
        int y = 2;

        y = header(y, "gui.eclipse.settings.section.display");
        y = toggle(y, "custom_menu", EclipseClientConfig::customMenu, EclipseClientConfig.CUSTOM_MENU);
        y = toggle(y, "sidebar", EclipseClientConfig::showSidebar, EclipseClientConfig.SHOW_SIDEBAR);
        y = enumCycle(y, "sidebar_side", "side",
                List.of(EclipseClientConfig.SidebarSide.values()),
                EclipseClientConfig::sidebarSide, EclipseClientConfig.SIDEBAR_SIDE);
        y = slider(y, "sidebar_scale", 0.6D, 1.4D, 0.05D,
                EclipseClientConfig::sidebarScale, EclipseClientConfig.SIDEBAR_SCALE,
                value -> String.format(Locale.ROOT, "\u00d7%.2f", value));
        y = enumCycle(y, "sidebar_overflow", "overflow",
                List.of(EclipseClientConfig.SidebarOverflow.values()),
                EclipseClientConfig::sidebarOverflow, EclipseClientConfig.SIDEBAR_OVERFLOW);
        y = toggle(y, "bossbar", EclipseClientConfig::showBossbarSkin, EclipseClientConfig.SHOW_BOSSBAR_SKIN);
        y = enumCycle(y, "bossbar_style", "bossbar_style",
                List.of(EclipseClientConfig.BossbarStyle.values()),
                EclipseClientConfig::bossbarStyle, EclipseClientConfig.BOSSBAR_STYLE);
        y = toggle(y, "day_timer", EclipseClientConfig::showDayTimer, EclipseClientConfig.SHOW_DAY_TIMER);
        y = toggle(y, "xp_bar", EclipseClientConfig::showCustomXpBar, EclipseClientConfig.SHOW_CUSTOM_XP_BAR);
        y = toggle(y, "death_screen", EclipseClientConfig::customDeathScreen,
                EclipseClientConfig.CUSTOM_DEATH_SCREEN);
        y = toggle(y, "loading_screens", EclipseClientConfig::customLoadingScreens,
                EclipseClientConfig.CUSTOM_LOADING_SCREENS);

        y = header(y, "gui.eclipse.settings.section.effects");
        y = toggle(y, "reduced_fx", EclipseClientConfig::reducedFx, EclipseClientConfig.REDUCED_FX);
        y = toggle(y, "veil_fx", EclipseClientConfig::veilPostFx, EclipseClientConfig.VEIL_POST_FX);
        y = toggle(y, "cursor", EclipseClientConfig::customCursor, EclipseClientConfig.CUSTOM_CURSOR);
        y = toggle(y, "cinematic_distance", EclipseClientConfig::cinematicViewDistance,
                EclipseClientConfig.CINEMATIC_VIEW_DISTANCE);
        y = toggle(y, "level_up_fx", EclipseClientConfig::levelUpCelebrations,
                EclipseClientConfig.LEVEL_UP_CELEBRATIONS);

        y = header(y, "gui.eclipse.settings.section.audio");
        y = toggle(y, "ui_sounds", EclipseClientConfig::uiSounds, EclipseClientConfig.UI_SOUNDS);
        y = slider(y, "ui_volume", 0.0D, 1.0D, 0.05D,
                EclipseClientConfig::uiSoundVolume, EclipseClientConfig.UI_SOUND_VOLUME,
                value -> Math.round(value * 100.0D) + "%");
        y = toggle(y, "heartbeat", EclipseClientConfig::heartbeatSound, EclipseClientConfig.HEARTBEAT_SOUND);

        y = header(y, "gui.eclipse.settings.section.notifications");
        y = toggle(y, "proc_messages", EclipseClientConfig::procMessages, EclipseClientConfig.PROC_MESSAGES);

        y = header(y, "gui.eclipse.settings.section.language");
        y = addRow(y, new ThemedEnumCycle<>("language", rowWidth(),
                List.of("auto", "en_us", "de_de"),
                token -> EclipseLang.tr("gui.eclipse.settings.lang." + switch (token) {
                    case "en_us" -> "en";
                    case "de_de" -> "de";
                    default -> "auto";
                }),
                EclipseLang::overrideRaw,
                SettingsPanel::applyLanguage));

        y = header(y, "gui.eclipse.settings.section.server");
        y = toggle(y, "server_render_distance", EclipseClientConfig::allowServerRenderDistance,
                EclipseClientConfig.ALLOW_SERVER_RENDER_DISTANCE);

        return y + 2;
    }

    private int header(int y, String titleKey) {
        if (!headers.isEmpty() || !rows.isEmpty()) {
            y += SECTION_TOP_GAP;
        }
        headers.add(new SectionHeader(titleKey, y));
        return y + 12 + EclipseUiTheme.GAP;
    }

    private int toggle(int y, String key, BooleanSupplier read, ModConfigSpec.BooleanValue handle) {
        return addRow(y, new ThemedToggle(key, rowWidth(), read, handle));
    }

    private <T extends Enum<T>> int enumCycle(int y, String key, String valuePrefix, List<T> options,
            Supplier<T> read, ModConfigSpec.EnumValue<T> handle) {
        return addRow(y, new ThemedEnumCycle<>(key, rowWidth(), options,
                value -> EclipseLang.tr("gui.eclipse.settings." + valuePrefix + "."
                        + value.name().toLowerCase(Locale.ROOT)),
                read, value -> save(handle, value)));
    }

    private int slider(int y, String key, double min, double max, double step,
            DoubleSupplier read, ModConfigSpec.DoubleValue handle, Function<Double, String> format) {
        return addRow(y, new ThemedSlider(key, rowWidth(), min, max, step, read,
                value -> setLive(handle, value), () -> persist(handle), format));
    }

    private int addRow(int y, Row row) {
        row.relY = y;
        rows.add(row);
        return y + ROW_HEIGHT + ROW_GAP;
    }

    private int rowWidth() {
        return this.width - SCROLLBAR_LANE;
    }

    // ---------------------------------------------------------------- config writes (B13)

    /** Typed write path: {@code set()} applies live, {@code save()} persists the TOML. */
    private static <T> void save(ModConfigSpec.ConfigValue<T> handle, T value) {
        if (!EclipseClientConfig.SPEC.isLoaded()) {
            return;
        }
        handle.set(value);
        handle.save();
    }

    /** Slider detent: apply live without touching disk (drag-friendly). */
    private static void setLive(ModConfigSpec.DoubleValue handle, double value) {
        if (EclipseClientConfig.SPEC.isLoaded()) {
            handle.set(value);
        }
    }

    /** Slider release/keyboard step: persist whatever {@code set()} already applied. */
    private static void persist(ModConfigSpec.DoubleValue handle) {
        if (EclipseClientConfig.SPEC.isLoaded()) {
            handle.save();
        }
    }

    /**
     * Same code path as {@code /lang} ({@code LangClientCommands.apply}); deferred one task
     * because {@link EclipseLang#reload()} re-inits the open screen (widget lists must not be
     * rebuilt while the click is still being routed through them).
     */
    private static void applyLanguage(String token) {
        Minecraft minecraft = Minecraft.getInstance();
        minecraft.tell(() -> {
            EclipseLang.setOverride(token); // persists via LangConfigBridge -> langOverride key
            if (minecraft.getConnection() != null) {
                PacketDistributor.sendToServer(new C2SLocalePayload(
                        EclipseLang.overrideRaw(), !"auto".equals(EclipseLang.overrideRaw())));
            }
        });
    }

    // ---------------------------------------------------------------- host surface (§7.2)

    /** Frozen §7.2 mount point: the panel is one composite widget — hosts add exactly this. */
    public List<AbstractWidget> widgets() {
        return List.of(this);
    }

    /** Current scroll offset (px) — hosts preserve it across re-inits. */
    public double scrollAmount() {
        return scroll;
    }

    public void setScrollAmount(double value) {
        scroll = Mth.clamp(value, 0.0D, maxScroll());
        layout();
    }

    // ---------------------------------------------------------------- layout & scrolling

    private int maxScroll() {
        return Math.max(0, contentHeight - this.height);
    }

    /** Applies scroll to the rows' absolute positions (hitboxes always match pixels). */
    private void layout() {
        int scrolled = (int) Math.round(scroll);
        for (Row row : rows) {
            row.setPosition(getX(), getY() + row.relY - scrolled);
        }
    }

    /** Keeps keyboard focus visible: scrolls the viewport to the newly focused row. */
    @Override
    public void setFocused(@Nullable GuiEventListener listener) {
        super.setFocused(listener);
        if (listener instanceof Row row) {
            if (row.relY - scroll < 0) {
                setScrollAmount(row.relY - SECTION_TOP_GAP - 12 - EclipseUiTheme.GAP);
            } else if (row.relY + ROW_HEIGHT - scroll > this.height) {
                setScrollAmount(row.relY + ROW_HEIGHT - this.height + 2);
            }
        }
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (!this.active || !this.visible || !isMouseOver(mouseX, mouseY)) {
            return false;
        }
        if (button == 0 && maxScroll() > 0 && mouseX >= getX() + this.width - SCROLLBAR_LANE) {
            scrollbarDragging = true;
            scrollToMouse(mouseY);
            return true;
        }
        if (super.mouseClicked(mouseX, mouseY, button)) {
            return true;
        }
        // Consume every in-panel click (a miss clears row focus but never falls through to
        // whatever sits behind the panel, e.g. the handbook's mouse-bound close check).
        setFocused((GuiEventListener) null);
        return true;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (scrollbarDragging) {
            scrollToMouse(mouseY);
            return true;
        }
        return super.mouseDragged(mouseX, mouseY, button, dragX, dragY);
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (scrollbarDragging && button == 0) {
            scrollbarDragging = false;
            return true;
        }
        return super.mouseReleased(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (!this.visible || !isMouseOver(mouseX, mouseY) || maxScroll() == 0) {
            return false;
        }
        setScrollAmount(scroll - scrollY * SCROLL_STEP);
        return true;
    }

    private void scrollToMouse(double mouseY) {
        int thumbH = thumbHeight();
        float fraction = (float) (mouseY - getY() - thumbH / 2.0D) / Math.max(1, this.height - thumbH);
        setScrollAmount(fraction * maxScroll());
    }

    private int thumbHeight() {
        return Math.max(12, this.height * this.height / Math.max(1, contentHeight));
    }

    // ---------------------------------------------------------------- rendering

    @Override
    protected void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        layout();
        int top = getY();
        int bottom = getY() + this.height;
        int scrolled = (int) Math.round(scroll);

        guiGraphics.enableScissor(getX(), top, getX() + this.width, bottom);
        for (SectionHeader header : headers) {
            int headerY = top + header.relY() - scrolled;
            if (headerY > bottom || headerY + 12 < top) {
                continue;
            }
            EclipseUiTheme.drawHeader(guiGraphics, font, EclipseLang.tr(header.titleKey()),
                    getX(), headerY, rowWidth());
        }
        for (Row row : rows) {
            if (row.getY() > bottom || row.getY() + ROW_HEIGHT < top) {
                continue;
            }
            row.render(guiGraphics, mouseX, mouseY, partialTick);
        }
        guiGraphics.disableScissor();
        renderScrollbar(guiGraphics);
    }

    /** 2px Quiet-Eclipse scrollbar in the right lane; only present when content overflows. */
    private void renderScrollbar(GuiGraphics guiGraphics) {
        int max = maxScroll();
        if (max <= 0) {
            return;
        }
        int barX = getX() + this.width - 3;
        guiGraphics.fill(barX, getY(), barX + 2, getY() + this.height, EclipseUiTheme.HAIRLINE);
        int thumbH = thumbHeight();
        int thumbY = getY() + (int) ((this.height - thumbH) * (scroll / max));
        guiGraphics.fill(barX, thumbY, barX + 2, thumbY + thumbH,
                scrollbarDragging ? EclipseUiTheme.ACCENT_DEEP : EclipseUiTheme.ACCENT);
    }

    @Override
    protected void updateWidgetNarration(NarrationElementOutput narrationElementOutput) {
        if (getFocused() instanceof AbstractWidget widget) {
            widget.updateNarration(narrationElementOutput);
        } else {
            narrationElementOutput.add(NarratedElementType.TITLE, getMessage());
        }
    }

    @Override
    public List<? extends GuiEventListener> children() {
        return rows;
    }

    private record SectionHeader(String titleKey, int relY) {}

    // ---------------------------------------------------------------- row widgets

    /** Shared row plumbing: label key, panel-space y, raised-card face. */
    private abstract static class Row extends EclipseWidget {
        final String optionKey;
        int relY;

        Row(String optionKey, int width) {
            super(0, 0, width, ROW_HEIGHT, EclipseLang.tr(OPTION_PREFIX + optionKey));
            this.optionKey = optionKey;
            setTooltip(Tooltip.create(EclipseLang.tr(OPTION_PREFIX + optionKey + ".tip")));
        }

        Component label() {
            return EclipseLang.tr(OPTION_PREFIX + optionKey);
        }

        void drawCard(GuiGraphics guiGraphics) {
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + this.height,
                    EclipseUiTheme.PANEL_RAISED);
        }

        void drawLabel(GuiGraphics guiGraphics, Font font, int maxWidth) {
            guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, label().getString(), maxWidth),
                    getX() + 4, getY() + (this.height - 8) / 2, EclipseUiTheme.TEXT);
        }

        int textY() {
            return getY() + (this.height - 8) / 2;
        }
    }

    /**
     * Boolean row: label left, On/Off state + accent pill right. Presses through
     * {@link UiSounds#toggle()} (B18); Enter/Space flips from the keyboard.
     */
    private static final class ThemedToggle extends Row {
        private static final int PILL_W = 16;
        private static final int PILL_H = 8;

        private final BooleanSupplier read;
        private final ModConfigSpec.BooleanValue handle;

        ThemedToggle(String optionKey, int width, BooleanSupplier read, ModConfigSpec.BooleanValue handle) {
            super(optionKey, width);
            this.read = read;
            this.handle = handle;
        }

        private void flip() {
            save(handle, !read.getAsBoolean());
        }

        @Override
        public void onClick(double mouseX, double mouseY, int button) {
            flip();
        }

        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            UiSounds.toggle();
        }

        @Override
        public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
            if (this.active && this.visible && CommonInputs.selected(keyCode)) {
                UiSounds.toggle();
                flip();
                return true;
            }
            return false;
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            drawCard(guiGraphics);
            boolean value = read.getAsBoolean();
            Font font = Minecraft.getInstance().font;

            int pillX = getX() + this.width - 4 - PILL_W;
            int pillY = getY() + (this.height - PILL_H) / 2;
            guiGraphics.fill(pillX, pillY, pillX + PILL_W, pillY + PILL_H, EclipseUiTheme.HAIRLINE);
            int knobX = value ? pillX + PILL_W - 7 : pillX + 1;
            guiGraphics.fill(knobX, pillY + 1, knobX + 6, pillY + PILL_H - 1,
                    value ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM);

            Component state = value ? CommonComponents.OPTION_ON : CommonComponents.OPTION_OFF;
            int stateW = font.width(state);
            guiGraphics.drawString(font, state, pillX - 4 - stateW, textY(),
                    value ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM);

            drawLabel(guiGraphics, font, this.width - PILL_W - stateW - 16);
        }
    }

    /**
     * Multi-state row: click (or Enter/Space) cycles forward, right-click backward, value
     * shown right in accent with quiet direction hints while hovered/focused.
     */
    private static final class ThemedEnumCycle<T> extends Row {
        private final List<T> options;
        private final Function<T, Component> valueLabel;
        private final Supplier<T> read;
        private final Consumer<T> write;

        ThemedEnumCycle(String optionKey, int width, List<T> options, Function<T, Component> valueLabel,
                Supplier<T> read, Consumer<T> write) {
            super(optionKey, width);
            this.options = options;
            this.valueLabel = valueLabel;
            this.read = read;
            this.write = write;
        }

        private void cycle(int direction) {
            int index = options.indexOf(read.get());
            write.accept(options.get(Math.floorMod(index + direction, options.size())));
        }

        @Override
        protected boolean isValidClickButton(int button) {
            return button == 0 || button == 1;
        }

        @Override
        public void onClick(double mouseX, double mouseY, int button) {
            cycle(button == 1 ? -1 : 1);
        }

        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            UiSounds.toggle();
        }

        @Override
        public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
            if (this.active && this.visible && CommonInputs.selected(keyCode)) {
                UiSounds.toggle();
                cycle(1);
                return true;
            }
            return false;
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            drawCard(guiGraphics);
            Font font = Minecraft.getInstance().font;
            Component value = valueLabel.apply(read.get());
            int valueW = font.width(value);
            int valueX = getX() + this.width - 8 - valueW;
            guiGraphics.drawString(font, value, valueX, textY(), EclipseUiTheme.ACCENT);
            if (isHoveredOrFocused()) {
                guiGraphics.drawString(font, "<", valueX - 8, textY(), EclipseUiTheme.DIM);
                guiGraphics.drawString(font, ">", getX() + this.width - 6, textY(), EclipseUiTheme.DIM);
            }
            drawLabel(guiGraphics, font, this.width - valueW - 28);
        }
    }

    /**
     * Continuous row (B18 custom slider): drag/click on the track or nudge with ←/→. Detents
     * apply live via {@code set()} with a {@link UiSounds#slider()} tick per step; the file is
     * saved once on release / keyboard step, never per drag frame.
     */
    private static final class ThemedSlider extends Row {
        private static final int TRACK_W = 56;
        private static final int VALUE_W = 34;

        private final double min;
        private final double max;
        private final double step;
        private final DoubleSupplier read;
        private final DoubleConsumer applyLive;
        private final Runnable commit;
        private final Function<Double, String> format;

        private double value;
        private boolean sliding;

        ThemedSlider(String optionKey, int width, double min, double max, double step,
                DoubleSupplier read, DoubleConsumer applyLive, Runnable commit,
                Function<Double, String> format) {
            super(optionKey, width);
            this.min = min;
            this.max = max;
            this.step = step;
            this.read = read;
            this.applyLive = applyLive;
            this.commit = commit;
            this.format = format;
            this.value = read.getAsDouble();
        }

        private int trackX() {
            return getX() + this.width - 8 - VALUE_W - 6 - TRACK_W;
        }

        private void setFromMouse(double mouseX) {
            applyQuantized(min + (max - min)
                    * Mth.clamp((mouseX - trackX()) / (double) TRACK_W, 0.0D, 1.0D));
        }

        /** Snaps to the step grid; on an actual detent change: live-apply + slider tick. */
        private void applyQuantized(double raw) {
            double quantized = Mth.clamp(min + Math.round((raw - min) / step) * step, min, max);
            if (Math.abs(quantized - value) > 1.0E-4) {
                value = quantized;
                applyLive.accept(quantized);
                UiSounds.slider();
            }
        }

        @Override
        public void onClick(double mouseX, double mouseY, int button) {
            if (mouseX >= trackX() - 4) {
                sliding = true;
                setFromMouse(mouseX);
            }
        }

        @Override
        protected void onDrag(double mouseX, double mouseY, double dragX, double dragY) {
            if (sliding) {
                setFromMouse(mouseX);
            }
        }

        @Override
        public void onRelease(double mouseX, double mouseY) {
            if (sliding) {
                sliding = false;
                commit.run();
            }
        }

        /** Track/keyboard audio comes from the detent ticks — no press sound (B18). */
        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {}

        @Override
        public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
            if (!this.active || !this.visible) {
                return false;
            }
            if (keyCode == GLFW.GLFW_KEY_LEFT || keyCode == GLFW.GLFW_KEY_RIGHT) {
                applyQuantized(value + (keyCode == GLFW.GLFW_KEY_RIGHT ? step : -step));
                commit.run();
                return true;
            }
            return false;
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            drawCard(guiGraphics);
            if (!sliding) {
                value = read.getAsDouble(); // stay in sync with external edits (config watcher)
            }
            Font font = Minecraft.getInstance().font;

            int trackX = trackX();
            int centerY = getY() + this.height / 2;
            float fraction = (float) Mth.clamp((value - min) / (max - min), 0.0D, 1.0D);
            guiGraphics.fill(trackX, centerY - 1, trackX + TRACK_W, centerY + 1, EclipseUiTheme.HAIRLINE);
            guiGraphics.fill(trackX, centerY - 1, trackX + Math.round(fraction * TRACK_W), centerY + 1,
                    EclipseUiTheme.ACCENT);
            int handleX = trackX + Math.round(fraction * (TRACK_W - 4));
            guiGraphics.fill(handleX, centerY - 5, handleX + 4, centerY + 5,
                    sliding ? EclipseUiTheme.ACCENT_DEEP : EclipseUiTheme.ACCENT);

            String valueText = format.apply(value);
            guiGraphics.drawString(font, valueText,
                    getX() + this.width - 8 - font.width(valueText), textY(), EclipseUiTheme.DIM);

            drawLabel(guiGraphics, font, trackX - 8 - getX());
        }
    }
}
