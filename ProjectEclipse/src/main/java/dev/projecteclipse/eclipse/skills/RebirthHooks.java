package dev.projecteclipse.eclipse.skills;

import java.util.UUID;

import dev.projecteclipse.eclipse.rebirth.RebirthApi;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * D2/D11 seam between the skill engine and the rebirth system. Created by D2 (the skill
 * curve indirection) and filled by D11: every per-player curve lookup in {@code skills}
 * routes through {@link #curveFor}, which applies the global per-rebirth level-cost
 * multiplier ({@code levelCostMultiplierPerRebirth ^ rebirthCount}) to {@code baseCost}.
 *
 * <p>Also the sanctioned entry for the rebirth transaction's full progression wipe:
 * {@link #resetSkillProgression} bridges to the package-private
 * {@code SkillsApi.resetAllProgression} helper so the frozen public {@code SkillsApi}
 * surface stays untouched.</p>
 */
public final class RebirthHooks {
    private RebirthHooks() {}

    /**
     * Per-player effective curve: {@code base} with {@code baseCost} scaled by the
     * player's rebirth level-cost multiplier. Returns {@code base} unchanged for players
     * who never rebirthed (multiplier 1.0) — zero cost on the hot path.
     */
    public static SkillCurve.Params curveFor(MinecraftServer server, UUID uuid, SkillCurve.Params base) {
        double multiplier = RebirthApi.levelCostMultiplier(server, uuid);
        if (multiplier == 1.0D) {
            return base;
        }
        return new SkillCurve.Params(base.baseCost() * multiplier,
                base.exponent(), base.softcapLevel(), base.softcapMult());
    }

    /**
     * FULL skill + level reset for the rebirth ceremony: zeroes lifetime XP, remainder,
     * owned nodes, spent/bonus points and {@code lastLevelSeen} (so re-earned levels grant
     * fresh points), keeping only the proc-message preference and the secret multiplier.
     * Ends in a client resync. Call {@code SkillsApi.resetTree} first if refund bookkeeping
     * should run — the rebirth transaction does, keeping both paths exercised.
     */
    public static void resetSkillProgression(ServerPlayer player) {
        SkillsApi.resetAllProgression(player);
    }
}
