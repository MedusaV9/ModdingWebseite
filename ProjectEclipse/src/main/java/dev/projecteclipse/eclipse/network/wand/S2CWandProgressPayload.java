package dev.projecteclipse.eclipse.network.wand;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * S2C wand progression sync ({@code eclipse:wand/progress}, V6-FIXWIRE #5 — the payload
 * the {@code WandProgressPanel} always documented as pending). Item state (path/level/xp/charge) keeps
 * riding the synced data components; what only THIS payload carries to a dedicated-server
 * client is the SERVER's tuning + live cooldowns, which used to be estimated from the
 * client's own local {@code wand.json}:
 *
 * <ul>
 *   <li>{@code level}/{@code xp}/{@code charge}: authoritative snapshot at send time
 *       (login arrives before the first inventory mirror tick).</li>
 *   <li>{@code chargeMax}, {@code xpPerCostPoint}, {@code xpKillBonus},
 *       {@code levelCosts}: the server's {@code WandConfig} numbers the panel renders
 *       (XP bar target, charge denominator, earn-hint line).</li>
 *   <li>{@code powers}: every configured power's cost + cooldownTicks, plus the caster's
 *       REMAINING cooldown ticks at send time (0 = ready) — the panel's live countdown.</li>
 * </ul>
 *
 * <p>Sent by {@code wand/WandProgressSync} on login, after every successful cast, kill
 * bonus, path choice, dev-command progression edit and {@code /dev reload} of
 * {@code wand.json}. Client handler feeds {@code client/wand/ClientWandProgress}.</p>
 */
public record S2CWandProgressPayload(
        int level,
        int xp,
        int charge,
        int chargeMax,
        float xpPerCostPoint,
        float xpKillBonus,
        List<Integer> levelCosts,
        List<PowerRow> powers) implements CustomPacketPayload {

    /** One power's server tuning + the receiving player's live cooldown at send time. */
    public record PowerRow(String key, int cost, int cooldownTicks, int cooldownRemainingTicks) {}

    public S2CWandProgressPayload {
        levelCosts = List.copyOf(levelCosts);
        powers = List.copyOf(powers);
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
        ByteBufCodecs.VAR_INT.encode(buf, value.charge());
        ByteBufCodecs.VAR_INT.encode(buf, value.chargeMax());
        ByteBufCodecs.FLOAT.encode(buf, value.xpPerCostPoint());
        ByteBufCodecs.FLOAT.encode(buf, value.xpKillBonus());
        ByteBufCodecs.VAR_INT.apply(ByteBufCodecs.list()).encode(buf, value.levelCosts());
        ByteBufCodecs.VAR_INT.encode(buf, value.powers().size());
        for (PowerRow row : value.powers()) {
            ByteBufCodecs.STRING_UTF8.encode(buf, row.key());
            ByteBufCodecs.VAR_INT.encode(buf, row.cost());
            ByteBufCodecs.VAR_INT.encode(buf, row.cooldownTicks());
            ByteBufCodecs.VAR_INT.encode(buf, row.cooldownRemainingTicks());
        }
    }

    private static S2CWandProgressPayload decode(ByteBuf buf) {
        int level = ByteBufCodecs.VAR_INT.decode(buf);
        int xp = ByteBufCodecs.VAR_INT.decode(buf);
        int charge = ByteBufCodecs.VAR_INT.decode(buf);
        int chargeMax = ByteBufCodecs.VAR_INT.decode(buf);
        float perCostPoint = ByteBufCodecs.FLOAT.decode(buf);
        float killBonus = ByteBufCodecs.FLOAT.decode(buf);
        List<Integer> levelCosts = ByteBufCodecs.VAR_INT.apply(ByteBufCodecs.list()).decode(buf);
        int count = ByteBufCodecs.VAR_INT.decode(buf);
        List<PowerRow> powers = new java.util.ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            powers.add(new PowerRow(
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf)));
        }
        return new S2CWandProgressPayload(level, xp, charge, chargeMax,
                perCostPoint, killBonus, levelCosts, powers);
    }

    @Override
    public CustomPacketPayload.Type<S2CWandProgressPayload> type() {
        return TYPE;
    }
}
