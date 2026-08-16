package de.sonic0810.goobymod;

import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * Server-Config (liegt in der Welt unter serverconfig/, wird beim Join zu den
 * Clients synchronisiert — der Server bestimmt die Werte, auch fuer die
 * Bubble-Renderdistanz). Alle Getter haben Fallback-Defaults, damit Code, der
 * vor dem Config-Load laeuft (z.B. GameTests), nie crasht.
 */
public final class GoobyConfig {
    public static final ModConfigSpec SPEC;

    public static final ModConfigSpec.BooleanValue ENABLE_SPECIAL_LINES;
    public static final ModConfigSpec.DoubleValue SPECIAL_LINE_CHANCE;
    public static final ModConfigSpec.IntValue BUBBLE_DISTANCE;
    public static final ModConfigSpec.IntValue IDLE_LINE_MIN_TICKS;
    public static final ModConfigSpec.IntValue IDLE_LINE_MAX_TICKS;
    public static final ModConfigSpec.IntValue GIFT_COOLDOWN_TICKS;
    public static final ModConfigSpec.IntValue MAX_GIFT_CHARGES;
    public static final ModConfigSpec.BooleanValue GOOBY_MOB_PROTECTION;
    public static final ModConfigSpec.BooleanValue ESCAPE_TO_OWNER;
    public static final ModConfigSpec.DoubleValue GOOBY_VOLUME_SCALE;
    public static final ModConfigSpec.DoubleValue HUNGER_HOURS;
    public static final ModConfigSpec.DoubleValue LONELY_MINUTES;
    public static final ModConfigSpec.BooleanValue CREEPER_ALARM;
    public static final ModConfigSpec.DoubleValue ALERT_RADIUS;
    public static final ModConfigSpec.BooleanValue NAME_RECOGNITION;
    public static final ModConfigSpec.BooleanValue GIVE_HANDBOOK_ON_TAME;
    public static final ModConfigSpec.IntValue DUSK_TRAVEL_RADIUS;
    public static final ModConfigSpec.IntValue FAMILY_GROWTH_TICKS;
    public static final ModConfigSpec.IntValue FAMILY_RITUAL_COOLDOWN;
    public static final ModConfigSpec.BooleanValue WILD_SPAWNS;
    public static final ModConfigSpec.BooleanValue SOCIAL_PLAY_CHASE;
    public static final ModConfigSpec.BooleanValue SOCIAL_EMOTE_REACTIONS;
    public static final ModConfigSpec.BooleanValue SEEK_ALLOW_ORES;
    public static final ModConfigSpec.IntValue SEEK_COOLDOWN_TICKS;

    public static final boolean DEFAULT_ENABLE_SPECIAL_LINES = true;
    public static final double DEFAULT_SPECIAL_LINE_CHANCE = 0.65;
    public static final int DEFAULT_BUBBLE_DISTANCE = 40;
    public static final int DEFAULT_IDLE_LINE_MIN_TICKS = 2400;
    public static final int DEFAULT_IDLE_LINE_MAX_TICKS = 4800;
    public static final int DEFAULT_GIFT_COOLDOWN_TICKS = 6000;
    public static final int DEFAULT_MAX_GIFT_CHARGES = 3;
    public static final boolean DEFAULT_GOOBY_MOB_PROTECTION = true;
    public static final boolean DEFAULT_ESCAPE_TO_OWNER = true;
    public static final double DEFAULT_GOOBY_VOLUME_SCALE = 1.0;
    public static final double DEFAULT_HUNGER_HOURS = 1.5;
    public static final double DEFAULT_LONELY_MINUTES = 10.0;
    public static final boolean DEFAULT_CREEPER_ALARM = true;
    public static final double DEFAULT_ALERT_RADIUS = 12.0;
    public static final boolean DEFAULT_NAME_RECOGNITION = true;
    public static final boolean DEFAULT_GIVE_HANDBOOK_ON_TAME = true;
    public static final int DEFAULT_DUSK_TRAVEL_RADIUS = 96;
    public static final int DEFAULT_FAMILY_GROWTH_TICKS = 36000;
    public static final int DEFAULT_FAMILY_RITUAL_COOLDOWN = 24000;
    public static final boolean DEFAULT_WILD_SPAWNS = true;
    public static final boolean DEFAULT_SOCIAL_PLAY_CHASE = true;
    public static final boolean DEFAULT_SOCIAL_EMOTE_REACTIONS = true;
    public static final boolean DEFAULT_SEEK_ALLOW_ORES = false;
    public static final int DEFAULT_SEEK_COOLDOWN_TICKS = 6000;

    static {
        ModConfigSpec.Builder builder = new ModConfigSpec.Builder();

        builder.push("specialLines");
        ENABLE_SPECIAL_LINES = builder
                .comment("Killswitch for the name-bound special speech lines. When false, every player",
                        "only ever gets the general line pools (purely cosmetic feature, no gameplay effect).")
                .define("enableSpecialLines", DEFAULT_ENABLE_SPECIAL_LINES);
        SPECIAL_LINE_CHANCE = builder
                .comment("Chance (0.0-1.0) that an idle line rolls from the special pool for the matching player.")
                .defineInRange("specialLineChance", DEFAULT_SPECIAL_LINE_CHANCE, 0.0, 1.0);
        builder.pop();

        builder.push("bubbles");
        BUBBLE_DISTANCE = builder
                .comment("Maximum distance in blocks at which speech bubbles are rendered.")
                .defineInRange("bubbleDistance", DEFAULT_BUBBLE_DISTANCE, 8, 128);
        IDLE_LINE_MIN_TICKS = builder
                .comment("Minimum ticks between two idle speech lines (20 ticks = 1 second).")
                .defineInRange("idleLineMinTicks", DEFAULT_IDLE_LINE_MIN_TICKS, 200, 72000);
        IDLE_LINE_MAX_TICKS = builder
                .comment("Maximum ticks between two idle speech lines. Must be >= idleLineMinTicks",
                        "(smaller values are clamped up at runtime).")
                .defineInRange("idleLineMaxTicks", DEFAULT_IDLE_LINE_MAX_TICKS, 200, 144000);
        builder.pop();

        builder.push("gifts");
        GIFT_COOLDOWN_TICKS = builder
                .comment("Cooldown in ticks between two dug-up gifts (20 ticks = 1 second).")
                .defineInRange("giftCooldownTicks", DEFAULT_GIFT_COOLDOWN_TICKS, 200, 720000);
        MAX_GIFT_CHARGES = builder
                .comment("How many gift charges a Gooby can store. One charge is gained per fed jar of Nutella.")
                .defineInRange("maxGiftCharges", DEFAULT_MAX_GIFT_CHARGES, 1, 9);
        builder.pop();

        builder.push("protection");
        GOOBY_MOB_PROTECTION = builder
                .comment("Protects tamed Goobys from damage caused by hostile and other non-player mobs.",
                        "Wild Goobys remain vulnerable. Player attacks are always harmless.")
                .define("goobyMobProtection", DEFAULT_GOOBY_MOB_PROTECTION);
        ESCAPE_TO_OWNER = builder
                .comment("Lets a pressured tamed Gooby flee to its owner, or to its hutch when the owner is absent.")
                .define("escapeToOwner", DEFAULT_ESCAPE_TO_OWNER);
        builder.pop();

        builder.push("audio");
        GOOBY_VOLUME_SCALE = builder
                .comment("Master volume multiplier for Gooby creature sounds (0.0-2.0).")
                .defineInRange("goobyVolumeScale", DEFAULT_GOOBY_VOLUME_SCALE, 0.0, 2.0);
        builder.pop();

        builder.push("needs");
        HUNGER_HOURS = builder
                .comment("Minecraft days since feeding before Gooby becomes hungry (legacy key name: hours).")
                .defineInRange("hungerHours", DEFAULT_HUNGER_HOURS, 0.05, 10.0);
        LONELY_MINUTES = builder
                .comment("Real-time minutes without a nearby online owner before a tamed Gooby becomes lonely.")
                .defineInRange("lonelyMinutes", DEFAULT_LONELY_MINUTES, 1.0, 200.0);
        builder.pop();

        builder.push("awareness");
        CREEPER_ALARM = builder
                .comment("Enables Gooby's louder, longer-range early warning for creepers.")
                .define("creeperAlarm", DEFAULT_CREEPER_ALARM);
        ALERT_RADIUS = builder
                .comment("Base radius in blocks in which Gooby detects hostile mobs.")
                .defineInRange("alertRadius", DEFAULT_ALERT_RADIUS, 4.0, 32.0);
        builder.pop();

        builder.push("bonding");
        NAME_RECOGNITION = builder
                .comment("Lets an owned, custom-named Gooby react when its owner says its name in chat.")
                .define("nameRecognition", DEFAULT_NAME_RECOGNITION);
        GIVE_HANDBOOK_ON_TAME = builder
                .comment("Gives each player one in-game Gooby Handbook after their first successful taming.")
                .define("giveHandbookOnTame", DEFAULT_GIVE_HANDBOOK_ON_TAME);
        builder.pop();

        builder.push("home");
        DUSK_TRAVEL_RADIUS = builder
                .comment("Maximum distance in blocks a Gooby will travel to its explicitly bound hutch at dusk.",
                        "Beyond this radius it sleeps rough without forgetting its home.")
                .defineInRange("duskTravelRadius", DEFAULT_DUSK_TRAVEL_RADIUS, 16, 256);
        builder.pop();

        builder.push("family");
        FAMILY_GROWTH_TICKS = builder
                .comment("Ticks a newborn Gooby remains a baby (36000 = 1.5 Minecraft days).")
                .defineInRange("growthTicks", DEFAULT_FAMILY_GROWTH_TICKS, 1200, 240000);
        FAMILY_RITUAL_COOLDOWN = builder
                .comment("Minimum ticks before the same two Goobys may complete another family ritual.")
                .defineInRange("ritualCooldown", DEFAULT_FAMILY_RITUAL_COOLDOWN, 1200, 240000);
        builder.pop();

        builder.push("worldgen");
        WILD_SPAWNS = builder
                .comment("Allows rare natural Gooby spawns in tagged meadow, cherry grove, and flower forest biomes.",
                        "Burrow residents and player-created Goobys are not affected.")
                .define("wildSpawns", DEFAULT_WILD_SPAWNS);
        builder.pop();

        builder.push("social");
        SOCIAL_PLAY_CHASE = builder
                .comment("Allows low-priority, 30-second maximum play chases between nearby Goobys.")
                .define("playChase", DEFAULT_SOCIAL_PLAY_CHASE);
        SOCIAL_EMOTE_REACTIONS = builder
                .comment("Lets Goobys mirror deliberate player bows and repeated happy jumps.")
                .define("emoteReactions", DEFAULT_SOCIAL_EMOTE_REACTIONS);
        builder.pop();

        builder.push("seek");
        SEEK_ALLOW_ORES = builder
                .comment("Allows Sniff & Seek to track ore blocks shown by their block item.",
                        "Disabled by default so the activity remains cozy rather than an ore scanner.")
                .define("allowOres", DEFAULT_SEEK_ALLOW_ORES);
        SEEK_COOLDOWN_TICKS = builder
                .comment("Cooldown in ticks between Sniff & Seek attempts (6000 = 5 minutes).")
                .defineInRange("cooldown", DEFAULT_SEEK_COOLDOWN_TICKS, 200, 72000);
        builder.pop();

        SPEC = builder.build();
    }

    private GoobyConfig() {
    }

    public static boolean enableSpecialLines() {
        return SPEC.isLoaded() ? ENABLE_SPECIAL_LINES.get() : DEFAULT_ENABLE_SPECIAL_LINES;
    }

    public static float specialLineChance() {
        return SPEC.isLoaded() ? SPECIAL_LINE_CHANCE.get().floatValue() : (float) DEFAULT_SPECIAL_LINE_CHANCE;
    }

    public static int bubbleDistance() {
        return SPEC.isLoaded() ? BUBBLE_DISTANCE.get() : DEFAULT_BUBBLE_DISTANCE;
    }

    public static int idleLineMinTicks() {
        return SPEC.isLoaded() ? IDLE_LINE_MIN_TICKS.get() : DEFAULT_IDLE_LINE_MIN_TICKS;
    }

    public static int idleLineMaxTicks() {
        int min = idleLineMinTicks();
        int max = SPEC.isLoaded() ? IDLE_LINE_MAX_TICKS.get() : DEFAULT_IDLE_LINE_MAX_TICKS;
        return Math.max(min, max);
    }

    public static int giftCooldownTicks() {
        return SPEC.isLoaded() ? GIFT_COOLDOWN_TICKS.get() : DEFAULT_GIFT_COOLDOWN_TICKS;
    }

    public static int maxGiftCharges() {
        return SPEC.isLoaded() ? MAX_GIFT_CHARGES.get() : DEFAULT_MAX_GIFT_CHARGES;
    }

    public static boolean goobyMobProtection() {
        return SPEC.isLoaded() ? GOOBY_MOB_PROTECTION.get() : DEFAULT_GOOBY_MOB_PROTECTION;
    }

    public static boolean escapeToOwner() {
        return SPEC.isLoaded() ? ESCAPE_TO_OWNER.get() : DEFAULT_ESCAPE_TO_OWNER;
    }

    public static float goobyVolumeScale() {
        return SPEC.isLoaded() ? GOOBY_VOLUME_SCALE.get().floatValue() : (float) DEFAULT_GOOBY_VOLUME_SCALE;
    }

    public static int hungerTicks() {
        double days = SPEC.isLoaded() ? HUNGER_HOURS.get() : DEFAULT_HUNGER_HOURS;
        return (int) Math.round(days * 24000.0);
    }

    public static int lonelyTicks() {
        double minutes = SPEC.isLoaded() ? LONELY_MINUTES.get() : DEFAULT_LONELY_MINUTES;
        return (int) Math.round(minutes * 1200.0);
    }

    public static boolean creeperAlarm() {
        return SPEC.isLoaded() ? CREEPER_ALARM.get() : DEFAULT_CREEPER_ALARM;
    }

    public static double alertRadius() {
        return SPEC.isLoaded() ? ALERT_RADIUS.get() : DEFAULT_ALERT_RADIUS;
    }

    public static boolean nameRecognition() {
        return SPEC.isLoaded() ? NAME_RECOGNITION.get() : DEFAULT_NAME_RECOGNITION;
    }

    public static boolean giveHandbookOnTame() {
        return SPEC.isLoaded() ? GIVE_HANDBOOK_ON_TAME.get() : DEFAULT_GIVE_HANDBOOK_ON_TAME;
    }

    public static int duskTravelRadius() {
        return SPEC.isLoaded() ? DUSK_TRAVEL_RADIUS.get() : DEFAULT_DUSK_TRAVEL_RADIUS;
    }

    public static int familyGrowthTicks() {
        return SPEC.isLoaded() ? FAMILY_GROWTH_TICKS.get() : DEFAULT_FAMILY_GROWTH_TICKS;
    }

    public static int familyRitualCooldown() {
        return SPEC.isLoaded() ? FAMILY_RITUAL_COOLDOWN.get() : DEFAULT_FAMILY_RITUAL_COOLDOWN;
    }

    public static boolean wildSpawns() {
        return SPEC.isLoaded() ? WILD_SPAWNS.get() : DEFAULT_WILD_SPAWNS;
    }

    public static boolean socialPlayChase() {
        return SPEC.isLoaded() ? SOCIAL_PLAY_CHASE.get() : DEFAULT_SOCIAL_PLAY_CHASE;
    }

    public static boolean socialEmoteReactions() {
        return SPEC.isLoaded() ? SOCIAL_EMOTE_REACTIONS.get() : DEFAULT_SOCIAL_EMOTE_REACTIONS;
    }

    public static boolean seekAllowOres() {
        return SPEC.isLoaded() ? SEEK_ALLOW_ORES.get() : DEFAULT_SEEK_ALLOW_ORES;
    }

    public static int seekCooldownTicks() {
        return SPEC.isLoaded() ? SEEK_COOLDOWN_TICKS.get() : DEFAULT_SEEK_COOLDOWN_TICKS;
    }
}
