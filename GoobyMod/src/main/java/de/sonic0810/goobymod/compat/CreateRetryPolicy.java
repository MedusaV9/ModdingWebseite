package de.sonic0810.goobymod.compat;

/**
 * Non-blocking retry gate for optional integration calls.
 *
 * <p>Runtime failures get three attempts with exponential tick backoff. Linkage
 * and reflection failures are API mismatches and disable only the integration
 * permanently; neither category can crash the game server.</p>
 */
public final class CreateRetryPolicy {
    public enum State {
        ACTIVE,
        TRANSIENT,
        PERMANENT_API_MISMATCH
    }

    @FunctionalInterface
    public interface Operation {
        boolean run() throws ReflectiveOperationException;
    }

    // Initial call plus three retries at 1, 2, and 4 ticks.
    private static final int MAX_ATTEMPTS = 4;
    private State state = State.ACTIVE;
    private int attempts;
    private long retryAtTick;

    public boolean execute(long gameTime, Operation operation) {
        if (!canAttempt(gameTime)) {
            return false;
        }
        this.attempts++;
        try {
            boolean result = operation.run();
            this.state = State.ACTIVE;
            this.attempts = 0;
            this.retryAtTick = 0;
            return result;
        } catch (ReflectiveOperationException | LinkageError mismatch) {
            this.state = State.PERMANENT_API_MISMATCH;
            return false;
        } catch (RuntimeException transientFailure) {
            this.state = State.TRANSIENT;
            this.retryAtTick = gameTime + (1L << Math.min(this.attempts - 1, 2));
            return false;
        }
    }

    public boolean canAttempt(long gameTime) {
        return this.state != State.PERMANENT_API_MISMATCH
                && this.attempts < MAX_ATTEMPTS
                && gameTime >= this.retryAtTick;
    }

    public State state() {
        return this.state;
    }

    public int attempts() {
        return this.attempts;
    }

    public long retryAtTick() {
        return this.retryAtTick;
    }
}
