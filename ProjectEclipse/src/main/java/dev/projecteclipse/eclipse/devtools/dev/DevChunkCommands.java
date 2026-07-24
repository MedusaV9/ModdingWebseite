package dev.projecteclipse.eclipse.devtools.dev;

import javax.annotation.Nullable;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.worldgen.stage.ChunkRegen;
import dev.projecteclipse.eclipse.worldgen.stage.ChunkRegenApi;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.coordinates.BlockPosArgument;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.ChunkPos;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev chunk regen} (PLAN-B B16): operator chunk regeneration through the
 * {@link ChunkRegenApi} — rewrite the targeted chunks from the frozen terrain function at
 * the committed stage and replay the vanilla pipeline. Registered through
 * {@link DevCommandRegistry} from the static initializer (freeze-before-boot rule);
 * Brigadier merges the {@code /dev} roots across files.
 *
 * <p>Syntax: {@code /dev chunk regen [<pos>|current] [<radius 0-2>] [force]} — defaults to
 * the caller's chunk, radius 0. Chunks intersecting a structure protection box are skipped
 * with a warning (the whole request is refused when nothing remains) unless {@code force}.
 * Permission 3, destructive.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevChunkCommands {
    /** Progress lines are throttled to every Nth chunk (plus the completion summary). */
    private static final int PROGRESS_EVERY_CHUNKS = 5;

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("chunk.regen", DevCategory.STAGE,
                        "/dev chunk regen [<pos>|current] [<radius>] [force]",
                        "dev.eclipse.doc.chunk.regen", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3));
    }

    private DevChunkCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("chunk")
                        .requires(source -> source.hasPermission(3))
                        .then(Commands.literal("regen")
                                .executes(context -> regen(context, null, 0, false))
                                .then(Commands.literal("current")
                                        .executes(context -> regen(context, null, 0, false))
                                        .then(Commands.argument("radius",
                                                        IntegerArgumentType.integer(0, ChunkRegen.MAX_RADIUS))
                                                .executes(context -> regen(context, null,
                                                        IntegerArgumentType.getInteger(context, "radius"), false))
                                                .then(Commands.literal("force")
                                                        .executes(context -> regen(context, null,
                                                                IntegerArgumentType.getInteger(context, "radius"),
                                                                true)))))
                                .then(Commands.argument("pos", BlockPosArgument.blockPos())
                                        .executes(context -> regen(context,
                                                BlockPosArgument.getBlockPos(context, "pos"), 0, false))
                                        .then(Commands.argument("radius",
                                                        IntegerArgumentType.integer(0, ChunkRegen.MAX_RADIUS))
                                                .executes(context -> regen(context,
                                                        BlockPosArgument.getBlockPos(context, "pos"),
                                                        IntegerArgumentType.getInteger(context, "radius"), false))
                                                .then(Commands.literal("force")
                                                        .executes(context -> regen(context,
                                                                BlockPosArgument.getBlockPos(context, "pos"),
                                                                IntegerArgumentType.getInteger(context, "radius"),
                                                                true))))))));
    }

    private static int regen(CommandContext<CommandSourceStack> context, @Nullable BlockPos pos,
            int radius, boolean force) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getLevel();
        BlockPos anchor = pos != null ? pos : BlockPos.containing(source.getPosition());
        ChunkPos center = new ChunkPos(anchor);

        ChunkRegen.StartResult result = ChunkRegenApi.regen(level, center, radius, force,
                new SourceFeedback(source));
        if (result.refusal() != null) {
            source.sendFailure(Component.translatable(refusalKey(result.refusal())));
            return 0;
        }
        if (result.protectedChunks() > 0) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.chunk.regen.protected",
                    result.protectedChunks()), false);
        }
        Component feedback = Component.translatable("dev.eclipse.chunk.regen.started",
                result.targetChunks(), center.x, center.z, radius);
        audit(source, feedback, "started chunk regen of " + result.targetChunks()
                + " chunk(s) around chunk [" + center.x + ", " + center.z + "] radius " + radius
                + (force ? " (FORCE)" : ""));
        return result.targetChunks();
    }

    private static String refusalKey(ChunkRegen.Refusal refusal) {
        return switch (refusal) {
            case NOT_DISC_DIMENSION -> "dev.eclipse.stage.disc_only";
            case SWEEP_RUNNING, REGEN_RUNNING -> "dev.eclipse.chunk.regen.refused.busy";
            case ALL_PROTECTED -> "dev.eclipse.chunk.regen.refused.structure";
        };
    }

    /** Throttled per-chunk progress + completion summary back to the issuing source. */
    private record SourceFeedback(CommandSourceStack source) implements ChunkRegen.Listener {
        @Override
        public void onChunkDone(int chunksDone, int chunksTotal, ChunkPos pos) {
            if (chunksTotal > 1 && chunksDone < chunksTotal
                    && chunksDone % PROGRESS_EVERY_CHUNKS == 0) {
                this.source.sendSuccess(() -> Component.translatable(
                        "dev.eclipse.chunk.regen.progress", chunksDone, chunksTotal), false);
            }
        }

        @Override
        public void onComplete(ChunkRegen.Result result) {
            this.source.sendSuccess(() -> Component.translatable("dev.eclipse.chunk.regen.done",
                    result.chunksRegenerated(), result.columnsWritten(), result.elapsedMillis(),
                    result.chunksSkippedProtected()), false);
        }
    }

    /** The DevBuffCommands audit convention: feedback + ops echo + log line. */
    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
