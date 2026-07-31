package dev.projecteclipse.eclipse.client.item;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArmArtifactItem;
import dev.projecteclipse.eclipse.client.collections.ClientCollectionsCache;
import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import dev.projecteclipse.eclipse.client.progression.ClientBestiaryCache;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.ritual.HeartExtractorItem;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.inventory.InventoryScreen;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.BlockEntityWithoutLevelRenderer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.extensions.common.IClientItemExtensions;
import net.neoforged.neoforge.client.extensions.common.RegisterClientExtensionsEvent;
import software.bernie.geckolib.animatable.GeoItem;

/**
 * Client wiring for the ITEMS-A GeckoLib items (arm artifact, heart extractor).
 * Self-registering — the {@code WandClientExtensions} pattern with no shared-file edits.
 * NeoForge 21.1's {@code AutomaticEventSubscriber} routes each listener to the bus its
 * event type belongs to, so one {@link EventBusSubscriber} class can hold both the MOD-bus
 * renderer registration and the GAME-bus animation hooks below (the deprecated
 * {@code bus =} attribute is not needed and is ignored).
 *
 * <h2>1. Renderer registration (MOD bus)</h2>
 * {@link RegisterClientExtensionsEvent} hangs each {@code GeoItemRenderer} onto its item
 * via {@link IClientItemExtensions#getCustomRenderer()} (both item models are
 * {@code builtin/entity}, so vanilla routes every perspective there, GUI included).
 * Renderers are created lazily ON first use so no GeckoLib model loading happens before
 * resource managers exist.
 *
 * <p>No {@code isBound()} guard needed here: unlike the wiring-doc-gated
 * {@code WandItems}, {@code EclipseItems.register} is a core line in
 * {@code EclipseMod}'s constructor — the holders are always bound by the time the
 * client-extensions event fires.</p>
 *
 * <h2>2. Unread-ledger tracker (GAME bus, MD2)</h2>
 * The census asks the artifact to breathe while the ledger holds UNREAD entries. There is
 * no unread flag anywhere in the mod — the bestiary/collections caches only expose their
 * synced knowledge — so this class derives one client-side from a monotonic
 * {@link #knowledgeScore knowledge score} (sum of bestiary tiers over all {@code eclipse:}
 * entity ids + granted collection tiers + discovered item-lexicon entries). Anything above
 * the score as of the last {@link HandbookScreen} visit counts as unread. Recomputation is
 * gated on the two caches' {@code generation()} counters, so a normal tick costs two int
 * comparisons.
 *
 * <p>Seeding is the delicate part: at login the server pushes the bestiary, collections and
 * lexicon snapshots over several ticks, and a naive baseline would read those as fresh
 * discoveries. The score is therefore re-baselined on every change during the first
 * {@value #SEED_GRACE_TICKS} ticks after the local player appears, and again whenever it
 * DROPS (logout wipe, collections config reload) — the flag fails quiet, never noisy.</p>
 *
 * <h2>3. Equip one-shots (GAME bus, MD2)</h2>
 * Both items own an {@code equip} flourish. GeckoLib's own trigger path is server-side, but
 * drawing an item is a purely cosmetic, purely client-side moment, and
 * {@code SingletonGeoAnimatable#triggerAnim} short-circuits to
 * {@code AnimatableInstanceCache#getManagerForId} when the passed entity is on a client
 * level — verified in GeckoLib 4.9.2 bytecode. The instance id must be {@link GeoItem#getId}
 * (NOT {@code getOrAssignId}, which is server-only): that is exactly what
 * {@code GeoItemRenderer#getInstanceId} feeds the renderer, including the shared
 * {@code Long.MAX_VALUE} bucket that stacks use before the server ever assigns them one.
 *
 * <p>Edge detection is per hand and by {@link Item} identity, so swapping hotbar slots
 * between two different items fires once. The artifact additionally flourishes when the
 * survival inventory opens: it lives PINNED in {@code ArtifactSlotLock.ARTIFACT_SLOT} and is
 * essentially never held, so the inventory is the only moment a player actually looks at
 * it.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ItemsAClientExtensions {
    /**
     * Ticks after the local player appears during which every score change re-baselines
     * instead of raising the flag. 5 s comfortably covers the login snapshot burst
     * (bestiary, collections and item lexicon arrive as three separate payloads).
     */
    private static final int SEED_GRACE_TICKS = 100;

    /** {@code Integer.MIN_VALUE} = "no snapshot seen yet"; the caches start at generation 0. */
    private static int lastBestiaryGen = Integer.MIN_VALUE;
    private static int lastCollectionsGen = Integer.MIN_VALUE;
    private static int knowledgeScore;
    private static int readScore;
    private static boolean unread;
    private static int joinTicks;

    private static Item lastMainHand;
    private static Item lastOffHand;
    private static boolean inventoryWasOpen;

    private ItemsAClientExtensions() {}

    // ---------------------------------------------------------------- renderers (MOD bus)

    @SubscribeEvent
    static void onRegisterClientExtensions(RegisterClientExtensionsEvent event) {
        register(event, EclipseItems.ARM_ARTIFACT.get(), ArmArtifactRenderer::new);
        register(event, EclipseItems.HEART_EXTRACTOR.get(), HeartExtractorRenderer::new);
    }

    private static void register(RegisterClientExtensionsEvent event, Item item,
            Supplier<? extends BlockEntityWithoutLevelRenderer> rendererFactory) {
        event.registerItem(new IClientItemExtensions() {
            private BlockEntityWithoutLevelRenderer renderer;

            @Override
            public BlockEntityWithoutLevelRenderer getCustomRenderer() {
                if (renderer == null) {
                    renderer = rendererFactory.get();
                }
                return renderer;
            }
        }, item);
    }

    // ------------------------------------------------------------- unread ledger (GAME bus)

    /**
     * Whether the ledger holds entries the player has not opened the handbook for since —
     * drives the artifact's {@code base} controller swap to
     * {@code animation.arm_artifact.idle_unread}. Read through
     * {@link ArmArtifactRenderer#hasUnreadLedgerEntries()} so the item class keeps
     * referencing a renderer the way {@code HeartExtractorItem} does.
     */
    static boolean hasUnreadLedgerEntries() {
        return unread;
    }

    /**
     * Sum of everything the handbook can show as "known". Monotonic in normal play: bestiary
     * tiers and collection tiers only ever climb, and the item lexicon only grows. Iterating
     * the entity registry is the only way to enumerate bestiary ids from here — the roster
     * itself is private to {@code BestiaryTab} — and it is strictly a superset of that
     * roster, so a future mob is tracked the moment it ships (unknown ids score 0).
     */
    private static int computeKnowledgeScore() {
        int score = 0;
        for (ResourceLocation id : BuiltInRegistries.ENTITY_TYPE.keySet()) {
            if (EclipseMod.MOD_ID.equals(id.getNamespace())) {
                score += ClientBestiaryCache.tierFor(id.getPath());
            }
        }
        for (ClientCollectionsCache.Entry entry : ClientCollectionsCache.all()) {
            score += entry.grantedTier();
        }
        return score + ClientCollectionsCache.discoveredItemCount();
    }

    private static void updateUnreadLedger(Minecraft minecraft) {
        if (joinTicks < SEED_GRACE_TICKS) {
            joinTicks++;
        }
        int bestiaryGen = ClientBestiaryCache.generation();
        int collectionsGen = ClientCollectionsCache.generation();
        if (bestiaryGen != lastBestiaryGen || collectionsGen != lastCollectionsGen) {
            lastBestiaryGen = bestiaryGen;
            lastCollectionsGen = collectionsGen;
            knowledgeScore = computeKnowledgeScore();
            if (joinTicks < SEED_GRACE_TICKS || knowledgeScore < readScore) {
                readScore = knowledgeScore; // login burst, or progress was wiped/reloaded
            }
            unread = knowledgeScore > readScore;
        }
        if (minecraft.screen instanceof HandbookScreen) {
            readScore = knowledgeScore;
            unread = false;
        }
    }

    // ------------------------------------------------------------- equip flourish (GAME bus)

    /**
     * Fires an item's {@code equip} one-shot on the client that is looking at it.
     * No-ops for anything that is not one of the two ITEMS-A items.
     */
    private static void triggerEquip(LocalPlayer player, ItemStack stack) {
        long instanceId = GeoItem.getId(stack);
        if (stack.getItem() instanceof ArmArtifactItem artifact) {
            artifact.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION,
                    ArmArtifactItem.ANIM_EQUIP);
        } else if (stack.getItem() instanceof HeartExtractorItem extractor) {
            extractor.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION,
                    HeartExtractorItem.ANIM_EQUIP);
        }
    }

    private static void updateEquipTriggers(Minecraft minecraft, LocalPlayer player) {
        ItemStack mainHand = player.getMainHandItem();
        if (mainHand.getItem() != lastMainHand) {
            lastMainHand = mainHand.getItem();
            triggerEquip(player, mainHand);
        }
        ItemStack offHand = player.getOffhandItem();
        if (offHand.getItem() != lastOffHand) {
            lastOffHand = offHand.getItem();
            triggerEquip(player, offHand);
        }

        boolean inventoryOpen = minecraft.screen instanceof InventoryScreen;
        if (inventoryOpen && !inventoryWasOpen) {
            for (int slot = 0; slot < player.getInventory().getContainerSize(); slot++) {
                ItemStack stack = player.getInventory().getItem(slot);
                if (stack.getItem() instanceof ArmArtifactItem) {
                    triggerEquip(player, stack);
                    break;
                }
            }
        }
        inventoryWasOpen = inventoryOpen;
    }

    // ------------------------------------------------------------------- lifecycle (GAME bus)

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null) {
            return;
        }
        updateUnreadLedger(minecraft);
        updateEquipTriggers(minecraft, player);
    }

    /** Fresh session: re-seed the baseline from whatever the server syncs next. */
    @SubscribeEvent
    static void onLoggingIn(ClientPlayerNetworkEvent.LoggingIn event) {
        resetSession();
    }

    /** One server's ledger state must never leak into the next (the caches reset too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        resetSession();
    }

    /**
     * Respawn / dimension change: the player entity is replaced, so hand tracking has to
     * forget its edge state — but the unread baseline must SURVIVE, or dying would silently
     * mark the ledger read.
     */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        lastMainHand = null;
        lastOffHand = null;
        inventoryWasOpen = false;
    }

    private static void resetSession() {
        lastBestiaryGen = Integer.MIN_VALUE;
        lastCollectionsGen = Integer.MIN_VALUE;
        knowledgeScore = 0;
        readScore = 0;
        unread = false;
        joinTicks = 0;
        lastMainHand = null;
        lastOffHand = null;
        inventoryWasOpen = false;
    }
}
