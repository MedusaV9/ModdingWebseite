package dev.projecteclipse.eclipse.protection;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.level.ExplosionEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * B7 (plans_v5) pre-protection: no-build zones over the mod's authored set-piece
 * landmarks, active from server start — i.e. BEFORE players ever reach them. Multi-zone
 * sibling of {@link dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection}
 * (deliberately a NEW file so the sanctum file's ownership stays disjoint):
 *
 * <ul>
 *   <li><b>Overworld breach crater</b> ({@code eclipse:nether_breach}): full-column
 *       cylinder, r = landmark radius + {@value #BREACH_PAD} — the funnel pierces the
 *       whole disc, so no vertical band applies.</li>
 *   <li><b>Nether arrival crater/chimney</b> ({@code eclipse:breach_arrival}): full
 *       column too (the chimney + ceiling bore span floor to world top), same pad.</li>
 *   <li><b>Observatory summit</b>: r {@value #SUMMIT_RADIUS} around the mountain
 *       center (the {@code eclipse:wizard_observatory} anchor), from
 *       {@value #SUMMIT_DEPTH} blocks below the deterministic summit surface to the
 *       sky. Deliberately NOT full-column — the Ancient City sits vertically below in
 *       the same footprint and must stay minable.</li>
 * </ul>
 *
 * <p>Break/place are cancelled for everyone except devmode players ({@link DevMode},
 * PROGFIX #5 — ops obey the zones until they toggle {@code /devmode}) with a polite
 * action-bar note ({@code message.eclipse.landmark_protected}); explosions
 * lose every affected block inside a zone. Zones derive purely from
 * {@link DiscMapData} plus one deterministic {@link DiscTerrainFunction} summit probe,
 * rebuilt per server start (statics never leak across singleplayer re-opens).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LandmarkProtection {
    /** Extra clearance past the breach landmarks' own radii (crater + creep halo rim). */
    public static final int BREACH_PAD = 12;
    /** Protection radius around the observatory summit anchor. */
    public static final int SUMMIT_RADIUS = 24;
    /** Depth below the summit surface still covered (the terraforming shelf cut). */
    public static final int SUMMIT_DEPTH = 24;
    /** WOAH-04 resonance-field valley radius (PLAN-04 §2.3: monoliths + light paths). */
    public static final int RESONANCE_RADIUS = 52;
    /** Depth below the anchor surface still covered (plateau cut + bowl carve − 12 pad). */
    public static final int RESONANCE_DEPTH = 24;

    /** One protected cylinder slice; full columns use MIN/MAX sentinels. */
    private record Zone(ResourceKey<Level> dimension, int x, int z, int radius,
            int minY, int maxY) {

        boolean contains(ResourceKey<Level> dim, BlockPos pos) {
            if (dim != this.dimension || pos.getY() < this.minY || pos.getY() > this.maxY) {
                return false;
            }
            long dx = pos.getX() - this.x;
            long dz = pos.getZ() - this.z;
            return dx * dx + dz * dz <= (long) this.radius * this.radius;
        }
    }

    @Nullable
    private static volatile List<Zone> zones;

    private LandmarkProtection() {}

    /** Builds the zone table once per server start (before any player can act). */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        List<Zone> built = buildZones();
        zones = built;
        for (Zone zone : built) {
            EclipseMod.LOGGER.info(
                    "Landmark protection active: r={} around ({}, {}) y[{}..{}] in {}",
                    zone.radius(), zone.x(), zone.z(), zone.minY(), zone.maxY(),
                    zone.dimension().location());
        }
    }

    /** Statics must never leak into the next world (singleplayer re-opens reuse the JVM). */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        zones = null;
    }

    /** Whether a position lies inside any landmark no-build zone. */
    public static boolean isProtected(Level level, BlockPos pos) {
        List<Zone> active = zones;
        if (active == null) {
            active = buildZones();
            zones = active;
        }
        for (Zone zone : active) {
            if (zone.contains(level.dimension(), pos)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Derives the zone table from the frozen map data. The observatory summit anchor is
     * the authored mountain center; its surface Y is the same deterministic probe the
     * observatory placer anchors on, so the band matches the stamped shelf.
     */
    private static List<Zone> buildZones() {
        DiscMapData map = DiscMapData.get();
        List<Zone> built = new ArrayList<>(3);
        DiscMapData.Landmark breach = landmark(map, DiscProfile.OVERWORLD, "eclipse:nether_breach");
        if (breach != null) {
            built.add(new Zone(Level.OVERWORLD, breach.x(), breach.z(),
                    breach.radius() + BREACH_PAD, Integer.MIN_VALUE, Integer.MAX_VALUE));
        }
        DiscMapData.Landmark arrival = landmark(map, DiscProfile.NETHER, "eclipse:breach_arrival");
        if (arrival != null) {
            built.add(new Zone(Level.NETHER, arrival.x(), arrival.z(),
                    arrival.radius() + BREACH_PAD, Integer.MIN_VALUE, Integer.MAX_VALUE));
        }
        DiscMapData.Mountain mountain = map.profile(DiscProfile.OVERWORLD).mountain();
        if (mountain != null) {
            int summitY = DiscTerrainFunction.surfaceY(
                    DiscProfile.OVERWORLD, mountain.x(), mountain.z());
            built.add(new Zone(Level.OVERWORLD, mountain.x(), mountain.z(),
                    SUMMIT_RADIUS, summitY - SUMMIT_DEPTH, Integer.MAX_VALUE));
        }
        // WOAH-04 resonance field (self-enqueued at stage 5, NOT a DiscMapDefaults row):
        // r-52 cylinder around the authored valley anchor from below the carved bowl
        // floor to the sky — the monoliths + light paths must never be undermined
        // (docs/plans_v3/woah/PLAN-04 §2.3). Deliberately active even before the site
        // is placed: the zone table exists from server start, players cannot pre-mine
        // the valley footprint. Same deterministic surface probe as the summit band.
        int resonanceY = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD,
                dev.projecteclipse.eclipse.woah.resonance.ResonanceFieldService.ANCHOR_X,
                dev.projecteclipse.eclipse.woah.resonance.ResonanceFieldService.ANCHOR_Z);
        built.add(new Zone(Level.OVERWORLD,
                dev.projecteclipse.eclipse.woah.resonance.ResonanceFieldService.ANCHOR_X,
                dev.projecteclipse.eclipse.woah.resonance.ResonanceFieldService.ANCHOR_Z,
                RESONANCE_RADIUS, resonanceY - RESONANCE_DEPTH, Integer.MAX_VALUE));
        return List.copyOf(built);
    }

    @Nullable
    private static DiscMapData.Landmark landmark(DiscMapData map, DiscProfile profile, String id) {
        for (DiscMapData.Landmark landmark : map.landmarks(profile)) {
            if (id.equals(landmark.id())) {
                return landmark;
            }
        }
        return null;
    }

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !isProtected(level, event.getPos())) {
            return;
        }
        Player player = event.getPlayer();
        if (isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        hint(player);
    }

    @SubscribeEvent
    public static void onBlockPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !isProtected(level, event.getPos())) {
            return;
        }
        Entity entity = event.getEntity();
        if (entity instanceof Player player && isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof Player player) {
            hint(player);
        }
    }

    /** Explosions may still hurt entities, but never reshape a landmark. */
    @SubscribeEvent
    public static void onExplosionDetonate(ExplosionEvent.Detonate event) {
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        event.getAffectedBlocks().removeIf(pos -> isProtected(level, pos));
    }

    /** PROGFIX #5: only devmode players bypass — ops obey the zones by default. */
    private static boolean isExempt(@Nullable Player player) {
        return DevMode.isExempt(player);
    }

    /** Polite deny: action bar + a muffled chime, never chat (SanctumProtection style). */
    private static void hint(@Nullable Player player) {
        if (player instanceof ServerPlayer serverPlayer) {
            serverPlayer.displayClientMessage(
                    Component.translatable("message.eclipse.landmark_protected"), true);
            serverPlayer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.BLOCKS, 0.7F, 0.7F);
        }
    }
}
