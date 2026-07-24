package dev.projecteclipse.eclipse.devtools.dev.handbook;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.ConfigRefEntry;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.EditBox;
import net.minecraft.client.gui.screens.ChatScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.lwjgl.glfw.GLFW;

/**
 * The DEV HANDBOOK (P5-W2, plan §2.2): every dev/admin command documented and clickable, for
 * ops only. Opened exclusively via {@code S2CDevHandbookPayload} (bare {@code /dev} or a
 * refresh round-trip) — there is no client-side opening path, so non-ops can never reach it.
 *
 * <p>Layout (flat/compact "Quiet Eclipse" — reuses the frozen {@code client.handbook} kit but
 * deliberately without parallax/hero art; this is a tool, not a diegetic book):</p>
 * <ul>
 *   <li><b>Left rail</b> — "All", every {@link DevCategory} that has visible entries, and a
 *       pinned "Configs" tab (the §2.12 config reference table).</li>
 *   <li><b>Header</b> — title left; live day/stage/timer snapshot right (from
 *       {@link ClientStateCache} day-clock + stage payload caches).</li>
 *   <li><b>Search</b> — fuzzy filter box ({@link DevHandbookSearch}), instant per keystroke;
 *       {@code /} focuses it from anywhere in the screen (screen-local hotkey).</li>
 *   <li><b>Entry cards</b> — syntax with argument placeholders, localized description
 *       (en+de ship in the jar), permission badge (OP2/OP3), danger badge (CAUTION amber /
 *       DESTRUCTIVE red), legacy tag, and one action button: <i>Run</i> for zero-argument
 *       commands (executes via the player's own connection — the server re-validates
 *       permissions exactly as if typed) or <i>To chat</i> for parameterized ones (closes the
 *       screen and pre-fills {@link ChatScreen} with the literal prefix).</li>
 *   <li><b>Confirm dialog</b> — every DESTRUCTIVE entry (stage load/revert, resets, clears)
 *       asks before running or inserting.</li>
 *   <li><b>Bottom bar</b> — match counter / status flash, Configs toggle, docs export, and a
 *       {@code /dev reload} button inside the Configs tab. {@code F5} re-requests the
 *       registry snapshot (op-gated server-side).</li>
 * </ul>
 *
 * <p>All chrome is {@code fill}/{@code text} through {@link EclipseUiTheme}, so the layout
 * stays crisp at every GUI scale (checked against 2/3; clamps keep it usable down to
 * ~480×270 logical). Card action buttons scroll with the list and are therefore manual hit
 * rects (recomputed every frame, clipped to the list viewport) rather than widgets; rail,
 * bar and search are real widgets from the {@link EclipseWidget} suite.</p>
 */
@OnlyIn(Dist.CLIENT)
public class DevHandbookScreen extends Screen {
    private static final float PANEL_PCT = 0.92F;
    private static final int MAX_PANEL_W = 580;
    private static final int MAX_PANEL_H = 340;
    private static final int RAIL_W = 92;
    private static final int HEADER_H = 22;
    private static final int SEARCH_H = 16;
    private static final int FOOTER_H = 18;
    private static final int BUTTON_W = 52;
    private static final int BUTTON_H = 13;
    private static final int SCROLL_STEP = 24;
    /** Amber for CAUTION badges (kit palette has GOOD/DANGER only; matches DevRoot's chat color). */
    private static final int CAUTION_COLOR = 0xFFE0A84C;
    private static final long STATUS_FLASH_MILLIS = 2500L;

    /** One laid-out entry card (heights vary with the wrapped description). */
    private record Card(DevCommandDoc doc, List<FormattedCharSequence> descLines, int y, int height) {}

    /** Manual hit rect for buttons that scroll with content (cards, confirm dialog). */
    private record HitRect(String key, int x, int y, int w, int h, boolean danger, Runnable action) {
        boolean contains(double mx, double my) {
            return mx >= x && mx < x + w && my >= y && my < y + h;
        }
    }

    // Panel geometry (recomputed in init()).
    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;
    private int railSepX;
    private int contentX;
    private int contentW;
    private int listY;
    private int listH;
    private int footerY;

    // View state (survives init()/resize/data refresh).
    @Nullable
    private DevCategory selectedCategory; // null = All
    private boolean configView;
    private String query = "";
    private double scrollY;
    private int contentHeight;
    @Nullable
    private DevCommandDoc confirmDoc;
    @Nullable
    private Component statusFlash;
    private long statusFlashUntil;
    private boolean refreshRequested;
    private boolean swallowSlashChar;
    /** Widget-list rebuilds are deferred to the next frame — never mutate mid-event-dispatch. */
    private boolean pendingRebuild;

    private final List<Card> cards = new ArrayList<>();
    private final List<HitRect> frameButtons = new ArrayList<>();
    @Nullable
    private String hoveredManualKey;
    @Nullable
    private String lastHoveredManualKey;

    private EditBox searchBox;

    public DevHandbookScreen() {
        super(Component.translatable("gui.eclipse.devhandbook.title"));
    }

    // ------------------------------------------------------------------ layout & widgets

    @Override
    protected void init() {
        panelW = Math.min(Math.round(this.width * PANEL_PCT), MAX_PANEL_W);
        panelH = Math.min(Math.round(this.height * PANEL_PCT), MAX_PANEL_H);
        panelW = Math.max(panelW, Math.min(this.width, RAIL_W + 200));
        panelH = Math.max(panelH, Math.min(this.height, 160));
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        railSepX = panelX + RAIL_W;
        contentX = railSepX + 1 + EclipseUiTheme.PAD;
        contentW = panelX + panelW - EclipseUiTheme.PAD - contentX;
        listY = panelY + HEADER_H + SEARCH_H + 8;
        footerY = panelY + panelH - FOOTER_H;
        listH = footerY - 4 - listY;

        buildRail();
        buildSearchBox();
        buildBottomBar();
        reflow();

        if (!refreshRequested) {
            refreshRequested = true;
            DevHandbookClient.requestRefresh(); // op-gated server-side; updates in place
        }
    }

    /** Rail rows: All, categories with visible entries (enum order), pinned Configs tab. */
    private void buildRail() {
        List<DevCategory> present = presentCategories();
        int rows = present.size() + 2;
        int railTop = panelY + 6;
        int railBottom = panelY + panelH - 6;
        int rowH = Mth.clamp((railBottom - railTop) / Math.max(1, rows), 10, 14);

        int y = railTop;
        addRenderableWidget(new RailButton(null, false, panelX + 2, y, RAIL_W - 5, rowH - 1));
        y += rowH;
        for (DevCategory category : present) {
            addRenderableWidget(new RailButton(category, false, panelX + 2, y, RAIL_W - 5, rowH - 1));
            y += rowH;
        }
        addRenderableWidget(new RailButton(null, true, panelX + 2, railBottom - rowH + 1, RAIL_W - 5, rowH - 1));
    }

    private void buildSearchBox() {
        int y = panelY + HEADER_H + 4;
        searchBox = new EditBox(this.font, contentX + 2, y + 2, contentW - 4, 12,
                Component.translatable("gui.eclipse.devhandbook.search.hint"));
        searchBox.setBordered(false);
        searchBox.setMaxLength(64);
        searchBox.setValue(query);
        searchBox.setHint(Component.translatable("gui.eclipse.devhandbook.search.hint")
                .withStyle(style -> style.withColor(EclipseUiTheme.DIM)));
        searchBox.setResponder(this::onQueryChanged);
        searchBox.setTextColor(EclipseUiTheme.TEXT);
        addRenderableWidget(searchBox);
    }

    private void buildBottomBar() {
        int y = footerY + 2;
        int x = panelX + panelW - EclipseUiTheme.PAD;

        x -= 58;
        addRenderableWidget(new BarButton(x, y, 58, 13,
                Component.translatable("gui.eclipse.devhandbook.button.docs"), false,
                () -> runRawCommand("dev docs export")));
        x -= 62;
        addRenderableWidget(new BarButton(x, y, 58, 13,
                Component.translatable(configView ? "gui.eclipse.devhandbook.button.commands"
                        : "gui.eclipse.devhandbook.button.configs"),
                configView, this::toggleConfigView));
        if (configView) {
            x -= 62;
            addRenderableWidget(new BarButton(x, y, 58, 13,
                    Component.translatable("gui.eclipse.devhandbook.button.reload"), false, () -> {
                        runRawCommand("dev reload");
                        DevHandbookClient.requestRefresh();
                    }));
        }
    }

    private void toggleConfigView() {
        configView = !configView;
        scrollY = 0.0D;
        pendingRebuild = true;
    }

    /** Categories (enum order) that have at least one synced entry. */
    private List<DevCategory> presentCategories() {
        Set<DevCategory> present = new LinkedHashSet<>();
        for (DevCommandDoc doc : DevHandbookClient.entries()) {
            present.add(doc.category());
        }
        List<DevCategory> ordered = new ArrayList<>();
        for (DevCategory category : DevCategory.values()) {
            if (present.contains(category)) {
                ordered.add(category);
            }
        }
        return ordered;
    }

    /** Payload receipt while open: keep selection/query/scroll, refresh rail + cards. */
    void onDataUpdated() {
        if (selectedCategory != null && !presentCategories().contains(selectedCategory)) {
            selectedCategory = null;
        }
        pendingRebuild = true;
    }

    private void onQueryChanged(String value) {
        if (!value.equals(query)) {
            query = value;
            scrollY = 0.0D;
            reflow();
        }
    }

    /** Recomputes the filtered, ranked card list and its layout heights. */
    private void reflow() {
        cards.clear();
        int textW = cardTextWidth();
        record Ranked(DevCommandDoc doc, int score, int index) {}
        List<Ranked> ranked = new ArrayList<>();
        List<DevCommandDoc> entries = DevHandbookClient.entries();
        for (int i = 0; i < entries.size(); i++) {
            DevCommandDoc doc = entries.get(i);
            if (selectedCategory != null && doc.category() != selectedCategory) {
                continue;
            }
            int score = DevHandbookSearch.score(query, doc.syntax(),
                    Component.translatable(doc.descKey()).getString());
            if (score > 0) {
                ranked.add(new Ranked(doc, score, i));
            }
        }
        ranked.sort(Comparator.comparingInt(Ranked::score).reversed()
                .thenComparingInt(Ranked::index)); // stable: registry order within a rank
        int y = 0;
        for (Ranked entry : ranked) {
            List<FormattedCharSequence> lines =
                    this.font.split(Component.translatable(entry.doc().descKey()), Math.max(40, textW));
            if (lines.size() > 2) {
                lines = lines.subList(0, 2);
            }
            int height = 18 + lines.size() * 10;
            cards.add(new Card(entry.doc(), lines, y, height));
            y += height + 3;
        }
        contentHeight = Math.max(0, y - 3);
        clampScroll();
    }

    private int cardTextWidth() {
        return contentW - BUTTON_W - 18;
    }

    private void clampScroll() {
        int max = Math.max(0, currentContentHeight() - listH);
        scrollY = Mth.clamp(scrollY, 0.0D, max);
    }

    private int currentContentHeight() {
        return configView ? configRowCount() * 12 + 14 : contentHeight;
    }

    private int configRowCount() {
        return DevHandbookClient.configRefs().size();
    }

    // ------------------------------------------------------------------ actions

    /** Card button press: DESTRUCTIVE asks first; then run (zero-arg) or chat-insert. */
    private void onCardAction(DevCommandDoc doc) {
        if (doc.danger() == Danger.DESTRUCTIVE) {
            confirmDoc = doc;
            return;
        }
        performAction(doc);
    }

    private void performAction(DevCommandDoc doc) {
        if (doc.clickAction() == ClickAction.RUN) {
            runRawCommand(runnableCommand(doc.syntax()));
        } else {
            insertIntoChat(doc);
        }
    }

    /**
     * Executes through the player's own connection — identical to typing the command, so the
     * server's Brigadier permission checks apply unchanged (never trust the client).
     */
    private void runRawCommand(String commandNoSlash) {
        if (this.minecraft != null && this.minecraft.player != null) {
            this.minecraft.player.connection.sendCommand(commandNoSlash);
            statusFlash = Component.translatable("gui.eclipse.devhandbook.ran", "/" + commandNoSlash);
            statusFlashUntil = System.currentTimeMillis() + STATUS_FLASH_MILLIS;
        }
    }

    /** Closes the handbook and re-opens chat pre-filled with the literal command prefix. */
    private void insertIntoChat(DevCommandDoc doc) {
        if (this.minecraft != null) {
            this.minecraft.setScreen(new ChatScreen(insertText(doc.syntax())));
        }
    }

    /** {@code "/dev timer add <duration>"} → {@code "dev timer add"} (RUN strips placeholders). */
    static String runnableCommand(String syntax) {
        String text = insertText(syntax).strip();
        return text.startsWith("/") ? text.substring(1) : text;
    }

    /** {@code "/dev timer add <duration>"} → {@code "/dev timer add "} (prefill for chat). */
    static String insertText(String syntax) {
        String text = syntax;
        for (String marker : new String[] {" <", " [", " (", "…"}) {
            int at = text.indexOf(marker);
            if (at > 0) {
                text = text.substring(0, at);
            }
        }
        text = text.strip();
        return text + " ";
    }

    // ------------------------------------------------------------------ rendering

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        if (pendingRebuild) {
            pendingRebuild = false;
            rebuildWidgets(); // safe here: render runs outside input dispatch
        }
        hoveredManualKey = null;
        super.render(guiGraphics, mouseX, mouseY, partialTick); // background + widgets
        if (confirmDoc != null) {
            renderConfirmDialog(guiGraphics, mouseX, mouseY);
        }
        if (hoveredManualKey != null) {
            CursorManager.requestPointer();
            if (!hoveredManualKey.equals(lastHoveredManualKey)) {
                UiSounds.hover();
            }
        }
        lastHoveredManualKey = hoveredManualKey;
        CursorManager.endFrame();
    }

    /** Flat veil + panel + rail separator + header + search underline + list + bottom bar. */
    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        frameButtons.clear();
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);
        EclipseUiTheme.drawPanel(guiGraphics, panelX, panelY, panelW, panelH);
        guiGraphics.fill(railSepX, panelY + 1, railSepX + 1, panelY + panelH - 1, EclipseUiTheme.HAIRLINE);

        renderHeader(guiGraphics);
        renderSearchChrome(guiGraphics);
        boolean dialogOpen = confirmDoc != null;
        int listMouseX = dialogOpen ? Integer.MIN_VALUE : mouseX;
        int listMouseY = dialogOpen ? Integer.MIN_VALUE : mouseY;
        guiGraphics.enableScissor(contentX - 2, listY, contentX + contentW + 2, listY + listH);
        if (configView) {
            renderConfigList(guiGraphics);
        } else {
            renderCards(guiGraphics, listMouseX, listMouseY);
        }
        guiGraphics.disableScissor();
        renderScrollbar(guiGraphics);
        renderFooter(guiGraphics);
    }

    /** Title left; live day/stage/timer snapshot right (client caches, §2.2). */
    private void renderHeader(GuiGraphics guiGraphics) {
        int textY = panelY + 8;
        Component snapshot = Component.translatable("gui.eclipse.devhandbook.header.snapshot",
                snapshotDay(), ClientStateCache.stageOverworld, timerText());
        int snapshotW = this.font.width(snapshot);
        boolean showSnapshot = snapshotW + 70 <= contentW;
        if (showSnapshot) {
            guiGraphics.drawString(this.font, snapshot, contentX + contentW - snapshotW, textY,
                    EclipseUiTheme.TEXT);
        }
        int titleMax = contentW - (showSnapshot ? snapshotW + 10 : 0);
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, this.title.getString(), Math.max(20, titleMax)),
                contentX, textY, EclipseUiTheme.ACCENT);
        EclipseUiTheme.drawHairline(guiGraphics, contentX, contentX + contentW, panelY + HEADER_H);
    }

    private int snapshotDay() {
        return ClientStateCache.clockSyncLocalMillis > 0L ? ClientStateCache.dayClockDay : ClientStateCache.day;
    }

    /** Remaining time to the next day boundary; "—" until the first clock sync. */
    private Component timerText() {
        if (ClientStateCache.clockSyncLocalMillis <= 0L || ClientStateCache.boundaryEpochMillis <= 0L) {
            return Component.literal("—");
        }
        if (ClientStateCache.dayClockPaused) {
            return Component.translatable("gui.eclipse.devhandbook.header.paused",
                    formatDuration(ClientStateCache.pauseRemainingMillis));
        }
        long serverNow = ClientStateCache.serverNowEpochMillis
                + (System.currentTimeMillis() - ClientStateCache.clockSyncLocalMillis);
        return Component.literal(formatDuration(ClientStateCache.boundaryEpochMillis - serverNow));
    }

    static String formatDuration(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        long hours = totalSeconds / 3600L;
        long minutes = (totalSeconds % 3600L) / 60L;
        long seconds = totalSeconds % 60L;
        if (hours > 0) {
            return String.format(java.util.Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds);
        }
        return String.format(java.util.Locale.ROOT, "%02d:%02d", minutes, seconds);
    }

    /** Raised strip + hairline under the search box (the EditBox itself is borderless). */
    private void renderSearchChrome(GuiGraphics guiGraphics) {
        int y = panelY + HEADER_H + 4;
        guiGraphics.fill(contentX, y, contentX + contentW, y + SEARCH_H - 2, EclipseUiTheme.PANEL_RAISED);
        EclipseUiTheme.drawHairline(guiGraphics, contentX, contentX + contentW, y + SEARCH_H - 2);
    }

    private void renderCards(GuiGraphics guiGraphics, int mouseX, int mouseY) {
        if (cards.isEmpty()) {
            Component empty = query.isBlank()
                    ? Component.translatable("gui.eclipse.devhandbook.empty.nodata")
                    : Component.translatable("gui.eclipse.devhandbook.empty.search", query);
            guiGraphics.drawString(this.font,
                    EclipseUiTheme.ellipsize(this.font, empty.getString(), contentW),
                    contentX, listY + 8, EclipseUiTheme.DIM);
            return;
        }
        int baseY = listY - (int) scrollY;
        for (Card card : cards) {
            int top = baseY + card.y();
            int bottom = top + card.height();
            if (bottom < listY || top > listY + listH) {
                continue;
            }
            renderCard(guiGraphics, card, top, mouseX, mouseY);
        }
    }

    private void renderCard(GuiGraphics guiGraphics, Card card, int top, int mouseX, int mouseY) {
        DevCommandDoc doc = card.doc();
        int right = contentX + contentW - 6;
        guiGraphics.fill(contentX, top, right, top + card.height(), EclipseUiTheme.PANEL_RAISED);
        guiGraphics.fill(contentX, top + card.height() - 1, right, top + card.height(),
                EclipseUiTheme.HAIRLINE);

        // Badges right-aligned before the action button: OP level, danger, legacy.
        int buttonX = right - BUTTON_W - 4;
        int badgeX = buttonX - 4;
        badgeX = renderBadgeRight(guiGraphics, badgeX, top + 4,
                Component.translatable("gui.eclipse.devhandbook.badge.perm", doc.permission()),
                doc.permission() >= 3 ? EclipseUiTheme.ACCENT : EclipseUiTheme.DIM);
        if (doc.danger() != Danger.SAFE) {
            badgeX = renderBadgeRight(guiGraphics, badgeX, top + 4,
                    Component.translatable(doc.danger().langKey()),
                    doc.danger() == Danger.DESTRUCTIVE ? EclipseUiTheme.DANGER : CAUTION_COLOR);
        }
        if (doc.legacy()) {
            badgeX = renderBadgeRight(guiGraphics, badgeX, top + 4,
                    Component.translatable("gui.eclipse.devhandbook.badge.legacy"), EclipseUiTheme.DIM);
        }

        // Syntax line (argument placeholders included), then the wrapped description.
        int syntaxMax = badgeX - contentX - 10;
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, doc.syntax(), Math.max(30, syntaxMax)),
                contentX + 6, top + 4, EclipseUiTheme.TEXT);
        int lineY = top + 15;
        for (FormattedCharSequence line : card.descLines()) {
            guiGraphics.drawString(this.font, line, contentX + 6, lineY, EclipseUiTheme.DIM);
            lineY += 10;
        }

        boolean run = doc.clickAction() == ClickAction.RUN;
        Component label = Component.translatable(run
                ? "gui.eclipse.devhandbook.button.run"
                : "gui.eclipse.devhandbook.button.insert");
        int buttonY = top + (card.height() - BUTTON_H) / 2;
        drawManualButton(guiGraphics, new HitRect("card:" + doc.id(), buttonX, buttonY, BUTTON_W, BUTTON_H,
                doc.danger() == Danger.DESTRUCTIVE, () -> onCardAction(doc)), label, mouseX, mouseY, true);
    }

    /** Draws one right-aligned badge; returns the new right edge for the next badge. */
    private int renderBadgeRight(GuiGraphics guiGraphics, int rightX, int y, Component text, int color) {
        int w = this.font.width(text) + 4;
        int x = rightX - w;
        guiGraphics.fill(x, y - 1, x + w, y + 9, EclipseUiTheme.withAlpha(color, 0.14F));
        guiGraphics.drawString(this.font, text, x + 2, y, color);
        return x - 4;
    }

    /** Config reference table (§2.12): file, purpose, layer, reload step. */
    private void renderConfigList(GuiGraphics guiGraphics) {
        List<ConfigRefEntry> refs = DevHandbookClient.configRefs();
        int y = listY - (int) scrollY;
        int fileW = Math.max(60, contentW * 28 / 100);
        int stepW = Math.max(56, contentW * 16 / 100);
        int layerW = Math.max(50, contentW * 18 / 100);
        int purposeX = contentX + fileW + 6;
        int purposeW = contentX + contentW - stepW - layerW - 12 - purposeX;

        guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.devhandbook.config.header"),
                contentX, y, EclipseUiTheme.ACCENT);
        y += 12;
        for (ConfigRefEntry ref : refs) {
            if (y > listY + listH) {
                break;
            }
            if (y + 10 >= listY) {
                guiGraphics.drawString(this.font,
                        EclipseUiTheme.ellipsize(this.font, ref.file(), fileW),
                        contentX, y, EclipseUiTheme.TEXT);
                guiGraphics.drawString(this.font,
                        EclipseUiTheme.ellipsize(this.font,
                                Component.translatable(ref.purposeKey()).getString(), Math.max(30, purposeW)),
                        purposeX, y, EclipseUiTheme.DIM);
                guiGraphics.drawString(this.font,
                        EclipseUiTheme.ellipsize(this.font,
                                Component.translatable(ref.layerKey()).getString(), layerW),
                        purposeX + purposeW + 6, y, EclipseUiTheme.DIM);
                Component step = ref.reloadStep() >= 1 && ref.reloadStep() <= 5
                        ? Component.translatable("gui.eclipse.devhandbook.config.step", ref.reloadStep())
                        : Component.translatable("gui.eclipse.devhandbook.config.manual");
                int stepColor = ref.reloadStep() >= 1 && ref.reloadStep() <= 5
                        ? EclipseUiTheme.GOOD : EclipseUiTheme.DIM;
                guiGraphics.drawString(this.font,
                        EclipseUiTheme.ellipsize(this.font, step.getString(), stepW),
                        purposeX + purposeW + layerW + 12, y, stepColor);
            }
            y += 12;
        }
    }

    private void renderScrollbar(GuiGraphics guiGraphics) {
        int total = currentContentHeight();
        if (total <= listH) {
            return;
        }
        int trackX = contentX + contentW - 2;
        guiGraphics.fill(trackX, listY, trackX + 2, listY + listH, EclipseUiTheme.HAIRLINE);
        int thumbH = Math.max(10, listH * listH / total);
        int thumbY = listY + (int) ((listH - thumbH) * scrollY / Math.max(1, total - listH));
        guiGraphics.fill(trackX, thumbY, trackX + 2, thumbY + thumbH, EclipseUiTheme.ACCENT_DEEP);
    }

    /** Bottom bar: status flash or match counter left (buttons are widgets on the right). */
    private void renderFooter(GuiGraphics guiGraphics) {
        EclipseUiTheme.drawHairline(guiGraphics, panelX + 1, panelX + panelW - 1, footerY);
        Component text;
        int color;
        if (statusFlash != null && System.currentTimeMillis() < statusFlashUntil) {
            text = statusFlash;
            color = EclipseUiTheme.GOOD;
        } else if (configView) {
            text = Component.translatable("gui.eclipse.devhandbook.footer.configs", configRowCount());
            color = EclipseUiTheme.DIM;
        } else {
            text = Component.translatable("gui.eclipse.devhandbook.footer.count",
                    cards.size(), DevHandbookClient.entries().size());
            color = EclipseUiTheme.DIM;
        }
        int maxW = Math.max(30, panelW - 2 * EclipseUiTheme.PAD - (configView ? 190 : 126));
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, text.getString(), maxW),
                panelX + EclipseUiTheme.PAD, footerY + 5, color);
    }

    /** Modal confirmation for DESTRUCTIVE entries — renders above every widget. */
    private void renderConfirmDialog(GuiGraphics guiGraphics, int mouseX, int mouseY) {
        DevCommandDoc doc = confirmDoc;
        if (doc == null) {
            return;
        }
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);
        int w = Math.min(280, panelW - 20);
        List<FormattedCharSequence> warning = this.font.split(
                Component.translatable("gui.eclipse.devhandbook.confirm.warning"), w - 16);
        int h = 34 + warning.size() * 10 + 24;
        int x = (this.width - w) / 2;
        int y = (this.height - h) / 2;
        EclipseUiTheme.drawPanel(guiGraphics, x, y, w, h);
        guiGraphics.fill(x, y, x + w, y + 1, EclipseUiTheme.DANGER); // danger top edge

        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font,
                        Component.translatable("gui.eclipse.devhandbook.confirm.title").getString(), w - 16),
                x + 8, y + 7, EclipseUiTheme.DANGER);
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, doc.syntax(), w - 16), x + 8, y + 20, EclipseUiTheme.TEXT);
        int lineY = y + 32;
        for (FormattedCharSequence line : warning) {
            guiGraphics.drawString(this.font, line, x + 8, lineY, EclipseUiTheme.DIM);
            lineY += 10;
        }

        int buttonY = y + h - 19;
        Component confirmLabel = Component.translatable(doc.clickAction() == ClickAction.RUN
                ? "gui.eclipse.devhandbook.button.run"
                : "gui.eclipse.devhandbook.button.insert");
        drawManualButton(guiGraphics, new HitRect("confirm:run", x + w - 2 * (BUTTON_W + 6), buttonY,
                BUTTON_W, BUTTON_H, true, this::confirmAccepted), confirmLabel, mouseX, mouseY, true);
        drawManualButton(guiGraphics, new HitRect("confirm:cancel", x + w - (BUTTON_W + 6), buttonY,
                BUTTON_W, BUTTON_H, false, this::confirmCancelled),
                Component.translatable("gui.eclipse.devhandbook.confirm.cancel"), mouseX, mouseY, true);
    }

    private void confirmAccepted() {
        DevCommandDoc doc = confirmDoc;
        confirmDoc = null;
        if (doc != null) {
            performAction(doc);
        }
    }

    private void confirmCancelled() {
        confirmDoc = null;
    }

    /** Draws a manual (non-widget) button and registers its hit rect for this frame. */
    private void drawManualButton(GuiGraphics guiGraphics, HitRect rect, Component label,
            int mouseX, int mouseY, boolean clickable) {
        boolean hovered = clickable && rect.contains(mouseX, mouseY)
                && (rect.key().startsWith("confirm:") || withinList(mouseY));
        guiGraphics.fill(rect.x(), rect.y(), rect.x() + rect.w(), rect.y() + rect.h(),
                EclipseUiTheme.PANEL_RAISED);
        int border = hovered ? (rect.danger() ? EclipseUiTheme.DANGER : EclipseUiTheme.ACCENT)
                : EclipseUiTheme.HAIRLINE;
        guiGraphics.fill(rect.x(), rect.y(), rect.x() + rect.w(), rect.y() + 1, border);
        guiGraphics.fill(rect.x(), rect.y() + rect.h() - 1, rect.x() + rect.w(), rect.y() + rect.h(), border);
        guiGraphics.fill(rect.x(), rect.y() + 1, rect.x() + 1, rect.y() + rect.h() - 1, border);
        guiGraphics.fill(rect.x() + rect.w() - 1, rect.y() + 1, rect.x() + rect.w(), rect.y() + rect.h() - 1,
                border);
        int textColor = rect.danger() ? EclipseUiTheme.DANGER
                : hovered ? EclipseUiTheme.ACCENT : EclipseUiTheme.TEXT;
        String text = EclipseUiTheme.ellipsize(this.font, label.getString(), rect.w() - 4);
        guiGraphics.drawString(this.font, text,
                rect.x() + (rect.w() - this.font.width(text)) / 2,
                rect.y() + (rect.h() - 8) / 2 + 1, textColor);
        if (clickable) {
            frameButtons.add(rect);
            if (hovered) {
                hoveredManualKey = rect.key();
            }
        }
    }

    private boolean withinList(double mouseY) {
        return mouseY >= listY && mouseY < listY + listH;
    }

    // ------------------------------------------------------------------ input

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (confirmDoc != null) {
            for (HitRect rect : frameButtons) {
                if (rect.key().startsWith("confirm:") && rect.contains(mouseX, mouseY)) {
                    UiSounds.click();
                    rect.action().run();
                    return true;
                }
            }
            return true; // modal: swallow everything else
        }
        if (super.mouseClicked(mouseX, mouseY, button)) {
            return true;
        }
        if (button == GLFW.GLFW_MOUSE_BUTTON_LEFT) {
            for (HitRect rect : frameButtons) {
                if (rect.contains(mouseX, mouseY) && withinList(mouseY)) {
                    UiSounds.click();
                    rect.action().run();
                    return true;
                }
            }
        }
        return false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double deltaY) {
        if (confirmDoc != null) {
            return true;
        }
        if (mouseX >= contentX && mouseX < contentX + contentW && withinList(mouseY)) {
            scrollY -= deltaY * SCROLL_STEP;
            clampScroll();
            return true;
        }
        return super.mouseScrolled(mouseX, mouseY, scrollX, deltaY);
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (confirmDoc != null) {
            if (keyCode == GLFW.GLFW_KEY_ESCAPE) {
                confirmCancelled();
                return true;
            }
            if (keyCode == GLFW.GLFW_KEY_ENTER || keyCode == GLFW.GLFW_KEY_KP_ENTER) {
                confirmAccepted();
                return true;
            }
            return true; // modal
        }
        if (keyCode == GLFW.GLFW_KEY_F5) {
            DevHandbookClient.requestRefresh();
            return true;
        }
        if (keyCode == GLFW.GLFW_KEY_SLASH && !searchBox.isFocused()) {
            setFocused(searchBox);
            swallowSlashChar = true; // the pairing charTyped('/') must not land in the box
            return true;
        }
        if (keyCode == GLFW.GLFW_KEY_PAGE_DOWN || keyCode == GLFW.GLFW_KEY_PAGE_UP) {
            scrollY += keyCode == GLFW.GLFW_KEY_PAGE_DOWN ? listH : -listH;
            clampScroll();
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers); // EditBox, widgets, ESC
    }

    @Override
    public boolean charTyped(char codePoint, int modifiers) {
        if (confirmDoc != null) {
            return true;
        }
        if (swallowSlashChar && codePoint == '/') {
            swallowSlashChar = false;
            return true;
        }
        swallowSlashChar = false;
        if (codePoint == '/' && !searchBox.isFocused()) {
            // Layout-independent variant of the '/' hotkey (e.g. Shift+7 on German keyboards).
            setFocused(searchBox);
            return true;
        }
        return super.charTyped(codePoint, modifiers);
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    /** ALWAYS hand the system cursor back, whatever screen comes next (kit rule R12). */
    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

    // ------------------------------------------------------------------ widgets

    /** Rail row: "All", one category, or the pinned Configs tab. */
    private class RailButton extends EclipseWidget {
        @Nullable
        private final DevCategory category;
        private final boolean configsTab;

        RailButton(@Nullable DevCategory category, boolean configsTab, int x, int y, int width, int height) {
            super(x, y, width, height, configsTab
                    ? Component.translatable("gui.eclipse.devhandbook.rail.configs")
                    : category == null
                            ? Component.translatable("gui.eclipse.devhandbook.rail.all")
                            : Component.translatable(category.langKey()));
            this.category = category;
            this.configsTab = configsTab;
        }

        private boolean isSelectedRow() {
            if (configsTab) {
                return configView;
            }
            return !configView && selectedCategory == category;
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            if (configsTab) {
                if (!configView) {
                    toggleConfigView();
                }
                return;
            }
            boolean leftConfig = configView;
            configView = false;
            selectedCategory = category;
            scrollY = 0.0D;
            reflow();
            if (leftConfig) {
                pendingRebuild = true; // bar buttons change; applied next frame
            }
        }

        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            if (!isSelectedRow()) {
                UiSounds.tab();
            }
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            boolean active = isSelectedRow();
            if (active) {
                guiGraphics.fill(panelX + 1, getY(), panelX + 3, getY() + this.height,
                        EclipseUiTheme.ACCENT);
            }
            int tint = active ? EclipseUiTheme.ACCENT
                    : isHoveredOrFocused() ? EclipseUiTheme.TEXT : EclipseUiTheme.DIM;
            guiGraphics.drawString(DevHandbookScreen.this.font,
                    EclipseUiTheme.ellipsize(DevHandbookScreen.this.font, getMessage().getString(),
                            this.width - 8),
                    getX() + 5, getY() + (this.height - 8) / 2 + 1, tint);
        }
    }

    /** Small bordered text button for the bottom bar (docs export, configs toggle, reload). */
    private class BarButton extends EclipseWidget {
        private final boolean active;
        private final Runnable action;

        BarButton(int x, int y, int width, int height, Component label, boolean active, Runnable action) {
            super(x, y, width, height, label);
            this.active = active;
            this.action = action;
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            action.run();
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + this.height,
                    EclipseUiTheme.PANEL_RAISED);
            int border = active ? EclipseUiTheme.ACCENT_DEEP : EclipseUiTheme.HAIRLINE;
            guiGraphics.fill(getX(), getY(), getX() + this.width, getY() + 1, border);
            guiGraphics.fill(getX(), getY() + this.height - 1, getX() + this.width, getY() + this.height,
                    border);
            guiGraphics.fill(getX(), getY() + 1, getX() + 1, getY() + this.height - 1, border);
            guiGraphics.fill(getX() + this.width - 1, getY() + 1, getX() + this.width,
                    getY() + this.height - 1, border);
            int tint = active ? EclipseUiTheme.ACCENT
                    : isHoveredOrFocused() ? EclipseUiTheme.TEXT : EclipseUiTheme.DIM;
            String text = EclipseUiTheme.ellipsize(DevHandbookScreen.this.font, getMessage().getString(),
                    this.width - 4);
            guiGraphics.drawString(DevHandbookScreen.this.font, text,
                    getX() + (this.width - DevHandbookScreen.this.font.width(text)) / 2,
                    getY() + (this.height - 8) / 2 + 1, tint);
        }
    }
}
