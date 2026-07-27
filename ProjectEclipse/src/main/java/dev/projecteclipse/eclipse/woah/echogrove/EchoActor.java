package dev.projecteclipse.eclipse.woah.echogrove;

/**
 * WOAH-05 shared contract of the two scene-actor ghosts ({@link EchoGhostEntity},
 * {@link EchoGhostWolfEntity}) — the scene player ({@code EchoSceneService}) drives
 * both through this interface and the renderers read the same synced values back.
 *
 * <p>All state is synched entity data on the implementing entity; the ACTION byte
 * uses the keyframe vocabulary below (plan §3.1/§3.3). Movement is NOT part of the
 * contract — the scene player calls {@code setPos}/{@code setYRot} directly and
 * {@code LivingEntityRenderer} derives limb swing from the position delta.</p>
 */
public interface EchoActor {
    byte ACTION_IDLE = 0;
    byte ACTION_WALK = 1;
    byte ACTION_RUN = 2;
    byte ACTION_SWING = 3;
    byte ACTION_SIT = 4;
    byte ACTION_JUMP = 5;
    byte ACTION_WAVE = 6;
    byte ACTION_THROW = 7;

    /** Fade window length (ticks) used for actor spawn/despawn and one-shot playback. */
    int FADE_TICKS = 30;

    byte echoAction();

    void setEchoAction(byte action);

    /** 0..{@value #FADE_TICKS}; renderer maps to alpha 0 → base (plan §3.1). */
    int echoFade();

    void setEchoFade(int ticks);

    /** 0..1 flood/finale brightness boost (server-set, plan §3.5). */
    float echoGlow();

    void setEchoGlow(float glow);

    /** Parses a keyframe {@code action} string ({@code "run"}, {@code "sit"}, …). */
    static byte parseAction(String name) {
        return switch (name == null ? "idle" : name.toLowerCase(java.util.Locale.ROOT)) {
            case "walk" -> ACTION_WALK;
            case "run" -> ACTION_RUN;
            case "swing" -> ACTION_SWING;
            case "sit" -> ACTION_SIT;
            case "jump" -> ACTION_JUMP;
            case "wave" -> ACTION_WAVE;
            case "throw" -> ACTION_THROW;
            default -> ACTION_IDLE;
        };
    }
}
