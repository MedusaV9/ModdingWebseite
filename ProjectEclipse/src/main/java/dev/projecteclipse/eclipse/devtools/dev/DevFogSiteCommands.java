// F-105 B6 acceptance aid
package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;

import javax.annotation.Nullable;

import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.worldgen.fog.FogStormSites;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * F-105 B6 acceptance aid — {@code /dev fogsite …}: unlocks live acceptance of the WAVE5
 * B6 chest-open sting ({@code FogChestSting}) on legacy saves.
 *
 * <p>Fog-storm sites normally materialize ONLY through the world-stage listener
 * ({@code FogStormSites.onStageTerrainComplete} → {@code StructurePendingRegistry.enqueue}).
 * On a save whose overworld stage is already past 3, a site newly added to
 * {@code fogstorms.json} can never materialize, and legacy sites placed by older code have
 * no persisted chest index ({@link EclipseWorldgenState.FogSiteState#chests()} empty) — so
 * B6 can never fire. This dev-only bridge re-runs the EXISTING public
 * {@link FogStormSites#materializeSite} pipeline on demand, which rebuilds the grove,
 * persists the chest index and registers the storm itself.</p>
 *
 * <pre>
 * /dev fogsite list
 * /dev fogsite rematerialize &lt;id&gt;
 * /dev fogsite retire &lt;id&gt;
 * </pre>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevFogSiteCommands {
    private static final SuggestionProvider<CommandSourceStack> SITE_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    FogStormSites.sites().stream().map(FogStormSites.Site::id), builder);

    static {
        // F-105 B6 acceptance aid — dev-only handbook rows; descKey lang entries are
        // deliberately NOT shipped (no-lang-changes law), so /dev help shows the raw key.
        DevCommandRegistry.register(
                new DevCommandDoc("fogsite.list", DevCategory.STAGE, "/dev fogsite list",
                        "dev.eclipse.doc.fogsite.list", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("fogsite.rematerialize", DevCategory.STAGE,
                        "/dev fogsite rematerialize", "dev.eclipse.doc.fogsite.rematerialize",
                        Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("fogsite.retire", DevCategory.STAGE,
                        "/dev fogsite retire", "dev.eclipse.doc.fogsite.retire",
                        Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevFogSiteCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("fogsite")
                        .then(Commands.literal("list").executes(DevFogSiteCommands::list))
                        .then(Commands.literal("rematerialize")
                                .then(Commands.argument("id", StringArgumentType.greedyString())
                                        .suggests(SITE_SUGGESTIONS)
                                        .executes(DevFogSiteCommands::rematerialize)))
                        .then(Commands.literal("retire")
                                .then(Commands.argument("id", StringArgumentType.greedyString())
                                        .suggests(SITE_SUGGESTIONS)
                                        .executes(DevFogSiteCommands::retire)))));
    }

    // ------------------------------------------------------------------ list

    /** Configured table ({@link FogStormSites#sites()}) + persisted per-site SavedData row. */
    private static int list(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        List<FogStormSites.Site> sites = FogStormSites.sites();
        EclipseWorldgenState state = EclipseWorldgenState.get(source.getServer());
        header(source, "fog-storm sites: " + sites.size()
                + (sites.isEmpty() ? " (fogstorms.json missing/empty — check /eclipse-worldgen reload)" : ""));
        for (FogStormSites.Site site : sites) {
            EclipseWorldgenState.FogSiteState saved = state.fogSiteState(site.id());
            detail(source, site.id() + "  x=" + site.x() + " z=" + site.z()
                    + " radius=" + site.radius() + " stage=" + site.stage()
                    + " active=" + site.active());
            detail(source, "  saved: placed=" + saved.placed() + " active=" + saved.active()
                    + " recovered=" + saved.recovered() + " chests=" + saved.chests().size());
            for (BlockPos chest : saved.chests()) {
                detail(source, "    chest @ " + chest.toShortString());
            }
        }
        return sites.size();
    }

    // ------------------------------------------------------------------ rematerialize

    /**
     * Re-runs {@link FogStormSites#materializeSite} for one configured site in the server's
     * overworld. materializeSite loads chunks asynchronously through SitePrep, so the
     * command replies "queued" immediately; completion/failure is reported from the
     * callbacks. SitePrep's {@code whenReady} callbacks run on the server thread (see
     * {@code SitePrep.PreparedGround#whenReady}), so replying to the command source there
     * is safe — the {@code [devfogsite]} INFO lines are logged regardless, as the grep
     * probe for headless acceptance. Chest index + storm registration are written by
     * materializeSite itself (setFogSiteState/broadcast); nothing is duplicated here.
     */
    private static int rematerialize(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id").strip();
        FogStormSites.Site site = FogStormSites.sites().stream()
                .filter(s -> s.id().equals(id)).findFirst().orElse(null);
        if (site == null) {
            source.sendFailure(Component.literal("[dev fogsite] unknown site id '" + id
                    + "' — see /dev fogsite list"));
            return 0;
        }
        ServerLevel overworld = source.getServer().overworld();
        FogStormSites.materializeSite(overworld, site,
                () -> {
                    EclipseMod.LOGGER.info("[devfogsite] rematerialized {}", site.id());
                    source.sendSuccess(() -> Component.literal("[dev fogsite] rematerialized "
                            + site.id() + " — chest index persisted, storm registered")
                            .withStyle(ChatFormatting.GREEN), false);
                },
                error -> {
                    EclipseMod.LOGGER.info("[devfogsite] FAILED {}: {}", site.id(), messageOf(error));
                    source.sendFailure(Component.literal("[dev fogsite] FAILED " + site.id()
                            + ": " + messageOf(error)));
                });
        EclipseMod.LOGGER.info("[devfogsite] queued rematerialize {}", site.id());
        header(source, "queued rematerialize " + site.id()
                + " — SitePrep runs tick-budgeted, completion is reported when the grove lands");
        return 1;
    }

    // ------------------------------------------------------------------ retire

    /**
     * F-105 B6 acceptance aid — persistently retires one standing storm via the existing
     * {@link FogStormSites#stormEnded} hook: wall drops, {@code active=false} survives
     * restart, the B13 snow-recovery sweep runs (budgeted, in the background). Needed on
     * GPU-less llvmpipe VMs where any registry storm in render distance triggers a
     * permanent framebuffer-blit failure (GL_INVALID_OPERATION depth attachment format
     * mismatch → black screen); {@code retire} clears the view for photo acceptance of
     * other features, {@code rematerialize} rebuilds the site fresh afterwards.
     */
    private static int retire(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id").strip();
        FogStormSites.Site site = FogStormSites.sites().stream()
                .filter(s -> s.id().equals(id)).findFirst().orElse(null);
        if (site == null) {
            source.sendFailure(Component.literal("[dev fogsite] unknown site id '" + id
                    + "' — see /dev fogsite list"));
            return 0;
        }
        FogStormSites.stormEnded(source.getServer().overworld(), site.id());
        EclipseMod.LOGGER.info("[devfogsite] retired {}", site.id());
        source.sendSuccess(() -> Component.literal("[devfogsite] retired " + site.id())
                .withStyle(ChatFormatting.GREEN), false);
        return 1;
    }

    private static String messageOf(@Nullable Throwable error) {
        if (error == null) {
            return "unknown error";
        }
        return error.getMessage() != null ? error.getMessage() : error.toString();
    }

    // ------------------------------------------------------------------ feedback

    private static void header(CommandSourceStack source, String message) {
        source.sendSuccess(() -> Component.literal("[dev fogsite] ")
                .withStyle(ChatFormatting.DARK_AQUA)
                .append(Component.literal(message).withStyle(ChatFormatting.GRAY)), false);
    }

    private static void detail(CommandSourceStack source, String message) {
        source.sendSuccess(() -> Component.literal(message).withStyle(ChatFormatting.GRAY), false);
    }
}
