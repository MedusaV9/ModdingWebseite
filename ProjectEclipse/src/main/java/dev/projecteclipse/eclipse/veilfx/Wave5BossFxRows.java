package dev.projecteclipse.eclipse.veilfx;

import java.util.List;
import java.util.function.Predicate;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.ferryman.ArenaDimension;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WAVE5 (F-105 A) A6 — Team A's {@link PhotonFxRegistry} row registrar: the boss-trophy
 * resonance wisp. The four boss death scripts leave a trophy monument at the tracked
 * arena center ({@code placeTrophyMonument} in Herald/Ferryman/RiftWarden/FogTyrant) and
 * publish a {@link FxAnchors} anchor on the monument's cap block; the {@link TrophyWisp}
 * window below breathes one quiet {@code eclipse:wave5_trophy_wisp} Photon loop over
 * each anchored monument while a player is close enough to look at it.
 *
 * <p>The asset is authored programmatically by {@code tools/photon/wave5_boss_fx.py}
 * (fxlib, uuid5-deterministic); re-run that script instead of hand-editing the gzip-NBT.
 * ONE shared asset serves all four monuments — the wisp is soul residue, not a
 * boss-specific effect — but each boss gets its OWN loop row/anchor id, because
 * {@link PhotonFxRegistry#ensureLoop} manages exactly one live loop per logical id and
 * the four monuments stand in different places.</p>
 *
 * <p>Cue/anchor ids follow the {@code SmallCueFxRows} two-sided precedent: both sides
 * derive the same {@code FxCues.cue("wave5_trophy_<boss>")} id (the boss entities derive
 * it server-side as their {@link FxAnchors} key, this registrar re-derives it as the
 * loop-row logical id), so {@code FxCues.java} — not Team-A ground this wave — stays
 * untouched. The rows are loop rows (WINDOWED-only law, INTEGRATION.md §4): they are
 * never payload-fired; registration is what carries the budget policy and what
 * {@code /dev photon} introspection lists.</p>
 *
 * <p><b>Scope honesty</b>: {@link FxAnchors} anchors are transient (in-memory, re-sent
 * to every login, cleared on server stop) and their payload carries no dimension — so
 * the wisp is a server-session flourish over the PERSISTENT monument block, and each
 * window adds its own per-boss dimension gate (Limbo/arena for the Ferryman's stern
 * lantern, overworld for the other three) so a Limbo anchor can never ghost-render at
 * the same coordinates in the overworld. {@code reducedFx} skips the loop entirely
 * (plan §3 A6): the monument itself is the baseline read.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class Wave5BossFxRows {
    /** Herald trophy (amethyst cluster on the dais center) — overworld altar arena. */
    public static final ResourceLocation CUE_TROPHY_HERALD = FxCues.cue("wave5_trophy_herald");
    /** Ferryman trophy (soul lantern on the stern deck) — Limbo ship / ferryman arena. */
    public static final ResourceLocation CUE_TROPHY_FERRYMAN = FxCues.cue("wave5_trophy_ferryman");
    /** Rift Warden trophy (obsidian + end rod at the ring center) — overworld vault. */
    public static final ResourceLocation CUE_TROPHY_WARDEN = FxCues.cue("wave5_trophy_warden");
    /** Fog Tyrant trophy (lightning rod at the lair center) — overworld storm site. */
    public static final ResourceLocation CUE_TROPHY_TYRANT = FxCues.cue("wave5_trophy_tyrant");

    /** The one shared asset: {@code assets/eclipse/fx/wave5_trophy_wisp.fx}. */
    private static final ResourceLocation TROPHY_WISP_FX =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wave5_trophy_wisp");

    private Wave5BossFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Photon-only garnish (Quasar leg null — legal for NEW cues, whose pre-row
        // baseline was nothing; the monument block is the photon-less read). AMBIENT:
        // this idles for minutes, it must never outbid a fight burst.
        for (ResourceLocation cue : List.of(CUE_TROPHY_HERALD, CUE_TROPHY_FERRYMAN,
                CUE_TROPHY_WARDEN, CUE_TROPHY_TYRANT)) {
            PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                    cue,
                    TROPHY_WISP_FX,
                    null,
                    FxBudget.Channel.AMBIENT,
                    PhotonFxRegistry.Mode.LAYER,
                    true));
        }
    }

    /**
     * The windowed-loop controller — the {@code NetherPitPlume}/{@code SanctumLightfall}
     * pattern, times four: each wisp owns a hysteresis band
     * ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}) around its {@link FxAnchors}
     * anchor, gated on its boss's dimension; healthy legs re-ensure every tick
     * (idempotent prune inside the registry), refusals back off {@value #RETRY_TICKS}
     * ticks. Idle cost per unset/far anchor: one map lookup / one distance check per
     * tick. Released on {@code reducedFx} / dimension mismatch / walk-away / logout.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class TrophyWisp {
        /** Close-look band: the wisp is a monument detail, not a landmark beacon. */
        static final double MATERIALIZE_DIST = 28.0D;
        static final double RELEASE_DIST = 36.0D;
        private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
        private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
        /** Refused-spawn retry cadence (ticks) — the NetherPitPlume cadence. */
        private static final int RETRY_TICKS = 40;

        /** One per-boss window: anchor/cue id + dimension gate + hysteresis state. */
        private static final class Wisp {
            final ResourceLocation id;
            final Predicate<ResourceKey<Level>> dimensionGate;
            boolean open;
            int retryCountdown;

            Wisp(ResourceLocation id, Predicate<ResourceKey<Level>> dimensionGate) {
                this.id = id;
                this.dimensionGate = dimensionGate;
            }
        }

        private static final Wisp[] WISPS = {
                new Wisp(CUE_TROPHY_HERALD, dim -> dim == Level.OVERWORLD),
                new Wisp(CUE_TROPHY_FERRYMAN,
                        dim -> dim == LimboDimension.LIMBO || ArenaDimension.isArena(dim)),
                new Wisp(CUE_TROPHY_WARDEN, dim -> dim == Level.OVERWORLD),
                new Wisp(CUE_TROPHY_TYRANT, dim -> dim == Level.OVERWORLD),
        };

        private TrophyWisp() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            Minecraft minecraft = Minecraft.getInstance();
            ClientLevel level = minecraft.level;
            if (level == null || EclipseClientConfig.reducedFx()) {
                for (Wisp wisp : WISPS) {
                    close(wisp, false);
                }
                return;
            }
            Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
            for (Wisp wisp : WISPS) {
                tickWisp(wisp, level, camera, minecraft.isPaused());
            }
        }

        private static void tickWisp(Wisp wisp, ClientLevel level, Vec3 camera, boolean paused) {
            Vec3 anchor = FxAnchors.get(wisp.id);
            if (anchor == null || !wisp.dimensionGate.test(level.dimension())) {
                close(wisp, false);
                return;
            }
            double distSq = camera.distanceToSqr(anchor);
            if (distSq > (wisp.open ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
                close(wisp, true); // walked away: graceful fade, not a pop
                return;
            }
            if (paused) {
                return; // keep the window, freeze the cadence
            }
            if (--wisp.retryCountdown > 0) {
                return;
            }
            wisp.open = true;
            // Healthy leg: re-ensure every tick (idempotent prune + re-spawn inside the
            // registry). Refused (photon absent / executor budget): back off RETRY_TICKS.
            wisp.retryCountdown = PhotonFxRegistry.ensureLoop(wisp.id, anchor) ? 1 : RETRY_TICKS;
        }

        /** Disconnect reset (the registry's own DisconnectReset releases the legs too). */
        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            for (Wisp wisp : WISPS) {
                close(wisp, false);
            }
        }

        private static void close(Wisp wisp, boolean graceful) {
            if (wisp.open) {
                PhotonFxRegistry.releaseLoop(wisp.id, graceful);
            }
            wisp.open = false;
            wisp.retryCountdown = 0;
        }
    }
}
