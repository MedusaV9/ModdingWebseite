package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;

/**
 * F-076 facade: fires a one-shot animation on the altar's GeckoLib model from ANY
 * server system without touching the ritual internals. The altar position comes from
 * {@link EclipseWorldState#getSanctumAltarPos()} (the one altar contract every consumer
 * keys off); the trigger rides GeckoLib's own block-entity trigger network path, so
 * there is no new payload and nothing to sync by hand — every client tracking the
 * altar's chunk plays the one-shot, then the controller falls back into {@code idle}.
 *
 * <p>Sanctioned animation names (constants on {@link AltarBlockEntity}):</p>
 * <ul>
 *   <li>{@link AltarBlockEntity#ANIM_HEARTBEAT} — strong single pulse. Already fired
 *       internally on every accepted payment (milestone deposit, shard banking,
 *       accepted offering); fire it for other "the altar noticed" beats.</li>
 *   <li>{@link AltarBlockEntity#ANIM_GIFT} — the altar "hands out": rings open, core
 *       lifts, light breaks free (~3.5 s). Meant for shop purchases / rewards
 *       (ALTARUI's buy flow should call this on a completed purchase).</li>
 *   <li>{@link AltarBlockEntity#ANIM_ERUPT} — the big-event quake (~6 s): rings race,
 *       core climbs high, the whole monument trembles. Meant for the End reveal and
 *       finale-grade moments.</li>
 *   <li>{@link AltarBlockEntity#ANIM_STAGE_UP} — short ascension fanfare. Already
 *       fired internally when a milestone completes.</li>
 * </ul>
 *
 * <p>Pass the OVERWORLD level — the sanctum altar lives there. A wrong dimension, an
 * unbuilt sanctum or an unloaded/replaced altar block degrades to a logged no-op
 * (returns {@code false}); the trigger is pure garnish and must never throw.</p>
 */
public final class AltarModelTriggers {
    private AltarModelTriggers() {}

    /**
     * Fires {@code animName} on the sanctum altar's model.
     *
     * @param level    the overworld (the dimension holding the sanctum altar)
     * @param animName one of the {@code AltarBlockEntity.ANIM_*} names
     * @return {@code true} iff an altar block entity was found and the trigger fired
     */
    public static boolean trigger(ServerLevel level, String animName) {
        BlockPos pos = EclipseWorldState.get(level.getServer()).getSanctumAltarPos();
        if (pos == null || !level.isLoaded(pos)) {
            return false; // sanctum not built yet, or the altar chunk is unloaded
        }
        if (!(level.getBlockEntity(pos) instanceof AltarBlockEntity altar)) {
            EclipseMod.LOGGER.debug("AltarModelTriggers.trigger({}): no altar BE at {}", animName, pos);
            return false;
        }
        altar.triggerAnim(AltarBlockEntity.CONTROLLER_STATE, animName);
        return true;
    }

    /** Convenience: the post-purchase "the altar gives" beat (ALTARUI wires this). */
    public static boolean gift(ServerLevel level) {
        return trigger(level, AltarBlockEntity.ANIM_GIFT);
    }

    /** Convenience: the big-event eruption (End reveal / finale beats). */
    public static boolean erupt(ServerLevel level) {
        return trigger(level, AltarBlockEntity.ANIM_ERUPT);
    }

    /** Convenience: a strong single pulse for "the altar noticed" moments. */
    public static boolean heartbeat(ServerLevel level) {
        return trigger(level, AltarBlockEntity.ANIM_HEARTBEAT);
    }
}
