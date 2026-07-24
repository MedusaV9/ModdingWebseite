package dev.projecteclipse.eclipse.client.drama;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.client.CaptionRenderer;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * W-P-ALTAR — client half of the altar level-up CEREMONY: dispatched from
 * {@code FxPayloads.handleFxEvent} on {@code FX_ALTAR_LEVELUP} ({@code pos} = altar,
 * {@code a} = the freshly reached level), it sequences a tick-scripted composition.
 *
 * <p><b>W-P-ALTAR2 dramaturgy:</b> every ceremony (tier ≥ 1) is book-ended by an
 * ANTICIPATION phase — {@value #ANTICIPATION_TICKS} t of inward-spiraling motes
 * ({@code eclipse:altar_indraw}, vortex + point-attractor pull) under a three-step
 * rising hum — and a SETTLE phase of drifting ash-light afterglow
 * ({@code eclipse:altar_afterglow}) with a low falling hum once the burst has landed.
 * The burst beats (below) shift {@code +ANTICIPATION_TICKS} accordingly; the server's
 * own immediate beam/ring stays at t=0 as the "the altar answers" spark that the
 * anticipation then builds on. Tier 0 skips both phases (minimal profile law).</p>
 *
 * <p>The burst ESCALATES with the level (every level replays the beats below it, then
 * adds its own):</p>
 * <ul>
 *   <li><b>L1</b> — unlock sting + one echo of the flattened ring burst.</li>
 *   <li><b>L2</b> — + screen shockwave ring + a climbing pillar of light (four
 *       {@code eclipse:altar_pillar} bursts stacked upward over ~½ s).</li>
 *   <li><b>L3</b> — + orbital burst around the island ({@code altar_orbit_burst}) +
 *       three waves of glyph rain from ten blocks up ({@code altar_glyph_rain}).</li>
 *   <li><b>L4</b> — + sky-crack flash (a 2-tick violet-white fullscreen flash via the
 *       {@link CaptionRenderer#fade} envelope), a hard shockwave and a bass drop
 *       ({@code event.end_shatter_rumble} pitched 0.72 at the listener).</li>
 *   <li><b>L5</b> — + full corona ignition: the {@link #skySurge} envelope flares the
 *       {@code AltarVeilSky} crown/signature for ~5 s ({@code altar_corona_ignite} burst
 *       at the altar), stacked rumbles — the beat every player sees in the sky, anywhere
 *       on the map.</li>
 * </ul>
 *
 * <p>One whisper caption per ceremony ({@code eclipse.caption.altar_level_<n>} — the
 * Other acknowledging the offering; EclipseLang's {@code eclipse.caption.} prefix).</p>
 *
 * <p><b>Performance/degradation (repo law):</b> every emitter spawn rides the
 * {@link FxBudget.Channel#SEQUENCE} channel (reducedFx halves the budget automatically);
 * particle beats are DISTANCE-CULLED at build time ({@value #EMITTER_RANGE} blocks —
 * matching the server's beam view range), while screen/sound beats (flash, shockwave,
 * bass drop, sky surge) stay world-visible by design. Tier 0
 * ({@link FxBudget#qualityTier()}) additionally skips the fullscreen flash and the
 * caption. The script is a handful of {@code Runnable}s; per-tick work while idle is one
 * empty-list check.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarCeremonyFx {
    private static final ResourceLocation PILLAR = emitter("altar_pillar");
    private static final ResourceLocation GLYPH_RAIN = emitter("altar_glyph_rain");
    private static final ResourceLocation ORBIT_BURST = emitter("altar_orbit_burst");
    private static final ResourceLocation CORONA_IGNITE = emitter("altar_corona_ignite");
    /** W-P-ALTAR2: anticipation in-draw + settle ash-light afterglow emitters. */
    private static final ResourceLocation INDRAW = emitter("altar_indraw");
    private static final ResourceLocation AFTERGLOW = emitter("altar_afterglow");

    /** Particle beats only materialize within this camera range (beam view-range twin). */
    private static final double EMITTER_RANGE = 96.0D;

    /** Anticipation phase length (2 s of inward-spiraling motes + rising hum). */
    private static final int ANTICIPATION_TICKS = 40;
    /** Settle phase start after the burst, stretched a little per level. */
    private static final int SETTLE_BASE_DELAY_TICKS = 34;
    private static final int SETTLE_PER_LEVEL_TICKS = 6;

    /** Offering sky-glow envelope (L3+ aurora response): rise 5 t, release 35 t. */
    private static final int OFFER_GLOW_IN_TICKS = 5;
    private static final int OFFER_GLOW_OUT_TICKS = 35;

    /** Sky-surge envelope (L5 corona ignition): rise 12 t, hold 30 t, release 60 t. */
    private static final int SURGE_IN_TICKS = 12;
    private static final int SURGE_HOLD_TICKS = 30;
    private static final int SURGE_OUT_TICKS = 60;
    /** Surge echo-ring travel window (EVAL-POL-F #6): outward over the rise + hold beats. */
    private static final int SURGE_ECHO_TRAVEL_TICKS = SURGE_IN_TICKS + SURGE_HOLD_TICKS;

    private record Step(int at, Runnable action) {}

    /** Pending ceremony steps, client thread only; empty while no ceremony is live. */
    private static final List<Step> STEPS = new ArrayList<>();
    /** Pause-frozen ceremony clock (advances with unpaused client ticks). */
    private static int clock;
    private static int ceremonyStart;
    private static int surgeStart = Integer.MIN_VALUE;
    /** W-P-ALTAR2: last offering-swallow arrival (drives the L3+ aurora glow). */
    private static int offeringGlowStart = Integer.MIN_VALUE;

    private AltarCeremonyFx() {}

    private static ResourceLocation emitter(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name);
    }

    // ------------------------------------------------------------------ payload seam

    /** {@code FX_ALTAR_LEVELUP} dispatch: pos = altar center, level = freshly reached level. */
    public static void start(Vec3 pos, int level) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel clientLevel = minecraft.level;
        if (clientLevel == null) {
            return;
        }
        int lvl = Mth.clamp(level, 1, 5);
        int tier = FxBudget.qualityTier();
        boolean near = minecraft.gameRenderer.getMainCamera().getPosition()
                .distanceToSqr(pos) <= EMITTER_RANGE * EMITTER_RANGE;
        STEPS.clear();
        ceremonyStart = clock;

        // --- W-P-ALTAR2 anticipation: a held breath before the strike (tier ≥ 1). The
        // sting stays at t=0 (the "look up" announcement), then motes spiral INTO the
        // altar while a three-step hum rises; every burst beat shifts +lead. ---
        int lead = tier >= 1 ? ANTICIPATION_TICKS : 0;
        at(0, () -> soundAt(pos, EclipseSounds.UI_UNLOCK_STING.get(),
                0.9F, 0.85F + 0.06F * lvl));
        if (lead > 0) {
            at(2, () -> soundAt(pos, EclipseSounds.EVENT_BEAM_HUM.get(), 0.55F, 0.78F));
            at(16, () -> soundAt(pos, EclipseSounds.EVENT_BEAM_HUM.get(), 0.65F, 1.0F));
            at(30, () -> soundAt(pos, EclipseSounds.EVENT_BEAM_HUM.get(), 0.75F, 1.24F));
            if (near) {
                // One long-lived in-draw emitter covers the whole window (vortex swirl
                // + inward point-attractor) — a single SEQUENCE charge.
                at(2, () -> QuasarSpawner.spawn(INDRAW,
                        pos.add(0.0D, 0.8D, 0.0D), FxBudget.Channel.SEQUENCE));
            }
        }

        // --- L1 base: a second flattened-ring echo over the server's own send ---
        if (near) {
            at(lead + 8, () -> QuasarSpawner.spawn(S2CQuasarPayload.ALTAR_LEVELUP_RING,
                    pos.add(0.0D, 0.6D, 0.0D), FxBudget.Channel.SEQUENCE));
        }

        // --- L2: shockwave ring + pillar of light ---
        if (lvl >= 2) {
            at(lead + 2, () -> EclipseFxState.startShockwave(pos, 0.45F + 0.08F * lvl, 36));
            at(lead + 4, () -> soundAt(pos, EclipseSounds.EVENT_EMERGE.get(), 0.9F, 1.15F));
            if (near) {
                for (int i = 0; i < 4; i++) {
                    double height = i * 2.5D;
                    at(lead + 4 + i * 3, () -> QuasarSpawner.spawn(PILLAR,
                            pos.add(0.0D, height, 0.0D), FxBudget.Channel.SEQUENCE));
                }
            }
        }

        // --- L3: orbital burst + glyph rain ---
        if (lvl >= 3) {
            at(lead + 10, () -> soundAt(pos, EclipseSounds.EVENT_ECLIPSE_DRONE.get(), 0.7F, 1.25F));
            if (near) {
                at(lead + 10, () -> QuasarSpawner.spawn(ORBIT_BURST,
                        pos.add(0.0D, 1.5D, 0.0D), FxBudget.Channel.SEQUENCE));
                for (int wave = 0; wave < 3; wave++) {
                    at(lead + 14 + wave * 8, () -> QuasarSpawner.spawn(GLYPH_RAIN,
                            pos.add(0.0D, 10.0D, 0.0D), FxBudget.Channel.SEQUENCE));
                }
            }
        }

        // --- L4: sky-crack flash + bass drop (world-visible: no distance gate) ---
        if (lvl >= 4) {
            if (tier >= 1) {
                // ARGB 0x9CEADCFF: a 2-tick violet-white crack of light, 16-tick release.
                at(lead + 2, () -> CaptionRenderer.fade(2, 3, 16, 0x9CEADCFF));
            }
            at(lead + 2, () -> EclipseFxState.startShockwave(pos, 0.9F, 50));
            at(lead + 2, () -> soundAtListener(EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(), 1.0F, 0.72F));
            at(lead + 6, () -> soundAt(pos, EclipseSounds.EVENT_STORM_BURST.get(), 1.0F, 0.65F));
        }

        // --- L5: full corona ignition + the world-visible sky flare ---
        if (lvl >= 5) {
            at(lead, () -> surgeStart = clock);
            at(lead + 8, () -> soundAtListener(EclipseSounds.EVENT_EMERGE.get(), 1.0F, 0.8F));
            at(lead + 20, () -> soundAtListener(EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(), 0.9F, 0.55F));
            if (near) {
                at(lead + 8, () -> QuasarSpawner.spawn(CORONA_IGNITE,
                        pos.add(0.0D, 2.0D, 0.0D), FxBudget.Channel.SEQUENCE));
            }
        }

        // One whisper from the Other, once the visual beats have landed.
        if (tier >= 1) {
            at(lead + 24, () -> CaptionRenderer.enqueue("eclipse.caption.altar_level_" + lvl,
                    0, S2CCaptionPayload.STYLE_WHISPER));
        }

        // --- W-P-ALTAR2 settle: drifting ash-light + a low falling hum as the burst
        // particles die away (tier ≥ 1; two afterglow spawns, staggered in height). ---
        if (tier >= 1) {
            int settle = lead + SETTLE_BASE_DELAY_TICKS + lvl * SETTLE_PER_LEVEL_TICKS;
            at(settle, () -> soundAt(pos, EclipseSounds.EVENT_BEAM_HUM.get(), 0.5F, 0.6F));
            if (near) {
                at(settle, () -> QuasarSpawner.spawn(AFTERGLOW,
                        pos.add(0.0D, 1.2D, 0.0D), FxBudget.Channel.SEQUENCE));
                at(settle + 22, () -> QuasarSpawner.spawn(AFTERGLOW,
                        pos.add(0.0D, 2.4D, 0.0D), FxBudget.Channel.SEQUENCE));
            }
        }
    }

    /** Ceremony surge 0..1 for {@code AltarVeilSky} (L5 corona ignition flare). */
    public static float skySurge(float partialTick) {
        if (surgeStart == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float t = clock + partialTick - surgeStart;
        if (t < SURGE_IN_TICKS) {
            return smooth(t / SURGE_IN_TICKS);
        }
        t -= SURGE_IN_TICKS;
        if (t < SURGE_HOLD_TICKS) {
            return 1.0F;
        }
        t -= SURGE_HOLD_TICKS;
        if (t < SURGE_OUT_TICKS) {
            return smooth(1.0F - t / SURGE_OUT_TICKS);
        }
        surgeStart = Integer.MIN_VALUE;
        return 0.0F;
    }

    /**
     * Monotonic 0→1 surge-echo travel clock (EVAL-POL-F #6): runs once from surge start
     * over {@value #SURGE_ECHO_TRAVEL_TICKS} ticks so {@code AltarVeilSky}'s echo ring fires
     * OUTWARD and dissipates — it never parks at max radius or retracts with the decaying
     * {@link #skySurge} envelope. Returns 1 (fully dissipated) while no surge is live.
     */
    public static float skySurgeEchoTravel(float partialTick) {
        if (surgeStart == Integer.MIN_VALUE) {
            return 1.0F;
        }
        float t = clock + partialTick - surgeStart;
        return Mth.clamp(t / SURGE_ECHO_TRAVEL_TICKS, 0.0F, 1.0F);
    }

    /**
     * W-P-ALTAR2: an offering-swallow just ARRIVED at the altar (called by
     * {@code OfferingSwallowFx} on the arrival tick) — arms the short sky-glow envelope
     * the L3+ aurora veil reads. Value-agnostic by design: every offering brightens the
     * sky the same amount (the value tell stays offerer-private).
     */
    public static void notifyOfferingSwallowed() {
        offeringGlowStart = clock;
    }

    /** Offering sky-glow 0..1 for {@code AltarVeilSky}'s L3+ aurora response. */
    public static float offeringSkyGlow(float partialTick) {
        if (offeringGlowStart == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float t = clock + partialTick - offeringGlowStart;
        if (t < OFFER_GLOW_IN_TICKS) {
            return smooth(t / OFFER_GLOW_IN_TICKS);
        }
        t -= OFFER_GLOW_IN_TICKS;
        if (t < OFFER_GLOW_OUT_TICKS) {
            return smooth(1.0F - t / OFFER_GLOW_OUT_TICKS);
        }
        offeringGlowStart = Integer.MIN_VALUE;
        return 0.0F;
    }

    // ------------------------------------------------------------------ tick loop

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            STEPS.clear();
            surgeStart = Integer.MIN_VALUE;
            offeringGlowStart = Integer.MIN_VALUE;
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze the script (and the surge envelope) with the game
        }
        clock++;
        if (STEPS.isEmpty()) {
            return;
        }
        int elapsed = clock - ceremonyStart;
        Iterator<Step> iterator = STEPS.iterator();
        while (iterator.hasNext()) {
            Step step = iterator.next();
            if (step.at() <= elapsed) {
                iterator.remove();
                step.action().run();
            }
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        STEPS.clear();
        surgeStart = Integer.MIN_VALUE;
        offeringGlowStart = Integer.MIN_VALUE;
    }

    // ------------------------------------------------------------------ helpers

    private static void at(int tick, Runnable action) {
        STEPS.add(new Step(tick, action));
    }

    /** Positional one-shot at the altar (natural distance falloff). */
    private static void soundAt(Vec3 pos, SoundEvent sound, float volume, float pitch) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level != null) {
            level.playLocalSound(pos.x, pos.y, pos.z, sound, SoundSource.BLOCKS,
                    volume, pitch, false);
        }
    }

    /** Listener-anchored one-shot — the world-wide bass-drop layer (no falloff). */
    private static void soundAtListener(SoundEvent sound, float volume, float pitch) {
        var player = Minecraft.getInstance().player;
        if (player != null) {
            player.playSound(sound, volume, pitch);
        }
    }

    private static float smooth(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }
}
