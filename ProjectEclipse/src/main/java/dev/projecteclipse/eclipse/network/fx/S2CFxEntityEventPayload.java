package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

/**
 * Server → client: entity-anchored FX cue — the ONE small payload addition the
 * IDEAS-mobs.md batch pre-authorizes ("a 1-int entity-id cue variant is the honest
 * carrier"). Shape mirrors {@link S2CFxEventPayload} plus the target's entity id: the
 * client resolves the id against its tracked entities and hands the cue to
 * {@code PhotonFxRegistry.dispatchEntity}; when the entity is not tracked (or already
 * gone) the row's legs degrade to the {@code pos} anchor, exactly like the position lane.
 *
 * <p>{@code pos} deliberately stays in the payload (instead of reading the entity
 * client-side) so the Quasar fallback leg and the degraded Photon anchor are
 * server-authoritative and identical on every client.</p>
 *
 * <p>Current senders: {@code ChargedLungeGoal} (hound windup/dash,
 * {@code FxCues.CUE_HOUND_WINDUP}/{@code CUE_HOUND_DASH}), {@code WandPowers.
 * castMagmasprung} ({@code CUE_GLUT_SPRUNG} cast-time launch — the landing re-send rides
 * the position lane from {@code WandTickService.MagmaJump}) and {@code SkyLauncher.launch}
 * ({@code CUE_SKY_LAUNCH} contrail on the launched player).</p>
 */
public record S2CFxEntityEventPayload(ResourceLocation id, int entityId, Vec3 pos, float a, float b)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CFxEntityEventPayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/entity_event"));

    /** Hand-rolled: 7 fields exceed {@code StreamCodec.composite}'s 6-component ceiling. */
    public static final StreamCodec<ByteBuf, S2CFxEntityEventPayload> STREAM_CODEC = StreamCodec.of(
            (buf, payload) -> {
                ResourceLocation.STREAM_CODEC.encode(buf, payload.id());
                ByteBufCodecs.VAR_INT.encode(buf, payload.entityId());
                buf.writeDouble(payload.pos().x);
                buf.writeDouble(payload.pos().y);
                buf.writeDouble(payload.pos().z);
                buf.writeFloat(payload.a());
                buf.writeFloat(payload.b());
            },
            buf -> new S2CFxEntityEventPayload(
                    ResourceLocation.STREAM_CODEC.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    new Vec3(buf.readDouble(), buf.readDouble(), buf.readDouble()),
                    buf.readFloat(),
                    buf.readFloat()));

    @Override
    public CustomPacketPayload.Type<S2CFxEntityEventPayload> type() {
        return TYPE;
    }
}
