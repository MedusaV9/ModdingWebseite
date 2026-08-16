package de.sonic0810.goobymod.compat;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.phys.AABB;
import net.neoforged.fml.ModList;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Optional Create facade. This class has no Create imports; all typed access is
 * deferred to {@link CreateBridge} after the mod-loaded guard succeeds.
 */
public final class CreateCompat {
    public enum IntegrationLevel {
        DORMANT,
        TYPED,
        REFLECTION_FALLBACK,
        TRANSIENT,
        PERMANENT_API_MISMATCH
    }

    private static final Logger LOGGER = LoggerFactory.getLogger("goobymod/CreateCompat");
    private static final String SEAT_BLOCK_CLASS = "com.simibubi.create.content.contraptions.actors.seat.SeatBlock";
    private static final CreateRetryPolicy SEAT_RETRY = new CreateRetryPolicy();
    private static final CreateRetryPolicy QUERY_RETRY = new CreateRetryPolicy();
    private static final CreateRetryPolicy MACHINE_RETRY = new CreateRetryPolicy();
    @Nullable
    private static volatile Method sitDownMethod;
    private static volatile boolean reflectionFallback;
    private static volatile boolean diagnosticsLogged;

    public static boolean isCreateLoaded() {
        return ModList.get().isLoaded("create");
    }

    /**
     * Create's 6.0 seat lifecycle depends on networking that its dedicated
     * GameTest server cannot provide. Keep production integration version-gated
     * while making the headless test environment fail closed.
     */
    public static boolean isSeatIntegrationAvailable() {
        if (!isCreateLoaded() || Boolean.getBoolean("neoforge.gameTestServer")) {
            return false;
        }
        return ModList.get().getModContainerById("create")
                .map(container -> container.getModInfo().getVersion().toString().startsWith("6.0."))
                .orElse(false);
    }

    /** True only for a permanent API mismatch, not for absent Create or a retryable failure. */
    public static boolean isDegraded() {
        return integrationLevel() == IntegrationLevel.PERMANENT_API_MISMATCH;
    }

    public static IntegrationLevel integrationLevel() {
        if (!isCreateLoaded()) {
            return IntegrationLevel.DORMANT;
        }
        if (SEAT_RETRY.state() == CreateRetryPolicy.State.PERMANENT_API_MISMATCH
                || QUERY_RETRY.state() == CreateRetryPolicy.State.PERMANENT_API_MISMATCH
                || MACHINE_RETRY.state() == CreateRetryPolicy.State.PERMANENT_API_MISMATCH) {
            return IntegrationLevel.PERMANENT_API_MISMATCH;
        }
        if (SEAT_RETRY.state() == CreateRetryPolicy.State.TRANSIENT
                || QUERY_RETRY.state() == CreateRetryPolicy.State.TRANSIENT
                || MACHINE_RETRY.state() == CreateRetryPolicy.State.TRANSIENT) {
            return IntegrationLevel.TRANSIENT;
        }
        return reflectionFallback ? IntegrationLevel.REFLECTION_FALLBACK : IntegrationLevel.TYPED;
    }

    /** Emits exactly one startup diagnostic useful in mixed-mod bug reports. */
    public static void logDiagnostics() {
        if (diagnosticsLogged) {
            return;
        }
        diagnosticsLogged = true;
        String version = ModList.get().getModContainerById("create")
                .map(container -> container.getModInfo().getVersion().toString())
                .orElse("not detected");
        LOGGER.info("Create compatibility: version={}, integration={}", version, integrationLevel());
    }

    /**
     * Seats Gooby using the typed Create API. API drift gets one verified
     * reflection fallback; transient Create runtime errors use tick backoff.
     */
    public static synchronized boolean trySeatGooby(GoobyEntity gooby) {
        if (!isSeatIntegrationAvailable() || gooby.isPassenger()) {
            return false;
        }
        CreateRetryPolicy.State before = SEAT_RETRY.state();
        boolean seated = SEAT_RETRY.execute(gooby.level().getGameTime(), () -> {
            try {
                return CreateBridge.trySeatGooby(gooby);
            } catch (LinkageError typedMismatch) {
                boolean reflected = trySeatReflectively(gooby);
                reflectionFallback = reflected;
                return reflected;
            }
        });
        logStateChange("seat", before, SEAT_RETRY.state());
        return seated;
    }

    public static synchronized boolean isOnContraption(Entity entity) {
        if (!isCreateLoaded()) {
            return false;
        }
        return QUERY_RETRY.execute(entity.level().getGameTime(), () -> CreateBridge.isOnContraption(entity));
    }

    public static synchronized boolean isOnMovingContraption(Entity entity) {
        if (!isCreateLoaded()) {
            return false;
        }
        CreateRetryPolicy.State before = QUERY_RETRY.state();
        boolean moving = QUERY_RETRY.execute(entity.level().getGameTime(),
                () -> CreateBridge.isOnMovingContraption(entity));
        logStateChange("contraption", before, QUERY_RETRY.state());
        return moving;
    }

    public static synchronized double contraptionMotionSqr(Entity entity) {
        if (!isCreateLoaded()) {
            return 0.0;
        }
        final double[] result = {0.0};
        QUERY_RETRY.execute(entity.level().getGameTime(), () -> {
            result[0] = CreateBridge.contraptionMotionSqr(entity);
            return true;
        });
        return result[0];
    }

    public static synchronized boolean hasRunningMachineNearby(Level level, BlockPos center, int radius) {
        if (!isCreateLoaded()) {
            return false;
        }
        CreateRetryPolicy.State before = MACHINE_RETRY.state();
        boolean running = MACHINE_RETRY.execute(level.getGameTime(),
                () -> CreateBridge.hasRunningMachineNearby(level, center, radius));
        logStateChange("kinetics", before, MACHINE_RETRY.state());
        return running;
    }

    /** Bearing assembly hook used by the Create-enabled integration GameTest. */
    public static synchronized boolean tryAssembleBearing(Level level, BlockPos pos, float speed) {
        return isCreateLoaded() && QUERY_RETRY.execute(level.getGameTime(),
                () -> CreateBridge.tryAssembleBearing(level, pos, speed));
    }

    /** Contraption disassembly hook used to verify arrival transfer behavior. */
    public static synchronized boolean tryDisassembleVehicle(Entity entity) {
        return isCreateLoaded() && QUERY_RETRY.execute(entity.level().getGameTime(),
                () -> CreateBridge.tryDisassembleVehicle(entity));
    }

    private static void logStateChange(String feature, CreateRetryPolicy.State before,
            CreateRetryPolicy.State after) {
        if (before == after || after == CreateRetryPolicy.State.ACTIVE) {
            return;
        }
        if (after == CreateRetryPolicy.State.TRANSIENT) {
            LOGGER.warn("Create {} integration hit a transient error; retrying with tick backoff", feature);
        } else {
            LOGGER.warn("Create {} integration disabled: permanent API mismatch", feature);
        }
    }

    @Nullable
    private static BlockPos findNearbySeat(Level level, BlockPos center) {
        for (BlockPos pos : BlockPos.betweenClosed(center.offset(-3, -1, -3), center.offset(3, 2, 3))) {
            Block block = level.getBlockState(pos).getBlock();
            ResourceLocation id = BuiltInRegistries.BLOCK.getKey(block);
            if ("create".equals(id.getNamespace()) && id.getPath().endsWith("seat") && isSeatFree(level, pos)) {
                return pos.immutable();
            }
        }
        return null;
    }

    private static boolean isSeatFree(Level level, BlockPos pos) {
        // Reflection-only fallback for an API-drifted Create build.
        return level.getEntitiesOfClass(Entity.class, new AABB(pos), entity ->
                entity.getClass().getName().startsWith("com.simibubi.create") && entity.isVehicle()).isEmpty();
    }

    private static boolean trySeatReflectively(GoobyEntity gooby) throws ReflectiveOperationException {
        BlockPos seatPos = findNearbySeat(gooby.level(), gooby.blockPosition());
        if (seatPos == null) {
            return false;
        }
        resolveSitDown().invoke(null, gooby.level(), seatPos, gooby);
        return gooby.isPassenger();
    }

    @Nullable
    private static Method resolveSitDown() throws ReflectiveOperationException {
        Method method = sitDownMethod;
        if (method == null) {
            Class<?> seatBlockClass = Class.forName(SEAT_BLOCK_CLASS);
            method = seatBlockClass.getMethod("sitDown", Level.class, BlockPos.class, Entity.class);
            if (!Modifier.isStatic(method.getModifiers()) || method.getReturnType() != void.class) {
                throw new NoSuchMethodException("Unexpected SeatBlock.sitDown signature: " + method);
            }
            sitDownMethod = method;
        }
        return method;
    }

    private CreateCompat() {
    }
}
