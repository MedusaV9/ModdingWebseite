package dev.projecteclipse.eclipse.drama;

import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;

/**
 * Boss-down release sting (FFIX-A / DOPA #3, closes IDEA-07 #6): the top of the reward
 * ladder was INVERTED — a Fog Colossus elite gave its killer a deeper kill-confirm chime
 * than the Herald's death gave anyone. This is the missing macro release beat:
 *
 * <ul>
 *   <li><b>Public layer:</b> {@code eclipse:event.boss_down} broadcast to ALL online
 *       players ({@code playNotifySound}, ambient) the tick a boss dies — everyone on the
 *       server hears the event world exhale, mirroring the global {@code STYLE_GOAL}
 *       announcement reach of MAIN goals.</li>
 *   <li><b>Killer layer:</b> a brighter private {@code UI_UNLOCK_STING} (0.7, pitched up)
 *       on top — the personal nod {@link KillConfirmService} deliberately left empty for
 *       bosses ("their scripted deaths own the moment"; the SET PIECE owns the visuals,
 *       this owns the ladder's top audio rung).</li>
 * </ul>
 *
 * <p><b>Ledger alias:</b> {@code event.boss_down} is registered in {@code EclipseSounds}
 * and shipped as a sounds.json alias of {@code event/submerge} re-pitched 0.48 — no new
 * binary asset (house rule). The play-time id resolution below predates the registration
 * (V6-FIXWIRE #4) and is kept as the usual self-healing read: should the row ever vanish,
 * the class falls back to {@link EclipseSounds#EVENT_STORM_BURST} at 0.6 pitch.</p>
 *
 * <p>Covers all four boss death paths in ONE seam: {@code LivingDeathEvent} at
 * {@link EventPriority#LOW} matched on the four boss entity ids ({@code herald},
 * {@code ferryman}, {@code rift_warden}, {@code fog_tyrant}) — Herald/Ferryman are plain
 * {@code Monster}s and the fog/rift bosses are GeckoLib set pieces, but they all die
 * through this event. Purely observational, no state, nothing to reset.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BossDownSting {
    /** The four boss entity ids (mirror of {@code BestiaryTiers.BOSS_IDS}). */
    private static final Set<String> BOSS_PATHS = Set.of("herald", "ferryman", "rift_warden", "fog_tyrant");

    /** Ledger id — registered in EclipseSounds; sounds.json alias of {@code event/submerge}. */
    private static final ResourceLocation BOSS_DOWN_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.boss_down");

    /** Public release: full volume, world-scale ("the event exhales"). */
    private static final float STING_VOLUME = 1.0F;
    /** Fallback re-pitch — storm burst pitched down reads as a low release rumble. */
    private static final float FALLBACK_PITCH = 0.6F;
    /** Killer's brighter private layer (DOPA #3 spec: UI_UNLOCK_STING at 0.7). */
    private static final float KILLER_VOLUME = 0.7F;
    private static final float KILLER_PITCH = 1.1F;

    private BossDownSting() {}

    /** LOW: after the death economy (kill XP, drops, bestiary) — this beat only listens. */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDeath(LivingDeathEvent event) {
        LivingEntity victim = event.getEntity();
        if (victim.level().isClientSide()) {
            return;
        }
        ResourceLocation id = BuiltInRegistries.ENTITY_TYPE.getKey(victim.getType());
        if (!EclipseMod.MOD_ID.equals(id.getNamespace()) || !BOSS_PATHS.contains(id.getPath())) {
            return;
        }
        MinecraftServer server = victim.getServer();
        if (server == null) {
            return;
        }

        SoundEvent ledger = resolveBossDown();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (ledger != null) {
                player.playNotifySound(ledger, SoundSource.AMBIENT, STING_VOLUME, 1.0F);
            } else {
                player.playNotifySound(EclipseSounds.EVENT_STORM_BURST.get(), SoundSource.AMBIENT,
                        STING_VOLUME, FALLBACK_PITCH);
            }
        }

        if (event.getSource().getEntity() instanceof ServerPlayer killer) {
            killer.playNotifySound(EclipseSounds.UI_UNLOCK_STING.get(), SoundSource.PLAYERS,
                    KILLER_VOLUME, KILLER_PITCH);
        }
    }

    /**
     * Ledger lookup at play time (registry frozen long before any boss can die). Not
     * memoized — boss deaths are ~4/event, a registry map hit is free at that cadence.
     */
    @Nullable
    private static SoundEvent resolveBossDown() {
        return BuiltInRegistries.SOUND_EVENT.getOptional(BOSS_DOWN_ID).orElse(null);
    }
}
