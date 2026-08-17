package de.sonic0810.goobymod.item;

import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModItems;
import java.util.List;
import java.util.UUID;
import javax.annotation.Nullable;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;

/**
 * Gooby-Ball: Rechtsklick wirft GENAU einen Ball als {@link ItemEntity} mit
 * Besitzer-Signatur. Der Wurf ist serverautoritativ: die Owner-UUID liegt in
 * den PersistentData der ItemEntity (ueberlebt Chunk-Reload), niemals im
 * ItemStack — aufgehobene Baelle sind wieder ganz normale Wurf-Items.
 * {@code GoobyFetchGoal} apportiert ausschliesslich Baelle des eigenen
 * Besitzers zurueck.
 *
 * <p>Merge-Schutz: geworfene Baelle bekommen zusaetzlich das Vanilla-Target
 * des Werfers plus ein gebounded ablaufendes Prioritaetsfenster (Cleanup via
 * {@code GoobyEvents.onItemTick}). Vanilla {@code ItemEntity.tryToMerge}
 * verlangt identische Targets — dadurch sind im Fenster sowohl Merges
 * zwischen Baellen VERSCHIEDENER Werfer (Signatur-Uebernahme) als auch mit
 * ungetaggten Boden-Stacks (stiller Signatur-Verlust) blockiert; Baelle
 * DESSELBEN Werfers duerfen weiterhin mergen und werden vom Gooby
 * Ball-fuer-Ball apportiert.</p>
 */
public final class GoobyBallItem extends Item {
    /** ItemEntity-PersistentData-Key: UUID des Werfers (= Fetch-Berechtigter). */
    public static final String BALL_OWNER_TAG = "GoobyModBallOwner";
    /** Wurf-Cooldown pro Spieler — kein Ball-Spam, kein Fetch-Goal-Flackern. */
    public static final int THROW_COOLDOWN_TICKS = 20;
    /** Werfer sammelt den fliegenden Ball nicht sofort selbst wieder ein. */
    public static final int PLAYER_PICKUP_DELAY_TICKS = 32;
    /**
     * Solange haelt das Werfer-Target auf dem geworfenen Ball: blockt
     * Fremd-Pickup UND Fremd-/Untagged-Merges, bis der Apport laengst durch
     * ist. Danach raeumt {@code GoobyEvents.onItemTick} das Target ab und der
     * Ball verhaelt sich wieder wie ein normales Item.
     */
    public static final int OWNER_PRIORITY_WINDOW_TICKS = 600;
    private static final double THROW_SPEED = 0.55;
    private static final double THROW_LIFT = 0.14;

    public GoobyBallItem(Properties properties) {
        super(properties);
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        // Serverautoritative Cooldown-Pruefung: der Client blockt zwar schon in
        // der GUI, aber ein manipuliertes Use-Paket darf keinen Spam werfen.
        if (player.getCooldowns().isOnCooldown(this)) {
            return InteractionResultHolder.fail(stack);
        }
        player.getCooldowns().addCooldown(this, THROW_COOLDOWN_TICKS);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.SNOWBALL_THROW, SoundSource.PLAYERS, 0.6F, 1.15F);
        if (level instanceof ServerLevel serverLevel) {
            throwBall(serverLevel, player, stack);
        }
        return InteractionResultHolder.sidedSuccess(stack, level.isClientSide);
    }

    /**
     * Testbarer Wurf-Kern: verbraucht (ausser im Creative) genau EIN Item aus
     * dem Stack und spawnt genau EINE ItemEntity mit Count 1 — die
     * Stack-Erhaltung ist die zentrale Dupe-Invariante.
     */
    public static ItemEntity throwBall(ServerLevel level, Player player, ItemStack stack) {
        ItemEntity ball = new ItemEntity(level, player.getX(), player.getEyeY() - 0.3, player.getZ(),
                stack.copyWithCount(1));
        Vec3 direction = player.getViewVector(1.0F);
        ball.setDeltaMovement(direction.x * THROW_SPEED, direction.y * THROW_SPEED + THROW_LIFT,
                direction.z * THROW_SPEED);
        ball.setThrower(player);
        ball.setPickUpDelay(PLAYER_PICKUP_DELAY_TICKS);
        ball.getPersistentData().putUUID(BALL_OWNER_TAG, player.getUUID());
        // Vanilla-Target + Ablauf-Fenster (siehe Klassen-Javadoc): schuetzt
        // Signatur und Pickup-Vorrang; der Fetch-Pickup des Goobys ist
        // Custom-Code und ignoriert das Target bewusst.
        ball.setTarget(player.getUUID());
        ball.getPersistentData().putLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG,
                level.getGameTime() + OWNER_PRIORITY_WINDOW_TICKS);
        // Verbrauch erst NACH erfolgreichem Spawn: cancelt ein Fremdmod das
        // EntityJoinLevelEvent, geht im Survival kein Ball verloren.
        if (level.addFreshEntity(ball) && !player.getAbilities().instabuild) {
            stack.shrink(1);
        }
        return ball;
    }

    /** UUID des Werfers oder {@code null} fuer nicht geworfene/fremde Item-Drops. */
    @Nullable
    public static UUID throwerOf(ItemEntity item) {
        if (!item.getItem().is(ModItems.GOOBY_BALL.get())
                || !item.getPersistentData().hasUUID(BALL_OWNER_TAG)) {
            return null;
        }
        return item.getPersistentData().getUUID(BALL_OWNER_TAG);
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable("tooltip.goobymod.gooby_ball").withStyle(ChatFormatting.GRAY));
        tooltip.add(Component.translatable("tooltip.goobymod.gooby_ball.fetch")
                .withStyle(ChatFormatting.DARK_GRAY));
    }
}
