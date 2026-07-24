package dev.projecteclipse.eclipse.client.contracts;

import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.math.Axis;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.contracts.ContractPayloads;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.multiplayer.PlayerInfo;
import net.minecraft.client.resources.PlayerSkin;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.world.level.block.entity.SkullBlockEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;

/**
 * The contract reveal ceremony + window chrome (IDEA-20 #2/#4/#9), self-registered as its
 * own GUI layer (the {@code AwardsOverlay} pattern — one {@code @EventBusSubscriber} class
 * carries the MOD-bus {@link RegisterGuiLayersEvent} and the game-bus tick; no shared-file
 * edit).
 *
 * <p><b>Hunter ceremony:</b> a strip of identical uniform heads decelerates (replicated
 * roulette physics, {@link ContractRouletteStrip}) and the landing head resolves into the
 * target's REAL face — fetched via {@code SkinManager} from the UUID, which bypasses the
 * uniform-skin entity mixin by construction — then a blood-red X stamps over it with a
 * screen kick, and the oath types out. Face only, never a name. Falls back to the uniform
 * face while (or if) the skin lookup is unresolved.</p>
 *
 * <p><b>Target ceremony:</b> "DU WIRST GEJAGT" — no hunter identity, deliberately
 * IDENTICAL for real targets and PRANK rounds. While the window runs, all players get a
 * subtle pulsing vignette + a top-right mini-marker (hunters keep the small X-stamped
 * face). Private resolution beats (fulfilled / lapsed / survived / prank exhale /
 * withdrawn) come in via {@link ContractPayloads.S2CContractResolvePayload}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ContractRevealOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "contract_reveal");

    // ceremony stage lengths (ticks)
    private static final int VEIL_TICKS = 10;
    private static final int SPIN_TICKS = 80;
    private static final int RESOLVE_TICKS = 14;
    private static final int STAMP_TICKS = 16;
    private static final int HOLD_TICKS = 40;
    private static final int FADE_TICKS = 20;

    private static final int RED = 0xFFE03040;
    private static final int DEEP_RED = 0xFFB01020;

    /** What the active ceremony is showing. */
    private enum Show {
        NONE, HUNTER_REVEAL, TARGET_REVEAL,
        FULFILLED, LAPSED, SURVIVED, PRANK_REVEAL, WITHDRAWN
    }

    private enum Stage {
        VEIL, SPIN, RESOLVE, STAMP, TEXT, HOLD, FADE
    }

    // --- ceremony state (client thread) ---
    private static Show show = Show.NONE;
    private static Stage stage = Stage.VEIL;
    private static int stageTicks;
    @Nullable
    private static ContractRouletteStrip strip;
    @Nullable
    private static Typer typer;
    @Nullable
    private static Typer subTyper;
    private static int windowMinutesShown = 30;

    // --- role/window state (survives the ceremony while the window runs) ---
    private static byte role;
    @Nullable
    private static UUID targetUuid;
    /** Set from skin-loader threads; render thread falls back to the uniform face while null. */
    @Nullable
    private static volatile PlayerSkin resolvedSkin;

    private ContractRevealOverlay() {}

    // ================================================================== payload entry points

    /** {@link ContractPayloads.S2CContractRevealPayload} (client main thread). */
    public static void handleReveal(ContractPayloads.S2CContractRevealPayload payload) {
        role = payload.role();
        windowMinutesShown = Math.max(1, payload.windowTicks() / (20 * 60));
        if (payload.role() == ContractPayloads.ROLE_HUNTER) {
            targetUuid = payload.targetUuid();
            resolveFace(payload.targetUuid());
            if (!payload.replay()) {
                startCeremony(Show.HUNTER_REVEAL);
            }
        } else {
            targetUuid = null;
            resolvedSkin = null;
            if (!payload.replay()) {
                startCeremony(Show.TARGET_REVEAL);
            }
        }
    }

    /** {@link ContractPayloads.S2CContractResolvePayload} (client main thread). */
    public static void handleResolve(ContractPayloads.S2CContractResolvePayload payload) {
        switch (payload.kind()) {
            case ContractPayloads.RESOLVE_FULFILLED -> startCeremony(Show.FULFILLED);
            case ContractPayloads.RESOLVE_LAPSED -> startCeremony(Show.LAPSED);
            case ContractPayloads.RESOLVE_SURVIVED -> startCeremony(Show.SURVIVED);
            case ContractPayloads.RESOLVE_PRANK_REVEAL -> startCeremony(Show.PRANK_REVEAL);
            case ContractPayloads.RESOLVE_WITHDRAWN -> startCeremony(Show.WITHDRAWN);
            default -> { /* unknown kind: ignore (forward-compat) */ }
        }
    }

    /** Window flag edge from {@link ContractClientState} (client main thread). */
    public static void onWindowChanged(boolean active) {
        if (!active && (show == Show.HUNTER_REVEAL || show == Show.TARGET_REVEAL)) {
            // The window closed under a running reveal (force-stop): cut the ceremony.
            reset(false);
        }
        if (!active) {
            role = 0;
        }
    }

    // ================================================================== ceremony state machine

    private static void startCeremony(Show kind) {
        show = kind;
        stageTicks = 0;
        typer = null;
        subTyper = null;
        boolean reduced = EclipseClientConfig.reducedFx();
        if (kind == Show.HUNTER_REVEAL) {
            strip = new ContractRouletteStrip(reduced ? 0 : SPIN_TICKS);
            stage = Stage.VEIL;
        } else {
            strip = null;
            stage = Stage.VEIL;
        }
    }

    private static void reset(boolean keepRole) {
        show = Show.NONE;
        stage = Stage.VEIL;
        stageTicks = 0;
        strip = null;
        typer = null;
        subTyper = null;
        if (!keepRole) {
            role = 0;
            targetUuid = null;
            resolvedSkin = null;
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            reset(false);
            return;
        }
        if (minecraft.isPaused() || show == Show.NONE) {
            return;
        }
        stageTicks++;
        switch (show) {
            case HUNTER_REVEAL -> tickHunterReveal();
            case TARGET_REVEAL -> tickTextCeremony(
                    "gui.eclipse.contract.hunted", "gui.eclipse.contract.hunted.sub", 8);
            case FULFILLED -> tickTextCeremony(null, "gui.eclipse.contract.fulfilled.sub", 6);
            case LAPSED -> tickTextCeremony(null, "gui.eclipse.contract.lapsed.sub", 6);
            case SURVIVED -> tickTextCeremony(null, "gui.eclipse.contract.survived.sub", 6);
            case PRANK_REVEAL -> tickTextCeremony(null, "gui.eclipse.contract.prank.sub", 10);
            case WITHDRAWN -> tickTextCeremony(null, "gui.eclipse.contract.withdrawn.sub", 6);
            default -> { }
        }
    }

    private static void tickHunterReveal() {
        switch (stage) {
            case VEIL -> {
                if (stageTicks >= VEIL_TICKS) {
                    advance(Stage.SPIN);
                }
            }
            case SPIN -> {
                if (strip != null) {
                    int passes = strip.tick();
                    if (passes > 0) {
                        UiSounds.rouletteTick(ContractRouletteStrip.tickPitch(strip.progress()));
                    }
                    if (strip.done()) {
                        advance(Stage.RESOLVE);
                    }
                } else {
                    advance(Stage.RESOLVE);
                }
            }
            case RESOLVE -> {
                if (stageTicks >= RESOLVE_TICKS) {
                    advance(Stage.STAMP);
                    playUi(SoundEvents.ANVIL_LAND, 0.55F, 0.8F);
                    playUi(SoundEvents.BELL_RESONATE, 0.5F, 0.6F);
                }
            }
            case STAMP -> {
                if (stageTicks >= STAMP_TICKS) {
                    advance(Stage.TEXT);
                    typer = new Typer(EclipseLang.trString(
                            "gui.eclipse.contract.oath", windowMinutesShown));
                }
            }
            case TEXT -> {
                if (typer == null || typer.tickDone()) {
                    advance(Stage.HOLD);
                }
            }
            case HOLD -> {
                if (stageTicks >= HOLD_TICKS) {
                    advance(Stage.FADE);
                }
            }
            case FADE -> {
                if (stageTicks >= FADE_TICKS) {
                    reset(true); // ceremony over; role + face persist for the mini-marker
                }
            }
            default -> { }
        }
    }

    /** Shared shape for every pure-text ceremony (target warning + resolution beats). */
    private static void tickTextCeremony(@Nullable String titleKey, String subKey, int veilTicks) {
        switch (stage) {
            case VEIL -> {
                if (stageTicks >= veilTicks) {
                    advance(Stage.TEXT);
                    typer = titleKey != null ? new Typer(EclipseLang.trString(titleKey)) : null;
                    subTyper = new Typer(EclipseLang.trString(subKey));
                    if (show == Show.PRANK_REVEAL) {
                        playUi(SoundEvents.AMETHYST_BLOCK_CHIME, 0.8F, 0.7F);
                    }
                }
            }
            case TEXT -> {
                boolean titleDone = typer == null || typer.tickDone();
                if (titleDone && (subTyper == null || subTyper.tickDone())) {
                    advance(Stage.HOLD);
                }
            }
            case HOLD -> {
                if (stageTicks >= HOLD_TICKS + (show == Show.PRANK_REVEAL ? 20 : 0)) {
                    advance(Stage.FADE);
                }
            }
            case FADE -> {
                if (stageTicks >= FADE_TICKS) {
                    boolean keepRole = show == Show.TARGET_REVEAL;
                    reset(keepRole);
                }
            }
            default -> { }
        }
    }

    private static void advance(Stage next) {
        stage = next;
        stageTicks = 0;
    }

    // ================================================================== face resolution

    /**
     * UUID → real face, hunter-only: online targets resolve through the connection's
     * {@code PlayerInfo} profile; otherwise the profile is fetched by UUID via
     * {@code SkullBlockEntity.fetchGameProfile}. Both funnel into
     * {@code SkinManager.getOrLoad}; every failure path simply leaves the uniform face.
     */
    private static void resolveFace(UUID uuid) {
        resolvedSkin = null;
        Minecraft minecraft = Minecraft.getInstance();
        try {
            PlayerInfo info = minecraft.getConnection() != null
                    ? minecraft.getConnection().getPlayerInfo(uuid) : null;
            if (info != null) {
                minecraft.getSkinManager().getOrLoad(info.getProfile())
                        .thenAccept(skin -> resolvedSkin = skin);
                return;
            }
            SkullBlockEntity.fetchGameProfile(uuid).thenAccept(optional ->
                    optional.ifPresent(profile -> minecraft.getSkinManager().getOrLoad(profile)
                            .thenAccept(skin -> resolvedSkin = skin)));
        } catch (Exception e) {
            EclipseMod.LOGGER.debug("Contract face lookup failed for {} — uniform fallback", uuid, e);
        }
    }

    // ================================================================== rendering

    /** GUI layer body (self-registered below; hidden under F1 like the other overlays). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        float partialTick = deltaTracker.getGameTimeDeltaPartialTick(true);
        if (ContractClientState.windowActive()) {
            renderWindowVignette(guiGraphics, minecraft);
            if (show == Show.NONE) {
                renderMiniMarker(guiGraphics, minecraft);
            }
        }
        switch (show) {
            case HUNTER_REVEAL -> renderHunterReveal(guiGraphics, minecraft, partialTick);
            case TARGET_REVEAL -> renderTextCeremony(guiGraphics, minecraft, RED, true);
            case FULFILLED -> renderFaceBeat(guiGraphics, minecraft, true,
                    "gui.eclipse.contract.fulfilled");
            case LAPSED -> renderFaceBeat(guiGraphics, minecraft, false, null);
            case SURVIVED, WITHDRAWN -> renderTextCeremony(guiGraphics, minecraft,
                    EclipseUiTheme.ACCENT, false);
            case PRANK_REVEAL -> renderTextCeremony(guiGraphics, minecraft, RED, false);
            default -> { }
        }
    }

    private static float ceremonyAlpha() {
        if (stage == Stage.FADE) {
            return Mth.clamp(1.0F - stageTicks / (float) FADE_TICKS, 0.0F, 1.0F);
        }
        if (stage == Stage.VEIL) {
            return Mth.clamp(stageTicks / (float) VEIL_TICKS, 0.0F, 1.0F);
        }
        return 1.0F;
    }

    private static void renderHunterReveal(GuiGraphics guiGraphics, Minecraft minecraft,
            float partialTick) {
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        int centerX = width / 2;
        int centerY = height / 2 - 10;
        float alpha = ceremonyAlpha();

        // Screen kick while the X stamps (skipped under reducedFx).
        boolean kicking = stage == Stage.STAMP && !EclipseClientConfig.reducedFx();
        guiGraphics.pose().pushPose();
        if (kicking) {
            float decay = 1.0F - stageTicks / (float) STAMP_TICKS;
            float kick = 3.5F * decay;
            guiGraphics.pose().translate(
                    Mth.sin(stageTicks * 2.7F) * kick, Mth.cos(stageTicks * 3.1F) * kick, 0.0F);
        }

        guiGraphics.fill(0, 0, width, height, EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));

        boolean landed = stage != Stage.VEIL && stage != Stage.SPIN;
        if (strip != null) {
            int halfWidth = Math.min(140, width / 2 - 10);
            strip.render(guiGraphics, centerX, centerY, halfWidth, partialTick, alpha, landed);
        }

        if (landed) {
            // The landed slot: real face glitching in over the uniform one (RESOLVE), then
            // held under the X (STAMP and later).
            float faceScale = 1.25F;
            PlayerSkin skin = resolvedSkin;
            float resolveProgress = stage == Stage.RESOLVE
                    ? Mth.clamp(stageTicks / (float) RESOLVE_TICKS, 0.0F, 1.0F) : 1.0F;
            if (skin == null || resolveProgress < 1.0F) {
                ContractRouletteStrip.drawHead(guiGraphics, ContractRouletteStrip.UNIFORM_SKIN,
                        centerX, centerY, faceScale, alpha);
            }
            if (skin != null && resolveProgress > 0.0F) {
                drawSkinHead(guiGraphics, skin, centerX, centerY, faceScale, alpha * resolveProgress);
            }
            if (stage == Stage.RESOLVE) {
                String shimmer = GlitchText.scramble(6, 77);
                guiGraphics.drawString(minecraft.font, shimmer,
                        centerX - minecraft.font.width(shimmer) / 2,
                        centerY + ContractRouletteStrip.HEAD_SIZE / 2 + 6,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
            }
            if (stage != Stage.RESOLVE) {
                float stampProgress = stage == Stage.STAMP
                        ? Mth.clamp((stageTicks + partialTick) / STAMP_TICKS, 0.0F, 1.0F) : 1.0F;
                drawRedX(guiGraphics, centerX, centerY, 20, stampProgress, alpha);
            }
        }

        if ((stage == Stage.TEXT || stage == Stage.HOLD || stage == Stage.FADE) && typer != null) {
            typer.render(guiGraphics, centerX, centerY + 34,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        }
        String header = EclipseLang.trString("gui.eclipse.contract.header");
        guiGraphics.drawString(minecraft.font, header, centerX - minecraft.font.width(header) / 2,
                centerY - 44, EclipseUiTheme.withAlpha(DEEP_RED, alpha));

        guiGraphics.pose().popPose();
    }

    /** Post-window face beats for the hunter: solid X + "ERFÜLLT", or the crumble-to-uniform. */
    private static void renderFaceBeat(GuiGraphics guiGraphics, Minecraft minecraft,
            boolean fulfilled, @Nullable String stampKey) {
        int centerX = guiGraphics.guiWidth() / 2;
        int centerY = guiGraphics.guiHeight() / 2 - 10;
        float alpha = ceremonyAlpha();
        guiGraphics.fill(0, 0, guiGraphics.guiWidth(), guiGraphics.guiHeight(),
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha * 0.8F));

        PlayerSkin skin = resolvedSkin;
        if (fulfilled) {
            if (skin != null) {
                drawSkinHead(guiGraphics, skin, centerX, centerY, 1.25F, alpha);
            } else {
                ContractRouletteStrip.drawHead(guiGraphics, ContractRouletteStrip.UNIFORM_SKIN,
                        centerX, centerY, 1.25F, alpha);
            }
            drawRedX(guiGraphics, centerX, centerY, 20, 1.0F, alpha);
            if (stampKey != null) {
                String stamp = EclipseLang.trString(stampKey);
                guiGraphics.drawString(minecraft.font, stamp,
                        centerX - minecraft.font.width(stamp) / 2, centerY + 26,
                        EclipseUiTheme.withAlpha(RED, alpha));
            }
        } else {
            // Anonymity resealing itself: the real face fades back into the uniform one.
            float crumble = Mth.clamp((stageTicks + (stage == Stage.VEIL ? 0 : 20)) / 50.0F, 0.0F, 1.0F);
            ContractRouletteStrip.drawHead(guiGraphics, ContractRouletteStrip.UNIFORM_SKIN,
                    centerX, centerY, 1.25F, alpha * crumble);
            if (skin != null && crumble < 1.0F) {
                drawSkinHead(guiGraphics, skin, centerX, centerY, 1.25F, alpha * (1.0F - crumble));
            }
        }
        if (subTyper != null) {
            subTyper.render(guiGraphics, centerX, centerY + 40,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        }
    }

    /** Target warning + text-only resolution beats. */
    private static void renderTextCeremony(GuiGraphics guiGraphics, Minecraft minecraft,
            int accent, boolean bigTitle) {
        int centerX = guiGraphics.guiWidth() / 2;
        int centerY = guiGraphics.guiHeight() / 2 - 10;
        float alpha = ceremonyAlpha();
        guiGraphics.fill(0, 0, guiGraphics.guiWidth(), guiGraphics.guiHeight(),
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha * 0.75F));
        if (typer != null && bigTitle) {
            guiGraphics.pose().pushPose();
            guiGraphics.pose().translate(centerX, centerY - 10, 0.0F);
            float pulse = 1.9F + 0.06F * Mth.sin(stageTicks * 0.35F);
            guiGraphics.pose().scale(pulse, pulse, 1.0F);
            typer.render(guiGraphics, 0, 0, EclipseUiTheme.withAlpha(accent, alpha));
            guiGraphics.pose().popPose();
        } else if (typer != null) {
            typer.render(guiGraphics, centerX, centerY - 12, EclipseUiTheme.withAlpha(accent, alpha));
        }
        if (subTyper != null) {
            subTyper.render(guiGraphics, centerX, centerY + (bigTitle ? 16 : 4),
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        }
    }

    /** Subtle pulsing edge tint every player sees while a window runs (never intrusive). */
    private static void renderWindowVignette(GuiGraphics guiGraphics, Minecraft minecraft) {
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        float pulse = 0.7F + 0.3F * Mth.sin(minecraft.gui.getGuiTicks() * Mth.PI / 30.0F);
        float alpha = 0.06F * pulse;
        int band = Math.max(10, height / 10);
        int solid = ((int) (alpha * 255.0F) << 24) | (RED & 0xFFFFFF);
        int clear = RED & 0xFFFFFF;
        guiGraphics.fillGradient(0, 0, width, band, solid, clear);
        guiGraphics.fillGradient(0, height - band, width, height, clear, solid);
    }

    /** Top-right mini-marker: hunter keeps the small X-stamped face; everyone gets the clock. */
    private static void renderMiniMarker(GuiGraphics guiGraphics, Minecraft minecraft) {
        long remaining = ContractClientState.remainingMillis();
        long totalSeconds = remaining / 1000L;
        String clock = String.format(java.util.Locale.ROOT, "%02d:%02d",
                totalSeconds / 60L, totalSeconds % 60L);
        int right = guiGraphics.guiWidth() - 6;
        int y = 6;
        if (role == ContractPayloads.ROLE_HUNTER) {
            int faceSize = 12;
            int faceX = right - faceSize;
            PlayerSkin skin = resolvedSkin;
            if (skin != null) {
                drawSkinHead(guiGraphics, skin, faceX + faceSize / 2.0F, y + faceSize / 2.0F,
                        faceSize / (float) ContractRouletteStrip.HEAD_SIZE, 0.9F);
            } else {
                ContractRouletteStrip.drawHead(guiGraphics, ContractRouletteStrip.UNIFORM_SKIN,
                        faceX + faceSize / 2.0F, y + faceSize / 2.0F,
                        faceSize / (float) ContractRouletteStrip.HEAD_SIZE, 0.9F);
            }
            drawRedX(guiGraphics, faceX + faceSize / 2, y + faceSize / 2, faceSize / 2 + 1, 1.0F, 0.9F);
            guiGraphics.drawString(minecraft.font, clock,
                    faceX - minecraft.font.width(clock) - 3, y + 2, EclipseUiTheme.withAlpha(RED, 0.9F));
        } else if (role == ContractPayloads.ROLE_TARGET) {
            float pulse = 0.6F + 0.4F * Mth.sin(minecraft.gui.getGuiTicks() * Mth.PI / 12.0F);
            String label = EclipseLang.trString("gui.eclipse.contract.marker.hunted");
            int labelX = right - minecraft.font.width(label);
            guiGraphics.drawString(minecraft.font, label, labelX, y,
                    EclipseUiTheme.withAlpha(RED, 0.55F + 0.45F * pulse));
            guiGraphics.drawString(minecraft.font, clock, right - minecraft.font.width(clock), y + 11,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, 0.9F));
        } else {
            // Bystander: the blackout clock only — the window is public, the pair is not.
            guiGraphics.drawString(minecraft.font, clock, right - minecraft.font.width(clock), y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, 0.8F));
        }
    }

    // ------------------------------------------------------------------ draw helpers

    /** Real-skin face blit (PlayerSkin overload handles the 1.21 hat layer). */
    private static void drawSkinHead(GuiGraphics guiGraphics, PlayerSkin skin, float centerX,
            float centerY, float scale, float alpha) {
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, centerY, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        com.mojang.blaze3d.systems.RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, Mth.clamp(alpha, 0.0F, 1.0F));
        net.minecraft.client.gui.components.PlayerFaceRenderer.draw(guiGraphics, skin,
                -ContractRouletteStrip.HEAD_SIZE / 2, -ContractRouletteStrip.HEAD_SIZE / 2,
                ContractRouletteStrip.HEAD_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        com.mojang.blaze3d.systems.RenderSystem.disableBlend();
        guiGraphics.pose().popPose();
    }

    /**
     * Two diagonal blood-red swipes; {@code progress} animates stroke one then stroke two
     * (0..0.5 → first, 0.5..1 → second), the stamp reading of IDEA-20 #2.
     */
    private static void drawRedX(GuiGraphics guiGraphics, int centerX, int centerY, int halfSize,
            float progress, float alpha) {
        float first = Mth.clamp(progress * 2.0F, 0.0F, 1.0F);
        float second = Mth.clamp(progress * 2.0F - 1.0F, 0.0F, 1.0F);
        drawStroke(guiGraphics, centerX, centerY, halfSize, 45.0F, first, alpha);
        drawStroke(guiGraphics, centerX, centerY, halfSize, -45.0F, second, alpha);
    }

    private static void drawStroke(GuiGraphics guiGraphics, int centerX, int centerY, int halfSize,
            float degrees, float progress, float alpha) {
        if (progress <= 0.0F) {
            return;
        }
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, centerY, 0.0F);
        guiGraphics.pose().mulPose(Axis.ZP.rotationDegrees(degrees));
        int reach = (int) (halfSize * progress);
        int thickness = 2;
        guiGraphics.fill(-reach, -thickness, reach, thickness,
                EclipseUiTheme.withAlpha(RED, alpha));
        guiGraphics.fill(-reach, -1, reach, 1, EclipseUiTheme.withAlpha(DEEP_RED, alpha));
        guiGraphics.pose().popPose();
    }

    private static void playUi(net.minecraft.sounds.SoundEvent sound, float pitch, float volume) {
        Minecraft.getInstance().getSoundManager().play(
                SimpleSoundInstance.forUI(sound, pitch, volume));
    }

    // ================================================================== layer registration

    /** MOD-bus listener in the same class — FML auto-routes (the AwardsOverlay pattern). */
    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAboveAll(LAYER_ID, ContractRevealOverlay::render);
    }

    // ================================================================== typewriter

    /** Minimal 1-char/tick typer (the {@code client.hud.TypewriterLine} class is package-private). */
    private static final class Typer {
        private final String text;
        private int revealed;

        Typer(String text) {
            this.text = text;
        }

        /** Advances one tick; returns {@code true} once fully typed. */
        boolean tickDone() {
            if (revealed < text.length()) {
                revealed++;
                if (revealed % 2 == 0 || revealed == text.length()) {
                    UiSounds.typewriter(0.9F + 0.2F * (float) Math.random());
                }
            }
            return revealed >= text.length();
        }

        void render(GuiGraphics guiGraphics, int centerX, int y, int color) {
            Minecraft minecraft = Minecraft.getInstance();
            String shown = text.substring(0, revealed);
            if (revealed < text.length() && (minecraft.gui.getGuiTicks() / 3) % 2 == 0) {
                shown = shown + "_";
            }
            guiGraphics.drawString(minecraft.font, shown,
                    centerX - minecraft.font.width(text) / 2, y, color);
        }
    }
}
