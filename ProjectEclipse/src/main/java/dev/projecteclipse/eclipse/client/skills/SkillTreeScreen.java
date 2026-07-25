package dev.projecteclipse.eclipse.client.skills;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.client.wand.WandProgressPanel;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.C2SSkillNodeBuyPayload;
import dev.projecteclipse.eclipse.skills.XpGates;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;
import org.lwjgl.glfw.GLFW;

import javax.annotation.Nullable;

/**
 * The skill tree screen (WB-SKILLS, plan §3.9 / design system §2 "Quiet Eclipse"; wave-5
 * A14 rework). One centered flat panel over the {@link EclipseUiTheme#VEIL} dim: header
 * row (title left; level, XP and unspent points right), a <b>tab strip</b>
 * ("Skills" | "Zauberstab" — the wand progression is reachable here any time, D10), the
 * {@link SkillTreeWidget} canvas at full width, a detail footer for the selected node
 * with the buy button, and the <b>rebirth strip</b> (count + next umbral-splinter cost +
 * hold-to-confirm button; locked until W-REBIRTH's sync arrives / the cost is covered).
 * Opens via the K keybind ({@link SkillKeybind}) or the inventory button
 * ({@link InventorySkillButton}); closes on ESC or the same binding (keyboard AND
 * mouse-bound, the handbook's B8 parity). TAB switches between the two tabs.
 *
 * <p><b>Zero desync:</b> the tree renders live from {@code ClientStateCache} every frame
 * — the server's {@code S2CSkillTreePayload}/{@code S2CSkillStatePayload} are the only
 * truth. A buy (footer button or <b>double-click on a node</b>; nodes costing
 * {@value #CONFIRM_COST}+ points arm a confirm step first) sends
 * {@code C2SSkillNodeBuyPayload} and locks the node in a PENDING state (padlock overlay,
 * footer button disabled); the lock resolves when the refreshed owned-node list arrives
 * (success → purchase celebration + {@code ui.skill_buy}) or clears after a short timeout
 * (failure — the server already showed the reason on the action bar). The client never
 * adds nodes or spends points locally.</p>
 *
 * <p>Motion follows §2.3: 5-tick fade + 4px rise on open/close ({@code reducedFx} snaps).
 * Cursor lifecycle: {@link CursorManager#endFrame()} once per frame,
 * {@link CursorManager#reset()} in {@link #removed()}.</p>
 */
@OnlyIn(Dist.CLIENT)
public class SkillTreeScreen extends Screen {
    private static final float PANEL_PCT = 0.92F;
    private static final int MAX_PANEL_W = 760;
    private static final int MAX_PANEL_H = 420;
    private static final int HEADER_H = 25;
    /** Tab strip row: "Skills" | "Zauberstab" (A14 §4). */
    private static final int TAB_H = 18;
    private static final int TAB_W = 100;
    /** Detail footer (46) + rebirth strip (20). */
    private static final int FOOTER_H = 66;
    private static final int REBIRTH_H = 20;
    private static final int OPEN_TICKS = 5;
    private static final int RISE_PX = 4;
    /** Pending-purchase failsafe: unlock after 3s if no state refresh resolves it. */
    private static final int PENDING_TIMEOUT_TICKS = 60;
    /** Nodes costing this many points or more keep a confirm step on buy (A14 §2). */
    private static final int CONFIRM_COST = 3;
    private static final long CONFIRM_WINDOW_MILLIS = 4000L;

    private enum Tab {
        SKILLS, WAND
    }

    private SkillTreeWidget canvas;
    private WandProgressPanel wandPanel;
    private BuyButton buyButton;
    private RebirthHoldButton rebirthButton;
    private TabButton tabSkills;
    private TabButton tabWand;

    private Tab tab = Tab.SKILLS;

    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;
    private int contentX;
    private int contentY;
    private int contentW;
    private int contentH;
    private int footerY;

    private int openTicks;
    private boolean closing;
    private int closeTicks;

    @Nullable
    private String selectedNodeId;
    @Nullable
    private String pendingNodeId;
    private int pendingTicks;
    /** Armed confirm step for a point-costly node (double-click/buy again to execute). */
    @Nullable
    private String confirmNodeId;
    private long confirmExpireMillis;

    /** Owned-node snapshot for purchase-confirmation detection (server truth diffing). */
    private Set<String> knownOwned = new HashSet<>();

    public SkillTreeScreen() {
        super(EclipseLang.tr("gui.eclipse.skills.title"));
        knownOwned = new HashSet<>(ClientStateCache.skillOwnedNodes);
    }

    @Override
    protected void init() {
        panelW = Math.min(Math.round(this.width * PANEL_PCT), MAX_PANEL_W);
        panelH = Math.min(Math.round(this.height * PANEL_PCT), MAX_PANEL_H);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        contentX = panelX + 1;
        int tabY = panelY + HEADER_H + 1;
        contentY = panelY + HEADER_H + TAB_H + 1;
        contentW = panelW - 2;
        footerY = panelY + panelH - FOOTER_H;
        contentH = Math.max(60, footerY - contentY);

        int tabWidth = Math.min(TAB_W, (panelW - 2) / 2);
        tabSkills = addRenderableWidget(new TabButton(contentX, tabY, tabWidth, TAB_H - 1,
                Tab.SKILLS, EclipseLang.tr("gui.eclipse.skills.tab.skills")));
        tabWand = addRenderableWidget(new TabButton(contentX + tabWidth, tabY, tabWidth, TAB_H - 1,
                Tab.WAND, EclipseLang.tr("gui.eclipse.skills.tab.wand")));

        canvas = addRenderableWidget(new SkillTreeWidget(contentX, contentY, contentW, contentH,
                this::onNodeSelected, this::handleBuyIntent));
        canvas.select(selectedNodeId);
        canvas.setPendingNode(pendingNodeId);

        // The wand tab has no node footer — the panel gets the full content height.
        int wandH = Math.max(60, panelY + panelH - 1 - contentY);
        wandPanel = addRenderableWidget(new WandProgressPanel(contentX, contentY, contentW, wandH));

        int buyW = 92;
        buyButton = addRenderableWidget(new BuyButton(
                panelX + panelW - EclipseUiTheme.PAD - buyW, footerY + 13, buyW, 20));

        int rebirthW = 88;
        rebirthButton = addRenderableWidget(new RebirthHoldButton(
                panelX + panelW - EclipseUiTheme.PAD - rebirthW,
                panelY + panelH - REBIRTH_H + 3, rebirthW, 14));

        applyTab(tab);
    }

    private void onNodeSelected(String nodeId) {
        if (!nodeId.equals(selectedNodeId)) {
            confirmNodeId = null;
        }
        selectedNodeId = nodeId;
        updateBuyButton();
    }

    // ------------------------------------------------------------------
    // Tabs (A14 §4: wand progression findable any time)
    // ------------------------------------------------------------------

    private void applyTab(Tab newTab) {
        tab = newTab;
        boolean skills = tab == Tab.SKILLS;
        canvas.visible = skills;
        canvas.active = skills;
        wandPanel.visible = !skills;
        wandPanel.active = !skills;
        rebirthButton.visible = skills;
        tabSkills.selected = skills;
        tabWand.selected = !skills;
        updateBuyButton();
    }

    private void switchTab(Tab newTab) {
        if (tab != newTab) {
            UiSounds.tab();
            applyTab(newTab);
        }
    }

    // ------------------------------------------------------------------
    // Buy flow (server-validated; optimistic pending lock only)
    // ------------------------------------------------------------------

    /**
     * Buy intent from the footer button or a node double-click (A14 §2): affordable
     * cheap nodes buy immediately; nodes costing {@value #CONFIRM_COST}+ points arm a
     * confirm window first — the next intent inside it executes.
     */
    private void handleBuyIntent(String nodeId) {
        if (tab != Tab.SKILLS) {
            return;
        }
        SkillTreeModel model = SkillTreeModel.current();
        SkillTreeModel.Node node = nodeId != null ? model.nodes().get(nodeId) : null;
        if (node == null || pendingNodeId != null
                || model.stateOf(node) == SkillTreeModel.State.OWNED) {
            return;
        }
        if (!model.affordable(node)) {
            UiSounds.error();
            return;
        }
        long now = Util.getMillis();
        boolean confirmed = node.id.equals(confirmNodeId) && now <= confirmExpireMillis;
        if (node.cost >= CONFIRM_COST && !confirmed) {
            confirmNodeId = node.id;
            confirmExpireMillis = now + CONFIRM_WINDOW_MILLIS;
            UiSounds.hover();
            updateBuyButton();
            return;
        }
        requestBuy(node);
    }

    private void requestBuy(SkillTreeModel.Node node) {
        confirmNodeId = null;
        pendingNodeId = node.id;
        pendingTicks = 0;
        canvas.setPendingNode(pendingNodeId);
        PacketDistributor.sendToServer(new C2SSkillNodeBuyPayload(node.id));
        updateBuyButton();
    }

    @Override
    public void tick() {
        // LIMBOFIX belt-and-braces: the keybind refuses to open in event dimensions, but
        // the limbo door / a teleport can move the player while the tree is open — close
        // it and hint why (the same line the keybind shows).
        if (!closing && this.minecraft.player != null
                && XpGates.isEventDimension(this.minecraft.player.level().dimension())) {
            this.minecraft.player.displayClientMessage(
                    EclipseLang.tr("message.eclipse.skills.sealed_in_limbo"), true);
            onClose();
            return;
        }
        if (openTicks < OPEN_TICKS) {
            openTicks++;
        }
        if (closing && --closeTicks <= 0) {
            this.minecraft.setScreen(null);
            return;
        }

        // Server-truth diff: every node that flipped to OWNED celebrates exactly once —
        // whether it was our pending buy, a /skills buy fallback or an admin grant.
        List<String> ownedNow = ClientStateCache.skillOwnedNodes;
        if (ownedNow.size() != knownOwned.size() || !knownOwned.containsAll(ownedNow)) {
            for (String id : ownedNow) {
                if (!knownOwned.contains(id)) {
                    canvas.onNodePurchased(id);
                    if (id.equals(pendingNodeId)) {
                        pendingNodeId = null;
                        canvas.setPendingNode(null);
                    }
                }
            }
            knownOwned = new HashSet<>(ownedNow);
        }

        // Failure resolution: the server refused (action-bar reason already shown) — the
        // state refresh won't contain the node, so release the lock after the failsafe.
        if (pendingNodeId != null && ++pendingTicks > PENDING_TIMEOUT_TICKS) {
            pendingNodeId = null;
            canvas.setPendingNode(null);
        }
        if (confirmNodeId != null && Util.getMillis() > confirmExpireMillis) {
            confirmNodeId = null;
        }
        updateBuyButton();
        rebirthButton.tickState();
    }

    private void updateBuyButton() {
        if (buyButton == null) {
            return;
        }
        SkillTreeModel model = SkillTreeModel.current();
        SkillTreeModel.Node node = selectedNodeId != null ? model.nodes().get(selectedNodeId) : null;
        boolean pending = pendingNodeId != null;
        buyButton.visible = tab == Tab.SKILLS && node != null
                && model.stateOf(node) != SkillTreeModel.State.OWNED;
        buyButton.active = node != null && !pending && model.affordable(node);
        buyButton.pending = pending && node != null && node.id.equals(pendingNodeId);
        buyButton.confirming = !pending && node != null && node.id.equals(confirmNodeId);
    }

    private boolean confirmArmedFor(SkillTreeModel.Node node) {
        return node.id.equals(confirmNodeId) && Util.getMillis() <= confirmExpireMillis;
    }

    // ------------------------------------------------------------------
    // Animation state (§2.3 open/close)
    // ------------------------------------------------------------------

    private float panelProgress(float partialTick) {
        if (EclipseClientConfig.reducedFx()) {
            return closing ? 0.0F : 1.0F;
        }
        if (closing) {
            return Mth.clamp((closeTicks - partialTick) / OPEN_TICKS, 0.0F, 1.0F);
        }
        return Mth.clamp((openTicks + partialTick) / OPEN_TICKS, 0.0F, 1.0F);
    }

    private float panelAlpha(float partialTick) {
        return easeOutCubic(panelProgress(partialTick));
    }

    private int panelRise(float partialTick) {
        return Math.round((1.0F - easeOutCubic(panelProgress(partialTick))) * RISE_PX);
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - t;
        return 1.0F - inv * inv * inv;
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        if (tab == Tab.SKILLS) {
            renderNodeTooltip(guiGraphics, mouseX, mouseY);
        }
        CursorManager.endFrame();
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        float alpha = panelAlpha(partialTick);
        int rise = panelRise(partialTick);
        int py = panelY + rise;
        wandPanel.setAlpha(alpha);

        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        EclipseUiTheme.drawPanel(guiGraphics, panelX, py, panelW, panelH, alpha);

        renderHeader(guiGraphics, py, alpha);
        // Hairline under the tab strip (the buttons draw their own active underline).
        EclipseUiTheme.drawHairline(guiGraphics, panelX + 1, panelX + panelW - 1,
                py + HEADER_H + TAB_H, alpha);

        if (tab == Tab.SKILLS) {
            renderFooter(guiGraphics, py, alpha);
            renderRebirthStrip(guiGraphics, py, alpha);
            if (SkillTreeModel.current().isEmpty()) {
                guiGraphics.drawCenteredString(this.font, EclipseLang.tr("gui.eclipse.skills.empty"),
                        panelX + panelW / 2, contentY + contentH / 2 - 4,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            }
        }
    }

    /** Header: title left (ACCENT), "Level N · x/y XP · ◇ P" glance right, hairline under. */
    private void renderHeader(GuiGraphics guiGraphics, int py, float alpha) {
        int textY = py + 9;
        int left = panelX + EclipseUiTheme.PAD;
        int right = panelX + panelW - EclipseUiTheme.PAD;

        String glance = EclipseLang.trString("gui.eclipse.skills.header",
                ClientStateCache.skillLevel,
                ClientStateCache.skillXpIntoLevel,
                Math.max(1, ClientStateCache.skillXpForLevel),
                ClientStateCache.skillUnspent);
        int glanceW = this.font.width(glance);
        if (glanceW <= panelW - 2 * EclipseUiTheme.PAD - 70) {
            guiGraphics.drawString(this.font, glance, right - glanceW, textY,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        } else {
            glanceW = 0;
        }

        int titleMax = panelW - 2 * EclipseUiTheme.PAD - (glanceW > 0 ? glanceW + 10 : 0);
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, this.title.getString(), Math.max(20, titleMax)),
                left, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        EclipseUiTheme.drawHairline(guiGraphics, panelX + 1, panelX + panelW - 1, py + HEADER_H, alpha);
    }

    /** Detail footer: selected node's icon, title, desc + cost/state; hint when idle. */
    private void renderFooter(GuiGraphics guiGraphics, int py, float alpha) {
        int hairY = py + (footerY - panelY);
        EclipseUiTheme.drawHairline(guiGraphics, panelX + 1, panelX + panelW - 1, hairY, alpha);
        int left = panelX + EclipseUiTheme.PAD;
        int textW = panelW - 2 * EclipseUiTheme.PAD - 100; // room for the buy button

        SkillTreeModel model = SkillTreeModel.current();
        SkillTreeModel.Node node = selectedNodeId != null ? model.nodes().get(selectedNodeId) : null;
        if (node == null) {
            guiGraphics.drawString(this.font,
                    EclipseUiTheme.ellipsize(this.font,
                            EclipseLang.trString("gui.eclipse.skills.footer_hint"), panelW - 2 * EclipseUiTheme.PAD),
                    left, hairY + 18, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
            return;
        }

        String locale = SkillTreeModel.pickLocale();
        guiGraphics.renderItem(node.icon(), left, hairY + 12);
        int titleX = left + 20;
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, node.title.pick(locale), textW - 20),
                titleX, hairY + 8, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, node.desc.pick(locale), textW - 20),
                titleX, hairY + 19, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));

        String status = EclipseLang.trString("gui.eclipse.skills.cost", node.cost) + " · " + stateLine(model, node);
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font, status, textW - 20),
                titleX, hairY + 30, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
    }

    /**
     * Rebirth strip (A14 §3, UI half of the D11/A13 rebirth service): count + next
     * umbral-splinter cost left, the hold-to-confirm button right. LOCKED (dim, inert)
     * until W-REBIRTH's {@code S2CRebirthStatePayload} arrives and the synced personal
     * splinter balance covers the cost.
     */
    private void renderRebirthStrip(GuiGraphics guiGraphics, int py, float alpha) {
        int stripTop = py + panelH - REBIRTH_H;
        EclipseUiTheme.drawHairline(guiGraphics, panelX + 1, panelX + panelW - 1, stripTop, alpha);
        int left = panelX + EclipseUiTheme.PAD;
        int textW = panelW - 2 * EclipseUiTheme.PAD - 96; // room for the hold button

        String line;
        int color;
        if (!ClientRebirthState.synced) {
            line = EclipseLang.trString("gui.eclipse.skills.rebirth.locked");
            color = EclipseUiTheme.DIM;
        } else if (rebirthButton.holding() || rebirthButton.isHoveredOrFocused()) {
            line = EclipseLang.trString("gui.eclipse.skills.rebirth.warning");
            color = EclipseUiTheme.DANGER;
        } else {
            line = EclipseLang.trString("gui.eclipse.skills.rebirth.status",
                    ClientRebirthState.count, ClientRebirthState.nextCostShards,
                    ClientStateCache.sidebarShards);
            color = rebirthButton.costCovered() ? EclipseUiTheme.TEXT : EclipseUiTheme.DIM;
        }
        guiGraphics.drawString(this.font, EclipseUiTheme.ellipsize(this.font, line, textW),
                left, stripTop + 6, EclipseUiTheme.withAlpha(color, alpha));
    }

    private String stateLine(SkillTreeModel model, SkillTreeModel.Node node) {
        if (node.id.equals(pendingNodeId)) {
            return EclipseLang.trString("gui.eclipse.skills.buy_pending");
        }
        if (confirmArmedFor(node)) {
            return EclipseLang.trString("gui.eclipse.skills.state.confirm");
        }
        return switch (model.stateOf(node)) {
            case OWNED -> EclipseLang.trString("gui.eclipse.skills.state.owned");
            case AVAILABLE -> ClientStateCache.skillUnspent >= node.cost
                    ? EclipseLang.trString("gui.eclipse.skills.state.available")
                    : EclipseLang.trString("gui.eclipse.skills.state.no_points");
            case LOCKED -> EclipseLang.trString("gui.eclipse.skills.requires",
                    String.join(", ", missingPrereqNames(model, node)));
        };
    }

    private List<String> missingPrereqNames(SkillTreeModel model, SkillTreeModel.Node node) {
        String locale = SkillTreeModel.pickLocale();
        List<String> names = new ArrayList<>();
        for (String req : node.requires) {
            if (!ClientStateCache.skillOwnedNodes.contains(req)) {
                SkillTreeModel.Node parent = model.nodes().get(req);
                names.add(parent != null ? parent.title.pick(locale) : req);
            }
        }
        return names;
    }

    /** Themed hover tooltip: title, wrapped desc (exact numbers), cost + state, on top of all. */
    private void renderNodeTooltip(GuiGraphics guiGraphics, int mouseX, int mouseY) {
        String hoveredId = canvas != null ? canvas.hoveredNodeId() : null;
        if (hoveredId == null || closing) {
            return;
        }
        SkillTreeModel model = SkillTreeModel.current();
        SkillTreeModel.Node node = model.nodes().get(hoveredId);
        if (node == null) {
            return;
        }
        String locale = SkillTreeModel.pickLocale();

        int wrapW = 170;
        List<FormattedCharSequence> descLines =
                this.font.split(Component.literal(node.desc.pick(locale)), wrapW);
        String costLine = EclipseLang.trString("gui.eclipse.skills.cost", node.cost)
                + " · " + stateLine(model, node);

        int tipW = Math.max(this.font.width(node.title.pick(locale)),
                Math.max(this.font.width(costLine),
                        descLines.stream().mapToInt(this.font::width).max().orElse(0))) + 2 * 6;
        tipW = Math.min(tipW, wrapW + 12);
        int tipH = 8 + 11 + descLines.size() * 10 + 11 + 4;

        int x = Math.min(mouseX + 10, this.width - tipW - 4);
        int y = Math.min(mouseY + 8, this.height - tipH - 4);

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F, 0.0F, 400.0F); // above widgets, like vanilla tooltips
        EclipseUiTheme.drawPanel(guiGraphics, x, y, tipW, tipH);
        int textX = x + 6;
        int textY = y + 6;
        guiGraphics.drawString(this.font, node.title.pick(locale), textX, textY, EclipseUiTheme.ACCENT);
        textY += 11;
        for (FormattedCharSequence line : descLines) {
            guiGraphics.drawString(this.font, line, textX, textY, EclipseUiTheme.TEXT);
            textY += 10;
        }
        textY += 1;
        guiGraphics.drawString(this.font, costLine, textX, textY, EclipseUiTheme.DIM);
        guiGraphics.pose().popPose();
    }

    // ------------------------------------------------------------------
    // Input / lifecycle
    // ------------------------------------------------------------------

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (closing) {
            return true;
        }
        if (SkillKeybind.OPEN_SKILLS.matches(keyCode, scanCode)) {
            onClose();
            return true;
        }
        // TAB cycles the two tabs (gamepad-free parity with the handbook rail; ESC still
        // closes via the vanilla Screen path below).
        if (keyCode == GLFW.GLFW_KEY_TAB) {
            switchTab(tab == Tab.SKILLS ? Tab.WAND : Tab.SKILLS);
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (closing) {
            return true;
        }
        if (super.mouseClicked(mouseX, mouseY, button)) {
            return true;
        }
        // B8 parity: a skills key rebound to a mouse button still closes the screen.
        if (SkillKeybind.OPEN_SKILLS.matchesMouse(button)) {
            onClose();
            return true;
        }
        return false;
    }

    @Override
    public void onClose() {
        if (closing || EclipseClientConfig.reducedFx()) {
            super.onClose();
            return;
        }
        closing = true;
        closeTicks = OPEN_TICKS;
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

    /** Header tab: label + accent underline when selected (rail-tab press sound). */
    private class TabButton extends EclipseWidget {
        private final Tab target;
        boolean selected;

        TabButton(int x, int y, int width, int height, Tab target, Component label) {
            super(x, y, width, height, label);
            this.target = target;
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            switchTab(target);
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            float alpha = panelAlpha(partialTick);
            if (selected) {
                guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + this.height,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
                guiGraphics.fill(getX() + 2, getY() + this.height - 2, getX() + this.width - 2,
                        getY() + this.height, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
            }
            int color = selected ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM;
            guiGraphics.drawCenteredString(SkillTreeScreen.this.font,
                    EclipseUiTheme.ellipsize(SkillTreeScreen.this.font,
                            getMessage().getString(), this.width - 8),
                    getX() + this.width / 2, getY() + (this.height - 8) / 2 + 1,
                    EclipseUiTheme.withAlpha(color, alpha));
        }

        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            // switchTab plays ui.tab exactly once, and only on an actual change.
        }
    }

    /** Footer buy button: KAUFEN/UNLOCK; confirm label for costly nodes; "…" in flight. */
    private class BuyButton extends EclipseWidget {
        boolean pending;
        boolean confirming;

        BuyButton(int x, int y, int width, int height) {
            super(x, y, width, height, EclipseLang.tr("gui.eclipse.skills.buy"));
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            handleBuyIntent(selectedNodeId);
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            float alpha = panelAlpha(partialTick);
            int fill = this.active ? EclipseUiTheme.PANEL_RAISED : EclipseUiTheme.PANEL;
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + this.height,
                    EclipseUiTheme.withAlpha(fill, alpha));
            int border = this.active ? EclipseUiTheme.ACCENT : EclipseUiTheme.HAIRLINE;
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + 1,
                    EclipseUiTheme.withAlpha(border, alpha));
            guiGraphics.fill(getX(), getY() + this.height - 1, getX() + this.width, getY() + this.height,
                    EclipseUiTheme.withAlpha(border, alpha));
            guiGraphics.fill(getX(), getY() + 1, getX() + 1, getY() + this.height - 1,
                    EclipseUiTheme.withAlpha(border, alpha));
            guiGraphics.fill(getX() + this.width - 1, getY() + 1, getX() + this.width, getY() + this.height - 1,
                    EclipseUiTheme.withAlpha(border, alpha));

            Component label;
            if (pending) {
                label = EclipseLang.tr("gui.eclipse.skills.buy_pending");
            } else if (confirming) {
                label = EclipseLang.tr("gui.eclipse.skills.buy_confirm");
            } else {
                label = EclipseLang.tr("gui.eclipse.skills.buy");
            }
            int color = this.active ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM;
            guiGraphics.drawCenteredString(SkillTreeScreen.this.font,
                    EclipseUiTheme.ellipsize(SkillTreeScreen.this.font, label.getString(), this.width - 8),
                    getX() + this.width / 2, getY() + (this.height - 8) / 2,
                    EclipseUiTheme.withAlpha(color, alpha));
        }

        /** No click plink when inactive; the base {@code ui.click} plays otherwise. */
        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            if (this.active) {
                UiSounds.click();
            }
        }
    }

    /**
     * Rebirth hold-to-confirm button (A14 §3): press and HOLD for
     * {@value #HOLD_MILLIS} ms to fire W-REBIRTH's rebirth request; releasing (or
     * leaving the button) cancels. Inert while locked (no sync yet / cost not covered)
     * and for a grace window after firing (the state refresh re-enables it).
     */
    private class RebirthHoldButton extends EclipseWidget {
        private static final long HOLD_MILLIS = 1200L;
        private static final long REFIRE_GRACE_MILLIS = 3000L;

        private long holdStartMillis;
        private long firedAtMillis;

        RebirthHoldButton(int x, int y, int width, int height) {
            super(x, y, width, height, EclipseLang.tr("gui.eclipse.skills.rebirth.hold"));
        }

        boolean holding() {
            return holdStartMillis != 0L;
        }

        boolean costCovered() {
            return ClientRebirthState.synced
                    && ClientStateCache.sidebarShards >= ClientRebirthState.nextCostShards;
        }

        /** Screen-tick hook: recompute the locked state from the synced caches. */
        void tickState() {
            this.active = this.visible && costCovered()
                    && Util.getMillis() - firedAtMillis > REFIRE_GRACE_MILLIS;
            if (!this.active) {
                holdStartMillis = 0L;
            }
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            if (this.active) {
                holdStartMillis = Util.getMillis();
            }
        }

        @Override
        public void onRelease(double mouseX, double mouseY) {
            holdStartMillis = 0L;
        }

        private void fire() {
            holdStartMillis = 0L;
            firedAtMillis = Util.getMillis();
            UiSounds.levelUp();
            // C2SRebirthPayload (PLAN-A A13 / PLAN-D D11): empty request payload,
            // registered in EclipsePayloads and validated ENTIRELY server-side in
            // rebirth.RebirthService (cost, life cap, dimension). The response rides
            // S2CRebirthStatePayload + the existing skill/hearts syncs — this button
            // only ever asks.
            PacketDistributor.sendToServer(new dev.projecteclipse.eclipse.network.C2SRebirthPayload());
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            float alpha = panelAlpha(partialTick);
            long now = Util.getMillis();
            if (holding() && !isHovered()) {
                holdStartMillis = 0L; // sliding off the button cancels the hold
            }
            float progress = holding()
                    ? Mth.clamp((now - holdStartMillis) / (float) HOLD_MILLIS, 0.0F, 1.0F) : 0.0F;
            if (progress >= 1.0F) {
                fire();
                progress = 0.0F;
            }

            int fill = this.active ? EclipseUiTheme.PANEL_RAISED : EclipseUiTheme.PANEL;
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + this.height,
                    EclipseUiTheme.withAlpha(fill, alpha));
            if (progress > 0.0F) {
                guiGraphics.fill(getX() + 1, getY() + 1,
                        getX() + 1 + Math.round((this.width - 2) * progress), getY() + this.height - 1,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, 0.65F * alpha));
            }
            int border = this.active ? EclipseUiTheme.ACCENT : EclipseUiTheme.HAIRLINE;
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + 1,
                    EclipseUiTheme.withAlpha(border, alpha));
            guiGraphics.fill(getX(), getY() + this.height - 1, getX() + this.width, getY() + this.height,
                    EclipseUiTheme.withAlpha(border, alpha));
            guiGraphics.fill(getX(), getY() + 1, getX() + 1, getY() + this.height - 1,
                    EclipseUiTheme.withAlpha(border, alpha));
            guiGraphics.fill(getX() + this.width - 1, getY() + 1, getX() + this.width, getY() + this.height - 1,
                    EclipseUiTheme.withAlpha(border, alpha));

            int color = this.active ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM;
            guiGraphics.drawCenteredString(SkillTreeScreen.this.font,
                    EclipseUiTheme.ellipsize(SkillTreeScreen.this.font,
                            getMessage().getString(), this.width - 8),
                    getX() + this.width / 2, getY() + (this.height - 8) / 2,
                    EclipseUiTheme.withAlpha(color, alpha));
        }

        /** Quiet press — the completion moment plays {@code UiSounds.levelUp} instead. */
        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            if (this.active) {
                UiSounds.click();
            }
        }
    }
}
