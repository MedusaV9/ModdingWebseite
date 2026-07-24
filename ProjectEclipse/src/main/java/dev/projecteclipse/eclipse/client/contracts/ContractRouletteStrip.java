package dev.projecteclipse.eclipse.client.contracts;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.PlayerFaceRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Deterministic head strip for the contract reveal — a faithful REPLICA of the
 * {@code client/awards/RouletteStrip} physics (that class is deliberately package-private,
 * so its ease-out-quart math is reproduced here; keep the two in sync if the curve ever
 * changes): total travel is fixed up front, {@code pos(t) = distance * (1 - (1 - t/T)^4)},
 * so the strip lands pixel-perfect under the marker with no correction step.
 *
 * <p>Unlike the awards strip there are no candidates to shuffle: every head is the SAME
 * uniform "eclipsed" face by design (the whole server wears one skin) — the drama is that
 * the landing head resolves into a REAL face, which {@link ContractRevealOverlay} draws on
 * top of the landed slot.</p>
 */
@OnlyIn(Dist.CLIENT)
final class ContractRouletteStrip {
    /** Head-to-head distance in GUI px (matches the awards strip look). */
    static final int SPACING = 30;
    static final int HEAD_SIZE = 24;

    /**
     * Same path literal as {@code AbstractClientPlayerMixin.ECLIPSE$UNIFORM_SKIN} and
     * {@code RouletteStrip.UNIFORM_SKIN} (mixins are never referenced from regular code).
     */
    static final ResourceLocation UNIFORM_SKIN = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/entity/eclipsed_player.png");

    private static final double TARGET_START_HEADS_PER_SECOND = 55.0;
    private static final int MIN_LOOPS = 2;
    private static final float CENTER_SCALE_BOOST = 0.25F;
    /** Virtual candidate count — purely visual; every head is the same uniform face. */
    private static final int VIRTUAL_HEADS = 12;

    private final int spinTicks;
    private final double totalDistance;

    private int ticks;
    private int lastPassedHead;

    ContractRouletteStrip(int spinTicks) {
        this.spinTicks = Math.max(0, spinTicks);
        this.totalDistance = SPACING * travelHeads(VIRTUAL_HEADS, 0, this.spinTicks);
        if (this.spinTicks == 0) {
            this.lastPassedHead = (int) Math.floor(this.totalDistance / SPACING);
        }
    }

    // --- physics (replicated from RouletteStrip; package-private for the same reason) ---

    static double easeOutQuart(double u) {
        double clamped = Mth.clamp(u, 0.0D, 1.0D);
        double inverse = 1.0D - clamped;
        return 1.0D - inverse * inverse * inverse * inverse;
    }

    static int travelHeads(int candidateCount, int winnerIndex, int spinTicks) {
        int count = Math.max(1, candidateCount);
        if (spinTicks <= 0) {
            return Math.max(0, winnerIndex);
        }
        double targetTravel = TARGET_START_HEADS_PER_SECOND * spinTicks / 80.0D;
        int loops = (int) Math.max(MIN_LOOPS, Math.round((targetTravel - winnerIndex) / count));
        return winnerIndex + count * loops;
    }

    static double positionAt(double totalDistance, int spinTicks, double time) {
        if (spinTicks <= 0) {
            return totalDistance;
        }
        return totalDistance * easeOutQuart(time / spinTicks);
    }

    /** Falls with strip speed, rises slightly over the last fifth (the awards-strip curve). */
    static float tickPitch(float progress) {
        float p = Mth.clamp(progress, 0.0F, 1.0F);
        float speedFraction = (1.0F - p) * (1.0F - p) * (1.0F - p);
        float pitch = 0.78F + 0.5F * speedFraction;
        if (p > 0.8F) {
            pitch += 0.27F * (p - 0.8F) / 0.2F;
        }
        return Mth.clamp(pitch, 0.5F, 2.0F);
    }

    // --- spin state ---

    /** Advances one tick; returns how many heads crossed the marker (throttle sounds to 1/tick). */
    int tick() {
        if (done()) {
            return 0;
        }
        ticks++;
        int passed = (int) Math.floor(positionAt(totalDistance, spinTicks, ticks) / SPACING);
        int passes = passed - lastPassedHead;
        lastPassedHead = passed;
        return passes;
    }

    boolean done() {
        return ticks >= spinTicks;
    }

    float progress() {
        return spinTicks <= 0 ? 1.0F : Mth.clamp(ticks / (float) spinTicks, 0.0F, 1.0F);
    }

    /**
     * Draws the strip centered on {@code (centerX, centerY)}. While {@code landed}, the
     * exact head under the marker is skipped — the overlay draws the resolved REAL face
     * (or its X-stamped variant) into that hole.
     */
    void render(GuiGraphics guiGraphics, int centerX, int centerY, int halfWidth,
            float partialTick, float alpha, boolean landed) {
        double time = Math.min(ticks + partialTick, spinTicks);
        double pos = positionAt(totalDistance, spinTicks, time);
        int landedHead = (int) Math.round(totalDistance / SPACING);

        int firstHead = (int) Math.floor((pos - halfWidth) / SPACING) - 1;
        int lastHead = (int) Math.ceil((pos + halfWidth) / SPACING) + 1;
        for (int head = firstHead; head <= lastHead; head++) {
            if (landed && head == landedHead) {
                continue;
            }
            float offset = (float) (head * (double) SPACING - pos);
            float edge = Math.abs(offset) / halfWidth;
            if (edge > 1.05F) {
                continue;
            }
            float headAlpha = alpha * Mth.clamp(1.0F - 0.65F * edge * edge, 0.0F, 1.0F);
            if (landed) {
                headAlpha *= 0.45F;
            }
            if (headAlpha < 0.03F) {
                continue;
            }
            float centerness = Mth.clamp(1.0F - Math.abs(offset) / SPACING, 0.0F, 1.0F);
            float scale = 1.0F + CENTER_SCALE_BOOST * centerness;
            drawHead(guiGraphics, UNIFORM_SKIN, centerX + offset, centerY, scale, headAlpha);
        }
    }

    /** One face blit, pose-scaled around its center (the BossbarSkin alpha-blit pattern). */
    static void drawHead(GuiGraphics guiGraphics, ResourceLocation skin, float centerX,
            float centerY, float scale, float alpha) {
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, centerY, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, Mth.clamp(alpha, 0.0F, 1.0F));
        PlayerFaceRenderer.draw(guiGraphics, skin, -HEAD_SIZE / 2, -HEAD_SIZE / 2, HEAD_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        guiGraphics.pose().popPose();
    }
}
