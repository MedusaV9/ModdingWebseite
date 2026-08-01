package dev.projecteclipse.eclipse.veilfx;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.sky.LimboSpecialEffects;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * F-104 (IDEA-18 §4/§7/§10) — the Limbo rowing soundscape, ticked from
 * {@link LimboAmbience#onClientTick} while the local level is {@code eclipse:limbo}
 * (inside the existing {@code inLimbo && !isPaused} branch). Three lanes, one clock:
 *
 * <ul>
 *   <li><b>Row dirge (§4)</b> — on every 60&nbsp;t row-clock boundary
 *       ({@code gameTime % ROW_SYNC_PERIOD_TICKS == 0}, the catch beat the blade splash
 *       rides) one low positioned {@code note_block.didgeridoo} hum at the nearest seated
 *       rower. The melody is procedural: a fixed minor-pentatonic pitch table indexed by
 *       {@code (gameTime / 60) % 8} — deterministic and identical on every client, no new
 *       audio asset — and every 4th cycle rests (silence sells a dirge).</li>
 *   <li><b>Rigging creaks (§10)</b> — the hull answers on the <i>recovery</i> beat
 *       (phase {@value #RECOVERY_PHASE}, opposite the catch): one quiet, low-pitched wood
 *       groan or chain clink from a hash-picked point along the gunwale (bench columns ×
 *       {@link GhostShipBuilder#halfWidthAt}, deck Y from the {@code ship_deck} anchor).
 *       Only within {@value #SHIP_EARSHOT} blocks of the ship anchor.</li>
 *   <li><b>Drowned bells (§7)</b> — every 2400–4800&nbsp;t one muffled
 *       {@code boss.ferryman_bell} from <i>below</i> the sea (y = waterline − 12,
 *       40–80 blocks off the beam), pitched down and quiet. Sells depth with zero new
 *       assets.</li>
 * </ul>
 *
 * <p><b>Guards</b>: the dirge and the creaks die while the tilt cutscene holds the crew
 * (any scanned deckhand's synced {@code isTilt()} — the client mirror of
 * {@code OarAnimator.isTiltActive}) and while the crew is risen (any scanned deckhand
 * {@code isHostile()} — the fight owns the soundscape then). The bell never tolls while a
 * {@link FerrymanEntity} is within render distance (client-side proxy for "the Ferryman
 * fight is audible" — the real bell must stay unambiguous); the entity scans run at fire
 * cadence only, never per tick.</p>
 *
 * <p><b>reducedFx</b> halves every cadence (the {@code BorderFxRenderer} pattern): dirge
 * and creaks fire on even cycles only, the bell interval doubles. All state is static and
 * reset by {@link #reset()} on dimension change / disconnect (the {@link LimboAmbience}
 * window-clear seam), so no countdown or dedupe mark survives into the next visit.</p>
 *
 * <p>Every fire carries a DEBUG log probe ({@code Limbo row chant note … } /
 * {@code Limbo rigging creak …} / {@code Limbo bell toll @…}) so the cadence and the
 * guard behavior are verifiable from {@code logs/debug.log} without audio hardware.</p>
 */
public final class LimboRowChant {
    /**
     * Minor-pentatonic dirge pitches indexed by {@code (gameTime / 60) % 8} (IDEA-18 §4's
     * table). Values sit in the didgeridoo's low register; 0.5 = the drone root.
     */
    private static final float[] DIRGE_PITCHES = {
            0.5F, 0.53F, 0.5F, 0.594F, 0.5F, 0.445F, 0.5F, 0.53F};
    /** The shared 60 t row clock ({@code DeckhandEntity.ROW_SYNC_PERIOD_TICKS}). */
    private static final int ROW_PERIOD = DeckhandEntity.ROW_SYNC_PERIOD_TICKS;
    /** Recovery-beat phase (ticks into the cycle) — opposite the catch splash at 0–4. */
    private static final int RECOVERY_PHASE = 30;
    /** Crew scan half-extent around the camera (blocks) — IDEA-18 §4's 24-block AABB. */
    private static final double CREW_SCAN_RANGE = 24.0D;
    /** Creaks only play while the camera is this close to the ship anchor (§10). */
    private static final double SHIP_EARSHOT = 28.0D;
    /** Bench columns along the hull (mirrors {@code DeckhandEntity.BENCH_X} — frozen). */
    private static final int[] BENCH_X = {-12, -4, 4, 12};

    /** Bell toll interval bounds (ticks): 2–4 minutes between tolls (IDEA-18 §7). */
    private static final int BELL_MIN_INTERVAL_TICKS = 2400;
    private static final int BELL_MAX_INTERVAL_TICKS = 4800;
    /** Toll placement: 40–80 blocks off the beam, {@value #BELL_DEPTH} below the waterline. */
    private static final double BELL_MIN_DISTANCE = 40.0D;
    private static final double BELL_MAX_DISTANCE = 80.0D;
    private static final double BELL_DEPTH = 12.0D;
    /** Ferryman guard scan half-extent (blocks) — "within render distance" proxy. */
    private static final double FERRYMAN_SCAN_RANGE = 160.0D;

    /** Cycle dedupe marks (one fire per 60 t boundary, robust against tick hiccups). */
    private static long lastChantCycle = Long.MIN_VALUE;
    private static long lastCreakCycle = Long.MIN_VALUE;
    /** Ticks until the next bell toll attempt; {@code <= 0} re-arms a fresh interval. */
    private static int bellCountdown;

    private LimboRowChant() {}

    /** Ticked from {@code LimboAmbience.onClientTick} (in-limbo, unpaused only). */
    static void tick(Minecraft minecraft, ClientLevel level) {
        long gameTime = level.getGameTime();
        tickBell(minecraft, level, gameTime);
        int phase = (int) Math.floorMod(gameTime, ROW_PERIOD);
        if (phase == 0) {
            fireChant(minecraft, level, gameTime);
        } else if (phase == RECOVERY_PHASE) {
            fireCreak(minecraft, level, gameTime);
        }
    }

    /** Dimension-change / disconnect reset (the LimboAmbience window-clear seam). */
    static void reset() {
        lastChantCycle = Long.MIN_VALUE;
        lastCreakCycle = Long.MIN_VALUE;
        bellCountdown = 0;
    }

    // ------------------------------------------------------------------ dirge (§4)

    private static void fireChant(Minecraft minecraft, ClientLevel level, long gameTime) {
        long cycle = gameTime / ROW_PERIOD;
        if (cycle == lastChantCycle) {
            return;
        }
        lastChantCycle = cycle;
        // reducedFx halves the cadence (BorderFxRenderer pattern): even cycles only.
        if (EclipseClientConfig.reducedFx() && (cycle & 1L) != 0L) {
            return;
        }
        // Every 4th cycle rests — silence sells a dirge (IDEA-18 §4).
        if ((cycle & 3L) == 3L) {
            return;
        }
        DeckhandEntity singer = scanCrew(minecraft, level);
        if (singer == null) {
            return; // no seated crew in earshot, or the tilt/hostile guard tripped
        }
        float pitch = DIRGE_PITCHES[(int) (cycle % DIRGE_PITCHES.length)];
        level.playLocalSound(singer.getX(), singer.getY() + 1.2D, singer.getZ(),
                SoundEvents.NOTE_BLOCK_DIDGERIDOO.value(), SoundSource.AMBIENT,
                0.25F, pitch, false);
        EclipseMod.LOGGER.debug("Limbo row chant note {} (cycle {}) @ {} {} {}",
                pitch, cycle, singer.getX(), singer.getY(), singer.getZ());
    }

    /**
     * The nearest seated rower within {@value #CREW_SCAN_RANGE} blocks of the camera —
     * or {@code null} while the crew must stay silent: the cutscene tilt
     * ({@code isTilt()}, the synced client mirror of {@code OarAnimator.isTiltActive})
     * and the risen crew ({@code isHostile()}) both silence the WHOLE chant, not just
     * the flagged rower — the keel-over and the fight own the soundscape.
     */
    private static DeckhandEntity scanCrew(Minecraft minecraft, ClientLevel level) {
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        List<DeckhandEntity> crew = level.getEntitiesOfClass(DeckhandEntity.class,
                AABB.ofSize(camera, CREW_SCAN_RANGE * 2.0D, CREW_SCAN_RANGE, CREW_SCAN_RANGE * 2.0D));
        DeckhandEntity nearest = null;
        double nearestDistSqr = Double.MAX_VALUE;
        for (DeckhandEntity rower : crew) {
            if (rower.isTilt() || rower.isHostile()) {
                return null;
            }
            if (!rower.isAlive()) {
                continue;
            }
            double distSqr = rower.distanceToSqr(camera.x, camera.y, camera.z);
            if (distSqr < nearestDistSqr) {
                nearestDistSqr = distSqr;
                nearest = rower;
            }
        }
        return nearest;
    }

    // ------------------------------------------------------------------ creaks (§10)

    private static void fireCreak(Minecraft minecraft, ClientLevel level, long gameTime) {
        long cycle = gameTime / ROW_PERIOD;
        if (cycle == lastCreakCycle) {
            return;
        }
        lastCreakCycle = cycle;
        if (EclipseClientConfig.reducedFx() && (cycle & 1L) != 0L) {
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.SHIP_DECK);
        if (anchor == null) {
            return; // anchor not synced yet — no hull to creak
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        if (camera.distanceToSqr(anchor) > SHIP_EARSHOT * SHIP_EARSHOT) {
            return;
        }
        // Same tilt/hostile guards as the dirge — one organism (IDEA-18 §10).
        if (scanCrew(minecraft, level) == null) {
            return;
        }
        // Hash-picked gunwale point: a bench column on a hashed side, at the hull's
        // half-width there; deterministic per cycle (all clients creak the same spot).
        int bench = BENCH_X[(int) (hash01((int) (cycle & 0x7FFFFFFFL), 11) * BENCH_X.length)
                & (BENCH_X.length - 1)];
        double side = hash01((int) (cycle & 0x7FFFFFFFL), 13) < 0.5D ? -1.0D : 1.0D;
        double x = anchor.x + bench;
        double z = anchor.z + side * GhostShipBuilder.halfWidthAt(bench);
        double y = anchor.y;
        boolean chain = hash01((int) (cycle & 0x7FFFFFFFL), 17) < 0.5D;
        float pitch = 0.5F + (float) hash01((int) (cycle & 0x7FFFFFFFL), 19) * 0.2F;
        level.playLocalSound(x, y, z,
                chain ? SoundEvents.CHAIN_STEP : SoundEvents.BAMBOO_WOOD_HANGING_SIGN_STEP,
                SoundSource.AMBIENT, 0.18F, pitch, false);
        EclipseMod.LOGGER.debug("Limbo rigging creak {} (cycle {}) @ {} {} {}",
                chain ? "chain" : "wood", cycle, x, y, z);
    }

    // ------------------------------------------------------------------ bells (§7)

    private static void tickBell(Minecraft minecraft, ClientLevel level, long gameTime) {
        if (bellCountdown <= 0) {
            RandomSource random = level.random;
            int interval = random.nextIntBetweenInclusive(
                    BELL_MIN_INTERVAL_TICKS, BELL_MAX_INTERVAL_TICKS);
            // reducedFx halves the toll cadence by doubling the interval.
            bellCountdown = EclipseClientConfig.reducedFx() ? interval * 2 : interval;
            return;
        }
        if (--bellCountdown > 0) {
            return;
        }
        // Guard (scan at toll cadence only, never per tick): no toll while the Ferryman
        // is within render distance — the fight's real bell must stay unambiguous.
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        if (!level.getEntitiesOfClass(FerrymanEntity.class,
                AABB.ofSize(camera, FERRYMAN_SCAN_RANGE * 2.0D, FERRYMAN_SCAN_RANGE * 2.0D,
                        FERRYMAN_SCAN_RANGE * 2.0D)).isEmpty()) {
            EclipseMod.LOGGER.debug("Limbo bell toll suppressed (Ferryman in range)");
            return; // countdown is 0 → the next tick re-arms a fresh full interval
        }
        RandomSource random = level.random;
        double angle = random.nextDouble() * Math.PI * 2.0D;
        double distance = BELL_MIN_DISTANCE
                + random.nextDouble() * (BELL_MAX_DISTANCE - BELL_MIN_DISTANCE);
        double x = camera.x + Math.cos(angle) * distance;
        double z = camera.z + Math.sin(angle) * distance;
        double y = LimboSpecialEffects.clientWaterlineY(level) - BELL_DEPTH;
        level.playLocalSound(x, y, z, EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                SoundSource.AMBIENT, 0.35F, 0.55F, false);
        EclipseMod.LOGGER.debug("Limbo bell toll @ {} {} {} ({} blocks out)",
                Mth.floor(x), Mth.floor(y), Mth.floor(z), Mth.floor(distance));
    }

    /**
     * Fixed-seed hash 0..1 (the {@code LimboSeascape.hash01} mixer with an own salt so
     * the creak picks cannot correlate with the storm/shoal/ship schedules) —
     * deterministic on every client.
     */
    private static double hash01(int a, int b) {
        long h = DiscMapData.ECLIPSE_SEED ^ (a * 341873128712L + b * 132897987541L + 0x6E1F35C9L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
    }
}
