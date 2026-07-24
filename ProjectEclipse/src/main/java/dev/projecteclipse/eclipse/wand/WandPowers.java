package dev.projecteclipse.eclipse.wand;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.protection.SpawnProtectionRules;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side power execution for the Zauberstab. Single entry point per network request
 * ({@link #handleCast}, {@link #handleChoosePath} — dispatched by
 * {@code network/wand/WandPayloads}); EVERYTHING is validated here: held item, ownership,
 * global disable ({@code /dev wand disable}), path lock, unlocked power index, charge,
 * per-player-per-power cooldowns and spawn-protection zones. The client never decides
 * anything.
 *
 * <p>All world FX go through the frozen budgeted channels: {@code FxPayloads.sendFxEvent}
 * ({@code FX_LIGHTNING_STRIKE} / {@code FX_RIFT_OPEN} / {@code FX_RIFT_CLOSE} /
 * {@code FX_SHOCKWAVE}) and {@code S2CQuasarPayload} one-shot emitters (client
 * {@code QuasarSpawner} enforces the P2 §3.5 budget law; over-budget cues drop silently).
 * Audio is server-owned per the {@code strikeLightning} contract. Multi-tick powers
 * (Feuerwelle ring, Sternschauer volley, Magmasprung landing, delayed rift closes) run on
 * {@link WandTickService}; the crash-safe Phasenwelle block engine is
 * {@link WandPhaseService}.</p>
 */
public final class WandPowers {
    /** In-memory per-player cooldowns: uuid → (power key → gameTime the power frees up). */
    private static final Map<UUID, Map<String, Long>> COOLDOWNS = new HashMap<>();

    /** FX broadcast radius for one-shot cues. */
    private static final double FX_RANGE = 64.0D;

    // One-shot quasar emitters (all loop:false — never dispatch looping ids via payload).
    private static final ResourceLocation UNLOCK_BURST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "unlock_burst");
    private static final ResourceLocation LIGHTNING_IMPACT =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "eclipse_lightning_impact");

    private WandPowers() {}

    /** Server-stop reset (singleplayer relaunch safety). */
    public static void clearRuntime() {
        COOLDOWNS.clear();
    }

    // ------------------------------------------------------------------ payload entry points

    /** {@code C2SWandCastPayload} handler — the ONLY way a power executes. */
    public static void handleCast(ServerPlayer player, boolean mainHand) {
        InteractionHand hand = mainHand ? InteractionHand.MAIN_HAND : InteractionHand.OFF_HAND;
        ItemStack stack = player.getItemInHand(hand);
        if (!(stack.getItem() instanceof EclipseWandItem)) {
            return; // stale/forged request
        }
        WandStore store = WandStore.get(player.server);
        if (store.isDisabled()) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.disabled",
                    (store.disabledRemainingSeconds() + 59L) / 60L), true);
            EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_STALL);
            return;
        }
        WandSoulbind.tick(player, stack); // conversion/claim races resolve before validation
        if (!WandSoulbind.isOwner(player, stack)) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.not_owner"), true);
            return;
        }
        WandPath path = WandSoulbind.pathOf(stack);
        if (path == WandPath.NONE) {
            return; // client opens the chooser; nothing to cast yet
        }
        int level = WandSoulbind.levelOf(stack);
        int selected = Mth.clamp(stack.getOrDefault(WandItems.WAND_SELECTED.get(), 0), 0, level - 1);
        String key = path.powerKey(selected);
        WandConfig.Power power = WandConfig.get().power(key);

        long now = player.serverLevel().getGameTime();
        long readyAt = COOLDOWNS.getOrDefault(player.getUUID(), Map.of()).getOrDefault(key, 0L);
        if (readyAt > now) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.cooldown",
                    Component.translatable(path.powerLangKey(selected)),
                    String.format("%.1f", (readyAt - now) / 20.0D)), true);
            return;
        }
        int charge = stack.getOrDefault(WandItems.WAND_CHARGE.get(), 0);
        if (charge < power.cost()) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.no_charge",
                    power.cost(), charge), true);
            EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_STALL);
            player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.6F, 0.5F);
            return;
        }
        if (SpawnProtectionRules.isInProtectionZone(player.level(), player.blockPosition())
                && !SpawnProtectionRules.isExempt(player)) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.protected"), true);
            return;
        }

        if (!execute(player, stack, path, selected, power)) {
            return; // refused (e.g. blink found no room) — no cost, no cooldown
        }
        stack.set(WandItems.WAND_CHARGE.get(), charge - power.cost());
        COOLDOWNS.computeIfAbsent(player.getUUID(), id -> new HashMap<>())
                .put(key, now + power.cooldownTicks());
        EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_USE);
        WandConfig.Xp xp = WandConfig.get().xp();
        awardXp(player, stack, power.cost() * xp.perCostPoint());
        SkillsApi.addXp(player, "wand", power.cost() * xp.skillXpPerCostPoint());
    }

    /** {@code C2SWandChoosePathPayload} handler — first-choice lock, server-validated. */
    public static void handleChoosePath(ServerPlayer player, int pathId) {
        WandPath chosen = WandPath.byId(pathId);
        if (chosen == WandPath.NONE) {
            return;
        }
        ItemStack stack = findHeldWand(player);
        if (stack == null) {
            return;
        }
        WandSoulbind.tick(player, stack);
        if (!WandSoulbind.isOwner(player, stack) || WandSoulbind.pathOf(stack) != WandPath.NONE) {
            return; // path already locked (or foreign wand) — silently ignore the stale request
        }
        stack.set(WandItems.WAND_PATH.get(), chosen.id());
        stack.set(WandItems.WAND_LEVEL.get(), 1);
        stack.set(WandItems.WAND_XP.get(), 0);
        stack.set(WandItems.WAND_SELECTED.get(), 0);
        WandSoulbind.persistToStore(player, stack);

        EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_AWAKEN);
        celebrationBurst(player.serverLevel(), player.position().add(0.0D, 1.0D, 0.0D));
        player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.BEACON_ACTIVATE, SoundSource.PLAYERS, 0.9F, 1.3F);
        player.sendSystemMessage(Component.translatable("wand.eclipse.msg.path_chosen",
                Component.translatable(chosen.langKey())));
    }

    /** Sneak-right-click: cycles the selected power among the unlocked ones. */
    public static void cycleSelected(ServerPlayer player, ItemStack stack) {
        WandPath path = WandSoulbind.pathOf(stack);
        if (path == WandPath.NONE) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.pathless"), true);
            return;
        }
        int level = WandSoulbind.levelOf(stack);
        int selected = (stack.getOrDefault(WandItems.WAND_SELECTED.get(), 0) + 1) % level;
        stack.set(WandItems.WAND_SELECTED.get(), selected);
        WandConfig.Power power = WandConfig.get().power(path.powerKey(selected));
        player.displayClientMessage(Component.translatable("wand.eclipse.msg.selected",
                Component.translatable(path.powerLangKey(selected)), power.cost()), true);
        player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.UI_BUTTON_CLICK.value(), SoundSource.PLAYERS, 0.35F, 1.6F);
    }

    // ------------------------------------------------------------------ XP / leveling

    /**
     * Adds wand XP (cast payout, kill bonus) and handles level-ups: {@code levelup} trigger
     * anim + a small wand-specific Quasar flourish (deliberately NOT the LevelUpOverlay) +
     * model stage growth via the synced components.
     */
    public static void awardXp(ServerPlayer player, ItemStack stack, float amount) {
        if (amount <= 0.0F || WandSoulbind.pathOf(stack) == WandPath.NONE) {
            return;
        }
        WandConfig.Xp config = WandConfig.get().xp();
        int xp = stack.getOrDefault(WandItems.WAND_XP.get(), 0) + Math.round(amount);
        int level = WandSoulbind.levelOf(stack);
        boolean leveled = false;
        while (level < WandPath.MAX_LEVEL && xp >= config.costForLevel(level)) {
            xp -= config.costForLevel(level);
            level++;
            leveled = true;
        }
        stack.set(WandItems.WAND_XP.get(), xp);
        stack.set(WandItems.WAND_LEVEL.get(), level);
        WandSoulbind.persistToStore(player, stack);
        if (!leveled) {
            return;
        }
        EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_LEVELUP);
        ServerLevel serverLevel = player.serverLevel();
        celebrationBurst(serverLevel, player.position().add(0.0D, 1.2D, 0.0D));
        serverLevel.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.8F, 1.4F);
        serverLevel.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.PLAYERS, 0.9F, 0.8F);
        WandPath path = WandSoulbind.pathOf(stack);
        player.sendSystemMessage(Component.translatable("wand.eclipse.msg.levelup", level,
                Component.translatable(path.powerLangKey(level - 1))));
    }

    /** Three staggered {@code unlock_burst} pops around a position (level-up / awaken cue). */
    private static void celebrationBurst(ServerLevel level, Vec3 center) {
        sendQuasar(level, UNLOCK_BURST, center);
        WandTickService.schedule(level, 4, () -> sendQuasar(level, UNLOCK_BURST, center.add(0.7D, 0.4D, -0.4D)));
        WandTickService.schedule(level, 8, () -> sendQuasar(level, UNLOCK_BURST, center.add(-0.6D, 0.7D, 0.5D)));
    }

    // ------------------------------------------------------------------ power dispatch

    private static boolean execute(ServerPlayer player, ItemStack stack, WandPath path,
            int selected, WandConfig.Power power) {
        // Level-4/5 powers are the upgraded re-runs of the level-2/3 powers (per spec).
        int effective = selected == 3 ? 1 : selected == 4 ? 2 : selected;
        return switch (path) {
            case RISS -> switch (effective) {
                case 0 -> castBlink(player, power);
                case 1 -> WandPhaseService.castWave(player, power);
                default -> castRissschlag(player, power);
            };
            case GLUT -> switch (effective) {
                case 0 -> castGlutstoss(player, power);
                case 1 -> castFeuerwelle(player, power);
                default -> castMagmasprung(player, power);
            };
            case STERN -> switch (effective) {
                case 0 -> castFunkenruf(player, power);
                case 1 -> castSternschauer(player, power);
                default -> castKometenschlag(player, power);
            };
            default -> false;
        };
    }

    // ------------------------------------------------------------------ Phasenriss (RISS)

    /** L1 Blink: short glitch teleport along the look ray through a fist-sized tear. */
    private static boolean castBlink(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 12.0F);
        Vec3 from = player.position();
        Vec3 target = findBlinkTarget(player, range);
        if (target == null) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.no_room"), true);
            return false;
        }
        Vec3 fxFrom = from.add(0.0D, 1.0D, 0.0D);
        Vec3 fxTo = target.add(0.0D, 1.0D, 0.0D);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxFrom, 2.0F, 1.0F, FX_RANGE);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxTo, 2.0F, 1.0F, FX_RANGE);
        WandTickService.schedule(level, 15, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxFrom, 0.0F, 0.0F, FX_RANGE);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxTo, 0.0F, 0.0F, FX_RANGE);
        });
        player.teleportTo(target.x, target.y, target.z);
        player.resetFallDistance();
        level.playSound(null, from.x, from.y, from.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.8F, 1.3F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.8F, 0.9F);
        return true;
    }

    /** Furthest collision-free spot along the look ray the player's box fits into. */
    private static Vec3 findBlinkTarget(ServerPlayer player, double range) {
        ServerLevel level = player.serverLevel();
        Vec3 eye = player.getEyePosition();
        Vec3 look = player.getLookAngle();
        HitResult hit = level.clip(new ClipContext(eye, eye.add(look.scale(range)),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
        double reach = hit.getType() == HitResult.Type.MISS ? range
                : Math.max(0.0D, hit.getLocation().distanceTo(eye) - 0.5D);
        for (double dist = reach; dist >= 2.0D; dist -= 0.5D) {
            Vec3 feet = player.position().add(look.scale(dist));
            AABB box = player.getBoundingBox().move(feet.subtract(player.position()));
            if (level.noCollision(player, box)) {
                return feet;
            }
        }
        return null;
    }

    /** L3 Rissschlag: a portal-style tear bursts open on the aimed point and lashes out. */
    private static boolean castRissschlag(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 24.0F)).add(0.0D, 1.2D, 0.0D);
        float width = power.param("width", 5.0F);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, target, width, 1.0F, FX_RANGE);
        sendQuasar(level, S2CQuasarPayload.BORDER_GLITCH, target);
        WandTickService.schedule(level, (int) power.param("openTicks", 25.0F),
                () -> FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, target, 0.0F, 0.0F, FX_RANGE));
        damageAround(player, target, power.param("radius", 4.0F), power.param("damage", 8.0F),
                power.param("knockback", 1.1F), 0);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 0.7F, 1.5F);
        return true;
    }

    // ------------------------------------------------------------------ Glutherz (GLUT)

    /** L1 Glutstoß: short fire dart — first living thing on the ray burns. */
    private static boolean castGlutstoss(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 12.0F);
        Vec3 eye = player.getEyePosition();
        Vec3 look = player.getLookAngle();
        HitResult blockHit = level.clip(new ClipContext(eye, eye.add(look.scale(range)),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
        double maxDist = blockHit.getType() == HitResult.Type.MISS ? range
                : blockHit.getLocation().distanceTo(eye);

        LivingEntity victim = null;
        double victimDist = maxDist;
        for (double dist = 1.0D; dist <= maxDist; dist += 0.5D) {
            Vec3 point = eye.add(look.scale(dist));
            level.sendParticles(ParticleTypes.FLAME, point.x, point.y, point.z, 2, 0.06D, 0.06D, 0.06D, 0.005D);
            if (victim == null) {
                List<LivingEntity> hits = level.getEntitiesOfClass(LivingEntity.class,
                        new AABB(point, point).inflate(0.6D), e -> e != player && e.isAlive());
                if (!hits.isEmpty()) {
                    victim = hits.get(0);
                    victimDist = dist;
                }
            }
        }
        Vec3 impact = eye.add(look.scale(victimDist));
        if (victim != null) {
            victim.hurt(player.damageSources().indirectMagic(player, player), power.param("damage", 5.0F));
            victim.igniteForSeconds((int) power.param("fireSeconds", 3.0F));
            level.sendParticles(ParticleTypes.LAVA, impact.x, impact.y, impact.z, 4, 0.2D, 0.2D, 0.2D, 0.0D);
        }
        level.sendParticles(ParticleTypes.SMALL_FLAME, impact.x, impact.y, impact.z, 8, 0.25D, 0.25D, 0.25D, 0.02D);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.FIRECHARGE_USE, SoundSource.PLAYERS, 0.7F, 1.2F);
        return true;
    }

    /**
     * L2 Feuerwelle: the giant fire wave — expanding ground flame ring, visual-first
     * ({@code FX_SHOCKWAVE} + marched flame particles), short fire ticks, and it NEVER
     * touches a block (no ignition, no griefing). Ring march runs on {@link WandTickService}.
     */
    private static boolean castFeuerwelle(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = player.position();
        int expandTicks = (int) power.param("expandTicks", 40.0F);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, center,
                1.2F, expandTicks, FX_RANGE + 32.0D);
        WandTickService.startFireWave(player, center,
                power.param("radius", 12.0F), expandTicks, power.param("damage", 7.0F),
                (int) (power.param("fireSeconds", 3.0F) * 20.0F), power.param("knockup", 0.42F));
        level.playSound(null, center.x, center.y, center.z, SoundEvents.FIRECHARGE_USE,
                SoundSource.PLAYERS, 1.0F, 0.6F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.BLAZE_SHOOT,
                SoundSource.PLAYERS, 0.9F, 0.7F);
        return true;
    }

    /** L3 Magmasprung: fiery leap; the landing slam is tracked by {@link WandTickService}. */
    private static boolean castMagmasprung(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float launch = power.param("launch", 1.15F);
        Vec3 look = player.getLookAngle();
        Vec3 flat = new Vec3(look.x, 0.0D, look.z);
        Vec3 dir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : Vec3.ZERO;
        player.setDeltaMovement(dir.scale(launch * 0.8D).add(0.0D, 0.9D * launch, 0.0D));
        player.hurtMarked = true; // force velocity sync to the client
        WandTickService.trackMagmaJump(player, power.param("damage", 6.0F),
                power.param("radius", 4.0F), power.param("knockback", 1.0F),
                (int) (power.param("fireSeconds", 2.0F) * 20.0F));
        level.sendParticles(ParticleTypes.FLAME, player.getX(), player.getY(), player.getZ(),
                20, 0.4D, 0.1D, 0.4D, 0.05D);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.BLAZE_SHOOT, SoundSource.PLAYERS, 0.9F, 0.8F);
        return true;
    }

    // ------------------------------------------------------------------ Sternenfall (STERN)

    /** L1 Funkenruf: a single spark from the dark sky onto the aimed point. */
    private static boolean castFunkenruf(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 32.0F));
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, target, 0.5F, 0.0F, FX_RANGE);
        sendQuasar(level, LIGHTNING_IMPACT, target);
        damageAround(player, target, power.param("radius", 2.0F), power.param("damage", 5.0F), 0.4F, 0);
        // Sender owns audio (strikeLightning contract).
        level.playSound(null, target.x, target.y, target.z, SoundEvents.LIGHTNING_BOLT_IMPACT,
                SoundSource.PLAYERS, 0.7F, 1.4F);
        return true;
    }

    /**
     * L2 Sternschauer: the star shower — telegraphed zone, then N falling stars (thin
     * {@code strikeLightning} ribbons read as star trails) rain over it. Scheduling on
     * {@link WandTickService}.
     */
    private static boolean castSternschauer(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 zone = aimPoint(player, power.param("range", 32.0F));
        float zoneRadius = power.param("zoneRadius", 8.0F);
        int telegraph = (int) power.param("telegraphTicks", 30.0F);
        int duration = (int) power.param("durationTicks", 60.0F);
        int count = Math.max(1, (int) power.param("count", 12.0F));
        float damage = power.param("damage", 5.0F);
        float hitRadius = power.param("hitRadius", 2.5F);

        // Telegraph: a quiet ring of end-rod motes so targets get their 1.5 s warning.
        for (int i = 0; i < 16; i++) {
            double angle = i * Math.PI * 2.0D / 16.0D;
            level.sendParticles(ParticleTypes.END_ROD,
                    zone.x + Math.cos(angle) * zoneRadius, zone.y + 0.3D, zone.z + Math.sin(angle) * zoneRadius,
                    1, 0.05D, 0.1D, 0.05D, 0.01D);
        }
        level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.0F, 0.6F);

        for (int i = 0; i < count; i++) {
            int delay = telegraph + (i * duration) / count;
            WandTickService.schedule(level, delay, () -> {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double dist = Math.sqrt(level.random.nextDouble()) * zoneRadius;
                double x = zone.x + Math.cos(angle) * dist;
                double z = zone.z + Math.sin(angle) * dist;
                double y = level.getHeight(Heightmap.Types.MOTION_BLOCKING, (int) Math.floor(x), (int) Math.floor(z));
                Vec3 impact = new Vec3(x, y, z);
                FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.3F, 0.0F, FX_RANGE);
                sendQuasar(level, LIGHTNING_IMPACT, impact);
                damageAround(player, impact, hitRadius, damage, 0.3F, 0);
                level.playSound(null, x, y, z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                        SoundSource.PLAYERS, 0.8F, 0.7F);
            });
        }
        return true;
    }

    /** L3 Kometenschlag: one giant comet after a short telegraph. */
    private static boolean castKometenschlag(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 32.0F));
        int telegraph = (int) power.param("telegraphTicks", 20.0F);
        float damage = power.param("damage", 12.0F);
        float radius = power.param("radius", 5.0F);
        float knockback = power.param("knockback", 1.4F);

        level.sendParticles(ParticleTypes.END_ROD, target.x, target.y + 0.4D, target.z,
                24, radius * 0.35D, 0.2D, radius * 0.35D, 0.02D);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        WandTickService.schedule(level, telegraph, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, target, 1.0F, 1.0F, FX_RANGE + 32.0D);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, target, 0.8F, 16.0F, FX_RANGE);
            sendQuasar(level, LIGHTNING_IMPACT, target);
            damageAround(player, target, radius, damage, knockback, 0);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.LIGHTNING_BOLT_THUNDER,
                    SoundSource.PLAYERS, 1.0F, 1.1F);
        });
        return true;
    }

    // ------------------------------------------------------------------ shared helpers

    /** The wand in the player's main or off hand (main hand wins), or null. */
    static ItemStack findHeldWand(ServerPlayer player) {
        ItemStack main = player.getMainHandItem();
        if (main.getItem() instanceof EclipseWandItem) {
            return main;
        }
        ItemStack off = player.getOffhandItem();
        return off.getItem() instanceof EclipseWandItem ? off : null;
    }

    /** Kill-bonus hook ({@code WandEvents}): flat wand XP when a held, owned wand watches a kill. */
    public static void handleKill(ServerPlayer killer) {
        ItemStack stack = findHeldWand(killer);
        if (stack == null || !WandSoulbind.isOwner(killer, stack)) {
            return;
        }
        awardXp(killer, stack, WandConfig.get().xp().killBonus());
    }

    /** Aimed point: block hit along the look ray, or the max-range point in the air. */
    static Vec3 aimPoint(ServerPlayer player, double range) {
        Vec3 eye = player.getEyePosition();
        Vec3 end = eye.add(player.getLookAngle().scale(range));
        HitResult hit = player.serverLevel().clip(new ClipContext(eye, end,
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
        return hit.getType() == HitResult.Type.MISS ? end : hit.getLocation();
    }

    /**
     * AoE damage helper: hurts living entities around {@code center} (never the caster,
     * never anyone standing inside a spawn-protection zone), with radial knockback and
     * optional fire ticks. Kill credit goes to the caster so kill XP flows.
     */
    static void damageAround(ServerPlayer caster, Vec3 center, float radius, float damage,
            float knockback, int fireTicks) {
        ServerLevel level = caster.serverLevel();
        List<LivingEntity> victims = level.getEntitiesOfClass(LivingEntity.class,
                new AABB(center, center).inflate(radius),
                e -> e != caster && e.isAlive() && e.position().distanceTo(center) <= radius);
        for (LivingEntity victim : victims) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            victim.hurt(caster.damageSources().indirectMagic(caster, caster), damage);
            if (fireTicks > 0) {
                victim.setRemainingFireTicks(Math.max(victim.getRemainingFireTicks(), fireTicks));
            }
            if (knockback > 0.0F) {
                Vec3 away = victim.position().subtract(center);
                Vec3 flat = new Vec3(away.x, 0.0D, away.z);
                Vec3 dir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : Vec3.ZERO;
                victim.push(dir.x * knockback * 0.5D, 0.25D * knockback, dir.z * knockback * 0.5D);
            }
        }
    }

    /** One-shot quasar emitter broadcast near a position (client budget law applies). */
    static void sendQuasar(ServerLevel level, ResourceLocation emitterId, Vec3 pos) {
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, FX_RANGE,
                new S2CQuasarPayload(emitterId, pos));
    }
}
