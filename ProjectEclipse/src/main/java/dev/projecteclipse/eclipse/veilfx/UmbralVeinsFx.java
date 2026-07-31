package dev.projecteclipse.eclipse.veilfx;

import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.LerpingBossEvent;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.phys.AABB;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.CustomizeGuiOverlayEvent;

/**
 * FX-Wave-13 N1 — <b>Umbral-Adern</b>: once a boss (Herald / Ferryman / Fog Tyrant) drops
 * under {@value #DREAD_ENTER} of its health, black veins creep in from the screen edges and
 * breathe on a ~1.2 s pulse. It is the endgame tell of every boss fight: the frame itself
 * starts to die before the boss does.
 *
 * <p><b>Pipeline</b>: {@code eclipse:umbral_veins}, FEATURE priority, registered with
 * {@link VeilPostController} from static init — the landed {@code GhostGradeFx} pattern.
 * Uniforms {@code VeinStrength} / {@code Time} / {@code Detail} (Veil's
 * {@code VeilRenderTime} does NOT exist in pinwheel post shaders, so the clock comes from
 * Java here, like {@code storm_interior} and {@code rift_glitch}).</p>
 *
 * <p><b>Iris gating</b>: none of its own, by construction — {@link VeilPostController}
 * hard-gates every row through {@code EclipseIrisState.postFxAllowed()} (shaderpack active
 * or {@code veilPostFx} off ⇒ no Eclipse post pass is ever added). There is deliberately no
 * world-space Iris fallback: a screen-edge vignette has no world-space analogue, and the
 * bossbar still tells the whole story.</p>
 *
 * <h2>Where the boss HP comes from (client-side only — zero new wire)</h2>
 * <ol>
 *   <li><b>The bossbar sync</b> (primary, works at any distance and through fog/walls): the
 *       three bosses each open a {@code ServerBossEvent} whose name is a fixed translation
 *       key ({@link #BOSS_BAR_KEYS}) and tag it {@code THEME_BOSS} over
 *       {@code S2CBossbarStylePayload}. The vanilla bar packet carries the progress =
 *       {@code health / maxHealth}, and NeoForge re-fires it per bar as
 *       {@link CustomizeGuiOverlayEvent.BossEventProgress}. Listening there is read-only and
 *       additive — the event is never cancelled, so {@code BossbarSkin} keeps rendering
 *       exactly as before and this class needs no hook into it.</li>
 *   <li><b>The boss entity itself</b> (backstop): {@code health / maxHealth} of a living
 *       boss within {@value #BOSS_SCAN_RANGE} blocks — synched entity data every tracking
 *       client already has ({@code DeepRumbleFx}'s window law). This covers the cases the
 *       bar cannot: an operator-renamed boss (a custom name replaces the bar name), and any
 *       frame where the bossbar layer does not render.</li>
 * </ol>
 * <p>The two sources are combined by taking the LOWEST health fraction seen, so the veins
 * always track the boss that is closest to death.</p>
 *
 * <p><b>Hysteresis + easing</b> (INTEGRATION.md §4): the window opens under
 * {@value #DREAD_ENTER} health and only closes again above {@value #DREAD_EXIT} (a boss
 * healing across the line cannot strobe the frame), and the uniform slews toward its target
 * at {@value #SLEW_PER_TICK}/tick — so the veins visibly GROW instead of snapping in, and
 * they retract over ~1 s when the boss dies or despawns. At exactly 0 the row is dropped
 * from the manager and the shader is a bit-identical passthrough.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class UmbralVeinsFx {
    public static final ResourceLocation UMBRAL_VEINS_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "umbral_veins");

    /** Bossbar name keys of the three endgame bosses (see the class javadoc, source 1). */
    private static final Set<String> BOSS_BAR_KEYS = Set.of(
            "entity.eclipse.herald.bossbar",
            "entity.eclipse.ferryman.bossbar",
            "entity.eclipse.fog_tyrant.bossbar");

    /** The veins start growing under this health fraction (the mandate's 20 %)… */
    private static final float DREAD_ENTER = 0.20F;
    /** …and the window only closes again above this one (hysteresis band). */
    private static final float DREAD_EXIT = 0.24F;
    /** Health fraction at which the veins are fully grown (the last breath). */
    private static final float DREAD_FLOOR = 0.02F;
    /** Uniform slew per tick — full growth/retraction in ~1 s; the veins never pop. */
    private static final float SLEW_PER_TICK = 0.05F;
    /** Below this the retraction is over: drop the pass entirely (idle-skip, §3.5). */
    private static final float MIN_ACTIVE = 0.002F;
    /** Entity backstop scan radius in blocks (an arena fight fits inside it). */
    private static final double BOSS_SCAN_RANGE = 64.0D;
    /** Entity backstop cadence in ticks (the bossbar feed is per-frame and free). */
    private static final int BOSS_SCAN_CADENCE = 5;
    /** A bossbar reading older than this is stale — the bar left the screen. */
    private static final long BAR_TTL_MILLIS = 500L;
    /** {@code Time} uniform wrap (one hour of ticks — the limbo clock-wrap precedent). */
    private static final int TIME_WRAP_TICKS = 72_000;

    /** Lowest boss health fraction seen on a tagged bossbar this frame (client thread only). */
    private static float barHealthFraction = 1.0F;
    private static long barSeenMillis;
    /** Lowest boss health fraction from the entity backstop, refreshed by the tick scan. */
    private static float entityHealthFraction = 1.0F;
    /** True while the hysteresis window is open (the DREAD_ENTER/DREAD_EXIT latch). */
    private static boolean windowOpen;
    /** The eased uniform; pause-frozen clock for the pulse. */
    private static float easedStrength;
    private static int veinTicks;
    private static int scanCountdown;

    static {
        // Feature rows register from static init (the W1 wiring note): the
        // @EventBusSubscriber scan loads this class during client mod construction, well
        // before the first tick — so the row exists before any boss can be summoned.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                UMBRAL_VEINS_POST,
                VeilPostController.PipelinePriority.FEATURE,
                UmbralVeinsFx::wantUmbralVeins,
                UmbralVeinsFx::feedUmbralVeins));
    }

    private UmbralVeinsFx() {}

    // ------------------------------------------------------------------ pipeline row

    /** Active while anything is left of the eased growth (in any dimension). */
    private static boolean wantUmbralVeins() {
        return Minecraft.getInstance().level != null && easedStrength > MIN_ACTIVE;
    }

    /** Per-frame feeder — no allocations (the {@link VeilPostController} contract). */
    private static void feedUmbralVeins(PostPipeline pipeline) {
        float partialTick = Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
        pipeline.getUniform("VeinStrength").setFloat(easedStrength);
        // Pause-frozen seconds: the pulse holds still on the pause screen like every other
        // eased FX clock. Hour wrap (one sub-frame pattern step per hour — the documented
        // limbo Time-wrap tradeoff).
        pipeline.getUniform("Time").setFloat((veinTicks % TIME_WRAP_TICKS + partialTick) / 20.0F);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }

    // ------------------------------------------------------------------ state feed

    /**
     * Read-only tap on the vanilla bossbar render pass: records the lowest progress of any
     * bar carrying one of the {@link #BOSS_BAR_KEYS} names. The event is NOT cancelled and
     * nothing is drawn here, so {@code BossbarSkin} is completely unaffected.
     */
    @SubscribeEvent
    static void onBossEventProgress(CustomizeGuiOverlayEvent.BossEventProgress event) {
        LerpingBossEvent bar = event.getBossEvent();
        if (!isEclipseBossBar(bar.getName())) {
            return;
        }
        long now = Util.getMillis();
        // First tagged bar of this frame resets the running minimum; later bars lower it.
        float progress = Mth.clamp(bar.getProgress(), 0.0F, 1.0F);
        barHealthFraction = now - barSeenMillis > BAR_TTL_MILLIS
                ? progress : Math.min(barHealthFraction, progress);
        barSeenMillis = now;
    }

    private static boolean isEclipseBossBar(Component name) {
        return name.getContents() instanceof TranslatableContents translatable
                && BOSS_BAR_KEYS.contains(translatable.getKey());
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return; // hold the state, freeze the pulse clock (the eased-FX law)
        }
        veinTicks++;
        if (--scanCountdown <= 0) {
            scanCountdown = BOSS_SCAN_CADENCE;
            entityHealthFraction = scanBossEntities(level, player);
        }
        float health = Math.min(entityHealthFraction, freshBarHealthFraction());
        // Hysteresis latch: open under DREAD_ENTER, close only above DREAD_EXIT.
        windowOpen = windowOpen ? health < DREAD_EXIT : health < DREAD_ENTER;
        float target = windowOpen ? Mth.clamp(
                (DREAD_ENTER - health) / (DREAD_ENTER - DREAD_FLOOR), 0.0F, 1.0F) : 0.0F;
        if (easedStrength < target) {
            easedStrength = Math.min(target, easedStrength + SLEW_PER_TICK);
        } else if (easedStrength > target) {
            easedStrength = Math.max(target, easedStrength - SLEW_PER_TICK);
        }
    }

    /** The bossbar reading, or "full health" once the bar stopped rendering. */
    private static float freshBarHealthFraction() {
        return Util.getMillis() - barSeenMillis <= BAR_TTL_MILLIS ? barHealthFraction : 1.0F;
    }

    /**
     * Entity backstop: the lowest {@code health / maxHealth} of any living Eclipse boss
     * within {@value #BOSS_SCAN_RANGE} blocks. Health is synched entity data, so every
     * tracking client already knows it — no packet, no server round trip.
     */
    private static float scanBossEntities(ClientLevel level, LocalPlayer player) {
        AABB box = player.getBoundingBox().inflate(BOSS_SCAN_RANGE);
        float lowest = 1.0F;
        lowest = Math.min(lowest, lowestHealth(level.getEntitiesOfClass(HeraldEntity.class, box)));
        lowest = Math.min(lowest, lowestHealth(level.getEntitiesOfClass(FerrymanEntity.class, box)));
        lowest = Math.min(lowest, lowestHealth(level.getEntitiesOfClass(FogTyrantEntity.class, box)));
        return lowest;
    }

    private static float lowestHealth(List<? extends LivingEntity> bosses) {
        float lowest = 1.0F;
        for (LivingEntity boss : bosses) {
            float max = boss.getMaxHealth();
            if (!boss.isAlive() || max <= 0.0F) {
                continue; // a corpse is not dread; the death FX owns that beat
            }
            lowest = Math.min(lowest, Mth.clamp(boss.getHealth() / max, 0.0F, 1.0F));
        }
        return lowest;
    }

    /** Disconnect/level-change reset — the veins never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    private static void reset() {
        barHealthFraction = 1.0F;
        barSeenMillis = 0L;
        entityHealthFraction = 1.0F;
        windowOpen = false;
        easedStrength = 0.0F;
        scanCountdown = 0;
    }

    /** Dev/QA introspection: the eased {@code VeinStrength} currently on the wire. */
    public static float veinStrength() {
        return easedStrength;
    }
}
