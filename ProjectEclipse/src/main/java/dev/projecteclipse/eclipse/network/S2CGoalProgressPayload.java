package dev.projecteclipse.eclipse.network;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.LangService;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.QuestEngine;
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
 * <p>Since P4-B2 the payload is re-sourced from the quest engine (wire shape UNCHANGED —
 * plan §2.2 "Legacy bridge"): {@link #currentFor} renders TODAY'S MAIN goals from
 * {@code progression/goals/QuestEngine} — lines are the specs' {@code Localized} text
 * picked per receiver via {@code LangService}, flags are the engine's main done flags
 * (team scopes read the team flag). When a day has no goals.json entry the engine's
 * config fallback renders the legacy days.json strings as manual mains, so this payload
 * keeps working on unmigrated content. The engine re-sends on every progress change; the
 * richer {@code S2CQuestStatePayload} (mains + sides + personals with counters) ships
 * alongside for P3's new HUD.</p>
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

    /** Today's main goals (engine-sourced, receiver-localized) with real completion flags. */
    public static S2CGoalProgressPayload currentFor(ServerPlayer player) {
        List<GoalSpec> mains = QuestEngine.currentMains(player.server);
        List<String> lines = new ArrayList<>(mains.size());
        for (GoalSpec spec : mains) {
            lines.add(LangService.pick(spec.text(), player));
        }
        return new S2CGoalProgressPayload(lines, QuestEngine.mainDoneFlags(player.server, player));
    }

    @Override
    public CustomPacketPayload.Type<S2CGoalProgressPayload> type() {
        return TYPE;
    }
}
