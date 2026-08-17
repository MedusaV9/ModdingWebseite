// Die Affenbank (GAME-DESIGN §2.8): Kette + Verrat — DIE Money-Signatur-Runde.
// Schnellfeuer-MC-4 an alle im 10-s-Takt: antwortet die MEHRHEIT richtig,
// wächst der Team-Pott 50 → 100 → 200 → 400 → 800 → 1.600 (Kappe). Jeder hat
// jederzeit den roten „BANK!"-Button: Wer bankt, schreibt sich den aktuellen
// Pott PERSÖNLICH gut — die Kette reißt für alle (der Verrats-Moment).
// Falsche Mehrheit = ungesicherter Pott verbrennt. 90 s Kette × 2 Durchgänge.
export const AFFENBANK_ID = "affenbank";

export const AFFENBANK_META = {
  id: AFFENBANK_ID,
  name: "Die Affenbank",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // §2.8: „Keine Streak/Speed" — nur über BANK! gesicherte Beträge zählen.
  streak: false,
  // EIN init() pro Runde: die Kette braucht viele Fragen (rotiert zyklisch).
  roundBased: true,
};

/**
 * Spieler-Aktionen: MC-4-Antwort im 10-s-Fenster ODER der BANK!-Knopf
 * (jederzeit während die Kette läuft; sichert den aktuellen Pott persönlich).
 */
export type AffenbankAction = { type: "answer"; choice: 0 | 1 | 2 | 3 } | { type: "bank" };

// ---------- Timing & Ökonomie (GAME-DESIGN §2.8, verbindlich) ----------

/** Die Pott-Kette: Wert nach 1, 2, 3 … Mehrheits-Treffern in Folge (Kappe 1.600). */
export const AB_KETTE = [50, 100, 200, 400, 800, 1600] as const;
export const AB_FRAGE_MS = 10_000; // Schnellfeuer im 10-s-Takt
export const AB_KETTE_MS = 90_000; // 90 s Kette pro Durchgang
export const AB_DURCHGAENGE = 2; // 2 Durchgänge pro Runde
// Quick Cash (§6.2): kompakte Variante — 1 Durchgang mit 45-s-Kette (~4–5
// Fenster). Hintergrund (Playtest 3): 2×90 s waren 184 s = 44 % der gesamten
// Quick-Matchzeit. Klassik/Marathon behalten 2×90 s; die Engine reicht das
// Tuning als FrageMods.affenbank an init() durch.
export const AB_QUICK_DURCHGAENGE = 1;
export const AB_QUICK_KETTE_MS = 45_000;

/** Laufzeit-Tuning der Runde (FrageMods.affenbank) — fehlt es, gilt 2×90 s. */
export interface AffenbankTuning {
  durchgaenge: number;
  ketteMs: number;
}
export const AB_PAUSE_MS = 4_000; // Tresen-Beat zwischen den Durchgängen
export const AB_BANK_FENSTER_MS = 1_000; // alle BANK!-Drücker im 1-s-Fenster: gleicher Betrag
/** Rest-Kette unter dieser Schwelle: kein neues Frage-Fenster mehr (nicht lesbar). */
export const AB_MIN_FENSTER_MS = 1_000;

/** Pott-Wert der Kette bei `stufe` Mehrheits-Treffern in Folge (0 = leer). */
export function abPottWert(stufe: number): number {
  if (stufe <= 0) return 0;
  return AB_KETTE[Math.min(stufe, AB_KETTE.length) - 1];
}

/** Eintrag der öffentlichen Ketten-Historie (Screen-Inszenierung + Event-Log). */
export interface AbHistorieEintrag {
  typ: "verdoppelt" | "verbrannt" | "gebankt" | "durchgang-start";
  /** Bei „gebankt": der Sicherer; bei „durchgang-start": erster Halter n/a. */
  playerId?: string;
  /** Pott-Wert nach dem Beat (bei „gebankt": der gesicherte Betrag). */
  betrag: number;
  atMs: number; // ms seit Spielstart
  durchgang: number;
}
