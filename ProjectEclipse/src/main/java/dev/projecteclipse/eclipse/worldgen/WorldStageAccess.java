package dev.projecteclipse.eclipse.worldgen;

/**
 * Static seam between the chunk generator and the persisted world stage.
 *
 * <p>{@link DiscChunkGenerator#fillFromNoise} runs on worldgen worker threads where a
 * {@code MinecraftServer} lookup is unsafe/unavailable, so the generator reads the
 * CURRENT COMMITTED stage from these volatile fields instead. They default to stage 0
 * (pre-intro geometry: main disc + player discs; empty nether).</p>
 *
 * <p>Worker 4's {@code WorldStageService} is responsible for connecting this seam to
 * {@code EclipseWorldState}: call {@link #setStage} once on server start (with the
 * persisted stage) and again on every stage commit, from the server thread, BEFORE any
 * new chunk of the grown annulus can generate.</p>
 *
 * <p>Stage <em>radii</em> come from the per-save freeze ({@link FrozenParams} →
 * {@link StageRadii}) on {@link net.neoforged.neoforge.event.server.ServerAboutToStartEvent};
 * {@link net.neoforged.neoforge.event.server.ServerStoppedEvent} resets both this class and
 * {@link StageRadii} to defaults (W1.9 / D9).</p>
 */
public final class WorldStageAccess {
    private static volatile int overworldStage = 0;
    private static volatile int netherStage = 0;

    private WorldStageAccess() {}

    /** The current committed stage of the given disc profile (default 0). */
    public static int stage(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? netherStage : overworldStage;
    }

    /** Publishes a committed stage (server thread; worldgen threads see it via volatile read). */
    public static void setStage(DiscProfile profile, int stage) {
        int clamped = Math.max(0, stage);
        if (profile == DiscProfile.NETHER) {
            netherStage = clamped;
        } else {
            overworldStage = clamped;
        }
    }
}
