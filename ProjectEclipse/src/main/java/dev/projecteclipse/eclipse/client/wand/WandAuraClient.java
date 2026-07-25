package dev.projecteclipse.eclipse.client.wand;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-PLAYER (IDEAS-player.md #6) — the per-path idle hand auras: three tiny looping Photon
 * effects ({@code eclipse:wand_idle_riss} scanline ribbon / {@code _glut} ember ring /
 * {@code _stern} star halo) attached to any visible player holding an owned, pathed wand.
 * This is a WINDOWED-loop controller (INTEGRATION.md §4, entity flavor): the window is
 * "this player is holding their soulbound pathed wand near me", with hysteresis on the
 * close edge so hotbar fumbles and chest screens don't strobe the aura.
 *
 * <p><b>Zero wire:</b> everything gates on data the client already has — the held
 * {@code ItemStack}'s synced {@code WAND_PATH}/{@code WAND_OWNER} components (components
 * sync to all trackers). Scan cadence is {@value #ENSURE_CADENCE} ticks;
 * {@code PhotonBridge.ensureAttachedFx} is the keepalive primitive (default
 * {@code allowMulti=false} dedup — a live loop makes the re-ensure a silent no-op,
 * untrack/re-track self-heals on the next scan). NEVER set allowMulti here: two stacked
 * auras is the failure mode.</p>
 *
 * <p><b>Gates</b> (any failing → windows close): {@code PhotonBridge.available()} (photon
 * present + {@code photonFx} + NOT {@code reducedFx} — a reducedFx flip force-kills every
 * aura on the next scan) and the {@code wandAuras} client toggle. Per player: holding the
 * wand in either hand, path chosen, owner matches the holder, within the
 * {@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}-block camera band, capped to the
 * {@value #MAX_HOLDERS} nearest holders, and the LOCAL player is skipped in first person
 * (the eye-anchored aura would sit inside the camera; it re-ensures in F5). Close edge:
 * {@value #RELEASE_MISSES} consecutive failed scans (~2 s) before the graceful stop.</p>
 *
 * <p><b>Fallback/budget:</b> pure additive cosmetic — no Quasar leg, photon-less clients
 * simply see no idle aura. Each aura is one executor (≤ 48 particles by asset budget)
 * against {@code PhotonBridge.MAX_LIVE_EXECUTORS}; the {@value #MAX_HOLDERS}-holder cap
 * bounds the worst case. Entity death/untrack cleanup is Photon's own (bridge sweep).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WandAuraClient {
    /** Scan/keepalive cadence in ticks (IDEAS-player §0: ensure on a slow 20–40t cadence). */
    private static final int ENSURE_CADENCE = 20;
    /** Failed scans before a window closes (hysteresis: ~2 s of grace for hotbar fumbles). */
    private static final int RELEASE_MISSES = 2;
    /** Auras materialize for holders within this camera distance (blocks)… */
    private static final double MATERIALIZE_DIST = 32.0D;
    /** …and release only beyond this one (no boundary strobing while circling someone). */
    private static final double RELEASE_DIST = 40.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Hard cap on simultaneously aura'd players (IDEAS-player #6 budget law). */
    private static final int MAX_HOLDERS = 8;
    /** Main-hand offset in the LOOK-rotated frame (eye anchor → hand height, IDEAS #6). */
    private static final Vec3 HAND_OFFSET = new Vec3(0.35D, -0.45D, 0.4D);

    private static final ResourceLocation IDLE_RISS = fx("wand_idle_riss");
    private static final ResourceLocation IDLE_GLUT = fx("wand_idle_glut");
    private static final ResourceLocation IDLE_STERN = fx("wand_idle_stern");

    /** Open windows: holder UUID → live aura state (client main thread only). */
    private static final Map<UUID, AuraState> AURAS = new HashMap<>();
    private static int cadence;

    private static final class AuraState {
        ResourceLocation fxId;
        int misses;

        AuraState(ResourceLocation fxId) {
            this.fxId = fxId;
        }
    }

    private WandAuraClient() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            AURAS.clear(); // executors died with the level (bridge sweep/logout reset)
            cadence = 0;
            return;
        }
        if (!PhotonBridge.available() || !EclipseClientConfig.wandAuras()) {
            // Global gate slammed (reducedFx flip, photonFx off, toggle off): kill every
            // loop NOW — reducedFx must not wait out a graceful fade.
            stopAll(level, true);
            cadence = 0;
            return;
        }
        if (minecraft.isPaused() || ++cadence < ENSURE_CADENCE) {
            return; // keep the windows, freeze the cadence
        }
        cadence = 0;
        scan(minecraft, level);
    }

    /** One keepalive scan: ensure the {@value #MAX_HOLDERS} nearest gated holders, age the rest. */
    private static void scan(Minecraft minecraft, ClientLevel level) {
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        // Gate pass 1: collect visible wand-holders inside their band, nearest first.
        List<Player> holders = new ArrayList<>();
        for (Player player : level.players()) {
            ResourceLocation aura = auraFor(player);
            if (aura == null) {
                continue;
            }
            if (player == minecraft.player && minecraft.options.getCameraType().isFirstPerson()) {
                continue; // inside the camera — self-corrects when toggling to F5
            }
            double distSq = camera.distanceToSqr(player.position());
            if (distSq > (AURAS.containsKey(player.getUUID())
                    ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
                continue; // outside the hysteresis band
            }
            holders.add(player);
        }
        holders.sort((first, second) -> Double.compare(
                camera.distanceToSqr(first.position()), camera.distanceToSqr(second.position())));
        // Gate pass 2: ensure the nearest MAX_HOLDERS, remembering who was kept alive.
        java.util.Set<UUID> ensured = new java.util.HashSet<>();
        for (Player player : holders) {
            if (ensured.size() >= MAX_HOLDERS) {
                break;
            }
            ResourceLocation aura = auraFor(player);
            AuraState state = AURAS.get(player.getUUID());
            if (state == null) {
                state = new AuraState(aura);
                AURAS.put(player.getUUID(), state);
            } else if (!state.fxId.equals(aura)) {
                // Path changed under us (dev edits): retire the old loop before the new.
                PhotonBridge.stopAttachedFx(state.fxId, player, false);
                state.fxId = aura;
            }
            state.misses = 0;
            PhotonBridge.ensureAttachedFx(aura, player, PhotonBridge.AUTO_ROTATE_LOOK, HAND_OFFSET);
            ensured.add(player.getUUID());
        }
        // Close pass: windows not re-ensured this scan age toward the graceful stop.
        for (Iterator<Map.Entry<UUID, AuraState>> it = AURAS.entrySet().iterator(); it.hasNext(); ) {
            Map.Entry<UUID, AuraState> entry = it.next();
            if (ensured.contains(entry.getKey())) {
                continue;
            }
            AuraState state = entry.getValue();
            if (++state.misses < RELEASE_MISSES) {
                continue; // hysteresis grace — the wand may be back in hand next scan
            }
            it.remove();
            Player holder = level.getPlayerByUUID(entry.getKey());
            if (holder != null) {
                PhotonBridge.stopAttachedFx(state.fxId, holder, false); // graceful fade
            }
            // Untracked holder: the bridge sweep already destroyed the executor.
        }
    }

    /**
     * The idle-aura fx id for {@code player}'s currently held wand, or {@code null} when
     * the per-player gate fails: no wand in either hand, path not chosen yet, or the
     * holder is not the soulbound owner (a stolen wand shows no aura — it will not cast
     * for the thief either).
     */
    @Nullable
    private static ResourceLocation auraFor(Player player) {
        ItemStack stack = heldWand(player);
        if (stack == null) {
            return null;
        }
        UUID owner = stack.get(WandItems.WAND_OWNER.get());
        if (owner == null || !owner.equals(player.getUUID())) {
            return null;
        }
        return switch (WandPath.byId(stack.getOrDefault(WandItems.WAND_PATH.get(), 0))) {
            case RISS -> IDLE_RISS;
            case GLUT -> IDLE_GLUT;
            case STERN -> IDLE_STERN;
            default -> null;
        };
    }

    /** The wand in either hand (main hand wins — mirrors {@code WandPowers.findHeldWand}). */
    @Nullable
    private static ItemStack heldWand(Player player) {
        ItemStack main = player.getMainHandItem();
        if (main.getItem() instanceof EclipseWandItem) {
            return main;
        }
        ItemStack off = player.getOffhandItem();
        return off.getItem() instanceof EclipseWandItem ? off : null;
    }

    /** Stops every live aura ({@code force=true} = instant kill, the reducedFx path). */
    private static void stopAll(ClientLevel level, boolean force) {
        if (AURAS.isEmpty()) {
            return;
        }
        for (Map.Entry<UUID, AuraState> entry : AURAS.entrySet()) {
            Player holder = level.getPlayerByUUID(entry.getKey());
            if (holder != null) {
                PhotonBridge.stopAttachedFx(entry.getValue().fxId, holder, force);
            }
        }
        AURAS.clear();
    }

    /** Disconnect reset — the bridge force-destroys the executors; drop the bookkeeping. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        AURAS.clear();
        cadence = 0;
    }
}
