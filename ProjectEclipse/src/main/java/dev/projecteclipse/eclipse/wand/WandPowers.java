package dev.projecteclipse.eclipse.wand;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.protection.SpawnProtectionRules;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
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
 *
 * <p><b>D10 FX identity law (visuals/audio only — numbers untouched):</b> every path
 * composes its own emitters and voice — RISS = voxel-dissolve cubes + datamosh shimmer +
 * digital chirps, GLUT = ember bursts + ground scorch decals + bass whooshes, STERN =
 * starfall streaks + light pillars + crystal chimes. Every cast fires an anticipation hand
 * flourish ({@code <path>_cast_hand}) and a caster-only 0.06 camera tick; big payoffs add a
 * small {@code S2CShakePayload} for bystanders. The one-shot {@code wand_awakening} music
 * sting rides the first soulbind (path lock) in {@link #handleChoosePath}.</p>
 */
public final class WandPowers {
    /** In-memory per-player cooldowns: uuid → (power key → gameTime the power frees up). */
    private static final Map<UUID, Map<String, Long>> COOLDOWNS = new HashMap<>();

    /** FX broadcast radius for one-shot cues. */
    private static final double FX_RANGE = 64.0D;

    // One-shot quasar emitters (all loop:false — never dispatch looping ids via payload).
    private static final ResourceLocation UNLOCK_BURST = emitter("unlock_burst");

    // D10 FX rework — one distinct Quasar composition per path (assets/eclipse/quasar/emitters/).
    // RISS (glitch/void, 0xB98CFF): voxel-dissolve cubes, datamosh shimmer, digital chirps.
    static final ResourceLocation RISS_CAST_HAND = emitter("riss_cast_hand");
    private static final ResourceLocation RISS_BLINK_TEAR = emitter("riss_blink_tear");
    static final ResourceLocation RISS_WAVE_FRONT = emitter("riss_wave_front");
    private static final ResourceLocation RISS_SCHLAG_MAW = emitter("riss_schlag_maw");
    // GLUT (ember/magma, 0xFF7B3C): ember bursts, ground scorch decals, bass whooshes.
    static final ResourceLocation GLUT_CAST_HAND = emitter("glut_cast_hand");
    private static final ResourceLocation GLUT_STOSS_LANCE = emitter("glut_stoss_lance");
    static final ResourceLocation GLUT_WELLE_RING = emitter("glut_welle_ring");
    static final ResourceLocation GLUT_SPRUNG_CRATER = emitter("glut_sprung_crater");
    // STERN (starlight, 0xBFD9FF/gold): starfall streaks, light pillars, crystal chimes.
    static final ResourceLocation STERN_CAST_HAND = emitter("stern_cast_hand");
    static final ResourceLocation STERN_FUNKE_FALL = emitter("stern_funke_fall");
    private static final ResourceLocation STERN_SCHAUER_FIELD = emitter("stern_schauer_field");
    private static final ResourceLocation STERN_KOMET_CORE = emitter("stern_komet_core");

    private WandPowers() {}

    private static ResourceLocation emitter(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name);
    }

    /** Server-stop reset (singleplayer relaunch safety). */
    public static void clearRuntime() {
        COOLDOWNS.clear();
    }

    /**
     * FFIX-B (POLISH-SOL-03): basic actor-state gate for every C2S wand entry point. A
     * modified client can send cast/choose packets while dead, mid-removal or in spectator
     * — none of which can reach the normal item-use path. Allowed game modes are exactly
     * the hand-interaction ones: survival, creative and adventure; spectator is rejected.
     * Rejections are SILENT (no message/sound) so forged packets cannot spam feedback.
     */
    private static boolean isActorValid(ServerPlayer player) {
        return player.isAlive() && !player.isRemoved() && !player.isSpectator();
    }

    // ------------------------------------------------------------------ payload entry points

    /** {@code C2SWandCastPayload} handler — the ONLY way a power executes. */
    public static void handleCast(ServerPlayer player, boolean mainHand) {
        if (!isActorValid(player)) {
            return; // forged/stale request from a dead, removed or spectator client
        }
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
        castFlourish(player, path, mainHand);
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
        if (!isActorValid(player)) {
            return; // same actor-state gate as casting (POLISH-SOL-03)
        }
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
        sendQuasar(player.serverLevel(), castHandEmitter(chosen),
                player.position().add(0.0D, 1.3D, 0.0D));
        player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.BEACON_ACTIVATE, SoundSource.PLAYERS, 0.9F, 1.3F);
        // D10 seam (W-MUSIC): first soulbind = the path lock — the private ~60 s
        // wand_awakening sting plays exactly once per player (a path can never return to
        // NONE outside dev edits). MusicCues validates the id and self-expires client-side.
        MusicCues.play("wand_awakening", player);
        player.displayClientMessage(Component.translatable("wand.eclipse.msg.awakening"), true);
        player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.path_chosen",
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
        player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.levelup", level,
                Component.translatable(path.powerLangKey(level - 1))));
    }

    /** Three staggered {@code unlock_burst} pops around a position (level-up / awaken cue). */
    private static void celebrationBurst(ServerLevel level, Vec3 center) {
        sendQuasar(level, UNLOCK_BURST, center);
        WandTickService.schedule(level, 4, () -> sendQuasar(level, UNLOCK_BURST, center.add(0.7D, 0.4D, -0.4D)));
        WandTickService.schedule(level, 8, () -> sendQuasar(level, UNLOCK_BURST, center.add(-0.6D, 0.7D, 0.5D)));
    }

    // ------------------------------------------------------------------ D10 cast feel layer

    /** The per-path hand-flourish emitter id. */
    private static ResourceLocation castHandEmitter(WandPath path) {
        return switch (path) {
            case GLUT -> GLUT_CAST_HAND;
            case STERN -> STERN_CAST_HAND;
            default -> RISS_CAST_HAND;
        };
    }

    /**
     * Cast anticipation flash (D10): a per-path hand flourish at the casting hand, a short
     * path-voiced chirp/crackle/chime, and a barely-there caster-only camera tick. Fired on
     * every SUCCESSFUL cast so the paths read distinct before the power's own FX land.
     * Purely audiovisual — the client {@code FxBudget} caps the emitter, and the shake is a
     * 0.06-strength 5-tick impulse (well inside the reducedFx-halved budget conventions).
     */
    private static void castFlourish(ServerPlayer player, WandPath path, boolean mainHand) {
        ServerLevel level = player.serverLevel();
        Vec3 look = player.getLookAngle();
        Vec3 flat = new Vec3(look.x, 0.0D, look.z);
        Vec3 side = flat.lengthSqr() > 1.0E-4D
                ? new Vec3(-flat.z, 0.0D, flat.x).normalize().scale(mainHand ? 0.35D : -0.35D)
                : Vec3.ZERO;
        Vec3 hand = player.getEyePosition().add(look.scale(0.55D)).add(side).add(0.0D, -0.25D, 0.0D);
        sendQuasar(level, castHandEmitter(path), hand);
        switch (path) {
            case RISS -> level.playSound(null, hand.x, hand.y, hand.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.35F, 1.7F);
            case GLUT -> level.playSound(null, hand.x, hand.y, hand.z,
                    SoundEvents.FIRECHARGE_USE, SoundSource.PLAYERS, 0.3F, 0.65F);
            case STERN -> level.playSound(null, hand.x, hand.y, hand.z,
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.45F, 1.85F);
            default -> { }
        }
        PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.06F, 5));
    }

    /** Impact-payoff camera feedback for everyone close to {@code pos} (small by design). */
    private static void shakeNear(ServerLevel level, Vec3 pos, double range, float strength, int ticks) {
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, range,
                S2CShakePayload.shake(strength, ticks));
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

    /**
     * L1 Blink: short glitch teleport along the look ray through a fist-sized tear.
     *
     * <p>D10 composition: two mirrored voxel-dissolve shard-implosions ({@code
     * riss_blink_tear}, cube render-style datamosh) at from/to over a NARROW rift pair,
     * a delayed second tear at the arrival point (the "re-rez" shimmer), digital chirps
     * (border-glitch static + pitched teleport crack) and a private camera tick.</p>
     */
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
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxFrom, 1.3F, 1.0F, FX_RANGE);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxTo, 1.3F, 1.0F, FX_RANGE);
        sendQuasar(level, RISS_BLINK_TEAR, fxFrom);
        sendQuasar(level, RISS_BLINK_TEAR, fxTo);
        // Arrival re-rez: a second tear + chirp two ticks late reads as the body knitting in.
        WandTickService.schedule(level, 2, () -> {
            sendQuasar(level, RISS_BLINK_TEAR, fxTo);
            level.playSound(null, fxTo.x, fxTo.y, fxTo.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.5F, 1.55F);
        });
        WandTickService.schedule(level, 12, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxFrom, 0.0F, 0.0F, FX_RANGE);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxTo, 0.0F, 0.0F, FX_RANGE);
        });
        player.teleportTo(target.x, target.y, target.z);
        player.resetFallDistance();
        level.playSound(null, from.x, from.y, from.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.7F, 1.55F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.7F, 0.85F);
        PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.09F, 7));
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

    /**
     * L3 Rissschlag: a portal-style tear bursts open on the aimed point and lashes out.
     *
     * <p>D10 composition: the rift IS the maw — {@code riss_schlag_maw} (inward-sucked
     * debris streaks around the lips) fires with the tear, a second gulp follows two ticks
     * later, and the bite lands with a crushed static "CHOMP" (low border-glitch burst +
     * shattering chirp) plus a short shared camera hit for everyone standing close.</p>
     */
    private static boolean castRissschlag(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 24.0F)).add(0.0D, 1.2D, 0.0D);
        float width = power.param("width", 5.0F);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, target, width, 1.0F, FX_RANGE);
        sendQuasar(level, RISS_SCHLAG_MAW, target);
        WandTickService.schedule(level, 2, () -> sendQuasar(level, RISS_SCHLAG_MAW, target));
        WandTickService.schedule(level, (int) power.param("openTicks", 25.0F), () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, target, 0.0F, 0.0F, FX_RANGE);
            sendQuasar(level, RISS_BLINK_TEAR, target); // the maw snaps shut on itself
            level.playSound(null, target.x, target.y, target.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.45F, 1.3F);
        });
        damageAround(player, target, power.param("radius", 4.0F), power.param("damage", 8.0F),
                power.param("knockback", 1.1F), 0);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 0.6F, 1.7F);
        level.playSound(null, target.x, target.y, target.z,
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.8F, 0.75F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.PLAYERS, 0.7F, 0.6F);
        shakeNear(level, target, 20.0D, 0.22F, 9);
        return true;
    }

    // ------------------------------------------------------------------ Glutherz (GLUT)

    /**
     * L1 Glutstoß: short fire dart — first living thing on the ray burns.
     *
     * <p>D10 composition: the flat FLAME march is gone — the dart is a compressed ember
     * lance ({@code glut_stoss_lance}) marched origin → midpoint → impact over three ticks
     * with a sparse heat-shimmer trail, a bass whoosh on release and a lava-splash payoff
     * where it lands.</p>
     */
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
            if (((int) (dist * 2.0D)) % 3 == 0) {
                // Heat shimmer, not a flame hose: one small flame every ~1.5 blocks.
                level.sendParticles(ParticleTypes.SMALL_FLAME, point.x, point.y, point.z,
                        1, 0.05D, 0.05D, 0.05D, 0.004D);
            }
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
        Vec3 mid = eye.add(look.scale(Math.max(1.0D, victimDist * 0.5D)));
        sendQuasar(level, GLUT_STOSS_LANCE, eye.add(look.scale(1.2D)).add(0.0D, -0.15D, 0.0D));
        WandTickService.schedule(level, 1, () -> sendQuasar(level, GLUT_STOSS_LANCE, mid));
        boolean hitSomething = victim != null;
        WandTickService.schedule(level, 2, () -> {
            sendQuasar(level, GLUT_STOSS_LANCE, impact);
            level.playSound(null, impact.x, impact.y, impact.z, SoundEvents.FIRE_EXTINGUISH,
                    SoundSource.PLAYERS, 0.5F, hitSomething ? 0.7F : 1.1F);
        });
        if (victim != null) {
            victim.hurt(player.damageSources().indirectMagic(player, player), power.param("damage", 5.0F));
            victim.igniteForSeconds((int) power.param("fireSeconds", 3.0F));
            level.sendParticles(ParticleTypes.LAVA, impact.x, impact.y, impact.z, 4, 0.2D, 0.2D, 0.2D, 0.0D);
        }
        level.sendParticles(ParticleTypes.SMALL_FLAME, impact.x, impact.y, impact.z, 8, 0.25D, 0.25D, 0.25D, 0.02D);
        // Bass whoosh: low-pitched firecharge under a blaze bark.
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.FIRECHARGE_USE, SoundSource.PLAYERS, 0.8F, 0.55F);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.BLAZE_SHOOT, SoundSource.PLAYERS, 0.4F, 0.7F);
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
        // D10 ignition beat: a magma crescent erupts at the caster before the ring rolls out
        // (the marching front FX + scorch decals live in WandTickService.FireWave).
        sendQuasar(level, GLUT_WELLE_RING, center.add(0.0D, 0.2D, 0.0D));
        WandTickService.startFireWave(player, center,
                power.param("radius", 12.0F), expandTicks, power.param("damage", 7.0F),
                (int) (power.param("fireSeconds", 3.0F) * 20.0F), power.param("knockup", 0.42F));
        // Bass whoosh stack: sub-pitched firecharge + blaze roar + a soft distant boom.
        level.playSound(null, center.x, center.y, center.z, SoundEvents.FIRECHARGE_USE,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.BLAZE_SHOOT,
                SoundSource.PLAYERS, 0.9F, 0.6F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.GENERIC_EXPLODE.value(),
                SoundSource.PLAYERS, 0.35F, 0.55F);
        shakeNear(level, center, 24.0D, 0.18F, 10);
        return true;
    }

    /**
     * L3 Magmasprung: fiery leap; the landing slam is tracked by {@link WandTickService}.
     *
     * <p>D10 composition: launch = ember crater burst ({@code glut_sprung_crater}) + a
     * scorched take-off decal + bass whoosh; the airborne ember contrail and the
     * lava-splash landing payoff (crater emitter, scorch decal, boom, shared shake) live
     * in {@code WandTickService.MagmaJump}.</p>
     */
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
        Vec3 feet = player.position();
        sendQuasar(level, GLUT_SPRUNG_CRATER, feet);
        WandTickService.spawnScorchDecal(level, feet, 1.1F, 100);
        level.sendParticles(ParticleTypes.FLAME, feet.x, feet.y, feet.z,
                14, 0.4D, 0.1D, 0.4D, 0.05D);
        // Launch bass whoosh: low blaze bark over a sub-pitched firecharge.
        level.playSound(null, feet.x, feet.y, feet.z,
                SoundEvents.BLAZE_SHOOT, SoundSource.PLAYERS, 0.9F, 0.55F);
        level.playSound(null, feet.x, feet.y, feet.z,
                SoundEvents.FIRECHARGE_USE, SoundSource.PLAYERS, 0.6F, 0.5F);
        return true;
    }

    // ------------------------------------------------------------------ Sternenfall (STERN)

    /**
     * L1 Funkenruf: a single spark from the dark sky onto the aimed point.
     *
     * <p>D10 composition: the generic lightning-impact pop is gone — a thin silver ribbon
     * (strike intensity 0.35) delivers a needle starfall streak with a short light pillar
     * ({@code stern_funke_fall} spawned raised + at ground, the descending column reads as
     * the star burying itself), crystal chimes instead of thunder.</p>
     */
    private static boolean castFunkenruf(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 32.0F));
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, target, 0.35F, 0.0F, FX_RANGE);
        sendQuasar(level, STERN_FUNKE_FALL, target.add(0.0D, 1.8D, 0.0D));
        WandTickService.schedule(level, 2,
                () -> sendQuasar(level, STERN_FUNKE_FALL, target.add(0.0D, 0.3D, 0.0D)));
        damageAround(player, target, power.param("radius", 2.0F), power.param("damage", 5.0F), 0.4F, 0);
        // Sender owns audio (strikeLightning contract) — crystal chimes, not thunder.
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 0.9F, 1.6F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.PLAYERS, 0.7F, 1.25F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.LIGHTNING_BOLT_IMPACT,
                SoundSource.PLAYERS, 0.35F, 1.8F);
        shakeNear(level, target, 14.0D, 0.1F, 6);
        return true;
    }

    /**
     * L2 Sternschauer: the star shower — telegraphed zone, then N falling stars rain over
     * it. Scheduling on {@link WandTickService}.
     *
     * <p>D10 composition: the telegraph is a rotating constellation ring ({@code
     * stern_schauer_field} re-pulsed at the halfway beat, its vortex module orbits the
     * motes) over the end-rod warning ring; each star is a 0.15-intensity silver ribbon +
     * a {@code stern_funke_fall} starfall streak, chimed at a rising random pitch; the
     * last star lands with a resonate payoff.</p>
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

        // Telegraph: a quiet ring of end-rod motes so targets get their 1.5 s warning,
        // crowned by the rotating constellation ring.
        for (int i = 0; i < 16; i++) {
            double angle = i * Math.PI * 2.0D / 16.0D;
            level.sendParticles(ParticleTypes.END_ROD,
                    zone.x + Math.cos(angle) * zoneRadius, zone.y + 0.3D, zone.z + Math.sin(angle) * zoneRadius,
                    1, 0.05D, 0.1D, 0.05D, 0.01D);
        }
        sendQuasar(level, STERN_SCHAUER_FIELD, zone.add(0.0D, 0.6D, 0.0D));
        WandTickService.schedule(level, Math.max(1, telegraph / 2),
                () -> sendQuasar(level, STERN_SCHAUER_FIELD, zone.add(0.0D, 0.6D, 0.0D)));
        level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.0F, 0.6F);
        level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 0.7F, 1.4F);

        for (int i = 0; i < count; i++) {
            int delay = telegraph + (i * duration) / count;
            boolean last = i == count - 1;
            float chimePitch = 1.1F + 0.6F * (i / (float) Math.max(1, count - 1));
            WandTickService.schedule(level, delay, () -> {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double dist = Math.sqrt(level.random.nextDouble()) * zoneRadius;
                double x = zone.x + Math.cos(angle) * dist;
                double z = zone.z + Math.sin(angle) * dist;
                double y = level.getHeight(Heightmap.Types.MOTION_BLOCKING, (int) Math.floor(x), (int) Math.floor(z));
                Vec3 impact = new Vec3(x, y, z);
                // Thin silver ribbon (0.15) + the starfall needle reading as a light pillar.
                FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.15F, 0.0F, FX_RANGE);
                sendQuasar(level, STERN_FUNKE_FALL, impact.add(0.0D, 1.6D, 0.0D));
                damageAround(player, impact, hitRadius, damage, 0.3F, 0);
                level.playSound(null, x, y, z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                        SoundSource.PLAYERS, 0.8F, chimePitch + level.random.nextFloat() * 0.1F);
                if (last) {
                    level.playSound(null, x, y, z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                            SoundSource.PLAYERS, 0.9F, 0.9F);
                    shakeNear(level, impact, 18.0D, 0.12F, 7);
                }
            });
        }
        return true;
    }

    /**
     * L3 Kometenschlag: one giant comet after a short telegraph.
     *
     * <p>D10 composition: the telegraph is a rotating constellation ring; the comet itself
     * exists — a huge trailing head ({@code stern_komet_core}) steps down the sky in two
     * descent beats before the impact tick, which lands as a giant strike + shockwave +
     * afterglow dome + light pillar with layered thunder/deep-chime audio and a real (but
     * still small) shared camera hit. Damage timing is UNCHANGED (impact at telegraph).</p>
     */
    private static boolean castKometenschlag(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 32.0F));
        int telegraph = (int) power.param("telegraphTicks", 20.0F);
        float damage = power.param("damage", 12.0F);
        float radius = power.param("radius", 5.0F);
        float knockback = power.param("knockback", 1.4F);

        level.sendParticles(ParticleTypes.END_ROD, target.x, target.y + 0.4D, target.z,
                24, radius * 0.35D, 0.2D, radius * 0.35D, 0.02D);
        sendQuasar(level, STERN_SCHAUER_FIELD, target.add(0.0D, 0.6D, 0.0D));
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 0.8F, 0.6F);

        // Descent beats: the comet head visibly falls (sky → mid) before the payoff tick.
        WandTickService.schedule(level, Math.max(1, telegraph - 8),
                () -> sendQuasar(level, STERN_KOMET_CORE, target.add(0.0D, 18.0D, 0.0D)));
        WandTickService.schedule(level, Math.max(2, telegraph - 4), () -> {
            sendQuasar(level, STERN_KOMET_CORE, target.add(0.0D, 9.0D, 0.0D));
            level.playSound(null, target.x, target.y + 9.0D, target.z,
                    SoundEvents.ELYTRA_FLYING, SoundSource.PLAYERS, 0.5F, 1.6F);
        });
        WandTickService.schedule(level, telegraph, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, target, 1.0F, 1.0F, FX_RANGE + 32.0D);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, target, 0.9F, 16.0F, FX_RANGE);
            sendQuasar(level, STERN_KOMET_CORE, target); // afterglow dome
            sendQuasar(level, STERN_FUNKE_FALL, target.add(0.0D, 2.2D, 0.0D)); // light pillar
            damageAround(player, target, radius, damage, knockback, 0);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.LIGHTNING_BOLT_THUNDER,
                    SoundSource.PLAYERS, 1.0F, 1.05F);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.PLAYERS, 1.0F, 0.55F);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                    SoundSource.PLAYERS, 0.9F, 0.8F);
            shakeNear(level, target, 32.0D, 0.4F, 13);
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
