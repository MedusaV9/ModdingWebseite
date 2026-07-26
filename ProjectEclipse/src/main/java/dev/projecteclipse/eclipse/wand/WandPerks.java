package dev.projecteclipse.eclipse.wand;

import dev.projecteclipse.eclipse.skills.SkillPerks;
import net.minecraft.server.level.ServerPlayer;

/**
 * WANDFIX-4: the wand-side reader for the skill tree's wand branch (nodes W1–W18 in
 * {@code skills/SkillTreeConfig}). One typed accessor per effect contract, all backed by
 * {@link SkillPerks#effect} (summed {@code effect.value} across owned nodes), with hard
 * caps applied HERE so a hand-edited {@code skilltree.json} can never zero a cast cost,
 * erase a cooldown or stack absurd damage. No wand behavior changes for players who own
 * nothing in the branch — every accessor degrades to the identity value.
 *
 * <p>Contracts (also listed in the skilltree {@code _doc}): {@code wand_charge_max_add}
 * (flat Veilladung), {@code wand_regen_pct}, {@code wand_cost_reduce_pct} (cap 40%),
 * {@code wand_cooldown_reduce_pct} (cap 50%), {@code wand_damage_pct} (cap +100%),
 * {@code wand_xp_pct}, {@code wand_free_cast_chance} (rolled through
 * {@link SkillPerks#procChance} so S3 Eclipsed folds in, proc feedback trio on hit).
 * Consumers: {@code EclipseWandItem.regenCharge}, {@code WandPowers} (cost / cooldown /
 * damage / XP), {@code WandPhaseService} (shear), {@code WandProgressSync} (per-player
 * effective numbers on the wire).</p>
 */
public final class WandPerks {
    /** Cost reduction cap — a cast must always cost something real. */
    private static final float COST_REDUCE_CAP = 0.40F;
    /** Cooldown reduction cap — spam ceilings stay meaningful. */
    private static final float COOLDOWN_REDUCE_CAP = 0.50F;
    /** Damage bonus cap. */
    private static final float DAMAGE_CAP = 1.00F;

    private WandPerks() {}

    /** Per-player Veilladung maximum: config max + owned {@code wand_charge_max_add}. */
    public static int chargeMax(ServerPlayer player) {
        return WandConfig.get().charge().max()
                + Math.max(0, Math.round(SkillPerks.effect(player, "wand_charge_max_add")));
    }

    /** Regen multiplier ({@code wand_regen_pct}); 1.0 without the perks. */
    public static float regenMultiplier(ServerPlayer player) {
        return 1.0F + Math.max(0.0F, SkillPerks.effect(player, "wand_regen_pct"));
    }

    /** Effective charge cost of a power for this player (floors at 1, cap 40% off). */
    public static int effectiveCost(ServerPlayer player, WandConfig.Power power) {
        float reduce = Math.clamp(SkillPerks.effect(player, "wand_cost_reduce_pct"),
                0.0F, COST_REDUCE_CAP);
        return Math.max(1, Math.round(power.cost() * (1.0F - reduce)));
    }

    /** Effective cooldown ticks of a power for this player (floors at 10, cap 50% off). */
    public static int effectiveCooldownTicks(ServerPlayer player, WandConfig.Power power) {
        float reduce = Math.clamp(SkillPerks.effect(player, "wand_cooldown_reduce_pct"),
                0.0F, COOLDOWN_REDUCE_CAP);
        return Math.max(10, Math.round(power.cooldownTicks() * (1.0F - reduce)));
    }

    /** Damage multiplier for every wand power hit ({@code wand_damage_pct}, cap +100%). */
    public static float damageMultiplier(ServerPlayer player) {
        return 1.0F + Math.clamp(SkillPerks.effect(player, "wand_damage_pct"), 0.0F, DAMAGE_CAP);
    }

    /** Wand-XP multiplier ({@code wand_xp_pct}); 1.0 without the perks. */
    public static float xpMultiplier(ServerPlayer player) {
        return 1.0F + Math.max(0.0F, SkillPerks.effect(player, "wand_xp_pct"));
    }

    /**
     * W18 Herz des Schleiers: rolls the free-cast chance and fires the standard proc
     * feedback trio on success. Called AFTER a cast executed, right before the charge is
     * deducted — a free cast still pays cooldown and still earns full XP.
     */
    public static boolean rollFreeCast(ServerPlayer player) {
        float base = SkillPerks.effect(player, "wand_free_cast_chance");
        if (base <= 0.0F
                || player.serverLevel().random.nextFloat() >= SkillPerks.procChance(player, base)) {
            return false;
        }
        SkillPerks.sendProcFeedback(player, "wand_free_cast", 1.0F);
        return true;
    }
}
