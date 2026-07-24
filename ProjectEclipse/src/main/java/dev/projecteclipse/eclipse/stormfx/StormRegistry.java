package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.worldgen.fog.FogStormSites;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side source of truth for every live storm wall/vortex (P2 W9, R14/R15). Storms are
 * persistent world features: this registry keeps their parameters in memory, broadcasts
 * {@link S2CStormStatePayload} lifecycle changes to the storm's dimension and re-syncs the
 * full set on login / dimension change / respawn, so late joiners always see standing storms.
 *
 * <p><b>Frozen control API</b> (consumed by W6's intro sequence, W2's {@code /eclipsefx storm}
 * dev commands and P1's fog-storm sites; see {@code docs/plans_v3/wiring/P2-W9_wiring.md}):</p>
 * <pre>{@code
 * int  id = StormRegistry.spawnVortex(level, center, 22.0F, 48.0F, StormRegistry.RAMP_TICKS);
 * int  id = StormRegistry.spawnWall(level, center, radius, height, StormRegistry.RAMP_TICKS);
 * StormRegistry.dissipate(id, StormRegistry.DISSIPATE_TICKS);   // fades out, then forgets
 * StormRegistry.remove(id);                                     // near-instant removal
 * StormRegistry.handleFogSite(level, siteId, center, radius, active); // P1 S2CFogStormPayload bridge
 * }</pre>
 *
 * <p>P1's fog sites need NO wiring at all: {@link #pollFogSites} watches the frozen
 * {@link FogStormSites#sites()} seam and plays the R14 reveal over every site P1
 * materializes (see the method doc). {@link #handleFogSite} stays public as the direct
 * bridge for a server-side {@code S2CFogStormPayload} route or dev commands.</p>
 *
 * <p>State is transient (in-memory): publishers re-register storms on server start — P1's
 * {@code FogStormSites} re-announces its sites (P1 gap: after a restart at stage ≥ 3 the
 * site list reloads {@code active=false} and never re-fires; flagged in the wiring doc),
 * the intro vortex only exists inside the intro sequence. Everything clears on
 * {@link ServerStoppedEvent} so integrated-server restarts never leak storms.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StormRegistry {
    // ------------------------------------------------------------------ frozen timeline constants
    /** Plain spawn ramp: shells fade/scale in over this many ticks (R14/R10). */
    public static final int RAMP_TICKS = 80;
    /** Default dissipate fade (R10 uses {@code DISSIPATE 60} for the intro vortex). */
    public static final int DISSIPATE_TICKS = 60;
    /** Reveal beat 1: pause after the terrain has loaded under the (still invisible) storm. */
    public static final int REVEAL_PAUSE_TICKS = 40;
    /** Reveal beat 2: the 0.4-strength rift-glitch pulse (client-run, see {@link StormFxClient}). */
    public static final int REVEAL_GLITCH_TICKS = 20;
    /** Reveal beat 3: five hammer strikes spread over this window. */
    public static final int REVEAL_STRIKE_TICKS = 60;
    /**
     * Full reveal choreography length: pause + glitch + strikes + the {@value #RAMP_TICKS}-tick
     * shell ramp. A SPAWN payload whose {@code ticks} exceeds {@value #RAMP_TICKS} is treated by
     * the client as reveal-style (hold hidden, glitch at the pause end, ramp over the LAST
     * {@value #RAMP_TICKS} ticks) — that is the whole client/server reveal protocol, no extra
     * payload shape needed.
     */
    public static final int REVEAL_TOTAL_TICKS =
            REVEAL_PAUSE_TICKS + REVEAL_GLITCH_TICKS + REVEAL_STRIKE_TICKS + RAMP_TICKS;

    /** Fallback storm size when P1 site data carries no explicit geometry (task: "fallback defaults"). */
    public static final float DEFAULT_RADIUS = 24.0F;

    /** {@link FogStormSites#sites()} poll cadence (2 s — site materialization is a rare event). */
    private static final int FOG_SITE_POLL_TICKS = 40;
    /** Wall stands slightly outside the scarred grove so P1's camp + chests sit fully in fog. */
    private static final float SITE_WALL_MARGIN = 4.0F;
    private static int fogSitePollCountdown;

    // ------------------------------------------------------------------ state
    /** One live server-side storm. Phase mirrors the payload state ints. */
    private static final class ServerStorm {
        final int id;
        final ResourceKey<Level> dimension;
        final Vec3 center;
        final float radius;
        final float height;
        final int stormType;
        /** {@link S2CStormStatePayload#STATE_SPAWN}/{@code STATE_ACTIVE}/{@code STATE_DISSIPATE}. */
        int state;
        /** Ticks left in the current SPAWN/DISSIPATE ramp ({@code 0} while ACTIVE). */
        int ticksLeft;
        /** Total ramp length of the current state (for late-join resync of mid-ramp storms). */
        int stateTotal;

        ServerStorm(int id, ResourceKey<Level> dimension, Vec3 center, float radius, float height, int stormType) {
            this.id = id;
            this.dimension = dimension;
            this.center = center;
            this.radius = radius;
            this.height = height;
            this.stormType = stormType;
        }
    }

    /** Read-only view handed to siblings (P6 storm-mob spawners may query positions later). */
    public record StormData(int stormId, ResourceKey<Level> dimension, Vec3 center,
            float radius, float height, int stormType, int state) {}

    private static final Map<Integer, ServerStorm> STORMS = new ConcurrentHashMap<>();
    /** Stable storm ids per P1 fog-site id, so repeat announcements never duplicate storms. */
    private static final Map<String, Integer> SITE_IDS = new ConcurrentHashMap<>();
    private static final AtomicInteger NEXT_ID = new AtomicInteger(1);

    private StormRegistry() {}

    // ------------------------------------------------------------------ frozen control API

    /** Spawns a fog-storm WALL that ramps in over {@code rampTicks}. @return the storm id. */
    public static int spawnWall(ServerLevel level, Vec3 center, float radius, float height, int rampTicks) {
        return spawnStorm(level, center, radius, height, S2CStormStatePayload.TYPE_WALL, rampTicks);
    }

    /**
     * Spawns a smoke/storm VORTEX (R15 — the intro spawn vortex; W6 drives it with
     * {@code spawnVortex(level, center, 22, 48, RAMP_TICKS)} at t=300 and {@link #dissipate}
     * with {@value #DISSIPATE_TICKS} at the giant strike). @return the storm id.
     */
    public static int spawnVortex(ServerLevel level, Vec3 center, float radius, float height, int rampTicks) {
        return spawnStorm(level, center, radius, height, S2CStormStatePayload.TYPE_VORTEX, rampTicks);
    }

    /** Generic spawn ({@code stormType} per the payload constants). @return the storm id. */
    public static int spawnStorm(ServerLevel level, Vec3 center, float radius, float height,
            int stormType, int rampTicks) {
        return register(level, NEXT_ID.getAndIncrement(), center, radius, height, stormType, Math.max(1, rampTicks));
    }

    /** Fades a storm out over {@code ticks}, then forgets it. Unknown ids are ignored. */
    public static void dissipate(int stormId, int ticks) {
        ServerStorm storm = STORMS.get(stormId);
        if (storm == null) {
            return;
        }
        storm.state = S2CStormStatePayload.STATE_DISSIPATE;
        storm.stateTotal = Math.max(1, ticks);
        storm.ticksLeft = storm.stateTotal;
        broadcast(storm);
    }

    /** Near-instant removal (2-tick fade so clients never see a hard pop). */
    public static void remove(int stormId) {
        dissipate(stormId, 2);
    }

    /** Snapshot of one storm, or {@code null} when the id is unknown/expired. */
    @Nullable
    public static StormData get(int stormId) {
        ServerStorm storm = STORMS.get(stormId);
        return storm == null ? null : snapshot(storm);
    }

    /** Snapshots of every live storm in the given dimension (small list, fresh copy). */
    public static List<StormData> storms(ServerLevel level) {
        List<StormData> list = new ArrayList<>(STORMS.size());
        for (ServerStorm storm : STORMS.values()) {
            if (storm.dimension == level.dimension()) {
                list.add(snapshot(storm));
            }
        }
        return list;
    }

    /**
     * Bridge for P1-W1.9's fog-storm sites ({@code S2CFogStormPayload {siteId, center, radius,
     * active}} / {@code FogStormSites}): announce a standing site ({@code active=true}, plain
     * {@value #RAMP_TICKS}-tick ramp — dramatic first-materialization goes through
     * {@link StormReveal#request} instead) or retire it ({@code active=false}). Repeat
     * announcements of an already-live site are no-ops, so P1 may call this every re-sync.
     * Height defaults to {@link #heightFor} until P1 site data carries an explicit height.
     */
    public static void handleFogSite(ServerLevel level, String siteId, Vec3 center, float radius, boolean active) {
        Integer known = SITE_IDS.get(siteId);
        if (active) {
            if (known != null && STORMS.containsKey(known)) {
                return; // already standing
            }
            float r = radius > 0.0F ? radius : DEFAULT_RADIUS;
            int id = siteStormId(siteId);
            register(level, id, center, r, heightFor(r), S2CStormStatePayload.TYPE_WALL, RAMP_TICKS);
        } else if (known != null) {
            dissipate(known, DISSIPATE_TICKS);
        }
    }

    /** Stable storm id for a P1 fog-site id (allocated once, survives re-announcements). */
    public static int siteStormId(String siteId) {
        return SITE_IDS.computeIfAbsent(siteId, key -> NEXT_ID.getAndIncrement());
    }

    /**
     * Self-serve consumption of P1-W1.9's frozen {@link FogStormSites#sites()} seam (§3.10):
     * a site {@code FogStormSites.materializeSite} just flipped {@code active} gets the full
     * R14 reveal ({@link StormReveal#request}) — the grove terrain is already placed by then,
     * matching the "terrain loads → pause → glitch → strikes → storm" order — and a site
     * flipped back inactive dissipates. No hub wiring needed; the poll is idempotent because
     * a revealed/standing site keeps its {@link #SITE_IDS} entry alive in {@link #STORMS}.
     * Overworld only: P1 fog sites are overworld stage-3 features.
     */
    private static void pollFogSites(MinecraftServer server) {
        List<FogStormSites.Site> sites = FogStormSites.sites();
        if (sites.isEmpty()) {
            return;
        }
        ServerLevel level = server.overworld();
        for (int i = 0; i < sites.size(); i++) {
            FogStormSites.Site site = sites.get(i);
            Integer known = SITE_IDS.get(site.id());
            boolean standing = known != null && STORMS.containsKey(known);
            if (site.active() && !standing) {
                float radius = (site.radius() > 0 ? site.radius() : DEFAULT_RADIUS) + SITE_WALL_MARGIN;
                int y = level.getHeight(Heightmap.Types.WORLD_SURFACE, site.x(), site.z());
                Vec3 center = new Vec3(site.x() + 0.5D, y, site.z() + 0.5D);
                String siteId = site.id();
                StormReveal.request(level, siteId, center, radius, heightFor(radius),
                        () -> EclipseMod.LOGGER.info("Storm wall revealed over fog site {}", siteId));
            } else if (!site.active() && standing) {
                dissipate(known, DISSIPATE_TICKS);
            }
        }
    }

    /** Default wall height for a radius when the placer provides none: {@code clamp(2r, 32, 96)}. */
    public static float heightFor(float radius) {
        return Mth.clamp(radius * 2.0F, 32.0F, 96.0F);
    }

    // ------------------------------------------------------------------ StormReveal seam

    /**
     * Registers a storm that plays the full reveal choreography client-side (SPAWN with
     * {@value #REVEAL_TOTAL_TICKS} ticks). Only {@link StormReveal} calls this; it owns the
     * matching server-side strike/finish beats.
     */
    static int beginRevealStorm(ServerLevel level, String areaId, Vec3 center, float radius, float height) {
        return register(level, siteStormId(areaId), center, radius, height,
                S2CStormStatePayload.TYPE_WALL, REVEAL_TOTAL_TICKS);
    }

    // ------------------------------------------------------------------ internals

    private static int register(ServerLevel level, int id, Vec3 center, float radius, float height,
            int stormType, int rampTicks) {
        ServerStorm storm = new ServerStorm(id, level.dimension(), center, radius, height, stormType);
        storm.state = S2CStormStatePayload.STATE_SPAWN;
        storm.stateTotal = rampTicks;
        storm.ticksLeft = rampTicks;
        STORMS.put(id, storm);
        broadcast(storm);
        return id;
    }

    private static StormData snapshot(ServerStorm storm) {
        return new StormData(storm.id, storm.dimension, storm.center, storm.radius,
                storm.height, storm.stormType, storm.state);
    }

    private static S2CStormStatePayload payloadFor(ServerStorm storm) {
        return new S2CStormStatePayload(storm.id, storm.center, storm.radius, storm.height,
                storm.stormType, storm.state, storm.ticksLeft);
    }

    private static void broadcast(ServerStorm storm) {
        // The whole dimension: storms are landmark-scale features, visible from anywhere.
        ServerLevel level = currentServerLevel(storm.dimension);
        if (level != null) {
            PacketDistributor.sendToPlayersInDimension(level, payloadFor(storm));
        }
    }

    @Nullable
    private static ServerLevel currentServerLevel(ResourceKey<Level> dimension) {
        MinecraftServer server = net.neoforged.neoforge.server.ServerLifecycleHooks.getCurrentServer();
        return server == null ? null : server.getLevel(dimension);
    }

    // ------------------------------------------------------------------ lifecycle events

    /** Keepalive cadence for ACTIVE storms (self-healing sync; handle() is idempotent). */
    private static final int KEEPALIVE_TICKS = 200;
    private static int keepaliveCountdown = KEEPALIVE_TICKS;

    /** Advances SPAWN→ACTIVE ramps, drops dissipated storms, and polls P1's fog sites. */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (--fogSitePollCountdown <= 0) {
            fogSitePollCountdown = FOG_SITE_POLL_TICKS;
            pollFogSites(event.getServer());
        }
        if (STORMS.isEmpty()) {
            return;
        }
        if (--keepaliveCountdown <= 0) {
            keepaliveCountdown = KEEPALIVE_TICKS;
            for (ServerStorm storm : STORMS.values()) {
                if (storm.state == S2CStormStatePayload.STATE_ACTIVE) {
                    broadcast(storm);
                }
            }
        }
        for (ServerStorm storm : STORMS.values()) {
            if (storm.state == S2CStormStatePayload.STATE_ACTIVE) {
                continue;
            }
            if (--storm.ticksLeft > 0) {
                continue;
            }
            if (storm.state == S2CStormStatePayload.STATE_SPAWN) {
                storm.state = S2CStormStatePayload.STATE_ACTIVE;
                storm.ticksLeft = 0;
                storm.stateTotal = 0;
                // Clients promote SPAWN→ACTIVE locally, but re-broadcast anyway: any client
                // that missed the SPAWN packet (dimension-swap window, join race) adopts the
                // storm here instead of never learning about it.
                broadcast(storm);
            } else {
                STORMS.remove(storm.id);
            }
        }
    }

    /** Login resync: the joining player gets every storm of their current dimension. */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            resync(player);
        }
    }

    /** Dimension-change resync (the client wiped its storms on the level swap). */
    @SubscribeEvent
    static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            resync(player);
        }
    }

    /** Respawn resync ({@code ClientPlayerNetworkEvent.Clone} cleared the client cache). */
    @SubscribeEvent
    static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            resync(player);
        }
    }

    private static void resync(ServerPlayer player) {
        for (ServerStorm storm : STORMS.values()) {
            if (storm.dimension == player.level().dimension()) {
                PacketDistributor.sendToPlayer(player, payloadFor(storm));
            }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        STORMS.clear();
        SITE_IDS.clear();
        NEXT_ID.set(1);
    }
}
