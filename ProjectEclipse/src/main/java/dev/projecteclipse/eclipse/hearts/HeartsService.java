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
 *
 * <p>v5 hearts rework (A13): 1 Leben/Life = {@value #HP_PER_LIFE} hp = 2 vanilla hearts.
 * The default 5 Leben therefore give exactly the vanilla 20 max health; the client
 * {@code PurpleHeartsLayer} draws ONE purple heart per Leben (compressed row), replacing
 * the vanilla hearts display entirely.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HeartsService {
    public static final int MIN_HEARTS = 0;
    /** Cap used by permanent Leben upgrades (Vitae Shard, D11 rebirth reward). */
    public static final int MAX_HEARTS = 7;
    /** Real max-health points per Leben: 1 Leben = 2 vanilla hearts (A13 hearts rework). */
    public static final int HP_PER_LIFE = 4;

    private static final ResourceLocation HEARTS_MODIFIER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "hearts");

    private HeartsService() {}

    /**
     * Replaces the transient max-health modifier with the value derived from
     * {@link LivesApi}. Five Leben therefore produce the vanilla twenty health points
     * (1 Leben = {@value #HP_PER_LIFE} hp = 2 vanilla hearts).
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
                hearts * (double) HP_PER_LIFE - 20.0D,
                AttributeModifier.Operation.ADD_VALUE));

        float lowerBound = player.isAlive() ? 1.0F : 0.0F;
        player.setHealth(Mth.clamp(player.getHealth(), lowerBound, player.getMaxHealth()));
    }

    /**
     * A13/D11: grants permanent bonus Leben (rebirth reward, Vitae-style upgrades),
     * clamped at {@link #MAX_HEARTS}. Applies max health + syncs through {@link LivesApi}.
     *
     * @return Leben actually added (0 when already at the cap)
     */
    public static int addPermanentLife(ServerPlayer player, int amount) {
        int before = LivesApi.get(player);
        int target = Math.min(MAX_HEARTS, before + Math.max(0, amount));
        if (target == before) {
            return 0;
        }
        LivesApi.set(player, target);
        return target - before;
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
