package dev.projecteclipse.eclipse.devtools.dev;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutscenePaths;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.network.S2CMilestonesPayload;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * {@code /dev reload} orchestration (§2.12): per-target ✔/✖ feedback with exception summaries.
 */
public final class DevReload {
    private DevReload() {}

    public record ReloadLine(String label, boolean success, String detail) {}

    /** Static config reference table (handbook + DEV_COMMANDS.md). */
    private static final List<ConfigRefEntry> CONFIG_REFS = List.of(
            new ConfigRefEntry("general.json", "dev.eclipse.config.general", "dev.eclipse.config.layer.global", 1),
            new ConfigRefEntry("days.json", "dev.eclipse.config.days", "dev.eclipse.config.layer.global", 1),
            new ConfigRefEntry("milestones.json", "dev.eclipse.config.milestones", "dev.eclipse.config.layer.global", 1),
            new ConfigRefEntry("modgate.json", "dev.eclipse.config.modgate", "dev.eclipse.config.layer.global", 1),
            new ConfigRefEntry("anticheat.json", "dev.eclipse.config.anticheat", "dev.eclipse.config.layer.global", 1),
            new ConfigRefEntry("stages.json", "dev.eclipse.config.stages", "dev.eclipse.config.layer.global", 1),
            new ConfigRefEntry("cutscenes/", "dev.eclipse.config.cutscenes", "dev.eclipse.config.layer.global", 2),
            new ConfigRefEntry("realtime.json", "dev.eclipse.config.realtime", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("goals.json", "dev.eclipse.config.goals", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("quests.json", "dev.eclipse.config.quests", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("skills.json", "dev.eclipse.config.skills", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("skilltree.json", "dev.eclipse.config.skilltree", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("awards.json", "dev.eclipse.config.awards", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("offering_values.json", "dev.eclipse.config.offerings", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("recipegate.json", "dev.eclipse.config.recipegate", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("glitch.json", "dev.eclipse.config.glitch", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("buffs.json", "dev.eclipse.config.buffs", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("protection.json", "dev.eclipse.config.protection", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("analytics.json", "dev.eclipse.config.analytics", "dev.eclipse.config.layer.global", 3),
            new ConfigRefEntry("xboxevent.json", "dev.eclipse.config.xboxevent", "dev.eclipse.config.layer.global", 4),
            new ConfigRefEntry("music.json", "dev.eclipse.config.music", "dev.eclipse.config.layer.global", 4),
            new ConfigRefEntry("modgate_ids.json", "dev.eclipse.config.modgate_ids", "dev.eclipse.config.layer.global", 4),
            new ConfigRefEntry("datapack loot tables", "dev.eclipse.config.loot", "dev.eclipse.config.layer.datapack", 6));

    public static List<ConfigRefEntry> configReferences() {
        return CONFIG_REFS;
    }

    public static int execute(CommandSourceStack source) {
        MinecraftServer server = source.getServer();
        List<ReloadLine> lines = new ArrayList<>();

        runStep(lines, "EclipseConfig (6 files + P4 ReloadHooks)", () -> EclipseConfig.reload());
        lines.add(new ReloadLine("P4 ReloadHooks bridge", true, "via EclipseConfig.reload()"));
        runStep(lines, "CutscenePaths", () -> CutscenePaths.reload());

        for (DevReloadRegistry.NamedHook hook : DevReloadRegistry.hooks()) {
            runStep(lines, hook.label(), hook.reload());
        }

        runStep(lines, "Client re-sync (day, milestones, cutscenes, stages)", () -> resyncClients(server));

        lines.add(new ReloadLine("Loot / datapack tables", true,
                "Use vanilla /reload for loot tables — not run automatically (too slow mid-event)"));

        int ok = 0;
        int fail = 0;
        for (ReloadLine line : lines) {
            if (line.success()) {
                ok++;
                source.sendSuccess(() -> successComponent(line), false);
            } else {
                fail++;
                source.sendFailure(errorComponent(line));
            }
        }

        int finalOk = ok;
        int finalFail = fail;
        source.sendSuccess(() -> Component.translatable("dev.eclipse.reload.summary", finalOk, finalFail), false);
        return fail == 0 ? 1 : 0;
    }

    private static void resyncClients(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), state.getAltarLevel(),
                EclipseConfig.day(state.getDay()).goals()));
        PacketDistributor.sendToAllPlayers(S2CMilestonesPayload.current());
        CutsceneService.syncLibraryToAll(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            WorldStageService.syncStagesTo(player);
        }
        // View-distance pin re-push (P5-W4) registers in DevReloadRegistry when available.
    }

    private static void runStep(List<ReloadLine> lines, String label, Runnable action) {
        try {
            action.run();
            lines.add(new ReloadLine(label, true, ""));
        } catch (Exception e) {
            String msg = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
            lines.add(new ReloadLine(label, false, msg));
        }
    }

    private static Component successComponent(ReloadLine line) {
        if (line.detail() == null || line.detail().isBlank()) {
            return Component.translatable("dev.eclipse.reload.ok", line.label());
        }
        return Component.translatable("dev.eclipse.reload.ok.detail", line.label(), line.detail());
    }

    private static Component errorComponent(ReloadLine line) {
        return Component.translatable("dev.eclipse.reload.fail", line.label(), line.detail());
    }

    /** Runs reload without chat output (used by tests / exporter sanity). */
    public static List<ReloadLine> dryRun(MinecraftServer server, Consumer<Runnable> runner) {
        List<ReloadLine> lines = new ArrayList<>();
        runner.accept(() -> runStep(lines, "dry", () -> {}));
        return lines;
    }
}
