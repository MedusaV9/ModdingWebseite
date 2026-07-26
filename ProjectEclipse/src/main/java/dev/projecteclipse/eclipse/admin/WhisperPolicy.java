package dev.projecteclipse.eclipse.admin;

import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import com.mojang.brigadier.ParseResults;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.context.ParsedCommandNode;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.protection.DevMode;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.CommandEvent;

/**
 * F-052 — whisper containment: a normal player may only {@code /msg} the event host
 * ({@value #DEFAULT_HOST}), never another player. Everything else about the whisper
 * commands stays vanilla.
 *
 * <p><b>Why {@link CommandEvent} and not a Brigadier redirect.</b> Replacing the vanilla
 * {@code /msg} node (or wrapping its {@code targets} argument) rebuilds the command tree
 * that is sent to clients, which is exactly what breaks tab completion and the client-side
 * argument parsers for the redirected {@code /tell} and {@code /w} aliases. Intercepting the
 * already-parsed command leaves the tree — and therefore completion — untouched, and it
 * covers all three aliases at once because they redirect to the same node.</p>
 *
 * <p>Ops (permission ≥ {@link Commands#LEVEL_GAMEMASTERS}), players with {@code /devmode} on
 * and the hosts in {@link #ALLOWED_TARGETS} themselves are exempt. {@code /teammsg} and
 * {@code /tm} are deliberately NOT handled here — the anonymity layer still seals those in
 * {@code anonymity.CommandBlocker}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WhisperPolicy {
    /** The one player everybody is allowed to whisper (the event host). */
    public static final String DEFAULT_HOST = "Sonic0810";

    /**
     * Whisper recipients allowed for normal players, matched case-insensitively. A list
     * rather than a single name so a co-host can be added with a one-line edit.
     */
    public static final List<String> ALLOWED_TARGETS = List.of(DEFAULT_HOST);

    /** Vanilla whisper roots; {@code tell}/{@code w} redirect to the {@code msg} node. */
    private static final Set<String> WHISPER_ROOTS = Set.of("msg", "tell", "w");

    /** Argument name of the recipients in vanilla {@code MsgCommand}. */
    private static final String TARGETS_ARGUMENT = "targets";

    private WhisperPolicy() {}

    @SubscribeEvent
    public static void onCommand(CommandEvent event) {
        ParseResults<CommandSourceStack> results = event.getParseResults();
        List<ParsedCommandNode<CommandSourceStack>> nodes = results.getContext().getNodes();
        if (nodes.isEmpty() || !WHISPER_ROOTS.contains(nodes.get(0).getNode().getName())) {
            return;
        }
        CommandSourceStack source = results.getContext().getSource();
        if (source.hasPermission(Commands.LEVEL_GAMEMASTERS)) {
            return;
        }
        if (source.getEntity() instanceof ServerPlayer player
                && (DevMode.isExempt(player) || isAllowed(player.getGameProfile().getName()))) {
            // The host is exempt from his own rule — otherwise he could never answer the
            // whispers this policy funnels to him, which is the whole point of it.
            return;
        }

        Collection<ServerPlayer> targets = recipients(results);
        if (targets == null) {
            // The selector did not resolve (offline name, empty selector). Vanilla will
            // report that itself and nothing is delivered — leave the error to it.
            return;
        }
        for (ServerPlayer target : targets) {
            if (!isAllowed(target.getGameProfile().getName())) {
                event.setCanceled(true);
                deny(source);
                return;
            }
        }
    }

    /** Case-insensitive membership test against {@link #ALLOWED_TARGETS}. */
    public static boolean isAllowed(String playerName) {
        String name = playerName == null ? "" : playerName.strip().toLowerCase(Locale.ROOT);
        return ALLOWED_TARGETS.stream().anyMatch(allowed -> allowed.toLowerCase(Locale.ROOT).equals(name));
    }

    /**
     * Resolves the parsed {@code targets} selector. The whisper aliases are Brigadier
     * REDIRECTS, so the arguments live in the innermost child context — reading them off the
     * root context would silently find nothing and let every whisper through.
     */
    private static Collection<ServerPlayer> recipients(ParseResults<CommandSourceStack> results) {
        try {
            CommandContext<CommandSourceStack> context = results.getContext()
                    .build(results.getReader().getString());
            while (context.getChild() != null) {
                context = context.getChild();
            }
            return EntityArgument.getPlayers(context, TARGETS_ARGUMENT);
        } catch (CommandSyntaxException | RuntimeException e) {
            EclipseMod.LOGGER.debug("Whisper policy could not resolve recipients — leaving it to vanilla", e);
            return null;
        }
    }

    private static void deny(CommandSourceStack source) {
        ServerPlayer player = source.getEntity() instanceof ServerPlayer sender ? sender : null;
        source.sendFailure(ServerLang.tr(player, "message.eclipse.whisper.denied", DEFAULT_HOST));
    }
}
