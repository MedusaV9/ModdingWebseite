package de.sonic0810.goobymod.client;

import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyTrick;
import de.sonic0810.goobymod.network.TrickMenuPayload;
import de.sonic0810.goobymod.network.TrickSelectPayload;
import de.sonic0810.goobymod.registry.ModSounds;
import net.minecraft.ChatFormatting;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractButton;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.client.sounds.SoundManager;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.util.Mth;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Nativer Trick-Selection-Screen (ersetzt das klickbare Chat-Menue beim
 * Sneak-Luftpfiff). Rein datengetrieben aus dem gebundeten S2C-Payload —
 * der Server bleibt die einzige Autoritaet, die Auswahl geht als schlanker
 * C2S-Payload zurueck und wird dort komplett neu validiert.
 *
 * <p>Responsives Karten-Grid (1–3 Spalten je nach Fensterbreite), gesperrte
 * Kunststuecke bleiben per Tab/Pfeiltasten fokussierbar und werden dem
 * Narrator als gesperrt vorgelesen. Done bestaetigt, Cancel/Esc verwirft;
 * "Aktiv" zeigt ausschliesslich den serverseitig bestaetigten Stand, die
 * unbestaetigte Auswahl heisst "Ausgewaehlt". Statuszeilen werden strikt auf
 * Kartenbreite geklammert (Scrolltext statt Ueberlauf). Keine eigenen
 * Texturen — Karten sind reine Fill-/Border-Flaechen.</p>
 */
public final class GoobyTrickScreen extends Screen {
    private static final int CARD_WIDTH = 116;
    private static final int CARD_HEIGHT = 44;
    private static final int CARD_MIN_HEIGHT = 26;
    private static final int CARD_GAP = 8;
    private static final int HEADER_HEIGHT = 42;
    private static final int FOOTER_HEIGHT = 36;
    private static final int BUTTON_WIDTH = 98;

    private final TrickMenuPayload menu;
    private GoobyTrick pending;
    private TrickCard initialFocusCard;

    public GoobyTrickScreen(TrickMenuPayload menu) {
        super(Component.translatable("screen.goobymod.trick_select.title", menu.goobyName()));
        this.menu = menu;
        this.pending = menu.selected();
    }

    @Override
    protected void init() {
        int entryCount = this.menu.entries().size();
        int columns = Mth.clamp((this.width - 2 * CARD_GAP) / (CARD_WIDTH + CARD_GAP), 1, 3);
        int rows = Mth.positiveCeilDiv(entryCount, columns);
        int availableHeight = this.height - HEADER_HEIGHT - FOOTER_HEIGHT;
        int cardHeight = Mth.clamp((availableHeight - (rows - 1) * CARD_GAP) / Math.max(1, rows),
                CARD_MIN_HEIGHT, CARD_HEIGHT);
        int gridWidth = columns * CARD_WIDTH + (columns - 1) * CARD_GAP;
        int gridHeight = rows * cardHeight + (rows - 1) * CARD_GAP;
        int left = (this.width - gridWidth) / 2;
        int top = HEADER_HEIGHT + Math.max(0, (availableHeight - gridHeight) / 2);

        for (int index = 0; index < entryCount; index++) {
            TrickMenuPayload.TrickEntry entry = this.menu.entries().get(index);
            int x = left + (index % columns) * (CARD_WIDTH + CARD_GAP);
            int y = top + (index / columns) * (cardHeight + CARD_GAP);
            TrickCard card = addRenderableWidget(new TrickCard(x, y, CARD_WIDTH, cardHeight, entry));
            if (entry.trick() == this.pending) {
                this.initialFocusCard = card;
            }
        }

        int buttonY = this.height - FOOTER_HEIGHT + (FOOTER_HEIGHT - 20) / 2;
        int buttonsLeft = this.width / 2 - (2 * BUTTON_WIDTH + CARD_GAP) / 2;
        addRenderableWidget(Button.builder(CommonComponents.GUI_CANCEL, button -> onClose())
                .bounds(buttonsLeft, buttonY, BUTTON_WIDTH, 20)
                .build());
        addRenderableWidget(Button.builder(CommonComponents.GUI_DONE, button -> confirmSelection())
                .bounds(buttonsLeft + BUTTON_WIDTH + CARD_GAP, buttonY, BUTTON_WIDTH, 20)
                .build());
    }

    @Override
    public void render(GuiGraphics graphics, int mouseX, int mouseY, float partialTick) {
        super.render(graphics, mouseX, mouseY, partialTick);
        graphics.drawCenteredString(this.font, this.title, this.width / 2, 12, 0xFFFFFF);
        graphics.drawCenteredString(this.font,
                Component.translatable("screen.goobymod.trick_select.subtitle")
                        .withStyle(ChatFormatting.GRAY),
                this.width / 2, 26, 0xA0A0A0);
    }

    /**
     * Vanilla wuerde nach {@code init()} bei Tastatur-Input per Tab-Navigation
     * das Widget NACH einer bereits fokussierten Karte anspringen. Der
     * gezielte InitialFocus-Pfad startet Tastatur und Narrator stattdessen
     * exakt auf der aktuell ausgewaehlten Karte.
     */
    @Override
    protected void setInitialFocus() {
        if (this.initialFocusCard != null) {
            setInitialFocus(this.initialFocusCard);
        } else {
            super.setInitialFocus();
        }
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    private void confirmSelection() {
        // Nur echte Aenderungen erzeugen Netzwerkverkehr; der Server validiert
        // die Auswahl anschliessend komplett neu (niemals Clientdaten trauen).
        if (this.pending != this.menu.selected()) {
            PacketDistributor.sendToServer(new TrickSelectPayload(this.menu.goobyId(), this.pending));
        }
        onClose();
    }

    /** Eine Kunststueck-Karte: Name, Sterne und Status; gesperrt bleibt fokussierbar. */
    private final class TrickCard extends AbstractButton {
        private final TrickMenuPayload.TrickEntry entry;

        TrickCard(int x, int y, int width, int height, TrickMenuPayload.TrickEntry entry) {
            super(x, y, width, height, Component.translatable(entry.trick().translationKey()));
            this.entry = entry;
            MutableComponent tooltip = Component.translatable(entry.trick().descriptionKey());
            if (!entry.unlocked()) {
                // Gesperrt bleibt bewusst nicht auswaehlbar — der Hinweis erklaert
                // den Trainingsweg (Sneak+Happen schaltet das Ziel durch).
                tooltip.append("\n\n").append(Component
                        .translatable("screen.goobymod.trick_select.locked_hint")
                        .withStyle(ChatFormatting.GRAY));
            }
            setTooltip(Tooltip.create(tooltip));
        }

        @Override
        public void onPress() {
            if (this.entry.unlocked()) {
                GoobyTrickScreen.this.pending = this.entry.trick();
            }
        }

        @Override
        public void playDownSound(SoundManager soundManager) {
            if (this.entry.unlocked()) {
                super.playDownSound(soundManager);
            } else {
                soundManager.play(SimpleSoundInstance.forUI(ModSounds.GOOBY_WHISTLE_DENIED.get(), 1.0F));
            }
        }

        @Override
        protected void renderWidget(GuiGraphics graphics, int mouseX, int mouseY, float partialTick) {
            boolean isPending = GoobyTrickScreen.this.pending == this.entry.trick();
            int background = !this.entry.unlocked() ? 0xC8141419
                    : isPending ? 0xE8283041 : 0xD01A1B26;
            int border = isPending ? 0xFFF7C948
                    : isHoveredOrFocused() ? 0xFF9AA7FF : 0xFF3C3F58;
            int left = getX();
            int top = getY();
            int right = left + this.width;
            int bottom = top + this.height;
            graphics.fill(left, top, right, bottom, background);
            graphics.fill(left, top, right, top + 1, border);
            graphics.fill(left, bottom - 1, right, bottom, border);
            graphics.fill(left, top, left + 1, bottom, border);
            graphics.fill(right - 1, top, right, bottom, border);

            // Text strikt auf Kartenbreite klammern: passt er, wird er links
            // ausgerichtet gezeichnet, sonst scrollt er im Scissor-Fenster.
            int textLeft = left + 7;
            int textRight = right - 5;
            int nameColor = this.entry.unlocked() ? 0xFFFFFF : 0x8A8A94;
            renderScrollingString(graphics, GoobyTrickScreen.this.font, getMessage(),
                    textLeft, textLeft, top + 5, textRight, top + 14, nameColor);
            graphics.drawString(GoobyTrickScreen.this.font, starsText(), textLeft, top + 17, 0xF7C948);
            if (this.height >= 39) {
                renderScrollingString(graphics, GoobyTrickScreen.this.font, stateText(),
                        textLeft, textLeft, top + 27, textRight, top + 36, stateColor());
            }
        }

        private Component starsText() {
            int stars = this.entry.stars();
            MutableComponent text = Component.literal("★".repeat(stars))
                    .withStyle(ChatFormatting.GOLD);
            return text.append(Component
                    .literal("☆".repeat(GoobyEntity.MAX_TRICK_PROFICIENCY - stars))
                    .withStyle(ChatFormatting.DARK_GRAY));
        }

        /**
         * "Aktiv" beschreibt NUR den serverseitig persistierten Stand — die
         * unbestaetigte Auswahl heisst "Ausgewaehlt". Damit zeigt der Screen
         * nach Cancel/Esc nie eine falsche Aktiv-Aussage.
         */
        private Component stateText() {
            if (!this.entry.unlocked()) {
                return Component.translatable("screen.goobymod.trick_select.state.locked");
            }
            if (GoobyTrickScreen.this.menu.selected() == this.entry.trick()) {
                return Component.translatable("screen.goobymod.trick_select.state.active");
            }
            if (GoobyTrickScreen.this.pending == this.entry.trick()) {
                return Component.translatable("screen.goobymod.trick_select.state.selected");
            }
            return Component.translatable("screen.goobymod.trick_select.state.available");
        }

        private int stateColor() {
            if (!this.entry.unlocked()) {
                return 0x8A8A94;
            }
            if (GoobyTrickScreen.this.menu.selected() == this.entry.trick()) {
                return 0x7FD98A;
            }
            if (GoobyTrickScreen.this.pending == this.entry.trick()) {
                return 0xF7C948;
            }
            return 0xA0A8BE;
        }

        @Override
        protected MutableComponent createNarrationMessage() {
            return Component.translatable("screen.goobymod.trick_select.narration",
                    getMessage(), this.entry.stars(), GoobyEntity.MAX_TRICK_PROFICIENCY, stateText());
        }

        @Override
        protected void updateWidgetNarration(NarrationElementOutput output) {
            defaultButtonNarrationText(output);
        }
    }
}
