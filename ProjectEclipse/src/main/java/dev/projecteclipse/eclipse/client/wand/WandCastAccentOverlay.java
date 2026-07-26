package dev.projecteclipse.eclipse.client.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * F-070 caster feedback: a brief path-tinted VEIL-CHARGE screen accent the moment the
 * local player's cast lands — the Veilladung visibly LEAVING the body. Zero wire: the
 * held wand's {@code wand_charge} data component is a synced component the
 * {@link WandChargeHud} already reads, so a tick-over-tick charge DROP on the same
 * path-locked wand is exactly "a cast was paid" (F-040: casting is the only spender;
 * regen only ever raises it). Heavier casts wash harder — intensity scales with the
 * paid cost, the same one intensity signal {@code WandPowers.castFlourish}'s D11 layer
 * uses.
 *
 * <p>House rules: {@code reducedFx} disables the accent entirely (no wash, detection
 * idles); F1 ({@code hideGui}) hides it; the wash is a single eased fade-out well under
 * the {@code MarkVignetteOverlay} alpha, never a strobe. GUI layer registered from THIS
 * class (the {@code BackroomsFlickerOverlay} no-shared-file precedent), under the
 * crosshair so the HUD stays readable. Hand-swaps and wand-swaps re-baseline without
 * triggering (the path guard + the reset on losing the wand).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WandCastAccentOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand_cast_accent");

    /** Accent length in ticks (short — a breath, not a state). */
    private static final int ACCENT_TICKS = 12;
    /** Peak edge alpha at full strength (MarkVignette runs 0.34; stay clearly under). */
    private static final float MAX_ALPHA = 0.22F;
    /** Cost that reads as a full-strength wash (the castFlourish heavy threshold ×2). */
    private static final float FULL_STRENGTH_COST = 60.0F;

    // Client thread only.
    private static int lastCharge = -1;
    private static int lastPathId = -1;
    private static int ticksLeft;
    private static float strength;
    private static int tintRgb = 0xB98CFF;

    private WandCastAccentOverlay() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerBelow(VanillaGuiLayers.CROSSHAIR, LAYER_ID, WandCastAccentOverlay::render);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null || minecraft.level == null) {
            lastCharge = -1;
            ticksLeft = 0;
            return;
        }
        if (ticksLeft > 0) {
            ticksLeft--;
        }
        ItemStack stack = player.getMainHandItem();
        if (!(stack.getItem() instanceof EclipseWandItem)) {
            stack = player.getOffhandItem();
        }
        if (!(stack.getItem() instanceof EclipseWandItem)) {
            lastCharge = -1; // no wand in either hand: drop the baseline, never trigger
            return;
        }
        WandPath path = WandSoulbind.pathOf(stack);
        int charge = stack.getOrDefault(WandItems.WAND_CHARGE.get(), 0);
        // A drop on the SAME path-locked wand = a paid cast. Path changes (fresh choice,
        // wand swap) and regen upticks only re-baseline.
        if (path != WandPath.NONE && path.id() == lastPathId
                && lastCharge >= 0 && charge < lastCharge
                && !EclipseClientConfig.reducedFx()) {
            float paid = lastCharge - charge;
            strength = Mth.clamp(0.45F + 0.55F * (paid / FULL_STRENGTH_COST), 0.45F, 1.0F);
            ticksLeft = ACCENT_TICKS;
            tintRgb = tint(path);
        }
        lastCharge = charge;
        lastPathId = path.id();
    }

    /** GUI-layer body; hidden under F1 and with {@code reducedFx} (calm variant: nothing). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        if (ticksLeft <= 0 || EclipseClientConfig.reducedFx()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        // One eased breath out — no pulse, no strobe (§A2 photosensitivity house rule).
        float t = (ticksLeft - deltaTracker.getGameTimeDeltaPartialTick(false)) / (float) ACCENT_TICKS;
        float alpha = MAX_ALPHA * strength * easeOutCubic(Mth.clamp(t, 0.0F, 1.0F));
        if (alpha <= 0.01F) {
            return;
        }

        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        int band = Math.max(10, height / 10);
        int red = (tintRgb >> 16) & 0xFF;
        int green = (tintRgb >> 8) & 0xFF;
        int blue = tintRgb & 0xFF;
        int solid = argb(alpha, red, green, blue);
        int clear = argb(0.0F, red, green, blue);
        // Path-tinted wash bleeding in from all four edges (the MarkVignette shape,
        // shorter and dimmer — reads as the veil charge flaring past the eyes).
        guiGraphics.fillGradient(0, 0, width, band, solid, clear);
        guiGraphics.fillGradient(0, height - band, width, height, clear, solid);
        fillGradientHorizontal(guiGraphics, 0, band, band, height - band, solid, clear);
        fillGradientHorizontal(guiGraphics, width - band, band, width, height - band, clear, solid);
    }

    /** Path accent RGB (the {@code WandChargeHud} tints, sans alpha). */
    private static int tint(WandPath path) {
        return switch (path) {
            case GLUT -> 0xFF9A4D;
            case STERN -> 0x7FE7FF;
            default -> 0xB98CFF; // RISS violet (NONE never triggers)
        };
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }

    private static void fillGradientHorizontal(GuiGraphics guiGraphics, int x0, int y0, int x1, int y1,
            int colorLeft, int colorRight) {
        int steps = Math.max(1, (x1 - x0) / 4);
        for (int i = 0; i < steps; i++) {
            float t0 = i / (float) steps;
            float t1 = (i + 1) / (float) steps;
            int sliceX0 = x0 + Math.round((x1 - x0) * t0);
            int sliceX1 = x0 + Math.round((x1 - x0) * t1);
            guiGraphics.fill(sliceX0, y0, sliceX1, y1, lerpColor(colorLeft, colorRight, (t0 + t1) * 0.5F));
        }
    }

    private static int lerpColor(int from, int to, float t) {
        int alpha = Mth.lerpInt(t, from >>> 24, to >>> 24);
        int red = Mth.lerpInt(t, (from >> 16) & 0xFF, (to >> 16) & 0xFF);
        int green = Mth.lerpInt(t, (from >> 8) & 0xFF, (to >> 8) & 0xFF);
        int blue = Mth.lerpInt(t, from & 0xFF, to & 0xFF);
        return (alpha << 24) | (red << 16) | (green << 8) | blue;
    }

    private static int argb(float alpha, int red, int green, int blue) {
        return (Mth.floor(Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | (red << 16) | (green << 8) | blue;
    }
}
