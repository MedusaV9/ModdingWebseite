package dev.projecteclipse.eclipse.xboxevent;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;

/**
 * Optional bridge to the music wave's server-facing cue API. The music classes are absent
 * in partial-wave builds, so this hook resolves them once by reflection and otherwise
 * remains a silent no-op.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class XboxMusicHook {
    private static final String MUSIC_CUES_CLASS =
            "dev.projecteclipse.eclipse.music.MusicCues";
    private static final String NOSTALGIA_CUE = "xbox_nostalgia";
    private static final Bridge BRIDGE = resolveBridge();
    private static final AtomicBoolean INVOCATION_FAILURE_LOGGED = new AtomicBoolean();

    private XboxMusicHook() {}

    @SubscribeEvent
    public static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        boolean leftXbox = XboxDimensions.isXboxDimension(event.getFrom());
        boolean enteredXbox = XboxDimensions.isXboxDimension(event.getTo());
        if (!leftXbox && enteredXbox) {
            BRIDGE.play(player);
        } else if (leftXbox && !enteredXbox) {
            BRIDGE.stop(player);
        }
    }

    /** Relogging into a still-open tutorial world has no dimension-change event. */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        String worldId = XboxDimensions.worldIdOf(player.level().dimension());
        if (worldId == null) {
            return;
        }
        XboxEventState state = XboxEventState.get(player.server);
        if (state.phase() == XboxEventState.Phase.OPEN && state.worldId().equals(worldId)) {
            BRIDGE.play(player);
        }
    }

    private interface Bridge {
        void play(ServerPlayer player);

        void stop(ServerPlayer player);
    }

    private static Bridge resolveBridge() {
        try {
            Class<?> musicCues = Class.forName(
                    MUSIC_CUES_CLASS, false, XboxMusicHook.class.getClassLoader());
            Method play = findStaticMethod(musicCues, "play", String.class, ServerPlayer.class);
            Method stopWithCue = findStaticMethod(musicCues, "stop", String.class, ServerPlayer.class);
            Method stopPlayer = findStaticMethod(musicCues, "stop", ServerPlayer.class);
            if (play == null || (stopWithCue == null && stopPlayer == null)) {
                EclipseMod.LOGGER.warn(
                        "{} is present but lacks play(String, player) or stop([String,] player); "
                                + "Xbox nostalgia music is disabled",
                        MUSIC_CUES_CLASS);
                return noOpBridge();
            }
            return new ReflectiveBridge(play, stopWithCue, stopPlayer);
        } catch (ClassNotFoundException | LinkageError ignored) {
            return noOpBridge();
        }
    }

    @Nullable
    private static Method findStaticMethod(Class<?> owner, String name, Class<?>... argumentTypes) {
        for (Method method : owner.getMethods()) {
            if (!method.getName().equals(name)
                    || !Modifier.isStatic(method.getModifiers())
                    || method.getParameterCount() != argumentTypes.length) {
                continue;
            }
            Class<?>[] parameters = method.getParameterTypes();
            boolean compatible = true;
            for (int i = 0; i < parameters.length; i++) {
                if (!parameters[i].isAssignableFrom(argumentTypes[i])) {
                    compatible = false;
                    break;
                }
            }
            if (compatible) {
                return method;
            }
        }
        return null;
    }

    private record ReflectiveBridge(
            Method playMethod,
            @Nullable Method stopWithCueMethod,
            @Nullable Method stopPlayerMethod) implements Bridge {

        @Override
        public void play(ServerPlayer player) {
            invoke(playMethod, NOSTALGIA_CUE, player);
        }

        @Override
        public void stop(ServerPlayer player) {
            if (stopWithCueMethod != null) {
                invoke(stopWithCueMethod, NOSTALGIA_CUE, player);
            } else if (stopPlayerMethod != null) {
                invoke(stopPlayerMethod, player);
            }
        }
    }

    private static void invoke(Method method, Object... arguments) {
        try {
            method.invoke(null, arguments);
        } catch (IllegalAccessException | InvocationTargetException | LinkageError e) {
            if (INVOCATION_FAILURE_LOGGED.compareAndSet(false, true)) {
                EclipseMod.LOGGER.warn("Xbox nostalgia music bridge failed; disabling further warnings", e);
            }
        }
    }

    private static Bridge noOpBridge() {
        return new Bridge() {
            @Override
            public void play(ServerPlayer player) {}

            @Override
            public void stop(ServerPlayer player) {}
        };
    }
}
