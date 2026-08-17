// Affenleiter (Sortieren, GAME-DESIGN §2.4) — beidseitige Meta, Fragen-Typ
// (angelehnt an CONTENT-PLAN §2.3 `sortier`) und Action-Typen.
import type { Schwierigkeit } from "../money";

export const AFFENLEITER_ID = "affenleiter";

export const AFFENLEITER_META = {
  id: AFFENLEITER_ID,
  name: "Affenleiter",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["dragList"] as const,
  contentKind: "sort" as const,
  streak: true, // §2.4/§3.1: Streak zählt NUR bei Komplett-Richtig (outcomes() = perfekt)
  // KEIN perSpielerFragen: Sortier-Fragen (kein MC-4) — Maßanzug greift hier nicht.
};

/**
 * Sortier-Frage — Feldnamen folgen CONTENT-PLAN §2.3 (`sortier`):
 * `korrektReihenfolge[i]` = Element-Index, der auf Sprosse i (unten = 0) gehört;
 * `aufloesungWerte[e]` = Anzeige-Wert von Element e (z. B. Jahreszahl).
 */
export interface LeiterFrage {
  id: string;
  text: string; // inkl. Kriterium, z. B. „… — das Älteste nach unten!"
  schwierigkeit: Schwierigkeit; // bestimmt den Grundwert (GAME-DESIGN §3.1)
  elemente: readonly [string, string, string, string];
  korrektReihenfolge: readonly [number, number, number, number];
  aufloesungWerte: readonly [string, string, string, string];
  erklaerung: string;
}

/**
 * Spieler-Aktionen: `sortierung` = Zwischenstand (zählt auch ohne Einloggen,
 * §2.4 „keine Abgabe = aktueller Stand zählt"), `einloggen` = verbindlich.
 * `reihenfolge[i]` = Element-Index auf Sprosse i.
 */
export type AffenleiterAction =
  { type: "sortierung"; reihenfolge: number[] } | { type: "einloggen"; reihenfolge: number[] };

/** 30 s sortieren — fix (GAME-DESIGN §2.4). */
export const LEITER_TIMER_MS = 30_000;

/** Perfekt-Bonus: komplett richtig = +50 % auf den Grundwert (§2.4). */
export const LEITER_PERFEKT_FAKTOR = 1.5;

/** Prüft, ob eine Reihenfolge eine gültige Permutation von 0–3 ist. */
export function istGueltigeReihenfolge(reihenfolge: unknown): reihenfolge is number[] {
  return (
    Array.isArray(reihenfolge) &&
    reihenfolge.length === 4 &&
    [0, 1, 2, 3].every((i) => reihenfolge.includes(i))
  );
}
