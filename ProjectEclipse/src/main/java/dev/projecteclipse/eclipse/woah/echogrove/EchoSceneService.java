package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * WOAH-05 scene player (plan §3.4) — owns every live echo actor. One
 * {@code ServerTickEvent.Post} subscriber with a cheap gate (grove placed AND a
 * player within {@value #GATE_DIST} of the center — one distance check per player
 * per tick); per scene a {@link SceneInstance} with the 64/72 materialize/release
 * hysteresis. Released scenes FREEZE (cursor back to the loop start — nobody can
 * tell, and it saves bookkeeping).
 *
 * <p>One-shot replays ({@link #playOnce}) clone a scene next to the player with a
 * glow boost, run a single loop and fade out; max one per player (a second click
 * aborts the first). The finale flips all loop instances into GATHER mode
 * (generated star-shaped walk-to-the-tree paths, then an idle ring with
 * occasional waves — plan §7.3).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoSceneService {
    private static final double GATE_DIST = 96.0D;
    private static final double MATERIALIZE_DIST = 64.0D;
    private static final double RELEASE_DIST = 72.0D;
    /** Hard-discard everything after this many gate-closed ticks (chunks unload anyway). */
    private static final int GATE_CLOSED_DISCARD_TICKS = 200;
    /** Re-swing cadence while a SWING/THROW keyframe holds. */
    private static final int SWING_REPEAT_TICKS = 30;
    private static final float ONE_SHOT_OFFSET = 4.0F;
    private static final double GATHER_RING_RADIUS = 4.5D;
    private static final double GATHER_WALK_PER_TICK = 0.085D;
    private static final double GATHER_RUN_PER_TICK = 0.16D;

    private static final Map<String, SceneInstance> LOOPS = new LinkedHashMap<>();
    private static final List<SceneInstance> ONE_SHOTS = new ArrayList<>();
    private static final Map<UUID, SceneInstance> ONE_SHOT_BY_PLAYER = new HashMap<>();
    private static int gateClosedTicks;
    private static boolean gathering;
    private static float floodGlow;

    private EchoSceneService() {}

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        ServerLevel level = event.getServer().overworld();
        EchoGroveState state = EchoGroveState.get(event.getServer());
        if (!state.placed() || state.treeCenter() == null) {
            return;
        }
        BlockPos tree = state.treeCenter();
        Vec3 center = Vec3.atCenterOf(tree);
        boolean gateOpen = false;
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(center) <= GATE_DIST * GATE_DIST) {
                gateOpen = true;
                break;
            }
        }
        if (!gateOpen) {
            if (!LOOPS.isEmpty() || !ONE_SHOTS.isEmpty()) {
                if (++gateClosedTicks > GATE_CLOSED_DISCARD_TICKS) {
                    discardAll();
                }
            }
            return;
        }
        gateClosedTicks = 0;
        ensureInstances(level, tree);
        for (SceneInstance instance : LOOPS.values()) {
            instance.tick(level);
        }
        Iterator<SceneInstance> it = ONE_SHOTS.iterator();
        while (it.hasNext()) {
            SceneInstance oneShot = it.next();
            oneShot.tick(level);
            if (oneShot.finished()) {
                oneShot.discard();
                it.remove();
                if (oneShot.owner != null) {
                    ONE_SHOT_BY_PLAYER.remove(oneShot.owner, oneShot);
                }
            }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        LOOPS.clear();
        ONE_SHOTS.clear();
        ONE_SHOT_BY_PLAYER.clear();
        gateClosedTicks = 0;
        gathering = false;
        floodGlow = 0.0F;
    }

    private static void ensureInstances(ServerLevel level, BlockPos tree) {
        if (!LOOPS.isEmpty()) {
            return;
        }
        // Scene anchors are grove-center-relative; the tree stands at the bowl center.
        BlockPos groveCenter = tree.above(EchoGroveLayout.BOWL_DEPTH);
        for (String id : EchoScenes.SCENE_ORDER) {
            EchoScenes.Scene scene = EchoScenes.scene(id);
            if (scene == null) {
                continue;
            }
            Vec3 anchor = groundAnchor(level,
                    groveCenter.getX() + scene.dx(), groveCenter.getZ() + scene.dz());
            LOOPS.put(id, new SceneInstance(scene, anchor, false, 0.0F, null));
        }
        EclipseMod.LOGGER.debug("EchoSceneService: {} scene instance(s) ready", LOOPS.size());
    }

    private static Vec3 groundAnchor(ServerLevel level, int x, int z) {
        BlockPos top = level.getHeightmapPos(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                new BlockPos(x, 0, z));
        return new Vec3(x + 0.5D, top.getY(), z + 0.5D);
    }

    // ------------------------------------------------------------------ public API

    /**
     * One amplified replay next to {@code player} (plan §3.4): a scene clone ~4
     * blocks ahead, one loop, glow-boosted, fade-in/out, then gone. A second
     * request per player aborts the first (hard discard — the new scene replaces it).
     */
    public static void playOnce(ServerLevel level, String sceneId, ServerPlayer player, float glow) {
        EchoScenes.Scene scene = EchoScenes.scene(sceneId);
        if (scene == null) {
            return;
        }
        SceneInstance previous = ONE_SHOT_BY_PLAYER.remove(player.getUUID());
        if (previous != null) {
            previous.discard();
            ONE_SHOTS.remove(previous);
        }
        float yawRad = player.getYRot() * Mth.DEG_TO_RAD;
        int x = Mth.floor(player.getX() - Mth.sin(yawRad) * ONE_SHOT_OFFSET);
        int z = Mth.floor(player.getZ() + Mth.cos(yawRad) * ONE_SHOT_OFFSET);
        SceneInstance instance = new SceneInstance(scene,
                groundAnchor(level, x, z), true, glow, player.getUUID());
        instance.materialize(level);
        ONE_SHOTS.add(instance);
        ONE_SHOT_BY_PLAYER.put(player.getUUID(), instance);
    }

    /** Flood/finale brightness boost for every live actor (plan §3.5 t0–t160). */
    public static void setGlowAll(float glow) {
        floodGlow = Mth.clamp(glow, 0.0F, 1.0F);
        for (SceneInstance instance : LOOPS.values()) {
            instance.applyGlow();
        }
        for (SceneInstance instance : ONE_SHOTS) {
            instance.applyGlow();
        }
    }

    /** Finale: all loop scenes walk their actors to a ring around the tree (plan §7.3). */
    public static void startGather(ServerLevel level, BlockPos tree) {
        gathering = true;
        ensureInstances(level, tree);
        Vec3 treeCenter = new Vec3(tree.getX() + 0.5D, tree.getY() + 1.0D, tree.getZ() + 0.5D);
        int slot = 0;
        int totalActors = 0;
        for (SceneInstance instance : LOOPS.values()) {
            totalActors += instance.scene.actors().size();
        }
        for (SceneInstance instance : LOOPS.values()) {
            instance.materialize(level);
            instance.gatherCenter = treeCenter;
            for (EchoScenes.Actor actor : instance.scene.actors()) {
                double angle = (slot / (double) Math.max(1, totalActors)) * Math.PI * 2.0D;
                instance.gatherTargets.put(actor.role(), treeCenter.add(
                        Math.cos(angle) * GATHER_RING_RADIUS, 0.0D,
                        Math.sin(angle) * GATHER_RING_RADIUS));
                slot++;
            }
        }
    }

    /** Finale over: scenes return to their loops. */
    public static void endGather() {
        gathering = false;
        for (SceneInstance instance : LOOPS.values()) {
            instance.gatherTargets.clear();
        }
    }

    /** Dev reset: everything down (loops rebuild lazily on the next gated tick). */
    public static void discardAll() {
        for (SceneInstance instance : LOOPS.values()) {
            instance.discard();
        }
        LOOPS.clear();
        for (SceneInstance instance : ONE_SHOTS) {
            instance.discard();
        }
        ONE_SHOTS.clear();
        ONE_SHOT_BY_PLAYER.clear();
        gathering = false;
        gateClosedTicks = 0;
    }

    /** Live actor count ({@code /dev woah echo status}). */
    public static int actorCount() {
        int count = 0;
        for (SceneInstance instance : LOOPS.values()) {
            count += instance.actors.size();
        }
        for (SceneInstance instance : ONE_SHOTS) {
            count += instance.actors.size();
        }
        return count;
    }

    public static int loopInstanceCount() {
        return LOOPS.size();
    }

    public static int oneShotCount() {
        return ONE_SHOTS.size();
    }

    // ------------------------------------------------------------------ instance

    private static final class SceneInstance {
        final EchoScenes.Scene scene;
        final Vec3 anchor;
        final boolean oneShot;
        final float glowBoost;
        @Nullable
        final UUID owner;
        final Map<String, Mob> actors = new HashMap<>();
        final Map<String, Vec3> gatherTargets = new HashMap<>();
        @Nullable
        Vec3 gatherCenter;
        final Map<String, Integer> lastSwing = new HashMap<>();
        final List<Display.BlockDisplay> props = new ArrayList<>();
        int cursor;
        int age;
        boolean active;
        /** −1 = not fading; otherwise counts down to discard/freeze. */
        int fadeOut = -1;
        boolean done;

        SceneInstance(EchoScenes.Scene scene, Vec3 anchor, boolean oneShot, float glowBoost,
                @Nullable UUID owner) {
            this.scene = scene;
            this.anchor = anchor;
            this.oneShot = oneShot;
            this.glowBoost = glowBoost;
            this.owner = owner;
        }

        void tick(ServerLevel level) {
            boolean playerNear = anyPlayerWithin(level, active ? RELEASE_DIST : MATERIALIZE_DIST);
            if (!active) {
                if (!playerNear && !oneShot && !gathering) {
                    return; // frozen at the loop start — free
                }
                materialize(level);
            }
            if (!playerNear && !oneShot && !gathering) {
                if (fadeOut < 0) {
                    fadeOut = EchoActor.FADE_TICKS;
                }
            } else if (!oneShot) {
                fadeOut = -1;
            }
            if (fadeOut >= 0) {
                fadeOut--;
                for (Mob actor : actors.values()) {
                    if (actor instanceof EchoActor echo) {
                        echo.setEchoFade(Math.max(0, fadeOut));
                    }
                }
                if (fadeOut < 0) {
                    release();
                }
                return;
            }
            age++;
            if (oneShot && age > scene.loopTicks()) {
                fadeOut = EchoActor.FADE_TICKS;
                return;
            }
            cursor = (cursor + 1) % Math.max(1, scene.loopTicks());
            for (EchoScenes.Actor actor : scene.actors()) {
                Mob mob = actors.get(actor.role());
                if (mob == null || mob.isRemoved()) {
                    continue;
                }
                if (mob instanceof EchoActor echo && echo.echoFade() < EchoActor.FADE_TICKS) {
                    echo.setEchoFade(echo.echoFade() + 1); // spawn fade-in
                }
                Vec3 gatherTarget = gathering ? gatherTargets.get(actor.role()) : null;
                if (gatherTarget != null) {
                    tickGather(actor, mob, gatherTarget);
                } else {
                    tickKeyframes(actor, mob);
                }
            }
        }

        private void tickKeyframes(EchoScenes.Actor actor, Mob mob) {
            EchoScenes.Pose pose = EchoScenes.sample(actor, scene.loopTicks(), cursor);
            mob.setPos(anchor.x + pose.pos().x, anchor.y + pose.pos().y, anchor.z + pose.pos().z);
            mob.setYRot(pose.yaw());
            mob.setYBodyRot(pose.yaw());
            mob.setYHeadRot(pose.yaw());
            if (mob instanceof EchoActor echo) {
                echo.setEchoAction(pose.action());
            }
            if (pose.action() == EchoActor.ACTION_SWING || pose.action() == EchoActor.ACTION_THROW) {
                int last = lastSwing.getOrDefault(actor.role(), -SWING_REPEAT_TICKS);
                if (age - last >= SWING_REPEAT_TICKS
                        || (pose.action() == EchoActor.ACTION_THROW && age - last >= scene.loopTicks() - 1)) {
                    mob.swing(InteractionHand.MAIN_HAND, true);
                    lastSwing.put(actor.role(), age);
                }
            }
        }

        private void tickGather(EchoScenes.Actor actor, Mob mob, Vec3 target) {
            Vec3 pos = mob.position();
            Vec3 delta = new Vec3(target.x - pos.x, 0.0D, target.z - pos.z);
            double dist = delta.length();
            boolean running = actor.isChild() || actor.isWolf();
            double step = running ? GATHER_RUN_PER_TICK : GATHER_WALK_PER_TICK;
            if (dist > 0.4D) {
                Vec3 move = delta.scale(Math.min(1.0D, step / Math.max(1.0E-4D, dist)));
                mob.setPos(pos.x + move.x, target.y, pos.z + move.z);
                float yaw = (float) (Mth.atan2(move.z, move.x) * Mth.RAD_TO_DEG) - 90.0F;
                mob.setYRot(yaw);
                mob.setYBodyRot(yaw);
                mob.setYHeadRot(yaw);
                if (mob instanceof EchoActor echo) {
                    echo.setEchoAction(running ? EchoActor.ACTION_RUN : EchoActor.ACTION_WALK);
                }
            } else if (mob instanceof EchoActor echo) {
                // Arrived: face the ring center (the tree), idle with scattered waves.
                Vec3 inward = gatherCenter != null ? gatherCenter : target;
                float yaw = (float) (Mth.atan2(inward.z - pos.z, inward.x - pos.x)
                        * Mth.RAD_TO_DEG) - 90.0F;
                mob.setYRot(yaw);
                mob.setYBodyRot(yaw);
                mob.setYHeadRot(yaw);
                echo.setEchoAction((age + mob.getId() * 37) % 160 < 20
                        ? EchoActor.ACTION_WAVE : EchoActor.ACTION_IDLE);
            }
        }

        void materialize(ServerLevel level) {
            if (active) {
                return;
            }
            active = true;
            fadeOut = -1;
            for (EchoScenes.Actor actor : scene.actors()) {
                EchoScenes.Pose pose = EchoScenes.sample(actor, scene.loopTicks(), cursor);
                Mob mob = spawnActor(level, actor,
                        anchor.add(pose.pos()), pose.yaw());
                if (mob != null) {
                    actors.put(actor.role(), mob);
                }
            }
            spawnProps(level);
            applyGlow();
        }

        @Nullable
        private Mob spawnActor(ServerLevel level, EchoScenes.Actor actor, Vec3 pos, float yaw) {
            Mob mob;
            if (actor.isWolf()) {
                if (!EchoGroveEntities.ECHO_GHOST_WOLF.isBound()) {
                    return null;
                }
                mob = new EchoGhostWolfEntity(EchoGroveEntities.ECHO_GHOST_WOLF.get(), level);
            } else {
                if (!EchoGroveEntities.ECHO_GHOST.isBound()) {
                    return null;
                }
                EchoGhostEntity ghost =
                        new EchoGhostEntity(EchoGroveEntities.ECHO_GHOST.get(), level);
                ghost.setChildEcho(actor.isChild());
                mob = ghost;
            }
            mob.setPos(pos.x, pos.y, pos.z);
            mob.setYRot(yaw);
            mob.setYBodyRot(yaw);
            mob.setYHeadRot(yaw);
            if (mob instanceof EchoActor echo) {
                echo.setEchoFade(0); // fade in over the next 30 ticks
            }
            level.addFreshEntity(mob);
            return mob;
        }

        private void spawnProps(ServerLevel level) {
            for (EchoScenes.Prop prop : scene.props()) {
                Block block = BuiltInRegistries.BLOCK.getOptional(
                        ResourceLocation.parse(prop.blockId())).orElse(Blocks.DARK_OAK_FENCE);
                Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(level);
                if (display == null) {
                    continue;
                }
                display.moveTo(anchor.x + prop.dx(), anchor.y + prop.dy(),
                        anchor.z + prop.dz(), 0.0F, 0.0F);
                display.setBlockState(block.defaultBlockState());
                display.addTag(EchoGroveSites.SCENE_DISPLAY_TAG);
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(0);
                float scale = prop.scale();
                display.setTransformation(new Transformation(
                        new Vector3f(-scale * 0.5F, 0.0F, -scale * 0.5F),
                        new Quaternionf(), new Vector3f(scale), new Quaternionf()));
                level.addFreshEntity(display);
                dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx
                        .setViewRange(display, 2.0F);
                props.add(display);
            }
        }

        void applyGlow() {
            float glow = Math.max(glowBoost, floodGlow);
            for (Mob actor : actors.values()) {
                if (actor instanceof EchoActor echo) {
                    echo.setEchoGlow(glow);
                }
            }
        }

        /** Fade finished: freeze (loops) — actors and props go away, cursor resets. */
        private void release() {
            for (Mob actor : actors.values()) {
                actor.discard();
            }
            actors.clear();
            for (Display.BlockDisplay prop : props) {
                prop.discard();
            }
            props.clear();
            lastSwing.clear();
            active = false;
            cursor = 0;
            if (oneShot) {
                done = true;
            }
        }

        boolean finished() {
            return oneShot && done;
        }

        void discard() {
            fadeOut = -1;
            release();
            done = true;
        }

        private boolean anyPlayerWithin(ServerLevel level, double dist) {
            double distSq = dist * dist;
            for (ServerPlayer player : level.players()) {
                if (player.position().distanceToSqr(anchor) <= distSq) {
                    return true;
                }
            }
            return false;
        }
    }
}
