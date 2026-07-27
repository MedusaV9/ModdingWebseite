package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Locale;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.woah.mansiondome.DomeShatterFx;
import dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeService;
import dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeState;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.VanillaLandmarks;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev dome …} — operator control over the WOAH-01 mansion glitch dome (perm 2;
 * the {@code DevGlitchCommands} bridge pattern). State persists in
 * {@code woah.mansiondome.MansionDomeState}, everything ticks in
 * {@code MansionDomeService}; nothing here messages regular players (silent-event law).
 *
 * <ul>
 *   <li>{@code status} — status byte, geometry, hits, zone/device ids, aftershocks.</li>
 *   <li>{@code arm} — arm at the real mansion landmark (fails while it is not PLACED);
 *       {@code arm here [radius]} — TEST dome at the caller (shader/renderer iteration
 *       without a stage-4 world; same code paths, marked transient).</li>
 *   <li>{@code hits <n>} — set the remaining melee hits (mirrored to the entity).</li>
 *   <li>{@code destroy} — full destruction sequence from t0.</li>
 *   <li>{@code shatter} — only the BlockDisplay shard show (FX iteration).</li>
 *   <li>{@code reset} — back to ACTIVE: fresh device/zone, shard sweep, schedule clear.</li>
 * </ul>
 *
 * <p>The interior post effect alone is testable without a world via the existing
 * {@code /dev glitch test dome [s]} (the {@code dome} id lives in
 * {@code GlitchZoneEffects.IDS}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevMansionDomeCommands {
    private static final int DEFAULT_TEST_RADIUS = 40;

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("dome.status", DevCategory.EVENT, "/dev dome status",
                        "dev.eclipse.doc.dome.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("dome.arm", DevCategory.EVENT, "/dev dome arm [here [radius]]",
                        "dev.eclipse.doc.dome.arm", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("dome.hits", DevCategory.EVENT, "/dev dome hits <n>",
                        "dev.eclipse.doc.dome.hits", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("dome.destroy", DevCategory.EVENT, "/dev dome destroy",
                        "dev.eclipse.doc.dome.destroy", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("dome.shatter", DevCategory.EVENT, "/dev dome shatter",
                        "dev.eclipse.doc.dome.shatter", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("dome.reset", DevCategory.EVENT, "/dev dome reset",
                        "dev.eclipse.doc.dome.reset", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevMansionDomeCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("dome")
                        .then(Commands.literal("status")
                                .executes(DevMansionDomeCommands::status))
                        .then(Commands.literal("arm")
                                .executes(DevMansionDomeCommands::armMansion)
                                .then(Commands.literal("here")
                                        .executes(ctx -> armHere(ctx, DEFAULT_TEST_RADIUS))
                                        .then(Commands.argument("radius",
                                                        IntegerArgumentType.integer(12, 96))
                                                .executes(ctx -> armHere(ctx,
                                                        IntegerArgumentType.getInteger(ctx, "radius"))))))
                        .then(Commands.literal("hits")
                                .then(Commands.argument("n",
                                                IntegerArgumentType.integer(0, MansionDomeState.MAX_HITS))
                                        .executes(DevMansionDomeCommands::hits)))
                        .then(Commands.literal("destroy")
                                .executes(DevMansionDomeCommands::destroy))
                        .then(Commands.literal("shatter")
                                .executes(DevMansionDomeCommands::shatter))
                        .then(Commands.literal("reset")
                                .executes(DevMansionDomeCommands::reset))));
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MansionDomeState state = MansionDomeState.get(source.getServer());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.dome.status",
                statusName(state.status()) + (state.testDome() ? " (test)" : ""),
                state.dimension().location().toString(), state.centre().toShortString(),
                String.format(Locale.ROOT, "%.1f", state.shellRadius()),
                state.groundY(), state.roofY(), state.devicePos().toShortString(),
                state.hitsRemaining(), MansionDomeState.MAX_HITS), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.dome.status2",
                String.valueOf(state.zoneId()), String.valueOf(state.deviceUuid()),
                state.collapseStartGameTime(), state.aftershocksRemaining(),
                state.nextAftershockGameTime(),
                DomeShatterFx.isActive() ? "LIVE" : "-"), false);
        return 1;
    }

    /** Arms at the real mansion landmark; fails while the site was never PLACED (§12 #12). */
    private static int armMansion(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MansionDomeState state = MansionDomeState.get(source.getServer());
        if (state.status() != MansionDomeState.STATUS_UNARMED) {
            source.sendFailure(Component.translatable("dev.eclipse.dome.already_armed",
                    statusName(state.status())));
            return 0;
        }
        if (!StructurePendingRegistry.wasPlaced(MansionDomeService.MANSION_SITE_ID)) {
            source.sendFailure(Component.translatable("dev.eclipse.dome.not_placed",
                    MansionDomeService.MANSION_SITE_ID));
            return 0;
        }
        BlockPos anchor = VanillaLandmarks.landmarkAnchor(DiscProfile.OVERWORLD,
                MansionDomeService.MANSION_SITE_ID);
        if (anchor == null) {
            source.sendFailure(Component.translatable("dev.eclipse.dome.no_anchor"));
            return 0;
        }
        ServerLevel overworld = source.getServer().overworld();
        MansionDomeService.arm(overworld, anchor, 80, 0, false);
        audit(source, Component.translatable("dev.eclipse.dome.armed",
                anchor.toShortString()), "dome arm @ " + anchor.toShortString());
        return 1;
    }

    /** Test dome at the caller — same paths, marked transient (never the real mansion). */
    private static int armHere(CommandContext<CommandSourceStack> context, int radius)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayerOrException();
        ServerLevel level = source.getLevel();
        BlockPos anchor = player.blockPosition();
        MansionDomeService.arm(level, anchor, Math.max(24, radius * 2), radius, true);
        audit(source, Component.translatable("dev.eclipse.dome.armed_here",
                        anchor.toShortString(), radius),
                "dome arm here r=" + radius + " @ " + anchor.toShortString());
        return 1;
    }

    private static int hits(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MansionDomeState state = MansionDomeState.get(source.getServer());
        if (state.status() != MansionDomeState.STATUS_ACTIVE) {
            source.sendFailure(Component.translatable("dev.eclipse.dome.not_active",
                    statusName(state.status())));
            return 0;
        }
        int n = IntegerArgumentType.getInteger(context, "n");
        ServerLevel level = source.getServer().getLevel(state.dimension());
        if (level == null) {
            return 0;
        }
        MansionDomeService.setHits(level, n);
        audit(source, Component.translatable("dev.eclipse.dome.hits_set", n,
                MansionDomeState.MAX_HITS), "dome hits " + n);
        return 1;
    }

    private static int destroy(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MansionDomeState state = MansionDomeState.get(source.getServer());
        ServerLevel level = source.getServer().getLevel(state.dimension());
        if (level == null || !MansionDomeService.devDestroy(level)) {
            source.sendFailure(Component.translatable("dev.eclipse.dome.not_active",
                    statusName(state.status())));
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.dome.destroying"), "dome destroy");
        return 1;
    }

    /** FX iteration: only the shard show — at the dome if armed, else at the caller. */
    private static int shatter(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        MansionDomeState state = MansionDomeState.get(source.getServer());
        ServerLevel level;
        Vec3 centre;
        float radius;
        if (state.status() != MansionDomeState.STATUS_UNARMED) {
            level = source.getServer().getLevel(state.dimension());
            if (level == null) {
                return 0;
            }
            centre = Vec3.atCenterOf(state.centre());
            radius = state.shellRadius();
        } else {
            ServerPlayer player = source.getPlayerOrException();
            level = source.getLevel();
            centre = player.position().add(0.0D, 8.0D, 0.0D);
            radius = 24.0F;
        }
        DomeShatterFx.clearAll();
        DomeShatterFx.begin(level, centre, radius);
        audit(source, Component.translatable("dev.eclipse.dome.shatter_started",
                        String.format(Locale.ROOT, "%.1f", radius)),
                "dome shatter r=" + radius);
        return 1;
    }

    private static int reset(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MansionDomeState state = MansionDomeState.get(source.getServer());
        ServerLevel level = source.getServer().getLevel(state.dimension());
        if (level == null || !MansionDomeService.reset(level)) {
            source.sendFailure(Component.translatable("dev.eclipse.dome.never_armed"));
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.dome.reset_done"), "dome reset");
        return 1;
    }

    private static String statusName(byte status) {
        return switch (status) {
            case MansionDomeState.STATUS_ACTIVE -> "ACTIVE";
            case MansionDomeState.STATUS_COLLAPSING -> "COLLAPSING";
            case MansionDomeState.STATUS_DESTROYED -> "DESTROYED";
            default -> "UNARMED";
        };
    }

    /** Same operator-audit convention as the other /dev command bridges. */
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
