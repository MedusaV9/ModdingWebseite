// Bananen-Bluff (GAME-DESIGN §2.12/3, v2): Lügen-Erkennung im KONFLIKT-Slot.
// Pro Frage ist EIN Affe der VERKÜNDER (rotiert durch die Sitz-Reihenfolge):
// nur er sieht die richtige Antwort und VERKÜNDET dann eine der 4 Optionen —
// die Wahrheit oder einen Bluff (kreative wahr/falsch-Nutzung der choice4-
// Fragen). Alle anderen stimmen ab: WAHR oder GELOGEN?
// Payoffs (W = Fragen-Grundwert, W/2 ist bei allen Stufen ganzzahlig):
//   · Rater richtig (Bluff durchschaut ODER Wahrheit erkannt) → +W/2 (Bank).
//   · Rater fällt auf den Bluff rein → er zahlt W/2 AN DEN VERKÜNDER
//     („Lügen ist Diebstahl" — exakter Nullsummen-Transfer).
//   · Rater misstraut der Wahrheit → 0 (nur entgangene Prämie).
//   · EHRLICHKEITS-PRÄMIE: verkündet der Verkünder SELBST die Wahrheit und
//     die strikte Mehrheit der abgegebenen Stimmen glaubt ihm → +W/2 (Bank).
// Timeout/Disconnect des Verkünders ⇒ Auto-Wahrheit OHNE Prämien-Anspruch.
// Design-Entscheidung: der Transfer ist KEIN Klau im Joker-Sinn — der
// Bananentresor (J6) schützt NICHT vor der eigenen Leichtgläubigkeit.
export const BANANEN_BLUFF_ID = "bananen-bluff";

export const BANANEN_BLUFF_META = {
  id: BANANEN_BLUFF_ID,
  name: "Bananen-Bluff",
  minPlayers: 3, // §2.12: mind. 3 — sonst gibt es nichts zu bluffen
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // Bluffen/Raten ist Psychologie, keine Quiz-Kette — keine Streak.
  streak: false,
  // EIN init() pro Runde: die Verkünder-Rotation braucht alle Fragen.
  roundBased: true,
};

/**
 * Spieler-Aktionen — bewusst BEIDE über den generischen answer/choice-Draht:
 * Verkünden-Fenster: der Verkünder wählt die Option, die er ansagt (0–3).
 * Rate-Fenster: alle anderen stimmen ab (0 = WAHR, 1 = GELOGEN).
 */
export type BananenBluffAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing & Ökonomie (Design-Entscheidungen dieses Formats) ----------

export const BB_VERKUENDEN_MS = 12_000; // Verkünder wählt Wahrheit oder Bluff
export const BB_RATEN_MS = 12_000; // alle anderen: WAHR oder GELOGEN?
export const BB_AUFDECKUNG_MS = 6_000; // Show-Moment: Lüge/Wahrheit + Ströme

/** Prämien-/Transfer-Betrag: W/2 — bei 100/250/500/1000 immer ganzzahlig. */
export function bbPraemie(frageWert: number): number {
  return Math.round(frageWert / 2);
}

/** Die beiden Rate-Optionen (Index = answer.choice der Rater). */
export const BB_RATE_OPTIONEN = ["WAHR — glaub ich!", "GELOGEN — Bluff!"] as const;
