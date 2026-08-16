package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.logging.LogUtils;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.animation.GoobyAnimationState;
import de.sonic0810.goobymod.entity.animation.GoobyLocomotion;
import de.sonic0810.goobymod.entity.animation.GoobyLocomotion.Gait;
import de.sonic0810.goobymod.registry.ModEntities;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeMap;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.gametest.framework.GameTestSequence;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;
import org.slf4j.Logger;

/**
 * Lokomotions-Suite: deterministische Gait-Schwellen (idle/walk/run) samt
 * EMA-Glaettung und Teleport-Guard, Clip-Vertraege der neuen walk/run-Loops
 * (Baby-sichere Bones, Loop-Nahtstellen, Squash/Stretch- und Followthrough-
 * Carrier), die Invariante, dass die Gait-Auswahl niemals Sitz-/Schlaf-
 * Bruecken der Pose-Maschine bricht, und eine AI-isolierte Live-Messung, die
 * alle real benutzten Speed-Modifier auf die erwarteten Gaits abbildet.
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyLocomotionTests {
    private static final Logger LOGGER = LogUtils.getLogger();
    private static final String ARENA = "arena";
    private static final String ARENA_LARGE = "arena_large";
    private static final double EPSILON = 1.0E-4;
    /** Ticks, bis die EMA nach einem Tempo-Wechsel sicher konvergiert ist. */
    private static final int CONVERGENCE_TICKS = 30;

    // ------------------------------------------------------------------
    // Helfer
    // ------------------------------------------------------------------

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyLocomotionTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    private static Set<String> geoBoneNames(GameTestHelper helper, String geoPath) {
        Set<String> names = new HashSet<>();
        JsonObject geometry = loadAssetJson(helper, geoPath);
        for (JsonElement element : geometry.getAsJsonArray("minecraft:geometry")
                .get(0).getAsJsonObject().getAsJsonArray("bones")) {
            names.add(element.getAsJsonObject().get("name").getAsString());
        }
        return names;
    }

    /** Keyframe-Objekt/-Liste zu seinem Vektor normalisieren (wie GeckoLib). */
    private static JsonArray keyframeVector(JsonElement entry) {
        if (entry.isJsonArray()) {
            return entry.getAsJsonArray();
        }
        JsonObject object = entry.getAsJsonObject();
        for (String key : new String[] {"vector", "post", "pre"}) {
            if (object.has(key)) {
                return object.getAsJsonArray(key);
            }
        }
        return new JsonArray();
    }

    /** Kanal-Keyframes als Zeit-sortierte Map (Zeit -> Vektor). */
    private static TreeMap<Double, JsonArray> channelKeyframes(JsonElement channel) {
        TreeMap<Double, JsonArray> frames = new TreeMap<>();
        if (channel.isJsonObject() && !channel.getAsJsonObject().has("vector")) {
            for (Map.Entry<String, JsonElement> entry : channel.getAsJsonObject().entrySet()) {
                frames.put(Double.parseDouble(entry.getKey()), keyframeVector(entry.getValue()));
            }
        } else {
            frames.put(0.0, keyframeVector(channel));
        }
        return frames;
    }

    private static boolean vectorsEqual(JsonArray left, JsonArray right) {
        if (left.size() != right.size()) {
            return false;
        }
        for (int index = 0; index < left.size(); index++) {
            if (Math.abs(left.get(index).getAsDouble() - right.get(index).getAsDouble()) > EPSILON) {
                return false;
            }
        }
        return true;
    }

    /** Frische Lokomotion, per konstantem Tempo bis zur Konvergenz gefuettert. */
    private static GoobyLocomotion convergedAt(double speed) {
        GoobyLocomotion locomotion = new GoobyLocomotion();
        for (long tick = 0; tick < CONVERGENCE_TICKS; tick++) {
            locomotion.update(tick, speed);
        }
        return locomotion;
    }

    // ------------------------------------------------------------------
    // 1. Schwellen + Hysterese (pure Selektor-Logik)
    // ------------------------------------------------------------------

    /** Enter-Schwellen liegen strikt ueber den Exit-Schwellen und ordnen sich sinnvoll. */
    @GameTest(template = ARENA)
    public static void gait_thresholds_are_ordered(GameTestHelper helper) {
        helper.assertTrue(GoobyLocomotion.WALK_EXIT_SPEED < GoobyLocomotion.WALK_ENTER_SPEED,
                "Walk-Exit muss unter Walk-Enter liegen (Hysterese)");
        helper.assertTrue(GoobyLocomotion.RUN_EXIT_SPEED < GoobyLocomotion.RUN_ENTER_SPEED,
                "Run-Exit muss unter Run-Enter liegen (Hysterese)");
        helper.assertTrue(GoobyLocomotion.WALK_ENTER_SPEED < GoobyLocomotion.RUN_EXIT_SPEED,
                "Das Walk-Band waere leer: Walk-Enter >= Run-Exit");
        helper.assertTrue(GoobyLocomotion.MAX_PLAUSIBLE_SPEED > GoobyLocomotion.RUN_ENTER_SPEED + 0.05,
                "Teleport-Guard wuerde legitime Sprint-Tempi verwerfen");
        helper.assertTrue(GoobyLocomotion.SMOOTHING > 0 && GoobyLocomotion.SMOOTHING <= 1,
                "EMA-Gewicht muss in (0, 1] liegen");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.IDLE,
                        GoobyLocomotion.WALK_ENTER_SPEED - EPSILON) == Gait.IDLE,
                "Knapp unter Walk-Enter darf IDLE nicht verlassen werden");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.IDLE,
                        GoobyLocomotion.WALK_ENTER_SPEED) == Gait.WALK,
                "Walk-Enter-Schwelle startet keinen Walk");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.IDLE,
                        GoobyLocomotion.RUN_ENTER_SPEED) == Gait.RUN,
                "Run-Enter-Schwelle startet aus IDLE keinen Run");
        helper.succeed();
    }

    /** Oszillation exakt um eine Enter-Schwelle darf den Gait nie zurueckflippen. */
    @GameTest(template = ARENA)
    public static void gait_selection_has_no_boundary_flutter(GameTestHelper helper) {
        GoobyLocomotion walkLocomotion = convergedAt(GoobyLocomotion.WALK_ENTER_SPEED + 0.01);
        helper.assertTrue(walkLocomotion.gait() == Gait.WALK,
                "Testaufbau: leicht ueber Walk-Enter muss WALK ergeben");
        long tick = CONVERGENCE_TICKS;
        for (int index = 0; index < 60; index++) {
            double speed = GoobyLocomotion.WALK_ENTER_SPEED + (index % 2 == 0 ? -EPSILON : EPSILON);
            helper.assertTrue(walkLocomotion.update(tick++, speed) == Gait.WALK,
                    "Walk flattert an der Enter-Schwelle (Tick " + index + ")");
        }

        GoobyLocomotion runLocomotion = convergedAt(GoobyLocomotion.RUN_ENTER_SPEED + 0.01);
        helper.assertTrue(runLocomotion.gait() == Gait.RUN,
                "Testaufbau: leicht ueber Run-Enter muss RUN ergeben");
        tick = CONVERGENCE_TICKS;
        for (int index = 0; index < 60; index++) {
            double speed = GoobyLocomotion.RUN_ENTER_SPEED + (index % 2 == 0 ? -EPSILON : EPSILON);
            helper.assertTrue(runLocomotion.update(tick++, speed) == Gait.RUN,
                    "Run flattert an der Enter-Schwelle (Tick " + index + ")");
        }
        helper.succeed();
    }

    /** Abbremsen durchlaeuft RUN -> WALK -> IDLE erst unterhalb der Exit-Schwellen. */
    @GameTest(template = ARENA)
    public static void gait_deceleration_uses_exit_thresholds(GameTestHelper helper) {
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.RUN,
                        GoobyLocomotion.RUN_EXIT_SPEED + EPSILON) == Gait.RUN,
                "RUN darf oberhalb der Run-Exit-Schwelle nicht abbrechen");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.RUN,
                        GoobyLocomotion.RUN_EXIT_SPEED) == Gait.WALK,
                "Run-Exit-Schwelle faellt nicht auf WALK zurueck");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.WALK,
                        GoobyLocomotion.WALK_EXIT_SPEED + EPSILON) == Gait.WALK,
                "WALK darf oberhalb der Walk-Exit-Schwelle nicht enden");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.WALK,
                        GoobyLocomotion.WALK_EXIT_SPEED) == Gait.IDLE,
                "Walk-Exit-Schwelle beendet den Walk nicht");
        helper.assertTrue(GoobyLocomotion.selectGait(Gait.RUN,
                        GoobyLocomotion.WALK_EXIT_SPEED) == Gait.IDLE,
                "Vollbremsung aus RUN muss direkt in IDLE landen");
        helper.succeed();
    }

    /** Gleiche Eingaben ergeben identische Gaits; Mehrfach-Update pro Tick ist idempotent. */
    @GameTest(template = ARENA)
    public static void gait_selection_is_deterministic(GameTestHelper helper) {
        Random random = new Random(20260816L);
        GoobyLocomotion first = new GoobyLocomotion();
        GoobyLocomotion second = new GoobyLocomotion();
        for (long tick = 0; tick < 200; tick++) {
            double speed = random.nextDouble() * 0.3;
            Gait fromFirst = first.update(tick, speed);
            // "second" simuliert mehrere Render-Frames/Controller im selben Tick.
            second.update(tick, speed);
            second.update(tick, speed);
            Gait fromSecond = second.update(tick, speed);
            helper.assertTrue(fromFirst == fromSecond,
                    "Gait-Auswahl ist nicht frame-idempotent bei Tempo " + speed);
        }
        helper.succeed();
    }

    /** Teleport-grosse Positionsspruenge (auch Client-Lerp-Raten) kippen den Gait nie. */
    @GameTest(template = ARENA)
    public static void gait_ignores_teleport_spikes(GameTestHelper helper) {
        GoobyLocomotion walking = convergedAt(0.12);
        helper.assertTrue(walking.gait() == Gait.WALK, "Testaufbau: 0.12 b/t muss WALK sein");
        long tick = CONVERGENCE_TICKS;
        // Der Client-Lerp verteilt einen 10-Block-Teleport auf ~3 Ticks.
        for (int index = 0; index < 3; index++) {
            helper.assertTrue(walking.update(tick++, 10.0 / 3.0) == Gait.WALK,
                    "Teleport-Spike hat den Gait gekippt (Spike-Tick " + index + ")");
        }
        helper.assertTrue(walking.update(tick++, 0.12) == Gait.WALK,
                "Gait erholt sich nach dem Teleport nicht sofort");

        GoobyLocomotion standing = convergedAt(0.0);
        helper.assertTrue(standing.update(CONVERGENCE_TICKS, 4.0) == Gait.IDLE,
                "Teleport aus dem Stand erzeugt einen Fake-Run");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 2. Clip-Vertraege der neuen walk/run-Loops
    // ------------------------------------------------------------------

    /** walk/run existieren, loopen, sind Baby-sicher und schneller Run < langsamer Walk. */
    @GameTest(template = ARENA)
    public static void walk_run_clips_available_and_baby_safe(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper,
                "assets/goobymod/animations/gooby.animation.json").getAsJsonObject("animations");
        Set<String> adultBones = geoBoneNames(helper, "assets/goobymod/geo/gooby.geo.json");
        Set<String> babyBones = geoBoneNames(helper, "assets/goobymod/geo/gooby_baby.geo.json");

        for (String clipName : List.of("animation.gooby.walk", "animation.gooby.run")) {
            helper.assertTrue(animations.has(clipName), "Lokomotions-Clip fehlt: " + clipName);
            JsonObject clip = animations.getAsJsonObject(clipName);
            helper.assertTrue(clip.has("loop") && clip.get("loop").getAsBoolean(),
                    clipName + " muss ein Loop sein");
            helper.assertTrue(clip.get("animation_length").getAsDouble() > 0,
                    clipName + " hat keine positive Laenge");

            JsonObject bones = clip.getAsJsonObject("bones");
            for (Map.Entry<String, JsonElement> bone : bones.entrySet()) {
                helper.assertTrue(adultBones.contains(bone.getKey()),
                        clipName + " animiert unbekannte Adult-Bone '" + bone.getKey() + "'");
                helper.assertTrue(babyBones.contains(bone.getKey()),
                        clipName + " animiert Bone '" + bone.getKey() + "', die dem Baby-Geo fehlt");
            }
            for (String required : List.of("root", "body", "earLeft", "earRight", "tail")) {
                helper.assertTrue(bones.has(required),
                        clipName + " laesst den Followthrough-/Squash-Traeger '" + required + "' aus");
            }
        }

        // Der Legacy-Hop-Loop bleibt fuer Resource-Packs/Trigger erhalten.
        helper.assertTrue(animations.has("animation.gooby.hop"),
                "Legacy-Clip animation.gooby.hop wurde entfernt (Kompatibilitaet!)");

        double walkLength = animations.getAsJsonObject("animation.gooby.walk")
                .get("animation_length").getAsDouble();
        double runLength = animations.getAsJsonObject("animation.gooby.run")
                .get("animation_length").getAsDouble();
        helper.assertTrue(runLength < walkLength,
                "Run-Kadenz (" + runLength + "s) muss schneller sein als Walk (" + walkLength + "s)");
        helper.succeed();
    }

    /** Squash/Stretch-Bogen, Antizipations-Dip und nahtlose Loop-Enden pro Kanal. */
    @GameTest(template = ARENA)
    public static void walk_run_clips_keep_squash_stretch_and_seamless_loops(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper,
                "assets/goobymod/animations/gooby.animation.json").getAsJsonObject("animations");

        for (String clipName : List.of("animation.gooby.walk", "animation.gooby.run")) {
            JsonObject clip = animations.getAsJsonObject(clipName);
            double length = clip.get("animation_length").getAsDouble();
            JsonObject bones = clip.getAsJsonObject("bones");

            // Airborne-Stretch + Landing-Squash auf der Body-Scale.
            TreeMap<Double, JsonArray> bodyScale =
                    channelKeyframes(bones.getAsJsonObject("body").get("scale"));
            boolean hasStretch = bodyScale.values().stream()
                    .anyMatch(vector -> vector.get(1).getAsDouble() > 1.0 + EPSILON);
            boolean hasSquash = bodyScale.values().stream()
                    .anyMatch(vector -> vector.get(1).getAsDouble() < 1.0 - EPSILON);
            helper.assertTrue(hasStretch, clipName + " hat keinen Airborne-Stretch (Body-Scale-Y > 1)");
            helper.assertTrue(hasSquash, clipName + " hat keinen Squash (Body-Scale-Y < 1)");

            // Antizipations-Dip + Flugbogen auf der Root-Position.
            TreeMap<Double, JsonArray> rootPosition =
                    channelKeyframes(bones.getAsJsonObject("root").get("position"));
            boolean hasDip = rootPosition.values().stream()
                    .anyMatch(vector -> vector.get(1).getAsDouble() < -EPSILON);
            boolean hasAirTime = rootPosition.values().stream()
                    .anyMatch(vector -> vector.get(1).getAsDouble() > 1.0);
            helper.assertTrue(hasDip, clipName + " hat keinen Antizipations-/Landungs-Dip (Root-Y < 0)");
            helper.assertTrue(hasAirTime, clipName + " hebt nie ab (kein Root-Y-Bogen)");

            // Ohren/Schwanz-Followthrough braucht Lag + Overshoot + Settle (>= 4 Keys).
            for (String follower : List.of("earLeft", "earRight", "tail")) {
                TreeMap<Double, JsonArray> rotation =
                        channelKeyframes(bones.getAsJsonObject(follower).get("rotation"));
                helper.assertTrue(rotation.size() >= 4, clipName + "/" + follower
                        + " hat zu wenige Keys fuer Followthrough (" + rotation.size() + ")");
            }

            // Jeder Kanal: Zeiten in [0, Laenge], erster == letzter Key (nahtloser Loop).
            for (Map.Entry<String, JsonElement> bone : bones.entrySet()) {
                for (Map.Entry<String, JsonElement> channel : bone.getValue().getAsJsonObject().entrySet()) {
                    TreeMap<Double, JsonArray> frames = channelKeyframes(channel.getValue());
                    String tag = clipName + "/" + bone.getKey() + "/" + channel.getKey();
                    helper.assertTrue(frames.firstKey() >= 0 && frames.lastKey() <= length + EPSILON,
                            tag + ": Keyframe-Zeit ausserhalb 0.." + length);
                    helper.assertTrue(vectorsEqual(frames.firstEntry().getValue(),
                                    frames.lastEntry().getValue()),
                            tag + ": Loop-Naht springt (erster != letzter Key)");
                }
            }
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 3. Gait-Auswahl bricht keine Pose-Bruecken
    // ------------------------------------------------------------------

    /** Auch mit Gait-getriebenem Moving-Flag laufen Sitz-/Schlaf-Bruecken vollstaendig. */
    @GameTest(template = ARENA)
    public static void gait_driven_pose_never_breaks_bridges(GameTestHelper helper) {
        // Ein sprintender Gooby, der einschlaeft, muss beim Aufstehen erst WAKE_UP spielen.
        GoobyAnimationState poseState = new GoobyAnimationState();
        GoobyLocomotion locomotion = new GoobyLocomotion();
        long locomotionTick = 0;
        Gait sprint = Gait.IDLE;
        for (int index = 0; index < CONVERGENCE_TICKS; index++) {
            sprint = locomotion.update(locomotionTick++, GoobyLocomotion.RUN_ENTER_SPEED + 0.06);
        }
        helper.assertTrue(sprint == Gait.RUN, "Sprint-Tempo muss RUN waehlen");
        poseState.update(GoobyAnimationState.selectPose(sprint.isMoving(), false, false, false, false), 0);
        helper.assertTrue(poseState.stablePose() == GoobyAnimationState.Pose.HOP,
                "Sprint muss die Moving-Pose waehlen");

        poseState.update(GoobyAnimationState.selectPose(false, true, false, false, false), 1);
        helper.assertTrue(poseState.transition() == GoobyAnimationState.Transition.SLEEP_DOWN,
                "Moving -> SLEEP braucht sleep_down");
        poseState.update(GoobyAnimationState.selectPose(false, true, false, false, false), 20);
        helper.assertTrue(poseState.stablePose() == GoobyAnimationState.Pose.SLEEP,
                "sleep_down endet nicht im SLEEP-Loop");

        // Aufwachen direkt in den Sprint: WAKE_UP darf nicht uebersprungen werden.
        Gait wakeSprint = locomotion.update(locomotionTick++, GoobyLocomotion.RUN_ENTER_SPEED + 0.06);
        poseState.update(GoobyAnimationState.selectPose(wakeSprint.isMoving(), false, false, false, false), 21);
        helper.assertTrue(poseState.transition() == GoobyAnimationState.Transition.WAKE_UP,
                "SLEEP -> Sprint muss zuerst wake_up spielen");
        // Waehrend der Bruecke bremst der Gait auf WALK ab — sie darf nicht abschneiden.
        Gait slowed = Gait.RUN;
        for (int index = 0; index < 20; index++) {
            slowed = locomotion.update(locomotionTick++, 0.1);
        }
        helper.assertTrue(slowed == Gait.WALK, "Abbremsen auf 0.1 b/t muss in WALK enden");
        poseState.update(GoobyAnimationState.selectPose(true, false, false, false, false), 25);
        helper.assertTrue(poseState.transition() == GoobyAnimationState.Transition.WAKE_UP,
                "Gait-Wechsel hat die laufende wake_up-Bruecke abgeschnitten");
        poseState.update(GoobyAnimationState.selectPose(true, false, false, false, false), 40);
        helper.assertFalse(poseState.isTransitioning(), "wake_up endet nicht deterministisch");
        helper.assertTrue(poseState.stablePose() == GoobyAnimationState.Pose.HOP,
                "Nach wake_up uebernimmt nicht die Moving-Pose");

        // WALK <-> RUN ist ein reiner Clip-Wechsel innerhalb der HOP-Pose: keine Bruecke.
        poseState.update(GoobyAnimationState.selectPose(true, false, false, false, false), 41);
        helper.assertFalse(poseState.isTransitioning(),
                "WALK/RUN-Wechsel darf keine Pose-Bruecke ausloesen");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 4. Live-Messung: alle realen Speed-Modifier treffen ihren Gait
    // ------------------------------------------------------------------

    /** Eine Messphase: ein real benutzter Speed-Modifier und sein erwarteter Gait. */
    private record GaitPhase(double speedModifier, Gait expected, List<Double> trace) {
        private GaitPhase(double speedModifier, Gait expected) {
            this(speedModifier, expected, new ArrayList<>());
        }
    }

    /**
     * Am echten Pfadfolger gemessen, AI-isoliert (keine konkurrierenden Goals):
     * Stroll (1.0), Follow-Owner (1.15) und Follow-Parent (1.18) muessen WALK
     * bleiben — auch aus einem laufenden RUN-Zustand heraus (Totband-
     * Regression) —, Zulauf (1.25) und Panik (1.4) muessen RUN erreichen und
     * halten.
     */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 2400)
    public static void navigation_speeds_match_gait_thresholds(GameTestHelper helper) {
        for (int x = 0; x < 17; x++) {
            for (int z = 0; z < 17; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.GRASS_BLOCK);
            }
        }
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 8));
        // AI-Isolation: nur der Test treibt die Navigation. Stroll-/Sitz-/
        // Schlaf-Goals wuerden sonst eigene Pfade mit eigenen Tempi einstreuen
        // und die Messung verwaessern (Flake-Quelle).
        gooby.goalSelector.removeAllGoals(goal -> true);
        gooby.setPersistenceRequired();
        Vec3 west = helper.absoluteVec(new Vec3(2.5, 2.0, 8.5));
        Vec3 east = helper.absoluteVec(new Vec3(14.5, 2.0, 8.5));

        // Aufsteigend sortiert: so folgt keine WALK-Phase direkt auf eine
        // schnellere Phase, deren Auslauf die Nie-RUN-Pruefung verfaelschen koennte.
        List<GaitPhase> phases = List.of(
                new GaitPhase(1.0, Gait.WALK),   // GoobyRhythmStrollGoal
                new GaitPhase(1.15, Gait.WALK),  // GoobyFollowOwnerGoal
                new GaitPhase(1.18, Gait.WALK),  // GoobyFollowParentGoal
                new GaitPhase(1.25, Gait.RUN),   // Spieler-Zulauf / Sprinter-Chase
                new GaitPhase(1.4, Gait.RUN));   // GoobyWildPanicGoal

        GameTestSequence sequence = helper.startSequence();
        for (GaitPhase phase : phases) {
            sequence = sequence
                    // Alten Pfad kappen, damit die Phase sofort mit ihrem
                    // eigenen Modifier faehrt statt den vorigen auszufahren.
                    .thenExecute(() -> gooby.getNavigation().stop())
                    .thenExecuteFor(160, () -> {
                        keepNavigating(gooby, west, east, phase.speedModifier());
                        phase.trace().add(gooby.horizontalTickSpeed());
                    });
        }
        sequence.thenExecute(() -> assertGaitPhases(helper, phases)).thenSucceed();
    }

    private static void assertGaitPhases(GameTestHelper helper, List<GaitPhase> phases) {
        // Erst alle Messwerte loggen (Kalibrier-Referenz), dann pruefen.
        for (GaitPhase phase : phases) {
            List<Double> moving = movingSamples(phase.trace());
            helper.assertTrue(moving.size() >= 30, "Phase @" + phase.speedModifier()
                    + " lieferte zu wenige Bewegungs-Samples: " + moving.size());
            LOGGER.info("[GoobyLocomotion] modifier={} n={} p25={} p50={} p75={} p90={} b/t",
                    phase.speedModifier(), moving.size(), quantile(moving, 0.25),
                    quantile(moving, 0.50), quantile(moving, 0.75), quantile(moving, 0.90));
        }

        for (GaitPhase phase : phases) {
            double sustained = quantile(movingSamples(phase.trace()), 0.75);
            String label = "Modifier " + phase.speedModifier() + " (sustained " + sustained + " b/t)";
            if (phase.expected() == Gait.WALK) {
                helper.assertTrue(GoobyLocomotion.selectGait(Gait.IDLE, sustained) == Gait.WALK,
                        label + " klassifiziert nicht WALK (Schwellen "
                                + GoobyLocomotion.WALK_ENTER_SPEED + ".."
                                + GoobyLocomotion.RUN_ENTER_SPEED + ")");
                // Die komplette Phase inkl. Anlauf und Wenden: nie faelschlich RUN.
                GoobyLocomotion fresh = new GoobyLocomotion();
                long tick = 0;
                for (double sample : phase.trace()) {
                    helper.assertTrue(fresh.update(tick++, sample) != Gait.RUN,
                            label + " kippte faelschlich in RUN");
                }
                // Totband-Regression: selbst ein Gooby, der gerade noch rannte,
                // muss auf diesem Tempo wieder aus RUN herausfallen und draussen
                // bleiben — sonst haengt der Gait bistabil am Vorzustand.
                GoobyLocomotion fromRun = convergedAt(GoobyLocomotion.RUN_ENTER_SPEED + 0.06);
                helper.assertTrue(fromRun.gait() == Gait.RUN, "Testaufbau: RUN-Vorzustand fehlt");
                long runTick = CONVERGENCE_TICKS;
                boolean leftRun = false;
                for (double sample : phase.trace()) {
                    Gait gait = fromRun.update(runTick++, sample);
                    if (leftRun) {
                        helper.assertTrue(gait != Gait.RUN,
                                label + " ist bistabil: RUN kehrte ohne Run-Tempo zurueck");
                    } else if (gait != Gait.RUN) {
                        leftRun = true;
                    }
                }
                helper.assertTrue(leftRun, label + " haelt einen alten RUN-Zustand fest (Totband)");
            } else {
                helper.assertTrue(GoobyLocomotion.selectGait(Gait.WALK, sustained) == Gait.RUN,
                        label + " klassifiziert nicht RUN (Run-Enter "
                                + GoobyLocomotion.RUN_ENTER_SPEED + ")");
                GoobyLocomotion fresh = new GoobyLocomotion();
                long tick = 0;
                int runTicks = 0;
                int ticksSinceRun = 0;
                for (double sample : phase.trace()) {
                    Gait gait = fresh.update(tick++, sample);
                    if (gait == Gait.RUN || ticksSinceRun > 0) {
                        ticksSinceRun++;
                        if (gait == Gait.RUN) {
                            runTicks++;
                        }
                    }
                }
                helper.assertTrue(ticksSinceRun > 0, label + " erreicht nie RUN");
                // Wende-Dips (echtes Abbremsen) sind erlaubt, aber RUN muss der
                // dominante Zustand der Phase bleiben.
                helper.assertTrue(runTicks * 10 >= ticksSinceRun * 6,
                        label + " haelt RUN nicht: nur " + runTicks + "/" + ticksSinceRun
                                + " Ticks nach dem ersten RUN");
            }
        }
    }

    /** Ping-Pong zwischen zwei Wegpunkten; Sitz-/Schlaf-Zufaelle raeumen wir weg. */
    private static void keepNavigating(GoobyEntity gooby, Vec3 west, Vec3 east, double speedModifier) {
        gooby.setSitting(false);
        gooby.setInSittingPose(false);
        gooby.setGoobySleeping(false);
        if (gooby.getNavigation().isDone()) {
            Vec3 target = gooby.position().distanceToSqr(east) >= gooby.position().distanceToSqr(west)
                    ? east : west;
            gooby.getNavigation().moveTo(target.x, target.y, target.z, speedModifier);
        }
    }

    private static List<Double> movingSamples(List<Double> samples) {
        return samples.stream()
                .filter(speed -> speed > 0.005)
                .sorted()
                .toList();
    }

    /** Quantil einer aufsteigend sortierten Liste (0..1). */
    private static double quantile(List<Double> sorted, double q) {
        int index = Math.min(sorted.size() - 1, (int) Math.floor(sorted.size() * q));
        return sorted.get(index);
    }

    private GoobyLocomotionTests() {
    }
}
