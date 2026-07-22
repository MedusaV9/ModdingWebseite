package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

/**
 * Server → client: spawn a one-shot Quasar particle emitter at a world position. Handled by
 * {@code veilfx.QuasarSpawner#spawnOrFallback} (client-only), which falls back to a small
 * vanilla particle burst when Veil/Quasar is unavailable or the emitter id is unknown.
 *
 * <p>The well-known emitter ids below match the JSONs under
 * {@code assets/eclipse/quasar/emitters/}; server-side senders (rituals, cutscenes, border,
 * bosses) should reference these constants instead of re-building the ids.</p>
 */
public record S2CQuasarPayload(ResourceLocation emitterId, Vec3 pos) implements CustomPacketPayload {
    public static final ResourceLocation ALTAR_BEAM = emitter("altar_beam");
    public static final ResourceLocation ARM_WISPS = emitter("arm_wisps");
    public static final ResourceLocation MAP_EXPAND_MATERIALIZE = emitter("map_expand_materialize");
    public static final ResourceLocation BORDER_GLITCH = emitter("border_glitch");
    public static final ResourceLocation BOSS_SLAM = emitter("boss_slam");
    public static final ResourceLocation HEART_BURST = emitter("heart_burst");
    public static final ResourceLocation LIMBO_MOTES = emitter("limbo_motes");
    public static final ResourceLocation CUTSCENE_VEIL = emitter("cutscene_veil");

    public static final CustomPacketPayload.Type<S2CQuasarPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "quasar"));

    public static final StreamCodec<ByteBuf, S2CQuasarPayload> STREAM_CODEC = StreamCodec.composite(
            ResourceLocation.STREAM_CODEC, S2CQuasarPayload::emitterId,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().x,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().y,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().z,
            (emitterId, x, y, z) -> new S2CQuasarPayload(emitterId, new Vec3(x, y, z)));

    private static ResourceLocation emitter(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name);
    }

    @Override
    public CustomPacketPayload.Type<S2CQuasarPayload> type() {
        return TYPE;
    }
}
