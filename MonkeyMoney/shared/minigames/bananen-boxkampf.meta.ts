// „Bananen-Boxkampf" (Buzz-Klassiker „Boxkampf" im Money-Gewand): 1v1 nach dem
// HERAUSFORDERER-Prinzip (der Letzte des Zwischenstands wählt den Gegner,
// Feiglings-Schutz wie am Lianensteg). Jede richtige Antwort ist ein SCHLAG:
// die Gegner-HP sinken um die Frage-Wert-abhängige Punch-Power. Sind BEIDE
// richtig, schlägt die SCHNELLERE richtige Antwort ZUERST (Buzzer-Reihenfolge
// via ctx.buzzer — bringt der Erstschlag den Gegner auf 0, entfällt dessen
// Konter: K.O. ist K.O.!). Kampf-Ende: K.O. (HP 0) oder PUNKTSIEG nach
// BX_RUNDEN Fragen (mehr Rest-HP gewinnt; HP-Gleichstand = Unentschieden).
// Die Zuschauer wetten 50 MM auf den Sieger — Wett-System wiederverwendet vom
// Lianensteg (ldWettAbrechnung, pari-mutuel + EXAKT nullsummig, Rundungs-Rest
// als „Trinkgeld" an den Sieger; klein + golden-getestet ⇒ Re-Export statt
// Kopie, Single Source of Truth).
// SCORING: K.O.-Sieger 400 MM / Punktsieger 300 MM aus der Bank; der Verlierer
// zahlt NICHTS (sportlicher Faustkampf — kein Konto-Abzug, anders als am
// Steg). Unentschieden: je 150, Wetten zurück. Kampflos (Gegner offline):
// 300 aus der Bank, Wetten zurück. Keine Streak (kein ±W-Standard).
import { LD_WETTE_MM, ldWettAbrechnung, type LdWettErgebnis } from "./lianensteg-duell.meta";
import type { Schwierigkeit } from "../money";

export const BOXKAMPF_ID = "bananen-boxkampf";

export const BOXKAMPF_META = {
  id: BOXKAMPF_ID,
  name: "Bananen-Boxkampf",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons", "buzzer"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() pro Runde: der Kampf braucht die ganze Fragen-Serie (bis zu
  // BX_RUNDEN Schlagabtausche) und bucht am Ende genau einmal.
  roundBased: true,
  // Prämie/Wetten sind kein ±W-Standard — keine Streak (§3.2-Schutz).
  streak: false,
};

/**
 * Spieler-Aktionen: `herausfordern` = Gegner-Wahl (NUR der Herausforderer),
 * `wette` = 50-MM-Siegerwette (NUR Zuschauer, vor Kampfbeginn),
 * `answer` = Speed-MC-4-Antwort der Boxer (die Antwort IST der Buzz).
 */
export type BoxkampfAction =
  | { type: "herausfordern"; targetId: string }
  | { type: "wette"; auf: string }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing ----------
export const BX_HERAUSFORDERUNG_MS = 10_000; // Gegner-Wahl-Fenster
export const BX_WETTEN_MS = 10_000; // Zuschauer-Wetten vor Kampfbeginn
export const BX_COUNTDOWN_MS = 3_000; // Ring-Gong-Countdown vor jeder Frage
export const BX_FRAGE_MS = 10_000; // Frage-Fenster (timerFaktor wirkt)
export const BX_SCHLAG_MS = 3_500; // Schlagabtausch-Beat (Punch-Cutscene)
export const BX_ERGEBNIS_MS = 8_000; // K.O./Punktsieg-Cutscene + Wett-Abrechnung

// ---------- Kampf-Regeln (verbindlich) ----------
/** Beide Boxer starten mit vollen 100 HP. */
export const BX_MAX_HP = 100;
/** Punch-Power nach Frage-Wert: HARD trifft in 4 sauberen Schlägen K.O. */
export const BX_PUNCH: Record<Schwierigkeit, number> = {
  easy: 15,
  medium: 20,
  hard: 30,
  ultrahard: 40,
};
/** Punktsieg-Limit: nach 8 Fragen entscheiden die Rest-HP. */
export const BX_RUNDEN = 8;
export const BX_SIEG_KO_MM = 400; // K.O.-Sieg (Bank)
export const BX_SIEG_PUNKTE_MM = 300; // Punktsieg / kampfloser Sieg (Bank)
export const BX_GETEILT_MM = 150; // Unentschieden: beide aus der Bank

// ---------- Wett-System: Wiederverwendung vom Lianensteg (s. Kopf) ----------
/** Fester Zuschauer-Einsatz (identisch zum Steg — vertraute Wett-Geste). */
export const BX_WETTE_MM = LD_WETTE_MM;
/** Pari-mutuel-Abrechnung, EXAKT nullsummig: Σ deltas + restAnSieger = 0. */
export const bxWettAbrechnung: (
  wetten: Record<string, string>,
  sieger: string | null,
) => LdWettErgebnis = ldWettAbrechnung;

/** Sieger-Prämie je Ausgang (kampflos zählt als Punktsieg-Prämie). */
export function bxSiegPraemie(ko: boolean): number {
  return ko ? BX_SIEG_KO_MM : BX_SIEG_PUNKTE_MM;
}
