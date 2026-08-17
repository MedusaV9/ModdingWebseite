// Alles oder Banane (GAME-DESIGN §2.9 + §3.3): die Wettrunde im RISIKO-Slot.
// Pro Frage wird NUR Kategorie + Schwierigkeit angeteasert; jeder setzt GEHEIM
// auf die eigene Antwort (Anhang A: A7 in v1 — Wetten auf andere ist v2),
// dann Reveal ALLER Einsätze VOR der Frage (der Show-Moment), dann MC-4.
// Richtig = +Einsatz, falsch = −Einsatz (an die Bank, NICHT ins Glas).
export const ALLES_ODER_BANANE_ID = "alles-oder-banane";

export const ALLES_ODER_BANANE_META = {
  id: ALLES_ODER_BANANE_ID,
  name: "Alles oder Banane",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["slider", "buttons"] as const,
  contentKind: "quiz" as const,
  // §2.9: „Keine Streak/Speed" — die Auszahlung ist exakt ±Einsatz.
  streak: false,
  // Info-Joker bleiben erlaubt (nur im Frage-Fenster, nach dem Einsatz-Reveal).
  jokerAktionen: ["fiftyFifty", "removeOne", "secondTry"] as const,
};

/**
 * Spieler-Aktionen: Einsatz einloggen (Setz-Fenster, rastet ein) und
 * MC-4-Antwort (Frage-Fenster). Beides idempotent — der erste Wert zählt.
 */
export type AllesOderBananeAction =
  { type: "einsatz"; betrag: number } | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing & Wett-Regeln (GAME-DESIGN §2.9/§3.3, verbindlich) ----------

export const AOB_SETZEN_MS = 12_000; // 12 s setzen
export const AOB_REVEAL_MS = 6_000; // 6 s Einsatz-Reveal (einzeln aufgedeckt)
export const AOB_FRAGE_MS = 20_000; // 20 s Frage (fix, NICHT nach Schwierigkeit)
export const AOB_EINSATZ_MIN = 100; // Einsatz 100–1.000 MM …
export const AOB_EINSATZ_MAX = 1_000;
export const AOB_SCHRITT = 50; // … in 50er-Schritten
export const AOB_KONTO_CAP = 0.5; // gedeckelt auf 50 % des Kontostands
/** Konto < 100: die Bank stellt 100 MM Gratis-Einsatz („Kredit der Affenbank",
 * wird nicht zurückgefordert — falsch kostet dann nichts, richtig zahlt +100). */
export const AOB_GRATIS_EINSATZ = 100;

/** Erlaubter Höchsteinsatz für einen Kontostand (0 = Gratis-Einsatz-Fall). */
export function aobEinsatzMax(kontostand: number): number {
  if (kontostand < AOB_EINSATZ_MIN) return AOB_GRATIS_EINSATZ;
  const cap = Math.floor((kontostand * AOB_KONTO_CAP) / AOB_SCHRITT) * AOB_SCHRITT;
  return Math.max(AOB_EINSATZ_MIN, Math.min(AOB_EINSATZ_MAX, cap));
}

/** Einsatz auf Raster + Grenzen klemmen (50er-Schritte, min 100, Konto-Cap). */
export function aobKlemmeEinsatz(betrag: number, kontostand: number): number {
  const max = aobEinsatzMax(kontostand);
  if (kontostand < AOB_EINSATZ_MIN) return AOB_GRATIS_EINSATZ; // fixer Bank-Kredit
  const gerastert = Math.round(betrag / AOB_SCHRITT) * AOB_SCHRITT;
  return Math.max(AOB_EINSATZ_MIN, Math.min(max, gerastert));
}
