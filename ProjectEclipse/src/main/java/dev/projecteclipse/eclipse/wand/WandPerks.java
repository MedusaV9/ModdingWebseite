package dev.projecteclipse.eclipse.wand;

import java.util.Set;

import net.minecraft.server.level.ServerPlayer;

/**
 * F-036: the aggregated effect reader of the wand's OWN skill tree ({@link WandTree},
 * persisted per player in {@link WandStore.Progress}) plus the permanent rebirth
 * multipliers. Replaces the old WANDFIX-4 bridge into the shared skill tree's wand
 * branch (W1–W18) — the wand now carries its whole progression itself. Hard caps are
 * applied HERE so no data edit can zero a cast cost or stack absurd damage; every
 * accessor degrades to the identity value for players who own nothing.
 *
 * <p>Contracts (summed {@code effectValue} across owned stat nodes):
 * {@link WandTree#FX_CHARGE_MAX_ADD} (flat Veilladung), {@link WandTree#FX_REGEN_PCT},
 * {@link WandTree#FX_COST_REDUCE_PCT} (cap 40%), {@link WandTree#FX_DAMAGE_PCT}
 * (cap +100%). Rebirths add {@code +15%} spell power and {@code +10%} max Veilladung
 * each ({@link WandTree#REBIRTH_POWER_PCT}/{@link WandTree#REBIRTH_CHARGE_PCT}).
 * F-040: there is NO cooldown contract anymore — cooldowns are gone entirely.</p>
 *
 * <p>Consumers: {@code EclipseWandItem.regenCharge}, {@code WandPowers} (cost/damage),
 * {@code WandSpellEffects}, {@code WandProgressSync} (per-player effective numbers on
 * the wire), {@code WandTreeService} (purchase/rebirth flow).</p>
 */
public final class WandPerks {
    /** Cost reduction cap — a cast must always cost something real. */
    private static final float COST_REDUCE_CAP = 0.40F;
    /** Node damage bonus cap (rebirth power multiplies ON TOP, uncapped by design). */
    private static final float DAMAGE_CAP = 1.00F;

    private WandPerks() {}

    /** Summed effect value of one contract across the player's owned stat nodes. */
    private static float effect(ServerPlayer player, String type) {
        WandStore.Progress progress = WandStore.get(player.server).progress(player.getUUID());
        Set<String> owned = progress.nodes;
        if (owned.isEmpty()) {
            return 0.0F;
        }
        float sum = 0.0F;
        for (String id : owned) {
            WandTree.Node node = WandTree.byId(id);
            if (node != null && type.equals(node.effectType())) {
                sum += node.effectValue();
            }
        }
        return sum;
    }

    private static int rebirths(ServerPlayer player) {
        return Math.max(0, WandStore.get(player.server).progress(player.getUUID()).rebirths);
    }

    /**
     * Per-player Veilladung maximum: (config max + owned {@code charge_max_add}) ×
     * (1 + 10% per rebirth).
     */
    public static int chargeMax(ServerPlayer player) {
        float base = WandConfig.get().charge().max()
                + Math.max(0.0F, effect(player, WandTree.FX_CHARGE_MAX_ADD));
        float rebirthMult = 1.0F + WandTree.REBIRTH_CHARGE_PCT * rebirths(player);
        return Math.max(1, Math.round(base * rebirthMult));
    }

    /** Regen multiplier ({@code regen_pct} nodes); 1.0 without the perks. */
    public static float regenMultiplier(ServerPlayer player) {
        return 1.0F + Math.max(0.0F, effect(player, WandTree.FX_REGEN_PCT));
    }

    /** Effective charge cost of a spell for this player (floors at 1, cap 40% off). */
    public static int effectiveCost(ServerPlayer player, WandConfig.Power power) {
        float reduce = Math.clamp(effect(player, WandTree.FX_COST_REDUCE_PCT),
                0.0F, COST_REDUCE_CAP);
        return Math.max(1, Math.round(power.cost() * (1.0F - reduce)));
    }

    /**
     * Damage multiplier for every wand spell hit: (1 + capped node bonus) ×
     * (1 + 15% spell power per rebirth) — the rebirth half is the permanent F-036 payoff.
     */
    public static float damageMultiplier(ServerPlayer player) {
        float nodes = 1.0F + Math.clamp(effect(player, WandTree.FX_DAMAGE_PCT), 0.0F, DAMAGE_CAP);
        float rebirth = 1.0F + WandTree.REBIRTH_POWER_PCT * rebirths(player);
        return nodes * rebirth;
    }

    /** Wand-XP multiplier — currently identity (reserved for future tree/rebirth hooks). */
    public static float xpMultiplier(ServerPlayer player) {
        return 1.0F;
    }
}
