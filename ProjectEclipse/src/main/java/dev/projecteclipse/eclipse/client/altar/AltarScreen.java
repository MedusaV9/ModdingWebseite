package dev.projecteclipse.eclipse.client.altar;

import java.util.List;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.altar.AltarPayloads;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The altar panel (ALTARUI tasks 1/2/4): a pure client {@link Screen} in the Quiet-Eclipse
 * theme, opened by a plain right-click on the altar via {@code S2CAltarPanelPayload}
 * ({@code openScreen=true}) — the {@code GoalEditorScreen} payload-driven pattern, no
 * {@code MenuType}. Shows ONLY current-stage content (the server guarantees it: the payload
 * never carries future-stage data):
 * <ul>
 *   <li><b>Left column</b> — the hungering milestone's live requirements (item, banked/needed,
 *       progress bar), the deposit hint, what completing the stage unseals, and the
 *       server-chosen boss instruction block (task 2 — Herald from day 7 / a core-hungry
 *       milestone, Ferryman on finale day 14, "done" lines after a kill).</li>
 *   <li><b>Right column</b> — the shard shop: buyable rows are clickable (one
 *       {@code C2SAltarBuyPayload}), day-locked rows render greyed with "from day N"
 *       (names + costs were always public via the action-bar browse cycle — no new
 *       secret, but a savings goal), dev-disabled rows never arrive at all. The running
 *       Double-XP surge shows its remaining time on its row; personal + team balances
 *       close the column.</li>
 * </ul>
 *
 * <p><b>Fly-in (task 4):</b> requirement rows swoop in from the top-left screen corner on
 * a staggered ease-out-cubic path, each landing with one soft {@link UiSounds#rouletteTick}
 * blip (pitch rises per row — reused mod sounds, no new assets, behind the {@code uiSounds}
 * switch). {@code EclipseClientConfig.reducedFx} skips the whole entrance: rows sit in
 * place immediately and only the page-turn open cue plays.</p>
 *
 * <p><b>Liveness:</b> other players' deposits move the progress while the screen is open,
 * so it polls {@code C2SAltarPanelRequestPayload} every {@value #REFRESH_INTERVAL_TICKS}
 * ticks; buy responses refresh immediately. Refreshes update in place and never restart
 * the entrance animation. Walking away (> 8 blocks) closes the panel like a container.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class AltarScreen extends Screen {
    /** Poll cadence for live milestone/shop state while the screen is open (2 s). */
    private static final int REFRESH_INTERVAL_TICKS = 40;
    /** Flight time of one requirement icon (ms) and the per-row launch stagger (ms). */
    private static final int FLY_MS = 650;
    private static final int STAGGER_MS = 110;
    /** Client-side mirror of the server's 8-block interact range: walk away → close. */
    private static final double CLOSE_RANGE_SQ = 8.0D * 8.0D;

    private static final int REQ_ROW_H = 22;
    private static final int OFFER_ROW_H = 24;

    private final BlockPos altarPos;
    private final long openedAtMillis;
    private final boolean animate;

    private AltarPayloads.Header header;
    private List<AltarPayloads.Requirement> requirements;
    private List<String> unlockKeys;
    private List<AltarPayloads.ShopEntry> offers;
    /** Arrival blips already played, indexed like {@link #requirements}. */
    private boolean[] landedBlipPlayed;

    private int refreshTimer = REFRESH_INTERVAL_TICKS;

    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;
    private int leftX;
    private int leftW;
    private int rightX;
    private int rightW;
    private int reqStartY;

    private AltarScreen(AltarPayloads.S2CAltarPanelPayload payload) {
        super(EclipseLang.tr("gui.eclipse.altar.title"));
        this.altarPos = payload.pos();
        this.animate = !EclipseClientConfig.reducedFx();
        this.openedAtMillis = Util.getMillis();
        apply(payload);
    }

    /**
     * Payload entry point ({@code network.altar.AltarPayloads}): {@code openScreen} opens a
     * fresh panel (never interrupting another screen — the {@code GoalEditorScreen.open}
     * rule); refresh snapshots update an already-open panel for the same altar in place.
     */
    public static void handlePanel(AltarPayloads.S2CAltarPanelPayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        if (payload.openScreen()) {
            if (minecraft.player != null && minecraft.screen == null) {
                minecraft.setScreen(new AltarScreen(payload));
                UiSounds.pageTurn();
            }
        } else if (minecraft.screen instanceof AltarScreen screen
                && screen.altarPos.equals(payload.pos())) {
            screen.apply(payload);
            screen.rebuildWidgets();
        }
    }

    /** Swaps in a snapshot WITHOUT touching the entrance-animation clock (refresh path). */
    private void apply(AltarPayloads.S2CAltarPanelPayload payload) {
        this.header = payload.header();
        this.requirements = payload.requirements();
        this.unlockKeys = payload.unlockKeys();
        this.offers = payload.offers();
        if (this.landedBlipPlayed == null || this.landedBlipPlayed.length != this.requirements.size()) {
            boolean[] played = new boolean[this.requirements.size()];
            for (int i = 0; i < played.length; i++) {
                // Rows already landed (or reducedFx) never (re)play their arrival blip.
                played[i] = flyProgress(i) >= 1.0F;
            }
            this.landedBlipPlayed = played;
        }
    }

    @Override
    protected void init() {
        clearWidgets();
        panelW = Mth.clamp(this.width - 40, 420, 560);
        panelH = Mth.clamp(this.height - 40, 250, 320);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        leftW = (panelW - 3 * EclipseUiTheme.PAD) * 58 / 100;
        leftX = panelX + EclipseUiTheme.PAD;
        rightX = leftX + leftW + EclipseUiTheme.PAD;
        rightW = panelX + panelW - EclipseUiTheme.PAD - rightX;
        reqStartY = panelY + 26 + EclipseUiTheme.ROW + EclipseUiTheme.GAP;

        int offerY = reqStartY;
        for (AltarPayloads.ShopEntry offer : offers) {
            addRenderableWidget(new OfferRow(offer, rightX, offerY, rightW, OFFER_ROW_H));
            offerY += OFFER_ROW_H + 2;
        }
    }

    // ------------------------------------------------------------------ liveness

    @Override
    public void tick() {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null
                || minecraft.player.position().distanceToSqr(Vec3.atCenterOf(altarPos)) > CLOSE_RANGE_SQ) {
            onClose();
            return;
        }
        if (--refreshTimer <= 0) {
            refreshTimer = REFRESH_INTERVAL_TICKS;
            PacketDistributor.sendToServer(new AltarPayloads.C2SAltarPanelRequestPayload(altarPos));
        }
        // Task 4 arrival blips: one soft tick per landed row, pitch rising down the list.
        for (int i = 0; i < landedBlipPlayed.length; i++) {
            if (!landedBlipPlayed[i] && flyProgress(i) >= 1.0F) {
                landedBlipPlayed[i] = true;
                UiSounds.rouletteTick(0.85F + 0.08F * i);
            }
        }
    }

    /** Eased entrance progress of requirement row {@code index} (1 = landed / reducedFx). */
    private float flyProgress(int index) {
        if (!animate) {
            return 1.0F;
        }
        long elapsed = Util.getMillis() - openedAtMillis - (long) index * STAGGER_MS;
        if (elapsed <= 0L) {
            return 0.0F;
        }
        if (elapsed >= FLY_MS) {
            return 1.0F;
        }
        float t = elapsed / (float) FLY_MS;
        return 1.0F - (1.0F - t) * (1.0F - t) * (1.0F - t); // easeOutCubic
    }

    // ------------------------------------------------------------------ rendering

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);
        EclipseUiTheme.drawPanel(guiGraphics, panelX, panelY, panelW, panelH);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);

        // Header line: title left, "Stage N · Day M" right.
        guiGraphics.drawString(this.font, this.title, leftX, panelY + 8, EclipseUiTheme.ACCENT);
        String stage = EclipseLang.trString("gui.eclipse.altar.stage", header.altarLevel(), header.day());
        guiGraphics.drawString(this.font, stage,
                panelX + panelW - EclipseUiTheme.PAD - this.font.width(stage), panelY + 8,
                EclipseUiTheme.TEXT);
        EclipseUiTheme.drawHairline(guiGraphics, leftX, panelX + panelW - EclipseUiTheme.PAD, panelY + 20);

        int y = renderRequirements(guiGraphics);
        renderBossBlock(guiGraphics, y);
        renderShopFooter(guiGraphics);
        CursorManager.endFrame();
    }

    /** Left column: requirement rows (fly-in), sealed note, deposit hint, unseal line. */
    private int renderRequirements(GuiGraphics guiGraphics) {
        int y = EclipseUiTheme.drawHeader(guiGraphics, this.font,
                EclipseLang.tr(header.completed()
                        ? "gui.eclipse.altar.complete_title" : "gui.eclipse.altar.needs"),
                leftX, panelY + 26, leftW);

        if (header.completed()) {
            for (FormattedCharSequence line : this.font.split(
                    EclipseLang.tr("gui.eclipse.altar.complete"), leftW)) {
                guiGraphics.drawString(this.font, line, leftX, y, EclipseUiTheme.DIM);
                y += EclipseUiTheme.ROW;
            }
            return y + EclipseUiTheme.GAP;
        }

        for (int i = 0; i < requirements.size(); i++) {
            AltarPayloads.Requirement requirement = requirements.get(i);
            float progress = flyProgress(i);
            float eased = Math.max(0.0F, progress);
            int rowY = y + i * REQ_ROW_H;

            // Task 4: the icon starts at the top-left screen corner and eases to its slot.
            int iconX = Math.round(Mth.lerp(eased, -20.0F, leftX));
            int iconY = Math.round(Mth.lerp(eased, -20.0F, rowY));
            ItemStack stack = new ItemStack(resolveItem(requirement.itemId()));
            if (eased > 0.0F) {
                guiGraphics.renderItem(stack, iconX, iconY);
            }
            if (eased < 1.0F) {
                continue; // name/progress fade in only once their icon has landed
            }

            boolean done = requirement.progress() >= requirement.required();
            String count = requirement.progress() + " / " + requirement.required();
            int countW = this.font.width(count);
            String name = EclipseUiTheme.ellipsize(this.font,
                    stack.getHoverName().getString(), leftW - 20 - countW - 4);
            guiGraphics.drawString(this.font, name, leftX + 20, rowY, EclipseUiTheme.TEXT);
            guiGraphics.drawString(this.font, count, leftX + leftW - countW, rowY,
                    done ? EclipseUiTheme.GOOD : EclipseUiTheme.ACCENT);
            // 3px progress bar under the row text.
            int barX = leftX + 20;
            int barW = leftW - 20;
            int fillW = (int) (barW * Math.min(1.0D,
                    requirement.progress() / (double) requirement.required()));
            guiGraphics.fill(barX, rowY + 11, barX + barW, rowY + 14, EclipseUiTheme.HAIRLINE);
            if (fillW > 0) {
                guiGraphics.fill(barX, rowY + 11, barX + fillW, rowY + 14,
                        done ? EclipseUiTheme.GOOD : EclipseUiTheme.ACCENT);
            }
        }
        y += requirements.size() * REQ_ROW_H + EclipseUiTheme.GAP;

        if (header.sealed()) {
            for (FormattedCharSequence line : this.font.split(
                    EclipseLang.tr("gui.eclipse.altar.sealed"), leftW)) {
                guiGraphics.drawString(this.font, line, leftX, y, EclipseUiTheme.DANGER);
                y += EclipseUiTheme.ROW;
            }
        } else {
            for (FormattedCharSequence line : this.font.split(
                    EclipseLang.tr("gui.eclipse.altar.hint"), leftW)) {
                guiGraphics.drawString(this.font, line, leftX, y, EclipseUiTheme.DIM);
                y += EclipseUiTheme.ROW;
            }
        }
        if (!unlockKeys.isEmpty()) {
            for (FormattedCharSequence line : this.font.split(
                    EclipseLang.tr("gui.eclipse.altar.unlocks", unlockNames()), leftW)) {
                guiGraphics.drawString(this.font, line, leftX, y, EclipseUiTheme.TEXT);
                y += EclipseUiTheme.ROW;
            }
        }
        return y + EclipseUiTheme.GAP;
    }

    /** Short display names of the current milestone's unlock keys (RewardsTab convention). */
    private String unlockNames() {
        StringBuilder names = new StringBuilder();
        for (String key : unlockKeys) {
            if (names.length() > 0) {
                names.append(", ");
            }
            String shortKey = "gui.eclipse.handbook.rewards.key." + key;
            names.append(EclipseLang.hasKey(shortKey) ? EclipseLang.trString(shortKey) : key);
        }
        return names.toString();
    }

    /** Task 2: the server-picked boss instruction block ({@code bossHintId} → title + body). */
    private void renderBossBlock(GuiGraphics guiGraphics, int y) {
        String hint = header.bossHintId();
        if (AltarPayloads.BOSS_HINT_NONE.equals(hint)) {
            return;
        }
        y = EclipseUiTheme.drawHeader(guiGraphics, this.font,
                EclipseLang.tr("gui.eclipse.altar.boss." + hint + ".title"), leftX, y, leftW);
        int bottom = panelY + panelH - EclipseUiTheme.PAD;
        for (FormattedCharSequence line : this.font.split(
                EclipseLang.tr("gui.eclipse.altar.boss." + hint + ".body"), leftW)) {
            if (y + EclipseUiTheme.ROW > bottom) {
                break; // never spill out of the panel on tiny windows
            }
            guiGraphics.drawString(this.font, line, leftX, y, EclipseUiTheme.DIM);
            y += EclipseUiTheme.ROW;
        }
    }

    /** Right column header + the balances under the offer rows. */
    private void renderShopFooter(GuiGraphics guiGraphics) {
        EclipseUiTheme.drawHeader(guiGraphics, this.font,
                EclipseLang.tr("gui.eclipse.altar.shop.title"), rightX, panelY + 26, rightW);
        int y = reqStartY + offers.size() * (OFFER_ROW_H + 2) + EclipseUiTheme.GAP;
        EclipseUiTheme.drawHairline(guiGraphics, rightX, rightX + rightW, y - 2);
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font,
                EclipseLang.trString("gui.eclipse.altar.shards.personal", header.personalShards()),
                rightW), rightX, y + 2, EclipseUiTheme.TEXT);
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font,
                EclipseLang.trString("gui.eclipse.altar.shards.pool", header.poolShards()),
                rightW), rightX, y + 2 + EclipseUiTheme.ROW, EclipseUiTheme.DIM);
    }

    private static Item resolveItem(String id) {
        ResourceLocation location = ResourceLocation.tryParse(id);
        if (location == null) {
            return Items.BARRIER;
        }
        return BuiltInRegistries.ITEM.getOptional(location).orElse(Items.BARRIER);
    }

    private static String formatSeconds(int seconds) {
        return String.format(java.util.Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60);
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

    // ------------------------------------------------------------------ shop rows

    /** One clickable shop offer; day-locked rows are inert and greyed ("from day N"). */
    private final class OfferRow extends EclipseWidget {
        private final AltarPayloads.ShopEntry offer;

        OfferRow(AltarPayloads.ShopEntry offer, int x, int y, int width, int height) {
            super(x, y, width, height, EclipseLang.tr(offer.nameKey()));
            this.offer = offer;
            this.active = offer.unlocked();
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            PacketDistributor.sendToServer(
                    new AltarPayloads.C2SAltarBuyPayload(altarPos, offer.offerId()));
            // The server answers every buy (win or refuse) with a fresh snapshot; pull the
            // next poll forward so a refused click never shows stale balances for 2 s.
            refreshTimer = Math.min(refreshTimer, 5);
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            float alpha = offer.unlocked() ? 1.0F : 0.45F;
            guiGraphics.fill(getX(), getY(), getX() + width, getY() + height,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));

            String cost = EclipseLang.trString("gui.eclipse.altar.shop.cost", offer.cost());
            int costW = AltarScreen.this.font.width(cost);
            String name = EclipseUiTheme.ellipsize(AltarScreen.this.font,
                    getMessage().getString(), width - costW - 10);
            guiGraphics.drawString(AltarScreen.this.font, name, getX() + 4, getY() + 3,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
            guiGraphics.drawString(AltarScreen.this.font, cost, getX() + width - costW - 4, getY() + 3,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));

            String detail;
            if (!offer.unlocked()) {
                detail = EclipseLang.trString("gui.eclipse.altar.shop.from_day", offer.minDay());
            } else {
                detail = EclipseLang.trString(offer.pooled()
                        ? "gui.eclipse.altar.shop.pooled" : "gui.eclipse.altar.shop.personal");
                if (offer.remainingSeconds() > 0) {
                    detail += " · " + EclipseLang.trString("gui.eclipse.altar.shop.remaining",
                            formatSeconds(offer.remainingSeconds()));
                }
            }
            guiGraphics.drawString(AltarScreen.this.font,
                    EclipseUiTheme.ellipsize(AltarScreen.this.font, detail, width - 8),
                    getX() + 4, getY() + 13, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
        }
    }
}
