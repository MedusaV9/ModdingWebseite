package dev.projecteclipse.eclipse.limbo;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.phys.AABB;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.LevelTickEvent;

/**
 * P6-W2 gutted this class: the ghost ship's oars are no longer eight free-floating
 * {@code BLOCK_DISPLAY} poles animated on their own server clock (user bug 4d — they
 * could never sync with the rowers' 78.5 t client-side arm swing). The oar is now part of
 * the Deckhand's own GeckoLib skeleton ({@code geo/entity/deckhand.geo.json}, bones
 * {@code oar/oar_loom/oar_shaft/oar_blade}) and swings inside the shared 60 t {@code row}
 * loop — one clock, one object. What remains here, keeping every pre-P6 signature:
 *
 * <ul>
 *   <li>{@link #ensureOars} — <b>display-oar cleanup/migration</b>: resolves the UUIDs
 *       persisted in {@link EclipseWorldState#getOarEntities()}, discards those displays
 *       and prunes the list toward {@code setOarEntities(List.of())}. Entity sections
 *       load asynchronously after boot, so unresolved UUIDs are retried on the level tick
 *       until the list is empty (then this class is effectively free). A one-shot
 *       positional sweep (hull band around {@code waterline + 2}) additionally catches
 *       legacy displays that fell off the list in a world-state reset — it runs on the
 *       first tick with a player in limbo, when the ship's entity sections are loaded.</li>
 *   <li>{@link #beginTilt}/{@link #endTilt} — the start-event cutscene hooks
 *       ({@code StartEventCutscene} t=TILT_TICK) now re-target the crew: they flip the
 *       static tilt flag that {@code DeckhandEntity.tick} mirrors into its synced
 *       {@code TILT} pose (oars shipped skyward while the ship keels over). The old
 *       display-transform interpolation duration is obsolete — the crew's {@code tilt}
 *       animation carries its own ramp.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class OarAnimator {
    /** Cadence of the migration retry while persisted display UUIDs remain unresolved. */
    private static final int MIGRATION_RETRY_TICKS = 100;
    /** Hull band swept for stray legacy oar displays: |x| ≤ this (ship half length + margin). */
    private static final int SWEEP_HALF_LENGTH = 22;
    /** Hull band half width (oars floated ≤ ~5.5 blocks off center; margin included). */
    private static final int SWEEP_HALF_WIDTH = 9;

    /** While true (start-event cutscene), the crew holds the keel-over tilt pose. */
    private static volatile boolean tiltMode = false;
    /** One positional stray-display sweep per boot, once limbo has a player (sections loaded). */
    private static boolean sweptThisBoot = false;

    private OarAnimator() {}

    /**
     * Legacy block-display oar migration (bug 4d): discards every persisted display and
     * empties {@link EclipseWorldState#getOarEntities()}. Displays whose entity section
     * is not loaded yet stay on the list and are retried by {@link #onLevelTick} — on a
     * fully migrated world the list is empty and this is a logged no-op.
     * Called by {@code GhostShipBuilder} on server start (pre-P6 signature kept).
     */
    public static void ensureOars(ServerLevel limbo) {
        sweptThisBoot = false;
        List<UUID> remaining = purgeListedDisplays(limbo);
        if (remaining.isEmpty()) {
            EclipseMod.LOGGER.info("Ghost ship oars: no legacy block-display oars left (oars live in the Deckhand model now)");
        } else {
            EclipseMod.LOGGER.info(
                    "Ghost ship oars: {} legacy display(s) not resolvable yet (entity sections still loading) — will retry",
                    remaining.size());
        }
    }

    /** Retries the UUID migration + runs the one-shot positional sweep once limbo is populated. */
    @SubscribeEvent
    public static void onLevelTick(LevelTickEvent.Post event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !level.dimension().equals(LimboDimension.LIMBO)) {
            return;
        }
        if (!sweptThisBoot && !level.players().isEmpty()) {
            sweptThisBoot = true;
            int swept = sweepStrayDisplays(level);
            if (swept > 0) {
                EclipseMod.LOGGER.info("Ghost ship oars: swept {} stray legacy oar display(s) off the hull band", swept);
            }
        }
        if (level.getGameTime() % MIGRATION_RETRY_TICKS != 0
                || EclipseWorldState.get(level.getServer()).getOarEntities().isEmpty()) {
            return;
        }
        List<UUID> remaining = purgeListedDisplays(level);
        if (remaining.isEmpty()) {
            EclipseMod.LOGGER.info("Ghost ship oars: legacy display migration complete");
        }
    }

    /**
     * Cutscene hook: the crew ships its oars and braces while the vessel keels over.
     * {@code durationTicks} (the old display interpolation window) is logged for parity
     * but unused — the deckhands' looping {@code tilt} animation has its own ramp.
     */
    public static void beginTilt(ServerLevel limbo, int durationTicks) {
        tiltMode = true;
        EclipseMod.LOGGER.info("start_event tilt: crew ships oars for the keel-over ({} ticks; {} deckhand(s) listed)",
                durationTicks, EclipseWorldState.get(limbo.getServer()).getDeckhandEntities().size());
    }

    /** Ends the cutscene tilt; the crew sags back into the rowing loop within a tick. */
    public static void endTilt() {
        tiltMode = false;
    }

    /** Read by {@code DeckhandEntity.tick} to mirror the pose into its synced TILT flag. */
    public static boolean isTiltActive() {
        return tiltMode;
    }

    /** Discards resolvable listed displays; persists + returns the still-unresolved rest. */
    private static List<UUID> purgeListedDisplays(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        List<UUID> listed = state.getOarEntities();
        if (listed.isEmpty()) {
            return List.of();
        }
        List<UUID> remaining = new ArrayList<>();
        int discarded = 0;
        for (UUID id : listed) {
            Entity entity = limbo.getEntity(id);
            if (entity == null) {
                remaining.add(id);
            } else {
                entity.discard();
                discarded++;
            }
        }
        state.setOarEntities(remaining);
        if (discarded > 0) {
            EclipseMod.LOGGER.info("Ghost ship oars: discarded {} legacy block-display oar(s), {} pending",
                    discarded, remaining.size());
        }
        return remaining;
    }

    /**
     * Belt-and-braces for worlds whose oar UUID list was lost (state desync/dev reset):
     * any block display floating in the old oar band — alongside the hull at
     * {@code waterline + 2} — is definitionally a legacy oar and gets discarded.
     */
    private static int sweepStrayDisplays(ServerLevel limbo) {
        int waterline = GhostShipBuilder.waterlineY(limbo);
        AABB band = new AABB(-SWEEP_HALF_LENGTH, waterline, -SWEEP_HALF_WIDTH,
                SWEEP_HALF_LENGTH, waterline + 4.0D, SWEEP_HALF_WIDTH);
        int swept = 0;
        for (Entity display : limbo.getEntities(EntityType.BLOCK_DISPLAY, band, entity -> true)) {
            display.discard();
            swept++;
        }
        return swept;
    }
}
