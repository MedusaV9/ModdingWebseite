// Append-only JSONL-Event-Log pro Match — Single Source of Truth für Stats.
// Schema (TECH-SPEC §5.3): { v, ts, matchId, seq, type, actor?, questionId?, payload }.
// TODO(Analytics-Agent): materialisierte Aggregate + tools/rebuild-stats (Replay).
import type { Clock } from "../../shared/time";
import type { Storage } from "../persistence/storage";

export interface LogEvent {
  type: string;
  actor?: string;
  questionId?: string;
  payload?: Record<string, unknown>;
}

export interface MatchEventLog {
  append(seq: number, event: LogEvent): void;
}

/**
 * Erstellt einen Logger für ein Match: data/events/<matchId>.jsonl.
 * Writes laufen fire-and-forget, aber strikt sequenziell (Ketten-Promise) —
 * ein Party-Abend darf nie an einem fsync hängen.
 *
 * Rotation light (Eval-7): Die Datei entsteht ERST beim Match-Start
 * (match_started/match_loaded) — Lobby-Events werden gepuffert und dann in
 * einem Rutsch nachgezogen. Räume, deren Match nie startet, hinterlassen so
 * KEINE Log-Leichen mehr (vorher: 101 Lobby-only-Dateien in data/events).
 */
export function createMatchEventLog(
  storage: Storage,
  matchId: string,
  clock: Clock,
): MatchEventLog {
  const datei = `events/${matchId}.jsonl`;
  let kette: Promise<void> = Promise.resolve();
  let aktiv = false;
  const puffer: string[] = [];
  const MAX_PUFFER = 1000; // Lobby-Events sind endlich — Deckel gegen Amok-Clients

  function schreibe(zeile: string): void {
    kette = kette
      .then(() => storage.appendLine(datei, zeile))
      .catch((err) => console.error(`Event-Log-Fehler (${datei}):`, err));
  }

  return {
    append(seq: number, event: LogEvent): void {
      const zeile = JSON.stringify({
        v: 1,
        ts: clock.now(),
        matchId,
        seq,
        type: event.type,
        ...(event.actor ? { actor: event.actor } : {}),
        ...(event.questionId ? { questionId: event.questionId } : {}),
        payload: event.payload ?? {},
      });
      if (!aktiv) {
        if (event.type !== "match_started" && event.type !== "match_loaded") {
          puffer.push(zeile);
          if (puffer.length > MAX_PUFFER) puffer.shift();
          return;
        }
        aktiv = true;
        for (const gepuffert of puffer) schreibe(gepuffert);
        puffer.length = 0;
      }
      schreibe(zeile);
    },
  };
}
