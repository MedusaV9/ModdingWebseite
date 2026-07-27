package dev.projecteclipse.eclipse.client.echo;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.woah.echogrove.EchoGroveLayout;
import dev.projecteclipse.eclipse.woah.echogrove.EchoGrovePayloads;
import net.minecraft.core.BlockPos;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

import dev.projecteclipse.eclipse.EclipseMod;

/**
 * WOAH-05 client mirror of the grove quest/lifecycle snapshot (plan §3.7) —
 * written by {@link EchoGrovePayloads}' client handler on the main thread, read
 * by {@link EchoGroveFx} (grade afterglow floor), {@link EchoOrbGlowFx} and the
 * renderers. A dedicated tiny cache instead of new {@code ClientStateCache}
 * mailbox fields: the shared hub file stays untouched (parallel-worker law).
 *
 * <p><b>Anchor without sync:</b> {@link #treeCenter()} prefers the payload's
 * server-authoritative tree center once {@code placed}; before that (or on a
 * fresh login race) it falls back to the same deterministic
 * {@link EchoGroveLayout#bowlCenter()} derivation the server terraformer used —
 * the {@code ObservatoryAmbience} school, so every window/grade can open even
 * if the snapshot payload is still in flight.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EchoGroveClientState {
    private static volatile boolean placed;
    @Nullable
    private static volatile BlockPos treeCenter;
    private static volatile int collectedMask;
    private static volatile int deposited;
    private static volatile boolean finaleDone;

    private EchoGroveClientState() {}

    /** Payload ingest ({@code EchoGrovePayloads.handleState} → client main thread). */
    public static void handleState(EchoGrovePayloads.S2CEchoGrovePayload payload) {
        placed = payload.placed();
        treeCenter = payload.placed() ? payload.treeCenter() : null;
        collectedMask = payload.collectedMask();
        deposited = payload.deposited();
        finaleDone = payload.finaleDone();
    }

    /** Whether the server has materialized the grove (payload-authoritative). */
    public static boolean placed() {
        return placed;
    }

    /**
     * Memory-tree base (bowl floor center): payload value once placed, else the
     * deterministic client derivation. Never null — the fallback IS the layout.
     */
    public static BlockPos treeCenter() {
        BlockPos synced = treeCenter;
        return synced != null ? synced : EchoGroveLayout.bowlCenter();
    }

    /** Tree-center as a Vec3 at block center (window/grade distance anchor). */
    public static Vec3 treeAnchor() {
        return Vec3.atCenterOf(treeCenter());
    }

    /** Bitmask of collected lost orbs (bit n = kind n, plan §3.6). */
    public static int collectedMask() {
        return collectedMask;
    }

    /** Deposited fragment count 0–5. */
    public static int deposited() {
        return deposited;
    }

    /** Persistent afterglow flag (grade floor 0.18, warmer orbs — plan §7.4). */
    public static boolean finaleDone() {
        return finaleDone;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        placed = false;
        treeCenter = null;
        collectedMask = 0;
        deposited = 0;
        finaleDone = false;
    }
}
