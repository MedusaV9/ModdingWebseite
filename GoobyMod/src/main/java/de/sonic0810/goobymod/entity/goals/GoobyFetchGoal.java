package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyEntity;
import it.unimi.dsi.fastutil.ints.Int2LongOpenHashMap;
import java.util.Comparator;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.item.ItemEntity;

/**
 * Apportieren: ein erwachsener, gezaehmter Gooby erkennt AUSSCHLIESSLICH
 * vom eigenen Besitzer geworfene Gooby-Baelle in begrenztem Radius, laeuft
 * hin, nimmt atomar genau einen auf und bringt ihn als ItemEntity mit
 * Empfaenger-Prioritaet zurueck.
 *
 * <p>Serverautoritaet und Verlustfreiheit: der Trage-Zustand lebt in der
 * Entity (synced + NBT-persistiert). Bricht das Goal ab (Owner offline,
 * STAY-Befehl, Alarm, ...), bleibt der Ball im Maul erhalten und die
 * Rueckgabe wird beim naechsten Start nahtlos fortgesetzt — auch nach
 * Chunk-/Server-Reload.</p>
 *
 * <p>Give-up: erreicht der Gooby einen Ball {@link #GIVE_UP_TICKS} lang
 * nicht (Loch, Zaun, ...), wird GENAU dieser Ball fuer
 * {@link #UNREACHABLE_RETRY_TICKS} zeitlich geblacklistet — der naechste
 * Scan ueberspringt ihn, Follow/Tempt & Co. kommen sofort wieder dran und
 * es gibt keine Endlos-Pathfinding-Schleife. Die Blacklist ist strikt
 * gebounded (Session-Entity-IDs, Ablauf-Purge, harte Obergrenze — kein
 * Leak) und die Trage-/Lieferphase kennt bewusst KEIN Timeout.</p>
 */
public final class GoobyFetchGoal extends Goal {
    public static final double SEARCH_RADIUS = 16.0;
    public static final double PICKUP_RANGE = 1.75;
    public static final double DELIVER_RANGE = 2.75;
    private static final int SCAN_INTERVAL_TICKS = 10;
    /** Unerreichbare Baelle (Loch, Zaun, ...) blockieren die KI nicht ewig. */
    public static final int GIVE_UP_TICKS = 600;
    /** So lange wird ein aufgegebener Ball nicht erneut anvisiert. */
    public static final int UNREACHABLE_RETRY_TICKS = 1200;
    /** Harte Obergrenze der Blacklist — mehr Ball-Leichen gibt es nie legitim. */
    private static final int MAX_UNREACHABLE_ENTRIES = 16;

    private final GoobyEntity gooby;
    private final double speed;
    @Nullable
    private ItemEntity targetBall;
    private int scanCooldown;
    private int activeTicks;
    /** Entity-ID → GameTime, bis zu der der Ball uebersprungen wird. */
    private final Int2LongOpenHashMap unreachableUntil = new Int2LongOpenHashMap();

    public GoobyFetchGoal(GoobyEntity gooby, double speed) {
        this.gooby = gooby;
        this.speed = speed;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK));
    }

    /**
     * Zustands-Gating (oeffentlich fuer GameTests): nur ein eigener,
     * erwachsener, nicht sitzender/schlafender/alarmierter und nicht
     * angeleinter Gooby ohne STAY-Befehl darf apportieren. Babys starten
     * das Feature nie.
     */
    public static boolean canWork(GoobyEntity gooby) {
        return gooby.isAlive() && gooby.isTame() && !gooby.isBaby()
                && !gooby.isOrderedToSit() && !gooby.isSitting()
                && !gooby.isGoobySleeping() && !gooby.isAlerting()
                && !gooby.isPanicking() && !gooby.isSeekingShelter()
                && !gooby.isActivelyDigging()
                && gooby.getCommandMode() != GoobyCommand.STAY
                && !gooby.isVehicle() && !gooby.isPassenger()
                && !gooby.isLeashed();
    }

    /** Nur ein lebender Online-Besitzer im selben Level ist ein Rueckgabe-Ziel. */
    @Nullable
    private ServerPlayer onlineOwner() {
        return this.gooby.getOwner() instanceof ServerPlayer owner
                && owner.isAlive() && !owner.isSpectator() && owner.level() == this.gooby.level()
                ? owner : null;
    }

    @Override
    public boolean canUse() {
        if (this.gooby.level().isClientSide || !canWork(this.gooby) || onlineOwner() == null) {
            return false;
        }
        if (this.gooby.isCarryingFetchItem()) {
            // Nach Reload/Abbruch direkt in der Rueckgabe-Phase weitermachen.
            return true;
        }
        if (this.scanCooldown-- > 0) {
            return false;
        }
        this.scanCooldown = reducedTickDelay(SCAN_INTERVAL_TICKS);
        this.targetBall = findNearestOwnBall();
        return this.targetBall != null;
    }

    @Override
    public boolean canContinueToUse() {
        if (!canWork(this.gooby) || onlineOwner() == null) {
            return false;
        }
        if (this.gooby.isCarryingFetchItem()) {
            // Trage-/Lieferphase kennt bewusst kein Give-up: der Ball im Maul
            // darf nie in einer Blacklist enden, die Rueckgabe wartet
            // notfalls beliebig lange auf einen erreichbaren Owner.
            return true;
        }
        if (this.targetBall == null || !this.gooby.isOwnFetchBall(this.targetBall)) {
            return false;
        }
        if (this.activeTicks > GIVE_UP_TICKS) {
            // Unerreichbar: zeitlich blacklisten, damit der naechste Scan ihn
            // ueberspringt und Follow/Tempt & Co. sofort wieder drankommen.
            markUnreachable(this.targetBall);
            return false;
        }
        return true;
    }

    @Override
    public void start() {
        this.activeTicks = 0;
    }

    @Override
    public void tick() {
        this.activeTicks++;
        ServerPlayer owner = onlineOwner();
        if (owner == null) {
            return;
        }
        if (this.gooby.isCarryingFetchItem()) {
            this.gooby.getLookControl().setLookAt(owner, 30.0F, 30.0F);
            if (this.gooby.distanceToSqr(owner) <= DELIVER_RANGE * DELIVER_RANGE) {
                this.gooby.getNavigation().stop();
                this.gooby.deliverFetchBallTo(owner);
                return;
            }
            if (this.gooby.tickCount % 10 == 0 || this.gooby.getNavigation().isDone()) {
                this.gooby.getNavigation().moveTo(owner, this.speed);
            }
            return;
        }
        ItemEntity ball = this.targetBall;
        if (ball == null || !this.gooby.isOwnFetchBall(ball)) {
            // canContinueToUse beendet den Lauf im naechsten Update.
            this.targetBall = null;
            return;
        }
        this.gooby.getLookControl().setLookAt(ball, 30.0F, 30.0F);
        if (this.gooby.distanceToSqr(ball) <= PICKUP_RANGE * PICKUP_RANGE) {
            if (this.gooby.tryPickUpFetchBall(ball)) {
                this.targetBall = null;
                this.gooby.getNavigation().stop();
            }
            return;
        }
        if (this.gooby.tickCount % 10 == 0 || this.gooby.getNavigation().isDone()) {
            this.gooby.getNavigation().moveTo(ball, this.speed);
        }
    }

    @Override
    public void stop() {
        // Der getragene Ball wird bei Goal-Abbruch NIE geloescht — er liegt
        // im persistierten Trage-Slot der Entity und wartet auf den Owner.
        this.targetBall = null;
        this.gooby.getNavigation().stop();
    }

    @Nullable
    private ItemEntity findNearestOwnBall() {
        purgeExpiredBlacklist();
        return this.gooby.level().getEntitiesOfClass(ItemEntity.class,
                        this.gooby.getBoundingBox().inflate(SEARCH_RADIUS, 4.0, SEARCH_RADIUS),
                        item -> this.gooby.isOwnFetchBall(item) && !isTemporarilyUnreachable(item))
                .stream()
                .min(Comparator.comparingDouble(this.gooby::distanceToSqr))
                .orElse(null);
    }

    /** Oeffentlich fuer GameTests: steht dieser Ball gerade auf der Give-up-Blacklist? */
    public boolean isTemporarilyUnreachable(ItemEntity ball) {
        return this.unreachableUntil.get(ball.getId()) > this.gooby.level().getGameTime();
    }

    private void markUnreachable(ItemEntity ball) {
        purgeExpiredBlacklist();
        if (this.unreachableUntil.size() >= MAX_UNREACHABLE_ENTRIES) {
            // Harte Schranke statt Wachstum: schlimmstenfalls wird ein alter
            // Eintrag frueher wieder probiert — nie ein Memory-Leak.
            this.unreachableUntil.clear();
        }
        this.unreachableUntil.put(ball.getId(),
                this.gooby.level().getGameTime() + UNREACHABLE_RETRY_TICKS);
    }

    private void purgeExpiredBlacklist() {
        if (this.unreachableUntil.isEmpty()) {
            return;
        }
        long now = this.gooby.level().getGameTime();
        this.unreachableUntil.int2LongEntrySet().removeIf(entry -> entry.getLongValue() <= now);
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }
}
