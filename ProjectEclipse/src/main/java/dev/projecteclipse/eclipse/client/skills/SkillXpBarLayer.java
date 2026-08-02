package dev.projecteclipse.eclipse.client.skills;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
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
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * The custom skill-XP bar (WB-SKILLS §3.9, reworked by PLAN-A A9): it REPLACES the vanilla
 * XP bar instead of stacking above it. While the replacement is active this class cancels
 * the vanilla {@code EXPERIENCE_BAR} and {@code EXPERIENCE_LEVEL} layers via
 * {@link RenderGuiLayerEvent.Pre} and renders the skill bar in the vanilla slot
 * (182px wide, centered, {@code guiHeight - 29..-24} band) with the skill level numeral
 * centered above it in the vanilla level position — mod styling (theme colors, odometer
 * level carry) retained.
 *
 * <p><b>Motion (dopamine, Quiet-Eclipse calm):</b> the displayed fill eases toward the
 * synced {@code xpIntoLevel/xpForLevel} fraction over ~6 ticks (count-up), every XP gain
 * lifts the fill color toward white for a soft 12-tick pulse and lights a leading spark
 * at the fill edge, and a level-up plays a 5-tick specular sweep (a bright band crossing
 * the accent bar) before the bar re-fills from empty on the new curve (the server curve
 * makes early levels fill visibly faster — this class only renders the synced fractions).
 * Multi-level gains queue one sweep per level (cap 3, W4-FEEL IDEA-05 #3) and the level
 * numeral odometer-increments once per sweep, flashing white each step. {@code reducedFx}
 * snaps the fill and drops pulse/spark/flash/carry.</p>
 *
 * <p>Gates (A9): {@code showCustomXpBar} config, F1 ({@code hideGui}), spectators, "no
 * skill sync yet" ({@code xpForLevel <= 0} — vanilla servers never show a dead bar),
 * pre-event ({@code !ClientStateCache.eventStarted}, the A8 §0.1 contract flag — vanilla
 * stays uncancelled and the mod bar hidden until the start event ran), and riding
 * ({@code player.jumpableVehicle() != null} — nothing is cancelled so the vanilla jump
 * meter owns the slot exactly like vanilla; vehicle-health rows are untouched anyway).
 * Cutscene HUD suppression cancels the layer via {@code LetterboxLayer}'s
 * {@code RenderGuiLayerEvent.Pre} hook (deliberately not whitelisted). Self-registered:
 * {@code EclipseGuiLayers} is frozen this wave (see the WB-SKILLS wiring doc).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SkillXpBarLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_xp_bar");

    private static final int BAR_WIDTH = 182;
    /** A9: the bar fills the whole vanilla XP-bar band (5px, sprite-exact). */
    private static final int BAR_HEIGHT = 5;
    /** Bar top: the vanilla XP-bar sprite top ({@code guiHeight - 32 + 3}). */
    private static final int BOTTOM_OFFSET = 29;
    /** Level numeral baseline: the vanilla level position ({@code guiHeight - 31 - 4}). */
    private static final int LEVEL_BOTTOM_OFFSET = 35;
    /** Fraction of the remaining distance covered per tick (~settles in 6 ticks). */
    private static final float FILL_STEP = 0.35F;
    private static final int PULSE_TICKS = 12;
    private static final int LEVEL_SWEEP_TICKS = 5;
    private static final int LEVEL_FLASH_TICKS = 12;
    /** Multi-level carry (W4-FEEL, IDEA-05 #3): at most this many queued sweeps. */
    private static final int MAX_CARRY_SWEEPS = 3;
    /** Carry sweeps 2/3 re-pitch the level-up sting a semitone-ish step each. */
    private static final float[] SWEEP_PITCHES = {1.0F, 1.06F, 1.12F};
    /** Specular band half-widths (px) and alphas, stacked bright core over soft skirt. */
    private static final int[] BAND_HALF_WIDTHS = {7, 4, 2};
    private static final float[] BAND_ALPHAS = {0.30F, 0.55F, 0.95F};
    /**
     * WAVE6 (F-106 C) — C7: the "+n" gain chip lives this many GAME ticks (gameTime-based
     * envelope: at {@code /tick rate 2} it stretches to ~6 real seconds — photographable —
     * instead of blinking away on the 20 Hz client clock).
     */
    private static final int CHIP_TICKS = 12;
    /** Total upward drift of the chip over its envelope (px). */
    private static final int CHIP_RISE_PX = 8;

    // Client tick thread only.
    private static float displayed;
    private static float displayedPrev;
    private static int pulseTicks;
    private static int sweepTicks;
    private static int flashTicks;
    /** Sweeps still owed (incl. the running one); numeral shown = level - pendingSweeps. */
    private static int pendingSweeps;
    /** Index of the running sweep within its chain (pitch lookup, clamped to 2). */
    private static int sweepChainIndex;
    private static long lastTotalXp;
    private static int lastLevel = -1;
    /** C7 chip state: summed gain while the envelope is live; 0 = no chip. */
    private static long chipAmount;
    private static long chipStartGameTime;

    private SkillXpBarLayer() {}

    /**
     * Mod-bus layer registration (nested, {@code SkillKeybind.Registrar} pattern).
     * Registered directly above {@code EXPERIENCE_BAR}: that IS the vanilla slot in the
     * layer order — the vanilla bar itself is cancelled by {@link #onRenderGuiLayerPre}
     * while the replacement is active, so exactly one bar ever occupies the slot.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAbove(VanillaGuiLayers.EXPERIENCE_BAR, LAYER_ID, SkillXpBarLayer::render);
        }
    }

    /**
     * A9 replacement gate — one truth for both the vanilla-cancel hook and {@link #render},
     * so the vanilla bar is never hidden without ours actually taking the slot.
     */
    private static boolean replacingVanillaBar(Minecraft minecraft) {
        return EclipseClientConfig.showCustomXpBar()
                && minecraft.level != null
                && minecraft.player != null
                && !minecraft.player.isSpectator()
                && ClientStateCache.eventStarted
                && ClientStateCache.skillXpForLevel > 0
                && lastLevel >= 0
                && minecraft.player.jumpableVehicle() == null;
    }

    /**
     * Cancels the vanilla {@code EXPERIENCE_BAR} + {@code EXPERIENCE_LEVEL} layers while
     * the skill bar owns the slot (game bus). Riding is excluded by the gate — the vanilla
     * jump meter (its own {@code JUMP_METER} layer) works exactly as before.
     */
    @SubscribeEvent
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (!event.getName().equals(VanillaGuiLayers.EXPERIENCE_BAR)
                && !event.getName().equals(VanillaGuiLayers.EXPERIENCE_LEVEL)) {
            return;
        }
        if (replacingVanillaBar(Minecraft.getInstance())) {
            event.setCanceled(true);
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
            pendingSweeps = 0;
            sweepChainIndex = 0;
            lastTotalXp = 0L;
            lastLevel = -1;
            chipAmount = 0L;
            chipStartGameTime = 0L;
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
            // Level-up: one full-bar sweep per level gained (cap 3 — IDEA-05 #3 carry),
            // then re-fill from empty on the new curve. The numeral odometer-increments
            // once per sweep (render shows level - pendingSweeps).
            if (reduced) {
                pendingSweeps = 0;
                sweepTicks = 0;
                flashTicks = 0;
            } else {
                pendingSweeps = Math.min(MAX_CARRY_SWEEPS,
                        pendingSweeps + (level - lastLevel));
                if (sweepTicks <= 0) {
                    sweepTicks = LEVEL_SWEEP_TICKS;
                    sweepChainIndex = 0;
                }
                flashTicks = LEVEL_FLASH_TICKS;
            }
            displayed = 0.0F;
            displayedPrev = 0.0F;
        } else if (level < lastLevel) {
            displayed = target; // admin xp set downward — just snap, no theater
            displayedPrev = target;
            pendingSweeps = 0;
            sweepTicks = 0;
        }
        if (totalXp > lastTotalXp && !reduced) {
            pulseTicks = PULSE_TICKS;
            // WAVE6 (F-106 C) — C7: arm/refresh the "+n" chip. Gains landing while a chip
            // is still live sum into it (one readable number, no chip stacks); reducedFx
            // skips the chip entirely (same gate as the pulse).
            long gained = totalXp - lastTotalXp;
            long gameTime = minecraft.level.getGameTime();
            boolean chipLive = chipAmount > 0 && gameTime - chipStartGameTime < CHIP_TICKS;
            chipAmount = (chipLive ? chipAmount : 0L) + gained;
            chipStartGameTime = gameTime;
            EclipseMod.LOGGER.debug("[w6c-xpchip] delta={}", gained);
        }
        lastLevel = level;
        lastTotalXp = totalXp;

        displayedPrev = displayed;
        if (sweepTicks > 0) {
            sweepTicks--;
            if (sweepTicks == 0) {
                pendingSweeps = Math.max(0, pendingSweeps - 1);
                if (reduced) {
                    pendingSweeps = 0; // toggled mid-chain: snap, no further theater
                } else if (pendingSweeps > 0) {
                    // Carry: chain the next sweep; the sting arpeggiates up per sweep
                    // (the first sweep's audio is LevelUpOverlay's own levelUp()).
                    sweepTicks = LEVEL_SWEEP_TICKS;
                    sweepChainIndex = Math.min(SWEEP_PITCHES.length - 1, sweepChainIndex + 1);
                    flashTicks = LEVEL_FLASH_TICKS;
                    UiSounds.levelUp(SWEEP_PITCHES[sweepChainIndex]);
                }
            }
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

    /** GUI layer body (self-registered above {@code EXPERIENCE_BAR} = the vanilla slot). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.options.hideGui || !replacingVanillaBar(minecraft)) {
            return;
        }

        int barX = (guiGraphics.guiWidth() - BAR_WIDTH) / 2;
        int barY = guiGraphics.guiHeight() - BOTTOM_OFFSET;
        float partial = deltaTracker.getGameTimeDeltaPartialTick(true);

        float fill = sweepTicks > 0 ? 1.0F : Mth.lerp(partial, displayedPrev, displayed);
        fill = Mth.clamp(fill, 0.0F, 1.0F);

        // Track (A9, vanilla-slot width): a quiet dark bed filling the vanilla band with a
        // 1px hairline top edge — reads as Eclipse UI in the exact place the vanilla bar sat.
        guiGraphics.fill(barX, barY, barX + BAR_WIDTH, barY + BAR_HEIGHT,
                EclipseUiTheme.withAlpha(0xFF140A24, 0.85F));
        guiGraphics.fill(barX, barY, barX + BAR_WIDTH, barY + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.6F));

        int fillWidth = Math.round(fill * BAR_WIDTH);
        if (fillWidth > 0) {
            if (sweepTicks > 0) {
                // Specular sweep (IDEA-05 #3): the bar holds accent while a bright band
                // travels left-to-right, visibly "spending" the overflow.
                guiGraphics.fill(barX, barY, barX + fillWidth, barY + BAR_HEIGHT,
                        EclipseUiTheme.ACCENT);
                float sweepProgress = Mth.clamp(
                        1.0F - (sweepTicks - partial) / LEVEL_SWEEP_TICKS, 0.0F, 1.0F);
                int center = barX + Math.round(sweepProgress * BAR_WIDTH);
                for (int i = 0; i < BAND_HALF_WIDTHS.length; i++) {
                    int x0 = Math.max(barX, center - BAND_HALF_WIDTHS[i]);
                    int x1 = Math.min(barX + BAR_WIDTH, center + BAND_HALF_WIDTHS[i]);
                    if (x1 > x0) {
                        guiGraphics.fill(x0, barY, x1, barY + BAR_HEIGHT,
                                EclipseUiTheme.withAlpha(0xFFFFFFFF, BAND_ALPHAS[i]));
                    }
                }
            } else {
                float pulse = pulseTicks > 0 ? (pulseTicks - partial) / PULSE_TICKS : 0.0F;
                int color = lerpColor(EclipseUiTheme.ACCENT, 0xFFFFFFFF, pulse * 0.55F);
                guiGraphics.fill(barX, barY, barX + fillWidth, barY + BAR_HEIGHT, color);

                // Leading spark: a 2px bright head at the fill edge while a gain pulse runs.
                if (pulse > 0.0F && fillWidth < BAR_WIDTH) {
                    guiGraphics.fill(barX + fillWidth, barY,
                            barX + Math.min(BAR_WIDTH, fillWidth + 2),
                            barY + BAR_HEIGHT, EclipseUiTheme.withAlpha(0xFFFFFFFF, pulse));
                }
            }
        }

        // A9: skill level numeral centered above the bar in the vanilla level position
        // (vanilla EXPERIENCE_LEVEL is cancelled while we own the slot), with the vanilla
        // 4-way dark outline for readability over world pixels but mod accent coloring.
        // Odometer carry (IDEA-05 #3): each pending sweep still owes one increment; like
        // vanilla, level 0 draws no numeral.
        int shownLevel = Math.max(0, ClientStateCache.skillLevel - pendingSweeps);
        if (shownLevel > 0) {
            String numeral = Integer.toString(shownLevel);
            float flash = flashTicks > 0 ? (flashTicks - partial) / LEVEL_FLASH_TICKS : 0.0F;
            int textColor = lerpColor(EclipseUiTheme.ACCENT, 0xFFFFFFFF, flash);
            int textX = (guiGraphics.guiWidth() - minecraft.font.width(numeral)) / 2;
            int textY = guiGraphics.guiHeight() - LEVEL_BOTTOM_OFFSET;
            guiGraphics.drawString(minecraft.font, numeral, textX + 1, textY, 0xFF000000, false);
            guiGraphics.drawString(minecraft.font, numeral, textX - 1, textY, 0xFF000000, false);
            guiGraphics.drawString(minecraft.font, numeral, textX, textY + 1, 0xFF000000, false);
            guiGraphics.drawString(minecraft.font, numeral, textX, textY - 1, 0xFF000000, false);
            guiGraphics.drawString(minecraft.font, numeral, textX, textY, textColor, false);
        }

        // WAVE6 (F-106 C) — C7: the "+n" gain chip rises off the bar's right end and fades
        // over a {@value #CHIP_TICKS}-GAME-tick envelope (gameTime + its partial, so slow
        // tick rates stretch it in real time instead of snapping). reducedFx never arms it.
        if (chipAmount > 0 && minecraft.level != null && !EclipseClientConfig.reducedFx()) {
            float age = (minecraft.level.getGameTime() - chipStartGameTime) + partial;
            if (age >= 0.0F && age < CHIP_TICKS) {
                float t = age / CHIP_TICKS;
                String chip = "+" + chipAmount;
                int chipX = barX + BAR_WIDTH - minecraft.font.width(chip);
                int chipY = barY - 10 - Math.round(t * CHIP_RISE_PX);
                guiGraphics.drawString(minecraft.font, chip, chipX, chipY,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.GOOD, 1.0F - t), true);
            }
        }
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
