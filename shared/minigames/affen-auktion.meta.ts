// Affen-Auktion (GAME-DESIGN §2.12/5, v2): das exklusive Antwortrecht wird
// VERSTEIGERT — Risiko-Handel im KONFLIKT-Slot. 20-s-Auktion im 25er-Raster
// („BIETEN +25"); Gebote in den letzten 5 s verlängern den Hammer um 5 s
// (Anti-Sniping, harte Kappe +20 s). Der Höchstbietende beantwortet die Frage
// danach EXKLUSIV (20 s, Info-Joker erlaubt):
//   · richtig → „Gebot ×2 zurück" = netto +Gebot (aus der Bank).
//   · falsch/Timeout → das Gebot wird AN ALLE ANDEREN VERTEILT: jeder
//     bekommt floor(Gebot/(N−1) auf 10er) — der Gewinner zahlt EXAKT die
//     Summe der Anteile (Rundungs-Rest bleibt bei ihm ⇒ nullsummig).
// Persönliches Gebots-Limit: max(100, min(1.000, Konto aufs 25er-Raster)) —
// auch Pleite-Affen dürfen bis 100 bieten (die Dispo-Klammer §3.2 deckt das).
// Keine Gebote ⇒ die Frage verfällt (niemand zahlt, niemand gewinnt).
// Disconnect des Höchstbietenden vor der Antwort ⇒ Gebot erstattet, Frage
// verfällt (Präzedenz: Alles-oder-Banane §2.9); Reconnect im Fenster hebt
// die Erstattung wieder auf. Der Höchstbietende kann sich nicht selbst
// überbieten. Das Bieter-Fenster heißt im State/View bewusst „setzen"
// (Setz-Fenster-Konvention von Alles-oder-Banane — generische Clients/Bots
// können damit sofort bieten).
export const AFFEN_AUKTION_ID = "affen-auktion";

export const AFFEN_AUKTION_META = {
  id: AFFEN_AUKTION_ID,
  name: "Affen-Auktion",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // Auktions-Payoff ist ±Gebot, kein ±W-Standard — keine Streak.
  streak: false,
  // Info-Joker nur im Frage-Fenster und nur für den Auktions-Gewinner.
  jokerAktionen: ["fiftyFifty", "removeOne", "secondTry"] as const,
};

/**
 * Spieler-Aktionen: `bieten` = Höchstgebot +25 (der große Hammer-Button),
 * `einsatz` = „erhöhe auf Betrag" (geklemmt aufs Raster/Limit — der
 * generische Setz-Draht), `answer` = MC-4-Antwort (NUR der Gewinner).
 */
export type AffenAuktionAction =
  | { type: "bieten" }
  | { type: "einsatz"; betrag: number }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing & Auktions-Regeln (Design-Entscheidungen) ----------

export const AA_AUKTION_MS = 20_000; // Basis-Auktionsfenster
export const AA_VERLAENGERUNG_MS = 5_000; // Gebot in den letzten 5 s ⇒ +5 s
export const AA_AUKTION_MAX_EXTRA_MS = 20_000; // harte Anti-Sniping-Kappe
export const AA_FRAGE_MS = 20_000; // exklusives Antwort-Fenster (timerFaktor wirkt)
export const AA_SCHRITT = 25; // „BIETEN +25"
export const AA_MIN_LIMIT = 100; // jeder darf bis 100 bieten (Dispo deckt)
export const AA_MAX_GEBOT = 1_000; // absolute Gebots-Kappe

/** Persönliches Gebots-Limit aus dem Kontostand (25er-Raster). */
export function aaMaxGebot(kontostand: number): number {
  const geraster = Math.floor(kontostand / AA_SCHRITT) * AA_SCHRITT;
  return Math.max(AA_MIN_LIMIT, Math.min(AA_MAX_GEBOT, geraster));
}

/** „Erhöhe auf Betrag" klemmen: 25er-Raster, mind. Höchstgebot+25, max. Limit.
 * null = Gebot nicht möglich (Limit erreicht). */
export function aaKlemmeGebot(betrag: number, hoechstgebot: number, limit: number): number | null {
  const mindest = hoechstgebot + AA_SCHRITT;
  if (mindest > limit) return null;
  const geraster = Math.round(betrag / AA_SCHRITT) * AA_SCHRITT;
  return Math.max(mindest, Math.min(limit, geraster));
}

/** Falsch-Fall: Kopf-Anteil für jeden anderen (auf 10er ABgerundet — der
 * Gewinner zahlt anteil × (N−1), der Rundungs-Rest bleibt bei ihm). */
export function aaVerteilAnteil(gebot: number, andere: number): number {
  if (andere <= 0) return 0;
  return Math.floor(gebot / andere / 10) * 10;
}
