package dev.projecteclipse.eclipse.hearts;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;

/**
 * Projects the persisted {@code eclipse:lives} attachment onto a player's real
 * maximum-health attribute. The modifier is transient so it is rebuilt exactly
 * once from the attachment instead of ever being serialized into player NBT.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HeartsService {
    public static final int MIN_HEARTS = 0;
    /** Cap used by permanent heart-upgrade items such as the later Vitae Shard. */
    public static final int MAX_HEARTS = 7;

    private static final ResourceLocation HEARTS_MODIFIER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "hearts");

    private HeartsService() {}

    /**
     * Replaces the transient max-health modifier with the value derived from
     * {@link LivesApi}. Five hearts therefore produce ten health points.
     */
    public static void apply(ServerPlayer player) {
        AttributeInstance maxHealth = player.getAttribute(Attributes.MAX_HEALTH);
        if (maxHealth == null) {
            EclipseMod.LOGGER.warn("Player {} has no MAX_HEALTH attribute; cannot apply Eclipse hearts",
                    player.getScoreboardName());
            return;
        }

        int hearts = LivesApi.get(player);
        maxHealth.addOrUpdateTransientModifier(new AttributeModifier(
                HEARTS_MODIFIER_ID,
                hearts * 2.0D - 20.0D,
                AttributeModifier.Operation.ADD_VALUE));

        float lowerBound = player.isAlive() ? 1.0F : 0.0F;
        player.setHealth(Mth.clamp(player.getHealth(), lowerBound, player.getMaxHealth()));
    }

    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            apply(player);
        }
    }

    @SubscribeEvent
    public static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            apply(player);
        }
    }

    @SubscribeEvent
    public static void onPlayerClone(PlayerEvent.Clone event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            apply(player);
        }
    }
}
