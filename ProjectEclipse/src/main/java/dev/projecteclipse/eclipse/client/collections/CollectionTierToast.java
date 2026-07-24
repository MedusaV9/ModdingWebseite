package dev.projecteclipse.eclipse.client.collections;

import java.util.ArrayDeque;
import java.util.List;
import java.util.Locale;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.collections.CollectionTiers;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionTierPayload;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
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
 * Collection tier-up card (D1, IDEAS-collections §3): {@code SkillProcToast}-style
 * two-line mini card above the hotbar — line 1 "✦ Iron Collection II" (ACCENT), line 2
 * "+100 XP · +1 SP · Shield unlocked" (TEXT) — fed by {@link S2CCollectionTierPayload}
 * via {@link ClientCollectionsCache}'s consumer install. Plays
 * {@code EclipseSounds.UI_UNLOCK_STING} ({@link UiSounds#unlockSting()}, the discovery
 * sting — deliberately NOT the skill-proc chirp) when a card becomes active. Queue cap
 * {@value #QUEUE_LIMIT} with oldest-dropped, mirroring the proc toast so tier bursts
 * (dev sets, retroactive reload sweeps) never overlap.
 *
 * <p>Sits one lane ABOVE the skill proc toast ({@code BOTTOM_OFFSET} 84 vs 59) — a mining
 * tier-up usually lands together with mine-XP procs and both beats must read. Self-
 * registered layer ({@code SkillProcToast.Registrar} pattern); F1-hidden; fade/rise
 * suppressed under {@code reducedFx}. The server's chat announcement
 * ({@code message.eclipse.collection.tier}) is the persistent record; this card is the
 * moment.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CollectionTierToast {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "collection_tier_toast");

    /** One lane above the skill proc toast's 59 so simultaneous beats never stack. */
    private static final int BOTTOM_OFFSET = 84;
    private static final int IN_TICKS = 5;
    private static final int HOLD_TICKS = 50;
    private static final int OUT_TICKS = 8;
    private static final int TOTAL_TICKS = IN_TICKS + HOLD_TICKS + OUT_TICKS;
    private static final int RISE_PX = 3;
    private static final int QUEUE_LIMIT = 4;
    /** At most this many unlock names spelled out; the rest collapse to "+n". */
    private static final int MAX_UNLOCK_NAMES = 2;

    // Client tick thread only.
    private static final ArrayDeque<S2CCollectionTierPayload> QUEUE = new ArrayDeque<>();
    @Nullable
    private static S2CCollectionTierPayload active;
    private static int ticks;

    private CollectionTierToast() {}

    /** Mod-bus layer registration (nested, {@code SkillProcToast.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAbove(VanillaGuiLayers.BOSS_OVERLAY, LAYER_ID, CollectionTierToast::render);
        }
    }

    /** Payload consumer (installed by {@link ClientCollectionsCache}); client main thread. */
    static void enqueue(S2CCollectionTierPayload payload) {
        if (QUEUE.size() >= QUEUE_LIMIT) {
            QUEUE.pollFirst(); // oldest card is the least interesting one
        }
        QUEUE.addLast(payload);
    }

    /** Logout reset (via {@link ClientCollectionsCache}). */
    static void reset() {
        QUEUE.clear();
        active = null;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze the active card; the queue stays intact
        }
        if (active != null && ++ticks > TOTAL_TICKS) {
            active = null;
        }
        if (active == null && !QUEUE.isEmpty()) {
            active = QUEUE.pollFirst();
            ticks = 0;
            UiSounds.unlockSting(); // the discovery sting, once per card
        }
    }

    /** GUI layer body (self-registered above the boss overlay). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        S2CCollectionTierPayload card = active;
        if (card == null || minecraft.options.hideGui) {
            return;
        }
        float t = ticks + deltaTracker.getGameTimeDeltaPartialTick(true);
        boolean reduced = EclipseClientConfig.reducedFx();

        float alpha;
        if (t < IN_TICKS) {
            alpha = reduced ? 1.0F : easeOutCubic(t / IN_TICKS);
        } else if (t <= IN_TICKS + HOLD_TICKS) {
            alpha = 1.0F;
        } else {
            alpha = 1.0F - easeOutCubic((t - IN_TICKS - HOLD_TICKS) / OUT_TICKS);
        }
        alpha = Mth.clamp(alpha, 0.0F, 1.0F);
        if (alpha <= 0.04F) {
            return; // fill() alpha-floor guard AND skips the invisible first frame
        }
        int rise = reduced ? 0 : Math.round((1.0F - easeOutCubic(Math.min(1.0F, t / IN_TICKS))) * RISE_PX);

        Font font = minecraft.font;
        String star = "✦ ";
        String title = titleText(card);
        String detail = detailText(card);
        int starWidth = font.width(star);
        int titleWidth = starWidth + font.width(title);
        int detailWidth = detail.isEmpty() ? 0 : font.width(detail);
        int width = Math.max(titleWidth, detailWidth);
        int centerX = guiGraphics.guiWidth() / 2;
        int y = guiGraphics.guiHeight() - BOTTOM_OFFSET + rise;
        int lines = detail.isEmpty() ? 1 : 2;
        int cardHeight = lines * (font.lineHeight + 1) + 4;

        // Quiet backdrop pill so the card reads over bright terrain (no hard panel).
        guiGraphics.fill(centerX - width / 2 - 5, y - 3, centerX + width / 2 + 5, y + cardHeight - 2,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, alpha * 0.7F));
        int titleX = centerX - titleWidth / 2;
        guiGraphics.drawString(font, star, titleX, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        guiGraphics.drawString(font, title, titleX + starWidth, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        if (!detail.isEmpty()) {
            guiGraphics.drawString(font, detail, centerX - detailWidth / 2, y + font.lineHeight + 2,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        }
    }

    /** Line 1: "Iron Collection II". */
    private static String titleText(S2CCollectionTierPayload card) {
        return uiText("gui.eclipse.collections.toast_title", "%s Collection %s",
                ClientCollectionsCache.displayName(card.collectionId()),
                CollectionTiers.roman(card.tier()));
    }

    /** Line 2: "+100 XP · +1 SP · Shield unlocked" (pieces drop when zero/absent). */
    private static String detailText(S2CCollectionTierPayload card) {
        StringBuilder detail = new StringBuilder();
        if (card.xp() > 0) {
            detail.append(uiText("gui.eclipse.collections.toast_xp", "+%s XP",
                    CollectionTiers.formatCount(card.xp())));
        }
        if (card.points() > 0) {
            appendSeparated(detail, uiText("gui.eclipse.collections.toast_points", "+%s SP", card.points()));
        }
        String unlocks = unlockText(card.unlockedItemIds());
        if (!unlocks.isEmpty()) {
            appendSeparated(detail, uiText("gui.eclipse.collections.toast_unlock", "%s unlocked", unlocks));
        }
        return detail.toString();
    }

    /** "Shield", "Crossbow, Minecart" or "Piston, Sticky Piston +1"; empty when none. */
    private static String unlockText(List<String> unlockEntries) {
        if (unlockEntries.isEmpty()) {
            return "";
        }
        StringBuilder names = new StringBuilder();
        int spelled = Math.min(unlockEntries.size(), MAX_UNLOCK_NAMES);
        for (int i = 0; i < spelled; i++) {
            if (i > 0) {
                names.append(", ");
            }
            names.append(ClientCollectionsCache.unlockName(unlockEntries.get(i)));
        }
        if (unlockEntries.size() > spelled) {
            names.append(" +").append(unlockEntries.size() - spelled);
        }
        return names.toString();
    }

    /** UI keys ride the langdrop; fall back to the English literal, never a raw key. */
    private static String uiText(String key, String fallback, Object... args) {
        return EclipseLang.hasKey(key) ? EclipseLang.trString(key, args)
                : String.format(Locale.ROOT, fallback, args);
    }

    private static void appendSeparated(StringBuilder builder, String piece) {
        if (builder.length() > 0) {
            builder.append(" \u00b7 ");
        }
        builder.append(piece);
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
