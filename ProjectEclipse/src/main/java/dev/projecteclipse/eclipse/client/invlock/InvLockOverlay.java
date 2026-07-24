package dev.projecteclipse.eclipse.client.invlock;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import net.minecraft.client.gui.screens.inventory.CreativeModeInventoryScreen;
import net.minecraft.network.chat.Component;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.Slot;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ContainerScreenEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * The sealed-inventory illusion (WB-SLOTLOCK): player-inventory slots that
 * {@code InvLockClientState} reports as locked are painted over as if the slot did not
 * exist — an opaque panel-dark fill over the full 18×18 slot cell (bevel border
 * included, so the sunken slot chrome vanishes) with a faint {@code ACCENT_DEEP}
 * diagonal hatch, phase-locked to screen coordinates so the weave runs continuously
 * across adjacent voided slots. Pure integer {@code fill}s — crisp at every gui scale.
 *
 * <p>Painting rides {@link ContainerScreenEvent.Render.Foreground} (the
 * {@code InventorySlotDecor} pattern: pose already translated to the container origin,
 * above slot items and the vanilla hover highlight, below tooltips and the carried
 * stack), raised to z {@value #COVER_Z} so stray slot items (z 150) can never poke
 * through mid-sync. It applies to every {@link AbstractContainerScreen} showing real
 * player-inventory slots — survival inventory, crafting table, chests, … — matched by
 * {@code slot.container instanceof Inventory} + container index, never by menu index.
 * The creative screen is excluded (own scrolled grid, fake slot indices; creative
 * players are never swept anyway). Slot 17 is never in the bitset (the pinned-artifact
 * exemption), so this overlay cannot touch {@code InventorySlotDecor}'s slot-17 frame.</p>
 *
 * <p>Interaction guard: mouse presses/releases over a voided slot are cancelled
 * ({@link ScreenEvent.MouseButtonPressed.Pre}/{@link ScreenEvent.MouseButtonReleased.Pre},
 * same {@code x−1..x+17} hitbox as the vanilla slot hit test), and hotbar-swap/offhand
 * key presses are swallowed while a voided slot is hovered — the server sweep already
 * reverses every escape path; this layer just keeps the illusion airtight. Hovering the
 * voided region shows one small padlock + day hint anchored to the row edge (never a
 * per-slot item tooltip).</p>
 *
 * <p>When a payload unseals slots, the cover materializes away: staggered per column,
 * each cover fades out while insetting toward the slot center, with a brief accent ring
 * — under {@code reducedFx} the cover simply vanishes. The unlock sting itself is played
 * by {@link InvLockClientState} (once per payload, not per slot).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class InvLockOverlay {
    /** Above slot items (z 150), below the carried stack (z 232) and tooltips (z 400). */
    private static final int COVER_Z = 200;
    /** Opaque panel fill ({@link EclipseUiTheme#PANEL} RGB at full alpha — no bevel bleed-through). */
    private static final int VOID_FILL = 0xFF000000 | (EclipseUiTheme.PANEL & 0xFFFFFF);
    /** Diagonal hatch pitch in px; phase-locked to (x+y) so it flows across slot seams. */
    private static final int HATCH_STEP = 6;
    private static final float HATCH_ALPHA = 0.22F;

    /** Materialize-in: per-slot fade duration and per-column stagger. */
    private static final int ANIM_FADE_MILLIS = 380;
    private static final int ANIM_STAGGER_MILLIS = 22;

    private InvLockOverlay() {}

    // ----------------------------------------------------------------- render

    @SubscribeEvent
    static void onRenderForeground(ContainerScreenEvent.Render.Foreground event) {
        AbstractContainerScreen<?> screen = event.getContainerScreen();
        if (screen instanceof CreativeModeInventoryScreen) {
            return;
        }
        boolean reducedFx = EclipseClientConfig.reducedFx();
        GuiGraphics guiGraphics = event.getGuiGraphics();
        long now = System.currentTimeMillis();
        Slot hoveredLocked = null;

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F, 0.0F, COVER_Z);
        for (Slot slot : screen.getMenu().slots) {
            if (!(slot.container instanceof Inventory) || !slot.isActive()) {
                continue; // vanilla renders only active slots — never void a hidden one
            }
            int containerSlot = slot.getContainerSlot();
            if (InvLockClientState.isLocked(containerSlot)) {
                drawVoid(guiGraphics, slot.x, slot.y, 1.0F);
                if (hoveredLocked == null && isInSlotHitbox(slot,
                        event.getMouseX() - screen.getGuiLeft(), event.getMouseY() - screen.getGuiTop())) {
                    hoveredLocked = slot;
                }
            } else {
                drawMaterializeIn(guiGraphics, slot, containerSlot, now, reducedFx);
            }
        }
        if (hoveredLocked != null) {
            drawRowEdgeHint(guiGraphics, screen, hoveredLocked);
        }
        guiGraphics.pose().popPose();
    }

    /** Opaque void cell over the full 18×18 slot rect (bevel included) + faint hatch. */
    private static void drawVoid(GuiGraphics guiGraphics, int slotX, int slotY, float alpha) {
        int x0 = slotX - 1;
        int y0 = slotY - 1;
        guiGraphics.fill(x0, y0, x0 + 18, y0 + 18, EclipseUiTheme.withAlpha(VOID_FILL, alpha));
        int hatch = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, HATCH_ALPHA * alpha);
        for (int dy = 0; dy < 18; dy++) {
            int phase = Math.floorMod(x0 + y0 + dy, HATCH_STEP);
            for (int dx = phase == 0 ? 0 : HATCH_STEP - phase; dx < 18; dx += HATCH_STEP) {
                guiGraphics.fill(x0 + dx, y0 + dy, x0 + dx + 1, y0 + dy + 1, hatch);
            }
        }
    }

    /**
     * A just-unsealed slot: the cover fades while insetting toward the slot center
     * (staggered per column so a row ripples back in), plus a brief accent ring.
     * {@code reducedFx} skips the motion entirely.
     */
    private static void drawMaterializeIn(GuiGraphics guiGraphics, Slot slot, int containerSlot,
            long now, boolean reducedFx) {
        long start = InvLockClientState.animStartMillis(containerSlot);
        if (start == 0L) {
            return;
        }
        int column = containerSlot >= 36 ? containerSlot - 36 : Math.floorMod(containerSlot - 9, 9);
        long elapsed = now - start - (long) column * ANIM_STAGGER_MILLIS;
        if (reducedFx || elapsed >= ANIM_FADE_MILLIS) {
            InvLockClientState.clearAnim(containerSlot);
            return;
        }
        if (elapsed < 0L) {
            drawVoid(guiGraphics, slot.x, slot.y, 1.0F); // stagger delay: still fully covered
            return;
        }
        float t = elapsed / (float) ANIM_FADE_MILLIS;
        float eased = t * t * (3.0F - 2.0F * t);
        int inset = Math.round(eased * 9.0F);
        int x0 = slot.x - 1 + inset;
        int y0 = slot.y - 1 + inset;
        int x1 = slot.x + 17 - inset;
        int y1 = slot.y + 17 - inset;
        if (x0 < x1 && y0 < y1) {
            guiGraphics.fill(x0, y0, x1, y1, EclipseUiTheme.withAlpha(VOID_FILL, 1.0F - eased));
        }
        // Accent glint: a 1px ring on the original cell edge, fading with the cover.
        int ring = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.55F * (1.0F - eased));
        int rx0 = slot.x - 1;
        int ry0 = slot.y - 1;
        guiGraphics.fill(rx0, ry0, rx0 + 18, ry0 + 1, ring);
        guiGraphics.fill(rx0, ry0 + 17, rx0 + 18, ry0 + 18, ring);
        guiGraphics.fill(rx0, ry0 + 1, rx0 + 1, ry0 + 17, ring);
        guiGraphics.fill(rx0 + 17, ry0 + 1, rx0 + 18, ry0 + 17, ring);
    }

    /**
     * One padlock + day hint panel anchored to the edge of the hovered voided row (per
     * the plan: a row-edge affordance, never per-slot tooltips). Flips to the left edge
     * when the right edge would clip the screen.
     */
    private static void drawRowEdgeHint(GuiGraphics guiGraphics, AbstractContainerScreen<?> screen,
            Slot hovered) {
        Font font = Minecraft.getInstance().font;
        int day = InvLockClientState.unlockDayFor(hovered.getContainerSlot());
        Component text = day > 0
                ? EclipseLang.tr("gui.eclipse.invlock.sealed_until", day)
                : EclipseLang.tr("gui.eclipse.invlock.sealed");
        int textWidth = font.width(text);
        int height = 16;
        int width = 4 + 8 + 3 + textWidth + 4;

        // Row bounds: the run of locked slots sharing the hovered slot's y (armor column
        // slots each form a one-slot "row", which anchors the hint right beside them).
        int rowLeft = hovered.x - 1;
        int rowRight = hovered.x + 17;
        for (Slot slot : screen.getMenu().slots) {
            if (slot.container instanceof Inventory && slot.isActive() && slot.y == hovered.y
                    && InvLockClientState.isLocked(slot.getContainerSlot())) {
                rowLeft = Math.min(rowLeft, slot.x - 1);
                rowRight = Math.max(rowRight, slot.x + 17);
            }
        }
        int x = rowRight + 4;
        if (screen.getGuiLeft() + x + width > guiGraphics.guiWidth() - 4) {
            x = rowLeft - 4 - width;
        }
        int y = hovered.y + 8 - height / 2;

        EclipseUiTheme.drawPanel(guiGraphics, x, y, width, height);
        drawPadlock(guiGraphics, x + 4, y + 4, EclipseUiTheme.ACCENT);
        guiGraphics.drawString(font, text, x + 4 + 8 + 3, y + 4, EclipseUiTheme.DIM);
    }

    /** Tiny 8×8 fill-built padlock (no texture dependency): shackle + body + keyhole. */
    private static void drawPadlock(GuiGraphics guiGraphics, int x, int y, int color) {
        guiGraphics.fill(x + 2, y, x + 6, y + 1, color);      // shackle top
        guiGraphics.fill(x + 1, y + 1, x + 2, y + 3, color);  // shackle left
        guiGraphics.fill(x + 6, y + 1, x + 7, y + 3, color);  // shackle right
        guiGraphics.fill(x, y + 3, x + 8, y + 8, color);      // body
        guiGraphics.fill(x + 3, y + 4, x + 5, y + 6, VOID_FILL); // keyhole
    }

    // ------------------------------------------------------------------ input

    /** Presses over a voided slot never reach the screen (the slot "does not exist"). */
    @SubscribeEvent
    static void onMousePressed(ScreenEvent.MouseButtonPressed.Pre event) {
        if (lockedSlotAt(event.getScreen(), event.getMouseX(), event.getMouseY()) != null) {
            event.setCanceled(true);
        }
    }

    /** Releases too — a drag started elsewhere cannot drop into a voided slot client-side. */
    @SubscribeEvent
    static void onMouseReleased(ScreenEvent.MouseButtonReleased.Pre event) {
        if (lockedSlotAt(event.getScreen(), event.getMouseX(), event.getMouseY()) != null) {
            event.setCanceled(true);
        }
    }

    /**
     * Quick-craft drags (vanilla distributes the carried stack in {@code mouseDragged})
     * must not sweep across a voided slot — cancelling while the cursor is over one keeps
     * the slot out of the drag set, same hitbox as the press/release guards.
     */
    @SubscribeEvent
    static void onMouseDragged(ScreenEvent.MouseDragged.Pre event) {
        if (lockedSlotAt(event.getScreen(), event.getMouseX(), event.getMouseY()) != null) {
            event.setCanceled(true);
        }
    }

    /** Hotbar-swap / offhand-swap / drop keys aimed at a hovered voided slot are swallowed. */
    @SubscribeEvent
    static void onKeyPressed(ScreenEvent.KeyPressed.Pre event) {
        if (!(event.getScreen() instanceof AbstractContainerScreen<?> screen)
                || screen instanceof CreativeModeInventoryScreen) {
            return;
        }
        Slot hovered = screen.getSlotUnderMouse();
        if (hovered == null || !(hovered.container instanceof Inventory)
                || !InvLockClientState.isLocked(hovered.getContainerSlot())) {
            return;
        }
        var options = Minecraft.getInstance().options;
        if (options.keySwapOffhand.matches(event.getKeyCode(), event.getScanCode())) {
            event.setCanceled(true);
            return;
        }
        if (options.keyDrop.matches(event.getKeyCode(), event.getScanCode())) {
            event.setCanceled(true);
            return;
        }
        for (var hotbarKey : options.keyHotbarSlots) {
            if (hotbarKey.matches(event.getKeyCode(), event.getScanCode())) {
                event.setCanceled(true);
                return;
            }
        }
    }

    /** The voided slot under the mouse (vanilla {@code x−1..x+17} hitbox), or {@code null}. */
    private static Slot lockedSlotAt(net.minecraft.client.gui.screens.Screen rawScreen,
            double mouseX, double mouseY) {
        if (!InvLockClientState.anyLocked()
                || !(rawScreen instanceof AbstractContainerScreen<?> screen)
                || screen instanceof CreativeModeInventoryScreen) {
            return null;
        }
        double relX = mouseX - screen.getGuiLeft();
        double relY = mouseY - screen.getGuiTop();
        for (Slot slot : screen.getMenu().slots) {
            if (slot.container instanceof Inventory && slot.isActive()
                    && InvLockClientState.isLocked(slot.getContainerSlot())
                    && isInSlotHitbox(slot, relX, relY)) {
                return slot;
            }
        }
        return null;
    }

    /** Mirrors {@code AbstractContainerScreen.isHovering}: {@code x−1 ≤ p < x+17}. */
    private static boolean isInSlotHitbox(Slot slot, double relX, double relY) {
        return relX >= slot.x - 1 && relX < slot.x + 17 && relY >= slot.y - 1 && relY < slot.y + 17;
    }
}
