package dev.projecteclipse.eclipse.client.echo;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.woah.echogrove.MemoryOrbEntity;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-05 orb attach-loops (plan §4.2 #8): {@code echo_orb_glow.fx} rides every
 * tracked {@link MemoryOrbEntity} within {@value #ATTACH_RANGE} blocks
 * (nearest-{@value #MAX_ATTACHED} cap); {@code DATA_LIT} orbs get the warmer
 * {@code _lit} variant. This is the {@code veilfx/PhotonMobFx} loop-tier schema
 * as a dedicated feature class — the shared PhotonMobFx table stays untouched
 * (parallel-worker law; documented in {@code woah_echo_status.md}). All the
 * loop-tier laws apply: {@code ensureAttachedFx} CACHE-dedup keepalive, graceful
 * {@code destroy(false)} on range exit / cap eviction / lit flips, wholesale
 * kill behind {@link PhotonBridge#available()}.
 *
 * <p>The variant swap on a lit flip releases the cold loop gracefully and
 * ensures the lit loop next tick — a one-tick gap the deposit chime covers.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EchoOrbGlowFx {
    private static final ResourceLocation ORB_GLOW =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "echo_orb_glow");
    private static final ResourceLocation ORB_GLOW_LIT =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "echo_orb_glow_lit");

    private static final double ATTACH_RANGE = 48.0D;
    /** Hysteresis: release only this many blocks PAST the attach range. */
    private static final double RELEASE_MARGIN = 2.0D;
    private static final int MAX_ATTACHED = 8;

    /** entityId → the fx variant currently attached (client main thread only). */
    private static final Map<Integer, ResourceLocation> ATTACHED = new HashMap<>();
    /** entityId → entity, parallel to {@link #ATTACHED} (for the release call). */
    private static final Map<Integer, Entity> ATTACHED_ENTITIES = new HashMap<>();

    private EchoOrbGlowFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || minecraft.player == null) {
            ATTACHED.clear(); // executors already died with the level
            ATTACHED_ENTITIES.clear();
            return;
        }
        if (!PhotonBridge.available()) {
            detachAll(true); // reducedFx / photonFx off: kill the tier wholesale
            return;
        }
        Vec3 camera = minecraft.player.position();

        // Candidates inside the release band, nearest first.
        List<MemoryOrbEntity> candidates = new ArrayList<>();
        double bandSq = square(ATTACH_RANGE + RELEASE_MARGIN);
        for (Entity entity : level.entitiesForRendering()) {
            if (entity instanceof MemoryOrbEntity orb && orb.isAlive()
                    && orb.distanceToSqr(camera) <= bandSq) {
                candidates.add(orb);
            }
        }
        candidates.sort((left, right) -> Double.compare(
                left.distanceToSqr(camera), right.distanceToSqr(camera)));

        Map<Integer, MemoryOrbEntity> want = new HashMap<>();
        for (MemoryOrbEntity orb : candidates) {
            if (want.size() >= MAX_ATTACHED) {
                break;
            }
            double gate = ATTACHED.containsKey(orb.getId())
                    ? ATTACH_RANGE + RELEASE_MARGIN : ATTACH_RANGE;
            if (orb.distanceToSqr(camera) <= gate * gate) {
                want.put(orb.getId(), orb);
            }
        }

        // Range exit / cap eviction / gone / lit flip: graceful destroy(false).
        Iterator<Map.Entry<Integer, ResourceLocation>> iterator = ATTACHED.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<Integer, ResourceLocation> entry = iterator.next();
            MemoryOrbEntity wanted = want.get(entry.getKey());
            if (wanted == null || !entry.getValue().equals(variantOf(wanted))) {
                Entity stale = ATTACHED_ENTITIES.remove(entry.getKey());
                if (stale != null) {
                    PhotonBridge.stopAttachedFx(entry.getValue(), stale, false);
                }
                iterator.remove();
            }
        }

        // Keepalive / attach (CACHE dedup absorbs the per-tick call while live).
        for (MemoryOrbEntity orb : want.values()) {
            ResourceLocation variant = variantOf(orb);
            if (PhotonBridge.ensureAttachedFx(variant, orb,
                    PhotonBridge.AUTO_ROTATE_NONE, null)) {
                ATTACHED.put(orb.getId(), variant);
                ATTACHED_ENTITIES.put(orb.getId(), orb);
            } else {
                ATTACHED.remove(orb.getId()); // refused — free retry next tick
                ATTACHED_ENTITIES.remove(orb.getId());
            }
        }
    }

    private static ResourceLocation variantOf(MemoryOrbEntity orb) {
        return orb.isLit() ? ORB_GLOW_LIT : ORB_GLOW;
    }

    private static void detachAll(boolean force) {
        for (Map.Entry<Integer, ResourceLocation> entry : ATTACHED.entrySet()) {
            Entity entity = ATTACHED_ENTITIES.get(entry.getKey());
            if (entity != null) {
                PhotonBridge.stopAttachedFx(entry.getValue(), entity, force);
            }
        }
        ATTACHED.clear();
        ATTACHED_ENTITIES.clear();
    }

    private static double square(double d) {
        return d * d;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        ATTACHED.clear(); // PhotonBridge.destroyAll force-kills the executors
        ATTACHED_ENTITIES.clear();
    }
}
