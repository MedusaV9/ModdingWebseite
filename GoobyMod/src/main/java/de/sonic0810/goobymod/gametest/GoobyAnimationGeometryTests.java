package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import de.sonic0810.goobymod.GoobyMod;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Geometrie-Sicherheitsnetz fuer alle Animations-Clips: sampelt jede
 * Animation gegen die Adult- UND Baby-Geometrie und stellt sicher, dass das
 * Modell nie im Boden verschwindet (Regressionstest fuer die urspruenglich
 * kaputte trick_roll, die bei -180 Grad komplett unter der Bodenplatte lag).
 *
 * <p>Der Sampler spiegelt die Bedrock/GeckoLib-Auswertung konservativ:
 * Bone-Hierarchie aus der Geo (Pivot, Basis-Rotation), Keyframe-Kurven mit
 * den im Projekt verwendeten Easings (catmullrom wird linear angenaehert),
 * Rotationsreihenfolge Z*Y*X um den Bone-Pivot, Scale um den Pivot. Damit
 * Vorzeichen-Konventionen keine Luecke reissen, wird jede Kombination aus
 * gespiegelter X- und Z-Rotation geprueft (worst case zaehlt).</p>
 *
 * <p>Schwellen (Modell-Einheiten, 16 = 1 Block), kalibriert am Bestand:
 * Voll-Ueberschlaege (Rotations-Keyframe &ge; {@link #FULL_FLIP_DEGREES}
 * auf X oder Z) muessen die kompletten Bounds ueber dem Boden halten
 * ({@link #STRICT_MIN_Y}); alle anderen Clips duerfen als kuenstlerischer
 * Plueschsquash begrenzt einsinken ({@link #LEGACY_MIN_Y}, Bestand:
 * trick_flop -11.6, baby_tumble -13.2), aber der hoechste Punkt darf nie
 * unter {@link #MIN_TOP_Y} fallen — die alte trick_roll (minY -20.4,
 * topMin +0.95) faellt durch alle drei Pruefungen.</p>
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyAnimationGeometryTests {
    private static final String ARENA = "arena";

    private static final double FULL_FLIP_DEGREES = 135.0;
    private static final double STRICT_MIN_Y = -1.5;
    private static final double LEGACY_MIN_Y = -15.0;
    private static final double MIN_TOP_Y = 4.0;
    private static final double SAMPLE_STEP_SECONDS = 0.02;

    private record Keyframe(double time, double[] vector, String easing) {
    }

    private record GeoBone(String parent, double[] pivot, double[] baseRotation,
            List<double[]> corners) {
    }

    /** Clips, Geometrien und Hierarchie einmal laden, dann alles durchsampeln. */
    @GameTest(template = ARENA)
    public static void animation_clips_stay_above_ground(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper,
                "assets/goobymod/animations/gooby.animation.json").getAsJsonObject("animations");
        List<Map<String, GeoBone>> geometries = List.of(
                loadGeometry(helper, "assets/goobymod/geo/gooby.geo.json"),
                loadGeometry(helper, "assets/goobymod/geo/gooby_baby.geo.json"));

        for (Map.Entry<String, JsonElement> entry : animations.entrySet()) {
            String clipName = entry.getKey();
            JsonObject clip = entry.getValue().getAsJsonObject();
            Map<String, Map<String, List<Keyframe>>> channels = parseChannels(clip);
            boolean fullFlip = hasFullFlip(channels);
            double length = clip.has("animation_length")
                    ? clip.get("animation_length").getAsDouble() : 0.0;

            double worstMinY = Double.MAX_VALUE;
            double worstTopY = Double.MAX_VALUE;
            int samples = Math.max(1, (int) Math.ceil(length / SAMPLE_STEP_SECONDS));
            for (int step = 0; step <= samples; step++) {
                double time = Math.min(step * SAMPLE_STEP_SECONDS, length);
                for (Map<String, GeoBone> geometry : geometries) {
                    for (int signX = -1; signX <= 1; signX += 2) {
                        for (int signZ = -1; signZ <= 1; signZ += 2) {
                            double[] minMax = sampleMinMaxY(geometry, channels, time, signX, signZ);
                            worstMinY = Math.min(worstMinY, minMax[0]);
                            worstTopY = Math.min(worstTopY, minMax[1]);
                        }
                    }
                }
            }

            double minLimit = fullFlip ? STRICT_MIN_Y : LEGACY_MIN_Y;
            helper.assertTrue(worstMinY >= minLimit, String.format(Locale.ROOT,
                    "%s taucht unter den Boden: minY=%.2f Einheiten (Limit %.1f, %s)",
                    clipName, worstMinY, minLimit,
                    fullFlip ? "Voll-Ueberschlag => strikt" : "Legacy-Squash-Toleranz"));
            helper.assertTrue(worstTopY >= MIN_TOP_Y, String.format(Locale.ROOT,
                    "%s verschwindet praktisch komplett im Boden: hoechster Punkt faellt auf "
                            + "%.2f Einheiten (Limit %.1f)", clipName, worstTopY, MIN_TOP_Y));
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Sampling
    // ------------------------------------------------------------------

    /** Liefert {minY, maxY} aller Cube-Ecken zum Zeitpunkt {@code time}. */
    private static double[] sampleMinMaxY(Map<String, GeoBone> geometry,
            Map<String, Map<String, List<Keyframe>>> channels, double time, int signX, int signZ) {
        Map<String, double[][]> localTransforms = new HashMap<>();
        for (Map.Entry<String, GeoBone> boneEntry : geometry.entrySet()) {
            GeoBone bone = boneEntry.getValue();
            Map<String, List<Keyframe>> animated = channels.get(boneEntry.getKey());
            double[] rotation = sampleChannel(animated, "rotation", time, 0.0);
            double[] position = sampleChannel(animated, "position", time, 0.0);
            double[] scale = sampleChannel(animated, "scale", time, 1.0);
            double[][] matrix = rotationMatrixZyx(
                    signX * (rotation[0] + bone.baseRotation()[0]),
                    rotation[1] + bone.baseRotation()[1],
                    signZ * (rotation[2] + bone.baseRotation()[2]));
            localTransforms.put(boneEntry.getKey(),
                    new double[][] {matrix[0], matrix[1], matrix[2], position, scale, bone.pivot()});
        }

        double minY = Double.MAX_VALUE;
        double maxY = -Double.MAX_VALUE;
        for (Map.Entry<String, GeoBone> boneEntry : geometry.entrySet()) {
            GeoBone bone = boneEntry.getValue();
            if (bone.corners().isEmpty()) {
                continue;
            }
            List<String> chain = new ArrayList<>();
            String current = boneEntry.getKey();
            while (current != null) {
                chain.add(current);
                current = geometry.get(current).parent();
            }
            for (double[] corner : bone.corners()) {
                double x = corner[0];
                double y = corner[1];
                double z = corner[2];
                for (String link : chain) {
                    double[][] transform = localTransforms.get(link);
                    double[] position = transform[3];
                    double[] scale = transform[4];
                    double[] pivot = transform[5];
                    double lx = (x - pivot[0]) * scale[0];
                    double ly = (y - pivot[1]) * scale[1];
                    double lz = (z - pivot[2]) * scale[2];
                    double rx = transform[0][0] * lx + transform[0][1] * ly + transform[0][2] * lz;
                    double ry = transform[1][0] * lx + transform[1][1] * ly + transform[1][2] * lz;
                    double rz = transform[2][0] * lx + transform[2][1] * ly + transform[2][2] * lz;
                    x = rx + pivot[0] + position[0];
                    y = ry + pivot[1] + position[1];
                    z = rz + pivot[2] + position[2];
                }
                minY = Math.min(minY, y);
                maxY = Math.max(maxY, y);
            }
        }
        return new double[] {minY, maxY};
    }

    private static double[] sampleChannel(Map<String, List<Keyframe>> animated, String channel,
            double time, double defaultValue) {
        double[] result = {defaultValue, defaultValue, defaultValue};
        if (animated == null || !animated.containsKey(channel)) {
            return result;
        }
        List<Keyframe> frames = animated.get(channel);
        Keyframe first = frames.get(0);
        if (time <= first.time()) {
            return first.vector().clone();
        }
        for (int i = 1; i < frames.size(); i++) {
            Keyframe to = frames.get(i);
            if (time <= to.time()) {
                Keyframe from = frames.get(i - 1);
                double span = to.time() - from.time();
                double progress = span <= 0.0 ? 1.0 : (time - from.time()) / span;
                progress = ease(to.easing(), progress);
                for (int axis = 0; axis < 3; axis++) {
                    result[axis] = from.vector()[axis]
                            + (to.vector()[axis] - from.vector()[axis]) * progress;
                }
                return result;
            }
        }
        return frames.get(frames.size() - 1).vector().clone();
    }

    /** Penner-Easings wie in Blockbench/GeckoLib; Unbekanntes faellt auf linear zurueck. */
    private static double ease(String easing, double x) {
        if (easing == null) {
            return x;
        }
        return switch (easing) {
            case "easeInQuad" -> x * x;
            case "easeOutQuad" -> 1.0 - (1.0 - x) * (1.0 - x);
            case "easeInOutQuad" -> x < 0.5 ? 2.0 * x * x
                    : 1.0 - Math.pow(-2.0 * x + 2.0, 2.0) / 2.0;
            case "easeInSine" -> 1.0 - Math.cos(x * Math.PI / 2.0);
            case "easeOutSine" -> Math.sin(x * Math.PI / 2.0);
            case "easeInOutSine" -> -(Math.cos(Math.PI * x) - 1.0) / 2.0;
            case "easeInBack" -> 2.70158 * x * x * x - 1.70158 * x * x;
            case "easeOutBack" -> 1.0 + 2.70158 * Math.pow(x - 1.0, 3.0)
                    + 1.70158 * Math.pow(x - 1.0, 2.0);
            default -> x;
        };
    }

    private static double[][] rotationMatrixZyx(double degreesX, double degreesY, double degreesZ) {
        double cx = Math.cos(Math.toRadians(degreesX));
        double sx = Math.sin(Math.toRadians(degreesX));
        double cy = Math.cos(Math.toRadians(degreesY));
        double sy = Math.sin(Math.toRadians(degreesY));
        double cz = Math.cos(Math.toRadians(degreesZ));
        double sz = Math.sin(Math.toRadians(degreesZ));
        return new double[][] {
                {cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx},
                {sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx},
                {-sy, cy * sx, cy * cx},
        };
    }

    // ------------------------------------------------------------------
    // Parsing
    // ------------------------------------------------------------------

    private static Map<String, Map<String, List<Keyframe>>> parseChannels(JsonObject clip) {
        Map<String, Map<String, List<Keyframe>>> channels = new HashMap<>();
        if (!clip.has("bones")) {
            return channels;
        }
        for (Map.Entry<String, JsonElement> boneEntry : clip.getAsJsonObject("bones").entrySet()) {
            Map<String, List<Keyframe>> boneChannels = new HashMap<>();
            for (Map.Entry<String, JsonElement> channelEntry
                    : boneEntry.getValue().getAsJsonObject().entrySet()) {
                List<Keyframe> frames = new ArrayList<>();
                JsonElement value = channelEntry.getValue();
                if (value.isJsonObject() && !value.getAsJsonObject().has("vector")) {
                    for (Map.Entry<String, JsonElement> frame
                            : value.getAsJsonObject().entrySet()) {
                        frames.add(parseKeyframe(Double.parseDouble(frame.getKey()),
                                frame.getValue()));
                    }
                } else {
                    frames.add(parseKeyframe(0.0, value));
                }
                frames.sort((a, b) -> Double.compare(a.time(), b.time()));
                boneChannels.put(channelEntry.getKey(), frames);
            }
            channels.put(boneEntry.getKey(), boneChannels);
        }
        return channels;
    }

    private static Keyframe parseKeyframe(double time, JsonElement entry) {
        if (entry.isJsonArray()) {
            return new Keyframe(time, toVector(entry.getAsJsonArray()), null);
        }
        JsonObject frame = entry.getAsJsonObject();
        JsonArray vector = frame.has("vector") ? frame.getAsJsonArray("vector")
                : frame.has("post") ? frame.getAsJsonArray("post") : frame.getAsJsonArray("pre");
        String easing = frame.has("easing") ? frame.get("easing").getAsString() : null;
        return new Keyframe(time, toVector(vector), easing);
    }

    private static double[] toVector(JsonArray array) {
        return new double[] {array.get(0).getAsDouble(), array.get(1).getAsDouble(),
                array.get(2).getAsDouble()};
    }

    private static boolean hasFullFlip(Map<String, Map<String, List<Keyframe>>> channels) {
        for (Map<String, List<Keyframe>> boneChannels : channels.values()) {
            List<Keyframe> rotation = boneChannels.get("rotation");
            if (rotation == null) {
                continue;
            }
            for (Keyframe frame : rotation) {
                if (Math.abs(frame.vector()[0]) >= FULL_FLIP_DEGREES
                        || Math.abs(frame.vector()[2]) >= FULL_FLIP_DEGREES) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Map<String, GeoBone> loadGeometry(GameTestHelper helper, String path) {
        JsonObject geometry = loadAssetJson(helper, path)
                .getAsJsonArray("minecraft:geometry").get(0).getAsJsonObject();
        Map<String, GeoBone> bones = new HashMap<>();
        for (JsonElement element : geometry.getAsJsonArray("bones")) {
            JsonObject bone = element.getAsJsonObject();
            List<double[]> corners = new ArrayList<>();
            if (bone.has("cubes")) {
                for (JsonElement cubeElement : bone.getAsJsonArray("cubes")) {
                    JsonObject cube = cubeElement.getAsJsonObject();
                    double[] origin = toVector(cube.getAsJsonArray("origin"));
                    double[] size = toVector(cube.getAsJsonArray("size"));
                    double inflate = cube.has("inflate") ? cube.get("inflate").getAsDouble() : 0.0;
                    for (int dx = 0; dx <= 1; dx++) {
                        for (int dy = 0; dy <= 1; dy++) {
                            for (int dz = 0; dz <= 1; dz++) {
                                corners.add(new double[] {
                                        origin[0] - inflate + dx * (size[0] + 2.0 * inflate),
                                        origin[1] - inflate + dy * (size[1] + 2.0 * inflate),
                                        origin[2] - inflate + dz * (size[2] + 2.0 * inflate)});
                            }
                        }
                    }
                }
            }
            bones.put(bone.get("name").getAsString(), new GeoBone(
                    bone.has("parent") ? bone.get("parent").getAsString() : null,
                    bone.has("pivot") ? toVector(bone.getAsJsonArray("pivot"))
                            : new double[] {0.0, 0.0, 0.0},
                    bone.has("rotation") ? toVector(bone.getAsJsonArray("rotation"))
                            : new double[] {0.0, 0.0, 0.0},
                    corners));
        }
        return bones;
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream =
                GoobyAnimationGeometryTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(
                    new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path
                    + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }
}
