package dev.projecteclipse.eclipse.hearts.client;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.player.Player;

/**
 * Vanilla-exact health-row math (W4-HEARTS R1/R2), extracted from
 * {@code HeartBurstOverlay.heartPosition} and verified against the NeoForge-patched
 * {@code Gui.renderHealthLevel}/{@code renderHearts} so that {@link PurpleHeartsLayer}
 * (the replacement renderer) and {@link HeartBurstOverlay} (the shatter layer above it)
 * resolve <b>identical pixels</b> for every heart slot — multi-row compression, the
 * regen-wave −2px lift and the ≤4&nbsp;hp jitter included.
 *
 * <p>All entry points run after the health layer's {@code leftHeight} increment (both
 * callers render above {@code PLAYER_HEALTH}), so the row origin is reconstructed from
 * the public post-layer {@code Gui.leftHeight}. Single-slot lookups return a packed
 * {@code long} ({@link #x(long)}/{@link #y(long)}) — zero per-frame allocations.</p>
 *
 * <p><b>Jitter/reducedFx contract:</b> vanilla always jitters the row at
 * {@code health + absorption <= 4}. When the purple layer owns the row it honors the
 * {@code reducedFx} opt-out ({@link #jitterSuppressed()}); the burst overlay must use the
 * same predicate or shatters desync from the drawn hearts by 1px.</p>
 */
public final class HeartRowGeometry {
    /** Horizontal advance between heart slots (vanilla). */
    public static final int HEART_STEP_X = 8;
    /** Heart sprite edge in GUI px (vanilla). */
    public static final int HEART_SIZE = 9;
    /** Vanilla low-health threshold: jitter while {@code health + absorption <= 4}. */
    public static final int JITTER_HEALTH_THRESHOLD = 4;
    /** Vanilla jitter seed multiplier ({@code Gui.renderHealthLevel}). */
    public static final long JITTER_SEED_MULTIPLIER = 312871L;

    private static final RandomSource JITTER_RANDOM = RandomSource.create();

    private HeartRowGeometry() {}

    /** Left edge of the health row (vanilla {@code guiWidth / 2 - 91}). */
    public static int rowLeft(GuiGraphics guiGraphics) {
        return guiGraphics.guiWidth() / 2 - 91;
    }

    /**
     * Vanilla's {@code f}: the hp value the row is sized for — the max-health attribute
     * or, briefly after damage/heal, the still-displayed health if larger.
     */
    public static float rowMaxHealth(Player player, int displayHealth) {
        return Math.max((float) player.getAttributeValue(Attributes.MAX_HEALTH),
                (float) Math.max(displayHealth, Mth.ceil(player.getHealth())));
    }

    /** Health heart slots (vanilla {@code i = ceil(f / 2)}). */
    public static int healthSlots(float rowMaxHealth) {
        return Mth.ceil(rowMaxHealth / 2.0D);
    }

    /** Total slots including absorption (vanilla {@code i + j}). */
    public static int totalSlots(float rowMaxHealth, int absorption) {
        return healthSlots(rowMaxHealth) + Mth.ceil(absorption / 2.0D);
    }

    /** Row count (vanilla {@code l1 = ceil((f + absorption) / 2 / 10)}), never below 1. */
    public static int rows(float rowMaxHealth, int absorption) {
        return Math.max(1, Mth.ceil((rowMaxHealth + absorption) / 2.0F / 10.0F));
    }

    /** Vertical compression step between rows (vanilla {@code max(10 - (rows - 2), 3)}). */
    public static int rowStep(int rows) {
        return Math.max(10 - (rows - 2), 3);
    }

    /** The health layer's exact {@code leftHeight} increment ({@code (rows-1)*step + 10}). */
    public static int leftHeightIncrement(int rows) {
        return (rows - 1) * rowStep(rows) + 10;
    }

    /**
     * Vanilla regen-wave slot index for this frame ({@code tickCount % ceil(f + 5)}),
     * or {@code -1} when the player has no regeneration. Only slots below
     * {@link #healthSlots} are lifted by 2px.
     */
    public static int regenSlot(Minecraft minecraft, Player player, float rowMaxHealth) {
        return player.hasEffect(MobEffects.REGENERATION)
                ? minecraft.gui.getGuiTicks() % Mth.ceil(rowMaxHealth + 5.0F)
                : -1;
    }

    /** Whether the ≤4&nbsp;hp jitter applies this frame (vanilla threshold). */
    public static boolean jitterActive(Player player) {
        return Mth.ceil(player.getHealth()) + Mth.ceil(player.getAbsorptionAmount())
                <= JITTER_HEALTH_THRESHOLD;
    }

    /** Purple-row opt-out: {@code reducedFx} suppresses the jitter (never vanilla's own). */
    public static boolean jitterSuppressed() {
        return EclipseClientConfig.reducedFx();
    }

    /**
     * Screen position of one heart slot, packed as {@code (x << 32) | y} — read via
     * {@link #x(long)}/{@link #y(long)}. Reconstructs the pre-layer row origin from the
     * post-layer {@code Gui.leftHeight}, replays vanilla's descending jitter draws for
     * exact per-slot values, and applies the regen lift. {@code displayHealth} is the
     * caller's best knowledge of vanilla's displayed health (pass
     * {@code Mth.ceil(player.getHealth())} when no mirror is available).
     */
    public static long heartPosition(GuiGraphics guiGraphics, Minecraft minecraft,
            int index, int displayHealth, boolean suppressJitter) {
        Player player = minecraft.player;
        float rowMax = rowMaxHealth(player, displayHealth);
        int absorption = Mth.ceil(player.getAbsorptionAmount());
        int rows = rows(rowMax, absorption);
        int rowStep = rowStep(rows);

        int x = rowLeft(guiGraphics) + (index % 10) * HEART_STEP_X;
        int y = guiGraphics.guiHeight() - minecraft.gui.leftHeight
                + leftHeightIncrement(rows) - (index / 10) * rowStep;

        if (jitterActive(player)) {
            // Vanilla consumes one nextInt(2) per slot from the TOP slot downwards; replay
            // the draws so this slot gets exactly the value the row renderer applied.
            JITTER_RANDOM.setSeed(minecraft.gui.getGuiTicks() * JITTER_SEED_MULTIPLIER);
            int total = totalSlots(rowMax, absorption);
            for (int slot = total - 1; slot >= index; slot--) {
                int jitter = JITTER_RANDOM.nextInt(2);
                if (slot == index && !suppressJitter) {
                    y += jitter;
                }
            }
        }
        if (index < healthSlots(rowMax) && index == regenSlot(minecraft, player, rowMax)) {
            y -= 2;
        }
        return pack(x, y);
    }

    /** Packs a screen position; see {@link #x(long)}/{@link #y(long)}. */
    public static long pack(int x, int y) {
        return ((long) x << 32) | (y & 0xFFFFFFFFL);
    }

    /** X component of a packed {@link #heartPosition} result. */
    public static int x(long packed) {
        return (int) (packed >> 32);
    }

    /** Y component of a packed {@link #heartPosition} result. */
    public static int y(long packed) {
        return (int) packed;
    }
}
