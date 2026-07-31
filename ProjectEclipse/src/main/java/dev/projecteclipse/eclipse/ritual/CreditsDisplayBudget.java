package dev.projecteclipse.eclipse.ritual;

import java.util.List;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.config.ModConfig;
import net.neoforged.fml.event.lifecycle.FMLConstructModEvent;
import net.neoforged.neoforge.common.ModConfigSpec;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * F-102 "Credits-Tausende" — the central DISPLAY-BUDGET LADDER of the final credits
 * sequence. Every big display population (island shatter, formation backdrop, black-hole
 * accretion + sky-drain streams, map-rip effigy) reads its counts from ONE
 * {@link Snapshot} taken at {@code CreditsSequence.begin()} instead of hardcoding them,
 * so the whole show scales over three tiers:
 *
 * <ul>
 *   <li><b>VERIFY</b> — low counts for the llvmpipe acceptance VM: every act stays
 *       readable and countable (RCON {@code /execute if entity @e[...]}) while the
 *       machine never renders more than ~1.1k displays at once.</li>
 *   <li><b>STANDARD</b> — the default live show: clearly denser than the pre-F-102
 *       counts on every key beat (shatter ≈ 2.6k fragments, finale peak ≈ 3.4k).</li>
 *   <li><b>EPIC</b> — "tausende": the real-GPU tier — shatter ≈ 4.6k fragments, finale
 *       peak ≈ 5.1k concurrent displays (the user's "hunderte bis tausende" ask).</li>
 * </ul>
 *
 * <p><b>Selection</b>: the {@code displayTier} common config
 * ({@value #COMMON_FILE_NAME}) is the persistent choice; {@code /dev credits tier
 * &lt;verify|standard|epic&gt;} overrides it at runtime (until server restart) —
 * the switch the main agent flips to {@code verify} before an acceptance run. The tier
 * is SNAPSHOTTED once per run at {@code begin()}: switching mid-run only affects the
 * next start (deterministic pose functions must never see counts change under them).</p>
 *
 * <p>Only counts/caps live here — spawn/removal stay budgeted per tick and every
 * population keeps its scope tag + orphan sweep (the F-084 pattern) regardless of
 * tier; the ladder can never bypass {@code CreditsSequence}'s hard cap, it IS the
 * hard cap's source.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CreditsDisplayBudget {
    public static final String COMMON_FILE_NAME = "eclipse-credits-budget.toml";

    /** The three rungs of the ladder (config value / {@code /dev credits tier} arg). */
    public enum Tier {
        VERIFY, STANDARD, EPIC;

        static Tier parse(String name) {
            for (Tier tier : values()) {
                if (tier.name().equalsIgnoreCase(name)) {
                    return tier;
                }
            }
            return STANDARD;
        }
    }

    /**
     * One immutable per-run budget resolution ({@code CreditsSequence.begin()} takes it
     * once and hands it to every act's {@code prepare}). Fields:
     *
     * <ul>
     *   <li>{@code displayHardCap} — {@code CreditsSequence.capReached}'s ceiling on
     *       live displays of ALL kinds.</li>
     *   <li>{@code shatter*} — island-shatter sample/splinter caps + spawn rate
     *       ({@code CreditsShatterAct}).</li>
     *   <li>{@code formationCap} — how many of the {@code CreditsFormationAct.TOTAL}
     *       backdrop displays are spawned (the sequence gates the spawn calls; the act
     *       itself stays untouched).</li>
     *   <li>{@code hole*}/{@code skyDrainCount} — accretion field size/rate + the F-102
     *       sky-contraction stream population ({@code CreditsBlackHoleAct}).</li>
     *   <li>{@code rip*} — map-effigy crust cap, pools and LOD base steps
     *       ({@code CreditsMapRipAct}; smaller steps = finer grid = more cells).</li>
     * </ul>
     */
    public record Snapshot(
            Tier tier,
            int displayHardCap,
            int shatterSampleCap,
            int shatterSplinterCap,
            int shatterSpawnPerTick,
            int formationCap,
            int holeCount,
            int holeSpawnPerTick,
            int skyDrainCount,
            int ripCellCap,
            int ripSeamPool,
            int ripShardPool,
            int ripUndersidePool,
            int ripStepNear,
            int ripStepFar) {}

    /**
     * The rungs. Audited concurrent peaks (worst window per tier, see the F-102
     * report; shatter = samples + splinter shower, finale = rip pools + accretion +
     * sky-drain): VERIFY beach ≈ 0.77k / shatter ≈ 0.29k / finale ≈ 0.94k;
     * STANDARD beach ≈ 2.27k / shatter ≈ 2.6k / finale ≈ 3.4k;
     * EPIC shatter ≈ 4.6k / finale ≈ 5.1k — each under its own hard cap.
     */
    private static final Snapshot VERIFY = new Snapshot(Tier.VERIFY,
            1_400, 220, 70, 40, 300, 180, 40, 60, 420, 60, 80, 140, 10, 16);
    private static final Snapshot STANDARD = new Snapshot(Tier.STANDARD,
            4_400, 1_900, 700, 64, CreditsFormationAct.TOTAL, 900, 56, 260,
            1_300, 160, 280, 500, 6, 10);
    private static final Snapshot EPIC = new Snapshot(Tier.EPIC,
            7_000, 3_200, 1_400, 80, CreditsFormationAct.TOTAL, 1_600, 80, 520,
            1_700, 220, 420, 640, 5, 9);

    private static final ModConfigSpec.Builder COMMON_BUILDER = new ModConfigSpec.Builder();
    private static final ModConfigSpec.ConfigValue<String> DISPLAY_TIER = COMMON_BUILDER
            .comment("Display-budget tier of the final credits sequence:",
                    "verify = low counts for headless/llvmpipe acceptance runs,",
                    "standard = the default live show, epic = thousands (real GPUs).",
                    "/dev credits tier <tier> overrides this until the next restart.")
            .defineInList("displayTier", "standard", List.of("verify", "standard", "epic"));
    public static final ModConfigSpec COMMON_SPEC = COMMON_BUILDER.build();

    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** Runtime override from {@code /dev credits tier} ({@code null} = config rules). */
    @Nullable
    private static volatile Tier override;

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("credits.tier", DevCategory.CUTSCENE,
                        "/dev credits tier",
                        "dev.eclipse.doc.credits.tier", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private CreditsDisplayBudget() {}

    /** The currently selected tier (runtime override beats the config). */
    public static Tier tier() {
        Tier current = override;
        if (current != null) {
            return current;
        }
        return COMMON_SPEC.isLoaded() ? Tier.parse(DISPLAY_TIER.get()) : Tier.STANDARD;
    }

    /** Resolves the current tier into the per-run budget snapshot. */
    static Snapshot snapshot() {
        return switch (tier()) {
            case VERIFY -> VERIFY;
            case STANDARD -> STANDARD;
            case EPIC -> EPIC;
        };
    }

    // ------------------------------------------------------------------ /dev credits tier

    /**
     * {@code /dev credits tier} (bare = show current) and {@code /dev credits tier
     * <verify|standard|epic>} (set the runtime override). Brigadier merges this
     * registration into the {@code /dev credits} tree {@code DevCreditsCommands} owns —
     * no shared file is touched. Takes effect at the NEXT {@code /dev credits start}.
     */
    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        var tierNode = Commands.literal("tier").executes(CreditsDisplayBudget::showTier);
        for (Tier tier : Tier.values()) {
            tierNode.then(Commands.literal(tier.name().toLowerCase(Locale.ROOT))
                    .executes(context -> setTier(context, tier)));
        }
        event.getDispatcher().register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("credits").then(tierNode)));
    }

    private static int showTier(CommandContext<CommandSourceStack> context) {
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.credits.tier_current", tier().name().toLowerCase(Locale.ROOT)), false);
        return 1;
    }

    private static int setTier(CommandContext<CommandSourceStack> context, Tier tier) {
        override = tier;
        EclipseMod.LOGGER.info("CreditsDisplayBudget: tier override set to {} (next credits run)", tier);
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.credits.tier_set", tier.name().toLowerCase(Locale.ROOT)), true);
        return 1;
    }

    // ------------------------------------------------------------------ config wiring

    public static void register(ModContainer modContainer) {
        if (REGISTERED.compareAndSet(false, true)) {
            modContainer.registerConfig(ModConfig.Type.COMMON, COMMON_SPEC, COMMON_FILE_NAME);
        }
    }

    /** Self-registration ({@code CreditsConfig} pattern); no shared config hub edit. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    static final class SelfRegistrar {
        private SelfRegistrar() {}

        @SubscribeEvent
        static void onConstruct(FMLConstructModEvent event) {
            event.enqueueWork(() -> ModList.get().getModContainerById(EclipseMod.MOD_ID)
                    .ifPresent(CreditsDisplayBudget::register));
        }
    }
}
