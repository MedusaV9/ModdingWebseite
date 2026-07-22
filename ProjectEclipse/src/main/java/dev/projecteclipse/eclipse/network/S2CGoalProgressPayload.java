package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;

/**
 * Server → client: the receiving player's personal goal lines for the current day plus one
 * completion flag per line, rendered as tick boxes by {@code client.hud.SidebarPanel}.
 *
 * <p>TODO(W13): v1 has no server-side goal-completion tracking (goals are plain strings in
 * {@code days.json}) — {@link #currentFor} therefore sends every flag as {@code false}.
 * Worker 13's goal ticking replaces that factory body with real per-player progress
 * (the {@code eclipse:goal_progress} attachment) and re-broadcasts on every tick change.</p>
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

    /**
     * The current day's goals with all-false completion flags — the pre-W13 stand-in
     * (see class TODO). Same payload for every player until per-player tracking exists.
     */
    public static S2CGoalProgressPayload currentFor(MinecraftServer server) {
        List<String> goals = EclipseConfig.day(EclipseWorldState.get(server).getDay()).goals();
        return new S2CGoalProgressPayload(goals, java.util.Collections.nCopies(goals.size(), Boolean.FALSE));
    }

    @Override
    public CustomPacketPayload.Type<S2CGoalProgressPayload> type() {
        return TYPE;
    }
}
