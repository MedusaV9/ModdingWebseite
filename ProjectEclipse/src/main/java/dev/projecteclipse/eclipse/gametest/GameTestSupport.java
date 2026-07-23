package dev.projecteclipse.eclipse.gametest;

import java.util.Objects;
import java.util.UUID;

import com.mojang.serialization.Codec;
import com.mojang.serialization.DynamicOps;
import com.mojang.serialization.JsonOps;

import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.GameType;

/**
 * Shared helpers for Eclipse NeoForge gametests (P4-A1 scaffolding). Wave-B packages import
 * these utilities instead of duplicating mock-player and day-set boilerplate.
 */
public final class GameTestSupport {
    /** Structure template id for empty 1×1×1 scenes. */
    public static final String EMPTY_TEMPLATE = "gametest.empty";

    private GameTestSupport() {}

    /** Spawns a real mock {@link ServerPlayer} at the structure origin in the requested mode. */
    @SuppressWarnings("removal")
    public static ServerPlayer mockServerPlayer(GameTestHelper helper, GameType gameType) {
        ServerPlayer player = helper.makeMockServerPlayerInLevel();
        helper.assertTrue(player != null, "mock server player");
        player.setGameMode(gameType);
        return player;
    }

    /** Spawns a survival mock server player at the structure origin. */
    public static ServerPlayer mockSurvivalPlayer(GameTestHelper helper) {
        return mockServerPlayer(helper, GameType.SURVIVAL);
    }

    /**
     * Sets the event day through the authoritative scheduler (persists + broadcasts). Safe in
     * gametests because it uses the same path as admin commands.
     */
    public static void setEventDay(MinecraftServer server, int day) {
        DayScheduler.setDay(server, day);
    }

    /**
     * Encodes then decodes a payload with its {@link StreamCodec} and asserts value equality.
     *
     * @throws GameTestHelper.GameTestAssertException when round-trip data differs
     */
    public static <T> void assertPayloadRoundTrip(StreamCodec<ByteBuf, T> codec, T original) {
        ByteBuf buf = Unpooled.buffer();
        codec.encode(buf, original);
        ByteBuf copy = buf.copy();
        buf.release();
        T decoded = codec.decode(copy);
        copy.release();
        if (!Objects.equals(original, decoded)) {
            throw new AssertionError("Payload round-trip mismatch: " + original + " != " + decoded);
        }
    }

    /**
     * JSON ops round-trip for attachment / SavedData codecs (e.g. {@code PlacedBlockData}).
     */
    public static <T> void assertCodecRoundTrip(Codec<T> codec, T original) {
        DynamicOps<com.google.gson.JsonElement> ops = JsonOps.INSTANCE;
        var encoded = codec.encodeStart(ops, original);
        if (encoded.isError()) {
            throw new AssertionError("Encode failed: " + encoded.error());
        }
        var decoded = codec.parse(ops, encoded.getOrThrow());
        if (decoded.isError()) {
            throw new AssertionError("Decode failed: " + decoded.error());
        }
        T result = decoded.getOrThrow();
        if (!Objects.equals(original, result)) {
            throw new AssertionError("Codec round-trip mismatch: " + original + " != " + result);
        }
    }

    /** Registers a temporary death listener and returns its idempotent removal handle. */
    public static Runnable registerPlayerDeathCounter(java.util.concurrent.atomic.AtomicInteger counter) {
        return EclipseSignals.onPlayerDeath((victim, killer) -> counter.incrementAndGet());
    }

    /** Stable UUID for gametest assertions. */
    public static UUID testUuid(int seed) {
        return new UUID(0xE000000000000000L | (seed & 0xFFFFL), seed);
    }
}
