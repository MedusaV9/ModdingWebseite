package dev.projecteclipse.eclipse.devtools.client;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseWidget;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.network.C2SConfigEditPayload;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.TriggerType;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.CycleButton;
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
 * current config envelope). Left: a day-selector grid. Right: one selected goal with EN/DE
 * text plus a real trigger type, target id and count. Save writes both {@code goals.json}
 * and the localized legacy fallback strings in {@code days.json}; the server re-validates
 * both before writing. ESC / Cancel discards.
 *
 * <p>Since P3-W4 each goal, title and subtitle carries English and German boxes; serialization
 * uses {@link Localized#toJsonElement()} ({@code {"en","de"}} objects, legacy string when DE
 * matches EN).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class GoalEditorScreen extends Screen {
    /** GoalConfig permits 24 mains+sides per day; only the legacy days.json mirror is capped at 8 mains. */
    private static final int MAX_GOALS = 24;
    private static final int MAX_LEGACY_GOALS = 8;
    private static final int GOAL_MAX_CHARS = 80;
    private static final int ID_MAX_CHARS = 96;
    private static final int UNLOCKS_MAX_CHARS = 200;
    private static final int TEXT_COLOR = 0xE8E0F5;
    private static final int ACCENT_COLOR = 0xB98CFF;
    private static final int DIM_COLOR = 0x9A8FB8;
    private static final int PANEL_COLOR = 0xF0140C24;

    /** Mutable trigger-typed goal model; fields not shown in v2 are preserved on round-trip. */
    private static final class GoalEntry {
        String id;
        GoalSpec.Kind kind;
        GoalSpec.Scope scope;
        GoalSpec.Trigger trigger;
        GoalSpec.Reward reward;
        Localized text;
        int weight;
        int minDay;
        int maxDay;

        static GoalEntry fromJson(JsonObject object) {
            GoalSpec spec = GoalSpec.fromJson(object, GoalSpec.Kind.MAIN);
            GoalEntry entry = new GoalEntry();
            entry.id = spec.id();
            entry.kind = spec.goalKind();
            entry.scope = spec.scope();
            entry.trigger = spec.trigger();
            entry.reward = spec.reward();
            entry.text = spec.text();
            entry.weight = spec.weight();
            entry.minDay = spec.minDay();
            entry.maxDay = spec.maxDay();
            return entry;
        }

        static GoalEntry manual(int day, int index, Localized text) {
            GoalEntry entry = new GoalEntry();
            entry.id = "goal_d" + day + "_" + (index + 1);
            entry.kind = GoalSpec.Kind.MAIN;
            entry.scope = GoalSpec.Scope.EACH_PLAYER;
            entry.trigger = GoalSpec.Trigger.manual();
            entry.reward = GoalSpec.Reward.NONE;
            entry.text = text;
            entry.weight = 1;
            return entry;
        }

        JsonObject toJson() {
            return new GoalSpec(id, kind, scope, trigger, reward, text, weight, minDay, maxDay).toJson();
        }
    }

    /** Mutable editing model of one day shared by days.json and goals.json. */
    private static final class DayEntry {
        int day;
        final List<GoalEntry> goals = new ArrayList<>();
        Localized title = Localized.of("");
        Localized subtitle = Localized.of("");
        String unlocks = "";
    }

    /** Widgets for the selected goal. */
    private static final class GoalFields {
        EditBox en;
        EditBox de;
        EditBox id;
        EditBox target;
        EditBox count;
        CycleButton<String> triggerType;
    }

    private final List<DayEntry> days = new ArrayList<>();
    private int selected;
    private int selectedGoal;
    @Nullable
    private Component error;

    @Nullable
    private GoalFields goalFields;
    @Nullable
    private EditBox titleEnBox;
    @Nullable
    private EditBox titleDeBox;
    @Nullable
    private EditBox subtitleEnBox;
    @Nullable
    private EditBox subtitleDeBox;
    @Nullable
    private EditBox unlocksBox;
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

    /** Fills the model from the v2 envelope; legacy raw days arrays remain accepted. */
    private void parse(String daysJson) {
        try {
            JsonElement parsed = JsonParser.parseString(daysJson);
            JsonArray dayConfig;
            JsonObject goalsByDay = new JsonObject();
            if (parsed.isJsonArray()) {
                dayConfig = parsed.getAsJsonArray();
            } else {
                JsonObject envelope = parsed.getAsJsonObject();
                dayConfig = envelope.getAsJsonArray("daysConfig");
                if (envelope.has("goalsConfig")) {
                    for (JsonElement dayElement : envelope.getAsJsonObject("goalsConfig").getAsJsonArray("days")) {
                        JsonObject goalDay = dayElement.getAsJsonObject();
                        goalsByDay.add(Integer.toString(goalDay.get("day").getAsInt()),
                                goalDay.getAsJsonArray("goals"));
                    }
                }
            }
            for (JsonElement element : dayConfig) {
                JsonObject obj = element.getAsJsonObject();
                DayEntry entry = new DayEntry();
                entry.day = obj.get("day").getAsInt();
                JsonArray realGoals = goalsByDay.has(Integer.toString(entry.day))
                        ? goalsByDay.getAsJsonArray(Integer.toString(entry.day)) : null;
                if (realGoals != null) {
                    for (JsonElement goal : realGoals) {
                        if (entry.goals.size() < MAX_GOALS) {
                            entry.goals.add(GoalEntry.fromJson(goal.getAsJsonObject()));
                        }
                    }
                } else if (obj.has("goals")) {
                    for (JsonElement goal : obj.getAsJsonArray("goals")) {
                        if (entry.goals.size() < MAX_GOALS) {
                            entry.goals.add(GoalEntry.manual(entry.day, entry.goals.size(),
                                    Localized.parse(goal)));
                        }
                    }
                }
                if (obj.has("title")) {
                    entry.title = Localized.parse(obj.get("title"));
                }
                if (obj.has("subtitle")) {
                    entry.subtitle = Localized.parse(obj.get("subtitle"));
                }
                if (obj.has("unlocks")) {
                    List<String> keys = new ArrayList<>();
                    obj.getAsJsonArray("unlocks").forEach(key -> keys.add(key.getAsString()));
                    entry.unlocks = String.join(", ", keys);
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
            error = Component.translatable("gui.eclipse.goaleditor.parse_failed");
        }
        selected = Mth.clamp(selected, 0, days.size() - 1);
        selectedGoal = 0;
    }

    @Override
    protected void init() {
        clearWidgets();
        goalFields = null;
        titleEnBox = titleDeBox = subtitleEnBox = subtitleDeBox = null;
        unlocksBox = null;

        panelW = Mth.clamp(this.width - 24, 420, 700);
        panelH = Mth.clamp(this.height - 24, 260, 360);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

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

        int y = panelY + 28;
        int boxH = 14;
        int halfW = (rightW - 4) / 2;

        titleEnBox = addLangBox(rightX, y, halfW, boxH,
                "gui.eclipse.goaleditor.title_en", entry.title.en());
        titleDeBox = addLangBox(rightX + halfW + 4, y, halfW, boxH, "gui.eclipse.goaleditor.title_de",
                entry.title.de() != null ? entry.title.de() : entry.title.en());
        y += boxH + 3;

        subtitleEnBox = addLangBox(rightX, y, halfW, boxH, "gui.eclipse.goaleditor.subtitle_en", entry.subtitle.en());
        subtitleDeBox = addLangBox(rightX + halfW + 4, y, halfW, boxH, "gui.eclipse.goaleditor.subtitle_de",
                entry.subtitle.de() != null ? entry.subtitle.de() : entry.subtitle.en());
        y += boxH + 8;

        selectedGoal = entry.goals.isEmpty() ? 0 : Mth.clamp(selectedGoal, 0, entry.goals.size() - 1);
        int navigationY = y;
        addRenderableWidget(Button.builder(Component.literal("◀"), button -> selectGoal(-1))
                .bounds(rightX, navigationY, 24, boxH).build()).active = selectedGoal > 0;
        addRenderableWidget(Button.builder(Component.literal("▶"), button -> selectGoal(1))
                .bounds(rightX + 28, navigationY, 24, boxH).build())
                .active = selectedGoal + 1 < entry.goals.size();
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.add"),
                        button -> addGoal())
                .bounds(rightX + rightW - 108, navigationY, 52, boxH).build())
                .active = entry.goals.size() < MAX_GOALS;
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.remove"),
                        button -> removeGoal())
                .bounds(rightX + rightW - 52, navigationY, 52, boxH).build())
                .active = !entry.goals.isEmpty();
        y += boxH + 4;

        if (!entry.goals.isEmpty()) {
            GoalEntry goal = entry.goals.get(selectedGoal);
            GoalFields fields = new GoalFields();
            fields.en = addLangBox(rightX, y, halfW, boxH,
                    "gui.eclipse.goaleditor.goal_en", goal.text.en());
            fields.de = addLangBox(rightX + halfW + 4, y, halfW, boxH,
                    "gui.eclipse.goaleditor.goal_de",
                    goal.text.de() != null ? goal.text.de() : goal.text.en());
            y += boxH + 3;

            fields.id = addTextBox(rightX, y, rightW, boxH,
                    "gui.eclipse.goaleditor.goal_id", goal.id, ID_MAX_CHARS);
            y += boxH + 3;

            fields.triggerType = CycleButton.<String>builder(Component::literal)
                    .withValues(TriggerType.ids())
                    .withInitialValue(goal.trigger.type().id())
                    .create(rightX, y, halfW, boxH,
                            Component.translatable("gui.eclipse.goaleditor.trigger_type"));
            addRenderableWidget(fields.triggerType);
            fields.target = addTextBox(rightX + halfW + 4, y, halfW, boxH,
                    "gui.eclipse.goaleditor.trigger_target", editableTarget(goal.trigger), ID_MAX_CHARS);
            y += boxH + 3;

            fields.count = addTextBox(rightX, y, 90, boxH,
                    "gui.eclipse.goaleditor.trigger_count",
                    Long.toString(goal.trigger.count()), 12);
            goalFields = fields;
            y += boxH + 6;
        }

        int fieldX = rightX + 52;
        int fieldW = Math.max(40, rightW - 52);
        unlocksBox = new EditBox(this.font, fieldX, y, fieldW, boxH,
                Component.translatable("gui.eclipse.goaleditor.unlocks"));
        unlocksBox.setMaxLength(UNLOCKS_MAX_CHARS);
        unlocksBox.setValue(entry.unlocks);
        addRenderableWidget(unlocksBox);

        int actionY = panelY + panelH - 24;
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.save"),
                        button -> save())
                .bounds(panelX + panelW - 210, actionY, 120, 18).build());
        addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.goaleditor.cancel"),
                        button -> onClose())
                .bounds(panelX + panelW - 84, actionY, 74, 18).build());
    }

    private EditBox addLangBox(int x, int y, int width, int height, String labelKey, String value) {
        EditBox box = new EditBox(this.font, x, y, width, height, Component.translatable(labelKey));
        box.setMaxLength(GOAL_MAX_CHARS);
        box.setValue(value);
        box.setHint(Component.translatable(labelKey));
        addRenderableWidget(box);
        return box;
    }

    private EditBox addTextBox(int x, int y, int width, int height, String labelKey,
            String value, int maxLength) {
        EditBox box = new EditBox(this.font, x, y, width, height, Component.translatable(labelKey));
        box.setMaxLength(maxLength);
        box.setValue(value);
        box.setHint(Component.translatable(labelKey));
        addRenderableWidget(box);
        return box;
    }

    private void commitFields() {
        DayEntry entry = days.get(selected);
        if (goalFields != null && selectedGoal >= 0 && selectedGoal < entry.goals.size()) {
            GoalEntry goal = entry.goals.get(selectedGoal);
            goal.text = new Localized(goalFields.en.getValue(), emptyToNull(goalFields.de.getValue()));
            String id = goalFields.id.getValue().trim().replaceAll("\\s+", "_");
            goal.id = id.isEmpty() ? "goal_d" + entry.day + "_" + (selectedGoal + 1) : id;
            TriggerType type = TriggerType.byId(goalFields.triggerType.getValue());
            long count = parseCount(goalFields.count.getValue(), goal.trigger.count());
            String parameter = goalFields.target.getValue().trim();
            GoalSpec.Trigger old = goal.trigger;
            String target = switch (type) {
                case STAT_THRESHOLD, MANUAL -> old.target();
                default -> parameter;
            };
            String statId = type == TriggerType.STAT_THRESHOLD ? parameter : old.statId();
            String beatId = type == TriggerType.MANUAL ? parameter : old.beatId();
            int radius = type == TriggerType.VISIT_LOCATION ? Math.max(1, old.radius()) : old.radius();
            goal.trigger = new GoalSpec.Trigger(type, target, count, old.naturalOnly(),
                    old.x(), old.z(), radius, old.y(), statId, beatId, old.purpose());
        }
        if (titleEnBox != null && titleDeBox != null) {
            entry.title = new Localized(titleEnBox.getValue(), emptyToNull(titleDeBox.getValue()));
        }
        if (subtitleEnBox != null && subtitleDeBox != null) {
            entry.subtitle = new Localized(subtitleEnBox.getValue(), emptyToNull(subtitleDeBox.getValue()));
        }
        if (unlocksBox != null) {
            entry.unlocks = unlocksBox.getValue();
        }
    }

    private static String editableTarget(GoalSpec.Trigger trigger) {
        return switch (trigger.type()) {
            case STAT_THRESHOLD -> trigger.statId();
            case MANUAL -> trigger.beatId();
            default -> trigger.target();
        };
    }

    private static long parseCount(String raw, long fallback) {
        try {
            return Math.max(1L, Long.parseLong(raw.trim()));
        } catch (NumberFormatException e) {
            return Math.max(1L, fallback);
        }
    }

    @Nullable
    private static String emptyToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    @Override
    protected void rebuildWidgets() {
        init();
    }

    private void selectDay(int index) {
        if (index == selected || index < 0 || index >= days.size()) {
            return;
        }
        commitFields();
        selected = index;
        selectedGoal = 0;
        UiSounds.tab();
        rebuildWidgets();
    }

    private void selectGoal(int delta) {
        DayEntry entry = days.get(selected);
        if (entry.goals.isEmpty()) {
            return;
        }
        int next = Mth.clamp(selectedGoal + delta, 0, entry.goals.size() - 1);
        if (next != selectedGoal) {
            commitFields();
            selectedGoal = next;
            UiSounds.tab();
            rebuildWidgets();
        }
    }

    private void addGoal() {
        commitFields();
        DayEntry entry = days.get(selected);
        if (entry.goals.size() < MAX_GOALS) {
            entry.goals.add(GoalEntry.manual(entry.day, entry.goals.size(), Localized.of("")));
            selectedGoal = entry.goals.size() - 1;
            rebuildWidgets();
        }
    }

    private void removeGoal() {
        commitFields();
        DayEntry entry = days.get(selected);
        if (!entry.goals.isEmpty()) {
            entry.goals.remove(Mth.clamp(selectedGoal, 0, entry.goals.size() - 1));
            selectedGoal = Math.max(0, Math.min(selectedGoal, entry.goals.size() - 1));
            rebuildWidgets();
        }
    }

    private void save() {
        commitFields();
        JsonArray dayArray = new JsonArray(days.size());
        JsonArray goalDays = new JsonArray(days.size());
        for (DayEntry entry : days) {
            JsonObject obj = new JsonObject();
            obj.addProperty("day", entry.day);
            JsonArray legacyGoals = new JsonArray();
            JsonArray realGoals = new JsonArray();
            for (GoalEntry goal : entry.goals) {
                if (!goal.text.isBlank()) {
                    realGoals.add(goal.toJson());
                    if (goal.kind == GoalSpec.Kind.MAIN && legacyGoals.size() < MAX_LEGACY_GOALS) {
                        legacyGoals.add(goal.text.toJsonElement());
                    }
                }
            }
            obj.add("goals", legacyGoals);
            if (!entry.title.isBlank()) {
                obj.add("title", entry.title.toJsonElement());
            }
            if (!entry.subtitle.isBlank()) {
                obj.add("subtitle", entry.subtitle.toJsonElement());
            }
            JsonArray unlocks = new JsonArray();
            for (String key : entry.unlocks.split(",")) {
                if (!key.isBlank()) {
                    unlocks.add(key.trim());
                }
            }
            obj.add("unlocks", unlocks);
            dayArray.add(obj);

            JsonObject goalDay = new JsonObject();
            goalDay.addProperty("day", entry.day);
            goalDay.add("goals", realGoals);
            goalDays.add(goalDay);
        }
        JsonObject goalsRoot = new JsonObject();
        goalsRoot.add("days", goalDays);
        String daysJson = dayArray.toString();
        String goalsJson = goalsRoot.toString();
        if (daysJson.getBytes(StandardCharsets.UTF_8).length > C2SConfigEditPayload.MAX_JSON_BYTES
                || goalsJson.getBytes(StandardCharsets.UTF_8).length
                        > C2SConfigEditPayload.MAX_JSON_BYTES) {
            error = Component.translatable("gui.eclipse.goaleditor.too_large");
            return;
        }
        // Same connection preserves packet order: real trigger config first, localized fallback second.
        PacketDistributor.sendToServer(new C2SConfigEditPayload("goals.json", goalsJson));
        PacketDistributor.sendToServer(new C2SConfigEditPayload("days.json", daysJson));
        onClose();
    }

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
        if (titleEnBox != null) {
            guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.goaleditor.title_row"),
                    rightX, titleEnBox.getY() - 9, DIM_COLOR);
        }
        if (unlocksBox != null) {
            guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.goaleditor.unlocks"),
                    rightX, unlocksBox.getY() + 3, DIM_COLOR);
        }
        DayEntry entry = days.get(selected);
        if (!entry.goals.isEmpty() && goalFields != null) {
            guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.goaleditor.goal_index",
                    selectedGoal + 1, entry.goals.size(), entry.goals.get(selectedGoal).kind.id()),
                    rightX + 58, goalFields.en.getY() - 18, DIM_COLOR);
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

    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

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
