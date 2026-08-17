// Duell am Lianensteg (GAME-DESIGN §2.12/6, v2 — Detail: docs/ideen/02 Nr. 15):
// 1v1-Buzzer-Duell nach dem HERAUSFORDERER-Prinzip. Der LETZTE des
// Zwischenstands ist der Herausforderer (Comeback-Beat, deterministisch über
// ctx.match.balance) und wählt seinen Gegner; „Feiglings-Schutz": der Letzte
// unter den GEGNERN kann nicht gezwungen werden (sofern es Alternativen gibt),
// der Führende ist IMMER wählbar. Timeout wählt den Führenden.
// Die NICHT-Duellanten wetten vor Duellbeginn 50 MM auf den Sieger
// (Zuschauer-Einbindung!). Wett-Abrechnung PARI-MUTUEL und EXAKT NULLSUMMIG:
// alle Einsätze wandern in den Wett-Topf, die richtigen Wetter teilen ihn
// (Anteil auf 10er abgerundet), der Rundungs-Rest geht als „Trinkgeld" an den
// Duell-Sieger — beim 50/50-Split ergibt das genau „Einsatz ×2" (Design).
// Duell: Best-of-5 Speed-MC-4 (3-2-1-Countdown, 10 s) — bei BEIDEN richtig
// entscheidet ctx.buzzer.ordne (Median-RTT-faire Zeiten + Fotofinish-Los).
// Sieger: 300 MM aus der Bank + 100 MM DIREKT vom Konto des Verlierers
// (nullsummiger Transfer). Sudden Death bei Gleichstand nach 5 Fragen;
// doppelter Sudden-Death-Gleichstand (Fotofinish) = geteilter Sieg (je 150,
// Wetten zurück). Duellant-Disconnect: kampflos (300 aus der Bank, KEIN
// Konto-Abzug beim Verlierer, Wetten zurück).
export const LIANENSTEG_DUELL_ID = "lianensteg-duell";

export const LIANENSTEG_DUELL_META = {
  id: LIANENSTEG_DUELL_ID,
  name: "Duell am Lianensteg",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons", "buzzer"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() pro Runde: das Duell braucht die ganze Fragen-Serie (Best-of-5
  // + Sudden-Death-Reserve) und bucht am Ende genau einmal.
  roundBased: true,
  // Prämie/Transfer/Wetten sind kein ±W-Standard — keine Streak (§3.2-Schutz).
  streak: false,
};

/**
 * Spieler-Aktionen: `herausfordern` = Gegner-Wahl (NUR der Herausforderer),
 * `wette` = 50-MM-Siegerwette (NUR Zuschauer, vor Duellbeginn),
 * `answer` = Speed-MC-4-Antwort der Duellanten (die Antwort IST der Buzz).
 */
export type LianenstegDuellAction =
  | { type: "herausfordern"; targetId: string }
  | { type: "wette"; auf: string }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing (Design Nr. 15: „5 Fragen à 10 s", 3-2-1-Countdown) ----------
export const LD_HERAUSFORDERUNG_MS = 10_000; // Gegner-Wahl-Fenster
export const LD_WETTEN_MS = 10_000; // Zuschauer-Wetten vor Duellbeginn
export const LD_COUNTDOWN_MS = 3_000; // 3-2-1 vor jeder Teilfrage
export const LD_FRAGE_MS = 10_000; // Teilfragen-Fenster (timerFaktor wirkt)
export const LD_SCHUBS_MS = 3_000; // Teilfragen-Ergebnis (Schubs-Animation)
export const LD_ERGEBNIS_MS = 8_000; // Sieger-Cutscene + Wett-Abrechnung

// ---------- Duell-Regeln (Design Nr. 15, verbindlich) ----------
export const LD_BESTOF = 5; // maximal 5 reguläre Teilfragen
export const LD_SIEGE = 3; // wer zuerst 3 Teilfragen holt, siegt sofort
export const LD_SUDDEN_DEATH_MAX = 2; // danach: geteilter Sieg (Anti-Endlos)
export const LD_WETTE_MM = 50; // fester Zuschauer-Einsatz
export const LD_SIEG_BANK_MM = 300; // Sieger-Prämie aus der Bank
export const LD_SIEG_TRANSFER_MM = 100; // direkt vom Konto des Verlierers
export const LD_GETEILT_MM = 150; // geteilter Sieg: beide aus der Bank

/** Pari-Mutuel-Anteil pro richtigem Wetter: Topf / Richtige, auf 10er ab. */
export function ldWettAnteil(topf: number, richtige: number): number {
  if (richtige <= 0) return 0;
  return Math.floor(topf / richtige / 10) * 10;
}

export interface LdWettErgebnis {
  /** Delta pro WETTER (Einsatz schon verrechnet): richtig +Anteil−50, falsch −50. */
  deltas: Record<string, number>;
  /** Rundungs-Rest des Topfs — geht als „Trinkgeld" an den Duell-Sieger. */
  restAnSieger: number;
}

/**
 * Wett-Abrechnung (EXAKT nullsummig): Σ deltas + restAnSieger = 0.
 * sieger = null (geteilt/kampflos/abgebrochen) ⇒ alle Wetten zurück (0/0).
 * Keine richtige Wette ⇒ der GANZE Topf geht an den Sieger.
 */
export function ldWettAbrechnung(
  wetten: Record<string, string>,
  sieger: string | null,
): LdWettErgebnis {
  const deltas: Record<string, number> = {};
  const wetter = Object.keys(wetten);
  if (sieger === null) {
    for (const w of wetter) deltas[w] = 0;
    return { deltas, restAnSieger: 0 };
  }
  const topf = wetter.length * LD_WETTE_MM;
  const richtige = wetter.filter((w) => wetten[w] === sieger);
  const anteil = ldWettAnteil(topf, richtige.length);
  for (const w of wetter) {
    deltas[w] = richtige.includes(w) ? anteil - LD_WETTE_MM : -LD_WETTE_MM;
  }
  return { deltas, restAnSieger: topf - anteil * richtige.length };
}
