package dev.projecteclipse.eclipse.cutscene;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * Replay contract of the big scripted sequences (P2 R12): every sequence exposes FX-only
 * replays of its phases for dev/QA runs.
 *
 * <p><b>THE CONTRACT — FX-ONLY</b> (§7 risk 9): {@link #replay} fires visuals, sounds,
 * captions, camera paths and client payloads exactly like the live phase, but performs
 * <b>no world mutations</b> (no block writes, no entity spawns that persist, no structure
 * placement), <b>no state commits</b> (no {@code EclipseWorldState} writes, no phase
 * advancement) and <b>no teleports</b> of the given players. Enforced in code review via
 * this single entry point.</p>
 *
 * <p><b>Who implements</b>: W6 registers {@code "intro"} ({@code sequence/IntroSequence}),
 * W7 registers {@code "expansion"} ({@code sequence/ExpansionSequence}) — both via
 * {@link Registry#register} from static init or server setup. <b>Who consumes</b>:
 * {@code cutscene/dev/FxDevCommands} ({@code /eclipsefx sequence <id> <phase>}) and P5-W6's
 * {@code /dev} aliases (§6.4).</p>
 */
public interface SequenceReplayable {

    /** Stable registry id, e.g. {@code "intro"} or {@code "expansion"} (lower-case). */
    String sequenceId();

    /** Phase ids accepted by {@link #replay}, in timeline order (upper-case, e.g. {@code "LIGHTNING"}). */
    List<String> phaseIds();

    /**
     * Replays one phase's FX for the given players (FX-only mode, see class contract).
     *
     * @return {@code false} when {@code phaseId} is unknown or the replay cannot start
     *         (callers report to the command source; nothing may have been mutated either way)
     */
    boolean replay(MinecraftServer server, String phaseId, Collection<ServerPlayer> players);

    /**
     * Insertion-ordered registry of replayable sequences. Registration is expected during
     * static init / common setup (before commands run); ids are case-insensitive.
     */
    final class Registry {
        private static final Map<String, SequenceReplayable> BY_ID = new LinkedHashMap<>();

        private Registry() {}

        /** Registers (or replaces) one sequence under {@link SequenceReplayable#sequenceId()}. */
        public static synchronized void register(SequenceReplayable sequence) {
            BY_ID.put(sequence.sequenceId().toLowerCase(Locale.ROOT), sequence);
        }

        public static synchronized Optional<SequenceReplayable> byId(String sequenceId) {
            return Optional.ofNullable(BY_ID.get(sequenceId.toLowerCase(Locale.ROOT)));
        }

        /** Registered sequence ids, insertion-ordered (command tab completion). */
        public static synchronized List<String> ids() {
            return List.copyOf(BY_ID.keySet());
        }
    }
}
