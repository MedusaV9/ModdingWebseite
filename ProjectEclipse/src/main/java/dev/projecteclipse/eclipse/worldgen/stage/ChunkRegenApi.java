package dev.projecteclipse.eclipse.worldgen.stage;

import javax.annotation.Nullable;

import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.ChunkPos;

/**
 * Public seam over {@link ChunkRegen} for sibling packages (PLAN-B B16 — e.g. the
 * W-SHARDS thin shell): start a deterministic chunk regeneration without depending on the
 * service internals. All calls are server-thread only; refusal semantics, structure
 * protection and pacing are documented on {@link ChunkRegen#start}.
 */
public final class ChunkRegenApi {
    private ChunkRegenApi() {}

    /**
     * Regenerates the single chunk at {@code pos} from the frozen terrain function at the
     * committed stage (structure-protected chunks are refused; no force).
     */
    public static ChunkRegen.StartResult regen(ServerLevel level, ChunkPos pos) {
        return ChunkRegen.start(level, pos, 0, false, null);
    }

    /**
     * Regenerates the square of chunks within {@code radius} (0..{@link ChunkRegen#MAX_RADIUS})
     * of {@code center}. {@code force} overrides the structure guard; {@code listener}
     * (optional) observes per-chunk progress and completion on the server thread.
     */
    public static ChunkRegen.StartResult regen(ServerLevel level, ChunkPos center, int radius,
            boolean force, @Nullable ChunkRegen.Listener listener) {
        return ChunkRegen.start(level, center, radius, force, listener);
    }

    /** Whether a regen job is currently running in the level's dimension. */
    public static boolean isRunning(ServerLevel level) {
        return ChunkRegen.isRunning(level);
    }
}
