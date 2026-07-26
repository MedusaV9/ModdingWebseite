package dev.projecteclipse.eclipse.scare;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsDimension;
import dev.projecteclipse.eclipse.backrooms.BackroomsMaze;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * F-065 — the {@code /dev backroomsscare} trip machine. The GhostScreen arc
 * ({@code ScareIds.BACKROOMS_CLIP}) plays on the target's client and ends in a sustained
 * blackout; this service teleports the player into the EXISTING {@code eclipse:backrooms}
 * dimension under that blackout (the maze is generated terrain — no event needs to run,
 * see {@code BackroomsEventService}'s "the maze is TERRAIN now" decree), holds them there
 * for {@value #TRIP_MIN_SECONDS}–{@value #TRIP_MAX_SECONDS} s and pulls them back to
 * their recorded spot with a glitch cover ({@code ScareIds.BACKROOMS_RETURN}).
 *
 * <ul>
 *   <li><b>Cannot die</b>: {@link LivingIncomingDamageEvent} at HIGHEST priority — ANY
 *       damage while inside is cancelled and answers with the glitch burst + the instant
 *       return teleport (the trip's whole threat model is "it spits you back out").</li>
 *   <li><b>Relog/stop robust</b>: trips persist in {@link ScareTripState} (wall-clock
 *       schedule). A PENDING trip whose owner relogs is dropped (the clip never finished
 *       on their screen); an INSIDE trip is resolved at login by teleporting the player
 *       back to the stored anchor — this login handler runs at LOWEST priority so it
 *       lands AFTER {@code BackroomsEventService}'s own login exit (which would otherwise
 *       park a backrooms occupant at the sanctum altar) and our anchor wins.</li>
 *   <li><b>No event coupling</b>: nothing here touches {@code BackroomsState} — no
 *       participation, no lockouts, no rewards, no bossbar. If a real backrooms event is
 *       OPEN at the same time the trip victim simply shares the maze with it.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ScareTripService {
    /**
     * Millis between the clip cue and the teleport — MUST match the client script: the
     * {@code backrooms_clip} blackout is fully opaque from tick 168 on
     * ({@code ScareScripts.CLIP_BLACKOUT_TICK}); 170 ticks × 50 ms keeps the hop covered.
     */
    public static final long CLIP_TELEPORT_DELAY_MILLIS = 170L * 50L;
    public static final int TRIP_MIN_SECONDS = 20;
    public static final int TRIP_MAX_SECONDS = 30;

    private ScareTripService() {}

    // ================================================================== begin

    /**
     * Starts a trip for {@code target}. @return {@code null} on success, otherwise the
     * translated refusal message (the {@code BackroomsEventService} result convention).
     */
    @Nullable
    public static Component begin(MinecraftServer server, ServerPlayer target) {
        ServerLevel backrooms = server.getLevel(BackroomsDimension.BACKROOMS);
        if (backrooms == null) {
            return Component.translatable("dev.eclipse.scare.backrooms.no_level",
                    BackroomsDimension.BACKROOMS.location().toString());
        }
        if (BackroomsDimension.isInBackrooms(target)) {
            return Component.translatable("dev.eclipse.scare.backrooms.inside");
        }
        ScareTripState state = ScareTripState.get(server);
        if (state.trip(target.getUUID()) != null) {
            return Component.translatable("dev.eclipse.scare.backrooms.already");
        }

        long seed = ThreadLocalRandom.current().nextLong();
        long now = System.currentTimeMillis();
        long teleportAt = now + CLIP_TELEPORT_DELAY_MILLIS;
        long durationMillis = (TRIP_MIN_SECONDS
                + Math.floorMod(seed, TRIP_MAX_SECONDS - TRIP_MIN_SECONDS + 1L)) * 1000L;
        state.put(target.getUUID(), new ScareTripState.Trip(
                ScareTripState.Phase.PENDING, target.level().dimension(),
                target.getX(), target.getY(), target.getZ(), target.getYRot(), target.getXRot(),
                teleportAt, teleportAt + durationMillis, seed));

        ScareService.send(target, ScareIds.BACKROOMS_CLIP, seed);
        EclipseMod.LOGGER.info("Backrooms scare trip armed for {}: clip {} ms, stay {} s",
                target.getScoreboardName(), CLIP_TELEPORT_DELAY_MILLIS, durationMillis / 1000L);
        return null;
    }

    // ================================================================== tick

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % 10 != 0) {
            return;
        }
        ScareTripState state = ScareTripState.get(server);
        Map<UUID, ScareTripState.Trip> snapshot = state.snapshot();
        if (snapshot.isEmpty()) {
            return;
        }
        long now = System.currentTimeMillis();
        for (Map.Entry<UUID, ScareTripState.Trip> entry : snapshot.entrySet()) {
            UUID uuid = entry.getKey();
            ScareTripState.Trip trip = entry.getValue();
            ServerPlayer player = server.getPlayerList().getPlayer(uuid);
            switch (trip.phase()) {
                case PENDING -> {
                    if (now < trip.teleportAtEpochMillis()) {
                        continue;
                    }
                    if (player == null) {
                        // Logged out mid-clip: the trip never happened.
                        state.remove(uuid);
                        continue;
                    }
                    clipIn(server, state, player, trip);
                }
                case INSIDE -> {
                    if (player == null) {
                        continue; // offline: resolved by the login cleanup
                    }
                    if (!BackroomsDimension.isInBackrooms(player)) {
                        // Something else already pulled them out (protected death exit,
                        // /backroomsleave, operator tp) — the trip just ends quietly.
                        state.remove(uuid);
                        continue;
                    }
                    if (now >= trip.endsAtEpochMillis()) {
                        returnPlayer(server, state, player, trip, "time up");
                    }
                }
            }
        }
    }

    /** PENDING → INSIDE: the hop under the clip blackout, onto the maze spawn cross. */
    private static void clipIn(MinecraftServer server, ScareTripState state,
            ServerPlayer player, ScareTripState.Trip trip) {
        ServerLevel backrooms = server.getLevel(BackroomsDimension.BACKROOMS);
        if (backrooms == null) {
            state.remove(player.getUUID());
            return;
        }
        BlockPos spawn = BackroomsMaze.cellCenter(BackroomsMaze.SPAWN_CELL, BackroomsMaze.SPAWN_CELL);
        player.teleportTo(backrooms, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                player.getYRot(), 0.0F);
        player.fallDistance = 0.0F;
        state.put(player.getUUID(), trip.withPhase(ScareTripState.Phase.INSIDE));
        // Arrival sting: the blackout on the client releases into the yellow rooms.
        ScareService.send(player, ScareIds.BACKROOMS_ARRIVE, trip.seed());
        EclipseMod.LOGGER.info("{} clipped into the backrooms (scare trip, {} s remaining)",
                player.getScoreboardName(),
                Math.max(0L, trip.endsAtEpochMillis() - System.currentTimeMillis()) / 1000L);
    }

    /** INSIDE → gone: glitch cover + teleport back to the recorded anchor. */
    private static void returnPlayer(MinecraftServer server, ScareTripState state,
            ServerPlayer player, ScareTripState.Trip trip, String reason) {
        ScareService.send(player, ScareIds.BACKROOMS_RETURN, trip.seed());
        ServerLevel target = server.getLevel(trip.dimension());
        if (target != null) {
            player.teleportTo(target, trip.x(), trip.y(), trip.z(), trip.yaw(), trip.pitch());
        } else {
            ServerLevel overworld = server.overworld();
            BlockPos spawn = overworld.getSharedSpawnPos();
            player.teleportTo(overworld, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                    overworld.getSharedSpawnAngle(), 0.0F);
        }
        player.fallDistance = 0.0F;
        state.remove(player.getUUID());
        EclipseMod.LOGGER.info("{} returned from the backrooms scare trip ({})",
                player.getScoreboardName(), reason);
    }

    // ================================================================== damage guard

    /**
     * The trip's death-proofing: ANY incoming damage while INSIDE cancels and bounces the
     * player home. HIGHEST priority so it wins before the lives pipeline (and before
     * {@code BackroomsEventService}'s protected-death handler could ever be needed).
     */
    @SubscribeEvent(priority = EventPriority.HIGHEST)
    public static void onLivingIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !BackroomsDimension.isInBackrooms(player)) {
            return;
        }
        MinecraftServer server = player.server;
        ScareTripState state = ScareTripState.get(server);
        ScareTripState.Trip trip = state.trip(player.getUUID());
        if (trip == null || trip.phase() != ScareTripState.Phase.INSIDE) {
            return;
        }
        event.setCanceled(true);
        player.setRemainingFireTicks(0);
        player.fallDistance = 0.0F;
        returnPlayer(server, state, player, trip,
                "damage bounce (" + event.getSource().getMsgId() + ")");
    }

    // ================================================================== login cleanup

    /**
     * LOWEST priority: runs AFTER {@code BackroomsEventService.onPlayerLoggedIn} (which
     * evicts any backrooms occupant to the sanctum altar while no event is OPEN), so the
     * trip's own anchor is the final word for INSIDE trips.
     */
    @SubscribeEvent(priority = EventPriority.LOWEST)
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        MinecraftServer server = player.server;
        ScareTripState state = ScareTripState.get(server);
        ScareTripState.Trip trip = state.trip(player.getUUID());
        if (trip == null) {
            return;
        }
        switch (trip.phase()) {
            // The clip never finished on their screen — drop the trip instead of
            // teleporting someone into the backrooms minutes/days later without cover.
            case PENDING -> state.remove(player.getUUID());
            case INSIDE -> returnPlayer(server, state, player, trip, "login cleanup");
        }
    }
}
