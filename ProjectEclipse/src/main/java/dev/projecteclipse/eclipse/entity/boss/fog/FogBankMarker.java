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
 * §2.4 summoning row + P6-W11): marks a storm site as the tyrant's LAIR, dresses it with
 * ambient fog-bank columns (campfire-smoke pillars on a r={@value #BANK_RING_RADIUS}
 * ring — vanilla stand-ins until P2's {@code eclipse:fog_bank} emitter, plan §4.2), and
 * keeps the {@link TyrantStatue} standing at the marked center. <b>F-081: the fight no
 * longer starts by proximity</b> — a player must STRIKE the statue; this class only
 * watches the lair and delegates arm/stand-down to the statue's state machine.
 *
 * <p><b>The P1 seam (one line, documented in
 * {@code docs/plans_v3/wiring/WB-TYRANT_wiring.md} — this class never touches
 * {@code FogStormSites}):</b> when P1 flags an active storm center, it calls</p>
 *
 * <pre>{@code
 * FogBankMarker.markLair(serverLevel, stormCenterBlockPos);
 * }</pre>
 *
 * <p>from wherever it materializes/restores that site (natural spots:
 * {@code FogStormSites.materializeSite}'s completion block and the restart-restore path
 * — lairs are deliberately NOT persisted here, so P1 re-marks on restore exactly like it
 * re-announces storm walls). Marking is idempotent; {@link #clearLair} / {@link #clearAll}
 * unmark. {@link #disarmLair} pulls a lair while the statue survives — the statue-hit
 * moment (the fight is committed; {@code TyrantStatue.onFightReset} re-marks after a
 * reset cooldown, closing re-arm gap G-1 in-session). {@link #clearLair} additionally
 * retires the statue entry outright (victory / site retirement), even when the lair was
 * already disarmed mid-fight.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogBankMarker {
    /** Radius of the ambient fog-bank pillar ring dressed around the lair center. */
    public static final double BANK_RING_RADIUS = 10.0D;
    /** No second tyrant near a lair (summonAt dedups too) — shared with the statue. */
    static final double LIVE_TYRANT_RANGE = 48.0D;
    /** Ambient FX only render for players reasonably close to the lair. */
    private static final double AMBIENT_RANGE = 64.0D;
    private static final int CHECK_CADENCE_TICKS = 40;
    private static final int BANK_PILLARS = 8;

    private static final Map<ResourceKey<Level>, List<BlockPos>> LAIRS = new ConcurrentHashMap<>();

    private FogBankMarker() {}

    /**
     * Marks {@code center} as a tyrant lair in {@code level} — THE P1/FogStormSites
     * seam. Idempotent; safe to call every restart/materialization. The lair stays
     * armed until its statue is struck (or {@link #clearLair} is called).
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

    /** Whether {@code center} currently rides the armed-lair list ({@code TyrantStatue} seam). */
    public static boolean isLairArmed(ServerLevel level, BlockPos center) {
        List<BlockPos> lairs = LAIRS.get(level.dimension());
        return lairs != null && lairs.contains(center.immutable());
    }

    /**
     * Pulls one lair WITHOUT retiring its statue entry — the statue-hit moment (F-081):
     * the fight is committed, and {@code TyrantStatue} owns the entry through
     * AWAKENING/FIGHT/COOLDOWN until it re-marks or retires. No-op when unmarked.
     */
    public static void disarmLair(ServerLevel level, BlockPos center) {
        List<BlockPos> lairs = LAIRS.get(level.dimension());
        if (lairs != null && lairs.remove(center.immutable())) {
            EclipseMod.LOGGER.info("FogBankMarker: lair at {} disarmed (statue struck)",
                    center.toShortString());
        }
    }

    /**
     * Unmarks one lair AND retires its statue (victory {@code stormEnded}, storm
     * downgrade). The retire runs even when the lair wasn't tracked — a mid-fight lair
     * is disarmed already, but its statue entry still rides FIGHT/COOLDOWN.
     */
    public static void clearLair(ServerLevel level, BlockPos center) {
        List<BlockPos> lairs = LAIRS.get(level.dimension());
        if (lairs != null && lairs.remove(center.immutable())) {
            EclipseMod.LOGGER.info("FogBankMarker: tyrant lair cleared at {}", center.toShortString());
        }
        TyrantStatue.retireLair(level, center);
    }

    /**
     * Unmarks every lair in {@code level} — the reconcile pattern (clear-all then
     * re-mark actives in the same pass). Deliberately does NOT retire statues: entries
     * whose lairs come straight back never flicker, and truly orphaned ones fall to
     * {@code TyrantStatue}'s armed-state sweep (which checks {@link #isLairArmed}).
     */
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
                tickLair(level, lair);
            }
        }
    }

    /**
     * The watched-lair pass (F-081): ambient dressing, then the statue delegation —
     * a live tyrant nearby stands the statue down ({@code noteFightRunning}, e.g. a
     * mid-fight restart where the reconcile re-marked the lair), otherwise the statue
     * stands/self-heals/hints ({@code ensureArmed}). No player proximity summons.
     */
    private static void tickLair(ServerLevel level, BlockPos lair) {
        Vec3 center = Vec3.atCenterOf(lair);
        boolean anyoneWatching = false;
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && player.position().distanceTo(center) <= AMBIENT_RANGE) {
                anyoneWatching = true;
                break;
            }
        }
        if (!anyoneWatching) {
            return;
        }
        stampBankPillars(level, center);
        boolean tyrantAlready = !level.getEntitiesOfClass(FogTyrantEntity.class,
                new AABB(lair).inflate(LIVE_TYRANT_RANGE), FogTyrantEntity::isAlive).isEmpty();
        if (tyrantAlready) {
            TyrantStatue.noteFightRunning(level, lair);
        } else {
            TyrantStatue.ensureArmed(level, lair);
        }
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
