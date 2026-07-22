package dev.projecteclipse.eclipse.network;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.progression.GoalTracker;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;

/**
 * Server → client: the receiving player's personal goal lines for the current day plus one
 * completion flag per line, rendered as tick boxes by {@code client.hud.SidebarPanel}.
 *
 * <p>Since W13 the flags are real: {@link #currentFor} reads the player's
 * {@code eclipse:goal_progress} bitmask via {@link GoalTracker#mask}, and
 * {@code GoalTracker.complete} re-sends this payload on every tick change (plus a
 * rebroadcast to everyone when the event day changes).</p>
 */
public record S2CGoalProgressPayload(List<String> goalLines, List<Boolean> done) implements CustomPacketPayload {
    public S2CGoalProgressPayload {
        goalLines = List.copyOf(goalLines);
        done = List.copyOf(done);
    }

    public static final CustomPacketPayload.Type<S2CGoalProgressPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "goal_progress"));

    public static final StreamCodec<ByteBuf, S2CGoalProgressPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CGoalProgressPayload::goalLines,
            ByteBufCodecs.BOOL.apply(ByteBufCodecs.list()), S2CGoalProgressPayload::done,
            S2CGoalProgressPayload::new);

    /** The current day's goals with the receiving player's REAL completion flags (W13). */
    public static S2CGoalProgressPayload currentFor(ServerPlayer player) {
        int day = EclipseWorldState.get(player.server).getDay();
        List<String> goals = EclipseConfig.day(day).goals();
        int mask = GoalTracker.mask(player, day);
        List<Boolean> done = new ArrayList<>(goals.size());
        for (int i = 0; i < goals.size(); i++) {
            done.add((mask & (1 << i)) != 0);
        }
        return new S2CGoalProgressPayload(goals, done);
    }

    @Override
    public CustomPacketPayload.Type<S2CGoalProgressPayload> type() {
        return TYPE;
    }
}
