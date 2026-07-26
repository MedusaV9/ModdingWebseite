package dev.projecteclipse.eclipse.client.scare;

import java.util.LinkedHashMap;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.scare.ScareIds;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;

import static dev.projecteclipse.eclipse.client.scare.ScareScript.script;

/**
 * The client script catalog of the Scare framework (F-064/F-065): one {@link ScareScript}
 * per {@link ScareIds} name, built once at class load. Adding a jumpscare = one id in
 * {@code ScareIds.JUMPSCARES} + one builder below + a {@code dev.eclipse.scare.desc.<id>}
 * lang pair — nothing else.
 *
 * <p><b>Authoring laws</b> (enforced by review, encoded in the beat model where possible):
 * flashes ≥ 3 ticks and ≥ ~2 s apart (never a strobe), at most ONE "very loud bang" per
 * script, blackouts always fade, and every script must end clean (the director hard-stops
 * at {@code durationTicks}). The 30 jumpscares deliberately span five timing archetypes —
 * instant shock, slow burn, fake calm, dread-only (no bang at all) and multi-act — and
 * distinct palettes via the GLITCHZONE accent colours.</p>
 *
 * <p><b>The backrooms clip contract</b> (F-065): {@code backrooms_clip}'s blackout is fully
 * opaque from tick {@value #CLIP_BLACKOUT_TICK} on and holds until the script ends;
 * {@code ScareTripService.CLIP_TELEPORT_DELAY_MILLIS} (170 ticks) hops the player under it,
 * and the {@code backrooms_arrive} cue replaces this script with one that opens ON black.
 * Changing the clip timing means changing BOTH constants.</p>
 */
public final class ScareScripts {
    /** The clip blackout is fully opaque from this script tick (see class doc). */
    public static final int CLIP_BLACKOUT_TICK = 168;

    /** New Photon assets built by {@code tools/photon/scare_fx.py}. */
    private static final ResourceLocation FX_SWARM = fx("scare_swarm");
    private static final ResourceLocation FX_WRAITH = fx("scare_wraith");

    // Text palette (ARGB rgb parts; alpha rides the beat envelope).
    private static final int BONE = 0xE8E2D0;
    private static final int BLOOD = 0xFF2A28;
    private static final int PHOSPHOR = 0x53FF7E;
    private static final int VOIDBLUE = 0x8FD8FF;

    private static final Map<String, ScareScript> SCRIPTS = new LinkedHashMap<>();

    static {
        SCRIPTS.put(ScareIds.GHOSTSCREEN, ghostscreen());
        SCRIPTS.put(ScareIds.BACKROOMS_CLIP, backroomsClip());
        SCRIPTS.put(ScareIds.BACKROOMS_ARRIVE, backroomsArrive());
        SCRIPTS.put(ScareIds.BACKROOMS_RETURN, backroomsReturn());
        registerJumpscares();
        // Contract check: every ScareIds name must resolve, or a /dev send would no-op.
        for (String id : ScareIds.JUMPSCARES) {
            if (!SCRIPTS.containsKey(id)) {
                EclipseMod.LOGGER.error("ScareScripts is missing a builder for '{}'", id);
            }
        }
    }

    private ScareScripts() {}

    /** Catalog lookup; {@code null} for unknown ids (the director logs and ignores). */
    @Nullable
    public static ScareScript byId(String id) {
        return SCRIPTS.get(id);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    // ================================================================== F-064 ghostscreen

    /** {@code /dev ghostscreen}: ghost → glitch text → escalating FX → ONE bang. ~10 s. */
    private static ScareScript ghostscreen() {
        return script(ScareIds.GHOSTSCREEN, 200)
                .ramp(0, 160, EclipseSounds.AMBIENT_GAZER_WHISPER, 0.0F, 0.85F, 0.9F, true)
                .ghost(15, 190)
                .pulse(30, 90, "scanlines", 0.35F, "")
                .overlay(40, 120, "smear_ghost", 0.68F, 0.42F, 0.65F, 0.45F, 25, 20, 2.0F, -0.03F, 0.0F)
                .text(70, 130, "message.eclipse.scare.text.found", 0.32F, BONE, 0.4F, 1.5F)
                .pulse(90, 150, "datamosh", 0.6F, "")
                .overlay(130, 165, "face_hollow", 0.5F, 0.5F, 0.9F, 0.8F, 8, 10, 4.0F, 0.0F, 0.0F)
                .pulse(150, 185, "invert", 0.95F, "", 4, 18)
                // THE one very loud bang of the arc.
                .sound(168, SoundEvents.GENERIC_EXPLODE::value, 1.6F, 0.6F)
                .sound(169, EclipseSounds.EVENT_RIFT_SLAM, 1.2F, 0.7F)
                .flash(168, 5, 0xFFFFFF, 0.65F)
                .shake(168, 1.3F, 18, 2.0F)
                .overlay(168, 184, "face_scream", 0.5F, 0.5F, 1.1F, 0.9F, 2, 10, 7.0F, 0.0F, 0.0F)
                .blackout(184, 200, 8, 8, 0.6F)
                .build();
    }

    // ================================================================== F-065 trip beats

    /** The ghostscreen arc that ENDS in a sustained blackout "clip" (teleport cover). */
    private static ScareScript backroomsClip() {
        return script(ScareIds.BACKROOMS_CLIP, 260)
                .ramp(0, 140, EclipseSounds.AMBIENT_GAZER_WHISPER, 0.0F, 0.9F, 0.85F, true)
                .ghost(10, 250)
                .pulse(20, 80, "scanlines", 0.4F, "")
                .overlay(30, 100, "smear_ghost", 0.3F, 0.45F, 0.6F, 0.4F, 20, 15, 2.0F, 0.04F, 0.0F)
                .text(100, 150, "message.eclipse.scare.text.clip", 0.3F, BONE, 0.45F, 1.5F)
                .pulse(80, 140, "datamosh", 0.7F, "")
                .overlay(120, 150, "face_hollow", 0.5F, 0.5F, 0.95F, 0.85F, 6, 8, 5.0F, 0.0F, 0.0F)
                .sound(148, SoundEvents.GENERIC_EXPLODE::value, 1.5F, 0.6F)
                .flash(148, 4, 0xFFFFFF, 0.6F)
                .shake(148, 1.2F, 16, 2.0F)
                .pulse(140, 168, "invert", 1.0F, "", 3, 10)
                // The clip cover: opaque from CLIP_BLACKOUT_TICK (150 + 18) until the arrive
                // cue replaces this script; the rift_glitch transition rides under it so the
                // dimension hop is double-covered.
                .blackout(150, 260, CLIP_BLACKOUT_TICK - 150, 0, 1.0F)
                .transition(158, 8, 60, 20)
                .text(200, 250, "message.eclipse.scare.text.noclip", 0.5F, VOIDBLUE, 0.3F, 1.0F)
                .build();
    }

    /** Arrival sting: opens ON black (seamless hand-off from the clip), releases slowly. */
    private static ScareScript backroomsArrive() {
        return script(ScareIds.BACKROOMS_ARRIVE, 90)
                .blackout(0, 50, 0, 25, 1.0F)
                .ramp(0, 80, EclipseSounds.AMBIENT_BORDER_STATIC, 0.5F, 0.15F, 0.8F, true)
                .sound(10, SoundEvents.AMBIENT_CAVE::value, 0.8F, 0.9F)
                .sound(28, EclipseSounds.UI_GHOST_BURST, 1.0F, 0.7F)
                .pulse(25, 70, "scanlines", 0.5F, "")
                .text(30, 80, "message.eclipse.scare.text.arrive", 0.4F, BONE, 0.35F, 1.3F)
                .build();
    }

    /** Damage bounce / time-up: a short violent glitch burst covering the return hop. */
    private static ScareScript backroomsReturn() {
        return script(ScareIds.BACKROOMS_RETURN, 70)
                .blackout(0, 20, 0, 12, 1.0F)
                .transition(0, 3, 30, 25)
                .pulse(0, 40, "datamosh", 1.0F, "", 2, 10)
                .sound(2, SoundEvents.GENERIC_EXPLODE::value, 1.2F, 0.7F)
                .sound(4, EclipseSounds.UI_ERROR_GLITCH, 1.0F, 0.8F)
                .flash(2, 4, 0xFFFFFF, 0.5F)
                .shake(2, 1.0F, 14, 2.0F)
                .text(25, 55, "message.eclipse.scare.text.ejected", 0.4F, BLOOD, 0.5F, 1.6F)
                .build();
    }

    // ================================================================== the 30 jumpscares

    private static void registerJumpscares() {
        // 1 static_face — instant shock: scanline burst + face flash + bang. White noise.
        SCRIPTS.put("static_face", script("static_face", 50)
                .fullscreen(0, 24, "scanline_veil", 0.5F, 1, 8, 4.0F)
                .pulse(0, 30, "scanlines", 1.0F, "", 2, 10)
                .overlay(2, 18, "face_static", 0.5F, 0.5F, 0.95F, 0.9F, 2, 8, 6.0F, 0.0F, 0.0F)
                .flash(2, 4, 0xFFFFFF, 0.7F)
                .sound(1, SoundEvents.GENERIC_EXPLODE::value, 1.4F, 0.75F)
                .sound(2, EclipseSounds.UI_ERROR_GLITCH, 1.0F, 0.6F)
                .shake(2, 1.1F, 14, 2.2F)
                .build());

        // 2 red_maw — instant shock: red invert flash + a maw filling the screen. Red.
        SCRIPTS.put("red_maw", script("red_maw", 70)
                .pulse(0, 40, "invert", 0.9F, "red", 3, 14)
                .tinted(3, 30, "maw", 0.5F, 0.55F, 1.1F, 0.95F, 3, 10, 5.0F, 0.0F, 0.0F, 0xFF6060)
                .flash(3, 5, 0xFF2020, 0.55F)
                .sound(2, () -> SoundEvents.RAVAGER_ROAR, 1.3F, 0.8F)
                .sound(4, SoundEvents.GENERIC_EXPLODE::value, 1.4F, 0.6F)
                .shake(3, 1.0F, 14, 1.8F)
                .build());

        // 3 whisper_turn — slow burn: whisper ramp, "do not turn around", then the face.
        SCRIPTS.put("whisper_turn", script("whisper_turn", 200)
                .ramp(0, 150, EclipseSounds.AMBIENT_GAZER_WHISPER, 0.0F, 0.9F, 0.95F, true)
                .ghost(20, 170)
                .pulse(30, 160, "void", 0.45F, "", 30, 20)
                .text(60, 150, "message.eclipse.scare.text.behind", 0.3F, BONE, 0.35F, 1.4F)
                .overlay(150, 176, "figure_crawl", 0.5F, 0.55F, 0.9F, 0.85F, 3, 12, 4.0F, 0.0F, 0.0F)
                .pulse(150, 180, "datamosh", 0.8F, "", 3, 12)
                .sound(152, () -> SoundEvents.ENDERMAN_SCREAM, 1.3F, 0.9F)
                .shake(152, 1.0F, 16, 1.6F)
                .build());

        // 4 false_calm — fake calm: soft cave ambience, then a double-hit face. Warm→white.
        SCRIPTS.put("false_calm", script("false_calm", 170)
                .sound(5, SoundEvents.AMBIENT_CAVE::value, 0.9F, 1.0F)
                .pulse(20, 100, "scanlines", 0.18F, "", 20, 20)
                .text(40, 90, "message.eclipse.scare.text.eyes", 0.62F, BONE, 0.15F, 1.0F)
                .sound(118, () -> SoundEvents.ANVIL_LAND, 1.2F, 0.7F)
                .overlay(120, 140, "face_scream", 0.5F, 0.5F, 1.0F, 0.9F, 2, 8, 6.0F, 0.0F, 0.0F)
                .sound(124, SoundEvents.GENERIC_EXPLODE::value, 1.5F, 0.55F)
                .flash(121, 4, 0xFFFFFF, 0.6F)
                .shake(120, 1.2F, 16, 2.0F)
                .pulse(118, 145, "invert", 0.85F, "", 3, 12)
                .build());

        // 5 eye_pair — dread only: eyes fade in over a void hush. NO bang by design.
        SCRIPTS.put("eye_pair", script("eye_pair", 160)
                .overlay(20, 140, "eyes_pair", 0.5F, 0.42F, 0.8F, 0.5F, 60, 30, 1.0F, 0.0F, 0.0F)
                .pulse(0, 160, "void", 0.55F, "", 40, 40)
                .ramp(0, 150, EclipseSounds.EVENT_ECLIPSE_DRONE, 0.0F, 0.5F, 0.8F, true)
                .sound(30, SoundEvents.SOUL_ESCAPE::value, 0.7F, 0.8F)
                .sound(90, SoundEvents.SOUL_ESCAPE::value, 0.6F, 0.7F)
                .build());

        // 6 datamosh_scream — codec meltdown + ghast scream. Purple.
        SCRIPTS.put("datamosh_scream", script("datamosh_scream", 70)
                .pulse(0, 50, "datamosh", 0.95F, "purple", 2, 20)
                .overlay(2, 36, "smear_ghost", 0.5F, 0.45F, 1.05F, 0.8F, 2, 10, 8.0F, 0.1F, 0.0F)
                .sound(1, () -> SoundEvents.GHAST_SCREAM, 1.3F, 0.75F)
                .sound(3, EclipseSounds.UI_GHOST_BURST, 1.0F, 0.9F)
                .flash(2, 4, 0xB040FF, 0.5F)
                .shake(2, 0.9F, 16, 1.5F)
                .build());

        // 7 mirror_glitch — invert flicker, "behind the glass", glass-break hit.
        SCRIPTS.put("mirror_glitch", script("mirror_glitch", 110)
                .pulse(10, 26, "invert", 0.7F, "", 3, 8)
                .text(20, 70, "message.eclipse.scare.text.glass", 0.35F, VOIDBLUE, 0.4F, 1.3F)
                .sound(62, () -> SoundEvents.GLASS_BREAK, 1.3F, 0.8F)
                .overlay(62, 84, "face_static", 0.5F, 0.5F, 0.7F, 0.8F, 3, 8, 5.0F, -0.15F, 0.0F)
                .sound(64, () -> SoundEvents.ENDERMAN_STARE, 1.1F, 0.7F)
                .pulse(60, 100, "invert", 0.95F, "", 3, 16)
                .flash(62, 4, 0xFFFFFF, 0.5F)
                .shake(62, 0.8F, 12, 2.0F)
                .build());

        // 8 heartbeat_rush — 10 s accelerating heartbeat ending in a sonic boom. Red-black.
        ScareScript.Builder heartbeat = script("heartbeat_rush", 200)
                .pulse(0, 180, "void", 0.6F, "red", 60, 20)
                .fov(120, 70, 0.8F, 40, 20)
                .sound(182, () -> SoundEvents.WARDEN_SONIC_BOOM, 1.5F, 0.9F)
                .blackout(182, 200, 2, 10, 1.0F)
                .shake(182, 1.3F, 18, 1.8F);
        int[] beatTimes = {0, 26, 50, 72, 92, 110, 126, 140, 152, 162, 170, 176, 180};
        for (int i = 0; i < beatTimes.length; i++) {
            heartbeat.sound(beatTimes[i], () -> SoundEvents.WARDEN_HEARTBEAT,
                    0.5F + 0.06F * i, 1.0F);
        }
        SCRIPTS.put("heartbeat_rush", heartbeat.build());

        // 9 ceiling_gaze — a face slides down from the top edge; thunder. Cold grey.
        SCRIPTS.put("ceiling_gaze", script("ceiling_gaze", 120)
                .overlay(10, 90, "face_hollow", 0.5F, -0.15F, 0.85F, 0.75F, 15, 15, 2.0F, 0.0F, 0.12F)
                .ramp(0, 90, EclipseSounds.AMBIENT_BORDER_STATIC, 0.0F, 0.6F, 0.9F, true)
                .pulse(40, 100, "scanlines", 0.5F, "")
                .sound(55, () -> SoundEvents.LIGHTNING_BOLT_THUNDER, 1.2F, 0.6F)
                .shake(55, 0.7F, 14, 1.2F)
                .build());

        // 10 hollow_choir — drone+whisper choir, three silhouettes, one bell strike. Grey.
        SCRIPTS.put("hollow_choir", script("hollow_choir", 180)
                .ramp(0, 160, EclipseSounds.EVENT_ECLIPSE_DRONE, 0.2F, 0.8F, 0.75F, true)
                .ramp(20, 160, EclipseSounds.AMBIENT_GAZER_WHISPER, 0.0F, 0.9F, 1.05F, true)
                .ghost(10, 170)
                .overlay(40, 160, "silhouette", 0.25F, 0.5F, 0.7F, 0.45F, 30, 20, 1.5F, 0.0F, 0.0F)
                .overlay(60, 160, "silhouette", 0.5F, 0.48F, 0.9F, 0.5F, 30, 20, 1.5F, 0.0F, 0.0F)
                .overlay(80, 160, "silhouette", 0.75F, 0.5F, 0.75F, 0.55F, 30, 20, 1.5F, 0.0F, 0.0F)
                .sound(150, EclipseSounds.BOSS_FERRYMAN_BELL, 1.2F, 0.5F)
                .sound(156, SoundEvents.GENERIC_EXPLODE::value, 1.2F, 0.5F)
                .pulse(140, 175, "void", 0.7F, "white", 8, 15)
                .shake(156, 0.9F, 14, 1.0F)
                .build());

        // 11 tv_shutdown — CRT collapse: scanline burst, band collapse to black, anvil clang.
        SCRIPTS.put("tv_shutdown", script("tv_shutdown", 80)
                .pulse(0, 60, "scanlines", 1.0F, "", 2, 10)
                .fullscreen(0, 60, "scanline_veil", 0.6F, 2, 10, 3.0F)
                .sound(30, EclipseSounds.UI_TIMER_ZERO, 0.9F, 1.0F)
                .flash(26, 5, 0xFFFFFF, 0.45F)
                .blackout(30, 80, 14, 0, 1.0F)
                .sound(44, () -> SoundEvents.ANVIL_LAND, 1.3F, 0.9F)
                .build());

        // 12 blood_static — red static face pulses + shrieker. All red.
        SCRIPTS.put("blood_static", script("blood_static", 90)
                .pulse(0, 70, "scanlines", 0.85F, "red", 4, 15)
                .tinted(10, 58, "face_static", 0.5F, 0.5F, 0.9F, 0.7F, 6, 10, 7.0F, 0.0F, 0.0F, 0xFF4040)
                .ramp(0, 70, EclipseSounds.AMBIENT_BORDER_STATIC, 0.3F, 0.8F, 0.7F, true)
                .sound(12, () -> SoundEvents.SCULK_SHRIEKER_SHRIEK, 1.2F, 0.8F)
                .sound(48, () -> SoundEvents.SCULK_SHRIEKER_SHRIEK, 1.3F, 0.7F)
                .shake(12, 0.6F, 12, 1.8F)
                .build());

        // 13 void_stare — void grade + ONE centered eye + enderman scream. Deep blue.
        SCRIPTS.put("void_stare", script("void_stare", 130)
                .pulse(0, 120, "void", 0.95F, "", 30, 25)
                .overlay(25, 105, "eye_single", 0.5F, 0.45F, 0.75F, 0.65F, 25, 20, 1.5F, 0.0F, 0.0F)
                .sound(20, () -> SoundEvents.ENDERMAN_STARE, 1.2F, 0.6F)
                .fov(80, 40, 0.85F, 15, 15)
                .sound(85, () -> SoundEvents.ENDERMAN_SCREAM, 1.35F, 0.85F)
                .shake(85, 0.8F, 14, 1.6F)
                .build());

        // 14 crawl_text — text-only horror: three whispers, then everything snaps to RUN.
        SCRIPTS.put("crawl_text", script("crawl_text", 160)
                .ramp(10, 115, EclipseSounds.AMBIENT_GAZER_WHISPER, 0.1F, 0.6F, 1.1F, true)
                .text(20, 120, "message.eclipse.scare.text.wall1", 0.3F, BONE, 0.25F, 1.0F)
                .text(45, 120, "message.eclipse.scare.text.wall2", 0.4F, BONE, 0.25F, 1.0F)
                .text(70, 120, "message.eclipse.scare.text.wall3", 0.5F, BONE, 0.25F, 1.0F)
                .text(120, 150, "message.eclipse.scare.text.run", 0.4F, BLOOD, 0.5F, 3.0F)
                .sound(120, EclipseSounds.UI_ERROR_GLITCH, 0.9F, 0.7F)
                .sound(122, SoundEvents.GENERIC_EXPLODE::value, 1.4F, 0.7F)
                .pulse(118, 150, "datamosh", 0.8F, "", 3, 12)
                .shake(122, 1.0F, 14, 2.0F)
                .build());

        // 15 sudden_dark — instant blackout, approaching steps, hands on the relight.
        SCRIPTS.put("sudden_dark", script("sudden_dark", 120)
                .blackout(0, 70, 2, 8, 1.0F)
                .sound(15, () -> SoundEvents.ZOMBIE_STEP, 0.5F, 0.7F)
                .sound(30, () -> SoundEvents.ZOMBIE_STEP, 0.7F, 0.65F)
                .sound(45, () -> SoundEvents.ZOMBIE_STEP, 0.9F, 0.6F)
                .sound(58, () -> SoundEvents.ZOMBIE_STEP, 1.1F, 0.55F)
                .overlay(70, 92, "hands", 0.5F, 0.5F, 1.0F, 0.85F, 2, 10, 4.0F, 0.0F, 0.0F)
                .sound(70, () -> SoundEvents.GHAST_SCREAM, 1.4F, 0.8F)
                .flash(70, 4, 0xFFFFFF, 0.5F)
                .pulse(68, 95, "invert", 0.8F, "", 3, 12)
                .shake(70, 1.1F, 14, 2.0F)
                .build());

        // 16 double_take — a small fake flash early; the REAL scare lands after the calm.
        SCRIPTS.put("double_take", script("double_take", 150)
                .flash(10, 4, 0xFFFFFF, 0.3F)
                .sound(10, EclipseSounds.UI_ERROR_GLITCH, 0.7F, 1.1F)
                .pulse(8, 20, "scanlines", 0.5F, "", 2, 8)
                .overlay(92, 116, "face_hollow", 0.5F, 0.5F, 1.0F, 0.9F, 2, 10, 5.0F, 0.0F, 0.0F)
                .sound(94, SoundEvents.GENERIC_EXPLODE::value, 1.5F, 0.6F)
                .sound(96, EclipseSounds.UI_GHOST_BURST, 1.0F, 0.8F)
                .pulse(90, 120, "invert", 0.9F, "", 3, 14)
                .shake(94, 1.2F, 16, 2.0F)
                .blackout(116, 150, 10, 15, 0.8F)
                .build());

        // 17 warden_pulse — cyan sonar palette: charge ramp into a sonic boom. Cyan.
        SCRIPTS.put("warden_pulse", script("warden_pulse", 110)
                .pulse(0, 100, "void", 0.85F, "cyan", 10, 20)
                .ramp(0, 60, () -> SoundEvents.WARDEN_SONIC_CHARGE, 0.2F, 1.0F, 0.8F, false)
                .sound(20, () -> SoundEvents.WARDEN_HEARTBEAT, 0.6F, 0.9F)
                .sound(40, () -> SoundEvents.WARDEN_HEARTBEAT, 0.8F, 0.95F)
                .fov(55, 30, 0.88F, 10, 15)
                .sound(62, () -> SoundEvents.WARDEN_SONIC_BOOM, 1.5F, 1.0F)
                .flash(62, 4, 0x40E0FF, 0.45F)
                .shake(62, 1.0F, 16, 1.4F)
                .build());

        // 18 glitch_cascade — outline → datamosh → invert ladder + white flash bang.
        SCRIPTS.put("glitch_cascade", script("glitch_cascade", 110)
                .pulse(0, 32, "outline", 0.7F, "green", 3, 8)
                .pulse(30, 62, "datamosh", 0.85F, "", 3, 8)
                .pulse(60, 84, "invert", 1.0F, "white", 3, 10)
                .sound(5, EclipseSounds.UI_ERROR_GLITCH, 0.8F, 1.2F)
                .sound(34, EclipseSounds.UI_ERROR_GLITCH, 0.9F, 1.0F)
                .sound(62, EclipseSounds.UI_ERROR_GLITCH, 1.0F, 0.8F)
                .fullscreen(60, 90, "scanline_veil", 0.4F, 3, 10, 6.0F)
                .flash(80, 5, 0xFFFFFF, 0.65F)
                .sound(80, SoundEvents.GENERIC_EXPLODE::value, 1.45F, 0.7F)
                .shake(80, 1.0F, 14, 2.2F)
                .build());

        // 19 porcelain — a pale mask closing in over 6 s under a curse riser. Pale pink.
        SCRIPTS.put("porcelain", script("porcelain", 140)
                .overlay(10, 70, "mask_pale", 0.5F, 0.45F, 0.35F, 0.55F, 20, 6, 0.8F, 0.0F, 0.0F)
                .overlay(70, 110, "mask_pale", 0.5F, 0.47F, 0.6F, 0.7F, 6, 6, 1.4F, 0.0F, 0.0F)
                .overlay(110, 128, "mask_pale", 0.5F, 0.5F, 1.05F, 0.9F, 4, 8, 3.0F, 0.0F, 0.0F)
                .ramp(20, 115, () -> SoundEvents.ELDER_GUARDIAN_CURSE, 0.2F, 0.9F, 0.7F, false)
                .ghost(10, 130)
                .sound(112, () -> SoundEvents.PHANTOM_BITE, 1.4F, 0.7F)
                .pulse(108, 130, "invert", 0.7F, "pink", 3, 10)
                .shake(112, 0.9F, 14, 1.8F)
                .build());

        // 20 backstep — pure dolly-zoom dread: FOV crush + a growl behind. NO overlay.
        SCRIPTS.put("backstep", script("backstep", 80)
                .fov(5, 60, 0.55F, 25, 20)
                .sound(8, () -> SoundEvents.WOLF_GROWL, 1.1F, 0.65F)
                .ramp(10, 60, () -> SoundEvents.PLAYER_BREATH, 0.3F, 0.8F, 0.9F, true)
                .pulse(40, 70, "datamosh", 0.5F, "", 3, 15)
                .shake(45, 0.5F, 30, 0.6F)
                .build());

        // 21 wither_wall — a silhouette sweeps across the screen + wither sting + thunder.
        SCRIPTS.put("wither_wall", script("wither_wall", 100)
                .overlay(15, 75, "silhouette", -0.2F, 0.5F, 1.0F, 0.7F, 8, 8, 2.0F, 0.3F, 0.0F)
                .sound(18, () -> SoundEvents.WITHER_AMBIENT, 1.2F, 0.8F)
                .sound(55, () -> SoundEvents.WITHER_SPAWN, 1.0F, 1.2F)
                .sound(60, () -> SoundEvents.LIGHTNING_BOLT_THUNDER, 1.3F, 0.7F)
                .pulse(50, 80, "datamosh", 0.6F, "purple", 4, 12)
                .flash(58, 4, 0x8040FF, 0.4F)
                .shake(60, 0.9F, 14, 1.4F)
                .build());

        // 22 red_rooms — red scanlines + ballast buzz + a glitching EXIT sign. No bang.
        SCRIPTS.put("red_rooms", script("red_rooms", 160)
                .pulse(0, 150, "scanlines", 0.75F, "red", 20, 25)
                .ramp(0, 140, EclipseSounds.AMBIENT_BORDER_STATIC, 0.4F, 0.9F, 0.8F, true)
                .tinted(0, 150, "scanline_veil", 0.5F, 0.5F, 0.0F, 0.3F, 15, 20, 2.0F, 0.0F, 0.0F, 0xFF5050)
                .text(30, 140, "message.eclipse.scare.text.exit", 0.3F, BLOOD, 0.6F, 2.5F)
                .sound(100, EclipseSounds.UI_TIMER_ZERO, 1.0F, 0.7F)
                .sound(142, () -> SoundEvents.IRON_DOOR_CLOSE, 1.2F, 0.6F)
                .build());

        // 23 soul_leak — soul motes drifting out of you; two faint ghosts; quiet ending.
        SCRIPTS.put("soul_leak", script("soul_leak", 150)
                .photon(20, FX_SWARM, 2.5D, 0.0D, 0.0D, 0.6F)
                .sound(15, SoundEvents.SOUL_ESCAPE::value, 0.8F, 0.75F)
                .sound(70, SoundEvents.SOUL_ESCAPE::value, 0.7F, 0.7F)
                .overlay(30, 90, "smear_ghost", 0.3F, 0.5F, 0.6F, 0.3F, 25, 20, 1.5F, 0.0F, -0.05F)
                .overlay(60, 120, "smear_ghost", 0.7F, 0.55F, 0.65F, 0.35F, 25, 20, 1.5F, 0.0F, -0.05F)
                .pulse(0, 140, "void", 0.4F, "cyan", 40, 40)
                .ramp(0, 130, EclipseSounds.EVENT_RIFT_DRONE, 0.1F, 0.5F, 0.85F, true)
                .build());

        // 24 phantom_swoop — a swoop crosses the screen, then the bite. Fast and physical.
        SCRIPTS.put("phantom_swoop", script("phantom_swoop", 70)
                .photon(4, FX_WRAITH, 3.0D, 0.5D, 0.0D, 1.0F)
                .sound(2, () -> SoundEvents.PHANTOM_SWOOP, 1.2F, 0.9F)
                .overlay(8, 30, "smear_ghost", -0.1F, 0.4F, 0.8F, 0.8F, 4, 6, 4.0F, 0.55F, 0.0F)
                .sound(26, () -> SoundEvents.PHANTOM_BITE, 1.45F, 0.8F)
                .pulse(22, 48, "datamosh", 0.75F, "", 3, 12)
                .flash(26, 4, 0xFFFFFF, 0.5F)
                .shake(26, 1.0F, 14, 2.0F)
                .build());

        // 25 last_breath — each breath dims the world a little more, then the ROAR.
        SCRIPTS.put("last_breath", script("last_breath", 180)
                .sound(5, () -> SoundEvents.PLAYER_BREATH, 0.9F, 0.85F)
                .blackout(5, 35, 6, 14, 0.35F)
                .sound(55, () -> SoundEvents.PLAYER_BREATH, 1.0F, 0.8F)
                .blackout(55, 85, 6, 14, 0.55F)
                .sound(105, () -> SoundEvents.PLAYER_BREATH, 1.1F, 0.75F)
                .blackout(105, 135, 6, 14, 0.8F)
                .text(40, 100, "message.eclipse.scare.text.breathe", 0.6F, BONE, 0.2F, 1.0F)
                .sound(140, () -> SoundEvents.WARDEN_ROAR, 1.5F, 0.85F)
                .overlay(140, 162, "face_scream", 0.5F, 0.5F, 1.05F, 0.9F, 2, 10, 5.0F, 0.0F, 0.0F)
                .pulse(138, 165, "invert", 0.85F, "", 3, 12)
                .flash(140, 4, 0xFFFFFF, 0.55F)
                .shake(140, 1.2F, 16, 1.8F)
                .build());

        // 26 null_error — ERROR spam + datamosh, ending in a fake crash-to-black. Green.
        SCRIPTS.put("null_error", script("null_error", 140)
                .text(10, 95, "message.eclipse.scare.text.error", 0.25F, PHOSPHOR, 0.7F, 1.5F)
                .text(25, 95, "message.eclipse.scare.text.error", 0.45F, PHOSPHOR, 0.7F, 1.5F)
                .text(40, 95, "message.eclipse.scare.text.error", 0.65F, PHOSPHOR, 0.7F, 1.5F)
                .sound(12, EclipseSounds.UI_ERROR_GLITCH, 1.0F, 1.0F)
                .sound(42, EclipseSounds.UI_ERROR_GLITCH, 1.0F, 0.85F)
                .sound(72, EclipseSounds.UI_ERROR_GLITCH, 1.1F, 0.7F)
                .pulse(0, 95, "datamosh", 0.9F, "green", 5, 10)
                .blackout(92, 140, 3, 0, 1.0F)
                .sound(96, () -> SoundEvents.ANVIL_LAND, 1.2F, 0.5F)
                .build());

        // 27 grin_flash — three spaced, escalating face pops (≥ 2 s apart), final bang.
        SCRIPTS.put("grin_flash", script("grin_flash", 150)
                .overlay(30, 42, "face_scream", 0.5F, 0.5F, 0.8F, 0.35F, 2, 6, 3.0F, 0.0F, 0.0F)
                .sound(31, EclipseSounds.UI_GHOST_BURST, 0.7F, 1.1F)
                .overlay(75, 87, "face_scream", 0.5F, 0.5F, 0.9F, 0.6F, 2, 6, 4.0F, 0.0F, 0.0F)
                .sound(76, EclipseSounds.UI_GHOST_BURST, 0.9F, 0.95F)
                .overlay(115, 130, "face_scream", 0.5F, 0.5F, 1.05F, 0.9F, 2, 8, 6.0F, 0.0F, 0.0F)
                .sound(116, SoundEvents.GENERIC_EXPLODE::value, 1.5F, 0.65F)
                .pulse(110, 140, "scanlines", 0.8F, "", 3, 12)
                .flash(116, 4, 0xFFFFFF, 0.6F)
                .shake(116, 1.1F, 16, 2.0F)
                .build());

        // 28 cold_call — three bell tolls, "it heard you", a dragon growl in the dark.
        SCRIPTS.put("cold_call", script("cold_call", 170)
                .sound(5, () -> SoundEvents.BELL_BLOCK, 1.0F, 0.6F)
                .sound(45, () -> SoundEvents.BELL_BLOCK, 1.1F, 0.55F)
                .sound(85, () -> SoundEvents.BELL_BLOCK, 1.2F, 0.5F)
                .text(95, 140, "message.eclipse.scare.text.heard", 0.35F, BONE, 0.3F, 1.4F)
                .ghost(60, 160)
                .sound(125, () -> SoundEvents.ENDER_DRAGON_GROWL, 1.4F, 0.7F)
                .blackout(125, 170, 12, 20, 0.9F)
                .pulse(100, 160, "void", 0.6F, "purple", 15, 20)
                .shake(125, 0.8F, 16, 1.2F)
                .build());

        // 29 swarm — a photon mote swarm rushes the camera + vex chitter. Green outline.
        SCRIPTS.put("swarm", script("swarm", 90)
                .photon(3, FX_SWARM, 4.0D, 0.0D, 0.0D, 1.2F)
                .photon(20, FX_SWARM, 2.5D, 0.0D, 1.0D, 0.8F)
                .sound(5, () -> SoundEvents.VEX_AMBIENT, 1.1F, 1.1F)
                .sound(24, () -> SoundEvents.VEX_CHARGE, 1.2F, 1.0F)
                .pulse(0, 70, "outline", 0.8F, "green", 5, 15)
                .fov(15, 40, 0.85F, 10, 15)
                .sound(50, EclipseSounds.EVENT_RIFT_SLAM, 1.3F, 0.8F)
                .shake(50, 0.9F, 14, 1.8F)
                .build());

        // 30 totality — the big one: drone, FOV crush, a giant eye, double bang, blackout.
        SCRIPTS.put("totality", script("totality", 240)
                .ramp(0, 200, EclipseSounds.EVENT_ECLIPSE_DRONE, 0.2F, 1.0F, 0.7F, true)
                .pulse(0, 190, "void", 0.9F, "purple", 60, 10)
                .fov(60, 150, 0.6F, 80, 30)
                .overlay(100, 200, "eye_single", 0.5F, 0.45F, 1.3F, 0.8F, 40, 15, 2.0F, 0.0F, 0.0F)
                .text(40, 110, "message.eclipse.scare.text.totality", 0.3F, BONE, 0.25F, 1.3F)
                .text(150, 200, "message.eclipse.scare.text.sees", 0.65F, BLOOD, 0.5F, 1.8F)
                .ghost(80, 210)
                .sound(205, SoundEvents.GENERIC_EXPLODE::value, 1.6F, 0.5F)
                .sound(207, () -> SoundEvents.WARDEN_SONIC_BOOM, 1.5F, 0.8F)
                .flash(205, 5, 0xFFFFFF, 0.7F)
                .shake(205, 1.4F, 24, 1.8F)
                .blackout(208, 240, 4, 20, 1.0F)
                .build());
    }
}
