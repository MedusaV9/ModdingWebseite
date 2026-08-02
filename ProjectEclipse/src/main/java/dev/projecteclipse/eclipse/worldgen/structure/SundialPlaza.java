package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.ritual.BeamEmitter;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * §F flavor landmark: the sundial plaza around the sanctum. The sanctum surface doubles
 * as a 24-block dial — 12 chiseled-blackstone hour markers on the r=11 ring (the north
 * marker gilded), plus a polished-basalt "shadow line" from the dais edge to the ring
 * whose angle encodes the current event day (day 1 = north, one 14th of the circle per
 * day). {@code DayScheduler.setDay} calls {@link #onDayChanged}: the old line is erased by
 * re-stamping the deterministic {@link AltarSanctumBuilder#groundMix} surface, then the new
 * line is placed — ~40 blocks rewritten per day change.
 *
 * <p><b>WAVE6 (F-106 C) — C3 shadow WANDER.</b> When the change is watchable (a player
 * within {@value #ANIMATE_PLAYER_RANGE} blocks AND the dial chunk loaded), the redraw is
 * no longer instant: a small server-tick task schedule erases the old line OUTWARD and
 * places the new line INWARD over ~{@value #STEP_INTERVAL_TICKS}×16 ≈ 30 ticks. Every
 * placement fires the existing {@code map_expand_materialize} Quasar puff plus a
 * {@code ui.caption_tick} to players within {@value #FX_SOUND_RANGE} blocks (rising pitch —
 * time audibly clicks forward). The finale flashes the ring marker the new line points at
 * gilded for {@value #MARKER_FLASH_TICKS}t and raises a {@value #BEAM_DURATION_TICKS}t
 * (5 s) {@link BeamEmitter} column on it (API call only). Boot-order law: server start,
 * catch-up bursts, no watcher or an unloaded dial chunk all keep the INSTANT legacy path —
 * and a chunk unloading mid-animation flushes the remaining writes instantly and silently.
 * Probe: {@code [w6c-sundial] animated=<b> steps=<n>}.</p>
 *
 * <p>P6-W4 re-anchor: everything here derives from
 * {@code EclipseWorldState.getSanctumAltarPos()} minus
 * {@value AltarSanctumBuilder#ALTAR_ABOVE_GROUND}, so when the sanctum flips to the v2
 * floating island the dial and shadow line automatically re-stamp onto the island TOP
 * (whose surface layer is {@link AltarSanctumBuilder#groundMix} for exactly this erase
 * contract — see {@code FloatingSanctumBuilder.massMix}). The r=11 ring and r 7..10
 * shadow band both fit inside the island's r=16/14 top ellipse. No code change needed —
 * do not key anything here off absolute ground Y.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SundialPlaza {
    /** Dial ring radius (markers sit inside the r=12 flattened grounds). */
    private static final int DIAL_RADIUS = 11;
    /** Radial extent of the shadow line (outside the dais slab skirt, inside the ring). */
    private static final int SHADOW_FROM = 7;
    private static final int SHADOW_TO = 10;
    /** Days per full dial revolution (the 14-day event arc). */
    private static final int DAYS_PER_REVOLUTION = 14;

    // --- C3 animation tuning ---
    /** A watcher this close (blocks, from the dial center) makes the wander worth playing. */
    private static final int ANIMATE_PLAYER_RANGE = 64;
    /** Per-placement puff + caption tick reach players within this many blocks. */
    private static final int FX_SOUND_RANGE = 24;
    /** One erase/place write every this many ticks (16 steps ≈ 30t total). */
    private static final int STEP_INTERVAL_TICKS = 2;
    /** Finale: how long the pointed-at ring marker flashes gilded. */
    private static final int MARKER_FLASH_TICKS = 15;
    /** Finale: 5 s beam column on the pointed-at marker. */
    private static final int BEAM_DURATION_TICKS = 100;
    /** One {@link BeamEmitter#emit} burst every this many ticks of the finale window. */
    private static final int BEAM_EMIT_INTERVAL_TICKS = 5;

    /** The running shadow wander; server thread only, at most one (newer flushes older). */
    private static Animation animation;

    private SundialPlaza() {}

    /** Called by {@code DayScheduler.setDay} after a day is applied. */
    public static void onDayChanged(MinecraftServer server, int previousDay, int newDay) {
        if (previousDay == newDay) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        BlockPos altarPos = state.getSanctumAltarPos();
        if (altarPos == null) {
            return;
        }
        ServerLevel overworld = server.overworld();
        // Catch-up bursts fire several day changes in one tick: a still-running wander
        // must land its end state before the next erase contract can hold.
        if (animation != null) {
            animation.finishInstantly();
            animation = null;
        }
        BlockPos center = new BlockPos(altarPos.getX(),
                altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND, altarPos.getZ());
        boolean watchable = overworld.isLoaded(center)
                && anyPlayerWithin(overworld, center, ANIMATE_PLAYER_RANGE);
        if (!watchable) {
            // INSTANT legacy path (boot-order law: never animate into unloaded chunks,
            // never for an audience of zero — server start / catch-up stays cheap).
            eraseShadow(overworld, altarPos, previousDay);
            placeShadow(overworld, altarPos, newDay);
            EclipseMod.LOGGER.info("Sundial shadow line moved: day {} -> {}", previousDay, newDay);
            EclipseMod.LOGGER.debug("[w6c-sundial] animated=false steps=0");
            return;
        }
        List<BlockPos> erase = new ArrayList<>(shadowLine(altarPos, previousDay)); // inner→outer
        List<BlockPos> place = new ArrayList<>(shadowLine(altarPos, newDay));
        Collections.reverse(place); // outer→inner: the new shadow sweeps INWARD to the dais
        animation = new Animation(overworld, altarPos, erase, place, newDay);
        EclipseMod.LOGGER.info("Sundial shadow line moved: day {} -> {}", previousDay, newDay);
        EclipseMod.LOGGER.debug("[w6c-sundial] animated=true steps={}", erase.size() + place.size());
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        Animation current = animation;
        if (current == null) {
            return;
        }
        if (current.level.getServer() != event.getServer()) {
            animation = null; // stale integrated-server leftover — never tick a dead level
            return;
        }
        if (current.advance()) {
            animation = null;
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        animation = null;
    }

    /** The 12 hour markers on the r=11 ring; north (towards −Z) is gilded. */
    static void buildDial(ServerLevel level, BlockPos altarPos) {
        int groundY = altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        for (int i = 0; i < 12; i++) {
            double angle = Math.toRadians(i * 30.0D);
            int x = altarPos.getX() + (int) Math.round(Math.sin(angle) * DIAL_RADIUS);
            int z = altarPos.getZ() - (int) Math.round(Math.cos(angle) * DIAL_RADIUS);
            level.setBlock(new BlockPos(x, groundY, z),
                    i == 0 ? Blocks.GILDED_BLACKSTONE.defaultBlockState()
                            : Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState(),
                    Block.UPDATE_ALL);
        }
    }

    /** Stamps the polished-basalt shadow line for {@code day}. */
    static void placeShadow(ServerLevel level, BlockPos altarPos, int day) {
        for (BlockPos pos : shadowLine(altarPos, day)) {
            level.setBlock(pos, Blocks.POLISHED_BASALT.defaultBlockState(), Block.UPDATE_ALL);
        }
    }

    /** Restores the deterministic ground mix under the previous day's line. */
    private static void eraseShadow(ServerLevel level, BlockPos altarPos, int day) {
        for (BlockPos pos : shadowLine(altarPos, day)) {
            level.setBlock(pos, AltarSanctumBuilder.groundMix(pos.getX(), pos.getZ()), Block.UPDATE_ALL);
        }
    }

    /** Ground positions of the shadow line for a day (day 1 = north, clockwise). */
    private static Set<BlockPos> shadowLine(BlockPos altarPos, int day) {
        int groundY = altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        double angle = Math.toRadians(Math.floorMod(day - 1, DAYS_PER_REVOLUTION)
                * (360.0D / DAYS_PER_REVOLUTION));
        Set<BlockPos> line = new LinkedHashSet<>();
        for (double d = SHADOW_FROM; d <= SHADOW_TO; d += 0.5D) {
            int x = altarPos.getX() + (int) Math.round(Math.sin(angle) * d);
            int z = altarPos.getZ() - (int) Math.round(Math.cos(angle) * d);
            line.add(new BlockPos(x, groundY, z));
        }
        return line;
    }

    /** The r=11 ring marker position closest to {@code day}'s shadow angle. */
    private static BlockPos markerFor(BlockPos altarPos, int day) {
        int groundY = altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        double angleDeg = Math.floorMod(day - 1, DAYS_PER_REVOLUTION)
                * (360.0D / DAYS_PER_REVOLUTION);
        double angle = Math.toRadians((Math.round(angleDeg / 30.0D) % 12) * 30.0D);
        int x = altarPos.getX() + (int) Math.round(Math.sin(angle) * DIAL_RADIUS);
        int z = altarPos.getZ() - (int) Math.round(Math.cos(angle) * DIAL_RADIUS);
        return new BlockPos(x, groundY, z);
    }

    private static boolean anyPlayerWithin(ServerLevel level, BlockPos center, int range) {
        double rangeSqr = (double) range * range;
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(center.getX() + 0.5D, center.getY() + 0.5D,
                    center.getZ() + 0.5D) <= rangeSqr) {
                return true;
            }
        }
        return false;
    }

    /**
     * One scheduled shadow wander: erase steps then place steps every
     * {@value #STEP_INTERVAL_TICKS}t, then the marker-flash/beam finale. All writes are the
     * exact Bestand block states ({@code groundMix} / polished basalt) — the animation only
     * spreads them over time, so flushing instantly is always byte-identical to the legacy
     * path.
     */
    private static final class Animation {
        final ServerLevel level;
        final List<BlockPos> erase;
        final List<BlockPos> place;
        final BlockPos marker;
        /** Canonical (self-healing) marker state — north stays gilded, the rest chiseled. */
        final BlockState markerRestore;
        int tick = -1;
        int step;
        boolean markerFlashed;

        Animation(ServerLevel level, BlockPos altarPos, List<BlockPos> erase,
                List<BlockPos> place, int newDay) {
            this.level = level;
            this.erase = erase;
            this.place = place;
            this.marker = markerFor(altarPos, newDay);
            BlockPos north = markerFor(altarPos, 1); // day 1 points north — the gilded marker
            this.markerRestore = marker.equals(north)
                    ? Blocks.GILDED_BLACKSTONE.defaultBlockState()
                    : Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState();
        }

        /** One server tick; returns {@code true} when the wander (incl. finale) is done. */
        boolean advance() {
            tick++;
            int totalSteps = erase.size() + place.size();
            if (step < totalSteps) {
                if (tick % STEP_INTERVAL_TICKS != 0) {
                    return false;
                }
                BlockPos pos = step < erase.size()
                        ? erase.get(step) : place.get(step - erase.size());
                if (!level.isLoaded(pos)) {
                    finishInstantly(); // watcher left, chunk dropped — no sync-loads for flavor
                    return true;
                }
                if (step < erase.size()) {
                    level.setBlock(pos, AltarSanctumBuilder.groundMix(pos.getX(), pos.getZ()),
                            Block.UPDATE_ALL);
                } else {
                    level.setBlock(pos, Blocks.POLISHED_BASALT.defaultBlockState(), Block.UPDATE_ALL);
                    placementFx(pos, step - erase.size());
                }
                step++;
                if (step == totalSteps) {
                    tick = -1; // finale window restarts the local clock
                }
                return false;
            }
            // Finale: gilded flash on the pointed-at marker + 5 s beam column (API only).
            if (tick == 0 && level.isLoaded(marker)) {
                level.setBlock(marker, Blocks.GILDED_BLACKSTONE.defaultBlockState(), Block.UPDATE_ALL);
                markerFlashed = true;
            }
            if (tick == MARKER_FLASH_TICKS) {
                restoreMarker();
            }
            if (tick % BEAM_EMIT_INTERVAL_TICKS == 0 && tick < BEAM_DURATION_TICKS) {
                BeamEmitter.emit(level, marker);
            }
            if (tick >= BEAM_DURATION_TICKS) {
                restoreMarker();
                return true;
            }
            return false;
        }

        /** Per-placement moment: basalt materialize puff + caption tick within 24 blocks. */
        private void placementFx(BlockPos pos, int placeIndex) {
            Vec3 fxPos = new Vec3(pos.getX() + 0.5D, pos.getY() + 1.0D, pos.getZ() + 0.5D);
            S2CQuasarPayload puff = new S2CQuasarPayload(
                    S2CQuasarPayload.MAP_EXPAND_MATERIALIZE, fxPos);
            double rangeSqr = (double) FX_SOUND_RANGE * FX_SOUND_RANGE;
            float pitch = 0.85F + 0.04F * placeIndex; // time audibly clicks forward
            for (ServerPlayer player : level.players()) {
                if (player.position().distanceToSqr(fxPos) > rangeSqr) {
                    continue;
                }
                PacketDistributor.sendToPlayer(player, puff);
                player.playNotifySound(EclipseSounds.UI_CAPTION_TICK.get(),
                        SoundSource.BLOCKS, 0.6F, pitch);
            }
        }

        /** Blind Bestand-style writes for everything not yet stepped; no FX, no finale. */
        void finishInstantly() {
            for (int i = step; i < erase.size() + place.size(); i++) {
                BlockPos pos = i < erase.size() ? erase.get(i) : place.get(i - erase.size());
                level.setBlock(pos, i < erase.size()
                        ? AltarSanctumBuilder.groundMix(pos.getX(), pos.getZ())
                        : Blocks.POLISHED_BASALT.defaultBlockState(), Block.UPDATE_ALL);
            }
            step = erase.size() + place.size();
            restoreMarker();
        }

        private void restoreMarker() {
            if (markerFlashed && level.isLoaded(marker)) {
                level.setBlock(marker, markerRestore, Block.UPDATE_ALL);
            }
            markerFlashed = false;
        }
    }
}
