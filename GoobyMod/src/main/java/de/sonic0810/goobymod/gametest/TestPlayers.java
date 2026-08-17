package de.sonic0810.goobymod.gametest;

import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;

/** Single lifecycle wrapper for NeoForge's embedded GameTest player. */
final class TestPlayers {
    private TestPlayers() {
    }

    @SuppressWarnings("removal")
    static ServerPlayer create(GameTestHelper helper) {
        return helper.makeMockServerPlayerInLevel();
    }

    static ServerPlayer create(GameTestHelper helper, Vec3 relativePos) {
        ServerPlayer player = create(helper);
        Vec3 absolute = helper.absoluteVec(relativePos);
        player.moveTo(absolute.x, absolute.y, absolute.z, 0.0F, 0.0F);
        return player;
    }

    static void remove(GameTestHelper helper, ServerPlayer player) {
        helper.getLevel().getServer().getPlayerList().remove(player);
    }
}
