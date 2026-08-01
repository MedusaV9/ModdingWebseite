package dev.projecteclipse.eclipse.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.event.entity.player.CriticalHitEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * W4-FEEL combat feedback bursts (F-104 Team A, IDEA-02 #5/#6) — two stateless
 * server-side listeners that make GOOD hits look better than ordinary ones:
 *
 * <ul>
 *   <li><b>A3 crit sparkles</b> ({@link #onCriticalHit}): every player crit that
 *       connects pops the existing {@code eclipse:impact_light} Quasar micro-flash at
 *       the victim's chest (the {@code WandPhaseService} re-rez pop — BURST-budgeted
 *       client-side, so spam self-limits) plus the new {@code wave4_crit_gleam}
 *       Photon gleam on the position cue lane. LAYER law: vanilla crit stars stay,
 *       photon-less clients keep stars + flash.</li>
 *   <li><b>A4 damage-magnitude bursts</b> ({@link #onLivingDamagePost}): player-dealt
 *       hits on {@link EclipseGeoMonster} victims read their weight class at a glance —
 *       &ge;{@value #SOLID_DAMAGE} final damage stamps a scaled CRIT
 *       {@code sendParticles} burst, &ge;{@value #HEAVY_DAMAGE} scales it up and adds
 *       the {@code wave4_heavy_impact} Photon payoff ({@code a} = damage drives the
 *       asset scale). Custom mobs only by design: vanilla mobs keep vanilla reads,
 *       and the bucket thresholds line up with the mobs' 4-8 damage attack range.</li>
 * </ul>
 *
 * <p>Listener shape mirrors {@link HitStopService} (same event lane, same guards) —
 * the two services deliberately stack: a crit for &ge;8 on a boss lands hit-stop +
 * stars + gleam + burst, each layer lean enough that the sum stays a pop, not a
 * fireworks show. Stateless — nothing to reset.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CombatFeedbackFx {
    /** The frozen D12 Quasar micro-flash (WandPhaseService re-rez pop precedent). */
    private static final ResourceLocation IMPACT_LIGHT_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "impact_light");
    /** Wave4 cue ids — re-derived inline (Wave3 two-sided naming law; FxCues frozen). */
    private static final ResourceLocation CUE_CRIT_GLEAM = FxCues.cue("wave4_crit_gleam");
    private static final ResourceLocation CUE_HEAVY_IMPACT = FxCues.cue("wave4_heavy_impact");

    /** A4 buckets (IDEA-02 #6): "solid" gets the burst, "heavy" gets burst + Photon. */
    private static final float HEAVY_DAMAGE = 8.0F;
    private static final float SOLID_DAMAGE = 4.0F;
    private static final double FX_RANGE = 48.0D;

    private CombatFeedbackFx() {}

    /**
     * A3: {@code CriticalHitEvent} fires from {@code Player.attack} on BOTH sides and
     * BEFORE the damage applies — server side only (the client gets the cue over the
     * wire), and living victims only (crits on boats/stands stay vanilla).
     */
    @SubscribeEvent
    static void onCriticalHit(CriticalHitEvent event) {
        if (!event.isCriticalHit() || !(event.getTarget() instanceof LivingEntity victim)
                || !(victim.level() instanceof ServerLevel level) || !victim.isAlive()) {
            return;
        }
        Vec3 chest = victim.position().add(0.0D, victim.getBbHeight() * 0.6D, 0.0D);
        PacketDistributor.sendToPlayersNear(level, null, chest.x, chest.y, chest.z, FX_RANGE,
                new S2CQuasarPayload(IMPACT_LIGHT_EMITTER, chest));
        FxPayloads.sendFxEvent(level, CUE_CRIT_GLEAM, chest, 0.0F, 0.0F, FX_RANGE);
    }

    /**
     * A4: post-application damage (so armor/absorption already ate their share — the
     * burst reads what actually LANDED), player-dealt only ({@code getSource().getEntity()}
     * covers melee and owned projectiles), {@link EclipseGeoMonster} victims only.
     */
    @SubscribeEvent
    static void onLivingDamagePost(LivingDamageEvent.Post event) {
        LivingEntity victim = event.getEntity();
        float damage = event.getNewDamage();
        if (victim.level().isClientSide() || damage < SOLID_DAMAGE
                || !(victim instanceof EclipseGeoMonster)
                || !(victim.level() instanceof ServerLevel level)
                || !(event.getSource().getEntity() instanceof ServerPlayer)) {
            return;
        }
        Vec3 chest = victim.position().add(0.0D, victim.getBbHeight() * 0.6D, 0.0D);
        boolean heavy = damage >= HEAVY_DAMAGE;
        // Scaled magnitude read: ~1.5 stars per damage point, bucket-banded so the
        // heavy tier is unmistakably denser (12+) than the solid tier (6-11).
        int count = heavy ? Mth.clamp((int) (damage * 1.6F), 12, 28)
                : Mth.clamp((int) (damage * 1.5F), 6, 11);
        level.sendParticles(ParticleTypes.CRIT, chest.x, chest.y, chest.z,
                count, 0.35D, 0.35D, 0.35D, 0.25D);
        if (heavy) {
            FxPayloads.sendFxEvent(level, CUE_HEAVY_IMPACT, chest, damage, 0.0F, FX_RANGE);
        }
    }
}
