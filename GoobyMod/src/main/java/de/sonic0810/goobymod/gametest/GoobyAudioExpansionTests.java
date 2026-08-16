package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.logging.LogUtils;
import de.sonic0810.goobymod.GoobyMod;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;
import org.slf4j.Logger;

/**
 * Audio-Polish-Wave: Ressourcen-Gates fuer die erweiterten Sound-Varianten.
 * Jede emotional haeufige Event-Familie besitzt mindestens drei klar
 * unterschiedliche Varianten; die Pools nutzen Gewichte plus sanften
 * Pitch-/Volume-Jitter. Die Tests parsen jede Ogg-Datei direkt aus dem
 * Runtime-Classpath (Magic, Vorbis-ID-Header, Kanaele, Samplerate, Dauer
 * ueber die Granule-Position) und beweisen, dass die Varianten nicht
 * bytegleich sind, dass sounds.json und die SoundEvent-Registry vollstaendig
 * synchron laufen und dass die drei Pfeifmodi bewusst distinct bleiben.
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyAudioExpansionTests {
    private static final Logger LOGGER = LogUtils.getLogger();
    private static final String ARENA = "arena";

    private static final String SOUNDS_JSON = "assets/goobymod/sounds.json";
    private static final String SOUND_PREFIX = "goobymod:entity/gooby/";
    private static final String CLIP_DIR = "assets/goobymod/sounds/entity/gooby/";

    /** Emotional haeufige Events: Pool muss >= 3 Varianten anbieten. */
    private static final List<String> FREQUENT_EVENTS = List.of(
            "entity.gooby.squeak", "entity.gooby.purr", "entity.gooby.boing",
            "entity.gooby.plop", "entity.gooby.munch", "entity.gooby.snore",
            "entity.gooby.ambient", "entity.gooby.sad_whimper", "entity.gooby.yawn",
            "entity.gooby.sniff", "entity.gooby.ambient_neutral",
            "entity.gooby.ambient_happy", "entity.gooby.ambient_sleepy",
            "entity.gooby.brush", "entity.gooby.whine_hungry",
            "entity.gooby.lonely_sigh", "entity.gooby.shake",
            "entity.gooby.tier_up_jingle", "entity.gooby.trick_chime",
            "entity.gooby.flop_thud", "entity.gooby.hutch_rustle",
            "entity.gooby.hutch_creak", "entity.gooby.baby_squeak",
            "entity.gooby.nuzzle", "entity.gooby.dress_up",
            "entity.gooby.wild_call", "entity.gooby.chirp_social",
            "entity.gooby.sniff_long", "entity.gooby.map_rustle");

    /** Bewusst einvariantige Sounds (Loop-Nahtlosigkeit bzw. Lern-Signatur). */
    private static final List<String> SINGLE_EVENTS = List.of(
            "entity.gooby.purr_loop", "entity.gooby.whistle_wander",
            "entity.gooby.whistle_follow", "entity.gooby.whistle_stay",
            "entity.gooby.snuggle_purr_long");

    /** Pools ohne Jitter-Pflicht: fixierte Groesse bzw. bewusster Deep-Pitch. */
    private static final Set<String> JITTER_EXEMPT_EVENTS =
            Set.of("entity.gooby.alarm_squeak", "entity.gooby.whistle_denied");

    private static final double DURATION_MIN = 0.14;
    private static final double DURATION_MAX = 5.0;
    private static final int SIZE_MIN = 2_000;
    private static final int SIZE_MAX = 150_000;

    // ACHTUNG: Diese Jitter-Bounds spiegeln scripts/gen_sounds.py
    // (POOL_PITCH_MIN/MAX, POOL_VOLUME_MIN/MAX) und docs/AUDIO.md --
    // immer alle drei Stellen zusammen aendern, sonst driften die Gates.
    private static final double POOL_PITCH_MIN = 0.94;
    private static final double POOL_PITCH_MAX = 1.06;
    private static final double POOL_VOLUME_MIN = 0.90;
    private static final double POOL_VOLUME_MAX = 1.0;

    // ------------------------------------------------------------------
    // Helfer
    // ------------------------------------------------------------------

    private record SoundRef(String file, int weight, Double pitch, Double volume) {
    }

    private record OggInfo(int channels, int sampleRate, double duration, int size) {
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyAudioExpansionTests.class.getClassLoader()
                .getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8))
                    .getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path
                    + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    private static byte[] loadClipBytes(GameTestHelper helper, String file) {
        String path = CLIP_DIR + file + ".ogg";
        try (InputStream stream = GoobyAudioExpansionTests.class.getClassLoader()
                .getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Sounddatei fehlt im Classpath: " + path);
            return stream.readAllBytes();
        } catch (IOException exception) {
            helper.fail("Sounddatei nicht lesbar: " + path + " (" + exception.getMessage() + ")");
            return new byte[0];
        }
    }

    /** sounds.json-Pools als Map Event -> Varianten-Referenzen. */
    private static Map<String, List<SoundRef>> soundPools(GameTestHelper helper) {
        JsonObject sounds = loadAssetJson(helper, SOUNDS_JSON);
        Map<String, List<SoundRef>> pools = new LinkedHashMap<>();
        for (var entry : sounds.entrySet()) {
            JsonObject definition = entry.getValue().getAsJsonObject();
            helper.assertTrue(definition.has("subtitle"),
                    "Sound ohne Subtitle-Key: " + entry.getKey());
            List<SoundRef> refs = new ArrayList<>();
            for (JsonElement element : definition.getAsJsonArray("sounds")) {
                String name;
                int weight = 1;
                Double pitch = null;
                Double volume = null;
                if (element.isJsonPrimitive()) {
                    name = element.getAsString();
                } else {
                    JsonObject sound = element.getAsJsonObject();
                    name = sound.get("name").getAsString();
                    if (sound.has("weight")) {
                        weight = sound.get("weight").getAsInt();
                    }
                    if (sound.has("pitch")) {
                        pitch = sound.get("pitch").getAsDouble();
                    }
                    if (sound.has("volume")) {
                        volume = sound.get("volume").getAsDouble();
                    }
                }
                helper.assertTrue(name.startsWith(SOUND_PREFIX),
                        entry.getKey() + " referenziert fremden Sound: " + name);
                refs.add(new SoundRef(name.substring(SOUND_PREFIX.length()),
                        weight, pitch, volume));
            }
            helper.assertTrue(!refs.isEmpty(), entry.getKey() + " hat einen leeren Pool");
            pools.put(entry.getKey(), refs);
        }
        return pools;
    }

    /**
     * Minimaler Ogg-Parser: prueft Magic + Version jeder Page, liest den
     * Vorbis-ID-Header (Kanaele, Samplerate) und leitet die Dauer aus der
     * hoechsten Granule-Position ab.
     */
    private static OggInfo parseOgg(GameTestHelper helper, String file, byte[] data) {
        helper.assertTrue(data.length > 58, file + ": Datei zu klein fuer Ogg/Vorbis");
        long lastGranule = 0;
        byte[] firstPayload = null;
        int offset = 0;
        while (offset + 27 <= data.length) {
            helper.assertTrue(data[offset] == 'O' && data[offset + 1] == 'g'
                            && data[offset + 2] == 'g' && data[offset + 3] == 'S',
                    file + ": OggS-Magic fehlt bei Offset " + offset);
            helper.assertTrue(data[offset + 4] == 0,
                    file + ": unbekannte Ogg-Version " + data[offset + 4]);
            long granule = ByteBuffer.wrap(data, offset + 6, 8)
                    .order(ByteOrder.LITTLE_ENDIAN).getLong();
            if (granule > 0) {
                lastGranule = Math.max(lastGranule, granule);
            }
            int segments = data[offset + 26] & 0xFF;
            int payloadLength = 0;
            for (int i = 0; i < segments; i++) {
                payloadLength += data[offset + 27 + i] & 0xFF;
            }
            int payloadOffset = offset + 27 + segments;
            helper.assertTrue(payloadOffset + payloadLength <= data.length,
                    file + ": Ogg-Page ragt ueber das Dateiende hinaus");
            if (firstPayload == null) {
                firstPayload = new byte[payloadLength];
                System.arraycopy(data, payloadOffset, firstPayload, 0, payloadLength);
            }
            offset = payloadOffset + payloadLength;
        }
        helper.assertTrue(offset == data.length, file + ": Muell hinter letzter Ogg-Page");
        helper.assertTrue(firstPayload != null && firstPayload.length >= 16
                        && firstPayload[0] == 1 && firstPayload[1] == 'v'
                        && firstPayload[2] == 'o' && firstPayload[3] == 'r'
                        && firstPayload[4] == 'b' && firstPayload[5] == 'i'
                        && firstPayload[6] == 's',
                file + ": Vorbis-ID-Header fehlt");
        int vorbisVersion = ByteBuffer.wrap(firstPayload, 7, 4)
                .order(ByteOrder.LITTLE_ENDIAN).getInt();
        helper.assertTrue(vorbisVersion == 0,
                file + ": Vorbis-Version " + vorbisVersion + " statt 0");
        int channels = firstPayload[11] & 0xFF;
        int sampleRate = ByteBuffer.wrap(firstPayload, 12, 4)
                .order(ByteOrder.LITTLE_ENDIAN).getInt();
        helper.assertTrue(sampleRate > 0, file + ": Samplerate unlesbar");
        return new OggInfo(channels, sampleRate,
                lastGranule / (double) sampleRate, data.length);
    }

    private static String familyOf(String file) {
        return file.replaceAll("\\d+$", "");
    }

    private static Set<String> uniqueFiles(Map<String, List<SoundRef>> pools) {
        Set<String> files = new TreeSet<>();
        for (List<SoundRef> refs : pools.values()) {
            for (SoundRef ref : refs) {
                files.add(ref.file());
            }
        }
        return files;
    }

    // ------------------------------------------------------------------
    // sounds.json <-> Registry
    // ------------------------------------------------------------------

    /** Jeder sounds.json-Eintrag ist registriert — und umgekehrt (beidseitig). */
    @GameTest(template = ARENA)
    public static void sounds_json_and_registry_fully_in_sync(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        Set<String> registered = new TreeSet<>();
        for (ResourceLocation id : BuiltInRegistries.SOUND_EVENT.keySet()) {
            if (GoobyMod.MODID.equals(id.getNamespace())) {
                registered.add(id.getPath());
            }
        }
        Set<String> defined = new TreeSet<>(pools.keySet());

        Set<String> unregistered = new TreeSet<>(defined);
        unregistered.removeAll(registered);
        helper.assertTrue(unregistered.isEmpty(),
                "sounds.json-Eintraege ohne SoundEvent-Registrierung: " + unregistered);

        Set<String> undefined = new TreeSet<>(registered);
        undefined.removeAll(defined);
        helper.assertTrue(undefined.isEmpty(),
                "Registrierte SoundEvents ohne sounds.json-Pool: " + undefined);

        LOGGER.info("[GoobyAudio] Registry-Sync: {} Events beidseitig vollstaendig",
                registered.size());
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Varianten-Kardinalitaeten
    // ------------------------------------------------------------------

    /**
     * Haeufige Familien >= 3 Varianten; Loop- und Pfeif-Sounds bleiben bewusst
     * einvariantig; alarm_squeak bleibt auf 2 fixiert (Gate in
     * {@code GoobyGameTests.awareness_assets_complete}).
     */
    @GameTest(template = ARENA)
    public static void frequent_families_ship_three_plus_variants(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        for (String event : FREQUENT_EVENTS) {
            List<SoundRef> refs = pools.get(event);
            helper.assertTrue(refs != null && refs.size() >= 3,
                    event + " braucht >= 3 Varianten, hat "
                            + (refs == null ? 0 : refs.size()));
        }
        for (String event : SINGLE_EVENTS) {
            List<SoundRef> refs = pools.get(event);
            helper.assertTrue(refs != null && refs.size() == 1,
                    event + " muss bewusst einvariantig bleiben");
        }
        List<SoundRef> alarm = pools.get("entity.gooby.alarm_squeak");
        helper.assertTrue(alarm != null && alarm.size() == 2,
                "alarm_squeak ist per Awareness-Gate auf exakt 2 Varianten fixiert");

        int variants = uniqueFiles(pools).size();
        LOGGER.info("[GoobyAudio] {} Events, {} eindeutige Clips, {} Familien >= 3 Varianten",
                pools.size(), variants, FREQUENT_EVENTS.size());
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Datei-Gesundheit: Magic, Kanaele, Samplerate, Dauer, Groesse
    // ------------------------------------------------------------------

    /** Jeder referenzierte Clip existiert und ist gesundes Mono-44.1-kHz-Vorbis. */
    @GameTest(template = ARENA)
    public static void clips_are_mono_44khz_healthy_ogg(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        for (String file : uniqueFiles(pools)) {
            OggInfo info = parseOgg(helper, file, loadClipBytes(helper, file));
            helper.assertTrue(info.channels() == 1,
                    file + ": " + info.channels() + " Kanaele statt mono");
            helper.assertTrue(info.sampleRate() == 44100,
                    file + ": Samplerate " + info.sampleRate() + " statt 44100");
        }
        helper.succeed();
    }

    /** Dauer (aus Granule-Position) und Dateigroesse bleiben in sinnvollen Grenzen. */
    @GameTest(template = ARENA)
    public static void clip_durations_and_sizes_within_bounds(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        double shortest = Double.MAX_VALUE;
        double longest = 0;
        long totalBytes = 0;
        for (String file : uniqueFiles(pools)) {
            OggInfo info = parseOgg(helper, file, loadClipBytes(helper, file));
            double min = DURATION_MIN;
            double max = DURATION_MAX;
            if ("purr_loop".equals(file)) {
                min = 1.9;
                max = 2.1;
            } else if ("snuggle_purr_long".equals(file)) {
                min = 3.9;
                max = 4.5;
            }
            helper.assertTrue(info.duration() >= min && info.duration() <= max,
                    file + ": Dauer " + info.duration() + "s ausserhalb ["
                            + min + ", " + max + "]");
            helper.assertTrue(info.size() >= SIZE_MIN && info.size() <= SIZE_MAX,
                    file + ": Groesse " + info.size() + "B ausserhalb ["
                            + SIZE_MIN + ", " + SIZE_MAX + "]");
            shortest = Math.min(shortest, info.duration());
            longest = Math.max(longest, info.duration());
            totalBytes += info.size();
        }
        LOGGER.info("[GoobyAudio] Clip-Dauern {}s..{}s, Gesamtgroesse {} KiB",
                String.format("%.2f", shortest), String.format("%.2f", longest),
                totalBytes / 1024);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Varianten wirklich unterschiedlich
    // ------------------------------------------------------------------

    /**
     * Varianten einer Familie duerfen niemals bytegleiche Kopien sein.
     * Paarweiser {@link Arrays#equals(byte[], byte[])}-Vergleich statt
     * 32-bit-Hashes: eine Hash-Kollision kann kein Duplikat maskieren.
     */
    @GameTest(template = ARENA)
    public static void variants_are_not_byte_identical(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        Map<String, List<String>> families = new HashMap<>();
        for (String file : uniqueFiles(pools)) {
            families.computeIfAbsent(familyOf(file), key -> new ArrayList<>()).add(file);
        }
        for (var family : families.entrySet()) {
            List<String> members = family.getValue();
            List<byte[]> payloads = new ArrayList<>(members.size());
            for (String file : members) {
                payloads.add(loadClipBytes(helper, file));
            }
            for (int left = 0; left < payloads.size(); left++) {
                for (int right = left + 1; right < payloads.size(); right++) {
                    helper.assertTrue(!Arrays.equals(payloads.get(left), payloads.get(right)),
                            "Familie " + family.getKey() + ": " + members.get(left)
                                    + " und " + members.get(right) + " sind bytegleich");
                }
            }
        }
        LOGGER.info("[GoobyAudio] {} Familien mit ausschliesslich unikaten Varianten",
                families.size());
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Gewichte + Jitter
    // ------------------------------------------------------------------

    /** Multi-Varianten-Pools nutzen Gewichte und sanften Pitch-/Volume-Jitter. */
    @GameTest(template = ARENA)
    public static void pools_apply_weights_and_gentle_jitter(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        for (var entry : pools.entrySet()) {
            String event = entry.getKey();
            List<SoundRef> refs = entry.getValue();
            if (refs.size() < 3 || JITTER_EXEMPT_EVENTS.contains(event)) {
                continue;
            }
            boolean weighted = false;
            boolean jittered = false;
            for (SoundRef ref : refs) {
                helper.assertTrue(ref.weight() >= 1 && ref.weight() <= 8,
                        event + ": Gewicht " + ref.weight() + " ausserhalb [1, 8]");
                if (ref.weight() > 1) {
                    weighted = true;
                }
                if (ref.pitch() != null) {
                    jittered = true;
                    helper.assertTrue(ref.pitch() >= POOL_PITCH_MIN && ref.pitch() <= POOL_PITCH_MAX,
                            event + ": Pitch-Jitter " + ref.pitch() + " ausserhalb ["
                                    + POOL_PITCH_MIN + ", " + POOL_PITCH_MAX + "]");
                }
                if (ref.volume() != null) {
                    jittered = true;
                    helper.assertTrue(ref.volume() >= POOL_VOLUME_MIN && ref.volume() <= POOL_VOLUME_MAX,
                            event + ": Volume-Jitter " + ref.volume() + " ausserhalb ["
                                    + POOL_VOLUME_MIN + ", " + POOL_VOLUME_MAX + "]");
                }
            }
            helper.assertTrue(weighted, event + ": Pool ohne Gewichtung");
            helper.assertTrue(jittered, event + ": Pool ohne Pitch-/Volume-Jitter");
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Pfeifmodi bleiben distinct
    // ------------------------------------------------------------------

    /** Die drei lernbaren Pfeifmodi bleiben einvariantig und paarweise distinct. */
    @GameTest(template = ARENA)
    public static void whistle_modes_stay_distinct(GameTestHelper helper) {
        Map<String, List<SoundRef>> pools = soundPools(helper);
        List<String> whistles = List.of("entity.gooby.whistle_wander",
                "entity.gooby.whistle_follow", "entity.gooby.whistle_stay");
        List<byte[]> payloads = new ArrayList<>(whistles.size());
        for (String event : whistles) {
            List<SoundRef> refs = pools.get(event);
            helper.assertTrue(refs != null && refs.size() == 1,
                    event + " muss genau einen lernbaren Klang besitzen");
            payloads.add(loadClipBytes(helper, refs.getFirst().file()));
        }
        for (int left = 0; left < payloads.size(); left++) {
            for (int right = left + 1; right < payloads.size(); right++) {
                helper.assertTrue(!Arrays.equals(payloads.get(left), payloads.get(right)),
                        whistles.get(left) + " und " + whistles.get(right)
                                + " teilen sich dieselbe Sounddatei");
            }
        }

        // whistle_denied bleibt der bewusst heruntergepitchte Squeak-Pool.
        for (SoundRef ref : pools.get("entity.gooby.whistle_denied")) {
            helper.assertTrue(ref.file().startsWith("squeak"),
                    "whistle_denied muss den Squeak-Pool wiederverwenden: " + ref.file());
            helper.assertTrue(ref.pitch() != null && ref.pitch() <= 0.7,
                    "whistle_denied braucht deutlichen Deep-Pitch, hat " + ref.pitch());
        }
        helper.succeed();
    }
}
