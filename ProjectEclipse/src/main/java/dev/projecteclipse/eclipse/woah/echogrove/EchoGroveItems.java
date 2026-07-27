package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.List;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.minecraft.world.item.component.ItemLore;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * WOAH-05 item registry (plan §3.6/§7.4). The central {@code registry/EclipseItems}
 * is a shared file, so this feature carries its OWN deferred register (the
 * {@code woah.chronostasis.ChronoStasisItems} precedent), bootstrapped from the
 * WOAH-05 anchor in {@code woah/WoahFeatures.register}.
 *
 * <p>Glint discipline follows the house rule (EclipseItems §2.3): the mote is
 * "charged questware" → glint + UNCOMMON; the blossom is a trophy-artifact →
 * EPIC, glint-free, its warm texture does the shimmering. Lore keys ship via
 * {@code docs/plans_v3/langdrop/woah_echo.json}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoGroveItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /** One collected "lost memory" (5 exist per world); deposited at the tree orbs. */
    public static final Supplier<Item> MEMORY_MOTE = ITEMS.register("memory_mote",
            () -> new Item(new Item.Properties()
                    .stacksTo(5)
                    .rarity(Rarity.UNCOMMON)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)
                    .component(DataComponents.LORE, new ItemLore(List.of(
                            Component.translatable("item.eclipse.memory_mote.lore"))))));

    /**
     * Finale reward (plan §7.4): passive trinket — while anywhere in the inventory,
     * inside the grove radius or anywhere at night, a gentle Regeneration&nbsp;I pulse
     * every 30 s up to 6 hearts ("memories keep you warm"). Ticked below.
     */
    public static final Supplier<Item> ECHO_BLOSSOM = ITEMS.register("echo_blossom",
            () -> new Item(new Item.Properties()
                    .stacksTo(1)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, new ItemLore(List.of(
                            Component.translatable("item.eclipse.echo_blossom.lore"))))));

    /** Pulse cadence (30 s) and the health ceiling (6 hearts) of the blossom trinket. */
    private static final int PULSE_INTERVAL_TICKS = 600;
    private static final float PULSE_MAX_HEALTH = 12.0F;

    private EchoGroveItems() {}

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }

    /**
     * Blossom trinket pulse: one Regen-I burst (2 s) every 30 s while below 6 hearts
     * AND (inside the grove radius OR it is night). Cost: one inventory scan every
     * 600 ticks per player — staggered by entity id so a full server never pulses
     * everyone on the same tick.
     */
    @SubscribeEvent
    static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof net.minecraft.server.level.ServerPlayer player)) {
            return;
        }
        if ((player.tickCount + (player.getId() & 63)) % PULSE_INTERVAL_TICKS != 0) {
            return;
        }
        if (player.getHealth() >= Math.min(PULSE_MAX_HEALTH, player.getMaxHealth())
                || player.isDeadOrDying()) {
            return;
        }
        if (!player.getInventory().contains(new net.minecraft.world.item.ItemStack(ECHO_BLOSSOM.get()))) {
            return;
        }
        boolean night = player.level().isNight();
        boolean inGrove = false;
        if (!night && player.level().dimension() == net.minecraft.world.level.Level.OVERWORLD) {
            int[] xz = EchoGroveLayout.landmarkXZ();
            double dx = player.getX() - xz[0];
            double dz = player.getZ() - xz[1];
            inGrove = dx * dx + dz * dz
                    <= (double) EchoGroveLayout.RADIUS * EchoGroveLayout.RADIUS;
        }
        if (night || inGrove) {
            player.addEffect(new MobEffectInstance(MobEffects.REGENERATION, 40, 0, true, false, true));
        }
    }
}
