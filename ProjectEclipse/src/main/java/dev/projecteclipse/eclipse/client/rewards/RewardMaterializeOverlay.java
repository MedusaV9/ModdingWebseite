package dev.projecteclipse.eclipse.client.rewards;

import java.util.ArrayDeque;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.network.rewards.RewardPayloads;
import dev.projecteclipse.eclipse.network.rewards.RewardPayloads.S2CRewardGrantPayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;

/**
 * W4-CEREMONY / IDEA-11 #1 — REWARD ITEM MATERIALIZATION: when the server confirms a
 * quest/award grant ({@link S2CRewardGrantPayload}), the reward stack visibly
 * <i>materializes</i> — rendered ~2.6× scale in the upper third, floating down toward the
 * hotbar on an ease-out curve while its name settles out of {@link GlitchText#scramble}
 * noise (the settled-prefix + scrambled-tail trick from {@code AwardsOverlay
 * .renderRewardLine}) with sparse {@code ACCENT_DEEP} flicker rects, then an absorb flash
 * + {@code ui.unlock_sting} as it lands. A carbon copy of the {@code LevelUpOverlay}
 * skeleton: ArrayDeque queue, {@code ClientTickEvent.Post} driver, self-registered
 * above-all GUI layer (never a Screen — input is never captured), F1 hides while state
 * keeps advancing, pause freezes, cutscene HUD suppression defers queued playback.
 *
 * <p><b>Calm variants:</b> {@code reducedFx} fades the stack in at its final position
 * (no descent, no scramble, no flicker). {@code replay=true} payloads (login delivery of
 * offline-queued rewards — the {@code AwardsOverlay} late-join rule) additionally skip
 * the sting so a returning player is not greeted by a fanfare barrage; multi-reward
 * logins play their calm cards one after another. Shard-only grants borrow the
 * {@code eclipse:umbral_shard} item as their stack visual. skill-XP-only rewards never
 * reach this overlay (the XP strip + {@code LevelUpOverlay} own that stage).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RewardMaterializeOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "reward_materialize");

    // --- timing (game ticks) ---
    private static final int FLOAT_TICKS = 30;
    private static final int FLASH_TICKS = 8;
    private static final int HOLD_TICKS = 18;
    private static final int FADE_TICKS = 8;
    /** Calm variant: fade-in at the final position replaces the descent. */
    private static final int CALM_IN_TICKS = 8;
    private static final int CALM_HOLD_TICKS = 34;
    /** Quiet gap between queued grants so bundles stay readable. */
    private static final int GAP_TICKS = 10;
    private static final int QUEUE_LIMIT = 4;

    private static final float SCALE_START = 2.6F;
    private static final float SCALE_LAND = 1.5F;

    /** One queued materialization; {@code calm} is latched at enqueue (replay) or start (reducedFx). */
    private record Grant(ItemStack stack, String label, boolean replay, int salt) {}

    // Client tick thread only.
    private static final ArrayDeque<Grant> QUEUE = new ArrayDeque<>();
    private static int nextSalt;
    /** Ticks into the active materialization; {@code -1} = idle. */
    private static int ticks = -1;
    private static Grant active;
    /** Latched per grant at start so a mid-flight settings flip cannot desync the phases. */
    private static boolean calm;

    private RewardMaterializeOverlay() {}

    /** Mod-bus layer registration (nested, {@code LevelUpOverlay.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAboveAll(LAYER_ID, RewardMaterializeOverlay::render);
        }
    }

    // ------------------------------------------------------------------ payload entry

    /** {@code RewardPayloads.handleRewardGrant} dispatch — client main thread. */
    public static void enqueue(S2CRewardGrantPayload payload) {
        if (Minecraft.getInstance().level == null) {
            return;
        }
        ItemStack stack = displayStack(payload);
        if (stack.isEmpty()) {
            return; // nothing resolvable to show (unknown ids and no shards)
        }
        while (QUEUE.size() >= QUEUE_LIMIT) {
            QUEUE.pollFirst(); // keep the NEWEST grants (LevelUpOverlay coalesce spirit)
        }
        QUEUE.addLast(new Grant(stack, buildLabel(payload, stack), payload.replay(), ++nextSalt));
    }

    /** First resolvable item entry, else the umbral-shard item for shard-only grants. */
    private static ItemStack displayStack(S2CRewardGrantPayload payload) {
        for (RewardPayloads.ItemEntry entry : payload.items()) {
            ResourceLocation id = ResourceLocation.tryParse(entry.itemId());
            Item item = id == null ? null : BuiltInRegistries.ITEM.getOptional(id).orElse(null);
            if (item != null && entry.count() > 0) {
                return new ItemStack(item, entry.count());
            }
        }
        if (payload.shards() > 0) {
            return new ItemStack(EclipseItems.UMBRAL_SHARD.get(), payload.shards());
        }
        return ItemStack.EMPTY;
    }

    /** "3× Vitae Shard · +2 more · 12 Umbral Shards" — locale-aware, no source names. */
    private static String buildLabel(S2CRewardGrantPayload payload, ItemStack stack) {
        StringBuilder label = new StringBuilder();
        boolean shardStandIn = payload.items().isEmpty();
        if (!shardStandIn) {
            if (stack.getCount() > 1) {
                label.append(stack.getCount()).append("× ");
            }
            label.append(stack.getHoverName().getString());
            int more = payload.items().size() - 1;
            if (more > 0) {
                label.append(" · ").append(EclipseLang.trString("gui.eclipse.reward.more", more));
            }
        }
        if (payload.shards() > 0) {
            if (label.length() > 0) {
                label.append(" · ");
            }
            label.append(EclipseLang.trString("gui.eclipse.reward.shards", payload.shards()));
        }
        return label.toString();
    }

    // ------------------------------------------------------------------ tick driver

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            ticks = -1;
            active = null;
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze mid-animation, queue intact
        }
        if (ticks >= 0) {
            ticks++;
            // Landing beat: absorb sting exactly once as the stack touches down (live grants
            // only — login replays stay silent by design).
            int landTick = calm ? CALM_IN_TICKS : FLOAT_TICKS;
            if (ticks == landTick && active != null && !active.replay()) {
                UiSounds.unlockSting();
            }
            if (ticks > totalTicks() + GAP_TICKS) {
                ticks = -1;
                active = null;
            }
        }
        // Cutscene flights defer playback (the layer render is cancelled anyway).
        if (ticks < 0 && !QUEUE.isEmpty() && !CameraDirector.isHudSuppressed()) {
            active = QUEUE.pollFirst();
            calm = active.replay() || EclipseClientConfig.reducedFx();
            ticks = 0;
        }
    }

    private static int totalTicks() {
        return calm ? CALM_IN_TICKS + CALM_HOLD_TICKS + FADE_TICKS
                : FLOAT_TICKS + HOLD_TICKS + FADE_TICKS;
    }

    // ------------------------------------------------------------------ rendering

    /** Above-all GUI layer body (self-registered; F1 hides, state keeps advancing). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        Grant grant = active;
        if (grant == null || ticks < 0 || ticks > totalTicks() || minecraft.options.hideGui) {
            return;
        }
        float t = ticks + (minecraft.isPaused() ? 0.0F
                : deltaTracker.getGameTimeDeltaPartialTick(true));
        int centerX = guiGraphics.guiWidth() / 2;
        int startY = guiGraphics.guiHeight() / 3;
        int landY = guiGraphics.guiHeight() - 58; // just above hotbar + xp bar

        float inTicks = calm ? CALM_IN_TICKS : FLOAT_TICKS;
        float holdEnd = inTicks + (calm ? CALM_HOLD_TICKS : HOLD_TICKS);
        float alpha;
        if (t < inTicks) {
            alpha = calm ? easeOutCubic(t / inTicks) : Mth.clamp(t / 4.0F, 0.0F, 1.0F);
        } else if (t <= holdEnd) {
            alpha = 1.0F;
        } else {
            alpha = 1.0F - easeOutCubic((t - holdEnd) / FADE_TICKS);
        }
        alpha = Mth.clamp(alpha, 0.0F, 1.0F);
        if (alpha <= 0.01F) {
            return;
        }

        float descent = calm ? 1.0F : easeOutCubic(Mth.clamp(t / inTicks, 0.0F, 1.0F));
        float itemY = calm ? landY : Mth.lerp(descent, startY, landY);
        float scale = calm ? SCALE_LAND : Mth.lerp(descent, SCALE_START, SCALE_LAND);

        // Absorb flash at touchdown (live variant only): expanding soft glow + hairline ring.
        if (!calm && t >= inTicks && t <= inTicks + FLASH_TICKS) {
            renderLandFlash(guiGraphics, centerX, landY, (t - inTicks) / FLASH_TICKS, alpha);
        }

        Font font = minecraft.font;
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, itemY, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        guiGraphics.renderItem(grant.stack(), -8, -8);
        guiGraphics.renderItemDecorations(font, grant.stack(), -8, -8);
        guiGraphics.pose().popPose();

        renderLabel(guiGraphics, font, grant, centerX,
                (int) (itemY + 8.0F * scale) + 6, t, inTicks, alpha);
    }

    /**
     * Name line riding under the stack: settled prefix in plain ACCENT, unsettled tail as a
     * re-rolling deep-purple scramble, sparse flicker rects while settling (live variant;
     * the calm variant renders the settled line only).
     */
    private static void renderLabel(GuiGraphics guiGraphics, Font font, Grant grant, int centerX,
            int y, float t, float inTicks, float alpha) {
        String label = grant.label();
        if (label.isEmpty()) {
            return;
        }
        float settleProgress = calm ? 1.0F : Mth.clamp(t / inTicks, 0.0F, 1.0F);
        int settled = Math.min(label.length(), (int) (label.length() * settleProgress));
        String settledPart = label.substring(0, settled);
        String scrambled = settled < label.length()
                ? GlitchText.scramble(label.length() - settled, grant.salt() * 7 + 1)
                : "";
        String full = settledPart + scrambled;
        int x = centerX - font.width(full) / 2;
        guiGraphics.drawString(font, settledPart, x, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        if (!scrambled.isEmpty()) {
            guiGraphics.drawString(font, scrambled, x + font.width(settledPart), y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha));
            // Sparse ACCENT_DEEP flicker rects around the settling line (AwardsOverlay craft).
            int flickerSeed = ((int) t / 2) * 31 + grant.salt();
            for (int i = 0; i < 4; i++) {
                int hash = flickerSeed * 0x9E3779B9 + i * 0x85EBCA6B;
                int fx = centerX + (hash % 60);
                int fy = y + ((hash >> 8) % 10) - 2;
                int fw = 3 + ((hash >> 16) & 7);
                guiGraphics.fill(fx, fy, fx + fw, fy + 2,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP,
                                0.30F * alpha * (1.0F - settleProgress)));
            }
        }
    }

    /** Quiet absorb flash: two nested soft glow quads + an expanding 1px accent ring. */
    private static void renderLandFlash(GuiGraphics guiGraphics, int centerX, int centerY,
            float flashProgress, float alpha) {
        float grow = easeOutCubic(flashProgress);
        float fade = (1.0F - flashProgress) * alpha;
        int outer = (int) (10.0F + 22.0F * grow);
        int inner = (int) (6.0F + 14.0F * grow);
        guiGraphics.fill(centerX - outer, centerY - outer, centerX + outer, centerY + outer,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.10F * fade));
        guiGraphics.fill(centerX - inner, centerY - inner, centerX + inner, centerY + inner,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, 0.18F * fade));
        int ring = (int) (12.0F + 26.0F * grow);
        int ringColor = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, 0.55F * fade);
        guiGraphics.fill(centerX - ring, centerY - ring, centerX + ring, centerY - ring + 1, ringColor);
        guiGraphics.fill(centerX - ring, centerY + ring - 1, centerX + ring, centerY + ring, ringColor);
        guiGraphics.fill(centerX - ring, centerY - ring + 1, centerX - ring + 1, centerY + ring - 1, ringColor);
        guiGraphics.fill(centerX + ring - 1, centerY - ring + 1, centerX + ring, centerY + ring - 1, ringColor);
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
