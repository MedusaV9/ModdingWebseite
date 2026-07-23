package dev.projecteclipse.eclipse.client.death;

import javax.annotation.Nullable;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.PoseStack;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.client.menu.EclipseMenuButton;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;

/**
 * The Quiet-Eclipse death screen (P3 §3.7 wireframe, WB-DEATH) — replaces the vanilla
 * {@code DeathScreen} via {@link DeathScreenSwap}. Anonymity by design: no score, no
 * coordinates, no killer names — only a localized cause-of-death flavor line
 * ({@code gui.eclipse.death.cause.<msgId>}, generic fallback).
 *
 * <p><b>Normal death</b> (hearts left): dimmed veil with a slow purple pulse, "DU BIST
 * GEFALLEN", the remaining heart row where the lost heart plays the 12-tick shatter
 * (reusing the {@code burst_sheet} frames at 2×), and the "Zur Reling" respawn button,
 * hold-gated with an accent progress hairline. <b>Ghost death</b> (0 hearts): the LAST
 * heart shatters big (4×), the translucent ghost-heart row fades in beneath it and the
 * button reads "Als Geist erwachen".</p>
 *
 * <p>Slow ash: one managed {@code eclipse:limbo_motes} loop emitter drifts around the
 * corpse while the screen is open (existing emitter, AMBIENT budget, removed with the
 * screen; skipped under {@code reducedFx}).</p>
 *
 * <p><b>Never blocks a respawn:</b> the button force-enables {@value #HOLD_FAILSAFE_MILLIS}
 * ms after opening no matter what the server said; the respawn click goes through the
 * plain vanilla {@code LocalPlayer.respawn()} packet; a small DIM "Hauptmenü" exit stays
 * available bottom-left (vanilla parity); and the screen closes itself if the player is
 * somehow alive again (instant-respawn gamerule, server-side respawn).</p>
 */
public final class EclipseDeathScreen extends Screen {
    /** The button becomes clickable this long after opening even if no payload arrived (15 s). */
    private static final long HOLD_FAILSAFE_MILLIS = 15_000L;

    private static final ResourceLocation BURST_SHEET =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/hearts/burst_sheet.png");
    private static final int FRAME_SIZE = 36;
    private static final int SHEET_WIDTH = FRAME_SIZE * 6;

    private static final ResourceLocation HEART_CONTAINER_SPRITE =
            ResourceLocation.withDefaultNamespace("hud/heart/container");
    private static final ResourceLocation HEART_FULL_SPRITE =
            ResourceLocation.withDefaultNamespace("hud/heart/full");

    /** Screen hearts render at 2× (18 px), the ghost centerpiece at 4× (36 px). */
    private static final int HEART_DRAW = 18;
    private static final int HEART_STEP = 20;
    private static final int GHOST_CENTER_DRAW = 36;

    /** The shatter starts this many ticks after the screen opened (a breath first). */
    private static final int SHATTER_DELAY_TICKS = 10;
    private static final int SHATTER_INTRO_TICKS = 5;
    private static final int SHATTER_FLIGHT_TICKS = 12;
    private static final int SHATTER_TOTAL_TICKS = SHATTER_INTRO_TICKS + SHATTER_FLIGHT_TICKS;
    /** Ghost variant: the ghost-heart row fades in once the big shatter has played out. */
    private static final int GHOST_ROW_FADE_START = SHATTER_DELAY_TICKS + SHATTER_TOTAL_TICKS;
    private static final int GHOST_ROW_FADE_TICKS = 16;

    private static final ResourceLocation ASH_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo_motes");

    private final long openedAtMillis = System.currentTimeMillis();
    private int ticksOpen;
    private Button respawnButton;
    @Nullable
    private ParticleEmitter ashEmitter;

    public EclipseDeathScreen() {
        super(EclipseLang.tr("gui.eclipse.death.title"));
    }

    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void init() {
        boolean ghost = DeathFlowController.deathGhost();
        respawnButton = Button.builder(
                        EclipseLang.tr(ghost ? "gui.eclipse.death.respawn.ghost" : "gui.eclipse.death.respawn"),
                        button -> respawn())
                .bounds(this.width / 2 - 100, buttonY(), 200, 20)
                .build(EclipseMenuButton::new);
        respawnButton.active = false;
        addRenderableWidget(respawnButton);

        addRenderableWidget(Button.builder(EclipseLang.tr("gui.eclipse.death.menu"), button -> exitToTitle())
                .bounds(8, this.height - 26, 78, 18)
                .build(EclipseMenuButton::new));

        if (ashEmitter == null && !EclipseClientConfig.reducedFx()
                && minecraft != null && minecraft.player != null) {
            ashEmitter = QuasarSpawner.spawnManaged(ASH_EMITTER,
                    minecraft.player.position().add(0.0D, 1.2D, 0.0D), FxBudget.Channel.AMBIENT);
        }
    }

    @Override
    public void tick() {
        ticksOpen++;
        if (minecraft == null || minecraft.player == null) {
            return;
        }
        if (minecraft.player.isAlive()) {
            // Instant-respawn gamerule or a server-side respawn beat us to it.
            minecraft.setScreen(null);
            return;
        }
        boolean holdOver = ticksOpen >= DeathFlowController.deathHoldTicks()
                || System.currentTimeMillis() - openedAtMillis >= HOLD_FAILSAFE_MILLIS;
        respawnButton.active = holdOver;
    }

    @Override
    public void removed() {
        if (ashEmitter != null) {
            try {
                if (!ashEmitter.isRemoved()) {
                    ashEmitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (LimboAmbience pattern) — dropping the reference matters.
            }
            ashEmitter = null;
        }
        super.removed();
    }

    @Override
    public boolean shouldCloseOnEsc() {
        return false; // vanilla death-screen parity: ESC never dismisses into the void
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    // ------------------------------------------------------------------ actions

    private void respawn() {
        if (minecraft == null || minecraft.player == null) {
            return;
        }
        DeathFlowController.noteRespawnClicked();
        minecraft.player.respawn(); // the plain vanilla PERFORM_RESPAWN packet — never blocked
        minecraft.setScreen(null);
    }

    /** Vanilla {@code DeathScreen.exitLevel} equivalent (safety hatch, DIM styling). */
    private void exitToTitle() {
        if (minecraft == null) {
            return;
        }
        if (minecraft.level != null) {
            minecraft.level.disconnect();
        }
        minecraft.disconnect();
        minecraft.setScreen(new TitleScreen());
    }

    // ------------------------------------------------------------------ rendering

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // Dimmed world under a slow purple pulse (never the vanilla red death gradient).
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);
        float pulse = 0.5F + 0.5F * Mth.sin((ticksOpen + partialTick) * Mth.TWO_PI / 90.0F);
        guiGraphics.fill(0, 0, this.width, this.height,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, 0.015F + pulse * 0.03F));
        drawVignette(guiGraphics, 0.05F + pulse * 0.05F);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        boolean ghost = DeathFlowController.deathGhost();
        float time = ticksOpen + partialTick;
        int centerX = this.width / 2;
        int y = this.height / 2 - 76;

        // Title at 2× accent.
        PoseStack pose = guiGraphics.pose();
        pose.pushPose();
        pose.translate(centerX, y, 0.0F);
        pose.scale(2.0F, 2.0F, 1.0F);
        Component title = EclipseLang.tr(ghost ? "gui.eclipse.death.title.ghost" : "gui.eclipse.death.title");
        guiGraphics.drawCenteredString(this.font, title, 0, 0, EclipseUiTheme.ACCENT);
        pose.popPose();

        // Cause flavor, DIM, quoted (anonymized — no names, ever).
        guiGraphics.drawCenteredString(this.font,
                Component.literal("\u00BB").append(causeLine(ghost)).append("\u00AB"),
                centerX, y + 24, EclipseUiTheme.DIM);

        if (ghost) {
            renderGhostHearts(guiGraphics, centerX, y + 42, time);
        } else {
            renderHeartRow(guiGraphics, centerX, y + 46, time);
            guiGraphics.drawCenteredString(this.font,
                    EclipseLang.tr("gui.eclipse.death.hearts_remaining",
                            DeathFlowController.deathHearts()),
                    centerX, y + 70, EclipseUiTheme.DIM);
        }

        renderHoldProgress(guiGraphics);

        guiGraphics.drawCenteredString(this.font,
                EclipseLang.tr(ghost ? "gui.eclipse.death.ship_hint.ghost" : "gui.eclipse.death.ship_hint"),
                centerX, buttonY() + 26, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, 0.9F));
    }

    /** Remaining hearts at 2× — the lost one plays the shatter, then leaves an empty container. */
    private void renderHeartRow(GuiGraphics guiGraphics, int centerX, int y, float time) {
        int hearts = Math.min(10, DeathFlowController.deathHearts());
        int lostIndex = DeathFlowController.deathLostHeartIndex();
        int slots = hearts + (lostIndex >= hearts ? 1 : 0);
        if (slots <= 0) {
            return;
        }
        int rowX = centerX - (slots * HEART_STEP - (HEART_STEP - HEART_DRAW)) / 2;
        RenderSystem.enableBlend();
        for (int i = 0; i < slots; i++) {
            int x = rowX + i * HEART_STEP;
            guiGraphics.blitSprite(HEART_CONTAINER_SPRITE, x, y, HEART_DRAW, HEART_DRAW);
            if (i == lostIndex) {
                drawShatter(guiGraphics, x, y, HEART_DRAW, time - SHATTER_DELAY_TICKS);
            } else if (i < hearts) {
                guiGraphics.blitSprite(HEART_FULL_SPRITE, x, y, HEART_DRAW, HEART_DRAW);
            }
        }
        RenderSystem.disableBlend();
    }

    /** Ghost variant: the last heart shatters BIG, the translucent ghost row fades in below. */
    private void renderGhostHearts(GuiGraphics guiGraphics, int centerX, int y, float time) {
        int bigX = centerX - GHOST_CENTER_DRAW / 2;
        RenderSystem.enableBlend();
        guiGraphics.blitSprite(HEART_CONTAINER_SPRITE, bigX, y, GHOST_CENTER_DRAW, GHOST_CENTER_DRAW);
        drawShatter(guiGraphics, bigX, y, GHOST_CENTER_DRAW, time - SHATTER_DELAY_TICKS);
        RenderSystem.disableBlend();

        float fade = Mth.clamp((time - GHOST_ROW_FADE_START) / GHOST_ROW_FADE_TICKS, 0.0F, 1.0F);
        if (fade > 0.0F) {
            int rowX = centerX - (GhostHeartsLayer.GHOST_HEART_COUNT * HEART_STEP - 2) / 2;
            for (int i = 0; i < GhostHeartsLayer.GHOST_HEART_COUNT; i++) {
                GhostHeartsLayer.drawGhostHeart(guiGraphics, rowX + i * HEART_STEP,
                        y + GHOST_CENTER_DRAW + 8, HEART_DRAW, 0.62F * fade);
            }
        }
    }

    /**
     * The burst-sheet shatter at an arbitrary scale: full heart → cracks → fading burst
     * frames (frames 0-5 of the shared 36 px sheet — same timing as the HUD overlay's
     * intro; the shard/spark flourish stays a HUD-only detail).
     */
    private void drawShatter(GuiGraphics guiGraphics, int x, int y, int size, float time) {
        if (time < 0.0F) {
            guiGraphics.blitSprite(HEART_FULL_SPRITE, x, y, size, size); // still whole, pre-beat
            return;
        }
        if (time >= SHATTER_TOTAL_TICKS) {
            return; // shattered — the empty container beneath stays
        }
        int frame;
        float alpha = 1.0F;
        if (time < 2.0F) {
            frame = 0;
        } else if (time < SHATTER_INTRO_TICKS) {
            frame = 1 + Math.min(2, Mth.floor(time - 2.0F));
        } else {
            float flight = time - SHATTER_INTRO_TICKS;
            frame = flight < 2.0F ? 4 : 5;
            alpha = Mth.clamp(1.0F - flight / SHATTER_FLIGHT_TICKS, 0.0F, 1.0F) * 0.85F;
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(BURST_SHEET, x, y, size, size,
                (float) (frame * FRAME_SIZE), 0.0F, FRAME_SIZE, FRAME_SIZE, SHEET_WIDTH, FRAME_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
    }

    /** Accent hairline under the button filling across the hold gate (the "countdown ring"). */
    private void renderHoldProgress(GuiGraphics guiGraphics) {
        if (respawnButton == null || respawnButton.active) {
            return;
        }
        float progress = Mth.clamp((float) ticksOpen / Math.max(1, DeathFlowController.deathHoldTicks()),
                0.0F, 1.0F);
        int x = respawnButton.getX();
        int y = respawnButton.getY() + respawnButton.getHeight() + 2;
        guiGraphics.fill(x, y, x + respawnButton.getWidth(), y + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.8F));
        guiGraphics.fill(x, y, x + Mth.floor(respawnButton.getWidth() * progress), y + 1,
                EclipseUiTheme.ACCENT);
    }

    private Component causeLine(boolean ghost) {
        if (ghost) {
            return EclipseLang.tr("gui.eclipse.death.flavor.ghost");
        }
        String key = "gui.eclipse.death.cause." + DeathFlowController.deathCauseKey();
        return EclipseLang.hasKey(key) ? EclipseLang.tr(key) : EclipseLang.tr("gui.eclipse.death.cause.generic");
    }

    private int buttonY() {
        return this.height / 2 + 34;
    }

    /** Soft purple edge wash (the HUD overlay's vignette shape, accent-colored). */
    private void drawVignette(GuiGraphics guiGraphics, float alpha) {
        int color = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha);
        int edge = 10;
        guiGraphics.fill(0, 0, this.width, edge, color);
        guiGraphics.fill(0, this.height - edge, this.width, this.height, color);
        guiGraphics.fill(0, edge, edge, this.height - edge, color);
        guiGraphics.fill(this.width - edge, edge, this.width, this.height - edge, color);
    }
}
