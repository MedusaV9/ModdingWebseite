package dev.projecteclipse.eclipse.client.skills;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * The custom skill-XP bar (WB-SKILLS, plan §3.9 {@code CustomXpBarLayer}): a slim 2px
 * accent strip, 182px wide like the vanilla bar, sitting 2px above the vanilla XP bar
 * (skill XP is a separate track — the vanilla bar is untouched), plus the current skill
 * level numeral in the free column right of the bar. Registered directly above
 * {@code EXPERIENCE_BAR} so the vanilla status rows (hearts/food) still draw over the
 * strip where they overlap — the strip peeks through their transparent edges instead of
 * striking through them.
 *
 * <p><b>Motion (dopamine, Quiet-Eclipse calm):</b> the displayed fill eases toward the
 * synced {@code xpIntoLevel/xpForLevel} fraction over ~6 ticks (count-up), every XP gain
 * lifts the fill color toward white for a soft 12-tick pulse and lights a leading spark
 * at the fill edge, and a level-up plays a 5-tick full-bar sweep before the bar re-fills
 * from empty on the new curve (the server curve makes early levels fill visibly faster —
 * this class only renders the synced fractions). The numeral flashes white on level-up.
 * {@code reducedFx} snaps the fill and drops pulse/spark/flash.</p>
 *
 * <p>Gates: {@code showCustomXpBar} config, F1 ({@code hideGui}), spectators, and "no
 * skill sync yet" ({@code xpForLevel <= 0} — vanilla servers never show a dead bar).
 * Cutscene HUD suppression cancels the layer via {@code LetterboxLayer}'s
 * {@code RenderGuiLayerEvent.Pre} hook (deliberately not whitelisted). Self-registered:
 * {@code EclipseGuiLayers} is frozen this wave (see the WB-SKILLS wiring doc).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SkillXpBarLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_xp_bar");

    private static final int BAR_WIDTH = 182;
    private static final int BAR_HEIGHT = 2;
    /** Bar top: 2px above the vanilla XP bar (its sprite top is at h-29). */
    private static final int BOTTOM_OFFSET = 33;
    /** Fraction of the remaining distance covered per tick (~settles in 6 ticks). */
    private static final float FILL_STEP = 0.35F;
    private static final int PULSE_TICKS = 12;
    private static final int LEVEL_SWEEP_TICKS = 5;
    private static final int LEVEL_FLASH_TICKS = 12;

    // Client tick thread only.
    private static float displayed;
    private static float displayedPrev;
    private static int pulseTicks;
    private static int sweepTicks;
    private static int flashTicks;
    private static long lastTotalXp;
    private static int lastLevel = -1;

    private SkillXpBarLayer() {}

    /** Mod-bus layer registration (nested, {@code SkillKeybind.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAbove(VanillaGuiLayers.EXPERIENCE_BAR, LAYER_ID, SkillXpBarLayer::render);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            displayed = 0.0F;
            displayedPrev = 0.0F;
            pulseTicks = 0;
            sweepTicks = 0;
            flashTicks = 0;
            lastTotalXp = 0L;
            lastLevel = -1;
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze mid-animation, like the announcement overlay
        }

        int level = ClientStateCache.skillLevel;
        long totalXp = ClientStateCache.skillTotalXp;
        float target = targetFraction();

        if (lastLevel < 0) {
            // First sync of the session: seed silently, no gain pulse for login XP.
            lastLevel = level;
            lastTotalXp = totalXp;
            displayed = target;
            displayedPrev = target;
            return;
        }

        boolean reduced = EclipseClientConfig.reducedFx();
        if (level > lastLevel) {
            // Level-up: brief full-bar sweep, then re-fill from empty on the new curve.
            sweepTicks = reduced ? 0 : LEVEL_SWEEP_TICKS;
            flashTicks = reduced ? 0 : LEVEL_FLASH_TICKS;
            displayed = 0.0F;
            displayedPrev = 0.0F;
        } else if (level < lastLevel) {
            displayed = target; // admin xp set downward — just snap, no theater
            displayedPrev = target;
        }
        if (totalXp > lastTotalXp && !reduced) {
            pulseTicks = PULSE_TICKS;
        }
        lastLevel = level;
        lastTotalXp = totalXp;

        displayedPrev = displayed;
        if (sweepTicks > 0) {
            sweepTicks--;
        } else if (reduced) {
            displayed = target;
            displayedPrev = target;
        } else {
            float delta = target - displayed;
            displayed = Math.abs(delta) < 0.002F ? target : displayed + delta * FILL_STEP;
        }
        if (pulseTicks > 0) {
            pulseTicks--;
        }
        if (flashTicks > 0) {
            flashTicks--;
        }
    }

    /** Current level progress 0..1 straight from the synced cache (server curve = truth). */
    private static float targetFraction() {
        int forLevel = ClientStateCache.skillXpForLevel;
        if (forLevel <= 0) {
            return 0.0F;
        }
        return Mth.clamp((float) ClientStateCache.skillXpIntoLevel / forLevel, 0.0F, 1.0F);
    }

    /** GUI layer body (self-registered above {@code EXPERIENCE_BAR}). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!EclipseClientConfig.showCustomXpBar()
                || minecraft.options.hideGui
                || minecraft.player == null
                || minecraft.player.isSpectator()
                || ClientStateCache.skillXpForLevel <= 0
                || lastLevel < 0) {
            return;
        }

        int barX = (guiGraphics.guiWidth() - BAR_WIDTH) / 2;
        int barY = guiGraphics.guiHeight() - BOTTOM_OFFSET;
        float partial = deltaTracker.getGameTimeDeltaPartialTick(true);

        float fill = sweepTicks > 0 ? 1.0F : Mth.lerp(partial, displayedPrev, displayed);
        fill = Mth.clamp(fill, 0.0F, 1.0F);

        // Track: quiet hairline so the strip reads as UI, not as damage to the HUD.
        guiGraphics.fill(barX, barY, barX + BAR_WIDTH, barY + BAR_HEIGHT,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.75F));

        int fillWidth = Math.round(fill * BAR_WIDTH);
        if (fillWidth > 0) {
            float pulse = pulseTicks > 0 ? (pulseTicks - partial) / PULSE_TICKS : 0.0F;
            int color = sweepTicks > 0 ? 0xFFFFFFFF
                    : lerpColor(EclipseUiTheme.ACCENT, 0xFFFFFFFF, pulse * 0.55F);
            guiGraphics.fill(barX, barY, barX + fillWidth, barY + BAR_HEIGHT, color);

            // Leading spark: a 2px bright head at the fill edge while a gain pulse runs.
            if (pulse > 0.0F && fillWidth < BAR_WIDTH) {
                guiGraphics.fill(barX + fillWidth, barY, barX + Math.min(BAR_WIDTH, fillWidth + 2),
                        barY + BAR_HEIGHT, EclipseUiTheme.withAlpha(0xFFFFFFFF, pulse));
            }
        }

        // Level numeral in the free column right of the bar (clear of the food row).
        String numeral = Integer.toString(ClientStateCache.skillLevel);
        float flash = flashTicks > 0 ? (flashTicks - partial) / LEVEL_FLASH_TICKS : 0.0F;
        int textColor = lerpColor(EclipseUiTheme.ACCENT, 0xFFFFFFFF, flash);
        guiGraphics.drawString(minecraft.font, numeral, barX + BAR_WIDTH + 4,
                barY - (minecraft.font.lineHeight - BAR_HEIGHT) / 2, textColor);
    }

    /** ARGB lerp (component-wise), t clamped 0..1. */
    private static int lerpColor(int from, int to, float t) {
        float clamped = Mth.clamp(t, 0.0F, 1.0F);
        int a = Math.round(Mth.lerp(clamped, (from >>> 24) & 0xFF, (to >>> 24) & 0xFF));
        int r = Math.round(Mth.lerp(clamped, (from >>> 16) & 0xFF, (to >>> 16) & 0xFF));
        int g = Math.round(Mth.lerp(clamped, (from >>> 8) & 0xFF, (to >>> 8) & 0xFF));
        int b = Math.round(Mth.lerp(clamped, from & 0xFF, to & 0xFF));
        return (a << 24) | (r << 16) | (g << 8) | b;
    }
}
