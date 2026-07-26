package dev.projecteclipse.eclipse.minigames;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.item.DyeColor;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.entity.SignBlockEntity;
import net.minecraft.world.level.block.entity.SignText;
import net.minecraft.world.level.block.state.BlockState;

/**
 * The minigame signboards ("Aushänge") — the notice boards both courses carry at their
 * entrance: the arena lobby pillar and the race gantry pillars.
 *
 * <p>{@link CourseBlocks} only moves block STATES, but a readable board needs the sign
 * BLOCK ENTITY's text — so a course hands its {@link SignSpec}s here from the
 * build-completion callback in {@link MinigameService}, after the budgeted build landed.
 * The pass is idempotent (it rewrites the same lines on every rebuild) and safe on cold
 * chunks: the sign block is (re)placed first, which loads the chunk and creates the block
 * entity. Lines stay {@link Component#translatable}, so a board reads German or English
 * depending on the viewer's client, exactly like vanilla sign text.</p>
 */
public final class MinigameSigns {

    /**
     * A signboard: the sign block plus the lines written into its block entity once the
     * budgeted build lands.
     */
    public record SignSpec(BlockPos pos, BlockState state, List<Component> lines, DyeColor color) {}

    private MinigameSigns() {}

    /**
     * Wall-sign state facing {@code facing} — the board hangs on the block BEHIND it
     * ({@code pos.relative(facing.getOpposite())}), which every caller must provide.
     */
    public static BlockState wallSign(Direction facing) {
        return Blocks.SPRUCE_WALL_SIGN.defaultBlockState()
                .setValue(HorizontalDirectionalBlock.FACING, facing);
    }

    /** Places every board and writes its lines; waxed so nobody can edit the rules away. */
    public static void apply(ServerLevel level, List<SignSpec> signs) {
        int written = 0;
        for (SignSpec spec : signs) {
            BlockPos pos = spec.pos();
            level.setBlock(pos, spec.state(), 3);
            if (!(level.getBlockEntity(pos) instanceof SignBlockEntity sign)) {
                EclipseMod.LOGGER.warn("Minigame signboard at {} has no sign block entity", pos);
                continue;
            }
            List<Component> lines = spec.lines();
            sign.updateText(text -> {
                SignText updated = text.setColor(spec.color());
                for (int line = 0; line < SignText.LINES; line++) {
                    updated = updated.setMessage(line,
                            line < lines.size() ? lines.get(line) : Component.empty());
                }
                return updated.setHasGlowingText(true);
            }, true);
            sign.setWaxed(true);
            sign.setChanged();
            level.sendBlockUpdated(pos, spec.state(), spec.state(), 3);
            written++;
        }
        EclipseMod.LOGGER.info("Minigame signboards written in {}: {}",
                level.dimension().location(), written);
    }
}
