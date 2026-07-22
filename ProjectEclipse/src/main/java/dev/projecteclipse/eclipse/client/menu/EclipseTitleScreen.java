package dev.projecteclipse.eclipse.client.menu;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Random;

import javax.annotation.Nullable;

import com.mojang.authlib.minecraft.BanDetails;
import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.SharedConstants;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
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
 * Eclipse title screen v2: the v1 cube map now turns at a deliberately slow cinematic
 * pace, with three independently drifting cloud layers, mouse parallax, screen-space
 * wisps, a vignette and a periodic eclipse flare across the logo. The vanilla
 * singleplayer/multiplayer/options/quit flows remain unchanged.
 */
@OnlyIn(Dist.CLIENT)
public class EclipseTitleScreen extends Screen {
    private static final String TITLE_TEXTURE_ROOT = "textures/gui/title/";
    private static final String PANORAMA_BASE_PATH = TITLE_TEXTURE_ROOT + "panorama";
    private static final ResourceLocation LOGO = titleTexture("logo.png");
    private static final ResourceLocation FLARE = titleTexture("flare_sweep.png");
    private static final ResourceLocation WISP = titleTexture("wisp.png");
    private static final ResourceLocation GEAR = titleTexture("gear.png");
    private static final ResourceLocation FALLBACK_BACKGROUND = titleTexture("background.png");
    private static final ResourceLocation[] PARALLAX = {
            titleTexture("parallax_far.png"),
            titleTexture("parallax_mid.png"),
            titleTexture("parallax_near.png")
    };

    private static final CubeMap CUBE_MAP =
            new CubeMap(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, PANORAMA_BASE_PATH));
    private static final PanoramaRenderer PANORAMA = new SlowPanoramaRenderer(CUBE_MAP);

    private static final int LOGO_TEXTURE_WIDTH = 512;
    private static final int LOGO_TEXTURE_HEIGHT = 160;
    private static final int LOGO_WIDTH = 256;
    private static final int LOGO_HEIGHT = 80;
    private static final int BACKGROUND_TEXTURE_WIDTH = 1024;
    private static final int BACKGROUND_TEXTURE_HEIGHT = 576;
    private static final int PARALLAX_TEXTURE_WIDTH = 1024;
    private static final int PARALLAX_TEXTURE_HEIGHT = 512;
    private static final int WISP_TEXTURE_SIZE = 32;
    private static final int FLARE_TEXTURE_WIDTH = 512;
    private static final int FLARE_TEXTURE_HEIGHT = 128;

    private static final long LOGO_PULSE_PERIOD_MS = 4000L;
    private static final long FLARE_PERIOD_MS = 12000L;
    private static final float FLARE_ACTIVE_FRACTION = 0.18F;
    private static final int BUTTON_WIDTH = 200;
    private static final int BUTTON_HEIGHT = 20;
    private static final int BUTTON_SPACING = 24;
    private static final int MAX_WISPS = 40;

    private final List<MenuWisp> wisps = new ArrayList<>();
    private final Random random = new Random();
    private boolean panoramaUsable;
    private int nextWispTicks;

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

        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.settings.title"),
                        button -> this.minecraft.setScreen(new EclipseSettingsScreen(this)))
                .bounds(x + BUTTON_WIDTH + 6, y + BUTTON_SPACING * 2, BUTTON_HEIGHT, BUTTON_HEIGHT)
                .tooltip(Tooltip.create(Component.translatable("gui.eclipse.settings.open")))
                .build(builder -> new EclipseMenuButton(builder, GEAR, 48, 48)));

        addRenderableWidget(Button.builder(Component.translatable("menu.quit"),
                        button -> this.minecraft.stop())
                .bounds(x, y + BUTTON_SPACING * 3, BUTTON_WIDTH, BUTTON_HEIGHT)
                .build(EclipseMenuButton::new));
    }

    @Override
    public void tick() {
        super.tick();
        if (EclipseClientConfig.reducedFx()) {
            wisps.clear();
            return;
        }
        if (--nextWispTicks <= 0 && wisps.size() < MAX_WISPS) {
            spawnWisp();
            nextWispTicks = 10 + random.nextInt(11); // one mote every 0.5–1.0 seconds
        }
        for (Iterator<MenuWisp> iterator = wisps.iterator(); iterator.hasNext();) {
            MenuWisp wisp = iterator.next();
            wisp.tick();
            if (wisp.age >= wisp.maxAge || wisp.y < -wisp.size) {
                iterator.remove();
            }
        }
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

    /** All six cube-map faces must resolve, otherwise we blit the static v1 fallback. */
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

        float mouseParallaxX = EclipseClientConfig.reducedFx()
                ? 0.0F
                : Mth.clamp(mouseX / Math.max(1.0F, this.width) * 2.0F - 1.0F, -1.0F, 1.0F);
        float mouseParallaxY = EclipseClientConfig.reducedFx()
                ? 0.0F
                : Mth.clamp(mouseY / Math.max(1.0F, this.height) * 2.0F - 1.0F, -1.0F, 1.0F);

        renderParallaxLayer(guiGraphics, PARALLAX[0], mouseParallaxX, mouseParallaxY, 2.0F, 2.0F, 0.36F);
        renderParallaxLayer(guiGraphics, PARALLAX[1], mouseParallaxX, mouseParallaxY, 4.0F, 5.0F, 0.48F);
        renderParallaxLayer(guiGraphics, PARALLAX[2], mouseParallaxX, mouseParallaxY, 8.0F, 10.0F, 0.56F);
        renderWisps(guiGraphics, partialTick);
        renderVignette(guiGraphics);
        renderLogo(guiGraphics);

        super.render(guiGraphics, mouseX, mouseY, partialTick);
        renderFooter(guiGraphics);
        CursorManager.endFrame();
    }

    private void renderEclipseBackground(GuiGraphics guiGraphics, float partialTick) {
        if (this.panoramaUsable) {
            try {
                PANORAMA.render(guiGraphics, this.width, this.height, 1.0F, partialTick);
                return;
            } catch (RuntimeException e) {
                this.panoramaUsable = false;
                EclipseMod.LOGGER.warn("Eclipse title panorama failed to render, using static background", e);
            }
        }
        guiGraphics.blit(FALLBACK_BACKGROUND, 0, 0, this.width, this.height, 0.0F, 0.0F,
                BACKGROUND_TEXTURE_WIDTH, BACKGROUND_TEXTURE_HEIGHT,
                BACKGROUND_TEXTURE_WIDTH, BACKGROUND_TEXTURE_HEIGHT);
    }

    /**
     * Repeats one transparent 2:1 cloud plate across the screen. Wall-clock drift gives
     * the far/mid/near layers distinct speeds; the mouse shifts them oppositely by 2/4/8px.
     */
    private void renderParallaxLayer(GuiGraphics guiGraphics, ResourceLocation texture,
            float mouseX, float mouseY, float mouseDepth, float speedPixelsPerSecond, float alpha) {
        int margin = 12;
        int tileWidth = this.width + margin * 2;
        int tileHeight = this.height + margin * 2;
        float seconds = EclipseClientConfig.reducedFx() ? 0.0F : Util.getMillis() / 1000.0F;
        int drift = Mth.floor(seconds * speedPixelsPerSecond) % Math.max(1, tileWidth);
        int parallaxX = -Math.round(mouseX * mouseDepth);
        int parallaxY = -Math.round(mouseY * mouseDepth * 0.5F);
        int firstX = -margin - drift + parallaxX;
        int y = -margin + parallaxY;

        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        for (int i = 0; i < 3; i++) {
            guiGraphics.blit(texture, firstX + i * tileWidth, y, tileWidth, tileHeight,
                    0.0F, 0.0F, PARALLAX_TEXTURE_WIDTH, PARALLAX_TEXTURE_HEIGHT,
                    PARALLAX_TEXTURE_WIDTH, PARALLAX_TEXTURE_HEIGHT);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    private void spawnWisp() {
        float size = 5.0F + random.nextFloat() * 8.0F;
        float x = random.nextFloat() * Math.max(1, this.width);
        float y = this.height * (0.52F + random.nextFloat() * 0.52F);
        float velocityX = (random.nextFloat() - 0.5F) * 0.10F;
        float velocityY = -(0.18F + random.nextFloat() * 0.28F);
        int maxAge = 120 + random.nextInt(121);
        wisps.add(new MenuWisp(x, y, velocityX, velocityY, size, maxAge, random.nextFloat() * 6.28318F));
    }

    private void renderWisps(GuiGraphics guiGraphics, float partialTick) {
        if (wisps.isEmpty()) {
            return;
        }
        RenderSystem.enableBlend();
        for (MenuWisp wisp : wisps) {
            float life = Mth.clamp((wisp.age + partialTick) / wisp.maxAge, 0.0F, 1.0F);
            float alpha = Mth.sin(life * Mth.PI) * 0.72F;
            float sway = Mth.sin(wisp.phase + (wisp.age + partialTick) * 0.055F) * 3.0F;
            int size = Math.max(2, Math.round(wisp.size));
            int x = Math.round(wisp.x + wisp.velocityX * partialTick + sway - size / 2.0F);
            int y = Math.round(wisp.y + wisp.velocityY * partialTick - size / 2.0F);
            guiGraphics.setColor(0.88F, 0.68F, 1.0F, alpha);
            guiGraphics.blit(WISP, x, y, size, size, 0.0F, 0.0F,
                    WISP_TEXTURE_SIZE, WISP_TEXTURE_SIZE, WISP_TEXTURE_SIZE, WISP_TEXTURE_SIZE);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
    }

    /** A soft screen-edge vignette plus bottom readability gradient. */
    private void renderVignette(GuiGraphics guiGraphics) {
        int edge = Math.max(20, this.height / 7);
        guiGraphics.fillGradient(0, 0, this.width, edge, 0x76000000, 0x00000000);
        guiGraphics.fillGradient(0, this.height - edge, this.width, this.height, 0x00000000, 0xA0000000);
        int sideWidth = Math.max(16, this.width / 12);
        for (int i = 0; i < 6; i++) {
            int alpha = 38 - i * 6;
            int band = Math.max(1, sideWidth / 6);
            int color = alpha << 24;
            guiGraphics.fill(i * band, 0, (i + 1) * band, this.height, color);
            guiGraphics.fill(this.width - (i + 1) * band, 0, this.width - i * band, this.height, color);
        }
    }

    /** Logo pulse plus a bright horizontal flare that crosses it once every twelve seconds. */
    private void renderLogo(GuiGraphics guiGraphics) {
        float phase = (Util.getMillis() % LOGO_PULSE_PERIOD_MS) / (float) LOGO_PULSE_PERIOD_MS;
        float pulse = 0.5F - 0.5F * Mth.cos(phase * (float) (Math.PI * 2.0));
        float alpha = 0.76F + 0.24F * pulse;
        int x = (this.width - LOGO_WIDTH) / 2;
        int y = this.height / 4 - LOGO_HEIGHT / 2;

        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F - 0.12F * pulse, 1.0F - 0.24F * pulse, 1.0F, alpha);
        guiGraphics.blit(LOGO, x, y, LOGO_WIDTH, LOGO_HEIGHT, 0.0F, 0.0F,
                LOGO_TEXTURE_WIDTH, LOGO_TEXTURE_HEIGHT, LOGO_TEXTURE_WIDTH, LOGO_TEXTURE_HEIGHT);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);

        if (!EclipseClientConfig.reducedFx()) {
            float flarePhase = (Util.getMillis() % FLARE_PERIOD_MS) / (float) FLARE_PERIOD_MS;
            if (flarePhase < FLARE_ACTIVE_FRACTION) {
                float sweep = flarePhase / FLARE_ACTIVE_FRACTION;
                float eased = sweep * sweep * (3.0F - 2.0F * sweep);
                int flareWidth = LOGO_WIDTH / 2;
                int flareHeight = LOGO_HEIGHT / 2;
                int flareX = Math.round(Mth.lerp(eased, x - flareWidth, x + LOGO_WIDTH));
                int flareY = y + (LOGO_HEIGHT - flareHeight) / 2;
                guiGraphics.enableScissor(x, y, x + LOGO_WIDTH, y + LOGO_HEIGHT);
                guiGraphics.setColor(1.0F, 0.90F, 1.0F, Mth.sin(sweep * Mth.PI) * 0.88F);
                guiGraphics.blit(FLARE, flareX, flareY, flareWidth, flareHeight, 0.0F, 0.0F,
                        FLARE_TEXTURE_WIDTH, FLARE_TEXTURE_HEIGHT,
                        FLARE_TEXTURE_WIDTH, FLARE_TEXTURE_HEIGHT);
                guiGraphics.disableScissor();
                guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
            }
        }
        RenderSystem.disableBlend();
    }

    private void renderFooter(GuiGraphics guiGraphics) {
        guiGraphics.drawString(this.font, "Minecraft " + SharedConstants.getCurrentVersion().getName(),
                2, this.height - 10, 0xFFD7CEE8);
        Component tagline = Component.translatable("gui.eclipse.title.tagline");
        guiGraphics.drawString(this.font, tagline,
                this.width - this.font.width(tagline) - 2, this.height - 10, 0xFFB98CFF);
        Component disclaimer = Component.translatable("gui.eclipse.title.disclaimer");
        guiGraphics.drawCenteredString(this.font, disclaimer, this.width / 2, this.height - 20, 0xAA9A8FB8);
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // No-op like vanilla TitleScreen: render() owns the panorama and all overlays.
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public boolean shouldCloseOnEsc() {
        return false;
    }

    /** ALWAYS return the system cursor when another screen replaces the title. */
    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

    private static ResourceLocation titleTexture(String file) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, TITLE_TEXTURE_ROOT + file);
    }

    private static final class MenuWisp {
        float x;
        float y;
        final float velocityX;
        final float velocityY;
        final float size;
        final int maxAge;
        final float phase;
        int age;

        MenuWisp(float x, float y, float velocityX, float velocityY, float size, int maxAge, float phase) {
            this.x = x;
            this.y = y;
            this.velocityX = velocityX;
            this.velocityY = velocityY;
            this.size = size;
            this.maxAge = maxAge;
            this.phase = phase;
        }

        void tick() {
            x += velocityX;
            y += velocityY;
            age++;
        }
    }

    /**
     * Vanilla's {@link PanoramaRenderer} replaces a non-zero partial tick with real-time
     * delta internally, so scaling the argument cannot slow it down. This tiny subclass
     * keeps the same CubeMap/overlay pipeline but advances at 18% of vanilla's spin rate.
     */
    private static final class SlowPanoramaRenderer extends PanoramaRenderer {
        private static final float SPIN_PER_REALTIME_TICK = 0.018F;
        private final CubeMap cubeMap;
        private float spin;

        SlowPanoramaRenderer(CubeMap cubeMap) {
            super(cubeMap);
            this.cubeMap = cubeMap;
        }

        @Override
        public void render(GuiGraphics guiGraphics, int width, int height, float fade, float partialTick) {
            Minecraft minecraft = Minecraft.getInstance();
            float delta = partialTick == 0.0F ? 0.0F : minecraft.getTimer().getRealtimeDeltaTicks();
            spin = wrap(spin + delta * minecraft.options.panoramaSpeed().get().floatValue()
                    * SPIN_PER_REALTIME_TICK, 360.0F);
            cubeMap.render(minecraft, 10.0F, -spin, fade);
            RenderSystem.enableBlend();
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, fade);
            guiGraphics.blit(PanoramaRenderer.PANORAMA_OVERLAY, 0, 0, width, height,
                    0.0F, 0.0F, 16, 128, 16, 128);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
            RenderSystem.disableBlend();
            RenderSystem.disableDepthTest();
        }

        private static float wrap(float value, float max) {
            return value > max ? value - max : value;
        }
    }
}
