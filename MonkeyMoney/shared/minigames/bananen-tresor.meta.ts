// Der Bananen-Tresor (Schätzrunde, GAME-DESIGN §2.3) — beidseitige Meta, Fragen-Typ
// (angelehnt an CONTENT-PLAN §2.3 `schaetz`), Festwert-Auszahlung und Slider-Skala.
export const BANANEN_TRESOR_ID = "bananen-tresor";

export const BANANEN_TRESOR_META = {
  id: BANANEN_TRESOR_ID,
  name: "Der Bananen-Tresor",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["slider"] as const,
  contentKind: "estimate" as const,
  streak: false, // §2.3: kein Speed-Bonus, KEINE Streak („der große Gleichmacher")
  // KEIN perSpielerFragen: Schätzfragen (kein MC-4) — Maßanzug greift hier nicht.
};

/**
 * Schätzfrage — Feldnamen folgen CONTENT-PLAN §2.3 (`schaetz`); Pool-Fragen
 * (kind "schaetz" aus dem Content-Loader) docken 1:1 an. `variante: "hard"`
 * schaltet die Marathon-Spätrunden-Festwerte (§2.3) frei.
 */
export interface TresorFrage {
  id: string;
  text: string;
  einheit: string;
  richtwert: number;
  eingabeMin: number;
  eingabeMax: number;
  skala: "linear" | "log";
  variante: "standard" | "hard";
  erklaerung: string;
  /** Volltreffer-Fenster in % vom Richtwert (Pool-Fragen; eingebaute Fragen
   * ohne Toleranz zahlen den Volltreffer nur bei EXAKTEM Wert). */
  toleranzProzent?: number;
  /** ABSOLUTE Toleranz in Einheiten — hat VORRANG vor toleranzProzent
   * (Jahreszahl-Fix: 1 % von 1969 wären ±20 Jahre, ±2–5 Jahre sind fair). */
  toleranzAbsolut?: number;
}

/** Volltreffer-Fenster der Frage in Einheiten: absolut VOR prozentual;
 * eingebaute Fragen ohne Toleranz-Felder verlangen den exakten Wert (0). */
export function volltrefferToleranz(
  frage: Pick<TresorFrage, "richtwert" | "toleranzProzent" | "toleranzAbsolut">,
): number {
  if (frage.toleranzAbsolut !== undefined && frage.toleranzAbsolut > 0) {
    return frage.toleranzAbsolut;
  }
  if (frage.toleranzProzent !== undefined && frage.toleranzProzent > 0) {
    return Math.abs(frage.richtwert) * (frage.toleranzProzent / 100);
  }
  return 0;
}

/**
 * Spieler-Aktionen: `tipp` = Slider bewegt (letzter Stand zählt auch ohne
 * Einloggen, §2.3 Edge-Case), `einloggen` = verbindlich einrasten.
 */
export type BananenTresorAction =
  { type: "tipp"; wert: number } | { type: "einloggen"; wert: number };

/** 20 s schätzen — fix, unabhängig von der Schwierigkeit (GAME-DESIGN §2.3). */
export const TRESOR_TIMER_MS = 20_000;

/**
 * Festwert-Auszahlung (immer, „Schätzen lohnt immer"): Plätze 1–3, Rest-Festwert
 * für alle Übrigen MIT Tipp, Volltreffer-Jackpot bei exaktem Wert (§2.3).
 */
export const TRESOR_FESTWERTE: Record<
  "standard" | "hard",
  { plaetze: readonly [number, number, number]; rest: number; volltreffer: number }
> = {
  standard: { plaetze: [400, 250, 150], rest: 50, volltreffer: 1000 },
  hard: { plaetze: [800, 500, 300], rest: 100, volltreffer: 2000 },
};

// ---------- Slider-Skala (Client-Slider UND Screen-Zahlenstrahl nutzen sie) ----------

/** Wert → Anteil [0,1] auf der Frage-Skala (log-Skala für große Spannen). */
export function wertZuAnteil(
  frage: Pick<TresorFrage, "eingabeMin" | "eingabeMax" | "skala">,
  wert: number,
): number {
  const w = Math.min(frage.eingabeMax, Math.max(frage.eingabeMin, wert));
  if (frage.skala === "log") {
    const min = Math.log(Math.max(1, frage.eingabeMin));
    const max = Math.log(frage.eingabeMax);
    return (Math.log(Math.max(1, w)) - min) / (max - min);
  }
  return (w - frage.eingabeMin) / (frage.eingabeMax - frage.eingabeMin);
}

/** Anteil [0,1] → gerundeter Wert auf der Frage-Skala (Umkehrung von wertZuAnteil). */
export function anteilZuWert(
  frage: Pick<TresorFrage, "eingabeMin" | "eingabeMax" | "skala">,
  anteil: number,
): number {
  const a = Math.min(1, Math.max(0, anteil));
  if (frage.skala === "log") {
    const min = Math.log(Math.max(1, frage.eingabeMin));
    const max = Math.log(frage.eingabeMax);
    return Math.round(Math.exp(min + a * (max - min)));
  }
  return Math.round(frage.eingabeMin + a * (frage.eingabeMax - frage.eingabeMin));
}
