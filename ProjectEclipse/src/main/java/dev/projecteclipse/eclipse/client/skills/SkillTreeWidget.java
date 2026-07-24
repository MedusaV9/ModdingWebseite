package dev.projecteclipse.eclipse.client.skills;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

import javax.annotation.Nullable;

/**
 * The pannable/zoomable skill tree canvas (WB-SKILLS, plan §3.9). Renders the laid-out
 * {@link SkillTreeModel} — connection lines below, 24px item-icon node tiles above — inside
 * a scissored viewport. Node states come from the synced cache every frame (server truth):
 * OWNED = accent fill + soft glow, AVAILABLE = hairline tile with a slow 2s pulse while
 * affordable, LOCKED = dark silhouette + padlock glyph. Connection lines light up with the
 * far node: owned edges are accent with a soft glow, purchasable edges shimmer dim, locked
 * edges stay hairline; when a node is bought its edges re-draw-in over ~6 ticks and the
 * tile plays a white flash + expanding glow ring (all wall-clock eased, {@code reducedFx}
 * snaps everything).
 *
 * <p>Interaction: drag = pan (grab cursor), scroll = zoom 0.75–1.5 anchored on the mouse,
 * click = select (the owning screen shows the detail footer + buy button), hover = pointer
 * cursor + themed tooltip (drawn by the screen so it overlays everything). Pan is clamped
 * to the content bounds, so a tree smaller than the viewport is simply centered and
 * effectively static. Offscreen nodes are culled before any pose math.</p>
 */
@OnlyIn(Dist.CLIENT)
public class SkillTreeWidget extends AbstractWidget {
    private static final float MIN_ZOOM = 0.75F;
    private static final float MAX_ZOOM = 1.5F;
    /** Wall-clock animation lengths (ms): 2t flash, 8t ring, 6t line draw-in. */
    private static final long FLASH_MILLIS = 100L;
    private static final long RING_MILLIS = 400L;
    private static final long LINE_MILLIS = 300L;
    private static final long PULSE_PERIOD_MILLIS = 2000L;
    /** Cascade (W4-FEEL, IDEA-06 #1): wake-up border flash length + sibling stagger. */
    private static final long UNLOCK_FLASH_MILLIS = 250L;
    private static final long UNLOCK_STAGGER_MILLIS = 80L;
    /** Canvas padding around the content bounds (room for branch headers + glow). */
    private static final int CONTENT_PAD = 28;

    private final Consumer<String> onSelect;

    /** View center in canvas units + zoom factor. */
    private float viewX;
    private float viewY;
    private float zoom = 1.0F;
    private boolean viewInitialized;

    private boolean dragging;
    private double dragTravel;

    @Nullable
    private String hoveredNodeId;
    @Nullable
    private String selectedNodeId;
    /** Node id currently awaiting server confirmation (padlock overlay), set by the screen. */
    @Nullable
    private String pendingNodeId;

    /** Purchase celebration start millis per node id (flash + ring + line draw-in). */
    private final Map<String, Long> purchaseAnimStart = new HashMap<>();

    /**
     * Cascade wake-up start millis per newly-available child id (W4-FEEL, IDEA-06 #1).
     * Starts sit in the FUTURE (buy ring + per-sibling stagger) — render sites skip
     * negative elapsed and prune once both the edge wipe and border flash finished.
     */
    private final Map<String, Long> unlockAnimStart = new HashMap<>();

    public SkillTreeWidget(int x, int y, int width, int height, Consumer<String> onSelect) {
        super(x, y, width, height, Component.empty());
        this.onSelect = onSelect;
    }

    // ------------------------------------------------------------------
    // State plumbing (owned by the screen)
    // ------------------------------------------------------------------

    @Nullable
    public String hoveredNodeId() {
        return hoveredNodeId;
    }

    @Nullable
    public String selectedNodeId() {
        return selectedNodeId;
    }

    public void select(@Nullable String nodeId) {
        selectedNodeId = nodeId;
    }

    public void setPendingNode(@Nullable String nodeId) {
        pendingNodeId = nodeId;
    }

    public boolean dragging() {
        return dragging;
    }

    /** Screen tick hook: a node flipped to OWNED — play the purchase celebration. */
    public void onNodePurchased(String nodeId) {
        long now = Util.getMillis();
        purchaseAnimStart.put(nodeId, now);
        UiSounds.skillBuy();

        // Cascade (W4-FEEL, IDEA-06 #1): the confirmation wave travels onward. Children
        // of the bought node that are AVAILABLE now were LOCKED a frame ago (they
        // required this node), so their edges draw in and their tiles wake up after the
        // buy ring, staggered per sibling — juice that doubles as information.
        SkillTreeModel model = SkillTreeModel.current();
        int order = 0;
        for (SkillTreeModel.Node child : model.nodes().values()) {
            if (child.requires.contains(nodeId)
                    && model.stateOf(child) == SkillTreeModel.State.AVAILABLE) {
                unlockAnimStart.put(child.id,
                        now + RING_MILLIS + UNLOCK_STAGGER_MILLIS * order);
                order++;
            }
        }
        if (order > 0) {
            UiSounds.skillUnlockWave(); // once per cascade, never per node
        }
    }

    /** Re-center on the tree (first open and after resize when the view was never touched). */
    public void resetViewIfUntouched(SkillTreeModel model) {
        if (viewInitialized || model.isEmpty()) {
            return;
        }
        viewInitialized = true;
        viewX = (model.minX() + model.maxX()) / 2.0F;
        // Top-align tall trees: show the roots first, they are what a fresh player buys.
        float contentH = model.maxY() - model.minY() + 2 * CONTENT_PAD;
        if (contentH * zoom > this.height) {
            viewY = model.minY() - CONTENT_PAD + this.height / (2.0F * zoom);
        } else {
            viewY = (model.minY() + model.maxY()) / 2.0F;
        }
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------

    @Override
    protected void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        SkillTreeModel model = SkillTreeModel.current();
        resetViewIfUntouched(model);
        clampView(model);

        hoveredNodeId = null;
        if (isHovered() && !dragging) {
            SkillTreeModel.Node hit = nodeAt(model, mouseX, mouseY);
            if (hit != null) {
                hoveredNodeId = hit.id;
                CursorManager.requestPointer();
            }
        }
        if (dragging) {
            CursorManager.requestGrab();
        }

        long now = Util.getMillis();
        boolean reduced = EclipseClientConfig.reducedFx();

        guiGraphics.enableScissor(getX(), getY(), getX() + this.width, getY() + this.height);
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(
                getX() + this.width / 2.0F - viewX * zoom,
                getY() + this.height / 2.0F - viewY * zoom, 0.0F);
        guiGraphics.pose().scale(zoom, zoom, 1.0F);

        renderBranchHeaders(guiGraphics, model);
        for (SkillTreeModel.Node node : model.nodes().values()) {
            renderEdges(guiGraphics, model, node, now, reduced);
        }
        for (SkillTreeModel.Node node : model.nodes().values()) {
            if (!culled(node)) {
                renderNode(guiGraphics, model, node, now, reduced);
            }
        }

        guiGraphics.pose().popPose();
        guiGraphics.disableScissor();
    }

    /** DIM branch labels above each column's topmost row. */
    private void renderBranchHeaders(GuiGraphics guiGraphics, SkillTreeModel model) {
        var font = net.minecraft.client.Minecraft.getInstance().font;
        String locale = SkillTreeModel.pickLocale();
        for (SkillTreeModel.Branch branch : model.branches()) {
            String label = branch.title() != null ? branch.title().pick(locale) : branch.id();
            guiGraphics.drawCenteredString(font, label, branch.centerX(),
                    model.minY() - 18, EclipseUiTheme.DIM);
        }
    }

    /** Edges into {@code node} from each prerequisite; drawn in the child's state color. */
    private void renderEdges(GuiGraphics guiGraphics, SkillTreeModel model, SkillTreeModel.Node node,
            long now, boolean reduced) {
        SkillTreeModel.State childState = model.stateOf(node);
        for (String parentId : node.requires) {
            SkillTreeModel.Node parent = model.nodes().get(parentId);
            if (parent == null) {
                continue;
            }
            int color;
            float glowPulse = 0.0F;
            switch (childState) {
                case OWNED -> color = EclipseUiTheme.ACCENT;
                case AVAILABLE -> {
                    color = EclipseUiTheme.ACCENT_DEEP;
                    if (!reduced) {
                        glowPulse = pulse(now, parentId.hashCode());
                    }
                }
                default -> color = EclipseUiTheme.HAIRLINE;
            }

            // Purchase draw-in: freshly-owned edges wipe from the parent to the child.
            float drawIn = 1.0F;
            Long animStart = purchaseAnimStart.get(node.id);
            if (!reduced && animStart != null && childState == SkillTreeModel.State.OWNED) {
                drawIn = Mth.clamp((now - animStart) / (float) LINE_MILLIS, 0.0F, 1.0F);
                drawIn = easeOutCubic(drawIn);
            }

            int alpha = childState == SkillTreeModel.State.AVAILABLE
                    ? (int) (150 + 80 * glowPulse) : 255;

            // Cascade light-up (IDEA-06 #1): edges into a freshly-unlocked child keep the
            // old locked hairline underlay while the dim-accent wipe travels over it.
            Long unlockStart = !reduced && childState == SkillTreeModel.State.AVAILABLE
                    ? unlockAnimStart.get(node.id) : null;
            if (unlockStart != null && now - unlockStart < LINE_MILLIS) {
                long unlockElapsed = now - unlockStart;
                drawEdge(guiGraphics, parent, node,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 1.0F), 1.0F);
                if (unlockElapsed >= 0L) {
                    float wipe = easeOutCubic(
                            Mth.clamp(unlockElapsed / (float) LINE_MILLIS, 0.0F, 1.0F));
                    drawEdge(guiGraphics, parent, node,
                            EclipseUiTheme.withAlpha(color, alpha / 255.0F), wipe);
                }
                continue;
            }

            drawEdge(guiGraphics, parent, node, EclipseUiTheme.withAlpha(color, alpha / 255.0F), drawIn);
        }
    }

    /**
     * 2px L-shaped connector: vertical out of the parent, horizontal at the midpoint,
     * vertical into the child. {@code drawIn} 0..1 wipes the path parent → child.
     */
    private void drawEdge(GuiGraphics guiGraphics, SkillTreeModel.Node parent, SkillTreeModel.Node child,
            int color, float drawIn) {
        int x0 = parent.centerX();
        int y0 = parent.y + SkillTreeModel.NODE_SIZE;
        int x1 = child.centerX();
        int y1 = child.y;
        if (y1 < y0) { // upward/sideways prereq (unusual): straight line segments still work
            y0 = parent.centerY();
            y1 = child.centerY();
        }
        int midY = (y0 + y1) / 2;

        int seg1 = Math.abs(midY - y0);
        int seg2 = Math.abs(x1 - x0);
        int seg3 = Math.abs(y1 - midY);
        float total = Math.max(1, seg1 + seg2 + seg3);
        float budget = drawIn * total;

        // Segment 1: vertical from parent toward midY (direction-aware for tier overrides).
        int len1 = (int) Math.min(seg1, budget);
        if (len1 > 0) {
            if (midY >= y0) {
                guiGraphics.fill(x0 - 1, y0, x0 + 1, y0 + len1, color);
            } else {
                guiGraphics.fill(x0 - 1, y0 - len1, x0 + 1, y0, color);
            }
        }
        budget -= seg1;
        if (budget <= 0) {
            return;
        }
        // Segment 2: horizontal toward the child column (wipe anchored at the parent side).
        int len2 = (int) Math.min(seg2, budget);
        if (len2 > 0) {
            if (x1 > x0) {
                guiGraphics.fill(x0, midY - 1, x0 + len2, midY + 1, color);
            } else {
                guiGraphics.fill(x0 - len2, midY - 1, x0, midY + 1, color);
            }
        }
        budget -= seg2;
        if (budget <= 0) {
            return;
        }
        // Segment 3: vertical from midY into the child (direction-aware, wipe toward child).
        int len3 = (int) Math.min(seg3, budget);
        if (len3 > 0) {
            if (y1 >= midY) {
                guiGraphics.fill(x1 - 1, midY, x1 + 1, midY + len3, color);
            } else {
                guiGraphics.fill(x1 - 1, midY - len3, x1 + 1, midY, color);
            }
        }
    }

    private void renderNode(GuiGraphics guiGraphics, SkillTreeModel model, SkillTreeModel.Node node,
            long now, boolean reduced) {
        SkillTreeModel.State state = model.stateOf(node);
        boolean hovered = node.id.equals(hoveredNodeId);
        boolean selected = node.id.equals(selectedNodeId);
        boolean pending = node.id.equals(pendingNodeId);
        int x = node.x;
        int y = node.y;
        int size = SkillTreeModel.NODE_SIZE;

        // Tile fill + border by state.
        switch (state) {
            case OWNED -> {
                guiGraphics.fill(x, y, x + size, y + size, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, 0.45F));
                drawBorder(guiGraphics, x, y, size, EclipseUiTheme.ACCENT, 1.0F);
                // Quiet permanent glow halo.
                drawBorderOutset(guiGraphics, x, y, size, 2, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.25F));
            }
            case AVAILABLE -> {
                guiGraphics.fill(x, y, x + size, y + size, EclipseUiTheme.PANEL_RAISED);
                float pulseAlpha = reduced || !model.affordable(node) ? 0.0F : pulse(now, node.id.hashCode());
                drawBorder(guiGraphics, x, y, size, EclipseUiTheme.HAIRLINE, 1.0F);
                if (pulseAlpha > 0.02F) {
                    drawBorder(guiGraphics, x, y, size, EclipseUiTheme.ACCENT, 0.35F + 0.5F * pulseAlpha);
                }
            }
            default -> {
                guiGraphics.fill(x, y, x + size, y + size, EclipseUiTheme.withAlpha(0xFF0B0713, 0.95F));
                drawBorder(guiGraphics, x, y, size, EclipseUiTheme.HAIRLINE, 0.6F);
            }
        }

        // Icon: locked nodes render a dark silhouette (icon dimmed under a veil overlay).
        guiGraphics.renderItem(node.icon(), x + (size - 16) / 2, y + (size - 16) / 2);
        if (state == SkillTreeModel.State.LOCKED) {
            guiGraphics.fill(x + 1, y + 1, x + size - 1, y + size - 1,
                    EclipseUiTheme.withAlpha(0xFF0B0713, 0.72F));
            drawLockGlyph(guiGraphics, x + size / 2, y + size / 2,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, 0.9F));
        }

        // Pending purchase: server confirmation in flight — lock badge + slow blink.
        if (pending) {
            float blink = reduced ? 0.6F : 0.4F + 0.3F * pulse(now, 7);
            guiGraphics.fill(x + 1, y + 1, x + size - 1, y + size - 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, blink));
            drawLockGlyph(guiGraphics, x + size / 2, y + size / 2, EclipseUiTheme.TEXT);
        }

        // Hover/selection ring (outside the tile so the icon stays clean).
        if (selected) {
            drawBorderOutset(guiGraphics, x, y, size, 2, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, 0.85F));
        } else if (hovered) {
            drawBorderOutset(guiGraphics, x, y, size, 2, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.6F));
        }

        // Cascade wake-up (IDEA-06 #1): a newly-available tile flashes a soft accent
        // border once after the buy ring reaches it, then the normal affordable pulse
        // takes over. reducedFx (or a state change) just drops the entry.
        Long unlockStart = unlockAnimStart.get(node.id);
        if (unlockStart != null) {
            if (reduced || state != SkillTreeModel.State.AVAILABLE) {
                unlockAnimStart.remove(node.id);
            } else {
                long unlockElapsed = now - unlockStart;
                if (unlockElapsed >= 0L && unlockElapsed <= UNLOCK_FLASH_MILLIS) {
                    float t = unlockElapsed / (float) UNLOCK_FLASH_MILLIS;
                    drawBorderOutset(guiGraphics, x, y, size, 2,
                            EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.6F * (1.0F - t)));
                } else if (unlockElapsed > Math.max(UNLOCK_FLASH_MILLIS, LINE_MILLIS)) {
                    unlockAnimStart.remove(node.id);
                }
            }
        }

        // Purchase celebration: 2t white flash + 8t expanding glow ring.
        Long animStart = purchaseAnimStart.get(node.id);
        if (animStart != null && !reduced) {
            long elapsed = now - animStart;
            if (elapsed <= FLASH_MILLIS) {
                guiGraphics.fill(x, y, x + size, y + size,
                        EclipseUiTheme.withAlpha(0xFFFFFFFF, 0.7F * (1.0F - elapsed / (float) FLASH_MILLIS)));
            }
            if (elapsed <= RING_MILLIS) {
                float t = easeOutCubic(elapsed / (float) RING_MILLIS);
                int spread = 2 + Math.round(t * 10.0F);
                drawBorderOutset(guiGraphics, x, y, size, spread,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.8F * (1.0F - t)));
            } else if (elapsed > Math.max(RING_MILLIS, LINE_MILLIS)) {
                purchaseAnimStart.remove(node.id);
            }
        } else if (animStart != null) {
            purchaseAnimStart.remove(node.id);
        }
    }

    /**
     * Tiny fill-drawn padlock centered on ({@code cx},{@code cy}) — the U+1F512 emoji is
     * outside the BMP and the vanilla font stack (ascii/accented/unifont) has no glyph for
     * it, so a drawn badge is the only way this never shows a missing-glyph box.
     */
    private static void drawLockGlyph(GuiGraphics guiGraphics, int cx, int cy, int color) {
        // Body: 7x5 with a 1px keyhole notch.
        guiGraphics.fill(cx - 3, cy - 1, cx + 4, cy + 4, color);
        // Shackle: 1px U-arch above the body.
        guiGraphics.fill(cx - 2, cy - 4, cx - 1, cy - 1, color);
        guiGraphics.fill(cx + 2, cy - 4, cx + 3, cy - 1, color);
        guiGraphics.fill(cx - 2, cy - 5, cx + 3, cy - 4, color);
    }

    private static void drawBorder(GuiGraphics guiGraphics, int x, int y, int size, int color, float alpha) {
        int c = EclipseUiTheme.withAlpha(color, alpha);
        guiGraphics.fill(x, y, x + size, y + 1, c);
        guiGraphics.fill(x, y + size - 1, x + size, y + size, c);
        guiGraphics.fill(x, y + 1, x + 1, y + size - 1, c);
        guiGraphics.fill(x + size - 1, y + 1, x + size, y + size - 1, c);
    }

    private static void drawBorderOutset(GuiGraphics guiGraphics, int x, int y, int size, int spread, int color) {
        int x0 = x - spread;
        int y0 = y - spread;
        int x1 = x + size + spread;
        int y1 = y + size + spread;
        guiGraphics.fill(x0, y0, x1, y0 + 1, color);
        guiGraphics.fill(x0, y1 - 1, x1, y1, color);
        guiGraphics.fill(x0, y0 + 1, x0 + 1, y1 - 1, color);
        guiGraphics.fill(x1 - 1, y0 + 1, x1, y1 - 1, color);
    }

    /** Slow 0..1 sine pulse (2s period), phase-salted so rows don't blink in lockstep. */
    private static float pulse(long now, int salt) {
        double phase = ((now + salt * 137L) % PULSE_PERIOD_MILLIS) / (double) PULSE_PERIOD_MILLIS;
        return (float) (0.5D + 0.5D * Math.sin(phase * Math.PI * 2.0D));
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - t;
        return 1.0F - inv * inv * inv;
    }

    // ------------------------------------------------------------------
    // View math + input
    // ------------------------------------------------------------------

    /** True when the node tile is fully outside the viewport (cheap pre-pose cull). */
    private boolean culled(SkillTreeModel.Node node) {
        float sx0 = canvasToScreenX(node.x - 14);
        float sx1 = canvasToScreenX(node.x + SkillTreeModel.NODE_SIZE + 14);
        float sy0 = canvasToScreenY(node.y - 14);
        float sy1 = canvasToScreenY(node.y + SkillTreeModel.NODE_SIZE + 14);
        return sx1 < getX() || sx0 > getX() + this.width || sy1 < getY() || sy0 > getY() + this.height;
    }

    private float canvasToScreenX(float canvasX) {
        return getX() + this.width / 2.0F + (canvasX - viewX) * zoom;
    }

    private float canvasToScreenY(float canvasY) {
        return getY() + this.height / 2.0F + (canvasY - viewY) * zoom;
    }

    private float screenToCanvasX(double screenX) {
        return (float) ((screenX - getX() - this.width / 2.0F) / zoom + viewX);
    }

    private float screenToCanvasY(double screenY) {
        return (float) ((screenY - getY() - this.height / 2.0F) / zoom + viewY);
    }

    @Nullable
    private SkillTreeModel.Node nodeAt(SkillTreeModel model, double mouseX, double mouseY) {
        float cx = screenToCanvasX(mouseX);
        float cy = screenToCanvasY(mouseY);
        for (SkillTreeModel.Node node : model.nodes().values()) {
            if (cx >= node.x - 2 && cx <= node.x + SkillTreeModel.NODE_SIZE + 2
                    && cy >= node.y - 2 && cy <= node.y + SkillTreeModel.NODE_SIZE + 2) {
                return node;
            }
        }
        return null;
    }

    /** Keeps the view center inside the padded content bounds (small trees stay centered). */
    private void clampView(SkillTreeModel model) {
        if (model.isEmpty()) {
            viewX = 0;
            viewY = 0;
            return;
        }
        float halfW = this.width / (2.0F * zoom);
        float halfH = this.height / (2.0F * zoom);
        viewX = clampAxis(viewX, model.minX() - CONTENT_PAD, model.maxX() + CONTENT_PAD, halfW);
        viewY = clampAxis(viewY, model.minY() - CONTENT_PAD, model.maxY() + CONTENT_PAD, halfH);
    }

    private static float clampAxis(float center, float min, float max, float halfView) {
        if (max - min <= halfView * 2.0F) {
            return (min + max) / 2.0F; // content fits — lock to center (static tree)
        }
        return Mth.clamp(center, min + halfView, max - halfView);
    }

    @Override
    public void onClick(double mouseX, double mouseY) {
        dragging = true;
        dragTravel = 0.0D;
        SkillTreeModel.Node hit = nodeAt(SkillTreeModel.current(), mouseX, mouseY);
        if (hit != null) {
            if (!hit.id.equals(selectedNodeId)) {
                selectedNodeId = hit.id;
                UiSounds.click();
                onSelect.accept(hit.id);
            }
        }
    }

    @Override
    protected void onDrag(double mouseX, double mouseY, double dragX, double dragY) {
        dragTravel += Math.abs(dragX) + Math.abs(dragY);
        if (dragTravel > 2.0D) {
            viewX -= (float) (dragX / zoom);
            viewY -= (float) (dragY / zoom);
        }
    }

    @Override
    public void onRelease(double mouseX, double mouseY) {
        dragging = false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (!isMouseOver(mouseX, mouseY)) {
            return false;
        }
        float anchorX = screenToCanvasX(mouseX);
        float anchorY = screenToCanvasY(mouseY);
        zoom = Mth.clamp(zoom * (scrollY > 0 ? 1.1F : 1.0F / 1.1F), MIN_ZOOM, MAX_ZOOM);
        // Keep the canvas point under the mouse stationary while zooming.
        viewX = anchorX - (float) ((mouseX - getX() - this.width / 2.0F) / zoom);
        viewY = anchorY - (float) ((mouseY - getY() - this.height / 2.0F) / zoom);
        clampView(SkillTreeModel.current());
        return true;
    }

    /** The canvas is silent — node selection plays its own {@code ui.click}. */
    @Override
    public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
    }

    @Override
    protected void updateWidgetNarration(NarrationElementOutput narrationElementOutput) {
        narrationElementOutput.add(net.minecraft.client.gui.narration.NarratedElementType.TITLE,
                EclipseLang.tr("gui.eclipse.skills.title"));
    }
}
