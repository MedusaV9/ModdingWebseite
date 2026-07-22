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
     * (warning 0, damage 0), centered on the persisted ring center, moving over {@code ms}
     * milliseconds ({@code <= 0} snaps). The failsafe diameter is persisted in the legacy
     * {@link EclipseWorldState#setBorderSize} field for status displays. Called by
     * {@link SoftBorder} only.
     */
    public static void applyFailsafe(MinecraftServer server, double ringRadius, long ms) {
        ServerLevel overworld = server.overworld();
        WorldBorder border = overworld.getWorldBorder();
        EclipseWorldState state = EclipseWorldState.get(server);
        border.setCenter(state.getBorderCenterX(), state.getBorderCenterZ());
        double size = 2.0D * (Math.max(0.0D, ringRadius) + SoftBorder.FAILSAFE_MARGIN);
        if (ms <= 0L) {
            border.setSize(size);
        } else {
            border.lerpSizeBetween(border.getSize(), size, ms);
        }
        border.setWarningBlocks(0);
        border.setDamagePerBlock(0.0D);
        state.setBorderSize(size);
        EclipseMod.LOGGER.info("Vanilla failsafe border set to {} (ring {} + {}) over {} ms",
                size, String.format(java.util.Locale.ROOT, "%.1f", ringRadius),
                SoftBorder.FAILSAFE_MARGIN, ms);
    }
}
