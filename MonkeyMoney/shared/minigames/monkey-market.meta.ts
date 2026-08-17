// Monkey Market (GAME-DESIGN §2.12/2, v2): die Handels-Runde im GELD-Slot.
// Jeder Affe bekommt 10 MARKT-CHIPS der Bank (Chip-Wert = W/10 der Frage) und
// verteilt sie im Handels-Fenster auf die 4 Antwort-FALLTÜREN — Chip für Chip
// (tippen), umschichten erlaubt, oder „ALLES AUF EINS" (Rest-Chips auf eine
// Tür). Öffnet die richtige Tür, zahlt jeder Chip dort ×2 zurück; Chips auf
// falschen Türen und unplatzierte Chips verfallen (Bank-Chips — kein eigener
// Verlust, mildes Geld-Format wie die Affenbank). MUT-BONUS: alle 10 Chips
// auf EINER Tür und richtig ⇒ +25 % auf die Auszahlung.
export const MONKEY_MARKET_ID = "monkey-market";

export const MONKEY_MARKET_META = {
  id: MONKEY_MARKET_ID,
  name: "Monkey Market",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // Chips-Hedging ist keine Richtig/Falsch-Antwort — keine Streak (§3.1-Geist).
  streak: false,
};

/**
 * Spieler-Aktionen: `chip` legt EINEN Chip auf eine Tür, `zurueck` nimmt einen
 * eigenen Chip von einer Tür, `answer` = „ALLES AUF EINS" (alle Rest-Chips
 * auf diese Tür — bewusst der generische answer/choice-Draht, damit auch
 * einfache Clients/Bots das Format spielen können).
 */
export type MonkeyMarketAction =
  | { type: "chip"; tuer: 0 | 1 | 2 | 3 }
  | { type: "zurueck"; tuer: 0 | 1 | 2 | 3 }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing & Ökonomie (Design-Entscheidungen dieses Formats) ----------

export const MM_MARKT_CHIPS = 10; // 10 Einsatz-Chips pro Affe und Frage
export const MM_HANDEL_MS = 20_000; // Handels-Fenster (fix, timerFaktor wirkt)
export const MM_MUT_BONUS = 0.25; // „Alles auf eins" richtig ⇒ +25 %

/** Chip-Wert einer Frage: W/10 (easy 10 · medium 25 · hard 50 · ultra 100). */
export function mmChipWert(frageWert: number): number {
  return Math.round(frageWert / MM_MARKT_CHIPS);
}

/**
 * Auszahlung eines Spielers: Chips auf der richtigen Tür ×2 Chip-Wert;
 * Mut-Bonus +25 % nur, wenn ALLE 10 Chips auf der (richtigen) Tür lagen.
 * Kaufmännisch auf 10er gerundet (Scheine-Anzeige §2.1).
 */
export function mmAuszahlung(
  chipsRichtig: number,
  chipWert: number,
  alleAufEiner: boolean,
): number {
  const basis = chipsRichtig * 2 * chipWert;
  const mitBonus =
    alleAufEiner && chipsRichtig === MM_MARKT_CHIPS ? basis * (1 + MM_MUT_BONUS) : basis;
  return Math.round(mitBonus / 10) * 10;
}
