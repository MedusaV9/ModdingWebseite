package dev.projecteclipse.eclipse.client.skills;

import com.mojang.blaze3d.platform.InputConstants;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import net.neoforged.neoforge.client.settings.KeyConflictContext;
import org.lwjgl.glfw.GLFW;

/**
 * The skill tree keybind (WB-SKILLS): default <b>K</b> in the existing "Project Eclipse"
 * category ({@code key.categories.eclipse}, shared with the J handbook binding). K is
 * unbound in vanilla 1.21.1, so the default ships conflict-free; {@link KeyConflictContext#IN_GAME}
 * keeps it from fighting GUI keys.
 *
 * <p>Self-registering ({@code EclipseKeyMappings} is frozen this wave): mod-bus
 * {@link RegisterKeyMappingsEvent} for the mapping, game-bus {@link ClientTickEvent.Post}
 * for the {@code consumeClick()} poll — the exact {@code ArtifactKeyHandler} pattern,
 * covering keyboard AND mouse bindings. No server round-trip is needed to open: the tree
 * and skill state live in {@code ClientStateCache} (synced at login and on every change),
 * so the screen renders instantly from cache. Closing with the same binding is handled
 * inside {@code SkillTreeScreen} (B8 parity), because this IN_GAME mapping never fires
 * while a screen is open.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SkillKeybind {
    /** Opens {@link SkillTreeScreen}; default K, category "Project Eclipse". */
    public static final KeyMapping OPEN_SKILLS = new KeyMapping(
            "key.eclipse.skills", KeyConflictContext.IN_GAME,
            InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_K, "key.categories.eclipse");

    private SkillKeybind() {}

    /**
     * Mapping registration, split into a nested subscriber like
     * {@code ClientStateCache.DisconnectReset}: {@code RegisterKeyMappingsEvent} is a MOD-bus
     * event while the outer class polls on the game bus — FML routes each
     * {@code @EventBusSubscriber} class by its methods' event types, and the codebase keeps
     * the two kinds in separate classes ({@code EclipseKeyMappings} vs
     * {@code ArtifactKeyHandler} precedent).
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterKeyMappings(RegisterKeyMappingsEvent event) {
            event.register(OPEN_SKILLS);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        while (OPEN_SKILLS.consumeClick()) {
            if (minecraft.player != null && minecraft.screen == null) {
                minecraft.setScreen(new SkillTreeScreen());
            }
        }
    }
}
