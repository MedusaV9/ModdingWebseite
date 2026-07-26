package dev.projecteclipse.eclipse.network.wand;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * S2C wand progression sync ({@code eclipse:wand/progress}, F-036 rework). The tree
 * STRUCTURE (nodes, parents, node costs, rebirth curve) is static shared Java
 * ({@code WandTree}/{@code WandSpells}) so it never rides the wire; this payload carries
 * the per-player STATE plus the server-authoritative numbers a dedicated-server client
 * cannot derive locally:
 *
 * <ul>
 *   <li>{@code level}: derived 1–5 display level; {@code xp}: spendable Wand-XP-Punkte;
 *       {@code rebirths}: the permanent counter (client computes the next rebirth cost
 *       from it via {@code WandTree.rebirthCost}).</li>
 *   <li>{@code charge}/{@code chargeMax}/{@code regenPerSecond}: the receiver's
 *       EFFECTIVE Veilladung economy (tree nodes + rebirth multipliers folded in).</li>
 *   <li>{@code damageMult}: effective spell-power multiplier (panel header stat).</li>
 *   <li>{@code xpPerCostPoint}/{@code xpKillBonus}: the server's earn tuning
 *       (panel earn-hint line).</li>
 *   <li>{@code nodes}: owned tree node ids — the client paints the whole tree from
 *       these.</li>
 *   <li>{@code spells}: one row per {@code WandSpells} entry with the receiver's
 *       EFFECTIVE cast cost (server config + cost-reduction nodes). F-040: no cooldown
 *       fields anymore — they no longer exist.</li>
 * </ul>
 *
 * <p>Sent by {@code wand/WandProgressSync} on login, cast, kill bonus, path choice, node
 * purchase, rebirth, dev edits and {@code /dev reload}. Handler feeds the client-only
 * {@code client/wand/ClientWandProgress} cache.</p>
 */
public record S2CWandProgressPayload(
        int level,
        int xp,
        int rebirths,
        int charge,
        int chargeMax,
        float regenPerSecond,
        float damageMult,
        float xpPerCostPoint,
        float xpKillBonus,
        List<String> nodes,
        List<SpellRow> spells) implements CustomPacketPayload {

    /** One spell's server tuning: key + the receiving player's effective charge cost. */
    public record SpellRow(String key, int cost) {}

    public S2CWandProgressPayload {
        nodes = List.copyOf(nodes);
        spells = List.copyOf(spells);
    }

    public static final CustomPacketPayload.Type<S2CWandProgressPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/progress"));

    public static final StreamCodec<ByteBuf, S2CWandProgressPayload> STREAM_CODEC = StreamCodec.of(
            S2CWandProgressPayload::encode,
            S2CWandProgressPayload::decode);

    private static void encode(ByteBuf buf, S2CWandProgressPayload value) {
        ByteBufCodecs.VAR_INT.encode(buf, value.level());
        ByteBufCodecs.VAR_INT.encode(buf, value.xp());
        ByteBufCodecs.VAR_INT.encode(buf, value.rebirths());
        ByteBufCodecs.VAR_INT.encode(buf, value.charge());
        ByteBufCodecs.VAR_INT.encode(buf, value.chargeMax());
        ByteBufCodecs.FLOAT.encode(buf, value.regenPerSecond());
        ByteBufCodecs.FLOAT.encode(buf, value.damageMult());
        ByteBufCodecs.FLOAT.encode(buf, value.xpPerCostPoint());
        ByteBufCodecs.FLOAT.encode(buf, value.xpKillBonus());
        ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()).encode(buf, value.nodes());
        ByteBufCodecs.VAR_INT.encode(buf, value.spells().size());
        for (SpellRow row : value.spells()) {
            ByteBufCodecs.STRING_UTF8.encode(buf, row.key());
            ByteBufCodecs.VAR_INT.encode(buf, row.cost());
        }
    }

    private static S2CWandProgressPayload decode(ByteBuf buf) {
        int level = ByteBufCodecs.VAR_INT.decode(buf);
        int xp = ByteBufCodecs.VAR_INT.decode(buf);
        int rebirths = ByteBufCodecs.VAR_INT.decode(buf);
        int charge = ByteBufCodecs.VAR_INT.decode(buf);
        int chargeMax = ByteBufCodecs.VAR_INT.decode(buf);
        float regenPerSecond = ByteBufCodecs.FLOAT.decode(buf);
        float damageMult = ByteBufCodecs.FLOAT.decode(buf);
        float perCostPoint = ByteBufCodecs.FLOAT.decode(buf);
        float killBonus = ByteBufCodecs.FLOAT.decode(buf);
        List<String> nodes = ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()).decode(buf);
        int count = ByteBufCodecs.VAR_INT.decode(buf);
        List<SpellRow> spells = new java.util.ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            spells.add(new SpellRow(
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf)));
        }
        return new S2CWandProgressPayload(level, xp, rebirths, charge, chargeMax,
                regenPerSecond, damageMult, perCostPoint, killBonus, nodes, spells);
    }

    @Override
    public CustomPacketPayload.Type<S2CWandProgressPayload> type() {
        return TYPE;
    }
}
