package dev.projecteclipse.eclipse.skills;

import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * Frozen server-side skills surface (plan §2.3 / §4). Consumers: P4-B2 quest rewards
 * ({@code addXp(player, "quest", spec.reward.skillXp)}), P4-C1 sidebar assembly
 * ({@code getLevel}/{@code getTotalXp}), P5 command polish ({@code xp add|set},
 * {@code setSecretMultiplier}, {@code resetTree}).
 *
 * <p>Secret multipliers are persisted per player, applied inside the XP pipeline, NEVER
 * synced to any client (the wire flag is hard-false) and never logged above DEBUG.</p>
 */
public final class SkillsApi {
    private SkillsApi() {}

    /**
     * Grants action XP through the full pipeline (source scale → S2 → buff → secret
     * multiplier → remainder → daily cap → level-ups). Source keys are the
     * {@code SkillService.SOURCE_*} constants; unknown keys behave like an uncapped,
     * unscaled source.
     *
     * @return whole XP points actually applied
     */
    public static int addXp(ServerPlayer player, String sourceKey, float baseAmount) {
        return SkillService.addXp(player, sourceKey, baseAmount);
    }

    /** Admin grant (no source scaling beyond the shared chain; capped only by "admin" if configured). */
    public static int addXp(ServerPlayer player, float baseAmount) {
        return SkillService.addXp(player, SkillService.SOURCE_ADMIN, baseAmount);
    }

    /** Hard-sets lifetime XP (admin). Level-up rewards trigger only for newly reached levels. */
    public static void setTotalXp(ServerPlayer player, long totalXp) {
        SkillState state = SkillState.get(player.server);
        SkillState.Entry entry = state.entry(player.getUUID());
        entry.totalXp = Math.max(0L, totalXp);
        entry.xpRemainder = 0.0F;
        state.setDirty();
        SkillService.runLevelSweepAndSync(player);
    }

    /** Level derived from lifetime XP (offline players included; 0 when unknown). */
    public static int getLevel(MinecraftServer server, UUID uuid) {
        return SkillCurve.levelForXp(getTotalXp(server, uuid), SkillConfig.get().curve());
    }

    public static long getTotalXp(MinecraftServer server, UUID uuid) {
        return SkillState.get(server).entry(uuid).totalXp;
    }

    public static int getUnspentPoints(MinecraftServer server, UUID uuid) {
        return SkillState.get(server).entry(uuid).unspentPoints();
    }

    /** Grants free tree points (dev/reward surface) without touching level tracking. */
    public static void addPoints(ServerPlayer player, int points) {
        SkillState state = SkillState.get(player.server);
        SkillState.Entry entry = state.entry(player.getUUID());
        entry.bonusPoints = Math.max(0, entry.bonusPoints + points);
        state.setDirty();
        SkillService.syncTo(player);
    }

    /** Clears the tree and refunds every spent point (P5 dev command). */
    public static void resetTree(ServerPlayer player) {
        SkillState state = SkillState.get(player.server);
        SkillState.Entry entry = state.entry(player.getUUID());
        int refund = SkillTree.totalCost(SkillTreeConfig.get().nodes(), entry.ownedNodes);
        entry.spentPoints = Math.max(0, entry.spentPoints - refund);
        entry.ownedNodes.clear();
        state.setDirty();
        SkillService.syncTo(player);
    }

    /**
     * Sets the hidden per-player XP multiplier (P5 surfaces the command). Persisted in
     * {@code eclipse_skills}; clamped to {@code [0, 100]}. DEBUG-level log only — this must
     * never appear in info logs, payloads or command broadcasts.
     */
    public static void setSecretMultiplier(MinecraftServer server, UUID uuid, float factor) {
        SkillState state = SkillState.get(server);
        SkillState.Entry entry = state.entry(uuid);
        entry.secretMultiplier = Math.clamp(factor, 0.0F, 100.0F);
        state.setDirty();
        EclipseMod.LOGGER.debug("Skill secret multiplier for {} set to {}", uuid, entry.secretMultiplier);
    }

    public static float getSecretMultiplier(MinecraftServer server, UUID uuid) {
        return SkillState.get(server).entry(uuid).secretMultiplier;
    }

    /** Chat proc-line opt-out toggle ({@code /skills procmsg on|off}). */
    public static void setProcMessagesEnabled(ServerPlayer player, boolean enabled) {
        SkillState state = SkillState.get(player.server);
        state.entry(player.getUUID()).procMsgEnabled = enabled;
        state.setDirty();
        SkillService.syncTo(player);
    }

    public static boolean isProcMessagesEnabled(MinecraftServer server, UUID uuid) {
        return SkillState.get(server).entry(uuid).procMsgEnabled;
    }

    /** Immediate skill-state payload resync (login sync, GUI refresh hooks). */
    public static void syncTo(ServerPlayer player) {
        SkillService.syncTo(player);
    }
}
