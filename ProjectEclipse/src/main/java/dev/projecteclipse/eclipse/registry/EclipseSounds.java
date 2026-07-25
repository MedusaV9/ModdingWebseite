package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Sound event registry for Project: Eclipse. */
public final class EclipseSounds {
    public static final DeferredRegister<SoundEvent> SOUNDS =
            DeferredRegister.create(Registries.SOUND_EVENT, EclipseMod.MOD_ID);

    /** Looping ambient bed of the Limbo dimension, played and faded by {@code veilfx.LimboAmbience}. */
    public static final Supplier<SoundEvent> AMBIENT_LIMBO_LOOP = SOUNDS.register(
            "ambient.limbo_loop",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.limbo_loop")));

    /** One-shot cue played when the ghost ship submerges during the start event. */
    public static final Supplier<SoundEvent> EVENT_SUBMERGE = SOUNDS.register(
            "event.submerge",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.submerge")));

    /**
     * One-shot cue at the end of the intro rise / finale return camera paths (referenced by
     * the default cutscene JSONs): a reverse-swell rising into a bright airy release.
     */
    public static final Supplier<SoundEvent> EVENT_EMERGE = SOUNDS.register(
            "event.emerge",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.emerge")));

    /** Glass-crack cue played locally when a permanent heart shatters after respawn. */
    public static final Supplier<SoundEvent> UI_HEART_SHATTER = SOUNDS.register(
            "ui.heart_shatter",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.heart_shatter")));

    /** Digital-static burst played when the soft border pushes an entity back (W7). */
    public static final Supplier<SoundEvent> EVENT_BORDER_GLITCH = SOUNDS.register(
            "event.border_glitch",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.border_glitch")));

    /** Single dry tick of the announcement typewriter line (W8; every 2nd revealed char). */
    public static final Supplier<SoundEvent> UI_TYPEWRITER = SOUNDS.register(
            "ui.typewriter",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.typewriter")));

    // W9 UI suite — played via client.handbook.UiSounds (SimpleSoundInstance.forUI,
    // gated by the uiSounds client config).

    /** Soft blip when an interactive UI element becomes hovered (edge-detected). */
    public static final Supplier<SoundEvent> UI_HOVER = SOUNDS.register(
            "ui.hover",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.hover")));

    /** Paper whoosh of the handbook page-turn animation. */
    public static final Supplier<SoundEvent> UI_PAGE_TURN = SOUNDS.register(
            "ui.page_turn",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.page_turn")));

    /** Short two-tone click when a handbook tab tongue is pressed. */
    public static final Supplier<SoundEvent> UI_TAB = SOUNDS.register(
            "ui.tab",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.tab")));

    /** Rising chime sting for UI-visible unlocks (altar ring level-up pulse). */
    public static final Supplier<SoundEvent> UI_UNLOCK_STING = SOUNDS.register(
            "ui.unlock_sting",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.unlock_sting")));

    /** Whisper loop of the Gazer (W10) — audible only within ~12 blocks (ambient sound). */
    public static final Supplier<SoundEvent> AMBIENT_GAZER_WHISPER = SOUNDS.register(
            "ambient.gazer_whisper",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.gazer_whisper"),
                    12.0F));

    // W11 Herald boss suite.

    /** Low glassy drone of the Herald (its mob ambient sound during the fight). */
    public static final Supplier<SoundEvent> BOSS_HERALD_AMBIENT = SOUNDS.register(
            "boss.herald_ambient",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_ambient")));

    /** Rising chime cue at the start of every volley telegraph (the "shoot me now" tell). */
    public static final Supplier<SoundEvent> BOSS_HERALD_TELEGRAPH = SOUNDS.register(
            "boss.herald_telegraph",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_telegraph")));

    // W12 Ferryman boss suite.

    /** Hollow, waterlogged groan of the Ferryman (its mob ambient sound during the fight). */
    public static final Supplier<SoundEvent> BOSS_FERRYMAN_AMBIENT = SOUNDS.register(
            "boss.ferryman_ambient",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.ferryman_ambient")));

    /** Sunken bell toll: crew-phase entry and each lantern re-lit by a ghost. */
    public static final Supplier<SoundEvent> BOSS_FERRYMAN_BELL = SOUNDS.register(
            "boss.ferryman_bell",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.ferryman_bell")));

    // P4 gameplay feedback (R3/R5/R6/R8).

    /** Short chime when a skill proc fires (double drop, etc.). */
    public static final Supplier<SoundEvent> SKILL_PROC = SOUNDS.register(
            "skill.proc",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill.proc")));

    /** Level-up sting when skill XP crosses a level boundary. */
    public static final Supplier<SoundEvent> SKILL_LEVELUP = SOUNDS.register(
            "skill.levelup",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill.levelup")));

    /** Daily award category reveal sting. */
    public static final Supplier<SoundEvent> AWARD_STING = SOUNDS.register(
            "award.sting",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "award.sting")));

    /** Altar personal offering accepted. */
    public static final Supplier<SoundEvent> OFFERING_ACCEPT = SOUNDS.register(
            "offering.accept",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "offering.accept")));

    /** Heart extractor use-finish cue (R8). */
    public static final Supplier<SoundEvent> RITUAL_EXTRACT = SOUNDS.register(
            "ritual.extract",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ritual.extract")));

    /** D4 heart-theft pulse (layered under a deep bell at the call site; shipped-ogg alias). */
    public static final Supplier<SoundEvent> THEFT_STEAL = SOUNDS.register(
            "theft.steal",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "theft.steal")));

    // P2-W1 FX suite (§3.5) — every entry maps to an EXISTING ogg in sounds.json as a
    // placeholder (P2 commits no new binary assets); consumers: W6 intro lightning, W9
    // storms, W7/W8 rifts, W5 supply beam, W2 captions.

    /** Violent close-range lightning crack (intro strikes within ~40 blocks). */
    public static final Supplier<SoundEvent> EVENT_LIGHTNING_CLOSE = SOUNDS.register(
            "event.lightning_close",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.lightning_close")));

    /** Rolling far-off lightning rumble (storm shells, distant intro strikes). */
    public static final Supplier<SoundEvent> EVENT_LIGHTNING_FAR = SOUNDS.register(
            "event.lightning_far",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.lightning_far")));

    /** Positional churn loop of a fog-storm wall/vortex (64-block falloff, W9). */
    public static final Supplier<SoundEvent> EVENT_STORM_LOOP = SOUNDS.register(
            "event.storm_loop",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_loop"),
                    64.0F));

    /** One-shot storm burst: vortex dissipate / giant-strike release (W6/W9). */
    public static final Supplier<SoundEvent> EVENT_STORM_BURST = SOUNDS.register(
            "event.storm_burst",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_burst")));

    // C8 fog-storm sphere suite — 2 ambient loops + 3 stingers, all sounds.json aliases of
    // shipped oggs (house rule: no new binary audio assets from event workers).

    /** Exterior wall roar of a sphere-type site storm (fixed 64, mirrors the churn loop). */
    public static final Supplier<SoundEvent> EVENT_STORM_SPHERE_ROAR = SOUNDS.register(
            "event.storm_sphere_roar",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_sphere_roar"),
                    64.0F));

    /** Muffled interior drone bed inside a sphere storm (relative loop, StormInteriorFx). */
    public static final Supplier<SoundEvent> AMBIENT_STORM_DOME_DRONE = SOUNDS.register(
            "ambient.storm_dome_drone",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.storm_dome_drone")));

    /** Heartbeat-adjacent sub-bass pulse of a sphere interior (heartbeatSound()-gated). */
    public static final Supplier<SoundEvent> EVENT_STORM_PULSE = SOUNDS.register(
            "event.storm_pulse",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_pulse")));

    /** Silhouette-flicker hiss of a sphere interior (the lightning-less scare sting). */
    public static final Supplier<SoundEvent> EVENT_STORM_FLICKER = SOUNDS.register(
            "event.storm_flicker",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_flicker")));

    /** Glass-shatter layer of the tyrant-death storm explosion (under the thunderclap). */
    public static final Supplier<SoundEvent> EVENT_STORM_SHATTER = SOUNDS.register(
            "event.storm_shatter",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_shatter")));

    /** Rift tear-open crackle (structure drops, xbox portal — W7/W8). */
    public static final Supplier<SoundEvent> EVENT_RIFT_OPEN = SOUNDS.register(
            "event.rift_open",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_open")));

    /** Structure slam when a rift drops its payload (W7). */
    public static final Supplier<SoundEvent> EVENT_RIFT_SLAM = SOUNDS.register(
            "event.rift_slam",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_slam")));

    /** Low eclipse drone bed while the world grade is crushed (W6/W7 sequences). */
    public static final Supplier<SoundEvent> EVENT_ECLIPSE_DRONE = SOUNDS.register(
            "event.eclipse_drone",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.eclipse_drone")));

    /** Supply-beam hum loop at the drop marker (W5, 48-block presence). */
    public static final Supplier<SoundEvent> EVENT_BEAM_HUM = SOUNDS.register(
            "event.beam_hum",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.beam_hum"),
                    48.0F));

    /** Caption typewriter tick (alias of {@code ui.typewriter}; W2 CaptionRenderer). */
    public static final Supplier<SoundEvent> UI_CAPTION_TICK = SOUNDS.register(
            "ui.caption_tick",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.caption_tick")));

    // W4-ATMOS sound suite (IDEA-07 §1/§2/§3/§7) — all aliases of shipped oggs.

    /** Sanctum aura hum loop (client.sound.SanctumHum resolves it at runtime, self-healing). */
    public static final Supplier<SoundEvent> AMBIENT_SANCTUM_HUM = SOUNDS.register(
            "ambient.sanctum_hum",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.sanctum_hum")));

    /** Soft-border static whisper loop (client.sound.BorderStaticSound, relative bed). */
    public static final Supplier<SoundEvent> AMBIENT_BORDER_STATIC = SOUNDS.register(
            "ambient.border_static",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.border_static")));

    /** Distant low howl layered under the Herald summon roar (heard disc-wide). */
    public static final Supplier<SoundEvent> BOSS_HERALD_ROAR_FAR = SOUNDS.register(
            "boss.herald_roar_far",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_roar_far")));

    /** Muffled far-shell volley telegraph for players kiting outside the arena. */
    public static final Supplier<SoundEvent> BOSS_HERALD_TELEGRAPH_FAR = SOUNDS.register(
            "boss.herald_telegraph_far",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_telegraph_far")));

    /** Periodic hum of the xbox portal (xboxevent.XboxPortal resolves it at runtime). */
    public static final Supplier<SoundEvent> EVENT_XBOX_PORTAL_LOOP = SOUNDS.register(
            "event.xbox_portal_loop",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.xbox_portal_loop")));

    // C17 era-immersion pair (client.xbox.XboxEraSounds) — both are sounds.json POOLS of
    // VANILLA asset files (C418-era tracks / cave1-13), so no audio is bundled.

    /** C418-era in-game music pool (Volume Alpha tracks; scheduled inside xbox dims). */
    public static final Supplier<SoundEvent> MUSIC_XBOX_ERA = SOUNDS.register(
            "music.xbox_era",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "music.xbox_era")));

    /** Era cave-ambience subset (cave1-13 only; {@code ambient.cave} remap target). */
    public static final Supplier<SoundEvent> AMBIENT_XBOX_CAVE = SOUNDS.register(
            "ambient.xbox_cave",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.xbox_cave")));

    // PLAN-C C11/C13 End-event suite — sounds.json aliases of shipped oggs (house rule:
    // event workers commit no new binary audio assets).

    /** Wind-altar launch whoosh (C11 sky launcher fire + return-pad step-off). */
    public static final Supplier<SoundEvent> EVENT_SKY_LAUNCH = SOUNDS.register(
            "event.sky_launch",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.sky_launch")));

    /** Bass rumble under the End-disc shatter beat 0 (C13, heard disc-wide). */
    public static final Supplier<SoundEvent> EVENT_END_SHATTER_RUMBLE = SOUNDS.register(
            "event.end_shatter_rumble",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.end_shatter_rumble")));

    /** Layered stone-crack stinger while the carve pass splits the disc (C13). */
    public static final Supplier<SoundEvent> EVENT_END_SHATTER_CRACK = SOUNDS.register(
            "event.end_shatter_crack",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.end_shatter_crack")));

    // C7 expansion-delivery suite (worldgen.stage.StructureFlightFx) — all sounds.json
    // aliases of shipped oggs (the P2-W1 placeholder doctrine; real oggs may replace the
    // aliases via the C19 pipeline without touching code).

    /** Deep tear-groan bed while a delivery rift is open (64+ block presence). */
    public static final Supplier<SoundEvent> EVENT_RIFT_DRONE = SOUNDS.register(
            "event.rift_drone",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_drone"),
                    96.0F));

    /** Whoosh of a structure-piece batch launching out of the rift mouth. */
    public static final Supplier<SoundEvent> EVENT_RIFT_WHOOSH = SOUNDS.register(
            "event.rift_whoosh",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_whoosh")));

    /** Bass thud of one flying piece settling on its target cell. */
    public static final Supplier<SoundEvent> EVENT_RIFT_THUD = SOUNDS.register(
            "event.rift_thud",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_thud")));

    /** Resolve chord as the delivery completes and the tear snaps shut. */
    public static final Supplier<SoundEvent> EVENT_RIFT_RESOLVE = SOUNDS.register(
            "event.rift_resolve",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_resolve")));

    // FFIX-A ledger event (V6-FIXWIRE #4) — sounds.json alias of a shipped ogg.

    /** Boss-down release sting broadcast to everyone (drama.BossDownSting). */
    public static final Supplier<SoundEvent> EVENT_BOSS_DOWN = SOUNDS.register(
            "event.boss_down",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.boss_down")));

    // --- Quiet-Eclipse UI kit (P3-W1 ledger; UiSounds resolves these by id at runtime) ---

    /** Generic widget press. */
    public static final Supplier<SoundEvent> UI_CLICK = uiEvent("ui.click");
    /** Toggle flip. */
    public static final Supplier<SoundEvent> UI_TOGGLE = uiEvent("ui.toggle");
    /** Slider drag notch. */
    public static final Supplier<SoundEvent> UI_SLIDER = uiEvent("ui.slider");
    /** Journey-gate / error glitch burst. */
    public static final Supplier<SoundEvent> UI_ERROR_GLITCH = uiEvent("ui.error_glitch");
    /** Skill level-up celebration. */
    public static final Supplier<SoundEvent> UI_LEVEL_UP = uiEvent("ui.level_up");
    /** Skill node purchase. */
    public static final Supplier<SoundEvent> UI_SKILL_BUY = uiEvent("ui.skill_buy");
    /** Award roulette tick. */
    public static final Supplier<SoundEvent> UI_ROULETTE_TICK = uiEvent("ui.roulette_tick");
    /** Award roulette winner sting. */
    public static final Supplier<SoundEvent> UI_ROULETTE_WIN = uiEvent("ui.roulette_win");
    /** Day timer reaching 00:00. */
    public static final Supplier<SoundEvent> UI_TIMER_ZERO = uiEvent("ui.timer_zero");
    /** Ship door creak of the death-flow door beat (W1-ledger id, closed by W4-ATMOS). */
    public static final Supplier<SoundEvent> UI_DOOR_OPEN = uiEvent("ui.door_open");
    /** Ghost-heart burst on revive. */
    public static final Supplier<SoundEvent> UI_GHOST_BURST = uiEvent("ui.ghost_burst");
    // W4-FEEL ui ledger (aliases; UiSounds self-heals until these land).
    /** Sidebar goal-complete stamp (pitch-salted at the call site). */
    public static final Supplier<SoundEvent> UI_GOAL_STAMP = uiEvent("ui.goal_stamp");
    /** Skill-tree purchase cascade whoosh (one per cascade). */
    public static final Supplier<SoundEvent> UI_SKILL_UNLOCK = uiEvent("ui.skill_unlock");
    /** Settings toggle knob-dock tick (ON 1.1 / OFF 0.75). */
    public static final Supplier<SoundEvent> UI_TOGGLE_SETTLE = uiEvent("ui.toggle_settle");
    // FFIX-A contract pair (V6-FIXWIRE #4 — the rows existed in sounds.json, only the
    // registrations were missing; UiSounds' runtime resolve now finds them).
    /** Soft glass chime — the contract prank exhale. */
    public static final Supplier<SoundEvent> UI_CHIME = uiEvent("ui.chime");
    /** Contract X-stamp slam (anvil-adjacent two-layer read baked into the alias). */
    public static final Supplier<SoundEvent> UI_STAMP = uiEvent("ui.stamp");

    private static Supplier<SoundEvent> uiEvent(String id) {
        return SOUNDS.register(id, () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, id)));
    }

    private EclipseSounds() {}

    public static void register(IEventBus modEventBus) {
        SOUNDS.register(modEventBus);
    }
}
