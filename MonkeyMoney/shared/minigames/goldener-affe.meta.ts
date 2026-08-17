// Der Goldene Affe (GAME-DESIGN §2.12 „v2-Finale-Alternative", Detail:
// docs/ideen/02 Nr. 22): dreistufiges Wechselfinale — der goldene Affentempel
// öffnet sich Stufe für Stufe.
//   STUFE 1 „Money-Drop": jeder verteilt 10 Chips auf die 4 Antworten einer
//   MC-4-Frage. Einsatz = 50 % des ECHTEN Kontostands (ctx.match, auf 10er
//   gerundet, mind. 100; Konto < 200 ⇒ 100 MM Gratis-Einsatz der Bank —
//   falsch kostet dann nichts). Chips auf der richtigen Tür kommen ×2 zurück,
//   der Rest fällt in den Abgrund. KEINE Verteilung = KEIN Einsatz (AFK-Schutz).
//   STUFE 2 „Schätz-Showdown": eine Schätzfrage, die 2 NÄCHSTEN am Richtwert
//   werden Finalisten, alle anderen scheiden aus (Distanz-Gleichstand: frühere
//   Abgabe). Kein Tipp = ausgeschieden. 2-Spieler-Spiel: Stufe entfällt.
//   Ausgeschiedene bleiben beteiligt: EINE 50-MM-Siegerwette auf einen
//   Finalisten — richtige Wetten zahlen ×3 (Design: aus der Bank, netto +100).
//   STUFE 3 „Buzzer-Best-of-3": Speed-MC-4, die schnellste RICHTIGE Antwort
//   holt den Punkt (ctx.buzzer-Ranking + Fotofinish-Los), 2 Punkte siegen.
//   Gleichstand nach 3 Fragen ⇒ finale Schätzfrage („die ultimative Antwort"),
//   näher dran gewinnt.
// DER SIEGER „nimmt die Bananen mit": +20 % der (projizierten) Konten aller
// anderen — ein EXAKT NULLSUMMIGER Transfer (Kappe: nur positive Konten).
export const GOLDENER_AFFE_ID = "goldener-affe";

export const GOLDENER_AFFE_META = {
  id: GOLDENER_AFFE_ID,
  name: "Der Goldene Affe",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons", "slider", "buzzer"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() für das ganze 3-Stufen-Finale (Drop-Frage + Buzzer-Serie),
  // genau EINE Buchung am Ende.
  roundBased: true,
  // Einsatz-/Wett-/Transfer-Payoffs sind kein ±W-Standard — keine Streak.
  streak: false,
};

/**
 * Spieler-Aktionen: `chips` = komplette Verteilung (letzter Stand im Fenster
 * zählt), `answer` = in Stufe 1 der „Alles auf eins"-Schnellzug, in Stufe 3
 * die Speed-Antwort der Finalisten. `tipp`/`einloggen` = Schätz-Slider
 * (Tresor-Konvention: letzter Stand zählt, Einloggen rastet ein).
 * `wette` = 50-MM-Siegerwette der Ausgeschiedenen.
 */
export type GoldenerAffeAction =
  | { type: "chips"; verteilung: number[] }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 }
  | { type: "tipp"; wert: number }
  | { type: "einloggen"; wert: number }
  | { type: "wette"; auf: string };

/** Schätzfrage der Stufen 2/Showdown (Feldnamen wie CONTENT-PLAN §2.3). */
export interface GaSchaetzfrage {
  id: string;
  text: string;
  einheit: string;
  richtwert: number;
  eingabeMin: number;
  eingabeMax: number;
  erklaerung: string;
}

// ---------- Timing (Design Nr. 22: „Stufe 1: 30 s, Stufe 2: 20 s, 3×10 s") ----------
export const GA_DROP_MS = 30_000;
export const GA_DROP_ERGEBNIS_MS = 8_000; // Falltür-Dramaturgie
export const GA_SCHAETZ_MS = 20_000;
export const GA_SCHAETZ_ERGEBNIS_MS = 6_000;
export const GA_WETTEN_MS = 10_000;
export const GA_BUZZER_FRAGE_MS = 10_000; // timerFaktor wirkt
export const GA_BUZZER_ERGEBNIS_MS = 4_000;
export const GA_KROENUNG_MS = 8_000;

// ---------- Regeln (Design Nr. 22, verbindlich) ----------
export const GA_CHIPS = 10;
export const GA_EINSATZ_ANTEIL = 0.5; // „mind. 50 % seines Vermögens"
export const GA_MIN_EINSATZ = 100; // darunter: Gratis-Einsatz der Bank
export const GA_FINALISTEN = 2;
export const GA_BUZZER_SIEGE = 2; // Best-of-3
export const GA_BUZZER_FRAGEN = 3;
export const GA_WETTE_MM = 50; // Häppchen der Ausgeschiedenen
export const GA_WETTE_FAKTOR = 3; // Auszahlung ×3 (netto +2×Einsatz, Bank)
export const GA_SIEGER_ANTEIL = 0.2; // „nimmt 20 % der Konten mit"

/** Money-Drop-Einsatz aus dem echten Kontostand (10er-Rundung, mind. 100). */
export function gaEinsatz(konto: number): { betrag: number; gratis: boolean } {
  const haelfte = Math.round((konto * GA_EINSATZ_ANTEIL) / 10) * 10;
  if (haelfte < GA_MIN_EINSATZ) return { betrag: GA_MIN_EINSATZ, gratis: true };
  return { betrag: haelfte, gratis: false };
}

/** Drop-Delta: Chips auf der richtigen Tür ×2 zurück, Rest weg (10er-Rundung).
 * Gratis-Einsatz: Verlust trägt die Bank (Delta nie negativ). */
export function gaDropDelta(
  einsatz: { betrag: number; gratis: boolean },
  chipsRichtig: number,
): number {
  const zurueck = Math.round((((einsatz.betrag * chipsRichtig) / GA_CHIPS) * 2) / 10) * 10;
  const delta = zurueck - einsatz.betrag;
  return einsatz.gratis ? Math.max(0, delta) : delta;
}

/** Timeout-Regel (Design Nr. 9): unverteilte Chips wandern reihum auf die
 * BELEGTEN Felder (deterministisch ab dem niedrigsten Index). Nichts belegt ⇒
 * leer (kein Einsatz). */
export function gaFuelleChipsAuf(verteilung: number[]): number[] {
  const felder = [0, 1, 2, 3].map((i) => Math.max(0, Math.floor(verteilung[i] ?? 0)));
  let summe = felder.reduce((a, b) => a + b, 0);
  if (summe === 0) return felder;
  if (summe > GA_CHIPS) {
    // Überzogene Verteilungen proportional stutzen (Server traut keinem Client).
    const skaliert = felder.map((c) => Math.floor((c * GA_CHIPS) / summe));
    let rest = GA_CHIPS - skaliert.reduce((a, b) => a + b, 0);
    for (let i = 0; i < 4 && rest > 0; i++) {
      if (felder[i] > 0) {
        skaliert[i] += 1;
        rest -= 1;
      }
    }
    return skaliert;
  }
  const belegt = [0, 1, 2, 3].filter((i) => felder[i] > 0);
  let i = 0;
  while (summe < GA_CHIPS) {
    felder[belegt[i % belegt.length]] += 1;
    summe += 1;
    i += 1;
  }
  return felder;
}

/** 20-%-Transfer eines (projizierten) Kontos an den Sieger — 10er-Rundung ab,
 * nie aus dem Minus (nullsummiger Transfer). */
export function gaTransfer(konto: number): number {
  return Math.floor((Math.max(0, konto) * GA_SIEGER_ANTEIL) / 10) * 10;
}
