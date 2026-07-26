package dev.projecteclipse.eclipse.scare;

import java.util.List;

/**
 * Canonical scare-script ids (F-064/F-065) — the single list shared by the
 * {@code /dev jumpscare} suggestion provider, {@link ScareService} validation and the
 * client script catalog ({@code client.scare.ScareScripts}). The names are the wire
 * contract of {@code S2CScareCuePayload}: adding a jumpscare = one entry here + one
 * script builder in {@code ScareScripts} + a {@code dev.eclipse.scare.desc.<id>} lang
 * pair (the {@code /dev jumpscare list} line).
 *
 * <p>The {@code BACKROOMS_*} ids are internal beats of the F-065 backrooms trip
 * ({@link ScareTripService}) and deliberately NOT part of {@link #JUMPSCARES} — they are
 * not directly triggerable versions, only script names the trip service sends.</p>
 */
public final class ScareIds {
    /** {@code /dev ghostscreen} — ghost overlay + glitch text + escalating FX + ONE bang. */
    public static final String GHOSTSCREEN = "ghostscreen";
    /** F-065 trip opener: the ghostscreen arc that ENDS in a sustained blackout "clip". */
    public static final String BACKROOMS_CLIP = "backrooms_clip";
    /** F-065 damage bounce / trip end: a short violent glitch burst covering the teleport. */
    public static final String BACKROOMS_RETURN = "backrooms_return";
    /** F-065 arrival sting inside the backrooms (played right after the clip teleport). */
    public static final String BACKROOMS_ARRIVE = "backrooms_arrive";

    /**
     * The 30 {@code /dev jumpscare <version>} scripts, in suggestion order. Every entry is
     * deliberately DISTINCT (overlay set, FX combination, sound design, timing archetype,
     * accent palette) — see the builder table in {@code client.scare.ScareScripts}.
     */
    public static final List<String> JUMPSCARES = List.of(
            "static_face",      // 1  instant: scanline burst + face flash + bang
            "red_maw",          // 2  instant: red invert flash + maw + ravager bang
            "whisper_turn",     // 3  slow-burn: whisper ramp, "do not turn around", face
            "false_calm",       // 4  fake calm: soft cave amb, then double-bang face
            "eye_pair",         // 5  dread-only: eyes fade in, sonar void, NO bang
            "datamosh_scream",  // 6  datamosh + ghast scream + purple accent
            "mirror_glitch",    // 7  invert flicker + "behind the glass" + glass bang
            "heartbeat_rush",   // 8  10 s accelerating heartbeat -> sonic boom
            "ceiling_gaze",     // 9  face slides down from the top edge + thunder
            "hollow_choir",     // 10 drone+whisper choir, ghost grade, bell bang
            "tv_shutdown",      // 11 CRT collapse: scanlines, closing bands, anvil bang
            "blood_static",     // 12 red static face pulses + shrieker
            "void_stare",       // 13 void grade + single centered eye + enderman scream
            "crawl_text",       // 14 text-only horror -> all lines snap to RUN + bang
            "sudden_dark",      // 15 instant blackout, approaching steps, face on relight
            "double_take",      // 16 small fake flash early, real scare after the calm
            "warden_pulse",     // 17 cyan sonar palette, sonic charge ramp + boom
            "glitch_cascade",   // 18 outline->datamosh->invert ladder + white flash bang
            "porcelain",        // 19 pale mask grows closer over 6 s + curse riser
            "backstep",        // 20 dolly-zoom FOV kick + growl, no overlay at all
            "wither_wall",      // 21 silhouette sweeps across + wither sting + thunder
            "red_rooms",        // 22 red scanlines + ballast buzz + EXIT text glitch
            "soul_leak",        // 23 soul-escape drift, two faint faces, quiet ending
            "phantom_swoop",    // 24 swoop overlay crosses the screen + bite bang
            "last_breath",      // 25 breathing dims the screen per breath -> ROAR
            "null_error",       // 26 ERROR text spam + datamosh + fake crash-to-black
            "grin_flash",       // 27 three spaced escalating face flashes + final bang
            "cold_call",        // 28 bell tolls, "it heard you", dragon growl bang
            "swarm",            // 29 photon mote swarm rushes the camera + vex chitter
            "totality");        // 30 the big one: drone, FOV crush, giant face, blackout

    private ScareIds() {}

    /** Whether {@code id} is a directly triggerable {@code /dev jumpscare} version. */
    public static boolean isJumpscare(String id) {
        return JUMPSCARES.contains(id);
    }

    /** Whether {@code id} names ANY known script (jumpscares + ghostscreen + trip beats). */
    public static boolean isKnown(String id) {
        return GHOSTSCREEN.equals(id) || BACKROOMS_CLIP.equals(id)
                || BACKROOMS_RETURN.equals(id) || BACKROOMS_ARRIVE.equals(id)
                || isJumpscare(id);
    }
}
