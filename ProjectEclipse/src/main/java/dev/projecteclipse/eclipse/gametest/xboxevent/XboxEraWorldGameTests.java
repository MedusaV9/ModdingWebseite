package dev.projecteclipse.eclipse.gametest.xboxevent;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import dev.projecteclipse.eclipse.xboxevent.XboxWorldInstaller;
import dev.projecteclipse.eclipse.xboxevent.XboxWorldsManifest;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.tags.FluidTags;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.decoration.ItemFrame;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.RedStoneWireBlock;
import net.minecraft.world.level.block.RepeaterBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.phys.AABB;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * C17 acceptance gametests for the tutorial-world pass:
 *
 * <ul>
 *   <li>{@link #fluidsAndRedstoneClockWorkInTuWorld}: the plan's "behavior never modified"
 *       proof — VANILLA water and lava placed inside an installed TU dimension flow, and a
 *       two-repeater ring clock oscillates (the baked {@code classic_water}/{@code
 *       classic_lava} are deliberately SOLID deco; only fresh vanilla fluid is dynamic).
 *       Runs on a pad far outside the baked map bounds (void chunks) and cleans up.</li>
 *   <li>{@link #framesDecorateIdempotently}: every world's loot manifest carries a
 *       {@code frames} section, {@code decorate} hangs the tagged display frames, and a
 *       second pass never double-hangs (the {@value XboxWorldInstaller#FRAME_TAG} rule).</li>
 * </ul>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class XboxEraWorldGameTests {

    private XboxEraWorldGameTests() {}

    /** Pad origin far outside every baked bound (|block| ≤ 431) — pure void chunks. */
    private static final BlockPos PAD = new BlockPos(600, 8, 600);

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE, timeoutTicks = 400)
    public static void fluidsAndRedstoneClockWorkInTuWorld(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        ServerLevel level = server.getLevel(XboxDimensions.XBOX_TU12);
        if (level == null) {
            helper.fail("xbox_tu12 dimension not loaded");
            return;
        }
        level.setChunkForced(PAD.getX() >> 4, PAD.getZ() >> 4, true); // ticking chunk

        // ---- build: stone pad + water/lava sources + a 2-repeater ring clock ----
        for (int x = -1; x <= 7; x++) {
            for (int z = -1; z <= 7; z++) {
                level.setBlock(PAD.offset(x, 0, z), Blocks.STONE.defaultBlockState(), 3);
                level.setBlock(PAD.offset(x, 1, z), Blocks.AIR.defaultBlockState(), 3);
            }
        }
        // Fluids sit in walled 2-cell basins so the spread can never wash the ring away.
        BlockPos water = PAD.offset(6, 1, 0);
        BlockPos lava = PAD.offset(6, 1, 6);
        for (BlockPos source : List.of(water, lava)) {
            for (int[] wall : new int[][] {{-2, 0}, {1, 0}, {-1, -1}, {0, -1}, {-1, 1}, {0, 1}}) {
                level.setBlock(source.offset(wall[0], 0, wall[1]),
                        Blocks.STONE.defaultBlockState(), 3);
            }
        }
        level.setBlock(water, Blocks.WATER.defaultBlockState(), 3);
        level.setBlock(lava, Blocks.LAVA.defaultBlockState(), 3);

        // Ring: wire(0,0) → repeater(1,0 FACING=WEST: in from west, out to east) → wires
        // (2,0),(2,1),(2,2) → repeater(1,2 FACING=EAST) → wires (0,2),(0,1) → back.
        // Period 2×(4-delay repeater) = 16 gt — slow enough that torch-burnout rules
        // (the reason a bare torch loop cannot be a clock) never apply.
        BlockState wire = Blocks.REDSTONE_WIRE.defaultBlockState();
        for (int[] cell : new int[][] {{0, 0}, {2, 0}, {2, 1}, {2, 2}, {0, 2}, {0, 1}}) {
            level.setBlock(PAD.offset(cell[0], 1, cell[1]), wire, 3);
        }
        level.setBlock(PAD.offset(1, 1, 0), Blocks.REPEATER.defaultBlockState()
                .setValue(BlockStateProperties.HORIZONTAL_FACING, Direction.WEST)
                .setValue(RepeaterBlock.DELAY, 4), 3);
        level.setBlock(PAD.offset(1, 1, 2), Blocks.REPEATER.defaultBlockState()
                .setValue(BlockStateProperties.HORIZONTAL_FACING, Direction.EAST)
                .setValue(RepeaterBlock.DELAY, 4), 3);
        // Pulse injection: a redstone block beside wire (0,0), removed after 10 gt.
        BlockPos pulse = PAD.offset(-1, 1, 0);
        level.setBlock(pulse, Blocks.REDSTONE_BLOCK.defaultBlockState(), 3);
        helper.runAfterDelay(10, () -> level.setBlock(pulse, Blocks.AIR.defaultBlockState(), 3));

        // ---- sample the circulating pulse at wire (0,0) ----
        BlockPos probe = PAD.offset(0, 1, 0);
        List<Integer> samples = new ArrayList<>();
        for (int tick = 14; tick <= 74; tick += 4) {
            helper.runAfterDelay(tick, () -> {
                BlockState state = level.getBlockState(probe);
                if (state.is(Blocks.REDSTONE_WIRE)) {
                    samples.add(state.getValue(RedStoneWireBlock.POWER));
                }
            });
        }

        helper.runAfterDelay(120, () -> {
            helper.assertTrue(!level.getFluidState(water.west()).isEmpty()
                    && level.getFluidState(water.west()).is(FluidTags.WATER),
                    "vanilla water flows in the TU dimension");
            helper.assertTrue(!level.getFluidState(lava.west()).isEmpty()
                    && level.getFluidState(lava.west()).is(FluidTags.LAVA),
                    "vanilla lava flows in the TU dimension");
            helper.assertTrue(samples.stream().anyMatch(power -> power > 0),
                    "clock pulse observed HIGH at the probe wire");
            helper.assertTrue(samples.stream().anyMatch(power -> power == 0),
                    "clock pulse observed LOW at the probe wire (oscillates)");

            // cleanup: leave the void chunk exactly as found
            for (int x = -1; x <= 7; x++) {
                for (int z = -1; z <= 7; z++) {
                    level.setBlock(PAD.offset(x, 1, z), Blocks.AIR.defaultBlockState(), 3);
                    level.setBlock(PAD.offset(x, 0, z), Blocks.AIR.defaultBlockState(), 3);
                }
            }
            level.setChunkForced(PAD.getX() >> 4, PAD.getZ() >> 4, false);
            helper.succeed();
        });
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE, timeoutTicks = 200)
    public static void framesDecorateIdempotently(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        for (String worldId : XboxWorldsManifest.all().keySet()) {
            helper.assertTrue(!XboxWorldsManifest.frames(server, worldId).isEmpty(),
                    worldId + " loot manifest has a frames section");
        }

        ServerLevel level = server.getLevel(XboxDimensions.XBOX_TU12);
        if (level == null) {
            helper.fail("xbox_tu12 dimension not loaded");
            return;
        }
        XboxWorldInstaller.decorate(server, "tu12");
        int placed = taggedFrames(level).size();
        helper.assertTrue(placed >= 4,
                "decorate hangs the display frames (got " + placed + " of "
                        + XboxWorldsManifest.frames(server, "tu12").size() + ")");
        XboxWorldInstaller.decorate(server, "tu12");
        helper.assertTrue(taggedFrames(level).size() == placed,
                "second decorate pass never double-hangs (tag idempotency)");
        helper.succeed();
    }

    private static List<Entity> taggedFrames(ServerLevel level) {
        BlockPos spawn = XboxWorldsManifest.byId("tu12").orElseThrow().spawn();
        return level.getEntities((Entity) null, new AABB(spawn).inflate(64.0D),
                entity -> entity instanceof ItemFrame
                        && entity.getTags().contains(XboxWorldInstaller.FRAME_TAG));
    }
}
