package dev.projecteclipse.eclipse.wand;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.network.wand.C2SWandCastPayload;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
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
 * Der Zauberstab — the mod's first GeckoLib <b>item</b> (IDEA-19 §1.1). Mirrors the frozen
 * P6 entity controller convention adapted for items: a {@code base} controller loops
 * {@code animation.eclipse_wand.idle}, an {@code action} controller holds the triggerable
 * one-shots ({@value #ANIM_USE}, {@value #ANIM_LEVELUP}, {@value #ANIM_AWAKEN},
 * {@value #ANIM_STALL}) fired server-side via {@link #triggerWandAnim} — GeckoLib syncs
 * those on its own channel because the constructor registers the item as a synced
 * animatable.
 *
 * <p>Rendering registers through NeoForge's {@code IClientItemExtensions}
 * ({@code client/wand/WandClientExtensions}) returning a {@code GeoItemRenderer}; the item
 * model {@code models/item/eclipse_wand.json} is {@code builtin/entity} so vanilla routes
 * to it. Per-path model evolution = bone-visibility + texture swap in
 * {@code client/wand/EclipseWandRenderer} keyed off the {@code wand_path}/{@code wand_level}
 * components.</p>
 *
 * <p>Interaction: right-click with a pathless wand opens the client path chooser; with a
 * chosen path it sends the {@code C2SWandCastPayload} cast request (ALL validation —
 * charge, cooldown, path, disabled state, protection zones — is server-side in
 * {@link WandPowers}). Sneak-right-click cycles the selected power server-side.</p>
 */
public final class EclipseWandItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/eclipse_wand.geo.json}, {@code animation.eclipse_wand.*}). */
    public static final String GEO_ID = "eclipse_wand";

    public static final String ANIM_USE = "use";
    public static final String ANIM_LEVELUP = "levelup";
    public static final String ANIM_AWAKEN = "awaken";
    public static final String ANIM_STALL = "stall";

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public EclipseWandItem(Properties properties) {
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
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE, 4,
                state -> state.setAndContinue(EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE))));
        AnimationController<EclipseWandItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_USE, EclipseGeoAnimations.once(GEO_ID, ANIM_USE));
        action.triggerableAnim(ANIM_LEVELUP, EclipseGeoAnimations.once(GEO_ID, ANIM_LEVELUP));
        action.triggerableAnim(ANIM_AWAKEN, EclipseGeoAnimations.once(GEO_ID, ANIM_AWAKEN));
        action.triggerableAnim(ANIM_STALL, EclipseGeoAnimations.once(GEO_ID, ANIM_STALL));
        controllers.add(action);
    }

    /** Server-side one-shot on the {@code action} controller, synced to tracking clients. */
    public static void triggerWandAnim(ServerPlayer player, ItemStack stack, String animName) {
        if (stack.getItem() instanceof EclipseWandItem wand) {
            long instanceId = GeoItem.getOrAssignId(stack, player.serverLevel());
            wand.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION, animName);
        }
    }

    // ------------------------------------------------------------------ interaction

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        if (player.isSecondaryUseActive()) {
            if (!level.isClientSide && player instanceof ServerPlayer serverPlayer) {
                WandPowers.cycleSelected(serverPlayer, stack);
            }
            return InteractionResultHolder.consume(stack);
        }
        if (level.isClientSide) {
            if (WandSoulbind.pathOf(stack) == WandPath.NONE) {
                // Lazy fully-qualified client reference (FxPayloads pattern) — never loads
                // on a dedicated server because this branch never executes there.
                dev.projecteclipse.eclipse.client.wand.WandPathScreen.open();
            } else {
                net.neoforged.neoforge.network.PacketDistributor.sendToServer(
                        new C2SWandCastPayload(hand == InteractionHand.MAIN_HAND));
            }
        }
        // Server-side casting happens exclusively through the validated payload path.
        return InteractionResultHolder.consume(stack);
    }

    @Override
    public void inventoryTick(ItemStack stack, Level level, Entity entity, int slotId, boolean isSelected) {
        if (level.isClientSide || !(entity instanceof ServerPlayer player) || player.isSpectator()) {
            return;
        }
        WandSoulbind.tick(player, stack);
        if (level.getGameTime() % 20L == 0L) {
            regenCharge(level, stack, isSelected || player.getOffhandItem() == stack);
        }
    }

    /** Once-a-second Veilladung regen; faster in held hands and during the dark hours. */
    private static void regenCharge(Level level, ItemStack stack, boolean held) {
        WandConfig.Charge config = WandConfig.get().charge();
        int charge = stack.getOrDefault(WandItems.WAND_CHARGE.get(), config.max());
        if (charge >= config.max()) {
            return;
        }
        float regen = held ? config.regenHeldPerSecond() : config.regenStowedPerSecond();
        if (level.isNight()) {
            regen *= config.nightMult();
        }
        int whole = (int) regen;
        float fraction = regen - whole;
        if (fraction > 0.0F && level.random.nextFloat() < fraction) {
            whole++;
        }
        if (whole > 0) {
            stack.set(WandItems.WAND_CHARGE.get(), Math.min(config.max(), charge + whole));
        }
    }

    // ------------------------------------------------------------------ presentation

    @Override
    public void appendHoverText(ItemStack stack, Item.TooltipContext context,
            List<Component> tooltip, TooltipFlag flag) {
        WandPath path = WandSoulbind.pathOf(stack);
        if (path == WandPath.NONE) {
            tooltip.add(Component.translatable("wand.eclipse.tooltip.pathless")
                    .withStyle(ChatFormatting.DARK_PURPLE, ChatFormatting.ITALIC));
        } else {
            int level = WandSoulbind.levelOf(stack);
            tooltip.add(Component.translatable("wand.eclipse.tooltip.path",
                            Component.translatable(path.langKey()), level)
                    .withStyle(ChatFormatting.LIGHT_PURPLE));
            int selected = Math.min(stack.getOrDefault(WandItems.WAND_SELECTED.get(), 0), level - 1);
            tooltip.add(Component.translatable("wand.eclipse.tooltip.selected",
                            Component.translatable(path.powerLangKey(selected)))
                    .withStyle(ChatFormatting.GRAY));
        }
        Integer charge = stack.get(WandItems.WAND_CHARGE.get());
        if (charge != null) {
            tooltip.add(Component.translatable("wand.eclipse.tooltip.charge",
                    charge, WandConfig.get().charge().max()).withStyle(ChatFormatting.DARK_AQUA));
        }
        UUID owner = stack.get(WandItems.WAND_OWNER.get());
        if (owner == null) {
            tooltip.add(Component.translatable("wand.eclipse.tooltip.unbound")
                    .withStyle(ChatFormatting.DARK_GRAY));
        } else if (FMLEnvironment.dist == Dist.CLIENT) {
            // Lazy client helper resolves the owner's display name from the tab list.
            tooltip.add(dev.projecteclipse.eclipse.client.wand.WandClientHints.ownerLine(owner));
        }
    }
}
