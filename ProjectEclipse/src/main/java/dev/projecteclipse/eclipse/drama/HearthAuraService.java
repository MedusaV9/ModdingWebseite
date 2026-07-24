package dev.projecteclipse.eclipse.drama;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.limbo.ShipLanterns;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CampfireBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * W4-CEREMONY / IDEA-10 #3 — CAMPFIRE HEARTH AURA: proximity voice needs proximity magnets.
 * Every {@value #SCAN_INTERVAL_TICKS} ticks (the {@code WitnessedLossService} scanner model:
 * early-outs, radius² everywhere), when TWO OR MORE living players share a lit (soul)
 * campfire within {@value #HEARTH_RANGE} blocks, the circle "holds":
 *
 * <ul>
 *   <li><b>cosy ring</b> — a slow {@code CAMPFIRE_COSY_SMOKE} ring around the fire (the
 *       exact {@code sendParticles} craft the fog pillars/breach rim already use), so the
 *       gathering is visible from afar;</li>
 *   <li><b>hearth regen</b> — every {@value #REGEN_INTERVAL_TICKS} ticks of continuously
 *       held circle each member heals one heart (2 HP). The only ambient regen source in
 *       the event — a strong, wordless reason to sit together. Leaving the circle resets
 *       the pulse.</li>
 * </ul>
 *
 * <p><b>Ghost-ship variant</b>: banned ghosts idling at the {@link ShipLanterns} soul
 * campfires get gentle rising {@code SOUL} motes (vanilla {@code sendParticles} — the
 * looping {@code limbo_motes} Quasar emitter is position-based and would leak if fired
 * via {@code S2CQuasarPayload}, see {@code QuasarSpawner.spawnManaged}'s loop contract),
 * making the limbo wait a shared vigil instead of solitary. No regen for ghosts — limbo
 * economy stays untouched.</p>
 *
 * <p>Anonymity intact: no text, no names, only smoke, soul motes and slow healing.
 * Statics reset on {@link ServerStoppedEvent} per house rule.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HearthAuraService {
    /** Scan cadence (2 s) — cheap block-box scans around players only. */
    private static final int SCAN_INTERVAL_TICKS = 40;
    /** Circle radius around a lit campfire. */
    private static final double HEARTH_RANGE = 5.0D;
    /** Vertical tolerance of the campfire search box around the player's feet. */
    private static final int HEARTH_RANGE_Y = 3;
    /** One heart (2 HP) per this many continuously-held ticks (30 s). */
    private static final int REGEN_INTERVAL_TICKS = 600;
    /** Minimum circle size for the aura. */
    private static final int MIN_CIRCLE = 2;

    /** Continuously-held aura ticks per player. Server thread only; statics reset on ServerStopped. */
    private static final Map<UUID, Integer> AURA_TICKS = new HashMap<>();

    private HearthAuraService() {}

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % SCAN_INTERVAL_TICKS != 0
                || server.getPlayerList().getPlayerCount() == 0) {
            return;
        }
        Map<UUID, Integer> previous = new HashMap<>(AURA_TICKS);
        AURA_TICKS.clear();
        for (ServerLevel level : server.getAllLevels()) {
            if (level.players().isEmpty()) {
                continue;
            }
            if (level.dimension().equals(LimboDimension.LIMBO)) {
                tickGhostVigil(level);
                continue;
            }
            tickHearths(level, previous);
        }
    }

    // ------------------------------------------------------------------ overworld/nether hearths

    private static void tickHearths(ServerLevel level, Map<UUID, Integer> previous) {
        // Bucket living players by the lit campfire nearest to them (usually 0–1 fires).
        Map<BlockPos, List<ServerPlayer>> circles = new HashMap<>();
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || player.isDeadOrDying()
                    || player.getData(EclipseAttachments.BANNED)) {
                continue;
            }
            BlockPos hearth = nearestLitCampfire(level, player);
            if (hearth != null) {
                circles.computeIfAbsent(hearth, pos -> new ArrayList<>(4)).add(player);
            }
        }
        for (Map.Entry<BlockPos, List<ServerPlayer>> circle : circles.entrySet()) {
            if (circle.getValue().size() < MIN_CIRCLE) {
                continue; // a lone sitter gets vanilla campfire cosiness only
            }
            sendCosyRing(level, circle.getKey());
            for (ServerPlayer member : circle.getValue()) {
                int held = previous.getOrDefault(member.getUUID(), 0) + SCAN_INTERVAL_TICKS;
                if (held >= REGEN_INTERVAL_TICKS) {
                    held = 0;
                    if (member.getHealth() < member.getMaxHealth()) {
                        member.heal(2.0F);
                        level.sendParticles(ParticleTypes.HEART,
                                member.getX(), member.getY() + 1.9D, member.getZ(),
                                1, 0.1D, 0.1D, 0.1D, 0.0D);
                    }
                }
                AURA_TICKS.put(member.getUUID(), held);
            }
        }
    }

    /** Slow smoke ring around the fire — legible from a distance, calm up close. */
    private static void sendCosyRing(ServerLevel level, BlockPos hearth) {
        double cx = hearth.getX() + 0.5D;
        double cy = hearth.getY() + 0.4D;
        double cz = hearth.getZ() + 0.5D;
        double spin = level.getGameTime() * 0.045D;
        for (int i = 0; i < 4; i++) {
            double angle = spin + i * (Math.PI / 2.0D);
            level.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                    cx + Math.cos(angle) * 2.0D, cy, cz + Math.sin(angle) * 2.0D,
                    1, 0.2D, 0.1D, 0.2D, 0.01D);
        }
    }

    /** The nearest lit (soul) campfire within the hearth box around the player, or null. */
    @Nullable
    private static BlockPos nearestLitCampfire(ServerLevel level, ServerPlayer player) {
        BlockPos feet = player.blockPosition();
        int range = (int) Math.ceil(HEARTH_RANGE);
        BlockPos best = null;
        double bestDistSq = HEARTH_RANGE * HEARTH_RANGE;
        for (BlockPos pos : BlockPos.betweenClosed(
                feet.offset(-range, -HEARTH_RANGE_Y, -range),
                feet.offset(range, HEARTH_RANGE_Y, range))) {
            BlockState state = level.getBlockState(pos);
            if (!(state.is(Blocks.CAMPFIRE) || state.is(Blocks.SOUL_CAMPFIRE))
                    || !state.getValue(CampfireBlock.LIT)) {
                continue;
            }
            double distSq = player.distanceToSqr(pos.getX() + 0.5D, pos.getY() + 0.5D, pos.getZ() + 0.5D);
            if (distSq <= bestDistSq) {
                bestDistSq = distSq;
                best = pos.immutable();
            }
        }
        return best;
    }

    // ------------------------------------------------------------------ ghost-ship vigil

    /** Soul motes over ghosts idling at the deck lanterns — a shared vigil, no regen. */
    private static void tickGhostVigil(ServerLevel limbo) {
        List<BlockPos> lanterns = null;
        double rangeSq = HEARTH_RANGE * HEARTH_RANGE;
        for (ServerPlayer player : limbo.players()) {
            if (!player.getData(EclipseAttachments.BANNED) || player.isSpectator()) {
                continue;
            }
            if (lanterns == null) {
                lanterns = ShipLanterns.positions(limbo); // lazy: most scans have no ghosts
            }
            for (BlockPos lantern : lanterns) {
                BlockState state = limbo.getBlockState(lantern);
                if (!state.is(Blocks.SOUL_CAMPFIRE) || !state.getValue(CampfireBlock.LIT)) {
                    continue;
                }
                if (player.distanceToSqr(lantern.getX() + 0.5D, lantern.getY() + 0.5D,
                        lantern.getZ() + 0.5D) <= rangeSq) {
                    limbo.sendParticles(ParticleTypes.SOUL,
                            player.getX(), player.getY() + 0.6D, player.getZ(),
                            2, 0.25D, 0.4D, 0.25D, 0.012D);
                    break;
                }
            }
        }
    }

    /** Statics reset so a singleplayer relaunch (same JVM) never leaks across saves. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        AURA_TICKS.clear();
    }
}
