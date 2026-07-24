package dev.projecteclipse.eclipse.devtools;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.border.SoftBorder;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * {@code /eclipse timeline} (W14, {@code docs/ideas/05_systems.md} §3): a source-only dump of
 * the whole event timeline state — day, altar level, per-dimension stage/ring radius/growth
 * cursor, the phase schedule ({@link PhaseScheduler}), soft border radii, the night event and
 * boss flags, per-player freeze/invuln/cutscene-ACK state, and the
 * {@link FreezeService#recentWatchdogEvents} ring buffer. Read-only: pure getters, no state
 * changes, v1 {@code /eclipse status} output style.
 */
public final class TimelineInspector {
    private TimelineInspector() {}

    /** All inspector lines, ready for {@code sendSuccess} one by one. */
    public static List<String> lines(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        List<String> lines = new ArrayList<>();

        lines.add("=== Eclipse timeline ===");
        lines.add("Day: " + state.getDay() + " | Altar level: " + state.getAltarLevel()
                + " | Start event done: " + state.isStartEventDone());
        lines.add("Phase schedule: " + PhaseScheduler.describe(server)
                + (state.getNextPhaseEpochMillis() != 0L
                        ? " -> day " + (state.getDay() + 1) : ""));

        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            int stage = state.getWorldStage(profile);
            StringBuilder line = new StringBuilder("Stage ").append(profile.name()).append(": ")
                    .append(stage).append("/").append(WorldStageService.maxStage(profile))
                    .append(" (radius ").append(StageRadii.radius(profile, stage)).append(")")
                    .append(" | soft border r=").append(String.format(Locale.ROOT, "%.1f",
                            SoftBorder.radius(server, profile)));
            String sweep = RingGrowthService.progressLine(profile);
            if (sweep != null) {
                line.append(" | sweeping: ").append(sweep);
            } else if (state.hasGrowthCursor() && profile.name().equals(state.getGrowthDimension())) {
                line.append(" | growth cursor ").append(state.getGrowthCursor());
            }
            int lastLoaded = state.getLastLoadedStage(profile);
            if (lastLoaded >= 0) {
                line.append(" | last loaded snapshot ").append(lastLoaded);
            }
            lines.add(line.toString());
        }

        lines.add("Night event: " + state.getActiveNightEvent()
                + (EclipseWorldState.NIGHT_EVENT_NONE.equals(state.getActiveNightEvent())
                        ? "" : " (day " + state.getNightEventDay() + ")")
                + " | Herald defeated: " + state.isHeraldDefeated()
                + " | Ferryman defeated: " + state.isFerrymanDefeated());

        List<ServerPlayer> online = server.getPlayerList().getPlayers();
        lines.add("Players (" + online.size() + ") — freeze / invuln / cutscene:");
        for (ServerPlayer player : online) {
            String cutscene = CutsceneService.activePathId(player);
            StringBuilder line = new StringBuilder(" - ").append(player.getScoreboardName()).append(": ")
                    .append(FreezeService.isFrozen(player) ? "FROZEN" : "free");
            if (FreezeService.isInvulnerableOnly(player)) {
                line.append(", INVULN (").append(FreezeService.invulnTicksRemaining(player))
                        .append("t left)");
            }
            line.append(cutscene != null
                    ? ", cutscene '" + cutscene + "' (awaiting finish ACK)" : ", no cutscene");
            lines.add(line.toString());
        }

        List<String> watchdog = FreezeService.recentWatchdogEvents();
        lines.add("Watchdog events since boot (" + watchdog.size() + "):");
        if (watchdog.isEmpty()) {
            lines.add(" - none");
        } else {
            for (String event : watchdog) {
                lines.add(" - " + event);
            }
        }
        return lines;
    }
}
