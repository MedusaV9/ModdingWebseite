package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.mojang.authlib.GameProfile;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.entity.GazerEntity;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.offering.OfferingRules;
import dev.projecteclipse.eclipse.offering.OfferingService;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseBlockEntities;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;
import software.bernie.geckolib.animatable.GeoBlockEntity;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.RawAnimation;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Server-side brain of the altar. Holds only transient per-player interaction
 * state (offering confirmations, revive-sigil selections); all durable
 * progress lives in {@link EclipseWorldState}.
 *
 * <p>Milestone progress is tracked in {@link EclipseWorldState#getMilestoneProgress(String)}
 * under {@code altar_level_<n>} (single-cost milestones) or
 * {@code altar_level_<n>:<item_id>} (one counter per cost entry of multi-cost milestones).</p>
 *
 * <p>All player feedback is action bar + sounds; nothing is ever sent to chat.</p>
 *
 * <p><b>F-076 GeckoLib chassis:</b> the altar renders through a GeckoLib model
 * ({@code geo/block/altar.geo.json} + {@code animations/block/altar.animation.json} +
 * {@code textures/block/altar.png}/{@code _glowmask}, drawn by
 * {@code client.altarmodel.AltarModelRenderer} — {@code AltarBlock} is
 * {@code RenderShape.INVISIBLE} now). One controller ({@value #CONTROLLER_STATE}) loops
 * {@code idle} (floating core, counter-rotating rune rings, drifting debris) and holds
 * four server-triggerable one-shots: {@value #ANIM_HEARTBEAT} (a strong pulse — fired
 * here on every accepted payment), {@value #ANIM_STAGE_UP} (the level-up fanfare, fired
 * from {@link #completeMilestone}), {@value #ANIM_GIFT} (the altar "hands out" — for
 * shop purchases) and {@value #ANIM_ERUPT} (the big-event quake — for the End reveal).
 * Other systems fire gift/erupt through the {@link AltarModelTriggers} facade; the
 * trigger rides GeckoLib's own BE network path, no new payloads.</p>
 */
public class AltarBlockEntity extends BlockEntity implements GeoBlockEntity {
    /** Geo/anim/texture triple id: {@code geo/block/altar.geo.json} etc. */
    public static final String GEO_ID = "altar";
    /** The single animation controller (idle loop + server-triggered one-shots). */
    public static final String CONTROLLER_STATE = "state";
    /** Triggerable one-shot: strong core pulse (accepted payments, special moments). */
    public static final String ANIM_HEARTBEAT = "heartbeat";
    /** Triggerable one-shot: rings open, core lifts, light breaks out (purchases). */
    public static final String ANIM_GIFT = "gift";
    /** Triggerable one-shot: the big-event quake (End reveal etc.). */
    public static final String ANIM_ERUPT = "erupt";
    /** Triggerable one-shot: short ascension fanfare when the altar level rises. */
    public static final String ANIM_STAGE_UP = "stage_up";

    private static final RawAnimation IDLE =
            EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE);
    private static final RawAnimation HEARTBEAT = EclipseGeoAnimations.once(GEO_ID, ANIM_HEARTBEAT);
    private static final RawAnimation GIFT = EclipseGeoAnimations.once(GEO_ID, ANIM_GIFT);
    private static final RawAnimation ERUPT = EclipseGeoAnimations.once(GEO_ID, ANIM_ERUPT);
    private static final RawAnimation STAGE_UP = EclipseGeoAnimations.once(GEO_ID, ANIM_STAGE_UP);

    /** Offerings are confirmed by a second sneak-right-click within this window (5 s). */
    public static final long OFFERING_CONFIRM_WINDOW_TICKS = 100L;
    /**
     * WAVE5 (F-105 C) — C2 armed-offering tension column (IDEA-12 #6): a bounded one-shot
     * Quasar emitter whose 100 t emitter lifetime mirrors
     * {@value #OFFERING_CONFIRM_WINDOW_TICKS} exactly — dark {@code #5B1E99} motes held in
     * a tight column over the stone while the altar "holds its breath" for the confirm
     * click. No cleanup bookkeeping: the emitter runs out on its own, so a lapsed window
     * fades without residue and a confirm visually hands over to the accept beam.
     */
    private static final ResourceLocation OFFERING_ARMED =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "offering_armed");
    /**
     * VEIL-REPASS-2 crowd-awareness: players within this range of the altar count as the
     * gathered CROWD when a milestone completes — the count rides the level-up payload's
     * previously-unused {@code b} param and widens the client ceremony's burst radius.
     */
    public static final double CROWD_RANGE = 20.0D;

    /** Item id + game time of each player's pending (unconfirmed) daily offering. */
    private final Map<UUID, PendingOffering> pendingOfferings = new HashMap<>();
    /** Currently-selected revive target (banned player UUID) per interacting player. */
    private final Map<UUID, UUID> sigilSelections = new HashMap<>();

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    private record PendingOffering(long armedAt, String itemId) {}

    public AltarBlockEntity(BlockPos pos, BlockState state) {
        super(EclipseBlockEntities.ALTAR.get(), pos, state);
    }

    // --- F-076 GeckoLib animation chassis ---

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, CONTROLLER_STATE, 4,
                state -> state.setAndContinue(IDLE))
                .triggerableAnim(ANIM_HEARTBEAT, HEARTBEAT)
                .triggerableAnim(ANIM_GIFT, GIFT)
                .triggerableAnim(ANIM_ERUPT, ERUPT)
                .triggerableAnim(ANIM_STAGE_UP, STAGE_UP));
    }

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return this.geoCache;
    }

    // --- milestone sacrifice ---

    /**
     * ALTARFIX2 #3 routing query: does the HUNGERING milestone still want this item?
     * {@code true} also while the ladder is sealed ({@code /dev altar lock}), so
     * {@link #handleMilestoneDeposit} can refuse with its own message instead of the item
     * silently sliding into the daily-offering lane and being eaten.
     */
    public boolean wantsForMilestone(MinecraftServer server, ItemStack stack) {
        if (stack.isEmpty()) {
            return false;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        EclipseConfig.Milestone milestone = EclipseConfig.milestone(state.getAltarLevel() + 1);
        if (milestone == null) {
            return false;
        }
        if (AltarAdminState.get(server).isProgressionLocked()) {
            // Sealed: still claim the item so handleMilestoneDeposit prints "sealed".
            String held = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
            for (EclipseConfig.ItemCost cost : milestone.cost()) {
                if (cost.item().equals(held)) {
                    return true;
                }
            }
            return false;
        }
        String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        for (EclipseConfig.ItemCost cost : milestone.cost()) {
            if (cost.item().equals(itemId)
                    && state.getMilestoneProgress(progressKey(milestone, cost.item())) < cost.count()) {
                return true;
            }
        }
        return false;
    }

    /**
     * Sneak-right-click with an item the milestone wants (ALTARFIX2 #3 moved this off the
     * plain right-click): consumes as much of the held stack as the next
     * milestone (current altar level + 1) still needs of that item. Completing
     * all cost entries raises the altar level, syncs it to all clients and plays
     * the subtle global cue (end-portal sound + portal particles, no text).
     */
    public void handleMilestoneDeposit(ServerPlayer player, ItemStack stack) {
        if (!(this.level instanceof ServerLevel serverLevel)) {
            return;
        }
        // W11: the Herald's Lure is a ritual item, not a milestone cost — hint at the
        // sneak-deposit (HeraldsLureItem#useOn) instead of barking "wrong item".
        if (stack.is(EclipseItems.HERALDS_LURE.get())) {
            actionBar(player, Component.translatable("ritual.eclipse.lure.sneak_hint"));
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.BLOCKS, 0.8F, 0.6F);
            return;
        }
        MinecraftServer server = player.server;
        // ALTARUI task 9: /dev altar lock freezes the LADDER — refuse before consuming
        // anything so no items are ever swallowed toward a milestone that cannot complete.
        // Banking, offerings, heart sacrifices and the shop deliberately stay open.
        if (AltarAdminState.get(server).isProgressionLocked()) {
            actionBar(player, Component.translatable("ritual.eclipse.altar.sealed"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.9F);
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        EclipseConfig.Milestone milestone = EclipseConfig.milestone(state.getAltarLevel() + 1);
        if (milestone == null) {
            actionBar(player, Component.translatable("ritual.eclipse.altar.complete"));
            return;
        }
        String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        EclipseConfig.ItemCost match = null;
        for (EclipseConfig.ItemCost cost : milestone.cost()) {
            if (cost.item().equals(itemId)
                    && state.getMilestoneProgress(progressKey(milestone, cost.item())) < cost.count()) {
                match = cost;
                break;
            }
        }
        if (match == null) {
            // W13: umbral shards are shop currency, not (usually) a milestone cost — hint
            // at the sneak-deposit bank instead of barking "wrong item".
            if (stack.is(EclipseItems.UMBRAL_SHARD.get())) {
                actionBar(player, Component.translatable("shop.eclipse.deposit_hint"));
                player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.BLOCKS, 0.8F, 0.6F);
                return;
            }
            actionBar(player, Component.translatable("ritual.eclipse.altar.wrong_item"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        String key = progressKey(milestone, match.item());
        long remaining = match.count() - state.getMilestoneProgress(key);
        int consumed = (int) Math.min(stack.getCount(), remaining);
        Component itemName = Component.translatable(stack.getItem().getDescriptionId());
        stack.shrink(consumed);
        long updated = state.addMilestoneProgress(key, consumed);
        EclipseSignals.fireAltarDeposit(player, ResourceLocation.parse(itemId), consumed,
                EclipseSignals.AltarDepositPurpose.MILESTONE);

        actionBar(player, Component.translatable("ritual.eclipse.altar.progress", updated, match.count(), itemName));
        // WAVE5 (F-105 C) — C4 milestone chime ladder (IDEA-12 #5): the receipt chime
        // climbs with cost-entry progress (0.7 at the first item -> 1.2 at the last)
        // instead of the fixed 0.8, so grinding a milestone is audibly "getting
        // somewhere". `updated <= count` by construction (consumed is clamped above);
        // completeMilestone keeps its own end-portal sting as the top of the ladder.
        float chimePitch = 0.7F + 0.5F * (updated / (float) match.count());
        serverLevel.playSound(null, this.worldPosition, SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 1.0F, chimePitch);
        EclipseMod.LOGGER.debug("[w5c-chime] pitch={} progress={}/{} item={}",
                chimePitch, updated, match.count(), match.item());

        // W10: a sacrifice never goes unobserved — one gazer materializes at the treeline.
        GazerEntity.watchSacrifice(serverLevel, this.worldPosition);

        if (isMilestoneComplete(state, milestone)) {
            completeMilestone(serverLevel, state, milestone);
        } else {
            // F-076: the altar visibly swallows the payment — one strong model pulse.
            // Only when the ladder did NOT complete (stage_up owns that beat).
            triggerAnim(CONTROLLER_STATE, ANIM_HEARTBEAT);
        }
    }

    private boolean isMilestoneComplete(EclipseWorldState state, EclipseConfig.Milestone milestone) {
        for (EclipseConfig.ItemCost cost : milestone.cost()) {
            if (state.getMilestoneProgress(progressKey(milestone, cost.item())) < cost.count()) {
                return false;
            }
        }
        return true;
    }

    private void completeMilestone(ServerLevel serverLevel, EclipseWorldState state, EclipseConfig.Milestone milestone) {
        state.setAltarLevel(milestone.level());
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), state.getAltarLevel(),
                EclipseConfig.day(state.getDay()).goals()));
        // Subtle global cue: end-portal sound for everyone, portal particles at the altar. No text.
        for (ServerPlayer online : serverLevel.getServer().getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.END_PORTAL_SPAWN, SoundSource.MASTER, 0.4F, 1.3F);
        }
        serverLevel.sendParticles(ParticleTypes.PORTAL,
                this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.2D, this.worldPosition.getZ() + 0.5D,
                150, 0.6D, 0.8D, 0.6D, 0.8D);
        // W4-ISLAND / IDEA-12 #3 moment layer: the beam plus an expanding gold→violet
        // ring for everyone in beam view range. The PERMANENT tells (AltarIdleMotes
        // window, SanctumOrbitals ring growth) ride the altarLevel sync above for free.
        Vec3 fxPos = Vec3.atCenterOf(this.worldPosition).add(0.0D, 0.7D, 0.0D);
        S2CQuasarPayload beam = new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, fxPos);
        S2CQuasarPayload ring = new S2CQuasarPayload(S2CQuasarPayload.ALTAR_LEVELUP_RING,
                fxPos.add(0.0D, 0.5D, 0.0D));
        double rangeSq = BeamEmitter.VIEW_RANGE * BeamEmitter.VIEW_RANGE;
        // W-P-ALTAR: the final milestone's beam is WORLD-VISIBLE — every player gets the
        // payload regardless of range (the L5 "corona ignition" ceremony beat).
        boolean worldVisible = milestone.level() >= 5;
        for (ServerPlayer online : serverLevel.players()) {
            if (worldVisible || online.position().distanceToSqr(fxPos) <= rangeSq) {
                PacketDistributor.sendToPlayer(online, beam);
                PacketDistributor.sendToPlayer(online, ring);
            }
        }
        // W4-CEREMONY / IDEA-11 #3: one map-wide radial light pulse for EVERY player — the
        // world itself acknowledges the unlock (client path exists: FxPayloads FX_SHOCKWAVE
        // → EclipseFxState.startShockwave; W4-ISLAND owns the beam/ring sends above).
        PacketDistributor.sendToAllPlayers(new S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE,
                Vec3.atCenterOf(this.worldPosition), 0.6F, 40.0F));
        // W-P-ALTAR: the per-level ceremony escalation. The client sequences the ring /
        // pillar / glyph-rain / sky-crack / corona-ignition beats off the level in `a`
        // (AltarCeremonyFx); particle beats distance-cull client-side, screen/sky beats
        // (L4 flash, L5 corona surge) are deliberately map-wide.
        // VEIL-REPASS-2 crowd-awareness: the previously-unused `b` param now carries how
        // many players are gathered AT the altar (within CROWD_RANGE) — the client widens
        // its ceremony shockwaves with the crowd. Old payload shape unchanged (b existed).
        int crowd = 0;
        double crowdRangeSq = CROWD_RANGE * CROWD_RANGE;
        for (ServerPlayer online : serverLevel.players()) {
            if (online.position().distanceToSqr(fxPos) <= crowdRangeSq) {
                crowd++;
            }
        }
        PacketDistributor.sendToAllPlayers(new S2CFxEventPayload(FxPayloads.FX_ALTAR_LEVELUP,
                fxPos, milestone.level(), crowd));
        // F-076: the model's short ascension fanfare (rings pop, core double-pulses)
        // plays under the ceremony FX above — GeckoLib syncs the trigger to watchers.
        triggerAnim(CONTROLLER_STATE, ANIM_STAGE_UP);
        EclipseMod.LOGGER.info("Altar milestone {} completed at {}; rewards {}",
                milestone.level(), this.worldPosition, milestone.rewards());
    }

    /**
     * Progress key for a milestone cost entry: {@code altar_level_<n>} when the
     * milestone has a single cost entry, else {@code altar_level_<n>:<item_id>}.
     * Public since ALTARUI: the altar-panel payload assembler
     * ({@code network.altar.AltarPayloads}) reads live progress under the same keys.
     */
    public static String progressKey(EclipseConfig.Milestone milestone, String itemId) {
        String base = "altar_level_" + milestone.level();
        return milestone.cost().size() == 1 ? base : base + ":" + itemId;
    }

    // --- personal daily offering ---

    /**
     * Sneak-right-click with an ordinary item. First click arms the exact item type; the
     * second within five seconds consumes one item. Values and duplicate outcomes stay secret.
     */
    public void handleOffering(ServerPlayer player, ItemStack stack) {
        if (!(this.level instanceof ServerLevel serverLevel) || stack.isEmpty()) {
            return;
        }
        UUID playerId = player.getUUID();
        if (OfferingService.hasOfferedToday(player)) {
            pendingOfferings.remove(playerId);
            actionBar(player, Component.translatable("ritual.eclipse.offering.already"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.1F);
            sendOfferingGutter(serverLevel); // NEWFX-B3: the world-side rejection tell
            return;
        }
        String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        long now = serverLevel.getGameTime();
        PendingOffering pending = pendingOfferings.get(playerId);
        if (OfferingRules.needsConfirmation(now, pending == null ? null : pending.armedAt(),
                pending == null ? "" : pending.itemId(), itemId, OFFERING_CONFIRM_WINDOW_TICKS)) {
            pendingOfferings.put(playerId, new PendingOffering(now, itemId));
            actionBar(player, Component.translatable("ritual.eclipse.offering.confirm", stack.getHoverName()));
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.BLOCKS, 0.8F, 0.7F);
            // WAVE5 (F-105 C) — C2: the armed window gets a physical tell — one bounded
            // 100 t "held breath" column for everyone near the altar (same 64-block lane
            // as the accept beam below). One-shot, outcome-blind, values stay secret.
            PacketDistributor.sendToPlayersNear(serverLevel, null,
                    this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.0D,
                    this.worldPosition.getZ() + 0.5D, 64.0D,
                    new S2CQuasarPayload(OFFERING_ARMED,
                            Vec3.atCenterOf(this.worldPosition).add(0.0D, 0.7D, 0.0D)));
            return;
        }

        pendingOfferings.remove(playerId);
        // Hand anchor for the swallow flight, captured before the stack shrinks.
        Vec3 handPos = player.getEyePosition()
                .add(player.getLookAngle().scale(0.7D)).subtract(0.0D, 0.35D, 0.0D);
        java.util.OptionalInt exactValue = OfferingService.acceptWithValue(player, stack);
        if (exactValue.isEmpty()) {
            actionBar(player, Component.translatable("ritual.eclipse.offering.already"));
            sendOfferingGutter(serverLevel); // NEWFX-B3: same tell on the post-accept race
            return;
        }
        actionBar(player, Component.translatable("ritual.eclipse.offering.done"));
        // W4-ISLAND / IDEA-12 #2: the ack chime is split — the OFFERER hears a quantized
        // pitch band (a private, deniable tier tell; values stay secret, no text/numbers),
        // bystanders keep the neutral 1.0 cue so the daily-winner metagame never leaks.
        player.playNotifySound(EclipseSounds.OFFERING_ACCEPT.get(), SoundSource.BLOCKS,
                1.0F, offeringTellPitch(exactValue.getAsInt(), serverLevel.random));
        serverLevel.playSound(player, this.worldPosition, EclipseSounds.OFFERING_ACCEPT.get(),
                SoundSource.BLOCKS, 1.0F, 1.0F);
        serverLevel.sendParticles(ParticleTypes.PORTAL,
                this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.15D,
                this.worldPosition.getZ() + 0.5D, 36, 0.35D, 0.35D, 0.35D, 0.3D);
        // W4-ISLAND / IDEA-12 #1: swallow FIRST, beam second (same connection, ordered):
        // the client spirals the offered item hand → altar over ~30 t and holds the beam
        // until the item vanishes into the stone. Non-Quasar clients keep the old beat via
        // QuasarSpawner.spawnOrFallback's vanilla burst.
        // W-P-ALTAR2 value tell: the OFFERER's swallow id rides a private brightness tier
        // (same quantized buckets as the pitch tell below — deniable, never text);
        // bystanders receive the neutral mid-tier id, mirroring the split-chime law.
        ResourceLocation offeredItem = ResourceLocation.parse(itemId);
        PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(
                S2CQuasarPayload.offeringSwallow(offeredItem,
                        offeringTellTier(exactValue.getAsInt())), handPos));
        PacketDistributor.sendToPlayersNear(serverLevel, player,
                this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.0D,
                this.worldPosition.getZ() + 0.5D, 64.0D,
                new S2CQuasarPayload(S2CQuasarPayload.offeringSwallow(offeredItem), handPos));
        if (exactValue.getAsInt() == 0) {
            // WAVE6 (F-106 C) — C6 junk sniff: a zero-value offering raises NO beam — the
            // altar swallows the item (flight + portal + chimes above stay untouched) and
            // exhales a smoke cough with a low fire-extinguish instead. This reveals ONLY
            // the junk boundary (exactValue == 0), never a tier: the offeringTellPitch /
            // swallow-tier paths above remain the sole (private, deniable) value tells.
            serverLevel.sendParticles(ParticleTypes.SMOKE,
                    this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.2D,
                    this.worldPosition.getZ() + 0.5D, 24, 0.25D, 0.2D, 0.25D, 0.02D);
            serverLevel.playSound(null, this.worldPosition, SoundEvents.FIRE_EXTINGUISH,
                    SoundSource.BLOCKS, 0.7F, 0.6F);
            EclipseMod.LOGGER.debug("[w6c-sniff] item={}", itemId);
        } else {
            PacketDistributor.sendToPlayersNear(serverLevel, null,
                    this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.0D,
                    this.worldPosition.getZ() + 0.5D, 64.0D,
                    new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM,
                            Vec3.atCenterOf(this.worldPosition).add(0.0D, 0.7D, 0.0D)));
        }
        GazerEntity.watchSacrifice(serverLevel, this.worldPosition);
        // F-076: the swallow lands ON the model — one strong pulse as the item vanishes.
        triggerAnim(CONTROLLER_STATE, ANIM_HEARTBEAT);
    }

    /**
     * IDEA-12 #2 pitch buckets (junk → 0.85, mid → 1.0, high → 1.15) with ±0.03 random
     * jitter so adjacent tiers stay deniable. Ear-training only — never text.
     */
    private static float offeringTellPitch(int exactValue, net.minecraft.util.RandomSource random) {
        float base = switch (offeringTellTier(exactValue)) {
            case 0 -> 0.85F;
            case 2 -> 1.15F;
            default -> 1.0F;
        };
        return base + (random.nextFloat() - 0.5F) * 0.06F;
    }

    /**
     * IDEA-12 #2 quantized value buckets (junk ≤ 5 / mid ≤ 40 / rich), shared by the
     * private pitch tell and the W-P-ALTAR2 swallow-brightness tell so the two cues can
     * never disagree. The exact value itself must stay unobservable.
     */
    private static int offeringTellTier(int exactValue) {
        return exactValue <= 5 ? 0 : exactValue <= 40 ? 1 : 2;
    }

    // --- empty-hand sneak ---

    /**
     * ALTARFIX2 #3: sneak-right-click with an EMPTY hand. This used to be the heart
     * sacrifice (two clicks → −1 life, one heart fragment dropped on the stone) — the
     * altar's only "hand an item out" path, and the one players triggered by accident.
     * It is gone: the altar takes, it never gives. Heart fragments come from the
     * craftable Heart Extractor ({@link HeartExtractorItem}: 2 hearts → 4 fragments).
     */
    public void handleEmptyHandDeposit(ServerPlayer player) {
        actionBar(player, Component.translatable("ritual.eclipse.altar.empty_hand"));
        player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.BLOCKS, 0.6F, 0.7F);
    }

    // --- revive sigil ---

    /**
     * Right-click with a revive sigil (not sneaking): advances this player's
     * selection through {@link EclipseWorldState#getBanned()} (deterministic
     * order) and shows the selected name on the action bar.
     */
    public void handleSigilCycle(ServerPlayer player) {
        MinecraftServer server = player.server;
        List<UUID> banned = new ArrayList<>(EclipseWorldState.get(server).getBanned());
        if (banned.isEmpty()) {
            sigilSelections.remove(player.getUUID());
            actionBar(player, Component.translatable("ritual.eclipse.revive.none_banned"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        banned.sort(Comparator.comparing(UUID::toString));
        int index = banned.indexOf(sigilSelections.get(player.getUUID()));
        UUID next = banned.get((index + 1) % banned.size());
        sigilSelections.put(player.getUUID(), next);
        actionBar(player, Component.translatable("ritual.eclipse.revive.selected", resolveName(server, next)));
        player.playNotifySound(SoundEvents.EXPERIENCE_ORB_PICKUP, SoundSource.PLAYERS, 0.6F, 1.4F);
    }

    /**
     * Sneak-right-click with a revive sigil (via {@link ReviveSigilItem#useOn}):
     * starts the {@link ReviveRitual} for the currently displayed selection. The
     * ritual consumes one sigil only when it completes successfully.
     */
    public void handleSigilConfirm(ServerPlayer player) {
        if (!(this.level instanceof ServerLevel serverLevel)) {
            return;
        }
        MinecraftServer server = player.server;
        if (ReviveRitual.isRunningAt(serverLevel, this.worldPosition)) {
            actionBar(player, Component.translatable("ritual.eclipse.revive.already_running"));
            return;
        }
        UUID target = sigilSelections.get(player.getUUID());
        if (target == null || !EclipseWorldState.get(server).getBanned().contains(target)) {
            actionBar(player, Component.translatable("ritual.eclipse.revive.no_selection"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        String targetName = resolveName(server, target);
        if (ReviveRitual.start(serverLevel, this.worldPosition, player, target, targetName)) {
            sigilSelections.remove(player.getUUID());
            actionBar(player, Component.translatable("ritual.eclipse.revive.started"));
        } else {
            actionBar(player, Component.translatable("ritual.eclipse.revive.already_running"));
        }
    }

    // --- helpers ---

    /**
     * NEWFX-B3 Offering Gutter — the anti-climax to the swallow's climax: the altar
     * flame shrinks to a cold ember, coughs one FALLING gray ash puff and two dim
     * violet wisps retreat into the stone ({@code eclipse:offering_gutter} +
     * {@code eclipse:offering_gutter_puff} Quasar leg). Fired from BOTH "already
     * offered" refusal branches of {@link #handleOffering}; position lane at the altar
     * crown (the +1.15 anchor the acceptance particles use), range 32. Deliberately
     * outcome-blind — offering values and duplicate outcomes stay secret.
     */
    private void sendOfferingGutter(ServerLevel serverLevel) {
        FxPayloads.sendFxEvent(serverLevel, FxCues.CUE_OFFERING_REJECT,
                new Vec3(this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.15D,
                        this.worldPosition.getZ() + 0.5D), 0.0F, 0.0F, 32.0D);
    }

    /**
     * All altar action-bar lines funnel through here; {@link ServerLang#resolve} bakes the
     * translatables for the player's effective MOD locale (a raw translatable would resolve
     * with the client's vanilla language and show English to German players).
     */
    private static void actionBar(ServerPlayer player, Component message) {
        player.displayClientMessage(ServerLang.resolve(player, message), true);
    }

    /** Player name for a UUID: online player, then profile cache, then a short UUID prefix. */
    private static String resolveName(MinecraftServer server, UUID id) {
        ServerPlayer online = server.getPlayerList().getPlayer(id);
        if (online != null) {
            return online.getScoreboardName();
        }
        if (server.getProfileCache() != null) {
            return server.getProfileCache().get(id).map(GameProfile::getName)
                    .orElse(id.toString().substring(0, 8));
        }
        return id.toString().substring(0, 8);
    }
}
