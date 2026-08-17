// Ökonomie-Formeln (GAME-DESIGN §3, verbindliche Zahlen) — pure + deterministisch.
// Grundwerte/Speed-Bonus leben in money.ts; hier: Streak, Rückenwind, Finale,
// Dispo/Pfandflaschen, Jackpot-Glas, AT-Umrechnung, Sozialrabatt.

/** Auf 10er runden (Anzeige in Scheinen, GAME-DESIGN §2.1-Beispiel). */
export function rundeAuf10(betrag: number): number {
  return Math.round(betrag / 10) * 10;
}

/** Auf den nächsten 50er AUFrunden (W_final, §3.5). */
export function rundeAuf50Hoch(betrag: number): number {
  return Math.ceil(betrag / 50) * 50;
}

// ---------- Streak (§3.1) ----------

/**
 * Streak-Multiplikator: ab 3 richtigen in Folge ×1,5, ab 5 ×2,0, harte Kappe ×2.
 * `streakInklusive` zählt die AKTUELLE richtige Antwort mit (Beispiel §2.1:
 * Streak 3 ⇒ ×1,5 auf diese Antwort).
 */
export function streakFaktor(streakInklusive: number): number {
  if (streakInklusive >= 5) return 2.0;
  if (streakInklusive >= 3) return 1.5;
  return 1.0;
}

// ---------- Rückenwind (§3.4) ----------

/** >40 % hinter dem Führenden ⇒ ×1,25 · >60 % ⇒ ×1,5 · sonst ×1. */
export function rueckenwindFaktor(eigenerStand: number, fuehrenderStand: number): number {
  if (fuehrenderStand <= 0) return 1.0;
  const rueckstand = (fuehrenderStand - Math.max(0, eigenerStand)) / fuehrenderStand;
  if (rueckstand > 0.6) return 1.5;
  if (rueckstand > 0.4) return 1.25;
  return 1.0;
}

/**
 * Überhol-Kappe (§3.4): der ZUSATZgewinn aus Rückenwind kann pro Buchung nie
 * über den Vordermann katapultieren — Aufholen ja, Überholen aus dem Stand nein.
 * Der Basisgewinn (ohne Rückenwind) darf weiterhin überholen.
 */
export function kappeRueckenwindExtra(
  extra: number,
  standNachBasisBuchung: number,
  vordermannStand: number,
): number {
  return Math.max(0, Math.min(extra, vordermannStand - standNachBasisBuchung));
}

// ---------- Finale-Formel (§3.5, Kernstück) ----------

/** W_final = max(500, aufrunden(faktor × G / Q, auf 50er)). */
export function wFinal(g: number, q: number, faktor = 1.25): number {
  if (q <= 0) return 500;
  return Math.max(500, rundeAuf50Hoch((faktor * Math.max(0, g)) / q));
}

/** Finale-Buchung: richtig +W, falsch −W/2, keine Antwort 0; Konto nie unter 0. */
export function finaleDelta(korrekt: boolean | null, w: number): number {
  if (korrekt === true) return w;
  if (korrekt === false) return -w / 2;
  return 0;
}

// ---------- Dispo / Pfandflaschen / Schuldenerlass (§3.2) ----------

export const DISPO_LIMIT = -500; // hart, tiefer nie
export const PFAND_GEWINN_FAKTOR = 0.75; // am Dispo-Limit: Gewinne nur zu 75 %

/** Pfandflaschen-Modus aktiv? (Konto am harten Dispo-Limit) */
export function istPfandflaschenModus(kontostand: number): boolean {
  return kontostand <= DISPO_LIMIT;
}

/** Buchung mit Dispo-Klammer: Konto fällt nie unter −500 (Finale: nie unter 0). */
export function klemmeAufDispo(kontostand: number, minimum = DISPO_LIMIT): number {
  return Math.max(minimum, kontostand);
}

// ---------- Jackpot-Glas & Jackpot-Frage (§3.1/§3.2) ----------

export const JACKPOT_GLAS_START = 500; // Grundfüllung bei Match-Start
export const JACKPOT_FRAGE_WERT = 2000; // + kompletter Glas-Inhalt
export const REKLAMATION_GEBUEHR = 100; // abgewiesene Reklamation → ins Glas
export const BANANENSTEUER = 100; // Pranger-Strafe → ins Glas

// ---------- Underdog-Konstanten (§3.4) ----------

export const MITLEIDS_BANANE = 300; // Letzter vor dem Finale, einmalig
export const APPLAUS_ALMOSEN = 25; // als Einziger falsch (bewusst halber Schein)
export const BAILOUT_ABSTAND_PROZENT = 0.15; // Banana Bailout: 15 % des Abstands

/** Sozialrabatt auf Joker-Preise: untere Hälfte −30 %, Letzter −50 %. */
export function sozialrabattFaktor(platz: number, spielerzahl: number): number {
  if (spielerzahl >= 2 && platz === spielerzahl) return 0.5;
  if (platz > spielerzahl / 2) return 0.7;
  return 1.0;
}

// ---------- Match → All-Time (§3.6) ----------

/** AT = Match-Endstand / 10 (mind. 50); Sieger ×1,5 auf seinen Betrag. */
export function atFuerEndstand(endstand: number, istSieger: boolean): number {
  const basis = Math.max(50, Math.floor(Math.max(0, endstand) / 10));
  return istSieger ? Math.round(basis * 1.5) : basis;
}

// ---------- GM-Leitplanken ----------

/** Soft-Cap für Punkte ± (§4.2 Werkzeug 1): ±20 % des Runden-Maximums. */
export function scoreAdjustSoftCap(fragenProRunde: number): number {
  // Runden-Maximum grob: HARD-Grundwert × Fragen (ohne Boni) — bewusst großzügig.
  return Math.round(0.2 * 500 * Math.max(1, fragenProRunde));
}
