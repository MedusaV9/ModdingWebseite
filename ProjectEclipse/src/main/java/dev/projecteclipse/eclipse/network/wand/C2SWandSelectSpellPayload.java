package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S "select this spell on my held wand" request ({@code eclipse:wand/select_spell},
 * F-039). Complements the relative sneak-scroll {@link C2SWandCyclePayload} with direct
 * selection from the tree tab's spell list. The server verifies the spell exists AND is
 * unlocked (its tree node owned) in {@code wand/WandTreeService.handleSelectSpell};
 * forged keys are dropped silently.
 *
 * @param spellKey a {@code WandSpells} key (e.g. {@code riss.blink})
 */
public record C2SWandSelectSpellPayload(String spellKey) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SWandSelectSpellPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/select_spell"));

    public static final StreamCodec<io.netty.buffer.ByteBuf, C2SWandSelectSpellPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.STRING_UTF8, C2SWandSelectSpellPayload::spellKey,
                    C2SWandSelectSpellPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SWandSelectSpellPayload> type() {
        return TYPE;
    }
}
