package dev.projecteclipse.eclipse.entity.boss.fog;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Fog-bank lair marker for the Fog Tyrant ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.4 summoning row + P6-W11): marks a mature storm site as the tyrant's LAIR, dresses
 * it with ambient fog-bank columns (campfire-smoke pillars on a r={@value #BANK_RING_RADIUS}
 * ring — vanilla stand-ins until P2's {@code eclipse:fog_bank} emitter, plan §4.2), and
 * arms a proximity trigger that summons the tyrant through
 * {@link FogTyrantEntity#summonAt} the moment a player wanders within
 * {@value #TRIGGER_RANGE} blocks of the marked center.
 *
 * <p><b>The P1 seam (one line, documented in
 * {@code docs/plans_v3/wiring/WB-TYRANT_wiring.md} — this class never touches
 * {@code FogStormSites}):</b> when P1 flags its strongest/mature storm center, it calls</p>
 *
 * <pre>{@code
 * FogBankMarker.markLair(serverLevel, stormCenterBlockPos);
 * }</pre>
 *
 * <p>from wherever it materializes/restores that site (natural spots:
 * {@code FogStormSites.materializeSite}'s completion block and the restart-restore path
 * — lairs are deliberately NOT persisted here, so P1 re-marks on restore exactly like it
 * re-announces storm walls). Marking is idempotent; {@link #clearLair} /
 * {@link #clearAll} unmark (the trigger also disarms itself after a successful summon —
 * the tyrant's own abandon-reset despawn re-arms it via {@code markLair} being called
 * again, or players simply re-approaching a still-armed lair).</p>
 *
 * <p>The trigger radius ({@value #TRIGGER_RANGE}) sits deliberately INSIDE the tyrant's
 * abandon-reset radius (24): a player hovering just outside the reset ring cannot
 * flap the boss between despawn and re-summon.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogBankMarker {
    /** Player proximity that springs the lair (kept below the boss's 24-block reset ring). */
    public static final double TRIGGER_RANGE = 20.0D;
    /** Radius of the ambient fog-bank pillar ring dressed around the lair center. */
    public static final double BANK_RING_RADIUS = 10.0D;
    /** No second tyrant while one already fights near the lair (summonAt dedups too). */
    private static final double LIVE_TYRANT_RANGE = 48.0D;
    /** Ambient FX only render for players reasonably close to the lair. */
    private static final double AMBIENT_RANGE = 64.0D;
    private static final int CHECK_CADENCE_TICKS = 40;
    private static final int BANK_PILLARS = 8;

    private static final Map<ResourceKey<Level>, List<BlockPos>> LAIRS = new ConcurrentHashMap<>();

    private FogBankMarker() {}

    /**
     * Marks {@code center} as a tyrant lair in {@code level} — THE P1/FogStormSites
     * seam. Idempotent; safe to call every restart/materialization. The lair stays
     * armed until a tyrant is summoned from it (or {@link #clearLair} is called).
     */
    public static void markLair(ServerLevel level, BlockPos center) {
        List<BlockPos> lairs = LAIRS.computeIfAbsent(level.dimension(), key -> new CopyOnWriteArrayList<>());
        BlockPos immutable = center.immutable();
        if (lairs.contains(immutable)) {
            return;
        }
        lairs.add(immutable);
        EclipseMod.LOGGER.info("FogBankMarker: tyrant lair marked at {} in {} ({} lair(s) armed)",
                immutable.toShortString(), level.dimension().location(), lairs.size());
    }

    /** Unmarks one lair (e.g. P1 downgrading a storm). No-op when it was never marked. */
    public static void clearLair(ServerLevel level, BlockPos center) {
        List<BlockPos> lairs = LAIRS.get(level.dimension());
        if (lairs != null && lairs.remove(center.immutable())) {
            EclipseMod.LOGGER.info("FogBankMarker: tyrant lair cleared at {}", center.toShortString());
        }
    }

    /** Unmarks every lair in {@code level}. */
    public static void clearAll(ServerLevel level) {
        List<BlockPos> lairs = LAIRS.remove(level.dimension());
        if (lairs != null && !lairs.isEmpty()) {
            EclipseMod.LOGGER.info("FogBankMarker: cleared {} tyrant lair(s) in {}",
                    lairs.size(), level.dimension().location());
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        LAIRS.clear(); // Lairs are session state; P1 re-marks on restore (javadoc contract).
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (LAIRS.isEmpty() || event.getServer().getTickCount() % CHECK_CADENCE_TICKS != 0
                || !FogBossEntities.FOG_TYRANT.isBound()) {
            return; // Dormant until the registrar wiring line lands (isBound guard).
        }
        for (Map.Entry<ResourceKey<Level>, List<BlockPos>> entry : LAIRS.entrySet()) {
            ServerLevel level = event.getServer().getLevel(entry.getKey());
            if (level == null) {
                continue;
            }
            for (BlockPos lair : entry.getValue()) {
                tickLair(level, lair, entry.getValue());
            }
        }
    }

    private static void tickLair(ServerLevel level, BlockPos lair, List<BlockPos> lairs) {
        Vec3 center = Vec3.atCenterOf(lair);
        ServerPlayer trigger = null;
        boolean anyoneWatching = false;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || !player.isAlive()) {
                continue;
            }
            double dist = player.position().distanceTo(center);
            if (dist <= AMBIENT_RANGE) {
                anyoneWatching = true;
            }
            if (dist <= TRIGGER_RANGE && (trigger == null
                    || player.position().distanceToSqr(center) < trigger.position().distanceToSqr(center))) {
                trigger = player;
            }
        }
        if (!anyoneWatching) {
            return;
        }
        stampBankPillars(level, center);
        if (trigger == null) {
            return;
        }
        boolean tyrantAlready = !level.getEntitiesOfClass(FogTyrantEntity.class,
                new AABB(lair).inflate(LIVE_TYRANT_RANGE), FogTyrantEntity::isAlive).isEmpty();
        if (tyrantAlready) {
            return; // Fight in progress — the lair re-arms once the boss resets/despawns.
        }
        EclipseMod.LOGGER.info("FogBankMarker: {} entered the lair at {} — summoning the Fog Tyrant",
                trigger.getScoreboardName(), lair.toShortString());
        FogTyrantEntity.summonAt(level, lair);
        lairs.remove(lair); // Disarm; P1 (or an admin) re-marks if the storm outlives the fight.
    }

    /** Ambient dressing: slow smoke pillars + spark motes on the bank ring (cheap). */
    private static void stampBankPillars(ServerLevel level, Vec3 center) {
        for (int i = 0; i < BANK_PILLARS; i++) {
            double angle = (Math.PI * 2.0D / BANK_PILLARS) * i
                    + (level.getGameTime() % 360) * 0.003D;
            double x = center.x + Math.cos(angle) * BANK_RING_RADIUS;
            double z = center.z + Math.sin(angle) * BANK_RING_RADIUS;
            level.sendParticles(ParticleTypes.CAMPFIRE_SIGNAL_SMOKE, x, center.y + 0.3D, z,
                    2, 0.25D, 0.1D, 0.25D, 0.004D);
            if (level.getRandom().nextInt(4) == 0) {
                level.sendParticles(ParticleTypes.ELECTRIC_SPARK, x, center.y + 1.2D, z,
                        1, 0.2D, 0.6D, 0.2D, 0.01D);
            }
        }
    }
}
