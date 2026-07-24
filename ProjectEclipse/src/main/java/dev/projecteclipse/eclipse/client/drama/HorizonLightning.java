package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.sky.OverworldPurpleEffects;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.stormfx.StormFxClient;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.SectionPos;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Distant horizon lightning at night (FIX-5, IDEAS-C #1): every
 * {@value #MIN_INTERVAL_TICKS}–{@value #MAX_INTERVAL_TICKS} ticks (30–90&nbsp;s) a silent,
 * low-intensity violet bolt flickers on the horizon — "the storms are still out there" —
 * with zero server traffic. Reuses the frozen {@link StormFxClient#strikeLightning}
 * client entry point (full jittered ribbon bolt + impact flash + budgeted point light).
 *
 * <p>Gates (all client-local): overworld only, deep night
 * ({@link OverworldPurpleEffects#dayFactor} {@code < }{@value #NIGHT_DAY_FACTOR_MAX}),
 * never during cutscene flights ({@link CameraDirector#isActive()}), expansion-sequence
 * sky moments ({@code ClientStateCache.stageAnimating*}) or a scripted eclipse phase
 * ({@link EclipseFxState#eclipsePhase()}). Each beat charges one
 * {@link FxBudget.Channel#AMBIENT} slot before firing, so tier 0 disables it outright and
 * a refused beat is skipped, not queued; {@code reducedFx} additionally doubles the
 * cadence (the {@code LimboAmbience} convention). Deliberately silent — the distance IS
 * the statement (senders own strike audio per the {@code strikeLightning} contract).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class HorizonLightning {
    /** Beat cadence: 30–90 s randomized. */
    private static final int MIN_INTERVAL_TICKS = 600;
    private static final int MAX_INTERVAL_TICKS = 1_800;
    /** Deep-night gate (IDEAS-C #1: {@code dayFactor < 0.1}). */
    private static final float NIGHT_DAY_FACTOR_MAX = 0.1F;
    /** Strike ring around the camera (blocks) — far enough to read as horizon. */
    private static final double DIST_MIN = 120.0D;
    private static final double DIST_MAX = 180.0D;
    /** Low intensity band (0.15–0.3) — a flicker, not a set piece. */
    private static final float INTENSITY_MIN = 0.15F;
    private static final float INTENSITY_SPAN = 0.15F;
    /** Sky origin height above the impact point. */
    private static final double BOLT_HEIGHT_MIN = 70.0D;
    private static final double BOLT_HEIGHT_SPAN = 40.0D;

    /** Ticks until the next beat; primed so the first bolt never fires on world join. */
    private static int countdown = MAX_INTERVAL_TICKS;

    private HorizonLightning() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            countdown = MAX_INTERVAL_TICKS; // re-prime for the next session
            return;
        }
        if (minecraft.isPaused() || level.dimension() != Level.OVERWORLD) {
            return;
        }
        if (--countdown > 0) {
            return;
        }
        RandomSource random = level.random;
        int interval = random.nextIntBetweenInclusive(MIN_INTERVAL_TICKS, MAX_INTERVAL_TICKS);
        // reducedFx doubles ambient cadence on top of the budget's own halving.
        countdown = FxBudget.qualityTier() >= 2 ? interval : interval * 2;

        // A failed gate skips THIS beat (no queueing — missed flickers stay missed).
        if (OverworldPurpleEffects.dayFactor(level, 1.0F) >= NIGHT_DAY_FACTOR_MAX
                || CameraDirector.isActive()
                || ClientStateCache.stageAnimatingOverworld
                || ClientStateCache.stageAnimatingNether
                || EclipseFxState.eclipsePhase() != EclipseFxState.PHASE_NONE) {
            return;
        }
        if (!FxBudget.tryEmitter(FxBudget.Channel.AMBIENT)) {
            return;
        }

        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        double azimuth = random.nextDouble() * Math.PI * 2.0D;
        double distance = DIST_MIN + random.nextDouble() * (DIST_MAX - DIST_MIN);
        double x = camera.x + Math.cos(azimuth) * distance;
        double z = camera.z + Math.sin(azimuth) * distance;
        Vec3 impact = new Vec3(x, groundY(level, camera, x, z), z);
        Vec3 from = impact.add((random.nextDouble() - 0.5D) * 14.0D,
                BOLT_HEIGHT_MIN + random.nextDouble() * BOLT_HEIGHT_SPAN,
                (random.nextDouble() - 0.5D) * 14.0D);
        StormFxClient.strikeLightning(from, impact,
                INTENSITY_MIN + random.nextFloat() * INTENSITY_SPAN);
    }

    /**
     * Impact height: the synced WORLD_SURFACE heightmap when the column is loaded (the
     * horizon usually is not — 120–180 blocks is beyond most render distances), otherwise
     * roughly the camera's own height, which reads fine at that distance.
     */
    private static double groundY(ClientLevel level, Vec3 camera, double x, double z) {
        int blockX = Mth.floor(x);
        int blockZ = Mth.floor(z);
        if (level.hasChunk(SectionPos.blockToSectionCoord(blockX), SectionPos.blockToSectionCoord(blockZ))) {
            int surfaceY = level.getHeight(Heightmap.Types.WORLD_SURFACE, blockX, blockZ);
            if (surfaceY > level.getMinBuildHeight()) {
                return surfaceY;
            }
        }
        return camera.y - 6.0D;
    }
}
