package de.sonic0810.goobymod.entity;

import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.api.GoobyAccessor;
import de.sonic0810.goobymod.api.event.GoobyGiftEvent;
import de.sonic0810.goobymod.api.event.GoobyTameEvent;
import de.sonic0810.goobymod.api.event.GoobyTierChangeEvent;
import de.sonic0810.goobymod.block.RabbitHutchBlock;
import de.sonic0810.goobymod.client.sound.GoobyPurrSound;
import de.sonic0810.goobymod.compat.CreateCompat;
import de.sonic0810.goobymod.entity.animation.GoobyAnimationState;
import de.sonic0810.goobymod.entity.animation.GoobyLocomotion;
import de.sonic0810.goobymod.entity.goals.GoobyAlertGoal;
import de.sonic0810.goobymod.entity.goals.GoobyDigGoal;
import de.sonic0810.goobymod.entity.goals.GoobyFamilyPlayGoal;
import de.sonic0810.goobymod.entity.goals.GoobyFetchGoal;
import de.sonic0810.goobymod.entity.goals.GoobyFollowParentGoal;
import de.sonic0810.goobymod.entity.goals.GoobyFollowOwnerGoal;
import de.sonic0810.goobymod.entity.goals.GoobyRandomSitGoal;
import de.sonic0810.goobymod.entity.goals.GoobyRhythmStrollGoal;
import de.sonic0810.goobymod.entity.goals.GoobyShelterGoal;
import de.sonic0810.goobymod.entity.goals.GoobySleepGoal;
import de.sonic0810.goobymod.entity.goals.GoobySocialGoal;
import de.sonic0810.goobymod.entity.goals.GoobyWildPanicGoal;
import de.sonic0810.goobymod.item.GoobyBallItem;
import de.sonic0810.goobymod.item.GoobyHandbookItem;
import de.sonic0810.goobymod.item.GoobyWhistleItem;
import de.sonic0810.goobymod.menu.GoobySatchelMenu;
import de.sonic0810.goobymod.network.GoobyNetwork;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItemTags;
import de.sonic0810.goobymod.registry.ModItems;
import de.sonic0810.goobymod.registry.ModParticles;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.EnumMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import javax.annotation.Nullable;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ItemParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.BlockTags;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.tags.FluidTags;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.MenuProvider;
import net.minecraft.world.SimpleContainer;
import net.minecraft.world.DifficultyInstance;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.damagesource.DamageTypes;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.AgeableMob;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityDimensions;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.SpawnGroupData;
import net.minecraft.world.entity.TamableAnimal;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.AvoidEntityGoal;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.SitWhenOrderedToGoal;
import net.minecraft.world.entity.ai.goal.TemptGoal;
import net.minecraft.world.entity.animal.Animal;
import net.minecraft.world.entity.animal.Rabbit;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.DyeItem;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.component.DyedItemColor;
import net.minecraft.world.item.crafting.Ingredient;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.ServerLevelAccessor;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.level.pathfinder.PathType;
import net.minecraft.world.level.pathfinder.WalkNodeEvaluator;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.Tags;
import net.neoforged.neoforge.common.NeoForge;
import org.joml.Vector3f;
import software.bernie.geckolib.animatable.GeoEntity;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.animation.RawAnimation;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * GOOBY — der dicke, grosse, niedliche Hase. Laechelt immer, will immer
 * gestreichelt werden, ist unverwundbar gegenueber Spielern und teleportiert
 * sich aus Gefahr. Frisst Nutella mit dem GANZEN Gesicht.
 *
 * <p>Seit 2.0 "Best Friends": echte Zaehmung (Nutella), Freundschaft 0-100 pro
 * Spieler-UUID (persistent), Pfeifen-Kommandos (Wander/Follow/Stay, nur fuer
 * den Besitzer), Geschenke mit Kosten + Cooldown, synchronisierte Huete.
 */
public class GoobyEntity extends TamableAnimal implements GeoEntity, MenuProvider, GoobyAccessor {
    public static final int MAX_SATISFACTION = 100;
    public static final int HAPPY_THRESHOLD = 60;
    public static final int PET_SATISFACTION = 15;
    public static final int NUTELLA_SATISFACTION = 30;

    public static final int MAX_FRIENDSHIP = 100;
    public static final int PET_FRIENDSHIP = 2;
    public static final int FEED_FRIENDSHIP = 8;
    public static final int CONVERT_FRIENDSHIP = 40;
    /** Streicheln zaehlt pro Spieler nur alle 5 Sekunden fuer die Freundschaft (Anti-Klickspam). */
    public static final int PET_FRIENDSHIP_COOLDOWN_TICKS = 100;
    /** Nach dem Aufwecken schlaeft Gooby mindestens 30 Sekunden lang nicht wieder ein. */
    public static final int SLEEP_SUPPRESS_TICKS = 600;
    /** Sichtbarer Schutz-Schreck nach einem abgefangenen Mob-Angriff. */
    public static final int GUARDIAN_PANIC_TICKS = 100;
    public static final int MAX_TRICK_PROFICIENCY = 3;
    public static final int TRAINING_COOLDOWN_TICKS = 40;
    public static final int TRICK_DOUBLE_CLICK_TICKS = 10;
    public static final int BABY_TREAT_GROWTH_TICKS = 2400;
    public static final int BABY_TUMBLE_COOLDOWN_TICKS = 1200;
    public static final byte SOCIAL_NONE = 0;
    public static final byte SOCIAL_GREETING_INITIATOR = 1;
    public static final byte SOCIAL_GREETING_MIRROR = 2;
    public static final byte SOCIAL_PLAY_CHASE = 3;
    public static final int SOCIAL_GREETING_TICKS = 32;
    public static final int SOCIAL_CHASE_TICKS = 600;
    public static final int SOCIAL_PAIR_COOLDOWN_TICKS = 6000;
    public static final int SATCHEL_SIZE = 4;
    public static final int GIFT_PICKUP_PRIORITY_TICKS = 200;
    /** Satisfaction-/Freundschafts-Bonus pro erfolgreichem Apport — mit Cooldown. */
    public static final int FETCH_SATISFACTION = 4;
    public static final int FETCH_FRIENDSHIP = 2;
    public static final int FETCH_REWARD_COOLDOWN_TICKS = 600;
    // Feedback-Wave: feste Low-Count-Budgets pro Trigger (keine Partikelflut)
    // plus Anti-Spam-Cooldowns. Konstanten sind public, damit die GameTests
    // Budget und Gating direkt gegen die Spawn-Aufrufe pruefen koennen.
    public static final int CONFETTI_TIER_UP_COUNT = 10;
    public static final int CONFETTI_TIER_UP_BEST_COUNT = 14;
    public static final int CONFETTI_TRICK_COUNT = 6;
    /** Zwischen zwei Trick-Konfetti-Salven liegen mindestens 5 Sekunden. */
    public static final int CONFETTI_TRICK_COOLDOWN_TICKS = 100;
    public static final int FLUFF_BRUSH_COUNT = 6;
    public static final int FLUFF_DRESS_UP_COUNT = 5;
    public static final int FLUFF_LANDING_COUNT = 6;
    public static final int MUSIC_NOTE_SPEAK_COUNT = 3;
    public static final int MUSIC_NOTE_DANCE_COUNT = 5;
    public static final int MUSIC_NOTE_PET_COUNT = 2;
    /** Streichel-Noten hoechstens alle 2 Sekunden — Klickspam bleibt stumm. */
    public static final int MUSIC_NOTE_PET_COOLDOWN_TICKS = 40;
    public static final float TREASURE_SCRAP_CHANCE = 0.05F;
    public static final int MAX_STORED_FRIENDSHIPS = 32;
    public static final int MAX_TRANSIENT_PLAYER_ENTRIES = 128;
    public static final int MAX_PARTNER_HISTORY_ENTRIES = 128;
    public static final String GIFT_PRIORITY_UNTIL_TAG = "GoobyModGiftPriorityUntil";
    private static final long TRANSIENT_PLAYER_STATE_TTL = 20L * 60L * 10L;
    private static final int MAX_SYNCED_ARGUMENT_LENGTH = 256;
    private static final int[][] ESCAPE_OFFSETS = {
            {0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1},
            {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
            {2, 0}, {-2, 0}, {0, 2}, {0, -2},
            {2, 1}, {2, -1}, {-2, 1}, {-2, -1}
    };

    private static final EntityDataAccessor<Integer> DATA_SATISFACTION =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.INT);
    private static final EntityDataAccessor<Boolean> DATA_SLEEPING =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_IN_HUTCH =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_SITTING =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_SAD =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_DIGGING =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<String> DATA_BUBBLE_KEY =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<Byte> DATA_COMMAND =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BYTE);
    /** Registry-Id des Hut-Items ("" = kein Hut) — synchronisiert, damit ALLE Spieler den Hut sehen. */
    private static final EntityDataAccessor<String> DATA_HAT =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<String> DATA_NECK =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<String> DATA_BACK =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<Byte> DATA_COAT =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BYTE);
    private static final EntityDataAccessor<Boolean> DATA_PANICKING =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_RECENTLY_WOKE =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<String> DATA_ACTIVE_PETTER =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<Byte> DATA_MOOD =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BYTE);
    private static final EntityDataAccessor<Boolean> DATA_ALERTING =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_SEEKING_SHELTER =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_SHAKING_WATER =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_HIDING_FROM_THUNDER =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<Boolean> DATA_SHY =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    private static final EntityDataAccessor<String> DATA_BUBBLE_ARG =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<Byte> DATA_SOCIAL_ACTION =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BYTE);
    private static final EntityDataAccessor<String> DATA_SOCIAL_PARTNER =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.STRING);
    private static final EntityDataAccessor<Boolean> DATA_SEEKING_TREASURE =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.BOOLEAN);
    /**
     * Getragener Apportier-Ball. Bewusst der Vanilla-ItemStack-Serializer
     * (bounded, gleiche Wire-Sicherheit wie ItemEntity/ItemFrame) — der Slot
     * traegt maximal einen kleinen Wurf-Stack, nie Fremd-NBT-Berge.
     */
    private static final EntityDataAccessor<ItemStack> DATA_CARRIED_BALL =
            SynchedEntityData.defineId(GoobyEntity.class, EntityDataSerializers.ITEM_STACK);

    private static final ResourceLocation HAPPY_SPEED_ID =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "happy_speed");
    private static final ResourceLocation ICON_FONT =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "icons");
    private static final AttributeModifier HAPPY_SPEED = new AttributeModifier(HAPPY_SPEED_ID, 0.30,
            AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL);

    // GeckoLib-Animationen
    protected static final RawAnimation ANIM_IDLE = RawAnimation.begin().thenLoop("animation.gooby.idle");
    // Legacy-Loop: fuer Adults durch die Gait-Clips walk/run ersetzt. Konstante
    // und JSON-Clip "animation.gooby.hop" bleiben bewusst erhalten, damit
    // Resource-Packs und externe Trigger auf den Namen weiter funktionieren.
    protected static final RawAnimation ANIM_HOP = RawAnimation.begin().thenLoop("animation.gooby.hop");
    protected static final RawAnimation ANIM_WALK = RawAnimation.begin().thenLoop("animation.gooby.walk");
    protected static final RawAnimation ANIM_RUN = RawAnimation.begin().thenLoop("animation.gooby.run");
    protected static final RawAnimation ANIM_SLEEP = RawAnimation.begin().thenLoop("animation.gooby.sleep");
    protected static final RawAnimation ANIM_SLEEP_CURL_TIGHT =
            RawAnimation.begin().thenLoop("animation.gooby.sleep_curl_tight");
    protected static final RawAnimation ANIM_SIT = RawAnimation.begin().thenLoop("animation.gooby.sit");
    protected static final RawAnimation ANIM_DIG = RawAnimation.begin().thenLoop("animation.gooby.dig");
    protected static final RawAnimation ANIM_SAD = RawAnimation.begin().thenLoop("animation.gooby.sad");
    protected static final RawAnimation ANIM_PET = RawAnimation.begin().thenPlay("animation.gooby.pet");
    protected static final RawAnimation ANIM_EAT = RawAnimation.begin().thenPlay("animation.gooby.eat");
    protected static final RawAnimation ANIM_WAVE = RawAnimation.begin().thenPlay("animation.gooby.wave");
    protected static final RawAnimation ANIM_LAND = RawAnimation.begin().thenPlay("animation.gooby.land");
    protected static final RawAnimation ANIM_BLINK = RawAnimation.begin().thenPlay("animation.gooby.blink");
    protected static final RawAnimation ANIM_EAR_TWITCH_L =
            RawAnimation.begin().thenPlay("animation.gooby.ear_twitch_l");
    protected static final RawAnimation ANIM_EAR_TWITCH_R =
            RawAnimation.begin().thenPlay("animation.gooby.ear_twitch_r");
    protected static final RawAnimation ANIM_NOSE_WIGGLE =
            RawAnimation.begin().thenPlay("animation.gooby.nose_wiggle");
    protected static final RawAnimation ANIM_STRETCH_YAWN =
            RawAnimation.begin().thenPlay("animation.gooby.stretch_yawn");
    protected static final RawAnimation ANIM_TAIL_WIGGLE =
            RawAnimation.begin().thenPlay("animation.gooby.tail_wiggle");
    protected static final RawAnimation ANIM_SIT_DOWN =
            RawAnimation.begin().thenPlay("animation.gooby.sit_down");
    protected static final RawAnimation ANIM_STAND_UP =
            RawAnimation.begin().thenPlay("animation.gooby.stand_up");
    protected static final RawAnimation ANIM_SLEEP_DOWN =
            RawAnimation.begin().thenPlay("animation.gooby.sleep_down");
    protected static final RawAnimation ANIM_WAKE_UP =
            RawAnimation.begin().thenPlay("animation.gooby.wake_up");
    protected static final RawAnimation ANIM_EARS_DROOP =
            RawAnimation.begin().thenLoop("animation.gooby.ears_droop");
    protected static final RawAnimation ANIM_BEG =
            RawAnimation.begin().thenLoop("animation.gooby.beg");
    protected static final RawAnimation ANIM_HAPPY_BOUNCE =
            RawAnimation.begin().thenPlay("animation.gooby.happy_bounce_in_place");
    protected static final RawAnimation ANIM_ALERT =
            RawAnimation.begin().thenLoop("animation.gooby.alert");
    protected static final RawAnimation ANIM_SHAKE_OFF_WATER =
            RawAnimation.begin().thenPlay("animation.gooby.shake_off_water");
    protected static final RawAnimation ANIM_HIDE_BEHIND =
            RawAnimation.begin().thenLoop("animation.gooby.hide_behind");
    protected static final RawAnimation ANIM_SHIVER =
            RawAnimation.begin().thenLoop("animation.gooby.shiver");
    protected static final RawAnimation ANIM_SNUGGLE_LEAN =
            RawAnimation.begin().thenPlay("animation.gooby.snuggle_lean");
    protected static final RawAnimation ANIM_TIER_UP_BOUNCE =
            RawAnimation.begin().thenPlay("animation.gooby.tier_up_bounce");
    protected static final RawAnimation ANIM_EARS_PERK =
            RawAnimation.begin().thenPlay("animation.gooby.ears_perk");
    protected static final RawAnimation ANIM_TRICK_SPIN =
            RawAnimation.begin().thenPlay("animation.gooby.trick_spin");
    protected static final RawAnimation ANIM_TRICK_HIGH_FIVE =
            RawAnimation.begin().thenPlay("animation.gooby.trick_high_five");
    protected static final RawAnimation ANIM_TRICK_FLOP =
            RawAnimation.begin().thenPlay("animation.gooby.trick_flop");
    protected static final RawAnimation ANIM_TRICK_SPEAK =
            RawAnimation.begin().thenPlay("animation.gooby.trick_speak");
    protected static final RawAnimation ANIM_TRICK_ROLL =
            RawAnimation.begin().thenPlay("animation.gooby.trick_roll");
    protected static final RawAnimation ANIM_TRICK_DANCE =
            RawAnimation.begin().thenPlay("animation.gooby.trick_dance");
    protected static final RawAnimation ANIM_TRAINING_SUCCESS =
            RawAnimation.begin().thenPlay("animation.gooby.training_success_hop");
    protected static final RawAnimation ANIM_HUTCH_ENTER =
            RawAnimation.begin().thenPlay("animation.gooby.hutch_enter");
    protected static final RawAnimation ANIM_HUTCH_EXIT =
            RawAnimation.begin().thenPlay("animation.gooby.hutch_exit");
    protected static final RawAnimation ANIM_BABY_HOP =
            RawAnimation.begin().thenLoop("animation.gooby.baby_hop");
    protected static final RawAnimation ANIM_BABY_TUMBLE =
            RawAnimation.begin().thenPlay("animation.gooby.baby_tumble");
    protected static final RawAnimation ANIM_PARENT_NUZZLE =
            RawAnimation.begin().thenPlay("animation.gooby.parent_nuzzle");
    protected static final RawAnimation ANIM_GROW_UP_POP =
            RawAnimation.begin().thenPlay("animation.gooby.grow_up_pop");
    protected static final RawAnimation ANIM_SEATED_CONTRAPTION =
            RawAnimation.begin().thenLoop("animation.gooby.seated_contraption_idle");
    protected static final RawAnimation ANIM_TRAIN_LEAN =
            RawAnimation.begin().thenLoop("animation.gooby.train_lean");
    protected static final RawAnimation ANIM_SHY_PEEK =
            RawAnimation.begin().thenLoop("animation.gooby.shy_peek");
    protected static final RawAnimation ANIM_GREETING_BOUNCE =
            RawAnimation.begin().thenLoop("animation.gooby.greeting_bounce");
    protected static final RawAnimation ANIM_PLAY_CHASE =
            RawAnimation.begin().thenLoop("animation.gooby.play_chase_lunge");
    protected static final RawAnimation ANIM_BOW =
            RawAnimation.begin().thenPlay("animation.gooby.bow");
    protected static final RawAnimation ANIM_NAP_HUDDLE =
            RawAnimation.begin().thenLoop("animation.gooby.nap_huddle");
    protected static final RawAnimation ANIM_SNIFF_SEEK =
            RawAnimation.begin().thenLoop("animation.gooby.sniff_seek");
    protected static final RawAnimation ANIM_DIG_EXCITED =
            RawAnimation.begin().thenPlay("animation.gooby.dig_excited");
    protected static final RawAnimation ANIM_PRESENT_ITEM =
            RawAnimation.begin().thenPlay("animation.gooby.present_item");

    private final AnimatableInstanceCache geckoCache = GeckoLibUtil.createInstanceCache(this);
    private final GoobyAnimationState clientAnimationState = new GoobyAnimationState();
    private final GoobyLocomotion clientLocomotion = new GoobyLocomotion();

    // Serverseitige Zustaende (persistiert)
    private final LinkedHashMap<UUID, Integer> friendship = new LinkedHashMap<>(16, 0.75F, true);
    private final Map<UUID, FriendshipMemory> memories = new LinkedHashMap<>(16, 0.75F, true);
    private final EnumMap<GoobyTrick, Integer> trickProficiency = new EnumMap<>(GoobyTrick.class);
    private GoobyTrick selectedTrick = GoobyTrick.SPIN;
    private int giftCharges;
    private int giftCooldown;
    @Nullable
    private BlockPos homePos;
    @Nullable
    private BlockPos jarTarget;
    @Nullable
    private UUID parentA;
    @Nullable
    private UUID parentB;
    @Nullable
    private BlockPos familyNestPos;
    private final Map<UUID, Long> familyRituals = new LinkedHashMap<>(16, 0.75F, true);
    private final Map<UUID, Long> socialCooldowns = new LinkedHashMap<>(16, 0.75F, true);
    private final Map<UUID, EmoteMemory> emoteMemories = new LinkedHashMap<>(16, 0.75F, true);
    private final SimpleContainer satchelInventory = new SimpleContainer(SATCHEL_SIZE);
    /** Serverautoritative Garderobe mit vollstaendigen ItemStacks (Name, Verzauberungen, Components). */
    private final GoobyWardrobe wardrobe = new GoobyWardrobe();
    private int unlockedCoatsMask = GoobyCoatVariant.CLASSIC.unlockBit();
    private boolean naturalWild;
    private boolean fedOnce;
    private boolean burrowResident;
    private long seekCooldownUntil;
    /** GameTime, ab der der naechste Apport wieder Bonus gibt (Anti-Spam, persistent). */
    private long fetchRewardCooldownUntil;
    @Nullable
    private BlockPos seekTarget;

    // Serverseitige Timer (transient)
    private final Map<UUID, Long> lastFriendshipGain = new LinkedHashMap<>(16, 0.75F, true);
    private final Map<UUID, Long> lastSatisfactionLoss = new LinkedHashMap<>(16, 0.75F, true);
    private final Map<UUID, Long> greetedPlayers = new LinkedHashMap<>(16, 0.75F, true);
    private final Map<UUID, Long> lastBareHandInteraction = new LinkedHashMap<>(16, 0.75F, true);
    private int bubbleTicks;
    private int sadTicks;
    private int digTicks;
    private int brushCooldown;
    private int satisfactionDecayTimer;
    private int nextIdleLineIn;
    private int petRequestIn;
    private boolean wantsPet;
    private int wantPetBubbleCooldown;
    private int sadBubbleCooldown;
    private int dangerCheckCooldown;
    private int sleepSuppressedTicks;
    private int panicTicks;
    private float guardianPressure = 40.0F;
    private int recentlyWokeTicks;
    private int actionAnimationTicks;
    private boolean wasOnGroundLastTick = true;
    private double airborneStartY;
    private int landingSquashes;
    private int activePetterTicks;
    private long lastFedTime;
    private long lastMoodChange;
    private int ownerAwayTicks;
    private int inspectionLookTicks;
    private int alarmCount;
    private int wetExposureTicks;
    private int shakeWaterTicks;
    private int hidingFromThunderTicks;
    private int tierUpCount;
    private int nameReactionCount;
    private int tagAlongTicks;
    private long lastTrainingTime = Long.MIN_VALUE;
    private int performedTrickCount;
    // Feedback-Wave: Countdown bis zum Konfetti des VOLLENDETEN Tricks,
    // Cooldown-Gates und reine Burst-Zaehler fuer die GameTests.
    private int trickConfettiIn;
    private long trickConfettiCooldownUntil;
    private long petNoteCooldownUntil;
    private int confettiBursts;
    private int fluffPuffBursts;
    private int musicNoteBursts;
    private int hutchWakeRoutineTicks;
    private int babyTumbleCooldown;
    private boolean wasBabyLastTick;
    private int createComfortTicks;
    private boolean wasOnMovingContraption;
    private int socialActionTicks;
    private int bowReactionCount;
    @Nullable
    private UUID tagAlongPlayer;

    // Rein lokale, allokationsfreie Micro-Animation-Timer.
    private int clientNextBlinkTick;
    private int clientNextNoseTick;
    private int clientNextFlavorTick;
    private int clientMicroEndTick;
    @Nullable
    private RawAnimation clientMicroAnimation;
    private boolean clientYawnedForWake;
    private float clientSmoothedHeadPitch;
    private float clientSmoothedHeadYaw;
    private int clientLastRenderedTick = Integer.MIN_VALUE;

    // Client-Caches fuer die synchronisierte Garderobe
    @Nullable
    private String cachedHatId;
    private ItemStack cachedHatStack = ItemStack.EMPTY;
    @Nullable
    private String cachedNeckId;
    private ItemStack cachedNeckStack = ItemStack.EMPTY;
    @Nullable
    private String cachedBackId;
    private ItemStack cachedBackStack = ItemStack.EMPTY;

    private static final class EmoteMemory {
        private boolean wasCrouching;
        private boolean wasOnGround = true;
        private int sneakPresses;
        private long sneakWindowStart = Long.MIN_VALUE;
        private int jumps;
        private long jumpWindowStart = Long.MIN_VALUE;
        /** Letzter Kontakt (GameTime) — Grundlage fuers Pruning gegen unbegrenztes Wachstum. */
        private long lastTouched;
    }

    public GoobyEntity(EntityType<? extends GoobyEntity> type, Level level) {
        super(type, level);
        this.nextIdleLineIn = newIdleLineDelay(this.random);
        this.petRequestIn = newPetRequestDelay(this.random);
        this.lastFedTime = level.getGameTime();
        this.setCanPickUpLoot(false);
        setPathfindingMalus(PathType.DANGER_FIRE, 16.0F);
        setPathfindingMalus(PathType.DAMAGE_FIRE, -1.0F);
        setPathfindingMalus(PathType.DANGER_OTHER, 16.0F);
        setPathfindingMalus(PathType.DAMAGE_OTHER, -1.0F);
        setPathfindingMalus(PathType.POWDER_SNOW, -1.0F);
        setPathfindingMalus(PathType.DANGER_POWDER_SNOW, 16.0F);
    }

    public static AttributeSupplier.Builder createAttributes() {
        return Animal.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 40.0)
                .add(Attributes.MOVEMENT_SPEED, 0.25)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0)
                .add(Attributes.STEP_HEIGHT, 1.0)
                .add(Attributes.FOLLOW_RANGE, 24.0);
    }

    @Override
    public SpawnGroupData finalizeSpawn(ServerLevelAccessor level, DifficultyInstance difficulty,
            MobSpawnType spawnType, @Nullable SpawnGroupData spawnData) {
        SpawnGroupData result = super.finalizeSpawn(level, difficulty, spawnType, spawnData);
        setSatisfaction(70);
        if (spawnType == MobSpawnType.NATURAL || spawnType == MobSpawnType.CHUNK_GENERATION) {
            this.naturalWild = true;
            this.entityData.set(DATA_SHY, true);
        } else if (spawnType == MobSpawnType.SPAWN_EGG) {
            setPersistenceRequired();
        } else if (spawnType == MobSpawnType.STRUCTURE) {
            markBurrowResident();
        }
        return result;
    }

    @Override
    public void tame(Player player) {
        boolean firstTaming = !isTame();
        super.tame(player);
        this.entityData.set(DATA_SHY, false);
        if (firstTaming) {
            NeoForge.EVENT_BUS.post(new GoobyTameEvent(this, player));
            GoobyHandbookItem.giveOnce(player);
        }
    }

    public boolean isNaturallySpawnedWild() {
        return this.naturalWild;
    }

    public boolean hasBeenFed() {
        return this.fedOnce;
    }

    public boolean isShyWild() {
        return !isTame() && this.entityData.get(DATA_SHY);
    }

    public boolean isBurrowResident() {
        return this.burrowResident;
    }

    /** Marks a structure-spawned Gooby as persistent and anchors its chamber home. */
    public void markBurrowResident() {
        this.burrowResident = true;
        this.naturalWild = false;
        this.entityData.set(DATA_SHY, true);
        if (this.homePos == null) {
            setHomePos(blockPosition());
        }
        setPersistenceRequired();
    }

    private static int newPetRequestDelay(RandomSource random) {
        // Alle 1-2 Minuten will Gooby MEHR Streicheleinheiten
        return 1200 + random.nextInt(1200);
    }

    private static int newIdleLineDelay(RandomSource random) {
        int min = GoobyConfig.idleLineMinTicks();
        int max = GoobyConfig.idleLineMaxTicks();
        return min + random.nextInt(Math.max(1, max - min + 1));
    }

    // ------------------------------------------------------------------
    // Datenhaltung
    // ------------------------------------------------------------------

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_SATISFACTION, 40);
        builder.define(DATA_SLEEPING, false);
        builder.define(DATA_IN_HUTCH, false);
        builder.define(DATA_SITTING, false);
        builder.define(DATA_SAD, false);
        builder.define(DATA_DIGGING, false);
        builder.define(DATA_BUBBLE_KEY, "");
        builder.define(DATA_COMMAND, (byte) GoobyCommand.WANDER.ordinal());
        builder.define(DATA_HAT, "");
        builder.define(DATA_NECK, "");
        builder.define(DATA_BACK, "");
        builder.define(DATA_COAT, (byte) GoobyCoatVariant.CLASSIC.ordinal());
        builder.define(DATA_PANICKING, false);
        builder.define(DATA_RECENTLY_WOKE, false);
        builder.define(DATA_ACTIVE_PETTER, "");
        builder.define(DATA_MOOD, (byte) GoobyMood.CONTENT.ordinal());
        builder.define(DATA_ALERTING, false);
        builder.define(DATA_SEEKING_SHELTER, false);
        builder.define(DATA_SHAKING_WATER, false);
        builder.define(DATA_HIDING_FROM_THUNDER, false);
        builder.define(DATA_SHY, false);
        builder.define(DATA_BUBBLE_ARG, "");
        builder.define(DATA_SOCIAL_ACTION, SOCIAL_NONE);
        builder.define(DATA_SOCIAL_PARTNER, "");
        builder.define(DATA_SEEKING_TREASURE, false);
        builder.define(DATA_CARRIED_BALL, ItemStack.EMPTY);
    }

    private <T> void setSynced(EntityDataAccessor<T> accessor, T value) {
        if (!Objects.equals(this.entityData.get(accessor), value)) {
            this.entityData.set(accessor, value);
        }
    }

    private static String boundedSyncString(@Nullable String value, int maximumLength) {
        if (value == null || value.isEmpty()) {
            return "";
        }
        return value.length() <= maximumLength ? value : value.substring(0, maximumLength);
    }

    private static <K, V> void trimOldest(Map<K, V> map, int maximumSize) {
        while (map.size() > maximumSize) {
            Iterator<K> oldest = map.keySet().iterator();
            if (!oldest.hasNext()) {
                return;
            }
            oldest.next();
            oldest.remove();
        }
    }

    @Override
    public void addAdditionalSaveData(CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        tag.putInt("Satisfaction", getSatisfaction());
        tag.putByte("Command", (byte) getCommandMode().ordinal());
        tag.putInt("GiftCharges", this.giftCharges);
        tag.putInt("GiftCooldown", this.giftCooldown);
        // Wire-Strings bleiben fuer Downgrade-Toleranz erhalten; WardrobeItems
        // persistiert zusaetzlich die vollen Stacks (Name/Verzauberung/Components).
        tag.putString("Hat", getHatItemId());
        tag.putString("NeckAccessory", getNeckAccessoryData());
        tag.putString("BackAccessory", getBackAccessoryData());
        CompoundTag wardrobeItems = this.wardrobe.save(registryAccess());
        if (!wardrobeItems.isEmpty()) {
            tag.put("WardrobeItems", wardrobeItems);
        }
        tag.putByte("CoatVariant", (byte) getCoatVariant().ordinal());
        tag.putInt("UnlockedCoats", this.unlockedCoatsMask);
        tag.putLong("LastFedTime", this.lastFedTime);
        tag.putLong("LastMoodChange", this.lastMoodChange);
        tag.putInt("OwnerAwayTicks", this.ownerAwayTicks);
        tag.putByte("Mood", (byte) getMood().ordinal());
        tag.putBoolean("Sleeping", isGoobySleeping());
        tag.putBoolean("InHutch", isInHutch());
        tag.putBoolean("NaturalWild", this.naturalWild);
        tag.putBoolean("FedOnce", this.fedOnce);
        tag.putBoolean("BurrowResident", this.burrowResident);
        tag.putBoolean("ShyUntilFed", isShyWild());
        tag.putLong("SeekCooldownUntil", this.seekCooldownUntil);
        if (this.seekTarget != null) {
            tag.put("SeekTarget", NbtUtils.writeBlockPos(this.seekTarget));
        }
        // Voller Stack inkl. DataComponents — Save liest nur, loescht nie
        // (keine Duplikation, kein Verlust bei Chunk-/Server-Reload).
        if (isCarryingFetchItem()) {
            tag.put("CarriedBall", getCarriedFetchItem().save(registryAccess()));
        }
        tag.putLong("FetchRewardCooldownUntil", this.fetchRewardCooldownUntil);
        tag.put("SatchelInventory", saveSatchelInventory());
        tag.putByte("SelectedTrick", (byte) this.selectedTrick.ordinal());
        CompoundTag trickLevels = new CompoundTag();
        for (GoobyTrick trick : GoobyTrick.values()) {
            trickLevels.putByte(trick.serializedName(), (byte) getTrickProficiency(trick));
        }
        tag.put("TrickProficiency", trickLevels);
        ListTag friends = new ListTag();
        for (Map.Entry<UUID, Integer> entry : this.friendship.entrySet()) {
            CompoundTag friend = new CompoundTag();
            friend.putUUID("UUID", entry.getKey());
            friend.putInt("Value", entry.getValue());
            friends.add(friend);
        }
        tag.put("Friendship", friends);
        ListTag memoryTags = new ListTag();
        for (Map.Entry<UUID, FriendshipMemory> entry : this.memories.entrySet()) {
            CompoundTag memory = entry.getValue().save();
            memory.putUUID("UUID", entry.getKey());
            memoryTags.add(memory);
        }
        tag.put("Memories", memoryTags);
        if (this.homePos != null) {
            tag.put("HomePos", NbtUtils.writeBlockPos(this.homePos));
        }
        if (this.jarTarget != null) {
            tag.put("JarTarget", NbtUtils.writeBlockPos(this.jarTarget));
        }
        if (this.parentA != null) {
            tag.putUUID("ParentA", this.parentA);
        }
        if (this.parentB != null) {
            tag.putUUID("ParentB", this.parentB);
        }
        if (this.familyNestPos != null) {
            tag.put("FamilyNestPos", NbtUtils.writeBlockPos(this.familyNestPos));
        }
        ListTag ritualTags = new ListTag();
        for (Map.Entry<UUID, Long> entry : this.familyRituals.entrySet()) {
            CompoundTag ritual = new CompoundTag();
            ritual.putUUID("Partner", entry.getKey());
            ritual.putLong("Time", entry.getValue());
            ritualTags.add(ritual);
        }
        tag.put("FamilyRituals", ritualTags);
        ListTag socialTags = new ListTag();
        for (Map.Entry<UUID, Long> entry : this.socialCooldowns.entrySet()) {
            CompoundTag cooldown = new CompoundTag();
            cooldown.putUUID("Partner", entry.getKey());
            cooldown.putLong("Until", entry.getValue());
            socialTags.add(cooldown);
        }
        tag.put("SocialCooldowns", socialTags);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag tag) {
        super.readAdditionalSaveData(tag);
        if (tag.contains("Satisfaction")) {
            setSatisfaction(tag.getInt("Satisfaction"));
        }
        setCommandMode(GoobyCommand.byId(tag.getByte("Command")));
        this.giftCharges = tag.getInt("GiftCharges");
        this.giftCooldown = tag.getInt("GiftCooldown");
        // Legacy-Migration: alte Saves kennen nur die Wire-Strings — die Setter
        // rekonstruieren daraus Basis-Stacks (Item + Farbe). Liegt das neue
        // WardrobeItems-NBT vor, gewinnen die vollen Stacks und die
        // Sync-Strings werden daraus abgeleitet.
        setHatItemId(tag.getString("Hat"));
        setNeckAccessoryData(tag.getString("NeckAccessory"));
        setBackAccessoryData(tag.getString("BackAccessory"));
        if (tag.contains("WardrobeItems", Tag.TAG_COMPOUND)) {
            this.wardrobe.load(tag.getCompound("WardrobeItems"), registryAccess());
            syncWireFromWardrobe(GoobyWardrobe.Slot.HEAD);
            syncWireFromWardrobe(GoobyWardrobe.Slot.NECK);
            syncWireFromWardrobe(GoobyWardrobe.Slot.BACK);
        }
        this.unlockedCoatsMask = tag.contains("UnlockedCoats")
                ? tag.getInt("UnlockedCoats") | GoobyCoatVariant.CLASSIC.unlockBit()
                : GoobyCoatVariant.CLASSIC.unlockBit();
        GoobyCoatVariant loadedCoat = GoobyCoatVariant.byId(tag.getByte("CoatVariant"));
        setCoatVariant(isCoatUnlocked(loadedCoat) ? loadedCoat : GoobyCoatVariant.CLASSIC);
        this.lastFedTime = tag.contains("LastFedTime") ? tag.getLong("LastFedTime") : this.level().getGameTime();
        this.lastMoodChange = tag.getLong("LastMoodChange");
        this.ownerAwayTicks = Math.max(0, tag.getInt("OwnerAwayTicks"));
        setMood(tag.contains("Mood") ? GoobyMood.byId(tag.getByte("Mood")) : GoobyMood.CONTENT);
        this.entityData.set(DATA_IN_HUTCH, tag.getBoolean("InHutch"));
        this.entityData.set(DATA_SLEEPING, tag.getBoolean("Sleeping"));
        this.naturalWild = tag.getBoolean("NaturalWild");
        this.fedOnce = tag.getBoolean("FedOnce");
        this.burrowResident = tag.getBoolean("BurrowResident");
        this.entityData.set(DATA_SHY, tag.getBoolean("ShyUntilFed") && !isTame());
        this.seekCooldownUntil = tag.getLong("SeekCooldownUntil");
        this.seekTarget = NbtUtils.readBlockPos(tag, "SeekTarget").orElse(null);
        this.entityData.set(DATA_SEEKING_TREASURE, this.seekTarget != null);
        this.entityData.set(DATA_CARRIED_BALL, tag.contains("CarriedBall", Tag.TAG_COMPOUND)
                ? ItemStack.parse(registryAccess(), tag.getCompound("CarriedBall")).orElse(ItemStack.EMPTY)
                : ItemStack.EMPTY);
        this.fetchRewardCooldownUntil = tag.getLong("FetchRewardCooldownUntil");
        loadSatchelInventory(tag.getList("SatchelInventory", Tag.TAG_COMPOUND));
        this.selectedTrick = tag.contains("SelectedTrick")
                ? GoobyTrick.byId(tag.getByte("SelectedTrick")) : GoobyTrick.SPIN;
        this.trickProficiency.clear();
        CompoundTag trickLevels = tag.getCompound("TrickProficiency");
        for (GoobyTrick trick : GoobyTrick.values()) {
            int level = Mth.clamp(trickLevels.getByte(trick.serializedName()), 0, MAX_TRICK_PROFICIENCY);
            if (level > 0) {
                this.trickProficiency.put(trick, level);
            }
        }
        this.friendship.clear();
        ListTag friends = tag.getList("Friendship", Tag.TAG_COMPOUND);
        for (int i = 0; i < friends.size(); i++) {
            CompoundTag friend = friends.getCompound(i);
            if (friend.hasUUID("UUID")) {
                this.friendship.put(friend.getUUID("UUID"),
                        Mth.clamp(friend.getInt("Value"), 0, MAX_FRIENDSHIP));
                pruneFriendships();
            }
        }
        this.memories.clear();
        ListTag memoryTags = tag.getList("Memories", Tag.TAG_COMPOUND);
        for (int i = 0; i < memoryTags.size(); i++) {
            CompoundTag memory = memoryTags.getCompound(i);
            if (memory.hasUUID("UUID")) {
                this.memories.put(memory.getUUID("UUID"), FriendshipMemory.load(memory));
                pruneMemories();
            }
        }
        pruneFriendships();
        this.homePos = NbtUtils.readBlockPos(tag, "HomePos").orElse(null);
        this.jarTarget = NbtUtils.readBlockPos(tag, "JarTarget").orElse(null);
        this.parentA = tag.hasUUID("ParentA") ? tag.getUUID("ParentA") : null;
        this.parentB = tag.hasUUID("ParentB") ? tag.getUUID("ParentB") : null;
        this.familyNestPos = NbtUtils.readBlockPos(tag, "FamilyNestPos").orElse(null);
        this.familyRituals.clear();
        ListTag ritualTags = tag.getList("FamilyRituals", Tag.TAG_COMPOUND);
        for (int i = 0; i < ritualTags.size(); i++) {
            CompoundTag ritual = ritualTags.getCompound(i);
            if (ritual.hasUUID("Partner")) {
                this.familyRituals.put(ritual.getUUID("Partner"), ritual.getLong("Time"));
                trimOldest(this.familyRituals, MAX_PARTNER_HISTORY_ENTRIES);
            }
        }
        this.socialCooldowns.clear();
        ListTag socialTags = tag.getList("SocialCooldowns", Tag.TAG_COMPOUND);
        for (int i = 0; i < socialTags.size(); i++) {
            CompoundTag cooldown = socialTags.getCompound(i);
            if (cooldown.hasUUID("Partner")) {
                this.socialCooldowns.put(cooldown.getUUID("Partner"), cooldown.getLong("Until"));
                trimOldest(this.socialCooldowns, MAX_PARTNER_HISTORY_ENTRIES);
            }
        }
        this.wasBabyLastTick = isBaby();
    }

    public int getSatisfaction() {
        return this.entityData.get(DATA_SATISFACTION);
    }

    public void setSatisfaction(int value) {
        setSynced(DATA_SATISFACTION, Mth.clamp(value, 0, MAX_SATISFACTION));
    }

    public void addSatisfaction(int delta) {
        setSatisfaction(getSatisfaction() + delta);
    }

    public GoobyMood getMood() {
        return GoobyMood.byId(this.entityData.get(DATA_MOOD));
    }

    public void setMood(GoobyMood mood) {
        setSynced(DATA_MOOD, (byte) mood.ordinal());
    }

    public void setMoodScaredImmediately() {
        if (getMood() != GoobyMood.SCARED) {
            setMood(GoobyMood.SCARED);
            this.lastMoodChange = this.level().getGameTime();
        }
    }

    public boolean isAlerting() {
        return this.entityData.get(DATA_ALERTING);
    }

    public void setAlerting(boolean alerting) {
        setSynced(DATA_ALERTING, alerting);
    }

    public boolean isSeekingShelter() {
        return this.entityData.get(DATA_SEEKING_SHELTER);
    }

    public void setSeekingShelter(boolean seekingShelter) {
        setSynced(DATA_SEEKING_SHELTER, seekingShelter);
    }

    public boolean isShakingWater() {
        return this.entityData.get(DATA_SHAKING_WATER);
    }

    public boolean isHidingFromThunder() {
        return this.entityData.get(DATA_HIDING_FROM_THUNDER);
    }

    public void markHidingFromThunder() {
        setSynced(DATA_HIDING_FROM_THUNDER, true);
        this.hidingFromThunderTicks = 30;
    }

    public int getAlarmCount() {
        return this.alarmCount;
    }

    public long getLastFedTime() {
        return this.lastFedTime;
    }

    public void setLastFedTime(long lastFedTime) {
        this.lastFedTime = lastFedTime;
    }

    public int getOwnerAwayTicks() {
        return this.ownerAwayTicks;
    }

    public void setOwnerAwayTicks(int ownerAwayTicks) {
        this.ownerAwayTicks = Math.max(0, ownerAwayTicks);
    }

    public boolean isGoobySleeping() {
        return this.entityData.get(DATA_SLEEPING);
    }

    public void setGoobySleeping(boolean sleeping) {
        boolean wasSleeping = isGoobySleeping();
        setSynced(DATA_SLEEPING, sleeping);
        if (wasSleeping && !sleeping && !isInHutch() && !this.level().isClientSide) {
            markJustWoke();
        }
    }

    public boolean isInHutch() {
        return this.entityData.get(DATA_IN_HUTCH);
    }

    public void setInHutch(boolean inHutch) {
        setSynced(DATA_IN_HUTCH, inHutch);
    }

    public boolean isSitting() {
        return this.entityData.get(DATA_SITTING) || isInSittingPose();
    }

    public void setSitting(boolean sitting) {
        setSynced(DATA_SITTING, sitting);
    }

    public boolean isSad() {
        return this.entityData.get(DATA_SAD);
    }

    public boolean isDigging() {
        return this.entityData.get(DATA_DIGGING);
    }

    public String getBubbleKey() {
        return this.entityData.get(DATA_BUBBLE_KEY);
    }

    public String getBubbleArgument() {
        return this.entityData.get(DATA_BUBBLE_ARG);
    }

    public byte getSocialAction() {
        return this.entityData.get(DATA_SOCIAL_ACTION);
    }

    @Nullable
    public UUID getSocialPartnerId() {
        String value = this.entityData.get(DATA_SOCIAL_PARTNER);
        try {
            return value.isEmpty() ? null : UUID.fromString(value);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    public boolean hasActiveSocialAction() {
        return getSocialAction() != SOCIAL_NONE;
    }

    public int getBowReactionCount() {
        return this.bowReactionCount;
    }

    public GoobyCommand getCommandMode() {
        return GoobyCommand.byId(this.entityData.get(DATA_COMMAND));
    }

    public void setCommandMode(GoobyCommand command) {
        setSynced(DATA_COMMAND, (byte) command.ordinal());
        if (!this.level().isClientSide) {
            setOrderedToSit(command == GoobyCommand.STAY);
            if (command == GoobyCommand.STAY) {
                getNavigation().stop();
            }
        }
    }

    @Override
    @Nullable
    public UUID goobyOwnerId() {
        return getOwnerUUID();
    }

    @Override
    public int goobySatisfaction() {
        return getSatisfaction();
    }

    @Override
    public GoobyMood goobyMood() {
        return getMood();
    }

    @Override
    public GoobyCommand goobyCommand() {
        return getCommandMode();
    }

    @Override
    public FriendshipTier goobyFriendshipTier(UUID playerId) {
        return getFriendshipTier(playerId);
    }

    @Override
    public boolean goobyIsBaby() {
        return isBaby();
    }

    @Override
    public boolean goobyIsWild() {
        return !isTame();
    }

    @Override
    public ItemStack goobyHat() {
        return getHatStack().copy();
    }

    @Override
    public ItemStack goobyNeckAccessory() {
        return getNeckStack().copy();
    }

    @Override
    public ItemStack goobyBackAccessory() {
        return getBackStack().copy();
    }

    private ListTag saveSatchelInventory() {
        ListTag items = new ListTag();
        for (int slot = 0; slot < this.satchelInventory.getContainerSize(); slot++) {
            ItemStack stack = this.satchelInventory.getItem(slot);
            if (stack.isEmpty()) {
                continue;
            }
            CompoundTag entry = new CompoundTag();
            entry.putByte("Slot", (byte) slot);
            entry.put("Item", stack.save(registryAccess()));
            items.add(entry);
        }
        return items;
    }

    private void loadSatchelInventory(ListTag items) {
        this.satchelInventory.clearContent();
        int legacySlot = 0;
        for (int index = 0; index < items.size(); index++) {
            CompoundTag entry = items.getCompound(index);
            boolean indexedFormat = entry.contains("Item", Tag.TAG_COMPOUND);
            int slot = indexedFormat ? Byte.toUnsignedInt(entry.getByte("Slot")) : legacySlot++;
            if (slot >= this.satchelInventory.getContainerSize()) {
                continue;
            }
            Tag itemTag = indexedFormat ? entry.get("Item") : entry;
            ItemStack.parse(registryAccess(), itemTag)
                    .ifPresent(stack -> this.satchelInventory.setItem(slot, stack));
        }
    }

    public void setJarTarget(@Nullable BlockPos pos) {
        this.jarTarget = pos;
    }

    @Nullable
    public BlockPos getJarTarget() {
        return this.jarTarget;
    }

    @Nullable
    public BlockPos getHomePos() {
        return this.homePos;
    }

    public void setHomePos(@Nullable BlockPos pos) {
        this.homePos = pos == null ? null : pos.immutable();
    }

    public void missBoundHutchTonight() {
        setMood(GoobyMood.LONELY);
        showBubble("bubble.goobymod.hutch_too_far");
        playSound(ModSounds.GOOBY_LONELY_SIGH.get(), 0.55F, 0.9F);
    }

    public boolean isSleepSuppressed() {
        return this.sleepSuppressedTicks > 0;
    }

    public boolean isPanicking() {
        return this.entityData.get(DATA_PANICKING);
    }

    public int getPanicTicks() {
        return this.panicTicks;
    }

    public float getGuardianPressure() {
        return this.guardianPressure;
    }

    public boolean hasRecentlyWoken() {
        return this.entityData.get(DATA_RECENTLY_WOKE);
    }

    public void markJustWoke() {
        this.recentlyWokeTicks = 80;
        this.entityData.set(DATA_RECENTLY_WOKE, true);
    }

    public int getLandingSquashes() {
        return this.landingSquashes;
    }

    /** Nur fuer GameTests: Anzahl bisher gesendeter Konfetti-Salven. */
    public int getConfettiBursts() {
        return this.confettiBursts;
    }

    /** Nur fuer GameTests: Anzahl bisher gesendeter Fellfussel-Bursts. */
    public int getFluffPuffBursts() {
        return this.fluffPuffBursts;
    }

    /** Nur fuer GameTests: Anzahl bisher gesendeter Musiknoten-Bursts. */
    public int getMusicNoteBursts() {
        return this.musicNoteBursts;
    }

    public int getActionAnimationTicks() {
        return this.actionAnimationTicks;
    }

    public boolean isBeingPettedBy(UUID playerId) {
        return playerId.toString().equals(this.entityData.get(DATA_ACTIVE_PETTER));
    }

    public void updateClientHeadLook(float targetPitch, float targetYaw) {
        this.clientSmoothedHeadPitch = Mth.lerp(0.28F, this.clientSmoothedHeadPitch, targetPitch);
        this.clientSmoothedHeadYaw = Mth.lerp(0.28F, this.clientSmoothedHeadYaw, targetYaw);
    }

    public void resetClientHeadLook() {
        this.clientSmoothedHeadPitch = 0.0F;
        this.clientSmoothedHeadYaw = 0.0F;
    }

    public float getClientSmoothedHeadPitch() {
        return this.clientSmoothedHeadPitch;
    }

    public float getClientSmoothedHeadYaw() {
        return this.clientSmoothedHeadYaw;
    }

    public void markClientRendered() {
        this.clientLastRenderedTick = this.tickCount;
    }

    public boolean isClientMicroLodActive() {
        Player nearest = this.level().getNearestPlayer(this, 24.0);
        int ticksSinceRendered = this.clientLastRenderedTick == Integer.MIN_VALUE
                ? Integer.MAX_VALUE : Math.max(0, this.tickCount - this.clientLastRenderedTick);
        double distanceSquared = nearest == null ? Double.POSITIVE_INFINITY : distanceToSqr(nearest);
        return shouldRunClientMicroAnimations(
                ticksSinceRendered, distanceSquared, GoobyClientConfig.reducedMotion());
    }

    public static boolean shouldRunClientMicroAnimations(
            int ticksSinceRendered, double distanceSquared, boolean reducedMotion) {
        return !reducedMotion && ticksSinceRendered <= 2 && distanceSquared <= 24.0 * 24.0;
    }

    public int getGiftCharges() {
        return this.giftCharges;
    }

    public void setGiftCharges(int charges) {
        this.giftCharges = Mth.clamp(charges, 0, GoobyConfig.maxGiftCharges());
    }

    public int getGiftCooldown() {
        return this.giftCooldown;
    }

    public void setGiftCooldown(int ticks) {
        this.giftCooldown = Math.max(0, ticks);
    }

    // ------------------------------------------------------------------
    // Freundschaft (pro Spieler-UUID, 0-100, persistent)
    // ------------------------------------------------------------------

    public int getFriendship(UUID playerId) {
        return this.friendship.getOrDefault(playerId, 0);
    }

    public void setFriendship(UUID playerId, int value) {
        this.friendship.put(playerId, Mth.clamp(value, 0, MAX_FRIENDSHIP));
        pruneFriendships();
    }

    public int getStoredFriendshipCount() {
        return this.friendship.size();
    }

    private void pruneFriendships() {
        UUID ownerId = getOwnerUUID();
        int maximum = MAX_STORED_FRIENDSHIPS
                + (ownerId != null && this.friendship.containsKey(ownerId) ? 1 : 0);
        while (this.friendship.size() > maximum) {
            Iterator<Map.Entry<UUID, Integer>> entries = this.friendship.entrySet().iterator();
            boolean removed = false;
            while (entries.hasNext()) {
                Map.Entry<UUID, Integer> candidate = entries.next();
                if (!candidate.getKey().equals(ownerId)) {
                    UUID evicted = candidate.getKey();
                    entries.remove();
                    this.memories.remove(evicted);
                    removed = true;
                    break;
                }
            }
            if (!removed) {
                return;
            }
        }
        pruneMemories();
    }

    private void pruneMemories() {
        UUID ownerId = getOwnerUUID();
        int maximum = MAX_STORED_FRIENDSHIPS
                + (ownerId != null && this.memories.containsKey(ownerId) ? 1 : 0);
        while (this.memories.size() > maximum) {
            Iterator<Map.Entry<UUID, FriendshipMemory>> entries = this.memories.entrySet().iterator();
            boolean removed = false;
            while (entries.hasNext()) {
                Map.Entry<UUID, FriendshipMemory> candidate = entries.next();
                if (!candidate.getKey().equals(ownerId)) {
                    entries.remove();
                    removed = true;
                    break;
                }
            }
            if (!removed) {
                return;
            }
        }
    }

    public FriendshipTier getFriendshipTier(UUID playerId) {
        return FriendshipTier.of(getFriendship(playerId));
    }

    public FriendshipMemory getMemory(UUID playerId) {
        FriendshipMemory memory = this.memories.computeIfAbsent(playerId, ignored -> new FriendshipMemory());
        pruneMemories();
        return memory;
    }

    public int getTierUpCount() {
        return this.tierUpCount;
    }

    public int getNameReactionCount() {
        return this.nameReactionCount;
    }

    public GoobyTrick getSelectedTrick() {
        return this.selectedTrick;
    }

    public int getTrickProficiency(GoobyTrick trick) {
        return this.trickProficiency.getOrDefault(trick, 0);
    }

    public void setTrickProficiency(GoobyTrick trick, int proficiency) {
        int clamped = Mth.clamp(proficiency, 0, MAX_TRICK_PROFICIENCY);
        if (clamped == 0) {
            this.trickProficiency.remove(trick);
        } else {
            this.trickProficiency.put(trick, clamped);
        }
    }

    public int getPerformedTrickCount() {
        return this.performedTrickCount;
    }

    public boolean areAllTricksMastered() {
        for (GoobyTrick trick : GoobyTrick.values()) {
            if (getTrickProficiency(trick) < MAX_TRICK_PROFICIENCY) {
                return false;
            }
        }
        return true;
    }

    public static String proficiencyStars(int proficiency) {
        int clamped = Mth.clamp(proficiency, 0, MAX_TRICK_PROFICIENCY);
        return "★".repeat(clamped) + "☆".repeat(MAX_TRICK_PROFICIENCY - clamped);
    }

    /**
     * Erhoeht die Freundschaft. Bei respectCooldown zaehlt der Gewinn pro
     * Spieler nur alle {@link #PET_FRIENDSHIP_COOLDOWN_TICKS} Ticks
     * (Anti-Klickspam beim Streicheln).
     */
    public void gainFriendship(Player player, int amount, boolean respectCooldown) {
        if (this.level().isClientSide) {
            return;
        }
        UUID id = player.getUUID();
        long now = this.level().getGameTime();
        if (respectCooldown) {
            Long last = this.lastFriendshipGain.get(id);
            if (last != null && now - last < PET_FRIENDSHIP_COOLDOWN_TICKS) {
                return;
            }
        }
        this.lastFriendshipGain.put(id, now);
        trimOldest(this.lastFriendshipGain, MAX_TRANSIENT_PLAYER_ENTRIES);
        int before = getFriendship(id);
        int after = Mth.clamp(before + amount, 0, MAX_FRIENDSHIP);
        if (after == before) {
            return;
        }
        setFriendship(id, after);
        FriendshipTier beforeTier = FriendshipTier.of(before);
        FriendshipTier afterTier = FriendshipTier.of(after);
        if (shouldDisplayFriendshipProgress(before, after) && beforeTier == afterTier) {
            player.displayClientMessage(Component.translatable(
                    "msg.goobymod.friendship", after, MAX_FRIENDSHIP), true);
        }
        if (afterTier != beforeTier) {
            onTierUp(player, beforeTier, afterTier, now);
        }
        if (before < MAX_FRIENDSHIP && after == MAX_FRIENDSHIP
                && player instanceof ServerPlayer serverPlayer) {
            GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.BEST_FRIENDS);
        }
    }

    public static boolean shouldDisplayFriendshipProgress(int before, int after) {
        return FriendshipTier.of(before) != FriendshipTier.of(after) || before / 5 != after / 5;
    }

    private void onTierUp(Player player, FriendshipTier previousTier, FriendshipTier tier, long now) {
        this.tierUpCount++;
        getMemory(player.getUUID()).rememberTier(tier, now);
        NeoForge.EVENT_BUS.post(new GoobyTierChangeEvent(this, player, previousTier, tier));
        triggerPriorityAction("tier_up", 34);
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(tier == FriendshipTier.BEST_FRIEND
                            ? ModParticles.HEART_GOLD.get() : ParticleTypes.HEART,
                    getX(), getY() + 1.3, getZ(), tier == FriendshipTier.BEST_FRIEND ? 16 : 10,
                    0.5, 0.4, 0.5, 0.03);
            // Tier-Ups sind selten (max. 3 pro Freundschaft) — Konfetti immer.
            spawnConfettiBurst(serverLevel, tier == FriendshipTier.BEST_FRIEND
                    ? CONFETTI_TIER_UP_BEST_COUNT : CONFETTI_TIER_UP_COUNT);
        }
        playSound(ModSounds.GOOBY_TIER_UP_JINGLE.get(), 1.0F, 1.0F);
        showBubble(switch (tier) {
            case STRANGER -> GoobySpeech.GREET.getFirst();
            case BUDDY -> GoobySpeech.TIER_UP_BUDDY;
            case FRIEND -> GoobySpeech.TIER_UP_FRIEND;
            case BEST_FRIEND -> GoobySpeech.TIER_UP_BEST_FRIEND;
        });
        player.displayClientMessage(Component.translatable("msg.goobymod.tier_up",
                tier.icon(), Component.translatable(tier.translationKey())), true);
    }

    // ------------------------------------------------------------------
    // KI
    // ------------------------------------------------------------------

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(1, new GoobyWildPanicGoal(this));
        this.goalSelector.addGoal(2, new GoobyAlertGoal(this));
        this.goalSelector.addGoal(3, new AvoidEntityGoal<>(this, Player.class, 10.0F,
                1.1, 1.35, player -> isShyWild() && !player.isSpectator()));
        this.goalSelector.addGoal(3, new GoobyShelterGoal(this));
        this.goalSelector.addGoal(4, new GoobyFollowParentGoal(this));
        this.goalSelector.addGoal(4, new GoobySitGoal(this));
        // Gleiche Prioritaet wie GoobyTemptGoal, aber VOR ihm registriert:
        // starten beide im selben Tick, gewinnt der Apport (Insertion-Order).
        // Ein BEREITS laufendes Tempt wird bewusst NICHT unterbrochen —
        // gleiche Prioritaet preemptet in Vanilla nie (WrappedGoal
        // .canBeReplacedBy verlangt strikt kleinere Zahl); der Apport startet,
        // sobald die Nutella-Lockung endet. Sicherheit/Flucht (Panic/Alert/
        // Shelter, Prio 1-3) bleibt immer vorrangig und beendet ueber die
        // canWork-Gates auch einen laufenden Apport sofort.
        this.goalSelector.addGoal(5, new GoobyFetchGoal(this, 1.25));
        this.goalSelector.addGoal(5, new GoobyTemptGoal(this));
        this.goalSelector.addGoal(6, new GoobyFollowOwnerGoal(this, 1.15, 6.0F, 2.5F));
        this.goalSelector.addGoal(7, new GoobySleepGoal(this));
        this.goalSelector.addGoal(8, new GoobyDigGoal(this));
        this.goalSelector.addGoal(9, new GoobyRandomSitGoal(this));
        this.goalSelector.addGoal(10, new GoobyFamilyPlayGoal(this));
        this.goalSelector.addGoal(10, new GoobyRhythmStrollGoal(this, 1.0));
        this.goalSelector.addGoal(11, new LookAtPlayerGoal(this, Player.class, 10.0F));
        this.goalSelector.addGoal(12, new RandomLookAroundGoal(this));
        this.goalSelector.addGoal(13, new GoobySocialGoal(this));
    }

    /**
     * Nur fuer GameTests: laeuft im GoalSelector gerade ein Goal dieses Typs
     * (inkl. Subklassen)? Macht Prioritaets-/Preemption-Verhalten testbar,
     * ohne Reflection auf Vanilla-Interna.
     */
    public boolean isGoalRunning(Class<? extends Goal> type) {
        return this.goalSelector.getAvailableGoals().stream()
                .anyMatch(wrapped -> wrapped.isRunning() && type.isInstance(wrapped.getGoal()));
    }

    /**
     * Sitzen NUR auf Befehl: Vanilla-{@link SitWhenOrderedToGoal} laesst Tiere
     * auch sitzen, wenn der Besitzer offline ist (getOwner() == null) — das
     * wuerde bei Goobys flackern. Diese Variante ist strikt befehlsgebunden.
     */
    private static class GoobySitGoal extends SitWhenOrderedToGoal {
        private final GoobyEntity gooby;

        GoobySitGoal(GoobyEntity gooby) {
            super(gooby);
            this.gooby = gooby;
        }

        @Override
        public boolean canUse() {
            return this.gooby.isOrderedToSit() && super.canUse();
        }
    }

    /** Nutella lockt — aber nicht, wenn der Besitzer STAY befohlen hat. */
    private static class GoobyTemptGoal extends TemptGoal {
        private final GoobyEntity gooby;

        GoobyTemptGoal(GoobyEntity gooby) {
            super(gooby, 1.15, Ingredient.of(ModItems.NUTELLA.get()), false);
            this.gooby = gooby;
        }

        @Override
        public boolean canUse() {
            return !this.gooby.isOrderedToSit() && super.canUse();
        }
    }

    @Override
    public void aiStep() {
        super.aiStep();
        if (this.level().isClientSide) {
            clientCuteParticles();
        }
    }

    private void clientCuteParticles() {
        if (isGoobySleeping() && !isInHutch() && this.tickCount % 30 == 0) {
            List<GoobyEntity> huddle = this.level().getEntitiesOfClass(GoobyEntity.class,
                    getBoundingBox().inflate(3.0), GoobyEntity::isGoobySleeping);
            if (huddle.size() >= 3 && huddle.stream().mapToInt(Entity::getId).min().orElse(getId()) != getId()) {
                return;
            }
            this.level().addParticle(ModParticles.ZZZ.get(),
                    this.getX() + (this.random.nextDouble() - 0.5) * 0.4,
                    this.getY() + 1.15,
                    this.getZ() + (this.random.nextDouble() - 0.5) * 0.4,
                    huddle.size() >= 3 ? 1.0 : 0.0, 0.03, 0.0);
        }
    }

    @Override
    protected void customServerAiStep() {
        super.customServerAiStep();
        ServerLevel level = (ServerLevel) this.level();

        tickBubble();
        tickSadness();
        tickDigging(level);
        tickSatisfaction(level);
        tickPetRequests(level);
        tickCreateIntegration(level);
        tickIdleLines(level);
        tickGreetings(level);
        tickTagAlong(level);
        tickAnniversary(level);
        tickWeatherSense(level);
        tickMood(level);
        tickOwnerInspection(level);
        tickJarTarget(level);
        tickDangerEscape();
        tickGuardianState();
        tickHutchWakeRoutine();
        tickFamilyLifecycle(level);
        tickWildWorldPresence(level);
        tickTreasureSeek(level);
        tickSocialCommunity(level);
        tickLanding(level);
        if (this.tickCount % 20 == 0) {
            pruneTransientPlayerState(level.getGameTime());
        }

        if (this.brushCooldown > 0) {
            this.brushCooldown--;
        }
        if (this.trickConfettiIn > 0 && --this.trickConfettiIn == 0) {
            // Der Trick ist jetzt VOLLENDET (Countdown = Clip-Dauer).
            spawnConfettiBurst(level, CONFETTI_TRICK_COUNT);
        }
        if (this.giftCooldown > 0) {
            this.giftCooldown--;
        }
        if (this.sleepSuppressedTicks > 0) {
            this.sleepSuppressedTicks--;
        }
        if (this.actionAnimationTicks > 0) {
            this.actionAnimationTicks--;
        }
        if (this.activePetterTicks > 0 && --this.activePetterTicks == 0) {
            this.entityData.set(DATA_ACTIVE_PETTER, "");
        }
        if (this.shakeWaterTicks > 0 && --this.shakeWaterTicks == 0) {
            this.entityData.set(DATA_SHAKING_WATER, false);
        }
        if (this.hidingFromThunderTicks > 0 && --this.hidingFromThunderTicks == 0) {
            this.entityData.set(DATA_HIDING_FROM_THUNDER, false);
        }
        if (this.babyTumbleCooldown > 0) {
            this.babyTumbleCooldown--;
        }
        if (this.recentlyWokeTicks > 0 && --this.recentlyWokeTicks == 0) {
            this.entityData.set(DATA_RECENTLY_WOKE, false);
        }
        if (isGoobySleeping()) {
            if (this.tickCount % 90 == 0) {
                playRateLimitedSound(ModSounds.GOOBY_SNORE.get(), 0.35F, 1.0F, 30);
            }
        }
    }

    private void tickFamilyLifecycle(ServerLevel level) {
        boolean baby = isBaby();
        if (this.wasBabyLastTick && !baby) {
            triggerPriorityAction("grow_up_pop", 30);
            playSound(ModSounds.GOOBY_NUZZLE.get(), 0.8F, 1.18F);
            level.sendParticles(ParticleTypes.HAPPY_VILLAGER, getX(), getY() + 0.9, getZ(),
                    18, 0.65, 0.55, 0.65, 0.04);
            showBubble("bubble.goobymod.grown_up");
        }
        this.wasBabyLastTick = baby;
        if (baby && this.tickCount % 1200 == 0 && this.bubbleTicks == 0
                && level.getNearestPlayer(this, 10.0) != null) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.BABY, this.random));
        }
    }

    private void tickWildWorldPresence(ServerLevel level) {
        if (this.burrowResident && this.homePos == null) {
            markBurrowResident();
        }
        if (!isTame() && this.tickCount % 600 == 0) {
            playRateLimitedSound(ModSounds.GOOBY_WILD_CALL.get(), 1.35F, 0.95F, 100);
        }
        if (this.burrowResident && this.tickCount % 20 == 0
                && level.getNearestPlayer(this, 8.0) instanceof ServerPlayer player) {
            GoobyAdvancements.grant(player, GoobyAdvancements.FOUND_BURROW);
        }
        if (!onGround() || this.tickCount % 6 != 0 || getDeltaMovement().horizontalDistanceSqr() < 0.001) {
            return;
        }
        if (level.getNearestPlayer(this, 24.0) == null) {
            return;
        }
        BlockState ground = level.getBlockState(blockPosition().below());
        if (ground.is(BlockTags.SAND) || ground.is(BlockTags.SNOW)
                || ground.is(Blocks.SNOW_BLOCK) || ground.is(Blocks.POWDER_SNOW)) {
            level.sendParticles(ModParticles.PAW_PRINT.get(), getX(), getY() + 0.03, getZ(),
                    1, 0.08, 0.0, 0.08, 0.0);
        }
    }

    public boolean isSeekingTreasure() {
        return this.entityData.get(DATA_SEEKING_TREASURE);
    }

    @Nullable
    public BlockPos getSeekTarget() {
        return this.seekTarget;
    }

    public long getSeekCooldownUntil() {
        return this.seekCooldownUntil;
    }

    /**
     * Starts one bounded underground search. A treat in the other hand is the
     * explicit cost, and failed searches still consume the cooldown so repeated
     * empty scans cannot become a server-tick exploit.
     */
    public boolean tryStartSeek(Player player, ItemStack shown, long gameTime) {
        if (!isOwnedBy(player) || isBaby()
                || !getFriendshipTier(player.getUUID()).canReceiveGifts()
                || isSeekingTreasure()) {
            denyInteraction(player, "msg.goobymod.seek_denied");
            return false;
        }
        if (gameTime < this.seekCooldownUntil) {
            // Cooldown NIE unsichtbar lassen: Restzeit in Sekunden anzeigen.
            denyInteraction(player, Component.translatable("msg.goobymod.seek_cooldown",
                    (this.seekCooldownUntil - gameTime + 19L) / 20L));
            return false;
        }
        ItemStack treat = player.getMainHandItem() == shown
                ? player.getOffhandItem() : player.getMainHandItem();
        if (!treat.is(ModItems.TRAINING_TREAT.get())) {
            denyInteraction(player, "msg.goobymod.seek_needs_treat");
            return false;
        }

        this.seekCooldownUntil = gameTime + GoobyConfig.seekCooldownTicks();
        if (!player.getAbilities().instabuild) {
            treat.shrink(1);
        }
        playSound(ModSounds.GOOBY_SNIFF_LONG.get(), 0.8F, 1.0F);
        BlockPos found = findSeekTarget(shown);
        if (found == null) {
            showBubble("bubble.goobymod.seek_nothing");
            player.displayClientMessage(Component.translatable("msg.goobymod.seek_nothing", getName()), true);
            return false;
        }

        this.seekTarget = found.immutable();
        this.entityData.set(DATA_SEEKING_TREASURE, true);
        showBubble("bubble.goobymod.seek_found");
        player.displayClientMessage(Component.translatable("msg.goobymod.seek_started", getName()), true);
        sendSeekTrail((ServerLevel) level(), found);
        return true;
    }

    @Nullable
    public BlockPos findSeekTarget(ItemStack shown) {
        if (!(this.level() instanceof ServerLevel serverLevel) || shown.isEmpty()) {
            return null;
        }
        BlockPos origin = blockPosition();
        BlockPos best = null;
        double bestDistance = Double.MAX_VALUE;
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int minimumY = Math.max(serverLevel.getMinBuildHeight(), origin.getY() - 16);
        for (int y = origin.getY() - 1; y >= minimumY; y--) {
            for (int x = origin.getX() - 24; x <= origin.getX() + 24; x++) {
                for (int z = origin.getZ() - 24; z <= origin.getZ() + 24; z++) {
                    cursor.set(x, y, z);
                    double distance = cursor.distSqr(origin);
                    if (distance > 24.0 * 24.0 || distance >= bestDistance) {
                        continue;
                    }
                    BlockState state = serverLevel.getBlockState(cursor);
                    if (isSeekMatch(shown, state)) {
                        bestDistance = distance;
                        best = cursor.immutable();
                    }
                }
            }
        }
        return best;
    }

    private static boolean isSeekMatch(ItemStack shown, BlockState state) {
        if (shown.is(Items.CARROT)) {
            return state.is(Blocks.CARROTS);
        }
        if (shown.is(Items.POTATO)) {
            return state.is(Blocks.POTATOES);
        }
        if (shown.is(Items.BEETROOT_SEEDS)) {
            return state.is(Blocks.BEETROOTS);
        }
        if (!(shown.getItem() instanceof BlockItem blockItem) || !state.is(blockItem.getBlock())) {
            return false;
        }
        return !state.is(Tags.Blocks.ORES) || GoobyConfig.seekAllowOres();
    }

    private void tickTreasureSeek(ServerLevel level) {
        if (!isSeekingTreasure() || this.seekTarget == null) {
            return;
        }
        if (!isAlive() || isGoobySleeping() || isOrderedToSit() || getCommandMode() == GoobyCommand.STAY) {
            clearSeekTarget();
            return;
        }
        if (this.tickCount % 10 == 0) {
            getNavigation().moveTo(this.seekTarget.getX() + 0.5, this.seekTarget.getY() + 1.0,
                    this.seekTarget.getZ() + 0.5, 1.2);
        }
        Vec3 marker = Vec3.atBottomCenterOf(this.seekTarget.above());
        if (position().distanceToSqr(marker) > 6.25) {
            return;
        }
        BlockPos markerPos = this.seekTarget.above();
        if (level.getBlockState(markerPos).canBeReplaced()) {
            level.setBlock(markerPos, ModBlocks.DUG_DIRT.get().defaultBlockState(), 3);
        }
        triggerPriorityAction("dig_excited", 34);
        playSound(ModSounds.GOOBY_TRICK_CHIME.get(), 0.8F, 1.08F);
        showBubble("bubble.goobymod.seek_here");
        clearSeekTarget();
    }

    private void clearSeekTarget() {
        this.seekTarget = null;
        this.entityData.set(DATA_SEEKING_TREASURE, false);
        getNavigation().stop();
    }

    private void sendSeekTrail(ServerLevel level, BlockPos target) {
        Vec3 start = position().add(0.0, 0.15, 0.0);
        Vec3 end = Vec3.atCenterOf(target.above());
        for (int step = 1; step <= 12; step++) {
            Vec3 point = start.lerp(end, step / 12.0);
            level.sendParticles(ModParticles.PAW_PRINT.get(), point.x, point.y, point.z,
                    1, 0.02, 0.01, 0.02, 0.0);
        }
    }

    public boolean canStartSocialBehavior() {
        return !hasActiveSocialAction() && socialPriorityClear();
    }

    public boolean canContinueSocialBehavior() {
        return hasActiveSocialAction() && socialPriorityClear();
    }

    private boolean socialPriorityClear() {
        return isAlive() && getCommandMode() != GoobyCommand.STAY && !isOrderedToSit()
                && !isGoobySleeping() && !isInHutch() && !isActivelyDigging()
                && !isAlerting() && !isSeekingShelter() && !isPanicking()
                && !isVehicle() && !isPassenger();
    }

    public boolean canSocializeWith(GoobyEntity partner) {
        return canStartSocialBehavior() && partner != this && partner.canStartSocialBehavior()
                && distanceToSqr(partner) <= 36.0;
    }

    public boolean startGreetingRitual(GoobyEntity partner) {
        if (!canSocializeWith(partner)) {
            return false;
        }
        setSocialAction(SOCIAL_GREETING_INITIATOR, partner, SOCIAL_GREETING_TICKS);
        partner.setSocialAction(SOCIAL_GREETING_MIRROR, this, SOCIAL_GREETING_TICKS);
        getLookControl().setLookAt(partner, 40.0F, 30.0F);
        partner.getLookControl().setLookAt(this, 40.0F, 30.0F);
        playSound(ModSounds.GOOBY_CHIRP_SOCIAL.get(), 0.7F, 1.08F);
        partner.playSound(ModSounds.GOOBY_CHIRP_SOCIAL.get(), 0.7F, 1.16F);
        String partnerName = partner.hasCustomName()
                ? partner.getCustomName().getString() : Component.translatable("entity.goobymod.gooby").getString();
        showBubble(GoobySpeech.pickFrom(GoobySpeech.SOCIAL, this.random), partnerName);
        return true;
    }

    /**
     * Production selector for autonomous social AI. Play-chase is attempted
     * when requested and falls back to the greeting ritual while cooling down.
     */
    public boolean startSocialInteraction(GoobyEntity partner, long gameTime, boolean preferChase) {
        return preferChase && startPlayChase(partner, gameTime) || startGreetingRitual(partner);
    }

    public boolean startPlayChase(GoobyEntity partner, long gameTime) {
        if (!GoobyConfig.socialPlayChase() || !canSocializeWith(partner)
                || gameTime < this.socialCooldowns.getOrDefault(partner.getUUID(), Long.MIN_VALUE)
                || gameTime < partner.socialCooldowns.getOrDefault(getUUID(), Long.MIN_VALUE)) {
            return false;
        }
        long until = gameTime + SOCIAL_PAIR_COOLDOWN_TICKS;
        this.socialCooldowns.put(partner.getUUID(), until);
        partner.socialCooldowns.put(getUUID(), until);
        trimOldest(this.socialCooldowns, MAX_PARTNER_HISTORY_ENTRIES);
        trimOldest(partner.socialCooldowns, MAX_PARTNER_HISTORY_ENTRIES);
        setSocialAction(SOCIAL_PLAY_CHASE, partner, SOCIAL_CHASE_TICKS);
        partner.setSocialAction(SOCIAL_PLAY_CHASE, this, SOCIAL_CHASE_TICKS);
        return true;
    }

    public boolean isPlayChaseCoolingDown(UUID partner, long gameTime) {
        return gameTime < this.socialCooldowns.getOrDefault(partner, Long.MIN_VALUE);
    }

    private void setSocialAction(byte action, GoobyEntity partner, int ticks) {
        setSynced(DATA_SOCIAL_ACTION, action);
        setSynced(DATA_SOCIAL_PARTNER, partner.getUUID().toString());
        this.socialActionTicks = ticks;
    }

    private void clearSocialAction() {
        setSynced(DATA_SOCIAL_ACTION, SOCIAL_NONE);
        setSynced(DATA_SOCIAL_PARTNER, "");
        this.socialActionTicks = 0;
        this.getNavigation().stop();
    }

    /** Deterministic timer hook used by the bounded chase regression test. */
    public void tickSocialStateForTest() {
        tickActiveSocialState();
    }

    private void tickActiveSocialState() {
        if (!hasActiveSocialAction()) {
            return;
        }
        if (!socialPriorityClear()) {
            clearSocialAction();
            return;
        }
        if (getSocialAction() == SOCIAL_PLAY_CHASE && this.tickCount % 10 == 0
                && level() instanceof ServerLevel level && getSocialPartnerId() != null
                && level.getEntity(getSocialPartnerId()) instanceof GoobyEntity partner && partner.isAlive()) {
            getNavigation().moveTo(partner, 1.28);
        }
        if (--this.socialActionTicks <= 0) {
            clearSocialAction();
        }
    }

    private void tickSocialCommunity(ServerLevel level) {
        tickActiveSocialState();
        tickPlayerEmotes(level);
        if (isGoobySleeping() && this.tickCount % 20 == 0) {
            checkGroupNapAdvancement(level);
        }
        if (this.giftCharges <= 0 || !socialPriorityClear() || this.tickCount % 1200 != getId() % 1200) {
            return;
        }
        GoobyEntity partner = level.getEntitiesOfClass(GoobyEntity.class, getBoundingBox().inflate(4.0),
                        candidate -> candidate != this && candidate.isAlive())
                .stream().findFirst().orElse(null);
        if (partner != null) {
            this.giftCharges--;
            level.sendParticles(ParticleTypes.HEART,
                    (getX() + partner.getX()) * 0.5, Math.max(getY(), partner.getY()) + 1.0,
                    (getZ() + partner.getZ()) * 0.5, 6, 0.35, 0.25, 0.35, 0.02);
            showBubble(GoobySpeech.pickFrom(GoobySpeech.SOCIAL, this.random),
                    partner.hasCustomName() ? partner.getCustomName().getString()
                            : Component.translatable("entity.goobymod.gooby").getString());
        }
    }

    private void tickPlayerEmotes(ServerLevel level) {
        if (!GoobyConfig.socialEmoteReactions()) {
            return;
        }
        long now = level.getGameTime();
        // players() statt getEntitiesOfClass(): Emote-Erkennung braucht Tick-genaue
        // Flanken, aber kein Entity-Section-Scan samt Listen-Allokation pro Gooby-Tick.
        AABB range = getBoundingBox().inflate(6.0);
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || !player.isAlive()
                    || !range.contains(player.getX(), player.getY(), player.getZ())) {
                continue;
            }
            EmoteMemory memory = emoteMemory(player.getUUID());
            memory.lastTouched = now;
            boolean crouching = player.isShiftKeyDown();
            if (crouching && !memory.wasCrouching) {
                recordSneakToggle(player, now, isLookedAtBy(player));
            }
            boolean grounded = player.onGround();
            if (!grounded && memory.wasOnGround && player.getDeltaMovement().y > 0.15) {
                recordNearbyJump(player, now);
            }
            memory.wasCrouching = crouching;
            memory.wasOnGround = grounded;
        }
    }

    private EmoteMemory emoteMemory(UUID playerId) {
        EmoteMemory memory = this.emoteMemories.computeIfAbsent(playerId, ignored -> new EmoteMemory());
        trimOldest(this.emoteMemories, MAX_TRANSIENT_PLAYER_ENTRIES);
        return memory;
    }

    public boolean recordSneakToggle(Player player, long gameTime, boolean lookingAtGooby) {
        if (!GoobyConfig.socialEmoteReactions()) {
            return false;
        }
        EmoteMemory memory = emoteMemory(player.getUUID());
        memory.lastTouched = gameTime;
        if (memory.sneakWindowStart == Long.MIN_VALUE || gameTime - memory.sneakWindowStart > 20L) {
            memory.sneakWindowStart = gameTime;
            memory.sneakPresses = 0;
        }
        memory.sneakPresses++;
        if (memory.sneakPresses < 2 || !lookingAtGooby) {
            return false;
        }
        memory.sneakPresses = 0;
        memory.sneakWindowStart = Long.MIN_VALUE;
        this.bowReactionCount++;
        triggerPriorityAction("bow", 26);
        showBubble(GoobySpeech.EMOTE_BOW);
        return true;
    }

    public boolean recordNearbyJump(Player player, long gameTime) {
        if (!GoobyConfig.socialEmoteReactions() || getMood() != GoobyMood.HAPPY) {
            return false;
        }
        EmoteMemory memory = emoteMemory(player.getUUID());
        memory.lastTouched = gameTime;
        if (memory.jumpWindowStart == Long.MIN_VALUE || gameTime - memory.jumpWindowStart > 40L) {
            memory.jumpWindowStart = gameTime;
            memory.jumps = 0;
        }
        memory.jumps++;
        if (memory.jumps < 3) {
            return false;
        }
        memory.jumps = 0;
        memory.jumpWindowStart = Long.MIN_VALUE;
        triggerPriorityAction("happy_bounce", 18);
        showBubble(GoobySpeech.EMOTE_JUMP);
        return true;
    }

    @Nullable
    public BlockPos findSocialNapSpot() {
        return level().getEntitiesOfClass(GoobyEntity.class, getBoundingBox().inflate(6.0),
                        candidate -> candidate != this && candidate.isGoobySleeping() && !candidate.isInHutch())
                .stream()
                .map(candidate -> candidate.blockPosition().east())
                .filter(pos -> level().getBlockState(pos).canBeReplaced())
                .findFirst()
                .orElse(null);
    }

    public boolean hasSleepingNeighbor() {
        return !level().getEntitiesOfClass(GoobyEntity.class, getBoundingBox().inflate(3.0),
                candidate -> candidate != this && candidate.isGoobySleeping()).isEmpty();
    }

    public boolean checkGroupNapAdvancement(ServerLevel level) {
        int sleepers = level.getEntitiesOfClass(GoobyEntity.class, getBoundingBox().inflate(3.0),
                GoobyEntity::isGoobySleeping).size();
        if (sleepers < 3) {
            return false;
        }
        for (ServerPlayer player : level.getEntitiesOfClass(ServerPlayer.class, getBoundingBox().inflate(8.0),
                candidate -> !candidate.isSpectator())) {
            GoobyAdvancements.grant(player, GoobyAdvancements.GROUP_NAP);
        }
        return true;
    }

    private void tickGuardianState() {
        if (this.panicTicks > 0 && --this.panicTicks == 0) {
            this.entityData.set(DATA_PANICKING, false);
        }
        // Virtuelle Schutz-"Ausdauer" erholt sich in ruhigen Momenten vollstaendig in ca. 20 s.
        this.guardianPressure = Math.min(getMaxHealth(), this.guardianPressure + getMaxHealth() / 400.0F);
    }

    private void tickLanding(ServerLevel level) {
        boolean grounded = onGround();
        if (!grounded && this.wasOnGroundLastTick) {
            this.airborneStartY = getY();
        } else if (grounded && !this.wasOnGroundLastTick) {
            double drop = this.airborneStartY - getY();
            if (drop > 2.0 && tryTriggerAction("land", 8)) {
                this.landingSquashes++;
                // Landungs-Plumps (inkl. Fetch-Spruenge): Fell staubt kurz auf.
                // tryTriggerAction("land", 8) dedupliziert bereits pro Landung.
                spawnFluffPuffs(level, FLUFF_LANDING_COUNT, getY() + 0.15);
            }
        }
        this.wasOnGroundLastTick = grounded;
    }

    private void pruneTransientPlayerState(long now) {
        this.greetedPlayers.entrySet().removeIf(entry -> now - entry.getValue() > TRANSIENT_PLAYER_STATE_TTL);
        this.lastFriendshipGain.entrySet().removeIf(entry -> now - entry.getValue() > TRANSIENT_PLAYER_STATE_TTL);
        this.lastSatisfactionLoss.entrySet().removeIf(entry -> now - entry.getValue() > TRANSIENT_PLAYER_STATE_TTL);
        this.lastBareHandInteraction.entrySet().removeIf(
                entry -> now - entry.getValue() > TRANSIENT_PLAYER_STATE_TTL);
        this.emoteMemories.entrySet().removeIf(
                entry -> now - entry.getValue().lastTouched > TRANSIENT_PLAYER_STATE_TTL);
        // Abgelaufene Eintraege verhalten sich exakt wie fehlende (getOrDefault MIN_VALUE);
        // ohne Pruning wachsen diese (teils persistierten) Maps mit jedem je getroffenen Partner.
        this.socialCooldowns.entrySet().removeIf(entry -> now >= entry.getValue());
        this.familyRituals.entrySet().removeIf(entry -> now - entry.getValue() >= GoobyConfig.familyRitualCooldown());
        trimOldest(this.greetedPlayers, MAX_TRANSIENT_PLAYER_ENTRIES);
        trimOldest(this.lastFriendshipGain, MAX_TRANSIENT_PLAYER_ENTRIES);
        trimOldest(this.lastSatisfactionLoss, MAX_TRANSIENT_PLAYER_ENTRIES);
        trimOldest(this.lastBareHandInteraction, MAX_TRANSIENT_PLAYER_ENTRIES);
        trimOldest(this.emoteMemories, MAX_TRANSIENT_PLAYER_ENTRIES);
        trimOldest(this.socialCooldowns, MAX_PARTNER_HISTORY_ENTRIES);
        trimOldest(this.familyRituals, MAX_PARTNER_HISTORY_ENTRIES);
    }

    /**
     * Symmetrische Lifecycle-Hooks pflegen den {@link GoobyLoadedIndex}:
     * Chunk-Load/-Unload, Discard, Tod und Dimensionswechsel halten ihn exakt
     * auf der Menge der geladenen serverseitigen Goobys (Logout-Cleanup laeuft
     * seit 5.3 ueber diesen Index statt ueber einen All-Entities-Scan).
     */
    @Override
    public void onAddedToLevel() {
        super.onAddedToLevel();
        if (!level().isClientSide) {
            GoobyLoadedIndex.add(this);
        }
    }

    @Override
    public void onRemovedFromLevel() {
        if (!level().isClientSide) {
            GoobyLoadedIndex.remove(this);
        }
        super.onRemovedFromLevel();
    }

    /** Drops session-only state immediately when a player disconnects. */
    public void removeTransientPlayerState(UUID playerId) {
        this.greetedPlayers.remove(playerId);
        this.lastFriendshipGain.remove(playerId);
        this.lastSatisfactionLoss.remove(playerId);
        this.lastBareHandInteraction.remove(playerId);
        this.emoteMemories.remove(playerId);
        if (playerId.equals(this.tagAlongPlayer)) {
            this.tagAlongPlayer = null;
            this.tagAlongTicks = 0;
        }
        if (playerId.toString().equals(this.entityData.get(DATA_ACTIVE_PETTER))) {
            this.activePetterTicks = 0;
            setSynced(DATA_ACTIVE_PETTER, "");
        }
    }

    /** Nur fuer GameTests: Gesamtgroesse der transienten Spieler-/Partner-Maps. */
    public int transientStateSizeForTest() {
        return this.emoteMemories.size() + this.socialCooldowns.size() + this.familyRituals.size()
                + this.greetedPlayers.size() + this.lastFriendshipGain.size()
                + this.lastSatisfactionLoss.size() + this.lastBareHandInteraction.size();
    }

    /** Nur fuer GameTests: erzwingt das Pruning, das sonst sekuendlich im Server-Tick laeuft. */
    public void pruneTransientStateForTest(long now) {
        pruneTransientPlayerState(now);
    }

    private void tickWeatherSense(ServerLevel level) {
        boolean exposedRain = level.isRaining() && level.canSeeSky(blockPosition());
        if (exposedRain) {
            this.wetExposureTicks = Math.min(200, this.wetExposureTicks + 1);
        } else if (this.wetExposureTicks >= 20 && this.shakeWaterTicks == 0 && onGround()) {
            this.wetExposureTicks = 0;
            this.shakeWaterTicks = 22;
            this.entityData.set(DATA_SHAKING_WATER, true);
            playSound(ModSounds.GOOBY_SHAKE.get(), 0.75F, 1.0F);
            level.sendParticles(ParticleTypes.SPLASH, getX(), getY() + 0.8, getZ(),
                    14, 0.55, 0.45, 0.55, 0.12);
        }
        if (level.isThundering()) {
            setMoodScaredImmediately();
        } else if (this.hidingFromThunderTicks == 0) {
            this.entityData.set(DATA_HIDING_FROM_THUNDER, false);
        }
    }

    private void tickMood(ServerLevel level) {
        if (this.tickCount % 20 != 0) {
            return;
        }
        ServerPlayer owner = getOwnerUUID() == null ? null
                : level.getServer().getPlayerList().getPlayer(getOwnerUUID());
        if (isTame() && (owner == null || owner.level() != level || distanceToSqr(owner) > 24.0 * 24.0)) {
            this.ownerAwayTicks = Math.min(Integer.MAX_VALUE - 20, this.ownerAwayTicks + 20);
        } else {
            this.ownerAwayTicks = 0;
        }
        long now = level.getGameTime();
        GoobyMood desired = GoobyMood.derive(getSatisfaction(), Math.max(0L, now - this.lastFedTime),
                level.isNight(), this.ownerAwayTicks, GoobyConfig.hungerTicks(), GoobyConfig.lonelyTicks(),
                isPanicking() || isAlerting() || level.isThundering());
        if (desired != getMood() && GoobyMood.canTransition(this.lastMoodChange, now)) {
            setMood(desired);
            this.lastMoodChange = now;
        }
        if (getMood() == GoobyMood.HUNGRY && this.tickCount % 200 == 0) {
            level.sendParticles(new ItemParticleOption(ParticleTypes.ITEM, new ItemStack(ModItems.NUTELLA.get())),
                    getX(), getY() + 1.55, getZ(), 1, 0.08, 0.08, 0.08, 0.0);
        }
    }

    private void tickOwnerInspection(ServerLevel level) {
        ServerPlayer owner = getOwnerUUID() == null ? null
                : level.getServer().getPlayerList().getPlayer(getOwnerUUID());
        if (owner == null || owner.level() != level || !owner.isShiftKeyDown()
                || distanceToSqr(owner) > 64.0 || !isLookedAtBy(owner)) {
            this.inspectionLookTicks = 0;
            return;
        }
        if (++this.inspectionLookTicks >= 20 && this.inspectionLookTicks % 20 == 0) {
            FriendshipTier tier = getFriendshipTier(owner.getUUID());
            owner.displayClientMessage(Component.translatable("msg.goobymod.status",
                    getSatisfaction(), tier.icon(), Component.translatable(tier.translationKey()),
                    Component.translatable(getMood().translationKey()), getGiftCharges(),
                    Component.translatable(this.selectedTrick.translationKey()),
                    proficiencyStars(getTrickProficiency(this.selectedTrick)), wardrobeGlyphs(),
                    Component.translatable(getCoatVariant().translationKey())), true);
        }
    }

    private boolean isLookedAtBy(Player player) {
        Vec3 look = player.getViewVector(1.0F).normalize();
        Vec3 toGooby = position().add(0.0, getBbHeight() * 0.6, 0.0)
                .subtract(player.getEyePosition()).normalize();
        return look.dot(toGooby) > 0.965;
    }

    private void tickBubble() {
        if (this.bubbleTicks > 0 && --this.bubbleTicks == 0) {
            this.entityData.set(DATA_BUBBLE_KEY, "");
            this.entityData.set(DATA_BUBBLE_ARG, "");
        }
        if (this.wantPetBubbleCooldown > 0) {
            this.wantPetBubbleCooldown--;
        }
        if (this.sadBubbleCooldown > 0) {
            this.sadBubbleCooldown--;
        }
    }

    private void tickSadness() {
        if (this.sadTicks > 0 && --this.sadTicks == 0) {
            this.entityData.set(DATA_SAD, false);
        }
    }

    private void tickDigging(ServerLevel level) {
        if (this.digTicks <= 0) {
            return;
        }
        this.getNavigation().stop();
        BlockPos below = this.blockPosition().below();
        if (this.tickCount % 4 == 0) {
            level.levelEvent(2001, below, net.minecraft.world.level.block.Block.getId(level.getBlockState(below)));
        }
        if (--this.digTicks == 0) {
            finishDig(this.random);
        }
    }

    private void tickSatisfaction(ServerLevel level) {
        if (!isGoobySleeping() && ++this.satisfactionDecayTimer >= 150) {
            this.satisfactionDecayTimer = 0;
            addSatisfaction(-1);
        }
        AttributeInstance speed = getAttribute(Attributes.MOVEMENT_SPEED);
        boolean happy = getSatisfaction() >= HAPPY_THRESHOLD;
        if (speed != null) {
            boolean has = speed.hasModifier(HAPPY_SPEED_ID);
            if (happy && !has) {
                speed.addTransientModifier(HAPPY_SPEED);
            } else if (!happy && has) {
                speed.removeModifier(HAPPY_SPEED_ID);
            }
        }
        // Gluecks-Aura: funkelnde Partikel, wenn Gooby richtig happy ist
        if (happy && !isGoobySleeping() && this.tickCount % 12 == 0) {
            level.sendParticles(ParticleTypes.HAPPY_VILLAGER,
                    this.getX() + (this.random.nextDouble() - 0.5) * 1.2,
                    this.getY() + 0.4 + this.random.nextDouble(),
                    this.getZ() + (this.random.nextDouble() - 0.5) * 1.2,
                    1, 0.0, 0.02, 0.0, 0.0);
        }
    }

    /**
     * Scheue Wild-Goobys FLIEHEN vor Spielern (AvoidEntityGoal). Sie duerfen
     * nicht gleichzeitig um Streicheleinheiten betteln oder winkend gruessen —
     * das widerspruechliche Doppel-Feedback fuehlte sich kaputt an.
     */
    public boolean isOpenToPlayers() {
        return !isShyWild() && !isPanicking() && !isAlerting();
    }

    private void tickPetRequests(ServerLevel level) {
        if (isGoobySleeping() || isDigging() || getMood() == GoobyMood.SLEEPY
                || !isOpenToPlayers()) {
            return;
        }
        if (!this.wantsPet && --this.petRequestIn <= 0) {
            this.wantsPet = true;
        }
        if (this.wantsPet) {
            Player nearest = level.getNearestPlayer(this, 12.0);
            if (nearest != null) {
                getLookControl().setLookAt(nearest, 30.0F, 30.0F);
                if (this.wantPetBubbleCooldown == 0) {
                    showBubble(GoobySpeech.WANT_PET);
                    this.wantPetBubbleCooldown = 180;
                    playSound(ModSounds.GOOBY_SQUEAK.get(), 0.6F, 1.25F);
                }
            }
        }
    }

    private void tickIdleLines(ServerLevel level) {
        if (--this.nextIdleLineIn > 0) {
            return;
        }
        Player nearest = level.getNearestPlayer(this, 16.0);
        if (nearest == null || isGoobySleeping() || this.bubbleTicks > 0) {
            this.nextIdleLineIn = 400;
            return;
        }
        boolean raining = level.isRaining() && level.canSeeSky(blockPosition());
        boolean night = level.isNight();
        boolean cake = isCakeNearby(level, nearest);
        GoobyEntity namedFriend = level.getEntitiesOfClass(GoobyEntity.class,
                        getBoundingBox().inflate(8.0),
                        candidate -> candidate != this && candidate.isAlive() && candidate.hasCustomName())
                .stream().findFirst().orElse(null);
        if (isShyWild()) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.SHY, this.random));
        } else if (namedFriend != null && this.random.nextFloat() < 0.35F) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.SOCIAL, this.random),
                    namedFriend.getCustomName().getString());
        } else if (getCommandMode() == GoobyCommand.STAY
                && CreateCompat.hasRunningMachineNearby(level, blockPosition(), 5)) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.MACHINERY, this.random));
        } else if (this.random.nextFloat() < 0.72F && getMood() == GoobyMood.HUNGRY) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.HUNGRY, this.random));
        } else if (this.random.nextFloat() < 0.72F && getMood() == GoobyMood.LONELY) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.LONELY, this.random));
        } else if (this.random.nextFloat() < 0.72F && getMood() == GoobyMood.SLEEPY) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.SLEEPY, this.random));
        } else {
            showBubble(GoobySpeech.pickIdleLine(nearest, raining, night, cake, this.random));
        }
        this.nextIdleLineIn = newIdleLineDelay(this.random);
    }

    private void tickCreateIntegration(ServerLevel level) {
        boolean moving = CreateCompat.isOnMovingContraption(this);
        if (this.wasOnMovingContraption && !moving && this.bubbleTicks == 0) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.CONTRAPTION_ARRIVAL, this.random));
        }
        this.wasOnMovingContraption = moving;

        if (getCommandMode() != GoobyCommand.STAY || this.tickCount % 100 != 0
                || !CreateCompat.hasRunningMachineNearby(level, blockPosition(), 5)) {
            if (this.tickCount % 100 == 0) {
                this.createComfortTicks = 0;
            }
            return;
        }
        this.createComfortTicks += 100;
        if (this.createComfortTicks >= 600) {
            this.createComfortTicks = 0;
            addSatisfaction(1);
        }
    }

    private boolean isCakeNearby(ServerLevel level, Player nearest) {
        if (nearest.getMainHandItem().is(Items.CAKE) || nearest.getOffhandItem().is(Items.CAKE)) {
            return true;
        }
        return BlockPos.findClosestMatch(blockPosition(), 6, 3,
                pos -> level.getBlockState(pos).is(Blocks.CAKE)).isPresent();
    }

    private void tickGreetings(ServerLevel level) {
        if (this.tickCount % 20 != 0 || isGoobySleeping() || !isOpenToPlayers()) {
            return;
        }
        List<Player> nearby = level.getEntitiesOfClass(Player.class, getBoundingBox().inflate(9.0),
                p -> !p.isSpectator());
        for (Player player : nearby) {
            Long last = this.greetedPlayers.get(player.getUUID());
            if (last == null || level.getGameTime() - last > 6000) {
                this.greetedPlayers.put(player.getUUID(), level.getGameTime());
                trimOldest(this.greetedPlayers, MAX_TRANSIENT_PLAYER_ENTRIES);
                FriendshipTier tier = getFriendshipTier(player.getUUID());
                if (tier.canWaveGreeting()) {
                    tryTriggerAction("wave", 32);
                }
                if (this.bubbleTicks == 0) {
                    List<String> pool = switch (tier) {
                        case STRANGER -> GoobySpeech.GREET;
                        case BUDDY -> GoobySpeech.GREET_BUDDY;
                        case FRIEND -> GoobySpeech.GREET_FRIEND;
                        case BEST_FRIEND -> GoobySpeech.GREET_BEST_FRIEND;
                    };
                    showBubble(GoobySpeech.pickReaction(pool, player, this.random));
                }
                playSound(ModSounds.GOOBY_SQUEAK.get(), 0.7F, 1.1F);
                break;
            }
        }
    }

    public boolean shouldTagAlong(Player player) {
        return isTame() && player.isSprinting()
                && getFriendshipTier(player.getUUID()).ordinal() >= FriendshipTier.FRIEND.ordinal()
                && getCommandMode() != GoobyCommand.STAY
                && !isGoobySleeping() && !isAlerting() && !isSeekingShelter();
    }

    private void tickTagAlong(ServerLevel level) {
        if (this.tagAlongTicks > 0 && this.tagAlongPlayer != null) {
            this.tagAlongTicks--;
            ServerPlayer player = level.getServer().getPlayerList().getPlayer(this.tagAlongPlayer);
            if (player == null || player.level() != level || distanceToSqr(player) > 18.0 * 18.0
                    || getCommandMode() == GoobyCommand.STAY) {
                this.tagAlongTicks = 0;
                this.tagAlongPlayer = null;
                return;
            }
            if (this.tickCount % 10 == 0 && distanceToSqr(player) > 3.0 * 3.0) {
                getNavigation().moveTo(player, 1.25);
            }
            return;
        }
        if (this.tickCount % 10 != 0) {
            return;
        }
        Player sprinter = level.getNearestPlayer(this, 6.0);
        if (sprinter != null && shouldTagAlong(sprinter)) {
            this.tagAlongPlayer = sprinter.getUUID();
            this.tagAlongTicks = 80;
            getNavigation().moveTo(sprinter, 1.25);
        }
    }

    private void tickAnniversary(ServerLevel level) {
        if (this.tickCount % 200 != 0 || this.bubbleTicks > 0) {
            return;
        }
        long now = level.getGameTime();
        for (Player player : level.getEntitiesOfClass(Player.class, getBoundingBox().inflate(12.0),
                candidate -> !candidate.isSpectator())) {
            FriendshipMemory memory = this.memories.get(player.getUUID());
            if (memory != null && memory.isAnniversaryDue(now)) {
                memory.markAnniversaryShown();
                showBubble(GoobySpeech.pickFrom(GoobySpeech.ANNIVERSARY, this.random));
                playSound(ModSounds.GOOBY_PURR.get(), 0.7F, 0.95F);
                break;
            }
        }
    }

    private void tickJarTarget(ServerLevel level) {
        if (this.jarTarget == null) {
            return;
        }
        if (!level.getBlockState(this.jarTarget).is(ModBlocks.NUTELLA_JAR.get())) {
            this.jarTarget = null;
            return;
        }
        if (this.jarTarget.distToCenterSqr(position()) < 3.5) {
            level.removeBlock(this.jarTarget, false);
            magicMoment(level, Vec3.atCenterOf(this.jarTarget));
            tryTriggerAction("eat", 44);
            playSound(ModSounds.GOOBY_MUNCH.get(), 1.0F, 1.0F);
            addSatisfaction(NUTELLA_SATISFACTION);
            showBubble(GoobySpeech.pickFrom(GoobySpeech.EAT, this.random));
            this.jarTarget = null;
        } else if (this.tickCount % 20 == 0) {
            getNavigation().moveTo(this.jarTarget.getX() + 0.5, this.jarTarget.getY(), this.jarTarget.getZ() + 0.5,
                    1.2);
        }
    }

    private void tickDangerEscape() {
        if (--this.dangerCheckCooldown > 0) {
            return;
        }
        this.dangerCheckCooldown = 10;
        if (isInLava() || isOnFire()) {
            teleportOutOfDanger();
        }
    }

    // ------------------------------------------------------------------
    // Interaktionen
    // ------------------------------------------------------------------

    @Override
    public InteractionResult mobInteract(Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);

        if (stack.is(ModItems.NUTELLA.get())) {
            if (!this.level().isClientSide) {
                eatNutella(player, stack);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.is(ModItems.GOOBY_BRUSH.get())) {
            if (!this.level().isClientSide) {
                if (player.isSecondaryUseActive()) {
                    cycleCoat(player);
                } else {
                    brush(player, stack, hand);
                }
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.is(ModItems.SHIMMER_FLUFF.get())) {
            if (!this.level().isClientSide) {
                unlockNextCoat(player, stack);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.is(ModItems.TRAINING_TREAT.get())) {
            if (!this.level().isClientSide) {
                if (isBaby()) {
                    accelerateBabyGrowth(player, stack);
                } else if (player.isSecondaryUseActive()) {
                    cycleTrainingTrick(player);
                } else {
                    trainSelectedTrick(player, stack, this.level().getGameTime());
                }
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (player.isSecondaryUseActive()
                && (stack.is(Items.CARROT) || stack.is(Items.POTATO)
                        || stack.is(Items.BEETROOT_SEEDS) || stack.getItem() instanceof BlockItem)
                && (player.getMainHandItem().is(ModItems.TRAINING_TREAT.get())
                        || player.getOffhandItem().is(ModItems.TRAINING_TREAT.get()))) {
            if (!this.level().isClientSide) {
                tryStartSeek(player, stack, this.level().getGameTime());
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.is(ModItems.GOOBY_WHISTLE.get())) {
            if (!this.level().isClientSide) {
                handleWhistle(player);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.getItem() instanceof DyeItem dye && isDyeableNeckAccessory(getNeckStack())) {
            if (!this.level().isClientSide) {
                tryDyeNeckAccessory(player, stack, dye);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (isNeckAccessory(stack)) {
            if (!this.level().isClientSide) {
                tryEquipAccessory(player, stack, GoobyWardrobe.Slot.NECK);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (isBackAccessory(stack)) {
            if (!this.level().isClientSide) {
                // Eine getragene Tasche wird per erneutem Tasche-Benutzen
                // GEOEFFNET; jedes andere Ruecken-Accessoire tauscht den Slot.
                if (stack.is(ModItems.TINY_SATCHEL.get()) && hasSatchel()) {
                    openSatchel(player);
                } else {
                    tryEquipAccessory(player, stack, GoobyWardrobe.Slot.BACK);
                }
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (isHatItem(stack)) {
            if (!this.level().isClientSide) {
                tryEquipAccessory(player, stack, GoobyWardrobe.Slot.HEAD);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.is(Items.SHEARS) && hasWardrobe()) {
            if (!this.level().isClientSide) {
                stripWardrobe(player);
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        if (stack.isEmpty() && hand == InteractionHand.MAIN_HAND) {
            // Pflegeitem in der ZWEITHAND? Dann die leere Haupthand durchreichen
            // (PASS), damit Vanilla die Zweithand-Interaktion ausfuehrt. Sonst
            // verschluckt das Streicheln z.B. das Nutella-Glas in der Offhand.
            if (isCareItem(player.getOffhandItem())) {
                return InteractionResult.PASS;
            }
            if (player.isSecondaryUseActive()) {
                if (!this.level().isClientSide) {
                    if (getFriendshipTier(player.getUUID()).canSnuggle()) {
                        trySnuggle(player);
                    } else {
                        tryMountOrSeat(player);
                    }
                }
                return InteractionResult.sidedSuccess(this.level().isClientSide);
            }
            if (!this.level().isClientSide) {
                handleBareHandInteraction(player, this.level().getGameTime());
            }
            return InteractionResult.sidedSuccess(this.level().isClientSide);
        }
        return super.mobInteract(player, hand);
    }

    /** Items mit eigener Gooby-Interaktion, die nie vom Bare-Hand-Pfad verdeckt werden duerfen. */
    public boolean isCareItem(ItemStack stack) {
        if (stack.isEmpty()) {
            return false;
        }
        return stack.is(ModItems.NUTELLA.get())
                || stack.is(ModItems.GOOBY_BRUSH.get())
                || stack.is(ModItems.SHIMMER_FLUFF.get())
                || stack.is(ModItems.TRAINING_TREAT.get())
                || stack.is(ModItems.GOOBY_WHISTLE.get())
                || isBackAccessory(stack)
                || isHatItem(stack)
                || isNeckAccessory(stack)
                || (stack.is(Items.SHEARS) && hasWardrobe())
                || (stack.getItem() instanceof DyeItem && isDyeableNeckAccessory(getNeckStack()));
    }

    /** Reiten/Create-Sitz: nur fuer gezaehmte Goobys, Reiter brauchen Freundschaft. */
    private void tryMountOrSeat(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_ride");
            return;
        }
        if (isOwnedBy(player) && CreateCompat.trySeatGooby(this)) {
            return;
        }
        if (!canRide(player)) {
            playSound(ModSounds.GOOBY_SQUEAK.get(), 0.6F, 0.8F);
            player.displayClientMessage(Component.translatable(
                    isTame() ? "msg.goobymod.ride_needs_friendship" : "msg.goobymod.not_tamed"), true);
            return;
        }
        // force=true: Vanilla blockiert Aufsitzen bei gedrueckter Shift-Taste
        // (Entity#canRide) — unsere Interaktion ERFORDERT aber Shift-Rechtsklick.
        if (player.startRiding(this, true)) {
            if (this.bubbleTicks == 0) {
                showBubble(GoobySpeech.pickFrom(GoobySpeech.RIDE, this.random));
            }
            if (!isHoldingNutella(player)) {
                // Ohne Nutella-Glas laesst sich Gooby nicht lenken — ohne diesen
                // Hinweis wirkt das Reiten wie ein Bug ("Gooby reagiert nicht").
                player.displayClientMessage(Component.translatable("msg.goobymod.ride_hint"), true);
            }
            if (player instanceof ServerPlayer serverPlayer) {
                GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.GOOBY_RIDE);
            }
        }
    }

    /** Reiten erfordert Zaehmung UND (Besitzer ODER freigeschaltete FRIEND-Stufe). */
    public boolean canRide(Player player) {
        return !isBaby() && isTame() && (isOwnedBy(player) || getFriendshipTier(player.getUUID()).canRide());
    }

    public boolean trySnuggle(Player player) {
        return trySnuggle(player, this.level().getGameTime());
    }

    /** Testbare Zeitvariante; Produktion verwendet immer die Server-GameTime. */
    public boolean trySnuggle(Player player, long gameTime) {
        FriendshipTier tier = getFriendshipTier(player.getUUID());
        if (!isTame() || !tier.canSnuggle()) {
            denyInteraction(player, "msg.goobymod.snuggle_locked");
            return false;
        }
        FriendshipMemory memory = getMemory(player.getUUID());
        if (!memory.canSnuggle(gameTime)) {
            denyInteraction(player, "msg.goobymod.snuggle_cooldown");
            return false;
        }
        memory.markSnuggle(gameTime);
        wakeUp();
        getNavigation().stop();
        getLookControl().setLookAt(player, 30.0F, 30.0F);
        tryTriggerAction("snuggle", 54);
        player.addEffect(new MobEffectInstance(MobEffects.REGENERATION, 200, 0));
        playSound(ModSounds.GOOBY_SNUGGLE_PURR_LONG.get(), 0.9F, 1.0F);
        showBubble(GoobySpeech.SNUGGLE);
        if (this.level() instanceof ServerLevel level) {
            level.sendParticles(ModParticles.HEART_GOLD.get(), getX(), getY() + 1.2, getZ(),
                    10, 0.45, 0.35, 0.45, 0.03);
        }
        if (player instanceof ServerPlayer serverPlayer) {
            GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.SNUGGLE_TIME);
        }
        return true;
    }

    public boolean cycleTrainingTrick(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_tricks");
            return false;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        this.selectedTrick = this.selectedTrick.next();
        player.displayClientMessage(Component.translatable("msg.goobymod.training_selected",
                Component.translatable(this.selectedTrick.translationKey()),
                proficiencyStars(getTrickProficiency(this.selectedTrick))), true);
        playSound(ModSounds.GOOBY_SQUEAK.get(), 0.5F, 1.2F);
        return true;
    }

    public boolean trainSelectedTrick(Player player, ItemStack treat, long gameTime) {
        if (isBaby()) {
            return accelerateBabyGrowth(player, treat);
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        if (this.lastTrainingTime != Long.MIN_VALUE
                && gameTime - this.lastTrainingTime < TRAINING_COOLDOWN_TICKS) {
            player.displayClientMessage(Component.translatable("msg.goobymod.training_cooldown"), true);
            return false;
        }
        int before = getTrickProficiency(this.selectedTrick);
        if (before >= MAX_TRICK_PROFICIENCY) {
            player.displayClientMessage(Component.translatable("msg.goobymod.training_already_mastered",
                    Component.translatable(this.selectedTrick.translationKey())), true);
            return false;
        }
        this.lastTrainingTime = gameTime;
        int after = before + 1;
        setTrickProficiency(this.selectedTrick, after);
        if (!player.getAbilities().instabuild) {
            treat.shrink(1);
        }
        wakeUp();
        getNavigation().stop();
        getLookControl().setLookAt(player, 30.0F, 30.0F);
        triggerPriorityAction("training_success", 24);
        playSound(ModSounds.GOOBY_TRICK_CHIME.get(), 0.85F, 1.0F + after * 0.06F);
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.HAPPY_VILLAGER, getX(), getY() + 1.2, getZ(),
                    5 + after * 2, 0.4, 0.35, 0.4, 0.03);
        }
        if (after == MAX_TRICK_PROFICIENCY) {
            player.displayClientMessage(Component.translatable("msg.goobymod.training_mastered",
                    Component.translatable(this.selectedTrick.translationKey())), true);
            if (player instanceof ServerPlayer serverPlayer) {
                GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.FIRST_TRICK);
                if (areAllTricksMastered()) {
                    GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.ALL_TRICKS_MASTERED);
                }
            }
        } else {
            player.displayClientMessage(Component.translatable("msg.goobymod.training_progress",
                    Component.translatable(this.selectedTrick.translationKey()),
                    after, MAX_TRICK_PROFICIENCY), true);
        }
        return true;
    }

    private void denyTraining(Player player) {
        player.displayClientMessage(Component.translatable(
                isTame() ? "msg.goobymod.training_not_owner" : "msg.goobymod.not_tamed"), true);
        playSound(ModSounds.GOOBY_WHISTLE_DENIED.get(), 0.7F, 1.0F);
    }

    /**
     * Einheitliches Ablehnungs-Feedback: JEDE verweigerte Interaktion ist
     * hoerbar (sanfter Squeak), nicht nur lesbar. Stumme Denials fuehlen sich
     * wie verschluckte Klicks an.
     */
    private void denyInteraction(Player player, Component message) {
        player.displayClientMessage(message, true);
        playSound(ModSounds.GOOBY_SQUEAK.get(), 0.55F, 0.75F);
    }

    private void denyInteraction(Player player, String translationKey) {
        denyInteraction(player, Component.translatable(translationKey));
    }

    private void denyBabyAction(Player player, String translationKey) {
        player.displayClientMessage(Component.translatable(translationKey), true);
        showBubble(GoobySpeech.pickFrom(GoobySpeech.BABY, this.random));
        playSound(ModSounds.GOOBY_BABY_SQUEAK.get(), 0.65F, 1.0F);
    }

    public boolean accelerateBabyGrowth(Player player, ItemStack treat) {
        if (!isBaby()) {
            return false;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        setAge(Math.min(0, getAge() + BABY_TREAT_GROWTH_TICKS));
        if (!player.getAbilities().instabuild) {
            treat.shrink(1);
        }
        if (this.level() instanceof ServerLevel level) {
            level.sendParticles(ParticleTypes.HAPPY_VILLAGER, getX(), getY() + 0.7, getZ(),
                    8, 0.35, 0.3, 0.35, 0.03);
        }
        player.displayClientMessage(Component.translatable("msg.goobymod.baby_growth_boost"), true);
        playSound(ModSounds.GOOBY_BABY_SQUEAK.get(), 0.7F, 1.08F);
        return true;
    }

    public boolean handleBareHandInteraction(Player player, long gameTime) {
        Long previous = this.lastBareHandInteraction.put(player.getUUID(), gameTime);
        trimOldest(this.lastBareHandInteraction, MAX_TRANSIENT_PLAYER_ENTRIES);
        // Doppelklick wird NUR zum Kunststueck-Wunsch, wenn der Trick auch wirklich
        // laufen kann. Sonst wuerde Klickspam-Streicheln (der Normalfall!) jeden
        // zweiten Klick in eine Absage-Nachricht samt Verweigerungs-Sound verwandeln.
        if (previous != null && gameTime - previous <= TRICK_DOUBLE_CLICK_TICKS
                && canPerformSelectedTrickFor(player)) {
            this.lastBareHandInteraction.remove(player.getUUID());
            return requestSelectedTrick(player);
        }
        pet(player);
        return false;
    }

    /** True only when a bare-hand double click would actually perform the trick. */
    public boolean canPerformSelectedTrickFor(Player player) {
        return !isBaby() && isOwnedBy(player) && getTrickProficiency(this.selectedTrick) > 0;
    }

    public boolean requestSelectedTrick(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_tricks");
            return false;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        if (getTrickProficiency(this.selectedTrick) == 0) {
            player.displayClientMessage(Component.translatable("msg.goobymod.trick_untrained",
                    Component.translatable(this.selectedTrick.translationKey())), true);
            playSound(ModSounds.GOOBY_WHISTLE_DENIED.get(), 0.65F, 1.0F);
            return false;
        }
        wakeUp();
        getNavigation().stop();
        getLookControl().setLookAt(player, 30.0F, 30.0F);
        triggerPriorityAction(this.selectedTrick.animation(), this.selectedTrick.durationTicks());
        this.performedTrickCount++;
        // Konfetti erst zum ENDE des Clips (vollendeter Trick) — und pro
        // Cooldown-Fenster hoechstens eine Salve (Doppelklick-Spam bleibt still).
        long now = this.level().getGameTime();
        if (now >= this.trickConfettiCooldownUntil) {
            this.trickConfettiCooldownUntil = now + CONFETTI_TRICK_COOLDOWN_TICKS;
            this.trickConfettiIn = this.selectedTrick.durationTicks();
        }
        playTrickPerformFeedback(this.selectedTrick);
        player.displayClientMessage(Component.translatable("msg.goobymod.trick_performed",
                getName(), Component.translatable(this.selectedTrick.translationKey())), true);
        return true;
    }

    /** Hoer- UND sichtbares Vorfuehr-Feedback pro Kunststueck — nur vorhandene Sounds/Partikel. */
    private void playTrickPerformFeedback(GoobyTrick trick) {
        switch (trick) {
            case SPEAK -> {
                showBubble(GoobySpeech.pickFrom(GoobySpeech.GENERAL, this.random));
                SoundEvent ambient = getAmbientSound();
                if (ambient != null) {
                    playSound(ambient, 0.75F, 1.05F);
                }
            }
            case FLOP -> playSound(ModSounds.GOOBY_FLOP_THUD.get(), 0.75F, 1.0F);
            case ROLL -> playSound(ModSounds.GOOBY_BOING.get(), 0.75F, 1.05F);
            case DANCE -> playSound(ModSounds.GOOBY_CHIRP_SOCIAL.get(), 0.8F, 1.1F);
            // SPIN und HIGH_FIVE waren komplett stumm — jede Interaktion klingt.
            case SPIN, HIGH_FIVE -> playSound(ModSounds.GOOBY_SQUEAK.get(), 0.7F, 1.2F);
        }
        if (this.level() instanceof ServerLevel serverLevel) {
            switch (trick) {
                case ROLL -> serverLevel.sendParticles(ParticleTypes.CLOUD,
                        getX(), getY() + 0.25, getZ(), 8, 0.45, 0.1, 0.45, 0.02);
                case DANCE -> spawnMusicNotes(serverLevel, MUSIC_NOTE_DANCE_COUNT);
                case SPEAK -> spawnMusicNotes(serverLevel, MUSIC_NOTE_SPEAK_COUNT);
                default -> serverLevel.sendParticles(ParticleTypes.HAPPY_VILLAGER,
                        getX(), getY() + 1.1, getZ(), 5, 0.4, 0.35, 0.4, 0.03);
            }
        }
    }

    // ------------------------------------------------------------------
    // Feedback-Wave: gebuendelte Low-Count-Spawns (Radius <= 0.6, feste
    // Budgets). sendParticles liefert nur an Spieler in Sichtweite aus —
    // Multiplayer-/Dedicated-sicher, kein Client-Code auf dem Server.
    // ------------------------------------------------------------------

    private void spawnConfettiBurst(ServerLevel level, int count) {
        this.confettiBursts++;
        level.sendParticles(ModParticles.CONFETTI.get(),
                getX(), getY() + 1.4, getZ(), count, 0.45, 0.25, 0.45, 0.11);
    }

    private void spawnFluffPuffs(ServerLevel level, int count, double y) {
        this.fluffPuffBursts++;
        level.sendParticles(ModParticles.FLUFF_PUFF.get(),
                getX(), y, getZ(), count, 0.4, 0.2, 0.4, 0.02);
    }

    private void spawnMusicNotes(ServerLevel level, int count) {
        this.musicNoteBursts++;
        level.sendParticles(ModParticles.MUSIC_NOTE.get(),
                getX(), getY() + 1.35, getZ(), count, 0.45, 0.3, 0.45, 0.05);
    }

    public boolean selectTrick(Player player, GoobyTrick trick) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_tricks");
            return false;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        this.selectedTrick = trick;
        player.displayClientMessage(Component.translatable("msg.goobymod.trick_selected",
                Component.translatable(trick.translationKey()),
                proficiencyStars(getTrickProficiency(trick))), true);
        playSound(ModSounds.GOOBY_SQUEAK.get(), 0.5F, 1.2F);
        return true;
    }

    /**
     * Whistle 3.0: oeffnet den nativen Trick-Selection-Screen. Validiert
     * Erwachsenenstatus, Besitz und Distanz serverseitig und schickt dann die
     * gebundeten S2C-Menuedaten; Clients ohne den Mod-Kanal erhalten ueber
     * {@link GoobyNetwork#sendTrickMenu} das alte Chat-Menue als Fallback.
     */
    public boolean openTrickMenu(ServerPlayer player) {
        if (!isAlive()) {
            // Gleiche Invariante wie GoobyNetwork.trySelectTrick: tote oder
            // bereits entfernte Goobys oeffnen kein Menue. Feedback nur an
            // den Sender — die sterbende Entity soll nicht noch quietschen.
            player.displayClientMessage(
                    Component.translatable("msg.goobymod.trick_menu_invalid"), true);
            player.playNotifySound(ModSounds.GOOBY_WHISTLE_DENIED.get(),
                    SoundSource.PLAYERS, 0.6F, 1.0F);
            return false;
        }
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_tricks");
            return false;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        if (player.distanceToSqr(this) > GoobyNetwork.TRICK_MENU_RANGE * GoobyNetwork.TRICK_MENU_RANGE) {
            denyInteraction(player, Component.translatable("msg.goobymod.trick_menu_too_far", getName()));
            return false;
        }
        GoobyNetwork.sendTrickMenu(player, this);
        return true;
    }

    /** Legacy-Chat-Menue — Fallback fuer Clients ohne Payload-Kanal und Addon-Kompatibilitaet. */
    public void sendTrickMenu(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_tricks");
            return;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return;
        }
        player.sendSystemMessage(Component.translatable("msg.goobymod.trick_menu", getName())
                .withStyle(ChatFormatting.GOLD));
        for (GoobyTrick trick : GoobyTrick.values()) {
            player.sendSystemMessage(buildTrickMenuLine(trick));
        }
    }

    /**
     * Eine Zeile des Chat-Menues. Gleiche Policy wie der native Screen und
     * {@code GoobyNetwork.trySelectTrick}: nur trainierte Kunststuecke sind
     * klickbar; gesperrte tragen statt des Click-Events den Trainings-Hinweis
     * (trainiert wird per Sneak + Trainingshappen). Oeffentlich fuer GameTests.
     */
    public Component buildTrickMenuLine(GoobyTrick trick) {
        int stars = getTrickProficiency(trick);
        var line = Component.literal("  ")
                .append(Component.translatable(trick.translationKey()))
                .append(Component.literal(" " + proficiencyStars(stars)));
        if (stars == 0) {
            return line.append(Component.literal(" — "))
                    .append(Component.translatable("screen.goobymod.trick_select.state.locked"))
                    .withStyle(ChatFormatting.DARK_GRAY);
        }
        String command = "/goobytrick " + getUUID() + " " + trick.serializedName();
        return line.withStyle(style -> style.withColor(trick == this.selectedTrick
                        ? ChatFormatting.GREEN : ChatFormatting.AQUA)
                .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, command)));
    }

    /** Returns true when the long-range call used a safe teleport. */
    public boolean callToOwner(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_follows_parents");
            return false;
        }
        if (!isOwnedBy(player)) {
            denyTraining(player);
            return false;
        }
        if (CreateCompat.isOnMovingContraption(this)) {
            showBubble(GoobySpeech.CONTRAPTION_REFUSAL);
            player.displayClientMessage(Component.translatable("msg.goobymod.whistle_on_train", getName()), true);
            playSound(ModSounds.GOOBY_WHISTLE_DENIED.get(), 0.7F, 1.0F);
            return false;
        }
        wakeUp();
        setCommandMode(GoobyCommand.FOLLOW);
        boolean teleported = distanceToSqr(player) > 32.0 * 32.0
                && trySafeFollowTeleportAround(player.blockPosition());
        if (!teleported) {
            getNavigation().moveTo(player, 1.25);
        }
        playSound(ModSounds.GOOBY_WHISTLE_FOLLOW.get(), 0.8F, 1.0F);
        showBubble(GoobySpeech.COMMAND_FOLLOW);
        player.displayClientMessage(Component.translatable(teleported
                ? "msg.goobymod.whistle_called_teleport" : "msg.goobymod.whistle_called",
                getName()), true);
        return teleported;
    }

    /** Pfeife: NUR der Besitzer schaltet Wander → Follow → Stay durch. */
    public void handleWhistle(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_follows_parents");
            return;
        }
        if (!isTame()) {
            player.displayClientMessage(Component.translatable("msg.goobymod.not_tamed"), true);
            playSound(ModSounds.GOOBY_WHISTLE_DENIED.get(), 0.7F, 1.0F);
            return;
        }
        if (!isOwnedBy(player)) {
            player.displayClientMessage(Component.translatable("msg.goobymod.not_owner"), true);
            playSound(ModSounds.GOOBY_WHISTLE_DENIED.get(), 0.7F, 1.0F);
            return;
        }
        GoobyCommand next = getCommandMode().next();
        setCommandMode(next);
        ItemStack whistle = player.getMainHandItem().is(ModItems.GOOBY_WHISTLE.get())
                ? player.getMainHandItem() : player.getOffhandItem();
        if (whistle.is(ModItems.GOOBY_WHISTLE.get())) {
            GoobyWhistleItem.rememberMode(whistle, next);
        }
        Component icon = Component.literal(next.icon()).withStyle(style -> style.withFont(ICON_FONT));
        player.displayClientMessage(Component.translatable("msg.goobymod.command_status",
                icon, getName(), Component.translatable(next.nameTranslationKey())), true);
        playSound(switch (next) {
            case WANDER -> ModSounds.GOOBY_WHISTLE_WANDER.get();
            case FOLLOW -> ModSounds.GOOBY_WHISTLE_FOLLOW.get();
            case STAY -> ModSounds.GOOBY_WHISTLE_STAY.get();
        }, 0.8F, 1.0F);
        if (this.bubbleTicks == 0) {
            showBubble(switch (next) {
                case WANDER -> GoobySpeech.COMMAND_WANDER;
                case FOLLOW -> GoobySpeech.COMMAND_FOLLOW;
                case STAY -> GoobySpeech.COMMAND_STAY;
            });
        }
        if (player instanceof ServerPlayer serverPlayer) {
            GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.WHISTLE_COMMAND);
        }
    }

    public void reactToName(ServerPlayer owner) {
        if (!isOwnedBy(owner)) {
            return;
        }
        this.nameReactionCount++;
        wakeUp();
        getLookControl().setLookAt(owner, 45.0F, 40.0F);
        tryTriggerAction("ears_perk", 18);
        if (this.bubbleTicks == 0) {
            List<String> pool = switch (getFriendshipTier(owner.getUUID())) {
                case STRANGER -> GoobySpeech.GREET;
                case BUDDY -> GoobySpeech.GREET_BUDDY;
                case FRIEND -> GoobySpeech.GREET_FRIEND;
                case BEST_FRIEND -> GoobySpeech.GREET_BEST_FRIEND;
            };
            showBubble(GoobySpeech.pickFrom(pool, this.random));
        }
    }

    /** STREICHELN! Herzchen, Quietschen, Zufriedenheit + Freundschaft — Goobys Lebenssinn. */
    public void pet(Player player) {
        boolean lonely = getMood() == GoobyMood.LONELY;
        getMemory(player.getUUID()).rememberFirstPet(this.level().getGameTime());
        wakeUp();
        addSatisfaction(lonely ? PET_SATISFACTION * 2 : PET_SATISFACTION);
        gainFriendship(player, PET_FRIENDSHIP, true);
        this.wantsPet = false;
        this.petRequestIn = newPetRequestDelay(this.random);
        if (tryTriggerAction("pet", 34)) {
            this.entityData.set(DATA_ACTIVE_PETTER, player.getUUID().toString());
            this.activePetterTicks = 34;
        }
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.HEART,
                    getX(), getY() + 1.3, getZ(), 5, 0.45, 0.3, 0.45, 0.02);
            // Schnurr-Kontext: zufriedene Noten, aber hoechstens alle 2 s.
            long now = serverLevel.getGameTime();
            if (now >= this.petNoteCooldownUntil) {
                this.petNoteCooldownUntil = now + MUSIC_NOTE_PET_COOLDOWN_TICKS;
                spawnMusicNotes(serverLevel, MUSIC_NOTE_PET_COUNT);
            }
        }
        playSound(this.random.nextBoolean() ? ModSounds.GOOBY_SQUEAK.get() : ModSounds.GOOBY_PURR.get(),
                0.9F, 0.95F + this.random.nextFloat() * 0.15F);
        if (this.bubbleTicks == 0 && this.random.nextFloat() < 0.45F) {
            showBubble(GoobySpeech.pickReaction(GoobySpeech.PET, player, this.random));
        }
    }

    /**
     * Nutella fuettern: zaehmt wilde Goobys (echter Besitz!), gibt Freundschaft
     * und laedt eine Geschenk-Ladung auf (die Kosten des Geschenk-Systems).
     */
    public void eatNutella(Player player, ItemStack stack) {
        boolean hungry = getMood() == GoobyMood.HUNGRY;
        this.fedOnce = true;
        this.entityData.set(DATA_SHY, false);
        getMemory(player.getUUID()).rememberFirstFeed(this.level().getGameTime());
        wakeUp();
        tryTriggerAction("eat", 44);
        addSatisfaction(NUTELLA_SATISFACTION);
        playSound(ModSounds.GOOBY_MUNCH.get(), 1.0F, 1.0F);
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.HEART, getX(), getY() + 1.3, getZ(), 3, 0.4, 0.3, 0.4, 0.02);
        }
        if (!player.getAbilities().instabuild) {
            stack.shrink(1);
        }
        boolean justTamed = false;
        if (!isTame()) {
            tame(player);
            setCommandMode(GoobyCommand.WANDER);
            spawnTamingParticles(true);
            showBubble(GoobySpeech.TAMED);
            justTamed = true;
        }
        this.lastFedTime = this.level().getGameTime();
        gainFriendship(player, FEED_FRIENDSHIP + (hungry ? 2 : 0), false);
        setGiftCharges(this.giftCharges + 1);
        if (!justTamed && this.bubbleTicks == 0) {
            showBubble(GoobySpeech.pickReaction(GoobySpeech.EAT, player, this.random));
        }
    }

    private void brush(Player player, ItemStack stack, InteractionHand hand) {
        if (this.brushCooldown > 0) {
            // Niemals den Klick stumm schlucken: Restzeit anzeigen + Wohlfuehl-Squeak.
            player.displayClientMessage(Component.translatable("msg.goobymod.brush_cooldown",
                    (this.brushCooldown + 19) / 20), true);
            playSound(ModSounds.GOOBY_SQUEAK.get(), 0.5F, 1.3F);
            tryTriggerAction("nose_wiggle_ack", 8);
            return;
        }
        this.brushCooldown = 400;
        wakeUp();
        spawnAtLocation(createBrushDrop(player, this.random), 0.6F);
        tryTriggerAction("pet", 34);
        addSatisfaction(8);
        playSound(ModSounds.GOOBY_BRUSH.get(), 0.75F, 1.0F);
        if (this.level() instanceof ServerLevel serverLevel) {
            // Fellfussel statt generischer Wolke — der 20-s-brushCooldown
            // oben ist zugleich das Anti-Spam-Gate fuer diesen Burst.
            spawnFluffPuffs(serverLevel, FLUFF_BRUSH_COUNT, getY() + 0.9);
        }
        stack.hurtAndBreak(1, player, hand == InteractionHand.MAIN_HAND
                ? net.minecraft.world.entity.EquipmentSlot.MAINHAND
                : net.minecraft.world.entity.EquipmentSlot.OFFHAND);
    }

    /** Seedable brush reward used by both gameplay and the 5% shimmer regression test. */
    public ItemStack createBrushDrop(Player player, RandomSource random) {
        if (getFriendshipTier(player.getUUID()) == FriendshipTier.BEST_FRIEND
                && random.nextFloat() < 0.05F) {
            return new ItemStack(ModItems.SHIMMER_FLUFF.get());
        }
        return new ItemStack(ModItems.GOOBY_FLUFF.get(), 1 + random.nextInt(2));
    }

    /** Aufwecken unterbricht den Schlaf ECHT: 30s Wiedereinschlaf-Sperre. */
    public void wakeUp() {
        if (isGoobySleeping()) {
            setGoobySleeping(false);
        }
        this.sleepSuppressedTicks = SLEEP_SUPPRESS_TICKS;
        if (this.entityData.get(DATA_SITTING)) {
            setSitting(false);
        }
    }

    /** Starts the dawn vignette after the sleep goal has placed Gooby at the door. */
    public void beginHutchWakeRoutine(Direction facing) {
        this.hutchWakeRoutineTicks = 52;
        setDeltaMovement(facing.getStepX() * 0.10, 0.24, facing.getStepZ() * 0.10);
        triggerPriorityAction("hutch_exit", 16);
        playSound(ModSounds.GOOBY_HUTCH_RUSTLE.get(), 0.7F, 1.08F);
    }

    private void tickHutchWakeRoutine() {
        if (this.hutchWakeRoutineTicks <= 0) {
            return;
        }
        if (this.hutchWakeRoutineTicks == 36) {
            // The existing recently-woke micro controller owns stretch_yawn.
            markJustWoke();
        } else if (this.hutchWakeRoutineTicks == 6) {
            playSound(ModSounds.GOOBY_AMBIENT_HAPPY.get(), 0.8F, 1.12F);
            showBubble(GoobySpeech.WAKE);
            LivingEntity owner = getOwner();
            if (owner != null && owner.isAlive() && distanceToSqr(owner) > 4.0) {
                getNavigation().moveTo(owner, 1.05);
            }
        }
        this.hutchWakeRoutineTicks--;
    }

    /** Called before the occupied hutch block entity disappears. */
    public void ejectFromBrokenHutch(BlockPos hutchPos, Direction facing) {
        setGoobySleeping(false);
        setInHutch(false);
        this.hutchWakeRoutineTicks = 0;
        setHomePos(null);
        getNavigation().stop();

        Vec3 exit = RabbitHutchBlock.exitAnchor(hutchPos, facing);
        if (!this.level().noCollision(this, getBoundingBox().move(exit.subtract(position())))) {
            exit = Vec3.atBottomCenterOf(hutchPos.above());
        }
        setPos(exit.x, exit.y, exit.z);
        setDeltaMovement(Vec3.ZERO);
        setMood(GoobyMood.LONELY);
        this.sadTicks = 100;
        this.entityData.set(DATA_SAD, true);
        showBubble("bubble.goobymod.hutch_broken");
        playSound(ModSounds.GOOBY_SAD_WHIMPER.get(), 0.8F, 0.9F);
    }

    // ------------------------------------------------------------------
    // Garderobe (drei synchronisierte Slots + permanente Fellvarianten)
    // ------------------------------------------------------------------

    public static boolean isHatItem(ItemStack stack) {
        return !stack.isEmpty() && stack.is(ModItemTags.GOOBY_HATS);
    }

    public static boolean isNeckAccessory(ItemStack stack) {
        return stack.is(ModItems.GOOBY_SCARF.get()) || stack.is(ModItems.GOOBY_BOWTIE.get())
                || stack.is(ModItems.ADVENTURE_BANDANA.get());
    }

    public static boolean isBackAccessory(ItemStack stack) {
        return stack.is(ModItems.TINY_SATCHEL.get()) || stack.is(ModItems.PICNIC_BACKPACK.get());
    }

    /** Am Gooby direkt umfaerbbare Hals-Accessoires (Schal und Abenteuer-Halstuch). */
    public static boolean isDyeableNeckAccessory(ItemStack stack) {
        return stack.is(ModItems.GOOBY_SCARF.get()) || stack.is(ModItems.ADVENTURE_BANDANA.get());
    }

    /** Vollstaendige Slot↔Item-Validierung des serverautoritativen Equip-Pfads. */
    public static boolean isAccessoryForSlot(GoobyWardrobe.Slot slot, ItemStack stack) {
        return switch (slot) {
            case HEAD -> isHatItem(stack);
            case NECK -> isNeckAccessory(stack);
            case BACK -> isBackAccessory(stack);
        };
    }

    public boolean hasHat() {
        return !getHatItemId().isEmpty();
    }

    public boolean hasWardrobe() {
        return hasHat() || !getNeckAccessoryData().isEmpty() || !getBackAccessoryData().isEmpty();
    }

    public boolean hasSatchel() {
        return getBackStack().is(ModItems.TINY_SATCHEL.get());
    }

    public SimpleContainer satchelInventory() {
        return this.satchelInventory;
    }

    public boolean canUseSatchel(Player player) {
        return hasSatchel() && isOwnedBy(player);
    }

    private void openSatchel(Player player) {
        if (!canUseSatchel(player)) {
            denyInteraction(player, "msg.goobymod.satchel_owner_only");
            return;
        }
        if (player instanceof ServerPlayer serverPlayer) {
            serverPlayer.openMenu(this, buffer -> buffer.writeVarInt(getId()));
        }
    }

    @Nullable
    @Override
    public AbstractContainerMenu createMenu(int containerId, Inventory inventory, Player player) {
        return canUseSatchel(player) ? new GoobySatchelMenu(containerId, inventory, this) : null;
    }

    /**
     * Atomic insertion helper used by gift stashing and tests. The caller owns
     * the returned remainder and only spends its charge after this method.
     */
    public ItemStack insertIntoSatchel(ItemStack stack) {
        ItemStack remainder = stack.copy();
        for (int slot = 0; slot < SATCHEL_SIZE && !remainder.isEmpty(); slot++) {
            ItemStack existing = this.satchelInventory.getItem(slot);
            if (!existing.isEmpty() && !ItemStack.isSameItemSameComponents(existing, remainder)) {
                continue;
            }
            int limit = Math.min(this.satchelInventory.getMaxStackSize(), remainder.getMaxStackSize());
            int accepted = existing.isEmpty()
                    ? Math.min(limit, remainder.getCount())
                    : Math.min(limit - existing.getCount(), remainder.getCount());
            if (accepted <= 0) {
                continue;
            }
            if (existing.isEmpty()) {
                this.satchelInventory.setItem(slot, remainder.copyWithCount(accepted));
            } else {
                existing.grow(accepted);
                this.satchelInventory.setChanged();
            }
            remainder = accepted == remainder.getCount()
                    ? ItemStack.EMPTY : remainder.copyWithCount(remainder.getCount() - accepted);
        }
        return remainder;
    }

    public boolean isSatchelFull() {
        for (int slot = 0; slot < SATCHEL_SIZE; slot++) {
            if (this.satchelInventory.getItem(slot).isEmpty()) {
                return false;
            }
        }
        return true;
    }

    public String getHatItemId() {
        return this.entityData.get(DATA_HAT);
    }

    public void setHatItemId(String itemId) {
        setSynced(DATA_HAT, boundedSyncString(itemId, GoobyWardrobe.MAX_SYNCED_KEY_LENGTH));
        this.wardrobe.reconcile(GoobyWardrobe.Slot.HEAD, getHatItemId());
    }

    public String getNeckAccessoryData() {
        return this.entityData.get(DATA_NECK);
    }

    public void setNeckAccessoryData(String encodedStack) {
        setSynced(DATA_NECK, boundedSyncString(encodedStack, GoobyWardrobe.MAX_SYNCED_KEY_LENGTH));
        this.wardrobe.reconcile(GoobyWardrobe.Slot.NECK, getNeckAccessoryData());
    }

    public String getBackAccessoryData() {
        return this.entityData.get(DATA_BACK);
    }

    public void setBackAccessoryData(String encodedStack) {
        setSynced(DATA_BACK, boundedSyncString(encodedStack, GoobyWardrobe.MAX_SYNCED_KEY_LENGTH));
        this.wardrobe.reconcile(GoobyWardrobe.Slot.BACK, getBackAccessoryData());
    }

    /**
     * Leitet den Sync-String nach {@code wardrobe.load} aus dem vollen Stack
     * ab — aber nur, wenn das gefahrlos moeglich ist. Ein leerer Slot (Item
     * aus deinstalliertem Fremd-Mod, NBT-Parse fehlgeschlagen) behaelt den
     * Legacy-Wire-String, damit die Item-Id Roundtrips uebersteht. Ein
     * Encode ueber der Sync-Grenze wuerde von {@code boundedSyncString}
     * gekappt und der volle Stack anschliessend von {@code reconcile}
     * vernichtet — auch dann bleibt der bestehende Wire-String stehen.
     */
    private void syncWireFromWardrobe(GoobyWardrobe.Slot slot) {
        ItemStack full = this.wardrobe.get(slot);
        if (full.isEmpty()) {
            return;
        }
        String encoded = GoobyWardrobe.encode(full);
        if (encoded.length() > GoobyWardrobe.MAX_SYNCED_KEY_LENGTH) {
            return;
        }
        switch (slot) {
            case HEAD -> setHatItemId(encoded);
            case NECK -> setNeckAccessoryData(encoded);
            case BACK -> setBackAccessoryData(encoded);
        }
    }

    /**
     * Synchronized head slot as an ItemStack. On the server a defensive copy
     * of the authoritative full stack (custom name, enchantments, components)
     * is returned — callers can never mutate the wardrobe past the sync; the
     * client falls back to decoding the synced wire string (render cache).
     */
    public ItemStack getHatStack() {
        String id = getHatItemId();
        if (id.isEmpty()) {
            return ItemStack.EMPTY;
        }
        ItemStack full = this.wardrobe.get(GoobyWardrobe.Slot.HEAD);
        if (!full.isEmpty()) {
            return full.copy();
        }
        if (!id.equals(this.cachedHatId)) {
            this.cachedHatId = id;
            ResourceLocation location = ResourceLocation.tryParse(id);
            this.cachedHatStack = location == null ? ItemStack.EMPTY
                    : BuiltInRegistries.ITEM.getOptional(location).map(ItemStack::new).orElse(ItemStack.EMPTY);
        }
        return this.cachedHatStack;
    }

    public ItemStack getNeckStack() {
        String encoded = getNeckAccessoryData();
        if (encoded.isEmpty()) {
            return ItemStack.EMPTY;
        }
        ItemStack full = this.wardrobe.get(GoobyWardrobe.Slot.NECK);
        if (!full.isEmpty()) {
            return full.copy();
        }
        if (!encoded.equals(this.cachedNeckId)) {
            this.cachedNeckId = encoded;
            this.cachedNeckStack = GoobyWardrobe.decode(encoded);
        }
        return this.cachedNeckStack;
    }

    public ItemStack getBackStack() {
        String encoded = getBackAccessoryData();
        if (encoded.isEmpty()) {
            return ItemStack.EMPTY;
        }
        ItemStack full = this.wardrobe.get(GoobyWardrobe.Slot.BACK);
        if (!full.isEmpty()) {
            return full.copy();
        }
        if (!encoded.equals(this.cachedBackId)) {
            this.cachedBackId = encoded;
            this.cachedBackStack = GoobyWardrobe.decode(encoded);
        }
        return this.cachedBackStack;
    }

    /**
     * Serverautoritativer Equip-Pfad fuer alle drei Garderoben-Slots — die
     * EINE Wahrheit fuer {@code mobInteract} UND
     * {@link de.sonic0810.goobymod.event.ExplorerOutfitEvents}. Validiert
     * Slot↔Item fail-closed, prueft Baby/Zaehmung/Besitzer und die
     * Sync-Grenze, uebernimmt den vollen Stack (Custom Name, Verzauberungen,
     * beliebige DataComponents) in die Garderobe, droppt das verdraengte
     * Accessoire (eine getragene Tasche gibt vorher ihren Inhalt zurueck)
     * und verbraucht das Item ausserhalb des Kreativmodus.
     *
     * @return {@code true} nur, wenn das Accessoire tatsaechlich angelegt
     *         wurde; abgelehnte Versuche konsumieren nichts.
     */
    public boolean tryEquipAccessory(Player player, ItemStack stack, GoobyWardrobe.Slot slot) {
        if (this.level().isClientSide) {
            return false;
        }
        if (!isAccessoryForSlot(slot, stack)) {
            // Slot↔Item-Mismatch (nur per API-Fehlgebrauch erreichbar):
            // fail-closed ohne Konsum, ohne Slot-Aenderung, ohne Feedback.
            return false;
        }
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_accessory");
            return false;
        }
        if (!isTame()) {
            denyInteraction(player, "msg.goobymod.not_tamed");
            return false;
        }
        if (!isOwnedBy(player)) {
            denyInteraction(player, "msg.goobymod.not_owner");
            return false;
        }
        // Der volle Stack (inkl. Custom Name/Verzauberungen/Components) wird
        // serverseitig behalten; der Sync-String traegt nur Id + Farbe.
        ItemStack equipped = stack.copyWithCount(1);
        String encoded = GoobyWardrobe.encode(equipped);
        if (encoded.length() > GoobyWardrobe.MAX_SYNCED_KEY_LENGTH) {
            // Fail-closed VOR dem Ausziehen des alten Accessoires: eine Id
            // ueber der Sync-Grenze wuerde beim Reload durch Truncation +
            // reconcile vernichtet. Item bleibt beim Spieler.
            denyInteraction(player, "msg.goobymod.accessory_id_too_long");
            return false;
        }
        dropWardrobeSlot(slot);
        switch (slot) {
            case HEAD -> setHatItemId(encoded);
            case NECK -> setNeckAccessoryData(encoded);
            case BACK -> setBackAccessoryData(encoded);
        }
        this.wardrobe.set(slot, equipped);
        if (!player.getAbilities().instabuild) {
            stack.shrink(1);
        }
        playSound(ModSounds.GOOBY_DRESS_UP.get(), 0.75F, 1.0F);
        player.displayClientMessage(Component.translatable(
                "msg.goobymod.accessory_equipped", getName(), equipped.getHoverName()), true);
        if (this.level() instanceof ServerLevel serverLevel) {
            // Beim Anziehen wirbelt das Fell: Fussel statt Villager-Funken.
            spawnFluffPuffs(serverLevel, FLUFF_DRESS_UP_COUNT, getY() + 1.2);
        }
        if (slot == GoobyWardrobe.Slot.HEAD && player instanceof ServerPlayer serverPlayer) {
            GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.HAT_FASHION);
        }
        if (hasHat() && !getNeckAccessoryData().isEmpty() && !getBackAccessoryData().isEmpty()
                && player instanceof ServerPlayer serverPlayer) {
            GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.FULL_OUTFIT);
        }
        return true;
    }

    /**
     * Faerbt das GETRAGENE Hals-Accessoire (Schal oder Abenteuer-Halstuch)
     * direkt am Gooby — serverautoritativ, ohne NBT-Reload. Crafting-Faerben
     * laeuft weiterhin ueber den Vanilla-{@code minecraft:dyeable}-Tag.
     *
     * @return {@code true} nur, wenn tatsaechlich gefaerbt wurde; abgelehnte
     *         Versuche konsumieren keinen Farbstoff.
     */
    public boolean tryDyeNeckAccessory(Player player, ItemStack dyeStack, DyeItem dye) {
        if (this.level().isClientSide) {
            return false;
        }
        ItemStack worn = getNeckStack();
        if (!isDyeableNeckAccessory(worn)) {
            return false;
        }
        if (!isOwnedBy(player)) {
            denyInteraction(player, "msg.goobymod.not_owner");
            return false;
        }
        ItemStack dyed = worn.copy();
        int color = dye.getDyeColor().getTextureDiffuseColor() & 0xFFFFFF;
        dyed.set(DataComponents.DYED_COLOR, new DyedItemColor(color, true));
        String encoded = GoobyWardrobe.encode(dyed);
        if (encoded.length() > GoobyWardrobe.MAX_SYNCED_KEY_LENGTH) {
            // Der #rrggbb-Suffix darf ein Accessoire an der Sync-Grenze nicht
            // in die reload-vernichtende Truncation schieben.
            denyInteraction(player, "msg.goobymod.accessory_id_too_long");
            return false;
        }
        setNeckAccessoryData(encoded);
        this.wardrobe.set(GoobyWardrobe.Slot.NECK, dyed);
        if (!player.getAbilities().instabuild) {
            dyeStack.shrink(1);
        }
        playSound(ModSounds.GOOBY_DRESS_UP.get(), 0.7F, 1.08F);
        sendWardrobeParticles(color, 12);
        player.displayClientMessage(Component.translatable(
                dyed.is(ModItems.ADVENTURE_BANDANA.get())
                        ? "msg.goobymod.bandana_dyed" : "msg.goobymod.scarf_dyed",
                getName(), Component.translatable("color.minecraft." + dye.getDyeColor().getName())), true);
        return true;
    }

    private void stripWardrobe(Player player) {
        if (!isOwnedBy(player)) {
            denyInteraction(player, "msg.goobymod.not_owner");
            return;
        }
        var removed = Component.empty();
        boolean first = true;
        for (ItemStack accessory : List.of(getHatStack(), getNeckStack(), getBackStack())) {
            if (accessory.isEmpty()) {
                continue;
            }
            if (!first) {
                removed.append(Component.literal(", "));
            }
            removed.append(accessory.getHoverName());
            first = false;
        }
        dropWardrobe();
        player.displayClientMessage(Component.translatable(
                "msg.goobymod.wardrobe_removed", getName(), removed), true);
        playSound(net.minecraft.sounds.SoundEvents.SHEEP_SHEAR, 0.7F, 1.2F);
    }

    private void dropWardrobeSlot(GoobyWardrobe.Slot slot) {
        ItemStack current = switch (slot) {
            case HEAD -> getHatStack();
            case NECK -> getNeckStack();
            case BACK -> getBackStack();
        };
        if (slot == GoobyWardrobe.Slot.BACK && current.is(ModItems.TINY_SATCHEL.get())) {
            dropSatchelContents();
        }
        if (!current.isEmpty()) {
            spawnAtLocation(current.copy(), 1.2F);
        }
        switch (slot) {
            case HEAD -> setHatItemId("");
            case NECK -> setNeckAccessoryData("");
            case BACK -> setBackAccessoryData("");
        }
        // Explizit leeren: raeumt auch konserviertes Fremd-Mod-NBT eines
        // unaufloesbaren Slots ab, das reconcile ("" == "") nicht anfasst.
        this.wardrobe.set(slot, ItemStack.EMPTY);
    }

    private void dropSatchelContents() {
        if (this.level().isClientSide) {
            return;
        }
        for (ItemStack stored : this.satchelInventory.removeAllItems()) {
            spawnAtLocation(stored, 1.1F);
        }
    }

    private void dropWardrobe() {
        dropWardrobeSlot(GoobyWardrobe.Slot.HEAD);
        dropWardrobeSlot(GoobyWardrobe.Slot.NECK);
        dropWardrobeSlot(GoobyWardrobe.Slot.BACK);
    }

    public GoobyCoatVariant getCoatVariant() {
        return GoobyCoatVariant.byId(this.entityData.get(DATA_COAT));
    }

    public void setCoatVariant(GoobyCoatVariant variant) {
        setSynced(DATA_COAT, (byte) variant.ordinal());
    }

    public boolean isCoatUnlocked(GoobyCoatVariant variant) {
        return (this.unlockedCoatsMask & variant.unlockBit()) != 0;
    }

    public int getUnlockedCoatsMask() {
        return this.unlockedCoatsMask;
    }

    private void unlockNextCoat(Player player, ItemStack shimmer) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_accessory");
            return;
        }
        if (!isTame() || !isOwnedBy(player)) {
            denyInteraction(player, Component.translatable(
                    isTame() ? "msg.goobymod.not_owner" : "msg.goobymod.not_tamed"));
            return;
        }
        if (shimmer.getCount() < 4) {
            denyInteraction(player, "msg.goobymod.coat_needs_shimmer");
            return;
        }
        GoobyCoatVariant unlocked = null;
        for (GoobyCoatVariant candidate : GoobyCoatVariant.values()) {
            if (candidate != GoobyCoatVariant.CLASSIC && !isCoatUnlocked(candidate)) {
                unlocked = candidate;
                break;
            }
        }
        if (unlocked == null) {
            player.displayClientMessage(Component.translatable("msg.goobymod.coats_complete"), true);
            return;
        }
        this.unlockedCoatsMask |= unlocked.unlockBit();
        setCoatVariant(unlocked);
        if (!player.getAbilities().instabuild) {
            shimmer.shrink(4);
        }
        playSound(ModSounds.GOOBY_DRESS_UP.get(), 0.9F, 1.2F);
        sendWardrobeParticles(0xF3D56B, 18);
        player.displayClientMessage(Component.translatable(
                "msg.goobymod.coat_unlocked", getName(), Component.translatable(unlocked.translationKey())), true);
    }

    private void cycleCoat(Player player) {
        if (isBaby()) {
            denyBabyAction(player, "msg.goobymod.baby_no_accessory");
            return;
        }
        if (!isTame() || !isOwnedBy(player)) {
            denyInteraction(player, Component.translatable(
                    isTame() ? "msg.goobymod.not_owner" : "msg.goobymod.not_tamed"));
            return;
        }
        if (this.unlockedCoatsMask == GoobyCoatVariant.CLASSIC.unlockBit()) {
            denyInteraction(player, "msg.goobymod.coat_locked");
            return;
        }
        GoobyCoatVariant[] variants = GoobyCoatVariant.values();
        int current = getCoatVariant().ordinal();
        for (int offset = 1; offset <= variants.length; offset++) {
            GoobyCoatVariant candidate = variants[(current + offset) % variants.length];
            if (isCoatUnlocked(candidate)) {
                setCoatVariant(candidate);
                playSound(ModSounds.GOOBY_DRESS_UP.get(), 0.7F, 1.0F);
                sendWardrobeParticles(0xE8D8C4, 8);
                player.displayClientMessage(Component.translatable(
                        "msg.goobymod.coat_selected", Component.translatable(candidate.translationKey())), true);
                return;
            }
        }
    }

    private void sendWardrobeParticles(int color, int count) {
        if (this.level() instanceof ServerLevel serverLevel) {
            Vector3f rgb = new Vector3f(
                    ((color >> 16) & 0xFF) / 255.0F,
                    ((color >> 8) & 0xFF) / 255.0F,
                    (color & 0xFF) / 255.0F);
            serverLevel.sendParticles(new DustParticleOptions(rgb, 1.0F),
                    getX(), getY() + 1.1, getZ(), count, 0.4, 0.45, 0.4, 0.02);
        }
    }

    private String wardrobeGlyphs() {
        return (hasHat() ? "🎩" : "·")
                + (!getNeckAccessoryData().isEmpty() ? "🧣" : "·")
                + (!getBackAccessoryData().isEmpty() ? "🎒" : "·");
    }

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource source, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, source, recentlyHit);
        // Normalpfad (doMobLoot=true): der Outfit-Drop laeuft INNERHALB des
        // captureDrops-Fensters von dropAllDeathLoot und ist damit fuer
        // LivingDropsEvent-Listener (Grave-/Loot-Mods) sichtbar.
        dropWardrobe();
        dropCarriedFetchItem();
    }

    @Override
    protected void dropAllDeathLoot(ServerLevel level, DamageSource source) {
        super.dropAllDeathLoot(level, source);
        // Rettungspfad: doMobLoot=false ueberspringt dropCustomDeathLoot —
        // /kill, Void-Schaden und deaktivierter Schutz duerfen Outfit und
        // Tascheninhalt trotzdem niemals vernichten. dropWardrobeSlot leert
        // die Slots, daher ist der Doppel-Aufruf idempotent (kein Dupe).
        dropWardrobe();
        dropCarriedFetchItem();
    }

    // ------------------------------------------------------------------
    // Buddeln & Geschenke (Cooldown + Kosten statt Endlos-Karotten)
    // ------------------------------------------------------------------

    public void beginDig(int ticks) {
        this.digTicks = ticks;
        this.entityData.set(DATA_DIGGING, true);
        playSound(net.minecraft.sounds.SoundEvents.SAND_BREAK, 0.6F, 1.2F);
    }

    public boolean isActivelyDigging() {
        return this.digTicks > 0;
    }

    /**
     * Buddel-Ende. Ein Geschenk gibt es NUR, wenn (a) eine Geschenk-Ladung da
     * ist (Kosten: 1 gefuettertes Nutella-Glas pro Ladung), (b) der Geschenk-
     * Cooldown abgelaufen ist und (c) ein Spieler der Stufe FRIEND in der
     * Naehe ist. Sonst buddelt Gooby nur zum
     * Spass. RNG injizierbar fuer Tests.
     */
    public void finishDig(RandomSource random) {
        this.digTicks = 0;
        this.entityData.set(DATA_DIGGING, false);
        if (this.level() instanceof ServerLevel level
                && level.getBlockState(blockPosition()).canBeReplaced()) {
            level.setBlock(blockPosition(), ModBlocks.DUG_DIRT.get().defaultBlockState(), 3);
        }
        if (tryGiveGift(random)) {
            return;
        }
        addSatisfaction(5);
        playSound(ModSounds.GOOBY_SQUEAK.get(), 0.8F, 1.3F);
        if (this.bubbleTicks == 0 && random.nextFloat() < 0.6F) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.DIG, random));
        }
    }

    /** Versucht, ein Geschenk auszubuddeln. Testbar; gibt true bei Erfolg zurueck. */
    public boolean tryGiveGift(RandomSource random) {
        if (this.giftCooldown > 0 || this.giftCharges <= 0
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return false;
        }
        ServerPlayer recipient = null;
        double best = Double.MAX_VALUE;
        for (ServerPlayer player : serverLevel.players()) {
            if (player.isSpectator() || !getFriendshipTier(player.getUUID()).canReceiveGifts()) {
                continue;
            }
            double dist = player.distanceToSqr(this);
            if (dist < best) {
                best = dist;
                recipient = player;
            }
        }
        if (recipient == null) {
            return false;
        }
        ItemStack gift = pickGift(random, getFriendshipTier(recipient.getUUID()));
        ItemStack deliveredGift = gift.copy();
        boolean stashed = false;
        if (best > 10.0 * 10.0 && hasSatchel()) {
            ItemStack remainder = insertIntoSatchel(gift);
            stashed = remainder.isEmpty();
            if (!stashed) {
                spawnGiftForRecipient(serverLevel, remainder, recipient);
            }
        } else {
            spawnGiftForRecipient(serverLevel, gift, recipient);
        }
        this.giftCharges--;
        this.giftCooldown = GoobyConfig.giftCooldownTicks();
        addSatisfaction(5);
        playSound(ModSounds.GOOBY_SQUEAK.get(), 0.9F, 1.2F);
        showBubble(GoobySpeech.pickFrom(GoobySpeech.GIFT, random));
        if (stashed) {
            triggerPriorityAction("present_item", 30);
            recipient.displayClientMessage(Component.translatable("msg.goobymod.gift_stashed", getName()), true);
            if (isSatchelFull()) {
                GoobyAdvancements.grant(recipient, GoobyAdvancements.SATCHEL_FULL);
            }
        }
        GoobyAdvancements.grant(recipient, GoobyAdvancements.GIFT_RECEIVED);
        NeoForge.EVENT_BUS.post(new GoobyGiftEvent(this, recipient, deliveredGift, stashed));
        return true;
    }

    public ItemEntity spawnGiftForRecipient(ServerLevel level, ItemStack gift, Player recipient) {
        ItemEntity dropped = new ItemEntity(level, getX(), getY() + 0.45, getZ(), gift.copy());
        dropped.setDeltaMovement(0.0, 0.18, 0.0);
        dropped.setTarget(recipient.getUUID());
        dropped.setThrower(this);
        dropped.getPersistentData().putLong(
                GIFT_PRIORITY_UNTIL_TAG, level.getGameTime() + GIFT_PICKUP_PRIORITY_TICKS);
        level.addFreshEntity(dropped);
        return dropped;
    }

    private static ItemStack pickGift(RandomSource random, FriendshipTier tier) {
        if (rollsTreasureScrap(random, tier)) {
            return new ItemStack(ModItems.TORN_MAP_SCRAP.get());
        }
        float roll = random.nextFloat();
        if (tier.canReceiveGoldenGifts() && roll < 0.15F) {
            return new ItemStack(Items.GOLDEN_CARROT);
        }
        if (roll < 0.55F) {
            return new ItemStack(Items.CARROT);
        }
        if (roll < 0.85F) {
            return new ItemStack(Items.COCOA_BEANS);
        }
        return new ItemStack(ModItems.GOOBY_FLUFF.get());
    }

    public static boolean rollsTreasureScrap(RandomSource random, FriendshipTier tier) {
        return tier == FriendshipTier.BEST_FRIEND && random.nextFloat() < TREASURE_SCRAP_CHANCE;
    }

    // ------------------------------------------------------------------
    // Apportieren (Gooby-Ball): tragen, atomar aufnehmen, zurueckbringen
    // ------------------------------------------------------------------

    public boolean isCarryingFetchItem() {
        return !this.entityData.get(DATA_CARRIED_BALL).isEmpty();
    }

    /**
     * Synchronisierter Trage-Stack (Renderer + Checks). Rueckgabe ist eine
     * defensive Kopie — Mutationen am Ergebnis schlagen nie in den
     * synchronisierten Slot durch.
     */
    public ItemStack getCarriedFetchItem() {
        return this.entityData.get(DATA_CARRIED_BALL).copy();
    }

    public void setCarriedFetchItem(ItemStack stack) {
        this.entityData.set(DATA_CARRIED_BALL, stack.copy());
    }

    public long getFetchRewardCooldownUntil() {
        return this.fetchRewardCooldownUntil;
    }

    /**
     * Nur eigene geworfene Gooby-Baelle zaehlen: Item-Typ UND Owner-UUID in
     * den PersistentData der ItemEntity muessen zum Besitzer passen —
     * fremde Baelle werden kategorisch ignoriert.
     */
    public boolean isOwnFetchBall(ItemEntity item) {
        UUID ownerId = getOwnerUUID();
        return ownerId != null && item.isAlive() && ownerId.equals(GoobyBallItem.throwerOf(item));
    }

    /**
     * Atomarer Pickup auf dem Server-Thread, Ball fuer Ball: aus der
     * ItemEntity wandert genau EIN Ball (inklusive aller DataComponents) in
     * den Trage-Slot; ein (same-owner-)gemergter Rest bleibt mitsamt
     * Owner-Signatur liegen und wird beim naechsten Apport geholt. split +
     * setItem/discard laufen im selben Aufruf — kein Dupe-/Verlustfenster.
     * Ein bereits tragender Gooby oder eine schon von einem anderen Gooby
     * geleerte Entity nimmt nie doppelt.
     */
    public boolean tryPickUpFetchBall(ItemEntity ball) {
        if (this.level().isClientSide || isCarryingFetchItem() || !isOwnFetchBall(ball)) {
            return false;
        }
        ItemStack remainder = ball.getItem().copy();
        ItemStack taken = remainder.split(1);
        setCarriedFetchItem(taken);
        if (remainder.isEmpty()) {
            ball.discard();
        } else {
            ball.setItem(remainder);
        }
        playSound(ModSounds.GOOBY_SQUEAK.get(), 0.8F, 1.25F);
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.POOF, ball.getX(), ball.getY() + 0.2, ball.getZ(),
                    4, 0.2, 0.15, 0.2, 0.01);
        }
        return true;
    }

    /**
     * Rueckgabe an den Besitzer ueber denselben Empfaenger-Prioritaets-Pfad
     * wie Buddelgeschenke ({@link #spawnGiftForRecipient}): Target-UUID,
     * Thrower und Prioritaetsfenster inklusive. Bonus (Satisfaction +
     * Freundschaft) nur ausserhalb des Fetch-Cooldowns — kein Spam-Farming.
     */
    public boolean deliverFetchBallTo(ServerPlayer owner) {
        if (!(this.level() instanceof ServerLevel serverLevel)
                || !isCarryingFetchItem() || !isOwnedBy(owner)) {
            return false;
        }
        ItemStack delivered = getCarriedFetchItem();
        setCarriedFetchItem(ItemStack.EMPTY);
        spawnGiftForRecipient(serverLevel, delivered, owner);
        triggerPriorityAction("present_item", 30);
        playSound(ModSounds.GOOBY_TRICK_CHIME.get(), 0.8F, 1.15F);
        showBubble(GoobySpeech.pickFrom(GoobySpeech.GIFT, this.random));
        owner.displayClientMessage(Component.translatable("msg.goobymod.fetch_returned", getName()), true);
        long now = serverLevel.getGameTime();
        if (now >= this.fetchRewardCooldownUntil) {
            this.fetchRewardCooldownUntil = now + FETCH_REWARD_COOLDOWN_TICKS;
            addSatisfaction(FETCH_SATISFACTION);
            gainFriendship(owner, FETCH_FRIENDSHIP, true);
            serverLevel.sendParticles(ParticleTypes.HEART, getX(), getY() + 1.3, getZ(),
                    5, 0.4, 0.3, 0.4, 0.02);
        }
        GoobyAdvancements.grant(owner, GoobyAdvancements.FIRST_FETCH);
        return true;
    }

    /**
     * Tod (beide Loot-Pfade): der getragene Ball wird sicher gedroppt, nie
     * vernichtet. Slot wird VOR dem Spawn geleert — Doppel-Aufruf bleibt
     * idempotent (kein Dupe), genau wie bei der Garderobe.
     */
    private void dropCarriedFetchItem() {
        if (this.level().isClientSide || !isCarryingFetchItem()) {
            return;
        }
        ItemStack carried = getCarriedFetchItem();
        setCarriedFetchItem(ItemStack.EMPTY);
        spawnAtLocation(carried, 0.8F);
    }

    // ------------------------------------------------------------------
    // Unverwundbarkeit + Gefahren-Teleport
    // ------------------------------------------------------------------

    public void raiseAlarm(boolean creeper) {
        this.alarmCount++;
        playSound(ModSounds.GOOBY_ALARM_SQUEAK.get(), creeper ? 1.35F : 0.9F, creeper ? 0.78F : 1.05F);
        if (this.bubbleTicks == 0) {
            showBubble(GoobySpeech.pickFrom(GoobySpeech.SCARED, this.random));
        }
        if (this.level() instanceof ServerLevel level) {
            level.sendParticles(creeper ? ParticleTypes.ELECTRIC_SPARK : ParticleTypes.POOF,
                    getX(), getY() + 1.45, getZ(), creeper ? 8 : 4, 0.35, 0.25, 0.35, 0.03);
        }
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (this.level().isClientSide) {
            return false;
        }
        // Spieler koennen Gooby NIEMALS wehtun — Boing! + trauriger Blick.
        // WICHTIG: identisches Verhalten fuer ALLE Spielernamen (kein Bonus).
        Player attackingPlayer = source.getEntity() instanceof Player sourcePlayer ? sourcePlayer
                : source.getDirectEntity() instanceof Player directPlayer ? directPlayer : null;
        if (attackingPlayer != null) {
            playSound(ModSounds.GOOBY_BOING.get(), 1.0F, 1.0F);
            this.sadTicks = 90;
            this.entityData.set(DATA_SAD, true);
            if (this.level() instanceof ServerLevel serverLevel) {
                serverLevel.sendParticles(ParticleTypes.POOF, getX(), getY() + 0.8, getZ(), 4, 0.3, 0.2, 0.3, 0.01);
            }
            if (this.sadBubbleCooldown == 0) {
                showBubble(GoobySpeech.pickFrom(GoobySpeech.SAD, this.random));
                this.sadBubbleCooldown = 140;
            }
            applyPlayerHitSatisfactionLoss(attackingPlayer);
            return false;
        }
        // Schutzengel: gezaehmte Goobys nehmen keinerlei Schaden von Mobs.
        // Projektil-Schaden wird ueber source.getEntity() dem Schuetzen zugeordnet.
        Entity attacker = source.getEntity() != null ? source.getEntity() : source.getDirectEntity();
        if (isTame() && GoobyConfig.goobyMobProtection()
                && attacker instanceof LivingEntity && !(attacker instanceof Player)) {
            handleProtectedMobDamage(amount);
            return false;
        }
        // Gefahr (Lava, Feuer, Ersticken, …): wegploppen statt leiden
        if (isEscapableDanger(source) && teleportOutOfDanger()) {
            return false;
        }
        boolean damaged = super.hurt(source, amount);
        if (damaged) {
            // Echter Treffer (auch der Panik-Ausloeser wilder Goobys)
            // unterbricht das Kunststueck — abgebrochene Tricks feiern nicht.
            this.trickConfettiIn = 0;
        }
        return damaged;
    }

    private void applyPlayerHitSatisfactionLoss(Player player) {
        long now = this.level().getGameTime();
        Long previous = this.lastSatisfactionLoss.get(player.getUUID());
        if (previous != null && now - previous < PET_FRIENDSHIP_COOLDOWN_TICKS) {
            return;
        }
        this.lastSatisfactionLoss.put(player.getUUID(), now);
        trimOldest(this.lastSatisfactionLoss, MAX_TRANSIENT_PLAYER_ENTRIES);
        addSatisfaction(-3);
    }

    private void handleProtectedMobDamage(float amount) {
        playSound(ModSounds.GOOBY_BOING.get(), 1.0F, 0.9F);
        this.panicTicks = GUARDIAN_PANIC_TICKS;
        this.entityData.set(DATA_PANICKING, true);
        this.guardianPressure = Math.max(0.0F, this.guardianPressure - Math.max(0.0F, amount));
        if (this.level() instanceof ServerLevel level) {
            level.sendParticles(ParticleTypes.POOF, getX(), getY() + 0.8, getZ(),
                    7, 0.4, 0.3, 0.4, 0.03);
        }
        if (GoobyConfig.escapeToOwner()
                && this.guardianPressure <= getMaxHealth() * 0.30F
                && escapeToOwnerOrHome()) {
            this.guardianPressure = getMaxHealth();
        }
    }

    @Override
    public void tryToTeleportToOwner() {
        LivingEntity owner = getOwner();
        if (owner != null && owner.level() == this.level()) {
            trySafeFollowTeleportAround(owner.blockPosition());
        }
    }

    /** Vanilla-compatible offset search with explicit border, void, fire and fluid rejection. */
    public boolean trySafeFollowTeleportAround(BlockPos ownerPos) {
        for (int attempt = 0; attempt < 10; attempt++) {
            int xOffset = this.random.nextIntBetweenInclusive(-3, 3);
            int zOffset = this.random.nextIntBetweenInclusive(-3, 3);
            if (Math.abs(xOffset) < 2 && Math.abs(zOffset) < 2) {
                continue;
            }
            int yOffset = this.random.nextIntBetweenInclusive(-1, 1);
            BlockPos target = ownerPos.offset(xOffset, yOffset, zOffset);
            if (isSafeFollowTeleportTarget(target)) {
                moveTo(target.getX() + 0.5, target.getY(), target.getZ() + 0.5, getYRot(), getXRot());
                getNavigation().stop();
                return true;
            }
        }
        // Random sampling keeps repeated calls visually varied, but it must not make a
        // perfectly safe open platform fail by chance. Exhaust the same bounded search
        // deterministically, preferring the owner's ground level.
        for (int yOffset : new int[] {0, 1, -1}) {
            for (int xOffset = -3; xOffset <= 3; xOffset++) {
                for (int zOffset = -3; zOffset <= 3; zOffset++) {
                    if (Math.abs(xOffset) < 2 && Math.abs(zOffset) < 2) {
                        continue;
                    }
                    BlockPos target = ownerPos.offset(xOffset, yOffset, zOffset);
                    if (isSafeFollowTeleportTarget(target)) {
                        moveTo(target.getX() + 0.5, target.getY(), target.getZ() + 0.5, getYRot(), getXRot());
                        getNavigation().stop();
                        return true;
                    }
                }
            }
        }
        return false;
    }

    public boolean isSafeFollowTeleportTarget(BlockPos target) {
        if (!(this.level() instanceof ServerLevel level)
                || !level.getWorldBorder().isWithinBounds(target)
                || target.getY() <= level.getMinBuildHeight()
                || target.getY() >= level.getMaxBuildHeight() - 1
                || !level.getFluidState(target).isEmpty()
                || !level.getFluidState(target.below()).isEmpty()
                || WalkNodeEvaluator.getPathTypeStatic(this, target) != PathType.WALKABLE
                || isExplicitTeleportHazard(target)
                || isExplicitTeleportHazard(target.below())) {
            return false;
        }
        BlockPos delta = target.subtract(blockPosition());
        return level.noCollision(this, getBoundingBox().move(delta));
    }

    private boolean isExplicitTeleportHazard(BlockPos pos) {
        return this.level().getBlockState(pos).is(Blocks.FIRE)
                || this.level().getBlockState(pos).is(Blocks.SOUL_FIRE)
                || this.level().getBlockState(pos).is(Blocks.LAVA)
                || this.level().getBlockState(pos).is(Blocks.CACTUS)
                || this.level().getBlockState(pos).is(Blocks.POWDER_SNOW)
                || this.level().getBlockState(pos).is(Blocks.SWEET_BERRY_BUSH);
    }

    /**
     * Guardian-Angel escape target order: online owner in this dimension,
     * then the remembered hutch. Returns whether a safe teleport succeeded.
     */
    public boolean escapeToOwnerOrHome() {
        if (!(this.level() instanceof ServerLevel level)) {
            return false;
        }
        ServerPlayer owner = getOwnerUUID() == null ? null
                : level.getServer().getPlayerList().getPlayer(getOwnerUUID());
        if (owner != null && owner.level() == level && tryTeleportNear(level, owner.blockPosition())) {
            owner.sendSystemMessage(Component.translatable("msg.goobymod.escaped_to_owner", getName()));
            return true;
        }
        if (this.homePos != null
                && level.getBlockState(this.homePos).is(ModBlocks.RABBIT_HUTCH.get())
                && tryTeleportNear(level, this.homePos)) {
            if (owner != null) {
                owner.sendSystemMessage(Component.translatable("msg.goobymod.escaped_home", getName()));
            }
            return true;
        }
        return false;
    }

    private boolean tryTeleportNear(ServerLevel level, BlockPos anchor) {
        Vec3 oldPos = position();
        for (int[] offset : ESCAPE_OFFSETS) {
            BlockPos target = anchor.offset(offset[0], 0, offset[1]);
            if (!level.getWorldBorder().isWithinBounds(target)
                    || target.getY() <= level.getMinBuildHeight()
                    || target.getY() >= level.getMaxBuildHeight() - 1
                    || !level.getFluidState(target).isEmpty()
                    || !level.getFluidState(target.below()).isEmpty()
                    || !level.getBlockState(target.below()).isSolidRender(level, target.below())) {
                continue;
            }
            if (randomTeleport(target.getX() + 0.5, target.getY(), target.getZ() + 0.5, false)) {
                setRemainingFireTicks(0);
                fallDistance = 0.0F;
                emitTeleportEffect(level, oldPos);
                return true;
            }
        }
        return false;
    }

    private void emitTeleportEffect(ServerLevel level, Vec3 oldPos) {
        level.sendParticles(ParticleTypes.PORTAL, oldPos.x, oldPos.y + 0.7, oldPos.z,
                24, 0.4, 0.5, 0.4, 0.15);
        level.sendParticles(ParticleTypes.END_ROD, getX(), getY() + 0.7, getZ(),
                12, 0.35, 0.5, 0.35, 0.03);
        playSound(ModSounds.GOOBY_PLOP.get(), 1.0F, 1.0F);
        if (this.bubbleTicks == 0) {
            showBubble(GoobySpeech.TELEPORT);
        }
    }

    private static boolean isEscapableDanger(DamageSource source) {
        return source.is(DamageTypeTags.IS_FIRE)
                || source.is(DamageTypes.DROWN)
                || source.is(DamageTypes.CACTUS)
                || source.is(DamageTypes.SWEET_BERRY_BUSH)
                || source.is(DamageTypes.FREEZE)
                || source.is(DamageTypes.IN_WALL)
                || source.is(DamageTypes.LIGHTNING_BOLT);
    }

    public boolean teleportOutOfDanger() {
        if (!(this.level() instanceof ServerLevel level)) {
            return false;
        }
        // Pass 1 verlangt trockenes, solides Land. Pass 2 erlaubt als Notnagel die
        // Wasseroberflaeche: Gooby schwimmt, und in Fluss-/Ozeanterrain ist Wasser
        // allemal besser, als im Fels zu ersticken oder zu verbrennen.
        return tryEscapeTeleport(level, false) || tryEscapeTeleport(level, true);
    }

    private boolean tryEscapeTeleport(ServerLevel level, boolean allowWaterSurface) {
        for (int attempt = 0; attempt < 24; attempt++) {
            int x = Mth.floor(getX() + (this.random.nextDouble() - 0.5) * 2.0 * (6 + attempt));
            int z = Mth.floor(getZ() + (this.random.nextDouble() - 0.5) * 2.0 * (6 + attempt));
            int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
            if (tryEscapeLanding(level, new BlockPos(x, y, z), allowWaterSurface)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Attempts to land at {@code target} (feet position, block above the heightmap
     * surface). The strict pass only accepts dry, solid ground; the relaxed pass
     * additionally accepts still-water surfaces because Goobys float.
     */
    private boolean tryEscapeLanding(ServerLevel level, BlockPos target, boolean allowWaterSurface) {
        if (!level.getWorldBorder().isWithinBounds(target)
                || target.getY() <= level.getMinBuildHeight()
                || target.getY() >= level.getMaxBuildHeight() - 1
                || isExplicitTeleportHazard(target)
                || isExplicitTeleportHazard(target.below())
                || !level.getFluidState(target).isEmpty()) {
            return false;
        }
        BlockPos below = target.below();
        FluidState fluidBelow = level.getFluidState(below);
        Vec3 oldPos = position();
        if (fluidBelow.isEmpty()) {
            if (!allowWaterSurface && !level.getBlockState(below).isSolidRender(level, below)) {
                return false;
            }
            // randomTeleport prueft selbst nochmal Kollision + Fluessigkeit am Ziel.
            if (randomTeleport(target.getX() + 0.5, target.getY(), target.getZ() + 0.5, false)) {
                finishEscapeTeleport(level, oldPos);
                return true;
            }
            return false;
        }
        if (!allowWaterSurface || !fluidBelow.is(FluidTags.WATER) || !fluidBelow.isSource()) {
            return false;
        }
        // randomTeleport() lehnt Fluessigkeiten kategorisch ab, deshalb setzt der
        // Notfall-Sprung von Hand direkt auf der Wasseroberflaeche auf.
        Vec3 destination = new Vec3(target.getX() + 0.5, target.getY(), target.getZ() + 0.5);
        if (!level.noCollision(this, getBoundingBox().move(destination.subtract(oldPos)))) {
            return false;
        }
        teleportTo(destination.x, destination.y, destination.z);
        getNavigation().stop();
        finishEscapeTeleport(level, oldPos);
        return true;
    }

    private void finishEscapeTeleport(ServerLevel level, Vec3 oldPos) {
        setRemainingFireTicks(0);
        fallDistance = 0.0F;
        emitTeleportEffect(level, oldPos);
    }

    /** Nur fuer GameTests: deterministischer Zugriff auf die Landeplatz-Logik. */
    public boolean escapeLandingForTest(BlockPos target, boolean allowWaterSurface) {
        return this.level() instanceof ServerLevel level && tryEscapeLanding(level, target, allowWaterSurface);
    }

    @Override
    public boolean causeFallDamage(float fallDistance, float multiplier, DamageSource source) {
        // Kugelrund und weich — Gooby federt jeden Fall ab
        return false;
    }

    // ------------------------------------------------------------------
    // Reiten (langsam, wackelig, urkomisch)
    // ------------------------------------------------------------------

    @Override
    @Nullable
    public LivingEntity getControllingPassenger() {
        if (getFirstPassenger() instanceof Player player && isHoldingNutella(player)) {
            return player;
        }
        return null;
    }

    private static boolean isHoldingNutella(Player player) {
        return player.getMainHandItem().is(ModItems.NUTELLA.get())
                || player.getOffhandItem().is(ModItems.NUTELLA.get());
    }

    /** Purely readable predicate shared by the client animation and GameTests. */
    public boolean shouldBegForNutella(@Nullable Player player) {
        return getMood() == GoobyMood.HUNGRY && player != null && isHoldingNutella(player);
    }

    @Override
    protected void tickRidden(Player player, Vec3 travelVector) {
        super.tickRidden(player, travelVector);
        // Wackeliger Gooby-Gang: der Blickwinkel eiert gemuetlich hin und her
        float wobble = Mth.sin(this.tickCount * 0.35F) * 5.0F;
        setRot(player.getYRot() + wobble, player.getXRot() * 0.5F);
        this.yRotO = this.yBodyRot = this.yHeadRot = getYRot();
        if (!this.level().isClientSide && onGround()
                && travelVector.horizontalDistanceSqr() > 0.0 && this.random.nextInt(40) == 0) {
            // Freuden-Hopser mit Quietscher
            setDeltaMovement(getDeltaMovement().add(0.0, 0.28, 0.0));
            playSound(ModSounds.GOOBY_SQUEAK.get(), 0.5F, 1.4F);
        }
    }

    @Override
    protected Vec3 getRiddenInput(Player player, Vec3 travelVector) {
        return new Vec3(player.xxa * 0.35F, 0.0, player.zza < 0.0F ? player.zza * 0.3F : player.zza * 0.85F);
    }

    @Override
    protected float getRiddenSpeed(Player player) {
        return (float) (getAttributeValue(Attributes.MOVEMENT_SPEED) * 0.6);
    }

    @Override
    protected Vec3 getPassengerAttachmentPoint(Entity entity, EntityDimensions dimensions, float partialTick) {
        return new Vec3(0.0, dimensions.height() * 0.88, -0.1);
    }

    // ------------------------------------------------------------------
    // Sprechblasen
    // ------------------------------------------------------------------

    public void showBubble(String translationKey) {
        showBubble(translationKey, "");
    }

    public void showBubble(String translationKey, String argument) {
        setSynced(DATA_BUBBLE_KEY, boundedSyncString(translationKey, GoobyWardrobe.MAX_SYNCED_KEY_LENGTH));
        setSynced(DATA_BUBBLE_ARG, boundedSyncString(argument, MAX_SYNCED_ARGUMENT_LENGTH));
        this.bubbleTicks = 100;
    }

    /**
     * Triggered action clips are fail-closed: a running action keeps priority
     * and a competing request is ignored instead of cutting it mid-keyframe.
     */
    public boolean tryTriggerAction(String animation, int durationTicks) {
        if (this.actionAnimationTicks > 0) {
            return false;
        }
        this.actionAnimationTicks = Math.max(1, durationTicks);
        triggerAnim("actions", animation);
        return true;
    }

    private void triggerPriorityAction(String animation, int durationTicks) {
        // Feedback-Wave: eine ersetzende Priority-Action bricht den laufenden
        // Trick-Clip ab — sein "Vollendet"-Konfetti wird storniert. Beim
        // Trick-Start selbst ist das harmlos: requestSelectedTrick armiert
        // den Countdown erst NACH diesem Aufruf.
        this.trickConfettiIn = 0;
        this.actionAnimationTicks = Math.max(1, durationTicks);
        triggerAnim("actions", animation);
    }

    // ------------------------------------------------------------------
    // Konversion: Wildhase + Nutella = GOOBY!
    // ------------------------------------------------------------------

    @Nullable
    public static GoobyEntity convertFromRabbit(Rabbit rabbit, @Nullable Player player) {
        GoobyEntity gooby = rabbit.convertTo(ModEntities.GOOBY.get(), false);
        if (gooby == null) {
            return null;
        }
        gooby.setSatisfaction(70);
        gooby.naturalWild = false;
        gooby.setPersistenceRequired();
        if (player != null) {
            gooby.fedOnce = true;
            // Wer den Hasen fuettert, ZAEHMT den frischen Gooby — echter Besitz ab Sekunde 1
            gooby.tame(player);
            gooby.setCommandMode(GoobyCommand.WANDER);
            gooby.setFriendship(player.getUUID(), CONVERT_FRIENDSHIP);
            FriendshipMemory memory = gooby.getMemory(player.getUUID());
            memory.rememberFirstFeed(gooby.level().getGameTime());
            memory.rememberTier(FriendshipTier.BUDDY, gooby.level().getGameTime());
        }
        if (gooby.level() instanceof ServerLevel serverLevel) {
            magicMoment(serverLevel, gooby.position().add(0.0, 0.7, 0.0));
        }
        gooby.playSound(ModSounds.GOOBY_PLOP.get(), 1.0F, 1.0F);
        gooby.showBubble(GoobySpeech.CONVERT);
        gooby.tryTriggerAction("wave", 32);
        return gooby;
    }

    /** Magischer Moment: Wirbel-Partikel! */
    public static void magicMoment(ServerLevel level, Vec3 center) {
        for (int i = 0; i < 40; i++) {
            double angle = (Math.PI * 2.0 * i) / 40.0;
            double radius = 0.4 + (i % 8) * 0.12;
            level.sendParticles(ParticleTypes.WITCH,
                    center.x + Math.cos(angle) * radius,
                    center.y + (i / 40.0) * 1.4,
                    center.z + Math.sin(angle) * radius,
                    1, 0.0, 0.05, 0.0, 0.0);
        }
        level.sendParticles(ParticleTypes.END_ROD, center.x, center.y + 0.4, center.z, 16, 0.4, 0.6, 0.4, 0.06);
        level.sendParticles(ParticleTypes.HEART, center.x, center.y + 1.0, center.z, 4, 0.4, 0.3, 0.4, 0.02);
    }

    // ------------------------------------------------------------------
    // Sounds & Sonstiges
    // ------------------------------------------------------------------

    public boolean isFamilyRitualEligible() {
        UUID owner = getOwnerUUID();
        return isAlive() && isTame() && !isBaby() && owner != null
                && getFriendshipTier(owner).ordinal() >= FriendshipTier.FRIEND.ordinal();
    }

    public boolean canStartFamilyWith(GoobyEntity partner, long gameTime) {
        if (partner == this || !isFamilyRitualEligible() || !partner.isFamilyRitualEligible()) {
            return false;
        }
        long cooldown = GoobyConfig.familyRitualCooldown();
        long mine = this.familyRituals.getOrDefault(partner.getUUID(), Long.MIN_VALUE);
        long theirs = partner.familyRituals.getOrDefault(getUUID(), Long.MIN_VALUE);
        return mine == Long.MIN_VALUE || gameTime - mine >= cooldown
                ? theirs == Long.MIN_VALUE || gameTime - theirs >= cooldown
                : false;
    }

    public void recordFamilyRitual(GoobyEntity partner, long gameTime) {
        this.familyRituals.put(partner.getUUID(), gameTime);
        trimOldest(this.familyRituals, MAX_PARTNER_HISTORY_ENTRIES);
    }

    @Nullable
    public GoobyEntity createRitualOffspring(ServerLevel level, GoobyEntity partner,
            @Nullable Player initiator, BlockPos nestPos) {
        GoobyEntity baby = getBreedOffspring(level, partner);
        if (baby == null) {
            return null;
        }
        baby.parentA = getUUID();
        baby.parentB = partner.getUUID();
        baby.familyNestPos = nestPos.immutable();
        baby.setAge(-GoobyConfig.familyGrowthTicks());

        UUID babyOwner = initiator != null && (isOwnedBy(initiator) || partner.isOwnedBy(initiator))
                ? initiator.getUUID() : getOwnerUUID();
        if (babyOwner != null) {
            baby.setOwnerUUID(babyOwner);
            baby.setTame(true, true);
            baby.setFriendship(babyOwner, FriendshipTier.FRIEND.minimum());
        }
        if (getOwnerUUID() != null) {
            baby.setFriendship(getOwnerUUID(), FriendshipTier.FRIEND.minimum());
        }
        if (partner.getOwnerUUID() != null) {
            baby.setFriendship(partner.getOwnerUUID(), FriendshipTier.FRIEND.minimum());
        }
        baby.setSatisfaction(80);
        return baby;
    }

    public boolean hasParent(UUID candidate) {
        return candidate != null && (candidate.equals(this.parentA) || candidate.equals(this.parentB));
    }

    @Nullable
    public UUID getFirstParentUUID() {
        return this.parentA;
    }

    @Nullable
    public UUID getSecondParentUUID() {
        return this.parentB;
    }

    @Nullable
    public BlockPos getFamilyNestPos() {
        return this.familyNestPos;
    }

    public void setFamilyData(@Nullable UUID firstParent, @Nullable UUID secondParent,
            @Nullable BlockPos nestPos) {
        this.parentA = firstParent;
        this.parentB = secondParent;
        this.familyNestPos = nestPos == null ? null : nestPos.immutable();
    }

    @Nullable
    public GoobyEntity findLoadedParent() {
        if (!(level() instanceof ServerLevel serverLevel)) {
            return null;
        }
        for (UUID parentId : new UUID[] {this.parentA, this.parentB}) {
            if (parentId != null && serverLevel.getEntity(parentId) instanceof GoobyEntity parent) {
                return parent;
            }
        }
        return null;
    }

    /**
     * Babies sleep at their ritual nest; loaded parents choose deterministic
     * adjacent spots so a family forms a small cluster rather than stacking.
     */
    @Nullable
    public BlockPos findFamilySleepSpot() {
        if (isBaby()) {
            return this.familyNestPos;
        }
        if (!(level() instanceof ServerLevel serverLevel)) {
            return null;
        }
        List<GoobyEntity> children = serverLevel.getEntitiesOfClass(GoobyEntity.class,
                getBoundingBox().inflate(32.0),
                child -> child.isBaby() && child.familyNestPos != null && child.hasParent(getUUID()));
        if (children.isEmpty()) {
            return null;
        }
        BlockPos nest = children.getFirst().familyNestPos;
        int[][] offsets = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
        int start = Math.floorMod(getUUID().hashCode(), offsets.length);
        for (int index = 0; index < offsets.length; index++) {
            int[] offset = offsets[(start + index) % offsets.length];
            BlockPos candidate = nest.offset(offset[0], 0, offset[1]);
            if (serverLevel.getBlockState(candidate).isAir()
                    && !serverLevel.getBlockState(candidate.below()).isAir()) {
                return candidate;
            }
        }
        return nest;
    }

    public boolean tryBabyTumble() {
        if (!isBaby() || this.babyTumbleCooldown > 0 || isGoobySleeping()) {
            return false;
        }
        this.babyTumbleCooldown = BABY_TUMBLE_COOLDOWN_TICKS;
        triggerPriorityAction("baby_tumble", 22);
        playSound(ModSounds.GOOBY_BABY_SQUEAK.get(), 0.55F, 0.92F);
        return true;
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        if (isGoobySleeping()) {
            return null;
        }
        if (isBaby()) {
            return ModSounds.GOOBY_BABY_SQUEAK.get();
        }
        if (getMood() == GoobyMood.HUNGRY) {
            return ModSounds.GOOBY_WHINE_HUNGRY.get();
        }
        if (getMood() == GoobyMood.LONELY) {
            return ModSounds.GOOBY_LONELY_SIGH.get();
        }
        return switch (getAmbientPool()) {
            case HAPPY -> ModSounds.GOOBY_AMBIENT_HAPPY.get();
            case NEUTRAL -> ModSounds.GOOBY_AMBIENT_NEUTRAL.get();
            case SLEEPY -> ModSounds.GOOBY_AMBIENT_SLEEPY.get();
        };
    }

    @Override
    public void playAmbientSound() {
        SoundEvent ambient = getAmbientSound();
        if (ambient != null && GoobySoundLimiter.tryAcquire(level(), blockPosition(), ambient, 20)) {
            playSound(ambient, getSoundVolume(), getVoicePitch());
        }
    }

    private void playRateLimitedSound(SoundEvent sound, float volume, float pitch, int cooldownTicks) {
        if (GoobySoundLimiter.tryAcquire(level(), blockPosition(), sound, cooldownTicks)) {
            playSound(sound, volume, pitch);
        }
    }

    public GoobySoundProfile.AmbientPool getAmbientPool() {
        return switch (getMood()) {
            case HAPPY -> GoobySoundProfile.AmbientPool.HAPPY;
            case SLEEPY -> GoobySoundProfile.AmbientPool.SLEEPY;
            default -> GoobySoundProfile.AmbientPool.NEUTRAL;
        };
    }

    @Override
    public int getAmbientSoundInterval() {
        return 300;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource source) {
        return isBaby() ? ModSounds.GOOBY_BABY_SQUEAK.get() : ModSounds.GOOBY_SAD_WHIMPER.get();
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return ModSounds.GOOBY_SAD_WHIMPER.get();
    }

    @Override
    protected void playStepSound(BlockPos pos, net.minecraft.world.level.block.state.BlockState state) {
        playSound(net.minecraft.sounds.SoundEvents.WOOL_STEP, 0.1F, 1.3F);
    }

    @Override
    public float getVoicePitch() {
        return isBaby() ? 1.4F : 1.0F;
    }

    @Override
    public void playSound(SoundEvent sound, float volume, float pitch) {
        if (!this.isSilent()) {
            float volumeJitter = 0.90F + this.random.nextFloat() * 0.20F;
            float pitchJitter = 0.90F + this.random.nextFloat() * 0.20F;
            super.playSound(sound, volume * volumeJitter * GoobyConfig.goobyVolumeScale(),
                    pitch * pitchJitter);
        }
    }

    @Override
    @Nullable
    public GoobyEntity getBreedOffspring(ServerLevel level, AgeableMob otherParent) {
        GoobyEntity baby = ModEntities.GOOBY.get().create(level);
        if (baby == null) {
            return null;
        }
        baby.parentA = getUUID();
        if (otherParent instanceof GoobyEntity otherGooby) {
            baby.parentB = otherGooby.getUUID();
        }
        baby.setAge(-GoobyConfig.familyGrowthTicks());
        return baby;
    }

    @Override
    public boolean isFood(ItemStack stack) {
        return false;
    }

    @Override
    public boolean removeWhenFarAway(double distance) {
        return this.naturalWild && !isTame() && !hasCustomName() && !isPersistenceRequired();
    }

    // ------------------------------------------------------------------
    // GeckoLib
    // ------------------------------------------------------------------

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, "movement", 4, this::movementAnimation));

        AnimationController<GoobyEntity> micro =
                new AnimationController<>(this, "micro", 2, this::microAnimation);
        micro.setSoundKeyframeHandler(event -> {
            String sound = event.getKeyframeData().getSound();
            if ("goobymod:yawn".equals(sound)) {
                playLocalMicroSound(ModSounds.GOOBY_YAWN.get(), 0.65F, 1.0F);
            } else if ("goobymod:sniff".equals(sound)) {
                playLocalMicroSound(ModSounds.GOOBY_SNIFF.get(), 0.45F, 1.05F);
            }
        });
        controllers.add(micro);

        // Last registration gives full-body action clips priority over additive micro motion.
        AnimationController<GoobyEntity> actions = new AnimationController<>(this, "actions", 3,
                state -> PlayState.STOP)
                .triggerableAnim("pet", ANIM_PET)
                .triggerableAnim("eat", ANIM_EAT)
                .triggerableAnim("wave", ANIM_WAVE)
                .triggerableAnim("land", ANIM_LAND)
                .triggerableAnim("snuggle", ANIM_SNUGGLE_LEAN)
                .triggerableAnim("tier_up", ANIM_TIER_UP_BOUNCE)
                .triggerableAnim("ears_perk", ANIM_EARS_PERK)
                .triggerableAnim("trick_spin", ANIM_TRICK_SPIN)
                .triggerableAnim("trick_high_five", ANIM_TRICK_HIGH_FIVE)
                .triggerableAnim("trick_flop", ANIM_TRICK_FLOP)
                .triggerableAnim("trick_speak", ANIM_TRICK_SPEAK)
                .triggerableAnim("trick_roll", ANIM_TRICK_ROLL)
                .triggerableAnim("trick_dance", ANIM_TRICK_DANCE)
                .triggerableAnim("training_success", ANIM_TRAINING_SUCCESS)
                .triggerableAnim("hutch_enter", ANIM_HUTCH_ENTER)
                .triggerableAnim("hutch_exit", ANIM_HUTCH_EXIT)
                .triggerableAnim("baby_tumble", ANIM_BABY_TUMBLE)
                .triggerableAnim("parent_nuzzle", ANIM_PARENT_NUZZLE)
                .triggerableAnim("grow_up_pop", ANIM_GROW_UP_POP)
                .triggerableAnim("bow", ANIM_BOW)
                .triggerableAnim("happy_bounce", ANIM_HAPPY_BOUNCE)
                .triggerableAnim("dig_excited", ANIM_DIG_EXCITED)
                .triggerableAnim("present_item", ANIM_PRESENT_ITEM)
                .triggerableAnim("nose_wiggle_ack", ANIM_NOSE_WIGGLE);
        actions.setSoundKeyframeHandler(event -> {
            if ("goobymod:purr_loop".equals(event.getKeyframeData().getSound())) {
                GoobyPurrSound.playForLocalPetter(this);
            }
        });
        controllers.add(actions);
    }

    private PlayState movementAnimation(AnimationState<GoobyEntity> state) {
        // Gait from replicated position deltas; GoobyLocomotion smooths and
        // clamps the samples (turn dips, teleport spikes) and its hysteresis
        // keeps boundary speeds from flickering between clips.
        GoobyLocomotion.Gait gait = this.clientLocomotion.update(this.tickCount, horizontalTickSpeed());
        if (CreateCompat.isOnContraption(this)) {
            return state.setAndContinue(CreateCompat.contraptionMotionSqr(this) > 0.01
                    ? ANIM_TRAIN_LEAN : ANIM_SEATED_CONTRAPTION);
        }
        if (isSeekingTreasure()) {
            return state.setAndContinue(ANIM_SNIFF_SEEK);
        }
        if (getSocialAction() == SOCIAL_GREETING_INITIATOR
                || getSocialAction() == SOCIAL_GREETING_MIRROR) {
            return state.setAndContinue(ANIM_GREETING_BOUNCE);
        }
        if (getSocialAction() == SOCIAL_PLAY_CHASE) {
            return state.setAndContinue(ANIM_PLAY_CHASE);
        }
        if (isGoobySleeping() && hasSleepingNeighbor()) {
            return state.setAndContinue(ANIM_NAP_HUDDLE);
        }
        if (isShyWild() && !gait.isMoving() && this.level().getNearestPlayer(this, 12.0) != null) {
            return state.setAndContinue(ANIM_SHY_PEEK);
        }
        GoobyAnimationState.Pose desired = GoobyAnimationState.selectPose(
                gait.isMoving(), isGoobySleeping(), isDigging(), isSitting(), isSad(), isAlerting());
        this.clientAnimationState.update(desired, this.tickCount);
        if (this.clientAnimationState.isTransitioning()) {
            return state.setAndContinue(switch (this.clientAnimationState.transition()) {
                case SIT_DOWN -> ANIM_SIT_DOWN;
                case STAND_UP -> ANIM_STAND_UP;
                case SLEEP_DOWN -> ANIM_SLEEP_DOWN;
                case WAKE_UP -> ANIM_WAKE_UP;
                case NONE -> ANIM_IDLE;
            });
        }
        return state.setAndContinue(switch (this.clientAnimationState.stablePose()) {
            // Babys teilen sich den Adult-run-Clip: GoobyRenderer#preRender
            // skaliert den ganzen PoseStack uniform (0.55), Root-/Limb-
            // Amplituden bleiben am Baby-Geo also proportional identisch.
            case HOP -> isBaby()
                    ? (gait == GoobyLocomotion.Gait.RUN ? ANIM_RUN : ANIM_BABY_HOP)
                    : (gait == GoobyLocomotion.Gait.RUN ? ANIM_RUN : ANIM_WALK);
            case SIT -> ANIM_SIT;
            case SLEEP -> isInHutch() ? ANIM_SLEEP_CURL_TIGHT : ANIM_SLEEP;
            case DIG -> ANIM_DIG;
            case SAD -> ANIM_SAD;
            case ALERT -> ANIM_ALERT;
            case IDLE -> ANIM_IDLE;
        });
    }

    /**
     * Horizontal distance covered in the last tick, in blocks. Based on the
     * replicated positions ({@code xo}/{@code zo}); the client interpolates
     * remote positions over a few ticks, so its values closely track — but are
     * not bit-identical to — the server's. Teleport-sized spikes (which the
     * client lerp spreads over ~3 ticks) are discarded by
     * {@link GoobyLocomotion#MAX_PLAUSIBLE_SPEED} before they reach the gait.
     */
    public double horizontalTickSpeed() {
        double dx = getX() - this.xo;
        double dz = getZ() - this.zo;
        return Math.sqrt(dx * dx + dz * dz);
    }

    private PlayState microAnimation(AnimationState<GoobyEntity> state) {
        int now = this.tickCount;
        if (!isClientMicroLodActive() || isGoobySleeping() || isDigging() || CreateCompat.isOnContraption(this)) {
            if (isGoobySleeping()) {
                this.clientYawnedForWake = false;
            }
            this.clientMicroAnimation = null;
            return PlayState.STOP;
        }
        if (isShakingWater()) {
            return state.setAndContinue(ANIM_SHAKE_OFF_WATER);
        }
        if (isHidingFromThunder()) {
            return state.setAndContinue(ANIM_HIDE_BEHIND);
        }
        if (this.level().isThundering() && getMood() == GoobyMood.SCARED) {
            return state.setAndContinue(ANIM_SHIVER);
        }
        // Dieselbe Gait-Wahrheit wie der movement-Controller (idempotent pro
        // Tick): GeckoLibs state.isMoving() nutzt eine eigene Schwelle und
        // wuerde Micro-Clips schon unterdruecken, waehrend noch Idle laeuft.
        if (this.clientLocomotion.update(this.tickCount, horizontalTickSpeed()).isMoving()) {
            this.clientMicroAnimation = null;
            return PlayState.STOP;
        }
        if (this.clientNextBlinkTick == 0) {
            int pace = isBaby() ? 2 : 1;
            this.clientNextBlinkTick = now + (60 + this.random.nextInt(81)) / pace;
            this.clientNextNoseTick = now + (80 + this.random.nextInt(121)) / pace;
            this.clientNextFlavorTick = now + (100 + this.random.nextInt(141)) / pace;
        }
        if (this.clientMicroAnimation != null && now < this.clientMicroEndTick) {
            return state.setAndContinue(this.clientMicroAnimation);
        }
        this.clientMicroAnimation = null;

        if (hasRecentlyWoken() && !this.clientYawnedForWake) {
            this.clientYawnedForWake = true;
            return beginMicro(state, ANIM_STRETCH_YAWN, 28);
        }
        if (now >= this.clientNextBlinkTick) {
            this.clientNextBlinkTick = now + (60 + this.random.nextInt(81)) / (isBaby() ? 2 : 1);
            return beginMicro(state, ANIM_BLINK, 4);
        }
        if (now >= this.clientNextNoseTick) {
            this.clientNextNoseTick = now + (80 + this.random.nextInt(121)) / (isBaby() ? 2 : 1);
            return beginMicro(state, ANIM_NOSE_WIGGLE, 10);
        }
        if (now >= this.clientNextFlavorTick) {
            this.clientNextFlavorTick = now + (100 + this.random.nextInt(141)) / (isBaby() ? 2 : 1);
            RawAnimation flavor = getMood() == GoobyMood.HAPPY && this.random.nextInt(3) == 0
                    ? ANIM_HAPPY_BOUNCE
                    : getSatisfaction() >= HAPPY_THRESHOLD && this.random.nextBoolean()
                    ? ANIM_TAIL_WIGGLE
                    : this.random.nextBoolean() ? ANIM_EAR_TWITCH_L : ANIM_EAR_TWITCH_R;
            return beginMicro(state, flavor,
                    flavor == ANIM_HAPPY_BOUNCE ? 14 : flavor == ANIM_TAIL_WIGGLE ? 16 : 7);
        }
        Player nearest = this.level().getNearestPlayer(this, 8.0);
        if (shouldBegForNutella(nearest)) {
            return state.setAndContinue(ANIM_BEG);
        }
        if (getMood() == GoobyMood.LONELY) {
            return state.setAndContinue(ANIM_EARS_DROOP);
        }
        return PlayState.STOP;
    }

    private PlayState beginMicro(AnimationState<GoobyEntity> state, RawAnimation animation, int durationTicks) {
        this.clientMicroAnimation = animation;
        this.clientMicroEndTick = this.tickCount + durationTicks;
        state.getController().forceAnimationReset();
        return state.setAndContinue(animation);
    }

    private void playLocalMicroSound(SoundEvent sound, float volume, float pitch) {
        if (this.level().isClientSide && !isSilent()) {
            this.level().playLocalSound(getX(), getY(), getZ(), sound, SoundSource.NEUTRAL,
                    volume * GoobyConfig.goobyVolumeScale(),
                    pitch * (0.9F + this.random.nextFloat() * 0.2F), false);
        }
    }

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return this.geckoCache;
    }

    /** Steht Gooby auf buddelbarem Boden? */
    public boolean isOnDiggableGround() {
        return this.level().getBlockState(blockPosition().below()).is(BlockTags.DIRT);
    }
}
