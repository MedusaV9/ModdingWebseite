package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.Locale;

import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.dev.FxDevPayloads;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.coordinates.Vec3Argument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev photon status|test} (PH-CORE) — operator smoke tests for the optional Photon
 * VFX layer. Both leaves are client-side actions (Photon spawning is 100% client-side, see
 * {@code docs/plans_v3/plans_v5/photon/API.md} §4), so they travel to the EXECUTING
 * player's client over the existing {@link FxDevPayloads} dev lane (optional registrar
 * group, dev-only wire contract) and run in {@code FxDevClient} — same pattern as
 * {@code /eclipsefx post|emitter|sun debug}.
 *
 * <ul>
 *   <li>{@code /dev photon status} — bridge guard chain, live-executor budget, loop cache,
 *       missing {@code .fx} ids, and every registered {@code PhotonFxRegistry} row.</li>
 *   <li>{@code /dev photon test <fxId> [pos]} — a registered cue id (e.g.
 *       {@code eclipse:fx/cue/template_burst}) dispatches through the full registry lane;
 *       a raw fx id (e.g. {@code eclipse:template_burst}) spawns directly via
 *       {@code PhotonBridge} with allow-multi. Default position: 4 blocks in front of the
 *       operator's eyes (so bursts are not spawned inside the camera).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevPhotonCommands {
    /** How far in front of the operator's eyes {@code test} anchors by default (blocks). */
    private static final double TEST_FORWARD_BLOCKS = 4.0D;

    private static final SuggestionProvider<CommandSourceStack> FX_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(List.of(
                    "eclipse:template_burst", "eclipse:template_loop",
                    "eclipse:fx/cue/template_burst", "eclipse:fx/cue/template_loop",
                    "eclipse:altar_levelup", "eclipse:expansion_rift_glow"), builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("photon.status", DevCategory.CUTSCENE, "/dev photon status",
                        "dev.eclipse.doc.photon.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("photon.test", DevCategory.CUTSCENE, "/dev photon test",
                        "dev.eclipse.doc.photon.test", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevPhotonCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("photon")
                        .then(Commands.literal("status").executes(DevPhotonCommands::status))
                        .then(Commands.literal("test")
                                .then(Commands.argument("fxId", StringArgumentType.string())
                                        .suggests(FX_SUGGESTIONS)
                                        .executes(ctx -> test(ctx, null))
                                        .then(Commands.argument("pos", Vec3Argument.vec3())
                                                .executes(ctx -> test(ctx,
                                                        Vec3Argument.getVec3(ctx, "pos"))))))));
    }

    private static int status(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        FxDevPayloads.sendAction(player, FxDevPayloads.ACTION_PHOTON_STATUS, "", Vec3.ZERO, 0.0F);
        reply(ctx, "photon status → sent to your client (report in chat)");
        return 1;
    }

    private static int test(CommandContext<CommandSourceStack> ctx, @javax.annotation.Nullable Vec3 posOrNull)
            throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String fxId = StringArgumentType.getString(ctx, "fxId");
        Vec3 pos = posOrNull != null ? posOrNull
                : player.getEyePosition().add(player.getLookAngle().scale(TEST_FORWARD_BLOCKS));
        FxDevPayloads.sendAction(player, FxDevPayloads.ACTION_PHOTON_TEST, fxId, pos, 0.0F);
        reply(ctx, "photon test " + fxId + " → spawning on your client at "
                + String.format(Locale.ROOT, "%.1f %.1f %.1f", pos.x, pos.y, pos.z));
        return 1;
    }

    private static void reply(CommandContext<CommandSourceStack> ctx, String message) {
        ctx.getSource().sendSuccess(() -> Component.literal("[dev photon] ")
                .withStyle(ChatFormatting.DARK_PURPLE)
                .append(Component.literal(message).withStyle(ChatFormatting.GRAY)), false);
    }
}
