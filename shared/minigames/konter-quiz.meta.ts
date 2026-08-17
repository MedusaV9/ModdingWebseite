// „Konter-Quiz" (konter-quiz, Duell-Welle): freundliches 1v1-Schnellrate-Duell.
// Duellanten-Auswahl nach dem HERAUSFORDERER-Muster des Boxkampfs (der Letzte
// des Zwischenstands wählt den Gegner; Feiglings-Schutz: der ärmste Gegner ist
// nicht wählbar, solange es Alternativen gibt; Timeout = Führender). Dann
// KQ_RUNDEN kurze Wissensfragen (leicht/mittel, MC-4) à ~8 s — BEIDE dürfen
// per Buzzer antworten (die Antwort IST der Buzz, ctx.buzzer ordnet fair mit
// Median-RTT + Fotofinish-Los).
// GELD-REGELN (verbindlich, „freundlich" = der Verlierer zahlt nie an die
// Bank, sondern höchstens an den Duell-Partner):
//   · richtige Antwort  = +KQ_RICHTIG_MM aus der BANK (beide können kassieren)
//   · falsche Antwort   = KQ_KONTER_MM wandern als KONTER-GUTSCHRIFT zum
//     Duell-Partner (Transfer-Anteil EXAKT nullsummig: −150 / +150)
//   · keine Antwort     = nichts (Schweigen kostet nichts — kein Timeout-Malus)
// RUNDENPUNKT (Duell-Balken, reine Show-Wertung ohne Extra-Geld): die
// SCHNELLERE richtige Antwort holt den Punkt der Frage (Buzzer-Reihenfolge);
// die Zuschauer sehen den Live-Duell-Balken mitwandern.
// EDGE-CASES: Duellant-Disconnect ⇒ die Runde endet SOFORT und OHNE Transfer
// (Bank-Gewinne bleiben, alle Konter-Gutschriften sind storniert — niemand
// verliert Geld, weil der Partner wegbricht); 2-Spieler-Spiel ⇒ keine
// Herausforderungs-Phase; GM-Skip vor dem Ergebnis ⇒ Abbruch ohne Zahlung.
import type { Schwierigkeit } from "../money";

export const KONTER_QUIZ_ID = "konter-quiz";

export const KONTER_QUIZ_META = {
  id: KONTER_QUIZ_ID,
  name: "Konter-Quiz",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons", "buzzer"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() pro Runde: das Duell braucht die ganze Fragen-Serie
  // (KQ_RUNDEN Schlagabtausche) und bucht am Ende genau einmal.
  roundBased: true,
  // Bank-Prämie + Konter-Transfer sind kein ±W-Standard — keine Streak (§3.2).
  streak: false,
};

/**
 * Spieler-Aktionen: `herausfordern` = Gegner-Wahl (NUR der Herausforderer),
 * `answer` = Speed-MC-4-Antwort der Duellanten (die Antwort IST der Buzz).
 */
export type KonterQuizAction =
  { type: "herausfordern"; targetId: string } | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing ----------
export const KQ_HERAUSFORDERUNG_MS = 10_000; // Gegner-Wahl-Fenster
export const KQ_COUNTDOWN_MS = 3_000; // „Duell beginnt"-Gong vor Frage 1
export const KQ_FRAGE_MS = 8_000; // kurzes Frage-Fenster (timerFaktor wirkt)
export const KQ_KONTER_MS = 3_500; // Konter-Beat: Gutschriften fliegen sichtbar
export const KQ_ERGEBNIS_MS = 7_000; // Duell-Bilanz + Sieger-Moment

// ---------- Geld-Regeln (verbindlich) ----------
/** Anzahl Fragen pro Duell (Punktstand entscheidet den Show-Sieger). */
export const KQ_RUNDEN = 8;
/** Bank-Prämie je richtiger Antwort (beide Duellanten können kassieren). */
export const KQ_RICHTIG_MM = 150;
/** Konter-Gutschrift je falscher Antwort: wandert 1:1 zum Duell-Partner. */
export const KQ_KONTER_MM = 150;

/** Erlaubte Frage-Schwierigkeiten (kurze leichte/mittlere Wissensfragen). */
export const KQ_SCHWIERIGKEITEN: readonly Schwierigkeit[] = ["easy", "medium"];

/** Eine ausgewertete Frage aus Duellanten-Sicht (Konter-Beat + Bilanz). */
export interface KqFrageDeltas {
  /** Bank-Anteil je Duellant (nur ≥ 0 — richtige Antworten). */
  bank: Record<string, number>;
  /** Transfer-Anteil je Duellant — Σ über beide ist EXAKT 0. */
  transfer: Record<string, number>;
}

/**
 * Geld-Mathe einer Frage (Single Source of Truth für Plugin, Tests UND
 * Bot-Beweis): richtig ⇒ +KQ_RICHTIG_MM Bank; falsch ⇒ −KQ_KONTER_MM selbst,
 * +KQ_KONTER_MM Partner; keine Antwort ⇒ nichts. Der Transfer-Anteil ist
 * konstruktionsbedingt nullsummig — der Wächter-Test prüft es trotzdem hart.
 */
export function kqFrageDeltas(
  duellanten: readonly [string, string],
  antworten: Record<string, { choice: number } | undefined>,
  correct: number,
): KqFrageDeltas {
  const [a, b] = duellanten;
  const bank: Record<string, number> = { [a]: 0, [b]: 0 };
  const transfer: Record<string, number> = { [a]: 0, [b]: 0 };
  for (const p of duellanten) {
    const antwort = antworten[p];
    if (antwort === undefined) continue; // Schweigen kostet nichts
    if (antwort.choice === correct) {
      bank[p] += KQ_RICHTIG_MM;
    } else {
      const partner = p === a ? b : a;
      transfer[p] -= KQ_KONTER_MM;
      transfer[partner] += KQ_KONTER_MM;
    }
  }
  return { bank, transfer };
}
