package dev.projecteclipse.eclipse.client.xbox;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.death.GhostHeartsLayer;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * C17 UI skin swap: the classic (console-era) HUD inside the Xbox tutorial dimensions —
 * a dimension-gated takeover of the hotbar and the health row, driven by the same gate as
 * the era color filter ({@link XboxEraFx#inXboxDimension()}).
 *
 * <ul>
 *   <li><b>Hotbar</b>: cancels the vanilla {@code HOTBAR} layer and redraws the classic
 *       gray bar from {@code textures/gui/xbox/hotbar_classic.png} — 9 slots, NO offhand
 *       slot and NO attack indicator (both are post-era, X360 had neither). Items render
 *       through the vanilla item renderer at the vanilla slot coordinates, so pick-up
 *       animations and stack counts behave exactly as expected.</li>
 *   <li><b>Hearts</b>: cancels {@code PLAYER_HEALTH} at {@link EventPriority#HIGH} —
 *       BEFORE {@code PurpleHeartsLayer}'s default-priority takeover, which then defers
 *       (its handler receives the cancelled event and clears its owning flag, the
 *       {@code GhostHeartsLayer} contract) — and draws the UNCOMPRESSED vanilla-law row
 *       (1 heart = 2 hp, up to 10 per row) from the classic 9×9 sprites under
 *       {@code textures/gui/xbox/}. No Leben compression inside: the era look is the
 *       full classic double-row of red hearts. The vanilla {@code leftHeight} increment
 *       is re-added so armor/food rows stack exactly like vanilla.</li>
 * </ul>
 *
 * <p>Defers to {@link GhostHeartsLayer} while that owns the health slot, and never
 * activates for spectators. Both replacement layers carry their own ids and are
 * deliberately NOT letterbox-whitelisted — cutscene HUD suppression hides them like the
 * vanilla layers they replace. Textures are procedurally recreated era-style art (see
 * {@code docs/XBOX_WORLDS.md} provenance).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class XboxHudSkin {
    public static final ResourceLocation HOTBAR_LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "xbox_hotbar");
    public static final ResourceLocation HEARTS_LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "xbox_hearts");

    private static final ResourceLocation HOTBAR_TEXTURE = texture("hotbar_classic");
    private static final ResourceLocation SELECTION_TEXTURE = texture("hotbar_selection_classic");
    private static final ResourceLocation HEART_CONTAINER = texture("heart_container_classic");
    private static final ResourceLocation HEART_FULL = texture("heart_full_classic");
    private static final ResourceLocation HEART_HALF = texture("heart_half_classic");

    private static final int HOTBAR_WIDTH = 182;
    private static final int HOTBAR_HEIGHT = 22;
    private static final int SELECTION_SIZE_X = 24;
    private static final int SELECTION_SIZE_Y = 23;
    private static final int HEART_SIZE = 9;
    private static final int HEART_STEP_X = 8;

    /** True between the Pre-cancel and the layer body — the frames each layer owns. */
    private static boolean owningHotbar;
    private static boolean owningHealth;

    private XboxHudSkin() {}

    /** The dimension gate shared by both takeovers (never active for spectators). */
    public static boolean classicHudActive() {
        Minecraft minecraft = Minecraft.getInstance();
        return XboxEraFx.inXboxDimension()
                && minecraft.player != null && !minecraft.player.isSpectator();
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAbove(VanillaGuiLayers.HOTBAR, HOTBAR_LAYER_ID, XboxHudSkin::renderHotbar);
        event.registerAbove(VanillaGuiLayers.PLAYER_HEALTH, HEARTS_LAYER_ID, XboxHudSkin::renderHearts);
    }

    /**
     * HIGH priority: must run before {@code PurpleHeartsLayer}'s default-priority handler
     * so the purple row defers to the classic skin (one cancel wins the slot; theirs
     * receives the cancelled event and clears its own flag).
     */
    @SubscribeEvent(priority = EventPriority.HIGH, receiveCanceled = true)
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (event.getName().equals(VanillaGuiLayers.HOTBAR)) {
            owningHotbar = false;
            if (event.isCanceled() || !classicHudActive()) {
                return;
            }
            Minecraft minecraft = Minecraft.getInstance();
            if (minecraft.options.hideGui
                    || !(minecraft.getCameraEntity() instanceof Player)) {
                return;
            }
            event.setCanceled(true);
            owningHotbar = true;
        } else if (event.getName().equals(VanillaGuiLayers.PLAYER_HEALTH)) {
            owningHealth = false;
            if (event.isCanceled() || !classicHudActive() || GhostHeartsLayer.isOwningHealthSlot()) {
                return;
            }
            Minecraft minecraft = Minecraft.getInstance();
            if (minecraft.options.hideGui
                    || minecraft.gameMode == null || !minecraft.gameMode.canHurtPlayer()
                    || !(minecraft.getCameraEntity() instanceof Player player)) {
                return; // vanilla would draw nothing either — leave the layer alone
            }
            event.setCanceled(true);
            // Vanilla-exact compensation (uncompressed law) so armor/food stack correctly.
            minecraft.gui.leftHeight += leftHeightIncrement(rows(player));
            owningHealth = true;
        }
    }

    // ------------------------------------------------------------------ hotbar body

    private static void renderHotbar(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!owningHotbar || !(minecraft.getCameraEntity() instanceof Player player)) {
            return;
        }
        int left = guiGraphics.guiWidth() / 2 - HOTBAR_WIDTH / 2;
        int top = guiGraphics.guiHeight() - HOTBAR_HEIGHT;

        RenderSystem.enableBlend();
        guiGraphics.blit(HOTBAR_TEXTURE, left, top, 0.0F, 0.0F,
                HOTBAR_WIDTH, HOTBAR_HEIGHT, HOTBAR_WIDTH, HOTBAR_HEIGHT);
        int selected = player.getInventory().selected;
        guiGraphics.blit(SELECTION_TEXTURE, left - 1 + selected * 20, top - 1, 0.0F, 0.0F,
                SELECTION_SIZE_X, SELECTION_SIZE_Y, SELECTION_SIZE_X, SELECTION_SIZE_Y);
        RenderSystem.disableBlend();

        // Vanilla slot coordinates (Gui.renderHotbarAndDecorations): x = left + 3 + i*20.
        int itemY = guiGraphics.guiHeight() - 19;
        int seed = 1;
        for (int slot = 0; slot < 9; slot++) {
            ItemStack stack = player.getInventory().items.get(slot);
            int itemX = left + 3 + slot * 20;
            guiGraphics.renderItem(player, stack, itemX, itemY, seed + slot);
            guiGraphics.renderItemDecorations(minecraft.font, stack, itemX, itemY);
        }
        // Era-correct omissions: no offhand slot, no attack-strength indicator.
    }

    // ------------------------------------------------------------------ hearts body

    private static void renderHearts(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!owningHealth || !(minecraft.getCameraEntity() instanceof Player player)) {
            return;
        }
        int health = Mth.ceil(player.getHealth());
        float rowMax = Math.max((float) player.getAttributeValue(Attributes.MAX_HEALTH), health);
        int absorption = Mth.ceil(player.getAbsorptionAmount());
        int healthSlots = Mth.ceil(rowMax / 2.0F);
        int totalSlots = healthSlots + Mth.ceil(absorption / 2.0F);
        int rows = rows(player);
        int rowStep = Math.max(10 - (rows - 2), 3);

        int rowX = guiGraphics.guiWidth() / 2 - 91;
        // The Pre hook already compensated leftHeight; reconstruct the pre-layer origin.
        int baseY = guiGraphics.guiHeight() - minecraft.gui.leftHeight + leftHeightIncrement(rows);

        RenderSystem.enableBlend();
        for (int slot = totalSlots - 1; slot >= 0; slot--) {
            int x = rowX + (slot % 10) * HEART_STEP_X;
            int y = baseY - (slot / 10) * rowStep;
            drawHeart(guiGraphics, HEART_CONTAINER, x, y);
            int hp = slot * 2;
            if (slot >= healthSlots) {
                int absorbed = hp - healthSlots * 2;
                if (absorbed < absorption) {
                    drawHeart(guiGraphics, absorbed + 1 == absorption ? HEART_HALF : HEART_FULL, x, y);
                }
            } else if (hp < health) {
                drawHeart(guiGraphics, hp + 1 == health ? HEART_HALF : HEART_FULL, x, y);
            }
        }
        RenderSystem.disableBlend();
    }

    private static void drawHeart(GuiGraphics guiGraphics, ResourceLocation sprite, int x, int y) {
        guiGraphics.blit(sprite, x, y, 0.0F, 0.0F,
                HEART_SIZE, HEART_SIZE, HEART_SIZE, HEART_SIZE);
    }

    // ------------------------------------------------------------------ shared math

    /** Vanilla row count on the UNCOMPRESSED law: {@code ceil((maxHealth + absorb) / 2 / 10)}. */
    private static int rows(Player player) {
        float rowMax = Math.max((float) player.getAttributeValue(Attributes.MAX_HEALTH),
                Mth.ceil(player.getHealth()));
        return Math.max(1, Mth.ceil((rowMax + Mth.ceil(player.getAbsorptionAmount())) / 2.0F / 10.0F));
    }

    /** Vanilla health-layer {@code leftHeight} increment: {@code (rows - 1) * step + 10}. */
    private static int leftHeightIncrement(int rows) {
        return (rows - 1) * Math.max(10 - (rows - 2), 3) + 10;
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/gui/xbox/" + name + ".png");
    }
}
