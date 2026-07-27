package dev.projecteclipse.eclipse.woah.resonance;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import dev.projecteclipse.eclipse.devtools.dev.DevRoot;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev woah resonance ...} — operator surface for the WOAH-04 Resonanzfeld
 * (plan §9). Hangs its subtree off the shared {@code woah} literal that
 * {@code ChronoStasisDevCommands} registered first (Brigadier merges separate
 * {@code register} calls automatically — the {@link DevRoot} convention).
 *
 * <ul>
 *   <li>{@code spawn [here]} — enqueue the build at the authored anchor (stage-gate
 *       bypassed); with {@code here} at the executor's feet (dev worlds).</li>
 *   <li>{@code melody print} — the current melody as tone indices + the matching
 *       crystal coordinates; {@code melody new} — reroll + immediate TEACH.</li>
 *   <li>{@code solve} — force the finale (FX / reward QA).</li>
 *   <li>{@code reset} — IDLE, cooldown cleared, displays + interactions discarded and
 *       rebuilt from SavedData (the self-heal acceptance test).</li>
 *   <li>{@code status} — server-side view: state, progress, cooldown, display /
 *       interaction census, spawn queue. (Live Photon handles are client-side and
 *       visible via {@code /dev photon} instead.)</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevResonanceCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("woah.resonance.spawn", DevCategory.EVENT,
                        "/dev woah resonance spawn [here]", "dev.eclipse.doc.woah.resonance.spawn",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.resonance.melody", DevCategory.EVENT,
                        "/dev woah resonance melody [print|new]",
                        "dev.eclipse.doc.woah.resonance.melody",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.resonance.solve", DevCategory.EVENT,
                        "/dev woah resonance solve", "dev.eclipse.doc.woah.resonance.solve",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.resonance.reset", DevCategory.EVENT,
                        "/dev woah resonance reset", "dev.eclipse.doc.woah.resonance.reset",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.resonance.status", DevCategory.EVENT,
                        "/dev woah resonance status", "dev.eclipse.doc.woah.resonance.status",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevResonanceCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("woah")
                        .then(Commands.literal("resonance")
                                .then(Commands.literal("spawn")
                                        .executes(context -> spawn(context, false))
                                        .then(Commands.literal("here")
                                                .executes(context -> spawn(context, true))))
                                .then(Commands.literal("melody")
                                        .executes(DevResonanceCommands::melodyPrint)
                                        .then(Commands.literal("print")
                                                .executes(DevResonanceCommands::melodyPrint))
                                        .then(Commands.literal("new")
                                                .executes(DevResonanceCommands::melodyNew)))
                                .then(Commands.literal("solve")
                                        .executes(DevResonanceCommands::solve))
                                .then(Commands.literal("reset")
                                        .executes(DevResonanceCommands::reset))
                                .then(Commands.literal("status")
                                        .executes(DevResonanceCommands::status)))));
    }

    /** Stage-gate bypass; the async placer takes it from the pending queue. */
    private static int spawn(CommandContext<CommandSourceStack> context, boolean here) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (ResonanceFieldData.get(level).built()) {
            source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.resonance.spawn.already"), false);
            return 0;
        }
        BlockPos anchor = here
                ? BlockPos.containing(source.getPosition())
                : ResonanceFieldService.authoredAnchor();
        ResonanceFieldService.enqueueIfNeeded(level, anchor);
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.resonance.spawn.started",
                anchor.getX(), anchor.getY(), anchor.getZ()), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} enqueued the resonance field at {}",
                source.getTextName(), anchor.toShortString());
        return 1;
    }

    /** Read-only melody dump — no audit line (the DevScareCommands list convention). */
    private static int melodyPrint(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        ServerLevel level = source.getServer().overworld();
        ResonanceFieldData data = ResonanceFieldData.get(level);
        if (!data.built()) {
            source.sendFailure(ServerLang.tr(player, "dev.eclipse.woah.resonance.not_built"));
            return 0;
        }
        int[] melody = data.melody();
        StringBuilder tones = new StringBuilder();
        for (int i = 0; i < melody.length; i++) {
            if (i > 0) {
                tones.append(" \u2192 ");
            }
            tones.append(melody[i]);
        }
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.resonance.melody.header",
                tones.toString(), data.progressIndex(), melody.length), false);
        for (int i = 0; i < melody.length; i++) {
            int toneIndex = melody[i];
            int crystalIdx = -1;
            for (int c = 0; c < data.monoliths().size(); c++) {
                if (data.monoliths().get(c).toneIndex == toneIndex) {
                    crystalIdx = c;
                    break;
                }
            }
            BlockPos pos = crystalIdx >= 0 ? data.monoliths().get(crystalIdx).basePos : null;
            String line = (i + 1) + ". tone " + toneIndex
                    + (pos == null ? " (?)"
                            : " @ " + pos.getX() + " " + pos.getY() + " " + pos.getZ());
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return melody.length;
    }

    private static int melodyNew(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (!ResonanceFieldData.get(level).built()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.resonance.not_built"));
            return 0;
        }
        ResonanceFieldService.devTeach(level, true);
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.resonance.melody.new_ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} rerolled the resonance melody (TEACH started)",
                source.getTextName());
        return 1;
    }

    private static int solve(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (!ResonanceFieldData.get(level).built()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.resonance.not_built"));
            return 0;
        }
        ResonanceFieldService.devSolve(level);
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.resonance.solve.ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} forced the resonance finale", source.getTextName());
        return 1;
    }

    private static int reset(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (!ResonanceFieldData.get(level).built()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.resonance.not_built"));
            return 0;
        }
        ResonanceFieldService.devReset(level);
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.resonance.reset.ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} reset the resonance field (full entity rebuild)",
                source.getTextName());
        return 1;
    }

    /** Read-only census — no audit line. */
    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        String status = ResonanceFieldService.devStatus(level);
        source.sendSuccess(() -> Component.literal("resonance: " + status), false);
        return 1;
    }
}
