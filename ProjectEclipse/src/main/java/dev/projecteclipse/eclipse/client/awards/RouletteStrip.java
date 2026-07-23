package dev.projecteclipse.eclipse.client.awards;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.UUID;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.PlayerFaceRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The scrolling head strip of one daily-award reveal ({@code docs/plans_v3/P3_ui.md} §3.10,
 * P3-W10): candidates repeat cyclically, the strip starts fast and eases out over the spin,
 * and — by construction — lands EXACTLY on the winner every time.
 *
 * <p><b>Deterministic landing.</b> The total travel is fixed up front:
 * {@code distance = SPACING * (loops * candidateCount + winnerDisplayIndex)}, and the
 * position curve is a pure ease-out quart {@code pos(t) = distance * (1 - (1 - t/T)^4)}.
 * Because {@code pos(T) == distance} exactly and the travel is an exact multiple of the
 * head spacing plus the winner offset, the winner's head sits pixel-perfect under the
 * center marker at the end of the spin — no correction step, no drift. The loop count is
 * chosen so the initial velocity is ≈{@value #TARGET_START_HEADS_PER_SECOND} heads/s
 * (design: "60→4 heads/s, ease-out"), which the quart curve then decays to zero.</p>
 *
 * <p><b>Anonymity.</b> The reveal payload deliberately carries UUIDs only
 * ({@code S2CAwardRevealPayload} javadoc) and every client player wears the one uniform
 * "eclipsed" skin ({@code client/mixin/AbstractClientPlayerMixin}), so ALL heads render the
 * same bundled face texture — that is correct by design, not a fallback. The display order
 * is shuffled with a day+category seed so the server's best-first candidate sorting leaks
 * no ranking; the seed is shared by every client, keeping the show identical for all
 * viewers. A shimmering {@link GlitchText} tag under the marker stands in for the names the
 * server never sent.</p>
 *
 * <p>All spin state advances in {@link #tick()} (game ticks, caller freezes it while
 * paused); {@link #render} is a pure function of {@code ticks + partialTick} and allocates
 * nothing per frame beyond the glitch tag string.</p>
 */
@OnlyIn(Dist.CLIENT)
final class RouletteStrip {
    /** Head-to-head distance in GUI px. */
    static final int SPACING = 30;
    /** Base head edge length in GUI px (scaled up toward the marker). */
    static final int HEAD_SIZE = 24;

    /**
     * The uniform skin every player wears — same path as
     * {@code AbstractClientPlayerMixin.ECLIPSE$UNIFORM_SKIN} (mixins are not referenced from
     * regular code; keep the two literals in sync if the skin ever moves).
     */
    static final ResourceLocation UNIFORM_SKIN = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/entity/eclipsed_player.png");

    /** Initial spin speed the travel distance is solved for (heads passing the marker per second). */
    private static final double TARGET_START_HEADS_PER_SECOND = 55.0;
    /** Never spin fewer than this many full candidate loops, however short the strip. */
    private static final int MIN_LOOPS = 2;
    /** Center-emphasis: heads grow up to this factor while under the marker. */
    private static final float CENTER_SCALE_BOOST = 0.25F;

    private final List<UUID> displayOrder;
    private final int winnerDisplayIndex;
    private final int spinTicks;
    private final double totalDistance;

    /** Whole game ticks elapsed; the render position adds the partial tick on top. */
    private int ticks;
    /** floor(pos/SPACING) after the last {@link #tick()} — marker-pass detection. */
    private int lastPassedHead;

    /**
     * @param candidates candidate UUIDs in payload order (server sends them best-first;
     *                   shuffled here for display)
     * @param primaryWinner the winner the strip must land on (first entry of the payload's
     *                      tie-aware {@code winners} list)
     * @param seed deterministic shuffle seed (same on every client: day + category id)
     * @param spinTicks spin duration in game ticks; {@code 0} = pre-landed (reduced FX)
     */
    RouletteStrip(List<UUID> candidates, UUID primaryWinner, long seed, int spinTicks) {
        this.displayOrder = shuffle(candidates, seed);
        int index = this.displayOrder.indexOf(primaryWinner);
        this.winnerDisplayIndex = Math.max(0, index);
        this.spinTicks = Math.max(0, spinTicks);
        this.totalDistance = SPACING
                * travelHeads(this.displayOrder.size(), this.winnerDisplayIndex, this.spinTicks);
        if (this.spinTicks == 0) {
            this.ticks = 0;
            this.lastPassedHead = (int) Math.floor(this.totalDistance / SPACING);
        }
    }

    // --- deterministic physics (package-private statics: exercised by the dev harness) ---

    /** Ease-out quart: fast start, exponential-feeling decay, exactly 1.0 at u = 1. */
    static double easeOutQuart(double u) {
        double clamped = Mth.clamp(u, 0.0D, 1.0D);
        double inverse = 1.0D - clamped;
        return 1.0D - inverse * inverse * inverse * inverse;
    }

    /**
     * Total marker passes for one spin: {@code winnerIndex + candidateCount * loops}, loops
     * solved so the t=0 velocity ({@code 4 * distance / spinTicks}) is close to
     * {@value #TARGET_START_HEADS_PER_SECOND} heads/s. Always ≥ {@value #MIN_LOOPS} loops.
     */
    static int travelHeads(int candidateCount, int winnerIndex, int spinTicks) {
        int count = Math.max(1, candidateCount);
        if (spinTicks <= 0) {
            return Math.max(0, winnerIndex);
        }
        // headsPerSecond(0) = 4 * travelHeads / spinTicks * 20  =>  target travel:
        double targetTravel = TARGET_START_HEADS_PER_SECOND * spinTicks / 80.0D;
        int loops = (int) Math.max(MIN_LOOPS, Math.round((targetTravel - winnerIndex) / count));
        return winnerIndex + count * loops;
    }

    /** Strip position in px after {@code time} ticks of a {@code spinTicks}-long spin. */
    static double positionAt(double totalDistance, int spinTicks, double time) {
        if (spinTicks <= 0) {
            return totalDistance;
        }
        return totalDistance * easeOutQuart(time / spinTicks);
    }

    /**
     * Tick-sound pitch over spin progress: falls with the strip's speed (fast blur → deep
     * slow clicks), then rises slightly over the last ~fifth for the classic "will it stop
     * on me" tension (task quality bar: exponential ease-out, pitch rising near the end).
     */
    static float tickPitch(float progress) {
        float p = Mth.clamp(progress, 0.0F, 1.0F);
        float speedFraction = (1.0F - p) * (1.0F - p) * (1.0F - p);
        float pitch = 0.78F + 0.5F * speedFraction;
        if (p > 0.8F) {
            pitch += 0.27F * (p - 0.8F) / 0.2F;
        }
        return Mth.clamp(pitch, 0.5F, 2.0F);
    }

    /** Seeded Fisher–Yates copy — identical on every client for the same day/category. */
    static List<UUID> shuffle(List<UUID> candidates, long seed) {
        List<UUID> order = new ArrayList<>(candidates);
        Random random = new Random(seed);
        for (int i = order.size() - 1; i > 0; i--) {
            int j = random.nextInt(i + 1);
            UUID swap = order.get(i);
            order.set(i, order.get(j));
            order.set(j, swap);
        }
        return order;
    }

    // --- spin state ---

    /**
     * Advances one game tick and returns how many heads crossed the center marker during it
     * (0 during the slow tail, several per tick at full speed). The caller plays at most one
     * {@code ui.roulette_tick} per game tick regardless.
     */
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

    /** 0..1 spin progress (1 when landed / pre-landed). */
    float progress() {
        return spinTicks <= 0 ? 1.0F : Mth.clamp(ticks / (float) spinTicks, 0.0F, 1.0F);
    }

    int candidateCount() {
        return displayOrder.size();
    }

    /** The candidate UUID currently under (or nearest to) the center marker. */
    UUID centeredCandidate() {
        double pos = positionAt(totalDistance, spinTicks, ticks);
        int head = (int) Math.round(pos / SPACING);
        return displayOrder.get(Math.floorMod(head, displayOrder.size()));
    }

    /**
     * Draws the strip centered on {@code (centerX, centerY)}, clipped by the caller's
     * scissor. While {@code landed}, the exact winner head under the marker is skipped —
     * {@code AwardsOverlay} draws its popped/flared version on top of this hole.
     */
    void render(GuiGraphics guiGraphics, Font font, int centerX, int centerY, int halfWidth,
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
                headAlpha *= 0.45F; // losers recede once the winner is framed
            }
            if (headAlpha < 0.03F) {
                continue;
            }
            float centerness = Mth.clamp(1.0F - Math.abs(offset) / SPACING, 0.0F, 1.0F);
            float scale = 1.0F + CENTER_SCALE_BOOST * centerness;
            drawHead(guiGraphics, centerX + offset, centerY, scale, headAlpha);
        }

        // Shimmering anonymized tag under the head crossing the marker — the strip's stand-in
        // for candidate names (the payload carries none, by design).
        if (!landed) {
            UUID centered = centeredCandidate();
            String tag = GlitchText.unknown(centered.hashCode());
            int tagWidth = font.width(tag);
            guiGraphics.drawString(font, tag, centerX - tagWidth / 2, centerY + HEAD_SIZE / 2 + 5,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
        }
    }

    /**
     * One uniform-skin face via the vanilla 1.21.1 helper, pose-scaled around its center.
     * Blend + shader-color handling follows the {@code BossbarSkin} house pattern for
     * alpha-tinted blits.
     */
    static void drawHead(GuiGraphics guiGraphics, float centerX, float centerY, float scale,
            float alpha) {
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, centerY, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, Mth.clamp(alpha, 0.0F, 1.0F));
        PlayerFaceRenderer.draw(guiGraphics, UNIFORM_SKIN, -HEAD_SIZE / 2, -HEAD_SIZE / 2, HEAD_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        guiGraphics.pose().popPose();
    }
}
