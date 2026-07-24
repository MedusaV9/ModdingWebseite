package dev.projecteclipse.eclipse.client.skills;

import java.util.ArrayDeque;
import java.util.Locale;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.ChatFormatting;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientChatReceivedEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Skill proc presentation (WB-SKILLS): the anti-chat-spam half of the proc feedback trio.
 * {@code S2CSkillProcPayload} (cached as {@code ClientStateCache.lastSkillProcId}/
 * {@code lastSkillProcMagnitude}, consumed-and-cleared here each tick) drives a
 * toast-like mini line above the hotbar — "✦ Fortune's Echo — the vein yields double! ×2"
 * — that fades in with a 3px rise, holds ~2s and fades out; procs queue (cap
 * {@value #QUEUE_LIMIT}, oldest dropped) so bursts never overlap.
 *
 * <p><b>Chat line (optional, client-gated):</b> the server also sends its own clickable
 * chat line for procs ({@code SkillPerks.sendProcFeedback}, opt-out {@code /skills
 * procmsg off} — a SERVER-side flag). This class intercepts that line via
 * {@link ClientChatReceivedEvent.System} (matched by its
 * {@code message.eclipse.skill.proc.*} translatable key, overlay/actionbar messages
 * ignored): with {@code procMessages=false} it is cancelled (no chat spam, toast still
 * plays), otherwise it is restyled in place with the [hide] suffix re-pointed at the
 * CLIENT command {@code /eclipse-ui procs off} ({@code SkillClientCommands}) so the click
 * toggles the {@code procMessages} client config — NeoForge routes RUN_COMMAND clicks
 * through {@code ClientCommandHandler} first, verified against this tree's patched
 * {@code ClientPacketListener}.</p>
 *
 * <p>Edge case (accepted): two payloads landing within one client tick collapse into one
 * toast — the cache holds only the latest proc and carries no sequence counter
 * ({@code network/**} is frozen). Layer is F1-hidden and cutscene-suppressed via the
 * letterbox hook; self-registered because {@code EclipseGuiLayers} is frozen this wave.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SkillProcToast {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_proc_toast");

    private static final String PROC_KEY_PREFIX = "message.eclipse.skill.proc.";
    private static final String DISABLE_KEY = "message.eclipse.skill.proc.disable";
    /** Toast baseline above the hotbar: below the actionbar (-68), above the armor row (-49). */
    private static final int BOTTOM_OFFSET = 59;
    private static final int IN_TICKS = 5;
    private static final int HOLD_TICKS = 36;
    private static final int OUT_TICKS = 8;
    private static final int TOTAL_TICKS = IN_TICKS + HOLD_TICKS + OUT_TICKS;
    private static final int RISE_PX = 3;
    private static final int QUEUE_LIMIT = 4;

    private record Proc(String procId, float magnitude) {}

    // Client tick thread only.
    private static final ArrayDeque<Proc> QUEUE = new ArrayDeque<>();
    @Nullable
    private static Proc active;
    private static int ticks;

    private SkillProcToast() {}

    /** Mod-bus layer registration (nested, {@code SkillKeybind.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAbove(VanillaGuiLayers.BOSS_OVERLAY, LAYER_ID, SkillProcToast::render);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            active = null;
            ClientStateCache.lastSkillProcId = "";
            ClientStateCache.lastSkillProcMagnitude = 0.0F;
            return;
        }

        // Consume-and-clear the payload marker (the handler only stores the latest proc).
        String procId = ClientStateCache.lastSkillProcId;
        if (!procId.isEmpty()) {
            ClientStateCache.lastSkillProcId = "";
            float magnitude = ClientStateCache.lastSkillProcMagnitude;
            ClientStateCache.lastSkillProcMagnitude = 0.0F;
            if (QUEUE.size() >= QUEUE_LIMIT) {
                QUEUE.pollFirst(); // oldest toast is the least interesting one
            }
            QUEUE.addLast(new Proc(procId, magnitude));
        }

        if (minecraft.isPaused()) {
            return; // freeze the active toast; the queue stays intact
        }
        if (active != null && ++ticks > TOTAL_TICKS) {
            active = null;
        }
        if (active == null && !QUEUE.isEmpty()) {
            active = QUEUE.pollFirst();
            ticks = 0;
        }
    }

    /** GUI layer body (self-registered above the boss overlay). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        Proc proc = active;
        if (proc == null || minecraft.options.hideGui) {
            return;
        }
        float t = ticks + deltaTracker.getGameTimeDeltaPartialTick(true);
        boolean reduced = EclipseClientConfig.reducedFx();

        float alpha;
        if (t < IN_TICKS) {
            alpha = reduced ? 1.0F : easeOutCubic(t / IN_TICKS);
        } else if (t <= IN_TICKS + HOLD_TICKS) {
            alpha = 1.0F;
        } else {
            alpha = 1.0F - easeOutCubic((t - IN_TICKS - HOLD_TICKS) / OUT_TICKS);
        }
        alpha = Mth.clamp(alpha, 0.0F, 1.0F);
        if (alpha <= 0.04F) {
            return; // fill() alpha-floor guard AND skips the invisible first frame
        }
        int rise = reduced ? 0 : Math.round((1.0F - easeOutCubic(Math.min(1.0F, t / IN_TICKS))) * RISE_PX);

        Font font = minecraft.font;
        String star = "✦ ";
        String body = toastText(proc);
        int starWidth = font.width(star);
        int width = starWidth + font.width(body);
        int x = (guiGraphics.guiWidth() - width) / 2;
        int y = guiGraphics.guiHeight() - BOTTOM_OFFSET + rise;

        // Quiet backdrop pill so the line reads over bright terrain (no hard panel).
        guiGraphics.fill(x - 5, y - 3, x + width + 5, y + font.lineHeight + 2,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, alpha * 0.7F));
        guiGraphics.drawString(font, star, x, y, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        guiGraphics.drawString(font, body, x + starWidth, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
    }

    /** Toast body: the proc's shipped lang line + a "×2"-style magnitude suffix. */
    private static String toastText(Proc proc) {
        String key = PROC_KEY_PREFIX + proc.procId();
        String name = EclipseLang.hasKey(key)
                ? EclipseLang.trString(key)
                : proc.procId().replace('_', ' '); // unknown future proc id — degrade readably
        float magnitude = proc.magnitude();
        if (magnitude > 0.0F && Math.abs(magnitude - 1.0F) > 0.001F) {
            String number = magnitude == Math.floor(magnitude)
                    ? Integer.toString((int) magnitude)
                    : String.format(Locale.ROOT, "%.1f", magnitude);
            return name + " " + EclipseLang.trString("gui.eclipse.skills.proc_mag", number);
        }
        return name;
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }

    // ------------------------------------------------------------------
    // Chat line: client-side gate + click-off re-pointing
    // ------------------------------------------------------------------

    @SubscribeEvent
    static void onSystemChat(ClientChatReceivedEvent.System event) {
        if (event.isOverlay()) {
            return; // actionbar lines (buy results, /skills info) are not proc chat
        }
        String procKey = findProcKey(event.getMessage());
        if (procKey == null) {
            return;
        }
        if (!EclipseClientConfig.procMessages()) {
            event.setCanceled(true); // toast already covers it — no chat spam
            return;
        }
        event.setMessage(buildChatLine(procKey));
    }

    /**
     * The re-styled proc chat line: same shape as the server's ({@code [✦] <proc> [hide]})
     * but with the [hide] click running the CLIENT command that flips {@code procMessages}
     * — one click mutes proc chat on this client without touching the server-side flag.
     */
    private static MutableComponent buildChatLine(String procKey) {
        return Component.literal("[✦] ").withStyle(ChatFormatting.DARK_PURPLE)
                .append(Component.translatable(procKey).withStyle(ChatFormatting.LIGHT_PURPLE))
                .append(Component.literal(" "))
                .append(Component.translatable(DISABLE_KEY)
                        .withStyle(style -> style
                                .withColor(ChatFormatting.DARK_GRAY)
                                .withUnderlined(true)
                                .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND,
                                        "/eclipse-ui procs off"))
                                .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                        EclipseLang.tr("gui.eclipse.skills.proc_off_tip")))));
    }

    /**
     * First {@code message.eclipse.skill.proc.<id>} translatable key in the component tree
     * (the [hide] suffix's {@code .disable} key doesn't count), or {@code null} when the
     * message is not a proc line. Matching by key keeps this robust against restyling.
     */
    @Nullable
    private static String findProcKey(Component component) {
        if (component.getContents() instanceof TranslatableContents contents
                && contents.getKey().startsWith(PROC_KEY_PREFIX)
                && !contents.getKey().equals(DISABLE_KEY)) {
            return contents.getKey();
        }
        for (Component sibling : component.getSiblings()) {
            String key = findProcKey(sibling);
            if (key != null) {
                return key;
            }
        }
        return null;
    }
}
