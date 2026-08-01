package dev.projecteclipse.eclipse.worldgen.fog;

import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.entity.spawn.EventSpawnRules;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.stormfx.StormRegistry;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.ChestMenu;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerContainerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * WAVE5 (F-105 B) B6 — chest-open storm reaction (IDEA-15 §10): the first time a player
 * opens one of a fog site's loot chests each session, the storm answers — the camp stops
 * being "free chests" and becomes a scene.
 *
 * <ul>
 * <li>A two-strike shell arc volley anchored at the WALL point facing the chest (server-
 *     projected {@code center + n̂·shellReach}; EVAL-4 {@code storm bolt} learning — the
 *     anchor is NEVER the player or the chest, the wall itself lashes out).</li>
 * <li>{@code event.lightning_far} at the chest (0.8/0.8 — the §10 "pitch 0.8" rumble).</li>
 * <li>30 % chance: one {@code fog_revenant} materializes {@value #REVENANT_MIN_DIST}–
 *     {@value #REVENANT_MAX_DIST} blocks out via {@link EventSpawnRules#trySpawnChestRevenant}
 *     — the single public hook that owns {@code SpawnGates.FOG_STORM} + both revenant caps,
 *     never duplicated here.</li>
 * </ul>
 *
 * <p>One-shot per chest per session ({@link #STUNG_CHESTS}, flushed on server stop):
 * re-opens stay silent. Chest positions come from the persisted
 * {@link EclipseWorldgenState.FogSiteState#chests()} index ({@code FogStormSites.placeChests}
 * writes it), matched against the opened {@link ChestMenu}'s backing block entity — sites
 * place single {@code Blocks.CHEST} columns, so the container is always one block entity.
 * The sting only fires while the site's storm is actually STANDING in {@link StormRegistry}
 * (checked before the latch, so a stormless open never burns the chest's one shot).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogChestSting {
    /** Arc volley: two same-tick strikes this many radians apart around the chest bearing. */
    private static final double VOLLEY_SPREAD_RAD = 0.12D;
    /** IDEA-15 §10: strike intensity 0.5 (the {@code FX_LIGHTNING_STRIKE} {@code a} lane). */
    private static final float ARC_INTENSITY = 0.5F;
    /** Local event, not a landmark: the volley payload reaches this far (never dimension-wide). */
    private static final double ARC_EVENT_RANGE = 160.0D;
    /** The wall anchor sits at this fraction of the storm height (mid-wall — readable). */
    private static final double WALL_ANCHOR_HEIGHT_FRAC = 0.55D;
    /** The rumble at the chest (plan §4 "0.8" + §10 "pitch 0.8" — volume and pitch). */
    private static final float RUMBLE_VOLUME = 0.8F;
    private static final float RUMBLE_PITCH = 0.8F;
    /** IDEA-15 §10: 30 % revenant sting, 12–16 blocks out from the chest. */
    private static final float REVENANT_CHANCE = 0.30F;
    private static final double REVENANT_MIN_DIST = 12.0D;
    private static final double REVENANT_MAX_DIST = 16.0D;

    /** Chests that already stung this session (one-shot latch; re-opens stay silent). */
    private static final Set<BlockPos> STUNG_CHESTS = Collections.synchronizedSet(new HashSet<>());

    private FogChestSting() {}

    @SubscribeEvent
    static void onContainerOpen(PlayerContainerEvent.Open event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !(player.level() instanceof ServerLevel level)
                || level.dimension() != Level.OVERWORLD) {
            return; // Fog sites are overworld stage-3 features (StormRegistry doc).
        }
        List<FogStormSites.Site> sites = FogStormSites.sites();
        if (sites.isEmpty()) {
            return;
        }
        BlockPos chest = containerPos(event.getContainer());
        if (chest == null) {
            return;
        }
        FogStormSites.Site site = siteOwningChest(level, sites, chest);
        if (site == null) {
            return;
        }
        // Standing-storm gate BEFORE the latch: a stormless open (site mid-retire) must
        // not burn the chest's single sting for the session.
        StormRegistry.StormData storm = StormRegistry.get(StormRegistry.siteStormId(site.id()));
        if (storm == null || storm.state() == S2CStormStatePayload.STATE_DISSIPATE
                || storm.state() == S2CStormStatePayload.STATE_EXPLODE) {
            return;
        }
        if (!STUNG_CHESTS.add(chest.immutable())) {
            return; // Re-open: silent (the one-shot latch).
        }

        // Wall anchor: the shell point on the chest's bearing from the storm center. For
        // sphere domes the shell's horizontal reach shrinks with height — anchoring at the
        // true dome band keeps |anchor − center| ≈ shell (the log-plausibility check).
        Vec3 center = storm.center();
        double dx = chest.getX() + 0.5D - center.x;
        double dz = chest.getZ() + 0.5D - center.z;
        double dist = Math.sqrt(dx * dx + dz * dz);
        double bearing = dist < 1.0E-3D
                ? level.getRandom().nextDouble() * Math.PI * 2.0D : Math.atan2(dz, dx);
        double yOff = storm.height() * WALL_ANCHOR_HEIGHT_FRAC;
        double reach = storm.stormType() == S2CStormStatePayload.TYPE_SPHERE
                ? Math.sqrt(Math.max(1.0D, storm.radius() * storm.radius() - yOff * yOff))
                : storm.radius();
        Vec3 wall = new Vec3(center.x + Math.cos(bearing) * reach, center.y + yOff,
                center.z + Math.sin(bearing) * reach);
        // The volley: two same-tick strikes straddling the chest bearing — both anchored
        // ON the wall (never the player). Audio is the sender's job (W1 wiring rule): the
        // beat is the far rumble AT the chest, the §10 "the storm noticed" read.
        for (int i = 0; i < 2; i++) {
            double a = bearing + (i == 0 ? -VOLLEY_SPREAD_RAD : VOLLEY_SPREAD_RAD);
            Vec3 impact = new Vec3(center.x + Math.cos(a) * reach, wall.y,
                    center.z + Math.sin(a) * reach);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact,
                    ARC_INTENSITY, 0.0F, ARC_EVENT_RANGE);
        }
        level.playSound(null, chest.getX() + 0.5D, chest.getY() + 0.5D, chest.getZ() + 0.5D,
                EclipseSounds.EVENT_LIGHTNING_FAR.get(), SoundSource.WEATHER,
                RUMBLE_VOLUME, RUMBLE_PITCH);

        BlockPos revenant = null;
        if (level.getRandom().nextFloat() < REVENANT_CHANCE) {
            revenant = EventSpawnRules.trySpawnChestRevenant(level, site,
                    Vec3.atCenterOf(chest), REVENANT_MIN_DIST, REVENANT_MAX_DIST);
        }
        EclipseMod.LOGGER.debug("[w5b-chest] site={} pos={} revenant={} wall=({}, {}, {})",
                site.id(), chest.toShortString(), revenant != null,
                String.format(java.util.Locale.ROOT, "%.1f", wall.x),
                String.format(java.util.Locale.ROOT, "%.1f", wall.y),
                String.format(java.util.Locale.ROOT, "%.1f", wall.z));
    }

    /** The active site whose persisted chest index contains {@code chest}, or {@code null}. */
    @Nullable
    private static FogStormSites.Site siteOwningChest(ServerLevel level,
            List<FogStormSites.Site> sites, BlockPos chest) {
        EclipseWorldgenState state = EclipseWorldgenState.get(level.getServer());
        for (FogStormSites.Site site : sites) {
            if (site.active() && state.fogSiteState(site.id()).chests().contains(chest)) {
                return site;
            }
        }
        return null;
    }

    /**
     * The opened container's block position: fog-site chests are single {@code Blocks.CHEST}
     * columns, so their menu is a {@link ChestMenu} backed by one chest block entity.
     * Anything else (double chests, minecarts, ender chests, other menus) → {@code null}.
     */
    @Nullable
    private static BlockPos containerPos(AbstractContainerMenu menu) {
        if (menu instanceof ChestMenu chestMenu
                && chestMenu.getContainer() instanceof BlockEntity blockEntity) {
            return blockEntity.getBlockPos();
        }
        return null;
    }

    /** Session latch hygiene: the next world's chests all get their sting back. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        STUNG_CHESTS.clear();
    }
}
