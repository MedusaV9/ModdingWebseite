package dev.projecteclipse.eclipse.limbo;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.LevelTickEvent;

/**
 * Spawns and animates the ghost ship's eight block-display oars (stripped dark oak logs)
 * along the hull. Every {@value #SWING_PERIOD_TICKS} ticks the server pushes a new
 * transformation (rotation about Z between ±{@value #SWING_DEGREES}°, mirrored per side)
 * with a matching interpolation duration so clients tween smoothly.
 *
 * <p>Oar entity UUIDs are persisted in {@link EclipseWorldState#getOarEntities()}; on
 * restart existing entities are re-attached by UUID instead of spawning duplicates.
 * The Display transformation setters are opened via {@code accesstransformer.cfg}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class OarAnimator {
    public static final int OAR_COUNT = 8;
    public static final int SWING_PERIOD_TICKS = 30;
    public static final float SWING_DEGREES = 25.0F;
    /** X offsets of the four oar pairs along the hull. */
    private static final int[] OAR_X = {-12, -4, 4, 12};

    private static final Vector3f OAR_SCALE = new Vector3f(0.25F, 3.0F, 0.25F);
    /** Centers the scaled shaft on the entity position so it pivots around its middle. */
    private static final Vector3f OAR_OFFSET = new Vector3f(-0.125F, -1.5F, -0.125F);

    /** While true (start-event cutscene), the rowing loop is suspended. */
    private static volatile boolean tiltMode = false;

    private OarAnimator() {}

    /**
     * Spawns the oars once (when no UUIDs are stored yet) and persists their UUIDs.
     * When UUIDs already exist this is a no-op; the tick loop re-attaches by UUID.
     */
    public static void ensureOars(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        if (!state.getOarEntities().isEmpty()) {
            EclipseMod.LOGGER.info("Re-attached to {} persisted ghost ship oars", state.getOarEntities().size());
            return;
        }
        int waterline = GhostShipBuilder.waterlineY(limbo);
        List<UUID> ids = new ArrayList<>(OAR_COUNT);
        for (int side = -1; side <= 1; side += 2) {
            for (int x : OAR_X) {
                double oz = side * (GhostShipBuilder.halfWidthAt(x) + 1.5);
                Display.BlockDisplay oar = EntityType.BLOCK_DISPLAY.create(limbo);
                if (oar == null) {
                    EclipseMod.LOGGER.error("Failed to create block_display oar at x={} side={}", x, side);
                    continue;
                }
                oar.moveTo(x + 0.5, waterline + 2.0, oz, 0.0F, 0.0F);
                oar.setBlockState(Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState());
                oar.setTransformation(oarTransformation(0.0F));
                limbo.addFreshEntity(oar);
                ids.add(oar.getUUID());
            }
        }
        state.setOarEntities(ids);
        EclipseMod.LOGGER.info("Spawned {} ghost ship oars in {}", ids.size(), LimboDimension.LIMBO.location());
    }

    @SubscribeEvent
    public static void onLevelTick(LevelTickEvent.Post event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !level.dimension().equals(LimboDimension.LIMBO)) {
            return;
        }
        if (tiltMode || level.getGameTime() % SWING_PERIOD_TICKS != 0 || level.players().isEmpty()) {
            return;
        }
        // Alternate stroke direction each period; port and starboard mirror each other.
        boolean forward = (level.getGameTime() / SWING_PERIOD_TICKS) % 2 == 0;
        List<UUID> ids = EclipseWorldState.get(level.getServer()).getOarEntities();
        for (int i = 0; i < ids.size(); i++) {
            Display.BlockDisplay oar = resolve(level, ids.get(i));
            if (oar == null) {
                continue;
            }
            int sideSign = i < ids.size() / 2 ? -1 : 1;
            float angle = (forward ? SWING_DEGREES : -SWING_DEGREES) * sideSign;
            applyInterpolated(oar, oarTransformation(angle), SWING_PERIOD_TICKS);
        }
    }

    /**
     * Cutscene hook: suspends rowing and slowly keels every oar over (rotation about Z,
     * interpolated over {@code durationTicks}) so the whole ship reads as tilting.
     */
    public static void beginTilt(ServerLevel limbo, int durationTicks) {
        tiltMode = true;
        int resolved = 0;
        for (UUID id : EclipseWorldState.get(limbo.getServer()).getOarEntities()) {
            Display.BlockDisplay oar = resolve(limbo, id);
            if (oar != null) {
                applyInterpolated(oar, oarTransformation(70.0F), durationTicks);
                resolved++;
            }
        }
        EclipseMod.LOGGER.info("start_event tilt: keeled over {} oar displays ({} ticks)", resolved, durationTicks);
    }

    /** Ends the cutscene tilt; the regular rowing loop resumes on its next period. */
    public static void endTilt() {
        tiltMode = false;
    }

    private static Display.BlockDisplay resolve(ServerLevel level, UUID id) {
        Entity entity = level.getEntity(id);
        return entity instanceof Display.BlockDisplay oar ? oar : null;
    }

    private static void applyInterpolated(Display.BlockDisplay oar, Transformation transformation, int durationTicks) {
        oar.setTransformationInterpolationDelay(0);
        oar.setTransformationInterpolationDuration(durationTicks);
        oar.setTransformation(transformation);
    }

    private static Transformation oarTransformation(float zRotationDegrees) {
        Quaternionf rotation = new Quaternionf().rotationZ((float) Math.toRadians(zRotationDegrees));
        // Rotate the centering offset too so the shaft pivots around the entity position.
        Vector3f translation = new Vector3f(OAR_OFFSET).rotate(rotation);
        return new Transformation(translation, rotation, new Vector3f(OAR_SCALE), new Quaternionf());
    }
}
