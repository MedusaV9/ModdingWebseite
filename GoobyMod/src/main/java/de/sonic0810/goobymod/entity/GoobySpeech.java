package de.sonic0810.goobymod.entity;

import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.api.GoobyApi;
import java.util.List;
import javax.annotation.Nullable;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.player.Player;

/**
 * Goobys Sprechblasen-Gehirn. Alle Lines sind Translation-Keys (en_us + de_de).
 * Zeit/Zufall werden IMMER injiziert (RandomSource-Parameter) — dadurch komplett testbar.
 *
 * <p>Die Special-Lines fuer {@link #SOPHIE_NAME} sind REIN kosmetisch: eine
 * lokale Sprechblase, kein Gameplay-Effekt, keine Logs/Telemetrie. Ueber die
 * Server-Config ({@code enableSpecialLines}) komplett abschaltbar; der Client
 * rendert sie zusaetzlich nur fuer den passenden Spieler selbst.
 */
public final class GoobySpeech {
    public static final String SOPHIE_NAME = "sophiex456";
    private static final String PREFIX = "bubble.goobymod.";
    private static final String SPECIAL_PREFIX = PREFIX + "sophie";

    // --- Nougatschleuse ---
    public static final List<String> NOUGAT = keys("nougat", 6);
    // --- Sein eigenes Handyspiel GOOBY ---
    public static final List<String> GAME = keys("game", 6);
    // --- Alltags-Witze ---
    public static final List<String> IDLE = keys("idle", 12);
    // --- Kontext-Lines ---
    public static final List<String> RAIN = keys("rain", 4);
    public static final List<String> NIGHT = keys("night", 4);
    public static final List<String> CAKE = keys("cake", 4);
    public static final List<String> GREET = keys("greet", 4);
    public static final List<String> PET = keys("pet", 5);
    public static final List<String> EAT = keys("eat", 4);
    public static final List<String> SAD = keys("sad", 4);
    public static final List<String> DIG = keys("dig", 4);
    public static final List<String> RIDE = keys("ride", 4);
    public static final List<String> GIFT = keys("gift", 4);
    public static final List<String> HUNGRY = keys("hungry", 4);
    public static final List<String> LONELY = keys("lonely", 4);
    public static final List<String> SLEEPY = keys("sleepy", 4);
    public static final List<String> SCARED = keys("scared", 4);
    public static final List<String> GREET_BUDDY = keys("greet_buddy", 4);
    public static final List<String> GREET_FRIEND = keys("greet_friend", 4);
    public static final List<String> GREET_BEST_FRIEND = keys("greet_best_friend", 4);
    public static final List<String> ANNIVERSARY = keys("anniversary", 4);
    public static final List<String> BABY = keys("baby", 6);
    public static final List<String> MACHINERY = keys("machinery", 6);
    public static final List<String> CONTRAPTION_ARRIVAL = keys("contraption_arrival", 6);
    public static final List<String> SHY = keys("shy", 5);
    public static final List<String> SOCIAL = keys("social", 8);
    public static final String WANT_PET = PREFIX + "want_pet";
    public static final String WAKE = PREFIX + "wake1";
    public static final String CONVERT = PREFIX + "convert1";
    public static final String TELEPORT = PREFIX + "teleport1";
    public static final String TAMED = PREFIX + "tamed1";
    public static final String BEST_FRIEND = PREFIX + "bestfriend1";
    public static final String TIER_UP_BUDDY = PREFIX + "tier_up_buddy";
    public static final String TIER_UP_FRIEND = PREFIX + "tier_up_friend";
    public static final String TIER_UP_BEST_FRIEND = PREFIX + "tier_up_best_friend";
    public static final String SNUGGLE = PREFIX + "snuggle";
    public static final String COMMAND_WANDER = PREFIX + "cmd_wander";
    public static final String COMMAND_FOLLOW = PREFIX + "cmd_follow";
    public static final String COMMAND_STAY = PREFIX + "cmd_stay";
    public static final String CONTRAPTION_REFUSAL = PREFIX + "contraption_refusal";
    public static final String EMOTE_BOW = PREFIX + "emote_bow";
    public static final String EMOTE_JUMP = PREFIX + "emote_jump";

    /**
     * Special-Lines NUR fuer sophiex456 — bleiben in beiden Sprachdateien deutsch
     * (Eigennamen-gebunden: Sophie & Vincent).
     */
    public static final List<String> SOPHIE = keys("sophie", 10);

    /** Der allgemeine Idle-Pool (Nougatschleuse + Handyspiel + Alltag). */
    public static final List<String> GENERAL = concat(NOUGAT, GAME, IDLE);

    private static List<String> keys(String base, int count) {
        return java.util.stream.IntStream.rangeClosed(1, count)
                .mapToObj(i -> PREFIX + base + i)
                .toList();
    }

    @SafeVarargs
    private static List<String> concat(List<String>... lists) {
        return java.util.Arrays.stream(lists).flatMap(List::stream).toList();
    }

    public static boolean isSophie(@Nullable Player player) {
        return player != null && isSophie(player.getGameProfile().getName());
    }

    /** Exakter Namensvergleich, nur case-insensitive — aehnliche Namen matchen NIE. */
    public static boolean isSophie(@Nullable String name) {
        return SOPHIE_NAME.equalsIgnoreCase(name);
    }

    /** Ist der Key eine der namensgebundenen Special-Lines? (Fuer lokales Client-Rendering.) */
    public static boolean isSpecialLine(@Nullable String key) {
        return key != null && key.startsWith(SPECIAL_PREFIX);
    }

    public static String pickFrom(List<String> pool, RandomSource random) {
        return pool.get(random.nextInt(pool.size()));
    }

    /** Waehlt eine Idle-Line; Special-Line-Verhalten kommt aus der Server-Config. */
    public static String pickIdleLine(@Nullable Player nearest, boolean raining, boolean night, boolean cakeNearby,
            RandomSource random) {
        return pickIdleLine(nearest, raining, night, cakeNearby, random,
                GoobyConfig.enableSpecialLines(), GoobyConfig.specialLineChance());
    }

    /**
     * Testbare Variante mit explizitem Killswitch + Chance. Sophie
     * (case-insensitive) bekommt mit erhoehter Haeufigkeit ihre Special-Lines;
     * alle anderen Spieler NIE.
     */
    public static String pickIdleLine(@Nullable Player nearest, boolean raining, boolean night, boolean cakeNearby,
            RandomSource random, boolean specialLinesEnabled, float specialLineChance) {
        if (specialLinesEnabled && isSophie(nearest) && random.nextFloat() < specialLineChance) {
            return pickFrom(SOPHIE, random);
        }
        if (cakeNearby && random.nextFloat() < 0.6F) {
            return pickFrom(CAKE, random);
        }
        if (raining && random.nextFloat() < 0.35F) {
            return pickFrom(RAIN, random);
        }
        if (night && random.nextFloat() < 0.35F) {
            return pickFrom(NIGHT, random);
        }
        return pickGeneralLine(random);
    }

    private static String pickGeneralLine(RandomSource random) {
        List<String> addon = GoobyApi.addonSpeechKeys();
        int index = random.nextInt(GENERAL.size() + addon.size());
        return index < GENERAL.size() ? GENERAL.get(index) : addon.get(index - GENERAL.size());
    }

    /** Reaktions-Line auf eine Interaktion; Sophie-Pool hat auch hier Vorrang (rein kosmetisch). */
    public static String pickReaction(List<String> pool, @Nullable Player player, RandomSource random) {
        return pickReaction(pool, player, random, GoobyConfig.enableSpecialLines());
    }

    /** Testbare Variante mit explizitem Killswitch. */
    public static String pickReaction(List<String> pool, @Nullable Player player, RandomSource random,
            boolean specialLinesEnabled) {
        if (specialLinesEnabled && isSophie(player) && random.nextFloat() < 0.4F) {
            return pickFrom(SOPHIE, random);
        }
        return pickFrom(pool, random);
    }

    private GoobySpeech() {
    }
}
