// BUZZER-FAIRNESS-Modul (TECH-SPEC §3.3, entschiedenes Verfahren) — pure Funktionen:
// Server-autoritative Zeit + Median-RTT-Kompensation mit hartem Clamp,
// 280-ms-Sammel-Fenster, Fotofinish-Los (<40 ms) über injizierten Rng.
// Minispiel-Plugins nutzen das Modul über ctx.buzzer (server/minigames/_api/plugin.ts).
import type { Rng } from "./rng";

export const BUZZER_SAMMELFENSTER_MS = 280; // Nachzügler-Fenster nach dem ersten Buzz
export const BUZZER_FOTOFINISH_MS = 40; // Differenz < 40 ms ⇒ sichtbarer Münzwurf
export const BUZZER_FRUEHBUZZ_SPERRE_MS = 1500; // Frühbuzz = 1,5 s Sperre (§2.11)

/** Median der letzten Messungen (Median statt Mittel — WLAN-Ausreißer). */
export function medianRtt(messungenMs: number[]): number {
  if (messungenMs.length === 0) return 0;
  const sortiert = [...messungenMs].sort((a, b) => a - b);
  return sortiert[Math.floor(sortiert.length / 2)];
}

export interface BuzzEingang {
  /** Client-Behauptung: Druckzeitpunkt in Server-Zeit umgerechnet. */
  pressedAtServerEst: number;
  /** Server-Empfangszeit des Buzz-Pakets. */
  receiveTime: number;
  /** Median-RTT dieses Clients (Server-Messung, letzte 5). */
  medianRtt: number;
}

/**
 * Harter Clamp OHNE Armierung: floor = receiveTime − medianRTT (mehr Gutschrift
 * als die gemessene Latenz gibt es NIE), Deckel = receiveTime. Ein manipulierter
 * Client kann sich nicht in die Vergangenheit buzzern.
 */
export function clampBuzz(e: BuzzEingang): number {
  const floor = e.receiveTime - Math.max(0, e.medianRtt);
  return Math.min(Math.max(e.pressedAtServerEst, floor), e.receiveTime);
}

/** Voller Clamp inkl. Armierung: final = max(armedAt, clamp(…)). */
export function finaleBuzzZeit(armedAt: number, e: BuzzEingang): number {
  return Math.max(armedAt, clampBuzz(e));
}

/** Ende des Sammel-Fensters nach dem ERSTEN eingegangenen Buzz. */
export function sammelfensterEnde(ersterBuzzReceiveTime: number): number {
  return ersterBuzzReceiveTime + BUZZER_SAMMELFENSTER_MS;
}

export interface BuzzKandidat {
  playerId: string;
  finalAt: number;
}

export interface BuzzErgebnis {
  playerId: string;
  finalAt: number;
  rank: number; // 1-basiert
  /** Diese Platzierung wurde per Fotofinish-Los entschieden (<40 ms). */
  fotofinish: boolean;
}

/**
 * Sortierung + Fotofinish: aufsteigend nach finalAt (Sekundärschlüssel playerId
 * für Determinismus); benachbarte Paare mit Differenz < 40 ms werden markiert
 * und per Münzwurf (injizierter Rng) geordnet — statt stillschweigendem
 * WLAN-Vorteil (§3.3 Punkt 6).
 */
export function ordneBuzzes(kandidaten: BuzzKandidat[], rng: Rng): BuzzErgebnis[] {
  const sortiert = [...kandidaten].sort(
    (a, b) => a.finalAt - b.finalAt || (a.playerId < b.playerId ? -1 : 1),
  );
  const ergebnis: BuzzErgebnis[] = sortiert.map((k, i) => ({
    playerId: k.playerId,
    finalAt: k.finalAt,
    rank: i + 1,
    fotofinish: false,
  }));
  for (let i = 1; i < ergebnis.length; i++) {
    const vorher = ergebnis[i - 1];
    const jetzt = ergebnis[i];
    if (jetzt.finalAt - vorher.finalAt < BUZZER_FOTOFINISH_MS) {
      vorher.fotofinish = true;
      jetzt.fotofinish = true;
      if (rng.next() < 0.5) {
        // Münzwurf: Plätze tauschen (Zeiten bleiben, Ränge wandern).
        ergebnis[i - 1] = { ...jetzt, rank: vorher.rank, fotofinish: true };
        ergebnis[i] = { ...vorher, rank: jetzt.rank, fotofinish: true };
      }
    }
  }
  return ergebnis;
}
