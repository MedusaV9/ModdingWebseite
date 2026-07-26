package dev.projecteclipse.eclipse.client.wand;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.wand.C2SWandChoosePathPayload;
import dev.projecteclipse.eclipse.network.wand.C2SWandNodeBuyPayload;
import dev.projecteclipse.eclipse.network.wand.C2SWandRebirthPayload;
import dev.projecteclipse.eclipse.network.wand.C2SWandSelectSpellPayload;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import dev.projecteclipse.eclipse.wand.WandSpell;
import dev.projecteclipse.eclipse.wand.WandSpells;
import dev.projecteclipse.eclipse.wand.WandTree;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.narration.NarratedElementType;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;

import javax.annotation.Nullable;

/**
 * Embedded wand skill-TREE panel — the "Zauberstab" tab of {@code SkillTreeScreen}
 * (F-036 rework of the old level-ladder view). Renders the full 48-node
 * {@link WandTree} as three path columns (RISS / GLUT / STERN, 16 nodes each) with
 * live state per node: owned (accent tick), buyable (cost highlighted when the synced
 * Wand-XP balance covers it), locked (missing parents, dimmed). The header shows the
 * spendable <b>Wand-XP-Punkte</b>, the rebirth counter and the effective economy stats
 * (Veilladung, regen/s, spell-power multiplier — all rebirth/node-boosted server
 * values from {@link ClientWandProgress}).
 *
 * <p>Interactions (ALL server-validated in {@code WandTreeService}; this panel only
 * asks): clicking a buyable node sends {@code C2SWandNodeBuyPayload} (pending lock
 * until the next sync); clicking an OWNED spell node sends
 * {@code C2SWandSelectSpellPayload} — the tree doubles as a spell picker next to the
 * sneak-scroll cycle. Once every node is owned, the footer's REBIRTH chip arms on the
 * first click and fires {@code C2SWandRebirthPayload} on the confirming second click
 * ({@value #CONFIRM_MILLIS} ms window) — tree resets, permanent +15% power/+10% max
 * Veilladung per rebirth.</p>
 *
 * <p>Three panel states: no wand in the inventory (hint), pathless wand (compact
 * three-card chooser — same {@code C2SWandChoosePathPayload} contract as
 * {@link WandPathScreen}), and the tree view. Until the first
 * {@code S2CWandProgressPayload} lands the tree shows a syncing hint instead of
 * guessed numbers.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class WandProgressPanel extends AbstractWidget {
    private static final WandPath[] PATHS = {WandPath.RISS, WandPath.GLUT, WandPath.STERN};
    /** Riss / Glut / Stern accents — same trio as {@link WandPathScreen}. */
    private static final int[] ACCENTS = {0xFFB98CFF, 0xFFFF9A4D, 0xFF7FE7FF};

    private static final int CARD_W = 104;
    private static final int CARD_H = 92;
    private static final int CARD_GAP = 12;
    private static final int COL_GAP = 10;
    /** After a path click, ignore further card clicks until the server mirror lands. */
    private static final long CHOOSE_PENDING_MILLIS = 3000L;
    /** Node-buy in flight: ignore further clicks on it until the sync resolves. */
    private static final long BUY_PENDING_MILLIS = 3000L;
    /** Rebirth confirm window: second click inside it fires the request. */
    private static final long CONFIRM_MILLIS = 4000L;

    /** Panel alpha, driven by the owning screen's open/close fade. */
    private float alpha = 1.0F;
    private long choseAtMillis;
    private int hoveredCard = -1;
    private int lastHoveredCard = -1;

    // Tree-view interaction state.
    @Nullable
    private WandTree.Node hoveredNode;
    @Nullable
    private String pendingNodeId;
    private long pendingAtMillis;
    private long rebirthArmedAtMillis;
    private boolean rebirthHovered;

    // Layout cache (recomputed every tree frame; used by the click hit tests).
    private int treeLeft;
    private int treeTop;
    private int colW;
    private int rowH;
    private int rebirthX;
    private int rebirthY;
    private int rebirthW;

    public WandProgressPanel(int x, int y, int width, int height) {
        super(x, y, width, height, EclipseLang.tr("gui.eclipse.skills.tab.wand"));
    }

    /** Called by the screen each frame before widgets render (§2.3 open fade). */
    public void setAlpha(float alpha) {
        this.alpha = Math.max(0.08F, alpha);
    }

    // ------------------------------------------------------------------
    // Wand lookup (client inventory scan; own soulbound wand preferred)
    // ------------------------------------------------------------------

    @Nullable
    private static ItemStack findWand() {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null) {
            return null;
        }
        Inventory inventory = player.getInventory();
        ItemStack fallback = null;
        for (int slot = 0; slot < inventory.getContainerSize(); slot++) {
            ItemStack stack = inventory.getItem(slot);
            if (stack.getItem() instanceof EclipseWandItem) {
                UUID owner = stack.get(WandItems.WAND_OWNER.get());
                if (owner != null && owner.equals(player.getUUID())) {
                    return stack;
                }
                if (fallback == null) {
                    fallback = stack;
                }
            }
        }
        return fallback;
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------

    @Override
    protected void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        hoveredCard = -1;
        hoveredNode = null;
        rebirthHovered = false;
        ItemStack wand = findWand();
        if (wand == null) {
            renderNoWand(guiGraphics);
        } else if (WandSoulbind.pathOf(wand) == WandPath.NONE) {
            renderChooser(guiGraphics, mouseX, mouseY);
        } else {
            renderTree(guiGraphics, wand, mouseX, mouseY);
        }
        if (hoveredCard != lastHoveredCard && hoveredCard >= 0) {
            UiSounds.hover(); // edge blip, never per-frame
        }
        lastHoveredCard = hoveredCard;
    }

    private void renderNoWand(GuiGraphics guiGraphics) {
        var font = Minecraft.getInstance().font;
        int centerX = getX() + this.width / 2;
        int y = getY() + this.height / 2 - 10;
        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.none"),
                centerX, y, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.none_hint"),
                centerX, y + 12, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
    }

    // --- pathless: compact three-card chooser -------------------------

    private int cardW() {
        return Math.min(CARD_W, (this.width - 2 * CARD_GAP - 16) / 3);
    }

    private int cardX(int index) {
        int w = cardW();
        int total = 3 * w + 2 * CARD_GAP;
        return getX() + (this.width - total) / 2 + index * (w + CARD_GAP);
    }

    private int cardY() {
        return getY() + Math.max(30, (this.height - CARD_H) / 2);
    }

    private int cardAt(double mouseX, double mouseY) {
        int y = cardY();
        if (mouseY < y || mouseY >= y + CARD_H) {
            return -1;
        }
        for (int i = 0; i < PATHS.length; i++) {
            int x = cardX(i);
            if (mouseX >= x && mouseX < x + cardW()) {
                return i;
            }
        }
        return -1;
    }

    private boolean choicePending() {
        return choseAtMillis != 0L && Util.getMillis() - choseAtMillis < CHOOSE_PENDING_MILLIS;
    }

    private void renderChooser(GuiGraphics guiGraphics, int mouseX, int mouseY) {
        var font = Minecraft.getInstance().font;
        int centerX = getX() + this.width / 2;
        int titleY = cardY() - 26;
        boolean pending = choicePending();

        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.choose"),
                centerX, titleY, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        guiGraphics.drawCenteredString(font,
                EclipseLang.tr(pending ? "gui.eclipse.skills.wand.pending" : "gui.eclipse.skills.wand.choose_hint"),
                centerX, titleY + 12, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));

        if (!pending && isHovered()) {
            hoveredCard = cardAt(mouseX, mouseY);
            if (hoveredCard >= 0) {
                CursorManager.requestPointer();
            }
        }

        int w = cardW();
        for (int i = 0; i < PATHS.length; i++) {
            WandPath path = PATHS[i];
            int accent = ACCENTS[i];
            int x = cardX(i);
            int y = cardY();
            boolean highlighted = i == hoveredCard;
            float cardAlpha = (pending ? 0.5F : highlighted ? 1.0F : 0.86F) * alpha;

            EclipseUiTheme.drawPanel(guiGraphics, x, y, w, CARD_H, cardAlpha);
            guiGraphics.fill(x + 1, y + 1, x + w - 1, y + 3,
                    EclipseUiTheme.withAlpha(accent, (highlighted ? 1.0F : 0.7F) * cardAlpha));

            int textX = x + 8;
            int textY = y + 10;
            guiGraphics.drawString(font,
                    EclipseUiTheme.ellipsize(font, EclipseLang.trString(path.langKey()), w - 16),
                    textX, textY, EclipseUiTheme.withAlpha(accent, cardAlpha));
            textY += 13;
            // F-039 preview: the path's first three ladder spells (of ten).
            List<WandSpell> spells = WandSpells.ofPath(path);
            for (int spell = 0; spell < 3 && spell < spells.size(); spell++) {
                guiGraphics.drawString(font,
                        EclipseUiTheme.ellipsize(font,
                                "T" + spells.get(spell).tier() + " "
                                        + EclipseLang.trString(spells.get(spell).langKey()), w - 16),
                        textX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, cardAlpha));
                textY += 10;
            }
            guiGraphics.drawCenteredString(font, EclipseLang.tr("wand.eclipse.screen.choose"),
                    x + w / 2, y + CARD_H - 13,
                    EclipseUiTheme.withAlpha(highlighted ? accent : EclipseUiTheme.DIM, cardAlpha));
        }
    }

    // --- chosen path: the 48-node tree ---------------------------------

    private static int accentOf(WandPath path) {
        for (int i = 0; i < PATHS.length; i++) {
            if (PATHS[i] == path) {
                return ACCENTS[i];
            }
        }
        return EclipseUiTheme.ACCENT;
    }

    /** Node display name: the spell's name for spell nodes, the stat label otherwise. */
    private static String nodeName(WandTree.Node node) {
        WandSpell spell = WandSpells.byKey(node.spellKey());
        return spell != null
                ? EclipseLang.trString(spell.langKey())
                : EclipseLang.trString(node.statLangKey());
    }

    private boolean buyPending(String nodeId) {
        return nodeId.equals(pendingNodeId)
                && Util.getMillis() - pendingAtMillis < BUY_PENDING_MILLIS;
    }

    private boolean rebirthArmed() {
        return rebirthArmedAtMillis != 0L
                && Util.getMillis() - rebirthArmedAtMillis < CONFIRM_MILLIS;
    }

    private void renderTree(GuiGraphics guiGraphics, ItemStack wand, int mouseX, int mouseY) {
        var font = Minecraft.getInstance().font;
        if (!ClientWandProgress.synced) {
            // Login sends the first payload before any screen can open; this is a
            // few-frames guard at worst — never render guessed numbers.
            guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.skills.wand.syncing"),
                    getX() + this.width / 2, getY() + this.height / 2 - 4,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            return;
        }
        WandPath ownPath = WandSoulbind.pathOf(wand);
        int ownAccent = accentOf(ownPath);
        String selectedSpell = wand.get(WandItems.WAND_SPELL.get());

        int left = getX() + EclipseUiTheme.PAD;
        int right = getX() + this.width - EclipseUiTheme.PAD;
        int y = getY() + 6;

        // ---- header: path + level left; Wand-XP points + rebirths right.
        guiGraphics.drawString(font, EclipseLang.tr(ownPath.langKey()), left, y,
                EclipseUiTheme.withAlpha(ownAccent, alpha));
        String levelLine = EclipseLang.trString("gui.eclipse.skills.wand.level",
                ClientWandProgress.level, WandPath.MAX_LEVEL);
        guiGraphics.drawString(font, levelLine,
                left + font.width(EclipseLang.trString(ownPath.langKey())) + 8, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        String pointsLine = EclipseLang.trString("gui.eclipse.skills.wand.points",
                ClientWandProgress.xp);
        if (ClientWandProgress.rebirths > 0) {
            pointsLine = EclipseLang.trString("gui.eclipse.skills.wand.rebirths",
                    ClientWandProgress.rebirths) + " · " + pointsLine;
        }
        guiGraphics.drawString(font, pointsLine, right - font.width(pointsLine), y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        y += 11;

        // ---- effective economy stats (server-synced, node/rebirth-boosted values).
        String stats = EclipseLang.trString("gui.eclipse.skills.wand.stats",
                ClientWandProgress.charge, ClientWandProgress.chargeMax,
                String.format(java.util.Locale.ROOT, "%.1f", ClientWandProgress.regenPerSecond),
                String.format(java.util.Locale.ROOT, "%.2f", ClientWandProgress.damageMult));
        guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, stats, right - left),
                left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
        y += 10;
        EclipseUiTheme.drawHairline(guiGraphics, left, right, y, alpha);
        y += 4;

        // ---- tree: three path columns, 16 node rows each.
        int footerH = 34;
        treeLeft = left;
        treeTop = y + 12;
        colW = (right - left - 2 * COL_GAP) / 3;
        rowH = Mth.clamp((getY() + this.height - footerH - treeTop) / 16, 9, 12);
        boolean hovering = isHovered();

        for (int p = 0; p < PATHS.length; p++) {
            WandPath path = PATHS[p];
            int accent = ACCENTS[p];
            int colX = left + p * (colW + COL_GAP);
            List<WandTree.Node> nodes = WandTree.ofPath(path);

            int owned = 0;
            for (WandTree.Node node : nodes) {
                if (ClientWandProgress.ownsNode(node.id())) {
                    owned++;
                }
            }
            String colTitle = EclipseLang.trString(path.langKey());
            guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, colTitle, colW - 34),
                    colX, y, EclipseUiTheme.withAlpha(accent, alpha));
            String count = owned + "/" + nodes.size();
            guiGraphics.drawString(font, count, colX + colW - font.width(count), y,
                    EclipseUiTheme.withAlpha(owned >= nodes.size() ? accent : EclipseUiTheme.DIM, alpha));

            for (int r = 0; r < nodes.size(); r++) {
                WandTree.Node node = nodes.get(r);
                int rowY = treeTop + r * rowH;
                boolean ownedNode = ClientWandProgress.ownsNode(node.id());
                boolean parentsOwned = WandTree.parentsOwned(node, ClientWandProgress.nodes());
                boolean affordable = ClientWandProgress.xp >= node.cost();
                boolean pending = buyPending(node.id());
                boolean isSelectedSpell = ownedNode && node.spellKey() != null
                        && node.spellKey().equals(selectedSpell);
                boolean hoveredRow = hovering && mouseX >= colX && mouseX < colX + colW
                        && mouseY >= rowY && mouseY < rowY + rowH;
                if (hoveredRow) {
                    hoveredNode = node;
                    if (ownedNode ? node.spellKey() != null : parentsOwned) {
                        CursorManager.requestPointer();
                    }
                    guiGraphics.fill(colX - 2, rowY - 1, colX + colW + 2, rowY + rowH - 1,
                            EclipseUiTheme.withAlpha(accent, 0.10F * alpha));
                }
                if (isSelectedSpell) {
                    guiGraphics.fill(colX - 2, rowY - 1, colX + colW + 2, rowY + rowH - 1,
                            EclipseUiTheme.withAlpha(accent, 0.14F * alpha));
                }

                String prefix = ownedNode ? "✔ " : parentsOwned ? "◆ " : "· ";
                String name = prefix + nodeName(node);
                if (isSelectedSpell) {
                    name = "▶ " + nodeName(node);
                }
                int nameColor = ownedNode ? (isSelectedSpell ? accent : EclipseUiTheme.TEXT)
                        : parentsOwned ? EclipseUiTheme.TEXT : EclipseUiTheme.DIM;
                float nameAlpha = ownedNode || parentsOwned ? 1.0F : 0.7F;
                guiGraphics.drawString(font,
                        EclipseUiTheme.ellipsize(font, name, colW - 30),
                        colX, rowY, EclipseUiTheme.withAlpha(nameColor, alpha * nameAlpha));

                String meta = pending ? "…" : ownedNode ? "" : String.valueOf(node.cost());
                if (!meta.isEmpty()) {
                    int metaColor = pending ? EclipseUiTheme.DIM
                            : parentsOwned && affordable ? accent : EclipseUiTheme.DIM;
                    guiGraphics.drawString(font, meta, colX + colW - font.width(meta), rowY,
                            EclipseUiTheme.withAlpha(metaColor, alpha * 0.95F));
                }
            }
        }
        y = treeTop + 16 * rowH + 2;

        // ---- footer: hovered node detail, or the earn/cycle hints + rebirth chip.
        if (y + 10 > getY() + this.height) {
            return;
        }
        EclipseUiTheme.drawHairline(guiGraphics, left, right, y, alpha);
        y += 4;
        renderRebirthChip(guiGraphics, right, y, mouseX, mouseY);
        int textW = right - left - rebirthW - 8;
        if (hoveredNode != null) {
            renderNodeDetail(guiGraphics, hoveredNode, left, y, textW);
        } else {
            guiGraphics.drawString(font,
                    EclipseUiTheme.ellipsize(font, EclipseLang.trString("gui.eclipse.skills.wand.earn_hint",
                            ClientWandProgress.xpPerCostPoint, (int) ClientWandProgress.xpKillBonus), textW),
                    left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
            y += 10;
            if (y + 9 <= getY() + this.height) {
                String second = ClientWandProgress.treeMaxed()
                        ? EclipseLang.trString("gui.eclipse.skills.wand.rebirth_ready",
                                ClientWandProgress.nextRebirthCost())
                        : EclipseLang.trString("gui.eclipse.skills.wand.cycle_hint");
                guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, second, textW),
                        left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
            }
        }
    }

    /** Hovered node: name + one-line desc + cost/state on the footer's text side. */
    private void renderNodeDetail(GuiGraphics guiGraphics, WandTree.Node node,
            int left, int y, int textW) {
        var font = Minecraft.getInstance().font;
        boolean owned = ClientWandProgress.ownsNode(node.id());
        boolean parentsOwned = WandTree.parentsOwned(node, ClientWandProgress.nodes());
        WandSpell spell = WandSpells.byKey(node.spellKey());

        String title = nodeName(node);
        String state;
        if (owned) {
            state = spell != null
                    ? EclipseLang.trString("gui.eclipse.skills.wand.select_hint")
                    : EclipseLang.trString("gui.eclipse.skills.state.owned");
        } else if (!parentsOwned) {
            StringBuilder parents = new StringBuilder();
            for (String req : node.requires()) {
                WandTree.Node parent = WandTree.byId(req);
                if (parent != null && !ClientWandProgress.ownsNode(req)) {
                    if (parents.length() > 0) {
                        parents.append(", ");
                    }
                    parents.append(nodeName(parent));
                }
            }
            state = EclipseLang.trString("gui.eclipse.skills.requires", parents.toString());
        } else if (ClientWandProgress.xp < node.cost()) {
            state = EclipseLang.trString("gui.eclipse.skills.state.no_points");
        } else {
            state = EclipseLang.trString("gui.eclipse.skills.state.available");
        }
        String head = title + " · " + EclipseLang.trString("gui.eclipse.skills.cost", node.cost())
                + " · " + state;
        if (spell != null) {
            head = head + " · " + EclipseLang.trString("gui.eclipse.skills.wand.spell_cost",
                    ClientWandProgress.spellCost(spell.key()),
                    EclipseLang.trString(spell.castType().langKey()));
        }
        guiGraphics.drawString(font, EclipseUiTheme.ellipsize(font, head, textW),
                left, y, EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        y += 10;

        String descKey = spell != null ? spell.descKey() : node.statLangKey() + ".desc";
        if (EclipseLang.hasKey(descKey)) {
            for (FormattedCharSequence line : font.split(EclipseLang.tr(descKey), textW)) {
                if (y + 9 > getY() + this.height) {
                    break;
                }
                guiGraphics.drawString(font, line, left, y,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.95F));
                y += 10;
            }
        }
    }

    /** The REBIRTH chip, bottom-right: dim until maxed+affordable, DANGER while armed. */
    private void renderRebirthChip(GuiGraphics guiGraphics, int right, int y,
            int mouseX, int mouseY) {
        var font = Minecraft.getInstance().font;
        boolean maxed = ClientWandProgress.treeMaxed();
        boolean affordable = ClientWandProgress.xp >= ClientWandProgress.nextRebirthCost();
        boolean armed = rebirthArmed();
        String label = armed
                ? EclipseLang.trString("gui.eclipse.skills.wand.rebirth_confirm")
                : EclipseLang.trString("gui.eclipse.skills.wand.rebirth",
                        ClientWandProgress.nextRebirthCost());
        rebirthW = font.width(label) + 12;
        rebirthX = right - rebirthW;
        rebirthY = y - 2;
        int chipH = 12;

        rebirthHovered = maxed && isHovered()
                && mouseX >= rebirthX && mouseX < rebirthX + rebirthW
                && mouseY >= rebirthY && mouseY < rebirthY + chipH;
        if (rebirthHovered && affordable) {
            CursorManager.requestPointer();
        }

        int border = armed ? EclipseUiTheme.DANGER
                : maxed && affordable ? EclipseUiTheme.ACCENT : EclipseUiTheme.HAIRLINE;
        int textColor = armed ? EclipseUiTheme.DANGER
                : maxed && affordable ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM;
        guiGraphics.fill(rebirthX, rebirthY, rebirthX + rebirthW, rebirthY + chipH,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED,
                        (rebirthHovered ? 1.0F : 0.8F) * alpha));
        guiGraphics.fill(rebirthX, rebirthY, rebirthX + rebirthW, rebirthY + 1,
                EclipseUiTheme.withAlpha(border, alpha));
        guiGraphics.fill(rebirthX, rebirthY + chipH - 1, rebirthX + rebirthW, rebirthY + chipH,
                EclipseUiTheme.withAlpha(border, alpha));
        guiGraphics.drawString(font, label, rebirthX + 6, rebirthY + 2,
                EclipseUiTheme.withAlpha(textColor, alpha));
    }

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------

    @Override
    public void onClick(double mouseX, double mouseY) {
        ItemStack wand = findWand();
        if (wand == null) {
            return;
        }
        if (WandSoulbind.pathOf(wand) == WandPath.NONE) {
            if (choicePending()) {
                return;
            }
            int card = cardAt(mouseX, mouseY);
            if (card >= 0) {
                // Same contract as WandPathScreen.choose — the server locks + re-validates.
                UiSounds.click();
                PacketDistributor.sendToServer(new C2SWandChoosePathPayload(PATHS[card].id()));
                choseAtMillis = Util.getMillis();
            }
            return;
        }
        if (!ClientWandProgress.synced) {
            return;
        }
        // Rebirth chip (maxed tree): first click arms, second inside the window fires.
        if (rebirthHovered) {
            handleRebirthClick();
            return;
        }
        WandTree.Node node = nodeAt(mouseX, mouseY);
        if (node != null) {
            handleNodeClick(node, wand);
        }
    }

    /** The node under (x, y) in the last-rendered tree grid, or null. */
    @Nullable
    private WandTree.Node nodeAt(double mouseX, double mouseY) {
        if (rowH <= 0 || mouseY < treeTop || mouseY >= treeTop + 16 * rowH) {
            return null;
        }
        int row = (int) ((mouseY - treeTop) / rowH);
        for (int p = 0; p < PATHS.length; p++) {
            int colX = treeLeft + p * (colW + COL_GAP);
            if (mouseX >= colX && mouseX < colX + colW) {
                List<WandTree.Node> nodes = WandTree.ofPath(PATHS[p]);
                return row < nodes.size() ? nodes.get(row) : null;
            }
        }
        return null;
    }

    /**
     * Node click: OWNED spell node → select that spell; buyable node → buy request
     * (with a pending lock). Everything re-validates server-side in
     * {@code WandTreeService}.
     */
    private void handleNodeClick(WandTree.Node node, ItemStack wand) {
        boolean owned = ClientWandProgress.ownsNode(node.id());
        if (owned) {
            WandSpell spell = WandSpells.byKey(node.spellKey());
            if (spell != null && !spell.key().equals(wand.get(WandItems.WAND_SPELL.get()))) {
                UiSounds.click();
                PacketDistributor.sendToServer(new C2SWandSelectSpellPayload(spell.key()));
            }
            return;
        }
        if (buyPending(node.id())) {
            return; // request already in flight
        }
        if (!WandTree.parentsOwned(node, ClientWandProgress.nodes())
                || ClientWandProgress.xp < node.cost()) {
            UiSounds.error();
            return;
        }
        UiSounds.click();
        pendingNodeId = node.id();
        pendingAtMillis = Util.getMillis();
        PacketDistributor.sendToServer(new C2SWandNodeBuyPayload(node.id()));
    }

    private void handleRebirthClick() {
        if (!ClientWandProgress.treeMaxed()
                || ClientWandProgress.xp < ClientWandProgress.nextRebirthCost()) {
            UiSounds.error();
            return;
        }
        if (rebirthArmed()) {
            rebirthArmedAtMillis = 0L;
            UiSounds.levelUp();
            PacketDistributor.sendToServer(new C2SWandRebirthPayload());
        } else {
            rebirthArmedAtMillis = Util.getMillis();
            UiSounds.hover();
        }
    }

    /** The panel is silent — clicks play their own cues in the handlers. */
    @Override
    public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
    }

    @Override
    protected void updateWidgetNarration(NarrationElementOutput narrationElementOutput) {
        narrationElementOutput.add(NarratedElementType.TITLE,
                EclipseLang.tr("gui.eclipse.skills.tab.wand"));
    }
}
