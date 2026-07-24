package dev.projecteclipse.eclipse.movement;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.protection.SpawnProtectionRules;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumVersionData;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;

/**
 * W4-ISLAND / IDEA-04 #1: wires the dormant edge-glide loop end-to-end. The geometry
 * ({@link FloatingSanctumBuilder#glideLedges}), the safety rule
 * ({@link SpawnProtectionRules#isInFallSafeZone}) and the client FX
 * ({@code FxPayloads.FX_GLIDE_START/STOP} → {@code glide_trail} attached emitter) all
 * existed — this service is the server brain that finally flags glide state
 * ({@code ContainmentService} pattern: game-bus {@code PlayerTickEvent.Post}, statics
 * reset on {@code ServerStoppedEvent}).
 *
 * <p><b>Down-glide</b>: a survival/adventure player who leaves an island glide notch
 * airborne with negative vy, within {@value #LEDGE_MATCH_RANGE} blocks horizontally of a
 * ledge column and inside the fall-safe band, enters glide — vy is damped to
 * ≥ {@value #GLIDE_MIN_VY} every tick (the established {@code setDeltaMovement} +
 * {@code hurtMarked} velocity-sync pattern), horizontal speed is clamped to
 * {@value #HORIZONTAL_SPEED_CAP} so the glide can never fling anyone off, and
 * {@code fallDistance} stays zeroed (belt over the fall-safe suspenders). The glide ends
 * on landing, sneaking, or leaving the fall-safe band.</p>
 *
 * <p><b>Up-glide</b> (the auto-up-glide): standing at the crater-rim ground below a
 * notch, looking up (pitch ≤ {@value #LOOK_UP_MAX_XROT}°) and jumping enters a gentle
 * lift up the ledge column — vy accelerates by {@value #LIFT_ACCEL}/t capped at
 * {@value #LIFT_MAX_VY}, with a soft centering pull onto the column. Reaching the island
 * lip hands the player a small inward nudge onto the lawn and ends the lift; sneaking
 * cancels at any point. Both directions share the {@code glide_trail} FX loop.</p>
 *
 * <p>Perf: the 4 ledge positions + island Ys are cached and refreshed every
 * {@value #CACHE_REFRESH_TICKS} ticks (they only ever change on the one-shot sanctum
 * flip); the per-player tick path is early-out heavy and allocation-free until a glide
 * actually starts. Feedback is action bar + FX only (house rule), one hint per mode per
 * session.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EdgeGlideService {
    /** Horizontal match range (blocks) from a ledge column for entry/centering. */
    public static final double LEDGE_MATCH_RANGE = 2.5D;
    /** Down-glide terminal fall speed (blocks/tick; damped to this every tick). */
    public static final double GLIDE_MIN_VY = -0.18D;
    /** Up-glide acceleration per tick / hard vy cap (gentle lift, never a launch). */
    public static final double LIFT_ACCEL = 0.10D;
    public static final double LIFT_MAX_VY = 0.42D;
    /** Horizontal speed clamp while gliding — the glide must NEVER fling players off. */
    public static final double HORIZONTAL_SPEED_CAP = 0.30D;
    /** Camera pitch at or above which (i.e. ≤ −45°) a jump below a notch starts the lift. */
    public static final float LOOK_UP_MAX_XROT = -45.0F;
    /** FX event broadcast range around the glider (matches the IDEA-04 spec). */
    private static final double FX_EVENT_RANGE = 64.0D;
    /** Ledge/island cache refresh cadence (server ticks). */
    private static final int CACHE_REFRESH_TICKS = 100;
    private static final double LEDGE_MATCH_RANGE_SQ = LEDGE_MATCH_RANGE * LEDGE_MATCH_RANGE;
    /** Soft centering pull toward the ledge column while lifting (per tick). */
    private static final double LIFT_CENTERING = 0.04D;
    /** Inward nudge onto the lawn when the lift crests the island lip. */
    private static final double LIP_NUDGE = 0.18D;
    private static final int HINT_COLOR = 0xB98CFF;

    private enum Mode { FALL, LIFT }

    // --- statics reset on ServerStopped (repo-wide rule) ---
    /** Live glides by player id. */
    private static final Map<UUID, Mode> ACTIVE = new HashMap<>();
    /** Players already shown the once-per-session action-bar hint, per mode. */
    private static final Set<UUID> HINTED_FALL = new HashSet<>();
    private static final Set<UUID> HINTED_LIFT = new HashSet<>();
    /** Cached ledge geometry (empty while the sanctum is not floating). */
    private static List<BlockPos> ledges = List.of();
    @Nullable
    private static BlockPos cachedAltar;
    private static int islandTopY;
    private static int islandGroundY;
    private static int nextCacheRefreshTick = Integer.MIN_VALUE;

    private EdgeGlideService() {}

    /** Whether the player is currently edge-gliding (either mode) — {@code SoftLandingFx} query. */
    public static boolean isGliding(ServerPlayer player) {
        return ACTIVE.containsKey(player.getUUID());
    }

    @SubscribeEvent
    public static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (!player.isAlive() || player.isSpectator()
                || player.level().dimension() != Level.OVERWORLD) {
            endGlide(player, false);
            return;
        }
        GameType mode = player.gameMode.getGameModeForPlayer();
        if (mode != GameType.SURVIVAL && mode != GameType.ADVENTURE) {
            endGlide(player, false);
            return;
        }
        refreshCache(player.server);
        if (ledges.isEmpty()) {
            endGlide(player, false);
            return;
        }
        Mode active = ACTIVE.get(player.getUUID());
        if (player.onGround() || player.isShiftKeyDown() || player.isInWater()
                || player.isPassenger() || player.isFallFlying()) {
            if (active != null) {
                endGlide(player, true);
            }
            return;
        }
        BlockPos nearestLedge = nearestLedgeWithin(player);
        if (active == null) {
            active = tryEnter(player, nearestLedge);
            if (active == null) {
                return;
            }
        }
        if (active == Mode.FALL) {
            tickFallGlide(player);
        } else {
            tickLiftGlide(player, nearestLedge);
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            // No STOP packet needed: the attached client emitter dies with the entity.
            ACTIVE.remove(player.getUUID());
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        ACTIVE.clear();
        HINTED_FALL.clear();
        HINTED_LIFT.clear();
        ledges = List.of();
        cachedAltar = null;
        nextCacheRefreshTick = Integer.MIN_VALUE;
    }

    // --- state machine ---

    /** Entry check: LIFT first (deliberate look-up gesture wins), then the FALL band. */
    @Nullable
    private static Mode tryEnter(ServerPlayer player, @Nullable BlockPos nearestLedge) {
        if (nearestLedge == null) {
            return null;
        }
        double vy = player.getDeltaMovement().y;
        if (vy > -0.05D && player.getXRot() <= LOOK_UP_MAX_XROT
                && player.getY() < islandTopY
                && player.getY() > islandGroundY - 6.0D
                && isFallSafe(player)) {
            beginGlide(player, Mode.LIFT);
            return Mode.LIFT;
        }
        if (vy < -0.10D && player.getY() < islandTopY + 2.0D && isFallSafe(player)) {
            beginGlide(player, Mode.FALL);
            return Mode.FALL;
        }
        return null;
    }

    /** Down-glide tick: damp vy, clamp horizontal, keep fall distance zero. */
    private static void tickFallGlide(ServerPlayer player) {
        Vec3 motion = player.getDeltaMovement();
        if (motion.y >= 0.0D || !isFallSafe(player)) {
            endGlide(player, true); // crested (bounce/updraft) or left the safe band
            return;
        }
        double vy = Math.max(motion.y, GLIDE_MIN_VY);
        Vec3 clamped = clampHorizontal(motion.x, vy, motion.z);
        player.setDeltaMovement(clamped);
        player.hurtMarked = true;
        player.fallDistance = 0.0F;
    }

    /** Up-glide tick: accelerate up the column, center onto it, crest onto the lawn. */
    private static void tickLiftGlide(ServerPlayer player, @Nullable BlockPos ledge) {
        if (ledge == null || !isFallSafe(player)) {
            endGlide(player, true); // drifted off the column or out of the safe band
            return;
        }
        Vec3 motion = player.getDeltaMovement();
        if (player.getY() >= islandTopY + 1.0D) {
            // Crest: a gentle inward nudge over the notch onto the lawn, then release.
            BlockPos altar = cachedAltar;
            double dx = altar == null ? 0.0D : (altar.getX() + 0.5D) - player.getX();
            double dz = altar == null ? 0.0D : (altar.getZ() + 0.5D) - player.getZ();
            double dist = Math.sqrt(dx * dx + dz * dz);
            Vec3 nudge = dist < 0.01D ? new Vec3(0.0D, 0.25D, 0.0D)
                    : new Vec3(dx / dist * LIP_NUDGE, 0.25D, dz / dist * LIP_NUDGE);
            player.setDeltaMovement(nudge);
            player.hurtMarked = true;
            player.fallDistance = 0.0F;
            endGlide(player, true);
            return;
        }
        double vy = Math.min(motion.y + LIFT_ACCEL, LIFT_MAX_VY);
        double pullX = (ledge.getX() + 0.5D - player.getX()) * LIFT_CENTERING;
        double pullZ = (ledge.getZ() + 0.5D - player.getZ()) * LIFT_CENTERING;
        Vec3 clamped = clampHorizontal(motion.x + pullX, vy, motion.z + pullZ);
        player.setDeltaMovement(clamped);
        player.hurtMarked = true;
        player.fallDistance = 0.0F;
    }

    private static void beginGlide(ServerPlayer player, Mode mode) {
        ACTIVE.put(player.getUUID(), mode);
        FxPayloads.sendFxEvent(player.serverLevel(), FxPayloads.FX_GLIDE_START,
                player.position(), 0.0F, 0.0F, FX_EVENT_RANGE);
        Set<UUID> hinted = mode == Mode.LIFT ? HINTED_LIFT : HINTED_FALL;
        if (hinted.add(player.getUUID())) {
            player.displayClientMessage(Component.translatable(mode == Mode.LIFT
                    ? "movement.eclipse.glide.lift"
                    : "movement.eclipse.glide.soften").withColor(HINT_COLOR), true);
        }
    }

    /** Removes the glide state; {@code sendStop} broadcasts the trail-detach FX event. */
    private static void endGlide(ServerPlayer player, boolean sendStop) {
        if (ACTIVE.remove(player.getUUID()) == null) {
            return;
        }
        if (sendStop && player.level() instanceof ServerLevel serverLevel) {
            FxPayloads.sendFxEvent(serverLevel, FxPayloads.FX_GLIDE_STOP,
                    player.position(), 0.0F, 0.0F, FX_EVENT_RANGE);
        }
    }

    // --- geometry helpers ---

    /** The nearest cached ledge column within {@value #LEDGE_MATCH_RANGE}, else null. */
    @Nullable
    private static BlockPos nearestLedgeWithin(ServerPlayer player) {
        BlockPos best = null;
        double bestSq = LEDGE_MATCH_RANGE_SQ;
        List<BlockPos> current = ledges;
        for (int i = 0; i < current.size(); i++) {
            BlockPos ledge = current.get(i);
            double dx = ledge.getX() + 0.5D - player.getX();
            double dz = ledge.getZ() + 0.5D - player.getZ();
            double distSq = dx * dx + dz * dz;
            if (distSq <= bestSq) {
                bestSq = distSq;
                best = ledge;
            }
        }
        return best;
    }

    private static boolean isFallSafe(ServerPlayer player) {
        return SpawnProtectionRules.isInFallSafeZone(player.level(), player.blockPosition());
    }

    /** Horizontal clamp to {@value #HORIZONTAL_SPEED_CAP} — the never-fling guarantee. */
    private static Vec3 clampHorizontal(double x, double y, double z) {
        double horizontal = Math.sqrt(x * x + z * z);
        if (horizontal > HORIZONTAL_SPEED_CAP) {
            double scale = HORIZONTAL_SPEED_CAP / horizontal;
            return new Vec3(x * scale, y, z * scale);
        }
        return new Vec3(x, y, z);
    }

    /**
     * Refreshes the ledge cache every {@value #CACHE_REFRESH_TICKS} ticks: the four
     * notch columns exist only once the sanctum is floating (the cache also catches the
     * live stage-0→1 flip within five seconds without any listener wiring).
     */
    private static void refreshCache(MinecraftServer server) {
        int now = server.getTickCount();
        if (now < nextCacheRefreshTick) {
            return;
        }
        nextCacheRefreshTick = now + CACHE_REFRESH_TICKS;
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null || SanctumVersionData.get(overworld).version()
                < SanctumVersionData.VERSION_FLOATING) {
            ledges = List.of();
            cachedAltar = null;
            return;
        }
        if (!altarPos.equals(cachedAltar)) {
            cachedAltar = altarPos;
            ledges = List.copyOf(FloatingSanctumBuilder.glideLedges(altarPos));
            islandTopY = FloatingSanctumBuilder.islandTopY(altarPos);
            islandGroundY = FloatingSanctumBuilder.groundY(altarPos);
            EclipseMod.LOGGER.info("EdgeGlideService armed: {} glide ledges around altar {} (top y{}, ground y{})",
                    ledges.size(), altarPos.toShortString(), islandTopY, islandGroundY);
        }
    }
}
