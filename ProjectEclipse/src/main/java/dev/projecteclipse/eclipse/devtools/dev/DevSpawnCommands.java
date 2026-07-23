package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.SpawnTuningData;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/** SavedData-backed spawn center/radius editor and operator-only particle preview. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevSpawnCommands {
    private static final int PREVIEW_INTERVAL = 10;
    private static final int PREVIEW_POINTS = 64;
    private static final double PREVIEW_VIEW_RANGE_SQ = 128.0D * 128.0D;

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("spawn.set", DevCategory.SPAWN,
                        "/dev spawn set <x> <y> <z>", "dev.eclipse.doc.spawn.set",
                        Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("spawn.radius", DevCategory.SPAWN,
                        "/dev spawn radius <blocks>", "dev.eclipse.doc.spawn.radius",
                        Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("spawn.show", DevCategory.SPAWN,
                        "/dev spawn show [on|off]", "dev.eclipse.doc.spawn.show",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevSpawnCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("spawn")
                        .then(Commands.literal("set")
                                .then(Commands.argument("x", IntegerArgumentType.integer(-30_000_000, 30_000_000))
                                        .then(Commands.argument("y", IntegerArgumentType.integer(-2048, 2048))
                                                .then(Commands.argument("z",
                                                        IntegerArgumentType.integer(-30_000_000, 30_000_000))
                                                        .executes(DevSpawnCommands::set)))))
                        .then(Commands.literal("radius")
                                .then(Commands.argument("blocks", IntegerArgumentType.integer(1, 512))
                                        .executes(DevSpawnCommands::radius)))
                        .then(Commands.literal("show")
                                .executes(DevSpawnCommands::show)
                                .then(Commands.literal("on")
                                        .executes(context -> preview(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> preview(context, false))))));
    }

    private static int set(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        BlockPos pos = new BlockPos(
                IntegerArgumentType.getInteger(context, "x"),
                IntegerArgumentType.getInteger(context, "y"),
                IntegerArgumentType.getInteger(context, "z"));
        ServerLevel overworld = source.getServer().overworld();
        overworld.setDefaultSpawnPos(pos, 0.0F);
        SpawnTuningData.get(source.getServer()).setSpawnOverride(pos);
        overworld.sendParticles(ParticleTypes.PORTAL,
                pos.getX() + 0.5D, pos.getY() + 1.0D, pos.getZ() + 0.5D,
                48, 0.7D, 1.0D, 0.7D, 0.1D);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.spawn.set",
                pos.getX(), pos.getY(), pos.getZ()), true);
        return 1;
    }

    private static int radius(CommandContext<CommandSourceStack> context) {
        int radius = IntegerArgumentType.getInteger(context, "blocks");
        SpawnTuningData.get(context.getSource().getServer()).setRadiusOverride(radius);
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.spawn.radius", radius), true);
        return radius;
    }

    private static int show(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        BlockPos center = SanctumProtection.center(level);
        if (center == null) {
            center = level.getSharedSpawnPos();
        }
        SpawnTuningData tuning = SpawnTuningData.get(source.getServer());
        int gameplayRadius = SanctumProtection.spawnRadius(source.getServer());
        int sanctumRadius = SanctumProtection.radius(source.getServer());
        BlockPos finalCenter = center;
        source.sendSuccess(() -> Component.translatable("dev.eclipse.spawn.show",
                finalCenter.getX(), finalCenter.getY(), finalCenter.getZ(), gameplayRadius,
                tuning.radiusOverride(), sanctumRadius, tuning.previewOn()), false);
        if (source.getEntity() instanceof ServerPlayer player && player.serverLevel() == level) {
            drawRing(level, player, center, gameplayRadius);
        }
        return 1;
    }

    private static int preview(CommandContext<CommandSourceStack> context, boolean enabled) {
        SpawnTuningData.get(context.getSource().getServer()).setPreviewOn(enabled);
        context.getSource().sendSuccess(() -> Component.translatable(
                enabled ? "dev.eclipse.spawn.preview.on" : "dev.eclipse.spawn.preview.off"), true);
        return 1;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        SpawnTuningData tuning = SpawnTuningData.get(event.getServer());
        if (event.getServer().getTickCount() % 20 == 0 && tuning.spawnOverride() != null
                && !tuning.spawnOverride().equals(event.getServer().overworld().getSharedSpawnPos())) {
            // The sanctum builder intentionally re-pins vanilla spawn on boot/stage flip.
            // A saved explicit dev override has higher precedence and is re-applied.
            event.getServer().overworld().setDefaultSpawnPos(tuning.spawnOverride(), 0.0F);
        }
        if (event.getServer().getTickCount() % PREVIEW_INTERVAL != 0) {
            return;
        }
        if (!tuning.previewOn()) {
            return;
        }
        ServerLevel level = event.getServer().overworld();
        BlockPos center = SanctumProtection.center(level);
        if (center == null) {
            return;
        }
        int radius = SanctumProtection.spawnRadius(event.getServer());
        for (ServerPlayer player : level.players()) {
            if (player.hasPermissions(2) && player.distanceToSqr(
                    center.getX() + 0.5D, center.getY(), center.getZ() + 0.5D) <= PREVIEW_VIEW_RANGE_SQ) {
                drawRing(level, player, center, radius);
            }
        }
    }

    private static void drawRing(ServerLevel level, ServerPlayer viewer, BlockPos center, int radius) {
        for (int point = 0; point < PREVIEW_POINTS; point++) {
            double angle = Math.PI * 2.0D * point / PREVIEW_POINTS;
            level.sendParticles(viewer, ParticleTypes.END_ROD, true,
                    center.getX() + 0.5D + Math.cos(angle) * radius,
                    center.getY() + 0.15D,
                    center.getZ() + 0.5D + Math.sin(angle) * radius,
                    1, 0.0D, 0.0D, 0.0D, 0.0D);
        }
    }
}
