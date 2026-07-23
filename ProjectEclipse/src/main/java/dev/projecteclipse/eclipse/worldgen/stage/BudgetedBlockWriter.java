package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.Comparator;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.SectionPos;
import net.minecraft.network.protocol.game.ClientboundLevelChunkWithLightPacket;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.level.ThreadedLevelLightEngine;
import net.minecraft.server.level.TicketType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.LightLayer;
import net.minecraft.world.level.chunk.LevelChunk;

/**
 * Shared machinery of the tick-budgeted bulk chunk writers (W14 refactor out of
 * {@link RingGrowthService}; also used by {@code devtools.StageIO}'s snapshot loader):
 * short-lived load tickets for chunks that must be rewritten, and the
 * relight-and-resend pass a chunk needs after its sections were mutated directly
 * (bypassing {@code Level.setBlock} — the flag 2|16 equivalent for bulk section writes).
 * Callers own their budget loop; behavior of the extracted pieces is byte-identical to
 * the pre-refactor {@code RingGrowthService} code.
 */
public final class BudgetedBlockWriter {
    /** Keeps freshly loaded chunks around long enough to rewrite + relight + resend. */
    public static final TicketType<ChunkPos> WRITER_TICKET =
            TicketType.create("eclipse_ring_growth", Comparator.comparingLong(ChunkPos::toLong), 200);

    /**
     * Keeps a bulk-rewritten chunk loaded until its async relight callback lands. A sweep
     * can queue thousands of light rebuilds, so {@code waitForPendingTasks} may complete
     * well after {@link #WRITER_TICKET}'s 200-tick TTL — an unloaded chunk at callback
     * time silently leaves watching clients with stale lighting. Rather than tracking and
     * refreshing tickets per pending relight, the TTL is raised to comfortably outlast a
     * saturated light queue (600 ticks = 30 s; measured worst-case drain during a full
     * stage sweep is far below that); the callback logs if a chunk still fell out.
     */
    private static final TicketType<ChunkPos> RELIGHT_TICKET =
            TicketType.create("eclipse_relight", Comparator.comparingLong(ChunkPos::toLong), 600);

    private BudgetedBlockWriter() {}

    /** Sync-loads a chunk from disk (or generates it) under a short-lived {@link #WRITER_TICKET}. */
    public static LevelChunk loadWithTicket(ServerLevel level, int chunkX, int chunkZ) {
        ChunkPos pos = new ChunkPos(chunkX, chunkZ);
        level.getChunkSource().addRegionTicket(WRITER_TICKET, pos, 1, pos);
        return level.getChunk(chunkX, chunkZ);
    }

    /**
     * Rebuilds a bulk-rewritten chunk's light through the light-engine task queue —
     * clear (mirrors vanilla {@code updateChunkStatus}) then re-init + propagate (mirrors
     * {@code initializeLight} + {@code lightChunk}; 1.21.1 has no {@code relight} helper)
     * — and resends the chunk to watching clients once the light tasks drain. The caller
     * must have re-primed heightmaps and dropped orphaned block entities already.
     */
    public static void relightAndResend(ServerLevel level, LevelChunk chunk) {
        ChunkPos pos = chunk.getPos();
        level.getChunkSource().addRegionTicket(RELIGHT_TICKET, pos, 1, pos);
        chunk.initializeLightSources();
        chunk.setUnsaved(true);
        chunk.setLightCorrect(false);

        ThreadedLevelLightEngine light = level.getChunkSource().getLightEngine();
        light.retainData(pos, false);
        light.setLightEnabled(pos, false);
        for (int section = light.getMinLightSection(); section < light.getMaxLightSection(); section++) {
            light.queueSectionData(LightLayer.BLOCK, SectionPos.of(pos, section), null);
            light.queueSectionData(LightLayer.SKY, SectionPos.of(pos, section), null);
        }
        for (int section = level.getMinSection(); section < level.getMaxSection(); section++) {
            light.updateSectionStatus(SectionPos.of(pos, section), true);
        }
        for (int index = 0; index < chunk.getSectionsCount(); index++) {
            if (!chunk.getSection(index).hasOnlyAir()) {
                light.updateSectionStatus(
                        SectionPos.of(pos, level.getSectionYFromSectionIndex(index)), false);
            }
        }
        light.propagateLightSources(pos);
        light.waitForPendingTasks(pos.x, pos.z).thenRunAsync(() -> {
            LevelChunk lit = level.getChunkSource().getChunkNow(pos.x, pos.z);
            if (lit == null) {
                // Should not happen under the 600-tick RELIGHT_TICKET; if it does, any
                // client still watching this chunk keeps pre-rewrite lighting until the
                // chunk reloads (light data was persisted, so this is display-only).
                EclipseMod.LOGGER.warn(
                        "Relight callback found chunk {} unloaded in {} — client lighting may be stale",
                        pos, level.dimension().location());
                return;
            }
            lit.setLightCorrect(true);
            ClientboundLevelChunkWithLightPacket packet = new ClientboundLevelChunkWithLightPacket(
                    lit, level.getChunkSource().getLightEngine(), null, null);
            for (ServerPlayer player : level.getChunkSource().chunkMap.getPlayers(pos, false)) {
                player.connection.send(packet);
            }
        }, level.getServer());
    }
}
