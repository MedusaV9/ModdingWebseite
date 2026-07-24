package dev.projecteclipse.eclipse.skills;

import java.util.Set;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.minigames.MinigameDimensions;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;

/**
 * D2 XP pacing gates: ACTION skill XP is OFF before the start event and OFF inside every
 * non-progression "event dimension" (limbo, the minigame arenas, the xbox/glitch worlds —
 * the user's "backrooms"). Explicit REWARD sources ({@link #EXEMPT_SOURCES}) always pay:
 * quests completed at the altar must keep paying even while an action gate is closed.
 *
 * <p>Minigame payout source keys are deliberately NOT exempt — per the v5 feedback
 * ("XP OFF in minigames") they are gated by the dimension check like any action lane.</p>
 *
 * <p>Both gates are config toggles in {@code skills.json} ({@code "gates": { "preEvent",
 * "eventDimensions" }}) so ops can re-enable XP for tests via {@code /eclipse reload}.</p>
 */
public final class XpGates {
    /**
     * Reward-style sources that bypass both gates. {@code collection} and {@code contract}
     * are reserved for the D1/D3 systems so their rewards stay exempt from day one.
     */
    private static final Set<String> EXEMPT_SOURCES = Set.of(
            SkillService.SOURCE_QUEST,
            SkillService.SOURCE_ALTAR,
            SkillService.SOURCE_ADVANCEMENT,
            SkillService.SOURCE_DEATH,
            SkillService.SOURCE_ADMIN,
            "collection",
            "contract");

    private XpGates() {}

    /** Whether a positive grant from {@code source} may pay out for this player right now. */
    public static boolean allows(ServerPlayer player, String source) {
        return isExemptSource(source) || actionXpAllowed(player);
    }

    /** Reward sources (quest/altar/advancement/death/admin/collection/contract) skip the gates. */
    public static boolean isExemptSource(String source) {
        return EXEMPT_SOURCES.contains(source);
    }

    /**
     * Single action-XP predicate: {@code false} while the start event has not completed
     * (pre-event lobby grind must not level anyone) and {@code false} inside any event
     * dimension. Each clause is individually toggleable in {@code skills.json}.
     */
    public static boolean actionXpAllowed(ServerPlayer player) {
        SkillConfig.Data cfg = SkillConfig.get();
        if (cfg.gatePreEvent() && !EclipseWorldState.get(player.server).isStartEventDone()) {
            return false;
        }
        if (cfg.gateEventDimensions() && isEventDimension(player.level().dimension())) {
            return false;
        }
        return true;
    }

    /** Limbo, minigame arenas ({@code minigame_arena}/{@code minigame_sky}) and xbox worlds. */
    public static boolean isEventDimension(ResourceKey<Level> dimension) {
        return LimboDimension.LIMBO.equals(dimension)
                || MinigameDimensions.isMinigameDimension(dimension)
                || XboxDimensions.isXboxDimension(dimension);
    }
}
