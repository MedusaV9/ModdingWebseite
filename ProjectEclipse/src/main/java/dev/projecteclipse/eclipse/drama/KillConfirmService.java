package dev.projecteclipse.eclipse.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import dev.projecteclipse.eclipse.entity.boss.rift.RiftWardenEntity;
import dev.projecteclipse.eclipse.entity.fog.FogColossusEntity;
import dev.projecteclipse.eclipse.entity.fog.StormHoundEntity;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;

/**
 * Kill-confirm sting (W4-FEEL, IDEA-02 #2): killing an Eclipse mob currently sounds
 * identical to wounding it. This adds a PRIVATE, dry "confirm" layer to the killer only —
 * a low amethyst chime with a ghosted attack-crit shimmer under it — so the moment of
 * death reads in the ear without broadcasting anything to bystanders (Quiet-Eclipse §2:
 * a private nod, not a fanfare).
 *
 * <p>Variants: regular Eclipse mobs get the standard chime; ELITES ({@link
 * FogColossusEntity}, {@link StormHoundEntity}) get a deeper, slightly louder version;
 * BOSSES ({@link FogTyrantEntity}, {@link RiftWardenEntity}) get NOTHING — their
 * scripted deaths (storm burst, gutter collapse) already own the moment. Herald and
 * Ferryman are plain {@code Monster}s, so the {@link EclipseGeoMonster} guard excludes
 * them for free.</p>
 *
 * <p>Runs at {@link EventPriority#LOW} on {@code LivingDeathEvent} — after the death
 * economy, purely observational (the {@code drama/FirstBloodService} pattern). Delivered
 * via {@code ServerPlayer.playNotifySound} — no new payload, no state, nothing to reset.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class KillConfirmService {
    /** Standard confirm: low chime + a barely-there crit shimmer ghosted under it. */
    private static final float CHIME_VOLUME = 0.5F;
    private static final float CHIME_PITCH = 0.7F;
    private static final float CRIT_VOLUME = 0.25F;
    private static final float CRIT_PITCH = 0.85F;
    /** Elite confirm: deeper and a touch louder — a felled colossus should land lower. */
    private static final float ELITE_CHIME_VOLUME = 0.65F;
    private static final float ELITE_CHIME_PITCH = 0.5F;
    private static final float ELITE_CRIT_VOLUME = 0.3F;
    private static final float ELITE_CRIT_PITCH = 0.6F;

    private KillConfirmService() {}

    /** LOW: after the death economy — this beat only observes that a mob died. */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDeath(LivingDeathEvent event) {
        LivingEntity victim = event.getEntity();
        if (victim.level().isClientSide() || !(victim instanceof EclipseGeoMonster)) {
            return;
        }
        if (victim instanceof FogTyrantEntity || victim instanceof RiftWardenEntity) {
            return; // boss deaths are scripted set pieces — they own their own audio
        }
        if (!(event.getSource().getEntity() instanceof ServerPlayer killer)) {
            return;
        }
        boolean elite = victim instanceof FogColossusEntity || victim instanceof StormHoundEntity;
        // Two layers: the chime is the confirm note, the ghosted crit gives it a metallic
        // "connect" texture. Both private to the killer (playNotifySound).
        killer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS,
                elite ? ELITE_CHIME_VOLUME : CHIME_VOLUME,
                elite ? ELITE_CHIME_PITCH : CHIME_PITCH);
        killer.playNotifySound(SoundEvents.PLAYER_ATTACK_CRIT, SoundSource.PLAYERS,
                elite ? ELITE_CRIT_VOLUME : CRIT_VOLUME,
                elite ? ELITE_CRIT_PITCH : CRIT_PITCH);
    }
}
