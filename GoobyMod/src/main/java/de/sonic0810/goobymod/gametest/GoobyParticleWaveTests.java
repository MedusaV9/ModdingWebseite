package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.authlib.GameProfile;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyTrick;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import javax.imageio.ImageIO;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Partikel-/Feedback-Wave: Konfetti, Fellfussel und Musiknoten.
 *
 * <p>Abgedeckt: der komplette Registry↔JSON↔PNG-Vertrag (jeder registrierte
 * goobymod-Partikeltyp besitzt ein Partikel-JSON, jede Frame-Referenz liegt
 * im goobymod-Namespace und loest zu einer PNG auf, Mindest-Framezahlen,
 * keine Duplikate, keine verwaisten JSONs oder Frames), Frame-Invarianten
 * (16x16 RGBA, transparenter Rand, Alpha-Coverage-Band, Tint-Helligkeit der
 * weissen Konfetti-/Noten-Sprites, monotones Aufloesen der Fussel-Frames,
 * paarweise verschiedene Varianten), die serverseitigen Trigger mit festen
 * Low-Count-Budgets und Anti-Spam-Cooldowns (Tier-Up- und Trick-Konfetti
 * erst nach VOLLENDETEM Clip, Streichel-Noten-Cooldown, Buersten-Cooldown,
 * Landungs-Fussel) sowie der Dedicated-Server-Vertrag: die Common-Klassen
 * referenzieren die client/particle-Klassen nachweislich NIE.</p>
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyParticleWaveTests {
    private static final String ARENA = "arena";

    private static final String PARTICLE_JSON_DIR = "assets/goobymod/particles/";
    private static final String PARTICLE_TEXTURE_DIR = "assets/goobymod/textures/particle/";
    private static final int SPRITE_SIZE = 16;
    private static final double COVERAGE_MIN = 0.03;
    private static final double COVERAGE_MAX = 0.70;
    private static final int TINT_MIN_AVG = 190;

    /** Registrierte Partikel -> Mindest-Framezahl (Feedback-Wave: >1 Variante). */
    private static final Map<String, Integer> EXPECTED_PARTICLES = Map.of(
            "zzz", 1, "heart_gold", 1, "paw_print", 1,
            "confetti", 4, "fluff_puff", 4, "music_note", 2);

    /** Sprites dieser Wave: nur fuer sie gilt der strikte Transparenz-Rand
     *  (die Legacy-Sprites wie paw_print malen historisch bis an die Kante). */
    private static final Set<String> WAVE_PARTICLES = Set.of("confetti", "fluff_puff", "music_note");

    // ------------------------------------------------------------------
    // Helfer
    // ------------------------------------------------------------------

    private static FakePlayer fakePlayer(GameTestHelper helper, String name) {
        return FakePlayerFactory.get(helper.getLevel(),
                new GameProfile(UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)), name));
    }

    private static void placeFloor(GameTestHelper helper) {
        for (int x = 0; x < 5; x++) {
            for (int z = 0; z < 5; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.DIRT);
            }
        }
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyParticleWaveTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    private static boolean resourceExists(String path) {
        return GoobyParticleWaveTests.class.getClassLoader().getResource(path) != null;
    }

    private static byte[] resourceBytes(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyParticleWaveTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Ressource fehlt im Runtime-Classpath: " + path);
            return stream.readAllBytes();
        } catch (IOException exception) {
            helper.fail("Ressource nicht lesbar: " + path + " (" + exception.getMessage() + ")");
            return new byte[0];
        }
    }

    /** Alle Frame-Referenzen eines Partikel-JSONs als Texturpfad-Suffixe. */
    private static List<String> frameRefs(GameTestHelper helper, String particleName) {
        JsonObject json = loadAssetJson(helper, PARTICLE_JSON_DIR + particleName + ".json");
        helper.assertTrue(json.has("textures") && json.get("textures").isJsonArray(),
                particleName + ".json: 'textures'-Liste fehlt");
        JsonArray textures = json.getAsJsonArray("textures");
        helper.assertTrue(!textures.isEmpty(), particleName + ".json: 'textures' ist leer");
        List<String> refs = new ArrayList<>();
        for (JsonElement element : textures) {
            refs.add(element.getAsString());
        }
        return refs;
    }

    private static BufferedImage readSprite(GameTestHelper helper, String texturePath) {
        try (InputStream stream = GoobyParticleWaveTests.class.getClassLoader()
                .getResourceAsStream(texturePath)) {
            helper.assertTrue(stream != null, "Partikel-Textur fehlt: " + texturePath);
            BufferedImage image = ImageIO.read(stream);
            helper.assertTrue(image != null, "PNG nicht dekodierbar: " + texturePath);
            return image;
        } catch (IOException exception) {
            helper.fail("Partikel-Textur nicht lesbar: " + texturePath + " (" + exception.getMessage() + ")");
            return new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
        }
    }

    private static int opaquePixels(BufferedImage image) {
        int count = 0;
        for (int y = 0; y < image.getHeight(); y++) {
            for (int x = 0; x < image.getWidth(); x++) {
                if ((image.getRGB(x, y) >>> 24) >= 8) {
                    count++;
                }
            }
        }
        return count;
    }

    private static boolean containsAscii(byte[] haystack, String needle) {
        byte[] target = needle.getBytes(StandardCharsets.US_ASCII);
        outer:
        for (int i = 0; i <= haystack.length - target.length; i++) {
            for (int j = 0; j < target.length; j++) {
                if (haystack[i + j] != target[j]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // 1. Registry ↔ JSON ↔ PNG
    // ------------------------------------------------------------------

    /**
     * Jeder registrierte goobymod-Partikeltyp hat ein JSON, jede Referenz
     * liegt im eigenen Namespace und loest zu einer PNG auf; Framezahlen,
     * Duplikat-, Orphan- und Fremd-Asset-Verbote inklusive.
     */
    @GameTest(template = ARENA)
    public static void particle_registry_json_texture_contract(GameTestHelper helper) {
        Set<String> registered = new TreeSet<>();
        for (ResourceLocation key : BuiltInRegistries.PARTICLE_TYPE.keySet()) {
            if (GoobyMod.MODID.equals(key.getNamespace())) {
                registered.add(key.getPath());
            }
        }
        helper.assertTrue(registered.equals(new TreeSet<>(EXPECTED_PARTICLES.keySet())),
                "Partikel-Registry driftet von der Testliste ab: " + registered
                        + " != " + new TreeSet<>(EXPECTED_PARTICLES.keySet()));

        for (Map.Entry<String, Integer> expected : EXPECTED_PARTICLES.entrySet()) {
            String name = expected.getKey();
            List<String> refs = frameRefs(helper, name);
            helper.assertTrue(refs.size() >= expected.getValue(),
                    name + ".json: nur " + refs.size() + " Frames, erwartet >= " + expected.getValue());
            helper.assertTrue(refs.size() == new TreeSet<>(refs).size(),
                    name + ".json: doppelte Frame-Referenzen: " + refs);
            for (String ref : refs) {
                ResourceLocation location = ResourceLocation.tryParse(ref);
                helper.assertTrue(location != null, name + ".json: unparsbare Referenz '" + ref + "'");
                // Negativ: keine fremden Assets — alles bleibt im Mod-Namespace.
                helper.assertTrue(GoobyMod.MODID.equals(location.getNamespace()),
                        name + ".json: Fremd-Namespace-Referenz '" + ref + "'");
                helper.assertTrue(resourceExists(PARTICLE_TEXTURE_DIR + location.getPath() + ".png"),
                        name + ".json: referenzierte Textur fehlt: " + location.getPath() + ".png");
            }
        }

        // Negativ: ein Frame HINTER dem Listenende darf nicht existieren —
        // sonst laege eine verwaiste Textur neben der JSON-Liste.
        for (String name : new String[] {"confetti", "fluff_puff", "music_note"}) {
            int frames = frameRefs(helper, name).size();
            helper.assertFalse(resourceExists(PARTICLE_TEXTURE_DIR + name + "_" + frames + ".png"),
                    "Verwaister Frame ausserhalb der JSON-Liste: " + name + "_" + frames + ".png");
        }

        // Negativ: kein verwaistes Partikel-JSON ohne Registry-Eintrag (im
        // Dev-Lauf liegen die Ressourcen als Verzeichnis vor und sind listbar).
        URL directory = GoobyParticleWaveTests.class.getClassLoader()
                .getResource(PARTICLE_JSON_DIR.substring(0, PARTICLE_JSON_DIR.length() - 1));
        if (directory != null && "file".equals(directory.getProtocol())) {
            try {
                File[] files = new File(directory.toURI()).listFiles();
                helper.assertTrue(files != null && files.length > 0, "Partikel-JSON-Ordner nicht listbar");
                for (File file : files) {
                    String base = file.getName().replace(".json", "");
                    helper.assertTrue(EXPECTED_PARTICLES.containsKey(base),
                            "Verwaistes Partikel-JSON ohne Registry-Eintrag: " + file.getName());
                }
            } catch (java.net.URISyntaxException exception) {
                helper.fail("Partikel-JSON-Ordner-URL unparsbar: " + exception.getMessage());
            }
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 2. Frame-Dimensionen + Alpha
    // ------------------------------------------------------------------

    /**
     * Alle Frames sind 16x16 RGBA mit transparentem 1-px-Rand und sinnvoller
     * Alpha-Coverage; Konfetti/Noten bleiben fast weiss (Client-Tint), die
     * Fussel-Frames loesen sich monoton auf und keine zwei Frames sind gleich.
     */
    @GameTest(template = ARENA)
    public static void particle_frames_dimension_and_alpha(GameTestHelper helper) {
        for (String name : EXPECTED_PARTICLES.keySet()) {
            List<String> refs = frameRefs(helper, name);
            Map<String, BufferedImage> frames = new LinkedHashMap<>();
            for (String ref : refs) {
                String path = ResourceLocation.parse(ref).getPath();
                frames.put(path, readSprite(helper, PARTICLE_TEXTURE_DIR + path + ".png"));
            }

            List<Integer> coverages = new ArrayList<>();
            for (Map.Entry<String, BufferedImage> entry : frames.entrySet()) {
                String tag = entry.getKey();
                BufferedImage image = entry.getValue();
                helper.assertTrue(image.getWidth() == SPRITE_SIZE && image.getHeight() == SPRITE_SIZE,
                        tag + ": " + image.getWidth() + "x" + image.getHeight()
                                + " statt " + SPRITE_SIZE + "x" + SPRITE_SIZE);
                helper.assertTrue(image.getColorModel().hasAlpha(), tag + ": PNG ohne Alphakanal");

                if (WAVE_PARTICLES.contains(name)) {
                    for (int i = 0; i < SPRITE_SIZE; i++) {
                        helper.assertTrue((image.getRGB(i, 0) >>> 24) == 0
                                        && (image.getRGB(i, SPRITE_SIZE - 1) >>> 24) == 0
                                        && (image.getRGB(0, i) >>> 24) == 0
                                        && (image.getRGB(SPRITE_SIZE - 1, i) >>> 24) == 0,
                                tag + ": 1-px-Rand ist nicht vollstaendig transparent (Atlas-Bleeding)");
                    }
                }

                int opaque = opaquePixels(image);
                double share = opaque / (double) (SPRITE_SIZE * SPRITE_SIZE);
                helper.assertTrue(share >= COVERAGE_MIN && share <= COVERAGE_MAX,
                        tag + ": Alpha-Coverage " + Math.round(share * 100)
                                + "% ausserhalb " + COVERAGE_MIN * 100 + "%.." + COVERAGE_MAX * 100 + "%");
                coverages.add(opaque);

                if ("confetti".equals(name) || "music_note".equals(name)) {
                    long red = 0;
                    long green = 0;
                    long blue = 0;
                    long count = 0;
                    for (int y = 0; y < SPRITE_SIZE; y++) {
                        for (int x = 0; x < SPRITE_SIZE; x++) {
                            int argb = image.getRGB(x, y);
                            if ((argb >>> 24) >= 8) {
                                red += argb >> 16 & 0xFF;
                                green += argb >> 8 & 0xFF;
                                blue += argb & 0xFF;
                                count++;
                            }
                        }
                    }
                    helper.assertTrue(count > 0 && red / count >= TINT_MIN_AVG
                                    && green / count >= TINT_MIN_AVG && blue / count >= TINT_MIN_AVG,
                            tag + ": Sprite ist zu dunkel fuer den Client-Tint (avg RGB "
                                    + (count == 0 ? "leer" : red / count + "/" + green / count + "/" + blue / count)
                                    + " < " + TINT_MIN_AVG + ")");
                }
            }

            if ("fluff_puff".equals(name)) {
                for (int i = 1; i < coverages.size(); i++) {
                    helper.assertTrue(coverages.get(i) < coverages.get(i - 1),
                            "fluff_puff: Frames loesen sich nicht monoton auf: " + coverages);
                }
            }

            // Varianten muessen sich sichtbar unterscheiden (nie byte-identisch).
            List<String> paths = new ArrayList<>(frames.keySet());
            for (int a = 0; a < paths.size(); a++) {
                for (int b = a + 1; b < paths.size(); b++) {
                    byte[] first = resourceBytes(helper, PARTICLE_TEXTURE_DIR + paths.get(a) + ".png");
                    byte[] second = resourceBytes(helper, PARTICLE_TEXTURE_DIR + paths.get(b) + ".png");
                    helper.assertFalse(java.util.Arrays.equals(first, second),
                            name + ": Frames " + paths.get(a) + " und " + paths.get(b) + " sind identisch");
                }
            }
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 3. Trigger: Tier-Up-Konfetti
    // ------------------------------------------------------------------

    /** Konfetti genau bei Tier-Wechseln — normale Freundschafts-Gewinne feiern nicht. */
    @GameTest(template = ARENA)
    public static void tier_up_spawns_confetti(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer owner = fakePlayer(helper, "confetti_tier_owner");
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        helper.assertTrue(gooby.getConfettiBursts() == 0, "Konfetti ohne Anlass beim Spawn");

        gooby.gainFriendship(owner, 25, false); // STRANGER -> BUDDY
        helper.assertTrue(gooby.getConfettiBursts() == 1,
                "Tier-Up auf BUDDY feuerte kein Konfetti: " + gooby.getConfettiBursts());

        gooby.gainFriendship(owner, 1, false); // kein Tier-Wechsel
        helper.assertTrue(gooby.getConfettiBursts() == 1,
                "Normaler Freundschafts-Gewinn darf NIE Konfetti ausloesen");

        gooby.gainFriendship(owner, 30, false); // BUDDY -> FRIEND
        helper.assertTrue(gooby.getConfettiBursts() == 2,
                "Tier-Up auf FRIEND feuerte kein Konfetti");

        // Budgets: alle Feier-Counts bleiben klein (keine Partikelflut).
        helper.assertTrue(GoobyEntity.CONFETTI_TIER_UP_COUNT <= 16
                        && GoobyEntity.CONFETTI_TIER_UP_BEST_COUNT <= 16
                        && GoobyEntity.CONFETTI_TRICK_COUNT <= 16
                        && GoobyEntity.FLUFF_BRUSH_COUNT <= 16
                        && GoobyEntity.FLUFF_DRESS_UP_COUNT <= 16
                        && GoobyEntity.FLUFF_LANDING_COUNT <= 16
                        && GoobyEntity.MUSIC_NOTE_SPEAK_COUNT <= 16
                        && GoobyEntity.MUSIC_NOTE_DANCE_COUNT <= 16
                        && GoobyEntity.MUSIC_NOTE_PET_COUNT <= 16,
                "Ein Partikel-Budget ueberschreitet das Low-Count-Limit von 16");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 4. Trigger: Trick-Konfetti erst nach VOLLENDETEM Clip + Cooldown
    // ------------------------------------------------------------------

    @GameTest(template = ARENA, timeoutTicks = 400)
    public static void trick_confetti_after_completion_with_cooldown(GameTestHelper helper) {
        placeFloor(helper);
        // Echter Mock-Spieler: isOwnedBy() loest den Besitzer ueber die
        // Level-Spielerliste auf — ein FakePlayer wuerde hier durchfallen.
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.SPIN, 1);
        helper.assertTrue(gooby.selectTrick(owner, GoobyTrick.SPIN), "Trick-Auswahl schlug fehl");
        int duration = GoobyTrick.SPIN.durationTicks();

        helper.assertTrue(gooby.requestSelectedTrick(owner), "Erster Trick startete nicht");
        helper.assertTrue(gooby.getConfettiBursts() == 0,
                "Konfetti darf erst beim VOLLENDETEN Trick fallen, nicht beim Start");

        helper.startSequence()
                .thenExecuteAfter(duration + 6, () -> {
                    helper.assertTrue(gooby.getConfettiBursts() == 1,
                            "Vollendeter Trick feuerte kein Konfetti: " + gooby.getConfettiBursts());
                    // Sofortiger Doppelklick-Spam: Trick laeuft, Konfetti nicht.
                    helper.assertTrue(gooby.requestSelectedTrick(owner), "Spam-Trick wurde abgelehnt");
                })
                .thenExecuteAfter(duration + 6, () -> helper.assertTrue(gooby.getConfettiBursts() == 1,
                        "Trick-Konfetti ignorierte den " + GoobyEntity.CONFETTI_TRICK_COOLDOWN_TICKS
                                + "-Tick-Cooldown"))
                .thenExecuteAfter(GoobyEntity.CONFETTI_TRICK_COOLDOWN_TICKS, () ->
                        helper.assertTrue(gooby.requestSelectedTrick(owner),
                                "Trick nach Cooldown startete nicht"))
                .thenExecuteAfter(duration + 6, () -> {
                    helper.assertTrue(gooby.getConfettiBursts() == 2,
                            "Nach Cooldown-Ablauf muss der vollendete Trick wieder feiern");
                    TestPlayers.remove(helper, owner);
                })
                .thenSucceed();
    }

    /**
     * Regression: NUR wirklich vollendete Tricks feiern. Eine ersetzende
     * Priority-Action (hier: Tier-Up mitten im Clip) und ein echter Treffer
     * stornieren den Konfetti-Countdown; die unbehelligte Kontroll-Salve am
     * Ende beweist, dass ohne Unterbrechung gefeiert worden waere.
     */
    @GameTest(template = ARENA, timeoutTicks = 500)
    public static void interrupted_trick_never_spawns_confetti(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.SPIN, 1);
        helper.assertTrue(gooby.selectTrick(owner, GoobyTrick.SPIN), "Trick-Auswahl schlug fehl");
        int duration = GoobyTrick.SPIN.durationTicks();

        // 1) Ersetzende Priority-Action: Tier-Up ersetzt den laufenden Clip.
        helper.assertTrue(gooby.requestSelectedTrick(owner), "Erster Trick startete nicht");
        gooby.gainFriendship(owner, 25, false); // STRANGER -> BUDDY, feiert selbst
        helper.assertTrue(gooby.getConfettiBursts() == 1,
                "Tier-Up-Konfetti muss sofort fallen: " + gooby.getConfettiBursts());

        helper.startSequence()
                .thenExecuteAfter(duration + 6, () -> helper.assertTrue(
                        gooby.getConfettiBursts() == 1,
                        "ERSETZTER Trick darf am Clip-Ende nicht feiern"))
                // 2) Echter Treffer mitten im Clip storniert den Countdown.
                .thenExecuteAfter(GoobyEntity.CONFETTI_TRICK_COOLDOWN_TICKS, () -> {
                    helper.assertTrue(gooby.requestSelectedTrick(owner),
                            "Zweiter Trick startete nicht");
                    helper.assertTrue(gooby.hurt(
                                    helper.getLevel().damageSources().generic(), 1.0F),
                            "Genereller Schaden muss beim zahmen Gooby durchkommen");
                })
                .thenExecuteAfter(duration + 6, () -> helper.assertTrue(
                        gooby.getConfettiBursts() == 1,
                        "UNTERBROCHENER Trick darf am Clip-Ende nicht feiern"))
                // 3) Kontrolle: der unbehelligte Trick feiert nach dem Cooldown.
                .thenExecuteAfter(GoobyEntity.CONFETTI_TRICK_COOLDOWN_TICKS, () ->
                        helper.assertTrue(gooby.requestSelectedTrick(owner),
                                "Kontroll-Trick startete nicht"))
                .thenExecuteAfter(duration + 6, () -> {
                    helper.assertTrue(gooby.getConfettiBursts() == 2,
                            "Unbehelligter Kontroll-Trick muss feiern: "
                                    + gooby.getConfettiBursts());
                    TestPlayers.remove(helper, owner);
                })
                .thenSucceed();
    }

    // ------------------------------------------------------------------
    // 5. Trigger: Musiknoten (SPEAK/DANCE sofort, Streicheln mit Cooldown)
    // ------------------------------------------------------------------

    @GameTest(template = ARENA, timeoutTicks = 200)
    public static void music_notes_for_speak_dance_and_pet(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.SPEAK, 1);
        gooby.setTrickProficiency(GoobyTrick.DANCE, 1);
        gooby.setTrickProficiency(GoobyTrick.SPIN, 1);

        helper.assertTrue(gooby.selectTrick(owner, GoobyTrick.SPEAK)
                && gooby.requestSelectedTrick(owner), "SPEAK startete nicht");
        helper.assertTrue(gooby.getMusicNoteBursts() == 1,
                "SPEAK muss sofort Noten zeigen: " + gooby.getMusicNoteBursts());

        helper.assertTrue(gooby.selectTrick(owner, GoobyTrick.DANCE)
                && gooby.requestSelectedTrick(owner), "DANCE startete nicht");
        helper.assertTrue(gooby.getMusicNoteBursts() == 2, "DANCE muss sofort Noten zeigen");

        // Negativ: SPIN gehoert nicht zum Noten-Kontext.
        helper.assertTrue(gooby.selectTrick(owner, GoobyTrick.SPIN)
                && gooby.requestSelectedTrick(owner), "SPIN startete nicht");
        helper.assertTrue(gooby.getMusicNoteBursts() == 2, "SPIN darf keine Noten ausloesen");

        // Streichel-/Schnurr-Kontext: erste Noten sofort, Spam bleibt stumm.
        gooby.pet(owner);
        helper.assertTrue(gooby.getMusicNoteBursts() == 3, "Streicheln zeigte keine Schnurr-Noten");
        gooby.pet(owner);
        helper.assertTrue(gooby.getMusicNoteBursts() == 3,
                "Klickspam ignorierte den Streichel-Noten-Cooldown");

        helper.startSequence()
                .thenExecuteAfter(GoobyEntity.MUSIC_NOTE_PET_COOLDOWN_TICKS + 4, () -> {
                    gooby.pet(owner);
                    helper.assertTrue(gooby.getMusicNoteBursts() == 4,
                            "Nach Cooldown-Ablauf muessen Streichel-Noten wieder erscheinen");
                    TestPlayers.remove(helper, owner);
                })
                .thenSucceed();
    }

    // ------------------------------------------------------------------
    // 6. Trigger: Fellfussel (Buersten mit Cooldown, Dress-up)
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void brush_and_dress_up_spawn_fluff(GameTestHelper helper) {
        placeFloor(helper);
        // Dress-up prueft isOwnedBy() — dafuer braucht es den echten
        // Mock-Spieler aus der Level-Spielerliste (kein FakePlayer).
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(2.5, 2.0, 2.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_BRUSH.get()));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getFluffPuffBursts() == 1,
                "Buersten wirbelte keine Fussel auf: " + gooby.getFluffPuffBursts());

        // Negativ: der 20-s-Buersten-Cooldown gilt auch fuer die Fussel.
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getFluffPuffBursts() == 1,
                "Buersten-Spam im Cooldown-Fenster wirbelte erneut Fussel auf");

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_SCARF.get()));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getFluffPuffBursts() == 2,
                "Dress-up (Schal) wirbelte keine Fussel auf");
        helper.assertTrue(!gooby.getNeckStack().isEmpty(), "Schal wurde nicht angelegt");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Ein echter Fall (>2 Bloecke) staubt Fell auf — gleiche Dedupe wie der Squash. */
    @GameTest(template = ARENA, timeoutTicks = 300)
    public static void landing_spawns_fluff(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new Vec3(2.5, 7.0, 2.5));
        helper.succeedWhen(() -> helper.assertTrue(
                gooby.getLandingSquashes() == 1 && gooby.getFluffPuffBursts() == 1,
                "Landung nach Fall >2 Bloecke muss genau EINEN Fussel-Burst ausloesen"));
    }

    // ------------------------------------------------------------------
    // 7. Dedicated-Server: Common-Code kennt die Client-Partikel NIE
    // ------------------------------------------------------------------

    /**
     * Dieser GameTest-Server IST ein Dedicated Server: die Partikeltypen sind
     * registriert, obwohl keine Client-Klasse geladen wird. Der Bytecode der
     * Common-Klassen (Entity, Registry, Mod-Hauptklasse) referenziert
     * client/particle nachweislich nirgends; ClientSetup dient als
     * Positiv-Kontrolle, dass der Konstantenpool-Scan wirklich anschlaegt.
     */
    @GameTest(template = ARENA)
    public static void dedicated_server_classloading_contract(GameTestHelper helper) {
        for (String name : EXPECTED_PARTICLES.keySet()) {
            helper.assertTrue(BuiltInRegistries.PARTICLE_TYPE.containsKey(
                            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, name)),
                    "Partikeltyp fehlt auf dem Dedicated Server: " + name);
        }

        String clientParticlePackage = "client/particle";
        for (String common : new String[] {
                "de/sonic0810/goobymod/entity/GoobyEntity.class",
                "de/sonic0810/goobymod/registry/ModParticles.class",
                "de/sonic0810/goobymod/GoobyMod.class"}) {
            byte[] bytecode = resourceBytes(helper, common);
            helper.assertTrue(bytecode.length > 0, "Bytecode leer: " + common);
            helper.assertFalse(containsAscii(bytecode, clientParticlePackage),
                    common + " referenziert " + clientParticlePackage
                            + " — Dedicated-Server-Classloading waere kaputt");
        }

        // Positiv-Kontrolle: der Scanner findet die Referenzen dort, wo sie
        // hingehoeren (reines Byte-Lesen classloadet ClientSetup NICHT).
        byte[] clientSetup = resourceBytes(helper, "de/sonic0810/goobymod/client/ClientSetup.class");
        helper.assertTrue(containsAscii(clientSetup, clientParticlePackage),
                "Positiv-Kontrolle fehlgeschlagen: ClientSetup registriert keine client/particle-Provider");

        // Die drei Client-Klassen existieren als Ressourcen im Jar/Classpath.
        for (String clientClass : new String[] {"ConfettiParticle", "FluffPuffParticle", "MusicNoteParticle"}) {
            helper.assertTrue(resourceExists(
                            "de/sonic0810/goobymod/client/particle/" + clientClass + ".class"),
                    "Client-Partikelklasse fehlt im Classpath: " + clientClass);
        }
        helper.succeed();
    }
}
