package dev.projecteclipse.eclipse.veilfx;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CAnchorPayload;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Named world positions other systems publish for FX (P2 §3.1, FROZEN API). The server sets
 * an anchor (P6 ship door/deck, P4/P6 altar) and it auto-syncs to every client via
 * {@link S2CAnchorPayload}; clients read positions with {@link #get}. Frozen ids:
 * {@link #SHIP_DOOR}, {@link #ALTAR_CENTER}, {@link #SHIP_DECK}.
 *
 * <p>Anchors are transient (in-memory): publishers re-set them on server start / structure
 * placement. Every anchor is re-sent to each player at login; both maps are cleared on
 * server stop / client disconnect so integrated-server restarts never leak positions.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FxAnchors {
    public static final ResourceLocation SHIP_DOOR =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ship_door");
    public static final ResourceLocation ALTAR_CENTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_center");
    public static final ResourceLocation SHIP_DECK =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ship_deck");

    private record Anchor(ResourceKey<Level> dimension, Vec3 pos) {}

    /** Server-authoritative anchors. */
    private static final Map<ResourceLocation, Anchor> SERVER_ANCHORS = new ConcurrentHashMap<>();
    /** Client mirror, fed by {@code network.fx.FxPayloads}. */
    private static final Map<ResourceLocation, Vec3> CLIENT_ANCHORS = new ConcurrentHashMap<>();

    private FxAnchors() {}

    /** Server: publishes/updates an anchor and re-broadcasts it to every connected player. */
    public static void set(ResourceLocation id, ServerLevel level, Vec3 pos) {
        SERVER_ANCHORS.put(id, new Anchor(level.dimension(), pos));
        PacketDistributor.sendToAllPlayers(new S2CAnchorPayload(id, true, pos));
    }

    /** Server: removes an anchor and broadcasts the removal. */
    public static void remove(ResourceLocation id, ServerLevel level) {
        if (SERVER_ANCHORS.remove(id) != null) {
            PacketDistributor.sendToAllPlayers(new S2CAnchorPayload(id, false, Vec3.ZERO));
        }
    }

    /** Client read; {@code null} while the anchor is unset. */
    @Nullable
    public static Vec3 get(ResourceLocation id) {
        return CLIENT_ANCHORS.get(id);
    }

    /** Client cache write — called only by the {@code S2CAnchorPayload} handler. */
    public static void handleClient(ResourceLocation id, boolean set, Vec3 pos) {
        if (set) {
            CLIENT_ANCHORS.put(id, pos);
        } else {
            CLIENT_ANCHORS.remove(id);
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            for (Map.Entry<ResourceLocation, Anchor> entry : SERVER_ANCHORS.entrySet()) {
                PacketDistributor.sendToPlayer(player,
                        new S2CAnchorPayload(entry.getKey(), true, entry.getValue().pos()));
            }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SERVER_ANCHORS.clear();
    }

    /** Client-side disconnect cleanup (separate class so the server never loads client events). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class ClientReset {
        private ClientReset() {}

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            CLIENT_ANCHORS.clear();
        }
    }
}
