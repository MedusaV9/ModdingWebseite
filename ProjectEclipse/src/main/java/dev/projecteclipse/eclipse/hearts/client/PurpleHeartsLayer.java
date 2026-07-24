package dev.projecteclipse.eclipse.hearts.client;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.death.GhostHeartsLayer;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.player.Player;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Purple hearts as THE player hearts renderer (W4-HEARTS R1). Cancels the vanilla
 * {@code PLAYER_HEALTH} layer (re-adding its exact {@code leftHeight} increment so
 * armor/vehicle rows keep their positions) and redraws the row from the eclipse-palette
 * 9x9 set under {@code textures/gui/hearts/} with full vanilla parity:
 *
 * <ul>
 *   <li>absorption hearts (violet-white {@code heart_absorbing_*} sprites),</li>
 *   <li>regen-wave −2px lift on the cycling slot,</li>
 *   <li>damage/heal blink (white containers + white-flash hearts up to the still-displayed
 *       health, driven by a faithful mirror of {@code Gui.healthBlinkTime}),</li>
 *   <li>≤4&nbsp;hp row jitter (suppressed under {@code reducedFx}),</li>
 *   <li>poison/wither/frozen status recolors (tint pass over the purple sprites),</li>
 *   <li>hardcore variants deliberately ignored — the event uses custom lives.</li>
 * </ul>
 *
 * <p>All row math is shared with {@link HeartBurstOverlay} via {@link HeartRowGeometry},
 * so shatters land pixel-exact on the drawn hearts. The layer registers <b>below</b>
 * {@code HeartBurstOverlay.LAYER_ID} (mod-bus priority LOW so the hub's registration in
 * {@code EclipseGuiLayers} runs first) and defers entirely to {@link GhostHeartsLayer}
 * while that layer owns the health slot — exactly one of the two ever cancels
 * {@code PLAYER_HEALTH}, so the compensation is never doubled.</p>
 *
 * <p><b>Kill-switch:</b> the {@code purpleHearts} client-config toggle (default ON), read
 * reflectively with a safe default until the shared {@code EclipseClientConfig} gains the
 * key (the {@code UiSounds.uiSoundVolume} precedent — see the W4-HEARTS wiring doc).
 * Off = the vanilla layer renders untouched, zero risk.</p>
 *
 * <p>Self-registered ({@code @EventBusSubscriber}, the {@code GhostHeartsLayer}
 * convention); allocation-free per frame.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PurpleHeartsLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "purple_hearts");

    private static final ResourceLocation CONTAINER = texture("heart_container");
    private static final ResourceLocation CONTAINER_BLINKING = texture("heart_container_blinking");
    private static final ResourceLocation FULL = texture("heart_full");
    private static final ResourceLocation HALF = texture("heart_half");
    private static final ResourceLocation FULL_BLINKING = texture("heart_full_blinking");
    private static final ResourceLocation HALF_BLINKING = texture("heart_half_blinking");
    private static final ResourceLocation ABSORBING_FULL = texture("heart_absorbing_full");
    private static final ResourceLocation ABSORBING_HALF = texture("heart_absorbing_half");

    private static final int HEART_SIZE = HeartRowGeometry.HEART_SIZE;

    /** Status recolors over the purple sprites (vanilla swaps whole sprite families). */
    private static final float[] TINT_POISON = {0.62F, 1.00F, 0.45F};
    private static final float[] TINT_WITHER = {0.42F, 0.36F, 0.46F};
    private static final float[] TINT_FROZEN = {0.55F, 0.78F, 1.00F};
    private static final float[] TINT_NONE = {1.0F, 1.0F, 1.0F};

    /** Vanilla jitter replay (same seed law as {@link HeartRowGeometry}). */
    private static final RandomSource JITTER_RANDOM = RandomSource.create();

    /** W3-shared config key, bound reflectively with default ON (UiSounds precedent). */
    private static final MethodHandle PURPLE_HEARTS_TOGGLE = findPurpleHeartsToggle();

    // --- faithful mirror of the private Gui blink state machine ---
    private static int lastHealth;
    private static int displayHealth;
    private static long lastHealthTime;
    private static long healthBlinkTime;

    /** True between our Pre-cancel and the layer body — the frames we own the slot. */
    private static boolean owningFrame;

    private PurpleHeartsLayer() {}

    // ------------------------------------------------------------------ public seam

    /** The kill-switch: {@code purpleHearts} client config, ON until the key lands. */
    public static boolean enabled() {
        if (PURPLE_HEARTS_TOGGLE == null) {
            return true;
        }
        try {
            return (boolean) PURPLE_HEARTS_TOGGLE.invokeExact();
        } catch (Throwable throwable) {
            return true;
        }
    }

    /**
     * The health value vanilla would still be displaying (blink window). Callers that
     * reconstruct row geometry while this layer owns the slot must use it so the row
     * count matches; falls back to live health when the layer is not rendering.
     */
    static int displayHealthMirror() {
        Minecraft minecraft = Minecraft.getInstance();
        if (owningFrame && minecraft.player != null) {
            return Math.max(displayHealth, Mth.ceil(minecraft.player.getHealth()));
        }
        return minecraft.player == null ? 0 : Mth.ceil(minecraft.player.getHealth());
    }

    /** Whether burst debris should be tinted to match the purple row this frame. */
    static boolean tintsBurst() {
        return owningFrame;
    }

    // ------------------------------------------------------------------ registration

    /**
     * Priority LOW: runs after {@code EclipseGuiLayers}' default-priority registration,
     * so anchoring below the already-registered burst layer is deterministic — shatters
     * always draw on top of the purple hearts.
     */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerBelow(HeartBurstOverlay.LAYER_ID, LAYER_ID, PurpleHeartsLayer::render);
    }

    /**
     * Takes over the slot exactly when vanilla would draw it (survival camera player,
     * HUD visible) and the ghost row is not showing. The compensation must be computed
     * BEFORE the blink mirror can change {@code displayHealth} mid-frame, hence the
     * update runs here and the render body only reads.
     *
     * <p>{@code receiveCanceled}: when another cancel wins the slot first (the ghost row,
     * cutscene HUD suppression), this handler must STILL run to clear {@link #owningFrame}
     * — otherwise a stale {@code true} from the previous frame would double-render.</p>
     */
    @SubscribeEvent(receiveCanceled = true)
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (!event.getName().equals(VanillaGuiLayers.PLAYER_HEALTH)) {
            return;
        }
        owningFrame = false;
        if (event.isCanceled() || !enabled() || GhostHeartsLayer.isOwningHealthSlot()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.options.hideGui
                || minecraft.gameMode == null || !minecraft.gameMode.canHurtPlayer()
                || !(minecraft.getCameraEntity() instanceof Player player)) {
            return; // vanilla would draw nothing either — leave the layer alone
        }
        event.setCanceled(true);
        updateBlinkState(minecraft, player);
        float rowMax = HeartRowGeometry.rowMaxHealth(player, displayHealth);
        int rows = HeartRowGeometry.rows(rowMax, Mth.ceil(player.getAbsorptionAmount()));
        minecraft.gui.leftHeight += HeartRowGeometry.leftHeightIncrement(rows);
        owningFrame = true;
    }

    // ------------------------------------------------------------------ blink mirror

    /** Line-for-line mirror of the private vanilla state machine in {@code renderHealthLevel}. */
    private static void updateBlinkState(Minecraft minecraft, Player player) {
        int health = Mth.ceil(player.getHealth());
        long millis = Util.getMillis();
        int guiTicks = minecraft.gui.getGuiTicks();
        if (health < lastHealth && player.invulnerableTime > 0) {
            lastHealthTime = millis;
            healthBlinkTime = guiTicks + 20L;
        } else if (health > lastHealth && player.invulnerableTime > 0) {
            lastHealthTime = millis;
            healthBlinkTime = guiTicks + 10L;
        }
        if (millis - lastHealthTime > 1000L) {
            displayHealth = health;
            lastHealthTime = millis;
        }
        lastHealth = health;
    }

    // ------------------------------------------------------------------ layer body

    /** GUI-layer body (below the burst overlay). Only draws on frames the Pre hook owned. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!owningFrame || !(minecraft.getCameraEntity() instanceof Player player)) {
            return;
        }

        int guiTicks = minecraft.gui.getGuiTicks();
        int health = Mth.ceil(player.getHealth());
        int absorption = Mth.ceil(player.getAbsorptionAmount());
        boolean highlight = healthBlinkTime > guiTicks && (healthBlinkTime - guiTicks) / 3L % 2L == 1L;

        float rowMax = HeartRowGeometry.rowMaxHealth(player, displayHealth);
        int healthSlots = HeartRowGeometry.healthSlots(rowMax);
        int totalSlots = HeartRowGeometry.totalSlots(rowMax, absorption);
        int rows = HeartRowGeometry.rows(rowMax, absorption);
        int rowStep = HeartRowGeometry.rowStep(rows);
        int rowX = HeartRowGeometry.rowLeft(guiGraphics);
        // Pre-hook already compensated leftHeight; reconstruct the pre-layer origin.
        int baseY = guiGraphics.guiHeight() - minecraft.gui.leftHeight
                + HeartRowGeometry.leftHeightIncrement(rows);
        int regenSlot = HeartRowGeometry.regenSlot(minecraft, player, rowMax);
        boolean jitter = HeartRowGeometry.jitterActive(player);
        boolean applyJitter = jitter && !HeartRowGeometry.jitterSuppressed();
        JITTER_RANDOM.setSeed(guiTicks * HeartRowGeometry.JITTER_SEED_MULTIPLIER);

        float[] tint = statusTint(player);
        boolean withered = player.hasEffect(MobEffects.WITHER);

        RenderSystem.enableBlend();
        // Vanilla iterates top slot -> 0, consuming one jitter draw per slot.
        for (int slot = totalSlots - 1; slot >= 0; slot--) {
            int x = rowX + (slot % 10) * HeartRowGeometry.HEART_STEP_X;
            int y = baseY - (slot / 10) * rowStep;
            if (jitter) {
                int offset = JITTER_RANDOM.nextInt(2);
                if (applyJitter) {
                    y += offset;
                }
            }
            if (slot < healthSlots && slot == regenSlot) {
                y -= 2;
            }

            drawSprite(guiGraphics, highlight ? CONTAINER_BLINKING : CONTAINER, x, y, TINT_NONE);

            int hp = slot * 2;
            if (slot >= healthSlots) {
                // Absorption slot. Vanilla renders WITHERED hearts here while withering.
                int absorbed = hp - healthSlots * 2;
                if (absorbed < absorption) {
                    boolean last = absorbed + 1 == absorption;
                    if (withered) {
                        drawSprite(guiGraphics, last ? HALF : FULL, x, y, tint);
                    } else {
                        drawSprite(guiGraphics, last ? ABSORBING_HALF : ABSORBING_FULL, x, y, TINT_NONE);
                    }
                }
            }
            if (highlight && hp < displayHealth) {
                drawSprite(guiGraphics, hp + 1 == displayHealth ? HALF_BLINKING : FULL_BLINKING,
                        x, y, tint);
            }
            if (hp < health) {
                drawSprite(guiGraphics, hp + 1 == health ? HALF : FULL, x, y, tint);
            }
        }
        RenderSystem.disableBlend();
    }

    private static void drawSprite(GuiGraphics guiGraphics, ResourceLocation sprite,
            int x, int y, float[] tint) {
        guiGraphics.setColor(tint[0], tint[1], tint[2], 1.0F);
        guiGraphics.blit(sprite, x, y, HEART_SIZE, HEART_SIZE,
                0.0F, 0.0F, HEART_SIZE, HEART_SIZE, HEART_SIZE, HEART_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
    }

    /** Poison/wither/frozen read as tints of the purple set (vanilla priority order). */
    private static float[] statusTint(Player player) {
        if (player.hasEffect(MobEffects.POISON)) {
            return TINT_POISON;
        }
        if (player.hasEffect(MobEffects.WITHER)) {
            return TINT_WITHER;
        }
        if (player.isFullyFrozen()) {
            return TINT_FROZEN;
        }
        return TINT_NONE;
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/gui/hearts/" + name + ".png");
    }

    private static MethodHandle findPurpleHeartsToggle() {
        try {
            return MethodHandles.publicLookup().findStatic(EclipseClientConfig.class,
                    "purpleHearts", MethodType.methodType(boolean.class));
        } catch (ReflectiveOperationException absent) {
            return null; // wiring ask not merged yet — default ON (see W4-HEARTS wiring)
        }
    }
}
