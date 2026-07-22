package dev.projecteclipse.eclipse.devtools.client;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import javax.annotation.Nullable;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.network.C2SConfigEditPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.EditBox;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The W14 goal/unlock editor ({@code docs/ideas/05_systems.md} §3): a client screen opened by
 * {@code /eclipse goals edit} (via {@code S2COpenGoalEditorPayload} carrying the server's
 * current {@code days.json}). Left: a day-selector grid (7 per column). Right: the selected
 * day's goal lines (up to {@value #MAX_GOALS} vanilla {@link EditBox}es — the GoalTracker
 * bitmask cap), the unlock keys as one comma-separated field, and the legacy border-size
 * field. Save re-serializes ALL days and sends {@code C2SConfigEditPayload("days.json", …)} —
 * the server re-checks permission level 3 and re-validates before writing (see
 * {@code devtools.ConfigEditor}). ESC / Cancel discards.
 *
 * <p>UI conventions follow the W9 handbook suite: {@link EclipseWidget} day buttons (hover
 * glow + {@code ui.hover}), {@link UiSounds#tab()} on day switch, one
 * {@link CursorManager#endFrame()} per frame and a {@link CursorManager#reset()} in
 * {@link #removed()}. Buttons and text fields are VANILLA widgets, so focus order and
 * narration stay intact.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class GoalEditorScreen extends Screen {
    /** {@code GoalTracker} tracks completion in one byte per day — hard UI cap. */
    private static final int MAX_GOALS = 8;
    private static final int GOAL_MAX_CHARS = 80;
    private static final int UNLOCKS_MAX_CHARS = 200;
    private static final int TEXT_COLOR = 0xE8E0F5;
    private static final int ACCENT_COLOR = 0xB98CFF;
    private static final int DIM_COLOR = 0x9A8FB8;
    private static final int PANEL_COLOR = 0xF0140C24;

    /** Mutable editing model of one {@code days.json} entry. */
    private static final class DayEntry {
        int day;
        final List<String> goals = new ArrayList<>();
        String unlocks = "";
        String borderSize = "1000.0";
    }

    private final List<DayEntry> days = new ArrayList<>();
    private int selected;
    @Nullable
    private Component error;

    // Rebuilt in init().
    private final List<EditBox> goalBoxes = new ArrayList<>();
    @Nullable
    private EditBox unlocksBox;
    @Nullable
    private EditBox borderBox;
    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;
    private int rightX;
    private int rightW;

    private GoalEditorScreen(String daysJson) {
        super(Component.translatable("gui.eclipse.goaleditor.title"));
        parse(daysJson);
    }

    /** Payload entry point (mirrors {@code ArtifactScreenOpener}: never interrupts another screen). */
    public static void open(String daysJson) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player != null && minecraft.screen == null) {
            minecraft.setScreen(new GoalEditorScreen(daysJson));
        }
    }

    /** Fills the model from the server's JSON; a parse failure yields one empty day + error line. */
    private void parse(String daysJson) {
        try {
            for (JsonElement element : JsonParser.parseString(daysJson).getAsJsonArray()) {
                JsonObject obj = element.getAsJsonObject();
                DayEntry entry = new DayEntry();
                entry.day = obj.get("day").getAsInt();
                if (obj.has("goals")) {
                    for (JsonElement goal : obj.getAsJsonArray("goals")) {
                        if (entry.goals.size() < MAX_GOALS) {
                            entry.goals.add(goal.getAsString());
                        }
                    }
                }
                if (obj.has("unlocks")) {
                    List<String> keys = new ArrayList<>();
                    obj.getAsJsonArray("unlocks").forEach(key -> keys.add(key.getAsString()));
                    entry.unlocks = String.join(", ", keys);
                }
                if (obj.has("borderSize")) {
                    entry.borderSize = String.format(Locale.ROOT, "%.1f", obj.get("borderSize").getAsDouble());
                }
                days.add(entry);
            }
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.error("GoalEditorScreen: failed to parse days.json payload", e);
            days.clear();
        }
        if (days.isEmpty()) {
            DayEntry fallback = new DayEntry();
            fallback.day = 1;
            days.add(fallback);
            error = Component.literal("Received days.json did not parse — editing a blank day 1.");
        }
        selected = Mth.clamp(selected, 0, days.size() - 1);
    }

    // --- layout ---

    @Override
    protected void init() {
        goalBoxes.clear();
        panelW = Mth.clamp(this.width - 24, 320, 460);
        panelH = Mth.clamp(this.height - 24, 216, 300);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        // Left: day grid, 7 per column.
        int columns = Math.max(1, (days.size() + 6) / 7);
        int dayW = 22;
        int dayH = 16;
        int gridX = panelX + 10;
        int gridY = panelY + 24;
        for (int i = 0; i < days.size(); i++) {
            int column = i / 7;
            int row = i % 7;
            addRenderableWidget(new DayButton(i, gridX + column * (dayW + 3), gridY + row * (dayH + 3), dayW, dayH));
        }

        rightX = gridX + columns * (dayW + 3) + 10;
        rightW = panelX + panelW - 10 - rightX;
        DayEntry entry = days.get(selected);

        // Goal lines + add/remove.
        int y = panelY + 32;
        int boxH = 14;
        for (int i = 0; i < entry.goals.size(); i++) {
            EditBox box = new EditBox(this.font, rightX, y, rightW, boxH,
                    Component.translatable("gui.eclipse.goaleditor.goal", i + 1));
            box.setMaxLength(GOAL_MAX_CHARS);
            box.setValue(entry.goals.get(i));
            addRenderableWidget(box);
            goalBoxes.add(box);
            y += boxH + 3;
        }
        int controlsY = y + 1;
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.add"),
                        button -> addGoal())
                .bounds(rightX, controlsY, 52, 14).build())
                .active = entry.goals.size() < MAX_GOALS;
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.remove"),
                        button -> removeGoal())
                .bounds(rightX + 56, controlsY, 52, 14).build())
                .active = !entry.goals.isEmpty();

        // Unlock keys + legacy border, labels drawn left of the boxes in render().
        int fieldX = rightX + 52;
        int fieldW = rightW - 52;
        int unlocksY = controlsY + 20;
        unlocksBox = new EditBox(this.font, fieldX, unlocksY, fieldW, boxH,
                Component.translatable("gui.eclipse.goaleditor.unlocks"));
        unlocksBox.setMaxLength(UNLOCKS_MAX_CHARS);
        unlocksBox.setValue(entry.unlocks);
        addRenderableWidget(unlocksBox);

        int borderY = unlocksY + boxH + 4;
        borderBox = new EditBox(this.font, fieldX, borderY, 70, boxH,
                Component.translatable("gui.eclipse.goaleditor.border"));
        borderBox.setMaxLength(16);
        borderBox.setValue(entry.borderSize);
        addRenderableWidget(borderBox);

        // Save / Cancel along the panel's bottom edge.
        int actionY = panelY + panelH - 24;
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.save"),
                        button -> save())
                .bounds(panelX + panelW - 210, actionY, 120, 18).build());
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.cancel"),
                        button -> onClose())
                .bounds(panelX + panelW - 84, actionY, 74, 18).build());
    }

    // --- model <-> widgets ---

    /** Copies the on-screen field values back into the selected day's model entry. */
    private void commitFields() {
        DayEntry entry = days.get(selected);
        for (int i = 0; i < goalBoxes.size() && i < entry.goals.size(); i++) {
            entry.goals.set(i, goalBoxes.get(i).getValue());
        }
        if (unlocksBox != null) {
            entry.unlocks = unlocksBox.getValue();
        }
        if (borderBox != null) {
            entry.borderSize = borderBox.getValue();
        }
    }

    private void selectDay(int index) {
        if (index == selected || index < 0 || index >= days.size()) {
            return;
        }
        commitFields();
        selected = index;
        UiSounds.tab();
        rebuildWidgets();
    }

    private void addGoal() {
        commitFields();
        DayEntry entry = days.get(selected);
        if (entry.goals.size() < MAX_GOALS) {
            entry.goals.add("");
            rebuildWidgets();
        }
    }

    private void removeGoal() {
        commitFields();
        DayEntry entry = days.get(selected);
        if (!entry.goals.isEmpty()) {
            entry.goals.remove(entry.goals.size() - 1);
            rebuildWidgets();
        }
    }

    /** Serializes ALL days back to the days.json shape and sends the edit to the server. */
    private void save() {
        commitFields();
        JsonArray array = new JsonArray(days.size());
        for (DayEntry entry : days) {
            JsonObject obj = new JsonObject();
            obj.addProperty("day", entry.day);
            JsonArray goals = new JsonArray();
            for (String goal : entry.goals) {
                if (!goal.isBlank() && goals.size() < MAX_GOALS) {
                    goals.add(goal.trim());
                }
            }
            obj.add("goals", goals);
            JsonArray unlocks = new JsonArray();
            for (String key : entry.unlocks.split(",")) {
                if (!key.isBlank()) {
                    unlocks.add(key.trim());
                }
            }
            obj.add("unlocks", unlocks);
            double borderSize;
            try {
                borderSize = Double.parseDouble(entry.borderSize.trim());
            } catch (NumberFormatException e) {
                borderSize = 1000.0D;
            }
            obj.addProperty("borderSize", borderSize);
            array.add(obj);
        }
        String json = array.toString();
        if (json.getBytes(StandardCharsets.UTF_8).length > C2SConfigEditPayload.MAX_JSON_BYTES) {
            error = Component.translatable("gui.eclipse.goaleditor.too_large");
            return;
        }
        PacketDistributor.sendToServer(new C2SConfigEditPayload("days.json", json));
        onClose();
    }

    // --- rendering ---

    /** Dark transparent gradient (no blur dirt) + the editor panel under the widgets. */
    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        renderTransparentBackground(guiGraphics);
        guiGraphics.fill(panelX, panelY, panelX + panelW, panelY + panelH, PANEL_COLOR);
        guiGraphics.fill(panelX, panelY, panelX + panelW, panelY + 1, ACCENT_COLOR | 0xFF000000);
        guiGraphics.fill(panelX, panelY + panelH - 1, panelX + panelW, panelY + panelH, ACCENT_COLOR | 0xFF000000);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        guiGraphics.drawString(this.font, this.title, panelX + 10, panelY + 8, ACCENT_COLOR);
        guiGraphics.drawString(this.font,
                Component.translatable("gui.eclipse.goaleditor.day", days.get(selected).day),
                rightX, panelY + 10, TEXT_COLOR);
        guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.goaleditor.goals"),
                rightX, panelY + 22, DIM_COLOR);
        if (unlocksBox != null) {
            guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.goaleditor.unlocks"),
                    rightX, unlocksBox.getY() + 3, DIM_COLOR);
        }
        if (borderBox != null) {
            guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.goaleditor.border"),
                    rightX, borderBox.getY() + 3, DIM_COLOR);
        }
        if (error != null) {
            guiGraphics.drawString(this.font, error, panelX + 10, panelY + panelH - 38, 0xFF6B6B);
        }
        CursorManager.endFrame();
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    /** ALWAYS hand the system cursor back, whatever screen comes next (risk R12). */
    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

    /** Day selector tile: W9 hover suite via {@link EclipseWidget}, tab sound on switch. */
    private final class DayButton extends EclipseWidget {
        private final int index;

        DayButton(int index, int x, int y, int width, int height) {
            super(x, y, width, height,
                    Component.translatable("gui.eclipse.goaleditor.day", days.get(index).day));
            this.index = index;
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            selectDay(index);
        }

        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            // selectDay plays ui.tab; the vanilla click would double up.
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            boolean active = index == selected;
            guiGraphics.fill(getX(), getY(), getX() + width, getY() + height, active ? 0xFF2E1F4A : 0xE01E1432);
            if (active) {
                renderGlowBorder(guiGraphics, 0.6F);
            }
            guiGraphics.drawCenteredString(GoalEditorScreen.this.font, String.valueOf(days.get(index).day),
                    getX() + width / 2, getY() + (height - 8) / 2, active ? ACCENT_COLOR : TEXT_COLOR);
        }
    }
}
