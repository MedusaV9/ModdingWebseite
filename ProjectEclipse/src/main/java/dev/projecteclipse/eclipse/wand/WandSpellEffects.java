package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.protection.SpawnProtectionRules;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;

/**
 * F-039 spell execution: the single dispatch for all 30 {@link WandSpells} entries plus
 * the 22 implementations that do not live in {@code WandPowers} (the eight carried-over
 * legacy casts stay there). Every spell works fully server-side — damage/effects first,
 * FX layered on top through the frozen budgeted channels ({@code FxPayloads} cues +
 * {@code S2CQuasarPayload} emitters + vanilla particles) with server-owned audio.
 *
 * <p>Design laws inherited from {@code WandPowers}: never hurt the caster, respect
 * spawn-protection zones ({@code WandPowers.damageAround} enforces both), never write a
 * single block (F-038's core demand — the Umbra-Lanze replaced the block-phasing
 * Phasenwelle exactly for this), and multi-tick choreography rides
 * {@link WandTickService#schedule} so a stopped server just drops pending FX.</p>
 */
public final class WandSpellEffects {
    private static final double FX_RANGE = WandPowers.FX_RANGE;

    private WandSpellEffects() {}

    /**
     * Executes {@code spell} for {@code player} with live tuning {@code power}.
     * Returns false when the cast refuses (no cost is charged then).
     */
    public static boolean cast(ServerPlayer player, WandSpell spell, WandConfig.Power power) {
        return switch (spell.key()) {
            // ---------------- RISS (legacy trio + 7 new)
            case "riss.blink" -> WandPowers.castBlink(player, power);
            case "riss.umbra_lanze" -> castUmbraLanze(player, power);
            case "riss.rissschlag" -> WandPowers.castRissschlag(player, power);
            case "riss.zugfeld" -> castZugfeld(player, power);
            case "riss.phasentausch" -> castPhasentausch(player, power);
            case "riss.echoklinge" -> castEchoklinge(player, power);
            case "riss.gravitationsbrunnen" -> castGravitationsbrunnen(player, power);
            case "riss.schattenriss" -> castSchattenriss(player, power);
            case "riss.leerensog" -> castLeerensog(player, power);
            case "riss.ereignishorizont" -> castEreignishorizont(player, power);
            // ---------------- GLUT
            case "glut.glutstoss" -> WandPowers.castGlutstoss(player, power);
            case "glut.flammenfaecher" -> castFlammenfaecher(player, power);
            case "glut.feuerball" -> castFeuerball(player, power);
            case "glut.feuerwelle" -> WandPowers.castFeuerwelle(player, power);
            case "glut.magmasprung" -> WandPowers.castMagmasprung(player, power);
            case "glut.aschesturm" -> castAschesturm(player, power);
            case "glut.eruptionslinie" -> castEruptionslinie(player, power);
            case "glut.phoenixschwinge" -> castPhoenixschwinge(player, power);
            case "glut.sonnenkern" -> castSonnenkern(player, power);
            case "glut.inferno" -> castInferno(player, power);
            // ---------------- STERN
            case "stern.funkenruf" -> WandPowers.castFunkenruf(player, power);
            case "stern.sternenschild" -> castSternenschild(player, power);
            case "stern.wurzelgriff" -> castWurzelgriff(player, power);
            case "stern.sternschauer" -> WandPowers.castSternschauer(player, power);
            case "stern.lichtsegen" -> castLichtsegen(player, power);
            case "stern.kometenschlag" -> WandPowers.castKometenschlag(player, power);
            case "stern.spiegelpanzer" -> castSpiegelpanzer(player, power);
            case "stern.sternenbann" -> castSternenbann(player, power);
            case "stern.novawaechter" -> castNovawaechter(player, power);
            case "stern.himmelsgericht" -> castHimmelsgericht(player, power);
            default -> false;
        };
    }

    // ==================================================================
    // RISS — Raum/Bewegung
    // ==================================================================

    /**
     * F-038 <b>Umbra-Lanze</b> (Void Lance) — the Phasenwelle replacement: a piercing
     * void beam that damages EVERY living thing on the line and detonates a small
     * implosion (inward pull + damage + slow) at the endpoint. Touches zero blocks.
     */
    private static boolean castUmbraLanze(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 24.0F);
        float damage = power.param("damage", 8.0F) * WandPerks.damageMultiplier(player);
        float implodeRadius = power.param("implodeRadius", 3.5F);
        float implodeDamage = power.param("implodeDamage", 5.0F);
        float pull = power.param("pull", 0.7F);
        int slowTicks = (int) power.param("slowTicks", 50.0F);

        Vec3 eye = player.getEyePosition();
        Vec3 look = player.getLookAngle();
        HitResult blockHit = level.clip(new ClipContext(eye, eye.add(look.scale(range)),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
        double length = blockHit.getType() == HitResult.Type.MISS ? range
                : blockHit.getLocation().distanceTo(eye);
        Vec3 end = eye.add(look.scale(length));

        // Pierce: every living thing whose body the lance passes through is hit once.
        List<LivingEntity> victims = new ArrayList<>();
        for (double dist = 1.0D; dist <= length; dist += 0.5D) {
            Vec3 point = eye.add(look.scale(dist));
            for (LivingEntity hit : level.getEntitiesOfClass(LivingEntity.class,
                    new AABB(point, point).inflate(0.9D),
                    e -> e != player && e.isAlive() && !victims.contains(e))) {
                victims.add(hit);
            }
            // Beam body: sparse void motes so the lance reads without flooding budget.
            if (((int) (dist * 2.0D)) % 2 == 0) {
                level.sendParticles(ParticleTypes.PORTAL, point.x, point.y, point.z,
                        1, 0.04D, 0.04D, 0.04D, 0.01D);
            }
            if (((int) (dist * 2.0D)) % 5 == 0) {
                level.sendParticles(ParticleTypes.END_ROD, point.x, point.y, point.z,
                        1, 0.02D, 0.02D, 0.02D, 0.002D);
            }
        }
        for (LivingEntity victim : victims) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            victim.hurt(player.damageSources().indirectMagic(player, player), damage);
            if (slowTicks > 0) {
                victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN,
                        slowTicks, 1), player);
            }
        }

        // Endpoint implosion: inhale, then the void bite (the Rissschlag pull inverted
        // into a finisher). Photon garnish rides CUE_WAND_UMBRA; the FX_RIFT pair and
        // the quasar wave-front stay the photon-less baseline.
        Vec3 impact = end.add(0.0D, 0.2D, 0.0D);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, impact, 1.0F, 1.0F, FX_RANGE);
        FxPayloads.sendFxEvent(level, FxCues.CUE_WAND_UMBRA, impact, 0.0F, 0.0F, FX_RANGE);
        WandPowers.sendQuasar(level, WandPowers.RISS_WAVE_FRONT, eye.add(look.scale(Math.min(2.5D, length))));
        WandPowers.sendQuasar(level, WandPowers.RISS_WAVE_FRONT, impact);
        for (LivingEntity dragged : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(impact, impact).inflate(implodeRadius * 1.5D),
                e -> e != player && e.isAlive())) {
            if (SpawnProtectionRules.isInProtectionZone(level, dragged.blockPosition())) {
                continue;
            }
            Vec3 in = impact.subtract(dragged.position());
            Vec3 flat = new Vec3(in.x, 0.0D, in.z);
            if (flat.lengthSqr() > 1.0E-4D) {
                Vec3 dir = flat.normalize();
                dragged.push(dir.x * pull, 0.1D * pull, dir.z * pull);
            }
        }
        WandTickService.schedule(level, 3, () -> {
            WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, impact);
            WandPowers.damageAround(player, impact, implodeRadius, implodeDamage, 0.0F, 0,
                    0.0F, 1.0F, slowTicks, 0);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, impact, 0.0F, 0.0F, FX_RANGE);
            level.playSound(null, impact.x, impact.y, impact.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.6F, 0.8F);
        });
        level.playSound(null, eye.x, eye.y, eye.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 0.5F, 1.9F);
        level.playSound(null, impact.x, impact.y, impact.z,
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.7F, 1.2F);
        WandPowers.shakeNear(level, impact, 16.0D, 0.14F, 7);
        return true;
    }

    /** Zugfeld: yanks everything living around the aimed point toward it, dazed + slowed. */
    private static boolean castZugfeld(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 24.0F)).add(0.0D, 0.6D, 0.0D);
        float radius = power.param("radius", 6.0F);
        float pull = power.param("pull", 0.9F);
        float damage = power.param("damage", 4.0F);
        int slowTicks = (int) power.param("slowTicks", 60.0F);

        pullToward(level, player, center, radius * 1.5F, pull);
        WandPowers.damageAround(player, center, radius, damage, 0.0F, 0, 0.0F, 1.0F, slowTicks, 0);
        WandPowers.sendQuasar(level, WandPowers.RISS_SCHLAG_MAW, center);
        // F-070: Photon maelstrom layer — the yank made visible (a = radius scales it).
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_RISS_MAELSTROM, center,
                radius, 0.0F, FX_RANGE);
        WandTickService.schedule(level, 3,
                () -> WandPowers.sendQuasar(level, WandPowers.RISS_MAW_SHIMMER, center));
        level.sendParticles(ParticleTypes.PORTAL, center.x, center.y, center.z,
                24, radius * 0.4D, 0.4D, radius * 0.4D, 0.15D);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 0.55F, 1.5F);
        level.playSound(null, center.x, center.y, center.z,
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.5F, 1.0F);
        return true;
    }

    /** Phasentausch: swap places with the first creature on the look ray. */
    private static boolean castPhasentausch(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 20.0F);
        LivingEntity target = firstOnRay(player, range);
        if (target == null) {
            player.displayClientMessage(dev.projecteclipse.eclipse.lang.ServerLang.tr(player,
                    "wand.eclipse.msg.no_target"), true);
            return false;
        }
        Vec3 mine = player.position();
        Vec3 theirs = target.position();
        Vec3 fxMine = mine.add(0.0D, 1.0D, 0.0D);
        Vec3 fxTheirs = theirs.add(0.0D, 1.0D, 0.0D);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxMine, 1.2F, 1.0F, FX_RANGE);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxTheirs, 1.2F, 1.0F, FX_RANGE);
        WandPowers.sendQuasar(level, WandPowers.RISS_BLINK_TEAR, fxMine);
        WandPowers.sendQuasar(level, WandPowers.RISS_BLINK_TEAR, fxTheirs);
        player.teleportTo(theirs.x, theirs.y, theirs.z);
        player.resetFallDistance();
        target.teleportTo(mine.x, mine.y, mine.z);
        target.resetFallDistance();
        float damage = power.param("damage", 4.0F) * WandPerks.damageMultiplier(player);
        if (!SpawnProtectionRules.isInProtectionZone(level, target.blockPosition())) {
            target.hurt(player.damageSources().indirectMagic(player, player), damage);
        }
        int veilTicks = (int) power.param("veilTicks", 30.0F);
        if (veilTicks > 0) {
            player.addEffect(new MobEffectInstance(MobEffects.DAMAGE_RESISTANCE, veilTicks, 1,
                    false, false, true));
        }
        WandTickService.schedule(level, 4, () -> {
            WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, fxMine);
            WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, fxTheirs);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxMine, 0.0F, 0.0F, FX_RANGE);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxTheirs, 0.0F, 0.0F, FX_RANGE);
        });
        level.playSound(null, mine.x, mine.y, mine.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.7F, 1.3F);
        level.playSound(null, theirs.x, theirs.y, theirs.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.7F, 0.9F);
        return true;
    }

    /** Echoklinge: three phase-blade pulses slice around the moving caster. */
    private static boolean castEchoklinge(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float radius = power.param("radius", 4.5F);
        float damage = power.param("damage", 5.0F);
        int hits = Math.max(1, (int) power.param("hits", 3.0F));
        int beat = Math.max(1, (int) power.param("beatTicks", 4.0F));
        float knockback = power.param("knockback", 0.6F);
        for (int i = 0; i < hits; i++) {
            float pitch = 1.2F + 0.25F * i;
            WandTickService.schedule(level, i * beat, () -> {
                Vec3 center = player.position().add(0.0D, 1.0D, 0.0D);
                WandPowers.damageAround(player, center, radius, damage, knockback, 0);
                WandPowers.sendQuasar(level, WandPowers.RISS_WAVE_FRONT, center);
                // F-070: Photon blade ring rides the caster per beat (entity lane;
                // allowMulti keeps all slices alive; a = radius scales the ring).
                FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WANDFX2_RISS_ECHO_BLADE,
                        player, radius, 0.0F, FX_RANGE);
                level.sendParticles(ParticleTypes.SWEEP_ATTACK, center.x, center.y, center.z,
                        4, radius * 0.4D, 0.2D, radius * 0.4D, 0.0D);
                level.playSound(null, center.x, center.y, center.z,
                        SoundEvents.PLAYER_ATTACK_SWEEP, SoundSource.PLAYERS, 0.7F, pitch);
                level.playSound(null, center.x, center.y, center.z,
                        EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.3F, 1.6F);
            });
        }
        return true;
    }

    /** Gravitationsbrunnen: a held pull-field — area denial that gathers its own targets. */
    private static boolean castGravitationsbrunnen(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 24.0F)).add(0.0D, 0.8D, 0.0D);
        float radius = power.param("radius", 7.0F);
        int duration = (int) power.param("durationTicks", 80.0F);
        float pull = power.param("pull", 0.35F);
        float pulseDamage = power.param("pulseDamage", 3.0F);
        int pulseEvery = Math.max(5, (int) power.param("pulseEveryTicks", 20.0F));

        WandPowers.sendQuasar(level, WandPowers.RISS_SCHLAG_MAW, center);
        // F-070: Photon well layer (orbital disc + infall, baked ~80t) and a T4 rumble
        // for bystanders — both purely audiovisual.
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_RISS_WELL, center,
                radius, duration, FX_RANGE);
        WandPowers.shakeNear(level, center, 18.0D, 0.12F, 6);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 0.7F, 0.7F);
        for (int tick = 0; tick <= duration; tick += 5) {
            boolean pulse = tick > 0 && tick % pulseEvery == 0;
            boolean last = tick + 5 > duration;
            WandTickService.schedule(level, tick, () -> {
                pullToward(level, player, center, radius, pull);
                level.sendParticles(ParticleTypes.PORTAL, center.x, center.y, center.z,
                        10, radius * 0.35D, 0.5D, radius * 0.35D, 0.2D);
                if (pulse) {
                    WandPowers.damageAround(player, center, radius, pulseDamage, 0.0F, 0);
                    WandPowers.sendQuasar(level, WandPowers.RISS_MAW_SHIMMER, center);
                    level.playSound(null, center.x, center.y, center.z,
                            EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.4F, 0.9F);
                }
                if (last) {
                    WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, center);
                    level.playSound(null, center.x, center.y, center.z,
                            EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.5F, 1.4F);
                }
            });
        }
        return true;
    }

    /** Schattenriss: step through the veil BEHIND a target and strike its back. */
    private static boolean castSchattenriss(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        double range = power.param("range", 20.0F);
        LivingEntity target = firstOnRay(player, range);
        if (target == null) {
            player.displayClientMessage(dev.projecteclipse.eclipse.lang.ServerLang.tr(player,
                    "wand.eclipse.msg.no_target"), true);
            return false;
        }
        Vec3 from = player.position();
        Vec3 behindDir = target.getLookAngle().scale(-1.0D);
        Vec3 flat = new Vec3(behindDir.x, 0.0D, behindDir.z);
        Vec3 dir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : player.getLookAngle().scale(-1.0D);
        Vec3 spot = target.position().add(dir.scale(1.6D));
        AABB box = player.getBoundingBox().move(spot.subtract(player.position()));
        if (!level.noCollision(player, box)) {
            spot = target.position().add(dir.scale(-1.6D)); // fall back to the front side
            box = player.getBoundingBox().move(spot.subtract(player.position()));
            if (!level.noCollision(player, box)) {
                player.displayClientMessage(dev.projecteclipse.eclipse.lang.ServerLang.tr(player,
                        "wand.eclipse.msg.no_room"), true);
                return false;
            }
        }
        Vec3 fxFrom = from.add(0.0D, 1.0D, 0.0D);
        Vec3 fxTo = spot.add(0.0D, 1.0D, 0.0D);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxFrom, 1.2F, 1.0F, FX_RANGE);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, fxTo, 1.2F, 1.0F, FX_RANGE);
        WandPowers.sendQuasar(level, WandPowers.RISS_BLINK_TEAR, fxFrom);
        WandPowers.sendQuasar(level, WandPowers.RISS_BLINK_TEAR, fxTo);
        // F-070: a SMALL Photon void crunch on the strike point — the backstab's residue
        // (2.2 blocks; purely a layer over the rift pair above).
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_RISS_MAELSTROM, fxTo,
                2.2F, 0.0F, FX_RANGE);
        player.teleportTo(spot.x, spot.y, spot.z);
        player.resetFallDistance();
        float damage = power.param("damage", 14.0F) * WandPerks.damageMultiplier(player);
        int slowTicks = (int) power.param("slowTicks", 60.0F);
        if (!SpawnProtectionRules.isInProtectionZone(level, target.blockPosition())) {
            target.hurt(player.damageSources().indirectMagic(player, player), damage);
            if (slowTicks > 0) {
                target.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN,
                        slowTicks, 1), player);
            }
        }
        int veilTicks = (int) power.param("veilTicks", 40.0F);
        if (veilTicks > 0) {
            player.addEffect(new MobEffectInstance(MobEffects.DAMAGE_RESISTANCE, veilTicks, 1,
                    false, false, true));
        }
        WandTickService.schedule(level, 4, () -> {
            WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, fxTo);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxFrom, 0.0F, 0.0F, FX_RANGE);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, fxTo, 0.0F, 0.0F, FX_RANGE);
        });
        level.playSound(null, spot.x, spot.y, spot.z, SoundEvents.ENDERMAN_TELEPORT,
                SoundSource.PLAYERS, 0.8F, 0.7F);
        level.playSound(null, spot.x, spot.y, spot.z,
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.6F, 1.4F);
        return true;
    }

    /** Leerensog: one violent void maelstrom — drag, crunch, slow. */
    private static boolean castLeerensog(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 24.0F)).add(0.0D, 0.8D, 0.0D);
        float radius = power.param("radius", 9.0F);
        float pull = power.param("pull", 1.4F);
        float damage = power.param("damage", 12.0F);
        int slowTicks = (int) power.param("slowTicks", 80.0F);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, center, 1.6F, 1.0F, FX_RANGE);
        WandPowers.sendQuasar(level, WandPowers.RISS_SCHLAG_MAW, center);
        // F-070: Photon maelstrom layer — the asset bakes its HDR bite at +6t, exactly
        // the crunch tick scheduled below (a = radius scales the inhale shell).
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_RISS_MAELSTROM, center,
                radius, 0.0F, FX_RANGE);
        WandTickService.schedule(level, 2,
                () -> WandPowers.sendQuasar(level, WandPowers.RISS_SCHLAG_MAW, center));
        pullToward(level, player, center, radius, pull);
        WandTickService.schedule(level, 6, () -> {
            pullToward(level, player, center, radius * 0.7F, pull * 0.7F);
            WandPowers.damageAround(player, center, radius * 0.8F, damage, 0.4F, 0,
                    0.0F, 1.0F, slowTicks, 0);
            WandPowers.sendQuasar(level, WandPowers.RISS_BLINK_TEAR, center);
            WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, center);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, center, 0.0F, 0.0F, FX_RANGE);
            level.playSound(null, center.x, center.y, center.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.8F, 0.7F);
            WandPowers.shakeNear(level, center, 20.0D, 0.2F, 9);
        });
        level.playSound(null, center.x, center.y, center.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 0.8F, 0.6F);
        return true;
    }

    /** Ereignishorizont (capstone): a long-held horizon that ends in a collapse blast. */
    private static boolean castEreignishorizont(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 28.0F)).add(0.0D, 1.0D, 0.0D);
        float radius = power.param("radius", 8.0F);
        int duration = (int) power.param("durationTicks", 120.0F);
        float pull = power.param("pull", 0.5F);
        float pulseDamage = power.param("pulseDamage", 4.0F);
        int pulseEvery = Math.max(5, (int) power.param("pulseEveryTicks", 15.0F));
        float finaleDamage = power.param("finaleDamage", 14.0F);
        float finaleKnockback = power.param("finaleKnockback", 1.6F);

        FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, center, 2.0F, 1.0F, FX_RANGE + 16.0D);
        FxPayloads.sendFxEvent(level, FxCues.CUE_WAND_HORIZON, center, duration, 0.0F, FX_RANGE + 16.0D);
        WandPowers.sendQuasar(level, WandPowers.RISS_SCHLAG_MAW, center);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.PORTAL_TRIGGER,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        WandPowers.shakeNear(level, center, 24.0D, 0.15F, 8);
        for (int tick = 5; tick < duration; tick += 5) {
            boolean pulse = tick % pulseEvery == 0;
            WandTickService.schedule(level, tick, () -> {
                pullToward(level, player, center, radius, pull);
                level.sendParticles(ParticleTypes.PORTAL, center.x, center.y, center.z,
                        12, radius * 0.4D, 0.6D, radius * 0.4D, 0.25D);
                if (pulse) {
                    WandPowers.damageAround(player, center, radius, pulseDamage, 0.0F, 0);
                    WandPowers.sendQuasar(level, WandPowers.RISS_MAW_SHIMMER, center);
                    level.playSound(null, center.x, center.y, center.z,
                            EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.45F, 0.8F);
                }
            });
        }
        // Collapse: the horizon folds in and detonates outward — the one moment the
        // capstone pushes instead of pulls.
        WandTickService.schedule(level, duration, () -> {
            WandPowers.damageAround(player, center, radius, finaleDamage, finaleKnockback, 0,
                    0.5F, 1.0F, 0, 0);
            WandPowers.sendQuasar(level, WandPowers.RISS_BLINK_TEAR, center);
            WandPowers.sendQuasar(level, WandPowers.RISS_SEAM_SCAR, center);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, center, 1.0F, 14.0F, FX_RANGE);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, center, 0.0F, 0.0F, FX_RANGE);
            level.playSound(null, center.x, center.y, center.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 1.0F, 0.55F);
            level.playSound(null, center.x, center.y, center.z, SoundEvents.GENERIC_EXPLODE.value(),
                    SoundSource.PLAYERS, 0.5F, 0.7F);
            WandPowers.shakeNear(level, center, 28.0D, 0.3F, 12);
        });
        return true;
    }

    // ==================================================================
    // GLUT — Zerstörung
    // ==================================================================

    /** Flammenfächer: a burning cone slap in front of the caster. */
    private static boolean castFlammenfaecher(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float range = power.param("range", 7.0F);
        float halfArc = power.param("arcDegrees", 70.0F) * 0.5F;
        float damage = power.param("damage", 7.0F) * WandPerks.damageMultiplier(player);
        int fireSeconds = (int) power.param("fireSeconds", 3.0F);
        float knockback = power.param("knockback", 0.5F);

        Vec3 origin = player.getEyePosition();
        Vec3 look = player.getLookAngle();
        Vec3 flatLook = new Vec3(look.x, 0.0D, look.z).normalize();
        int hit = 0;
        for (LivingEntity victim : level.getEntitiesOfClass(LivingEntity.class,
                player.getBoundingBox().inflate(range),
                e -> e != player && e.isAlive())) {
            Vec3 to = victim.position().add(0.0D, victim.getBbHeight() * 0.5D, 0.0D).subtract(origin);
            if (to.length() > range) {
                continue;
            }
            Vec3 flatTo = new Vec3(to.x, 0.0D, to.z);
            if (flatTo.lengthSqr() < 1.0E-4D) {
                continue;
            }
            double angle = Math.toDegrees(Math.acos(net.minecraft.util.Mth.clamp(
                    flatLook.dot(flatTo.normalize()), -1.0D, 1.0D)));
            if (angle > halfArc) {
                continue;
            }
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            victim.hurt(player.damageSources().indirectMagic(player, player), damage);
            victim.igniteForSeconds(fireSeconds);
            Vec3 push = flatTo.normalize().scale(knockback);
            victim.push(push.x, 0.15D * knockback, push.z);
            hit++;
        }
        // Fan FX: three flame tongues sweep the arc, ash settles behind them.
        for (int i = -1; i <= 1; i++) {
            double yaw = Math.toRadians(player.getYRot() + i * halfArc * 0.75F);
            Vec3 dir = new Vec3(-Math.sin(yaw), 0.0D, Math.cos(yaw));
            for (double d = 1.0D; d <= range; d += 1.0D) {
                Vec3 p = origin.add(dir.scale(d)).add(0.0D, -0.3D, 0.0D);
                level.sendParticles(ParticleTypes.FLAME, p.x, p.y, p.z, 2, 0.15D, 0.1D, 0.15D, 0.015D);
            }
        }
        Vec3 mid = origin.add(flatLook.scale(range * 0.5D)).add(0.0D, -0.4D, 0.0D);
        WandPowers.sendQuasar(level, WandPowers.GLUT_STOSS_LANCE, mid);
        // F-070: a small Photon detonation mid-arc — the fan's payoff beat (2 blocks).
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_GLUT_BURST, mid, 2.0F, 0.0F, FX_RANGE);
        WandTickService.schedule(level, 4,
                () -> WandPowers.sendQuasar(level, WandPowers.GLUT_ASH_FLAKES, mid));
        level.playSound(null, origin.x, origin.y, origin.z, SoundEvents.FIRECHARGE_USE,
                SoundSource.PLAYERS, 0.9F, hit > 0 ? 0.6F : 0.75F);
        level.playSound(null, origin.x, origin.y, origin.z, SoundEvents.BLAZE_SHOOT,
                SoundSource.PLAYERS, 0.5F, 0.8F);
        return true;
    }

    /** Feuerball: a marched ember projectile that detonates on the first thing it meets. */
    private static boolean castFeuerball(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float range = power.param("range", 28.0F);
        float speed = Math.max(0.5F, power.param("speed", 1.4F));
        float damage = power.param("damage", 9.0F);
        float radius = power.param("radius", 3.0F);
        int fireSeconds = (int) power.param("fireSeconds", 4.0F);
        float knockback = power.param("knockback", 0.8F);

        Vec3 origin = player.getEyePosition().add(player.getLookAngle().scale(1.2D));
        Vec3 step = player.getLookAngle().scale(speed);
        int maxSteps = (int) Math.ceil(range / speed);
        boolean[] done = new boolean[1];
        Vec3[] pos = new Vec3[] {origin};
        level.playSound(null, origin.x, origin.y, origin.z, SoundEvents.FIRECHARGE_USE,
                SoundSource.PLAYERS, 0.8F, 0.9F);
        WandPowers.sendQuasar(level, WandPowers.GLUT_STOSS_LANCE, origin);
        // F-070: Photon comet layer — streaks fly along the asset's local +Z at the
        // shipped speed; rotate +Z onto the cast ray via the X/Y Euler pair (the
        // heartTheftArc JOML rotationXYZ convention). The vanilla FLAME march below
        // stays the photon-less trail baseline.
        Vec3 aim = player.getLookAngle();
        float cometXDeg = (float) Math.toDegrees(Math.atan2(-aim.y, aim.z));
        float cometYDeg = (float) Math.toDegrees(
                Math.atan2(aim.x, Math.sqrt(aim.y * aim.y + aim.z * aim.z)));
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_GLUT_COMET, origin,
                cometXDeg, cometYDeg, FX_RANGE);
        for (int i = 1; i <= maxSteps; i++) {
            boolean lastStep = i == maxSteps;
            WandTickService.schedule(level, i, () -> {
                if (done[0]) {
                    return;
                }
                Vec3 from = pos[0];
                Vec3 to = from.add(step);
                HitResult hit = level.clip(new ClipContext(from, to,
                        ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
                Vec3 reached = hit.getType() == HitResult.Type.MISS ? to : hit.getLocation();
                List<LivingEntity> victims = level.getEntitiesOfClass(LivingEntity.class,
                        new AABB(from, reached).inflate(0.8D),
                        e -> e != player && e.isAlive());
                boolean explode = lastStep || hit.getType() != HitResult.Type.MISS
                        || !victims.isEmpty();
                pos[0] = reached;
                level.sendParticles(ParticleTypes.FLAME, reached.x, reached.y, reached.z,
                        4, 0.1D, 0.1D, 0.1D, 0.01D);
                level.sendParticles(ParticleTypes.SMALL_FLAME, from.x, from.y, from.z,
                        2, 0.08D, 0.08D, 0.08D, 0.005D);
                if (!explode) {
                    return;
                }
                done[0] = true;
                Vec3 impact = !victims.isEmpty()
                        ? victims.get(0).position().add(0.0D, victims.get(0).getBbHeight() * 0.5D, 0.0D)
                        : reached;
                // Detonation: visual burst + AoE, never an ignition on terrain.
                WandPowers.damageAround(player, impact, radius, damage, knockback,
                        fireSeconds * 20);
                WandPowers.sendQuasar(level, WandPowers.GLUT_SPRUNG_CRATER, impact);
                // F-070: Photon detonation layer — core pop + fire ring + physics
                // ember debris (a = blast radius scales the payoff).
                FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_GLUT_BURST, impact,
                        radius, 0.0F, FX_RANGE);
                WandTickService.schedule(level, 3,
                        () -> WandPowers.sendQuasar(level, WandPowers.GLUT_ASH_FLAKES, impact));
                level.sendParticles(ParticleTypes.LAVA, impact.x, impact.y, impact.z,
                        10, radius * 0.3D, 0.2D, radius * 0.3D, 0.0D);
                level.sendParticles(ParticleTypes.FLAME, impact.x, impact.y, impact.z,
                        18, radius * 0.4D, 0.3D, radius * 0.4D, 0.04D);
                level.playSound(null, impact.x, impact.y, impact.z,
                        SoundEvents.GENERIC_EXPLODE.value(), SoundSource.PLAYERS, 0.7F, 0.9F);
                level.playSound(null, impact.x, impact.y, impact.z, SoundEvents.LAVA_POP,
                        SoundSource.PLAYERS, 0.7F, 0.6F);
                WandPowers.shakeNear(level, impact, 16.0D, 0.16F, 7);
            });
        }
        return true;
    }

    /** Aschesturm: a smothering ash zone — heat pulses, embers, slowed silhouettes. */
    private static boolean castAschesturm(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 24.0F)).add(0.0D, 0.5D, 0.0D);
        float radius = power.param("radius", 6.0F);
        int duration = (int) power.param("durationTicks", 60.0F);
        float pulseDamage = power.param("pulseDamage", 3.0F);
        int pulseEvery = Math.max(5, (int) power.param("pulseEveryTicks", 15.0F));
        int fireTicks = (int) (power.param("fireSeconds", 2.0F) * 20.0F);
        int slowTicks = (int) power.param("slowTicks", 50.0F);

        WandPowers.sendQuasar(level, WandPowers.GLUT_ASH_FLAKES, center.add(0.0D, 1.2D, 0.0D));
        // F-070: Photon ash-bank layer — billowing gusty smoke carousel + ember swirl +
        // floor coals, baked to the authored 60t window (a = radius scales the zone).
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_GLUT_ASCHESTURM, center,
                radius, 0.0F, FX_RANGE);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.FIRE_AMBIENT,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        for (int tick = 0; tick <= duration; tick += 5) {
            boolean pulse = tick > 0 && tick % pulseEvery == 0;
            WandTickService.schedule(level, tick, () -> {
                level.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                        center.x, center.y + 0.8D, center.z,
                        3, radius * 0.4D, 0.5D, radius * 0.4D, 0.01D);
                level.sendParticles(ParticleTypes.SMALL_FLAME, center.x, center.y + 0.3D, center.z,
                        4, radius * 0.4D, 0.2D, radius * 0.4D, 0.01D);
                if (pulse) {
                    WandPowers.damageAround(player, center, radius, pulseDamage, 0.0F, fireTicks,
                            0.0F, 1.0F, slowTicks, 0);
                    WandPowers.sendQuasar(level, WandPowers.GLUT_ASH_FLAKES,
                            center.add(0.0D, 1.0D, 0.0D));
                    level.playSound(null, center.x, center.y, center.z,
                            SoundEvents.CAMPFIRE_CRACKLE, SoundSource.PLAYERS, 0.7F, 0.7F);
                }
            });
        }
        return true;
    }

    /** Eruptionslinie: five staggered ground eruptions march away from the caster. */
    private static boolean castEruptionslinie(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float length = power.param("length", 14.0F);
        int steps = Math.max(2, (int) power.param("steps", 5.0F));
        int stepTicks = Math.max(1, (int) power.param("stepTicks", 3.0F));
        float damage = power.param("damage", 8.0F);
        float radius = power.param("radius", 2.5F);
        int fireTicks = (int) (power.param("fireSeconds", 3.0F) * 20.0F);
        float knockup = power.param("knockup", 0.5F);

        Vec3 look = player.getLookAngle();
        Vec3 dir = new Vec3(look.x, 0.0D, look.z);
        if (dir.lengthSqr() < 1.0E-4D) {
            dir = new Vec3(1.0D, 0.0D, 0.0D);
        }
        Vec3 flat = dir.normalize();
        Vec3 start = player.position();
        level.playSound(null, start.x, start.y, start.z, SoundEvents.BLAZE_SHOOT,
                SoundSource.PLAYERS, 0.9F, 0.55F);
        // F-070: T4 bystander rumble as the line starts marching (purely audiovisual).
        WandPowers.shakeNear(level, start, 18.0D, 0.14F, 7);
        for (int i = 1; i <= steps; i++) {
            double dist = length * i / (double) steps;
            float pitch = 0.7F + 0.12F * i;
            WandTickService.schedule(level, i * stepTicks, () -> {
                double x = start.x + flat.x * dist;
                double z = start.z + flat.z * dist;
                double y = level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                        (int) Math.floor(x), (int) Math.floor(z));
                Vec3 spot = new Vec3(x, y, z);
                WandPowers.damageAround(player, spot.add(0.0D, 0.8D, 0.0D), radius, damage,
                        0.4F, fireTicks, knockup, 1.0F, 0, 0);
                WandPowers.sendQuasar(level, WandPowers.GLUT_WELLE_RING, spot.add(0.0D, 0.2D, 0.0D));
                // F-070: one Photon detonation per eruption step (allowMulti row —
                // the staggered steps legitimately stack; a = step radius).
                FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_GLUT_BURST,
                        spot.add(0.0D, 0.4D, 0.0D), radius, 0.0F, FX_RANGE);
                level.sendParticles(ParticleTypes.LAVA, x, y + 0.3D, z, 4, 0.3D, 0.2D, 0.3D, 0.0D);
                level.sendParticles(ParticleTypes.FLAME, x, y + 0.3D, z, 10, 0.4D, 0.4D, 0.4D, 0.03D);
                level.playSound(null, x, y, z, SoundEvents.GENERIC_EXPLODE.value(),
                        SoundSource.PLAYERS, 0.45F, pitch);
            });
        }
        return true;
    }

    /** Phönixschwinge: rise on burning wings — fire nova below, feather-fall above. */
    private static boolean castPhoenixschwinge(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float launch = power.param("launch", 1.5F);
        float radius = power.param("radius", 6.0F);
        float damage = power.param("damage", 10.0F);
        int fireTicks = (int) (power.param("fireSeconds", 4.0F) * 20.0F);
        float knockback = power.param("knockback", 1.3F);
        int slowFall = (int) (power.param("slowFallSeconds", 6.0F) * 20.0F);
        int resist = (int) (power.param("resistSeconds", 5.0F) * 20.0F);

        Vec3 feet = player.position();
        player.setDeltaMovement(player.getDeltaMovement().x * 0.3D, 0.9D * launch,
                player.getDeltaMovement().z * 0.3D);
        player.hurtMarked = true;
        if (slowFall > 0) {
            player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING, slowFall, 0,
                    false, false, true));
        }
        if (resist > 0) {
            player.addEffect(new MobEffectInstance(MobEffects.FIRE_RESISTANCE, resist, 0,
                    false, false, true));
        }
        WandPowers.damageAround(player, feet, radius, damage, knockback, fireTicks);
        WandPowers.sendQuasar(level, WandPowers.GLUT_SPRUNG_CRATER, feet);
        WandTickService.schedule(level, 2, () -> WandPowers.sendQuasar(level,
                WandPowers.GLUT_HEAT_COLUMN, feet.add(0.0D, 1.4D, 0.0D)));
        level.sendParticles(ParticleTypes.FLAME, feet.x, feet.y + 0.3D, feet.z,
                24, radius * 0.4D, 0.3D, radius * 0.4D, 0.05D);
        level.sendParticles(ParticleTypes.LAVA, feet.x, feet.y + 0.2D, feet.z,
                6, radius * 0.25D, 0.1D, radius * 0.25D, 0.0D);
        level.playSound(null, feet.x, feet.y, feet.z, SoundEvents.BLAZE_SHOOT,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        level.playSound(null, feet.x, feet.y, feet.z, SoundEvents.PHANTOM_FLAP,
                SoundSource.PLAYERS, 0.9F, 0.6F);
        WandPowers.shakeNear(level, feet, 18.0D, 0.18F, 8);
        return true;
    }

    /** Sonnenkern: a captured piece of sun crashes onto the aimed point. */
    private static boolean castSonnenkern(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 target = WandPowers.aimPoint(player, power.param("range", 32.0F));
        int telegraph = (int) power.param("telegraphTicks", 24.0F);
        float damage = power.param("damage", 22.0F);
        float radius = power.param("radius", 6.0F);
        int fireTicks = (int) (power.param("fireSeconds", 5.0F) * 20.0F);
        float knockup = power.param("knockup", 1.0F);
        float knockback = power.param("knockback", 1.6F);

        // Telegraph: growing ember rings + a heat column standing on the impact point.
        FxPayloads.sendFxEvent(level, FxCues.CUE_WAND_SONNENKERN, target, telegraph, 0.0F,
                FX_RANGE + 32.0D);
        WandPowers.sendQuasar(level, WandPowers.GLUT_HEAT_COLUMN, target.add(0.0D, 1.4D, 0.0D));
        level.playSound(null, target.x, target.y, target.z, SoundEvents.FIRE_AMBIENT,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        WandTickService.schedule(level, Math.max(1, telegraph - 12),
                () -> WandPowers.groundLightRing(level, target, radius * 0.4D));
        WandTickService.schedule(level, Math.max(2, telegraph - 6), () -> {
            WandPowers.groundLightRing(level, target, radius * 0.75D);
            level.playSound(null, target.x, target.y + 12.0D, target.z,
                    SoundEvents.ELYTRA_FLYING, SoundSource.PLAYERS, 0.6F, 0.7F);
        });
        WandTickService.schedule(level, telegraph, () -> {
            WandPowers.damageAround(player, target, radius, damage, knockback, fireTicks,
                    knockup, 1.0F, 0, 0);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, target, 1.0F, 14.0F,
                    FX_RANGE + 32.0D);
            WandPowers.sendQuasar(level, WandPowers.GLUT_SPRUNG_CRATER, target);
            WandTickService.schedule(level, 2, () -> WandPowers.sendQuasar(level,
                    WandPowers.GLUT_HEAT_COLUMN, target.add(0.0D, 1.4D, 0.0D)));
            WandTickService.spawnScorchDecal(level, target, 1.8F, 200);
            level.sendParticles(ParticleTypes.FLAME, target.x, target.y + 0.3D, target.z,
                    30, radius * 0.4D, 0.4D, radius * 0.4D, 0.06D);
            level.sendParticles(ParticleTypes.LAVA, target.x, target.y + 0.3D, target.z,
                    12, radius * 0.3D, 0.2D, radius * 0.3D, 0.0D);
            level.playSound(null, target.x, target.y, target.z,
                    SoundEvents.GENERIC_EXPLODE.value(), SoundSource.PLAYERS, 1.0F, 0.6F);
            level.playSound(null, target.x, target.y, target.z, SoundEvents.BLAZE_SHOOT,
                    SoundSource.PLAYERS, 0.8F, 0.5F);
            WandPowers.shakeNear(level, target, 30.0D, 0.35F, 12);
        });
        return true;
    }

    /** Inferno (capstone): a held firestorm zone — random eruptions rain for seven seconds. */
    private static boolean castInferno(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 28.0F));
        float radius = power.param("radius", 9.0F);
        int duration = (int) power.param("durationTicks", 140.0F);
        int eruptions = Math.max(3, (int) power.param("eruptions", 10.0F));
        float damage = power.param("damage", 7.0F);
        float hitRadius = power.param("hitRadius", 3.0F);
        int fireTicks = (int) (power.param("fireSeconds", 4.0F) * 20.0F);
        float knockup = power.param("knockup", 0.5F);

        FxPayloads.sendFxEvent(level, FxCues.CUE_WAND_INFERNO, center.add(0.0D, 0.5D, 0.0D),
                duration, 0.0F, FX_RANGE + 32.0D);
        WandPowers.sendQuasar(level, WandPowers.GLUT_WELLE_RING, center.add(0.0D, 0.2D, 0.0D));
        WandPowers.groundLightRing(level, center, radius);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.BLAZE_SHOOT,
                SoundSource.PLAYERS, 1.0F, 0.45F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.FIRE_AMBIENT,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        WandPowers.shakeNear(level, center, 26.0D, 0.2F, 10);
        for (int i = 0; i < eruptions; i++) {
            int delay = 10 + (i * (duration - 20)) / eruptions;
            WandTickService.schedule(level, delay, () -> {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double dist = Math.sqrt(level.random.nextDouble()) * radius;
                double x = center.x + Math.cos(angle) * dist;
                double z = center.z + Math.sin(angle) * dist;
                double y = level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                        (int) Math.floor(x), (int) Math.floor(z));
                Vec3 spot = new Vec3(x, y, z);
                WandPowers.damageAround(player, spot.add(0.0D, 0.8D, 0.0D), hitRadius, damage,
                        0.4F, fireTicks, knockup, 1.0F, 0, 0);
                WandPowers.sendQuasar(level, WandPowers.GLUT_SPRUNG_CRATER, spot);
                level.sendParticles(ParticleTypes.FLAME, x, y + 0.3D, z,
                        12, hitRadius * 0.4D, 0.4D, hitRadius * 0.4D, 0.04D);
                level.sendParticles(ParticleTypes.LAVA, x, y + 0.3D, z, 4, 0.3D, 0.2D, 0.3D, 0.0D);
                level.playSound(null, x, y, z, SoundEvents.GENERIC_EXPLODE.value(),
                        SoundSource.PLAYERS, 0.5F, 0.7F + level.random.nextFloat() * 0.3F);
            });
        }
        WandTickService.schedule(level, duration, () -> {
            WandPowers.sendQuasar(level, WandPowers.GLUT_ASH_FLAKES, center.add(0.0D, 1.2D, 0.0D));
            level.playSound(null, center.x, center.y, center.z, SoundEvents.FIRE_EXTINGUISH,
                    SoundSource.PLAYERS, 0.6F, 0.6F);
        });
        return true;
    }

    // ==================================================================
    // STERN — Schutz/Bindung
    // ==================================================================

    /** Sternenschild: a woven star shell — absorption hearts + resistance. */
    private static boolean castSternenschild(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        int absorption = Math.max(1, (int) power.param("absorption", 2.0F));
        int resistSeconds = (int) power.param("resistSeconds", 12.0F);
        int durationSeconds = Math.max(1, (int) power.param("durationSeconds", 15.0F));

        player.addEffect(new MobEffectInstance(MobEffects.ABSORPTION, durationSeconds * 20,
                absorption - 1, false, false, true));
        if (resistSeconds > 0) {
            player.addEffect(new MobEffectInstance(MobEffects.DAMAGE_RESISTANCE,
                    resistSeconds * 20, 0, false, false, true));
        }
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WAND_SCHILD, player, durationSeconds,
                0.0F, FX_RANGE);
        Vec3 center = player.position().add(0.0D, 1.1D, 0.0D);
        WandPowers.sendQuasar(level, WandPowers.STERN_CONSTELLATION, center);
        level.sendParticles(ParticleTypes.END_ROD, center.x, center.y, center.z,
                16, 0.7D, 0.8D, 0.7D, 0.02D);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 0.9F, 1.3F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 0.7F, 1.7F);
        return true;
    }

    /** Wurzelgriff: star-light roots pin everything in a small zone to the ground. */
    private static boolean castWurzelgriff(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 24.0F)).add(0.0D, 0.4D, 0.0D);
        float radius = power.param("radius", 4.5F);
        float damage = power.param("damage", 4.0F);
        int rootTicks = (int) power.param("rootTicks", 70.0F);
        int markTicks = (int) power.param("markTicks", 100.0F);

        // Root = Slowness V (near-standstill) — server-side and honest about what it is.
        for (LivingEntity victim : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(center, center).inflate(radius),
                e -> e != player && e.isAlive())) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, rootTicks, 4), player);
            victim.addEffect(new MobEffectInstance(MobEffects.GLOWING, markTicks, 0), player);
        }
        WandPowers.damageAround(player, center, radius, damage, 0.0F, 0);
        WandPowers.sendQuasar(level, WandPowers.STERN_FUNKE_FALL, center.add(0.0D, 1.2D, 0.0D));
        WandPowers.groundLightRing(level, center, radius);
        // F-070: Photon binding-seal layer — ground ring + orbiting glyph stars + root
        // filaments of light (a = zone radius scales the seal).
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_STERN_SEAL, center,
                radius, 0.0F, FX_RANGE);
        level.sendParticles(ParticleTypes.END_ROD, center.x, center.y + 0.2D, center.z,
                12, radius * 0.4D, 0.15D, radius * 0.4D, 0.01D);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 0.9F, 0.7F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.PLAYERS, 0.7F, 0.9F);
        return true;
    }

    /** Lichtsegen: healing starlight over the caster and nearby allies. */
    private static boolean castLichtsegen(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        float heal = power.param("heal", 6.0F);
        int regenTicks = (int) (power.param("regenSeconds", 8.0F) * 20.0F);
        int speedTicks = (int) (power.param("speedSeconds", 8.0F) * 20.0F);
        float radius = power.param("radius", 6.0F);

        Vec3 center = player.position().add(0.0D, 1.0D, 0.0D);
        List<Player> blessed = new ArrayList<>();
        blessed.add(player);
        for (Player ally : level.getEntitiesOfClass(Player.class,
                new AABB(center, center).inflate(radius),
                p -> p != player && p.isAlive() && !p.isSpectator())) {
            blessed.add(ally);
        }
        for (Player target : blessed) {
            target.heal(heal);
            if (regenTicks > 0) {
                target.addEffect(new MobEffectInstance(MobEffects.REGENERATION, regenTicks, 1,
                        false, false, true));
            }
            if (speedTicks > 0) {
                target.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SPEED, speedTicks, 0,
                        false, false, true));
            }
            Vec3 at = target.position().add(0.0D, 1.2D, 0.0D);
            level.sendParticles(ParticleTypes.END_ROD, at.x, at.y, at.z, 10, 0.4D, 0.6D, 0.4D, 0.015D);
        }
        WandPowers.sendQuasar(level, WandPowers.STERN_FUNKE_FALL, center.add(0.0D, 1.0D, 0.0D));
        WandPowers.sendQuasar(level, WandPowers.STERN_CONSTELLATION, center);
        // F-070: Photon blessing layer on the caster (entity lane) — descending light
        // shafts + star-mote rain + one soft dome breath.
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WANDFX2_STERN_BLESS, player,
                0.0F, 0.0F, FX_RANGE);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 0.9F, 1.5F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.PLAYER_LEVELUP,
                SoundSource.PLAYERS, 0.4F, 1.8F);
        return true;
    }

    /** Spiegelpanzer: a mirror ward — hardened skin plus a marking repulse nova. */
    private static boolean castSpiegelpanzer(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        int resistTicks = (int) (power.param("resistSeconds", 8.0F) * 20.0F);
        float novaRadius = power.param("novaRadius", 5.0F);
        float novaDamage = power.param("novaDamage", 6.0F);
        float knockback = power.param("knockback", 1.5F);
        int markTicks = (int) power.param("markTicks", 100.0F);

        if (resistTicks > 0) {
            player.addEffect(new MobEffectInstance(MobEffects.DAMAGE_RESISTANCE, resistTicks, 1,
                    false, false, true));
        }
        Vec3 center = player.position().add(0.0D, 1.0D, 0.0D);
        WandPowers.damageAround(player, center, novaRadius, novaDamage, knockback, 0,
                0.2F, 1.0F, 0, markTicks);
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WAND_SCHILD, player,
                resistTicks / 20.0F, 1.0F, FX_RANGE);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, player.position(), 0.6F, 10.0F, FX_RANGE);
        WandPowers.sendQuasar(level, WandPowers.STERN_CONSTELLATION, center);
        level.sendParticles(ParticleTypes.END_ROD, center.x, center.y, center.z,
                20, 0.8D, 0.9D, 0.8D, 0.03D);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 1.0F, 0.9F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.PLAYERS, 0.8F, 0.7F);
        WandPowers.shakeNear(level, center, 14.0D, 0.12F, 6);
        return true;
    }

    /** Sternenbann: a wide binding seal — mark, root and weaken everything inside. */
    private static boolean castSternenbann(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 center = WandPowers.aimPoint(player, power.param("range", 28.0F)).add(0.0D, 0.4D, 0.0D);
        float radius = power.param("radius", 10.0F);
        float damage = power.param("damage", 5.0F);
        int rootTicks = (int) power.param("rootTicks", 100.0F);
        int weaknessTicks = (int) power.param("weaknessTicks", 120.0F);
        int markTicks = (int) power.param("markTicks", 140.0F);

        for (LivingEntity victim : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(center, center).inflate(radius),
                e -> e != player && e.isAlive())) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, rootTicks, 2), player);
            victim.addEffect(new MobEffectInstance(MobEffects.WEAKNESS, weaknessTicks, 1), player);
            victim.addEffect(new MobEffectInstance(MobEffects.GLOWING, markTicks, 0), player);
        }
        WandPowers.damageAround(player, center, radius, damage, 0.0F, 0);
        WandPowers.sendQuasar(level, WandPowers.STERN_SCHAUER_FIELD, center.add(0.0D, 0.6D, 0.0D));
        WandPowers.sendQuasar(level, WandPowers.STERN_CONSTELLATION, center.add(0.0D, 1.2D, 0.0D));
        WandPowers.groundLightRing(level, center, radius);
        // F-070: the wide Photon binding seal (a = radius scales it to the 10-block
        // zone) and a T4 bystander rumble — both purely audiovisual.
        FxPayloads.sendFxEvent(level, FxCues.CUE_WANDFX2_STERN_SEAL, center,
                radius, 0.0F, FX_RANGE);
        WandPowers.shakeNear(level, center, 20.0D, 0.14F, 7);
        WandTickService.schedule(level, 6, () -> WandPowers.groundLightRing(level, center, radius * 0.6D));
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 1.0F, 0.6F);
        level.playSound(null, center.x, center.y, center.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 0.9F, 0.5F);
        return true;
    }

    /** Nova-Wächter: an orbiting guardian star smites the nearest threat every second. */
    private static boolean castNovawaechter(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        int duration = (int) power.param("durationTicks", 120.0F);
        int every = Math.max(10, (int) power.param("strikeEveryTicks", 20.0F));
        float strikeRange = power.param("strikeRange", 8.0F);
        float strikeDamage = power.param("strikeDamage", 6.0F);
        float markBonus = power.param("markBonus", 1.25F);
        int markTicks = (int) power.param("markTicks", 60.0F);

        Vec3 start = player.position().add(0.0D, 1.4D, 0.0D);
        WandPowers.sendQuasar(level, WandPowers.STERN_CONSTELLATION, start);
        // F-070: Photon guardian layer — ONE bright star pacing a head-height orbit on
        // the caster for the baked ~120t window (entity lane; strikes stay Quasar).
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WANDFX2_STERN_GUARDIAN, player,
                duration, 0.0F, FX_RANGE);
        level.playSound(null, start.x, start.y, start.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 0.9F, 1.2F);
        for (int tick = 4; tick <= duration; tick += 4) {
            boolean strike = tick % every == 0;
            int angleTick = tick;
            WandTickService.schedule(level, tick, () -> {
                if (!player.isAlive() || player.serverLevel() != level) {
                    return; // guardian evaporates with its caster
                }
                // Orbit trace: one end-rod mote circling head height.
                double angle = angleTick * 0.35D;
                Vec3 orbit = player.position().add(Math.cos(angle) * 1.4D, 1.5D,
                        Math.sin(angle) * 1.4D);
                level.sendParticles(ParticleTypes.END_ROD, orbit.x, orbit.y, orbit.z,
                        1, 0.02D, 0.02D, 0.02D, 0.001D);
                if (!strike) {
                    return;
                }
                LivingEntity target = nearestHostileTo(level, player, strikeRange);
                if (target == null) {
                    return;
                }
                Vec3 impact = target.position();
                FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.25F, 0.0F,
                        FX_RANGE);
                WandPowers.sendQuasar(level, WandPowers.STERN_FUNKE_FALL,
                        impact.add(0.0D, 1.6D, 0.0D));
                WandPowers.damageAround(player, impact, 1.5F, strikeDamage, 0.3F, 0,
                        0.0F, markBonus, 0, markTicks);
                level.playSound(null, impact.x, impact.y, impact.z,
                        SoundEvents.AMETHYST_CLUSTER_BREAK, SoundSource.PLAYERS, 0.7F,
                        1.2F + level.random.nextFloat() * 0.3F);
            });
        }
        return true;
    }

    /** Himmelsgericht (capstone): seven comets, then one zone-wide verdict pulse. */
    private static boolean castHimmelsgericht(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Vec3 zone = WandPowers.aimPoint(player, power.param("range", 32.0F));
        float zoneRadius = power.param("zoneRadius", 9.0F);
        int comets = Math.max(3, (int) power.param("comets", 7.0F));
        float cometDamage = power.param("cometDamage", 10.0F);
        float cometRadius = power.param("cometRadius", 3.5F);
        int stepTicks = Math.max(2, (int) power.param("stepTicks", 5.0F));
        int telegraph = (int) power.param("telegraphTicks", 20.0F);
        float finaleDamage = power.param("finaleDamage", 16.0F);
        float markBonus = power.param("markBonus", 1.5F);
        float knockup = power.param("knockup", 0.8F);

        int finaleDelay = telegraph + comets * stepTicks + 8;
        WandPowers.sendQuasar(level, WandPowers.STERN_SCHAUER_FIELD, zone.add(0.0D, 0.6D, 0.0D));
        WandPowers.groundLightRing(level, zone, zoneRadius);
        FxPayloads.sendFxEvent(level, FxCues.CUE_WAND_GERICHT, zone, finaleDelay, 0.0F,
                FX_RANGE + 32.0D);
        level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.PLAYERS, 1.0F, 0.5F);
        level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.PLAYERS, 1.0F, 0.45F);
        for (int i = 0; i < comets; i++) {
            int delay = telegraph + i * stepTicks;
            float chime = 0.9F + 0.5F * (i / (float) Math.max(1, comets - 1));
            WandTickService.schedule(level, delay, () -> {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double dist = Math.sqrt(level.random.nextDouble()) * zoneRadius;
                double x = zone.x + Math.cos(angle) * dist;
                double z = zone.z + Math.sin(angle) * dist;
                double y = level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                        (int) Math.floor(x), (int) Math.floor(z));
                Vec3 impact = new Vec3(x, y, z);
                FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact, 0.5F, 0.0F,
                        FX_RANGE + 16.0D);
                WandPowers.sendQuasar(level, WandPowers.STERN_KOMET_CORE, impact.add(0.0D, 6.0D, 0.0D));
                WandPowers.sendQuasar(level, WandPowers.STERN_FUNKE_FALL, impact.add(0.0D, 1.8D, 0.0D));
                WandPowers.damageAround(player, impact, cometRadius, cometDamage, 0.6F, 0,
                        knockup, markBonus, 0, 80);
                level.playSound(null, x, y, z, SoundEvents.AMETHYST_CLUSTER_BREAK,
                        SoundSource.PLAYERS, 0.9F, chime);
                level.playSound(null, x, y, z, SoundEvents.LIGHTNING_BOLT_IMPACT,
                        SoundSource.PLAYERS, 0.4F, 1.4F);
            });
        }
        // The verdict: one synced zone-wide pulse — marked (Glowing) targets pay extra.
        WandTickService.schedule(level, finaleDelay, () -> {
            FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, zone, 1.0F, 1.0F,
                    FX_RANGE + 32.0D);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, zone, 1.0F, 16.0F,
                    FX_RANGE + 16.0D);
            WandPowers.sendQuasar(level, WandPowers.STERN_KOMET_CORE, zone);
            WandPowers.sendQuasar(level, WandPowers.STERN_FUNKE_FALL, zone.add(0.0D, 2.2D, 0.0D));
            WandPowers.damageAround(player, zone, zoneRadius, finaleDamage, 0.8F, 0,
                    knockup, markBonus, 0, 0);
            level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.LIGHTNING_BOLT_THUNDER,
                    SoundSource.PLAYERS, 1.0F, 0.9F);
            level.playSound(null, zone.x, zone.y, zone.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.PLAYERS, 1.0F, 0.5F);
            WandPowers.shakeNear(level, zone, 32.0D, 0.4F, 13);
        });
        return true;
    }

    // ==================================================================
    // shared helpers
    // ==================================================================

    /** Radial drag toward {@code center} for every living non-caster in range. */
    private static void pullToward(ServerLevel level, ServerPlayer caster, Vec3 center,
            float radius, float pull) {
        for (LivingEntity victim : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(center, center).inflate(radius),
                e -> e != caster && e.isAlive())) {
            if (SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                continue;
            }
            Vec3 in = center.subtract(victim.position());
            Vec3 flat = new Vec3(in.x, 0.0D, in.z);
            if (flat.lengthSqr() > 1.0E-4D) {
                Vec3 dir = flat.normalize();
                victim.push(dir.x * pull, 0.1D * pull, dir.z * pull);
            }
        }
    }

    /** First living non-caster whose body the look ray passes through, or null. */
    private static LivingEntity firstOnRay(ServerPlayer player, double range) {
        ServerLevel level = player.serverLevel();
        Vec3 eye = player.getEyePosition();
        Vec3 look = player.getLookAngle();
        HitResult blockHit = level.clip(new ClipContext(eye, eye.add(look.scale(range)),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
        double maxDist = blockHit.getType() == HitResult.Type.MISS ? range
                : blockHit.getLocation().distanceTo(eye);
        for (double dist = 1.0D; dist <= maxDist; dist += 0.5D) {
            Vec3 point = eye.add(look.scale(dist));
            List<LivingEntity> hits = level.getEntitiesOfClass(LivingEntity.class,
                    new AABB(point, point).inflate(0.8D),
                    e -> e != player && e.isAlive());
            if (!hits.isEmpty()) {
                return hits.get(0);
            }
        }
        return null;
    }

    /** Closest living non-player threat to {@code player} within {@code range}, or null. */
    private static LivingEntity nearestHostileTo(ServerLevel level, ServerPlayer player,
            float range) {
        Vec3 center = player.position();
        LivingEntity best = null;
        double bestDist = Double.MAX_VALUE;
        for (LivingEntity candidate : level.getEntitiesOfClass(LivingEntity.class,
                new AABB(center, center).inflate(range),
                e -> e != player && e.isAlive() && !(e instanceof Player))) {
            if (SpawnProtectionRules.isInProtectionZone(level, candidate.blockPosition())) {
                continue;
            }
            double dist = candidate.position().distanceToSqr(center);
            if (dist < bestDist) {
                bestDist = dist;
                best = candidate;
            }
        }
        return best;
    }
}
