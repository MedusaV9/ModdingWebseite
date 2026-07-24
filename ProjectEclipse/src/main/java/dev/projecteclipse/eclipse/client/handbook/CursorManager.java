package dev.projecteclipse.eclipse.client.handbook;

import java.io.InputStream;
import java.nio.ByteBuffer;
import java.util.EnumMap;
import java.util.Map;

import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterClientReloadListenersEvent;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWImage;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;

/**
 * GLFW mouse-cursor lifecycle for Eclipse screens ({@code docs/ideas/03_ui_ux.md} §A
 * "Cursors" — there is no vanilla API). Themed 32x32 cursors are loaded from
 * {@code textures/gui/cursor/{arrow,hand,grab}.png} (hotspots (0,0)/(8,0)/(16,16)) via
 * {@link NativeImage} → {@link GLFW#glfwCreateCursor}; when that fails the guarded
 * fallback is {@link GLFW#glfwCreateStandardCursor} (0 → skip, system default stays).
 *
 * <p>Lifecycle rules (risk R12 in {@code docs/PLAN_V2.md}):
 * <ul>
 *   <li>pointers are created lazily, CACHED, and applied only on hover-state change;</li>
 *   <li>screens MUST call {@link #reset()} from {@code Screen#removed()} —
 *       {@code glfwSetCursor(handle, MemoryUtil.NULL)} — so the system cursor always
 *       returns, whatever screen comes next;</li>
 *   <li>all GLFW calls run on the render thread only (guarded);</li>
 *   <li>cached cursors are destroyed + recreated on resource reload (F3+T), registered via
 *       {@link RegisterClientReloadListenersEvent} below;</li>
 *   <li>{@code customCursor=false} disables the whole feature (any applied cursor is
 *       reset on the next frame).</li>
 * </ul>
 *
 * <p>Per-frame use: widgets/tabs call {@link #requestPointer()} / {@link #requestGrab()}
 * while rendering; the owning screen calls {@link #endFrame()} once per frame, which
 * applies the strongest request (GRAB &gt; POINTER &gt; ARROW) and clears the flags. W15's
 * menu/settings screens reuse this by following the same request/endFrame/reset pattern.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CursorManager {
    /** The three cursor shapes of the Eclipse UI. */
    public enum Cursor {
        ARROW("arrow", 0, 0, GLFW.GLFW_ARROW_CURSOR),
        POINTER("hand", 8, 0, GLFW.GLFW_POINTING_HAND_CURSOR),
        GRAB("grab", 16, 16, GLFW.GLFW_RESIZE_ALL_CURSOR);

        final String texture;
        final int hotX;
        final int hotY;
        final int standardShape;

        Cursor(String texture, int hotX, int hotY, int standardShape) {
            this.texture = texture;
            this.hotX = hotX;
            this.hotY = hotY;
            this.standardShape = standardShape;
        }
    }

    /** Lazily created GLFW cursor pointers; 0 = creation failed, don't retry until reload. */
    private static final Map<Cursor, Long> CACHE = new EnumMap<>(Cursor.class);
    /** The cursor currently applied to the window; null = system default (NULL applied). */
    private static Cursor applied;
    private static boolean pointerRequested;
    private static boolean grabRequested;

    private CursorManager() {}

    /** An interactive element is hovered this frame → pointing hand. */
    public static void requestPointer() {
        pointerRequested = true;
    }

    /** A drag (timeline spine) is active this frame → grab fist. */
    public static void requestGrab() {
        grabRequested = true;
    }

    /**
     * Applies the strongest cursor request of the frame and clears the flags. Call once
     * per frame at the end of the screen's render. No-ops (and resets any themed cursor)
     * when {@code customCursor} is off.
     */
    public static void endFrame() {
        boolean grab = grabRequested;
        boolean pointer = pointerRequested;
        grabRequested = false;
        pointerRequested = false;
        if (!RenderSystem.isOnRenderThread()) {
            return;
        }
        if (!EclipseClientConfig.customCursor()) {
            if (applied != null) {
                reset();
            }
            return;
        }
        apply(grab ? Cursor.GRAB : pointer ? Cursor.POINTER : Cursor.ARROW);
    }

    /**
     * Returns the window to the system default cursor
     * ({@code glfwSetCursor(handle, MemoryUtil.NULL)}). MUST be called from
     * {@code Screen#removed()} of every screen that uses this manager.
     */
    public static void reset() {
        if (!RenderSystem.isOnRenderThread()) {
            return;
        }
        try {
            GLFW.glfwSetCursor(windowHandle(), MemoryUtil.NULL);
        } catch (Throwable throwable) {
            EclipseMod.LOGGER.warn("Failed to reset GLFW cursor", throwable);
        }
        applied = null;
        pointerRequested = false;
        grabRequested = false;
    }

    /** Swap only on change; a failed pointer (0) leaves the system cursor untouched. */
    private static void apply(Cursor cursor) {
        if (cursor == applied) {
            return;
        }
        long pointer = CACHE.computeIfAbsent(cursor, CursorManager::create);
        try {
            // ARROW falls back to the system default when themed creation failed (NULL is
            // the default arrow anyway); other failed shapes keep whatever is applied.
            if (pointer == MemoryUtil.NULL && cursor != Cursor.ARROW) {
                return;
            }
            GLFW.glfwSetCursor(windowHandle(), pointer);
            applied = cursor;
        } catch (Throwable throwable) {
            EclipseMod.LOGGER.warn("Failed to apply GLFW cursor {}", cursor, throwable);
        }
    }

    /** Themed PNG first, guarded standard-cursor fallback second; 0 = give up until reload. */
    private static long create(Cursor cursor) {
        long themed = createThemed(cursor);
        if (themed != MemoryUtil.NULL) {
            return themed;
        }
        try {
            long standard = GLFW.glfwCreateStandardCursor(cursor.standardShape);
            if (standard == MemoryUtil.NULL) {
                EclipseMod.LOGGER.warn("glfwCreateStandardCursor({}) returned 0 — keeping system cursor", cursor);
            }
            return standard;
        } catch (Throwable throwable) {
            EclipseMod.LOGGER.warn("glfwCreateStandardCursor({}) failed", cursor, throwable);
            return MemoryUtil.NULL;
        }
    }

    /** PNG → NativeImage → tightly-packed RGBA buffer → glfwCreateCursor. */
    private static long createThemed(Cursor cursor) {
        ResourceLocation location = ResourceLocation.fromNamespaceAndPath(
                EclipseMod.MOD_ID, "textures/gui/cursor/" + cursor.texture + ".png");
        try (InputStream stream = Minecraft.getInstance().getResourceManager().open(location);
                NativeImage image = NativeImage.read(stream)) {
            int width = image.getWidth();
            int height = image.getHeight();
            ByteBuffer pixels = MemoryUtil.memAlloc(width * height * 4);
            try {
                for (int pixelY = 0; pixelY < height; pixelY++) {
                    for (int pixelX = 0; pixelX < width; pixelX++) {
                        int abgr = image.getPixelRGBA(pixelX, pixelY); // memory order R,G,B,A
                        pixels.put((byte) (abgr & 0xFF));
                        pixels.put((byte) (abgr >> 8 & 0xFF));
                        pixels.put((byte) (abgr >> 16 & 0xFF));
                        pixels.put((byte) (abgr >> 24 & 0xFF));
                    }
                }
                pixels.flip();
                try (MemoryStack stack = MemoryStack.stackPush()) {
                    GLFWImage glfwImage = GLFWImage.malloc(stack);
                    glfwImage.set(width, height, pixels);
                    return GLFW.glfwCreateCursor(glfwImage, cursor.hotX, cursor.hotY);
                }
            } finally {
                MemoryUtil.memFree(pixels);
            }
        } catch (Throwable throwable) {
            EclipseMod.LOGGER.warn("Failed to create themed cursor {} from {}", cursor, location, throwable);
            return MemoryUtil.NULL;
        }
    }

    /** Reload hook: reset to system default, destroy every cached pointer, recreate lazily. */
    private static void destroyAll() {
        reset();
        for (Map.Entry<Cursor, Long> entry : CACHE.entrySet()) {
            if (entry.getValue() != MemoryUtil.NULL) {
                try {
                    GLFW.glfwDestroyCursor(entry.getValue());
                } catch (Throwable throwable) {
                    EclipseMod.LOGGER.warn("Failed to destroy GLFW cursor {}", entry.getKey(), throwable);
                }
            }
        }
        CACHE.clear();
    }

    private static long windowHandle() {
        return Minecraft.getInstance().getWindow().getWindow();
    }

    /**
     * Resource reload (F3+T / pack change) invalidates the themed textures: destroy the
     * GLFW cursors and let the next {@link #endFrame()} recreate them from the fresh
     * resources. The apply phase of a client reload runs on the render thread.
     */
    @SubscribeEvent
    static void onRegisterReloadListeners(RegisterClientReloadListenersEvent event) {
        event.registerReloadListener((net.minecraft.server.packs.resources.ResourceManagerReloadListener)
                manager -> destroyAll());
    }
}
