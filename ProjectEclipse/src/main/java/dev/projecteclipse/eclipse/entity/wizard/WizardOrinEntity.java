package dev.projecteclipse.eclipse.entity.wizard;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MoveTowardsRestrictionGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Orin the Sun-Reader / Orin der Sonnenleser — the hermit astronomer of the mountain
 * observatory (W4-WIZARD; {@code docs/plans_v3/ideas_wave4/IDEA-19_wand.md} §3): a
 * NEUTRAL named NPC ({@code eclipse:wizard_orin}, id FROZEN) who gates the veil-wand
 * catalyst behind an earn-or-take choice.
 *
 * <p><b>Neutral hermit</b>: wanders his observatory (leashed via
 * {@link #restrictTo(BlockPos, int)} + {@link MoveTowardsRestrictionGoal}), gazes at the
 * sky (the {@code idle} sky-gaze loop), watches players who come close
 * ({@link LookAtPlayerGoal} + a pitched-villager greeting hum, once per player per
 * ~minute), and trades nothing.</p>
 *
 * <p><b>Dialogue</b>: right-click cycles four localized eclipse riddles
 * ({@code dialogue.eclipse.wizard_orin.1..4}, per-player rotation) as an "Orin:" chat
 * caption. While the player has not yet earned a catalyst, every fourth line is replaced
 * by the fetch-quest hint carrying the live remaining counts.</p>
 *
 * <p><b>Fetch quest</b> (once per player, ledger in {@link WizardData}): bring
 * {@value #QUEST_AMETHYST} amethyst shards + {@value #QUEST_UMBRAL} umbral shard —
 * right-clicking with them in inventory consumes both and hands over one
 * {@code eclipse:wizard_catalyst}. The grant is recorded BEFORE the item spawns (no dupe
 * window), and {@code /dev wizard resetquest} re-opens the ledger.</p>
 *
 * <p><b>Or take it</b>: damage from a player provokes him. He stands his ground and
 * answers with <b>star_call</b> — a telegraphed mini star shower (the raise anim +
 * rising chimes for {@value #STAR_CALL_TELEGRAPH_TICKS}t, then
 * {@value #STAR_CALL_BOLTS} visual sky-bolts via the frozen {@code FX_LIGHTNING_STRIKE}
 * payload raining over the attacker's marked zone, {@value #STAR_CALL_DAMAGE} dmg near
 * each impact). The attack deliberately quotes the Sternenfall wand path (IDEA-19 §2 C:
 * "the boss teaches the player what the wand can become"). On death he drops exactly ONE
 * catalyst ({@link #dropCustomDeathLoot}) and {@link WizardService} respawns him at his
 * hut the next overworld day.</p>
 */
public class WizardOrinEntity extends EclipseGeoMob {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "wizard_orin";

    public static final String ANIM_STAR_CALL = "star_call";
    public static final String ANIM_HURT = "hurt";

    /** Fetch quest cost (IDEA-19 §1.3 economy sink, resolved against live registries). */
    public static final int QUEST_AMETHYST = 8;
    public static final int QUEST_UMBRAL = 1;

    /** Scripted sit-down-fade death length ({@code animation.wizard_orin.death} = 2.0 s). */
    public static final int DEATH_DURATION_TICKS = 40;

    /** How far from home Orin will wander (restriction radius, blocks). */
    public static final int HOME_RADIUS = 10;

    private static final int STAR_CALL_COOLDOWN_TICKS = 140;
    private static final int STAR_CALL_TELEGRAPH_TICKS = 25;
    private static final int STAR_CALL_BOLTS = 8;
    private static final int STAR_CALL_BOLT_INTERVAL = 5;
    private static final double STAR_CALL_ZONE_RADIUS = 3.5D;
    private static final double STAR_CALL_HIT_RADIUS = 2.2D;
    private static final float STAR_CALL_DAMAGE = 5.0F;
    /** Provocation memory: calm down after this long without being hurt again. */
    private static final int PROVOKED_TICKS = 600;
    private static final double GREET_RANGE = 6.0D;
    private static final int GREET_COOLDOWN_TICKS = 1200;
    private static final int DIALOGUE_LINES = 4;

    /** True while the star_call raise telegraph runs (hat star + staff tip flare cue). */
    private static final EntityDataAccessor<Boolean> DATA_CASTING =
            SynchedEntityData.defineId(WizardOrinEntity.class, EntityDataSerializers.BOOLEAN);

    // --- transient server state (deliberately NOT persisted: a restart calms him) ---
    @Nullable
    private UUID provokedBy;
    private int provokedTicks;
    private int castCooldown = 60;
    private int telegraphTimer = -1;
    private int boltsLeft;
    private int boltTimer;
    @Nullable
    private Vec3 starZone;
    private final Map<UUID, Integer> dialogueCursor = new HashMap<>();
    private final Map<UUID, Long> greetedAt = new HashMap<>();

    public WizardOrinEntity(EntityType<? extends WizardOrinEntity> entityType, Level level) {
        super(entityType, level);
        this.setPersistenceRequired();
    }

    /** A sturdy but killable hermit: 60 HP, no melee, sure-footed on his summit. */
    public static AttributeSupplier.Builder createAttributes() {
        return createMobAttributes()
                .add(Attributes.MAX_HEALTH, 60.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.28D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 0.4D)
                .add(Attributes.FOLLOW_RANGE, 48.0D);
    }

    /** Applies the NPC dressing every spawner path shares (service spawn + /summon). */
    public void initAsNpc(BlockPos home) {
        this.setCustomName(Component.translatable("name.eclipse.wizard_orin"));
        this.setCustomNameVisible(true); // NameTagHider only hides PLAYER tags — safe.
        this.restrictTo(home, HOME_RADIUS);
        this.setPersistenceRequired();
    }

    // --- GeckoLib wiring (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(ANIM_STAR_CALL, EclipseGeoAnimations.once(GEO_ID, ANIM_STAR_CALL));
        action.triggerableAnim(ANIM_HURT, EclipseGeoAnimations.once(GEO_ID, ANIM_HURT));
    }

    // --- AI (gentle observatory life; combat is scripted in tick()) ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(3, new MoveTowardsRestrictionGoal(this, 1.0D));
        this.goalSelector.addGoal(4, new WaterAvoidingRandomStrollGoal(this, 0.6D));
        this.goalSelector.addGoal(5, new LookAtPlayerGoal(this, Player.class, 8.0F, 0.08F));
        this.goalSelector.addGoal(6, new RandomLookAroundGoal(this));
        // No target goals: he never hunts. star_call answers his attacker from tick().
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_CASTING, false);
    }

    public boolean isCasting() {
        return this.entityData.get(DATA_CASTING);
    }

    private void setCasting(boolean casting) {
        this.entityData.set(DATA_CASTING, casting);
    }

    // --- ticking (greeting + the scripted star_call defense) ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        tickGreeting(serverLevel);
        tickProvocation(serverLevel);
        tickStarCall(serverLevel);
    }

    /** A small "hmm?" hum for players stepping close — once per player per minute. */
    private void tickGreeting(ServerLevel level) {
        if (this.tickCount % 10 != 0 || isProvoked()) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || !player.isAlive()
                    || player.distanceToSqr(this) > GREET_RANGE * GREET_RANGE) {
                continue;
            }
            long last = this.greetedAt.getOrDefault(player.getUUID(), Long.MIN_VALUE);
            if (level.getGameTime() - last < GREET_COOLDOWN_TICKS) {
                continue;
            }
            this.greetedAt.put(player.getUUID(), level.getGameTime());
            this.getLookControl().setLookAt(player, 30.0F, 30.0F);
            // Vanilla aliases (no sounds.json edits): a low villager hum + a star chime.
            level.playSound(null, this.blockPosition(), SoundEvents.VILLAGER_AMBIENT,
                    SoundSource.NEUTRAL, 0.8F, 0.78F);
            level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.NEUTRAL, 0.6F, 1.4F);
        }
    }

    /** Provocation memory: forget an attacker who is gone/dead/quiet, and heal up. */
    private void tickProvocation(ServerLevel level) {
        if (this.provokedBy == null) {
            return;
        }
        ServerPlayer attacker = resolveAttacker(level);
        boolean gone = attacker == null || !attacker.isAlive() || attacker.isSpectator()
                || attacker.distanceToSqr(this) > 48.0D * 48.0D;
        if (gone || --this.provokedTicks <= 0) {
            EclipseMod.LOGGER.info("Orin calms down (attacker {})", gone ? "gone" : "quiet");
            this.provokedBy = null;
            this.telegraphTimer = -1;
            this.boltsLeft = 0;
            this.starZone = null;
            setCasting(false);
            this.setHealth(this.getMaxHealth()); // The mountain mends its keeper.
        }
    }

    private boolean isProvoked() {
        return this.provokedBy != null;
    }

    @Nullable
    private ServerPlayer resolveAttacker(ServerLevel level) {
        return this.provokedBy == null ? null
                : level.getServer().getPlayerList().getPlayer(this.provokedBy);
    }

    /**
     * The scripted star_call cycle: cooldown → {@value #STAR_CALL_TELEGRAPH_TICKS}t
     * rooted raise (anim + rising chime + zone marker particles = the fairness
     * telegraph) → {@value #STAR_CALL_BOLTS} sky-bolts released over the locked zone,
     * one per {@value #STAR_CALL_BOLT_INTERVAL}t.
     */
    private void tickStarCall(ServerLevel level) {
        // Release phase: rain the remaining bolts over the locked zone.
        if (this.boltsLeft > 0) {
            if (--this.boltTimer <= 0) {
                this.boltTimer = STAR_CALL_BOLT_INTERVAL;
                this.boltsLeft--;
                dropStarBolt(level);
            }
            return;
        }
        ServerPlayer attacker = resolveAttacker(level);
        if (attacker == null) {
            return;
        }
        // Telegraph phase: rooted raise, zone sparkles where the stars will land.
        if (this.telegraphTimer >= 0) {
            this.getNavigation().stop();
            this.getLookControl().setLookAt(attacker, 30.0F, 30.0F);
            if (this.starZone != null && this.telegraphTimer % 5 == 0) {
                int elapsed = STAR_CALL_TELEGRAPH_TICKS - this.telegraphTimer;
                float pitch = 0.9F + elapsed / (float) STAR_CALL_TELEGRAPH_TICKS * 0.8F;
                level.playSound(null, BlockPos.containing(this.starZone),
                        SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.NEUTRAL, 1.2F, pitch);
                level.sendParticles(ParticleTypes.END_ROD, this.starZone.x,
                        this.starZone.y + 0.4D, this.starZone.z,
                        6, STAR_CALL_ZONE_RADIUS * 0.5D, 0.2D, STAR_CALL_ZONE_RADIUS * 0.5D, 0.01D);
            }
            if (--this.telegraphTimer < 0) {
                setCasting(false);
                this.boltsLeft = STAR_CALL_BOLTS;
                this.boltTimer = 1;
                EclipseMod.LOGGER.info("Orin star_call released: {} bolts over ({})",
                        STAR_CALL_BOLTS, this.starZone == null ? "?" : this.starZone.toString());
            }
            return;
        }
        if (--this.castCooldown > 0) {
            return;
        }
        // Wind up a new shower on the attacker's current ground position.
        this.castCooldown = STAR_CALL_COOLDOWN_TICKS;
        this.telegraphTimer = STAR_CALL_TELEGRAPH_TICKS;
        this.starZone = attacker.position();
        setCasting(true);
        triggerAction(ANIM_STAR_CALL);
        this.getNavigation().stop();
        level.playSound(null, this.blockPosition(), SoundEvents.EVOKER_PREPARE_SUMMON,
                SoundSource.NEUTRAL, 0.9F, 1.5F);
        EclipseMod.LOGGER.info("Orin star_call telegraphed: {}t over ({}, {}, {})",
                STAR_CALL_TELEGRAPH_TICKS,
                String.format(java.util.Locale.ROOT, "%.1f", this.starZone.x),
                String.format(java.util.Locale.ROOT, "%.1f", this.starZone.y),
                String.format(java.util.Locale.ROOT, "%.1f", this.starZone.z));
    }

    /** One falling star: a thin sky ribbon (frozen FX payload) + burst + zone damage. */
    private void dropStarBolt(ServerLevel level) {
        if (this.starZone == null) {
            this.boltsLeft = 0;
            return;
        }
        double angle = this.random.nextDouble() * Math.PI * 2.0D;
        double radius = this.random.nextDouble() * STAR_CALL_ZONE_RADIUS;
        Vec3 impact = new Vec3(this.starZone.x + Math.cos(angle) * radius,
                this.starZone.y, this.starZone.z + Math.sin(angle) * radius);
        // Visual: a low-intensity veil-lightning ribbon reads as a falling star
        // (IDEA-19 §2 C tier 4 — the exact trick the Sternenfall wand path will use).
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.25F, 0.0F, 96.0D);
        level.sendParticles(ParticleTypes.END_ROD, impact.x, impact.y + 0.3D, impact.z,
                10, 0.3D, 0.4D, 0.3D, 0.08D);
        level.sendParticles(ParticleTypes.FIREWORK, impact.x, impact.y + 0.2D, impact.z,
                6, 0.25D, 0.2D, 0.25D, 0.05D);
        level.playSound(null, BlockPos.containing(impact), SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.NEUTRAL, 1.0F, 1.6F);
        for (LivingEntity target : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(BlockPos.containing(impact)).inflate(STAR_CALL_HIT_RADIUS),
                entity -> entity != this && entity.isAlive())) {
            target.hurt(level.damageSources().indirectMagic(this, this), STAR_CALL_DAMAGE);
        }
    }

    // --- interaction (dialogue + fetch quest) ---

    @Override
    protected InteractionResult mobInteract(Player player, InteractionHand hand) {
        if (hand != InteractionHand.MAIN_HAND || !this.isAlive()) {
            return super.mobInteract(player, hand);
        }
        if (this.level().isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(player instanceof ServerPlayer serverPlayer)
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return InteractionResult.CONSUME;
        }
        if (isProvoked()) {
            say(serverPlayer, Component.translatable("dialogue.eclipse.wizard_orin.provoked"));
            return InteractionResult.CONSUME;
        }
        if (tryQuestTurnIn(serverLevel, serverPlayer)) {
            return InteractionResult.CONSUME;
        }
        speakLine(serverLevel, serverPlayer);
        return InteractionResult.CONSUME;
    }

    /**
     * Fetch-quest turn-in: needs {@value #QUEST_AMETHYST} amethyst shards +
     * {@value #QUEST_UMBRAL} umbral shard in inventory, once per player. Returns true
     * only when the trade completed (items consumed, catalyst handed over).
     */
    private boolean tryQuestTurnIn(ServerLevel level, ServerPlayer player) {
        if (!WizardEntities.WIZARD_CATALYST.isBound()) {
            return false; // Registrar not wired: dialogue-only NPC until the line lands.
        }
        WizardData data = WizardData.get(level.getServer().overworld());
        Item umbral = umbralShardItem();
        if (data.hasCatalyst(player.getUUID())) {
            if (countItem(player, Items.AMETHYST_SHARD) >= QUEST_AMETHYST
                    && umbral != null && countItem(player, umbral) >= QUEST_UMBRAL) {
                say(player, Component.translatable("dialogue.eclipse.wizard_orin.quest_already"));
                return true;
            }
            return false;
        }
        if (umbral == null || countItem(player, Items.AMETHYST_SHARD) < QUEST_AMETHYST
                || countItem(player, umbral) < QUEST_UMBRAL) {
            return false;
        }
        // Ledger first, then consume, then hand over — a crash mid-way can lose the
        // trade (re-openable via /dev wizard resetquest) but can never dupe a catalyst.
        if (!data.grantCatalyst(player.getUUID())) {
            return false;
        }
        consumeItem(player, Items.AMETHYST_SHARD, QUEST_AMETHYST);
        consumeItem(player, umbral, QUEST_UMBRAL);
        ItemStack catalyst = new ItemStack(WizardEntities.WIZARD_CATALYST.get());
        if (!player.getInventory().add(catalyst)) {
            player.drop(catalyst, false);
        }
        say(player, Component.translatable("dialogue.eclipse.wizard_orin.quest_done"));
        this.getLookControl().setLookAt(player, 30.0F, 30.0F);
        triggerAction(ANIM_STAR_CALL); // A small ceremonial flourish over the hand-over.
        level.playSound(null, this.blockPosition(), SoundEvents.VILLAGER_CELEBRATE,
                SoundSource.NEUTRAL, 1.0F, 0.8F);
        level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.NEUTRAL, 1.2F, 1.3F);
        level.sendParticles(ParticleTypes.END_ROD, this.getX(), this.getY() + 1.8D, this.getZ(),
                20, 0.5D, 0.8D, 0.5D, 0.06D);
        EclipseMod.LOGGER.info("Orin fetch quest complete: {} traded {} amethyst + {} umbral for a catalyst",
                player.getScoreboardName(), QUEST_AMETHYST, QUEST_UMBRAL);
        return true;
    }

    /** Rotates the four riddles per player; unearned players get the quest hint 1-in-4. */
    private void speakLine(ServerLevel level, ServerPlayer player) {
        WizardData data = WizardData.get(level.getServer().overworld());
        int cursor = this.dialogueCursor.merge(player.getUUID(), 1, Integer::sum) - 1;
        boolean earned = data.hasCatalyst(player.getUUID());
        Component line;
        if (!earned && cursor % DIALOGUE_LINES == DIALOGUE_LINES - 1) {
            Item umbral = umbralShardItem();
            int haveAmethyst = countItem(player, Items.AMETHYST_SHARD);
            int haveUmbral = umbral == null ? 0 : countItem(player, umbral);
            line = Component.translatable("dialogue.eclipse.wizard_orin.quest_hint",
                    Math.max(0, QUEST_AMETHYST - haveAmethyst), Math.max(0, QUEST_UMBRAL - haveUmbral));
        } else {
            line = Component.translatable("dialogue.eclipse.wizard_orin." + (cursor % DIALOGUE_LINES + 1));
        }
        say(player, line);
        this.getLookControl().setLookAt(player, 30.0F, 30.0F);
        level.playSound(null, this.blockPosition(), SoundEvents.VILLAGER_TRADE,
                SoundSource.NEUTRAL, 0.7F, 0.75F);
    }

    /** "Orin: <line>" chat caption (gold name, per the NPC caption convention). */
    private void say(ServerPlayer player, Component line) {
        player.sendSystemMessage(Component.empty()
                .append(Component.translatable("name.eclipse.wizard_orin")
                        .withStyle(ChatFormatting.GOLD))
                .append(Component.literal(": ").withStyle(ChatFormatting.GOLD))
                .append(line.copy().withStyle(ChatFormatting.YELLOW)));
    }

    // --- inventory helpers (main + off hand + backpack rows) ---

    /** By-id lookup (zero compile-time coupling to the P4-owned registry entry). */
    @Nullable
    private static Item umbralShardItem() {
        return BuiltInRegistries.ITEM.getOptional(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "umbral_shard")).orElse(null);
    }

    private static int countItem(Player player, Item item) {
        int count = 0;
        for (int slot = 0; slot < player.getInventory().getContainerSize(); slot++) {
            ItemStack stack = player.getInventory().getItem(slot);
            if (stack.is(item)) {
                count += stack.getCount();
            }
        }
        return count;
    }

    private static void consumeItem(Player player, Item item, int amount) {
        int remaining = amount;
        for (int slot = 0; slot < player.getInventory().getContainerSize() && remaining > 0; slot++) {
            ItemStack stack = player.getInventory().getItem(slot);
            if (stack.is(item)) {
                int take = Math.min(remaining, stack.getCount());
                stack.shrink(take);
                remaining -= take;
            }
        }
        player.containerMenu.broadcastChanges();
    }

    // --- combat hooks (provocation + flinch) ---

    @Override
    public boolean hurt(DamageSource source, float amount) {
        boolean hurt = super.hurt(source, amount);
        if (hurt && !this.level().isClientSide && this.isAlive()) {
            if (source.getEntity() instanceof ServerPlayer attacker && !attacker.isSpectator()) {
                boolean fresh = this.provokedBy == null;
                this.provokedBy = attacker.getUUID();
                this.provokedTicks = PROVOKED_TICKS;
                if (fresh) {
                    this.castCooldown = Math.min(this.castCooldown, 30); // Answer promptly.
                    say(attacker, Component.translatable("dialogue.eclipse.wizard_orin.provoked"));
                    EclipseMod.LOGGER.info("Orin provoked by {}", attacker.getScoreboardName());
                }
            }
            if (this.telegraphTimer < 0) {
                triggerAction(ANIM_HURT); // Flinch, unless mid-raise (the cast reads through).
            }
        }
        return hurt;
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            setCasting(false);
            triggerAction(EclipseGeoAnimations.ANIM_DEATH); // Sit-down-fade, held.
            if (this.level() instanceof ServerLevel serverLevel) {
                WizardService.onWizardDied(serverLevel, this);
            }
            EclipseMod.LOGGER.info("Orin died ({}) — catalyst drop + next-day respawn scheduled",
                    damageSource.getMsgId());
        }
    }

    /** Scripted 40 t sit-down-fade, then the poof (Ferryman/Rift-Warden precedent). */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        this.setDeltaMovement(0.0D, Math.min(this.getDeltaMovement().y, 0.0D), 0.0D);
        if (this.deathTime % 5 == 0) {
            serverLevel.sendParticles(ParticleTypes.END_ROD,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 3, 0.3D, 0.5D, 0.3D, 0.02D);
        }
        if (this.deathTime >= DEATH_DURATION_TICKS && !this.isRemoved()) {
            serverLevel.sendParticles(ParticleTypes.FIREWORK,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 20, 0.4D, 0.8D, 0.4D, 0.08D);
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /**
     * The guaranteed take-path drop: exactly ONE catalyst at the corpse, independent of
     * loot tables, kill credit and looting (IDEA-19 §3 "1× catalyst guaranteed on death").
     */
    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        if (!WizardEntities.WIZARD_CATALYST.isBound()) {
            EclipseMod.LOGGER.warn("Orin death drop skipped: eclipse:wizard_catalyst not registered "
                    + "(apply docs/plans_v3/wiring/W4-WIZARD_wiring.md)");
            return;
        }
        ItemEntity drop = this.spawnAtLocation(new ItemStack(WizardEntities.WIZARD_CATALYST.get()));
        if (drop != null) {
            drop.setUnlimitedLifetime(); // Never let the summit wind despawn the gate item.
        }
    }

    // --- chassis ---

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // The hermit keeps his watch.
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void doPush(Entity entity) {
        // Never shoves guests around the observatory.
    }

    @Override
    public boolean isInvulnerableTo(DamageSource source) {
        // Environmental deaths would strand the catalyst loop in a lava crack; players
        // (and /kill) remain the only ways to take him down.
        if (source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return false;
        }
        if (source.getEntity() instanceof Player) {
            return super.isInvulnerableTo(source);
        }
        return true;
    }

    // --- sounds (villager family pitched down — the wiring doc lists the aliases) ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return isProvoked() ? null : SoundEvents.VILLAGER_AMBIENT;
    }

    @Override
    public float getVoicePitch() {
        return 0.78F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.VILLAGER_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.VILLAGER_DEATH;
    }

    // --- persistence (home restriction survives restarts) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        if (this.hasRestriction()) {
            compound.putLong("HomePos", this.getRestrictCenter().asLong());
        }
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("HomePos")) {
            this.restrictTo(BlockPos.of(compound.getLong("HomePos")), HOME_RADIUS);
        }
    }
}
