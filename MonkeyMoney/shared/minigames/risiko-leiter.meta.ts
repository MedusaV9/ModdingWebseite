// „Risiko-Leiter" (risiko-leiter, Welle 4): der Gewinnleiter-Klassiker der
// Spielshow-Geschichte — jeder Spieler klettert INDIVIDUELL eine 8-Stufen-
// Money-Leiter (100 → 200 → 400 → 700 → 1.100 → 1.600 → 2.200 → 3.000 MM).
// ABLAUF pro Stufe: VOR der Frage wählt jeder aktive Kletterer WEITERKLETTERN
// oder ABSICHERN (Kasse machen = aktueller Leiter-Stand wird gutgeschrieben,
// die Runde ist für diesen Spieler beendet — er wartet charmant als Zuschauer).
// Dann MC-4-Frage (Schwierigkeit steigt mit der Leiter: das Plugin sortiert
// den Fragen-Vorrat easy → ultrahard).
// SICHERHEITSSTUFE (Gewinnleiter-Klassiker-Regel, verbindlich): Stufe 3 =
// 400 MM. Eine FALSCHE Antwort (oder Schweigen NACH aktiver Weiter-Wahl) =
// Absturz auf die letzte erklommene Sicherheitsstufe — wer Stufe 3 geschafft
// hat, fällt auf 400 MM, darunter auf 0.
// GIPFEL: Wer bis Stufe 8 klettert UND richtig antwortet, bekommt 3.000 MM
// plus RL_JACKPOT_BONUS als Jackpot-Bonus der Bank (Gipfel-Fanfare).
// TIMEOUT-REGELN: Wer im Entscheidungs-Fenster schweigt, KLETTERT WEITER
// („Wer zögert, klettert" — Show-Psychologie, verhindert den Guck-Exploit:
// erst die Frage sehen, dann absichern gibt es NICHT). Getrennte Kletterer
// sichern automatisch ab (charmanter AFK-Schutz).
import type { Schwierigkeit } from "../money";

export const RISIKO_LEITER_ID = "risiko-leiter";

export const RISIKO_LEITER_META = {
  id: RISIKO_LEITER_ID,
  name: "Risiko-Leiter",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() pro Runde: die Leiter braucht die ganze 8-Fragen-Serie
  // (aufsteigende Schwierigkeit) und bucht am Ende genau einmal.
  roundBased: true,
  // Absicherungs-/Absturz-Gutschriften sind kein ±W-Standard — keine Streak.
  streak: false,
  // answeredCount zählt je nach Phase Entscheidungen ODER Antworten —
  // die Auto-GM-+10s-Heuristik würde Entscheidungs-Fenster falsch verlängern.
  autoVerlaengerung: false,
};

/**
 * Spieler-Aktionen: `entscheidung` = WEITERKLETTERN oder ABSICHERN vor der
 * Frage (erste Wahl rastet ein; Absichern wirkt sofort und ist endgültig),
 * `answer` = MC-4-Antwort der aktiven Kletterer (erste Antwort zählt).
 */
export type RisikoLeiterAction =
  | { type: "entscheidung"; wahl: "weiter" | "absichern" }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Die Leiter (verbindlich — Gewinnleiter-Klassiker-Kurve) ----------
/** Money-Leiter: Wert NACH 1, 2, … 8 erklommenen Stufen. */
export const RL_LEITER = [100, 200, 400, 700, 1_100, 1_600, 2_200, 3_000] as const;
export const RL_STUFEN = RL_LEITER.length; // 8
/** Sicherheitsstufe: ab hier fällt niemand mehr unter 400 MM (Stufe 3). */
export const RL_SICHERHEITSSTUFE = 3;
/** Jackpot-Bonus der Bank für den kompletten Aufstieg (Stufe 8 richtig). */
export const RL_JACKPOT_BONUS = 500;

// ---------- Timing ----------
export const RL_ENTSCHEIDUNG_MS = 9_000; // Weiterklettern-oder-Kasse-Fenster
export const RL_FRAGE_MS = 15_000; // MC-4-Fenster (timerFaktor wirkt)
export const RL_AUFSTIEG_MS = 5_000; // Kletter-/Absturz-Beat mit Auflösung
export const RL_ERGEBNIS_MS = 8_000; // Leiter-Bilanz + Gipfel-Moment

/** Schwierigkeits-Rang für die Leiter-Sortierung (easy unten, ultrahard oben). */
export const RL_SCHWIERIGKEITS_RANG: Record<Schwierigkeit, number> = {
  easy: 0,
  medium: 1,
  hard: 2,
  ultrahard: 3,
};

/** Leiter-Stand nach `stufe` erklommenen Stufen (0 = Boden = 0 MM). */
export function rlLeiterWert(stufe: number): number {
  if (stufe <= 0) return 0;
  return RL_LEITER[Math.min(stufe, RL_STUFEN) - 1];
}

/** Absturz-Gutschrift: letzte erreichte SICHERHEITSSTUFE (Stufe 3 = 400 MM);
 * wer die Sicherheitsstufe noch nicht erklommen hat, fällt auf 0. */
export function rlAbsturzWert(stufe: number): number {
  return stufe >= RL_SICHERHEITSSTUFE ? rlLeiterWert(RL_SICHERHEITSSTUFE) : 0;
}

/** Gipfel-Gutschrift: Stufe 8 richtig = 3.000 MM + Jackpot-Bonus der Bank. */
export function rlGipfelWert(): number {
  return rlLeiterWert(RL_STUFEN) + RL_JACKPOT_BONUS;
}
