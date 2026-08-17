// „Einer gegen alle" (einer-gegen-alle, Welle 4): der Spielshow-Klassiker
// „einer gegen den Rest des Saals" — der FÜHRENDE des Zwischenstands tritt
// als SOLIST allein gegen die versammelte Menge an.
// ABLAUF: EGA_FRAGEN MC-4-Fragen. Der Solist antwortet für sich, die Menge
// stimmt kollektiv ab — die MEHRHEITS-Antwort zählt für das Team (Gleichstand
// zwischen Top-Optionen: das Los entscheidet, ctx.rng). Der Solist sieht die
// Mengen-Antwort NIE vor der Auflösung (Leak-Wache!), die Abstimmungs-Balken
// bleiben bis zur Enthüllung anonym (nur die Stimm-ANZAHL reist live).
// GELD-REGELN (verbindlich, alles aus der Bank):
//   · Solist richtig + Menge falsch  = Solist +EGA_SOLO_MM (400)
//   · beide richtig                  = je +EGA_BEIDE_MM (150 — Solist UND
//     jedes Mengen-Mitglied)
//   · Menge richtig + Solist falsch  = jedes Mengen-Mitglied +EGA_TEAM_MM (200)
//   · beide falsch                   = nichts
// EDGE-CASES: Solist-Disconnect = das Format endet NEUTRAL (niemand bekommt
// etwas); Mengen-Mitglied-Disconnect = seine Stimme entfällt künftig, das
// Team spielt weiter; KEINE Stimmen in einem Fenster = die Menge liegt falsch.
// MINDESTBESETZUNG: 3 Spieler (1 Solist + Menge ab 2) — meta.minPlayers 3
// (dokumentarisch wie beim Bananen-Bluff: die Engine erzwingt das Feld nicht;
// mit 2 Spielern degradiert das Format sauber zum Duell Solist vs. 1er-Menge).

export const EINER_GEGEN_ALLE_ID = "einer-gegen-alle";

export const EINER_GEGEN_ALLE_META = {
  id: EINER_GEGEN_ALLE_ID,
  name: "Einer gegen alle",
  // 1 Solist braucht mindestens 2 Gegenstimmen — sonst ist es nur ein Duell.
  minPlayers: 3,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // EIN init() pro Runde: der Schlagabtausch braucht die ganze Fragen-Serie
  // (EGA_FRAGEN Duell-Beats) und bucht am Ende genau einmal.
  roundBased: true,
  // Solo-/Team-Prämien sind kein ±W-Standard — keine Streak (§3.2).
  streak: false,
  // answeredCount zählt Solist-Antwort UND Mengen-Stimmen gemischt — die
  // Auto-GM-+10s-Heuristik wäre hier irreführend.
  autoVerlaengerung: false,
};

/** Spieler-Aktionen: `answer` = Solist-Antwort ODER Mengen-Stimme (dasselbe
 * Feld — der Server weiß, wer Solist ist; erste Wahl rastet ein). */
export type EinerGegenAlleAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing ----------
export const EGA_VORSTELLUNG_MS = 6_000; // Podest-Beat: Solist vs. Tribüne
export const EGA_FRAGE_MS = 12_000; // Antwort-/Abstimmungs-Fenster (timerFaktor)
export const EGA_ENTHUELLUNG_MS = 6_000; // Balken fallen, Deltas fliegen
export const EGA_ERGEBNIS_MS = 7_000; // Schluss-Bilanz Solist vs. Team

// ---------- Geld-Regeln (verbindlich) ----------
/** Anzahl Fragen pro Runde. */
export const EGA_FRAGEN = 6;
/** Solist richtig + Menge falsch: der Solo-Coup. */
export const EGA_SOLO_MM = 400;
/** Beide richtig: der Unentschieden-Beat (jeder — Solist UND Menge). */
export const EGA_BEIDE_MM = 150;
/** Menge richtig + Solist falsch: der Team-Triumph (jedes Mengen-Mitglied). */
export const EGA_TEAM_MM = 200;

/** Ergebnis der Mehrheits-Auszählung eines Abstimmungs-Fensters. */
export interface EgaMehrheit {
  /** Die Team-Antwort — null, wenn KEINE Stimmen abgegeben wurden. */
  choice: number | null;
  /** Stimmen je Option (Länge = Options-Zahl). */
  verteilung: number[];
  /** true = Gleichstand zwischen Top-Optionen, das Los hat entschieden. */
  gleichstand: boolean;
}

/**
 * Mehrheits-Logik (Single Source of Truth für Plugin, Tests UND Bot-Beweis):
 * meiste Stimmen gewinnen; Gleichstand zwischen den Top-Optionen ⇒ Los über
 * den injizierten Rng (deterministisch mit Seed); keine Stimmen ⇒ null.
 */
export function egaMehrheit(
  stimmen: Record<string, number>,
  optionsZahl: number,
  rng: { int: (maxExclusive: number) => number },
): EgaMehrheit {
  const verteilung = Array.from({ length: optionsZahl }, () => 0);
  for (const choice of Object.values(stimmen)) {
    if (Number.isInteger(choice) && choice >= 0 && choice < optionsZahl) verteilung[choice] += 1;
  }
  const max = Math.max(...verteilung);
  if (max === 0) return { choice: null, verteilung, gleichstand: false };
  const spitze = verteilung.flatMap((n, i) => (n === max ? [i] : []));
  if (spitze.length === 1) return { choice: spitze[0], verteilung, gleichstand: false };
  return { choice: spitze[rng.int(spitze.length)], verteilung, gleichstand: true };
}

/**
 * Geld-Mathe einer Frage (Single Source of Truth): Solo-Coup 400 · beide
 * richtig je 150 · Team-Triumph 200 pro Mengen-Mitglied · beide falsch nichts.
 */
export function egaFrageDeltas(
  solist: string,
  menge: readonly string[],
  solistRichtig: boolean,
  mengeRichtig: boolean,
): Record<string, number> {
  const deltas: Record<string, number> = { [solist]: 0 };
  for (const p of menge) deltas[p] = 0;
  if (solistRichtig && !mengeRichtig) deltas[solist] = EGA_SOLO_MM;
  if (solistRichtig && mengeRichtig) {
    deltas[solist] = EGA_BEIDE_MM;
    for (const p of menge) deltas[p] = EGA_BEIDE_MM;
  }
  if (!solistRichtig && mengeRichtig) {
    for (const p of menge) deltas[p] = EGA_TEAM_MM;
  }
  return deltas;
}
