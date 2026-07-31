package dev.projecteclipse.eclipse.artifact;

import java.util.List;

import dev.projecteclipse.eclipse.entity.geo.EclipseActionController;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.network.EclipsePayloads;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.SlotAccess;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.ClickAction;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.fml.loading.FMLEnvironment;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * The player's permanent in-game interface artifact ({@code eclipse:arm_artifact}).
 * Lives PINNED in inventory slot {@value ArtifactSlotLock#ARTIFACT_SLOT} — the top-right
 * storage slot of the inventory GUI (enforced by {@link ArtifactSlotLock}), cannot be
 * dropped (toss is cancelled there), never enters a death grave
 * ({@link ArtifactDropGuard}, B17) and cannot be nested inside container items
 * ({@link #canFitInsideContainerItems()}).
 *
 * <p><b>Right-click-in-inventory flow (v3, plans_v3 P3 §3.1):</b>
 * {@link #overrideOtherStackedOnMe} is the bundle-pattern hook — it fires when the
 * artifact's slot is clicked with ANY carried stack (including an empty cursor) and it
 * runs on BOTH sides of the container click. Returning {@code true} for BOTH click
 * actions consumes the click, which makes the stack un-pickable by mouse: visual pinning
 * with zero menu mixins (shift-move/number-swap bypass this hook and are reverted by the
 * {@link ArtifactSlotLock} sweep within a second). On {@link ClickAction#SECONDARY} the
 * CLIENT side additionally routes through
 * {@code client.ArtifactScreenOpener#openFromInventory()}, which defers one frame so the
 * container-close packet leaves before the handbook opens. That client-only class is
 * referenced strictly inside the {@code isClientSide} branch (never taken on a dedicated
 * server), the same lazy-classload convention {@code network.EclipsePayloads} documents.</p>
 *
 * <p><b>Held right-click fallback ({@link #use}):</b> the item can sit in the hotbar
 * transiently (fresh grant before the first sweep), so {@code use()} keeps working: the
 * server pushes fresh {@code S2CLivesPayload} + {@code S2CDayStatePayload} and then a
 * {@code S2COpenArtifactPayload}; same-connection ordering guarantees the
 * {@code ClientStateCache} is fresh by the time the open instruction lands.</p>
 *
 * <p><b>GeckoLib (PLAN-ITEMS A2):</b> the artifact is a geo item (severed-forearm model,
 * {@code geo/item/arm_artifact.geo.json}) following the wand pilot's controller idiom —
 * a {@code base} controller loops {@code animation.arm_artifact.idle} (ledger-mote orbit
 * + slow finger curl) and an {@code action} controller holds the triggerable
 * {@value #ANIM_OPEN} one-shot (fingers splay, mote flares), fired server-side at both
 * ledger-open moments this class owns: the held right-click and the server side of the
 * pinned-slot secondary click. The plan's optional {@code deny} anim is skipped —
 * {@link ArtifactSlotLock} exposes no per-refusal hook and adding one is out of scope.
 * Rendering registers through {@code client/item/ItemsAClientExtensions}
 * ({@code IClientItemExtensions#getCustomRenderer} → {@code ArmArtifactRenderer});
 * {@code models/item/arm_artifact.json} is {@code builtin/entity}.</p>
 */
public class ArmArtifactItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/arm_artifact.geo.json}, {@code animation.arm_artifact.*}). */
    public static final String GEO_ID = "arm_artifact";
    /** Triggerable one-shot on the {@code action} controller: the ledger-open flick. */
    public static final String ANIM_OPEN = "open";
    /** Base-controller loop while the ledger holds unread entries (breathing pulse). */
    public static final String ANIM_IDLE_UNREAD = "idle_unread";
    /**
     * Triggerable one-shot on the {@code action} controller: the draw/reveal flourish.
     * Fired CLIENT-side only, by {@code client/item/ItemsAClientExtensions} — drawing an
     * item is cosmetic, so it never travels over the wire.
     */
    public static final String ANIM_EQUIP = "equip";

    /** Mirrors the client suite's {@code EclipseUiTheme.ACCENT} (that class is client-only). */
    private static final int TOOLTIP_ACCENT = 0xB98CFF;

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public ArmArtifactItem(Properties properties) {
        super(properties);
        // Required for server-side triggerAnim() to reach tracking clients.
        SingletonGeoAnimatable.registerSyncedAnimatable(this);
    }

    // ------------------------------------------------------------------ GeckoLib

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return geoCache;
    }

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE, 4, state -> {
            if (FMLEnvironment.dist == Dist.CLIENT
                    // Lazy fully-qualified client reference (HeartExtractorItem pattern) —
                    // the predicate only executes while a client renders the item.
                    && dev.projecteclipse.eclipse.client.item.ArmArtifactRenderer.hasUnreadLedgerEntries()) {
                return state.setAndContinue(EclipseGeoAnimations.loop(GEO_ID, ANIM_IDLE_UNREAD));
            }
            return state.setAndContinue(EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE));
        }));
        // POLISH2 (contract v2): `open` blends 2 t (worst single-frame snap 26.0° on
        // glow_page_a.roty out of idle_unread -> 13°/frame; the screen-open on the same
        // tick is unaffected). `equip` MUST stay hard: its sheet starts `ledger.roty`
        // at -360° (a full authored spin) which is pose-identical to idle's 0° on a cut,
        // but an unwrapped 2 t transition would whip the ledger a whole revolution.
        AnimationController<ArmArtifactItem> action = new EclipseActionController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION,
                animName -> ANIM_OPEN.equals(animName) ? 2 : 0,
                state -> PlayState.STOP);
        action.triggerableAnim(ANIM_OPEN, EclipseGeoAnimations.once(GEO_ID, ANIM_OPEN));
        action.triggerableAnim(ANIM_EQUIP, EclipseGeoAnimations.once(GEO_ID, ANIM_EQUIP));
        controllers.add(action);
    }

    /** Server-side {@value #ANIM_OPEN} one-shot, synced to tracking clients (wand pattern). */
    private static void triggerOpenAnim(ServerPlayer player, ItemStack stack) {
        if (stack.getItem() instanceof ArmArtifactItem artifact) {
            long instanceId = GeoItem.getOrAssignId(stack, player.serverLevel());
            artifact.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_OPEN);
        }
    }

    /** Keeps the artifact out of shulker boxes and bundles. */
    @Override
    public boolean canFitInsideContainerItems() {
        return false;
    }

    /**
     * Consumes every mouse click on the artifact's slot (= pinning) and opens the handbook
     * on right-click. {@code stack} is the artifact in the slot, {@code other} the carried
     * stack (possibly empty); see the class javadoc for the full flow.
     */
    @Override
    public boolean overrideOtherStackedOnMe(ItemStack stack, ItemStack other, Slot slot, ClickAction action,
            Player player, SlotAccess access) {
        if (action == ClickAction.SECONDARY) {
            if (player.level().isClientSide()) {
                dev.projecteclipse.eclipse.client.ArtifactScreenOpener.openFromInventory();
            } else if (player instanceof ServerPlayer serverPlayer) {
                // Server side of the same container click — the ledger-open moment for
                // the pinned slot; GeckoLib syncs the one-shot on its own channel.
                triggerOpenAnim(serverPlayer, stack);
            }
        }
        return true;
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        if (player instanceof ServerPlayer serverPlayer) {
            triggerOpenAnim(serverPlayer, player.getItemInHand(hand));
            EclipsePayloads.sendArtifactState(serverPlayer, true);
        }
        return InteractionResultHolder.sidedSuccess(player.getItemInHand(hand), level.isClientSide());
    }

    /** The one-line affordance for the pinned slot: "Right-click: open the ledger". */
    @Override
    public void appendHoverText(ItemStack stack, Item.TooltipContext context, List<Component> tooltipComponents,
            TooltipFlag tooltipFlag) {
        tooltipComponents.add(Component.translatable("item.eclipse.arm_artifact.tooltip").withColor(TOOLTIP_ACCENT));
    }
}
