package dev.projecteclipse.eclipse.client.menu;

import javax.annotation.Nullable;

import com.mojang.authlib.minecraft.BanDetails;
import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.SharedConstants;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.multiplayer.JoinMultiplayerScreen;
import net.minecraft.client.gui.screens.multiplayer.SafetyScreen;
import net.minecraft.client.gui.screens.options.OptionsScreen;
import net.minecraft.client.gui.screens.worldselection.SelectWorldScreen;
import net.minecraft.client.renderer.CubeMap;
import net.minecraft.client.renderer.PanoramaRenderer;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The Eclipse-themed replacement for the vanilla title screen (installed by
 * {@link TitleScreenSwap}). Renders the rotating {@code eclipse:textures/gui/title/panorama_0..5}
 * cube map (falling back to a stretched {@code background.png} if any panorama face is missing),
 * the {@code logo.png} with a slow purple alpha pulse, and the four {@link EclipseMenuButton}s.
 * The buttons open exactly the screens vanilla {@code TitleScreen#createNormalMenuOptions} /
 * {@code init} use: {@link SelectWorldScreen}, {@link JoinMultiplayerScreen} (behind
 * {@link SafetyScreen} unless the warning was dismissed), {@link OptionsScreen}, and
 * {@code Minecraft#stop()} for quit.
 */
@OnlyIn(Dist.CLIENT)
public class EclipseTitleScreen extends Screen {
    private static final ResourceLocation LOGO =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/title/logo.png");
    private static final ResourceLocation FALLBACK_BACKGROUND =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/title/background.png");
    private static final String PANORAMA_BASE_PATH = "textures/gui/title/panorama";

    private static final CubeMap CUBE_MAP =
            new CubeMap(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, PANORAMA_BASE_PATH));
    private static final PanoramaRenderer PANORAMA = new PanoramaRenderer(CUBE_MAP);

    /** Source texture size of logo.png. */
    private static final int LOGO_TEXTURE_WIDTH = 512;
    private static final int LOGO_TEXTURE_HEIGHT = 160;
    /** On-screen logo size (half the texture, GUI-scaled units). */
    private static final int LOGO_WIDTH = 256;
    private static final int LOGO_HEIGHT = 80;
    /** Source texture size of background.png. */
    private static final int BACKGROUND_TEXTURE_WIDTH = 1024;
    private static final int BACKGROUND_TEXTURE_HEIGHT = 576;
    /** Full period of the logo alpha pulse, in milliseconds. */
    private static final long LOGO_PULSE_PERIOD_MS = 4000L;

    private static final int BUTTON_WIDTH = 200;
    private static final int BUTTON_HEIGHT = 20;
    private static final int BUTTON_SPACING = 24;

    private boolean panoramaUsable;

    public EclipseTitleScreen() {
        super(Component.translatable("narrator.screen.title"));
    }

    @Override
    protected void init() {
        this.panoramaUsable = checkPanoramaTextures();

        int x = this.width / 2 - BUTTON_WIDTH / 2;
        int y = this.height / 4 + 48;

        addRenderableWidget(Button.builder(Component.translatable("menu.singleplayer"),
                        button -> this.minecraft.setScreen(new SelectWorldScreen(this)))
                .bounds(x, y, BUTTON_WIDTH, BUTTON_HEIGHT)
                .build(EclipseMenuButton::new));

        Component multiplayerDisabledReason = getMultiplayerDisabledReason();
        addRenderableWidget(Button.builder(Component.translatable("menu.multiplayer"), button -> {
                    // Same flow as vanilla: safety warning first unless it was permanently dismissed.
                    Screen next = this.minecraft.options.skipMultiplayerWarning
                            ? new JoinMultiplayerScreen(this)
                            : new SafetyScreen(this);
                    this.minecraft.setScreen(next);
                })
                .bounds(x, y + BUTTON_SPACING, BUTTON_WIDTH, BUTTON_HEIGHT)
                .tooltip(multiplayerDisabledReason != null ? Tooltip.create(multiplayerDisabledReason) : null)
                .build(EclipseMenuButton::new)).active = multiplayerDisabledReason == null;

        addRenderableWidget(Button.builder(Component.translatable("menu.options"),
                        button -> this.minecraft.setScreen(new OptionsScreen(this, this.minecraft.options)))
                .bounds(x, y + BUTTON_SPACING * 2, BUTTON_WIDTH, BUTTON_HEIGHT)
                .build(EclipseMenuButton::new));

        addRenderableWidget(Button.builder(Component.translatable("menu.quit"),
                        button -> this.minecraft.stop())
                .bounds(x, y + BUTTON_SPACING * 3, BUTTON_WIDTH, BUTTON_HEIGHT)
                .build(EclipseMenuButton::new));
    }

    /** Mirrors vanilla {@code TitleScreen#getMultiplayerDisabledReason}. */
    @Nullable
    private Component getMultiplayerDisabledReason() {
        if (this.minecraft.allowsMultiplayer()) {
            return null;
        }
        if (this.minecraft.isNameBanned()) {
            return Component.translatable("title.multiplayer.disabled.banned.name");
        }
        BanDetails banDetails = this.minecraft.multiplayerBan();
        if (banDetails != null) {
            return banDetails.expires() != null
                    ? Component.translatable("title.multiplayer.disabled.banned.temporary")
                    : Component.translatable("title.multiplayer.disabled.banned.permanent");
        }
        return Component.translatable("title.multiplayer.disabled");
    }

    /** All six cube-map faces must resolve, otherwise we blit the static fallback. */
    private boolean checkPanoramaTextures() {
        for (int i = 0; i < 6; i++) {
            ResourceLocation face = ResourceLocation.fromNamespaceAndPath(
                    EclipseMod.MOD_ID, PANORAMA_BASE_PATH + "_" + i + ".png");
            if (this.minecraft.getResourceManager().getResource(face).isEmpty()) {
                EclipseMod.LOGGER.warn("Eclipse title panorama face {} missing, using static background", face);
                return false;
            }
        }
        return true;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        renderEclipseBackground(guiGraphics, partialTick);
        // Subtle darkening towards the bottom keeps buttons and text readable over the corona.
        guiGraphics.fillGradient(0, 0, this.width, this.height, 0x22000000, 0x66000000);
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        renderLogo(guiGraphics);

        guiGraphics.drawString(this.font, "Minecraft " + SharedConstants.getCurrentVersion().getName(),
                2, this.height - 10, 0xFFFFFFFF);
        Component tagline = Component.translatable("gui.eclipse.title.tagline");
        guiGraphics.drawString(this.font, tagline,
                this.width - this.font.width(tagline) - 2, this.height - 10, 0xFFB98CFF);
    }

    private void renderEclipseBackground(GuiGraphics guiGraphics, float partialTick) {
        if (this.panoramaUsable) {
            try {
                PANORAMA.render(guiGraphics, this.width, this.height, 1.0F, partialTick);
                return;
            } catch (RuntimeException e) {
                // Defensive: never crash the main menu over broken art, degrade to the still image.
                this.panoramaUsable = false;
                EclipseMod.LOGGER.warn("Eclipse title panorama failed to render, using static background", e);
            }
        }
        guiGraphics.blit(FALLBACK_BACKGROUND, 0, 0, this.width, this.height, 0.0F, 0.0F,
                BACKGROUND_TEXTURE_WIDTH, BACKGROUND_TEXTURE_HEIGHT,
                BACKGROUND_TEXTURE_WIDTH, BACKGROUND_TEXTURE_HEIGHT);
    }

    /** Logo centered horizontally, its center at ~1/4 screen height, with a slow purple alpha pulse. */
    private void renderLogo(GuiGraphics guiGraphics) {
        float phase = (Util.getMillis() % LOGO_PULSE_PERIOD_MS) / (float) LOGO_PULSE_PERIOD_MS;
        float pulse = 0.5F - 0.5F * Mth.cos(phase * (float) (Math.PI * 2.0)); // smooth 0..1..0
        float alpha = 0.70F + 0.30F * pulse;

        int x = (this.width - LOGO_WIDTH) / 2;
        int y = this.height / 4 - LOGO_HEIGHT / 2;

        RenderSystem.enableBlend();
        // Tint drifts from white towards purple at the bright end of the pulse.
        guiGraphics.setColor(1.0F - 0.18F * pulse, 1.0F - 0.32F * pulse, 1.0F, alpha);
        guiGraphics.blit(LOGO, x, y, LOGO_WIDTH, LOGO_HEIGHT, 0.0F, 0.0F,
                LOGO_TEXTURE_WIDTH, LOGO_TEXTURE_HEIGHT, LOGO_TEXTURE_WIDTH, LOGO_TEXTURE_HEIGHT);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // No-op like vanilla TitleScreen: the panorama/fallback is drawn in render() instead,
        // and the default menu background must not paint over it.
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public boolean shouldCloseOnEsc() {
        return false;
    }
}
