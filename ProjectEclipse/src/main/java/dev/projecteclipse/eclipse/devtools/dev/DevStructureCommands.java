package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import javax.annotation.Nullable;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import dev.projecteclipse.eclipse.worldgen.structure.StructureGrounding;
import dev.projecteclipse.eclipse.worldgen.structure.VanillaLandmarks;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.ResourceLocationArgument;
import net.minecraft.commands.arguments.coordinates.BlockPosArgument;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.core.Vec3i;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.Structure;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructurePlaceSettings;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructureTemplate;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * F-054 — {@code /dev structure …}: place ANY Minecraft/datapack structure on the disc,
 * grounded the way the world's own landmarks are grounded.
 *
 * <p>Minecraft keeps structures in two unrelated places and vanilla's {@code /place}
 * mirrors that split with two subcommands the operator has to pick correctly up front:</p>
 *
 * <ul>
 *   <li><b>configured structures</b> — {@link Registries#STRUCTURE} entries
 *       ({@code minecraft:village_plains}, {@code minecraft:ancient_city}, any datapack
 *       structure). They are GENERATED (biome checks, jigsaw assembly, loot seeds) before
 *       anything is pasted;</li>
 *   <li><b>templates</b> — the raw {@code .nbt} blobs of the
 *       {@code StructureTemplateManager} ({@code minecraft:igloo/top}, every piece of every
 *       jigsaw pool, and anything an operator saved from a structure block). They are
 *       pasted verbatim.</li>
 * </ul>
 *
 * <p>{@code place} resolves the id against both and picks whichever answers (registry
 * first — a datapack that ships an {@code x:y} structure AND an {@code x:y} template means
 * the assembled one); {@code configured} / {@code template} force one lane when that
 * matters. All three suggest their own id set, so tab completion is the discovery tool.</p>
 *
 * <p><b>Grounding.</b> The disc's terrain is deterministic and its landmarks are seated by
 * {@link StructureGrounding} — footprint-minimum seat, {@link SitePrep} plateau, foundation
 * fill — so a dev-placed structure goes through the SAME pipeline instead of vanilla's
 * "paste at the chunk's own idea of the ground" and floating half a hillside. Configured
 * structures reuse {@link VanillaLandmarks#placeVanillaAsync} whole; templates run the
 * three steps directly (seat → plateau → paste → {@link StructureGrounding#fillFoundations}).
 * Because SitePrep is tick-budgeted, the grounded path REPORTS as queued and the placement
 * lands a few ticks later — the success/failure message arrives then.</p>
 *
 * <p>Two escape hatches: {@code exact} after an explicit position pastes verbatim at that
 * position with no terraforming (the only way to put an ancient city back underground), and
 * non-disc dimensions (limbo, backrooms — no {@link DiscProfile}) automatically fall back to
 * that same raw path, seated on the live heightmap.</p>
 *
 * <pre>
 * /dev structure place &lt;id&gt; [x y z] [exact]
 * /dev structure configured &lt;id&gt; [x y z] [exact]
 * /dev structure template &lt;id&gt; [x y z] [exact]
 * /dev structure list [filter]
 * </pre>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevStructureCommands {
    /** Ids one {@code list} page prints per lane before it reports the remainder. */
    private static final int LIST_LIMIT = 30;

    /** Which id space a branch resolves against. */
    private enum Lane {
        /** Registry first, template second — the {@code place} branch. */
        AUTO,
        CONFIGURED,
        TEMPLATE
    }

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("structure.place", DevCategory.STAGE,
                        "/dev structure place", "dev.eclipse.doc.structure.place",
                        Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("structure.configured", DevCategory.STAGE,
                        "/dev structure configured", "dev.eclipse.doc.structure.configured",
                        Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("structure.template", DevCategory.STAGE,
                        "/dev structure template", "dev.eclipse.doc.structure.template",
                        Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("structure.list", DevCategory.STAGE,
                        "/dev structure list", "dev.eclipse.doc.structure.list",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevStructureCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("structure")
                        .then(Commands.literal("list")
                                .executes(context -> list(context, ""))
                                .then(Commands.argument("filter", StringArgumentType.greedyString())
                                        .executes(context -> list(context,
                                                StringArgumentType.getString(context, "filter")))))
                        .then(branch("place", Lane.AUTO))
                        .then(branch("configured", Lane.CONFIGURED))
                        .then(branch("template", Lane.TEMPLATE))));
    }

    /** {@code <lane> <id> [x y z] [exact]} — one shape for all three id lanes. */
    private static LiteralArgumentBuilder<CommandSourceStack> branch(String literal, Lane lane) {
        return Commands.literal(literal)
                .then(Commands.argument("id", ResourceLocationArgument.id())
                        .suggests(suggestions(lane))
                        // No position: the operator's own feet (the "hier" case).
                        .executes(context -> place(context, lane, null, false))
                        .then(Commands.argument("pos", BlockPosArgument.blockPos())
                                .executes(context -> place(context, lane,
                                        BlockPosArgument.getBlockPos(context, "pos"), false))
                                .then(Commands.literal("exact")
                                        .executes(context -> place(context, lane,
                                                BlockPosArgument.getBlockPos(context, "pos"), true)))));
    }

    // ------------------------------------------------------------------ suggestions

    private static SuggestionProvider<CommandSourceStack> suggestions(Lane lane) {
        return (context, builder) -> SharedSuggestionProvider.suggestResource(
                ids(context.getSource(), lane), builder);
    }

    /** Every id the lane can place, in the order {@link Lane#AUTO} resolves them. */
    private static Stream<ResourceLocation> ids(CommandSourceStack source, Lane lane) {
        Stream<ResourceLocation> configured = lane == Lane.TEMPLATE ? Stream.empty()
                : source.registryAccess().registryOrThrow(Registries.STRUCTURE).keySet().stream();
        Stream<ResourceLocation> templates = lane == Lane.CONFIGURED ? Stream.empty()
                : source.getLevel().getStructureManager().listTemplates();
        return Stream.concat(configured, templates);
    }

    // ------------------------------------------------------------------ list

    private static int list(CommandContext<CommandSourceStack> context, String filter) {
        CommandSourceStack source = context.getSource();
        String needle = filter.strip().toLowerCase(java.util.Locale.ROOT);
        List<ResourceLocation> configured = matching(ids(source, Lane.CONFIGURED), needle);
        List<ResourceLocation> templates = matching(ids(source, Lane.TEMPLATE), needle);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.list.header",
                configured.size(), templates.size(),
                needle.isEmpty() ? "*" : needle), false);
        if (configured.isEmpty() && templates.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.list.empty"), false);
            return 0;
        }
        printLane(source, "configured", configured);
        printLane(source, "template", templates);
        return configured.size() + templates.size();
    }

    private static List<ResourceLocation> matching(Stream<ResourceLocation> ids, String needle) {
        return ids.filter(id -> needle.isEmpty() || id.toString().contains(needle))
                .sorted(java.util.Comparator.comparing(ResourceLocation::toString))
                .toList();
    }

    private static void printLane(CommandSourceStack source, String label, List<ResourceLocation> ids) {
        if (ids.isEmpty()) {
            return;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.list.section",
                label, ids.size()), false);
        for (ResourceLocation id : ids.subList(0, Math.min(LIST_LIMIT, ids.size()))) {
            source.sendSuccess(() -> Component.literal("  " + id), false);
        }
        if (ids.size() > LIST_LIMIT) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.list.more",
                    ids.size() - LIST_LIMIT), false);
        }
    }

    // ------------------------------------------------------------------ placement

    /**
     * Resolves {@code id} in the lane's id space and hands it to the matching placer.
     *
     * @param requested explicit target, or {@code null} for the source's own position
     * @param exact     paste verbatim at {@code requested} — no seat, no terraform
     */
    private static int place(CommandContext<CommandSourceStack> context, Lane lane,
            @Nullable BlockPos requested, boolean exact) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getLevel();
        ResourceLocation id = ResourceLocationArgument.getId(context, "id");
        BlockPos target = requested != null ? requested : BlockPos.containing(source.getPosition());

        Structure configured = lane == Lane.TEMPLATE ? null
                : level.registryAccess().registryOrThrow(Registries.STRUCTURE).get(id);
        if (configured != null) {
            audit(source, "place configured structure " + id + " at " + target.toShortString()
                    + (exact ? " (exact)" : ""));
            return placeConfigured(source, level, id, configured, target, exact);
        }
        Optional<StructureTemplate> template = lane == Lane.CONFIGURED
                ? Optional.empty() : templateOf(level, id);
        if (template.isPresent()) {
            audit(source, "place structure template " + id + " at " + target.toShortString()
                    + (exact ? " (exact)" : ""));
            return placeTemplate(source, level, id, template.get(), target, exact);
        }
        source.sendFailure(Component.translatable("dev.eclipse.structure.unknown",
                id.toString(), lane.name().toLowerCase(java.util.Locale.ROOT)));
        return 0;
    }

    /** {@code get} rejects ids the template loader considers malformed rather than missing. */
    private static Optional<StructureTemplate> templateOf(ServerLevel level, ResourceLocation id) {
        try {
            return level.getStructureManager().get(id);
        } catch (RuntimeException error) {
            EclipseMod.LOGGER.warn("Structure template {} could not be read", id, error);
            return Optional.empty();
        }
    }

    // --- configured ---

    /**
     * Grounded lane: {@link VanillaLandmarks#placeVanillaAsync} in
     * {@link SitePrep.Mode#PLATEAU} — the exact pipeline the stage stamper puts
     * villages/mansions/outposts through, {@link StructureGrounding} seat and foundation
     * fill included. Falls through to {@link #placeConfiguredRaw} when the dimension has
     * no disc profile, when {@code exact} was asked for, or when generation refused (the
     * raw path re-rolls at the world seed instead of the frozen map seed and may still
     * land).
     */
    private static int placeConfigured(CommandSourceStack source, ServerLevel level,
            ResourceLocation id, Structure structure, BlockPos target, boolean exact) {
        DiscProfile profile = exact ? null : WorldStageService.profileOf(level.dimension());
        if (profile != null) {
            // Anchor Y is only the seat's fallback — placeVanillaAsync re-seats the pieces
            // on the footprint minimum itself.
            BlockPos anchor = new BlockPos(target.getX(),
                    DiscTerrainFunction.surfaceY(profile, target.getX(), target.getZ()), target.getZ());
            BoundingBox queued = VanillaLandmarks.placeVanillaAsync(level, id, anchor,
                    SitePrep.Mode.PLATEAU,
                    placed -> succeed(source, id, "configured",
                            new BlockPos(placed.minX(), placed.minY(), placed.minZ())),
                    error -> fail(source, id, error.getMessage()));
            if (queued != null) {
                source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.queued",
                        id.toString(), anchor.getX(), anchor.getY(), anchor.getZ()), false);
                EclipseMod.LOGGER.info("DEV STRUCTURE: queued grounded placement of {} at {} (bounds {})",
                        id, anchor.toShortString(), queued);
                return 1;
            }
            EclipseMod.LOGGER.warn("DEV STRUCTURE: grounded placement of {} at {} refused to generate; "
                    + "retrying on the raw /place path", id, anchor.toShortString());
        }
        return placeConfiguredRaw(source, level, id, structure, target);
    }

    /**
     * Vanilla {@code /place structure} semantics (generate at the target chunk, paste chunk
     * by chunk) with one deliberate difference: chunks in the way are force-loaded instead
     * of failing the command, because a dev target is regularly outside the loaded ring.
     */
    private static int placeConfiguredRaw(CommandSourceStack source, ServerLevel level,
            ResourceLocation id, Structure structure, BlockPos target) {
        ChunkGenerator generator = level.getChunkSource().getGenerator();
        StructureStart start;
        try {
            start = structure.generate(level.registryAccess(), generator, generator.getBiomeSource(),
                    level.getChunkSource().randomState(), level.getStructureManager(),
                    level.getSeed(), new ChunkPos(target), 0, level, biome -> true);
        } catch (RuntimeException error) {
            EclipseMod.LOGGER.error("DEV STRUCTURE: {} threw while generating at {}",
                    id, target.toShortString(), error);
            return fail(source, id, error.toString());
        }
        if (start == null || !start.isValid()) {
            return fail(source, id, "generated no valid pieces at " + target.toShortString());
        }
        BoundingBox bounds = start.getBoundingBox();
        ChunkPos min = new ChunkPos(SectionPos.blockToSectionCoord(bounds.minX()),
                SectionPos.blockToSectionCoord(bounds.minZ()));
        ChunkPos max = new ChunkPos(SectionPos.blockToSectionCoord(bounds.maxX()),
                SectionPos.blockToSectionCoord(bounds.maxZ()));
        ChunkPos.rangeClosed(min, max).forEach(chunk -> level.getChunk(chunk.x, chunk.z));
        ChunkPos.rangeClosed(min, max).forEach(chunk -> start.placeInChunk(level,
                level.structureManager(), generator, level.getRandom(),
                new BoundingBox(chunk.getMinBlockX(), level.getMinBuildHeight(), chunk.getMinBlockZ(),
                        chunk.getMaxBlockX(), level.getMaxBuildHeight(), chunk.getMaxBlockZ()),
                chunk));
        return succeed(source, id, "configured",
                new BlockPos(bounds.minX(), bounds.minY(), bounds.minZ()));
    }

    // --- template ---

    /**
     * Templates are pasted from their min corner, which makes "put it where I stand"
     * awkward, so the footprint is CENTERED on the target column and only the seat height
     * is derived. Grounded lane: footprint seat → {@link SitePrep} plateau → paste →
     * foundation fill; the bottom layer lands ON the plateau top (the same convention
     * vanilla pieces are seated with — a temple's floor row replaces the surface block
     * instead of hovering one above it).
     */
    private static int placeTemplate(CommandSourceStack source, ServerLevel level,
            ResourceLocation id, StructureTemplate template, BlockPos target, boolean exact) {
        Vec3i size = template.getSize();
        if (size.getX() < 1 || size.getY() < 1 || size.getZ() < 1) {
            return fail(source, id, "template is empty (" + size.getX() + "x" + size.getY()
                    + "x" + size.getZ() + ")");
        }
        int minX = target.getX() - size.getX() / 2;
        int minZ = target.getZ() - size.getZ() / 2;
        int maxX = minX + size.getX() - 1;
        int maxZ = minZ + size.getZ() - 1;
        DiscProfile profile = exact ? null : WorldStageService.profileOf(level.dimension());
        if (profile == null) {
            int y = exact ? target.getY()
                    : level.getHeightmapPos(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                            new BlockPos(minX, target.getY(), minZ)).getY();
            BlockPos origin = new BlockPos(minX, y, minZ);
            return paste(level, template, origin, size)
                    ? succeed(source, id, "template", origin)
                    : fail(source, id, "paste refused at " + origin.toShortString());
        }
        int seatY = StructureGrounding.seatY(profile, minX, minZ, maxX, maxZ, target.getY());
        BlockPos origin = new BlockPos(minX, seatY, minZ);
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, profile,
                minX, minZ, maxX, maxZ, seatY);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.queued",
                id.toString(), origin.getX(), origin.getY(), origin.getZ()), false);
        EclipseMod.LOGGER.info("DEV STRUCTURE: queued grounded template {} ({}x{}x{}) seated at {}",
                id, size.getX(), size.getY(), size.getZ(), origin.toShortString());
        prepared.whenReady(() -> {
            if (!paste(level, template, origin, size)) {
                fail(source, id, "paste refused at " + origin.toShortString());
                return;
            }
            BoundingBox placed = new BoundingBox(minX, seatY, minZ,
                    maxX, seatY + size.getY() - 1, maxZ);
            SitePrep.touchBounds(prepared, minX, minZ, maxX, maxZ);
            StructureGrounding.fillFoundations(level, profile, prepared, placed, () -> {
                SitePrep.finish(level, prepared);
                succeed(source, id, "template", origin);
            }, error -> fail(source, id, String.valueOf(error.getMessage())));
        }, error -> fail(source, id, String.valueOf(error.getMessage())));
        return 1;
    }

    /** Force-loads the footprint, then pastes the template with client updates only. */
    private static boolean paste(ServerLevel level, StructureTemplate template, BlockPos origin,
            Vec3i size) {
        ChunkPos min = new ChunkPos(origin);
        ChunkPos max = new ChunkPos(origin.offset(size.getX() - 1, 0, size.getZ() - 1));
        ChunkPos.rangeClosed(min, max).forEach(chunk -> level.getChunk(chunk.x, chunk.z));
        return template.placeInWorld(level, origin, origin, new StructurePlaceSettings(),
                level.getRandom(), Block.UPDATE_CLIENTS);
    }

    // ------------------------------------------------------------------ feedback

    private static int succeed(CommandSourceStack source, ResourceLocation id, String lane,
            BlockPos at) {
        source.sendSuccess(() -> Component.translatable("dev.eclipse.structure.placed",
                id.toString(), lane, at.getX(), at.getY(), at.getZ()), false);
        EclipseMod.LOGGER.info("DEV STRUCTURE: placed {} ({}) at {}", id, lane, at.toShortString());
        return 1;
    }

    private static int fail(CommandSourceStack source, ResourceLocation id, String reason) {
        source.sendFailure(Component.translatable("dev.eclipse.structure.failed",
                id.toString(), reason));
        EclipseMod.LOGGER.warn("DEV STRUCTURE: {} failed — {}", id, reason);
        return 0;
    }

    /**
     * Same operator-audit convention as the other /dev command bridges, minus the local
     * feedback line: placement reports its own outcome (and does so asynchronously on the
     * grounded path), so the audit here records the INTENT at the moment it was issued.
     */
    private static void audit(CommandSourceStack source, String logDetail) {
        Component notice = Component.literal("/dev structure: " + logDetail);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), notice));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
