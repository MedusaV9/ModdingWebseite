package de.sonic0810.goobymod.entity.animation;

/**
 * Allocation-free client pose state machine. It keeps short bridge clips from
 * being replaced by a stable loop on the next render frame.
 */
public final class GoobyAnimationState {
    public enum Pose {
        IDLE,
        HOP,
        SIT,
        SLEEP,
        DIG,
        SAD,
        ALERT
    }

    public enum Transition {
        NONE(0, Pose.IDLE),
        SIT_DOWN(8, Pose.SIT),
        STAND_UP(7, Pose.IDLE),
        SLEEP_DOWN(13, Pose.SLEEP),
        WAKE_UP(13, Pose.IDLE);

        private final int durationTicks;
        private final Pose target;

        Transition(int durationTicks, Pose target) {
            this.durationTicks = durationTicks;
            this.target = target;
        }

        public int durationTicks() {
            return this.durationTicks;
        }

        public Pose target() {
            return this.target;
        }
    }

    private Pose stablePose = Pose.IDLE;
    private Transition transition = Transition.NONE;
    private int transitionEndTick;

    public void update(Pose desiredPose, int tick) {
        if (this.transition != Transition.NONE) {
            if (tick < this.transitionEndTick) {
                return;
            }
            this.stablePose = this.transition.target();
            this.transition = Transition.NONE;
        }

        if (desiredPose == this.stablePose) {
            return;
        }

        Transition bridge = bridge(this.stablePose, desiredPose);
        if (bridge == Transition.NONE) {
            this.stablePose = desiredPose;
            return;
        }
        this.transition = bridge;
        this.transitionEndTick = tick + bridge.durationTicks();
    }

    private static Transition bridge(Pose from, Pose to) {
        if (from == Pose.SLEEP) {
            return Transition.WAKE_UP;
        }
        if (from == Pose.SIT) {
            return Transition.STAND_UP;
        }
        if (to == Pose.SLEEP) {
            return Transition.SLEEP_DOWN;
        }
        if (to == Pose.SIT) {
            return Transition.SIT_DOWN;
        }
        return Transition.NONE;
    }

    public Pose stablePose() {
        return this.stablePose;
    }

    public Transition transition() {
        return this.transition;
    }

    public boolean isTransitioning() {
        return this.transition != Transition.NONE;
    }

    /** Pure selector shared by the movement controller and GameTests. */
    public static Pose selectPose(boolean moving, boolean sleeping, boolean digging,
            boolean sitting, boolean sad) {
        return selectPose(moving, sleeping, digging, sitting, sad, false);
    }

    public static Pose selectPose(boolean moving, boolean sleeping, boolean digging,
            boolean sitting, boolean sad, boolean alerting) {
        if (alerting) {
            return Pose.ALERT;
        }
        if (sleeping) {
            return Pose.SLEEP;
        }
        if (digging) {
            return Pose.DIG;
        }
        if (sitting) {
            return Pose.SIT;
        }
        if (moving) {
            return Pose.HOP;
        }
        return sad ? Pose.SAD : Pose.IDLE;
    }
}
