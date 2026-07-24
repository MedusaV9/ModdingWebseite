package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * The elytra ring race (game id {@code race}, dimension {@code eclipse:minigame_sky}):
 * a seeded looping course of {@value #MIN_RINGS}–{@value #MAX_RINGS} floating glass/light
 * rings (~600-block loop), flown with a disposable elytra + firework kit. Checkpoints are
 * passed sequentially (within {@value #DETECT_RADIUS} blocks of a ring center); passing
 * the start ring arms the lap timer and re-passing it after all checkpoints finishes the
 * lap. First-to-finish and new best times are announced ANONYMOUSLY (no names — the
 * anonymity rules hold); each racer privately sees their own time and position. Falling
 * (or dying to the void — cancelled upstream) teleports back to the last checkpoint.
 */
public final class ElytraRace {

    /** Deterministic course for one seed: ring centers + all blocks + the start pad. */
    public record Course(List<Vec3> ringCenters, List<CourseBlocks.Placement> blocks,
            Vec3 startPad, float startYaw) {}

    static final int MIN_RINGS = 12;
    static final int MAX_RINGS = 16;
    /** Ring build radius (blocks) — the opening is comfortably elytra-sized. */
    private static final int RING_RADIUS = 5;
    /** Checkpoint trigger distance from the ring center. */
    private static final double DETECT_RADIUS = 6.5D;
    private static final int BASE_Y = 130;
    /** Below this the racer is rescued back to the last checkpoint (void is far lower). */
    private static final int FALL_RESCUE_Y = 70;
    private static final int FIREWORKS_PER_KIT = 64;
    private static final int FIREWORKS_PER_LAP = 32;

    /** Single-entry deterministic course cache (server thread only). */
    private static int cachedSeed = Integer.MIN_VALUE;
    private static Course cachedCourse;

    private ElytraRace() {}

    // ------------------------------------------------------------------ course generation

    /** Deterministic course for {@code seed} (cached; layouts vary per open). */
    public static Course courseFor(int seed) {
        if (cachedCourse == null || cachedSeed != seed) {
            cachedCourse = generate(seed);
            cachedSeed = seed;
        }
        return cachedCourse;
    }

    private static Course generate(int seed) {
        RandomSource rand = RandomSource.create(seed * 31L + 101L);
        int ringCount = MIN_RINGS + rand.nextInt(MAX_RINGS - MIN_RINGS + 1);
        double loopRadius = 90.0D + rand.nextInt(21); // 2πR ≈ 565–695 blocks of spline
        double radialPhase = rand.nextDouble() * Math.PI * 2.0D;
        double heightPhase = rand.nextDouble() * Math.PI * 2.0D;
        double radialAmp = 10.0D + rand.nextInt(8);
        double heightAmp = 12.0D + rand.nextInt(8);

        List<Vec3> centers = new ArrayList<>(ringCount);
        for (int i = 0; i < ringCount; i++) {
            double theta = (Math.PI * 2.0D * i) / ringCount;
            double radius = loopRadius + radialAmp * Math.sin(2.0D * theta + radialPhase);
            double y = BASE_Y + heightAmp * Math.sin(3.0D * theta + heightPhase);
            centers.add(new Vec3(Math.cos(theta) * radius, y, Math.sin(theta) * radius));
        }

        // Rings face the flight direction: plane spanned by up and the radial direction.
        Map<BlockPos, BlockState> blocks = new LinkedHashMap<>();
        BlockState glass = Blocks.LIGHT_BLUE_STAINED_GLASS.defaultBlockState();
        BlockState light = Blocks.SEA_LANTERN.defaultBlockState();
        BlockState startLight = Blocks.GLOWSTONE.defaultBlockState();
        for (int i = 0; i < ringCount; i++) {
            double theta = (Math.PI * 2.0D * i) / ringCount;
            Vec3 center = centers.get(i);
            Vec3 up = new Vec3(0.0D, 1.0D, 0.0D);
            Vec3 radial = new Vec3(Math.cos(theta), 0.0D, Math.sin(theta));
            boolean startRing = i == 0;
            int steps = 32;
            for (int step = 0; step < steps; step++) {
                double a = (Math.PI * 2.0D * step) / steps;
                Vec3 offset = up.scale(RING_RADIUS * Math.cos(a))
                        .add(radial.scale(RING_RADIUS * Math.sin(a)));
                BlockPos pos = BlockPos.containing(center.add(offset));
                BlockState state = startRing
                        ? (step % 2 == 0 ? startLight : glass)
                        : (step % 4 == 0 ? light : glass);
                blocks.putIfAbsent(pos, state);
            }
        }

        // Start pad: 9×9 glass floor a little behind and above the start ring.
        Vec3 ring0 = centers.get(0);
        Vec3 tangent0 = new Vec3(-Math.sin(0.0D), 0.0D, Math.cos(0.0D)); // theta = 0 → (0,0,1)
        Vec3 pad = ring0.subtract(tangent0.scale(16.0D)).add(0.0D, 4.0D, 0.0D);
        BlockPos padFloor = BlockPos.containing(pad).below();
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                blocks.putIfAbsent(padFloor.offset(dx, 0, dz),
                        Blocks.WHITE_STAINED_GLASS.defaultBlockState());
            }
        }
        float startYaw = (float) Math.toDegrees(Math.atan2(-tangent0.x, tangent0.z));

        List<CourseBlocks.Placement> placements = new ArrayList<>(blocks.size());
        blocks.forEach((pos, state) -> placements.add(new CourseBlocks.Placement(pos, state)));
        EclipseMod.LOGGER.info("Elytra race course generated for seed {}: {} rings, {} blocks",
                seed, ringCount, placements.size());
        return new Course(List.copyOf(centers), List.copyOf(placements),
                new Vec3(padFloor.getX() + 0.5D, padFloor.getY() + 1.0D, padFloor.getZ() + 0.5D),
                startYaw);
    }

    /** Course bounds for the close-time entity sweep (covers every possible seed). */
    public static AABB bounds() {
        return new AABB(-150, FALL_RESCUE_Y - 20, -150, 150, BASE_Y + 60, 150);
    }

    // ------------------------------------------------------------------ kit & spawn

    /** Disposable race kit — vanishes on exit via the ticket restore. */
    public static void giveKit(ServerPlayer player) {
        player.setItemSlot(EquipmentSlot.CHEST, new ItemStack(Items.ELYTRA));
        player.getInventory().add(new ItemStack(Items.FIREWORK_ROCKET, FIREWORKS_PER_KIT));
        player.inventoryMenu.broadcastChanges();
    }

    /** Teleports the player onto the start pad, facing the start ring. */
    public static void placeIntoRace(ServerLevel sky, MinigameState state, ServerPlayer player) {
        Course course = courseFor(state.openCount());
        player.teleportTo(sky, course.startPad().x, course.startPad().y, course.startPad().z,
                course.startYaw(), 0.0F);
        player.fallDistance = 0.0F;
        state.setRaceProgress(player.getUUID(), 0);
        state.setRaceLapStart(player.getUUID(), 0L);
    }

    // ------------------------------------------------------------------ race tick

    /**
     * Per-service-tick race driver: sequential checkpoint detection, lap arming at the
     * start ring, finish handling (podium order, best-time records) and fall rescue.
     */
    public static void tick(MinecraftServer server, MinigameState state, List<ServerPlayer> racers) {
        Course course = courseFor(state.openCount());
        int ringCount = course.ringCenters().size();
        long now = System.currentTimeMillis();
        for (ServerPlayer racer : racers) {
            if (racer.isSpectator()) {
                continue;
            }
            if (racer.getY() < FALL_RESCUE_Y) {
                respawnAtCheckpoint(server, state, racer);
                racer.displayClientMessage(Component.translatable("eclipse.minigame.race.fell")
                        .withStyle(ChatFormatting.AQUA), true);
                continue;
            }
            UUID uuid = racer.getUUID();
            int next = state.raceProgress(uuid);
            Vec3 target = course.ringCenters().get(next % ringCount);
            if (racer.position().distanceTo(target) > DETECT_RADIUS) {
                continue;
            }
            if (next == 0) {
                state.setRaceLapStart(uuid, now);
                state.setRaceProgress(uuid, 1);
                racer.displayClientMessage(Component.translatable("eclipse.minigame.race.lap_armed")
                        .withStyle(ChatFormatting.GREEN), true);
                racer.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.7F, 1.8F);
            } else if (next >= ringCount) {
                finishLap(server, state, racer, now);
            } else {
                state.setRaceProgress(uuid, next + 1);
                racer.displayClientMessage(Component.translatable("eclipse.minigame.race.checkpoint",
                        next, ringCount).withStyle(ChatFormatting.AQUA), true);
                racer.playNotifySound(SoundEvents.EXPERIENCE_ORB_PICKUP, SoundSource.PLAYERS, 0.8F, 1.4F);
            }
        }
    }

    private static void finishLap(MinecraftServer server, MinigameState state,
            ServerPlayer racer, long now) {
        UUID uuid = racer.getUUID();
        long lapStart = state.raceLapStart(uuid);
        long lapMillis = lapStart > 0L ? now - lapStart : 0L;
        boolean newBest = state.offerBestLap(lapMillis);
        int position = state.addRaceFinisher(uuid);

        racer.displayClientMessage(Component.translatable("eclipse.minigame.race.own_lap",
                lapTime(lapMillis)).withStyle(ChatFormatting.GOLD), false);
        racer.playNotifySound(SoundEvents.UI_TOAST_CHALLENGE_COMPLETE, SoundSource.PLAYERS, 0.8F, 1.0F);

        // Anonymity rule: broadcasts carry times only, never names.
        if (position == 1) {
            broadcast(server, Component.translatable("eclipse.minigame.race.first_finish",
                    lapTime(lapMillis)).withStyle(ChatFormatting.GOLD));
        } else if (newBest) {
            broadcast(server, Component.translatable("eclipse.minigame.race.best_time",
                    lapTime(lapMillis)).withStyle(ChatFormatting.YELLOW));
        }

        if (position >= 1 && position <= 3) {
            MinigameConfig.Values config = MinigameConfig.get();
            int shards = config.podiumShards().get(position - 1);
            int xp = config.podiumSkillXp().get(position - 1);
            if (shards > 0) {
                ShardEconomy.addShards(racer, shards);
            }
            if (xp > 0) {
                SkillsApi.addXp(racer, "minigame", xp);
            }
            racer.displayClientMessage(Component.translatable("eclipse.minigame.race.finish_position",
                    position, shards, xp).withStyle(ChatFormatting.GOLD), false);
        }

        // Roll straight into the next lap: timer re-arms, fireworks top up.
        state.setRaceLapStart(uuid, now);
        state.setRaceProgress(uuid, 1);
        racer.getInventory().add(new ItemStack(Items.FIREWORK_ROCKET, FIREWORKS_PER_LAP));
        racer.inventoryMenu.broadcastChanges();
        EclipseMod.LOGGER.info("Race lap finished by {} in {} (position {}, best={})",
                racer.getScoreboardName(), lapTime(lapMillis), position, newBest);
    }

    /** Teleports a fallen/slain racer to their last passed checkpoint (or the start pad). */
    public static void respawnAtCheckpoint(MinecraftServer server, MinigameState state,
            ServerPlayer racer) {
        ServerLevel sky = server.getLevel(MinigameDimensions.SKY);
        if (sky == null) {
            return;
        }
        Course course = courseFor(state.openCount());
        int next = state.raceProgress(racer.getUUID());
        Vec3 spot;
        float yaw;
        if (next <= 0) {
            spot = course.startPad();
            yaw = course.startYaw();
        } else {
            int lastRing = (next - 1) % course.ringCenters().size();
            spot = course.ringCenters().get(lastRing);
            // Face the next ring so the racer can re-deploy straight away.
            Vec3 toNext = course.ringCenters().get(next % course.ringCenters().size()).subtract(spot);
            yaw = (float) Math.toDegrees(Math.atan2(-toNext.x, toNext.z));
        }
        racer.teleportTo(sky, spot.x, spot.y, spot.z, yaw, 0.0F);
        racer.fallDistance = 0.0F;
    }

    /** Close-time summary: the anonymized best lap of the instance, if any lap completed. */
    public static void announceClosingSummary(MinecraftServer server, MinigameState state) {
        if (state.bestLapMillis() > 0L) {
            broadcast(server, Component.translatable("eclipse.minigame.race.closing_best",
                    state.raceFinishersSnapshot().size(), lapTime(state.bestLapMillis()))
                    .withStyle(ChatFormatting.GOLD));
        }
    }

    /** {@code 01:23.456} lap-time formatting. */
    public static String lapTime(long millis) {
        long clamped = Math.max(0L, millis);
        return String.format(Locale.ROOT, "%02d:%02d.%03d",
                clamped / 60_000L, (clamped / 1000L) % 60L, clamped % 1000L);
    }

    private static void broadcast(MinecraftServer server, Component message) {
        server.getPlayerList().broadcastSystemMessage(message, false);
    }
}
