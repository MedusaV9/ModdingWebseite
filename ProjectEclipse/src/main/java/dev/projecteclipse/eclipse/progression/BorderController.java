package dev.projecteclipse.eclipse.progression;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.border.SoftBorder;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.border.WorldBorder;

/**
 * Owner of the VANILLA world border, which since worker 7 is only a hidden fail-safe: it
 * always sits at {@code overworld soft ring + }{@value SoftBorder#FAILSAFE_MARGIN} blocks
 * (warning 0, damage 0), centered on the ring center, and its visuals are cancelled
 * client-side by {@code client.mixin.LevelRendererMixin}. The authoritative playable
 * boundary is the circular {@link SoftBorder}.
 *
 * <p>The v1 {@link #setBorder} API keeps working for legacy callers but is repointed: the
 * given vanilla-style SIZE (diameter) becomes an overworld ring radius of {@code size / 2}.
 * Startup enforcement moved into {@code SoftBorder.onServerStarted}, which calls
 * {@link #applyFailsafe} after deriving the ring radius.</p>
 */
public final class BorderController {
    private BorderController() {}

    /**
     * v1-compatible entry point, repointed to the ring API: sets the OVERWORLD soft ring to
     * a radius of {@code size / 2} over {@code ms} milliseconds ({@code ms <= 0} snaps).
     * {@code SoftBorder.setRing} moves the vanilla failsafe along and persists everything.
     */
    public static void setBorder(MinecraftServer server, double size, long ms) {
        SoftBorder.setRing(server, DiscProfile.OVERWORLD, size / 2.0D, ms);
    }

    /**
     * Places the vanilla failsafe border at {@code ringRadius + }{@value SoftBorder#FAILSAFE_MARGIN}
     * (warning 0/0, damage 0), centered on the persisted ring center. The failsafe diameter
     * is persisted in the legacy {@link EclipseWorldState#setBorderSize} field for status
     * displays. Called by {@link SoftBorder} only.
     *
     * <p><b>Always snaps</b> (plans_v5 C6): the failsafe's wall is hidden client-side
     * ({@code LevelRendererMixin}), so a {@code lerpSizeBetween} bought nothing visually —
     * but vanilla arms the red GUI vignette during ANY lerp at
     * {@code max(warningBlocks, min(lerpSpeed × warningTime, |target − size|))}, and the
     * old code never zeroed {@code warningTime} (vanilla default 15 s, persisted in
     * level.dat): the intro's huge scripted resize covered the whole map in a stuck red
     * frame until the lerp completed. Every resize now takes the snap branch ({@code ms}
     * is kept for call-site compatibility/logging only) and both warning knobs are zeroed,
     * so the vignette can structurally never arm. The paced, player-facing growth remains
     * the soft ring's job.</p>
     */
    public static void applyFailsafe(MinecraftServer server, double ringRadius, long ms) {
        ServerLevel overworld = server.overworld();
        WorldBorder border = overworld.getWorldBorder();
        EclipseWorldState state = EclipseWorldState.get(server);
        border.setCenter(state.getBorderCenterX(), state.getBorderCenterZ());
        double size = 2.0D * (Math.max(0.0D, ringRadius) + SoftBorder.FAILSAFE_MARGIN);
        border.setSize(size);
        border.setWarningBlocks(0);
        border.setWarningTime(0);
        border.setDamagePerBlock(0.0D);
        state.setBorderSize(size);
        EclipseMod.LOGGER.info("Vanilla failsafe border snapped to {} (ring {} + {}; requested pace {} ms — failsafe always snaps)",
                size, String.format(java.util.Locale.ROOT, "%.1f", ringRadius),
                SoftBorder.FAILSAFE_MARGIN, ms);
    }

    /**
     * Belt-and-suspenders red-vignette clear (plans_v5 C6): re-zeroes the failsafe border's
     * warning distance AND warning time. Worlds saved before the {@code setWarningTime(0)}
     * fix persist the vanilla 15 s default in level.dat, and a pre-fix lerp could still be
     * in flight — {@code CutsceneService} calls this whenever a cutscene session ends, so
     * no player ever keeps a red frame past a cutscene. No-ops (and sends no border
     * packets) when both knobs are already 0.
     */
    public static void clearWarningVisuals(MinecraftServer server) {
        WorldBorder border = server.overworld().getWorldBorder();
        if (border.getWarningBlocks() != 0) {
            border.setWarningBlocks(0);
        }
        if (border.getWarningTime() != 0) {
            border.setWarningTime(0);
        }
    }
}
