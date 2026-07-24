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
    /** W4-ISLAND: altar level-up flattened ring burst (IDEA-12 #3 moment layer). */
    public static final ResourceLocation ALTAR_LEVELUP_RING = emitter("altar_levelup_ring");
    /**
     * W4-ISLAND: offering swallow (IDEA-12 #1). The bare id is the trail emitter JSON;
     * live payloads ride the offered item id in the path suffix
     * ({@link #offeringSwallow}) so no new payload shape is needed — the client handler
     * routes any {@code offering_swallow/…} id to {@code client.drama.OfferingSwallowFx}.
     */
    public static final ResourceLocation OFFERING_SWALLOW = emitter("offering_swallow");

    private static final String OFFERING_SWALLOW_PREFIX = "offering_swallow/";

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

    /**
     * Offering-swallow emitter id carrying the offered item:
     * {@code eclipse:offering_swallow/<item namespace>/<item path>} (both components are
     * already valid resource-location path characters, so the composite id is well-formed).
     * This neutral form implies the mid value-tell tier ({@code 1}) — it is what
     * bystanders receive.
     */
    public static ResourceLocation offeringSwallow(ResourceLocation itemId) {
        return emitter(OFFERING_SWALLOW_PREFIX + itemId.getNamespace() + "/" + itemId.getPath());
    }

    /**
     * W-P-ALTAR2 value tell: offering-swallow id additionally carrying an OFFERER-PRIVATE
     * brightness tier ({@code 0} junk / {@code 1} mid / {@code 2} rich — the IDEA-12 #2
     * pitch buckets): {@code eclipse:offering_swallow/t<tier>/<ns>/<path>}. Sent only to
     * the offerer; everyone else gets the neutral {@link #offeringSwallow(ResourceLocation)}
     * form so the daily-winner metagame never leaks (the split-chime law).
     */
    public static ResourceLocation offeringSwallow(ResourceLocation itemId, int tier) {
        int clamped = Math.min(Math.max(tier, 0), 2);
        return emitter(OFFERING_SWALLOW_PREFIX + "t" + clamped + "/"
                + itemId.getNamespace() + "/" + itemId.getPath());
    }

    /** The item id riding an offering-swallow emitter id, or {@code null} for other ids. */
    @javax.annotation.Nullable
    public static ResourceLocation offeringSwallowItem(ResourceLocation emitterId) {
        String rest = offeringSwallowRest(emitterId);
        if (rest == null) {
            return null;
        }
        int slash = rest.indexOf('/');
        if (slash <= 0 || slash >= rest.length() - 1) {
            return null;
        }
        return ResourceLocation.tryBuild(rest.substring(0, slash), rest.substring(slash + 1));
    }

    /**
     * The value-tell tier riding an offering-swallow id; {@code 1} (mid/neutral) when the
     * id carries no tier segment or is not an offering-swallow id at all.
     */
    public static int offeringSwallowTier(ResourceLocation emitterId) {
        if (EclipseMod.MOD_ID.equals(emitterId.getNamespace())
                && emitterId.getPath().startsWith(OFFERING_SWALLOW_PREFIX)) {
            String rest = emitterId.getPath().substring(OFFERING_SWALLOW_PREFIX.length());
            if (hasTierSegment(rest)) {
                return rest.charAt(1) - '0';
            }
        }
        return 1;
    }

    /** Swallow-id remainder with the optional {@code t<tier>/} segment stripped, or null. */
    @javax.annotation.Nullable
    private static String offeringSwallowRest(ResourceLocation emitterId) {
        if (!EclipseMod.MOD_ID.equals(emitterId.getNamespace())
                || !emitterId.getPath().startsWith(OFFERING_SWALLOW_PREFIX)) {
            return null;
        }
        String rest = emitterId.getPath().substring(OFFERING_SWALLOW_PREFIX.length());
        return hasTierSegment(rest) ? rest.substring(3) : rest;
    }

    /** {@code t<0..2>/} tier segment probe (no real item namespace collides with it). */
    private static boolean hasTierSegment(String rest) {
        return rest.length() > 3 && rest.charAt(0) == 't' && rest.charAt(2) == '/'
                && rest.charAt(1) >= '0' && rest.charAt(1) <= '2';
    }

    @Override
    public CustomPacketPayload.Type<S2CQuasarPayload> type() {
        return TYPE;
    }
}
