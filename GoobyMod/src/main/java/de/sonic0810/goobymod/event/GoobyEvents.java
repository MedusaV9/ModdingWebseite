package de.sonic0810.goobymod.event;

import com.mojang.brigadier.arguments.StringArgumentType;
import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobySoundLimiter;
import de.sonic0810.goobymod.entity.GoobyTrick;
import de.sonic0810.goobymod.entity.goals.CatStareAtGoobyGoal;
import de.sonic0810.goobymod.entity.goals.RabbitFollowWildGoobyGoal;
import de.sonic0810.goobymod.network.GoobyNetwork;
import de.sonic0810.goobymod.registry.ModItems;
import java.util.Locale;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.UuidArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.GoalSelector;
import net.minecraft.world.entity.ai.goal.WrappedGoal;
import net.minecraft.world.entity.animal.Cat;
import net.minecraft.world.entity.animal.Rabbit;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.event.ServerChatEvent;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent.PlayerLoggedOutEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.EntityTickEvent;

@EventBusSubscriber(modid = GoobyMod.MODID)
public final class GoobyEvents {
    /** Nur noch Legacy-Cleanup: das persistente Pre-5.1-Flag wird beim Join entfernt. */
    private static final String FAUNA_GOALS_ADDED = "GoobyModFaunaGoals";

    /** Wildhase + Nutella = GOOBY! Der magische Moment. */
    @SubscribeEvent
    public static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (!(event.getTarget() instanceof Rabbit rabbit) || rabbit.isBaby()) {
            return;
        }
        ItemStack stack = event.getItemStack();
        if (!stack.is(ModItems.NUTELLA.get())) {
            return;
        }
        event.setCanceled(true);
        event.setCancellationResult(InteractionResult.sidedSuccess(event.getLevel().isClientSide));
        if (!event.getLevel().isClientSide) {
            feedNutellaToRabbit(event.getEntity(), rabbit, stack);
        }
    }

    /** Testbarer Kern der Konversion — wird auch von GameTests direkt aufgerufen. */
    public static GoobyEntity feedNutellaToRabbit(Player player, Rabbit rabbit, ItemStack stack) {
        if (!player.getAbilities().instabuild) {
            stack.shrink(1);
        }
        return GoobyEntity.convertFromRabbit(rabbit, player);
    }

    @SubscribeEvent
    public static void onEntityJoin(EntityJoinLevelEvent event) {
        if (!event.getLevel().isClientSide) {
            injectFaunaGoals(event.getEntity());
        }
    }

    /**
     * Injiziert die transienten Fauna-Goals idempotent pro geladener
     * Entity-Instanz; gibt {@code true} zurueck, wenn ein Goal neu ergaenzt wurde.
     *
     * <p>Goals werden nie ins NBT geschrieben, muessen also bei JEDEM Join
     * einer Instanz neu gesetzt werden — auch nach Chunk-Reload oder
     * Server-Neustart. Ein persistentes NBT-Flag (der Pre-5.1-Bug) ueberlebte
     * den Reload, waehrend das Goal selbst verschwand, und blockierte die
     * erneute Injektion dauerhaft. Stattdessen prueft die Injektion direkt den
     * lebenden GoalSelector; das Legacy-Flag wird aus alten Saves entfernt.</p>
     */
    public static boolean injectFaunaGoals(Entity entity) {
        // getPersistentData() allokiert das Tag lazily — deshalb nur fuer die
        // beiden Arten anfassen, die das Pre-5.1-Flag ueberhaupt tragen konnten.
        if (entity instanceof Rabbit rabbit) {
            rabbit.getPersistentData().remove(FAUNA_GOALS_ADDED);
            if (!hasGoal(rabbit.goalSelector, RabbitFollowWildGoobyGoal.class)) {
                rabbit.goalSelector.addGoal(5, new RabbitFollowWildGoobyGoal(rabbit));
                return true;
            }
            return false;
        }
        if (entity instanceof Cat cat) {
            cat.getPersistentData().remove(FAUNA_GOALS_ADDED);
            if (!hasGoal(cat.goalSelector, CatStareAtGoobyGoal.class)) {
                cat.goalSelector.addGoal(7, new CatStareAtGoobyGoal(cat));
                return true;
            }
        }
        return false;
    }

    private static boolean hasGoal(GoalSelector selector, Class<? extends Goal> goalType) {
        for (WrappedGoal wrapped : selector.getAvailableGoals()) {
            if (goalType.isInstance(wrapped.getGoal())) {
                return true;
            }
        }
        return false;
    }

    /** Gift ownership is exclusive for ten seconds, then normal pickup rules resume. */
    @SubscribeEvent
    public static void onItemTick(EntityTickEvent.Post event) {
        if (!(event.getEntity() instanceof ItemEntity item)
                || item.level().isClientSide || item.getTarget() == null) {
            return;
        }
        long priorityUntil = item.getPersistentData().getLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG);
        if (priorityUntil > 0L && item.level().getGameTime() >= priorityUntil) {
            item.setTarget(null);
            item.getPersistentData().remove(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG);
        }
    }

    @SubscribeEvent
    public static void onServerChat(ServerChatEvent event) {
        if (GoobyConfig.nameRecognition()) {
            handleNameRecognition(event.getPlayer(), event.getRawText());
        }
    }

    @SubscribeEvent
    public static void onPlayerLogout(PlayerLoggedOutEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        GoobyNetwork.forgetSelectSender(player.getUUID());
        for (var level : player.getServer().getAllLevels()) {
            for (var entity : level.getAllEntities()) {
                if (entity instanceof GoobyEntity gooby) {
                    gooby.removeTransientPlayerState(player.getUUID());
                }
            }
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        GoobySoundLimiter.clear();
        GoobyNetwork.clearSelectThrottle();
    }

    /** Bounded nearby scan; returns the number of owned Goobys that reacted. */
    public static int handleNameRecognition(ServerPlayer player, String rawMessage) {
        String message = rawMessage.toLowerCase(Locale.ROOT);
        int reactions = 0;
        for (GoobyEntity gooby : player.serverLevel().getEntitiesOfClass(GoobyEntity.class,
                player.getBoundingBox().inflate(32.0),
                candidate -> candidate.isOwnedBy(player) && candidate.hasCustomName())) {
            if (mentionsName(message, gooby.getCustomName().getString())) {
                gooby.reactToName(player);
                reactions++;
            }
        }
        return reactions;
    }

    public static boolean mentionsName(String lowerCaseMessage, String goobyName) {
        String name = goobyName.strip().toLowerCase(Locale.ROOT);
        return !name.isEmpty() && lowerCaseMessage.contains(name);
    }

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("goobytrick")
                .then(Commands.argument("gooby", UuidArgument.uuid())
                        .then(Commands.argument("trick", StringArgumentType.word())
                                .suggests((context, builder) -> SharedSuggestionProvider.suggest(
                                        java.util.Arrays.stream(GoobyTrick.values())
                                                .map(GoobyTrick::serializedName), builder))
                                .executes(context -> {
                                    ServerPlayer player = context.getSource().getPlayerOrException();
                                    GoobyTrick trick = GoobyTrick.byNameStrict(
                                            StringArgumentType.getString(context, "trick"));
                                    if (trick == null) {
                                        context.getSource().sendFailure(
                                                Component.translatable("msg.goobymod.trick_menu_invalid"));
                                        return 0;
                                    }
                                    // Exakt dieselbe Autorisierung wie der native Screen
                                    // (alive/owner/baby/range/trainiert) inklusive
                                    // Spam-Drosselung — keine Policy-Divergenz.
                                    return GoobyNetwork.handleSelectRequest(player,
                                            UuidArgument.getUuid(context, "gooby"), trick)
                                            .accepted() ? 1 : 0;
                                }))));
    }

    private GoobyEvents() {
    }
}
