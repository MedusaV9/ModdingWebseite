package dev.projecteclipse.eclipse.client.altar;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import org.lwjgl.glfw.GLFW;

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
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
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
 *   <li><b>Right column</b> — the shard shop: every arriving row is buyable; not-yet-unlocked
 *       offers arrive only as the opaque {@code Header.sealedOffers} COUNT (AUDITFIX-3
 *       anti-spoiler — no id, name, price or unlock day ever leaves the server) and render
 *       as inert sealed "???" rows; dev-disabled rows never arrive at all. The running
 *       Double-XP surge shows its remaining time on its row; personal + team balances close
 *       the column.</li>
 * </ul>
 *
 * <p><b>F-074 readability pass:</b> taller requirement/offer rows on more air, a vertical
 * hairline separating the two columns, an affordability edge + a framed price chip
 * (count + currency icon) on every offer row, currency icons on the balance footer, the
 * boss instruction body lifted off the low-contrast DIM tone, and hover tooltips on the
 * requirement rows (full item name + exact banked/needed numbers — names ellipsize on
 * narrow panels).</p>
 *
 * <p><b>F-074 purchase flow:</b> clicking an offer no longer buys blind — it opens a modal
 * confirmation overlay (reward icon, itemised price, which purse pays, the balance after
 * the buy; Enter or the Kaufen button confirms, Esc/outside-click cancels). Only a
 * confirmed click sends {@code C2SAltarBuyPayload}; the server's guard chain
 * ({@code ShardEconomy.buyById}) still validates every purchase unchanged. The
 * {@code S2CAltarBuyResultPayload} receipt then drives the purchase ANIMATION — currency
 * icons fly from the paying balance line into the offer row, the row pulses gold under a
 * spark burst and a win sting, and ~1.25 s later the panel closes itself so the in-world
 * ceremony ({@code economy.AltarBuyCeremony}, category-dependent, at the altar) takes the
 * stage. A refused buy flashes the row red with the glitch error blip instead.
 * {@code reducedFx} skips the fly/pulse frames: win sting, quick close, ceremony.</p>
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

    // --- F-074 readability: taller rows, adaptive shop density ---
    /** Requirement row height (F-074: 22 → 24 for a clearer name/bar separation). */
    private static final int REQ_ROW_H = 24;
    /** Offer rows breathe at 28px and compress down to 20px when the day is offer-heavy. */
    private static final int OFFER_ROW_H_MAX = 28;
    private static final int OFFER_ROW_H_MIN = 20;
    private static final int OFFER_ROW_GAP = 3;
    /** Balance footer: hairline + two icon rows. */
    private static final int SHOP_FOOTER_H = 40;

    // --- F-074 confirmation overlay ---
    private static final int CONFIRM_W = 248;
    private static final int CONFIRM_H = 132;
    private static final int CONFIRM_BUTTON_H = 16;

    // --- F-074 purchase animation (all times in ms; Util.getMillis clock) ---
    private static final int BUYFX_FLY_COUNT = 6;
    private static final int BUYFX_FLY_MS = 520;
    private static final int BUYFX_FLY_STAGGER_MS = 55;
    private static final int BUYFX_PULSE_START_MS = 320;
    private static final int BUYFX_PULSE_MS = 820;
    private static final int BUYFX_SPARK_COUNT = 10;
    /** The panel closes itself this long after a confirmed buy (world ceremony follows). */
    private static final int BUYFX_CLOSE_MS = 1250;
    private static final int BUYFX_REDUCED_CLOSE_MS = 300;
    private static final int FAIL_FLASH_MS = 450;
    /** Server-receipt watchdog: clear the awaiting lock if no answer arrives (ticks). */
    private static final int AWAIT_TIMEOUT_TICKS = 60;

    /** Purchase-gold accents (house palette side-tone, only used by the buy animation). */
    private static final int GOLD = 0xFFF2C879;
    private static final int GOLD_BRIGHT = 0xFFFFE9B0;

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
    /** Adaptive offer-row height (see {@link #init()}) and the balance-footer anchor. */
    private int offerRowH = OFFER_ROW_H_MAX;
    private int shopFooterY;

    /** Live offer-row widgets (buy-animation targeting + modal tooltip suppression). */
    private final List<OfferRow> offerRows = new ArrayList<>();
    /** The currency item shown on the balance footer (first offer's currency). */
    private ItemStack footerCurrency = ItemStack.EMPTY;
    /** Footer icon anchors, refreshed every frame — the buy animation launches here. */
    private int footerIconX;
    private int footerPersonalY;
    private int footerPoolY;

    // --- F-074 modal confirmation state ---
    @Nullable
    private AltarPayloads.ShopEntry confirmOffer;
    /** Button rects of the live confirm overlay (rebuilt every rendered frame). */
    @Nullable
    private Rect confirmBuyRect;
    @Nullable
    private Rect confirmCancelRect;
    @Nullable
    private Rect confirmPanelRect;

    /** A confirmed buy is in flight to the server; blocks re-clicks until the receipt. */
    private boolean awaitingResult;
    private String awaitingOfferId = "";
    private int awaitingTicks;

    // --- F-074 purchase animation state ---
    @Nullable
    private BuyFx buyFx;
    private long failFlashStart = Long.MIN_VALUE;
    private String failOfferId = "";

    /** Requirement-row hover tooltip queued during render, drawn on top of everything. */
    @Nullable
    private List<Component> hoverTooltip;

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

    /**
     * F-074 buy receipt ({@code S2CAltarBuyResultPayload}, buyer-private): success starts
     * the purchase animation, failure flashes the refused row red. Ignored when the panel
     * for that altar is no longer open (the world ceremony still plays server-side).
     */
    public static void handleBuyResult(AltarPayloads.S2CAltarBuyResultPayload payload) {
        if (Minecraft.getInstance().screen instanceof AltarScreen screen
                && screen.altarPos.equals(payload.pos())) {
            screen.onBuyResult(payload);
        }
    }

    /** Swaps in a snapshot WITHOUT touching the entrance-animation clock (refresh path). */
    private void apply(AltarPayloads.S2CAltarPanelPayload payload) {
        this.header = payload.header();
        this.requirements = payload.requirements();
        this.unlockKeys = payload.unlockKeys();
        this.offers = payload.offers();
        this.footerCurrency = this.offers.isEmpty()
                ? ItemStack.EMPTY : new ItemStack(resolveItem(this.offers.get(0).currencyItemId()));
        if (this.landedBlipPlayed == null || this.landedBlipPlayed.length != this.requirements.size()) {
            boolean[] played = new boolean[this.requirements.size()];
            for (int i = 0; i < played.length; i++) {
                // Rows already landed (or reducedFx) never (re)play their arrival blip.
                played[i] = flyProgress(i) >= 1.0F;
            }
            this.landedBlipPlayed = played;
        }
        // Keep a live confirmation in sync with the fresh snapshot (balances move while
        // the overlay is open); an offer that vanished (day rollover, /dev toggle)
        // dismisses it — a stale confirm must never send a blind buy.
        if (confirmOffer != null) {
            AltarPayloads.ShopEntry fresh = offerById(confirmOffer.offerId());
            if (fresh == null) {
                closeConfirm();
            } else {
                confirmOffer = fresh;
            }
        }
    }

    @Nullable
    private AltarPayloads.ShopEntry offerById(String offerId) {
        for (AltarPayloads.ShopEntry offer : offers) {
            if (offer.offerId().equals(offerId)) {
                return offer;
            }
        }
        return null;
    }

    @Override
    protected void init() {
        clearWidgets();
        offerRows.clear();
        // F-074: a slightly roomier panel — the old 420×250 floor squeezed the shop rows.
        panelW = Mth.clamp(this.width - 40, 440, 600);
        panelH = Mth.clamp(this.height - 40, 260, 340);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        leftW = (panelW - 3 * EclipseUiTheme.PAD) * 58 / 100;
        leftX = panelX + EclipseUiTheme.PAD;
        rightX = leftX + leftW + EclipseUiTheme.PAD;
        rightW = panelX + panelW - EclipseUiTheme.PAD - rightX;
        reqStartY = panelY + 26 + EclipseUiTheme.ROW + EclipseUiTheme.GAP;

        // F-074 adaptive density: rows render at 28px when they fit, and compress (never
        // below 20px) on offer-heavy days so the balance footer always stays inside the
        // panel instead of clipping.
        int totalRows = offers.size() + header.sealedOffers();
        int available = panelY + panelH - EclipseUiTheme.PAD - SHOP_FOOTER_H - reqStartY;
        offerRowH = totalRows == 0
                ? OFFER_ROW_H_MAX
                : Mth.clamp(available / totalRows - OFFER_ROW_GAP, OFFER_ROW_H_MIN, OFFER_ROW_H_MAX);

        int offerY = reqStartY;
        for (AltarPayloads.ShopEntry offer : offers) {
            OfferRow row = new OfferRow(offer, rightX, offerY, rightW, offerRowH);
            offerRows.add(row);
            addRenderableWidget(row);
            offerY += offerRowH + OFFER_ROW_GAP;
        }
        // AUDITFIX-3: locked placeholders — the server sent only a count, so these rows
        // know nothing they could spoil.
        for (int i = 0; i < header.sealedOffers(); i++) {
            addRenderableWidget(new SealedRow(rightX, offerY, rightW, offerRowH));
            offerY += offerRowH + OFFER_ROW_GAP;
        }
        shopFooterY = offerY + EclipseUiTheme.GAP;
        // Refresh rebuilds may land mid-modal: keep the row tooltips suppressed.
        applyModalTooltipState();
    }

    /** Whether a modal layer (confirm overlay / purchase animation) owns the input. */
    private boolean modalActive() {
        return confirmOffer != null || buyFx != null || awaitingResult;
    }

    /** Row tooltips pop OVER the confirm veil, so they are silenced while it is open. */
    private void applyModalTooltipState() {
        for (OfferRow row : offerRows) {
            row.refreshTooltip(!modalActive());
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
        // Receipt watchdog: a lost buy answer must not lock the panel forever.
        if (awaitingResult && ++awaitingTicks > AWAIT_TIMEOUT_TICKS) {
            awaitingResult = false;
            awaitingOfferId = "";
            applyModalTooltipState();
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

    // ------------------------------------------------------------------ input (modal layers)

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (buyFx != null || awaitingResult) {
            return true; // the purchase beat owns the panel — no re-clicks, no cancels
        }
        if (confirmOffer != null) {
            if (confirmBuyRect != null && confirmBuyRect.contains(mouseX, mouseY)) {
                if (canAfford(confirmOffer)) {
                    UiSounds.click();
                    confirmBuy();
                } else {
                    UiSounds.error();
                }
                return true;
            }
            if (confirmCancelRect != null && confirmCancelRect.contains(mouseX, mouseY)) {
                UiSounds.click();
                closeConfirm();
                return true;
            }
            if (confirmPanelRect == null || !confirmPanelRect.contains(mouseX, mouseY)) {
                closeConfirm(); // clicking past the dialog dismisses it, container-style
            }
            return true; // modal: nothing reaches the rows underneath
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (confirmOffer != null) {
            if (keyCode == GLFW.GLFW_KEY_ESCAPE) {
                closeConfirm(); // Esc cancels the confirm, never the whole panel
                return true;
            }
            if (keyCode == GLFW.GLFW_KEY_ENTER || keyCode == GLFW.GLFW_KEY_KP_ENTER) {
                if (canAfford(confirmOffer)) {
                    confirmBuy();
                } else {
                    UiSounds.error();
                }
                return true;
            }
            return true; // modal: swallow everything else
        }
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    // ------------------------------------------------------------------ confirm flow

    /** Held amount of the purse {@code offer} is charged against. */
    private int purseBalance(AltarPayloads.ShopEntry offer) {
        return offer.pooled() ? header.poolShards() : header.personalShards();
    }

    private boolean canAfford(AltarPayloads.ShopEntry offer) {
        return purseBalance(offer) >= offer.cost();
    }

    /** Offer row clicked (idle state only): open the confirmation overlay. */
    private void openConfirm(AltarPayloads.ShopEntry offer) {
        confirmOffer = offer;
        applyModalTooltipState();
    }

    private void closeConfirm() {
        confirmOffer = null;
        confirmBuyRect = null;
        confirmCancelRect = null;
        confirmPanelRect = null;
        applyModalTooltipState();
    }

    /** The confirmed click: NOW the buy payload leaves; the receipt drives what follows. */
    private void confirmBuy() {
        AltarPayloads.ShopEntry offer = confirmOffer;
        if (offer == null || awaitingResult) {
            return;
        }
        awaitingResult = true;
        awaitingOfferId = offer.offerId();
        awaitingTicks = 0;
        closeConfirm();
        applyModalTooltipState();
        PacketDistributor.sendToServer(
                new AltarPayloads.C2SAltarBuyPayload(altarPos, offer.offerId()));
        // The server answers every buy (win or refuse) with a fresh snapshot; pull the
        // next poll forward so a refused click never shows stale balances for 2 s.
        refreshTimer = Math.min(refreshTimer, 5);
    }

    /** The server's receipt: success → purchase animation, failure → refusal flash. */
    private void onBuyResult(AltarPayloads.S2CAltarBuyResultPayload payload) {
        awaitingResult = false;
        awaitingTicks = 0;
        awaitingOfferId = "";
        if (payload.success()) {
            startBuyFx(payload.offerId());
        } else {
            failFlashStart = Util.getMillis();
            failOfferId = payload.offerId();
            UiSounds.error();
        }
        applyModalTooltipState();
    }

    // ------------------------------------------------------------------ purchase animation

    /** One live purchase celebration: fly icons → gold pulse → sparks → panel close. */
    private final class BuyFx {
        final String offerId;
        final long start = Util.getMillis();
        final ItemStack currency;
        final boolean pooled;
        /** Last known target-row rect — kept when a refresh drops the row mid-beat. */
        Rect rowRect;
        final boolean[] flyBlipPlayed = new boolean[BUYFX_FLY_COUNT];
        boolean winStingPlayed;
        boolean closeRequested;
        /** reducedFx profile: no frames, just the sting and a quick close. */
        final boolean reduced = EclipseClientConfig.reducedFx();

        BuyFx(String offerId, ItemStack currency, boolean pooled, Rect rowRect) {
            this.offerId = offerId;
            this.currency = currency;
            this.pooled = pooled;
            this.rowRect = rowRect;
        }
    }

    private void startBuyFx(String offerId) {
        AltarPayloads.ShopEntry offer = offerById(offerId);
        Rect rect = rowRectFor(offerId);
        ItemStack currency = offer != null
                ? new ItemStack(resolveItem(offer.currencyItemId()))
                : (footerCurrency.isEmpty() ? new ItemStack(Items.AMETHYST_SHARD) : footerCurrency);
        buyFx = new BuyFx(offerId, currency, offer == null || offer.pooled(), rect);
        if (buyFx.reduced) {
            buyFx.winStingPlayed = true;
            UiSounds.rouletteWin();
        }
    }

    /** Live rect of the offer row (refresh rebuilds move rows), or the last known one. */
    private Rect rowRectFor(String offerId) {
        for (OfferRow row : offerRows) {
            if (row.offer.offerId().equals(offerId)) {
                return new Rect(row.getX(), row.getY(), row.getWidth(), row.getHeight());
            }
        }
        return new Rect(rightX, reqStartY, rightW, offerRowH);
    }

    /** Renders the fly/pulse/spark frames and closes the panel once the beat has landed. */
    private void renderBuyFx(GuiGraphics guiGraphics) {
        BuyFx fx = buyFx;
        if (fx == null) {
            return;
        }
        long elapsed = Util.getMillis() - fx.start;
        long closeMs = fx.reduced ? BUYFX_REDUCED_CLOSE_MS : BUYFX_CLOSE_MS;
        if (elapsed >= closeMs) {
            if (!fx.closeRequested) {
                fx.closeRequested = true;
                onClose(); // the world ceremony (AltarBuyCeremony) takes over from here
            }
            return;
        }
        if (fx.reduced) {
            return;
        }
        // Track the live row while it exists; keep the cached rect when it vanished.
        Rect live = rowRectFor(fx.offerId);
        fx.rowRect = live;
        int targetX = live.x() + live.w() / 2;
        int targetY = live.y() + live.h() / 2;
        int sourceX = footerIconX + 8;
        int sourceY = (fx.pooled ? footerPoolY : footerPersonalY) + 8;

        // --- phase 1: currency icons fly from the paying balance line into the row ---
        for (int i = 0; i < BUYFX_FLY_COUNT; i++) {
            float t = (elapsed - (long) i * BUYFX_FLY_STAGGER_MS) / (float) BUYFX_FLY_MS;
            if (t >= 1.0F && !fx.flyBlipPlayed[i]) {
                fx.flyBlipPlayed[i] = true;
                UiSounds.rouletteTick(1.0F + 0.06F * i);
            }
            if (t <= 0.0F || t >= 1.0F) {
                continue;
            }
            float eased = 1.0F - (1.0F - t) * (1.0F - t); // easeOutQuad toward the row
            float px = Mth.lerp(eased, sourceX, targetX);
            float py = Mth.lerp(eased, sourceY, targetY)
                    - Mth.sin((float) (Math.PI * t)) * (12.0F + 4.0F * (i % 3));
            float scale = 0.55F + 0.15F * Mth.sin((float) (Math.PI * t));
            guiGraphics.pose().pushPose();
            guiGraphics.pose().translate(px, py, 0.0F);
            guiGraphics.pose().scale(scale, scale, 1.0F);
            guiGraphics.renderItem(fx.currency, -8, -8);
            guiGraphics.pose().popPose();
        }

        // --- phase 2: the bought row pulses gold under a small spark burst ---
        float pulse = (elapsed - BUYFX_PULSE_START_MS) / (float) BUYFX_PULSE_MS;
        if (pulse >= 0.0F && pulse <= 1.0F) {
            if (!fx.winStingPlayed) {
                fx.winStingPlayed = true;
                UiSounds.rouletteWin();
            }
            float wave = Mth.sin((float) (Math.PI * pulse));
            int fill = EclipseUiTheme.withAlpha(GOLD, 0.30F * wave);
            guiGraphics.fill(live.x(), live.y(), live.x() + live.w(), live.y() + live.h(), fill);
            int ring = EclipseUiTheme.withAlpha(GOLD_BRIGHT, 0.85F * wave);
            guiGraphics.fill(live.x() - 1, live.y() - 1, live.x() + live.w() + 1, live.y(), ring);
            guiGraphics.fill(live.x() - 1, live.y() + live.h(),
                    live.x() + live.w() + 1, live.y() + live.h() + 1, ring);
            guiGraphics.fill(live.x() - 1, live.y(), live.x(), live.y() + live.h(), ring);
            guiGraphics.fill(live.x() + live.w(), live.y(),
                    live.x() + live.w() + 1, live.y() + live.h(), ring);

            // Sparkles: little gold crosses bursting outward, deterministic per index.
            for (int i = 0; i < BUYFX_SPARK_COUNT; i++) {
                float sparkT = Mth.clamp(pulse * 1.6F - i * 0.05F, 0.0F, 1.0F);
                if (sparkT <= 0.0F || sparkT >= 1.0F) {
                    continue;
                }
                float angle = (float) (i * Math.PI * 2.0D / BUYFX_SPARK_COUNT) + 0.7F * (i % 2);
                float dist = 6.0F + sparkT * 20.0F;
                int sx = Math.round(targetX + Mth.cos(angle) * dist * 1.6F);
                int sy = Math.round(targetY + Mth.sin(angle) * dist * 0.7F);
                int spark = EclipseUiTheme.withAlpha(GOLD_BRIGHT, 1.0F - sparkT);
                guiGraphics.fill(sx - 1, sy, sx + 2, sy + 1, spark);      // cross arm —
                guiGraphics.fill(sx, sy - 1, sx + 1, sy + 2, spark);      // cross arm |
            }
        }
    }

    /** Short red flash over a row whose buy the server refused (stale click, empty purse). */
    private void renderFailFlash(GuiGraphics guiGraphics) {
        if (failFlashStart == Long.MIN_VALUE) {
            return;
        }
        float t = (Util.getMillis() - failFlashStart) / (float) FAIL_FLASH_MS;
        if (t >= 1.0F) {
            failFlashStart = Long.MIN_VALUE;
            return;
        }
        Rect rect = rowRectFor(failOfferId);
        guiGraphics.fill(rect.x(), rect.y(), rect.x() + rect.w(), rect.y() + rect.h(),
                EclipseUiTheme.withAlpha(EclipseUiTheme.DANGER, 0.35F * (1.0F - t)));
    }

    // ------------------------------------------------------------------ rendering

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);
        EclipseUiTheme.drawPanel(guiGraphics, panelX, panelY, panelW, panelH);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        hoverTooltip = null;
        super.render(guiGraphics, mouseX, mouseY, partialTick);

        // Header line: title left, "Stage N · Day M" right.
        guiGraphics.drawString(this.font, this.title, leftX, panelY + 8, EclipseUiTheme.ACCENT);
        String stage = EclipseLang.trString("gui.eclipse.altar.stage", header.altarLevel(), header.day());
        guiGraphics.drawString(this.font, stage,
                panelX + panelW - EclipseUiTheme.PAD - this.font.width(stage), panelY + 8,
                EclipseUiTheme.TEXT);
        EclipseUiTheme.drawHairline(guiGraphics, leftX, panelX + panelW - EclipseUiTheme.PAD, panelY + 20);
        // F-074: a vertical hairline between the milestone column and the shop column —
        // the two halves used to bleed into each other on wide panels.
        int dividerX = rightX - (EclipseUiTheme.PAD + 1) / 2 - 1;
        guiGraphics.fill(dividerX, panelY + 24, dividerX + 1,
                panelY + panelH - EclipseUiTheme.PAD, EclipseUiTheme.HAIRLINE);

        int y = renderRequirements(guiGraphics, mouseX, mouseY);
        renderBossBlock(guiGraphics, y);
        renderShopFooter(guiGraphics);
        renderFailFlash(guiGraphics);
        renderBuyFx(guiGraphics);
        if (hoverTooltip != null && !modalActive()) {
            guiGraphics.renderComponentTooltip(this.font, hoverTooltip, mouseX, mouseY);
        }
        renderConfirmOverlay(guiGraphics, mouseX, mouseY);
        CursorManager.endFrame();
    }

    /** Left column: requirement rows (fly-in), sealed note, deposit hint, unseal line. */
    private int renderRequirements(GuiGraphics guiGraphics, int mouseX, int mouseY) {
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
            // F-074: the banked count carries the state color, the "/ needed" tail stays
            // quiet — and a ✓ marks finished lines without reading the numbers at all.
            String banked = (done ? "\u2713 " : "") + requirement.progress();
            String needed = " / " + requirement.required();
            int neededW = this.font.width(needed);
            int bankedW = this.font.width(banked);
            String name = EclipseUiTheme.ellipsize(this.font,
                    stack.getHoverName().getString(), leftW - 20 - bankedW - neededW - 6);
            guiGraphics.drawString(this.font, name, leftX + 20, rowY + 1, EclipseUiTheme.TEXT);
            guiGraphics.drawString(this.font, needed, leftX + leftW - neededW, rowY + 1,
                    EclipseUiTheme.DIM);
            guiGraphics.drawString(this.font, banked, leftX + leftW - neededW - bankedW, rowY + 1,
                    done ? EclipseUiTheme.GOOD : EclipseUiTheme.ACCENT);
            // F-074: 4px progress bar on a full-width underlay (was a floating 3px sliver).
            int barX = leftX + 20;
            int barW = leftW - 20;
            int fillW = (int) (barW * Math.min(1.0D,
                    requirement.progress() / (double) requirement.required()));
            guiGraphics.fill(barX, rowY + 13, barX + barW, rowY + 17, EclipseUiTheme.HAIRLINE);
            if (fillW > 0) {
                guiGraphics.fill(barX, rowY + 13, barX + fillW, rowY + 17,
                        done ? EclipseUiTheme.GOOD : EclipseUiTheme.ACCENT);
            }
            // F-074 hover detail: long item names ellipsize on narrow panels — hovering
            // the row shows the full name and the exact banked/needed numbers.
            if (mouseX >= leftX && mouseX < leftX + leftW
                    && mouseY >= rowY && mouseY < rowY + REQ_ROW_H) {
                hoverTooltip = List.of(
                        stack.getHoverName(),
                        Component.literal(requirement.progress() + " / " + requirement.required()));
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
        // F-074: the multi-paragraph fight instructions were the least readable text on
        // the panel in DIM — lift them most of the way to full text contrast.
        int bodyColor = EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, 0.85F);
        for (FormattedCharSequence line : this.font.split(
                EclipseLang.tr("gui.eclipse.altar.boss." + hint + ".body"), leftW)) {
            if (y + EclipseUiTheme.ROW > bottom) {
                break; // never spill out of the panel on tiny windows
            }
            guiGraphics.drawString(this.font, line, leftX, y, bodyColor);
            y += EclipseUiTheme.ROW;
        }
    }

    /** Right column header + the balances under the offer rows (real + sealed). */
    private void renderShopFooter(GuiGraphics guiGraphics) {
        EclipseUiTheme.drawHeader(guiGraphics, this.font,
                EclipseLang.tr("gui.eclipse.altar.shop.title"), rightX, panelY + 26, rightW);
        int y = shopFooterY;
        EclipseUiTheme.drawHairline(guiGraphics, rightX, rightX + rightW, y - 2);
        // F-074: both balances lead with the actual currency ITEM icon — the same icon
        // the price chips use, so "which splinter pays" is one glance, not a tooltip.
        footerIconX = rightX;
        footerPersonalY = y + 1;
        footerPoolY = y + 1 + EclipseUiTheme.ROW + 6;
        int textX = rightX;
        if (!footerCurrency.isEmpty()) {
            guiGraphics.renderItem(footerCurrency, footerIconX, footerPersonalY);
            guiGraphics.renderItem(footerCurrency, footerIconX, footerPoolY);
            textX = rightX + 20;
        }
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font,
                EclipseLang.trString("gui.eclipse.altar.shards.personal", header.personalShards()),
                rightX + rightW - textX), textX, footerPersonalY + 4, EclipseUiTheme.TEXT);
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font,
                EclipseLang.trString("gui.eclipse.altar.shards.pool", header.poolShards()),
                rightX + rightW - textX), textX, footerPoolY + 4, EclipseUiTheme.DIM);
    }

    // ------------------------------------------------------------------ confirm overlay

    /**
     * F-074 modal confirmation: reward icon + name, itemised price (count × currency
     * icon + name), which purse pays and what it holds AFTER the buy — or how far short
     * it is (Kaufen disabled). Enter/Kaufen confirms, Esc/Abbrechen/outside-click cancels.
     * Drawn AFTER every panel layer so nothing bleeds through; the buttons are plain
     * rect hit-tests (widgets would render UNDER this overlay — z-order law of
     * {@code super.render}).
     */
    private void renderConfirmOverlay(GuiGraphics guiGraphics, int mouseX, int mouseY) {
        AltarPayloads.ShopEntry offer = confirmOffer;
        if (offer == null) {
            return;
        }
        // Veil the whole panel so the dialog is unmistakably modal.
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);

        int cx = (this.width - CONFIRM_W) / 2;
        int cy = (this.height - CONFIRM_H) / 2;
        confirmPanelRect = new Rect(cx, cy, CONFIRM_W, CONFIRM_H);
        EclipseUiTheme.drawPanel(guiGraphics, cx, cy, CONFIRM_W, CONFIRM_H);
        int innerX = cx + EclipseUiTheme.PAD;
        int innerW = CONFIRM_W - 2 * EclipseUiTheme.PAD;
        int y = EclipseUiTheme.drawHeader(guiGraphics, this.font,
                EclipseLang.tr("gui.eclipse.altar.confirm.title"), innerX, cy + 8, innerW);

        // What you are buying: the reward item's own icon (currency icon for the
        // non-item team offers) + the offer name.
        ItemStack reward = offer.rewardItemId().isEmpty()
                ? new ItemStack(resolveItem(offer.currencyItemId()))
                : new ItemStack(resolveItem(offer.rewardItemId()));
        guiGraphics.renderItem(reward, innerX, y);
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font,
                EclipseLang.trString(offer.nameKey()), innerW - 22),
                innerX + 22, y + 4, EclipseUiTheme.TEXT);
        y += 20;

        // Itemised price: count × currency icon + real currency name, then the purse.
        ItemStack currency = new ItemStack(resolveItem(offer.currencyItemId()));
        String price = EclipseLang.trString("gui.eclipse.altar.confirm.price",
                offer.cost(), currency.getHoverName().getString());
        guiGraphics.renderItem(currency, innerX, y - 2);
        boolean affordable = canAfford(offer);
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font, price, innerW - 22),
                innerX + 22, y + 2, affordable ? EclipseUiTheme.ACCENT : EclipseUiTheme.DANGER);
        y += 16;
        String purse = EclipseLang.trString(offer.pooled()
                ? "gui.eclipse.altar.shop.pooled" : "gui.eclipse.altar.shop.personal");
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font, purse, innerW),
                innerX, y, EclipseUiTheme.DIM);
        y += EclipseUiTheme.ROW;
        String outcome = affordable
                ? EclipseLang.trString("gui.eclipse.altar.confirm.after",
                        purseBalance(offer) - offer.cost())
                : EclipseLang.trString("gui.eclipse.altar.shop.short_by",
                        offer.cost() - purseBalance(offer));
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font, outcome, innerW),
                innerX, y, affordable ? EclipseUiTheme.GOOD : EclipseUiTheme.DANGER);

        // Keyboard hint just above the buttons.
        String hint = EclipseLang.trString("gui.eclipse.altar.confirm.hint");
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font, hint, innerW),
                innerX, cy + CONFIRM_H - EclipseUiTheme.PAD - CONFIRM_BUTTON_H - 13,
                EclipseUiTheme.DIM);

        // Buttons: Abbrechen (quiet) left, Kaufen (accent, disabled while short) right.
        int buttonW = (innerW - EclipseUiTheme.PAD) / 2;
        int buttonY = cy + CONFIRM_H - EclipseUiTheme.PAD - CONFIRM_BUTTON_H;
        confirmCancelRect = new Rect(innerX, buttonY, buttonW, CONFIRM_BUTTON_H);
        confirmBuyRect = new Rect(innerX + buttonW + EclipseUiTheme.PAD, buttonY,
                buttonW, CONFIRM_BUTTON_H);
        drawOverlayButton(guiGraphics, confirmCancelRect,
                EclipseLang.trString("gui.eclipse.altar.confirm.cancel"),
                mouseX, mouseY, false, true);
        drawOverlayButton(guiGraphics, confirmBuyRect,
                EclipseLang.trString("gui.eclipse.altar.confirm.buy"),
                mouseX, mouseY, true, affordable);
    }

    /** One flat overlay button: accent fill for the primary action, raised fill otherwise. */
    private void drawOverlayButton(GuiGraphics guiGraphics, Rect rect, String label,
            int mouseX, int mouseY, boolean primary, boolean enabled) {
        boolean hovered = enabled && rect.contains(mouseX, mouseY);
        int fill;
        int textColor;
        if (!enabled) {
            fill = EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, 0.6F);
            textColor = EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, 0.6F);
        } else if (primary) {
            fill = hovered ? EclipseUiTheme.ACCENT : EclipseUiTheme.ACCENT_DEEP;
            textColor = 0xFF120B1E; // dark label on the accent fill
        } else {
            fill = hovered
                    ? EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 1.0F)
                    : EclipseUiTheme.PANEL_RAISED;
            textColor = EclipseUiTheme.TEXT;
        }
        guiGraphics.fill(rect.x(), rect.y(), rect.x() + rect.w(), rect.y() + rect.h(), fill);
        int border = hovered ? EclipseUiTheme.ACCENT : EclipseUiTheme.HAIRLINE;
        guiGraphics.fill(rect.x(), rect.y(), rect.x() + rect.w(), rect.y() + 1, border);
        guiGraphics.fill(rect.x(), rect.y() + rect.h() - 1,
                rect.x() + rect.w(), rect.y() + rect.h(), border);
        guiGraphics.fill(rect.x(), rect.y(), rect.x() + 1, rect.y() + rect.h(), border);
        guiGraphics.fill(rect.x() + rect.w() - 1, rect.y(),
                rect.x() + rect.w(), rect.y() + rect.h(), border);
        String clamped = EclipseUiTheme.ellipsize(this.font, label, rect.w() - 8);
        guiGraphics.drawString(this.font, clamped,
                rect.x() + (rect.w() - this.font.width(clamped)) / 2,
                rect.y() + (rect.h() - 8) / 2 + 1, textColor);
        if (hovered) {
            CursorManager.requestPointer();
        }
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

    /** Simple immutable pixel rect for the overlay hit-tests and the buy-animation target. */
    private record Rect(int x, int y, int w, int h) {
        boolean contains(double mx, double my) {
            return mx >= x && mx < x + w && my >= y && my < y + h;
        }
    }

    // ------------------------------------------------------------------ shop rows

    /**
     * One clickable shop offer (only currently purchasable offers ever arrive).
     *
     * <p>ALTARFIX2 #4: the price is shown as the currency ITEM (icon + its real display
     * name) times the count, plus which purse pays — "20 Splitter" alone was ambiguous
     * between Umbrasplitter, Vitae-Splitter and Glitch-Splitter, and said nothing about
     * the personal balance vs. the team pool. {@code cost} and {@code currencyItemId}
     * both arrive from the same server-side {@code Offer} that gets charged.</p>
     *
     * <p>F-074: the row leads with a 2px affordability edge (green = buyable now, red =
     * short), the price sits in a framed chip (count + icon) so it reads as ONE unit,
     * and a click opens the confirmation overlay instead of buying blind.</p>
     */
    private final class OfferRow extends EclipseWidget {
        /** Square size the currency icon is drawn at (vanilla item sprite). */
        private static final int ICON = 16;

        private final AltarPayloads.ShopEntry offer;
        private final ItemStack currency;

        OfferRow(AltarPayloads.ShopEntry offer, int x, int y, int width, int height) {
            super(x, y, width, height, EclipseLang.tr(offer.nameKey()));
            this.offer = offer;
            this.currency = new ItemStack(resolveItem(offer.currencyItemId()));
            refreshTooltip(true);
        }

        /** (Re)arms or silences the price tooltip (silenced while a modal layer is open). */
        void refreshTooltip(boolean enabled) {
            setTooltip(enabled ? Tooltip.create(priceTooltip()) : null);
        }

        /** Held amount of the purse this offer is charged against (same source as the row). */
        private int purseBalance() {
            return offer.pooled() ? header.poolShards() : header.personalShards();
        }

        /**
         * The itemised price breakdown: what the offer is, how many of WHICH item it
         * costs, which purse pays, what that purse currently holds and — when it is not
         * enough — how far short it is. Rebuilt on every panel refresh (the screen calls
         * {@code rebuildWidgets()} after each snapshot), so the balances never go stale.
         */
        private Component priceTooltip() {
            String currencyName = currency.getHoverName().getString();
            MutableComponent tooltip = Component.empty()
                    .append(EclipseLang.tr(offer.nameKey()))
                    .append("\n")
                    .append(EclipseLang.tr("gui.eclipse.altar.shop.cost", offer.cost(), currencyName))
                    .append("\n")
                    .append(EclipseLang.tr(offer.pooled()
                            ? "gui.eclipse.altar.shop.pooled" : "gui.eclipse.altar.shop.personal"))
                    .append("\n")
                    .append(EclipseLang.tr(offer.pooled()
                                    ? "gui.eclipse.altar.shop.have.pooled"
                                    : "gui.eclipse.altar.shop.have.personal",
                            purseBalance(), currencyName));
            int missing = offer.cost() - purseBalance();
            tooltip.append("\n").append(missing > 0
                    ? EclipseLang.tr("gui.eclipse.altar.shop.short_by", missing)
                    : EclipseLang.tr("gui.eclipse.altar.shop.buy_hint"));
            return tooltip;
        }

        @Override
        protected void onHoverStart() {
            if (!modalActive()) {
                super.onHoverStart();
            }
        }

        @Override
        protected void whileHovered() {
            if (!modalActive()) {
                super.whileHovered();
            }
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            // F-074: no blind buys — the click opens the confirmation overlay; only the
            // confirmed second click (Kaufen/Enter) sends C2SAltarBuyPayload.
            if (!modalActive()) {
                openConfirm(offer);
            }
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            guiGraphics.fill(getX(), getY(), getX() + width, getY() + height,
                    EclipseUiTheme.PANEL_RAISED);
            boolean affordable = purseBalance() >= offer.cost();
            // F-074 affordability edge: scannable buyable/short state without reading.
            guiGraphics.fill(getX(), getY(), getX() + 2, getY() + height,
                    affordable ? EclipseUiTheme.GOOD : EclipseUiTheme.DANGER);

            // F-074 price chip on the right edge: count + currency icon in ONE framed
            // unit, so the price never blurs into the offer name.
            String count = EclipseLang.trString("gui.eclipse.altar.shop.count", offer.cost());
            int countW = AltarScreen.this.font.width(count);
            int chipW = countW + ICON + 8;
            int chipX = getX() + width - chipW - 3;
            int chipY0 = getY() + 2;
            int chipY1 = getY() + height - 2;
            guiGraphics.fill(chipX, chipY0, chipX + chipW, chipY1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, 0.75F));
            guiGraphics.fill(chipX, chipY0, chipX + chipW, chipY0 + 1, EclipseUiTheme.HAIRLINE);
            guiGraphics.fill(chipX, chipY1 - 1, chipX + chipW, chipY1, EclipseUiTheme.HAIRLINE);
            guiGraphics.fill(chipX, chipY0, chipX + 1, chipY1, EclipseUiTheme.HAIRLINE);
            guiGraphics.fill(chipX + chipW - 1, chipY0, chipX + chipW, chipY1, EclipseUiTheme.HAIRLINE);
            guiGraphics.drawString(AltarScreen.this.font, count, chipX + 4,
                    getY() + (height - 8) / 2,
                    affordable ? EclipseUiTheme.ACCENT : EclipseUiTheme.DANGER);
            guiGraphics.renderItem(currency, chipX + chipW - ICON - 2, getY() + (height - ICON) / 2);

            int textW = chipX - getX() - 10;
            guiGraphics.drawString(AltarScreen.this.font,
                    EclipseUiTheme.ellipsize(AltarScreen.this.font, getMessage().getString(), textW),
                    getX() + 6, getY() + 4, EclipseUiTheme.TEXT);

            // Second line names the currency outright and says which purse pays for it.
            String detail = currency.getHoverName().getString() + " · " + EclipseLang.trString(
                    offer.pooled() ? "gui.eclipse.altar.shop.pooled" : "gui.eclipse.altar.shop.personal");
            if (offer.remainingSeconds() > 0) {
                detail += " · " + EclipseLang.trString("gui.eclipse.altar.shop.remaining",
                        formatSeconds(offer.remainingSeconds()));
            }
            guiGraphics.drawString(AltarScreen.this.font,
                    EclipseUiTheme.ellipsize(AltarScreen.this.font, detail, textW),
                    getX() + 6, getY() + height - 11, EclipseUiTheme.DIM);
        }
    }

    /**
     * One sealed shop slot (AUDITFIX-3): the server sends only a COUNT of not-yet-unlocked
     * offers, so this row knows nothing it could spoil — it renders "???" over the sealed
     * caption and stays fully inert (no click, no hover blip, no pointer cursor).
     */
    private final class SealedRow extends EclipseWidget {
        private static final float SEALED_ALPHA = 0.45F;

        SealedRow(int x, int y, int width, int height) {
            super(x, y, width, height, EclipseLang.tr("gui.eclipse.altar.shop.sealed"));
            this.active = false;
        }

        @Override
        protected void onHoverStart() {
            // Inert: no blip — there is nothing here to interact with.
        }

        @Override
        protected void whileHovered() {
            // Inert: no pointer cursor either.
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            guiGraphics.fill(getX(), getY(), getX() + width, getY() + height,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, SEALED_ALPHA));
            guiGraphics.drawString(AltarScreen.this.font, "???", getX() + 6, getY() + 4,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, SEALED_ALPHA));
            guiGraphics.drawString(AltarScreen.this.font,
                    EclipseUiTheme.ellipsize(AltarScreen.this.font,
                            getMessage().getString(), width - 12),
                    getX() + 6, getY() + height - 11,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, SEALED_ALPHA));
        }
    }
}
