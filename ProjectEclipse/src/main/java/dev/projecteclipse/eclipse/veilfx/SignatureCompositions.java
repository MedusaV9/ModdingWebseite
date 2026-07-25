package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.client.CaptionRenderer;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * V7-SIGCOMP — the reusable §5 signature-composition recipes (FX-STYLE-GUIDE.md), client
 * side. Each recipe is a small tick-scripted stack over the existing engines (Photon via
 * {@link PhotonBridge}, Quasar via {@link QuasarSpawner}, screen via
 * {@code EclipseFxState}/{@link CaptionRenderer}, sound via {@code EclipseSounds}) with
 * its budget spend, stage-token discipline ({@link WorldStageArbiter}) and reduced forms
 * baked in — call sites pass only their per-context anchor/scale/sting flavor.
 *
 * <ul>
 *   <li><b>C11 CROWN VERDICT</b> ({@link #crownVerdictLeg}) — S-MAX boss-defeat coda:
 *       world indraw → gold white-out + double-pulse shockwave → gold ash rain + grade
 *       exhale. Registered as the {@code CUE_SIG_CROWN_VERDICT} row leg.</li>
 *   <li><b>C2 GOLD RUSH</b> ({@link #goldRush}) — A-class reward burst (glint gather →
 *       flash frame → physics star shards + glint-rain trails). Shared by the award
 *       podium, collection tier ≥ 5 and the altar milestone reward beat.</li>
 *   <li><b>C1 SANCTUM BLOOM</b> ({@link #sanctumBloomLayer}) — S-class consecration
 *       layered ON TOP of the shipped {@code AltarCeremonyFx} spine (the ceremony's
 *       {@code altar_indraw} IS the C1 L2 beat — no second indraw is spawned).</li>
 * </ul>
 *
 * <p>The step scheduler is the {@code AltarCeremonyFx} pattern: a handful of
 * {@code Runnable}s on a pause-frozen clock, cleared on level unload/logout. All entry
 * points are client main thread only.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SignatureCompositions {
    // --- C11 Crown Verdict (assets: tools/photon/sig_fx.py) ---
    private static final ResourceLocation CROWN_VERDICT_FX = fx("sig/crown_verdict");
    /** Coda-only variant (no L1 indraw) for hosts that ship their own (Tyrant implosion). */
    private static final ResourceLocation CROWN_VERDICT_CODA_FX = fx("sig/crown_verdict_coda");
    private static final ResourceLocation CROWN_HALO_EMITTER = fx("sig_crown_verdict_halo");
    /** WorldStage token id; S-MAX — outranks everything (§6.1). */
    private static final String STAGE_CROWN_VERDICT = "sig:crown_verdict";
    /** Impact tick offsets: full form (12t indraw) vs coda form riding the host's 24t indraw. */
    private static final int CROWN_IMPACT_FULL = 12;
    private static final int CROWN_IMPACT_CODA = 24;
    private static final int CROWN_LEASE_TICKS = 80;
    /** Grade exhale: brief warm gold-white lift, relaxing over 30t (0xAARRGGBB). */
    private static final int CROWN_EXHALE_ARGB = 0x52FFF2CC;
    /** Demoted single-pulse strength — below the shockwave v3 double-pulse gate (§6.1). */
    private static final float CROWN_SHOCK_FULL = 1.0F;
    private static final float CROWN_SHOCK_DEMOTED = 0.45F;

    // --- C2 Gold Rush ---
    private static final ResourceLocation GOLD_RUSH_FX = fx("sig/gold_rush");
    private static final ResourceLocation GOLD_GLINTS_EMITTER = fx("sig_gold_rush_glints");
    /** Shipped podium-burst emitter — kept as the flash sketch when the Photon leg dies. */
    private static final ResourceLocation UNLOCK_BURST_EMITTER = fx("unlock_burst");
    /** C2 spine: 8t glint gather, then the flash/shards impact. */
    private static final int GOLD_RUSH_IMPACT = 8;

    // --- C1 Sanctum Bloom ---
    private static final ResourceLocation SANCTUM_BLOOM_FX = fx("sig/sanctum_bloom");
    private static final ResourceLocation SANCTUM_GLYPH_EMITTER = fx("sig_sanctum_glyph");
    private static final ResourceLocation SANCTUM_ORBIT_EMITTER = fx("sig_sanctum_orbit");
    private static final String STAGE_SANCTUM_BLOOM = "sig:sanctum_bloom";
    /** The bloom's own anticipation inside the ceremony lead (glyph write-in, §5 C1 L1). */
    private static final int SANCTUM_ANTICIPATION = 10;
    /** Shared token-release delay after a composition impact (settles are 20–40t, §3). */
    private static final int RELEASE_AFTER_IMPACT = 60;

    /** C2 sting flavor (§5 C2 L5); NONE = the call site already played its own sting. */
    public enum Sting { AWARD, UNLOCK, NONE }

    private record Step(int at, Runnable action) {}

    /** Pending steps, client thread only; empty while no composition is live. */
    private static final List<Step> STEPS = new ArrayList<>();
    /** Pause-frozen composition clock (advances with unpaused client ticks). */
    private static int clock;

    private SignatureCompositions() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    // ------------------------------------------------------------------ C11 CROWN VERDICT

    /**
     * The {@code CUE_SIG_CROWN_VERDICT} row's Photon leg (S-MAX): claims the world stage
     * (forcibly releasing a held S token — the one legal preemption), spawns the Photon
     * choreography and scripts the screen/sound beats around its impact frame.
     *
     * <p>{@code b} &gt; 0.5 = the host seam ships its own indraw (Tyrant implosion): the
     * coda-only asset plays with its impact re-timed onto the host's white-out. Failing
     * the claim (another S-MAX holds — vanishingly rare) plays the §6.1 demoted form:
     * post layer dropped (no grade exhale, single-pulse shockwave), no halo.</p>
     *
     * @return whether a Photon effect started (drives the row's REPLACE fallback)
     */
    static boolean crownVerdictLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        boolean hostIndraw = b > 0.5F;
        int impact = hostIndraw ? CROWN_IMPACT_CODA : CROWN_IMPACT_FULL;
        boolean full = WorldStageArbiter.tryClaim(STAGE_CROWN_VERDICT, pos, CROWN_LEASE_TICKS, true);
        if (!full) {
            WorldStageArbiter.logDemotion(CROWN_VERDICT_FX);
        }
        int tier = FxBudget.qualityTier();

        // L1–L3: the Photon choreography (indraw → white-out flash → gold ash rain); all
        // internal delays are baked into the asset. Guard chain inside the bridge.
        boolean photonPlayed = PhotonBridge.spawn(hostIndraw ? CROWN_VERDICT_CODA_FX : photonFx, pos);

        // L2 screen half: the shockwave earns the v3 double-pulse at full strength;
        // demoted plays a single pulse (below the 0.72 gate) and drops the post lift.
        boolean fullForm = full;
        at(impact, () -> EclipseFxState.startShockwave(pos,
                fullForm ? CROWN_SHOCK_FULL : CROWN_SHOCK_DEMOTED, 44));
        if (full && tier >= 1) {
            // L5 grade exhale — the inverse of Storm Herald's dim: 2t warm gold-white
            // lift relaxing over 30t (the CaptionRenderer fade envelope, L4 sky-crack law).
            at(impact, () -> CaptionRenderer.fade(2, 4, 30, CROWN_EXHALE_ARGB));
        }
        // L4 crown halo: one soft expanding gold ring overhead (SEQUENCE — scripted context).
        if (full) {
            at(impact + 3, () -> QuasarSpawner.spawn(CROWN_HALO_EMITTER,
                    pos.add(0.0D, 3.5D, 0.0D), FxBudget.Channel.SEQUENCE));
        }
        // L6 audio: telegraph silence until the impact; the world-exhale sting rides the
        // one-sting-per-40t slot (the kill-tick BossDownSting broadcast is > 40t behind
        // every collapse coda); award.sting +8t is the §6.5 staggered second rung.
        at(impact, () -> {
            if (WorldStageArbiter.tryStingSlot()) {
                soundAt(pos, EclipseSounds.EVENT_BOSS_DOWN.get(), 1.0F, 1.0F);
            }
        });
        at(impact + 8, () -> soundAt(pos, EclipseSounds.AWARD_STING.get(), 0.6F, 0.95F));
        at(impact + RELEASE_AFTER_IMPACT,
                () -> WorldStageArbiter.release(STAGE_CROWN_VERDICT));
        return photonPlayed;
    }

    // ------------------------------------------------------------------ C2 GOLD RUSH

    /**
     * The reusable reward burst (A-class — plays freely, never claims the token): glint
     * gather (Quasar, also the photon-less sketch base) → flash frame + physics star
     * shards + glint-rain trails (Photon, {@code scale} = the per-context ladder). When
     * the Photon leg dies (photon-less / reducedFx) the shipped {@code unlock_burst}
     * emitter stamps the flash beat so no context ever falls below its old baseline.
     *
     * <p>The sting rides the {@link WorldStageArbiter#tryStingSlot} discipline — a refusal
     * inside another composition's window stays silent (the glints already carry the
     * shimmer; §6.5 tail-alias law).</p>
     */
    public static void goldRush(Vec3 pos, @Nullable Entity anchor, double scale, Sting sting) {
        // L1 glint gather — 8 sparks arcing inward over the 8t anticipation.
        QuasarSpawner.spawn(GOLD_GLINTS_EMITTER, pos, FxBudget.Channel.BURST);
        at(GOLD_RUSH_IMPACT, () -> {
            boolean photonPlayed;
            PhotonBridge.SpawnOptions options =
                    PhotonBridge.SpawnOptions.DEFAULT.withScale(scale, scale, scale);
            if (anchor != null && !anchor.isRemoved()) {
                photonPlayed = PhotonBridge.spawnOnEntity(GOLD_RUSH_FX, anchor,
                        PhotonBridge.AUTO_ROTATE_NONE, options);
            } else {
                photonPlayed = PhotonBridge.spawn(GOLD_RUSH_FX, pos, options);
            }
            if (!photonPlayed) {
                QuasarSpawner.spawnOrFallback(UNLOCK_BURST_EMITTER, pos, FxBudget.Channel.BURST);
            }
            if (sting == Sting.AWARD && WorldStageArbiter.tryStingSlot()) {
                soundAt(pos, EclipseSounds.AWARD_STING.get(), 0.9F, 1.0F);
            } else if (sting == Sting.UNLOCK && WorldStageArbiter.tryStingSlot()) {
                soundAt(pos, EclipseSounds.UI_UNLOCK_STING.get(), 0.8F, 1.05F);
            }
        });
    }

    // ------------------------------------------------------------------ C1 SANCTUM BLOOM

    /**
     * The consecration layer over the altar level-up ceremony — called by
     * {@code AltarCeremonyFx.start} with the ceremony's own anticipation {@code lead}, so
     * every beat rides the SAME spine (no doubling: the ceremony's {@code altar_indraw}
     * IS the C1 L2 indraw; this layer adds the L1 glyph write-in, the L3/L4 Photon
     * pillar + bloom burst at the ceremony's impact and the L5 settle orbit motes).
     *
     * <p>Claims the S token for the moment. Demoted / preempted mid-flight (a Crown
     * Verdict nearby) sheds the Photon hero layers and keeps glyph + chime — the §5
     * reduced form. Tier 0 or a far camera adds nothing (the ceremony's minimal profile
     * already owns that rung).</p>
     */
    public static void sanctumBloomLayer(Vec3 pos, int level, int leadTicks, boolean near) {
        int tier = FxBudget.qualityTier();
        if (tier <= 0 || !near) {
            return;
        }
        boolean claimed = WorldStageArbiter.tryClaim(STAGE_SANCTUM_BLOOM, pos,
                leadTicks + RELEASE_AFTER_IMPACT, false);
        if (!claimed) {
            WorldStageArbiter.logDemotion(SANCTUM_BLOOM_FX);
        }
        int glyphAt = Math.max(0, leadTicks - SANCTUM_ANTICIPATION);
        // L1 ground glyph: 10t arc write-in so its completion lands on the ceremony impact.
        at(glyphAt, () -> QuasarSpawner.spawn(SANCTUM_GLYPH_EMITTER,
                pos.add(0.0D, 0.15D, 0.0D), FxBudget.Channel.SEQUENCE));
        if (claimed) {
            // L3+L4 Photon hero half (pillar beam + bloom burst; impact delay baked at
            // +10t so it lands with the glyph completion). Re-checked at spawn time: an
            // S-MAX preemption during the write-in demotes to the glyph-only form.
            at(glyphAt, () -> {
                if (WorldStageArbiter.holdsStage(STAGE_SANCTUM_BLOOM)) {
                    PhotonBridge.spawn(SANCTUM_BLOOM_FX, pos);
                } else {
                    WorldStageArbiter.logDemotion(SANCTUM_BLOOM_FX);
                }
            });
            // L5 orbit motes into the settle (asset fades itself to SAC_VOID).
            at(leadTicks + 3, () -> QuasarSpawner.spawn(SANCTUM_ORBIT_EMITTER,
                    pos.add(0.0D, 1.0D, 0.0D), FxBudget.Channel.SEQUENCE));
        }
        // L7 chime at impact — the level-up flavor of the C1 sting (skill.levelup); rides
        // the sting slot: the ceremony's own t=0 sting is exactly one window earlier.
        int chimePitchLevel = Math.max(1, Math.min(5, level));
        at(leadTicks, () -> {
            if (WorldStageArbiter.tryStingSlot()) {
                soundAt(pos, EclipseSounds.SKILL_LEVELUP.get(), 0.9F,
                        0.9F + 0.05F * chimePitchLevel);
            }
        });
        at(leadTicks + RELEASE_AFTER_IMPACT,
                () -> WorldStageArbiter.release(STAGE_SANCTUM_BLOOM));
    }

    // ------------------------------------------------------------------ tick loop

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            STEPS.clear();
            return;
        }
        if (minecraft.isPaused()) {
            return; // freeze the scripts with the game
        }
        clock++;
        if (STEPS.isEmpty()) {
            return;
        }
        Iterator<Step> iterator = STEPS.iterator();
        while (iterator.hasNext()) {
            Step step = iterator.next();
            if (step.at() <= clock) {
                iterator.remove();
                step.action().run();
            }
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        STEPS.clear();
    }

    // ------------------------------------------------------------------ helpers

    private static void at(int delay, Runnable action) {
        if (delay <= 0) {
            action.run();
            return;
        }
        STEPS.add(new Step(clock + delay, action));
    }

    /** Positional one-shot (natural distance falloff). */
    private static void soundAt(Vec3 pos, SoundEvent sound, float volume, float pitch) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level != null) {
            level.playLocalSound(pos.x, pos.y, pos.z, sound, SoundSource.AMBIENT,
                    volume, pitch, false);
        }
    }
}
