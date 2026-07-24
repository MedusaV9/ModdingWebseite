package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.ritual.HeartExtractorItem;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.crafting.Ingredient;
import net.minecraft.world.item.crafting.RecipeHolder;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Revival page (NEW in v3 — plans_v3 P3 §3.1): documents the revive ritual as three
 * numbered seals with real item icons and code-drawn arrows:
 *
 * <pre>
 *   I.   ❤❤ ──(Heart Extractor)──▶ ▦▦▦▦          2 hearts → 4 fragments
 *   II.  ▦▦▦▦ + materials ──▶ Revive Sigil        (materials read live from the recipe)
 *   III. Sigil + Altar ──▶ the fallen returns ❤1  (cycle · sneak-confirm at the altar)
 * </pre>
 *
 * <p>The extraction math reads the LANDED P4-B8 item constants directly
 * ({@link HeartExtractorItem#HEART_COST} = 2 own hearts per channel,
 * {@link HeartExtractorItem#FRAGMENT_REWARD} = 4 fragments, safety floor
 * {@link HeartExtractorItem#MIN_REMAINING_HEARTS} = the extractor refuses any cut past
 * one heart), so the page can never drift from gameplay. The step-II material row is
 * data-driven too: it reads the synced {@code eclipse:revive_sigil} recipe from the
 * client's {@code RecipeManager} (fragment demand included), falling back to the shipped
 * recipe's materials (4x netherite ingot, nether star, dragon's breath) when the lookup
 * is unavailable. The revived wakes with a single heart on the ship of the dead. Item
 * icons render only above 50% crossfade alpha — {@code renderItem} ignores alpha and
 * would burn through the page fade otherwise.</p>
 *
 * <p>Long-page plumbing matches the other tabs: wheel + content drag + the shared
 * {@link TabScrollbar}; presses are only consumed while something can scroll (B20 rule);
 * content height is measured during render so the wrap-dependent layout can never drift
 * from the scroll range.</p>
 */
@OnlyIn(Dist.CLIENT)
public class RevivalTab extends HandbookTab {
    private static final ResourceLocation HEART_FULL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_full.png");

    /** Fallback fragment demand when the recipe is not synced yet (shipped recipe = 4). */
    private static final int FALLBACK_FRAGMENTS = 4;
    /** Icon strip row height (16px items + breathing room). */
    private static final int ICON_ROW_H = 20;
    private static final int LINE_HEIGHT = 10;
    /** Right-side inset reserved for the scrollbar + a small gap. */
    private static final int SCROLLBAR_INSET = 8;

    private final TabScrollbar scrollbar = new TabScrollbar();
    private double scrollAmount;
    private boolean dragging;

    // Recipe-derived data (resolved in onInit, fallback-safe).
    private int fragmentsNeeded = FALLBACK_FRAGMENTS;
    private int heartsNeeded = heartsFor(FALLBACK_FRAGMENTS);
    private int fragmentsYield = yieldFor(FALLBACK_FRAGMENTS);
    private List<ItemStack> sigilMaterials = List.of();

    // Wrapped text caches (rebuilt on init/resize; EclipseLang reload re-inits the screen).
    private final List<FormattedCharSequence> introLines = new ArrayList<>();
    private final List<List<FormattedCharSequence>> stepLines =
            List.of(new ArrayList<>(), new ArrayList<>(), new ArrayList<>());
    private final List<FormattedCharSequence> warningLines = new ArrayList<>();
    private final List<FormattedCharSequence> aftercareLines = new ArrayList<>();

    /** Content height measured by the last render pass (wrap + icon rows), for the scroll range. */
    private int measuredContentHeight;

    /** Extractor channels needed to cover {@code fragments} (each yields FRAGMENT_REWARD). */
    private static int channelsFor(int fragments) {
        return Math.max(1, (fragments + HeartExtractorItem.FRAGMENT_REWARD - 1)
                / HeartExtractorItem.FRAGMENT_REWARD);
    }

    /** Total own hearts paid to cover {@code fragments} (HEART_COST per channel). */
    private static int heartsFor(int fragments) {
        return channelsFor(fragments) * HeartExtractorItem.HEART_COST;
    }

    /** Fragments actually produced by those channels (>= demand when it does not divide). */
    private static int yieldFor(int fragments) {
        return channelsFor(fragments) * HeartExtractorItem.FRAGMENT_REWARD;
    }

    @Override
    public String id() {
        return "revival";
    }

    @Override
    protected void onInit() {
        resolveRecipe();
        int wrapWidth = Math.max(40, width - SCROLLBAR_INSET);
        introLines.clear();
        introLines.addAll(font.split(EclipseLang.tr("gui.eclipse.handbook.revival.intro"), wrapWidth));
        for (int step = 0; step < 3; step++) {
            List<FormattedCharSequence> lines = stepLines.get(step);
            lines.clear();
            Object[] args = step == 0
                    ? new Object[] {HeartExtractorItem.HEART_COST, HeartExtractorItem.FRAGMENT_REWARD,
                            fragmentsNeeded}
                    : new Object[0];
            lines.addAll(font.split(EclipseLang.tr(
                    "gui.eclipse.handbook.revival.step" + (step + 1) + ".text", args), wrapWidth));
        }
        warningLines.clear();
        warningLines.addAll(font.split(EclipseLang.tr("gui.eclipse.handbook.revival.warning",
                HeartExtractorItem.HEART_COST + HeartExtractorItem.MIN_REMAINING_HEARTS),
                wrapWidth - 6));
        aftercareLines.clear();
        aftercareLines.addAll(font.split(EclipseLang.tr("gui.eclipse.handbook.revival.aftercare"),
                wrapWidth - 20));
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());
    }

    @Override
    public void onShown() {
        dragging = false;
    }

    /**
     * Reads fragment count + companion materials from the synced
     * {@code eclipse:revive_sigil} recipe; falls back to the shipped recipe when the
     * client has no level / the recipe was removed by a datapack.
     */
    private void resolveRecipe() {
        int fragments = 0;
        Map<Item, Integer> counts = new LinkedHashMap<>();
        if (minecraft != null && minecraft.level != null) {
            RecipeHolder<?> holder = minecraft.level.getRecipeManager()
                    .byKey(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "revive_sigil"))
                    .orElse(null);
            if (holder != null) {
                for (Ingredient ingredient : holder.value().getIngredients()) {
                    ItemStack[] options = ingredient.getItems();
                    if (options.length == 0) {
                        continue;
                    }
                    ItemStack first = options[0];
                    if (first.is(EclipseItems.HEART_FRAGMENT.get())) {
                        fragments++;
                    } else {
                        counts.merge(first.getItem(), 1, Integer::sum);
                    }
                }
            }
        }
        fragmentsNeeded = fragments > 0 ? fragments : FALLBACK_FRAGMENTS;
        heartsNeeded = heartsFor(fragmentsNeeded);
        fragmentsYield = yieldFor(fragmentsNeeded);
        if (counts.isEmpty()) {
            sigilMaterials = List.of(new ItemStack(Items.NETHERITE_INGOT, 4),
                    new ItemStack(Items.NETHER_STAR), new ItemStack(Items.DRAGON_BREATH));
        } else {
            List<ItemStack> materials = new ArrayList<>(counts.size());
            counts.forEach((item, count) -> materials.add(new ItemStack(item, count)));
            sigilMaterials = List.copyOf(materials);
        }
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());
        boolean drawItems = alpha >= 0.5F; // renderItem ignores alpha — skip mid-crossfade

        guiGraphics.enableScissor(x, y, x + width, y + height);
        int top = y + 2 - (int) scrollAmount;
        int drawY = top;

        drawY = drawLines(guiGraphics, introLines, x, drawY, DIM_COLOR, alpha);
        drawY += EclipseUiTheme.GAP;

        for (int step = 0; step < 3; step++) {
            drawY += EclipseUiTheme.GAP;
            guiGraphics.drawString(font,
                    ellipsize(font, EclipseLang.trString(
                            "gui.eclipse.handbook.revival.step" + (step + 1) + ".title"),
                            width - SCROLLBAR_INSET),
                    x, drawY, withAlpha(ACCENT_COLOR, alpha));
            drawY += LINE_HEIGHT + 2;
            drawY = drawLines(guiGraphics, stepLines.get(step), x, drawY, TEXT_COLOR, alpha);
            drawY += 2;
            switch (step) {
                case 0 -> drawExtractionRow(guiGraphics, drawY, drawItems, alpha);
                case 1 -> drawForgeRow(guiGraphics, drawY, drawItems, alpha);
                default -> drawAltarRow(guiGraphics, drawY, drawItems, alpha);
            }
            drawY += ICON_ROW_H + EclipseUiTheme.GAP;
        }

        // Warning block: hairline above, DANGER bar + DANGER text.
        drawY += EclipseUiTheme.GAP;
        EclipseUiTheme.drawHairline(guiGraphics, x, x + width - SCROLLBAR_INSET + 2, drawY, alpha);
        drawY += EclipseUiTheme.GAP + 2;
        int warningTop = drawY;
        drawY = drawLines(guiGraphics, warningLines, x + 6, drawY,
                EclipseUiTheme.DANGER & 0xFFFFFF, alpha);
        guiGraphics.fill(x, warningTop - 1, x + 2, drawY - 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.DANGER, alpha));

        // Aftercare footnote: vitae shard icon + DIM line.
        drawY += EclipseUiTheme.GAP;
        int aftercareTop = drawY;
        if (drawItems) {
            guiGraphics.renderItem(new ItemStack(EclipseItems.VITAE_SHARD.get()), x, aftercareTop);
        }
        int textHeight = aftercareLines.size() * LINE_HEIGHT;
        drawY = drawLines(guiGraphics, aftercareLines, x + 20,
                aftercareTop + Math.max(0, (16 - textHeight) / 2), DIM_COLOR, alpha);
        drawY = Math.max(drawY, aftercareTop + 16);

        guiGraphics.disableScissor();
        measuredContentHeight = drawY + 2 - top;

        scrollbar.layout(x + width, y + 2, height - 4);
        scrollbar.size(height, measuredContentHeight);
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    private int drawLines(GuiGraphics guiGraphics, List<FormattedCharSequence> lines, int textX, int textY,
            int color, float alpha) {
        for (FormattedCharSequence line : lines) {
            if (textY > y - LINE_HEIGHT && textY < y + height) {
                guiGraphics.drawString(font, line, textX, textY, withAlpha(color, alpha));
            }
            textY += LINE_HEIGHT;
        }
        return textY;
    }

    /** Step I strip: ❤ x heartsNeeded ── extractor ──▶ fragment stack, + math caption. */
    private void drawExtractionRow(GuiGraphics guiGraphics, int rowY, boolean drawItems, float alpha) {
        int cursor = x + 2;
        cursor = drawHearts(guiGraphics, cursor, rowY, heartsNeeded, alpha);
        cursor = drawArrow(guiGraphics, cursor, rowY, alpha);
        cursor = drawStack(guiGraphics, cursor, rowY,
                new ItemStack(EclipseItems.HEART_EXTRACTOR.get()), drawItems);
        cursor = drawArrow(guiGraphics, cursor, rowY, alpha);
        cursor = drawStack(guiGraphics, cursor, rowY,
                new ItemStack(EclipseItems.HEART_FRAGMENT.get(), fragmentsYield), drawItems);
        drawRowCaption(guiGraphics, cursor, rowY, alpha,
                EclipseLang.trString("gui.eclipse.handbook.revival.step1.math", heartsNeeded, fragmentsYield));
    }

    /** Step II strip: fragments + each recipe material ──▶ sigil, + math caption. */
    private void drawForgeRow(GuiGraphics guiGraphics, int rowY, boolean drawItems, float alpha) {
        int cursor = x + 2;
        cursor = drawStack(guiGraphics, cursor, rowY,
                new ItemStack(EclipseItems.HEART_FRAGMENT.get(), fragmentsNeeded), drawItems);
        for (ItemStack material : sigilMaterials) {
            cursor = drawPlus(guiGraphics, cursor, rowY, alpha);
            cursor = drawStack(guiGraphics, cursor, rowY, material, drawItems);
        }
        cursor = drawArrow(guiGraphics, cursor, rowY, alpha);
        cursor = drawStack(guiGraphics, cursor, rowY,
                new ItemStack(EclipseItems.REVIVE_SIGIL.get()), drawItems);
        drawRowCaption(guiGraphics, cursor, rowY, alpha,
                EclipseLang.trString("gui.eclipse.handbook.revival.step2.math", fragmentsNeeded));
    }

    /** Step III strip: sigil + altar ──▶ ❤1, + math caption. */
    private void drawAltarRow(GuiGraphics guiGraphics, int rowY, boolean drawItems, float alpha) {
        int cursor = x + 2;
        cursor = drawStack(guiGraphics, cursor, rowY,
                new ItemStack(EclipseItems.REVIVE_SIGIL.get()), drawItems);
        cursor = drawPlus(guiGraphics, cursor, rowY, alpha);
        cursor = drawStack(guiGraphics, cursor, rowY, new ItemStack(EclipseItems.ALTAR.get()), drawItems);
        cursor = drawArrow(guiGraphics, cursor, rowY, alpha);
        cursor = drawHearts(guiGraphics, cursor, rowY, 1, alpha);
        drawRowCaption(guiGraphics, cursor, rowY, alpha,
                EclipseLang.trString("gui.eclipse.handbook.revival.step3.math"));
    }

    /** Right-aligned DIM caption on an icon strip; silently dropped when it cannot fit. */
    private void drawRowCaption(GuiGraphics guiGraphics, int stripEnd, int rowY, float alpha, String caption) {
        int captionWidth = font.width(caption);
        int right = x + width - SCROLLBAR_INSET;
        if (stripEnd + 10 + captionWidth <= right) {
            guiGraphics.drawString(font, caption, right - captionWidth, rowY + 6,
                    withAlpha(DIM_COLOR, alpha));
        }
    }

    private int drawStack(GuiGraphics guiGraphics, int cursor, int rowY, ItemStack stack, boolean drawItems) {
        if (drawItems) {
            guiGraphics.renderItem(stack, cursor, rowY + 2);
            if (stack.getCount() > 1) {
                guiGraphics.renderItemDecorations(font, stack, cursor, rowY + 2,
                        String.valueOf(stack.getCount()));
            }
        }
        return cursor + 18;
    }

    /** A short row of 9px heart icons (1:1 blits, never scaled). */
    private int drawHearts(GuiGraphics guiGraphics, int cursor, int rowY, int count, float alpha) {
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        for (int i = 0; i < count; i++) {
            guiGraphics.blit(HEART_FULL, cursor + i * 11, rowY + 5, 0, 0, 9, 9, 9, 9);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        return cursor + count * 11 + 1;
    }

    /** Code-drawn right arrow (shaft + solid triangle head), DIM — crisp at any gui scale. */
    private int drawArrow(GuiGraphics guiGraphics, int cursor, int rowY, float alpha) {
        int color = withAlpha(DIM_COLOR, alpha);
        int cy = rowY + 9;
        int shaftStart = cursor + 3;
        guiGraphics.fill(shaftStart, cy, shaftStart + 7, cy + 1, color);
        guiGraphics.fill(shaftStart + 7, cy - 3, shaftStart + 8, cy + 4, color);
        guiGraphics.fill(shaftStart + 8, cy - 2, shaftStart + 9, cy + 3, color);
        guiGraphics.fill(shaftStart + 9, cy - 1, shaftStart + 10, cy + 2, color);
        guiGraphics.fill(shaftStart + 10, cy, shaftStart + 11, cy + 1, color);
        return shaftStart + 14;
    }

    /** Small code-drawn plus between combined inputs, DIM. */
    private int drawPlus(GuiGraphics guiGraphics, int cursor, int rowY, float alpha) {
        int color = withAlpha(DIM_COLOR, alpha);
        int cx = cursor + 4;
        int cy = rowY + 9;
        guiGraphics.fill(cx - 2, cy, cx + 3, cy + 1, color);
        guiGraphics.fill(cx, cy - 2, cx + 1, cy + 3, color);
        return cursor + 11;
    }

    // --- scroll plumbing (wheel + content drag + shared scrollbar; B20-safe) ---

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseClicked(mouseX, mouseY, scrollAmount, value -> scrollAmount = value)) {
            return true;
        }
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            dragging = true;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseDragged(mouseY, value -> scrollAmount = value)) {
            return true;
        }
        if (dragging) {
            scrollAmount = Mth.clamp(scrollAmount - dragY, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseReleased()) {
            return true;
        }
        if (dragging) {
            dragging = false;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * LINE_HEIGHT * 2, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    private double maxScroll() {
        return Math.max(0, measuredContentHeight - height);
    }

    @Override
    public boolean dragging() {
        return dragging || scrollbar.dragging();
    }
}
