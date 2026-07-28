package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;

/**
 * Frozen logical FX cue ids for the {@code PhotonFxRegistry} lane (INTEGRATION.md §3):
 * plain server-referenceable constants so server code never touches client classes (repo
 * rule). A cue travels over one of TWO frozen carriers — the position lane
 * {@code S2CFxEventPayload} ({@link FxPayloads#sendFxEvent}) or, for cues that ride a
 * living target, the entity lane {@code S2CFxEntityEventPayload}
 * ({@link FxPayloads#sendFxEntityEvent}, the one payload addition the IDEAS-mobs batch
 * pre-authorized). Bytes are identical whether or not the client has Photon. On the
 * client, {@code veilfx/PhotonFxRegistry} resolves the cue to a Photon effect and/or a
 * Quasar fallback via its registered row ({@code dispatch} / {@code dispatchEntity}).
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
    /** F-058: island-shatter dust/updraft veil ({@code eclipse:credits_collapse}), sent by {@code CreditsShatterAct} at the island center. */
    public static final ResourceLocation CUE_CREDITS_COLLAPSE = cue("credits_collapse");
    /** F-056: black-hole accretion maw ({@code eclipse:black_hole_maw}), re-fired on its runtime cadence by {@code CreditsBlackHoleAct}. */
    public static final ResourceLocation CUE_BLACK_HOLE = cue("black_hole");
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
     * F-081: Tyrant statue idle aura ({@code eclipse:boss/tyrant_statue_idle}) — a slow
     * ember orbit up the statue column + faint crown sparks so the statue reads as
     * INTERACTIVE ("strike me"). Sent by {@code TyrantStatue.ensureArmed} on its 40t
     * armed-lair cadence; the asset runs 200t and 40 divides 200, so re-sends are
     * silent dedup no-ops mid-run and the loop sustains seamlessly (the
     * {@link #CUE_TYRANT_FOG_ARMS} cadence law). LAYER law: the server keeps stamping
     * the vanilla spark-spiral baseline for photon-less clients.
     */
    public static final ResourceLocation CUE_TYRANT_STATUE_IDLE = cue("tyrant_statue_idle");
    /**
     * FX-Wave-10: Fog Tyrant storm-step VANISH beat ({@code eclipse:boss/tyrant_step_out})
     * — the fog fold gulping the body: inward shell motes, a swelling indigo core that
     * snaps shut with an electric fleck burst, and a floor dust skirt. Fired by
     * {@code FogTyrantEntity.maybeStartStormStep} at body center (+1.5). LAYER law:
     * the shipped {@code fogBurstFx} CLOUD puffs stay the photon-less baseline.
     */
    public static final ResourceLocation CUE_TYRANT_STEP_OUT = cue("tyrant_step_out");
    /**
     * FX-Wave-10: Fog Tyrant storm-step REAPPEAR beat ({@code eclipse:boss/tyrant_step_in})
     * — the fold bursting open on the flank: expanding fog shell, ground shock ring,
     * short wisp pillar and falling electric embers. Fired by
     * {@code FogTyrantEntity.executeStormStep} at the destination (+1.5); same LAYER law.
     */
    public static final ResourceLocation CUE_TYRANT_STEP_IN = cue("tyrant_step_in");
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

    // NEWFX-B — altar, souls & ceremonies (PLAN-NEWFX §2 B1–B5). Rows registered by the
    // client-only registrar `veilfx/CeremonyPhotonFxRows`; assets generated by
    // `tools/photon/ceremony_fx.py`. All five are rare, moment-grade cues (no
    // high-frequency sender anywhere near them — frequency law satisfied by seam).
    /**
     * NEWFX-B1: dawn-toll sky bloom ({@code eclipse:dawn_toll_bloom}) — three god-ray
     * petals opening overhead in sync with the ceremony's 3×{@code TOLL_SPACING_TICKS}
     * descending bells (the pacing is staged INSIDE the asset via start delays). Sent by
     * {@code drama/DawnCeremony.dawnToll} once per online player on the ENTITY lane,
     * addressed to that player ONLY (personal sky ceremony —
     * {@code PacketDistributor.sendToPlayer}, never the range broadcast: N clustered
     * players must not stack N×N blooms). reducedFx skips the whole row client-side
     * (ceremony law: reduced players keep the pre-plan bells-only dawn).
     */
    public static final ResourceLocation CUE_DAWN_TOLL = cue("dawn_toll");
    /**
     * NEWFX-B2: Starfall Rebirth ceremony ({@code eclipse:rebirth_starfall}) — 5–7 sky
     * star-streaks converge into the reborn player, an indraw shell collapses to a
     * blinding seam, then a wing-shell of violet fire snaps open and rains ash-glitter.
     * Sent by {@code rebirth/RebirthService.ceremony} on the ENTITY lane (target = the
     * reborn player, range 64); {@code a} = the new rebirth count (informational).
     * REPLACES the old vanilla TOTEM/REVERSE_PORTAL/END_ROD spam, which the seam removed
     * outright — photon-less clients get the {@code eclipse:rebirth_ring} Quasar leg.
     */
    public static final ResourceLocation CUE_REBIRTH_CEREMONY = cue("rebirth_ceremony");
    /**
     * NEWFX-B3: altar offering rejection tell ({@code eclipse:offering_gutter}) — the
     * altar flame shrinks to a cold ember, coughs ONE falling gray ash puff and two dim
     * violet wisps retreat into the stone. The anti-climax to the swallow's climax: sent
     * by BOTH "already offered" refusal branches of
     * {@code ritual/AltarBlockEntity.handleOffering} (pre-check AND post-
     * {@code acceptWithValue} empty), position lane at the altar crown, range 32.
     * Values/duplicate outcomes stay secret — the gutter is outcome-blind.
     */
    public static final ResourceLocation CUE_OFFERING_REJECT = cue("offering_reject");
    /**
     * NEWFX-B4: permanent-death soul departure ({@code eclipse:ghost_soul_departure}) —
     * a pale mist silhouette peels off the corpse, holds a kneel beat, then is drawn
     * skyward as a stretching soul-ribbon that tears with a faint glitch pop. Sent by
     * {@code lives/LifecycleEvents} from the exact ban-at-0-hearts branch (the
     * {@code BanService.ban} call for a FINAL death only — plain deaths stay silent),
     * position lane at the corpse, range 64: bystanders finally SEE a permanent death
     * differ from a normal one.
     */
    public static final ResourceLocation CUE_GHOST_DEPARTURE = cue("ghost_departure");
    /**
     * NEWFX-B5: revive-ritual completion thunderbloom ({@code eclipse:
     * revive_thunderbloom}) — a white beam-collapse into the sigil that re-erupts as a
     * ground-hugging ring of violet lightning filaments plus rising heart motes; the
     * global thunder SOUND finally has its picture. Sent by
     * {@code ritual/ReviveRitual.succeed} beside the thunder cue, position lane at the
     * altar crown, range 96 (the asset covers the witness circle — no second cue).
     */
    public static final ResourceLocation CUE_REVIVE_COMPLETE = cue("revive_complete");

    // NEWFX-A progression & personal-celebration cues (PLAN-NEWFX §2 A1–A5). Rows
    // registered by the client-only registrar `veilfx/ProgressionPhotonFxRows`; assets
    // generated by `tools/photon/newfx_a_fx.py`.
    /**
     * NEWFX-A1: Decree Sigil Burst ({@code eclipse:quest_sigil_burst}) — quest-completion
     * celebration on the credited player. ENTITY lane ({@link FxPayloads#sendFxEntityEvent},
     * sent by {@code QuestEngine.feedback} beside the completion chime); {@code a} = the
     * goal's {@code GoalSpec.Kind} ordinal (0 = MAIN → large variant + one-beat light
     * pillar), {@code b} = 0. Team completions fire once per credited online player —
     * dedup-free because the entity anchors differ.
     */
    public static final ResourceLocation CUE_QUEST_COMPLETE = cue("quest_complete");
    /**
     * NEWFX-A2: Collection Tier Halo ({@code eclipse:collection_tier_halo}) — world-side
     * tier-up halo on the collector. ENTITY lane (sent by
     * {@code CollectionsService.applyTierGrant} beside the toast payload); {@code a} = the
     * freshly granted tier number (client scale ladder; tier ≥ 4 adds a brief gold rain),
     * {@code b} = 0.
     */
    public static final ResourceLocation CUE_COLLECTION_TIER = cue("collection_tier");
    /**
     * NEWFX-A3: Skill Spark Column ({@code eclipse:skill_spend_spark} Quasar +
     * {@code eclipse:skill_spend_glint} Photon garnish) — deliberately small point-spend
     * accent. ENTITY lane (sent by {@code SkillService.buyNode} OK branch beside the
     * SKILL_LEVELUP sound, throttled server-side to ≤ 1 cue/player/second — spends can be
     * rapid); {@code a} = the bought node's point cost (client glint scale), {@code b} = 0.
     */
    public static final ResourceLocation CUE_SKILL_SPEND = cue("skill_spend");
    /**
     * NEWFX-A4: Landmark Discovery Flare ({@code eclipse:landmark_flare}) — compass-rose
     * reveal over the freshly charted site. POSITION lane at the landmark center (range
     * 128 — everyone nearby shares the reveal), sent by the
     * {@code LandmarkDiscoveryService} sweep call site ({@code discover(server, id)} keeps
     * its signature; dev force-charts stay FX-less). {@code a}/{@code b} = 0.
     */
    public static final ResourceLocation CUE_LANDMARK_DISCOVERED = cue("landmark_discovered");
    /**
     * NEWFX-A4 echo half: the discoverer's small personal glint ({@code eclipse:
     * landmark_echo}). ENTITY lane on the discovering player, sent one line after
     * {@link #CUE_LANDMARK_DISCOVERED}. The row is a Photon-only garnish (Quasar leg
     * {@code null}) BY DESIGN: reducedFx/photon-less clients get no echo per the A4
     * reduced spec — the shared flare already carries the moment.
     */
    public static final ResourceLocation CUE_LANDMARK_ECHO = cue("landmark_echo");
    /**
     * NEWFX-A5: Catalyst Handover ({@code eclipse:wizard_catalyst_handover}) — shard
     * indraw + fuse flash + star-trail drop over Orin's fetch-quest trade. ENTITY lane
     * anchored on the wizard (sent by {@code WizardOrinEntity.tryQuestTurnIn} success
     * branch; the vanilla END_ROD puff stays as the photon-less floor); {@code a} = 0
     * reserved, {@code b} = 0. ReducedFx clients keep the vanilla baseline only (the
     * row's leg quality-gates its Quasar half).
     */
    public static final ResourceLocation CUE_WIZARD_CATALYST = cue("wizard_catalyst");

    // NEWFX-C world-event & contest cues (PLAN-NEWFX §2 C1–C5). Rows registered by the
    // client-only registrar `veilfx/WorldEventPhotonFxRows`; assets generated by
    // `tools/photon/worldevents_fx.py`. All five triggers are rare event moments
    // (boss summons, contract windows, minigame lifecycle, supply drops, first
    // dungeon discoveries) — frequency law satisfied by seam.
    /**
     * NEWFX-C1: boss Summon Beacon ({@code eclipse:boss_summon_beacon_<kind>}) — a
     * mile-high hair-thin light column at the summon site, readable disc-wide. Sent by
     * {@code BossPayloads.sendIntro} as one ADDITIONAL position-lane send with
     * dimension-wide range (the 96-block {@link #CUE_BOSS_INTRO_SHOCKWAVE} stays
     * untouched); {@code a} = boss kind ordinal (0 Herald / 1 Ferryman / 2 Fog Tyrant /
     * 3 Rift Warden — palette tint, clamped client-side), {@code b} = 0. The row's leg
     * distance-scales the column's X/Z width so far cameras still resolve the hairline;
     * reducedFx keeps the Quasar pillar leg (distant players still get the info).
     */
    public static final ResourceLocation CUE_SUMMON_BEACON = cue("boss_summon_beacon");
    /**
     * NEWFX-C2: contract Omen Ripple ({@code eclipse:contract_omen_ripple} open /
     * {@code _release} close) — the crimson ankle-height world ring of the dread and its
     * gray exhale. Sent by {@code ContractService} per ONLINE player at THAT player's own
     * position ({@code FxPayloads.sendFxEventTo} — the omen is everywhere, leaking
     * nothing): {@code announceOmen} with {@code b} = 0 (open) and the shared
     * {@code finishWindow} teardown with {@code b} = 1 (release — every resolution path
     * funnels there). reducedFx skips the row entirely client-side (shake + music + text
     * already carry it; anonymity design keeps text primacy).
     */
    public static final ResourceLocation CUE_CONTRACT_OMEN = cue("contract_omen");
    /**
     * NEWFX-C3a: minigame Gate Fanfare / collapse ({@code eclipse:minigame_gate_fanfare}
     * / {@code _collapse}) — the portal frame igniting edge-running light at event open,
     * unwinding to one point at close. Sent by {@code MinigameService.start} (portal
     * spawn spot, {@code b} = 0) and {@code beginClosing} ({@code b} = 1), position lane
     * at the portal frame center, range 96. reducedFx keeps the Quasar half only (the
     * leg quality-gates the Photon spawn via the bridge).
     */
    public static final ResourceLocation CUE_MINIGAME_GATE = cue("minigame_gate");
    /**
     * NEWFX-C3b: race Finish Ribbon ({@code eclipse:race_finish_ribbon} /
     * {@code _gold}) — the start/finish gantry flashes and sheds a checkered light-ribbon
     * spiral. Sent by {@code LegacyRace.finishRacer}, position lane at the finish line,
     * range 128; {@code a} = podium position (1 = the gold-burst variant), {@code b} = 0.
     * The leg forces {@code allowMulti}: two finishers inside one asset lifetime share
     * the anchor. reducedFx plays the Quasar ribbon for position 1 only.
     */
    public static final ResourceLocation CUE_RACE_FINISH = cue("race_finish");
    /**
     * NEWFX-C4: Supply Herald ({@code eclipse:supply_herald}) — a patch of sky shimmers,
     * tears a slit of white and coughs one falling ember streak ~3 s BEFORE the crate +
     * marker appear on that line. Sent by {@code SupplyBeacon.drop} at {@code surfacePos}
     * (the drop body is deferred {@code SupplyBeacon.HERALD_LEAD_TICKS}), position lane,
     * dimension-wide range — coordinates stay secret because the visual is at altitude
     * (the row's leg re-anchors at surface+70), findable exactly like the beam.
     * reducedFx skips the pre-beat (the beam remains the announcement).
     */
    public static final ResourceLocation CUE_SUPPLY_HERALD = cue("supply_incoming");
    /**
     * NEWFX-C5 one-shot: Dungeon Maw Breath ({@code eclipse:dungeon_maw_breath}) — the
     * entrance exhales a slow bank of cold dust plus two eye-glint sparks deep in the
     * dark. Sent by {@code worldgen/structure/DungeonDiscovery} when the FIRST player
     * comes within its discovery radius of a deterministic
     * {@code UndergroundSites.sitesFor} anchor (persisted per site id), position lane at
     * the site anchor, range 48. reducedFx keeps the Quasar dust leg only.
     */
    public static final ResourceLocation CUE_DUNGEON_FOUND = cue("dungeon_found");
    /**
     * NEWFX-C5 loop: dungeon maw idle breath ({@code eclipse:dungeon_maw_idle}). Loop
     * row — WINDOWED-only, never payload-fired; driven client-side by
     * {@code WorldEventPhotonFxRows.DungeonMawIdle} off the same deterministic anchor
     * set, gated on the {@code dungeon:<siteId>} unlock key synced via
     * {@code UnlockSync} (the A6 landmark precedent). Photon-first REPLACE with a Quasar
     * stand-in; released unconditionally under reducedFx (loop law).
     */
    public static final ResourceLocation CUE_DUNGEON_MAW_IDLE = cue("dungeon_maw_idle");
    /**
     * F-092: rim-mountain recede dust curtain + low rumble ({@code eclipse:rim_recede}),
     * fired ONCE per player (overworld only) at the expansion RELEASE moment by
     * {@code ExpansionBorderFx}'s gate release — {@code pos} = the nearest point of the
     * OLD rim to that player ({@code FxPayloads.sendFxEventTo}, leaking nothing beyond
     * the already-synced ring radius), {@code a} = the old ring radius (informational),
     * {@code b} = 0. Accompanies the {@code SoftBorder.releaseGrowthHold} lerp that
     * glides the {@code RimMountainSilhouette} ring (and the border) outward. Photon-less
     * clients get the {@code growth_dust_wall} Quasar leg (row in
     * {@code WorldEventPhotonFxRows}).
     */
    public static final ResourceLocation CUE_RIM_RECEDE = cue("rim_recede");

    // NEWFX-D — client atmosphere & transit (PLAN-NEWFX §2 D1–D5). The package is wire-free
    // by design: D1/D4 are client-latched one-shots spawned directly through
    // PhotonBridge/QuasarSpawner (no cue crosses the wire), D2 is an entity-attached loop on
    // the LOCAL player (rows are position-anchored — the CUE_GROWTH_RIDER law — so it rides
    // PhotonBridge.ensureAttachedFx, no cue: the PH-SOCIAL precedent) and D3 needs one loop
    // per rift anchor (the STORM_CROWN_HALO "not a registry row" law — per-anchor
    // LoopHandles in veilfx/rift/RiftDrawIn). Only D5's single wind-ribbon fits the registry
    // loop lane; its row lives in the package registrar `veilfx/AtmospherePhotonFxRows`.
    /**
     * NEWFX-D5: storm-outrunner wind ribbon ({@code eclipse:storm_outrunners}) — ONE torn
     * horizontal gray ribbon whipping past at head height inside the 60→20 block outside-
     * approach band. Loop row — WINDOWED-only, never payload-fired; driven client-side by
     * {@code stormfx/StormApproachFx} off {@code StormInteriorFx.approachAmount()}
     * (engage &gt; 0.5, release &lt; 0.3; re-anchored by release + re-ensure as the player
     * moves). The Quasar outrunner-wisp cadence is the photon-less baseline and is spawned
     * by the same controller, NOT by this row (the row is Photon-only garnish).
     */
    public static final ResourceLocation CUE_STORM_OUTRUNNERS = cue("storm_outrunners");

    // F-034/F-033 — the storm near-field LOD-handover suite. Rows registered by the
    // client-only registrar `veilfx/StormNearfieldFxRows`; assets generated by
    // `tools/photon/storm_nearfield_fx.py`; all four are driven client-side by
    // `stormfx/StormNearfieldFx` (the wire never fires them today — the cue ids exist
    // so the rows live in the shared table and the shockwave stays server-fireable).
    /**
     * F-034: horizontal fog streaks racing around the storm wall. Loop row —
     * WINDOWED-only; {@code stormfx/StormNearfieldFx} owns the 150–250-block handover
     * window and the live emission blend.
     */
    public static final ResourceLocation CUE_STORM_NEARFIELD_WISPS = cue("storm_nearfield_wisps");
    /** F-034: ground-hugging cloud shreds + grit at the wall foot. Loop row — WINDOWED-only. */
    public static final ResourceLocation CUE_STORM_GROUND_SCUD = cue("storm_ground_scud");
    /** F-034: three standing updraft mote columns inside the wall. Loop row — WINDOWED-only. */
    public static final ResourceLocation CUE_STORM_UPDRAFT_MOTES = cue("storm_updraft_motes");
    /**
     * F-033 stage 2: the burst shockwave ring, fired ONCE at the release moment of a
     * storm explosion. One-shot row with a custom leg — {@code a} = executor scale
     * (storm radius / the asset's authored reference radius 24), {@code b} unused.
     */
    public static final ResourceLocation CUE_STORM_BURST_SHOCKWAVE = cue("storm_burst_shockwave");

    // V7-SIGCOMP — the FX-STYLE-GUIDE.md §5 signature compositions. Rows registered by
    // the client-only registrar `veilfx/SignaturePhotonFxRows`; assets generated by
    // `tools/photon/sig_fx.py` into the new `fx/sig/` folder (§4 naming law). GOLD RUSH
    // (C2) and SANCTUM BLOOM (C1) are deliberately wire-free: both are client-latched
    // from already-shipped payloads (podium LAND transition, CUE_COLLECTION_TIER row,
    // FX_ALTAR_LEVELUP ceremony) via `veilfx/SignatureCompositions`.
    /**
     * V7-SIGCOMP C11: CROWN VERDICT — the boss defeat coda (S-MAX, world indraw → gold
     * white-out + double-pulse shockwave → gold ash rain + grade exhale). Fired at each
     * boss's collapse "money beat" — Herald {@code shatter}, Ferryman final bell toll,
     * Fog Tyrant thunderclap, Rift Warden {@code implode} — replacing/upgrading the
     * scattered per-boss defeat particles into ONE composition. {@code a} = boss kind
     * ordinal (0 Herald / 1 Ferryman / 2 Fog Tyrant / 3 Rift Warden — informational),
     * {@code b} = 1 → the host seam already provides its own indraw (the Tyrant's shipped
     * {@link #CUE_TYRANT_DEATH_IMPLOSION}) so the composition plays its coda-only form.
     */
    public static final ResourceLocation CUE_SIG_CROWN_VERDICT = cue("sig_crown_verdict");
    /**
     * V7-SIGCOMP C10: DEEP RUMBLE — the sub-visual subterranean dread bed (ceiling dust +
     * pebble hops + 1% frame breathing; the composition IS the rumble sound, visuals
     * garnish it). Loop row — WINDOWED-only, never payload-fired; driven client-side by
     * {@code client/drama/DeepRumbleFx} over its three windows (Fog Tyrant lair
     * proximity, the Ferryman arena dimension, the Backrooms).
     */
    public static final ResourceLocation CUE_SIG_DEEP_RUMBLE = cue("sig_deep_rumble");

    // PH-IMPROVE-2 — the PHOTON-QUALITY.md §3 gap backlog (never-shipped IDEAS-*.md
    // concepts). Assets generated by `tools/photon/backlog_fx.py`; rows live in the
    // owning registrars named per cue. Deliberately NO cues for the backlog's other
    // seams: `riss_maw_snap` rides the existing CUE_RISS_SCHLAG leg (delayed second
    // spawn), the mob loops (revenant ribbons / glitch drip / deckhand flames) are
    // PhotonMobFx attach rows (zero wire), `intro_storm_wall` is a per-storm windowed
    // loop latched off the shipped vortex storm payloads + lightning beats
    // (stormfx/IntroStormWallFx — the STORM_CROWN_HALO "not a registry row" law),
    // `credits_contrail` attaches client-locally to the credits flyers
    // (client/credits/CreditsContrailFx) and `era_dust_motes` is a player-scoped
    // windowed loop inside the xbox dims (client/xbox/EraDustMotes, the D2 pattern).
    /**
     * PH-IMPROVE-2 (IDEAS-mobs #6): shadow-bolt detonation flower ({@code eclipse:
     * shadow_bolt_impact}) — REVERSE_SUB dark rip + ADD violet shards + 4-beam raycast
     * micro-cross. Sent by {@code ShadowBoltProjectile.burst} (impact AND timeout)
     * beside the shipped WITCH/REVERSE_PORTAL pops, position lane, range 48. The row's
     * leg forces {@code allowMulti=true}: a 3-bolt fan can strike the same wall block
     * within 2 ticks and the default dedup would eat the siblings.
     */
    public static final ResourceLocation CUE_SHADOW_BOLT_IMPACT = cue("shadow_bolt_impact");
    /**
     * PH-IMPROVE-2 (IDEAS-events #8): intro SUNRISE god-ray ribbons ({@code eclipse:
     * intro_sunrise_rays}) — 4 staggered ara ribbons climbing sunward off the island rim
     * + rim motes, 230t one-shot spanning ramp + linger. Sent by {@code IntroSequence.
     * beginSunrise} at the altar anchor (dimension-wide, the FX_SHOCKWAVE burst
     * precedent); the asset's baked 20t first-ray delay matches
     * {@code SUNRISE_BLOOM_DELAY_TICKS} so ray one and the warm screen bloom arrive
     * together. Replay {@code SUNRISE} sends the same cue.
     */
    public static final ResourceLocation CUE_INTRO_SUNRISE = cue("intro_sunrise");
    /**
     * PH-IMPROVE-2 (IDEAS-boss #10): Fog Tyrant P3 fog-arm mesh tendrils ({@code
     * eclipse:boss/tyrant_fog_arms}) — model particles emitted along the shipped
     * {@code eclipse:item/fog_tendril} claw mesh, precessing + breathing. ENTITY lane
     * (the rig rides the stalking boss); sent at the P3 transition in {@code
     * FogTyrantEntity.updatePhase} and re-fired every 100t from the P3 fight tick —
     * each re-send is a silent dedup no-op while the 200t runtime lives and 100 divides
     * 200, so the sustain is seamless (the spec's 160t cadence would gap 120t under the
     * absorb-only CACHE dedup). Entity death auto-kills it: the death implosion never
     * fights a live arm rig.
     */
    public static final ResourceLocation CUE_TYRANT_FOG_ARMS = cue("tyrant_fog_arms");
    /**
     * PH-IMPROVE-2 (IDEAS-world #6a, Option B): dragon-death crack light-bleed
     * ({@code eclipse:end_crack_bleed}) — 3 splayed HDR bleed shafts + seam-strip embers
     * per crack-race step. Sent by {@code EndShatterSequence} one line BEFORE each race
     * step's {@code FX_RIFT_OPEN} (same flash pos, range 256): the row's leg records the
     * bleed so {@code RiftFx.openRift} retires its generic {@code EXPANSION_RIFT_GLOW}
     * for that tear (REPLACE-by-suppression; photon-less clients keep the full shipped
     * rift stack). Race steps are 4t apart at different BlockPos — dedup is a non-issue.
     */
    public static final ResourceLocation CUE_END_CRACK = cue("end_crack");
    /**
     * PH-IMPROVE-2 (IDEAS-world #10): Orin's observatory hearth ambience ({@code
     * eclipse:wizard_hearth}) — gusty chimney sparks + one rising smoke wisp + interior
     * lantern motes. Loop row — WINDOWED-only, never payload-fired; driven client-side
     * by {@code client/wizard/ObservatoryAmbience} off the client-derivable summit
     * anchor (disc-map mountain center + the dome-cap copper probe), 48/60 hysteresis.
     */
    public static final ResourceLocation CUE_WIZARD_HEARTH = cue("wizard_hearth");

    /**
     * F-053: Herald spawn-cutscene light+ash column ({@code eclipse:boss/herald_summon_pillar})
     * at the summon point — the announcement beat's physical source. Sent by
     * {@code sequence.HeraldSummonSequence}, position lane, range 128. Photon-less clients
     * keep the {@code altar_pillar} Quasar shaft (LAYER row).
     */
    public static final ResourceLocation CUE_HERALD_SUMMON_PILLAR = cue("herald_summon_pillar");
    /**
     * F-053: Herald spawn-cutscene rune bands ({@code eclipse:boss/herald_glyph_swirl}) —
     * two counter-rotating glyph rings around the column. Sent TWICE by
     * {@code sequence.HeraldSummonSequence} (arming beat + materialisation); the second
     * send lands 100+ ticks after the first, well past the 140t runtime, so the CACHE
     * dedup never eats it. Position lane, range 128.
     */
    public static final ResourceLocation CUE_HERALD_GLYPH_SWIRL = cue("herald_glyph_swirl");

    // F-038/F-039 wand spell-system cues (assets from `tools/photon/wand2_fx.py`, rows in
    // the client-only registrar `client/wand/WandPhotonFxRows` — all Mode.LAYER garnish;
    // the server-side Quasar/vanilla compositions in WandSpellEffects stay the baseline).
    /** Umbra-Lanze endpoint void implosion ({@code eclipse:wand_umbra_implosion}); pos = beam end. */
    public static final ResourceLocation CUE_WAND_UMBRA = cue("wand_umbra");
    /** Ereignishorizont vortex ({@code eclipse:wand_event_horizon}); {@code a} = durationTicks. */
    public static final ResourceLocation CUE_WAND_HORIZON = cue("wand_horizon");
    /** Sonnenkern solar impact ({@code eclipse:wand_sonnenkern}); {@code a} = telegraphTicks (client setDelay). */
    public static final ResourceLocation CUE_WAND_SONNENKERN = cue("wand_sonnenkern");
    /** Inferno fire-storm pillar ({@code eclipse:wand_inferno_pillar}); {@code a} = durationTicks. */
    public static final ResourceLocation CUE_WAND_INFERNO = cue("wand_inferno");
    /** Sternenschild dome ({@code eclipse:wand_star_dome}); ENTITY lane on the caster. */
    public static final ResourceLocation CUE_WAND_SCHILD = cue("wand_schild");
    /** Himmelsgericht finale lance ({@code eclipse:wand_judgment_finale}); {@code a} = delay ticks. */
    public static final ResourceLocation CUE_WAND_GERICHT = cue("wand_gericht");

    // FERRYMAN2 finale-arc cues (assets from `tools/photon/ferryman2_fx.py`, rows in the
    // client registrar `veilfx/FerrymanFinaleFxRows`). Senders live in
    // `ferryman.finale.*` and `FerrymanEntity`.
    /** F-044 dawn rift over the center island ({@code eclipse:day_rift_maw}); ~560t one-shot. */
    public static final ResourceLocation CUE_DAY_RIFT_MAW = cue("day_rift_maw");
    /**
     * F-045 portal-interior soul veil ({@code eclipse:portal_soul_veil}); 100t one-shot
     * re-fired on the gate's 80t sustain cadence. {@code a} = the gate's yaw in degrees
     * (custom leg aligns the flat veil plane with the door).
     */
    public static final ResourceLocation CUE_PORTAL_VEIL = cue("portal_veil");
    /** F-046 arena fog-bank segment ({@code eclipse:arena_mist_wall}); {@code a} = wall yaw. */
    public static final ResourceLocation CUE_ARENA_MIST = cue("arena_mist");
    /** F-046b Seelenernte telegraph ring ({@code eclipse:ferry_harvest_ring}); 44t one-shot. */
    public static final ResourceLocation CUE_FERRY_HARVEST = cue("ferry_harvest");
    /** F-046b Ruderschlag-Welle crest ({@code eclipse:ferry_wave_crest}); {@code a} = boss yaw. */
    public static final ResourceLocation CUE_FERRY_WAVE = cue("ferry_wave");
    /** F-045b gate-breach wisp burst ({@code eclipse:wisp_gush}); {@code a} = gate yaw. */
    public static final ResourceLocation CUE_WISP_GUSH = cue("wisp_gush");

    // F-070 wand spell VISUAL OVERHAUL cues (assets from `tools/photon/wandfx2_fx.py`,
    // rows in the NEW client registrar `client/wand/WandFx2PhotonRows` — all Mode.LAYER
    // garnish over the untouched Quasar/vanilla compositions in WandSpellEffects /
    // WandPowers; refused Photon spawns change nothing).
    /**
     * F-070 phase-1 muzzle flash at the casting hand, fired by
     * {@code WandPowers.castFlourish} on EVERY successful cast. {@code a} = path id
     * ({@code WandPath.id()}), {@code b} = spell tier 1–5 — the row picks the per-path
     * asset and tier-scales the executor so capstone casts visibly flare bigger.
     */
    public static final ResourceLocation CUE_WANDFX2_MUZZLE = cue("wandfx2_muzzle");
    /**
     * F-070 Feuerball flight comet ({@code eclipse:wandfx2_glut_comet}); pos = launch
     * point, {@code a}/{@code b} = X/Y Euler degrees rotating the asset's local +Z onto
     * the cast ray (the {@code heartTheftArc} aim convention).
     */
    public static final ResourceLocation CUE_WANDFX2_GLUT_COMET = cue("wandfx2_glut_comet");
    /**
     * F-070 shared GLUT detonation ({@code eclipse:wandfx2_glut_burst}) — Feuerball
     * impact, Eruptionslinie steps, Flammenfächer mid-arc. {@code a} = blast radius in
     * blocks (asset authored at ~3; the row scales), re-sent per step with allowMulti.
     */
    public static final ResourceLocation CUE_WANDFX2_GLUT_BURST = cue("wandfx2_glut_burst");
    /**
     * F-070 Aschesturm channel zone ({@code eclipse:wandfx2_glut_aschesturm}); ~60t ash
     * bank baked to the authored durationTicks default. {@code a} = zone radius
     * (authored ~6; the row scales).
     */
    public static final ResourceLocation CUE_WANDFX2_GLUT_ASCHESTURM = cue("wandfx2_glut_aschesturm");
    /**
     * F-070 Gravitationsbrunnen channel well ({@code eclipse:wandfx2_riss_well}); ~80t
     * orbital disc baked to the authored durationTicks default. {@code a} = well radius
     * (authored ~5; the row scales).
     */
    public static final ResourceLocation CUE_WANDFX2_RISS_WELL = cue("wandfx2_riss_well");
    /**
     * F-070 violent void crunch ({@code eclipse:wandfx2_riss_maelstrom}) — Leerensog
     * (bite baked at +6t, matching the crunch schedule), Zugfeld's yank and the
     * Schattenriss backstab (small). {@code a} = radius (authored ~4.5; the row scales).
     */
    public static final ResourceLocation CUE_WANDFX2_RISS_MAELSTROM = cue("wandfx2_riss_maelstrom");
    /**
     * F-070 Echoklinge sweep ({@code eclipse:wandfx2_riss_echo_blade}); ENTITY lane on
     * the caster, re-sent per blade beat (allowMulti). {@code a} = hit radius (authored
     * ~4.5; the row scales).
     */
    public static final ResourceLocation CUE_WANDFX2_RISS_ECHO_BLADE = cue("wandfx2_riss_echo_blade");
    /**
     * F-070 Wurzelgriff/Sternenbann binding seal ({@code eclipse:wandfx2_stern_seal});
     * ground ring + glyph stars + root filaments. {@code a} = zone radius (authored
     * ~4.5; the row scales).
     */
    public static final ResourceLocation CUE_WANDFX2_STERN_SEAL = cue("wandfx2_stern_seal");
    /**
     * F-070 Nova-Wächter guardian star ({@code eclipse:wandfx2_stern_guardian}); ENTITY
     * lane on the caster, ~120t orbit baked to the authored durationTicks default.
     * Strike beats stay the server's Quasar baseline.
     */
    public static final ResourceLocation CUE_WANDFX2_STERN_GUARDIAN = cue("wandfx2_stern_guardian");
    /**
     * F-070 Lichtsegen blessing ({@code eclipse:wandfx2_stern_bless}); ENTITY lane on
     * the caster — descending light shafts + star-mote rain + dome breath (~40t).
     */
    public static final ResourceLocation CUE_WANDFX2_STERN_BLESS = cue("wandfx2_stern_bless");

    private FxCues() {}

    /** {@code eclipse:fx/cue/<name>} — use for every new registry cue id. */
    public static ResourceLocation cue(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/cue/" + name);
    }
}
