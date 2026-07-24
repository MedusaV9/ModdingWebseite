package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayDeque;
import java.util.concurrent.ThreadLocalRandom;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.boss.BossPayloads;
import dev.projecteclipse.eclipse.network.boss.BossPayloads.S2CBossIntroPayload;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

/**
 * Boss intro title card (IDEA-16 #1), client half of
 * {@link S2CBossIntroPayload}: the boss name arrives corrupted and resolves. A centered
 * cinematic band in the upper third shows the name at 2x scale, starting as
 * {@link GlitchText#scramble} noise and locking in one real character every
 * {@value #TICKS_PER_CHAR}t left to right (random per-client salt so two viewers never
 * sync); the epithet subtitle types in underneath during the hold. Visual language is
 * {@code THEME_BOSS}: near-black scrim, breathing {@link EclipseUiTheme#DANGER} hairlines.
 *
 * <p>Deliberately separate from {@link AnnouncementOverlay} (different owner, different
 * stack): this renders from {@link RenderGuiEvent.Post}, so it survives the cutscene
 * letterbox's GUI-layer suppression — boss intros often play UNDER the letterbox. Only F1
 * ({@code hideGui}) hides it. Incoming intros queue (cap {@value #QUEUE_LIMIT}); with
 * {@code reducedFx} the noise is {@code GlitchText}'s calm static run and the hairline
 * breathing stops.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BossIntroOverlay {
    /** One real character locks in every this many ticks. */
    private static final int TICKS_PER_CHAR = 2;
    /** Pure-noise flare before the first character locks. */
    private static final int PRE_TICKS = 10;
    /** Hold after the full name locked (subtitle types during this window). */
    private static final int HOLD_TICKS = 70;
    private static final int FADE_TICKS = 20;
    private static final int QUEUE_LIMIT = 3;
    /** DANGER→TEXT flash length right after the name locks completely. */
    private static final int LOCK_FLASH_TICKS = 12;
    /** Band paddings around the two text lines (logical px). */
    private static final int BAND_PAD_TOP = 12;
    private static final int BAND_PAD_BOTTOM = 10;

    static {
        // Payload consumer seam (GatePayloads pattern): installed on client class-load, so
        // BossPayloads itself never references client classes.
        BossPayloads.setClientIntroHandler(BossIntroOverlay::handle);
    }

    /** Client thread only. */
    private static final ArrayDeque<S2CBossIntroPayload> QUEUE = new ArrayDeque<>();

    private static String name = "";
    private static String subtitle = "";
    private static int glitchSalt;
    /** Ticks since the active card started; {@code -1} = no card running. */
    private static int ticks = -1;
    private static boolean lockSoundPlayed;

    private BossIntroOverlay() {}

    /** {@link S2CBossIntroPayload} entry point (client main thread). */
    public static void handle(S2CBossIntroPayload payload) {
        if (QUEUE.size() < QUEUE_LIMIT) {
            QUEUE.add(payload);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            ticks = -1;
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze mid-card like the announcement overlay; the queue stays intact
        }
        if (ticks < 0 && !QUEUE.isEmpty()) {
            start(QUEUE.poll());
        }
        if (ticks < 0) {
            return;
        }
        ticks++;
        int decodeEnd = decodeEndTick();
        if (ticks <= decodeEnd) {
            // Decode tick every 2nd locked character, pitch climbing as the name resolves.
            int locked = lockedChars(ticks);
            if (locked > 0 && locked % 2 == 0 && locked != lockedChars(ticks - 1)) {
                UiSounds.typewriter(0.7F + 0.6F * locked / Math.max(1, name.length()));
            }
            if (!lockSoundPlayed && locked >= name.length()) {
                lockSoundPlayed = true;
                UiSounds.timerZero(); // dark glitch-boom as the name snaps true
            }
        }
        if (ticks > decodeEnd + HOLD_TICKS + FADE_TICKS) {
            ticks = -1;
        }
    }

    private static void start(S2CBossIntroPayload payload) {
        name = EclipseLang.tr(payload.nameKey()).getString();
        subtitle = payload.subtitleKey().isEmpty() ? ""
                : EclipseLang.tr(payload.subtitleKey()).getString();
        glitchSalt = ThreadLocalRandom.current().nextInt();
        ticks = 0;
        lockSoundPlayed = false;
        UiSounds.error(); // arrival glitch burst
    }

    /** Tick at which the last character locks (end of the decode phase). */
    private static int decodeEndTick() {
        return PRE_TICKS + name.length() * TICKS_PER_CHAR;
    }

    /** How many leading characters show as real text at the given card tick. */
    private static int lockedChars(int atTick) {
        return Mth.clamp((atTick - PRE_TICKS) / TICKS_PER_CHAR, 0, name.length());
    }

    @SubscribeEvent
    static void onRenderGui(RenderGuiEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (ticks < 0 || minecraft.level == null || minecraft.options.hideGui || name.isEmpty()) {
            return;
        }
        GuiGraphics guiGraphics = event.getGuiGraphics();
        DeltaTracker deltaTracker = event.getPartialTick();
        float t = ticks + deltaTracker.getGameTimeDeltaPartialTick(true);
        int decodeEnd = decodeEndTick();
        float alpha = t <= decodeEnd + HOLD_TICKS ? 1.0F
                : Mth.clamp(1.0F - (t - decodeEnd - HOLD_TICKS) / FADE_TICKS, 0.0F, 1.0F);
        if (alpha < 0.03F) {
            return;
        }

        Minecraft mc = minecraft;
        int centerX = guiGraphics.guiWidth() / 2;
        int nameTop = guiGraphics.guiHeight() / 4; // upper third, clear of crosshair + bossbars
        boolean reduced = EclipseClientConfig.reducedFx();

        // --- cinematic band: full-width scrim + breathing DANGER hairlines (THEME_BOSS) ---
        int bandTop = nameTop - BAND_PAD_TOP;
        int bandBottom = nameTop + 18 + (subtitle.isEmpty() ? 0 : 14) + BAND_PAD_BOTTOM;
        guiGraphics.fill(0, bandTop, guiGraphics.guiWidth(), bandBottom,
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        float breathe = reduced ? 0.6F
                : 0.45F + 0.35F * Mth.sin((float) (System.currentTimeMillis() % 100_000L) * 0.0021F);
        int hairline = EclipseUiTheme.withAlpha(EclipseUiTheme.DANGER, alpha * breathe);
        guiGraphics.fill(0, bandTop, guiGraphics.guiWidth(), bandTop + 1, hairline);
        guiGraphics.fill(0, bandBottom - 1, guiGraphics.guiWidth(), bandBottom, hairline);

        // --- boss name, 2x scale, GlitchText decode-in ---
        int locked = lockedChars(ticks);
        String lockedPart = name.substring(0, locked);
        String noiseTail = buildNoiseTail(locked);
        float lockFlash = locked < name.length() ? 0.0F
                : Mth.clamp(1.0F - (t - decodeEnd) / LOCK_FLASH_TICKS, 0.0F, 1.0F);
        int lockedRgb = lerpRgb(EclipseUiTheme.TEXT & 0xFFFFFF, EclipseUiTheme.DANGER & 0xFFFFFF,
                lockFlash);
        int alphaByte = Mth.clamp((int) (alpha * 255.0F), 8, 255);

        var pose = guiGraphics.pose();
        pose.pushPose();
        pose.scale(2.0F, 2.0F, 1.0F);
        int scaledLeft = centerX / 2 - mc.font.width(name) / 2;
        int scaledY = (nameTop + 2) / 2;
        if (!lockedPart.isEmpty()) {
            guiGraphics.drawString(mc.font, lockedPart, scaledLeft, scaledY,
                    (alphaByte << 24) | lockedRgb);
        }
        if (!noiseTail.isEmpty()) {
            int tailX = scaledLeft + mc.font.width(lockedPart);
            guiGraphics.drawString(mc.font, noiseTail, tailX, scaledY,
                    (Mth.clamp((int) (alpha * 210.0F), 8, 255) << 24)
                            | (EclipseUiTheme.DANGER & 0xFFFFFF));
        }
        pose.popPose();

        // --- epithet subtitle, typed 1 char/tick once the name locked ---
        if (!subtitle.isEmpty() && locked >= name.length()) {
            int revealed = Mth.clamp(ticks - decodeEnd, 0, subtitle.length());
            String shown = subtitle.substring(0, revealed);
            if (!shown.isEmpty()) {
                guiGraphics.drawString(mc.font, shown, centerX - mc.font.width(subtitle) / 2,
                        nameTop + 22, (alphaByte << 24) | (EclipseUiTheme.DIM & 0xFFFFFF));
            }
        }
    }

    /**
     * Noise for the not-yet-locked tail: {@link GlitchText#scramble} re-rolls every 3t
     * ({@code reducedFx} → calm static {@code ?}s); real spaces stay spaces so the name's
     * word shape reads through the corruption.
     */
    private static String buildNoiseTail(int locked) {
        int tail = name.length() - locked;
        if (tail <= 0) {
            return "";
        }
        String noise = GlitchText.scramble(tail, glitchSalt);
        StringBuilder builder = new StringBuilder(tail);
        for (int i = 0; i < tail; i++) {
            builder.append(name.charAt(locked + i) == ' ' ? ' ' : noise.charAt(i));
        }
        return builder.toString();
    }

    /** Component-wise RGB lerp (no alpha). */
    private static int lerpRgb(int from, int to, float t) {
        t = Mth.clamp(t, 0.0F, 1.0F);
        int red = (int) Mth.lerp(t, (from >> 16) & 0xFF, (to >> 16) & 0xFF);
        int green = (int) Mth.lerp(t, (from >> 8) & 0xFF, (to >> 8) & 0xFF);
        int blue = (int) Mth.lerp(t, from & 0xFF, to & 0xFF);
        return (red << 16) | (green << 8) | blue;
    }
}
