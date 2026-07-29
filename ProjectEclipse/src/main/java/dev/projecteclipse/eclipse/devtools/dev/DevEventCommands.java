package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArtifactSlotLock;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.util.SpawnReturns;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.sequence.HeraldSummonSequence;
import dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder;
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
 * {@code /dev event …} — PROGFIX #3 operator toggles for the persisted intro-event flags
 * (perm 2):
 *
 * <ul>
 *   <li>{@code stormtouched on|off} — sets/clears {@link EclipseWorldState#isStormTouched}.
 *       {@code on} also runs an immediate {@link ArtifactSlotLock#grantAll} pass (the same
 *       grant the APPROACH → LIGHTNING trigger fires); {@code off} lets the next 1 s sweep
 *       purge every artifact copy again — the normal pre-storm state.</li>
 *   <li>{@code stormtouched status} — reads the flag.</li>
 *   <li>{@code start herold [here]} — F-053: runs the Herald's full arrival cutscene
 *       ({@link HeraldSummonSequence}) and the summon it ends on. Without {@code here} the
 *       cutscene plays over the persisted sanctum altar exactly like the day-7 lure path;
 *       {@code here} stages it at the operator's own feet for iterating on the beats away
 *       from the arena. Unlike the day-gated lure this ignores the day/dusk checks —
 *       the sequence itself is the thing under test.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevEventCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("event.stormtouched", DevCategory.EVENT,
                        "/dev event stormtouched on|off|status",
                        "dev.eclipse.doc.event.stormtouched", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("event.start.herold", DevCategory.EVENT,
                        "/dev event start herold",
                        "dev.eclipse.doc.event.start.herold", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevEventCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("event")
                        .then(Commands.literal("stormtouched")
                                .then(Commands.literal("on")
                                        .executes(context -> set(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> set(context, false)))
                                .then(Commands.literal("status")
                                        .executes(DevEventCommands::status)))
                        .then(Commands.literal("start")
                                .then(Commands.literal("herold")
                                        .executes(context -> startHerald(context, false))
                                        .then(Commands.literal("here")
                                                .executes(context -> startHerald(context, true)))))));
    }

    /**
     * F-053: arms {@link HeraldSummonSequence} — the SAME entry point the day-7 lure uses,
     * so what an operator previews here is what players get.
     *
     * @param here stage the cutscene at the source instead of the persisted sanctum altar
     */
    private static int startHerald(CommandContext<CommandSourceStack> context, boolean here) {
        CommandSourceStack source = context.getSource();
        BlockPos altarPos = here ? null : EclipseWorldState.get(source.getServer()).getSanctumAltarPos();
        // The sanctum altar is an overworld fixture; everything else stages where the
        // operator stands, which may well be the nether or the end.
        ServerLevel level = altarPos != null ? source.getServer().overworld() : source.getLevel();
        int groundY;
        if (altarPos != null) {
            // The dais floor sits ALTAR_ABOVE_GROUND under the altar block (lure path).
            groundY = altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        } else {
            // Free-standing preview: seat the cutscene on the terrain under the source. The
            // band scan (not the global heightmap) matters — from day 12 the End disc hangs
            // at y≈360 over the map center and MOTION_BLOCKING resolves to the DISC, arming
            // the whole show 270 blocks over the operator's head (F-089 trap family).
            BlockPos at = BlockPos.containing(source.getPosition());
            groundY = SpawnReturns.groundY(level, at.getX(), at.getZ(), at.getY());
            altarPos = new BlockPos(at.getX(), groundY + AltarSanctumBuilder.ALTAR_ABOVE_GROUND, at.getZ());
        }
        if (!HeraldSummonSequence.begin(level, altarPos, groundY)) {
            source.sendFailure(Component.translatable("dev.eclipse.event.start.herold.busy"));
            return 0;
        }
        BlockPos at = altarPos;
        audit(source, Component.translatable("dev.eclipse.event.start.herold",
                        at.getX(), at.getY(), at.getZ()),
                "started the Herald summon cutscene at " + at.toShortString());
        return 1;
    }

    private static int set(CommandContext<CommandSourceStack> context, boolean touched) {
        CommandSourceStack source = context.getSource();
        EclipseWorldState state = EclipseWorldState.get(source.getServer());
        state.setStormTouched(touched);
        if (touched) {
            // Same ceremony pass IntroSequence fires — everyone online gets the artifact now
            // instead of on the next sweep.
            ArtifactSlotLock.grantAll(source.getServer());
        }
        Component feedback = Component.translatable(touched
                ? "dev.eclipse.event.stormtouched.on" : "dev.eclipse.event.stormtouched.off");
        audit(source, feedback, "set stormTouched " + (touched ? "on" : "off"));
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        boolean touched = EclipseWorldState.get(source.getServer()).isStormTouched();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.event.stormtouched.status",
                touched ? "ON" : "OFF"), false);
        return touched ? 1 : 0;
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
