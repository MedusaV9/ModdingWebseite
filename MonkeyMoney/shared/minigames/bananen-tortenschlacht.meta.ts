// „Die große Bananen-Tortenschlacht" (Buzz-Klassiker „Tortenschlacht" im
// Money-Gewand): Jede Runde EINE Frage an ALLE aktiven Affen; wer richtig
// antwortet, darf eine SAHNETORTE auf einen Gegner werfen (geheime Ziel-Wahl
// wie beim Taschendieb). Wer 3 Torten im Gesicht trägt, ist RAUS — der letzte
// saubere Affe gewinnt den Topf.
//
// SCORING (Design-Geist §2.6/§2.7: Überleben ist der Spannungs-Kern, KEIN
// Money pro Frage — sonst würde Mitspielen statt Überleben belohnt):
//   · Topf: fester Bank-Topf TS_TOPF_MM (1.500 MM ≈ Konflikt-Runden-Ertrag
//     eines Sieger-Laufs bei 4×HARD) für den letzten sauberen Affen. Teilen
//     sich mehrere den Sieg (Punktsieg-Gleichstand), wird der Topf auf 10er
//     abgerundet geteilt, der Rundungs-Rest geht deterministisch an den
//     Sieger mit der früheren Join-Reihenfolge.
//   · Trost GESTAFFELT nach Überlebensdauer: der k-te Rausgeworfene bekommt
//     k × TS_TROST_SCHRITT (100/200/300 …) — wer länger durchhält, kriegt
//     mehr. Überlebende ohne Sieg (Punktsieg mit mehr Torten als der Sieger)
//     bekommen die nächste Stufe über dem letzten Rausgeworfenen.
// Keine Streak (kein ±W-Standard), kein Speed-Bonus — die Engine bucht die
// scores() 1:1.
import type { Schwierigkeit } from "../money";

export const TORTENSCHLACHT_ID = "bananen-tortenschlacht";

export const TORTENSCHLACHT_META = {
  id: TORTENSCHLACHT_ID,
  name: "Die große Bananen-Tortenschlacht",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() pro Runde: die Rauswurf-Schlacht braucht die ganze Fragen-Serie
  // und bucht am Ende genau einmal (Topf + gestaffelter Trost).
  roundBased: true,
  // Topf/Trost sind kein ±W-Standard — keine Streak (§3.2-Schutz).
  streak: false,
};

/** Spieler-Aktionen: MC-4-Antwort für alle Aktiven; „wurf" nur für Werfer. */
export type TortenschlachtAction =
  { type: "answer"; choice: 0 | 1 | 2 | 3 } | { type: "wurf"; targetId: string };

// ---------- Timing (mehrere Fragen pro Runde ⇒ knackiger als Taschendieb) ----------
export const TS_FRAGE_MS: Record<Schwierigkeit, number> = {
  easy: 12_000,
  medium: 12_000,
  hard: 15_000,
  ultrahard: 15_000,
};
export const TS_ZIELWAHL_MS = 7_000; // geheime Ziel-Wahl der Werfer
export const TS_WURF_MS = 4_500; // Torten-Salve (Flug + Klatsch-Inszenierung)
export const TS_NIEMAND_MS = 2_500; // Beat, wenn NIEMAND richtig lag (keine Torte)
export const TS_ERGEBNIS_MS = 7_000; // Sieger-Beat (letzter sauberer Affe)

// ---------- Schlacht-Regeln (verbindlich) ----------
/** 3 Torten im Gesicht = raus (Sahne-Schichten 1/2/3 sichtbar auf der Puppe). */
export const TS_TORTEN_RAUS = 3;
/** Der Topf für den letzten sauberen Affen (Bank-finanziert). */
export const TS_TOPF_MM = 1_500;
/** Trost-Staffel: k-ter Rausgeworfener bekommt k × 100 MM. */
export const TS_TROST_SCHRITT = 100;

/** Trost des k-ten Rausgeworfenen (k 1-basiert) — Staffel nach Überlebensdauer. */
export function tsTrost(rausIndex: number): number {
  return rausIndex * TS_TROST_SCHRITT;
}

/**
 * Topf-Teilung bei geteiltem Punktsieg: Anteil auf 10er abgerundet, der
 * Rundungs-Rest geht an den ERSTEN Sieger (Join-Reihenfolge) — deterministisch,
 * Σ Anteile + Rest = Topf.
 */
export function tsTopfAnteile(anzahlSieger: number): { anteil: number; rest: number } {
  if (anzahlSieger <= 0) return { anteil: 0, rest: 0 };
  const anteil = Math.floor(TS_TOPF_MM / anzahlSieger / 10) * 10;
  return { anteil, rest: TS_TOPF_MM - anteil * anzahlSieger };
}
