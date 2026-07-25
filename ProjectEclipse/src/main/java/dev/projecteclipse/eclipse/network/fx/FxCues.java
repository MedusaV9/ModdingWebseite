package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;

/**
 * Frozen logical FX cue ids for the {@code PhotonFxRegistry} lane (INTEGRATION.md §3):
 * plain server-referenceable constants so server code never touches client classes (repo
 * rule). A cue travels over the EXISTING {@code S2CFxEventPayload}
 * ({@link FxPayloads#sendFxEvent}) — no new payload type, no registrar bump, identical
 * bytes whether or not the client has Photon. On the client,
 * {@code veilfx/PhotonFxRegistry} resolves the cue to a Photon effect and/or a Quasar
 * fallback via its registered row.
 *
 * <p>Namespace law: cue ids reuse the {@code eclipse:fx/} prefix (collision-free with the
 * v1 payload ids) with an extra {@code cue/} segment so they are visually distinct from
 * the handler-dispatched {@code fx/*} ids in {@link FxPayloads}.</p>
 *
 * <p>Content workers: add one {@code CUE_*} constant here per new cue (server side) and
 * register the matching row in your own {@code *PhotonFxRows} client registrar class
 * (see {@code veilfx/PhotonFxRows} for the reference pattern).</p>
 */
public final class FxCues {
    /** PH-CORE smoke test: one-shot spark burst ({@code eclipse:template_burst}). */
    public static final ResourceLocation CUE_TEMPLATE_BURST = cue("template_burst");
    /** PH-CORE smoke test: looping aura ring ({@code eclipse:template_loop}, WINDOWED-only). */
    public static final ResourceLocation CUE_TEMPLATE_LOOP = cue("template_loop");
    /**
     * PH-RIFT (IDEAS-events #4): growth-wavefront front-rider announce — {@code pos} = the
     * rider's spawn/discard point, {@code a} = the rider entity's network id (entity ids
     * are session-scoped ints well inside float precision), {@code b} = 1 attach / 0
     * release. Entity-anchored, so it is dispatched by a dedicated {@code FxPayloads}
     * branch (INTEGRATION.md §3.5 law 5) to {@code ExpansionSequence.ClientHooks}, NOT by
     * a {@code PhotonFxRegistry} row (rows are position-anchored).
     */
    public static final ResourceLocation CUE_GROWTH_RIDER = cue("growth_rider");

    /**
     * PH-EVENTS: per-strike beam of the credits t=420 lightning ladder
     * ({@code eclipse:credits_strike_beam}). Sent by {@code CreditsSequence.
     * beatLightningStrike} one line after its {@code FX_LIGHTNING_STRIKE} broadcast —
     * same impact pos, same intensity in {@code a} (client maps it to executor scale).
     * Deliberately NOT piggybacked on {@code FX_LIGHTNING_STRIKE}: that id also fires at
     * 15-tick cadence during the intro's LIGHTNING hold (frequency law).
     */
    public static final ResourceLocation CUE_CREDITS_STRIKE = cue("credits_strike");
    /**
     * PH-EVENTS: DOOMSDAY burst confetti mesh shards ({@code eclipse:
     * credits_confetti_burst}), sent by {@code CreditsSequence.beatBurst} at
     * {@code runnersCenter} alongside its shockwave. Not keyed off {@code FX_SHOCKWAVE}
     * (the (1.0, 50) giant signature is claimed by the intro burst ring's client seam).
     */
    public static final ResourceLocation CUE_CREDITS_BURST = cue("credits_burst");
    /**
     * PH-EVENTS: structure-slam dust mushroom with collision sub-emitters
     * ({@code eclipse:structure_slam_mushroom}), sent by {@code ExpansionSequence.slamFx}
     * at the slam pos with {@code a} = site footprint (client maps it to executor scale).
     */
    public static final ResourceLocation CUE_STRUCTURE_SLAM = cue("structure_slam");

    /**
     * PH-BOSS-B (IDEAS-boss #2): Fog Tyrant C8 death implosion — indraw + HDR white-out +
     * physics debris with FirstCollision fog puffs ({@code eclipse:boss/tyrant_death_implosion}).
     */
    public static final ResourceLocation CUE_TYRANT_DEATH_IMPLOSION = cue("tyrant_death_implosion");
    /**
     * PH-BOSS-B (IDEAS-boss #6): Fog Tyrant blind-squall release flash + staggered fog
     * shells ({@code eclipse:boss/tyrant_blind_burst}).
     */
    public static final ResourceLocation CUE_TYRANT_SQUALL = cue("tyrant_squall");
    /**
     * PH-BOSS-B (IDEAS-boss #3): Rift Warden volley-telegraph eye laser
     * ({@code eclipse:boss/warden_eye_laser}). Carries {@code a} = the warden's yaw in
     * degrees so the client can aim the raycast beam (rotation cannot ride the generic
     * {@code PhotonFxRegistry.dispatch(id, pos)} tail — see the explicit
     * {@code FxPayloads.handleFxEvent} branch).
     */
    public static final ResourceLocation CUE_WARDEN_VOLLEY_TELEGRAPH = cue("warden_volley_telegraph");
    /**
     * PH-BOSS-B (IDEAS-boss #7): Rift Warden stagger glitch-shard orbit, 40t =
     * {@code STAGGER_TICKS} ({@code eclipse:boss/warden_glitch_orbit}).
     */
    public static final ResourceLocation CUE_WARDEN_STAGGER = cue("warden_stagger");
    /**
     * PH-ALTAR (IDEAS-world #9): idle L5 corona ribbons ({@code eclipse:altar_corona_idle}).
     * Loop row — WINDOWED-only, never payload-fired; driven client-side by
     * {@code client/drama/AltarCoronaIdle} off the {@code ALTAR_CENTER} anchor.
     */
    public static final ResourceLocation CUE_ALTAR_CORONA_IDLE = cue("altar_corona_idle");

    // PH-WORLD landmark cues (IDEAS-world.md concepts 5/6b/7). Rows registered by the
    // client-only registrar `veilfx/WorldPhotonFxRows`.
    /**
     * PH-WORLD (IDEAS-world #5): sky-launcher charge helix ({@code eclipse:
     * sky_launch_charge}) — 3 ara ribbons flying the golden-angle spiral, exactly
     * {@code SkyLauncher.CHARGE_TICKS} long. Sent by {@code SkyLauncher.beginCharge}
     * beside the AMETHYST_BLOCK_CHIME, pos = pad center, range 64. Charge cancel needs
     * no stop wiring: the asset is 15t finite and the launch cue simply never follows.
     */
    public static final ResourceLocation CUE_SKY_LAUNCH_CHARGE = cue("sky_launch_charge");
    /**
     * PH-WORLD (IDEAS-world #5): launch contrail ({@code eclipse:sky_launch_contrail}),
     * sent by {@code SkyLauncher.launch} beside the EVENT_SKY_LAUNCH sound on the ENTITY
     * lane ({@link FxPayloads#sendFxEntityEvent}, target = the launched player) so the
     * row's Photon leg rides the flyer via {@code PhotonBridge.spawnOnEntity} — entity
     * death auto-cleans mid-flight. An untracked target degrades to the nearest player
     * (the {@code FxPayloads.nearestPlayer} glide pattern, 8-block match), then to the
     * position anchor.
     */
    public static final ResourceLocation CUE_SKY_LAUNCH = cue("sky_launch");
    /**
     * PH-WORLD (IDEAS-world #7): nether-breach ash geyser ({@code eclipse:
     * breach_ash_geyser}). Loop row — WINDOWED-only, never payload-fired; driven
     * client-side by {@code client/breach/BreachAmbience} off the client-computable
     * {@code BreachGeometry} chimney anchor.
     */
    public static final ResourceLocation CUE_BREACH_ASH_GEYSER = cue("breach_ash_geyser");
    /**
     * PH-WORLD (IDEAS-world #7): nether-breach ember ribbon updrafts ({@code eclipse:
     * breach_ember_updraft}). Loop row — WINDOWED-only, same {@code BreachAmbience}
     * window as {@link #CUE_BREACH_ASH_GEYSER}.
     */
    public static final ResourceLocation CUE_BREACH_EMBER_UPDRAFT = cue("breach_ember_updraft");
    /**
     * PH-WORLD (IDEAS-world #6b): end-disc void wisps ({@code eclipse:end_void_wisps}),
     * the 1200-particle GPU-instancing showcase. Loop row — WINDOWED-only; driven
     * client-side by {@code client/end/EndVoidWisps} off the frozen
     * {@code DiscProfile.END_DISC_*} constants.
     */
    public static final ResourceLocation CUE_END_VOID_WISPS = cue("end_void_wisps");

    /**
     * PH-BOSS-A (IDEAS-boss #1): shared boss-agnostic roar ring — ground-hugging HDR ring +
     * light column + spark sheet ({@code eclipse:boss/roar_shockwave}). Fired at summon
     * arrivals and phase breaks (Herald summon/P3, Ferryman summon; Tyrant/Warden sites may
     * reuse it).
     */
    public static final ResourceLocation CUE_BOSS_ROAR = cue("boss_roar");
    /**
     * PH-BOSS-A (IDEAS-boss #4): Ferryman crew-phase entrance — soul-lantern model swarm
     * rising off the kneeling boss ({@code eclipse:boss/ferry_lantern_swarm}). One-shot 80t
     * at the stern kneel anchor; the sustain is {@link #CUE_FERRY_KNEEL_CORONA}.
     */
    public static final ResourceLocation CUE_FERRY_LANTERN_SWARM = cue("ferry_lantern_swarm");
    /**
     * PH-BOSS-A (IDEAS-boss #8): Ferryman oar-sweep water-tear arc
     * ({@code eclipse:boss/ferry_oar_tear}). Carries {@code a} = the boss's yaw in degrees;
     * the row's custom Photon leg rotates the executor so the function-shape half-circle
     * (bulge at local −Z) aligns with the boss's forward.
     */
    public static final ResourceLocation CUE_FERRY_OAR_SWEEP = cue("ferry_oar_sweep");
    /**
     * PH-BOSS-A (IDEAS-boss #9): Ferryman kneel corona sustain — quiet teal halo + inert
     * shell while the boss kneels invulnerable ({@code eclipse:boss/ferry_kneel_corona}).
     * Re-sent every {@code CREW_CHECK_TICKS} (20t) from {@code tickCrewPhase}: each re-send
     * is a silent Photon dedup no-op while the 100t runtime lives ({@code allowMulti=false});
     * when {@code endCrewPhase} stops the re-fire the last cycle fades out naturally.
     */
    public static final ResourceLocation CUE_FERRY_KNEEL_CORONA = cue("ferry_kneel_corona");

    // PH-PLAYER wand power cues (IDEAS-player.md concepts 2/4/5). Rows registered by the
    // client-only registrar `client/wand/WandPhotonFxRows`; the Quasar compositions these
    // powers already fire keep running unchanged (all rows are Mode.LAYER garnish).
    /**
     * PH-PLAYER (IDEAS-player #2): STERN L3 Kometenschlag descent ribbon + delayed HDR
     * impact ({@code eclipse:stern_komet_fall} / {@code _impact}). pos = aimed point,
     * {@code a} = telegraphTicks — the client {@code setDelay}s the impact bloom by exactly
     * this so it lands on the damage tick. Sent once at cast from
     * {@code WandPowers.castKometenschlag}.
     */
    public static final ResourceLocation CUE_STERN_KOMET = cue("stern_komet");
    /**
     * PH-PLAYER (IDEAS-player #4): RISS L3 Rissschlag maw implosion
     * ({@code eclipse:riss_schlag_maw} + Death sub-chain). pos = maw target,
     * {@code a} = openTicks (informational — the ~25t implosion window is baked into the
     * asset). Sent once at cast from {@code WandPowers.castRissschlag}.
     */
    public static final ResourceLocation CUE_RISS_SCHLAG = cue("riss_schlag");
    /**
     * PH-PLAYER (IDEAS-player #5): GLUT L3 Magmasprung eruption
     * ({@code eclipse:glut_sprung_crater} + Collision/Death sub-emitters), fired TWICE:
     * at cast over the ENTITY lane ({@link FxPayloads#sendFxEntityEvent}, caster anchor —
     * the eruption departs with the launch) and at touchdown over the position lane from
     * {@code WandTickService.MagmaJump} ({@code b} = 1 marks the landing re-send).
     */
    public static final ResourceLocation CUE_GLUT_SPRUNG = cue("glut_sprung");

    /**
     * PH-SOCIAL (IDEAS-player #3): heart-theft soul arc — the stolen Leben visibly flying
     * from the corpse to the killer. {@code pos} = the victim's corpse (feet), {@code a} =
     * killer entity network id, {@code b} = victim entity network id (session-scoped ints,
     * float-safe — the {@code CUE_GROWTH_RIDER} precedent). Needs per-executor rotation +
     * delays the generic {@code PhotonFxRegistry.dispatch(id, pos)} tail cannot carry, so
     * {@code FxPayloads.handleFxEvent} routes it to
     * {@code veilfx/PlayerFxPhotonRows.heartTheftArc} (the warden-telegraph pattern).
     * Sent by {@code HeartTheftService.celebrate} one line after its {@code HEART_BURST}
     * Quasar payload — that drift stays the photon-less baseline (Mode.LAYER).
     */
    public static final ResourceLocation CUE_HEART_THEFT = cue("heart_theft");

    // PH-SOCIAL windowed entity loops (IDEAS-player #7/#8/#9/#10) deliberately have NO cue
    // constants: rebirth aura / hunter mark / ghost wisp / glide trail are client-resolved
    // from already-synced truth (rebirth payload, reveal payload, ghost team, glide FX
    // events) — "no wire at all" per the doc's cross-cutting notes.

    // PH-MOBS custom-mob + celebration cues (IDEAS-mobs.md #1, #4, #5). Rows registered
    // by the client-only registrar `veilfx/MobPhotonFxRows`; the entity-attached loop
    // tier (#6/#7/#8/#9/#10) is NOT cue-driven — `veilfx/PhotonMobFx` attaches those
    // client-locally off synced state, zero wire traffic.
    /**
     * PH-MOBS (IDEAS-mobs #1): boss-intro name-lock ground shockwave
     * ({@code eclipse:boss_intro_shockwave}). Sent by {@code BossPayloads.sendIntro}
     * with the same {@code center}; the client parks the spawn behind
     * {@code setDelay(BossIntroOverlay.pendingLockDelayTicks())} so the ring erupts on
     * the card's DANGER→TEXT lock flash (delay 0 when no card is live).
     */
    public static final ResourceLocation CUE_BOSS_INTRO_SHOCKWAVE = cue("boss_intro_shockwave");
    /**
     * PH-MOBS (IDEAS-mobs #5): the code-reserved {@code eclipse:glitch_pop} datamosh
     * slot — REVERSE_SUB+ADD two-pass burst, sent TWICE per {@code GlitchedMonster.
     * tryBlink} (origin + exit). The row's Photon leg forces {@code allowMulti=true}:
     * short blinks can land both endpoints in the SAME BlockPos and the default dedup
     * would eat the exit half. The paired REVERSE_PORTAL bursts stay untouched.
     */
    public static final ResourceLocation CUE_GLITCH_POP = cue("glitch_pop");
    /**
     * PH-MOBS (IDEAS-mobs #4): Storm Hound charge-up spiral over the 20t rooted windup
     * ({@code eclipse:hound_lunge_windup}), sent by {@code ChargedLungeGoal.start} on the
     * ENTITY lane ({@link FxPayloads#sendFxEntityEvent}) so the telegraph rides the
     * rooted hound; untracked targets degrade to the position anchor.
     */
    public static final ResourceLocation CUE_HOUND_WINDUP = cue("hound_windup");
    /**
     * PH-MOBS (IDEAS-mobs #4): Storm Hound dash fog ribbon ({@code eclipse:
     * hound_dash_trail}), sent at the WINDUP→DASH commit on the ENTITY lane and attached
     * {@code AutoRotate.FORWARD} so the ara ribbon lays along the locked dash line.
     */
    public static final ResourceLocation CUE_HOUND_DASH = cue("hound_dash");

    private FxCues() {}

    /** {@code eclipse:fx/cue/<name>} — use for every new registry cue id. */
    public static ResourceLocation cue(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/cue/" + name);
    }
}
