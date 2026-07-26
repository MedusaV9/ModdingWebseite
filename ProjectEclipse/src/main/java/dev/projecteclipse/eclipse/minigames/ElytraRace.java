package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * The elytra ring race (game id {@code race}, dimension {@code eclipse:minigame_sky}):
 * a seeded FIGURE-EIGHT course of {@value #MIN_RINGS}–{@value #MAX_RINGS} floating
 * glass/light rings (~700-block lemniscate loop) with a lit crossover gate at the
 * center and floating debris hazards off the racing line, flown with a disposable
 * elytra + firework kit. Checkpoints are passed sequentially — detection is
 * SEGMENT-based (the path flown since the last sample is tested against the ring, so
 * full-boost racers cannot tunnel between two 0.5&nbsp;s samples); each racer privately
 * sees their next ring as an end-rod particle cluster. Passing the start ring arms the
 * lap timer and re-passing it after all checkpoints finishes the lap. First-to-finish
 * and new best times are announced ANONYMOUSLY (no names — the anonymity rules hold);
 * each racer privately sees their own time and position. Falling (or dying to the void
 * — cancelled upstream) teleports back to the last checkpoint with a short Slow
 * Falling grace so the elytra can be re-deployed.
 */
public final class ElytraRace {

    /** Deterministic course for one seed: ring centers/radii + all blocks + the start pad. */
    public record Course(List<Vec3> ringCenters, List<Integer> ringRadii,
            List<CourseBlocks.Placement> blocks, Vec3 startPad, float startYaw) {}

    static final int MIN_RINGS = 14;
    static final int MAX_RINGS = 18;
    /** Ring build radius spread (blocks) — every opening stays comfortably elytra-sized. */
    private static final int RING_RADIUS_MIN = 4;
    private static final int RING_RADIUS_MAX = 6;
    private static final int START_RING_RADIUS = 5;
    /** Detection margin added onto each ring's radius for the segment test. */
    private static final double DETECT_MARGIN = 1.75D;
    private static final int BASE_Y = 130;
    /** Below this the racer is rescued back to the last checkpoint (void is far lower). */
    private static final int FALL_RESCUE_Y = 70;
    private static final int FIREWORKS_PER_KIT = 64;
    private static final int FIREWORKS_PER_LAP = 32;
    /** Slow Falling grace after a checkpoint respawn (ticks) — time to re-open the elytra. */
    private static final int RESPAWN_SLOW_FALL_TICKS = 200;
    /** Max checkpoint advances per sample — one boosted segment can clip two rings. */
    private static final int MAX_HOPS_PER_SAMPLE = 3;

    /** Single-entry deterministic course cache (server thread only). */
    private static int cachedSeed = Integer.MIN_VALUE;
    private static Course cachedCourse;

    /**
     * Last sampled position per racer (transient, server thread only) — the anchor of
     * the flown segment tested against the next ring. Entries are dropped on teleports
     * (respawn/entry) so a warp is never mistaken for a flown path, and pruned to the
     * current racer set every tick.
     */
    private static final Map<UUID, Vec3> LAST_POS = new HashMap<>();

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

    /**
     * Figure-eight (Gerono lemniscate) parametrization: {@code x = A·cos t},
     * {@code z = Z·sin 2t}, {@code y = BASE_Y + H·sin t + 3·sin(3t + φ)}. The
     * {@code H·sin t} term guarantees the two passes over the central crossing
     * (t = π/2 and 3π/2) stay ≥ {@code 2H − 6} blocks apart vertically.
     */
    private record Shape(double halfLength, double crossAmp, double heightAmp, double wobblePhase) {
        Vec3 pointAt(double t) {
            return new Vec3(halfLength * Math.cos(t),
                    BASE_Y + heightAmp * Math.sin(t) + 3.0D * Math.sin(3.0D * t + wobblePhase),
                    crossAmp * Math.sin(2.0D * t));
        }

        /** Horizontal flight direction (unit, XZ only) — never degenerate on this curve. */
        Vec3 tangentAt(double t) {
            return new Vec3(-halfLength * Math.sin(t), 0.0D,
                    2.0D * crossAmp * Math.cos(2.0D * t)).normalize();
        }
    }

    private static Course generate(int seed) {
        RandomSource rand = RandomSource.create(seed * 31L + 101L);
        int ringCount = MIN_RINGS + rand.nextInt(MAX_RINGS - MIN_RINGS + 1);
        Shape shape = new Shape(
                95.0D + rand.nextInt(21),          // half-length A: 95–115
                50.0D + rand.nextInt(16),          // crossing amplitude Z: 50–65
                10.0D + rand.nextInt(7),           // height amplitude H: 10–16
                rand.nextDouble() * Math.PI * 2.0D);

        List<Vec3> centers = new ArrayList<>(ringCount);
        List<Integer> radii = new ArrayList<>(ringCount);
        for (int i = 0; i < ringCount; i++) {
            double t = (Math.PI * 2.0D * i) / ringCount;
            centers.add(shape.pointAt(t));
            radii.add(i == 0 ? START_RING_RADIUS
                    : RING_RADIUS_MIN + rand.nextInt(RING_RADIUS_MAX - RING_RADIUS_MIN + 1));
        }

        Map<BlockPos, BlockState> blocks = new LinkedHashMap<>();
        BlockState glass = Blocks.LIGHT_BLUE_STAINED_GLASS.defaultBlockState();
        BlockState light = Blocks.SEA_LANTERN.defaultBlockState();
        BlockState startLight = Blocks.GLOWSTONE.defaultBlockState();

        // Rings face the flight direction: plane spanned by up and the side normal.
        for (int i = 0; i < ringCount; i++) {
            double t = (Math.PI * 2.0D * i) / ringCount;
            Vec3 center = centers.get(i);
            int radius = radii.get(i);
            Vec3 tangent = shape.tangentAt(t);
            Vec3 up = new Vec3(0.0D, 1.0D, 0.0D);
            Vec3 side = new Vec3(-tangent.z, 0.0D, tangent.x);
            boolean startRing = i == 0;
            int steps = radius * 8;
            for (int step = 0; step < steps; step++) {
                double a = (Math.PI * 2.0D * step) / steps;
                Vec3 offset = up.scale(radius * Math.cos(a)).add(side.scale(radius * Math.sin(a)));
                BlockPos pos = BlockPos.containing(center.add(offset));
                BlockState state = startRing
                        ? (step % 2 == 0 ? startLight : glass)
                        : (step % 4 == 0 ? light : glass);
                blocks.putIfAbsent(pos, state);
            }
        }

        // Crossover gate: both lemniscate passes thread the (0, 0) column — two obsidian
        // pylons flank it so the crossing is flown as a 16-block-wide lit slot.
        BlockState obsidian = Blocks.OBSIDIAN.defaultBlockState();
        BlockState cryingObsidian = Blocks.CRYING_OBSIDIAN.defaultBlockState();
        int gateTop = BASE_Y + (int) shape.heightAmp() + 10;
        int gateBottom = BASE_Y - (int) shape.heightAmp() - 10;
        for (int sideSign = -1; sideSign <= 1; sideSign += 2) {
            for (int y = gateBottom; y <= gateTop; y++) {
                blocks.putIfAbsent(new BlockPos(0, y, sideSign * 8),
                        y % 4 == 0 ? cryingObsidian : obsidian);
            }
        }

        // Debris hazards: small blackstone/obsidian clumps floating 6–10 blocks off the
        // racing line between rings — corner-cutters graze them, the honest line is clear.
        // The launch straight (segment 0) and the finish approach stay clean.
        BlockState blackstone = Blocks.POLISHED_BLACKSTONE.defaultBlockState();
        BlockState glow = Blocks.SHROOMLIGHT.defaultBlockState();
        int blobIndex = 0;
        for (int i = 1; i < ringCount - 1; i++) {
            boolean skip = rand.nextInt(3) == 0;
            double tMid = (Math.PI * 2.0D * (i + 0.5D)) / ringCount;
            double offset = (6 + rand.nextInt(5)) * (rand.nextBoolean() ? 1 : -1);
            int lift = rand.nextInt(6) - 2;
            if (skip) {
                continue; // draws above stay in fixed order → determinism holds
            }
            Vec3 tangent = shape.tangentAt(tMid);
            Vec3 side = new Vec3(-tangent.z, 0.0D, tangent.x);
            Vec3 blobCenter = shape.pointAt(tMid).add(side.scale(offset)).add(0.0D, lift, 0.0D);
            BlockPos core = BlockPos.containing(blobCenter);
            boolean lit = blobIndex++ % 3 == 0;
            for (int dx = -1; dx <= 1; dx++) {
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dz = -1; dz <= 1; dz++) {
                        if (dx * dx + dy * dy + dz * dz > 2) {
                            continue;
                        }
                        boolean isCore = dx == 0 && dy == 0 && dz == 0;
                        BlockState state = isCore && lit ? glow
                                : (Math.floorMod(dx + dy + dz, 2) == 0 ? blackstone : obsidian);
                        blocks.putIfAbsent(core.offset(dx, dy, dz), state);
                    }
                }
            }
        }

        // Start pad: 9×9 glass floor a little behind and above the start ring. The
        // tangent at t = 0 is always (0, 0, 1) on this curve.
        Vec3 ring0 = centers.get(0);
        Vec3 tangent0 = shape.tangentAt(0.0D);
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
        return new Course(List.copyOf(centers), List.copyOf(radii), List.copyOf(placements),
                new Vec3(padFloor.getX() + 0.5D, padFloor.getY() + 1.0D, padFloor.getZ() + 0.5D),
                startYaw);
    }

    /** Course bounds for the close-time entity sweep (covers every possible seed). */
    public static AABB bounds() {
        return new AABB(-150, FALL_RESCUE_Y - 20, -150, 150, BASE_Y + 60, 150);
    }

    /** Clears transient per-racer segment anchors and the course cache (server stop/close). */
    static void resetTransient() {
        LAST_POS.clear();
        cachedCourse = null;
        cachedSeed = Integer.MIN_VALUE;
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
        LAST_POS.remove(player.getUUID()); // a warp is not a flown segment
        player.teleportTo(sky, course.startPad().x, course.startPad().y, course.startPad().z,
                course.startYaw(), 0.0F);
        player.fallDistance = 0.0F;
        state.setRaceProgress(player.getUUID(), 0);
        state.setRaceLapStart(player.getUUID(), 0L);
    }

    // ------------------------------------------------------------------ race tick

    /**
     * Per-service-tick race driver: SEGMENT-based sequential checkpoint detection (the
     * position delta since the last 0.5&nbsp;s sample is tested against the next ring, so
     * boosted racers cannot fly through a ring between samples), lap arming at the start
     * ring, finish handling (podium order, best-time records), fall rescue and the
     * private next-ring particle guidance.
     */
    public static void tick(MinecraftServer server, MinigameState state, List<ServerPlayer> racers) {
        Course course = courseFor(state.openCount());
        int ringCount = course.ringCenters().size();
        long now = System.currentTimeMillis();

        Set<UUID> present = new HashSet<>();
        for (ServerPlayer racer : racers) {
            present.add(racer.getUUID());
        }
        LAST_POS.keySet().retainAll(present);

        for (ServerPlayer racer : racers) {
            if (racer.isSpectator()) {
                continue;
            }
            if (racer.getY() < FALL_RESCUE_Y) {
                respawnAtCheckpoint(server, state, racer);
                racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.fell")
                        .withStyle(ChatFormatting.AQUA), true);
                continue;
            }
            UUID uuid = racer.getUUID();
            Vec3 current = racer.position();
            Vec3 previous = LAST_POS.put(uuid, current);
            if (previous == null) {
                previous = current;
            }

            for (int hop = 0; hop < MAX_HOPS_PER_SAMPLE; hop++) {
                int next = state.raceProgress(uuid);
                int ringIndex = next % ringCount;
                Vec3 target = course.ringCenters().get(ringIndex);
                double detect = course.ringRadii().get(ringIndex) + DETECT_MARGIN;
                if (distanceToSegment(target, previous, current) > detect) {
                    break;
                }
                if (next == 0) {
                    state.setRaceLapStart(uuid, now);
                    state.setRaceProgress(uuid, 1);
                    racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.lap_armed")
                            .withStyle(ChatFormatting.GREEN), true);
                    racer.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.7F, 1.8F);
                } else if (next >= ringCount) {
                    finishLap(server, state, racer, now);
                    break;
                } else {
                    state.setRaceProgress(uuid, next + 1);
                    racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.checkpoint",
                            next, ringCount).withStyle(ChatFormatting.AQUA), true);
                    racer.playNotifySound(SoundEvents.EXPERIENCE_ORB_PICKUP, SoundSource.PLAYERS, 0.8F, 1.4F);
                }
            }

            sendGuidance(racer, state, course);
        }
    }

    /** Shortest distance from {@code point} to the segment {@code a → b}. */
    private static double distanceToSegment(Vec3 point, Vec3 a, Vec3 b) {
        Vec3 ab = b.subtract(a);
        double lengthSq = ab.lengthSqr();
        if (lengthSq < 1.0E-6D) {
            return point.distanceTo(a);
        }
        double u = Mth.clamp(point.subtract(a).dot(ab) / lengthSq, 0.0D, 1.0D);
        return point.distanceTo(a.add(ab.scale(u)));
    }

    /**
     * Private next-ring beacon: an end-rod cluster only THIS racer sees (targeted
     * {@code sendParticles} overload, force-rendered past the 32-block cull) — soul
     * flames once the next pass is the finish ring.
     */
    private static void sendGuidance(ServerPlayer racer, MinigameState state, Course course) {
        int ringCount = course.ringCenters().size();
        int next = state.raceProgress(racer.getUUID());
        int ringIndex = next % ringCount;
        Vec3 target = course.ringCenters().get(ringIndex);
        double spread = course.ringRadii().get(ringIndex) * 0.5D;
        var particle = next >= ringCount ? ParticleTypes.SOUL_FIRE_FLAME : ParticleTypes.END_ROD;
        racer.serverLevel().sendParticles(racer, particle, true,
                target.x, target.y, target.z, 10, spread, spread, spread, 0.02D);
    }

    /** NEWFX-C3b: finish-ribbon cue broadcast radius around the start/finish ring. */
    private static final double FINISH_CUE_RANGE = 128.0D;

    private static void finishLap(MinecraftServer server, MinigameState state,
            ServerPlayer racer, long now) {
        UUID uuid = racer.getUUID();
        long lapStart = state.raceLapStart(uuid);
        long lapMillis = lapStart > 0L ? now - lapStart : 0L;
        boolean newBest = state.offerBestLap(lapMillis);
        int position = state.addRaceFinisher(uuid);

        // NEWFX-C3b: the finish ring flashes and sheds a checkered light-ribbon spiral
        // — position lane at the ring-0 center (the lap always closes there), a = podium
        // position (1 = the gold-burst variant; reducedFx clients only play position 1).
        // Anonymity holds: the ribbon marks the RING, not the racer.
        dev.projecteclipse.eclipse.network.fx.FxPayloads.sendFxEvent(racer.serverLevel(),
                dev.projecteclipse.eclipse.network.fx.FxCues.CUE_RACE_FINISH,
                courseFor(state.openCount()).ringCenters().get(0), position, 0.0F,
                FINISH_CUE_RANGE);

        racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.own_lap",
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
            // FFIX-B (FINAL-SAT-SOL H4): queue + claim-before-give by a stable
            // instance-scoped id — the finisher record and the payout ledger live in the
            // SAME SavedData, so a crash replay can never double-pay this position.
            MinigameState.PendingPayout payout = new MinigameState.PendingPayout(
                    "minigame:race:" + state.openCount() + ":finish:" + position, shards, xp);
            state.queuePayout(uuid, payout);
            if (MinigameService.grantPayout(state, racer, payout)) {
                racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.finish_position",
                        position, shards, xp).withStyle(ChatFormatting.GOLD), false);
            }
        }

        // Roll straight into the next lap: timer re-arms, fireworks top up.
        state.setRaceLapStart(uuid, now);
        state.setRaceProgress(uuid, 1);
        racer.getInventory().add(new ItemStack(Items.FIREWORK_ROCKET, FIREWORKS_PER_LAP));
        racer.inventoryMenu.broadcastChanges();
        EclipseMod.LOGGER.info("Race lap finished by {} in {} (position {}, best={})",
                racer.getScoreboardName(), lapTime(lapMillis), position, newBest);
    }

    /**
     * Teleports a fallen/slain racer to their last passed checkpoint (or the start pad)
     * with a Slow Falling grace — a mid-air respawn without it just plummeted straight
     * back below the rescue line before the elytra could re-open.
     */
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
        LAST_POS.remove(racer.getUUID()); // a warp is not a flown segment
        racer.teleportTo(sky, spot.x, spot.y, spot.z, yaw, 0.0F);
        racer.setDeltaMovement(Vec3.ZERO);
        racer.fallDistance = 0.0F;
        racer.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                RESPAWN_SLOW_FALL_TICKS, 0, false, false, true));
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
        // LANGAUDIT: bake per recipient so the mod locale (not the vanilla client
        // language) decides the line; ServerLang.resolve passes unknown keys through.
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.sendSystemMessage(ServerLang.resolve(online, message));
        }
    }
}
