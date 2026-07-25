package dev.projecteclipse.eclipse.client.credits;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.CreditsSequence;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-IMPROVE-2 (IDEAS-events #9b) — credits flyover contrails: one crisp
 * {@code eclipse:credits_contrail} ara ribbon on up to {@value #MAX_ATTACHED} of the
 * t=420–560 {@code BLOCK_DISPLAY} debris flyers, turning the arc overhead into a meteor
 * shower over the runners. Fully client-local (zero wire): during an active credits run
 * ({@link CreditsClient#nonce()} — latched off the begin payload) any block display in
 * the {@code eclipse:epilogue} dimension above {@value #FLYER_MIN_Y} is a flyer — the
 * wheel lives in limbo and the shadow pucks hug the sand, so the y-filter excludes both;
 * command tags don't sync to clients, so this doc-specced heuristic beats a protocol
 * change.
 *
 * <p><b>Movement latch</b> (the spec's leak fix): flyers spawn scale-ramped from
 * invisible at their pre-launch hold, so attaching on first sight would draw a ribbon on
 * an invisible block. Each display is latched only once it has drifted more than
 * {@value #MOVE_LATCH_DIST} blocks from its first-seen position — i.e. its staggered
 * launch actually began. Nearest-{@value #MAX_ATTACHED} cap; the {@code T_FLYERS_END}
 * server discard auto-destroys the executors (0.9 s ribbon tails fade well before the
 * t=650 burst), and Photon's per-entity CACHE dedup makes the per-tick ensure a no-op
 * while a ribbon lives ({@code PhotonMobFx} loop-tier laws).</p>
 *
 * <p>Not a {@code PhotonMobFx} row: the attach predicate here is stateful (nonce window
 * + per-entity movement latch on vanilla {@link Display.BlockDisplay}s), which the
 * static row table deliberately doesn't model. The fallback is the shipped show — the
 * flyers themselves; {@code reducedFx}/photon-less clients keep it bit-identical.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsContrailFx {
    private static final ResourceLocation CREDITS_CONTRAIL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits_contrail");
    /**
     * Flyer altitude filter: beach sand top (mirrors the private
     * {@code CreditsSequence.BEACH_Y} = 63) + the spec's 10-block margin. Shadow pucks
     * ride ~1 block over the sand; the flyer arcs apex 30+ blocks up.
     */
    private static final double FLYER_MIN_Y = 63.0D + 10.0D;
    /** Ribbon cap (IDEAS-events #9b: "attach to the first 8 nearest only"). */
    private static final int MAX_ATTACHED = 8;
    /** Movement latch: attach only after this much drift from the first-seen position. */
    private static final double MOVE_LATCH_DIST = 0.1D;

    /** First-seen position per display id (movement-latch state). Client thread only. */
    private static final Map<Integer, Vec3> FIRST_SEEN = new HashMap<>();
    /** Display ids that cleared the movement latch this run. */
    private static final Map<Integer, Entity> ATTACHED = new HashMap<>();

    private CreditsContrailFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || minecraft.player == null) {
            clearBookkeeping(); // executors already died with the level (bridge sweep)
            return;
        }
        boolean windowOpen = CreditsClient.nonce() != 0
                && level.dimension().equals(CreditsSequence.EPILOGUE);
        if (!windowOpen || !PhotonBridge.available()) {
            // Credits over / wrong dimension / reducedFx: retire live ribbons (graceful
            // when merely windowed out; the bridge gate makes force moot either way).
            detachAll(!windowOpen);
            FIRST_SEEN.clear();
            return;
        }
        Vec3 camera = minecraft.player.position();

        // Candidates: block displays above the flyer band that have cleared the latch.
        List<Entity> latched = new ArrayList<>();
        for (Entity entity : level.entitiesForRendering()) {
            if (!(entity instanceof Display.BlockDisplay) || !entity.isAlive()
                    || entity.getY() < FLYER_MIN_Y) {
                continue;
            }
            Vec3 first = FIRST_SEEN.putIfAbsent(entity.getId(), entity.position());
            if (first != null && entity.position().distanceToSqr(first)
                    > MOVE_LATCH_DIST * MOVE_LATCH_DIST) {
                latched.add(entity);
            }
        }
        latched.sort((left, right) -> Double.compare(
                left.distanceToSqr(camera), right.distanceToSqr(camera)));

        Map<Integer, Entity> want = new HashMap<>();
        for (Entity entity : latched) {
            if (want.size() >= MAX_ATTACHED) {
                break;
            }
            want.put(entity.getId(), entity);
        }

        // Cap evictions / gone flyers: graceful stop (T_FLYERS_END discards handle the
        // common case for free — the entity executor auto-destroys with its entity).
        Iterator<Map.Entry<Integer, Entity>> iterator = ATTACHED.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<Integer, Entity> entry = iterator.next();
            if (!want.containsKey(entry.getKey())) {
                PhotonBridge.stopAttachedFx(CREDITS_CONTRAIL, entry.getValue(), false);
                iterator.remove();
            }
        }
        for (Entity entity : want.values()) {
            if (PhotonBridge.ensureAttachedFx(CREDITS_CONTRAIL, entity,
                    PhotonBridge.AUTO_ROTATE_NONE, null)) {
                ATTACHED.put(entity.getId(), entity);
            } else {
                ATTACHED.remove(entity.getId()); // refused (budget) — retry next tick
            }
        }
        // Displays that vanished entirely (discard beat): forget their latch state too.
        FIRST_SEEN.keySet().removeIf(id -> level.getEntity(id) == null);
    }

    private static void detachAll(boolean graceful) {
        for (Entity entity : ATTACHED.values()) {
            PhotonBridge.stopAttachedFx(CREDITS_CONTRAIL, entity, !graceful);
        }
        ATTACHED.clear();
    }

    private static void clearBookkeeping() {
        FIRST_SEEN.clear();
        ATTACHED.clear();
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clearBookkeeping(); // PhotonBridge.destroyAll force-kills the executors
    }
}
