package dev.projecteclipse.eclipse.network;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.lang.LangService;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;

/** Server → client: current event day, altar level, and the day's goal lines. */
public record S2CDayStatePayload(int day, int altarLevel, List<String> goals) implements CustomPacketPayload {
    public S2CDayStatePayload {
        goals = List.copyOf(goals);
    }

    public static final CustomPacketPayload.Type<S2CDayStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "day_state"));

    public static final StreamCodec<ByteBuf, S2CDayStatePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CDayStatePayload::day,
            ByteBufCodecs.VAR_INT, S2CDayStatePayload::altarLevel,
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CDayStatePayload::goals,
            S2CDayStatePayload::new);

    /** Current day state with every server-baked goal picked for the receiver's locale. */
    public static S2CDayStatePayload currentFor(ServerPlayer player) {
        EclipseWorldState state = EclipseWorldState.get(player.server);
        return currentFor(player, state.getDay(), state.getAltarLevel());
    }

    /** Explicit day/altar variant used by the day-change broadcast choke point. */
    public static S2CDayStatePayload currentFor(ServerPlayer player, int day, int altarLevel) {
        List<Localized> configured = EclipseConfig.day(day).localizedGoals();
        List<String> localized = new ArrayList<>(configured.size());
        for (Localized goal : configured) {
            localized.add(LangService.pick(goal, player));
        }
        return new S2CDayStatePayload(day, altarLevel, localized);
    }

    @Override
    public CustomPacketPayload.Type<S2CDayStatePayload> type() {
        return TYPE;
    }
}
