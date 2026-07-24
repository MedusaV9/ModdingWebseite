package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;

import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.awards.AwardsState;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.devtools.StageBackups;
import dev.projecteclipse.eclipse.ghosts.GhostsState;
import dev.projecteclipse.eclipse.offering.OfferingState;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeConfig;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeMath;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import dev.projecteclipse.eclipse.sequence.IntroSequence;
import dev.projecteclipse.eclipse.stormfx.StormRegistry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Compact read-only operator dashboard for the live Eclipse event. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevStatusCommands {
    static {
        DevCommandRegistry.register(new DevCommandDoc(
                "status", DevCategory.EVENT, "/dev status", "dev.eclipse.doc.status",
                Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevStatusCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("status").executes(DevStatusCommands::status)));
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        int day = DayScheduler.getDay(server);

        send(source, Component.translatable("dev.eclipse.status.header", day, EclipseConfig.maxDay())
                .withStyle(ChatFormatting.LIGHT_PURPLE));
        send(source, timerLine(server));
        send(source, stageLine(server, DiscProfile.OVERWORLD, "dev.eclipse.status.overworld"));
        send(source, stageLine(server, DiscProfile.NETHER, "dev.eclipse.status.nether"));
        send(source, Component.translatable("dev.eclipse.status.sequences",
                state(IntroSequence.isRunning()), Component.translatable("dev.eclipse.status.na")));
        send(source, Component.translatable("dev.eclipse.status.storms", stormCount(server)));

        EclipseWorldgenState worldgen = EclipseWorldgenState.get(server);
        send(source, Component.translatable("dev.eclipse.status.flags",
                yesNo(worldgen.breachOpen()), yesNo(worldgen.endDiscMaterialized())));

        List<StageBackups.BackupInfo> backups = StageBackups.list(server);
        long overworldBackups = backups.stream()
                .filter(backup -> backup.profile() == DiscProfile.OVERWORLD).count();
        long netherBackups = backups.size() - overworldBackups;
        send(source, Component.translatable("dev.eclipse.status.backups",
                backups.size(), overworldBackups, netherBackups));

        AwardsState awards = AwardsState.get(server);
        OfferingState offerings = OfferingState.get(server);
        var resolvedAwards = awards.resolved(day);
        Component awardState = resolvedAwards.isPresent()
                ? Component.translatable("dev.eclipse.status.awards.resolved",
                        resolvedAwards.get().categories().size())
                : Component.translatable("dev.eclipse.status.awards.open");
        int offerCount = offerings.offers(day).size();
        Component offeringState = offerings.resolved(day).isPresent()
                ? Component.translatable("dev.eclipse.status.offerings.resolved", offerCount)
                : Component.translatable("dev.eclipse.status.offerings.open", offerCount);
        send(source, Component.translatable("dev.eclipse.status.daily", day, awardState, offeringState));

        List<String> buffs = TimedBuffApi.Holder.get().active(server);
        Component buffSummary = buffs.isEmpty() ? Component.translatable("dev.eclipse.status.none")
                : Component.literal(String.join(", ", buffs));
        send(source, Component.translatable("dev.eclipse.status.buffs", buffSummary));
        send(source, Component.translatable("dev.eclipse.status.players",
                server.getPlayerList().getPlayerCount(), GhostsState.get(server).all().size()));
        return 1;
    }

    private static Component timerLine(MinecraftServer server) {
        RealtimeState timer = RealtimeState.get(server);
        Component mode = Component.translatable(!timer.isArmed()
                ? "dev.eclipse.timer.mode.disarmed"
                : timer.isPaused() ? "dev.eclipse.timer.mode.paused" : "dev.eclipse.timer.mode.running");
        if (!timer.isArmed()) {
            Component unavailable = Component.translatable("dev.eclipse.status.na");
            return Component.translatable("dev.eclipse.status.timer", mode, unavailable, unavailable);
        }

        long now = EclipseClock.epochMillis();
        long remaining = timer.isPaused() ? timer.getPauseRemainingMillis()
                : Math.max(0L, timer.getBoundaryEpochMillis() - now);
        long boundary = timer.isPaused() ? now + remaining : timer.getBoundaryEpochMillis();
        return Component.translatable("dev.eclipse.status.timer", mode,
                RealtimeDayService.formatInstant(boundary, RealtimeConfig.get().zone()),
                RealtimeMath.remainingText(remaining));
    }

    private static Component stageLine(MinecraftServer server, DiscProfile profile, String nameKey) {
        int stage = WorldStageService.stage(server, profile);
        return Component.translatable("dev.eclipse.status.stage", Component.translatable(nameKey),
                stage, StageRadii.radius(profile, stage),
                Component.translatable(RingGrowthService.isRunning(profile)
                        ? "dev.eclipse.status.animating" : "dev.eclipse.status.idle"));
    }

    private static int stormCount(MinecraftServer server) {
        int count = 0;
        for (ServerLevel level : server.getAllLevels()) {
            count += StormRegistry.storms(level).size();
        }
        return count;
    }

    private static Component state(boolean active) {
        return Component.translatable(active ? "dev.eclipse.status.active" : "dev.eclipse.status.idle");
    }

    private static Component yesNo(boolean value) {
        return Component.translatable(value ? "dev.eclipse.yes" : "dev.eclipse.no");
    }

    private static void send(CommandSourceStack source, Component line) {
        source.sendSuccess(() -> line, false);
    }
}
