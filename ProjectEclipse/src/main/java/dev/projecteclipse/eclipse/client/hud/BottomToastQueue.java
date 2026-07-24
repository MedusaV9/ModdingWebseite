package dev.projecteclipse.eclipse.client.hud;

import java.util.ArrayDeque;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * The ONE shared bottom-center toast lane (EVAL-DOPA-F #5 / DOPA-S-05): {@code
 * ShardGainToast} and {@code CollectionTierToast} used to run their own queues on
 * near-identical bottom offsets (82 vs 84, measured from different bases), so a shard pill
 * landing during a tier card rendered straight through it. Both now enqueue here — a single
 * renderer with {@value #MAX_VISIBLE} stacked slots, FIFO activation, oldest-dropped cap
 * {@value #QUEUE_LIMIT} — so simultaneous pills can never overlap: the second toast takes
 * the slot ABOVE the first ({@value #SLOT_SPACING} px spacing clears even a two-line card).
 *
 * <p>The whole stack sits one lane above {@code SkillProcToast} (59) and, while a reward
 * materialization is touching down (the same {@code RewardMaterializeOverlay
 * .isMaterializing()} signal that lifts the proc toast to 70), lifts a further
 * {@value #MATERIALIZE_LIFT} px so it also clears the LIFTED proc lane — the DOPA-S-05
 * "lifted proc under an active collection card" stack is gone too.</p>
 *
 * <p>Fade in / hold / fade out and the 3 px rise mirror the retired per-class renderers
 * (fade + rise suppressed under {@code reducedFx}); hold length is per-toast (a two-line
 * card holds longer than a one-line pill). Pause freezes active toasts and the queue.
 * Self-registered GUI layer ({@code SkillProcToast.Registrar} pattern); F1-hidden;
 * cutscene-suppressed via the letterbox whitelist like every non-whitelisted layer.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BottomToastQueue {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "bottom_toast_queue");

    /**
     * One toast in the shared bottom lane. Implementations draw their own pill/card
     * centered on {@code centerX} with the first text line's baseline at {@code y};
     * the queue owns timing, alpha, rise and slot placement.
     */
    public interface Toast {
        /** Full-alpha hold length in ticks (fade in/out ride on top of this). */
        int holdTicks();

        /** Called once when the toast becomes visible (activation sting hook). */
        default void onShow() {}

        void draw(GuiGraphics guiGraphics, Font font, int centerX, int y, float alpha);
    }

    /**
     * Base bottom offset of slot 0: clears the un-lifted skill-proc pill at 59 (a two-line
     * card's bottom lands at ≈ h−64 vs the proc's top at ≈ h−62).
     */
    private static final int BASE_BOTTOM_OFFSET = 86;
    /** Slot 1 sits this far above slot 0 — clears a two-line card in slot 0 with air. */
    private static final int SLOT_SPACING = 30;
    /**
     * Extra stack lift while a reward materialization is touching down — the proc toast
     * lifts to 70 for the same window, so the stack steps above it in lockstep.
     */
    private static final int MATERIALIZE_LIFT = 16;
    private static final int MAX_VISIBLE = 2;
    private static final int QUEUE_LIMIT = 6;
    private static final int IN_TICKS = 5;
    private static final int OUT_TICKS = 8;
    private static final int RISE_PX = 3;

    // Client tick thread only.
    private static final ArrayDeque<Toast> QUEUE = new ArrayDeque<>();
    private static final Toast[] SLOT = new Toast[MAX_VISIBLE];
    private static final int[] SLOT_TICKS = new int[MAX_VISIBLE];

    private BottomToastQueue() {}

    /** Mod-bus layer registration (nested, {@code SkillProcToast.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAbove(VanillaGuiLayers.BOSS_OVERLAY, LAYER_ID, BottomToastQueue::render);
        }
    }

    /** FIFO enqueue (client tick thread); the oldest queued toast drops past the cap. */
    public static void enqueue(Toast toast) {
        if (QUEUE.size() >= QUEUE_LIMIT) {
            QUEUE.pollFirst(); // oldest toast is the least interesting one
        }
        QUEUE.addLast(toast);
    }

    /** Logout/disconnect reset — queue and live slots drop together. */
    public static void reset() {
        QUEUE.clear();
        for (int s = 0; s < MAX_VISIBLE; s++) {
            SLOT[s] = null;
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze the active toasts; the queue stays intact
        }
        for (int s = 0; s < MAX_VISIBLE; s++) {
            Toast toast = SLOT[s];
            if (toast != null && ++SLOT_TICKS[s] > IN_TICKS + toast.holdTicks() + OUT_TICKS) {
                SLOT[s] = null;
            }
        }
        // FIFO activation into the lowest free slot; at most MAX_VISIBLE on screen.
        for (int s = 0; s < MAX_VISIBLE && !QUEUE.isEmpty(); s++) {
            if (SLOT[s] == null) {
                SLOT[s] = QUEUE.pollFirst();
                SLOT_TICKS[s] = 0;
                SLOT[s].onShow();
            }
        }
    }

    /** GUI layer body (self-registered above the boss overlay). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.options.hideGui) {
            return;
        }
        boolean reduced = EclipseClientConfig.reducedFx();
        int lift = dev.projecteclipse.eclipse.client.rewards.RewardMaterializeOverlay
                .isMaterializing() ? MATERIALIZE_LIFT : 0;
        Font font = minecraft.font;
        int centerX = guiGraphics.guiWidth() / 2;
        for (int s = 0; s < MAX_VISIBLE; s++) {
            Toast toast = SLOT[s];
            if (toast == null) {
                continue;
            }
            float t = SLOT_TICKS[s] + deltaTracker.getGameTimeDeltaPartialTick(true);
            int hold = toast.holdTicks();
            float alpha;
            if (t < IN_TICKS) {
                alpha = reduced ? 1.0F : easeOutCubic(t / IN_TICKS);
            } else if (t <= IN_TICKS + hold) {
                alpha = 1.0F;
            } else {
                alpha = 1.0F - easeOutCubic((t - IN_TICKS - hold) / OUT_TICKS);
            }
            alpha = Mth.clamp(alpha, 0.0F, 1.0F);
            if (alpha <= 0.04F) {
                continue; // fill() alpha-floor guard AND skips the invisible first frame
            }
            int rise = reduced ? 0
                    : Math.round((1.0F - easeOutCubic(Math.min(1.0F, t / IN_TICKS))) * RISE_PX);
            int y = guiGraphics.guiHeight() - (BASE_BOTTOM_OFFSET + s * SLOT_SPACING + lift) + rise;
            toast.draw(guiGraphics, font, centerX, y, alpha);
        }
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
