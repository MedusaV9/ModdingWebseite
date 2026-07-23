package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayDeque;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.language.I18n;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client half of {@link S2CAnnouncePayload} ({@code docs/ideas/03_ui_ux.md} §E). Every
 * announcement plays two simultaneous pieces:
 * <ul>
 *   <li>a {@link TypewriterLine} above the hotbar (1 char/tick, tick sound every 2 chars,
 *       full line posted to chat once when typing completes), and</li>
 *   <li>a client-local bossbar sweep re-using {@link BossbarSkin#drawThemedBar}: the fill
 *       sweeps 0→1 over {@value #SWEEP_IN_TICKS}t with a bright leading edge, holds
 *       {@value #SWEEP_HOLD_TICKS}t showing the title, then fades. No {@code BossEvent} is
 *       involved — the bar exists purely in this overlay, stacked below any real bars via
 *       {@link BossbarSkin#nextFreeBarY()}.</li>
 * </ul>
 *
 * <p>Payload styles map onto the three bar skins: {@code day}→day, {@code boss}→boss,
 * {@code goal}/{@code unlock}→goal. Incoming announcements queue (cap
 * {@value #QUEUE_LIMIT}) so unlock bursts play one after another instead of overwriting.
 * The layer is deliberately NOT letterbox-whitelisted: cutscene HUD suppression hides it.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AnnouncementOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "announcements");
    /** Celebratory Quasar fountain spawned once per UNLOCK-style announcement (client-only emitter). */
    private static final ResourceLocation UNLOCK_BURST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "unlock_burst");

    private static final int SWEEP_IN_TICKS = 30;
    private static final int SWEEP_HOLD_TICKS = 60;
    private static final int SWEEP_FADE_TICKS = 20;
    private static final int QUEUE_LIMIT = 8;
    private static final String UNLOCK_KEY_PREFIX = "announce.eclipse.unlock.key.";
    /** Typewriter baseline above the hotbar (clear of the vanilla actionbar at -68). */
    private static final int TYPEWRITER_BOTTOM_OFFSET = 80;

    /** Client thread only. */
    private static final ArrayDeque<S2CAnnouncePayload> QUEUE = new ArrayDeque<>();
    private static TypewriterLine typewriter;
    private static Component sweepTitle;
    private static String sweepTheme;
    /** Ticks since the active sweep started; {@code -1} = no sweep running. */
    private static int sweepTicks = -1;

    private AnnouncementOverlay() {}

    /** {@link S2CAnnouncePayload} entry point (client main thread). */
    public static void handle(S2CAnnouncePayload payload) {
        if (S2CAnnouncePayload.STYLE_UNLOCK.equals(payload.style())) {
            spawnUnlockBurst();
        }
        if (QUEUE.size() < QUEUE_LIMIT) {
            QUEUE.add(payload);
        }
    }

    /**
     * One {@code eclipse:unlock_burst} Quasar fountain (purple/gold sparks) at the local
     * player's feet per UNLOCK-style announcement — the style used only for timeline
     * milestone/config-key unlocks ({@code timeline.AnnouncementService}), never for
     * day/goal/boss lines. Spawned on payload arrival (the unlock moment) rather than when
     * the queued sweep plays; gated on {@code reducedFx} like the other non-essential
     * particle FX.
     */
    private static void spawnUnlockBurst() {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null || EclipseClientConfig.reducedFx()) {
            return;
        }
        QuasarSpawner.spawnOrFallback(UNLOCK_BURST, player.position());
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            typewriter = null;
            sweepTicks = -1;
            return;
        }
        if (minecraft.isPaused()) {
            // The client tick keeps firing while paused — announcements (typewriter
            // advancement + its tick sounds included) freeze; the queue stays intact.
            return;
        }
        if (typewriter == null && sweepTicks < 0 && !QUEUE.isEmpty()) {
            start(QUEUE.poll());
        }
        if (typewriter != null && typewriter.tick()) {
            typewriter = null;
        }
        if (sweepTicks >= 0 && ++sweepTicks > SWEEP_IN_TICKS + SWEEP_HOLD_TICKS + SWEEP_FADE_TICKS) {
            sweepTicks = -1;
        }
    }

    private static void start(S2CAnnouncePayload payload) {
        Component title = Component.translatable(payload.titleKey());
        Component subtitle = resolve(payload.subtitleKey());
        typewriter = new TypewriterLine(subtitle != null ? subtitle : title);
        sweepTitle = title;
        sweepTheme = switch (payload.style()) {
            case S2CAnnouncePayload.STYLE_BOSS -> S2CBossbarStylePayload.THEME_BOSS;
            case S2CAnnouncePayload.STYLE_DAY -> S2CBossbarStylePayload.THEME_DAY;
            default -> S2CBossbarStylePayload.THEME_GOAL; // goal + unlock share the goal skin
        };
        sweepTicks = 0;
    }

    /**
     * Resolves a subtitle key; empty → {@code null} (the typewriter falls back to the
     * title). Unlock announcements for NON-default config keys have no shipped lang line —
     * humanize the raw key instead of showing the untranslated lang key.
     */
    private static Component resolve(String key) {
        if (key.isEmpty()) {
            return null;
        }
        if (!I18n.exists(key) && key.startsWith(UNLOCK_KEY_PREFIX)) {
            return Component.literal("Seal broken: "
                    + key.substring(UNLOCK_KEY_PREFIX.length()).replace('_', ' '));
        }
        return Component.translatable(key);
    }

    /** GUI layer body (registered above the boss overlay in {@code EclipseGuiLayers}). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.options.hideGui) {
            return;
        }
        if (sweepTicks >= 0) {
            float t = sweepTicks + deltaTracker.getGameTimeDeltaPartialTick(true);
            float progress = Mth.clamp(t / SWEEP_IN_TICKS, 0.0F, 1.0F);
            float alpha = t <= SWEEP_IN_TICKS + SWEEP_HOLD_TICKS ? 1.0F
                    : Mth.clamp(1.0F - (t - SWEEP_IN_TICKS - SWEEP_HOLD_TICKS) / SWEEP_FADE_TICKS, 0.0F, 1.0F);
            // Bright leading edge while sweeping, decaying pulse during the hold.
            float glow = t < SWEEP_IN_TICKS ? 1.0F
                    : Mth.clamp(1.0F - (t - SWEEP_IN_TICKS) / 20.0F, 0.25F, 1.0F);
            Component name = t >= SWEEP_IN_TICKS ? sweepTitle : null;
            BossbarSkin.drawThemedBar(guiGraphics, guiGraphics.guiWidth() / 2 - 91,
                    BossbarSkin.nextFreeBarY() + 12, sweepTheme, progress, glow, name, alpha);
        }
        if (typewriter != null) {
            typewriter.render(guiGraphics, guiGraphics.guiWidth() / 2,
                    guiGraphics.guiHeight() - TYPEWRITER_BOTTOM_OFFSET);
        }
    }
}
