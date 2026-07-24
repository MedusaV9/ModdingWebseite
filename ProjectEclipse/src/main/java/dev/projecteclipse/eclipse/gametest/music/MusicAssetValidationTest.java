package dev.projecteclipse.eclipse.gametest.music;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * V5-FIXGUARD / EVAL-SAT-F #1 — the music asset regression guard planned as C19 §4 and
 * never landed. The original "total silence" launch bug shipped because corrupt music
 * assets (Theora video in an .ogg, 96 kHz generation-API downloads) passed unnoticed;
 * {@code tools/music/validate_oggs.py} guards commits but nothing automated ran in CI.
 * This gametest ports that script's Ogg header checks to Java (page/identification
 * headers only — no audio decode) and asserts, for every {@code music.*} entry in
 * {@code assets/eclipse/sounds.json} that resolves into THIS jar (the {@code eclipse:}
 * namespace — {@code minecraft:} rows like the {@code music.xbox_era} vanilla calm/hal
 * tracks live in Mojang's asset index, not here):
 *
 * <ul>
 *   <li>the referenced {@code assets/eclipse/sounds/<path>.ogg} exists in the jar;</li>
 *   <li>it contains EXACTLY one logical Ogg stream, codec Vorbis — Theora ({@code
 *       \x80theora}) and Opus ({@code OpusHead}) streams are called out by name because
 *       the sound engine silently fails on both;</li>
 *   <li>the Vorbis identification header says sample rate ≤ {@value #MAX_SAMPLE_RATE} Hz
 *       (higher = raw generation-API download the engine may refuse) and stereo;</li>
 *   <li>the file is within the {@value #SIZE_BUDGET_BYTES}-byte budget
 *       (treblo_generate's post-process contract).</li>
 * </ul>
 *
 * <p>Resources are read through the mod classloader, so the test validates whatever is
 * actually packed — dev resources in a gametest run, the real jar in a production-style
 * run.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class MusicAssetValidationTest {
    static final int MAX_SAMPLE_RATE = 48_000;
    static final int REQUIRED_CHANNELS = 2;
    /** Keep in sync with tools/music/treblo_generate.py SIZE_BUDGET_BYTES. */
    static final int SIZE_BUDGET_BYTES = 2_500_000;

    private MusicAssetValidationTest() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void everyMusicEntryIsPlayableVorbis(GameTestHelper helper) {
        Map<String, List<String>> entries = musicResourcesFromSoundsJson();
        helper.assertTrue(!entries.isEmpty(), "sounds.json declares music.* events");
        List<String> failures = new ArrayList<>();
        int checked = 0;
        for (Map.Entry<String, List<String>> event : entries.entrySet()) {
            for (String resourcePath : event.getValue()) {
                checked++;
                for (String error : validateOgg(resourcePath)) {
                    failures.add(event.getKey() + " (" + resourcePath + "): " + error);
                }
            }
        }
        helper.assertTrue(checked > 0, "at least one eclipse-namespace music file checked");
        helper.assertTrue(failures.isEmpty(), "music assets valid: " + String.join(" | ", failures));
        helper.succeed();
    }

    // ------------------------------------------------------------------ sounds.json

    /**
     * Every jar resource path referenced by a {@code music.*} sounds.json entry in the
     * {@code eclipse:} namespace, keyed by event id (the python script's
     * {@code music_files_from_sounds_json}).
     */
    static Map<String, List<String>> musicResourcesFromSoundsJson() {
        JsonObject sounds = JsonParser
                .parseString(readResourceText("/assets/eclipse/sounds.json"))
                .getAsJsonObject();
        Map<String, List<String>> out = new LinkedHashMap<>();
        for (Map.Entry<String, JsonElement> event : sounds.entrySet()) {
            if (!event.getKey().startsWith("music.")) {
                continue;
            }
            JsonObject definition = event.getValue().getAsJsonObject();
            if (!definition.has("sounds")) {
                continue;
            }
            for (JsonElement entry : definition.getAsJsonArray("sounds")) {
                String name = entry.isJsonObject()
                        ? entry.getAsJsonObject().get("name").getAsString()
                        : entry.getAsString();
                String namespace = name.contains(":") ? name.substring(0, name.indexOf(':')) : "minecraft";
                if (!EclipseMod.MOD_ID.equals(namespace)) {
                    continue; // vanilla rows (music.xbox_era) live in Mojang's asset index
                }
                String rel = name.substring(name.indexOf(':') + 1);
                out.computeIfAbsent(event.getKey(), key -> new ArrayList<>())
                        .add("/assets/eclipse/sounds/" + rel + ".ogg");
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ ogg validation

    /** Validates one jar OGG; returns human-readable violations (empty = playable). */
    static List<String> validateOgg(String resourcePath) {
        byte[] data;
        try (InputStream stream = MusicAssetValidationTest.class.getResourceAsStream(resourcePath)) {
            if (stream == null) {
                return List.of("missing jar resource");
            }
            data = stream.readAllBytes();
        } catch (IOException e) {
            return List.of("unreadable: " + e.getMessage());
        }
        List<String> errors = new ArrayList<>();
        if (data.length > SIZE_BUDGET_BYTES) {
            errors.add(data.length + " bytes exceeds the " + SIZE_BUDGET_BYTES + "-byte budget");
        }
        List<byte[]> bosPrefixes;
        try {
            bosPrefixes = parseOggBosPrefixes(data);
        } catch (IllegalArgumentException e) {
            errors.add(e.getMessage());
            return errors;
        }
        if (bosPrefixes.isEmpty()) {
            errors.add("no Ogg streams found");
            return errors;
        }
        List<String> codecs = new ArrayList<>();
        for (byte[] prefix : bosPrefixes) {
            codecs.add(codecName(prefix));
        }
        if (bosPrefixes.size() != 1 || !"vorbis".equals(codecs.get(0))) {
            errors.add("expected exactly one Vorbis stream, found: " + String.join(", ", codecs));
            return errors;
        }
        byte[] id = bosPrefixes.get(0);
        if (id.length < 16) {
            errors.add("truncated Vorbis identification header (" + id.length + " bytes)");
            return errors;
        }
        int channels = id[11] & 0xFF;
        long sampleRate = readLeUint32(id, 12);
        if (sampleRate > MAX_SAMPLE_RATE) {
            errors.add("sample rate " + sampleRate + " Hz > " + MAX_SAMPLE_RATE
                    + " Hz (raw generation-API download?)");
        }
        if (channels != REQUIRED_CHANNELS) {
            errors.add(channels + " channel(s), expected stereo");
        }
        return errors;
    }

    /**
     * Walks every Ogg page and returns the first-packet prefix (16 bytes) of each BOS
     * (beginning-of-stream) page — one per logical stream. Scans the WHOLE file so a
     * chained/concatenated second stream (another corruption mode) is counted too.
     *
     * @throws IllegalArgumentException on a broken page capture pattern
     */
    static List<byte[]> parseOggBosPrefixes(byte[] data) {
        List<byte[]> streams = new ArrayList<>();
        int offset = 0;
        while (offset + 27 <= data.length) {
            if (data[offset] != 'O' || data[offset + 1] != 'g' || data[offset + 2] != 'g'
                    || data[offset + 3] != 'S') {
                throw new IllegalArgumentException("bad Ogg capture pattern at byte " + offset);
            }
            int headerType = data[offset + 5] & 0xFF;
            int segments = data[offset + 26] & 0xFF;
            if (offset + 27 + segments > data.length) {
                throw new IllegalArgumentException("truncated Ogg segment table at byte " + offset);
            }
            int bodyLength = 0;
            for (int i = 0; i < segments; i++) {
                bodyLength += data[offset + 27 + i] & 0xFF;
            }
            int bodyStart = offset + 27 + segments;
            if ((headerType & 0x02) != 0) { // BOS page: body starts with the codec id header
                int prefixLength = Math.min(16, Math.max(0, data.length - bodyStart));
                byte[] prefix = new byte[prefixLength];
                System.arraycopy(data, bodyStart, prefix, 0, prefixLength);
                streams.add(prefix);
            }
            offset = bodyStart + bodyLength;
        }
        return streams;
    }

    private static String codecName(byte[] prefix) {
        if (startsWith(prefix, new byte[] {0x01, 'v', 'o', 'r', 'b', 'i', 's'})) {
            return "vorbis";
        }
        if (startsWith(prefix, new byte[] {(byte) 0x80, 't', 'h', 'e', 'o', 'r', 'a'})) {
            return "THEORA VIDEO";
        }
        if (startsWith(prefix, new byte[] {'O', 'p', 'u', 's', 'H', 'e', 'a', 'd'})) {
            return "OPUS";
        }
        return "unknown";
    }

    private static boolean startsWith(byte[] data, byte[] magic) {
        if (data.length < magic.length) {
            return false;
        }
        for (int i = 0; i < magic.length; i++) {
            if (data[i] != magic[i]) {
                return false;
            }
        }
        return true;
    }

    private static long readLeUint32(byte[] data, int offset) {
        return ((data[offset] & 0xFFL)
                | (data[offset + 1] & 0xFFL) << 8
                | (data[offset + 2] & 0xFFL) << 16
                | (data[offset + 3] & 0xFFL) << 24);
    }

    private static String readResourceText(String resourcePath) {
        try (InputStream stream = MusicAssetValidationTest.class.getResourceAsStream(resourcePath)) {
            if (stream == null) {
                throw new UncheckedIOException(new IOException("missing jar resource " + resourcePath));
            }
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
