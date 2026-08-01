package dev.projecteclipse.eclipse.economy;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-074 — the post-purchase MINI-CUTSCENE at the altar (~3–6 s): after a successful
 * shard-shop buy ({@code AltarPayloads.handleBuy} success branch) the altar visibly
 * "hands over" the purchase to the whole gathering, not just the buyer's screen. The
 * run starts {@value #START_DELAY_TICKS}t after the buy so the panel's own purchase
 * animation (client-side, ~1.25 s, then the screen closes itself) finishes first —
 * the world ceremony picks up exactly where the UI lets go.
 *
 * <p><b>Category mapping is data-driven off the {@link ShardEconomy.Offer} shape</b>
 * (F-074 spec: derive from the offer type, no hand-kept id lists):</p>
 * <ul>
 *   <li>{@link Category#TEAM} — {@code offer.item() == null} (Eclipse's Favor, Double
 *       XP, Supply Beacon): a rising two-arm light spiral out of the altar crown plus a
 *       violet→gold colour wave rolling over the ground (screen shockwave + dust ring).</li>
 *   <li>{@link Category#HEART} — the reward item is a {@link VitaeShardItem} (heart
 *       fragment / the "special" purchase): a taller light fountain with three stacked
 *       pillar bursts and a descending-then-ascending bell line.</li>
 *   <li>{@link Category#GEAR} — every other item offer: the bought item rises out of
 *       the altar as an {@link Display.ItemDisplay}, spins in a small light spot and
 *       then flies into the buyer, landing with a pickup pop.</li>
 * </ul>
 *
 * <p><b>Infrastructure reuse only</b> (F-074 rule "prefer existing altar FX"): world
 * beats ride the shipped wire primitives — {@link S2CQuasarPayload} sends of the
 * existing altar emitters ({@code altar_beam}, {@code altar_pillar},
 * {@code altar_levelup_ring}, {@code heart_burst}), {@code FxPayloads.FX_SHOCKWAVE}
 * for the colour wave, vanilla {@code sendParticles} for the scripted geometry and the
 * {@link Display} entity pattern from {@code sequence.HeraldSummonSequence} for the
 * gift flight. No new payloads, no new FX cues, no client class — photon-less and
 * reduced-FX clients keep the full read (Quasar emitters degrade inside
 * {@code QuasarSpawner.spawnOrFallback} as usual).</p>
 *
 * <p><b>Despawn guarantee</b> ({@code HeraldSummonSequence}/{@code StormDebrisFx}
 * doctrine): the gift display carries {@value #ENTITY_TAG} and is tracked in a
 * live-UUID set; a tagged display joining a level untracked is a crash stray and is
 * discarded on load. {@code /kill @e[tag=eclipse_altar_buy_gift]} always works.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AltarBuyCeremony {
    /** Frozen command tag on the gift ItemDisplay — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_altar_buy_gift";

    /** UI grace: the panel's purchase animation (~25t) plays before the world beats start. */
    private static final int START_DELAY_TICKS = 28;
    /** Broadcast radius of the ceremony's particle/Quasar/sound beats. */
    private static final double FX_RANGE = 48.0D;
    /** Concurrent-run cap (a team buying in a burst): oldest run is finished early. */
    private static final int MAX_RUNS = 8;

    // --- TEAM: light spiral + colour wave (~5 s) ---
    private static final int TEAM_END_TICK = 100;
    private static final int TEAM_SPIRAL_END_TICK = 80;
    private static final double TEAM_SPIRAL_RADIUS = 1.25D;
    private static final double TEAM_SPIRAL_HEIGHT = 6.0D;
    private static final int TEAM_WAVE_TICK = 16;
    private static final int TEAM_WAVE2_TICK = 52;
    private static final int TEAM_RING_END_TICK = 44;
    private static final double TEAM_RING_MAX_RADIUS = 8.0D;

    // --- GEAR: item rises, spins in the light, flies into the buyer (~4.5 s) ---
    private static final int GEAR_RISE_END_TICK = 30;
    private static final int GEAR_HOVER_END_TICK = 58;
    private static final int GEAR_FLIGHT_END_TICK = 82;
    private static final double GEAR_RISE_HEIGHT = 1.35D;
    private static final float GEAR_SCALE = 0.85F;
    /** Transform push cadence == interpolation duration (the DisplayAnimator law). */
    private static final int GEAR_PUSH_INTERVAL_TICKS = 2;
    /** Buyer farther than this from the altar at flight start → the gift bursts at the crown. */
    private static final double GEAR_FLIGHT_MAX_RANGE = 24.0D;

    // --- HEART: light fountain + bells (~6 s) ---
    private static final int HEART_END_TICK = 120;
    private static final int HEART_FOUNTAIN_END_TICK = 90;
    private static final int[] HEART_PILLAR_TICKS = {4, 10, 16};
    private static final int[] HEART_BELL_TICKS = {24, 44, 64};
    private static final float[] HEART_BELL_PITCHES = {0.8F, 1.0F, 1.25F};

    /** Existing altar Quasar emitters (see {@code assets/eclipse/quasar/emitters/}). */
    private static final ResourceLocation ALTAR_PILLAR = emitter("altar_pillar");

    /** House palette for the dust geometry: violet → gold. */
    private static final Vector3f DUST_VIOLET = new Vector3f(0.72F, 0.55F, 1.0F);
    private static final Vector3f DUST_GOLD = new Vector3f(1.0F, 0.83F, 0.45F);
    private static final Vector3f DUST_HEART = new Vector3f(1.0F, 0.38F, 0.55F);

    /** How a purchase is celebrated — derived from the offer's data shape, never by id. */
    public enum Category {
        /** Non-item team offer: rising light spiral + colour wave. */
        TEAM,
        /** Item offer: the bought item rises, spins in the light and flies into the buyer. */
        GEAR,
        /** Heart fragment (VitaeShardItem) / special: light fountain + bells. */
        HEART
    }

    /** Live runs (server thread only); several buyers may celebrate concurrently. */
    private static final List<Run> RUNS = new ArrayList<>();
    /** UUIDs of gift displays spawned THIS session; tagged joiners outside it are strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private AltarBuyCeremony() {}

    private static ResourceLocation emitter(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name);
    }

    // ------------------------------------------------------------------ public API

    /**
     * Arms the post-purchase ceremony for a SUCCESSFUL buy (the caller — {@code
     * AltarPayloads.handleBuy} — already verified the purse was charged). Starts after
     * the {@value #START_DELAY_TICKS}t UI grace so the panel animation lands first.
     */
    public static void begin(ServerPlayer buyer, BlockPos altarPos, ShardEconomy.Offer offer) {
        if (!(buyer.level() instanceof ServerLevel level)) {
            return;
        }
        while (RUNS.size() >= MAX_RUNS) {
            RUNS.remove(0).finish();
        }
        RUNS.add(new Run(level, altarPos, buyer, offer));
        EclipseMod.LOGGER.info("Altar buy ceremony armed: {} bought '{}' ({}) at {}",
                buyer.getScoreboardName(), offer.id(), categoryOf(offer),
                altarPos.toShortString());
    }

    /**
     * F-074 data-driven category mapping (see the class doc): non-item offers are TEAM
     * ceremonies, {@link VitaeShardItem} rewards are the HEART fountain, every other
     * item reward is GEAR. New offers pick their ceremony automatically from their
     * {@link ShardEconomy.Offer} shape — no id list to maintain.
     */
    public static Category categoryOf(ShardEconomy.Offer offer) {
        if (offer.item() == null) {
            return Category.TEAM;
        }
        Item item = offer.item().get();
        if (item instanceof VitaeShardItem) {
            return Category.HEART;
        }
        return Category.GEAR;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: displays that made it to disk are swept by the join check on
        // the next boot (they can never be adopted — LIVE_DISPLAYS is cleared here).
        for (Run run : RUNS) {
            run.discardDisplay();
        }
        RUNS.clear();
        LIVE_DISPLAYS.clear();
    }

    /** StormDebrisFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.ItemDisplay
                && entity.getTags().contains(ENTITY_TAG)
                && !LIVE_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (RUNS.isEmpty()) {
            return;
        }
        Iterator<Run> iterator = RUNS.iterator();
        while (iterator.hasNext()) {
            Run run = iterator.next();
            if (run.level.getServer() != event.getServer()) {
                continue;
            }
            run.tick();
            if (run.done) {
                iterator.remove();
            }
        }
    }

    // ------------------------------------------------------------------ the run

    private static final class Run {
        final ServerLevel level;
        final BlockPos altarPos;
        /** Altar crown — every beat is anchored just above the stone. */
        final Vec3 crown;
        final Category category;
        final UUID buyerId;
        final ItemStack gift;

        /** Ticks until the first beat (UI grace), then {@link #age} counts the script. */
        int delay = START_DELAY_TICKS;
        int age = -1;
        boolean done;

        @Nullable
        Display.ItemDisplay display;
        /** Cumulative spin of the gift display (deg) — accelerates over the phases. */
        float spinDeg;
        /** Flight-phase anchor: where the hover ended, so the flight eases from there. */
        @Nullable
        Vec3 flightFrom;
        @Nullable
        Vec3 flightTo;
        boolean flightAborted;

        Run(ServerLevel level, BlockPos altarPos, ServerPlayer buyer, ShardEconomy.Offer offer) {
            this.level = level;
            this.altarPos = altarPos;
            this.crown = new Vec3(altarPos.getX() + 0.5D, altarPos.getY() + 1.15D,
                    altarPos.getZ() + 0.5D);
            this.category = categoryOf(offer);
            this.buyerId = buyer.getUUID();
            this.gift = offer.item() == null
                    ? ItemStack.EMPTY : new ItemStack(offer.item().get());
        }

        void tick() {
            if (this.delay > 0) {
                this.delay--;
                return;
            }
            this.age++;
            if (this.age == 0) {
                beatOpening();
            }
            switch (this.category) {
                case TEAM -> tickTeam();
                case GEAR -> tickGear();
                case HEART -> tickHeart();
            }
        }

        /** Shared t=0 beat: the altar answers — beam + chime + the model's gift bow. */
        private void beatOpening() {
            quasar(S2CQuasarPayload.ALTAR_BEAM, this.crown);
            sound(SoundEvents.AMETHYST_BLOCK_CHIME, 1.0F, 1.1F);
            dev.projecteclipse.eclipse.ritual.AltarModelTriggers.gift(this.level);
            // WAVE3 (F-103 C): category-tinted Photon bloom over the crown — the client
            // row in veilfx/Wave3FxRows re-derives this cue id (a = Category ordinal).
            FxPayloads.sendFxEvent(this.level, dev.projecteclipse.eclipse.network.fx.FxCues
                    .cue("wave3_altar_buy"), this.crown, this.category.ordinal(), 0.0F, FX_RANGE);
        }

        // ------------------------------------------------------------ TEAM

        /** Rising two-arm light spiral + violet→gold colour wave over the ground. */
        private void tickTeam() {
            if (this.age <= TEAM_SPIRAL_END_TICK && this.age % 2 == 0) {
                double t = this.age / (double) TEAM_SPIRAL_END_TICK;
                double y = this.crown.y + t * TEAM_SPIRAL_HEIGHT;
                double radius = TEAM_SPIRAL_RADIUS * (1.0D - 0.35D * t);
                double angle = this.age * 0.30D;
                for (int arm = 0; arm < 2; arm++) {
                    double a = angle + arm * Math.PI;
                    double x = this.crown.x + Math.cos(a) * radius;
                    double z = this.crown.z + Math.sin(a) * radius;
                    this.level.sendParticles(ParticleTypes.END_ROD, x, y, z, 1,
                            0.02D, 0.02D, 0.02D, 0.0D);
                    this.level.sendParticles(dust(mix(DUST_VIOLET, DUST_GOLD, (float) t), 1.1F),
                            x, y + 0.15D, z, 1, 0.05D, 0.05D, 0.05D, 0.0D);
                }
            }
            if (this.age == TEAM_WAVE_TICK) {
                // Colour wave part 1: the screen-space ring. NOT the reserved (1.0, 50)
                // giant signature — that pair belongs to the intro/credits burst seam.
                FxPayloads.sendFxEvent(this.level, FxPayloads.FX_SHOCKWAVE,
                        this.crown, 0.5F, 26.0F, FX_RANGE);
                sound(SoundEvents.BEACON_ACTIVATE, 0.8F, 1.2F);
            }
            if (this.age >= TEAM_WAVE_TICK && this.age <= TEAM_RING_END_TICK
                    && this.age % 2 == 0) {
                // Colour wave part 2: a physical dust ring rolling outward at ankle height.
                double t = (this.age - TEAM_WAVE_TICK)
                        / (double) (TEAM_RING_END_TICK - TEAM_WAVE_TICK);
                double radius = 1.0D + t * (TEAM_RING_MAX_RADIUS - 1.0D);
                DustParticleOptions ring = dust(mix(DUST_VIOLET, DUST_GOLD, (float) t), 1.3F);
                for (int i = 0; i < 16; i++) {
                    double a = Math.PI * 2.0D * i / 16 + t * 0.8D;
                    this.level.sendParticles(ring,
                            this.crown.x + Math.cos(a) * radius,
                            this.altarPos.getY() + 0.25D,
                            this.crown.z + Math.sin(a) * radius,
                            1, 0.08D, 0.02D, 0.08D, 0.0D);
                }
            }
            if (this.age == TEAM_WAVE2_TICK) {
                FxPayloads.sendFxEvent(this.level, FxPayloads.FX_SHOCKWAVE,
                        this.crown, 0.32F, 20.0F, FX_RANGE);
                sound(SoundEvents.BEACON_POWER_SELECT, 0.7F, 1.35F);
            }
            if (this.age == TEAM_SPIRAL_END_TICK + 4) {
                quasar(S2CQuasarPayload.ALTAR_LEVELUP_RING, this.crown.add(0.0D, 0.4D, 0.0D));
                sound(SoundEvents.AMETHYST_BLOCK_CHIME, 0.8F, 1.5F);
            }
            if (this.age >= TEAM_END_TICK) {
                finish();
            }
        }

        // ------------------------------------------------------------ GEAR

        /** The bought item rises as an ItemDisplay, spins in a light spot, flies home. */
        private void tickGear() {
            if (this.age == 0) {
                spawnGift();
            }
            Display.ItemDisplay gift = this.display;
            if (gift == null || gift.isRemoved()) {
                // Display lost (spawn refused, dimension unload, /kill): end quietly.
                if (this.age > 0) {
                    finish();
                }
                return;
            }

            // Spin accelerates per phase: presentation (slow) → spotlight → flight (fast).
            this.spinDeg += this.age <= GEAR_RISE_END_TICK ? 5.0F
                    : this.age <= GEAR_HOVER_END_TICK ? 11.0F : 17.0F;

            if (this.age == GEAR_HOVER_END_TICK) {
                armFlight();
            }
            if (this.age % GEAR_PUSH_INTERVAL_TICKS == 0) {
                gift.setTransformationInterpolationDelay(0);
                gift.setTransformationInterpolationDuration(GEAR_PUSH_INTERVAL_TICKS);
                gift.setTransformation(gearPose(this.age + GEAR_PUSH_INTERVAL_TICKS));
            }

            // Light spot: a slow ring of white motes circling the presented item.
            if (this.age <= GEAR_HOVER_END_TICK && this.age % 4 == 0) {
                Vec3 at = gearWorldPos(this.age);
                double a = this.age * 0.45D;
                this.level.sendParticles(ParticleTypes.END_ROD,
                        at.x + Math.cos(a) * 0.7D, at.y - 0.1D, at.z + Math.sin(a) * 0.7D,
                        1, 0.02D, 0.02D, 0.02D, 0.0D);
                this.level.sendParticles(dust(DUST_GOLD, 0.9F),
                        at.x - Math.cos(a) * 0.7D, at.y + 0.2D, at.z - Math.sin(a) * 0.7D,
                        1, 0.04D, 0.04D, 0.04D, 0.0D);
            }
            if (this.age == GEAR_RISE_END_TICK) {
                sound(SoundEvents.AMETHYST_BLOCK_CHIME, 0.9F, 1.4F);
            }
            // Flight trail into the buyer.
            if (this.age > GEAR_HOVER_END_TICK && this.age % 2 == 0) {
                Vec3 at = gearWorldPos(this.age);
                this.level.sendParticles(ParticleTypes.END_ROD, at.x, at.y, at.z,
                        1, 0.03D, 0.03D, 0.03D, 0.0D);
            }
            if (this.age >= GEAR_FLIGHT_END_TICK) {
                beatGearCatch();
                finish();
            }
        }

        private void spawnGift() {
            Display.ItemDisplay gift = EntityType.ITEM_DISPLAY.create(this.level);
            if (gift == null) {
                return;
            }
            gift.getSlot(0).set(this.gift.copy());
            gift.moveTo(this.crown.x, this.crown.y, this.crown.z, 0.0F, 0.0F);
            gift.addTag(ENTITY_TAG);
            DisplayBrightnessFx.set(gift, 15, 15, 2.0F);
            gift.setTransformationInterpolationDelay(0);
            gift.setTransformationInterpolationDuration(0);
            gift.setTransformation(gearPose(0));
            LIVE_DISPLAYS.add(gift.getUUID());
            this.level.addFreshEntity(gift);
            this.display = gift;
        }

        /** Locks the flight endpoints the moment the hover ends (buyer may keep moving). */
        private void armFlight() {
            this.flightFrom = gearTranslation(GEAR_HOVER_END_TICK);
            ServerPlayer buyer = buyer();
            if (buyer == null
                    || buyer.position().distanceToSqr(this.crown) > GEAR_FLIGHT_MAX_RANGE
                            * GEAR_FLIGHT_MAX_RANGE) {
                this.flightAborted = true; // gift bursts at the crown instead
                this.flightTo = this.flightFrom;
                return;
            }
            this.flightTo = buyer.position().add(0.0D, 1.1D, 0.0D).subtract(this.crown);
        }

        /** Gift translation (relative to the crown mount) as a pure function of age. */
        private Vec3 gearTranslation(int t) {
            if (t <= GEAR_RISE_END_TICK) {
                double raw = Mth.clamp(t / (double) GEAR_RISE_END_TICK, 0.0D, 1.0D);
                double eased = 1.0D - (1.0D - raw) * (1.0D - raw) * (1.0D - raw);
                return new Vec3(0.0D, 0.1D + eased * GEAR_RISE_HEIGHT, 0.0D);
            }
            if (t <= GEAR_HOVER_END_TICK || this.flightFrom == null || this.flightTo == null) {
                double bob = Math.sin((t - GEAR_RISE_END_TICK) * 0.35D) * 0.08D;
                return new Vec3(0.0D, 0.1D + GEAR_RISE_HEIGHT + bob, 0.0D);
            }
            double raw = Mth.clamp((t - GEAR_HOVER_END_TICK)
                    / (double) (GEAR_FLIGHT_END_TICK - GEAR_HOVER_END_TICK), 0.0D, 1.0D);
            double eased = raw * raw * (3.0D - 2.0D * raw);
            // Live-retarget toward the buyer so the catch lands even while they move.
            ServerPlayer buyer = buyer();
            if (!this.flightAborted && buyer != null) {
                this.flightTo = buyer.position().add(0.0D, 1.1D, 0.0D).subtract(this.crown);
            }
            return new Vec3(
                    Mth.lerp(eased, this.flightFrom.x, this.flightTo.x),
                    Mth.lerp(eased, this.flightFrom.y, this.flightTo.y)
                            + Math.sin(Math.PI * raw) * 0.6D,
                    Mth.lerp(eased, this.flightFrom.z, this.flightTo.z));
        }

        private float gearScale(int t) {
            if (t <= GEAR_RISE_END_TICK) {
                double raw = Mth.clamp(t / (double) GEAR_RISE_END_TICK, 0.0D, 1.0D);
                return (float) (0.3D + (GEAR_SCALE - 0.3D)
                        * (1.0D - (1.0D - raw) * (1.0D - raw)));
            }
            if (t <= GEAR_HOVER_END_TICK) {
                return GEAR_SCALE;
            }
            double raw = Mth.clamp((t - GEAR_HOVER_END_TICK)
                    / (double) (GEAR_FLIGHT_END_TICK - GEAR_HOVER_END_TICK), 0.0D, 1.0D);
            return (float) Mth.lerp(raw, GEAR_SCALE, 0.2D);
        }

        private Transformation gearPose(int t) {
            Vec3 translation = gearTranslation(t);
            float scale = gearScale(t);
            return new Transformation(
                    new Vector3f((float) translation.x, (float) translation.y,
                            (float) translation.z),
                    new Quaternionf().rotateY((float) Math.toRadians(this.spinDeg)),
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        private Vec3 gearWorldPos(int t) {
            return this.crown.add(gearTranslation(t));
        }

        /** The catch: burst + pickup pop at the buyer (or at the crown when aborted). */
        private void beatGearCatch() {
            ServerPlayer buyer = buyer();
            Vec3 at = !this.flightAborted && buyer != null
                    ? buyer.position().add(0.0D, 1.0D, 0.0D)
                    : gearWorldPos(GEAR_FLIGHT_END_TICK);
            quasar(S2CQuasarPayload.HEART_BURST, at);
            this.level.sendParticles(ParticleTypes.END_ROD, at.x, at.y, at.z,
                    10, 0.3D, 0.3D, 0.3D, 0.05D);
            this.level.playSound(null, BlockPos.containing(at), SoundEvents.ITEM_PICKUP,
                    SoundSource.PLAYERS, 0.9F, 1.0F);
            this.level.playSound(null, BlockPos.containing(at), SoundEvents.PLAYER_LEVELUP,
                    SoundSource.PLAYERS, 0.45F, 1.6F);
        }

        // ------------------------------------------------------------ HEART

        /** Heart fragment / special: a taller light fountain + bells. */
        private void tickHeart() {
            if (this.age == 0) {
                sound(SoundEvents.BELL_RESONATE, 1.0F, 0.7F);
            }
            for (int pillar = 0; pillar < HEART_PILLAR_TICKS.length; pillar++) {
                if (this.age == HEART_PILLAR_TICKS[pillar]) {
                    quasar(ALTAR_PILLAR, this.crown.add(0.0D, pillar * 2.2D, 0.0D));
                }
            }
            if (this.age <= HEART_FOUNTAIN_END_TICK && this.age % 3 == 0) {
                // Directed fountain jets (count=0 → dx/dy/dz is the velocity vector).
                for (int jet = 0; jet < 3; jet++) {
                    double a = (this.age * 0.7D) + jet * (Math.PI * 2.0D / 3.0D);
                    this.level.sendParticles(ParticleTypes.END_ROD,
                            this.crown.x + Math.cos(a) * 0.25D, this.crown.y,
                            this.crown.z + Math.sin(a) * 0.25D,
                            0, Math.cos(a) * 0.12D, 1.0D, Math.sin(a) * 0.12D, 0.32D);
                }
                this.level.sendParticles(dust(DUST_HEART, 1.2F),
                        this.crown.x, this.crown.y + 1.6D, this.crown.z,
                        2, 0.5D, 0.9D, 0.5D, 0.0D);
            }
            for (int bell = 0; bell < HEART_BELL_TICKS.length; bell++) {
                if (this.age == HEART_BELL_TICKS[bell]) {
                    sound(SoundEvents.AMETHYST_BLOCK_CHIME, 1.0F, HEART_BELL_PITCHES[bell]);
                    sound(SoundEvents.BELL_RESONATE, 0.6F, HEART_BELL_PITCHES[bell]);
                }
            }
            if (this.age == 30) {
                quasar(S2CQuasarPayload.HEART_BURST, this.crown.add(0.0D, 1.2D, 0.0D));
            }
            if (this.age > HEART_FOUNTAIN_END_TICK && this.age % 4 == 0) {
                // Settle: pink-gold ash drifting back down around the altar.
                this.level.sendParticles(dust(mix(DUST_HEART, DUST_GOLD, 0.5F), 1.0F),
                        this.crown.x, this.crown.y + 2.0D, this.crown.z,
                        3, 1.1D, 0.8D, 1.1D, 0.0D);
            }
            if (this.age == HEART_END_TICK - 8) {
                sound(SoundEvents.BELL_RESONATE, 0.5F, 1.4F);
            }
            if (this.age >= HEART_END_TICK) {
                finish();
            }
        }

        // ------------------------------------------------------------ helpers

        @Nullable
        private ServerPlayer buyer() {
            ServerPlayer player = this.level.getServer().getPlayerList().getPlayer(this.buyerId);
            return player != null && player.level() == this.level ? player : null;
        }

        private void quasar(ResourceLocation emitterId, Vec3 pos) {
            PacketDistributor.sendToPlayersNear(this.level, null, pos.x, pos.y, pos.z,
                    FX_RANGE, new S2CQuasarPayload(emitterId, pos));
        }

        private void sound(SoundEvent sound, float volume, float pitch) {
            this.level.playSound(null, this.altarPos, sound, SoundSource.BLOCKS, volume, pitch);
        }

        private static DustParticleOptions dust(Vector3f color, float size) {
            return new DustParticleOptions(color, size);
        }

        private static Vector3f mix(Vector3f from, Vector3f to, float t) {
            return new Vector3f(
                    Mth.lerp(t, from.x(), to.x()),
                    Mth.lerp(t, from.y(), to.y()),
                    Mth.lerp(t, from.z(), to.z()));
        }

        void finish() {
            discardDisplay();
            this.done = true;
        }

        void discardDisplay() {
            Display.ItemDisplay gift = this.display;
            if (gift != null) {
                LIVE_DISPLAYS.remove(gift.getUUID());
                if (!gift.isRemoved()) {
                    gift.discard();
                }
                this.display = null;
            }
        }
    }
}
