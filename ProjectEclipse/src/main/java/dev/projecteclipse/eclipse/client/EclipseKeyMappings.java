package dev.projecteclipse.eclipse.client;

import com.mojang.blaze3d.platform.InputConstants;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.KeyMapping;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import net.neoforged.neoforge.client.settings.KeyConflictContext;
import org.lwjgl.glfw.GLFW;

/** Client keybind registration (mod bus, client only). */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseKeyMappings {
    /** Opens the artifact menu; default J. Polled in {@link ArtifactKeyHandler}. */
    public static final KeyMapping OPEN_MENU = new KeyMapping(
            "key.eclipse.menu", KeyConflictContext.IN_GAME,
            InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_J, "key.categories.eclipse");

    private EclipseKeyMappings() {}

    @SubscribeEvent
    static void onRegisterKeyMappings(RegisterKeyMappingsEvent event) {
        event.register(OPEN_MENU);
    }
}
