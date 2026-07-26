package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.cutscene.SequenceReplayable;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.scores.PlayerTeam;
import net.minecraft.world.scores.Team;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * FINAL CREDITS SEQUENCE (plans_v5 C15, design IDEAS-backrooms_finale §B) — the day-14
 * ending. {@code FinaleRitual.tickVictory} calls {@link #begin} once the revive queue
 * drains, INSTEAD of {@code bringEveryoneHome} (the {@code creditsEnabled} common config
 * falls back to the old {@code finale_return} behavior).
 *
 * <p><b>Timeline</b> ({@code t} = server ticks since {@link #begin}; the F-056/057/058
 * rework — a shatter prologue in front, the auto-run cut in favor of a statically-standing
 * (and invisible) audience under a thousands-strong formation backdrop, and a black-hole
 * finale + operator-released hold replacing the old close/halt ending):</p>
 * <ol>
 *   <li>t=0 — fade to black (10t rise), music out, every player turned INVISIBLE
 *       (particle-less effect + the {@value #HIDE_TEAM} no-nametag team — F-057: nobody
 *       blocks anyone's view for the whole sequence; reverted only by the end/cleanup
 *       paths, disconnect-proof via the {@value #HIDDEN_TAG} entity tag). The epilogue
 *       beach starts pre-stamping through {@code BudgetedBlockWriter} behind the fades.
 *       The client suppresses ALL non-whitelisted HUD from the begin payload.</li>
 *   <li>t={@value #T_SHATTER_VANTAGE} — <b>F-058 shatter prologue</b>: behind black,
 *       everyone is parked (frozen, midair) at a vantage south of the sanctum island;
 *       the black releases onto the island. t={@value #T_SHATTER_BREAK} — the island and
 *       altar SHATTER: {@code CreditsShatterAct} spawns displays over the REAL sampled
 *       surface blocks (the world is never modified) that drift apart and rise; the sky
 *       contracts toward black with stars ({@code S2CCreditsSkyPayload} COLLAPSE), the
 *       eclipse sky element fades out ({@code ECLIPSE_ENDING}), the collapse Photon veil
 *       plays. t={@value #T_SHATTER_DARK} — black over the drifting debris;
 *       t={@value #T_SHATTER_END} — fragments discarded behind it, sky handed back.</li>
 *   <li>t={@value #T_SHIP} — behind black: the ghost-ship helm shot (helm double at the
 *       block-display wheel, 140t {@code credits_helm} push-in).</li>
 *   <li>t={@value #T_WHITEOUT} — fade WHITE + the disguised white loading screen
 *       ({@code eclipse:credits_white}) covering the teleport to the pre-dawn beach in
 *       {@code eclipse:epilogue}.</li>
 *   <li>t={@value #T_BEACH} — beach: {@code day_final} + the credits roll. NO auto-run
 *       (F-057): everyone is placed AT the surf line and re-frozen — a still audience
 *       under the sunrise. t={@value #T_FORMATION} — the <b>formation backdrop</b>
 *       ({@code CreditsFormationAct}): {@value CreditsFormationAct#TOTAL} displays in
 *       spiral bands / rotating rings / ascending columns, spawned
 *       {@value CreditsFormationAct#SPAWN_PER_TICK}/t, denser at the horizon and open in
 *       the view center.</li>
 *   <li>t={@value #T_LIGHTNING} — offshore lightning ladder + the {@value #FLYER_COUNT}-
 *       display debris sky (until t={@value #T_FLYERS_END}, together with the
 *       formations).</li>
 *   <li>t={@value #T_ECLIPSE_RISE} — the eclipse sphere + corona rise;
 *       t={@value #T_BURST} — it EXPLODES (shockwave, hurled debris, shake/brightness
 *       ladder, slow FOV zoom in).</li>
 *   <li>t={@value #T_WHITE_FADE} — full white; t={@value #T_WHITE_PEAK} — every display
 *       discarded behind it. t={@value #T_TRACK2} — {@code title_theme} as the white
 *       melts to black; t={@value #T_HOME} — everyone home behind it. Over black:
 *       t={@value #T_CARD_TITLE} "Minecraft Eclipse" (+ maker card),
 *       t={@value #T_CARD_RETURNS} / t={@value #T_CARD_NEXT} the RETURNS-IN pair.</li>
 *   <li>t={@value #T_FINALE_TELE} — <b>F-056 black-hole finale</b>: after ~9 s of held
 *       black, everyone is parked at a HIGH tele-vantage over the map edge (FOV crushed
 *       to {@value #FINALE_FOV_SCALE} — the orthographic read), {@code victory_theme}
 *       starts, the sky flips to SPACE (dense stars, no sun/moon;
 *       {@code S2CCreditsSkyPayload}). t={@value #T_FINALE_REVEAL} — the black releases:
 *       a giant black hole ({@code black_hole_maw} Photon + the {@code eclipse:black_hole}
 *       Veil post distortion/desaturation + {@value CreditsBlackHoleAct#COUNT} spiraling
 *       displays, {@code CreditsBlackHoleAct}) slowly eats the map while the frame drains
 *       gray. t={@value #T_FINALE_DARK} — everything melts to black;
 *       t={@value #T_FINALE_TITLE} — "Minecraft Eclipse" holds until the victory theme
 *       ends.</li>
 *   <li>t={@value #T_FINALE_HOLD} — the HOLD: completion persisted, players quietly moved
 *       home behind the black, displays gone — and the screen STAYS black (re-sent every
 *       {@value #HOLD_REFRESH_PERIOD}t) until an operator runs {@code /dev end_event}
 *       ({@link #endEvent}), which releases the fade, restores visibility/HUD/FOV and
 *       ends the run. No client close, no server halt.</li>
 * </ol>
 *
 * <p><b>Display budget</b>: hard cap {@value #DISPLAY_HARD_CAP} live displays of all kinds
 * (spawns beyond it are dropped, logged); every wave spawns budgeted; transform pushes ride
 * 4–14t interpolation windows; every act discards behind a fade and belt-and-braces in
 * {@link #endEvent}.</p>
 *
 * <p><b>Failure-safety</b> (IDEAS §B5): the machine is purely time-driven (no beat can
 * wedge it); {@link CreditsData} persists started/completed/phase — a restart mid-sequence
 * skips to the end state; joins/rejoins mid-run are re-synced into the current beat AND
 * re-hidden; a login with no live run strips leftover invisibility/team state (the
 * {@value #HIDDEN_TAG} marker) and rescues players out of the epilogue dimension.
 * {@code /dev credits skip} jumps to the fade-out beat (rehearsal); {@code /dev end_event}
 * ends any run — including the hold — immediately.</p>
 *
 * <p><b>Replay</b>: registered as {@link SequenceReplayable} id {@code "credits"} —
 * {@code /eclipsefx sequence credits <PHASE>} replays each beat FX-only (no teleports, no
 * entities, no state writes, never a close).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CreditsSequence implements SequenceReplayable {
    // --- frozen ids ---
    private static final String SEQUENCE_ID = "credits";
    private static final String PATH_HELM = "credits_helm";
    /** Mirrors {@code PortalTransitionController.STYLE_CREDITS_WHITE} (client class — never referenced here). */
    private static final String STYLE_CREDITS_WHITE = "eclipse:credits_white";
    private static final String MUSIC_FINALE_CUE = "day_final";
    /** FIN-6 track two: the title theme returns on the white→black melt. */
    private static final String MUSIC_OUTRO_CUE = "title_theme";
    /** F-056 track three: the victory theme carries the black-hole finale + title card. */
    private static final String MUSIC_VICTORY_CUE = "victory_theme";
    /** {@code MusicCues.VICTORY_THEME.durationTicks()} — frozen enum data, mirrored here. */
    private static final int VICTORY_THEME_TICKS = 3_600;

    /** The one-shot epilogue dimension (pre-dawn beach; datapack JSONs). */
    public static final ResourceKey<Level> EPILOGUE = ResourceKey.create(Registries.DIMENSION,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "epilogue"));

    // FIN-6 end cards (langdrop finale2; the Avengers gag titles are gone).
    private static final String TITLE_END = "eclipse.credits.end.title";
    private static final String TITLE_RETURNS = "eclipse.credits.end.returns";
    private static final String TITLE_NEXT = "eclipse.credits.end.next";

    // --- F-058 shatter prologue tick table (in front of the shifted IDEAS §B1 table) ---
    /** Behind black: everyone parked (frozen) at the island vantage; the black releases. */
    private static final int T_SHATTER_VANTAGE = 40;
    /** The island/altar breaks: fragment displays, collapse cue, sky contraction. */
    private static final int T_SHATTER_BREAK = 120;
    /** Black rises back over the drifting debris field. */
    private static final int T_SHATTER_DARK = 580;
    /** Fragments discarded behind the black; the sky override eases off. */
    private static final int T_SHATTER_END = 620;
    /** Everything of the original tick table below moved back by the prologue's length. */
    private static final int SHATTER_SHIFT = 600;

    // --- IDEAS §B1 tick table (shifted by {@link #SHATTER_SHIFT}) ---
    private static final int T_SHIP = 40 + SHATTER_SHIFT;
    /** {@code credits_helm.json} runs 140t from T_SHIP, whiteout rises 20t after handback. */
    private static final int T_WHITEOUT = 200 + SHATTER_SHIFT;
    /** Hands-settle wheel micro-anim: grip turn / relax-back run ticks (path t≈0.78/0.86). */
    private static final int WHEEL_SETTLE_AT = T_SHIP + 108;
    private static final int WHEEL_RELAX_AT = T_SHIP + 120;
    /** The wheel's rest spin ("caught mid-turn"); the settle nudges a few degrees off it. */
    private static final float WHEEL_REST_SPIN_DEGREES = 45.0F;
    /**
     * BD-SHIP living helm: the wheel turns continuously at {@value
     * #WHEEL_TURN_DEG_PER_TICK}°/t with two incommensurate sine rate-noise terms — it
     * drifts, hesitates and pulls like a helm riding a swell, never a metronome. Pushed
     * as 4t interpolation windows (~5–11° each) on the run clock (stateless absolute
     * poses). Every {@value #WHEEL_GLINT_PERIOD}t (≈ one 45° spoke crossing at the base
     * rate) a {@value #WHEEL_GLINT_RAMP}t sine brightness ramp rises and clears back to
     * natural light — dawn light catching a spoke.
     */
    private static final float WHEEL_TURN_DEG_PER_TICK = 0.85F;
    private static final float WHEEL_NOISE_A_DEG = 6.5F;
    private static final float WHEEL_NOISE_A_PERIOD = 46.0F;
    private static final float WHEEL_NOISE_B_DEG = 4.0F;
    private static final float WHEEL_NOISE_B_PERIOD = 117.0F;
    private static final int WHEEL_GLINT_PERIOD = 50;
    private static final int WHEEL_GLINT_RAMP = 14;
    /**
     * REPASS-BD sunrise catch: the low-east dawn spoke angle. The glint cycle is
     * phase-shifted by {@link #WHEEL_GLINT_OFFSET} so its PEAK lands where the MEAN
     * wheel angle crosses this angle (mod the wheel's 45° spoke symmetry) — the flash
     * happens when a spoke actually sweeps the sunrise line, not on a bare run clock.
     * (True noisy-crossing detection stays rejected — the rate noise double-blinks it;
     * a constant phase shift of the fixed cycle is branch-free and reads identically.)
     */
    private static final float WHEEL_GLINT_SUN_DEG = 25.0F;
    private static final int WHEEL_GLINT_OFFSET = Math.round(
            (((WHEEL_GLINT_SUN_DEG - WHEEL_REST_SPIN_DEGREES) % 45.0F + 45.0F) % 45.0F)
                    / WHEEL_TURN_DEG_PER_TICK) - WHEEL_GLINT_RAMP / 2;
    private static final int T_PORTAL = 230 + SHATTER_SHIFT;
    private static final int T_EPILOGUE = 260 + SHATTER_SHIFT;
    private static final int T_BEACH = 300 + SHATTER_SHIFT;
    /** F-057: the formation backdrop starts building shortly after the beach reveal. */
    private static final int T_FORMATION = T_BEACH + 60;
    private static final int T_LIGHTNING = 420 + SHATTER_SHIFT;
    private static final int LIGHTNING_STRIKES = 6;
    private static final int LIGHTNING_INTERVAL = 12;
    /**
     * FXTEAM CUT-CREDITS near-far ladder: per-strike distance past the surf line
     * (blocks). Far strikes get delayed, low, quiet thunder; the final strike is the
     * closest AND strongest (the intensity ramp peaks with it).
     */
    private static final int[] STRIKE_DEPTHS = {64, 10, 34, 78, 16, 6};
    /** The eclipse starts rising out of the sea (spawn + slow-rise pushes). */
    private static final int T_ECLIPSE_RISE = 700 + SHATTER_SHIFT;
    /** The debris sky + formations shrink out (20t) and are discarded before the burst. */
    private static final int T_FLYERS_END = 1750 + SHATTER_SHIFT;
    private static final int FLYER_SHRINK_TICKS = 20;
    /** The eclipse explodes; the FOV zoom and the shake/brightness ladders start. */
    private static final int T_BURST = 1900 + SHATTER_SHIFT;
    /** The final white rises (40t) into a full hold... */
    private static final int T_WHITE_FADE = 2060 + SHATTER_SHIFT;
    /** ...and behind it every display is discarded. */
    private static final int T_WHITE_PEAK = 2100 + SHATTER_SHIFT;
    /** Track two starts; the white melts to black over 160t (fade crossfade). */
    private static final int T_TRACK2 = 2160 + SHATTER_SHIFT;
    private static final int T_HOME = 2200 + SHATTER_SHIFT;
    /** "Minecraft Eclipse" over the still-held "Made by Sonic0810" (both centered). */
    private static final int T_CARD_TITLE = 2320 + SHATTER_SHIFT;
    /** The maker card fades out (roll stop payload); the title caption ends itself. */
    private static final int T_CARDS_OUT = 2430 + SHATTER_SHIFT;
    private static final int T_CARD_RETURNS = 2520 + SHATTER_SHIFT;
    private static final int T_CARD_NEXT = 2700 + SHATTER_SHIFT;

    // --- F-056 black-hole finale tick table (replaces the old close/halt ending) ---
    /**
     * Behind the long post-card black (~9 s of pure black after the NEXT card's
     * envelope): everyone parked at the tele-vantage, FOV crushed, SPACE sky armed,
     * {@code victory_theme} in, the accretion displays start building.
     */
    private static final int T_FINALE_TELE = 3640;
    /** The black releases (60t) onto the black-hole shot. */
    private static final int T_FINALE_REVEAL = 3720;
    /** The frame melts to black (160t) — the hole has eaten everything. */
    private static final int T_FINALE_DARK = 5020;
    /** "Minecraft Eclipse", centered over black, held until the victory theme ends. */
    private static final int T_FINALE_TITLE = 5200;
    /** The HOLD: completion persisted, players home, displays gone — black stays. */
    private static final int T_FINALE_HOLD = 5240;
    /** Sustained-black re-send cadence during the hold (fades clamp at 600t holds). */
    private static final int HOLD_REFRESH_PERIOD = 400;
    /** Client FOV multiplier of the tele shot (~70° × 0.25 ≈ 17° — the ortho read). */
    private static final float FINALE_FOV_SCALE = 0.25F;
    /** SPACE-sky/post intensity ladder after the tele beat (offsets from T_FINALE_REVEAL). */
    private static final int[] FINALE_SKY_STEP_AT = {300, 700, 1100};
    private static final float[] FINALE_SKY_STEP_INTENSITY = {0.6F, 0.85F, 1.0F};
    /**
     * Credits roll span (FIN-6: over twice the old scroll speed's span — the roll ends
     * at t=1780, where the maker card takes the center and holds).
     */
    private static final int ROLL_TICKS = 1480;

    // --- beach geometry (eclipse:epilogue; stamped once per run behind the black) ---
    /** Top sand layer Y; players walk on {@code +1}. */
    private static final int BEACH_Y = 63;
    private static final int BEACH_WEST_X = -24;
    /** Last sand column; water starts one block east. */
    private static final int BEACH_SAND_EAST_X = 96;
    private static final int BEACH_EAST_X = 150;
    private static final int BEACH_HALF_Z = 30;
    /** Run-lane rails (invisible barriers) — nobody drifts into the water sideways. */
    private static final int LANE_HALF_Z = 11;
    /** Legacy runner start line (now only the empty-beach fallback anchor). */
    private static final int START_X = -8;
    /**
     * F-057 (auto-run removed): everyone is placed directly AT the surf line and stands
     * still for the whole beach act — the audience row, a few blocks shy of the water.
     */
    private static final int SURF_X = BEACH_SAND_EAST_X - 8;
    /** East heading (yaw of +X). */
    private static final float RUN_YAW = -90.0F;

    // --- flying debris displays (FIN-6: the "hundreds flying" sky) ---
    /** Debris-sky population (was 24). Budgeted in at {@value #FLYER_SPAWN_PER_TICK}/t. */
    private static final int FLYER_COUNT = 288;
    private static final int FLYER_SPAWN_PER_TICK = 24;
    /** Transform push cadence (interpolation window length) for the debris sky. */
    private static final int FLYER_PUSH_STRIDE = 4;
    /** Per-flyer arc cycle length (ticks): {@value #FLYER_CYCLE_MIN} + hash × {@value #FLYER_CYCLE_VAR}. */
    private static final int FLYER_CYCLE_MIN = 260;
    private static final int FLYER_CYCLE_VAR = 140;
    /**
     * Hard cap on live credits displays of ALL kinds (flyers + eclipse + burst debris +
     * shatter fragments + formations + black-hole accretion): spawns beyond it are
     * dropped and logged — a lag spiral can never out-spawn the budget. F-057 raised it
     * for the thousands-strong backdrop (worst concurrent set ≈ flyers 288 + shadows ~45
     * + formations 1800 + eclipse 136 + burst 300 ≈ 2570).
     */
    private static final int DISPLAY_HARD_CAP = 3600;
    private static final String FLYER_TAG = "eclipse_credits_flyer";
    private static final String WHEEL_TAG = "eclipse_credits_wheel";
    /** Golden angle (radians) — tumble/placement phases: neighbors maximally de-phased. */
    static final float GOLDEN_ANGLE = 2.3999632F;
    /**
     * BD-SHIP scale envelope: flyers grow in over the first {@value #FLYER_SCALE_RAMP}
     * of each arc and shrink out over the last — arc wraps and the end-of-beat discard
     * never pop a block out of the sky. The floor is never exactly 0 (a zero scale
     * column degenerates the client interpolator's affine decomposition).
     */
    private static final float FLYER_SCALE_RAMP = 0.12F;
    private static final float FLYER_SCALE_FLOOR = 0.02F;
    /** The run's greatest hits: ship planks, altar stone, disc basalt, amethyst. */
    private static final BlockState[] FLYER_PALETTE = {
            Blocks.DARK_OAK_PLANKS.defaultBlockState(),
            Blocks.DARK_OAK_LOG.defaultBlockState(),
            Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState(),
            Blocks.DEEPSLATE_TILES.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.AMETHYST_BLOCK.defaultBlockState()};

    // --- the eclipse (FIN-6: rises on the horizon, then explodes) ---
    /**
     * Anchor column of every eclipse/burst display. Entity positions must stay inside
     * the display tracking range of players on the beach (~10 chunks), so the anchor
     * sits at x={@value}, and the visual body rides {@value #ECLIPSE_VISUAL_OFFSET_X}
     * blocks further east on the TRANSLATION (with a widened {@code view_range}) — the
     * sphere reads ~140 blocks off the surf line without ever leaving tracking range.
     */
    private static final double ECLIPSE_ANCHOR_X = 170.0D;
    private static final double ECLIPSE_VISUAL_OFFSET_X = 60.0D;
    /** Sphere center starts this far below the beach line (hidden behind the sea rim). */
    private static final double ECLIPSE_START_DEPTH = 26.0D;
    /** Total rise of the sphere center across the rise act. */
    private static final double ECLIPSE_RISE_BLOCKS = 66.0D;
    private static final double ECLIPSE_RADIUS = 13.0D;
    private static final int ECLIPSE_SHELL_COUNT = 120;
    private static final int ECLIPSE_CORONA_COUNT = 16;
    private static final float ECLIPSE_SCALE = 5.0F;
    private static final float CORONA_SCALE = 2.4F;
    /** Rise-phase push cadence (slow motion → long windows, few packets). */
    private static final int ECLIPSE_PUSH_STRIDE = 10;
    /** Burst-phase push cadence for shell + corona + hurled debris. */
    private static final int BURST_PUSH_STRIDE = 5;
    /** Debris displays hurled toward the players at the burst (budgeted spawn). */
    private static final int BURST_DEBRIS_COUNT = 300;
    private static final int BURST_SPAWN_PER_TICK = 25;
    /** Widened display view range (×64 blocks) for the far-anchored eclipse displays. */
    private static final float ECLIPSE_VIEW_RANGE = 4.0F;
    /** Cadence of the building thunder rumble (and its low shake) under the rise. */
    private static final int RUMBLE_PERIOD = 90;
    /** Cadence of the burst act's stacking white pulses + shake ladder. */
    private static final int BURST_PULSE_PERIOD = 30;
    /** FOV target of the slow zoom INTO the burst ({@code S2CCreditsFovPayload}). */
    private static final float BURST_FOV_SCALE = 0.62F;
    /** Gentle end-card holds (50t in + hold + 50t out on the client). */
    private static final int CARD_TITLE_HOLD = 50;
    private static final int CARD_RETURNS_HOLD = 80;
    private static final int CARD_NEXT_HOLD = 130;
    /**
     * FIN-6 sunrise clock: the epilogue shares the OVERWORLD day clock (DerivedLevelData),
     * so {@link #driveSunrise} steps the overworld's dayTime 1t/t from this pre-dawn
     * time-of-day, snapped behind the full white at {@link #T_EPILOGUE}. Vanilla dawn is
     * ~23960 — the sun breaks the horizon roughly 800 ticks into the roll.
     */
    private static final long SUNRISE_DAY_TICK = 23160L;
    /** The dark body of the sphere. */
    private static final BlockState[] ECLIPSE_PALETTE = {
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.BLACK_CONCRETE.defaultBlockState(),
            Blocks.COAL_BLOCK.defaultBlockState()};
    /** The glowing corona ring (brightness-overridden to full). */
    private static final BlockState[] CORONA_PALETTE = {
            Blocks.MAGMA_BLOCK.defaultBlockState(),
            Blocks.SHROOMLIGHT.defaultBlockState(),
            Blocks.GOLD_BLOCK.defaultBlockState()};

    // --- F-057 player hiding (invisible, nametag-less audience) ---
    /** Scoreboard team hiding nametags/collision for the sequence's whole cast. */
    static final String HIDE_TEAM = "eclipse_credits_hide";
    /**
     * Entity tag marking a player the credits made invisible — persisted in player NBT,
     * so the login cleanup can strip leftover hiding after a crash/restart without ever
     * guessing whether an invisibility effect belonged to the credits.
     */
    static final String HIDDEN_TAG = "eclipse_credits_hidden";

    /** Client eclipse-sky phase ids (mirrors {@code EclipseFxState.PHASE_*}; server-safe). */
    private static final int ECLIPSE_NONE = 0;
    private static final int ECLIPSE_ENDING = 3;

    private static final CreditsSequence INSTANCE = new CreditsSequence();
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** The single live run, or {@code null}. Server thread only. */
    @Nullable
    private static Run run;
    /** Tick scheduler for FX replays. Server thread only. */
    private static final List<Task> TASKS = new ArrayList<>();
    /**
     * UUIDs of wheel/flyer displays spawned THIS session; tagged joiners outside it are
     * crash strays ({@code StructureFlightFx.onEntityJoin} doctrine, POL-S-05).
     */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private CreditsSequence() {}

    // ------------------------------------------------------------------ wiring

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (REGISTERED.compareAndSet(false, true)) {
            SequenceReplayable.Registry.register(INSTANCE);
            EclipseMod.LOGGER.info("CreditsSequence registered (replay id '{}')", SEQUENCE_ID);
        }
    }

    /** Restart recovery: a world stopped mid-credits skips to the end state, never resumes. */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        CreditsData data = CreditsData.get(event.getServer());
        if (data.isStarted() && !data.isCompleted()) {
            EclipseMod.LOGGER.warn("CreditsSequence: world restarted mid-credits (phase {}) — skipping to end "
                    + "state; the close broadcast is NEVER fired after a restart", data.phase());
            data.setCompleted(true);
            data.setPhase("");
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        run = null;
        TASKS.clear();
        // In-memory only: orphaned displays that made it to disk are swept by the
        // join-time stray check on next boot (the StructureFlightFx pattern).
        LIVE_DISPLAYS.clear();
    }

    /** StructureFlightFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && (entity.getTags().contains(WHEEL_TAG) || entity.getTags().contains(FLYER_TAG)
                        || entity.getTags().contains(CreditsShatterAct.TAG)
                        || entity.getTags().contains(CreditsFormationAct.TAG)
                        || entity.getTags().contains(CreditsBlackHoleAct.TAG))
                && !LIVE_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    // ------------------------------------------------------------------ the run

    /** Human-readable beat names for the persisted phase + FX replays. */
    private enum Phase { SHATTER, HELM, WHITEOUT, BEACH, LIGHTNING, ECLIPSE, BURST, OUTRO, BLACKHOLE, HOLD }

    private static final class Run {
        final MinecraftServer server;
        final int nonce;
        int ticks;
        /** The player posed at the wheel for the helm shot. */
        @Nullable
        UUID helmPlayer;
        @Nullable
        Display.BlockDisplay wheel;
        final List<Display.BlockDisplay> flyers = new ArrayList<>();
        /** FXTEAM CUT-CREDITS ground shadows under the low debris arcs (~15% of flyers). */
        final List<ShadowPuck> shadows = new ArrayList<>();
        // FIN-6 eclipse act (list index == deterministic pose index; a failed create
        // never advances the cursor, so the alignment is an invariant).
        final List<Display.BlockDisplay> eclipseShell = new ArrayList<>();
        final List<Display.BlockDisplay> eclipseCorona = new ArrayList<>();
        final List<Display.BlockDisplay> burstDebris = new ArrayList<>();
        /** Budgeted spawn cursors (flyers / hurled burst debris). */
        int flyerCursor;
        int burstCursor;
        /** Hard-cap warning latch (log once per run, never spam). */
        boolean capWarned;
        /** Overworld dayTime baseline for {@link #driveSunrise} (set once behind the white). */
        long sunriseBase = Long.MIN_VALUE;
        /** Budgeted beach-stamp cursor (started at t=0; the epilogue beat blocks on it). */
        final BeachStamp beachStamp = new BeachStamp();
        /** F-058 island-shatter prologue stage manager. */
        final CreditsShatterAct shatter = new CreditsShatterAct();
        /** F-057 formation-backdrop stage manager (~1800 choreographed displays). */
        final CreditsFormationAct formations = new CreditsFormationAct();
        /** F-056 black-hole finale stage manager. */
        final CreditsBlackHoleAct blackHole = new CreditsBlackHoleAct();

        Run(MinecraftServer server, int nonce) {
            this.server = server;
            this.nonce = nonce;
        }

        void enter(Phase phase) {
            CreditsData.get(this.server).setPhase(phase.name());
            EclipseMod.LOGGER.info("CreditsSequence: phase {} (t={})", phase, this.ticks);
        }
    }

    /**
     * Starts the final credits sequence for the whole server. The {@code FinaleRitual}
     * revive-drain hook: returns {@code false} ONLY when the {@code creditsEnabled} config
     * kill-switch is off (the caller falls back to the pre-credits trip home) or the
     * epilogue dimension is missing; an already-running sequence returns {@code true}
     * (the ending is being handled). A completed world logs and runs again anyway
     * (dev re-fires via {@code /dev credits start}).
     */
    public static boolean begin(MinecraftServer server) {
        if (!CreditsConfig.creditsEnabled()) {
            EclipseMod.LOGGER.info("CreditsSequence: creditsEnabled=false — falling back to the plain finale return");
            return false;
        }
        if (run != null) {
            EclipseMod.LOGGER.warn("CreditsSequence: already running (t={}) — ignoring begin()", run.ticks);
            return true;
        }
        ServerLevel epilogue = server.getLevel(EPILOGUE);
        if (epilogue == null) {
            EclipseMod.LOGGER.error("CreditsSequence: dimension {} is not loaded — falling back to the plain "
                    + "finale return", EPILOGUE.location());
            return false;
        }
        CreditsData data = CreditsData.get(server);
        if (data.isCompleted()) {
            EclipseMod.LOGGER.warn("CreditsSequence: this world already rolled credits — running again (dev re-fire)");
        }
        int nonce = ThreadLocalRandom.current().nextInt(1, Integer.MAX_VALUE);
        run = new Run(server, nonce);
        data.setStarted(true);
        data.setCompleted(false);
        data.setNonce(nonce);
        run.enter(Phase.SHATTER);

        // F-058: sample the sanctum island NOW (behind the opening fade) — the shatter
        // prologue never modifies the world, it only reads the real surface blocks.
        BlockPos altar = EclipseWorldState.get(server).getSanctumAltarPos();
        if (!run.shatter.prepare(server.overworld(), altar)) {
            EclipseMod.LOGGER.warn("CreditsSequence: no sanctum island to shatter — the F-058 prologue is skipped");
        }
        // F-056: the black-hole finale always has a stage (altar column or spawn fallback).
        run.blackHole.prepare(server.overworld(), altar);

        // t=0: fade to black (held through the shatter vantage hop at T_SHATTER_VANTAGE),
        // music out, everyone hidden (F-057: invisibility without particles + the
        // no-nametag team — nobody blocks anyone's view for the whole sequence), and the
        // budgeted beach stamp starts while nobody can see it (POL-S-02).
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendBegin(player, nonce);
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(10, 60, 25, 0xFF000000));
            MusicCues.stop(player);
            if (!player.isSpectator()) {
                applyHiding(player);
            }
        }
        startBeachStamp(run, epilogue);
        EclipseMod.LOGGER.info("CreditsSequence: started for {} player(s) (nonce {})",
                server.getPlayerList().getPlayerCount(), nonce);
        return true;
    }

    /** Whether the credits phase machine is currently live. */
    public static boolean isRunning() {
        return run != null;
    }

    /**
     * GAMEMASTER skip (IDEAS §B5): jump straight to the white fade-out beat — the outro,
     * the black-hole finale and the hold still play (the hold releases via
     * {@link #endEvent}). Returns {@code false} while no run is live.
     */
    public static boolean skip(MinecraftServer server) {
        Run current = run;
        if (current == null) {
            return false;
        }
        if (current.ticks < T_WHITE_FADE) {
            discardWheel(current);
            discardFlyers(current);
            discardEclipse(current);
            current.shatter.discard();
            current.formations.discard();
            // The white fade-out beat expects the sky override gone (the shatter may
            // still own it when skipping early).
            PacketDistributor.sendToAllPlayers(new CreditsPayloads.S2CCreditsSkyPayload(
                    CreditsPayloads.S2CCreditsSkyPayload.MODE_OFF, 0.0F, 40, 0.0D, 0.0D, 0.0D));
            FxPayloads.sendEclipsePhase(server, ECLIPSE_NONE, 0.0F, 40, false);
            current.ticks = T_WHITE_FADE - 1; // the next tick executes the white fade-out beat
        }
        EclipseMod.LOGGER.info("CreditsSequence: skipped to the outro (hold ends via /dev end_event)");
        return true;
    }

    /**
     * F-056 — {@code /dev end_event}: ends the credits IMMEDIATELY, from ANY beat
     * (including the indefinite post-finale hold, its designed release). Every player is
     * un-hidden, un-frozen, handed the HUD/FOV back, faded in and returned to the
     * overworld spawn; every display of every act is discarded; completion is persisted.
     * Returns {@code false} while no run is live.
     */
    public static boolean endEvent(MinecraftServer server) {
        Run current = run;
        if (current == null) {
            return false;
        }
        CreditsData data = CreditsData.get(server);
        data.setCompleted(true);
        data.setPhase("");
        discardWheel(current);
        discardFlyers(current);
        discardEclipse(current);
        current.shatter.discard();
        current.formations.discard();
        current.blackHole.discard();
        run = null;
        ServerLevel overworld = server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            FreezeService.unfreeze(player);
            clearHiding(player);
            if (!player.isSpectator()) {
                BlockPos column = spawn.offset(2 * (returned % 5 - 2), 0, 2 * (returned / 5 % 5 - 2));
                int y = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        column.getX(), column.getZ());
                player.teleportTo(overworld, column.getX() + 0.5D, y, column.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
                returned++;
            }
            MusicCues.stop(player);
            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                    CreditsPayloads.S2CCreditsSkyPayload.MODE_OFF, 0.0F, 60, 0.0D, 0.0D, 0.0D));
            CreditsPayloads.sendFov(player, 1.0F, 40);
            CreditsPayloads.sendRoll(player, 0); // hands the HUD back (CreditsClient.onRollStopped)
            // Release the sustained hold: short black that fades itself out.
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(0, 20, 60, 0xFF000000));
        }
        FxPayloads.sendEclipsePhase(server, ECLIPSE_NONE, 0.0F, 40, false);
        EclipseMod.LOGGER.info("CreditsSequence: /dev end_event — hold released, {} player(s) returned home",
                returned);
        return true;
    }

    // ------------------------------------------------------------------ tick machine

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        tickScheduler(event.getServer());
        Run current = run;
        if (current == null) {
            return;
        }
        current.ticks++;
        int t = current.ticks;
        switch (t) {
            case T_SHATTER_VANTAGE -> beatShatterVantage(current);
            case T_SHATTER_BREAK -> beatShatterBreak(current);
            case T_SHATTER_DARK -> beatShatterDark(current);
            case T_SHATTER_END -> beatShatterEnd(current);
            case T_SHIP -> beatShip(current);
            case T_WHITEOUT -> beatWhiteout(current);
            case T_PORTAL -> beatPortal(current);
            case T_EPILOGUE -> beatEpilogue(current);
            case T_BEACH -> beatBeach(current);
            case T_ECLIPSE_RISE -> beatEclipseRise(current);
            case T_BURST -> beatBurst(current);
            case T_WHITE_FADE -> beatWhiteFade(current);
            case T_WHITE_PEAK -> beatWhitePeak(current);
            case T_TRACK2 -> beatTrackTwo(current);
            case T_HOME -> beatHome(current);
            case T_CARD_TITLE -> beatCardTitle(current);
            case T_CARDS_OUT -> beatCardsOut(current);
            case T_CARD_RETURNS -> beatCardReturns(current);
            case T_CARD_NEXT -> beatCardNext(current);
            case T_FINALE_TELE -> beatFinaleTele(current);
            case T_FINALE_REVEAL -> beatFinaleReveal(current);
            case T_FINALE_DARK -> beatFinaleDark(current);
            case T_FINALE_TITLE -> beatFinaleTitle(current);
            case T_FINALE_HOLD -> beatFinaleHold(current);
            default -> { }
        }
        // Overlapping continuous work.
        // F-058 shatter prologue: budgeted fragment spawn + drift pushes.
        if (t > T_SHATTER_BREAK && t < T_SHATTER_DARK && current.shatter.prepared()) {
            ServerLevel overworld = current.server.overworld();
            if (current.shatter.spawnRemaining()) {
                current.shatter.spawnBatch(overworld, t - T_SHATTER_BREAK);
            }
            if ((t - T_SHATTER_BREAK) % CreditsShatterAct.PUSH_STRIDE == 0) {
                current.shatter.animate(t - T_SHATTER_BREAK);
            }
            if ((t - T_SHATTER_BREAK) % RUMBLE_PERIOD == 0) {
                shatterRumble(current, t);
            }
        }
        if (t > T_SHIP && t < T_EPILOGUE && (t - T_SHIP) % 4 == 0) {
            animateWheel(current, t); // BD-SHIP: the helm never stands still on camera
        }
        if (t >= T_EPILOGUE && t <= T_WHITE_PEAK) {
            driveSunrise(current, t); // FIN-6: a real, slow sunrise across the whole roll
        }
        if (t >= T_LIGHTNING && t <= T_LIGHTNING + (LIGHTNING_STRIKES - 1) * LIGHTNING_INTERVAL
                && (t - T_LIGHTNING) % LIGHTNING_INTERVAL == 0) {
            int index = (t - T_LIGHTNING) / LIGHTNING_INTERVAL;
            beatLightningStrike(current, index);
        }
        // FIN-6 display budget: every wave below spawns ≤ its per-tick budget, never past
        // DISPLAY_HARD_CAP; every animation rides interpolation windows on a fixed stride.
        // F-057 formation backdrop (spawn → drift → shrink-out with the flyers).
        if (t >= T_FORMATION && t < T_FLYERS_END) {
            ServerLevel epilogue = current.server.getLevel(EPILOGUE);
            if (epilogue != null) {
                if (current.formations.spawnRemaining()) {
                    current.formations.spawnBatch(epilogue, t - T_FORMATION);
                }
                if ((t - T_FORMATION) % CreditsFormationAct.PUSH_STRIDE == 0) {
                    current.formations.animate(t - T_FORMATION);
                }
            }
        }
        if (t >= T_LIGHTNING && t < T_FLYERS_END && current.flyerCursor < FLYER_COUNT) {
            spawnFlyerBatch(current);
        }
        if (t > T_LIGHTNING && t < T_FLYERS_END && (t - T_LIGHTNING) % FLYER_PUSH_STRIDE == 0) {
            animateFlyers(current, t);
        }
        if (t == T_FLYERS_END) {
            shrinkOutFlyers(current);
            current.formations.shrinkOut(T_FLYERS_END - T_FORMATION, FLYER_SHRINK_TICKS);
        }
        if (t == T_FLYERS_END + FLYER_SHRINK_TICKS) {
            discardFlyers(current);
            current.formations.discard();
        }
        if (t >= T_ECLIPSE_RISE && t < T_BURST
                && current.eclipseShell.size() + current.eclipseCorona.size()
                        < ECLIPSE_SHELL_COUNT + ECLIPSE_CORONA_COUNT) {
            spawnEclipseBatch(current);
        }
        if (t > T_ECLIPSE_RISE && t < T_BURST && (t - T_ECLIPSE_RISE) % ECLIPSE_PUSH_STRIDE == 0) {
            animateEclipseRise(current, t);
        }
        if (t >= T_ECLIPSE_RISE && t < T_BURST && (t - T_ECLIPSE_RISE) % RUMBLE_PERIOD == 0) {
            eclipseRumble(current, t);
        }
        if (t > T_BURST && t < T_WHITE_PEAK && current.burstCursor < BURST_DEBRIS_COUNT) {
            spawnBurstDebrisBatch(current);
        }
        if (t > T_BURST && t < T_WHITE_PEAK && (t - T_BURST) % BURST_PUSH_STRIDE == 0) {
            animateBurst(current, t);
        }
        if (t > T_BURST && t < T_WHITE_FADE && (t - T_BURST) % BURST_PULSE_PERIOD == 0) {
            burstEscalation(current, t);
        }
        // F-056 black-hole finale: accretion spawn/pushes, maw cue cadence, sky ladder.
        if (t > T_FINALE_TELE && t < T_FINALE_HOLD) {
            ServerLevel overworld = current.server.overworld();
            if (current.blackHole.spawnRemaining()) {
                current.blackHole.spawnBatch(overworld, t - T_FINALE_TELE);
            }
            if ((t - T_FINALE_TELE) % CreditsBlackHoleAct.PUSH_STRIDE == 0) {
                current.blackHole.animate(t - T_FINALE_TELE);
            }
            if (t >= T_FINALE_REVEAL && t < T_FINALE_DARK
                    && (t - T_FINALE_REVEAL) % CreditsBlackHoleAct.MAW_CADENCE == 0) {
                fireBlackHoleMaw(current, t);
            }
            for (int step = 0; step < FINALE_SKY_STEP_AT.length; step++) {
                if (t == T_FINALE_REVEAL + FINALE_SKY_STEP_AT[step]) {
                    sendFinaleSky(current, FINALE_SKY_STEP_INTENSITY[step], 260);
                }
            }
        }
        // The HOLD: black forever (re-sent under the client fade clamp) until end_event.
        if (t >= T_FINALE_HOLD && (t - T_FINALE_HOLD) % HOLD_REFRESH_PERIOD == 0) {
            for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
                PacketDistributor.sendToPlayer(player,
                        S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
            }
        }
    }

    // ------------------------------------------------------------------ F-057 hiding

    /**
     * F-057: makes one player a ghost audience member — particle-less invisibility (no
     * expiry; removed by the cleanup paths) + the {@value #HIDE_TEAM} team (nametags off,
     * collision off, no see-friendly-invisibles ghosting) + the {@value #HIDDEN_TAG}
     * NBT-persisted marker for crash cleanup. Players already on ANOTHER team (e.g. the
     * BanService ghost team) keep it — the effect still hides their model.
     */
    private static void applyHiding(ServerPlayer player) {
        player.addEffect(new MobEffectInstance(MobEffects.INVISIBILITY,
                MobEffectInstance.INFINITE_DURATION, 0, true, false, false));
        player.addTag(HIDDEN_TAG);
        net.minecraft.server.ServerScoreboard scoreboard = player.server.getScoreboard();
        PlayerTeam team = scoreboard.getPlayerTeam(HIDE_TEAM);
        if (team == null) {
            team = scoreboard.addPlayerTeam(HIDE_TEAM);
            team.setNameTagVisibility(Team.Visibility.NEVER);
            team.setCollisionRule(Team.CollisionRule.NEVER);
            team.setSeeFriendlyInvisibles(false);
        }
        PlayerTeam existing = scoreboard.getPlayersTeam(player.getScoreboardName());
        if (existing == null) {
            scoreboard.addPlayerToTeam(player.getScoreboardName(), team);
        }
    }

    /** Reverts {@link #applyHiding} for one player (idempotent — safe on the unhidden). */
    private static void clearHiding(ServerPlayer player) {
        player.removeEffect(MobEffects.INVISIBILITY);
        player.removeTag(HIDDEN_TAG);
        net.minecraft.server.ServerScoreboard scoreboard = player.server.getScoreboard();
        PlayerTeam team = scoreboard.getPlayersTeam(player.getScoreboardName());
        if (team != null && HIDE_TEAM.equals(team.getName())) {
            scoreboard.removePlayerFromTeam(player.getScoreboardName(), team);
        }
    }

    // ------------------------------------------------------------------ F-058 shatter beats

    /**
     * t={@value #T_SHATTER_VANTAGE} — behind the opening black: everyone parked (frozen,
     * midair, invisible) at the vantage south of the sanctum island; the black releases
     * onto the still-whole island. A world without a sanctum skips the whole prologue.
     */
    private static void beatShatterVantage(Run current) {
        if (!current.shatter.prepared()) {
            current.ticks = T_SHIP - 1; // no island: straight to the helm shot
            return;
        }
        ServerLevel overworld = current.server.overworld();
        Vec3 vantage = current.shatter.vantage();
        Vec3 center = current.shatter.islandCenter();
        float yaw = (float) Math.toDegrees(Math.atan2(
                -(center.x - vantage.x), center.z - vantage.z));
        float pitch = (float) Math.toDegrees(Math.atan2(vantage.y - center.y,
                Math.sqrt(Math.pow(center.x - vantage.x, 2.0D) + Math.pow(center.z - vantage.z, 2.0D))));
        int placed = 0;
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            if (player.isSpectator()) {
                continue;
            }
            // Invisible audience: everyone can share (almost) the same seat — tiny
            // deterministic offsets only so nobody z-fights the same camera point.
            double dx = 0.7D * (placed % 3 - 1);
            double dy = 0.5D * (placed / 3 % 3);
            placed++;
            player.teleportTo(overworld, vantage.x + dx, vantage.y + dy, vantage.z, yaw, pitch);
            player.setDeltaMovement(Vec3.ZERO);
            player.fallDistance = 0.0F;
            // Midair statue seat; survives=false → the T_SHIP limbo hop auto-releases it.
            FreezeService.freeze(player, T_SHIP - T_SHATTER_VANTAGE + 40, false, 0);
            // Release the opening black onto the island (gentle 30t reveal).
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(0, 20, 30, 0xFF000000));
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} player(s) at the shatter vantage", placed);
    }

    /**
     * t={@value #T_SHATTER_BREAK} — the island BREAKS: the sampled-surface fragment
     * displays start spawning (continuous work), the collapse Photon veil fires at the
     * island center, the sky contracts toward black with stars (COLLAPSE mode) and the
     * eclipse sky element starts its slow fade-out.
     */
    private static void beatShatterBreak(Run current) {
        current.enter(Phase.SHATTER);
        ServerLevel overworld = current.server.overworld();
        Vec3 center = current.shatter.islandCenter();
        FxPayloads.sendFxEvent(overworld, FxCues.CUE_CREDITS_COLLAPSE, center, 0.0F, 0.0F, -1.0D);
        // F-058: "der Himmel zieht sich zusammen" — dome toward black, stars out...
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                    CreditsPayloads.S2CCreditsSkyPayload.MODE_COLLAPSE, 0.75F, 360,
                    0.0D, 0.0D, 0.0D));
        }
        // ...and the eclipse element itself slowly leaves the sky (no permanent rim).
        FxPayloads.sendEclipsePhase(current.server, ECLIPSE_ENDING, 0.0F, 400, false);
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(1.1F, 70));
        for (ServerPlayer player : overworld.players()) {
            player.playNotifySound(SoundEvents.END_PORTAL_SPAWN, SoundSource.MASTER, 0.9F, 0.5F);
            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER, 0.9F, 0.45F);
        }
    }

    /** A low grinding rumble under the drift (every {@value #RUMBLE_PERIOD}t of the act). */
    private static void shatterRumble(Run current, int t) {
        float progress = Mth.clamp((t - T_SHATTER_BREAK)
                / (float) (T_SHATTER_DARK - T_SHATTER_BREAK), 0.0F, 1.0F);
        for (ServerPlayer player : current.server.overworld().players()) {
            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                    0.35F + 0.25F * progress, 0.42F + 0.1F * progress);
        }
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(0.2F + 0.2F * progress, RUMBLE_PERIOD));
    }

    /** t={@value #T_SHATTER_DARK} — black rises back over the drifting debris field. */
    private static void beatShatterDark(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player,
                    S2CScreenFadePayload.sustained(50, 600, 0, 0xFF000000));
        }
    }

    /**
     * t={@value #T_SHATTER_END} — behind the black: every fragment is discarded and the
     * sky override eases off (the beach act needs the vanilla dome for its sunrise).
     */
    private static void beatShatterEnd(Run current) {
        current.shatter.discard();
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                    CreditsPayloads.S2CCreditsSkyPayload.MODE_OFF, 0.0F, 100, 0.0D, 0.0D, 0.0D));
        }
        FxPayloads.sendEclipsePhase(current.server, ECLIPSE_NONE, 0.0F, 60, false);
    }

    // ------------------------------------------------------------------ F-056 finale beats

    /** Broadcasts the SPACE sky at {@code intensity} (also drives the post pass strength). */
    private static void sendFinaleSky(Run current, float intensity, int rampTicks) {
        Vec3 hole = current.blackHole.holeCenter();
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                    CreditsPayloads.S2CCreditsSkyPayload.MODE_SPACE, intensity, rampTicks,
                    hole.x, hole.y, hole.z));
        }
    }

    /**
     * The Photon maw, re-fired on its {@value CreditsBlackHoleAct#MAW_CADENCE}t cadence
     * (the kneel-corona sustain law — re-sends inside the runtime dedup silently) at the
     * SCREEN-ALIGNED near anchor, plus the building devour-rumble.
     */
    private static void fireBlackHoleMaw(Run current, int t) {
        ServerLevel overworld = current.server.overworld();
        FxPayloads.sendFxEvent(overworld, FxCues.CUE_BLACK_HOLE,
                current.blackHole.fxAnchor(), 0.0F, 0.0F, -1.0D);
        float progress = Mth.clamp((t - T_FINALE_REVEAL)
                / (float) (T_FINALE_DARK - T_FINALE_REVEAL), 0.0F, 1.0F);
        for (ServerPlayer player : overworld.players()) {
            player.playNotifySound(SoundEvents.END_PORTAL_SPAWN, SoundSource.MASTER,
                    0.35F + 0.3F * progress, 0.4F - 0.1F * progress);
        }
    }

    /**
     * t={@value #T_FINALE_TELE} — behind the long post-card black: everyone to the HIGH
     * tele-vantage (frozen, still invisible), the FOV crushed to
     * {@value #FINALE_FOV_SCALE} (tele/ortho read), the SPACE sky armed at its first
     * intensity step, {@code victory_theme} in, the HUD re-suppressed (the cards-out
     * beat handed it back), and the accretion displays start building (continuous work).
     */
    private static void beatFinaleTele(Run current) {
        current.enter(Phase.BLACKHOLE);
        ServerLevel overworld = current.server.overworld();
        Vec3 vantage = current.blackHole.vantage();
        float yaw = current.blackHole.vantageYaw();
        float pitch = current.blackHole.vantagePitch();
        int placed = 0;
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            // Same-nonce begin re-send: CreditsClient re-suppresses the HUD, nothing else.
            CreditsPayloads.sendBegin(player, current.nonce);
            PacketDistributor.sendToPlayer(player,
                    S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
            if (!player.isSpectator()) {
                double dx = 0.7D * (placed % 3 - 1);
                double dy = 0.5D * (placed / 3 % 3);
                placed++;
                player.teleportTo(overworld, vantage.x + dx, vantage.y + dy, vantage.z, yaw, pitch);
                player.setDeltaMovement(Vec3.ZERO);
                player.fallDistance = 0.0F;
                FreezeService.freeze(player, T_FINALE_HOLD - T_FINALE_TELE + 100, false, 0);
            }
            CreditsPayloads.sendFov(player, FINALE_FOV_SCALE, 80);
            MusicCues.play(MUSIC_VICTORY_CUE, player);
        }
        sendFinaleSky(current, 0.35F, 200);
        EclipseMod.LOGGER.info("CreditsSequence: {} player(s) at the black-hole vantage", placed);
    }

    /** t={@value #T_FINALE_REVEAL} — the black releases onto the tele shot of the map. */
    private static void beatFinaleReveal(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(0, 10, 60, 0xFF000000));
        }
        fireBlackHoleMaw(current, T_FINALE_REVEAL);
    }

    /**
     * t={@value #T_FINALE_DARK} — the hole has eaten everything: the frame (already
     * drained gray by the post ladder) melts to a sustained black over 8 s; the FOV
     * eases part-way back out — the "langsames weiteres Rauszoomen" beat under the melt.
     */
    private static void beatFinaleDark(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player,
                    S2CScreenFadePayload.sustained(160, 600, 0, 0xFF000000));
            CreditsPayloads.sendFov(player, 0.4F, 200);
        }
    }

    /**
     * t={@value #T_FINALE_TITLE} — "Minecraft Eclipse", large and centered over the
     * black, held until {@code victory_theme} runs out (the F-056 contract: the card and
     * the music end together; the hold length is derived from the cue's frozen duration).
     */
    private static void beatFinaleTitle(Run current) {
        int hold = Math.max(200, T_FINALE_TELE + VICTORY_THEME_TICKS - T_FINALE_TITLE - 100);
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendGentleTitle(player, TITLE_END, hold);
        }
    }

    /**
     * t={@value #T_FINALE_HOLD} — the HOLD arms: completion persisted FIRST (a crash
     * during the hold must never replay the sequence), the accretion field discarded and
     * everyone quietly moved home behind the black — the world under the black screen is
     * already the post-credits world. The screen then STAYS black (refresh wave in
     * {@link #onServerTick}) until an operator runs {@code /dev end_event}.
     */
    private static void beatFinaleHold(Run current) {
        current.enter(Phase.HOLD);
        CreditsData data = CreditsData.get(current.server);
        data.setCompleted(true);
        current.blackHole.discard();
        ServerLevel overworld = current.server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            FreezeService.unfreeze(player);
            if (!player.isSpectator()) {
                BlockPos column = spawn.offset(2 * (returned % 5 - 2), 0, 2 * (returned / 5 % 5 - 2));
                int y = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        column.getX(), column.getZ());
                player.teleportTo(overworld, column.getX() + 0.5D, y, column.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
                returned++;
            }
            PacketDistributor.sendToPlayer(player,
                    S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
        }
        EclipseMod.LOGGER.info("CreditsSequence: HOLD armed — {} player(s) home behind the black; "
                + "/dev end_event releases it", returned);
    }

    // ------------------------------------------------------------------ beats

    /** t={@value #T_SHIP} — behind black: crew to the ship stern, helm double posed, push-in plays. */
    private static void beatShip(Run current) {
        current.enter(Phase.HELM);
        MinecraftServer server = current.server;
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("CreditsSequence: limbo missing — skipping the helm shot");
            current.ticks = T_WHITEOUT - 1;
            return;
        }
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        List<ServerPlayer> online = new ArrayList<>(server.getPlayerList().getPlayers());
        int placed = 0;
        for (ServerPlayer player : online) {
            if (player.isSpectator()) {
                continue;
            }
            if (current.helmPlayer == null) {
                // The helm double: first online living player (the egg-offerer in spirit —
                // FinaleRitual does not record the ritual starter; IDEAS §B1 fallback).
                current.helmPlayer = player.getUUID();
                player.teleportTo(limbo, -18.5D, deckY + 7, 0.5D, RUN_YAW, 4.0F);
            } else {
                // Crew behind the sterncastle on the main deck (FinaleRitual deckSpot spread).
                int x = 2 + 2 * (placed % 3);
                int z = placed / 3 % 3 - 1;
                placed++;
                player.teleportTo(limbo, x + 0.5D, deckY + 1, z + 0.5D, RUN_YAW, 0.0F);
            }
        }
        spawnWheel(current, limbo, deckY);
        // Everyone is already on the ship: LOCAL play, world-anchored at the helm double.
        // play() installs its OWN freeze and releases it on the flight-end ACK — the
        // callback re-locks everyone (survives-dimension-change) so nobody wanders off
        // the deck behind the whiteout; beatEpilogue's transport re-anchors that lock.
        CutsceneService.play(PATH_HELM, online, new Vec3(-18.5D, deckY + 7, 0.5D),
                CreditsSequence::refreezeAfterHelmShot, CutsceneService.PlayOptions.LOCAL);
        // FXTEAM CUT-CREDITS hands-settle beat (path t≈0.77 ≈ run tick 148, synced with
        // the t=0.77 "wheel" whisper — EVAL-V6-CUTBD §3 defect 5 moved the caption from
        // t=0.72/run≈141 onto the grip): the grip pull now rides the continuous rotation
        // as a deterministic offset envelope — see gripOffset() (BD-SHIP transport;
        // the CUT-CREDITS timing constants WHEEL_SETTLE_AT/WHEEL_RELAX_AT still rule).
    }

    /** Flight-end callback: keep everyone posed until the beach releases them. */
    private static void refreezeAfterHelmShot() {
        Run current = run;
        if (current == null || current.ticks >= T_EPILOGUE) {
            return;
        }
        int ttl = T_BEACH - current.ticks + 20;
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            if (!player.isSpectator()) {
                FreezeService.freeze(player, ttl, true, 0);
            }
        }
    }

    /**
     * t=200 — the shot is over: rise to white and hold (the fade hands over to the portal
     * FX). FXTEAM CUT-CREDITS retime: 36/44/20 — the rise is a touch gentler and the
     * release ends exactly at {@link #T_BEACH} (t=300), so the sunrise finishes revealing
     * the same tick {@code day_final} starts.
     */
    private static void beatWhiteout(Run current) {
        current.enter(Phase.WHITEOUT);
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(36, 44, 20, 0xFFFFFFFF));
    }

    /** t=230 — the disguised white loading screen arms (covers the dimension teleport). */
    private static void beatPortal(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(
                    S2CPortalFxPayload.Phase.ENTER, STYLE_CREDITS_WHITE, 60));
        }
    }

    /**
     * t={@value #T_EPILOGUE} — behind the white: everyone to the beach, placed directly
     * AT the surf line, facing east (F-057: the auto-run is gone — the audience stands).
     */
    private static void beatEpilogue(Run current) {
        MinecraftServer server = current.server;
        ServerLevel epilogue = server.getLevel(EPILOGUE);
        if (epilogue == null) {
            EclipseMod.LOGGER.error("CreditsSequence: epilogue dimension vanished mid-run — sending everyone home");
            discardWheel(current);
            current.ticks = T_WHITE_FADE - 1;
            return;
        }
        if (!current.beachStamp.done) {
            // The budgeted stamp had ~T_EPILOGUE ticks of cover; a saturated writer queue
            // can still leave a remainder — finish it now, never drop runners into void.
            EclipseMod.LOGGER.warn("CreditsSequence: beach stamp incomplete at arrival ({} of {} columns) "
                    + "— finishing synchronously", current.beachStamp.cursor, BeachStamp.TOTAL_COLUMNS);
            current.beachStamp.advance(epilogue, Integer.MAX_VALUE);
        }
        discardWheel(current);
        List<ServerPlayer> online = server.getPlayerList().getPlayers();
        int placed = 0;
        for (ServerPlayer player : online) {
            if (player.isSpectator()) {
                continue;
            }
            double z = Math.max(-LANE_HALF_Z + 1, Math.min(LANE_HALF_Z - 1, 2 * (placed - online.size() / 2)));
            placed++;
            // transport (not teleportTo): the helm freeze is still live — this re-anchors
            // the lock at the surf line so the rubber-band never yanks anyone back to limbo.
            FreezeService.transport(player, epilogue,
                    new Vec3(SURF_X + 0.5D, BEACH_Y + 1, z + 0.5D), RUN_YAW, 6.0F);
            player.setDeltaMovement(Vec3.ZERO);
            player.fallDistance = 0.0F;
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} player(s) on the epilogue beach", placed);
    }

    /**
     * t={@value #T_BEACH} — sunrise: music finale + credits roll. F-057 (auto-run
     * removed): the helm freeze is REPLACED by a fresh statue lock at the surf line —
     * everyone stands and watches the whole act; the formation backdrop starts building
     * at t={@value #T_FORMATION} around them.
     */
    private static void beatBeach(Run current) {
        current.enter(Phase.BEACH);
        // The formation anchor: just past the audience row, eye-height over the surf.
        current.formations.setAnchor(new Vec3(SURF_X + 2.5D, BEACH_Y + 4.0D, 0.0D));
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            MusicCues.play(MUSIC_FINALE_CUE, player);
            CreditsPayloads.sendRoll(player, ROLL_TICKS);
            if (!player.isSpectator()) {
                // Re-anchor at the surf: a fresh lock (free look-around, no walking)
                // that lasts the whole beach/eclipse/burst act. survives=false — the
                // T_HOME dimension hop would auto-release it even without the explicit
                // unfreeze there.
                FreezeService.freeze(player, T_WHITE_PEAK - T_BEACH + 60, false, 0);
            }
        }
    }

    /**
     * One offshore strike of the t=420 lightning beat, intensity 0.6→1.0 (IDEAS §B1).
     * FXTEAM CUT-CREDITS depth staggering: strike distances walk a deterministic
     * near↔far ladder ({@link #STRIKE_DEPTHS}, blocks past the surf line, sides
     * alternating), and the thunder arrives LATE by distance (~17 blocks/tick of sound
     * travel) — far bolts rumble low and quiet a beat after their flash, the climactic
     * last strike cracks close, loud and immediate.
     */
    private static void beatLightningStrike(Run current, int index) {
        if (index == 0) {
            current.enter(Phase.LIGHTNING);
            // The debris sky starts building the same tick (budgeted spawnFlyerBatch wave).
        }
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        float intensity = 0.6F + 0.4F * index / Math.max(1, LIGHTNING_STRIKES - 1);
        int depth = STRIKE_DEPTHS[index % STRIKE_DEPTHS.length];
        double x = BEACH_SAND_EAST_X + depth + hash01(index, 21) * 6.0D;
        double z = (index % 2 == 0 ? 1 : -1) * (8.0D + hash01(index, 22) * 26.0D);
        Vec3 impact = new Vec3(x, BEACH_Y + 1, z);
        FxPayloads.sendFxEvent(epilogue, FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F, -1.0D);
        // PH-EVENTS (IDEAS-events #2): the per-strike Photon beam cue — same impact, same
        // intensity in a (client maps it to executor scale). Its own cue by design, never
        // piggybacked on FX_LIGHTNING_STRIKE (that id also fires at 15t cadence during the
        // intro's LIGHTNING hold — frequency law); photon-less clients no-op on it.
        FxPayloads.sendFxEvent(epilogue, FxCues.CUE_CREDITS_STRIKE, impact, intensity, 0.0F, -1.0D);
        LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(epilogue);
        if (bolt != null) {
            bolt.moveTo(impact);
            bolt.setVisualOnly(true);
            epilogue.addFreshEntity(bolt);
        }
        // Light now, sound later: far strikes lose top end (lower pitch, softer volume).
        boolean far = depth > 40;
        float volume = (0.7F + 0.5F * intensity) * (far ? 0.72F : 1.0F);
        float pitch = (far ? 0.72F : 0.9F) + (float) hash01(index, 23) * 0.12F;
        schedule(current.server, 1 + depth / 17, () -> {
            ServerLevel level = current.server.getLevel(EPILOGUE);
            if (run != current || level == null) {
                return;
            }
            for (ServerPlayer player : level.players()) {
                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                        volume, pitch);
            }
        });
    }

    /**
     * t={@value #T_ECLIPSE_RISE} — the ECLIPSE act enters: the dark sphere + glowing
     * corona spawn budgeted (the onServerTick wave) and start their slow rise out of the
     * sea. The beat itself only marks the phase — everything else is continuous work.
     */
    private static void beatEclipseRise(Run current) {
        current.enter(Phase.ECLIPSE);
    }

    /**
     * t={@value #T_BURST} — the eclipse EXPLODES: the intro-mirror giant shockwave
     * (the (1.0, 50) signature the client seam layers the HDR ring onto), the Photon
     * confetti cue, a first heavy shake, a first white pulse, and the slow FOV zoom
     * INTO the burst. The shell blow-out, hurled debris and the stacking pulse ladder
     * are continuous work from here to the white ({@link #animateBurst},
     * {@link #spawnBurstDebrisBatch}, {@link #burstEscalation}).
     */
    private static void beatBurst(Run current) {
        current.enter(Phase.BURST);
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue != null) {
            Vec3 center = eclipseCenter(1.0F);
            FxPayloads.sendFxEvent(epilogue, FxPayloads.FX_SHOCKWAVE, center, 1.0F, 50.0F, -1.0D);
            // PH-EVENTS: its own cue — NOT keyed off FX_SHOCKWAVE (the (1.0, 50) giant
            // signature is claimed by the intro burst ring's client seam).
            FxPayloads.sendFxEvent(epilogue, FxCues.CUE_CREDITS_BURST, center, 0.0F, 0.0F, -1.0D);
            for (ServerPlayer player : epilogue.players()) {
                player.playNotifySound(SoundEvents.END_PORTAL_SPAWN, SoundSource.MASTER, 1.0F, 0.62F);
                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER, 1.0F, 0.55F);
            }
        }
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(1.6F, 60));
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(6, 6, 10, 0x50FFFFFF));
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendFov(player, BURST_FOV_SCALE, T_WHITE_FADE - T_BURST + 30);
        }
    }

    /**
     * The burst act's rising ladder (every {@value #BURST_PULSE_PERIOD}t): a stacking
     * white pulse (alpha climbing toward the full white), a stronger shake, and a
     * closer thunder crack — "everything shakes and it gets brighter and brighter".
     */
    private static void burstEscalation(Run current, int t) {
        int step = (t - T_BURST) / BURST_PULSE_PERIOD;
        float ladder = Math.min(1.0F, step / 5.0F);
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(0.7F + 0.9F * ladder, BURST_PULSE_PERIOD + 14));
        int alpha = Math.min(0xE0, 0x40 + step * 0x28);
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(8, 10, 14, (alpha << 24) | 0x00FFFFFF));
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue != null) {
            for (ServerPlayer player : epilogue.players()) {
                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                        0.5F + 0.5F * ladder, 0.5F + 0.08F * ladder);
            }
        }
    }

    /**
     * t={@value #T_WHITE_FADE} — the last pulse rises into the FULL WHITE hold (40t up,
     * clamped 600t hold — {@link #beatTrackTwo} replaces it with the black melt long
     * before it expires).
     */
    private static void beatWhiteFade(Run current) {
        current.enter(Phase.OUTRO);
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(40, 600, 0, 0xFFFFFFFF));
        }
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(2.0F, 50));
    }

    /** t={@value #T_WHITE_PEAK} — behind the full white: every display is discarded. */
    private static void beatWhitePeak(Run current) {
        discardFlyers(current);
        discardEclipse(current);
        current.formations.discard(); // belt-and-braces (normally gone with the flyers)
        current.shatter.discard(); // belt-and-braces (normally gone at T_SHATTER_END)
    }

    /**
     * t={@value #T_TRACK2} — track two: the title theme returns ({@code MusicManager}'s
     * own 2 s crossfade takes {@code day_final} out) as the white melts to BLACK over
     * 8 s — the {@code CaptionRenderer} fade crossfade turns the replacement into a
     * smooth color melt instead of a pop.
     */
    private static void beatTrackTwo(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            MusicCues.play(MUSIC_OUTRO_CUE, player);
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(160, 600, 0, 0xFF000000));
        }
    }

    /**
     * t={@value #T_HOME} — behind the black: everyone home to the overworld spawn (the
     * post-credits world state; {@code bringEveryoneHome}'s deterministic spread). The
     * black cover is re-sent AFTER the hop so the arrival is never visible.
     */
    private static void beatHome(Run current) {
        MinecraftServer server = current.server;
        ServerLevel overworld = server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            // A skip() jumps time — the helm re-freeze may still be live; never teleport
            // a rubber-banded player (the lock would yank them back to the beach anchor).
            FreezeService.unfreeze(player);
            if (!player.level().dimension().equals(EPILOGUE)) {
                continue;
            }
            BlockPos column = spawn.offset(2 * (returned % 5 - 2), 0, 2 * (returned / 5 % 5 - 2));
            int y = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                    column.getX(), column.getZ());
            player.teleportTo(overworld, column.getX() + 0.5D, y, column.getZ() + 0.5D,
                    overworld.getSharedSpawnAngle(), 0.0F);
            returned++;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} player(s) brought home behind the black", returned);
    }

    /**
     * t={@value #T_CARD_TITLE} — "Minecraft Eclipse" fades up (gentle card, no glitch)
     * over the still-held, centered "Made by Sonic0810" — the FIN-6 end sequence's first
     * composite frame.
     */
    private static void beatCardTitle(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendGentleTitle(player, TITLE_END, CARD_TITLE_HOLD);
        }
    }

    /**
     * t={@value #T_CARDS_OUT} — both center cards leave: the zero-duration roll payload
     * fades the maker card out ({@code CreditsPanel}) and hands the HUD/FOV back
     * ({@code CreditsClient.onRollStopped} — irrelevant behind the held black); the
     * gentle title card ends itself on its own envelope.
     */
    private static void beatCardsOut(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendRoll(player, 0);
        }
    }

    /** t={@value #T_CARD_RETURNS} — "Minecraft Eclipse kehrt zurück in" (gentle fade over black). */
    private static void beatCardReturns(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendGentleTitle(player, TITLE_RETURNS, CARD_RETURNS_HOLD);
        }
    }

    /**
     * t={@value #T_CARD_NEXT} — the answer card: "Minecraft 2Worlds : Timeless". The
     * black hold is re-sent with it (the 600t fade clamp would expire before the finale
     * tele beat otherwise).
     */
    private static void beatCardNext(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendGentleTitle(player, TITLE_NEXT, CARD_NEXT_HOLD);
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
        }
    }

    // ------------------------------------------------------------------ props: wheel + flyers

    /** The ship's wheel: one block-display trapdoor stood upright on the poop deck. */
    private static void spawnWheel(Run current, ServerLevel limbo, int deckY) {
        Display.BlockDisplay wheel = EntityType.BLOCK_DISPLAY.create(limbo);
        if (wheel == null) {
            return;
        }
        wheel.moveTo(-17.4D, deckY + 7.1D, 0.5D, 0.0F, 0.0F);
        wheel.setBlockState(Blocks.DARK_OAK_TRAPDOOR.defaultBlockState());
        wheel.addTag(WHEEL_TAG);
        wheel.setTransformationInterpolationDelay(0);
        wheel.setTransformationInterpolationDuration(0);
        wheel.setTransformation(wheelPose(wheelAngle(T_SHIP)));
        LIVE_DISPLAYS.add(wheel.getUUID());
        limbo.addFreshEntity(wheel);
        current.wheel = wheel;
    }

    /**
     * The wheel's transform at a given spin: the flat trapdoor stood upright in the YZ
     * plane (facing the helmsman, +X), rotated {@code spinDegrees} like a wheel caught
     * mid-turn, centered on its anchor (the translation must be recomputed per spin —
     * it counter-rotates the block's half extent).
     */
    private static Transformation wheelPose(float spinDegrees) {
        Quaternionf rotation = new Quaternionf()
                .rotationZ((float) Math.toRadians(90.0D))
                .rotateY((float) Math.toRadians(spinDegrees));
        Vector3f half = new Vector3f(0.55F, 0.55F, 0.55F);
        Vector3f translation = new Vector3f(0.0F, 0.0F, 0.0F).sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(1.1F, 1.1F, 1.1F), new Quaternionf());
    }

    /**
     * BD-SHIP living helm driver (every 4t while the wheel is on stage): one 4t
     * interpolation window toward the absolute pose at {@code t + 4} — a lookahead
     * piecewise-linear sampling of the noisy angle curve, worst window ≈ 11° (far under
     * the ~90° flattening law). No-op once the wheel is gone (helm-skip path discards
     * it before the window ends). Also drives the spoke-glint brightness ramp.
     */
    private static void animateWheel(Run current, int t) {
        Display.BlockDisplay wheel = current.wheel;
        if (wheel == null || wheel.isRemoved()) {
            return;
        }
        wheel.setTransformationInterpolationDelay(0);
        wheel.setTransformationInterpolationDuration(4);
        wheel.setTransformation(wheelPose(wheelAngle(t + 4)));
        applyWheelGlint(wheel, t);
    }

    /**
     * Absolute wheel angle (degrees) at run tick {@code t}: rest spin + steady turn +
     * two incommensurate rate-noise sines + the CUT-CREDITS hands-settle grip envelope.
     * A pure function of the run clock, so re-pushes always agree (stateless-push law).
     */
    private static float wheelAngle(int t) {
        float run = t - T_SHIP;
        return WHEEL_REST_SPIN_DEGREES
                + WHEEL_TURN_DEG_PER_TICK * run
                + WHEEL_NOISE_A_DEG * (float) Math.sin(run * (Math.PI * 2.0D / WHEEL_NOISE_A_PERIOD))
                + WHEEL_NOISE_B_DEG * (float) Math.sin(run * (Math.PI * 2.0D / WHEEL_NOISE_B_PERIOD) + 2.1D)
                + gripOffset(t);
    }

    /**
     * FXTEAM CUT-CREDITS hands-settle beat as a deterministic envelope on the turning
     * wheel: the grip pulls the wheel 9° down-left over 10t at {@link #WHEEL_SETTLE_AT}
     * (the dolly reaching the wheel), relaxes back to −6.5° over 14t at
     * {@link #WHEEL_RELAX_AT}, and holds. The timings and magnitudes are the original
     * nudge beat's — only the transport changed (it rides the continuous rotation now).
     */
    private static float gripOffset(int t) {
        if (t < WHEEL_SETTLE_AT) {
            return 0.0F;
        }
        if (t < WHEEL_RELAX_AT) {
            return -9.0F * Math.min(1.0F, (t - WHEEL_SETTLE_AT) / 10.0F);
        }
        return -6.5F - 2.5F * Math.max(0.0F, 1.0F - (t - WHEEL_RELAX_AT) / 14.0F);
    }

    /**
     * Spoke-light glint: a {@value #WHEEL_GLINT_RAMP}t sine brightness ramp every
     * {@value #WHEEL_GLINT_PERIOD}t, then the override is CLEARED back to natural
     * light. Fixed-period on the run clock rather than true spoke-crossing detection
     * (the rate noise would make an {@code angle mod 45°} trigger double-blink) — but
     * REPASS-BD phase-locks the cycle to the SUNRISE spoke angle
     * ({@link #WHEEL_GLINT_OFFSET}) and warm-biases the ramp: block light leads
     * (6→15→6) while sky trails (6→11→6), so the flash reads as low dawn light on
     * varnished wood, not a fullbright pop.
     */
    private static void applyWheelGlint(Display.BlockDisplay wheel, int t) {
        int cycle = Math.floorMod(t - T_SHIP - WHEEL_GLINT_OFFSET, WHEEL_GLINT_PERIOD);
        if (cycle < WHEEL_GLINT_RAMP) {
            float env = (float) Math.sin(Math.PI * cycle / (double) WHEEL_GLINT_RAMP);
            applyBrightnessOverride(wheel,
                    6 + Math.round(5.0F * env), 6 + Math.round(9.0F * env));
        } else if (cycle < WHEEL_GLINT_RAMP + 4) {
            clearBrightnessOverride(wheel);
        }
    }

    private static void discardWheel(Run current) {
        if (current.wheel != null) {
            LIVE_DISPLAYS.remove(current.wheel.getUUID());
            current.wheel.discard();
            current.wheel = null;
        }
    }

    /**
     * FIN-6 debris sky, budgeted: up to {@value #FLYER_SPAWN_PER_TICK} new fragments per
     * tick until {@value #FLYER_COUNT} are aloft — never a single-tick entity dump, never
     * past {@link #DISPLAY_HARD_CAP}. Every fragment is dimmed via a display brightness
     * override (sky 7 / block 4 — backlit silhouettes against the sunrise instead of
     * fullbright floating blocks); ~15% of the LOW arcs drag a flattened tinted-glass
     * "shadow puck" along the sand underneath, clamped to the sand strip so no shadow
     * ever hovers over water. Arcs are anchored at each fragment's apex column and CYCLE
     * ({@link #flyerProgress}) — the sky stays busy for the whole 1300-tick act while
     * every display entity is reused instead of respawned.
     */
    private static void spawnFlyerBatch(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        Vec3 center = runnersCenter(epilogue);
        int budget = FLYER_SPAWN_PER_TICK;
        while (budget-- > 0 && current.flyerCursor < FLYER_COUNT) {
            if (capReached(current)) {
                current.flyerCursor = FLYER_COUNT; // over cap: keep what flies, stop trying
                break;
            }
            Display.BlockDisplay flyer = EntityType.BLOCK_DISPLAY.create(epilogue);
            if (flyer == null) {
                return; // retry the same index next tick (list/index alignment invariant)
            }
            int i = current.flyerCursor;
            double apexX = center.x + 10.0D + hash01(i, 1) * 30.0D;
            double apexY = BEACH_Y + 12.0D + hash01(i, 2) * 22.0D;
            double z = center.z + (hash01(i, 3) * 2.0D - 1.0D) * (LANE_HALF_Z + 10.0D);
            flyer.moveTo(apexX, apexY, z, 0.0F, 0.0F);
            flyer.setBlockState(FLYER_PALETTE[(int) (hash01(i, 4) * FLYER_PALETTE.length) % FLYER_PALETTE.length]);
            flyer.addTag(FLYER_TAG);
            flyer.setTransformationInterpolationDelay(0);
            flyer.setTransformationInterpolationDuration(0);
            flyer.setTransformation(flyerPose(i, flyerProgress(i, current.ticks), 1.0F));
            applyBrightnessOverride(flyer, 7, 4);
            LIVE_DISPLAYS.add(flyer.getUUID());
            epilogue.addFreshEntity(flyer);
            current.flyers.add(flyer);
            current.flyerCursor++;
            if (hash01(i, 2) < 0.15D) {
                spawnShadowPuck(current, epilogue, i, apexX, z);
            }
        }
        if (current.flyerCursor >= FLYER_COUNT) {
            EclipseMod.LOGGER.info("CreditsSequence: debris sky complete — {} flyer(s), {} shadow "
                    + "puck(s), {} display(s) live", current.flyers.size(), current.shadows.size(),
                    LIVE_DISPLAYS.size());
        }
    }

    /**
     * {@code Display.setBrightnessOverride} is private — round-trip the entity through
     * its own save NBT with a {@code brightness} compound instead (the vanilla data path,
     * so nothing reflective and nothing version-fragile beyond the tag name). Shared
     * with the stage-manager acts.
     */
    static void applyBrightnessOverride(Display.BlockDisplay display, int sky, int block) {
        CompoundTag data = display.saveWithoutId(new CompoundTag());
        CompoundTag brightness = new CompoundTag();
        brightness.putInt("sky", sky);
        brightness.putInt("block", block);
        data.put("brightness", brightness);
        display.load(data);
    }

    /**
     * Clears the override back to natural light through the same save-data round trip —
     * the vanilla read path resets the override when the {@code brightness} compound is
     * absent. No-op (no round trip) while no override is set.
     */
    private static void clearBrightnessOverride(Display.BlockDisplay display) {
        CompoundTag data = display.saveWithoutId(new CompoundTag());
        if (data.contains("brightness")) {
            data.remove("brightness");
            display.load(data);
        }
    }

    /**
     * One flattened tinted-glass display riding the sand under a low debris arc — the
     * "shadows-ish" ground read. Same {@link #FLYER_TAG} (the stray sweep covers it),
     * same discard lifecycle as the flyers.
     */
    private static void spawnShadowPuck(Run current, ServerLevel epilogue, int index,
            double apexX, double z) {
        Display.BlockDisplay puck = EntityType.BLOCK_DISPLAY.create(epilogue);
        if (puck == null) {
            return;
        }
        puck.moveTo(apexX, BEACH_Y + 1.03D, z, 0.0F, 0.0F);
        puck.setBlockState(Blocks.TINTED_GLASS.defaultBlockState());
        puck.addTag(FLYER_TAG);
        puck.setTransformationInterpolationDelay(0);
        puck.setTransformationInterpolationDuration(0);
        // Clamp the puck's east travel to the sand strip (never a shadow on open water).
        float maxDx = (float) (BEACH_SAND_EAST_X - 2 - apexX);
        puck.setTransformation(shadowPose(index, flyerProgress(index, current.ticks), maxDx, 1.0F));
        LIVE_DISPLAYS.add(puck.getUUID());
        epilogue.addFreshEntity(puck);
        current.shadows.add(new ShadowPuck(puck, index, maxDx));
    }

    /**
     * Interpolated transform push every {@value #FLYER_PUSH_STRIDE} ticks (FloatingDecor
     * transport pattern), one lookahead window toward the pose at {@code t + stride}.
     */
    private static void animateFlyers(Run current, int t) {
        if (current.flyers.isEmpty() && current.shadows.isEmpty()) {
            return;
        }
        for (int i = 0; i < current.flyers.size(); i++) {
            Display.BlockDisplay flyer = current.flyers.get(i);
            if (flyer.isRemoved()) {
                continue;
            }
            flyer.setTransformationInterpolationDelay(0);
            flyer.setTransformationInterpolationDuration(FLYER_PUSH_STRIDE);
            flyer.setTransformation(flyerPose(i, flyerProgress(i, t + FLYER_PUSH_STRIDE), 1.0F));
        }
        for (ShadowPuck shadow : current.shadows) {
            if (shadow.display().isRemoved()) {
                continue;
            }
            shadow.display().setTransformationInterpolationDelay(0);
            shadow.display().setTransformationInterpolationDuration(FLYER_PUSH_STRIDE);
            shadow.display().setTransformation(shadowPose(shadow.index(),
                    flyerProgress(shadow.index(), t + FLYER_PUSH_STRIDE), shadow.maxDx(), 1.0F));
        }
    }

    /**
     * t={@value #T_FLYERS_END} — one long push shrinks the whole debris sky to the scale
     * floor over {@value #FLYER_SHRINK_TICKS}t; the discard lands after the window so
     * nothing ever pops out of the air mid-frame.
     */
    private static void shrinkOutFlyers(Run current) {
        for (int i = 0; i < current.flyers.size(); i++) {
            Display.BlockDisplay flyer = current.flyers.get(i);
            if (flyer.isRemoved()) {
                continue;
            }
            flyer.setTransformationInterpolationDelay(0);
            flyer.setTransformationInterpolationDuration(FLYER_SHRINK_TICKS);
            flyer.setTransformation(flyerPose(i, flyerProgress(i, T_FLYERS_END), FLYER_SCALE_FLOOR));
        }
        for (ShadowPuck shadow : current.shadows) {
            if (shadow.display().isRemoved()) {
                continue;
            }
            shadow.display().setTransformationInterpolationDelay(0);
            shadow.display().setTransformationInterpolationDuration(FLYER_SHRINK_TICKS);
            shadow.display().setTransformation(shadowPose(shadow.index(),
                    flyerProgress(shadow.index(), T_FLYERS_END), shadow.maxDx(), FLYER_SCALE_FLOOR));
        }
    }

    /**
     * FIN-6 cycling arc clock: each fragment re-flies its west→east arc on its own loop
     * length ({@value #FLYER_CYCLE_MIN}..{@value #FLYER_CYCLE_MIN}+{@value #FLYER_CYCLE_VAR}t)
     * and phase — the sky reads as an endless debris stream while every entity is
     * REUSED. The wrap seam (a big westward translation jump inside one interpolation
     * window) is hidden by the scale envelope: the fragment is at the
     * {@value #FLYER_SCALE_FLOOR} floor on both sides of the seam. Pure function of the
     * run clock (stateless-push law).
     */
    private static float flyerProgress(int index, int t) {
        int cycle = FLYER_CYCLE_MIN + (int) (hash01(index, 16) * FLYER_CYCLE_VAR);
        int phase = (int) (hash01(index, 14) * cycle);
        return Math.floorMod(t - T_LIGHTNING + phase, cycle) / (float) cycle;
    }

    /**
     * Absolute pose of one debris fragment at arc progress 0..1: a west→east ballistic
     * arc through the apex anchor (translation ±~40 blocks, parabolic height) —
     * everything deterministic per index, so replays and re-pushes always agree.
     * BD-SHIP motion pass: the tumble carries a golden-angle phase (neighboring flyers
     * can never spin in sync) and DAMPS to ~35% of its launch rate by landing (debris
     * stabilizing, not a pinwheel); the scale envelope hides arc wraps; {@code shrink}
     * rides the end-of-act shrink-out push.
     */
    private static Transformation flyerPose(int index, float p, float shrink) {
        float u = p * 2.0F - 1.0F; // -1 → +1 along the arc
        float xOff = u * (30.0F + (float) hash01(index, 6) * 10.0F);
        float arcHeight = 10.0F + (float) hash01(index, 7) * 8.0F;
        float yOff = -arcHeight * u * u; // 0 at the apex, -h at both ends
        float spin = index * GOLDEN_ANGLE
                + (float) ((2.0D + hash01(index, 9) * 4.0D) * Math.PI) * dampedTumble(p);
        Vector3f axis = new Vector3f(
                (float) (hash01(index, 10) * 2.0D - 1.0D),
                (float) (0.4D + hash01(index, 11)),
                (float) (hash01(index, 12) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        float scale = Math.max(FLYER_SCALE_FLOOR,
                (0.5F + (float) hash01(index, 13) * 0.8F) * scaleEnvelope(p) * shrink);
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        Vector3f translation = new Vector3f(xOff, yOff, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /**
     * Damped tumble integral: reaches exactly 1 at p=1 (total spin magnitude unchanged)
     * while the instantaneous rate decays linearly to ~35% of its launch value.
     */
    private static float dampedTumble(float p) {
        return (p - 0.325F * p * p) / 0.675F;
    }

    /** In/out scale ramp over the first/last {@value #FLYER_SCALE_RAMP} of the flight. */
    private static float scaleEnvelope(float p) {
        float env = Math.min(p, 1.0F - p) / FLYER_SCALE_RAMP;
        return Math.max(FLYER_SCALE_FLOOR, Math.min(1.0F, env));
    }

    private static void discardFlyers(Run current) {
        discardAll(current.flyers);
        for (ShadowPuck shadow : current.shadows) {
            LIVE_DISPLAYS.remove(shadow.display().getUUID());
            shadow.display().discard();
        }
        current.shadows.clear();
    }

    private static void discardAll(List<Display.BlockDisplay> displays) {
        for (Display.BlockDisplay display : displays) {
            LIVE_DISPLAYS.remove(display.getUUID());
            display.discard();
        }
        displays.clear();
    }

    /**
     * FIN-6 hard cap: refuses new displays once {@value #DISPLAY_HARD_CAP} of ANY kind
     * are live (logged once per run) — a lag spiral can never out-spawn the budget.
     */
    private static boolean capReached(Run current) {
        if (LIVE_DISPLAYS.size() < DISPLAY_HARD_CAP) {
            return false;
        }
        if (!current.capWarned) {
            current.capWarned = true;
            EclipseMod.LOGGER.warn("CreditsSequence: display hard cap {} reached — further spawns dropped",
                    DISPLAY_HARD_CAP);
        }
        return true;
    }

    /** One ground-shadow display bound to its flyer's deterministic arc index. */
    private record ShadowPuck(Display.BlockDisplay display, int index, float maxDx) {}

    /**
     * Ground-shadow pose mirroring {@link #flyerPose}'s horizontal travel (same
     * staggered-progress/u/xOff math, east travel clamped to the sand strip), flattened
     * to a 0.045-high slab. The footprint swells up to +50% while its debris is at apex
     * (highest = biggest, softest-reading shadow), counter-spins slowly at 30% of the
     * (damped, golden-phased) debris tumble, and rides the same scale envelope so a
     * pre-launch or landed flyer never drags a visible puck.
     */
    private static Transformation shadowPose(int index, float p, float maxDx, float shrink) {
        float u = p * 2.0F - 1.0F;
        float xOff = Math.min(u * (30.0F + (float) hash01(index, 6) * 10.0F), maxDx);
        float heightFrac = 1.0F - u * u; // 1 at apex, 0 at both ends (mirrors -h·u²)
        float spin = (index * GOLDEN_ANGLE
                + (float) ((2.0D + hash01(index, 9) * 4.0D) * Math.PI) * dampedTumble(p)) * 0.3F;
        float base = 0.5F + (float) hash01(index, 13) * 0.8F;
        float footprint = Math.max(FLYER_SCALE_FLOOR,
                base * (0.9F + 0.5F * heightFrac) * scaleEnvelope(p) * shrink);
        Quaternionf rotation = new Quaternionf().rotationY(spin);
        Vector3f scale = new Vector3f(footprint, 0.045F, footprint);
        Vector3f half = new Vector3f(footprint * 0.5F, 0.0F, footprint * 0.5F);
        Vector3f translation = new Vector3f(xOff, 0.0F, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    // ------------------------------------------------------------------ the eclipse act

    /** Eased rise progress 0..1 of the eclipse across {@code T_ECLIPSE_RISE..T_BURST}. */
    private static float riseProgress(int t) {
        return Mth.clamp((t - T_ECLIPSE_RISE) / (float) (T_BURST - T_ECLIPSE_RISE), 0.0F, 1.0F);
    }

    /** Burst progress 0..1 across {@code T_BURST..T_WHITE_PEAK}. */
    private static float burstProgress(int t) {
        return Mth.clamp((t - T_BURST) / (float) (T_WHITE_PEAK - T_BURST), 0.0F, 1.0F);
    }

    /** Smoothstep — the sphere leaves the sea gently and settles gently. */
    private static float easeInOut(float p) {
        return p * p * (3.0F - 2.0F * p);
    }

    /** Eclipse VISUAL center Y offset relative to the anchor entities (BEACH_Y + 1). */
    private static float eclipseCenterYOff(float rise) {
        return (float) (-ECLIPSE_START_DEPTH - 1.0D + easeInOut(rise) * ECLIPSE_RISE_BLOCKS);
    }

    /** Eclipse VISUAL center in world space (the FX/sound anchor for the act). */
    private static Vec3 eclipseCenter(float rise) {
        return new Vec3(ECLIPSE_ANCHOR_X + ECLIPSE_VISUAL_OFFSET_X,
                BEACH_Y + 1.0D + eclipseCenterYOff(rise), 0.0D);
    }

    /** Golden-spiral unit direction {@code index} of {@code count} (even sphere coverage). */
    private static Vector3f sphereDir(int index, int count) {
        float y = 1.0F - 2.0F * (index + 0.5F) / count;
        float r = (float) Math.sqrt(Math.max(0.0F, 1.0F - y * y));
        float theta = index * GOLDEN_ANGLE;
        return new Vector3f(r * (float) Math.cos(theta), y, r * (float) Math.sin(theta));
    }

    /** Per-fragment blow-out distance at full burst (blocks past the shell radius). */
    private static float burstReach(int index) {
        return 60.0F + (float) hash01(index, 35) * 80.0F;
    }

    /**
     * FIN-6 eclipse build (budgeted at {@value #FLYER_SPAWN_PER_TICK}/t): a golden-spiral
     * shell of {@value #ECLIPSE_SHELL_COUNT} dark displays plus a
     * {@value #ECLIPSE_CORONA_COUNT}-display glowing corona ring. Every piece is anchored
     * at x={@value #ECLIPSE_ANCHOR_X} (INSIDE display tracking range of the surf line)
     * with the visual body offset {@value #ECLIPSE_VISUAL_OFFSET_X} blocks further east
     * on the translation and a widened {@code view_range} — the sphere reads far out at
     * sea without ever leaving tracking range. Shell pieces are brightness-crushed to
     * 0/0 (a black body); corona pieces burn at 15/15.
     */
    private static void spawnEclipseBatch(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        int budget = FLYER_SPAWN_PER_TICK;
        float rise = riseProgress(current.ticks);
        while (budget-- > 0) {
            boolean shell = current.eclipseShell.size() < ECLIPSE_SHELL_COUNT;
            if (!shell && current.eclipseCorona.size() >= ECLIPSE_CORONA_COUNT) {
                return;
            }
            if (capReached(current)) {
                return;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(epilogue);
            if (piece == null) {
                return;
            }
            int i = shell ? current.eclipseShell.size() : current.eclipseCorona.size();
            piece.moveTo(ECLIPSE_ANCHOR_X, BEACH_Y + 1.0D, 0.0D, 0.0F, 0.0F);
            piece.setBlockState(shell
                    ? ECLIPSE_PALETTE[(int) (hash01(i, 31) * ECLIPSE_PALETTE.length) % ECLIPSE_PALETTE.length]
                    : CORONA_PALETTE[i % CORONA_PALETTE.length]);
            piece.addTag(FLYER_TAG);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            piece.setTransformation(shell ? shellPose(i, rise, 0.0F) : coronaPose(i, rise, 0.0F));
            applyBrightnessOverride(piece, shell ? 0 : 15, shell ? 0 : 15);
            applyViewRange(piece, ECLIPSE_VIEW_RANGE);
            LIVE_DISPLAYS.add(piece.getUUID());
            epilogue.addFreshEntity(piece);
            (shell ? current.eclipseShell : current.eclipseCorona).add(piece);
            if (current.eclipseShell.size() == ECLIPSE_SHELL_COUNT
                    && current.eclipseCorona.size() == ECLIPSE_CORONA_COUNT) {
                EclipseMod.LOGGER.info("CreditsSequence: eclipse assembled — {} shell + {} corona "
                        + "display(s), {} live", ECLIPSE_SHELL_COUNT, ECLIPSE_CORONA_COUNT,
                        LIVE_DISPLAYS.size());
            }
        }
    }

    /**
     * Shell fragment pose: golden-spiral sphere point, risen by the eased rise; at
     * {@code burst > 0} the fragment flies outward along its sphere normal by
     * {@link #burstReach} and starts tumbling.
     */
    private static Transformation shellPose(int index, float rise, float burst) {
        Vector3f dir = sphereDir(index, ECLIPSE_SHELL_COUNT);
        float radius = (float) ECLIPSE_RADIUS + burstReach(index) * burst;
        float tumble = burst * (2.0F + (float) hash01(index, 33) * 6.0F);
        Quaternionf rotation = new Quaternionf().rotationAxis(
                index * GOLDEN_ANGLE + tumble, sphereDir(index + 7, ECLIPSE_SHELL_COUNT));
        float scale = ECLIPSE_SCALE * (0.8F + (float) hash01(index, 34) * 0.5F);
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = new Vector3f(
                (float) ECLIPSE_VISUAL_OFFSET_X + dir.x * radius,
                eclipseCenterYOff(rise) + dir.y * radius,
                dir.z * radius).sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /**
     * Corona pose: a glowing ring in the Y-Z plane (face-on to the west-watching
     * runners), 1.3× the shell radius, blown outward and spun at the burst.
     */
    private static Transformation coronaPose(int index, float rise, float burst) {
        double phi = index * (Math.PI * 2.0D / ECLIPSE_CORONA_COUNT);
        float ringRadius = (float) (ECLIPSE_RADIUS * 1.3D) + burstReach(index + 5) * burst * 1.2F;
        Quaternionf rotation = new Quaternionf().rotationX((float) phi + burst * 6.0F);
        float scale = CORONA_SCALE * (0.85F + (float) hash01(index, 36) * 0.3F);
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = new Vector3f(
                (float) ECLIPSE_VISUAL_OFFSET_X,
                eclipseCenterYOff(rise) + (float) Math.cos(phi) * ringRadius,
                (float) Math.sin(phi) * ringRadius).sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /** Slow-rise pushes on the {@value #ECLIPSE_PUSH_STRIDE}t stride (long windows, few packets). */
    private static void animateEclipseRise(Run current, int t) {
        pushEclipse(current, riseProgress(t + ECLIPSE_PUSH_STRIDE), 0.0F, ECLIPSE_PUSH_STRIDE);
    }

    /** Burst pushes: shell + corona blow-out and the hurled debris, on the burst stride. */
    private static void animateBurst(Run current, int t) {
        float bp = burstProgress(t + BURST_PUSH_STRIDE);
        pushEclipse(current, 1.0F, bp, BURST_PUSH_STRIDE);
        for (int i = 0; i < current.burstDebris.size(); i++) {
            Display.BlockDisplay debris = current.burstDebris.get(i);
            if (debris.isRemoved()) {
                continue;
            }
            debris.setTransformationInterpolationDelay(0);
            debris.setTransformationInterpolationDuration(BURST_PUSH_STRIDE);
            debris.setTransformation(debrisPose(i, bp));
        }
    }

    private static void pushEclipse(Run current, float rise, float burst, int window) {
        for (int i = 0; i < current.eclipseShell.size(); i++) {
            Display.BlockDisplay piece = current.eclipseShell.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(window);
            piece.setTransformation(shellPose(i, rise, burst));
        }
        for (int i = 0; i < current.eclipseCorona.size(); i++) {
            Display.BlockDisplay piece = current.eclipseCorona.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(window);
            piece.setTransformation(coronaPose(i, rise, burst));
        }
    }

    /**
     * FIN-6 hurled debris (budgeted at {@value #BURST_SPAWN_PER_TICK}/t, up to
     * {@value #BURST_DEBRIS_COUNT}): fragments thrown from the burst TOWARD and OVER the
     * players — same anchor/view-range trick as the sphere, mixed dark + greatest-hits
     * palette.
     */
    private static void spawnBurstDebrisBatch(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        int budget = BURST_SPAWN_PER_TICK;
        float bp = burstProgress(current.ticks);
        while (budget-- > 0 && current.burstCursor < BURST_DEBRIS_COUNT) {
            if (capReached(current)) {
                current.burstCursor = BURST_DEBRIS_COUNT;
                return;
            }
            Display.BlockDisplay debris = EntityType.BLOCK_DISPLAY.create(epilogue);
            if (debris == null) {
                return;
            }
            int i = current.burstCursor;
            debris.moveTo(ECLIPSE_ANCHOR_X, BEACH_Y + 1.0D, 0.0D, 0.0F, 0.0F);
            debris.setBlockState(hash01(i, 48) < 0.55D
                    ? ECLIPSE_PALETTE[(int) (hash01(i, 49) * ECLIPSE_PALETTE.length) % ECLIPSE_PALETTE.length]
                    : FLYER_PALETTE[(int) (hash01(i, 49) * FLYER_PALETTE.length) % FLYER_PALETTE.length]);
            debris.addTag(FLYER_TAG);
            debris.setTransformationInterpolationDelay(0);
            debris.setTransformationInterpolationDuration(0);
            debris.setTransformation(debrisPose(i, bp));
            applyBrightnessOverride(debris, 7, 4);
            applyViewRange(debris, ECLIPSE_VIEW_RANGE);
            LIVE_DISPLAYS.add(debris.getUUID());
            epilogue.addFreshEntity(debris);
            current.burstDebris.add(debris);
            current.burstCursor++;
        }
    }

    /**
     * One hurled burst fragment: staggered leave from the sphere's final center,
     * accelerating WEST toward and over the beach (ease-in on the translation), fanning
     * ±z wider as it comes and dropping toward head height as it passes — the
     * "thrown at you" read.
     */
    private static Transformation debrisPose(int index, float p) {
        float launch = (float) hash01(index, 40) * 0.35F;
        float q = Mth.clamp((p - launch) / (1.0F - launch), 0.0F, 1.0F);
        float drive = q * q * (2.0F - q); // ease-in that never stops accelerating the eye
        float startY = eclipseCenterYOff(1.0F)
                + ((float) hash01(index, 41) * 2.0F - 1.0F) * (float) ECLIPSE_RADIUS;
        float endY = 6.0F + (float) hash01(index, 42) * 18.0F;
        float endX = (float) -(ECLIPSE_ANCHOR_X - START_X + 30.0D + hash01(index, 43) * 60.0D);
        float x = (float) ECLIPSE_VISUAL_OFFSET_X
                + (endX - (float) ECLIPSE_VISUAL_OFFSET_X) * drive;
        float y = startY + (endY - startY) * drive
                + 6.0F * (float) Math.sin(Math.PI * drive) * (float) hash01(index, 44);
        float z = (((float) hash01(index, 45) * 2.0F - 1.0F) * (float) ECLIPSE_RADIUS)
                * (1.0F + 3.0F * drive);
        float spin = index * GOLDEN_ANGLE
                + drive * (float) ((3.0D + hash01(index, 46) * 5.0D) * Math.PI);
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, sphereDir(index + 13, BURST_DEBRIS_COUNT));
        float scale = 0.8F + (float) hash01(index, 47) * 1.6F;
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = new Vector3f(x, y, z).sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /**
     * A building thunder rumble under the rise (every {@value #RUMBLE_PERIOD}t): louder,
     * higher and physically closer-reading as the sphere climbs, with a low shake once
     * the body clears the horizon.
     */
    private static void eclipseRumble(Run current, int t) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        float rise = riseProgress(t);
        for (ServerPlayer player : epilogue.players()) {
            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                    0.25F + 0.55F * rise, 0.5F + 0.15F * rise);
        }
        if (rise > 0.3F) {
            PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(0.15F + 0.35F * rise, RUMBLE_PERIOD));
        }
    }

    private static void discardEclipse(Run current) {
        discardAll(current.eclipseShell);
        discardAll(current.eclipseCorona);
        discardAll(current.burstDebris);
    }

    /**
     * {@code Display.setViewRange} is private like the brightness setter — same
     * save-data round trip ({@code view_range} is a vanilla display save tag). Shared
     * with the stage-manager acts.
     */
    static void applyViewRange(Display.BlockDisplay display, float range) {
        CompoundTag data = display.saveWithoutId(new CompoundTag());
        data.putFloat("view_range", range);
        display.load(data);
    }

    // ------------------------------------------------------------------ the sunrise

    /**
     * FIN-6 sunrise: the epilogue dimension shares the OVERWORLD day clock
     * ({@code DerivedLevelData}), so the sun is driven by stepping the overworld's
     * {@code dayTime} 1t/t from the {@value #SUNRISE_DAY_TICK} pre-dawn boundary,
     * snapped once behind the full white — deterministic regardless of
     * {@code doDaylightCycle}, and a REAL slow dawn across the whole roll. The clock is
     * left at early morning afterwards: dawn over the post-credits world is the point.
     */
    private static void driveSunrise(Run current, int t) {
        ServerLevel overworld = current.server.overworld();
        if (current.sunriseBase == Long.MIN_VALUE) {
            long day = overworld.getDayTime();
            current.sunriseBase = day - Math.floorMod(day, 24000L) + SUNRISE_DAY_TICK;
        }
        overworld.setDayTime(current.sunriseBase + (t - T_EPILOGUE));
    }

    // ------------------------------------------------------------------ beach stamp

    /**
     * Queues the epilogue beach stamp through {@link BudgetedBlockWriter} (POL-S-02): the
     * ~44.6k writes are spread over budgeted column slices behind the t=0 black and t=200
     * white fades instead of one synchronous tick. The job drops itself if the run it
     * belongs to ends first; {@link #beatEpilogue} finishes any remainder synchronously
     * before the teleport (the runners must never land on a half-stamped set).
     */
    private static void startBeachStamp(Run owner, ServerLevel epilogue) {
        long start = System.nanoTime();
        BudgetedBlockWriter.enqueue(epilogue, budget -> {
            if (run != owner) {
                return true; // the run ended/was replaced — drop the one-shot job
            }
            return owner.beachStamp.advance(epilogue, budget);
        }, () -> EclipseMod.LOGGER.info("CreditsSequence: epilogue beach stamped in {} ms (budgeted)",
                (System.nanoTime() - start) / 1_000_000L),
                error -> EclipseMod.LOGGER.error(
                        "CreditsSequence: budgeted beach stamp failed — the epilogue beat will retry "
                                + "synchronously", error));
    }

    /**
     * Resumable cursor of the epilogue beach set (idempotent — pure {@code setBlock} of
     * the same shape): a sand strip with 2% {@code suspicious_sand} nothing-burgers, a
     * water plane east toward the frozen sunrise, an outer barrier rim that contains the
     * water, and barrier run-lane rails at z ±{@value #LANE_HALF_Z}. One logical operation
     * is one (x, z) column (at most 8 writes), so a {@code BudgetedBlockWriter} slice
     * stays around 4–5k writes. Column order matches the old synchronous loop (x outer,
     * z inner) — the layout stays byte-identical and deterministic. Flag
     * {@code UPDATE_CLIENTS} only — no neighbor updates, nothing to react anyway in a
     * void dimension.
     */
    private static final class BeachStamp {
        static final int SPAN_Z = 2 * BEACH_HALF_Z + 1;
        static final int TOTAL_COLUMNS = (BEACH_EAST_X - BEACH_WEST_X + 1) * SPAN_Z;

        int cursor;
        boolean done;

        /** Stamps up to {@code columnBudget} columns; returns {@code true} once complete. */
        boolean advance(ServerLevel epilogue, int columnBudget) {
            if (this.done) {
                return true;
            }
            BlockState sand = Blocks.SAND.defaultBlockState();
            BlockState suspicious = Blocks.SUSPICIOUS_SAND.defaultBlockState();
            BlockState water = Blocks.WATER.defaultBlockState();
            BlockState barrier = Blocks.BARRIER.defaultBlockState();
            int end = (int) Math.min((long) this.cursor + columnBudget, TOTAL_COLUMNS);
            for (; this.cursor < end; this.cursor++) {
                int x = BEACH_WEST_X + this.cursor / SPAN_Z;
                int z = -BEACH_HALF_Z + this.cursor % SPAN_Z;
                // Base slab under everything (also the sea floor).
                for (int y = BEACH_Y - 3; y <= BEACH_Y - 1; y++) {
                    set(epilogue, x, y, z, sand);
                }
                boolean rim = x == BEACH_WEST_X || x == BEACH_EAST_X || Math.abs(z) == BEACH_HALF_Z;
                if (x <= BEACH_SAND_EAST_X) {
                    set(epilogue, x, BEACH_Y, z, hash01(x * 31 + z, 15) < 0.02D ? suspicious : sand);
                } else {
                    set(epilogue, x, BEACH_Y, z, rim ? barrier : water);
                }
                if (rim) {
                    for (int y = BEACH_Y + 1; y <= BEACH_Y + 3; y++) {
                        set(epilogue, x, y, z, barrier);
                    }
                }
                // Run-lane rails over the sand (invisible; keep the line together).
                if (Math.abs(z) == LANE_HALF_Z && x <= BEACH_SAND_EAST_X) {
                    for (int y = BEACH_Y + 1; y <= BEACH_Y + 2; y++) {
                        set(epilogue, x, y, z, barrier);
                    }
                }
            }
            this.done = this.cursor >= TOTAL_COLUMNS;
            return this.done;
        }
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.getChunk(x >> 4, z >> 4); // force-load (GhostShipBuilder pattern)
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_CLIENTS);
    }

    /** Average runner position on the beach (fallback: the start line). */
    private static Vec3 runnersCenter(ServerLevel epilogue) {
        double x = 0.0D;
        double z = 0.0D;
        int count = 0;
        for (ServerPlayer player : epilogue.players()) {
            if (!player.isSpectator()) {
                x += player.getX();
                z += player.getZ();
                count++;
            }
        }
        return count == 0 ? new Vec3(START_X, BEACH_Y + 1, 0.0D)
                : new Vec3(x / count, BEACH_Y + 1, z / count);
    }

    // ------------------------------------------------------------------ join / rejoin safety

    /**
     * Mid-run joins are folded into the current beat (nonce + fade + roll + hiding); a
     * player a crash left in the epilogue dimension AFTER the run is returned to the
     * overworld spawn, and leftover credits hiding (the {@value #HIDDEN_TAG} marker) is
     * stripped — no hanging invisibility after a restart mid-credits.
     */
    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        Run current = run;
        if (current == null) {
            // Post-crash/restart cleanup: strip credits hiding + rescue from the set.
            if (player.getTags().contains(HIDDEN_TAG)) {
                clearHiding(player);
                EclipseMod.LOGGER.info("CreditsSequence: {} un-hidden at login (no live run)",
                        player.getScoreboardName());
            }
            if (player.level().dimension().equals(EPILOGUE)) {
                MinecraftServer server = player.server;
                ServerLevel overworld = server.overworld();
                BlockPos spawn = overworld.getSharedSpawnPos();
                int y = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        spawn.getX(), spawn.getZ());
                player.teleportTo(overworld, spawn.getX() + 0.5D, y, spawn.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
                EclipseMod.LOGGER.info("CreditsSequence: {} rescued from the epilogue set at login",
                        player.getScoreboardName());
            }
            return;
        }
        CreditsPayloads.sendBegin(player, current.nonce);
        if (!player.isSpectator()) {
            applyHiding(player); // F-057: rejoins stay invisible for the run's whole span
        }
        int t = current.ticks;
        if (t < T_EPILOGUE) {
            // Held black until just past the epilogue teleport, then released — the beach
            // beat (roll + statue lock) still reaches this player because it broadcasts.
            PacketDistributor.sendToPlayer(player,
                    S2CScreenFadePayload.sustained(0, Math.max(20, T_EPILOGUE + 20 - t), 30, 0xFF000000));
        } else if (t < T_WHITE_FADE) {
            if (t >= T_BEACH) {
                MusicCues.play(MUSIC_FINALE_CUE, player);
                int rollLeft = ROLL_TICKS - (t - T_BEACH);
                if (rollLeft > 40) {
                    CreditsPayloads.sendRoll(player, rollLeft);
                }
                if (t >= T_BURST) {
                    CreditsPayloads.sendFov(player, BURST_FOV_SCALE, Math.max(20, T_WHITE_FADE - t));
                }
                if (!player.isSpectator() && player.level().dimension().equals(EPILOGUE)) {
                    FreezeService.freeze(player, Math.max(40, T_WHITE_PEAK - t + 60), false, 0);
                }
            }
        } else if (t < T_TRACK2) {
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(0, 600, 0, 0xFFFFFFFF));
        } else if (t < T_FINALE_TELE) {
            MusicCues.play(MUSIC_OUTRO_CUE, player);
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
        } else if (t < T_FINALE_HOLD) {
            // Mid-finale join: fold into the black-hole shot (vantage, FOV, space sky).
            MusicCues.play(MUSIC_VICTORY_CUE, player);
            if (!player.isSpectator()) {
                Vec3 vantage = current.blackHole.vantage();
                player.teleportTo(current.server.overworld(), vantage.x, vantage.y, vantage.z,
                        current.blackHole.vantageYaw(), current.blackHole.vantagePitch());
                player.setDeltaMovement(Vec3.ZERO);
                player.fallDistance = 0.0F;
                FreezeService.freeze(player, Math.max(40, T_FINALE_HOLD - t + 100), false, 0);
            }
            CreditsPayloads.sendFov(player, FINALE_FOV_SCALE, 20);
            float intensity = 0.35F;
            for (int step = 0; step < FINALE_SKY_STEP_AT.length; step++) {
                if (t >= T_FINALE_REVEAL + FINALE_SKY_STEP_AT[step]) {
                    intensity = FINALE_SKY_STEP_INTENSITY[step];
                }
            }
            Vec3 hole = current.blackHole.holeCenter();
            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                    CreditsPayloads.S2CCreditsSkyPayload.MODE_SPACE, intensity, 40,
                    hole.x, hole.y, hole.z));
            if (t >= T_FINALE_DARK) {
                PacketDistributor.sendToPlayer(player,
                        S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
            }
        } else {
            // The HOLD: pure black (the refresh wave keeps it alive until end_event).
            PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(0, 600, 0, 0xFF000000));
        }
    }

    // ------------------------------------------------------------------ replay (FX-only)

    @Override
    public String sequenceId() {
        return SEQUENCE_ID;
    }

    @Override
    public List<String> phaseIds() {
        return List.of("SHATTER", "HELM", "WHITEOUT", "BEACH", "LIGHTNING", "ECLIPSE", "BURST",
                "OUTRO", "BLACKHOLE");
    }

    /**
     * FX-only replays (R12 contract): fades, cards, captions, camera path and sounds like
     * the live beats — but LOCAL plays only, no teleports, no entities, no block writes, no
     * {@link CreditsData} commits and NEVER a close broadcast.
     */
    @Override
    public boolean replay(MinecraftServer server, String phaseId, Collection<ServerPlayer> players) {
        List<ServerPlayer> watchers = List.copyOf(players);
        switch (phaseId.toUpperCase(Locale.ROOT)) {
            case "SHATTER" -> {
                // FX-only F-058: the collapse veil + sky contraction + rumble at the
                // watcher (no displays, no teleports, no eclipse-phase commit).
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                            .S2CFxEventPayload(FxCues.CUE_CREDITS_COLLAPSE, player.position(), 0.0F, 0.0F));
                    CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                            CreditsPayloads.S2CCreditsSkyPayload.MODE_COLLAPSE, 0.75F, 200,
                            0.0D, 0.0D, 0.0D));
                    PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(1.1F, 70));
                    player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                            0.9F, 0.45F);
                }
                schedule(server, 400, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                                    CreditsPayloads.S2CCreditsSkyPayload.MODE_OFF, 0.0F, 80,
                                    0.0D, 0.0D, 0.0D));
                        }
                    }
                });
                return true;
            }
            case "BLACKHOLE" -> {
                // FX-only F-056: SPACE sky + post distortion + the maw cue 60 blocks
                // down the watcher's view line + the tele FOV — all handed back after.
                for (ServerPlayer player : watchers) {
                    Vec3 ahead = player.position().add(player.getLookAngle().scale(60.0D));
                    CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                            CreditsPayloads.S2CCreditsSkyPayload.MODE_SPACE, 0.85F, 120,
                            ahead.x, ahead.y, ahead.z));
                    PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                            .S2CFxEventPayload(FxCues.CUE_BLACK_HOLE, ahead, 0.0F, 0.0F));
                    CreditsPayloads.sendFov(player, FINALE_FOV_SCALE, 80);
                }
                schedule(server, 600, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            CreditsPayloads.sendSky(player, new CreditsPayloads.S2CCreditsSkyPayload(
                                    CreditsPayloads.S2CCreditsSkyPayload.MODE_OFF, 0.0F, 100,
                                    0.0D, 0.0D, 0.0D));
                            CreditsPayloads.sendFov(player, 1.0F, 60);
                        }
                    }
                });
                return true;
            }
            case "HELM" -> {
                Vec3 anchor = watchers.isEmpty() ? Vec3.ZERO : watchers.get(0).position();
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(10, 40, 0, 0xFF000000));
                }
                schedule(server, 30, () -> CutsceneService.play(PATH_HELM, watchers, anchor, null,
                        CutsceneService.PlayOptions.LOCAL));
                return true;
            }
            case "WHITEOUT" -> {
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(30, 40, 20, 0xFFFFFFFF));
                    GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(
                            S2CPortalFxPayload.Phase.ENTER, STYLE_CREDITS_WHITE, 40));
                }
                return true;
            }
            case "BEACH" -> {
                for (ServerPlayer player : watchers) {
                    MusicCues.play(MUSIC_FINALE_CUE, player);
                    CreditsPayloads.sendRoll(player, 400);
                }
                return true;
            }
            case "LIGHTNING" -> {
                for (int i = 0; i < LIGHTNING_STRIKES; i++) {
                    int index = i;
                    // Mirrors the live near-far ladder: flash on the interval, thunder
                    // arriving late/low/quiet by depth (FXTEAM CUT-CREDITS).
                    int depth = STRIKE_DEPTHS[index % STRIKE_DEPTHS.length];
                    boolean far = depth > 40;
                    schedule(server, i * LIGHTNING_INTERVAL, () -> {
                        float intensity = 0.6F + 0.4F * index / (LIGHTNING_STRIKES - 1);
                        for (ServerPlayer player : watchers) {
                            if (player.hasDisconnected()) {
                                continue;
                            }
                            Vec3 impact = player.position().add(14.0D + depth, 0.0D,
                                    (index % 2 == 0 ? 1 : -1) * (8.0D + hash01(index, 22) * 26.0D));
                            PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                                    .S2CFxEventPayload(FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F));
                            // PH-EVENTS replay parity (R12): the live ladder pairs every
                            // strike with its Photon beam cue — so does the replay.
                            PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                                    .S2CFxEventPayload(FxCues.CUE_CREDITS_STRIKE, impact, intensity, 0.0F));
                        }
                    });
                    schedule(server, i * LIGHTNING_INTERVAL + 1 + depth / 17, () -> {
                        float intensity = 0.6F + 0.4F * index / (LIGHTNING_STRIKES - 1);
                        for (ServerPlayer player : watchers) {
                            if (!player.hasDisconnected()) {
                                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER,
                                        SoundSource.WEATHER,
                                        (0.7F + 0.5F * intensity) * (far ? 0.72F : 1.0F),
                                        (far ? 0.72F : 0.9F) + (float) hash01(index, 23) * 0.12F);
                            }
                        }
                    });
                }
                return true;
            }
            case "ECLIPSE" -> {
                // FX-only: the building rumble/shake ladder of the rise (no displays).
                for (int k = 0; k < 4; k++) {
                    int step = k;
                    schedule(server, k * 40, () -> {
                        for (ServerPlayer player : watchers) {
                            if (!player.hasDisconnected()) {
                                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER,
                                        SoundSource.WEATHER, 0.3F + 0.18F * step, 0.5F + 0.05F * step);
                                PacketDistributor.sendToPlayer(player,
                                        S2CShakePayload.shake(0.15F + 0.1F * step, 40));
                            }
                        }
                    });
                }
                return true;
            }
            case "BURST" -> {
                for (ServerPlayer player : watchers) {
                    // Replay parity (EVAL-V6-PHOTON §4): the live beatBurst leads with the
                    // giant FX_SHOCKWAVE(1.0, 50) — the exact signature the client seam
                    // layers the Photon INTRO_BURST_RING onto — so the FX-only replay
                    // sends it too, anchored at the watcher.
                    PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                            .S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE, player.position(), 1.0F, 50.0F));
                    // PH-EVENTS replay parity (R12): the live burst pairs the flash with
                    // the confetti cue — replay anchors it at the watcher.
                    PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                            .S2CFxEventPayload(FxCues.CUE_CREDITS_BURST, player.position(), 0.0F, 0.0F));
                    PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(1.6F, 60));
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(6, 6, 10, 0x50FFFFFF));
                    CreditsPayloads.sendFov(player, BURST_FOV_SCALE, 130);
                }
                // The stacking pulse/shake ladder, compressed to a rehearsal-sized act.
                for (int k = 1; k <= 4; k++) {
                    int step = k;
                    schedule(server, k * BURST_PULSE_PERIOD, () -> {
                        int alpha = Math.min(0xE0, 0x40 + step * 0x28);
                        for (ServerPlayer player : watchers) {
                            if (!player.hasDisconnected()) {
                                PacketDistributor.sendToPlayer(player,
                                        new S2CScreenFadePayload(8, 10, 14, (alpha << 24) | 0x00FFFFFF));
                                PacketDistributor.sendToPlayer(player,
                                        S2CShakePayload.shake(0.7F + 0.2F * step, 40));
                            }
                        }
                    });
                }
                schedule(server, 170, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            CreditsPayloads.sendFov(player, 1.0F, 40); // FX-only: hand the FOV back
                        }
                    }
                });
                return true;
            }
            case "OUTRO" -> {
                // White hold → track two + black melt → the three gentle end cards.
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, S2CScreenFadePayload.sustained(20, 600, 0, 0xFFFFFFFF));
                }
                schedule(server, 60, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            MusicCues.play(MUSIC_OUTRO_CUE, player);
                            PacketDistributor.sendToPlayer(player,
                                    S2CScreenFadePayload.sustained(160, 600, 0, 0xFF000000));
                        }
                    }
                });
                schedule(server, 240, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            CreditsPayloads.sendGentleTitle(player, TITLE_END, CARD_TITLE_HOLD);
                        }
                    }
                });
                schedule(server, 420, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            CreditsPayloads.sendGentleTitle(player, TITLE_RETURNS, CARD_RETURNS_HOLD);
                        }
                    }
                });
                schedule(server, 620, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            CreditsPayloads.sendGentleTitle(player, TITLE_NEXT, CARD_NEXT_HOLD);
                        }
                    }
                });
                schedule(server, 880, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player,
                                    new S2CScreenFadePayload(0, 20, 60, 0xFF000000));
                        }
                    }
                });
                return true;
            }
            default -> {
                return false;
            }
        }
    }

    // ------------------------------------------------------------------ scheduler (replays)

    private record Task(long dueTick, Runnable action) {}

    private static void schedule(MinecraftServer server, int delayTicks, Runnable action) {
        TASKS.add(new Task(server.getTickCount() + Math.max(0, delayTicks), action));
    }

    private static void tickScheduler(MinecraftServer server) {
        if (TASKS.isEmpty()) {
            return;
        }
        long now = server.getTickCount();
        List<Task> due = null;
        Iterator<Task> iterator = TASKS.iterator();
        while (iterator.hasNext()) {
            Task task = iterator.next();
            if (task.dueTick() <= now) {
                iterator.remove();
                if (due == null) {
                    due = new ArrayList<>(4);
                }
                due.add(task);
            }
        }
        if (due != null) {
            for (Task task : due) {
                task.action().run();
            }
        }
    }

    /** Tiny deterministic hash in [0, 1) (FloatingDecor mixer). Shared with the acts. */
    static double hash01(int index, int salt) {
        int h = index * 374761393 + salt * 668265263;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / (double) 0x80000000L;
    }

    // ------------------------------------------------------------------ act hooks

    /**
     * Cap check for the stage-manager acts (shatter/formation/black hole): {@code true}
     * refuses the spawn — either no run is live or the {@link #DISPLAY_HARD_CAP} budget
     * is exhausted (logged once through {@link #capReached}).
     */
    static boolean actCapReached() {
        Run current = run;
        return current == null || capReached(current);
    }

    /** Registers an act-spawned display with the session-live set (stray-sweep contract). */
    static void trackDisplay(Display.BlockDisplay display) {
        LIVE_DISPLAYS.add(display.getUUID());
    }

    /** Unregisters an act display right before its discard. */
    static void untrackDisplay(Display.BlockDisplay display) {
        LIVE_DISPLAYS.remove(display.getUUID());
    }

    // ------------------------------------------------------------------ persisted phase

    /**
     * The credits sequence's own persisted state ({@code data/eclipse_credits_sequence.dat},
     * IntroSequence's {@code IntroData} pattern): {@code started}/{@code completed}/{@code
     * phase} drive the restart contract (skip to end state, never resume, never re-close),
     * {@code nonce} records the last run's close token for diagnostics.
     */
    public static final class CreditsData extends SavedData {
        static final String DATA_NAME = "eclipse_credits_sequence";
        private static final String TAG_STARTED = "started";
        private static final String TAG_COMPLETED = "completed";
        private static final String TAG_PHASE = "phase";
        private static final String TAG_NONCE = "nonce";

        private boolean started;
        private boolean completed;
        private String phase = "";
        private int nonce;

        public CreditsData() {}

        static CreditsData get(MinecraftServer server) {
            return server.overworld().getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(CreditsData::new, CreditsData::load), DATA_NAME);
        }

        static CreditsData load(CompoundTag tag, HolderLookup.Provider registries) {
            CreditsData data = new CreditsData();
            data.started = tag.getBoolean(TAG_STARTED);
            data.completed = tag.getBoolean(TAG_COMPLETED);
            data.phase = tag.getString(TAG_PHASE);
            data.nonce = tag.getInt(TAG_NONCE);
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putBoolean(TAG_STARTED, this.started);
            tag.putBoolean(TAG_COMPLETED, this.completed);
            tag.putString(TAG_PHASE, this.phase);
            tag.putInt(TAG_NONCE, this.nonce);
            return tag;
        }

        boolean isStarted() {
            return this.started;
        }

        void setStarted(boolean started) {
            this.started = started;
            setDirty();
        }

        boolean isCompleted() {
            return this.completed;
        }

        void setCompleted(boolean completed) {
            this.completed = completed;
            setDirty();
        }

        String phase() {
            return this.phase;
        }

        void setPhase(String phase) {
            this.phase = phase;
            setDirty();
        }

        void setNonce(int nonce) {
            this.nonce = nonce;
            setDirty();
        }
    }
}
