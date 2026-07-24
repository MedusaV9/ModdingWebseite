package dev.projecteclipse.eclipse.client.sanctum;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * W4-ISLAND geometry v3 (c)+(e) client half — the waterfall-of-light and the crater
 * updraft: two looping managed emitters keyed on the client-synced
 * {@link FxAnchors#ALTAR_CENTER} anchor (zero server blocks / zero new packets).
 * {@code eclipse:sanctum_lightfall} pours a thin quasar column from the island underside
 * ({@value #LIGHTFALL_BELOW_ANCHOR} below the anchor) down into the crater;
 * {@code eclipse:crater_updraft} breathes faint motes up out of the bowl
 * ({@value #UPDRAFT_BELOW_ANCHOR} below the anchor). Offsets derive from the published
 * {@link FloatingSanctumBuilder} / {@link AltarSanctumBuilder} constants, so the client
 * stays in lockstep with the deterministic server geometry.
 *
 * <p><b>Floating gate</b>: the anchor is synced at R10 t=500 while the altar is still
 * grounded inside the vortex — a lightfall then would render underground. The gate is a
 * physical probe: the column only runs while the block {@value #FLOAT_PROBE_BELOW} below
 * the anchor (inside the island/ground air gap, below the deepest belly, above the
 * flattened ground) is loaded AND air, which is only ever true once the island actually
 * floats. Self-correcting, no new sync needed.</p>
 *
 * <p>Window rules as {@code AltarIdleMotes}/{@code LimboAmbience}: AMBIENT channel,
 * hysteresis band ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}) so the boundary
 * never flickers, handles pruned when Veil drops them, everything released under
 * {@code reducedFx} / dimension change / logout, budget refusals retried every
 * {@value #RETRY_TICKS} ticks. Idle cost while far away: one distance check per tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SanctumLightfall {
    private static final ResourceLocation LIGHTFALL_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "sanctum_lightfall");
    private static final ResourceLocation UPDRAFT_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "crater_updraft");

    /** Tall landmark: visible further out than the altar motes, released with hysteresis. */
    private static final double MATERIALIZE_DIST = 96.0D;
    private static final double RELEASE_DIST = 110.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;

    /** Lightfall source: just under the deepest island belly (anchor = altar center Y). */
    private static final int LIGHTFALL_BELOW_ANCHOR = AltarSanctumBuilder.ALTAR_ABOVE_GROUND + 9;
    /** Updraft source: inside the crater bowl, 2 above the flattened-ground datum − depth. */
    private static final int UPDRAFT_BELOW_ANCHOR =
            AltarSanctumBuilder.ALTAR_ABOVE_GROUND + FloatingSanctumBuilder.ISLAND_LIFT + 2;
    /** Floating-gate probe: in the island/ground air gap — air only once the island flies. */
    private static final int FLOAT_PROBE_BELOW =
            AltarSanctumBuilder.ALTAR_ABOVE_GROUND + FloatingSanctumBuilder.ISLAND_LIFT - 3;
    /** Budget-refusal / probe retry cadence (ticks). */
    private static final int RETRY_TICKS = 40;

    @Nullable
    private static ParticleEmitter lightfall;
    @Nullable
    private static ParticleEmitter updraft;
    private static int retryCountdown;

    private SanctumLightfall() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            clear();
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null) {
            clear();
            return;
        }
        boolean anyLive = lightfall != null || updraft != null;
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        if (distSq > (anyLive ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            clear();
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        lightfall = prune(lightfall);
        updraft = prune(updraft);
        if (lightfall != null && updraft != null) {
            return;
        }
        if (--retryCountdown > 0) {
            return;
        }
        retryCountdown = RETRY_TICKS;
        BlockPos probe = BlockPos.containing(anchor).below(FLOAT_PROBE_BELOW);
        if (!level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                SectionPos.blockToSectionCoord(probe.getZ()))
                || !level.getBlockState(probe).isAir()) {
            clear(); // island not floating (yet) — the grounded-altar anchor gate
            retryCountdown = RETRY_TICKS; // keep the probe on the retry cadence too
            return;
        }
        if (lightfall == null) {
            lightfall = QuasarSpawner.spawnManaged(LIGHTFALL_EMITTER,
                    anchor.add(0.0D, -LIGHTFALL_BELOW_ANCHOR, 0.0D), FxBudget.Channel.AMBIENT);
        }
        if (updraft == null) {
            updraft = QuasarSpawner.spawnManaged(UPDRAFT_EMITTER,
                    anchor.add(0.0D, -UPDRAFT_BELOW_ANCHOR, 0.0D), FxBudget.Channel.AMBIENT);
        }
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    /** Drops a handle Veil already removed (level swap cleared the particle manager). */
    @Nullable
    private static ParticleEmitter prune(@Nullable ParticleEmitter emitter) {
        if (emitter == null) {
            return null;
        }
        try {
            return emitter.isRemoved() ? null : emitter;
        } catch (Throwable t) {
            return null;
        }
    }

    private static void clear() {
        lightfall = release(lightfall);
        updraft = release(updraft);
        retryCountdown = 0;
    }

    @Nullable
    private static ParticleEmitter release(@Nullable ParticleEmitter emitter) {
        if (emitter != null) {
            try {
                if (!emitter.isRemoved()) {
                    emitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (LimboAmbience pattern).
            }
        }
        return null;
    }
}
