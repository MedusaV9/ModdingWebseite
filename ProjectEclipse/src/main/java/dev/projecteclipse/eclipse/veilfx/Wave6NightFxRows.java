package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * WAVE6 (F-106 A) — Team A's {@link PhotonFxRegistry} row registrar: the two night-dread
 * one-shot cues, docked onto the {@code EclipseSpawner} night loop. Both assets are
 * authored programmatically by {@code tools/photon/wave6_night_fx.py} (fxlib,
 * uuid5-deterministic); re-run that script instead of hand-editing the gzip-NBT.
 *
 * <ul>
 *   <li><b>Pack landing stage</b> ({@link #CUE_PACK_LAND}) — A4: the landed Umbral
 *       Stalker pack's existing howl finally gets a picture: a low ground-fog ring plus
 *       3–4 brief eye glints at the pack center ({@code EclipseSpawner.spawnStalkerPack},
 *       range = the howl's 64 blocks). {@code a} = landed pack size (scales the ring
 *       ~0.9→1.1), {@code b} = 1 on Umbral Nights / 0 otherwise (informational — one
 *       shared asset, Photon has no runtime tint).</li>
 *   <li><b>Dawn release</b> ({@link #CUE_DAWN_RELEASE}) — A6: the inverse of
 *       {@code wave3_night_omen} — a bright mote ring rising off the receiving player
 *       and dissolving, on the {@code FxPayloads.sendFxEventTo} personal lane
 *       ({@code EclipseSpawner.clearNightEvent}). {@code a} = 1 the ended event was
 *       umbral / 0 pale (reserved; the release is one shared "breathe out" look).</li>
 * </ul>
 *
 * <p>Cue ids follow the {@code Wave3FxRows} two-sided naming precedent: the server
 * hooks re-derive the same {@code FxCues.cue("…")} ids inline, so {@code FxCues.java}
 * (frozen) stays untouched. Quasar legs are {@code null} — legal for NEW cues (pre-row
 * baseline was nothing) — but each leg carries a hand-rolled VANILLA fallback for
 * Photon-less clients (plan §3 A4: a {@code CAMPFIRE_COSY_SMOKE} ring; the dawn release
 * degrades to a few rising END_ROD motes), so the beat never drops below a readable
 * sketch. {@code reducedFx} drops both entirely: the howl carries the landing, the
 * exhale sound + returning daylight carry the dawn. One-shots only — no WINDOWED loop
 * bookkeeping; Photon's same-anchor dedup stays on as the free anti-stack guard.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class Wave6NightFxRows {
    /**
     * WAVE6 A4 — stalker pack landing stage ({@code a} = pack size 1–4, {@code b} =
     * 1 umbral / 0 normal night; ≤3 s one-shot at the pack center, ground-anchored).
     */
    public static final ResourceLocation CUE_PACK_LAND = FxCues.cue("wave6_pack_land");
    /**
     * WAVE6 A6 — dawn release ({@code a} = 1 ended-umbral / 0 ended-pale, {@code b}
     * unused; ~5 s one-shot at the receiving player's feet, personal lane).
     */
    public static final ResourceLocation CUE_DAWN_RELEASE = FxCues.cue("wave6_dawn_release");

    /** Pack-land scale ramp: a 1-straggler landing ~0.9, a full 4-pack 1.1. */
    private static final double PACK_SCALE_BASE = 0.85D;
    private static final double PACK_SCALE_PER_MEMBER = 0.06D;
    private static final double PACK_SCALE_MIN = 0.9D;
    private static final double PACK_SCALE_MAX = 1.1D;

    /** Vanilla-fallback geometry (Photon-less clients only). */
    private static final int FALLBACK_RING_COUNT = 12;
    private static final double FALLBACK_RING_RADIUS = 1.8D;
    private static final int FALLBACK_RELEASE_COUNT = 8;
    private static final double FALLBACK_RELEASE_RADIUS = 1.2D;

    private Wave6NightFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // A4 — BURST: positional, at most one per 100t spawner pass, naturally spread
        // across the night; the lean two-emitter asset keeps the worst case cheap.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_PACK_LAND,
                fx("wave6_pack_land"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave6NightFxRows::packLandLeg));
        // A6 — SEQUENCE: at most one per dawn, personal lane means exactly one copy
        // per client, ever (the wave3_night_omen twin, inverted).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_DAWN_RELEASE,
                fx("wave6_dawn_release"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave6NightFxRows::dawnReleaseLeg));
    }

    // ------------------------------------------------------------------ A4 leg

    /**
     * Pack-land leg: Photon ring+glints scaled with the landed pack size ({@code a});
     * Photon refused/absent → the plan's vanilla CAMPFIRE_COSY_SMOKE ground ring.
     */
    private static boolean packLandLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the landing howl already carries the fairness cue
        }
        double scale = Mth.clamp(PACK_SCALE_BASE + PACK_SCALE_PER_MEMBER * a,
                PACK_SCALE_MIN, PACK_SCALE_MAX);
        if (PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT
                .withScale(scale, scale, scale))) {
            return true;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level != null) {
            RandomSource random = level.random;
            for (int i = 0; i < FALLBACK_RING_COUNT; i++) {
                double angle = (Math.PI * 2.0D / FALLBACK_RING_COUNT) * i
                        + random.nextDouble() * 0.35D;
                double radius = FALLBACK_RING_RADIUS + random.nextDouble() * 0.8D;
                level.addParticle(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                        pos.x + Math.cos(angle) * radius, pos.y + 0.15D,
                        pos.z + Math.sin(angle) * radius,
                        0.0D, 0.02D + random.nextDouble() * 0.02D, 0.0D);
            }
        }
        return true;
    }

    // ------------------------------------------------------------------ A6 leg

    /**
     * Dawn-release leg: the personal rising-mote ring; Photon refused/absent → a few
     * rising END_ROD motes around the player (the omen's inverse, sketched).
     */
    private static boolean dawnReleaseLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the quiet exhale + returning daylight carry the release
        }
        if (PhotonBridge.spawn(photonFx, pos)) {
            return true;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level != null) {
            RandomSource random = level.random;
            for (int i = 0; i < FALLBACK_RELEASE_COUNT; i++) {
                double angle = (Math.PI * 2.0D / FALLBACK_RELEASE_COUNT) * i
                        + random.nextDouble() * 0.4D;
                level.addParticle(ParticleTypes.END_ROD,
                        pos.x + Math.cos(angle) * FALLBACK_RELEASE_RADIUS,
                        pos.y + 0.2D + random.nextDouble() * 0.4D,
                        pos.z + Math.sin(angle) * FALLBACK_RELEASE_RADIUS,
                        0.0D, 0.05D + random.nextDouble() * 0.03D, 0.0D);
            }
        }
        return true;
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
