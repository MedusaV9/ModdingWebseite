package dev.projecteclipse.eclipse.limbo;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * PLAN-C C4 — pre-event limbo safety (v5 items 7 + 8's event owner). Before
 * {@code /start_event} runs, every player waits on the ghost ship in survival and was
 * fully vulnerable: drowning off the gunwale meant a REAL death through the whole
 * {@code DeathFlowHooks} pipeline — a lost life before the event even started. This
 * class is the single event owner for the two server-side guards:
 *
 * <ul>
 *   <li><b>Pre-event immunity</b>: {@link LivingIncomingDamageEvent} is cancelled (and
 *       {@link LivingDeathEvent} as a belt, at HIGHEST so it runs before
 *       {@code LifecycleEvents}' NORMAL-priority heart decrement) for players in
 *       {@link LimboDimension#LIMBO} while
 *       {@link EclipseWorldState#isStartEventDone()} is false. Sources tagged
 *       {@code BYPASSES_INVULNERABILITY} (e.g. {@code /kill}) still pass — the same
 *       admin escape hatch as vanilla invulnerability and {@code FreezeService}.</li>
 *   <li><b>Water rescue</b> (pre- AND post-event): a player who falls into the limbo
 *       sea — or ends up overboard DRY, outside the ship footprint at or below deck
 *       height (a {@code LimboSeascape} wreck/spire/buoy prop) — turns invisible on the
 *       spot, is frozen via {@link FreezeService} (which
 *       already grants invulnerability + the rubber-band position lock), the screen
 *       slowly fades to black ({@link S2CScreenFadePayload} →
 *       {@code CaptionRenderer.fade}), and at t={@value #RESCUE_TP_TICK} they are
 *       {@link FreezeService#transport}ed back onto the midship deck behind the black,
 *       fading back in as the freeze and invisibility release. A per-player
 *       {@value #RESCUE_COOLDOWN_TICKS}t cooldown, armed as the rescue completes, keeps
 *       the beat from looping while
 *       someone insists on swimming. The rescue stands down while a Ferryman is alive
 *       (falling overboard during the crossing has its own flow — the
 *       {@code FinaleRitual} fight seam), while the start-event keel-over cutscene
 *       floods the deck ({@link OarAnimator#isTiltActive()}), and for players some
 *       other system already froze (cutscene gathers own their position).</li>
 * </ul>
 *
 * <p>Item 8 (a ghost gaining a life stays a ghost) is the other half of C4 and lives in
 * {@code core/state/LivesApi}'s post-mutation hook — see there.</p>
 *
 * <p>All state here is transient statics (server-thread only): a restart can never leak
 * a half-run rescue; the freeze's own watchdog TTL releases the lock even if this class
 * were to miss its release tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PreEventSafety {
    /** Rescue timeline: transport back to the deck once the screen is fully black. */
    private static final int RESCUE_TP_TICK = 40;
    /** Rescue timeline: release the freeze + invisibility (fade-out is under way). */
    private static final int RESCUE_RELEASE_TICK = 52;
    /** Freeze watchdog TTL — comfortably past the scripted release. */
    private static final int RESCUE_FREEZE_TTL_TICKS = 80;
    /**
     * Per-player anti-loop cooldown (2 s), armed when a rescue COMPLETES (not when it
     * triggers — arming at the trigger left a ~5 s dead window after the release tick in
     * which re-entering the water did nothing). Long enough to outlive the fade-out
     * tail, short enough that a player who deliberately jumps back in is rescued again
     * promptly.
     */
    private static final int RESCUE_COOLDOWN_TICKS = 40;
    /**
     * Overboard-footprint skirt around the hull box ({@code GhostShipBuilder.HALF_LENGTH}
     * / {@code HALF_WIDTH}): |x| ≤ 21, |z| ≤ 6 — the same margin the ship's own
     * clear-volume uses, covering the sternpost/rudder (x −20..−21) and the bow stem +
     * skull (x 20..21) so nobody standing on hull trim is "outside the ship".
     */
    private static final int FOOTPRINT_MARGIN = 2;
    /** Slow fade-to-black envelope (rise / hold / release), opaque black. */
    private static final int FADE_IN_TICKS = 30;
    private static final int FADE_HOLD_TICKS = 15;
    private static final int FADE_OUT_TICKS = 25;
    private static final int FADE_BLACK_ARGB = 0xFF000000;
    /** Invisibility outlives the release tick slightly; it is removed explicitly anyway. */
    private static final int INVISIBILITY_TICKS = RESCUE_RELEASE_TICK + 20;
    /** Owner token so the release can never free a foreign (cutscene/admin) lock. */
    private static final String FREEZE_OWNER = "eclipse:limbo_water_rescue";
    private static final String CAPTION_RESCUE = "eclipse.caption.limbo.rescue";
    private static final int CAPTION_TICKS = 70;

    /** Elapsed rescue ticks by player UUID (server thread only, transient by design). */
    private static final Map<UUID, Integer> RESCUES = new HashMap<>();
    /** Remaining cooldown ticks by player UUID (server thread only, transient). */
    private static final Map<UUID, Integer> COOLDOWNS = new HashMap<>();

    private PreEventSafety() {}

    // ------------------------------------------------------------------ item 7: immunity

    /** True while the player is under the pre-event shield (limbo, event not started). */
    private static boolean isPreEventProtected(ServerPlayer player) {
        return player.serverLevel().dimension().equals(LimboDimension.LIMBO)
                && !EclipseWorldState.get(player.server).isStartEventDone();
    }

    @SubscribeEvent
    static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (event.getEntity() instanceof ServerPlayer player
                && isPreEventProtected(player)
                // /kill and friends must still work — mirror vanilla invulnerability.
                && !event.getSource().is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            event.setCanceled(true);
        }
    }

    /**
     * Belt for the damage cancel: HIGHEST so a death that slips through any other path
     * is cancelled BEFORE {@code LifecycleEvents.onLivingDeath} (NORMAL) can decrement a
     * heart — pre-event players can NEVER lose a life. Health is restored to at least
     * half a heart so the cancelled death cannot immediately re-fire.
     */
    @SubscribeEvent(priority = EventPriority.HIGHEST)
    static void onLivingDeath(LivingDeathEvent event) {
        if (event.getEntity() instanceof ServerPlayer player
                && isPreEventProtected(player)
                && !event.getSource().is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            event.setCanceled(true);
            player.setHealth(Math.max(1.0F, player.getHealth()));
            EclipseMod.LOGGER.info("PreEventSafety: cancelled pre-event death of {} in limbo (source {})",
                    player.getScoreboardName(), event.getSource().getMsgId());
        }
    }

    // ------------------------------------------------------------------ water rescue

    @SubscribeEvent
    static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        UUID id = player.getUUID();
        Integer cooldown = COOLDOWNS.get(id);
        if (cooldown != null) {
            if (cooldown <= 1) {
                COOLDOWNS.remove(id);
            } else {
                COOLDOWNS.put(id, cooldown - 1);
            }
        }
        Integer elapsed = RESCUES.get(id);
        if (elapsed != null) {
            tickRescue(player, elapsed);
        } else {
            maybeBeginRescue(player);
        }
    }

    private static void maybeBeginRescue(ServerPlayer player) {
        if (!player.serverLevel().dimension().equals(LimboDimension.LIMBO)
                // In the water, OR dry-but-overboard (a LimboSeascape wreck/spire/buoy
                // prop keeps the feet out of the water — the sea still refuses them).
                || (!player.isInWater() && !isOverboard(player))
                || COOLDOWNS.containsKey(player.getUUID())
                || player.isSpectator()
                || player.isCreative()
                || player.isDeadOrDying()
                // A cutscene/admin freeze owns their position — never fight another lock.
                || FreezeService.isFrozen(player)
                // The start-event keel-over floods parts of the ship deliberately.
                || OarAnimator.isTiltActive()) {
            return;
        }
        ServerLevel limbo = player.serverLevel();
        // FinaleRitual seam: while the Ferryman is afloat, overboard players belong to
        // the crossing's own flow — the rescue stands down for the whole fight.
        if (!limbo.getEntities(EclipseEntities.FERRYMAN.get(), LivingEntity::isAlive).isEmpty()) {
            return;
        }
        RESCUES.put(player.getUUID(), 0);
        // The "turn invisible in the water" beat: the sea takes them out of sight first.
        player.addEffect(new MobEffectInstance(MobEffects.INVISIBILITY, INVISIBILITY_TICKS, 0, false, false));
        FreezeService.freeze(player, RESCUE_FREEZE_TTL_TICKS, FREEZE_OWNER);
        PacketDistributor.sendToPlayer(player,
                new S2CScreenFadePayload(FADE_IN_TICKS, FADE_HOLD_TICKS, FADE_OUT_TICKS, FADE_BLACK_ARGB));
        PacketDistributor.sendToPlayer(player,
                new S2CCaptionPayload(CAPTION_RESCUE, CAPTION_TICKS, S2CCaptionPayload.STYLE_WHISPER));
        player.playNotifySound(SoundEvents.AMBIENT_UNDERWATER_ENTER, SoundSource.PLAYERS, 1.0F, 0.7F);
        EclipseMod.LOGGER.info("PreEventSafety: water rescue started for {} at {}",
                player.getScoreboardName(), player.blockPosition().toShortString());
    }

    /**
     * Whether the player has left the ship: outside the hull footprint
     * ({@code GhostShipBuilder.HALF_LENGTH}/{@code HALF_WIDTH} around 0,0 — the frozen
     * ship-center contract — plus the {@value #FOOTPRINT_MARGIN}-block trim skirt) while
     * at or below deck height ({@code waterline + 3}). Catches players standing DRY on a
     * {@code LimboSeascape} wreck/spire/buoy prop, whom {@code isInWater()} never flags.
     * Everything legitimately walkable on the ship keeps the feet ABOVE {@code deckY}
     * (main deck, spawn platform and walkway at {@code deckY + 1}, castles higher), so
     * this can never fire on deck; a bowsprit climber (x up to 25) is above deck height
     * too.
     */
    private static boolean isOverboard(ServerPlayer player) {
        if (Math.abs(player.getX()) <= GhostShipBuilder.HALF_LENGTH + FOOTPRINT_MARGIN
                && Math.abs(player.getZ()) <= GhostShipBuilder.HALF_WIDTH + FOOTPRINT_MARGIN) {
            return false;
        }
        int deckY = GhostShipBuilder.waterlineY(player.serverLevel()) + 3;
        return player.getY() <= deckY + 0.5D;
    }

    private static void tickRescue(ServerPlayer player, int elapsed) {
        // Abort cleanly if the world moved on under us (bypass kill, admin tp out of limbo).
        if (player.isDeadOrDying() || !player.serverLevel().dimension().equals(LimboDimension.LIMBO)) {
            finishRescue(player);
            return;
        }
        int now = elapsed + 1;
        RESCUES.put(player.getUUID(), now);
        if (now == RESCUE_TP_TICK) {
            // Screen is fully black: back onto the midship deck, facing the bow (+X).
            ServerLevel limbo = player.serverLevel();
            Vec3 deck = new Vec3(0.5D, GhostShipBuilder.waterlineY(limbo) + 4.0D, 0.5D);
            FreezeService.transport(player, limbo, deck, -90.0F, 0.0F);
            player.playNotifySound(SoundEvents.AMBIENT_UNDERWATER_EXIT, SoundSource.PLAYERS, 1.0F, 0.9F);
        } else if (now >= RESCUE_RELEASE_TICK) {
            finishRescue(player);
            EclipseMod.LOGGER.info("PreEventSafety: water rescue finished for {} — back on the deck",
                    player.getScoreboardName());
        }
    }

    /**
     * Releases OUR freeze (owner-checked) and the invisibility; idempotent. Arms the
     * anti-loop cooldown HERE — from the completion, not the trigger — so there is never
     * a dead window in which a player back in the water is silently ignored.
     */
    private static void finishRescue(ServerPlayer player) {
        RESCUES.remove(player.getUUID());
        COOLDOWNS.put(player.getUUID(), RESCUE_COOLDOWN_TICKS);
        FreezeService.unfreeze(player, FREEZE_OWNER);
        player.removeEffect(MobEffects.INVISIBILITY);
    }

    // ------------------------------------------------------------------ lifecycle hygiene

    /** Logout mid-rescue: drop the flow (the freeze self-releases); a re-login re-triggers cleanly. */
    @SubscribeEvent
    static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            RESCUES.remove(player.getUUID());
        }
    }

    /** Integrated-server restarts must never leak rescue state into the next world. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        RESCUES.clear();
        COOLDOWNS.clear();
    }
}
