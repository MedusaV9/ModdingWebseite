package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
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
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
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

    // D11 FX residue layer — every path now LEAVES something behind (visuals/audio only):
    // RISS scars reality, GLUT sheds ash + heat, STERN writes tiny star maps.
    static final ResourceLocation RISS_SEAM_SCAR = emitter("riss_seam_scar");
    private static final ResourceLocation RISS_MAW_SHIMMER = emitter("riss_maw_shimmer");
    private static final ResourceLocation GLUT_ASH_FLAKES = emitter("glut_ash_flakes");
    static final ResourceLocation GLUT_HEAT_COLUMN = emitter("glut_heat_column");
    private static final ResourceLocation STERN_CONSTELLATION = emitter("stern_constellation");
    // D11 soulbind ceremony (path-agnostic): converging white orbit + one white flash.
    private static final ResourceLocation SOULBIND_ORBIT = emitter("wand_soulbind_orbit");
    private static final ResourceLocation SOULBIND_FLASH = emitter("wand_soulbind_flash");

    private WandPowers() {}

    private static ResourceLocation emitter(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name);
    }

    /** Server-stop reset (singleplayer relaunch safety). */
    public static void clearRuntime() {
        COOLDOWNS.clear();
    }

    /** Read view of one player's live cooldowns (power key → ready-at game time) for the sync. */
    static Map<String, Long> cooldownsOf(UUID uuid) {
        return COOLDOWNS.getOrDefault(uuid, Map.of());
    }

    /**
     * FFIX-B (POLISH-SOL-03): basic actor-state gate for every C2S wand entry point. A
     * modified client can send cast/choose packets while dead, mid-removal or in spectator
     * — none of which can reach the normal item-use path. Allowed game modes are exactly
     * the hand-interaction ones: survival, creative and adventure; spectator is rejected.
     * Rejections are SILENT (no message/sound) so forged packets cannot spam feedback.
     *
     * <p>WANDFIX-7: cutscene-frozen players ({@code FreezeService.isFrozen}) are rejected
     * here too. The freeze cancels {@code PlayerInteractEvent}s, but the wand's C2S
     * payloads never pass through those events — without this gate a frozen player (or a
     * client that fires the payload directly) could cast from EITHER hand mid-scene.</p>
     */
    private static boolean isActorValid(ServerPlayer player) {
        return player.isAlive() && !player.isRemoved() && !player.isSpectator()
                && !FreezeService.isFrozen(player);
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
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.disabled",
                    (store.disabledRemainingSeconds() + 59L) / 60L), true);
            EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_STALL);
            return;
        }
        WandSoulbind.tick(player, stack); // conversion/claim races resolve before validation
        if (!WandSoulbind.isOwner(player, stack)) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.not_owner"), true);
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
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.cooldown",
                    Component.translatable(path.powerLangKey(selected)),
                    String.format("%.1f", (readyAt - now) / 20.0D)), true);
            return;
        }
        // WANDFIX-4: cost/cooldown honor the wand-branch skill nodes (WandPerks caps them).
        int cost = WandPerks.effectiveCost(player, power);
        int charge = stack.getOrDefault(WandItems.WAND_CHARGE.get(), 0);
        if (charge < cost) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.no_charge",
                    cost, charge), true);
            EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_STALL);
            player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.6F, 0.5F);
            return;
        }
        if (SpawnProtectionRules.isInProtectionZone(player.level(), player.blockPosition())
                && !SpawnProtectionRules.isExempt(player)) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.protected"), true);
            return;
        }

        if (!execute(player, stack, path, selected, power)) {
            return; // refused (e.g. blink found no room) — no cost, no cooldown
        }
        castFlourish(player, path, mainHand, power);
        // W18 Herz des Schleiers: a free cast skips only the charge — cooldown and XP flow.
        if (!WandPerks.rollFreeCast(player)) {
            stack.set(WandItems.WAND_CHARGE.get(), charge - cost);
        }
        COOLDOWNS.computeIfAbsent(player.getUUID(), id -> new HashMap<>())
                .put(key, now + WandPerks.effectiveCooldownTicks(player, power));
        EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_USE);
        WandConfig.Xp xp = WandConfig.get().xp();
        awardXp(player, stack, cost * xp.perCostPoint());
        SkillsApi.addXp(player, "wand", cost * xp.skillXpPerCostPoint());
        // V6-FIXWIRE #5: xp + the just-armed cooldown reach the client's panel this tick.
        WandProgressSync.syncTo(player);
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
        // D11 first-bind ceremony: white wisps spiral inward and converge into the wand
        // over ~1 s (two orbit pulses), then ONE white flash pops on the same tick the
        // wand_awakening sting starts — flash and musical downbeat land together. The
        // ceremony is path-agnostic white; the path's own cast-hand flourish rides the
        // flash beat so the chosen color is the first thing seen after the white.
        ServerLevel ceremonyLevel = player.serverLevel();
        sendQuasar(ceremonyLevel, SOULBIND_ORBIT, player.position().add(0.0D, 1.3D, 0.0D));
        ceremonyLevel.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.PLAYERS, 0.7F, 1.35F);
        WandTickService.schedule(ceremonyLevel, 7, () -> sendQuasar(ceremonyLevel,
                SOULBIND_ORBIT, player.position().add(0.0D, 1.3D, 0.0D)));
        WandTickService.schedule(ceremonyLevel, 18, () -> {
            if (player.hasDisconnected()) {
                return; // ceremony evaporates quietly; the sting stays unplayed until relog casts
            }
            Vec3 wandPos = player.position().add(0.0D, 1.3D, 0.0D);
            sendQuasar(ceremonyLevel, SOULBIND_FLASH, wandPos);
            sendQuasar(ceremonyLevel, castHandEmitter(chosen), wandPos);
            celebrationBurst(ceremonyLevel, player.position().add(0.0D, 1.0D, 0.0D));
            ceremonyLevel.playSound(null, player.getX(), player.getY(), player.getZ(),
                    SoundEvents.BEACON_ACTIVATE, SoundSource.PLAYERS, 0.9F, 1.3F);
            // D10 seam (W-MUSIC): first soulbind = the path lock — the private ~60 s
            // wand_awakening sting plays exactly once per player (a path can never return
            // to NONE outside dev edits). MusicCues validates the id and self-expires
            // client-side. D11 moved it onto the flash tick for the timing sync.
            MusicCues.play("wand_awakening", player);
        });
        player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.awakening"), true);
        player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.path_chosen",
                Component.translatable(chosen.langKey())));
        WandProgressSync.syncTo(player);
    }

    /**
     * {@code C2SWandCyclePayload} handler (WANDFIX-3) — sneak-scroll power switching in
     * BOTH directions. Same validation ladder as casting: actor gate (includes the
     * WANDFIX-7 freeze check), held wand, ownership.
     */
    public static void handleCycle(ServerPlayer player, boolean forward) {
        if (!isActorValid(player)) {
            return; // forged/stale request, or frozen mid-cutscene (WANDFIX-7)
        }
        ItemStack stack = findHeldWand(player);
        if (stack == null) {
            return;
        }
        WandSoulbind.tick(player, stack);
        if (!WandSoulbind.isOwner(player, stack)) {
            return; // silent — a foreign wand gives no selection feedback either
        }
        cycleSelected(player, stack, forward ? 1 : -1);
    }

    /**
     * Cycles the selected power among the unlocked ones. Direction −1 steps backwards
     * (WANDFIX-3: sneak-scroll goes both ways; the legacy sneak-right-click stays a
     * forward step). The pitch of the click tracks the slot so cycling is audible too.
     */
    public static void cycleSelected(ServerPlayer player, ItemStack stack, int direction) {
        WandPath path = WandSoulbind.pathOf(stack);
        if (path == WandPath.NONE) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.pathless"), true);
            return;
        }
        int level = WandSoulbind.levelOf(stack);
        int selected = Math.floorMod(stack.getOrDefault(WandItems.WAND_SELECTED.get(), 0) + direction, level);
        stack.set(WandItems.WAND_SELECTED.get(), selected);
        WandConfig.Power power = WandConfig.get().power(path.powerKey(selected));
        player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.selected",
                Component.translatable(path.powerLangKey(selected)), power.cost()), true);
        player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.UI_BUTTON_CLICK.value(), SoundSource.PLAYERS, 0.35F,
                1.3F + 0.15F * selected);
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
        amount *= WandPerks.xpMultiplier(player); // WANDFIX-4 lore line (W13/W14)
        WandConfig.Xp config = WandConfig.get().xp();
        int xp = stack.getOrDefault(WandItems.WAND_XP.get(), 0) + Math.round(amount);
        int level = WandSoulbind.levelOf(stack);
        boolean firstSecondPower = level < 2; // WANDFIX-3: about to own a second power?
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
        if (firstSecondPower && level >= 2) {
            // WANDFIX-3: the moment a second power exists, teach the switch gesture once
            // (sneak-scroll cycles both ways; sneak-right-click still steps forward).
            player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.cycle_hint"));
        }
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
     *
     * <p>D11 weight scaling: the wand casts on an instant click (no hold-time exists in the
     * cast flow — {@code EclipseWandItem#use} sends the payload immediately), so the one
     * intensity signal available is the cast's CHARGE COST. Heavy payoffs (cost ≥
     * {@value #HEAVY_CAST_COST}) get a second flourish pop a tick later just above the hand
     * and a slightly firmer (still caster-only) camera tick; cheap spam casts stay
     * feather-light.</p>
     */
    private static final int HEAVY_CAST_COST = 30;

    private static void castFlourish(ServerPlayer player, WandPath path, boolean mainHand,
            WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 look = player.getLookAngle();
        Vec3 flat = new Vec3(look.x, 0.0D, look.z);
        Vec3 side = flat.lengthSqr() > 1.0E-4D
                ? new Vec3(-flat.z, 0.0D, flat.x).normalize().scale(mainHand ? 0.35D : -0.35D)
                : Vec3.ZERO;
        Vec3 hand = player.getEyePosition().add(look.scale(0.55D)).add(side).add(0.0D, -0.25D, 0.0D);
        sendQuasar(level, castHandEmitter(path), hand);
        boolean heavy = power.cost() >= HEAVY_CAST_COST;
        if (heavy) {
            // Second pop rides one tick behind, slightly above — reads as the flourish
            // SWELLING for the big spells rather than a separate effect.
            WandTickService.schedule(level, 1,
                    () -> sendQuasar(level, castHandEmitter(path), hand.add(0.0D, 0.28D, 0.0D)));
        }
        switch (path) {
            case RISS -> level.playSound(null, hand.x, hand.y, hand.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS,
                    heavy ? 0.45F : 0.35F, heavy ? 1.5F : 1.7F);
            case GLUT -> level.playSound(null, hand.x, hand.y, hand.z,
                    SoundEvents.FIRECHARGE_USE, SoundSource.PLAYERS,
                    heavy ? 0.4F : 0.3F, heavy ? 0.55F : 0.65F);
            case STERN -> level.playSound(null, hand.x, hand.y, hand.z,
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS,
                    heavy ? 0.55F : 0.45F, heavy ? 1.7F : 1.85F);
            default -> { }
        }
        PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(heavy ? 0.08F : 0.06F, 5));
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
     *
     * <p>WANDFIX-2 Phasenschleier: for {@code veilTicks} after arrival the body hasn't
     * fully re-knit — Resistance II — turning the blink into a real dodge, not just a
     * hop.</p>
     */
    private static boolean castBlink(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 16.0F);
        Vec3 from = player.position();
        Vec3 target = findBlinkTarget(player, range);
        if (target == null) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.no_room"), true);
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
        // D11 afterimage doubling: a laterally offset ghost tear re-flickers at the
        // DEPARTURE point — for a beat the spot reads as two overlapping selves before
        // both dissolve.
        Vec3 look = player.getLookAngle();
        Vec3 doubling = new Vec3(-look.z, 0.0D, look.x);
        Vec3 ghost = fxFrom.add(doubling.lengthSqr() > 1.0E-4D
                ? doubling.normalize().scale(0.35D) : new Vec3(0.35D, 0.0D, 0.0D));
        WandTickService.schedule(level, 3, () -> sendQuasar(level, RISS_BLINK_TEAR, ghost));
        // D11 reality seams: thin glitch scars flicker for ~2 s where both tears opened,
        // then heal — the blink leaves a mark on the world instead of vanishing cleanly.
        WandTickService.schedule(level, 5, () -> {
            sendQuasar(level, RISS_SEAM_SCAR, fxFrom);
            sendQuasar(level, RISS_SEAM_SCAR, fxTo);
            level.playSound(null, fxFrom.x, fxFrom.y, fxFrom.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.22F, 1.95F);
        });
        WandTickService.schedule(level, 12, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxFrom, 0.0F, 0.0F, FX_RANGE);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxTo, 0.0F, 0.0F, FX_RANGE);
        });
        player.teleportTo(target.x, target.y, target.z);
        player.resetFallDistance();
        int veilTicks = (int) power.param("veilTicks", 30.0F);
        if (veilTicks > 0) {
            // Phasenschleier: half-re-rezzed for a beat — Resistance II, no icon spam.
            player.addEffect(new MobEffectInstance(MobEffects.DAMAGE_RESISTANCE, veilTicks, 1,
                    false, false, true));
        }
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
     *
     * <p>WANDFIX-2 mechanics: the maw now PULLS — everything living within 2× the bite
     * radius is dragged toward the lips before the teeth land ({@code pull}), so the AoE
     * groups its own targets. The L5 upgrade adds an echo bite ({@code echo} fraction of
     * the damage) 10 ticks later — the maw chews twice.</p>
     */
    private static boolean castRissschlag(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 24.0F)).add(0.0D, 1.2D, 0.0D);
        float width = power.param("width", 5.0F);
        float radius = power.param("radius", 4.5F);
        float damage = power.param("damage", 10.0F);
        float knockback = power.param("knockback", 1.2F);
        float pull = power.param("pull", 0.0F);
        float echo = power.param("echo", 0.0F);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, target, width, 1.0F, FX_RANGE);
        int openTicks = (int) power.param("openTicks", 25.0F);
        // PH-PLAYER (IDEAS-player #4): Photon implosion maw + Death sub-chain
        // (a = openTicks, informational). Sent BEFORE the maw payloads: payload order per
        // connection is guaranteed, so the client's retirement probe
        // (PhotonBridge.enhanceQuasarCue, PHOTON-QUALITY §6) sees the live Photon maw and
        // skips the Quasar maw emitter — emitter-only REPLACE; shimmer/blink-tear/seam-scar
        // dressing below stays LAYER. Photon-less clients: the probe never fires, every
        // Quasar beat plays — the unchanged baseline.
        FxPayloads.sendFxEvent(level, FxCues.CUE_RISS_SCHLAG, target, openTicks, 0.0F, FX_RANGE);
        sendQuasar(level, RISS_SCHLAG_MAW, target);
        WandTickService.schedule(level, 2, () -> sendQuasar(level, RISS_SCHLAG_MAW, target));
        if (openTicks >= 10) {
            // D11 pre-snap tell: the maw's lips shimmer (flickering ring, drifting inward)
            // and a thin rising chirp sounds ~6 ticks before the bite snaps shut. Pure
            // readability — the close timing itself is untouched.
            WandTickService.schedule(level, openTicks - 6, () -> {
                sendQuasar(level, RISS_MAW_SHIMMER, target);
                level.playSound(null, target.x, target.y, target.z,
                        EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.3F, 1.9F);
            });
        }
        WandTickService.schedule(level, openTicks, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, target, 0.0F, 0.0F, FX_RANGE);
            sendQuasar(level, RISS_BLINK_TEAR, target); // the maw snaps shut on itself
            // D11 reality seam: the snap leaves a glitch scar hanging where the maw was,
            // flickering out over ~2 s — reality closes badly here.
            WandTickService.schedule(level, 3, () -> sendQuasar(level, RISS_SEAM_SCAR, target));
            level.playSound(null, target.x, target.y, target.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.45F, 1.3F);
        });
        if (pull > 0.0F) {
            // The maw inhales first: everything in 2× the bite radius is dragged toward
            // the lips (inverse knockback), THEN the teeth land on the packed group.
            List<LivingEntity> dragged = level.getEntitiesOfClass(LivingEntity.class,
                    new AABB(target, target).inflate(radius * 2.0D),
                    e -> e != player && e.isAlive());
            for (LivingEntity victim : dragged) {
                if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                    continue;
                }
                Vec3 toMaw = target.subtract(victim.position());
                Vec3 flat = new Vec3(toMaw.x, 0.0D, toMaw.z);
                if (flat.lengthSqr() > 1.0E-4D) {
                    Vec3 dir = flat.normalize();
                    victim.push(dir.x * pull, 0.12D * pull, dir.z * pull);
                }
            }
        }
        damageAround(player, target, radius, damage, knockback, 0);
        if (echo > 0.0F) {
            // Echo bite: the maw chews a second time — half-weight damage + a second
            // gulp emitter so the double-hit reads on screen too.
            WandTickService.schedule(level, 10, () -> {
                sendQuasar(level, RISS_SCHLAG_MAW, target);
                damageAround(player, target, radius, damage * echo, knockback * 0.4F, 0);
                level.playSound(null, target.x, target.y, target.z,
                        EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.55F, 0.9F);
            });
        }
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
     *
     * <p>WANDFIX-2 pierce: the lance now burns THROUGH — up to {@code pierce} creatures
     * on the ray are hit and ignited instead of only the first, so a line of mobs is a
     * target, not a shield.</p>
     */
    private static boolean castGlutstoss(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 12.0F);
        int maxTargets = Math.max(1, (int) power.param("pierce", 1.0F));
        Vec3 eye = player.getEyePosition();
        Vec3 look = player.getLookAngle();
        HitResult blockHit = level.clip(new ClipContext(eye, eye.add(look.scale(range)),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
        double maxDist = blockHit.getType() == HitResult.Type.MISS ? range
                : blockHit.getLocation().distanceTo(eye);

        List<LivingEntity> victims = new ArrayList<>();
        double lastHitDist = maxDist;
        for (double dist = 1.0D; dist <= maxDist; dist += 0.5D) {
            Vec3 point = eye.add(look.scale(dist));
            if (((int) (dist * 2.0D)) % 3 == 0) {
                // Heat shimmer, not a flame hose: one small flame every ~1.5 blocks.
                level.sendParticles(ParticleTypes.SMALL_FLAME, point.x, point.y, point.z,
                        1, 0.05D, 0.05D, 0.05D, 0.004D);
            }
            if (victims.size() < maxTargets) {
                List<LivingEntity> hits = level.getEntitiesOfClass(LivingEntity.class,
                        new AABB(point, point).inflate(0.6D),
                        e -> e != player && e.isAlive() && !victims.contains(e));
                if (!hits.isEmpty()) {
                    victims.add(hits.get(0));
                    lastHitDist = dist;
                }
            }
        }
        Vec3 impact = eye.add(look.scale(victims.isEmpty() ? maxDist : lastHitDist));
        Vec3 mid = eye.add(look.scale(Math.max(1.0D, lastHitDist * 0.5D)));
        sendQuasar(level, GLUT_STOSS_LANCE, eye.add(look.scale(1.2D)).add(0.0D, -0.15D, 0.0D));
        WandTickService.schedule(level, 1, () -> sendQuasar(level, GLUT_STOSS_LANCE, mid));
        boolean hitSomething = !victims.isEmpty();
        WandTickService.schedule(level, 2, () -> {
            sendQuasar(level, GLUT_STOSS_LANCE, impact);
            level.playSound(null, impact.x, impact.y, impact.z, SoundEvents.FIRE_EXTINGUISH,
                    SoundSource.PLAYERS, 0.5F, hitSomething ? 0.7F : 1.1F);
        });
        // D11 ash fallout: the lance's wake sheds slow NON-glowing ash flakes (the one
        // alpha-blended GLUT emitter) that drift down for ~2 s at the midpoint and the
        // impact — the burn leaves residue, not just light. Soft crackle under the flakes.
        WandTickService.schedule(level, 4, () -> sendQuasar(level, GLUT_ASH_FLAKES, mid));
        WandTickService.schedule(level, 6, () -> {
            sendQuasar(level, GLUT_ASH_FLAKES, impact);
            level.playSound(null, impact.x, impact.y, impact.z,
                    SoundEvents.CAMPFIRE_CRACKLE, SoundSource.PLAYERS, 0.5F, 0.75F);
        });
        float damage = power.param("damage", 6.0F) * WandPerks.damageMultiplier(player);
        int fireSeconds = (int) power.param("fireSeconds", 4.0F);
        for (LivingEntity victim : victims) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            victim.hurt(player.damageSources().indirectMagic(player, player), damage);
            victim.igniteForSeconds(fireSeconds);
            level.sendParticles(ParticleTypes.LAVA, victim.getX(), victim.getY() + 0.8D,
                    victim.getZ(), 4, 0.2D, 0.2D, 0.2D, 0.0D);
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
     *
     * <p>WANDFIX-2 burn combo: targets that are ALREADY burning when the front reaches
     * them take {@code burnBonus}× — Glutstoß pre-burn feeds the wave. The L4 upgrade
     * marches a SECOND ring 12 ticks behind the first ({@code waves}), catching whatever
     * the knock-up drops back into the fire.</p>
     */
    private static boolean castFeuerwelle(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = player.position();
        int expandTicks = (int) power.param("expandTicks", 40.0F);
        float radius = power.param("radius", 12.0F);
        // Direct-hurt path (the ring hurts in WandTickService) — boost here, once.
        float damage = power.param("damage", 9.0F) * WandPerks.damageMultiplier(player);
        int fireTicks = (int) (power.param("fireSeconds", 4.0F) * 20.0F);
        float knockup = power.param("knockup", 0.42F);
        float burnBonus = power.param("burnBonus", 1.0F);
        int waves = Math.max(1, (int) power.param("waves", 1.0F));
        FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, center,
                1.2F, expandTicks, FX_RANGE + 32.0D);
        // D10 ignition beat: a magma crescent erupts at the caster before the ring rolls out
        // (the marching front FX + scorch decals live in WandTickService.FireWave).
        sendQuasar(level, GLUT_WELLE_RING, center.add(0.0D, 0.2D, 0.0D));
        WandTickService.startFireWave(player, center, radius, expandTicks, damage,
                fireTicks, knockup, burnBonus);
        if (waves > 1) {
            // Twin ring (L4): the echo wave re-rolls from the SAME center 12 ticks later
            // — the first ring ignites, the second collects the burn bonus.
            WandTickService.schedule(level, 12, () -> {
                sendQuasar(level, GLUT_WELLE_RING, center.add(0.0D, 0.2D, 0.0D));
                FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, center,
                        1.0F, expandTicks, FX_RANGE + 32.0D);
                WandTickService.startFireWave(player, center, radius, expandTicks, damage,
                        fireTicks, knockup, burnBonus);
                level.playSound(null, center.x, center.y, center.z, SoundEvents.BLAZE_SHOOT,
                        SoundSource.PLAYERS, 0.8F, 0.5F);
            });
        }
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
     *
     * <p>WANDFIX-2 mechanics: the launch wraps the caster in a fire veil
     * ({@code resistSeconds} of Fire Resistance — dive into your own flames). The L5
     * upgrade detonates an ember ring from the crater on touchdown
     * ({@code eruptRadius}/{@code eruptDamage}/{@code eruptFireSeconds}) — a
     * mini-Feuerwelle rolls out of the landing.</p>
     */
    private static boolean castMagmasprung(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float launch = power.param("launch", 1.3F);
        Vec3 look = player.getLookAngle();
        Vec3 flat = new Vec3(look.x, 0.0D, look.z);
        Vec3 dir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : Vec3.ZERO;
        player.setDeltaMovement(dir.scale(launch * 0.8D).add(0.0D, 0.9D * launch, 0.0D));
        player.hurtMarked = true; // force velocity sync to the client
        int resistSeconds = (int) power.param("resistSeconds", 5.0F);
        if (resistSeconds > 0) {
            // Fire veil: your own fire fields can't cook you mid-combo (no icon spam).
            player.addEffect(new MobEffectInstance(MobEffects.FIRE_RESISTANCE,
                    resistSeconds * 20, 0, false, false, true));
        }
        float boost = WandPerks.damageMultiplier(player); // direct-hurt path (MagmaJump)
        WandTickService.trackMagmaJump(player, power.param("damage", 8.0F) * boost,
                power.param("radius", 4.5F), power.param("knockback", 1.0F),
                (int) (power.param("fireSeconds", 2.0F) * 20.0F),
                power.param("eruptRadius", 0.0F), power.param("eruptDamage", 0.0F) * boost,
                (int) (power.param("eruptFireSeconds", 0.0F) * 20.0F));
        Vec3 feet = player.position();
        sendQuasar(level, GLUT_SPRUNG_CRATER, feet);
        // PH-PLAYER (IDEAS-player #5): Photon eruption with physics-bouncing chunks +
        // Collision/Death sub-emitters, ENTITY lane — the debris departs WITH the launch
        // (the landing re-send in WandTickService.MagmaJump reuses the same cue, b = 1).
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_GLUT_SPRUNG, player, 0.0F, 0.0F, FX_RANGE);
        WandTickService.spawnScorchDecal(level, feet, 1.1F, 100);
        // D11 take-off heat: a faint shimmer column stands over the launch scorch for a
        // second — the ground remembers the blast-off (landing gets the full treatment
        // in WandTickService.MagmaJump). +1.4 because the cylinder shape is
        // center-anchored (same convention as stern_funke_fall): base sits on the ground.
        WandTickService.schedule(level, 2,
                () -> sendQuasar(level, GLUT_HEAT_COLUMN, feet.add(0.0D, 1.4D, 0.0D)));
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
     *
     * <p>WANDFIX-2 Sternenmal: victims are stamped with Glowing for {@code markTicks} —
     * visible through walls, and every other STERN power deals its {@code markBonus}
     * against marked targets. Funkenruf is the cheap opener that feeds the whole path.</p>
     */
    private static boolean castFunkenruf(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 32.0F));
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, target, 0.35F, 0.0F, FX_RANGE);
        sendQuasar(level, STERN_FUNKE_FALL, target.add(0.0D, 1.8D, 0.0D));
        WandTickService.schedule(level, 2,
                () -> sendQuasar(level, STERN_FUNKE_FALL, target.add(0.0D, 0.3D, 0.0D)));
        // D11 micro-constellation: five near-static star points with hairline trails drift
        // apart over the impact — the lines connect-the-dots into a tiny star map that
        // twinkles for ~1.7 s, then fades. One high quiet chime marks it.
        WandTickService.schedule(level, 4, () -> {
            sendQuasar(level, STERN_CONSTELLATION, target.add(0.0D, 1.1D, 0.0D));
            level.playSound(null, target.x, target.y, target.z,
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.35F, 1.95F);
        });
        damageAround(player, target, power.param("radius", 2.5F), power.param("damage", 6.0F),
                0.4F, 0, 0.0F, 1.0F, 0, (int) power.param("markTicks", 100.0F));
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
     *
     * <p>WANDFIX-2 mechanics: every star hit dusts its victims with Slowness II for
     * {@code slowTicks} (Sternenstaub — the zone is now real area denial) and collects
     * the Sternenmal {@code markBonus} against Glowing targets. The L4 upgrade arms the
     * D11 finale pulse with {@code finaleDamage}: the synced re-light at the end DETONATES
     * across the whole zone instead of only shining.</p>
     */
    private static boolean castSternschauer(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 zone = aimPoint(player, power.param("range", 32.0F));
        float zoneRadius = power.param("zoneRadius", 8.0F);
        int telegraph = (int) power.param("telegraphTicks", 30.0F);
        int duration = (int) power.param("durationTicks", 60.0F);
        int count = Math.max(1, (int) power.param("count", 14.0F));
        float damage = power.param("damage", 6.0F);
        float hitRadius = power.param("hitRadius", 2.5F);
        int slowTicks = (int) power.param("slowTicks", 40.0F);
        float markBonus = power.param("markBonus", 1.25F);
        float finaleDamage = power.param("finaleDamage", 0.0F);

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

        List<Vec3> landed = new ArrayList<>();
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
                landed.add(impact); // remembered for the D11 synced-pillar finale
                // Thin silver ribbon (0.15) + the starfall needle reading as a light pillar.
                FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.15F, 0.0F, FX_RANGE);
                sendQuasar(level, STERN_FUNKE_FALL, impact.add(0.0D, 1.6D, 0.0D));
                damageAround(player, impact, hitRadius, damage, 0.3F, 0, 0.0F, markBonus, slowTicks, 0);
                level.playSound(null, x, y, z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                        SoundSource.PLAYERS, 0.8F, chimePitch + level.random.nextFloat() * 0.1F);
                if (last) {
                    level.playSound(null, x, y, z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                            SoundSource.PLAYERS, 0.9F, 0.9F);
                    shakeNear(level, impact, 18.0D, 0.12F, 7);
                }
            });
        }
        // D11 field finale: one synced pulse — every landed star's pillar re-lights AT
        // ONCE a beat after the last impact (sampled down to 6 pillars for the budget
        // law; reducedFx clients drop extras silently), over a single held resonate.
        // The shower now ENDS instead of trailing off. WANDFIX-2 (L4): with finaleDamage
        // armed the pulse also DETONATES — one zone-wide burst closes the shower.
        WandTickService.schedule(level, telegraph + duration + 6, () -> {
            if (landed.isEmpty()) {
                return;
            }
            int step = Math.max(1, landed.size() / 6);
            int pulsed = 0;
            for (int i = 0; i < landed.size() && pulsed < 6; i += step, pulsed++) {
                sendQuasar(level, STERN_FUNKE_FALL, landed.get(i).add(0.0D, 1.6D, 0.0D));
            }
            Vec3 heart = landed.get(landed.size() / 2);
            if (finaleDamage > 0.0F) {
                damageAround(player, zone, zoneRadius, finaleDamage, 0.0F, 0,
                        0.35F, markBonus, 0, 0);
                shakeNear(level, zone, 20.0D, 0.16F, 8);
            }
            level.playSound(null, heart.x, heart.y, heart.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.PLAYERS, 0.85F, 1.1F);
            level.playSound(null, heart.x, heart.y, heart.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.PLAYERS, 0.6F, 1.5F);
        });
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
     *
     * <p>WANDFIX-2 mechanics: the impact hurls victims SKYWARD ({@code knockup}) and
     * collects the Sternenmal {@code markBonus} against Glowing targets. The L5 upgrade
     * shatters — {@code splinters} shard-comets crash around the crater over the next
     * half-second ({@code splinterDamage} in {@code splinterRadius} each).</p>
     */
    private static boolean castKometenschlag(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = aimPoint(player, power.param("range", 32.0F));
        int telegraph = (int) power.param("telegraphTicks", 20.0F);
        float damage = power.param("damage", 16.0F);
        float radius = power.param("radius", 5.0F);
        float knockback = power.param("knockback", 1.5F);
        float knockup = power.param("knockup", 0.8F);
        float markBonus = power.param("markBonus", 1.25F);
        int splinters = (int) power.param("splinters", 0.0F);
        float splinterDamage = power.param("splinterDamage", 8.0F);
        float splinterRadius = power.param("splinterRadius", 3.0F);

        level.sendParticles(ParticleTypes.END_ROD, target.x, target.y + 0.4D, target.z,
                24, radius * 0.35D, 0.2D, radius * 0.35D, 0.02D);
        sendQuasar(level, STERN_SCHAUER_FIELD, target.add(0.0D, 0.6D, 0.0D));
        // PH-PLAYER (IDEAS-player #2): one cue at cast carries the telegraph in `a` — the
        // client spawns the real falling head + ribbon now and setDelay()s the HDR impact
        // bloom so it lands exactly on the damage tick below. The server keeps sending
        // every Quasar beat (photon-blind law); on Photon clients the retirement probe
        // (PhotonBridge.enhanceQuasarCue, PHOTON-QUALITY §6) suppresses the
        // stern_komet_core beats while the real fall/impact is live — two comet heads at
        // once read as double-vision. stern_funke_fall stays LAYER (complementary).
        FxPayloads.sendFxEvent(level, FxCues.CUE_STERN_KOMET, target, telegraph, 0.0F,
                FX_RANGE + 32.0D);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 0.8F, 0.6F);

        // Descent beats: the comet head visibly falls (sky → mid) before the payoff tick.
        // D11 impact herald: each beat also draws a GROWING light circle on the ground —
        // the landing zone brightens as the comet closes in (vanilla END_ROD rings, no
        // emitter budget), with a rising chime tracking the growth.
        WandTickService.schedule(level, Math.max(1, telegraph - 8), () -> {
            sendQuasar(level, STERN_KOMET_CORE, target.add(0.0D, 18.0D, 0.0D));
            groundLightRing(level, target, radius * 0.35D);
            level.playSound(null, target.x, target.y, target.z,
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.35F, 1.0F);
        });
        WandTickService.schedule(level, Math.max(2, telegraph - 4), () -> {
            sendQuasar(level, STERN_KOMET_CORE, target.add(0.0D, 9.0D, 0.0D));
            groundLightRing(level, target, radius * 0.6D);
            level.playSound(null, target.x, target.y + 9.0D, target.z,
                    SoundEvents.ELYTRA_FLYING, SoundSource.PLAYERS, 0.5F, 1.6F);
            level.playSound(null, target.x, target.y, target.z,
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.4F, 1.25F);
        });
        WandTickService.schedule(level, Math.max(3, telegraph - 1), () -> {
            groundLightRing(level, target, radius * 0.9D);
            level.playSound(null, target.x, target.y, target.z,
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.45F, 1.5F);
        });
        WandTickService.schedule(level, telegraph, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, target, 1.0F, 1.0F, FX_RANGE + 32.0D);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, target, 0.9F, 16.0F, FX_RANGE);
            sendQuasar(level, STERN_KOMET_CORE, target); // afterglow dome
            sendQuasar(level, STERN_FUNKE_FALL, target.add(0.0D, 2.2D, 0.0D)); // light pillar
            damageAround(player, target, radius, damage, knockback, 0, knockup, markBonus, 0, 0);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.LIGHTNING_BOLT_THUNDER,
                    SoundSource.PLAYERS, 1.0F, 1.05F);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.PLAYERS, 1.0F, 0.55F);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                    SoundSource.PLAYERS, 0.9F, 0.8F);
            shakeNear(level, target, 32.0D, 0.4F, 13);
        });
        // WANDFIX-2 (L5) Splitterregen: shard-comets crash around the crater right after
        // the main hit — thin ribbons + starfall streaks, each a small AoE of its own.
        for (int i = 0; i < splinters; i++) {
            int delay = telegraph + 4 + i * 3;
            WandTickService.schedule(level, delay, () -> {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double dist = radius * (0.6D + level.random.nextDouble() * 0.7D);
                double x = target.x + Math.cos(angle) * dist;
                double z = target.z + Math.sin(angle) * dist;
                double y = level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                        (int) Math.floor(x), (int) Math.floor(z));
                Vec3 impact = new Vec3(x, y, z);
                FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.3F, 0.0F, FX_RANGE);
                sendQuasar(level, STERN_FUNKE_FALL, impact.add(0.0D, 1.6D, 0.0D));
                damageAround(player, impact, splinterRadius, splinterDamage, 0.5F, 0,
                        0.0F, markBonus, 0, 0);
                level.playSound(null, x, y, z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                        SoundSource.PLAYERS, 0.8F, 1.0F + level.random.nextFloat() * 0.4F);
            });
        }
        return true;
    }

    /**
     * D11 Kometenschlag herald: one ring of END_ROD motes laid on the ground around the
     * aim point — called with a growing radius per descent beat so the landing light
     * visibly expands. Vanilla particles by design (14/ring — no Quasar budget spend).
     */
    private static void groundLightRing(ServerLevel level, Vec3 center, double ringRadius) {
        int points = 14;
        for (int i = 0; i < points; i++) {
            double angle = i * Math.PI * 2.0D / points;
            level.sendParticles(ParticleTypes.END_ROD,
                    center.x + Math.cos(angle) * ringRadius, center.y + 0.25D,
                    center.z + Math.sin(angle) * ringRadius, 1, 0.03D, 0.05D, 0.03D, 0.004D);
        }
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
        WandProgressSync.syncTo(killer);
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
        damageAround(caster, center, radius, damage, knockback, fireTicks, 0.0F, 1.0F, 0, 0);
    }

    /**
     * Full-fat AoE helper (WANDFIX-2 rebalance): the base contract plus the new mechanics
     * — {@code knockup} hurls victims skyward on top of the radial push, {@code markBonus}
     * &gt; 1 multiplies damage against Glowing targets (the STERN Sternenmal combo),
     * {@code slowTicks} applies Slowness II (Sternenstaub), {@code glowTicks} stamps the
     * Sternenmal mark itself. Zeros/1.0 = the classic behavior.
     */
    static void damageAround(ServerPlayer caster, Vec3 center, float radius, float damage,
            float knockback, int fireTicks, float knockup, float markBonus, int slowTicks,
            int glowTicks) {
        ServerLevel level = caster.serverLevel();
        damage *= WandPerks.damageMultiplier(caster); // WANDFIX-4 damage line (W11/12/15/16)
        List<LivingEntity> victims = level.getEntitiesOfClass(LivingEntity.class,
                new AABB(center, center).inflate(radius),
                e -> e != caster && e.isAlive() && e.position().distanceTo(center) <= radius);
        for (LivingEntity victim : victims) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            float dealt = markBonus > 1.0F && victim.hasEffect(MobEffects.GLOWING)
                    ? damage * markBonus : damage;
            victim.hurt(caster.damageSources().indirectMagic(caster, caster), dealt);
            if (fireTicks > 0) {
                victim.setRemainingFireTicks(Math.max(victim.getRemainingFireTicks(), fireTicks));
            }
            if (slowTicks > 0) {
                victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, slowTicks, 1), caster);
            }
            if (glowTicks > 0) {
                victim.addEffect(new MobEffectInstance(MobEffects.GLOWING, glowTicks, 0), caster);
            }
            if (knockback > 0.0F || knockup > 0.0F) {
                Vec3 away = victim.position().subtract(center);
                Vec3 flat = new Vec3(away.x, 0.0D, away.z);
                Vec3 dir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : Vec3.ZERO;
                victim.push(dir.x * knockback * 0.5D, 0.25D * knockback + knockup,
                        dir.z * knockback * 0.5D);
            }
        }
    }

    /** One-shot quasar emitter broadcast near a position (client budget law applies). */
    static void sendQuasar(ServerLevel level, ResourceLocation emitterId, Vec3 pos) {
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, FX_RANGE,
                new S2CQuasarPayload(emitterId, pos));
    }
}
