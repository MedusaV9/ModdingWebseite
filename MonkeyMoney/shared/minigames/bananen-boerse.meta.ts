// Bananen-Börse (GAME-DESIGN §2.12/4, v2): Live-Investieren im GELD-Slot.
// Die Frage + 4 Optionen liegen offen, das Parkett handelt 20 s in VIER
// 5-s-KURS-BLÖCKEN. Jeder investiert den festen Einsatz E = W/2 in EINE
// Option (KAUFEN); die QUOTE wird beim Kauf eingefroren und stammt aus dem
// Block-Anfangs-Snapshot: quote = max(1,2, 3,0 − 1,5 × Halter/Spieler) —
// Herdenverhalten drückt den Kurs (§2.12: „Quote sinkt mit Herdenverhalten").
// KAUFEN/HALTEN/VERKAUFEN: wer kalte Füße bekommt, VERKAUFT vor Börsenschluss
// (−25 % Spread auf E, genau 1× pro Spieler) und darf danach 1× neu kaufen.
// Abrechnung am Börsenschluss:
//   · Position auf der RICHTIGEN Option → +rundeAuf10(E × (quote − 1)).
//   · Position auf einer falschen Option → −E.
//   · verkauft (je Verkauf) → zusätzlich −rundeAuf10(E × 0,25) an die Bank.
//   · nie gehandelt → 0.
// Die Kurs-Historie (Snapshot pro Block) wandert ins View — Futter für den
// Kurs-Chart-Canvas auf Screen + Handy. Disconnect: offene Position bleibt
// liegen (kein Auto-Verkauf) und wird normal abgerechnet.
export const BANANEN_BOERSE_ID = "bananen-boerse";

export const BANANEN_BOERSE_META = {
  id: BANANEN_BOERSE_ID,
  name: "Bananen-Börse",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // Auszahlung ist Quote-Mathe, kein ±W-Standard — keine Streak.
  streak: false,
};

/**
 * Spieler-Aktionen: `answer` = KAUFEN (Option 0–3, generischer choice-Draht),
 * `verkaufen` = offene Position schließen (Spread −25 %, max. 1×).
 */
export type BananenBoerseAction = { type: "answer"; choice: 0 | 1 | 2 | 3 } | { type: "verkaufen" };

// ---------- Timing & Kurs-Formeln (GAME-DESIGN §2.12/4, verbindlich) ----------

export const BOERSE_HANDEL_MS = 20_000; // Börsen-Fenster (timerFaktor wirkt)
export const BOERSE_BLOECKE = 4; // Abrechnung in 5-s-Kurs-Blöcken
export const BOERSE_QUOTE_START = 3.0;
export const BOERSE_QUOTE_HERDE = 1.5; // Quote = 3,0 − 1,5 × Anteil …
export const BOERSE_QUOTE_MIN = 1.2; // … mindestens 1,2
export const BOERSE_SPREAD = 0.25; // Verkaufs-Spread: 25 % des Einsatzes
export const BOERSE_MAX_VERKAEUFE = 1; // 1 Umschichtung pro Spieler

/** Fester Einsatz pro Position: E = W/2 (bei allen Stufen ganzzahlig). */
export function boerseEinsatz(frageWert: number): number {
  return Math.round(frageWert / 2);
}

/** Block-Quote aus dem Herden-Anteil (Halter der Option / Spielerzahl). */
export function boerseQuote(halter: number, spielerZahl: number): number {
  const anteil = spielerZahl > 0 ? halter / spielerZahl : 0;
  return Math.max(BOERSE_QUOTE_MIN, BOERSE_QUOTE_START - BOERSE_QUOTE_HERDE * anteil);
}

/** Nettogewinn einer richtigen Position: rundeAuf10(E × (quote − 1)). */
export function boerseGewinn(einsatz: number, quote: number): number {
  return Math.round((einsatz * (quote - 1)) / 10) * 10;
}

/** Spread-Verlust eines Verkaufs: rundeAuf10(E × 0,25). */
export function boerseSpreadVerlust(einsatz: number): number {
  return Math.round((einsatz * BOERSE_SPREAD) / 10) * 10;
}
