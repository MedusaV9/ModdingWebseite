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
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.C2SSkillNodeBuyPayload;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;

import javax.annotation.Nullable;

/**
 * The skill tree screen (WB-SKILLS, plan §3.9 / design system §2 "Quiet Eclipse"). One
 * centered flat panel over the {@link EclipseUiTheme#VEIL} dim: header row (title left;
 * level, XP and unspent points right), the {@link SkillTreeWidget} canvas at full width,
 * and a detail footer for the selected node with the buy button. Opens via the K keybind
 * ({@link SkillKeybind}) or the inventory button ({@link InventorySkillButton}); closes on
 * ESC or the same binding (keyboard AND mouse-bound, the handbook's B8 parity).
 *
 * <p><b>Zero desync:</b> the tree renders live from {@code ClientStateCache} every frame
 * — the server's {@code S2CSkillTreePayload}/{@code S2CSkillStatePayload} are the only
 * truth. A buy click sends {@code C2SSkillNodeBuyPayload} and locks the node in a PENDING
 * state (padlock overlay, footer button disabled); the lock resolves when the refreshed
 * owned-node list arrives (success → purchase celebration + {@code ui.skill_buy}) or
 * clears after a short timeout (failure — the server already showed the reason on the
 * action bar). The client never adds nodes or spends points locally.</p>
 *
 * <p>Motion follows §2.3: 5-tick fade + 4px rise on open/close ({@code reducedFx} snaps).
 * Cursor lifecycle: {@link CursorManager#endFrame()} once per frame,
 * {@link CursorManager#reset()} in {@link #removed()}.</p>
 */
@OnlyIn(Dist.CLIENT)
public class SkillTreeScreen extends Screen {
    private static final float PANEL_PCT = 0.9F;
    private static final int MAX_PANEL_W = 620;
    private static final int MAX_PANEL_H = 360;
    private static final int HEADER_H = 25;
    /** Detail footer: hairline + two text rows + buy button. */
    private static final int FOOTER_H = 46;
    private static final int OPEN_TICKS = 5;
    private static final int RISE_PX = 4;
    /** Pending-purchase failsafe: unlock after 3s if no state refresh resolves it. */
    private static final int PENDING_TIMEOUT_TICKS = 60;

    private SkillTreeWidget canvas;
    private BuyButton buyButton;

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
        contentY = panelY + HEADER_H + 1;
        contentW = panelW - 2;
        footerY = panelY + panelH - FOOTER_H;
        contentH = Math.max(60, footerY - contentY);

        canvas = addRenderableWidget(new SkillTreeWidget(contentX, contentY, contentW, contentH,
                this::onNodeSelected));
        canvas.select(selectedNodeId);
        canvas.setPendingNode(pendingNodeId);

        int buyW = 92;
        buyButton = addRenderableWidget(new BuyButton(
                panelX + panelW - EclipseUiTheme.PAD - buyW, footerY + 14, buyW, 20));
        updateBuyButton();
    }

    private void onNodeSelected(String nodeId) {
        selectedNodeId = nodeId;
        updateBuyButton();
    }

    // ------------------------------------------------------------------
    // Buy flow (server-validated; optimistic pending lock only)
    // ------------------------------------------------------------------

    private void requestBuy() {
        SkillTreeModel model = SkillTreeModel.current();
        SkillTreeModel.Node node = selectedNodeId != null ? model.nodes().get(selectedNodeId) : null;
        if (node == null || pendingNodeId != null || !model.affordable(node)) {
            return;
        }
        pendingNodeId = node.id;
        pendingTicks = 0;
        canvas.setPendingNode(pendingNodeId);
        PacketDistributor.sendToServer(new C2SSkillNodeBuyPayload(node.id));
        updateBuyButton();
    }

    @Override
    public void tick() {
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
        updateBuyButton();
    }

    private void updateBuyButton() {
        if (buyButton == null) {
            return;
        }
        SkillTreeModel model = SkillTreeModel.current();
        SkillTreeModel.Node node = selectedNodeId != null ? model.nodes().get(selectedNodeId) : null;
        boolean pending = pendingNodeId != null;
        buyButton.visible = node != null && model.stateOf(node) != SkillTreeModel.State.OWNED;
        buyButton.active = node != null && !pending && model.affordable(node);
        buyButton.pending = pending && node != null && node.id.equals(pendingNodeId);
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
        renderNodeTooltip(guiGraphics, mouseX, mouseY);
        CursorManager.endFrame();
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        float alpha = panelAlpha(partialTick);
        int rise = panelRise(partialTick);
        int py = panelY + rise;

        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        EclipseUiTheme.drawPanel(guiGraphics, panelX, py, panelW, panelH, alpha);

        renderHeader(guiGraphics, py, alpha);
        renderFooter(guiGraphics, py, alpha);

        if (SkillTreeModel.current().isEmpty()) {
            guiGraphics.drawCenteredString(this.font, EclipseLang.tr("gui.eclipse.skills.empty"),
                    panelX + panelW / 2, contentY + contentH / 2 - 4,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
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

    private String stateLine(SkillTreeModel model, SkillTreeModel.Node node) {
        if (node.id.equals(pendingNodeId)) {
            return EclipseLang.trString("gui.eclipse.skills.buy_pending");
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

    /** Footer buy button: KAUFEN/UNLOCK; disabled + "…" while a purchase is in flight. */
    private class BuyButton extends EclipseWidget {
        boolean pending;

        BuyButton(int x, int y, int width, int height) {
            super(x, y, width, height, EclipseLang.tr("gui.eclipse.skills.buy"));
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            requestBuy();
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

            Component label = pending
                    ? EclipseLang.tr("gui.eclipse.skills.buy_pending")
                    : EclipseLang.tr("gui.eclipse.skills.buy");
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
}
