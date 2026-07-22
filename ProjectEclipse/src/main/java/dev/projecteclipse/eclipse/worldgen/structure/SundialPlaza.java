package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.LinkedHashSet;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;

/**
 * §F flavor landmark: the sundial plaza around the sanctum. The flattened sanctum grounds
 * double as a 24-block dial — 12 chiseled-blackstone hour markers on the r=11 ring (the
 * north marker gilded), plus a polished-basalt "shadow line" from the dais edge to the ring
 * whose angle encodes the current event day (day 1 = north, one 14th of the circle per
 * day). {@code DayScheduler.setDay} calls {@link #onDayChanged}: the old line is erased by
 * re-stamping the deterministic {@link AltarSanctumBuilder#groundMix} surface, then the new
 * line is placed — ~40 blocks rewritten per day change.
 */
public final class SundialPlaza {
    /** Dial ring radius (markers sit inside the r=12 flattened grounds). */
    private static final int DIAL_RADIUS = 11;
    /** Radial extent of the shadow line (outside the dais slab skirt, inside the ring). */
    private static final int SHADOW_FROM = 7;
    private static final int SHADOW_TO = 10;
    /** Days per full dial revolution (the 14-day event arc). */
    private static final int DAYS_PER_REVOLUTION = 14;

    private SundialPlaza() {}

    /** Called by {@code DayScheduler.setDay} after a day is applied. */
    public static void onDayChanged(MinecraftServer server, int previousDay, int newDay) {
        if (previousDay == newDay) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        BlockPos altarPos = state.getSanctumAltarPos();
        if (altarPos == null) {
            return;
        }
        ServerLevel overworld = server.overworld();
        eraseShadow(overworld, altarPos, previousDay);
        placeShadow(overworld, altarPos, newDay);
        EclipseMod.LOGGER.info("Sundial shadow line moved: day {} -> {}", previousDay, newDay);
    }

    /** The 12 hour markers on the r=11 ring; north (towards −Z) is gilded. */
    static void buildDial(ServerLevel level, BlockPos altarPos) {
        int groundY = altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        for (int i = 0; i < 12; i++) {
            double angle = Math.toRadians(i * 30.0D);
            int x = altarPos.getX() + (int) Math.round(Math.sin(angle) * DIAL_RADIUS);
            int z = altarPos.getZ() - (int) Math.round(Math.cos(angle) * DIAL_RADIUS);
            level.setBlock(new BlockPos(x, groundY, z),
                    i == 0 ? Blocks.GILDED_BLACKSTONE.defaultBlockState()
                            : Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState(),
                    Block.UPDATE_ALL);
        }
    }

    /** Stamps the polished-basalt shadow line for {@code day}. */
    static void placeShadow(ServerLevel level, BlockPos altarPos, int day) {
        for (BlockPos pos : shadowLine(altarPos, day)) {
            level.setBlock(pos, Blocks.POLISHED_BASALT.defaultBlockState(), Block.UPDATE_ALL);
        }
    }

    /** Restores the deterministic ground mix under the previous day's line. */
    private static void eraseShadow(ServerLevel level, BlockPos altarPos, int day) {
        for (BlockPos pos : shadowLine(altarPos, day)) {
            level.setBlock(pos, AltarSanctumBuilder.groundMix(pos.getX(), pos.getZ()), Block.UPDATE_ALL);
        }
    }

    /** Ground positions of the shadow line for a day (day 1 = north, clockwise). */
    private static Set<BlockPos> shadowLine(BlockPos altarPos, int day) {
        int groundY = altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        double angle = Math.toRadians(Math.floorMod(day - 1, DAYS_PER_REVOLUTION)
                * (360.0D / DAYS_PER_REVOLUTION));
        Set<BlockPos> line = new LinkedHashSet<>();
        for (double d = SHADOW_FROM; d <= SHADOW_TO; d += 0.5D) {
            int x = altarPos.getX() + (int) Math.round(Math.sin(angle) * d);
            int z = altarPos.getZ() - (int) Math.round(Math.cos(angle) * d);
            line.add(new BlockPos(x, groundY, z));
        }
        return line;
    }
}
