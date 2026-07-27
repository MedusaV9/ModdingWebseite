package dev.projecteclipse.eclipse.woah.echogrove;

import java.io.BufferedReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.packs.resources.Resource;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * WOAH-05 scene definitions (plan §3.3): authored keyframe loops for the five
 * memory scenes, with Catmull-Rom position sampling and linear shortest-way yaw.
 *
 * <p><b>Data lane:</b> JSON per scene under {@code data/eclipse/echo_scenes/<id>.json}
 * (shipped as reference/override templates) is read from the server resource
 * manager on {@link ServerStartedEvent}; the CODE defaults below are authoritative
 * when a file is absent or broken — absence never breaks the grove (the
 * GhostConfig "reload + defaults" spirit; there is no generic
 * SimpleJsonResourceReloadListener seam in this repo, so the load is a plain
 * startup pass — scenes are static art, not live-tuned data).</p>
 *
 * <p><b>Loop seam law:</b> the last keyframe must equal the first (validator WARNs
 * otherwise); the scene player never fades at the seam.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoScenes {
    /** Actor variants. */
    public static final String VARIANT_PLAYER = "player";
    public static final String VARIANT_PLAYER_CHILD = "player_child";
    public static final String VARIANT_WOLF = "wolf";

    /** One sampled pose: position (scene-local), yaw, keyframe action. */
    public record Pose(Vec3 pos, float yaw, byte action) {}

    public record Keyframe(int t, double x, double y, double z, float yaw, byte action) {}

    public record Actor(String role, String variant, List<Keyframe> keyframes) {
        public boolean isChild() {
            return VARIANT_PLAYER_CHILD.equals(variant);
        }

        public boolean isWolf() {
            return VARIANT_WOLF.equals(variant);
        }
    }

    /** Scene-instance prop (dynamic BlockDisplays living with the instance, plan §3.4). */
    public record Prop(String blockId, double dx, double dy, double dz, float scale) {}

    public record Scene(String id, int loopTicks, int fadeTicks, int dx, int dz,
            List<Actor> actors, List<Prop> props) {}

    /** Scene ids in orb-kind order 0–4 (plan §7.1). */
    public static final List<String> SCENE_ORDER = List.of(
            "children_chase", "miner", "bench_couple", "dog_fetch", "lantern_walk");

    /** The three lantern posts (grove-local XZ) — shared with the terraformer. */
    public static final int[][] LANTERN_POSTS = {{8, 22}, {16, 14}, {22, 4}};

    private static volatile Map<String, Scene> scenes = Map.of();

    private EchoScenes() {}

    public static String sceneIdFor(int index) {
        return SCENE_ORDER.get(Math.floorMod(index, SCENE_ORDER.size()));
    }

    @Nullable
    public static Scene scene(String id) {
        Map<String, Scene> current = scenes;
        if (current.isEmpty()) {
            current = defaults();
            scenes = current;
        }
        return current.get(id);
    }

    public static Map<String, Scene> all() {
        Map<String, Scene> current = scenes;
        if (current.isEmpty()) {
            current = defaults();
            scenes = current;
        }
        return current;
    }

    // ------------------------------------------------------------------ sampling

    /**
     * Catmull-Rom sample of an actor's loop at tick {@code t} (0 ≤ t < loopTicks).
     * Neighbor keyframes wrap around the loop seam (last == first), so the curve is
     * smooth across the seam; yaw interpolates linearly along the shortest way.
     */
    public static Pose sample(Actor actor, int loopTicks, double t) {
        List<Keyframe> frames = actor.keyframes();
        if (frames.isEmpty()) {
            return new Pose(Vec3.ZERO, 0.0F, EchoActor.ACTION_IDLE);
        }
        if (frames.size() == 1) {
            Keyframe only = frames.get(0);
            return new Pose(new Vec3(only.x(), only.y(), only.z()), only.yaw(), only.action());
        }
        int segment = frames.size() - 1; // last == first: segments span [i, i+1]
        int i1 = 0;
        for (int i = 0; i < segment; i++) {
            if (t >= frames.get(i).t() && t <= frames.get(i + 1).t()) {
                i1 = i;
                break;
            }
            if (i == segment - 1) {
                i1 = i; // past the last keyframe (clamp into the final segment)
            }
        }
        Keyframe k1 = frames.get(i1);
        Keyframe k2 = frames.get(i1 + 1);
        Keyframe k0 = frames.get(i1 == 0 ? Math.max(0, segment - 1) : i1 - 1);
        Keyframe k3 = frames.get(i1 + 2 <= segment ? i1 + 2 : 1);
        double span = Math.max(1, k2.t() - k1.t());
        double u = Mth.clamp((t - k1.t()) / span, 0.0D, 1.0D);
        double x = catmullRom(u, k0.x(), k1.x(), k2.x(), k3.x());
        double y = catmullRom(u, k0.y(), k1.y(), k2.y(), k3.y());
        double z = catmullRom(u, k0.z(), k1.z(), k2.z(), k3.z());
        float yaw = k1.yaw() + Mth.wrapDegrees(k2.yaw() - k1.yaw()) * (float) u;
        return new Pose(new Vec3(x, y, z), yaw, k1.action());
    }

    private static double catmullRom(double t, double p0, double p1, double p2, double p3) {
        double t2 = t * t;
        double t3 = t2 * t;
        return 0.5D * ((2.0D * p1) + (-p0 + p2) * t
                + (2.0D * p0 - 5.0D * p1 + 4.0D * p2 - p3) * t2
                + (-p0 + 3.0D * p1 - 3.0D * p2 + p3) * t3);
    }

    // ------------------------------------------------------------------ loading

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        Map<String, Scene> loaded = new HashMap<>(defaults());
        int overridden = 0;
        Map<ResourceLocation, Resource> resources = event.getServer().getResourceManager()
                .listResources("echo_scenes", rl -> EclipseMod.MOD_ID.equals(rl.getNamespace())
                        && rl.getPath().endsWith(".json"));
        for (Map.Entry<ResourceLocation, Resource> entry : resources.entrySet()) {
            try (BufferedReader reader = entry.getValue().openAsReader()) {
                Scene scene = parseScene(JsonParser.parseReader(reader).getAsJsonObject());
                validate(scene);
                loaded.put(scene.id(), scene);
                overridden++;
            } catch (Exception e) {
                EclipseMod.LOGGER.error("EchoScenes: bad scene json {} — keeping code default",
                        entry.getKey(), e);
            }
        }
        scenes = Map.copyOf(loaded);
        EclipseMod.LOGGER.info("EchoScenes: {} scene(s) active ({} from datapack)",
                scenes.size(), overridden);
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        scenes = Map.of();
    }

    static Scene parseScene(JsonObject root) {
        String id = root.get("id").getAsString();
        int loopTicks = root.get("loop_ticks").getAsInt();
        int fadeTicks = root.has("fade_ticks") ? root.get("fade_ticks").getAsInt() : 30;
        JsonObject anchor = root.getAsJsonObject("anchor");
        int dx = anchor.get("dx").getAsInt();
        int dz = anchor.get("dz").getAsInt();
        List<Actor> actors = new ArrayList<>();
        for (JsonElement actorElement : root.getAsJsonArray("actors")) {
            JsonObject actorObj = actorElement.getAsJsonObject();
            List<Keyframe> frames = new ArrayList<>();
            for (JsonElement frameElement : actorObj.getAsJsonArray("keyframes")) {
                JsonObject frame = frameElement.getAsJsonObject();
                frames.add(new Keyframe(
                        frame.get("t").getAsInt(),
                        frame.get("x").getAsDouble(),
                        frame.has("y") ? frame.get("y").getAsDouble() : 0.0D,
                        frame.get("z").getAsDouble(),
                        frame.has("yaw") ? frame.get("yaw").getAsFloat() : 0.0F,
                        EchoActor.parseAction(frame.has("action")
                                ? frame.get("action").getAsString() : "idle")));
            }
            actors.add(new Actor(actorObj.get("role").getAsString(),
                    actorObj.has("variant") ? actorObj.get("variant").getAsString() : VARIANT_PLAYER,
                    List.copyOf(frames)));
        }
        List<Prop> props = new ArrayList<>();
        if (root.has("props")) {
            JsonArray propArray = root.getAsJsonArray("props");
            for (JsonElement propElement : propArray) {
                JsonObject prop = propElement.getAsJsonObject();
                if (prop.has("static") && prop.get("static").getAsBoolean()) {
                    continue; // static props are terraforming's job (plan §2.2 no. 5)
                }
                props.add(new Prop(prop.get("block").getAsString(),
                        prop.get("dx").getAsDouble(), prop.get("dy").getAsDouble(),
                        prop.get("dz").getAsDouble(),
                        prop.has("scale") ? prop.get("scale").getAsFloat() : 1.0F));
            }
        }
        return new Scene(id, loopTicks, fadeTicks, dx, dz, List.copyOf(actors), List.copyOf(props));
    }

    private static void validate(Scene scene) {
        for (Actor actor : scene.actors()) {
            if (actor.keyframes().size() < 2) {
                continue;
            }
            Keyframe first = actor.keyframes().get(0);
            Keyframe last = actor.keyframes().get(actor.keyframes().size() - 1);
            if (first.x() != last.x() || first.y() != last.y() || first.z() != last.z()) {
                EclipseMod.LOGGER.warn(
                        "EchoScenes: scene {} actor {} loop seam is open (last != first) — "
                                + "the loop will pop", scene.id(), actor.role());
            }
        }
    }

    // ------------------------------------------------------------------ authored defaults

    private static Keyframe kf(int t, double x, double z, float yaw, byte action) {
        return new Keyframe(t, x, 0.0D, z, yaw, action);
    }

    private static Keyframe kf(int t, double x, double y, double z, float yaw, byte action) {
        return new Keyframe(t, x, y, z, yaw, action);
    }

    /** The five authored scenes (plan §3.3) — mirrored 1:1 in {@code data/eclipse/echo_scenes/}. */
    static Map<String, Scene> defaults() {
        Map<String, Scene> map = new HashMap<>();

        // 1. children_chase (320t) — two children round the old tree at (−14, 6),
        //    counter-phased by 40t; the tree itself is real terrain (no prop).
        List<Keyframe> childA = List.of(
                kf(0, 0.0D, 3.0D, 90.0F, EchoActor.ACTION_RUN),
                kf(80, 3.0D, 0.0D, 180.0F, EchoActor.ACTION_RUN),
                kf(160, 0.0D, -3.0D, 270.0F, EchoActor.ACTION_RUN),
                kf(240, -3.0D, 0.0D, 0.0F, EchoActor.ACTION_RUN),
                kf(320, 0.0D, 3.0D, 90.0F, EchoActor.ACTION_RUN));
        List<Keyframe> childB = List.of(
                kf(0, -2.4D, 2.4D, 135.0F, EchoActor.ACTION_RUN),
                kf(80, 2.4D, 2.4D, 225.0F, EchoActor.ACTION_RUN),
                kf(160, 2.4D, -2.4D, 315.0F, EchoActor.ACTION_RUN),
                kf(240, -2.4D, -2.4D, 45.0F, EchoActor.ACTION_RUN),
                kf(320, -2.4D, 2.4D, 135.0F, EchoActor.ACTION_RUN));
        map.put("children_chase", new Scene("children_chase", 320, 30, -14, 6,
                List.of(new Actor("child_a", VARIANT_PLAYER_CHILD, childA),
                        new Actor("child_b", VARIANT_PLAYER_CHILD, childB)),
                List.of()));

        // 2. miner (240t) — three steps up to the deepslate rock at (18, −10), four
        //    swings on a 30t beat, a look over the shoulder, then back to the mark.
        List<Keyframe> miner = List.of(
                kf(0, -3.0D, 0.0D, 90.0F, EchoActor.ACTION_IDLE),
                kf(40, -1.0D, 0.0D, 90.0F, EchoActor.ACTION_WALK),
                kf(60, 0.0D, 0.0D, 90.0F, EchoActor.ACTION_IDLE),
                kf(70, 0.0D, 0.0D, 90.0F, EchoActor.ACTION_SWING),
                kf(100, 0.0D, 0.0D, 90.0F, EchoActor.ACTION_SWING),
                kf(130, 0.0D, 0.0D, 90.0F, EchoActor.ACTION_SWING),
                kf(160, 0.0D, 0.0D, 90.0F, EchoActor.ACTION_SWING),
                kf(180, 0.0D, 0.0D, 210.0F, EchoActor.ACTION_IDLE),   // the shoulder look
                kf(200, 0.0D, 0.0D, 90.0F, EchoActor.ACTION_IDLE),
                kf(230, -3.0D, 0.0D, 270.0F, EchoActor.ACTION_WALK),
                kf(240, -3.0D, 0.0D, 90.0F, EchoActor.ACTION_IDLE));
        map.put("miner", new Scene("miner", 240, 30, 18, -10,
                List.of(new Actor("miner", VARIANT_PLAYER, miner)),
                List.of(new Prop("minecraft:dark_oak_button", 2.2D, 0.2D, 1.4D, 0.6F),
                        new Prop("minecraft:dark_oak_button", 2.2D, 0.2D, -1.4D, 0.6F))));

        // 3. bench_couple (400t) — two ghosts sit on the bench at (10, 16); at t=200
        //    one turns the head (yaw ±25°), at t=340 a small wave.
        List<Keyframe> benchA = List.of(
                kf(0, -0.5D, 0.0D, 180.0F, EchoActor.ACTION_SIT),
                kf(200, -0.5D, 0.0D, 205.0F, EchoActor.ACTION_SIT),
                kf(280, -0.5D, 0.0D, 180.0F, EchoActor.ACTION_SIT),
                kf(400, -0.5D, 0.0D, 180.0F, EchoActor.ACTION_SIT));
        List<Keyframe> benchB = List.of(
                kf(0, 0.5D, 0.0D, 180.0F, EchoActor.ACTION_SIT),
                kf(200, 0.5D, 0.0D, 155.0F, EchoActor.ACTION_SIT),
                kf(340, 0.5D, 0.0D, 165.0F, EchoActor.ACTION_WAVE),
                kf(360, 0.5D, 0.0D, 180.0F, EchoActor.ACTION_SIT),
                kf(400, 0.5D, 0.0D, 180.0F, EchoActor.ACTION_SIT));
        map.put("bench_couple", new Scene("bench_couple", 400, 30, 10, 16,
                List.of(new Actor("partner_a", VARIANT_PLAYER, benchA),
                        new Actor("partner_b", VARIANT_PLAYER, benchB)),
                List.of()));

        // 4. dog_fetch (280t) — throw at t=20; the wolf sprints 8 blocks out, jumps at
        //    the stick (t=120), trots back (t=260). The stick lies at the far mark.
        List<Keyframe> owner = List.of(
                kf(0, 0.0D, 0.0D, 0.0F, EchoActor.ACTION_IDLE),
                kf(20, 0.0D, 0.0D, 0.0F, EchoActor.ACTION_THROW),
                kf(140, 0.0D, 0.0D, 0.0F, EchoActor.ACTION_IDLE),
                kf(260, 0.0D, 0.0D, 0.0F, EchoActor.ACTION_WAVE),
                kf(280, 0.0D, 0.0D, 0.0F, EchoActor.ACTION_IDLE));
        List<Keyframe> dog = List.of(
                kf(0, 1.0D, 0.5D, 0.0F, EchoActor.ACTION_IDLE),
                kf(30, 1.0D, 0.5D, 0.0F, EchoActor.ACTION_IDLE),
                kf(100, 1.0D, 8.0D, 0.0F, EchoActor.ACTION_RUN),
                kf(120, 1.0D, 0.6D, 8.6D, 0.0F, EchoActor.ACTION_JUMP),
                kf(140, 1.0D, 8.0D, 180.0F, EchoActor.ACTION_IDLE),
                kf(260, 1.0D, 0.5D, 180.0F, EchoActor.ACTION_WALK),
                kf(280, 1.0D, 0.5D, 0.0F, EchoActor.ACTION_IDLE));
        map.put("dog_fetch", new Scene("dog_fetch", 280, 30, -6, -18,
                List.of(new Actor("owner", VARIANT_PLAYER, owner),
                        new Actor("dog", VARIANT_WOLF, dog)),
                List.of(new Prop("minecraft:dark_oak_fence", 1.0D, 0.05D, 8.6D, 0.3F))));

        // 5. lantern_walk (360t) — the lantern keeper walks post 1 → 2 → 3 and back,
        //    pausing at each (IDLE), with a small wave at post 2. Anchor = post 1;
        //    the other posts are LANTERN_POSTS deltas.
        double p2x = LANTERN_POSTS[1][0] - LANTERN_POSTS[0][0]; // +8
        double p2z = LANTERN_POSTS[1][1] - LANTERN_POSTS[0][1]; // −8
        double p3x = LANTERN_POSTS[2][0] - LANTERN_POSTS[0][0]; // +14
        double p3z = LANTERN_POSTS[2][1] - LANTERN_POSTS[0][1]; // −18
        List<Keyframe> keeper = List.of(
                kf(0, 0.0D, 0.0D, 135.0F, EchoActor.ACTION_IDLE),
                kf(20, 0.0D, 0.0D, 135.0F, EchoActor.ACTION_WALK),
                kf(90, p2x, p2z, 135.0F, EchoActor.ACTION_IDLE),
                kf(110, p2x, p2z, 100.0F, EchoActor.ACTION_WAVE),
                kf(130, p2x, p2z, 145.0F, EchoActor.ACTION_WALK),
                kf(210, p3x, p3z, 145.0F, EchoActor.ACTION_IDLE),
                kf(240, p3x, p3z, 325.0F, EchoActor.ACTION_WALK),
                kf(350, 0.0D, 0.0D, 315.0F, EchoActor.ACTION_IDLE),
                kf(360, 0.0D, 0.0D, 135.0F, EchoActor.ACTION_IDLE));
        map.put("lantern_walk", new Scene("lantern_walk", 360, 30,
                LANTERN_POSTS[0][0], LANTERN_POSTS[0][1],
                List.of(new Actor("keeper", VARIANT_PLAYER, keeper)),
                List.of()));

        return Map.copyOf(map);
    }
}
