package dev.projecteclipse.eclipse.client.collections;

import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.hud.BottomToastQueue;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.collections.CollectionTiers;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionTierPayload;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;

/**
 * Collection tier-up card (D1, IDEAS-collections §3): two-line mini card — line 1
 * "✦ Iron Collection II" (ACCENT), line 2 "+100 XP · +1 SP · Shield unlocked" (TEXT) —
 * fed by {@link S2CCollectionTierPayload} via {@link ClientCollectionsCache}'s consumer
 * install. Plays {@code EclipseSounds.UI_UNLOCK_STING} ({@link UiSounds#unlockSting()},
 * the discovery sting — deliberately NOT the skill-proc chirp) when the card becomes
 * visible. Since EVAL-DOPA-F #5 the card lives in {@link BottomToastQueue} (single
 * renderer, stacked slots, FIFO, max 2 visible) — a tier card and a shard pill landing
 * together stack into separate slots instead of overlapping; this class only builds the
 * card entry and its text. The server's chat announcement
 * ({@code message.eclipse.collection.tier}) is the persistent record; this card is the
 * moment.
 */
public final class CollectionTierToast {
    /** Hold length of the two-line card (longer than the one-line pills — more to read). */
    private static final int HOLD_TICKS = 50;
    /** At most this many unlock names spelled out; the rest collapse to "+n". */
    private static final int MAX_UNLOCK_NAMES = 2;

    private record Card(S2CCollectionTierPayload payload) implements BottomToastQueue.Toast {
        @Override
        public int holdTicks() {
            return HOLD_TICKS;
        }

        @Override
        public void onShow() {
            UiSounds.unlockSting(); // the discovery sting, once per card
        }

        @Override
        public void draw(GuiGraphics guiGraphics, Font font, int centerX, int y, float alpha) {
            String star = "✦ ";
            String title = titleText(payload);
            String detail = detailText(payload);
            int starWidth = font.width(star);
            int titleWidth = starWidth + font.width(title);
            int detailWidth = detail.isEmpty() ? 0 : font.width(detail);
            int width = Math.max(titleWidth, detailWidth);
            int lines = detail.isEmpty() ? 1 : 2;
            int cardHeight = lines * (font.lineHeight + 1) + 4;

            // Quiet backdrop pill so the card reads over bright terrain (no hard panel).
            guiGraphics.fill(centerX - width / 2 - 5, y - 3, centerX + width / 2 + 5,
                    y + cardHeight - 2,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, alpha * 0.7F));
            int titleX = centerX - titleWidth / 2;
            guiGraphics.drawString(font, star, titleX, y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
            guiGraphics.drawString(font, title, titleX + starWidth, y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
            if (!detail.isEmpty()) {
                guiGraphics.drawString(font, detail, centerX - detailWidth / 2,
                        y + font.lineHeight + 2,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
            }
        }
    }

    private CollectionTierToast() {}

    /** Payload consumer (installed by {@link ClientCollectionsCache}); client main thread. */
    static void enqueue(S2CCollectionTierPayload payload) {
        BottomToastQueue.enqueue(new Card(payload));
    }

    /** Logout reset (via {@link ClientCollectionsCache}) — drops the whole shared lane. */
    static void reset() {
        BottomToastQueue.reset();
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
}
