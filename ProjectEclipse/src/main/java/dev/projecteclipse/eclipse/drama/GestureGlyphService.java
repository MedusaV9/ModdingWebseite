package dev.projecteclipse.eclipse.drama;

import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * W4-CEREMONY / IDEA-10 #2 — SNEAK-PATTERN GESTURE GLYPHS: uniform skins erase identity but
 * not motion. This service samples every player's sneak state per server tick (the
 * {@code drama.WitnessedLossService} scanner model: early-outs, no allocations on the hot
 * path), keeps a tiny ring buffer of completed press edges, and recognizes three wordless
 * gestures:
 *
 * <ul>
 *   <li><b>greet</b> (glyph 0) — three quick taps within ~2 s;</li>
 *   <li><b>danger</b> (glyph 1) — two long holds within ~4 s;</li>
 *   <li><b>follow me</b> (glyph 2) — tap, long hold, tap within ~4 s.</li>
 * </ul>
 *
 * <p>On recognition the sanctioned seam {@link FxPayloads#sendFxEvent} broadcasts
 * {@link #FX_GLYPH} ({@code a} = glyph index, {@code b} unused, range 24 blocks) — no text,
 * no names, exactly like every other FX id. The CLIENT dispatch for this id lives in the
 * frozen {@code FxPayloads.handleFxEvent} switch and is therefore a one-line wiring ask
 * (exact diff in {@code docs/plans_v3/wiring/W4-CEREMONY_wiring.md}); until it lands the
 * payload is safely ignored client-side (unknown-id debug log). The renderer
 * ({@code client.drama.GestureGlyphFx}) attaches a 2 s Quasar glyph above the head via the
 * {@code ArmParticles} attach pattern.</p>
 *
 * <p><b>Anti-spam:</b> {@value #COOLDOWN_TICKS}-tick per-player cooldown; client-side every
 * spawn is additionally {@code FxBudget}-gated. <b>Exclusions:</b> banned ghosts (limbo
 * stays muted, the {@code LogoutGhostService.shouldSkip} predicate family) and spectators.
 * Statics reset on {@link ServerStoppedEvent} per house rule.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GestureGlyphService {
    /**
     * FX id of the glyph event ({@code a} = glyph index 0..2). Lives here (owner: this
     * service) until the FxPayloads owner lands the client-dispatch diff; the id string is
     * frozen either way.
     */
    public static final ResourceLocation FX_GLYPH =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/glyph");

    public static final int GLYPH_GREET = 0;
    public static final int GLYPH_DANGER = 1;
    public static final int GLYPH_FOLLOW = 2;

    /** A press this short is a tap… */
    private static final int TAP_MAX_TICKS = 8;
    /** …this long is a hold; in-between presses match neither (deliberate dead zone). */
    private static final int HOLD_MIN_TICKS = 15;
    /** Greet: first tap's release within this window of the third's. */
    private static final int GREET_WINDOW_TICKS = 40;
    /** Danger/follow: slower shapes get a more forgiving window. */
    private static final int LONG_WINDOW_TICKS = 80;
    /** Per-player recognition cooldown (5 s). */
    private static final int COOLDOWN_TICKS = 100;
    /** Broadcast radius of the glyph event. */
    private static final double GLYPH_RANGE = 24.0D;
    /** Ring buffer capacity (longest pattern is 3 presses; one spare). */
    private static final int PRESS_BUFFER = 4;
    /** Offline-sampler prune cadence. */
    private static final int PRUNE_INTERVAL_TICKS = 200;

    private record Press(long releaseTick, int durationTicks) {}

    /** Per-player sneak sampler. Server thread only. */
    private static final class Sampler {
        boolean sneaking;
        long pressStartTick;
        long cooldownUntilTick;
        final ArrayDeque<Press> presses = new ArrayDeque<>(PRESS_BUFFER);
    }

    // statics reset on ServerStopped
    private static final Map<UUID, Sampler> SAMPLERS = new HashMap<>();

    private GestureGlyphService() {}

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getPlayerList().getPlayerCount() == 0) {
            return;
        }
        long now = server.getTickCount();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator() || player.getData(EclipseAttachments.BANNED)) {
                SAMPLERS.remove(player.getUUID()); // limbo stays muted; mid-gesture bans drop cleanly
                continue;
            }
            sample(player, now);
        }
        if (now % PRUNE_INTERVAL_TICKS == 0) {
            SAMPLERS.keySet().removeIf(id -> server.getPlayerList().getPlayer(id) == null);
        }
    }

    private static void sample(ServerPlayer player, long now) {
        Sampler sampler = SAMPLERS.computeIfAbsent(player.getUUID(), id -> new Sampler());
        boolean sneaking = player.isShiftKeyDown();
        if (sneaking == sampler.sneaking) {
            return;
        }
        sampler.sneaking = sneaking;
        if (sneaking) {
            sampler.pressStartTick = now;
            return;
        }
        // Release edge: record the completed press and try to recognize a pattern.
        int duration = (int) Math.max(1L, now - sampler.pressStartTick);
        if (sampler.presses.size() >= PRESS_BUFFER) {
            sampler.presses.pollFirst();
        }
        sampler.presses.addLast(new Press(now, duration));
        recognize(player, sampler, now);
    }

    private static void recognize(ServerPlayer player, Sampler sampler, long now) {
        if (now < sampler.cooldownUntilTick) {
            return;
        }
        Press[] last = sampler.presses.toArray(new Press[0]);
        int glyph = -1;
        if (matchesFollow(last, now)) {
            glyph = GLYPH_FOLLOW;
        } else if (matchesDanger(last, now)) {
            glyph = GLYPH_DANGER;
        } else if (matchesGreet(last, now)) {
            glyph = GLYPH_GREET;
        }
        if (glyph < 0) {
            return;
        }
        sampler.presses.clear();
        sampler.cooldownUntilTick = now + COOLDOWN_TICKS;
        FxPayloads.sendFxEvent((ServerLevel) player.level(), FX_GLYPH,
                player.position(), glyph, 0.0F, GLYPH_RANGE);
    }

    /** tap, hold, tap (most specific shape — checked first). */
    private static boolean matchesFollow(Press[] presses, long now) {
        if (presses.length < 3) {
            return false;
        }
        Press first = presses[presses.length - 3];
        Press middle = presses[presses.length - 2];
        Press innerLast = presses[presses.length - 1];
        return isTap(first) && isHold(middle) && isTap(innerLast)
                && now - first.releaseTick() <= LONG_WINDOW_TICKS;
    }

    /** hold, hold. */
    private static boolean matchesDanger(Press[] presses, long now) {
        if (presses.length < 2) {
            return false;
        }
        Press first = presses[presses.length - 2];
        Press second = presses[presses.length - 1];
        return isHold(first) && isHold(second)
                && now - first.releaseTick() <= LONG_WINDOW_TICKS;
    }

    /** tap, tap, tap inside ~2 s. */
    private static boolean matchesGreet(Press[] presses, long now) {
        if (presses.length < 3) {
            return false;
        }
        Press first = presses[presses.length - 3];
        Press middle = presses[presses.length - 2];
        Press innerLast = presses[presses.length - 1];
        return isTap(first) && isTap(middle) && isTap(innerLast)
                && now - first.releaseTick() <= GREET_WINDOW_TICKS;
    }

    private static boolean isTap(Press press) {
        return press.durationTicks() <= TAP_MAX_TICKS;
    }

    private static boolean isHold(Press press) {
        return press.durationTicks() >= HOLD_MIN_TICKS;
    }

    /** Statics reset so a singleplayer relaunch (same JVM) never leaks across saves. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SAMPLERS.clear();
    }
}
