// Stopp die Kokosnuss-Uhr (Stop the Clock, GAME-DESIGN §2.2) — beidseitige Meta,
// Action-Typen und die Sack-Mathematik (Client zeigt den live schrumpfenden Betrag
// mit DERSELBEN Formel wie der Server wertet — Tick-Stufen machen Latenz egal).
import type { Schwierigkeit } from "../money";

export const KOKOSNUSS_UHR_ID = "kokosnuss-uhr";

export const KOKOSNUSS_UHR_META = {
  id: KOKOSNUSS_UHR_ID,
  name: "Stopp die Kokosnuss-Uhr",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  streak: true, // §3.1: Frage-Format — Streak zählt normal (outcomes() liefert richtig/falsch)
  // Maßanzug/Portfolio: eigene Frage pro Spieler, der eigene Sack tickt normal.
  perSpielerFragen: true,
};

/** Spieler-Aktion: Antworten friert DEN EIGENEN Sack ein (Antwort-Lock). */
export type KokosnussUhrAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

/** Der Sack schrumpft in sichtbaren 50-MM-Ticks (GAME-DESIGN §2.2). */
export const SACK_TICK_MM = 50;

/**
 * Sack-Startwerte: MEDIUM 400 / HARD 750 sind Design-Festwerte (§2.2).
 * EASY 200 und ULTRAHARD 1500 sind konsistent extrapoliert (≈ Grundwert × 1,5–2,
 * 50er-teilbar) — im Design nur MEDIUM/HARD spezifiziert (AUFBAU-Format).
 */
export const SACK_STARTWERTE: Record<Schwierigkeit, number> = {
  easy: 200,
  medium: 400,
  hard: 750,
  ultrahard: 1500,
};

/** Tick-Intervall so, dass der Sack GENAU mit dem Timer bei 0 ankommt. */
export function sackTickIntervallMs(startwert: number, timerMs: number): number {
  return timerMs / (startwert / SACK_TICK_MM);
}

/** Sack-Wert nach `elapsedMs` — Tick-Stufen, nie negativ. Wertet UND rendert. */
export function sackWertBei(startwert: number, tickIntervallMs: number, elapsedMs: number): number {
  const ticks = Math.floor(Math.max(0, elapsedMs) / tickIntervallMs);
  return Math.max(0, startwert - ticks * SACK_TICK_MM);
}
