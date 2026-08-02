package dev.projecteclipse.eclipse.network.night;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * WAVE6 (F-106 A) A1 — server → client: the active night event ({@code none}/{@code pale}/
 * {@code umbral}, the {@code EclipseWorldState.NIGHT_EVENT_*} vocabulary) plus the day it
 * was rolled on. Sent on nightfall ({@code EclipseSpawner.announceNightEvent}), at dawn
 * ({@code EclipseSpawner.clearNightEvent}, event = none), on login and by the
 * {@link NightPayloads.Sync} drift watcher (covers {@code /eclipse event set none}, which
 * mutates the state without traversing either spawner hook).
 *
 * <p>Client sink: {@code client.drama.NightDreadFx} (installed consumer — this package
 * stays loadable on dedicated servers). Before this payload existed, NO renderer could
 * know an Umbral/Pale Night was running (WAVE6_PLAN §1.3 census).</p>
 */
public record S2CNightEventPayload(String event, int day) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CNightEventPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "night/event"));

    public static final StreamCodec<ByteBuf, S2CNightEventPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.STRING_UTF8, S2CNightEventPayload::event,
                    ByteBufCodecs.VAR_INT, S2CNightEventPayload::day,
                    S2CNightEventPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CNightEventPayload> type() {
        return TYPE;
    }
}
