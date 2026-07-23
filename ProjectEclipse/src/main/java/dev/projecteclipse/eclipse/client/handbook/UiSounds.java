package dev.projecteclipse.eclipse.client.handbook;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The Eclipse UI sound suite (plans_v3 P3 §2.3): thin {@code SimpleSoundInstance.forUI}
 * helpers, all gated by the {@code uiSounds} client config and scaled by the
 * {@code uiSoundVolume} slider (§7.1). Hover calls are meant to be driven by edge
 * detection ({@code EclipseWidget}'s {@code wasHovered} flip), never per-frame. Every
 * interactive Quiet-Eclipse widget presses through {@link #click()} — no vanilla plinks
 * anywhere in themed UI (B18). Deliberately NOT routed through here: the heart-shatter
 * crack and the mark bell toll (gameplay-critical warnings that must survive
 * {@code uiSounds=false}).
 *
 * <p><b>New {@code ui.*} events (W1 ledger):</b> {@code ui.click/toggle/slider/
 * error_glitch/roulette_tick/roulette_win/level_up/skill_buy/timer_zero/door_open/
 * ghost_burst} are registered centrally in {@code EclipseSounds} + {@code sounds.json} by
 * the integrator (see {@code docs/plans_v3/wiring/P3-W1_wiring.md}). Until that ledger
 * lands, the helpers below resolve the event id from the registry at play time and fall
 * back to the shipped W9 events re-pitched (§2.3's "procedural fallback = reuse ui.tab
 * pitched down") — so this class compiles and SOUNDS today and picks the real events up
 * automatically after the merge, no code change needed.</p>
 *
 * <p><b>Volume shim:</b> {@code EclipseClientConfig.uiSoundVolume()} is a W3-owned §7.1
 * getter that may not exist in this tree yet. It is looked up once via MethodHandle and
 * treated as {@code 1.0} while absent; the integrator may inline the direct call after
 * wave 1 (noted in the wiring doc).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class UiSounds {
    /** Resolved-or-fallback cache per ledger sound path (registry is frozen by play time). */
    private static final Map<String, SoundEvent> RESOLVED = new ConcurrentHashMap<>();

    /** W3's {@code uiSoundVolume()} getter, or {@code null} until that config key lands. */
    private static final MethodHandle UI_SOUND_VOLUME = findUiSoundVolume();

    private UiSounds() {}

    // --- shipped W9 suite ---

    /** Interactive element became hovered. Small pitch jitter keeps rows of widgets lively. */
    public static void hover() {
        play(EclipseSounds.UI_HOVER.get(), 0.95F + ThreadLocalRandom.current().nextFloat() * 0.1F, 0.5F);
    }

    /** Handbook page-turn whoosh (keyboard tab switch; §2.3 keeps it at 0.9 volume). */
    public static void pageTurn() {
        play(EclipseSounds.UI_PAGE_TURN.get(), 0.9F + ThreadLocalRandom.current().nextFloat() * 0.2F, 0.9F);
    }

    /** Rail/tongue tab press. */
    public static void tab() {
        play(EclipseSounds.UI_TAB.get(), 1.0F, 0.7F);
    }

    /** Unlock sting (altar level-up pulse, unlock reveals). */
    public static void unlockSting() {
        play(EclipseSounds.UI_UNLOCK_STING.get(), 1.0F, 0.9F);
    }

    /**
     * Typewriter tick of the announcement line (every 2nd revealed character). The caller
     * supplies the per-tick pitch jitter; volume matches the other UI blips.
     */
    public static void typewriter(float pitch) {
        play(EclipseSounds.UI_TYPEWRITER.get(), pitch, 0.55F);
    }

    // --- §2.3 additions (ledger events with self-healing fallbacks) ---

    /** Soft press of any themed widget — the default {@code EclipseWidget} down sound (B18). */
    public static void click() {
        play("ui.click", 1.0F, 0.55F, EclipseSounds.UI_TAB, 1.25F);
    }

    /** Settings toggle flip (W3 widgets). */
    public static void toggle() {
        play("ui.toggle", 1.0F, 0.6F, EclipseSounds.UI_TAB, 0.85F);
    }

    /** Settings slider detent tick (W3 widgets; call on value change, not per-frame). */
    public static void slider() {
        play("ui.slider", 0.95F + ThreadLocalRandom.current().nextFloat() * 0.1F, 0.4F,
                EclipseSounds.UI_HOVER, 1.35F);
    }

    /** Glitchy error burst (journey fake-error theater, invalid input). */
    public static void error() {
        play("ui.error_glitch", 1.0F, 0.8F, EclipseSounds.EVENT_BORDER_GLITCH, 1.5F);
    }

    /** Level-up celebration sting (W9, client-local). */
    public static void levelUp() {
        play("ui.level_up", 1.0F, 0.9F, EclipseSounds.UI_UNLOCK_STING, 1.15F);
    }

    /** Skill purchase confirmation (W9). */
    public static void skillBuy() {
        play("ui.skill_buy", 1.0F, 0.8F, EclipseSounds.UI_UNLOCK_STING, 0.9F);
    }

    /** One roulette head passing the needle (W10); pitch falls as the strip slows. */
    public static void rouletteTick(float pitch) {
        play("ui.roulette_tick", pitch, 0.45F, EclipseSounds.UI_TYPEWRITER, 1.1F);
    }

    /** Roulette lands on the winner (W10). */
    public static void rouletteWin() {
        play("ui.roulette_win", 1.0F, 0.95F, EclipseSounds.UI_UNLOCK_STING, 1.0F);
    }

    /** Day-timer reaches 00:00:00 (W6; exactly once per zero crossing). */
    public static void timerZero() {
        play("ui.timer_zero", 1.0F, 0.9F, EclipseSounds.EVENT_BORDER_GLITCH, 0.7F);
    }

    /** Ghost hearts burst back into real hearts on revive (W7). */
    public static void ghostBurst() {
        play("ui.ghost_burst", 1.0F, 0.9F, EclipseSounds.UI_UNLOCK_STING, 0.7F);
    }

    // --- plumbing ---

    /**
     * Plays a ledger-registered {@code eclipse:<path>} event when present in the sound
     * registry, else the {@code fallback} event with its pitch scaled by
     * {@code fallbackPitchScale} (so placeholder audio still reads as a distinct cue).
     */
    private static void play(String path, float pitch, float volume,
            Supplier<SoundEvent> fallback, float fallbackPitchScale) {
        SoundEvent registered = RESOLVED.computeIfAbsent(path, key -> BuiltInRegistries.SOUND_EVENT
                .getOptional(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, key))
                .orElse(null));
        if (registered != null) {
            play(registered, pitch, volume);
        } else {
            play(fallback.get(), pitch * fallbackPitchScale, volume);
        }
    }

    private static void play(SoundEvent sound, float pitch, float volume) {
        if (!EclipseClientConfig.uiSounds()) {
            return;
        }
        float scaled = volume * userVolume();
        if (scaled <= 0.005F) {
            return;
        }
        Minecraft.getInstance().getSoundManager().play(SimpleSoundInstance.forUI(sound, pitch, scaled));
    }

    /** {@code eclipse-client.toml} {@code uiSoundVolume} (0..1), or 1.0 until W3's key exists. */
    private static float userVolume() {
        if (UI_SOUND_VOLUME == null) {
            return 1.0F;
        }
        try {
            return (float) Mth.clamp((double) UI_SOUND_VOLUME.invokeExact(), 0.0D, 1.0D);
        } catch (Throwable throwable) {
            return 1.0F;
        }
    }

    private static MethodHandle findUiSoundVolume() {
        try {
            return MethodHandles.publicLookup().findStatic(EclipseClientConfig.class,
                    "uiSoundVolume", MethodType.methodType(double.class));
        } catch (ReflectiveOperationException absent) {
            return null; // W3 (wave 1) has not landed in this tree yet — full volume.
        }
    }
}
