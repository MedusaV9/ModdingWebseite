package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.block.RabbitHutchBlock;
import de.sonic0810.goobymod.block.entity.RabbitHutchBlockEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.phys.Vec3;

/**
 * Nachts sucht Gooby seinen Hasenstall (bevorzugt sein gemerktes Zuhause),
 * kuschelt sich hinein und schlaeft (Zzz-Partikel!). Morgens gibt es Herzchen
 * und einen guten Start in den Tag. Ohne Stall schlaeft er irgendwann einfach
 * an Ort und Stelle ein.
 *
 * <p>Aufwecken (Streicheln, Fuettern, …) unterbricht den Schlaf ECHT: solange
 * {@link GoobyEntity#isSleepSuppressed()} gilt, schlaeft Gooby nicht wieder ein
 * und der Goal beendet sich sauber.
 */
public class GoobySleepGoal extends Goal {
    private final GoobyEntity gooby;
    @Nullable
    private BlockPos hutchPos;
    @Nullable
    private BlockPos familySleepPos;
    private int searchCooldown;
    private int repathCooldown;
    private int noHutchSleepDelay;
    private int hutchApproachTicks;
    private int hutchEnterTicks;
    private int farHomeLineCooldown;
    private boolean sleptAtHutch;

    public GoobySleepGoal(GoobyEntity gooby) {
        this.gooby = gooby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK, Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        if (!this.gooby.level().isNight() || this.gooby.isVehicle() || this.gooby.isPassenger()
                || this.gooby.isInWater() || this.gooby.isSleepSuppressed()
                || this.gooby.isAlerting() || this.gooby.isSeekingShelter()) {
            return false;
        }
        if (this.searchCooldown > 0) {
            this.searchCooldown--;
            if (this.farHomeLineCooldown > 0) {
                this.farHomeLineCooldown--;
            }
            return false;
        }
        this.searchCooldown = 60;
        this.familySleepPos = this.gooby.findFamilySleepSpot();
        if (this.familySleepPos == null) {
            this.familySleepPos = this.gooby.findSocialNapSpot();
        }
        this.hutchPos = this.familySleepPos == null ? findHutch() : null;
        // Ohne Stall pennt Gooby erst nach einer Weile ein
        return this.familySleepPos != null || this.hutchPos != null || this.gooby.getRandom().nextInt(5) == 0;
    }

    @Nullable
    private BlockPos findHutch() {
        return findPreferredHutch(this.gooby, this);
    }

    /**
     * Bound homes win over every nearby unbound hutch. Kept public so the
     * fail-closed GameTest exercises the exact production selector.
     */
    @Nullable
    public static BlockPos findPreferredHutch(GoobyEntity gooby) {
        return findPreferredHutch(gooby, null);
    }

    @Nullable
    private static BlockPos findPreferredHutch(GoobyEntity gooby, @Nullable GoobySleepGoal goal) {
        BlockPos home = gooby.getHomePos();
        if (home != null) {
            if (!gooby.level().getBlockState(home).is(ModBlocks.RABBIT_HUTCH.get())) {
                gooby.setHomePos(null);
            } else if (gooby.level().getBlockEntity(home) instanceof RabbitHutchBlockEntity hutch) {
                if (hutch.isBoundTo(gooby)) {
                    int radius = GoobyConfig.duskTravelRadius();
                    if (home.distSqr(gooby.blockPosition()) <= (double) radius * radius) {
                        return home;
                    }
                    if (goal == null || goal.farHomeLineCooldown == 0) {
                        gooby.missBoundHutchTonight();
                        if (goal != null) {
                            goal.farHomeLineCooldown = 20;
                        }
                    }
                    return null;
                }
                if (hutch.getResident() != null) {
                    gooby.setHomePos(null);
                } else if (hutch.isAvailableFor(gooby)
                        && home.distSqr(gooby.blockPosition()) <= 16.0 * 16.0) {
                    return home;
                }
            }
        }
        return BlockPos.findClosestMatch(gooby.blockPosition(), 16, 4,
                pos -> gooby.level().getBlockState(pos).is(ModBlocks.RABBIT_HUTCH.get())
                        && gooby.level().getBlockEntity(pos) instanceof RabbitHutchBlockEntity hutch
                        && hutch.isAvailableFor(gooby)).orElse(null);
    }

    @Override
    public void start() {
        this.sleptAtHutch = false;
        this.hutchApproachTicks = 0;
        this.hutchEnterTicks = 0;
        this.noHutchSleepDelay = 100 + this.gooby.getRandom().nextInt(200);
        if (this.familySleepPos != null) {
            moveToFamilySpot();
        } else if (this.hutchPos != null) {
            moveToHutch();
        }
    }

    private void moveToFamilySpot() {
        if (this.familySleepPos != null) {
            this.gooby.getNavigation().moveTo(this.familySleepPos.getX() + 0.5,
                    this.familySleepPos.getY(), this.familySleepPos.getZ() + 0.5, 1.0);
        }
    }

    private void moveToHutch() {
        if (this.hutchPos != null) {
            Direction facing = this.gooby.level().getBlockState(this.hutchPos)
                    .getValue(HorizontalDirectionalBlock.FACING);
            Vec3 anchor = RabbitHutchBlock.exitAnchor(this.hutchPos, facing);
            this.gooby.getNavigation().moveTo(anchor.x, anchor.y, anchor.z, 1.0);
        }
    }

    @Override
    public boolean canContinueToUse() {
        return this.gooby.level().isNight() && !this.gooby.isVehicle() && !this.gooby.isPassenger()
                && !this.gooby.isSleepSuppressed() && !this.gooby.isAlerting();
    }

    @Override
    public void tick() {
        if (this.gooby.isGoobySleeping()) {
            this.gooby.getNavigation().stop();
            return;
        }
        if (this.familySleepPos != null) {
            Vec3 familyAnchor = Vec3.atBottomCenterOf(this.familySleepPos);
            if (familyAnchor.distanceToSqr(this.gooby.position()) < 1.5) {
                this.gooby.setPos(familyAnchor.x, familyAnchor.y, familyAnchor.z);
                fallAsleep(false);
            } else if (--this.repathCooldown <= 0) {
                this.repathCooldown = 40;
                moveToFamilySpot();
            }
        } else if (this.hutchPos != null) {
            if (this.hutchEnterTicks > 0) {
                Vec3 interior = RabbitHutchBlock.interiorAnchor(this.hutchPos);
                Vec3 step = interior.subtract(this.gooby.position()).scale(1.0 / this.hutchEnterTicks);
                this.gooby.setPos(this.gooby.getX() + step.x,
                        this.gooby.getY() + step.y, this.gooby.getZ() + step.z);
                if (--this.hutchEnterTicks == 0) {
                    fallAsleep(true);
                }
                return;
            }
            this.hutchApproachTicks++;
            // Vanilla-Bodennavigation stoppt knapp vor dem Blockzentrum. Dort uebergibt sie
            // an den exakten, kollisionsfreien Innenanker. Falls ein PathNode trotz offenem
            // Collision-Shape haengt, garantiert ein begrenztes 5-s-Fallback den Innenanker.
            Direction facing = this.gooby.level().getBlockState(this.hutchPos)
                    .getValue(HorizontalDirectionalBlock.FACING);
            Vec3 entrance = RabbitHutchBlock.exitAnchor(this.hutchPos, facing);
            if (entrance.distanceToSqr(this.gooby.position()) < 2.0
                    || this.hutchApproachTicks >= 100) {
                beginHutchEntry(facing);
            } else if (--this.repathCooldown <= 0) {
                this.repathCooldown = 40;
                moveToHutch();
            }
        } else if (--this.noHutchSleepDelay <= 0 && this.gooby.onGround()) {
            fallAsleep(false);
        }
    }

    private void beginHutchEntry(Direction facing) {
        this.gooby.getNavigation().stop();
        this.gooby.setYRot(facing.toYRot());
        this.gooby.setYHeadRot(facing.toYRot());
        this.gooby.tryTriggerAction("hutch_enter", 16);
        this.gooby.playSound(ModSounds.GOOBY_HUTCH_RUSTLE.get(), 0.65F, 1.05F);
        this.hutchEnterTicks = 16;
    }

    private void fallAsleep(boolean atHutch) {
        this.gooby.getNavigation().stop();
        this.sleptAtHutch = atHutch;
        if (atHutch && this.hutchPos != null) {
            Vec3 anchor = RabbitHutchBlock.interiorAnchor(this.hutchPos);
            this.gooby.setPos(anchor.x, anchor.y, anchor.z);
            this.gooby.setInHutch(true);
            if (this.gooby.level().getBlockEntity(this.hutchPos) instanceof RabbitHutchBlockEntity hutch) {
                hutch.occupy(this.gooby);
            }
            // Gooby merkt sich seinen Stall als Zuhause (persistent)
            this.gooby.setHomePos(this.hutchPos);
        }
        this.gooby.setGoobySleeping(true);
    }

    @Override
    public void stop() {
        this.gooby.setGoobySleeping(false);
        this.gooby.setInHutch(false);
        if (this.sleptAtHutch && this.hutchPos != null
                && this.gooby.level() instanceof ServerLevel level
                && level.getBlockState(this.hutchPos).is(ModBlocks.RABBIT_HUTCH.get())) {
            Direction facing = level.getBlockState(this.hutchPos)
                    .getValue(HorizontalDirectionalBlock.FACING);
            if (level.getBlockEntity(this.hutchPos) instanceof RabbitHutchBlockEntity hutch) {
                if (level.isDay()) {
                    hutch.applyMorningComfort(level, this.gooby, this.gooby.getRandom());
                } else {
                    hutch.vacate();
                }
            }
            Vec3 exit = RabbitHutchBlock.exitAnchor(this.hutchPos, facing);
            this.gooby.setPos(exit.x, exit.y, exit.z);
            if (level.isDay()) {
                level.sendParticles(ParticleTypes.HEART, exit.x, exit.y + 1.2, exit.z,
                        7, 0.5, 0.4, 0.5, 0.02);
                this.gooby.beginHutchWakeRoutine(facing);
            } else {
                this.gooby.playSound(ModSounds.GOOBY_HUTCH_RUSTLE.get(), 0.55F, 0.95F);
            }
        }
        this.hutchPos = null;
        this.familySleepPos = null;
        this.hutchEnterTicks = 0;
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }
}
