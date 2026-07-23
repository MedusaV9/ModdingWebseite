package dev.projecteclipse.eclipse.worldgen.vanilla;

import java.util.Collection;
import java.util.Set;
import java.util.concurrent.ConcurrentMap;

import com.google.common.collect.MapMaker;
import com.mojang.logging.LogUtils;

import org.slf4j.Logger;

import net.minecraft.core.Holder;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeGenerationSettings;
import net.minecraft.world.level.levelgen.GenerationStep;
import net.minecraft.world.level.levelgen.carver.ConfiguredWorldCarver;
import net.minecraft.world.level.levelgen.placement.PlacedFeature;

/**
 * Per-biome generation settings filter of the disc generator (design D1.1): returns each
 * biome's REAL {@link BiomeGenerationSettings} minus a deny-list of placed features, so
 * vanilla vegetation, springs, geodes, monster rooms and stone blobs decorate the disc
 * while every vanilla mineral-ore feature stays out (the {@code worldgen/ore} OreField
 * engine owns ore placement — stage-annulus gated, never surface-exposed).
 *
 * <p>The deny-list is the union of {@link #VANILLA_ORE_DENY} (hardcoded vanilla mineral
 * ore placed-feature ids; stone-variety blobs like granite/diorite/andesite/tuff/dirt/
 * gravel/clay and nether magma/soul-sand/blackstone stay allowed) and a config-driven
 * set pushed via {@link #setConfigDeny} from {@code worldgen_tuning.json →
 * features.deny[]} (loaded by W1.5's {@code GrowthPacing}, see the W1.1 wiring notes).</p>
 *
 * <p><b>Freeze semantics</b>: {@code ChunkGenerator} memoises its feature-step ordering
 * ({@code featuresPerStep}) from these settings on first decoration. A deny-list that
 * changed afterwards would desynchronise the sorted step index from the per-biome lists
 * and could place the WRONG feature (index aliasing). The filter therefore freezes on
 * the first {@link #settingsFor} call; later {@link #setConfigDeny} pushes with a
 * different content are logged and ignored — deny changes take effect on the next
 * server boot. Carvers are never filtered.</p>
 */
public final class BiomeFeatureFilter {
    private static final Logger LOGGER = LogUtils.getLogger();

    /**
     * Vanilla mineral-ore placed features replaced by the OreField engine (D5). Exact
     * 1.21.1 ids — note {@code ore_debris_small} (not {@code ore_ancient_debris_small}).
     */
    private static final Set<ResourceLocation> VANILLA_ORE_DENY = Set.of(
            ResourceLocation.withDefaultNamespace("ore_coal_upper"),
            ResourceLocation.withDefaultNamespace("ore_coal_lower"),
            ResourceLocation.withDefaultNamespace("ore_copper"),
            ResourceLocation.withDefaultNamespace("ore_copper_large"),
            ResourceLocation.withDefaultNamespace("ore_iron_upper"),
            ResourceLocation.withDefaultNamespace("ore_iron_middle"),
            ResourceLocation.withDefaultNamespace("ore_iron_small"),
            ResourceLocation.withDefaultNamespace("ore_gold"),
            ResourceLocation.withDefaultNamespace("ore_gold_lower"),
            ResourceLocation.withDefaultNamespace("ore_gold_extra"),
            ResourceLocation.withDefaultNamespace("ore_gold_nether"),
            ResourceLocation.withDefaultNamespace("ore_gold_deltas"),
            ResourceLocation.withDefaultNamespace("ore_redstone"),
            ResourceLocation.withDefaultNamespace("ore_redstone_lower"),
            ResourceLocation.withDefaultNamespace("ore_lapis"),
            ResourceLocation.withDefaultNamespace("ore_lapis_buried"),
            ResourceLocation.withDefaultNamespace("ore_diamond"),
            ResourceLocation.withDefaultNamespace("ore_diamond_medium"),
            ResourceLocation.withDefaultNamespace("ore_diamond_large"),
            ResourceLocation.withDefaultNamespace("ore_diamond_buried"),
            ResourceLocation.withDefaultNamespace("ore_emerald"),
            ResourceLocation.withDefaultNamespace("ore_quartz_nether"),
            ResourceLocation.withDefaultNamespace("ore_quartz_deltas"),
            ResourceLocation.withDefaultNamespace("ore_ancient_debris_large"),
            ResourceLocation.withDefaultNamespace("ore_debris_small"));

    /**
     * Filtered settings per biome holder. Weak identity keys: holders are per-registry
     * singletons, and a datapack reload / next server boot must not pin the old registry.
     */
    private static final ConcurrentMap<Holder<Biome>, BiomeGenerationSettings> CACHE =
            new MapMaker().weakKeys().makeMap();

    private static volatile Set<ResourceLocation> configDeny = Set.of();
    private static volatile boolean frozen = false;

    private BiomeFeatureFilter() {}

    /**
     * The biome's real generation settings minus the deny-list; cached per holder. This
     * is the disc generator's {@code generationSettingsGetter}, so vanilla decoration,
     * carver lookups and {@code BiomeFilter} placement checks all agree on one filtered
     * view. Freezes the deny-list on first use (see class contract). Thread-safe.
     */
    public static BiomeGenerationSettings settingsFor(Holder<Biome> biome) {
        frozen = true;
        BiomeGenerationSettings cached = CACHE.get(biome);
        if (cached != null) {
            return cached;
        }
        return CACHE.computeIfAbsent(biome, BiomeFeatureFilter::filter);
    }

    /**
     * Publishes the {@code worldgen_tuning.json → features.deny[]} list (W1.5's
     * {@code GrowthPacing} loader pushes here on reload; see P1-W1.1 wiring). Must run
     * before the first chunk decorates — later pushes that would CHANGE the effective
     * deny-list are ignored with a warning and need a server restart to apply.
     */
    public static void setConfigDeny(Collection<ResourceLocation> ids) {
        Set<ResourceLocation> copy = Set.copyOf(ids);
        if (frozen) {
            if (!copy.equals(configDeny)) {
                LOGGER.warn("eclipse: features.deny changed after worldgen started ({} -> {} entries); "
                        + "the feature deny-list is frozen per boot — restart to apply", configDeny.size(), copy.size());
            }
            return;
        }
        configDeny = copy;
    }

    /** The currently active config-driven deny ids (frozen once decoration starts). */
    public static Set<ResourceLocation> configDeny() {
        return configDeny;
    }

    private static BiomeGenerationSettings filter(Holder<Biome> biome) {
        BiomeGenerationSettings real = biome.value().getGenerationSettings();
        Set<ResourceLocation> deny = configDeny;
        boolean changed = false;
        StepPreservingBuilder builder = new StepPreservingBuilder();
        for (GenerationStep.Carving step : GenerationStep.Carving.values()) {
            for (Holder<ConfiguredWorldCarver<?>> carver : real.getCarvers(step)) {
                builder.addCarver(step, carver);
            }
        }
        var steps = real.features();
        for (int step = 0; step < steps.size(); step++) {
            for (Holder<PlacedFeature> feature : steps.get(step)) {
                if (isDenied(feature, deny)) {
                    changed = true;
                    continue;
                }
                builder.addFeature(step, feature);
            }
        }
        if (!changed) {
            return real; // keep the original instance (and its HolderSet identities)
        }
        // Preserve the step count even when a tail step lost all its features, so the
        // per-step index stays aligned with the generator's sorted feature table.
        builder.ensureSteps(steps.size());
        return builder.build();
    }

    private static boolean isDenied(Holder<PlacedFeature> feature, Set<ResourceLocation> deny) {
        ResourceLocation id = feature.unwrapKey().map(key -> key.location()).orElse(null);
        return id != null && (VANILLA_ORE_DENY.contains(id) || deny.contains(id));
    }

    /** Exposes {@code addFeatureStepsUpTo} so empty tail steps survive the rebuild. */
    private static final class StepPreservingBuilder extends BiomeGenerationSettings.PlainBuilder {
        void ensureSteps(int count) {
            if (count > 0) {
                this.addFeatureStepsUpTo(count - 1);
            }
        }
    }
}
