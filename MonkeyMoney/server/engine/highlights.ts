// REPLAY-HIGHLIGHTS (v2, E-01): Heuristiken über der Match-Chronik.
// Die Engine sammelt während des Matches kompakte Chronik-Einträge (dieselben
// Daten, die auch ins JSONL-Event-Log fließen); am Match-Ende extrahiert
// extrahiereHighlights daraus die 3–5 besten Momente für die
// „Highlights des Abends"-Sequenz vor der Siegerehrung.
// ALLES pure + deterministisch — kein Rng, keine Uhr (Testbarkeit!).
import { formatMM } from "../../shared/money";

/** Kompakter Chronik-Eintrag — wird in schliesseFrageAb aus Buchungs-Events,
 * Plugin-Outcomes und Minigame-State (Duck-Typing) abgeleitet. */
export type ChronikEintrag =
  | {
      art: "antwort";
      playerId: string;
      frageNr: number;
      correct: boolean;
      delta: number;
      nachMs?: number;
    }
  | { art: "buzzer"; playerId: string; zweiterId: string; deltaMs: number; frageNr: number }
  | { art: "klau"; dieb: string; opfer: string; betrag: number; frageNr: number }
  | { art: "bank"; playerId: string; betrag: number; frageNr: number }
  | { art: "jackpot"; playerId: string; betrag: number; frageNr: number }
  | { art: "stand"; frageNr: number; staende: Record<string, number> };

export type HighlightArt =
  | "groesster-klau"
  | "knappster-buzzer"
  | "teuerste-falschantwort"
  | "bank-verrat"
  | "comeback"
  | "jackpot";

export interface Highlight {
  id: string;
  art: HighlightArt;
  titel: string;
  text: string;
  playerId: string; // Haupt-Akteur („DU warst das!" auf dem eigenen Handy)
  gegnerId?: string;
  betrag?: number;
  frageNr: number;
  /** Spektakel-Wert der Auswahl-Heuristik (nur für die Top-5-Auswahl). */
  score: number;
}

// ---------- Schwellen der Heuristiken (Design-Zahlen, testbar) ----------
export const HIGHLIGHT_MAX_ANZAHL = 5;
/** Klaus unter 50 MM sind kein Highlight (Abpraller/Mini-Beute). */
export const HIGHLIGHT_MIN_KLAU = 50;
/** „Knappster Buzzer": nur Fotofinish-Momente mit Delta < 50 ms. */
export const HIGHLIGHT_BUZZER_MS = 50;
/** Falschantworten unter 100 MM Verlust sind kein Drama. */
export const HIGHLIGHT_MIN_FALSCHANTWORT = 100;
/** Comeback braucht mindestens 2 gutgemachte Plätze. */
export const HIGHLIGHT_MIN_COMEBACK_PLAETZE = 2;

const nameVon = (namen: Record<string, string>, id: string): string => namen[id] ?? "?";

/** Rang eines Spielers in einem Stand (1-basiert; Gleichstand teilt den Rang). */
function rang(staende: Record<string, number>, playerId: string): number {
  const eigener = staende[playerId] ?? 0;
  return 1 + Object.values(staende).filter((b) => b > eigener).length;
}

function groessterKlau(chronik: ChronikEintrag[], namen: Record<string, string>): Highlight | null {
  let bester: (ChronikEintrag & { art: "klau" }) | null = null;
  for (const e of chronik) {
    if (e.art !== "klau" || e.betrag < HIGHLIGHT_MIN_KLAU) continue;
    if (bester === null || e.betrag > bester.betrag) bester = e;
  }
  if (bester === null) return null;
  return {
    id: `hl-klau-${bester.frageNr}`,
    art: "groesster-klau",
    titel: "🕵️ Der Mega-Klau",
    text: `${nameVon(namen, bester.dieb)} zieht ${nameVon(namen, bester.opfer)} eiskalt ${formatMM(bester.betrag)} aus der Tasche!`,
    playerId: bester.dieb,
    gegnerId: bester.opfer,
    betrag: bester.betrag,
    frageNr: bester.frageNr,
    score: bester.betrag,
  };
}

function knappsterBuzzer(
  chronik: ChronikEintrag[],
  namen: Record<string, string>,
): Highlight | null {
  let bester: (ChronikEintrag & { art: "buzzer" }) | null = null;
  for (const e of chronik) {
    if (e.art !== "buzzer" || e.deltaMs >= HIGHLIGHT_BUZZER_MS) continue;
    if (bester === null || e.deltaMs < bester.deltaMs) bester = e;
  }
  if (bester === null) return null;
  return {
    id: `hl-buzzer-${bester.frageNr}`,
    art: "knappster-buzzer",
    titel: "⚡ Fotofinish am Buzzer",
    text: `${nameVon(namen, bester.playerId)} schlägt ${nameVon(namen, bester.zweiterId)} um ${bester.deltaMs} Millisekunden — Wimpernschlag!`,
    playerId: bester.playerId,
    gegnerId: bester.zweiterId,
    betrag: undefined,
    frageNr: bester.frageNr,
    score: 900 - bester.deltaMs * 10,
  };
}

function teuersteFalschantwort(
  chronik: ChronikEintrag[],
  namen: Record<string, string>,
): Highlight | null {
  let beste: (ChronikEintrag & { art: "antwort" }) | null = null;
  for (const e of chronik) {
    if (e.art !== "antwort" || e.correct || e.delta > -HIGHLIGHT_MIN_FALSCHANTWORT) continue;
    if (beste === null || e.delta < beste.delta) beste = e;
  }
  if (beste === null) return null;
  const verlust = Math.abs(beste.delta);
  return {
    id: `hl-patzer-${beste.frageNr}`,
    art: "teuerste-falschantwort",
    titel: "💸 Der teuerste Patzer",
    text: `${nameVon(namen, beste.playerId)} versenkt ${formatMM(verlust)} mit EINER falschen Antwort. Autsch.`,
    playerId: beste.playerId,
    betrag: verlust,
    frageNr: beste.frageNr,
    score: verlust * 1.2,
  };
}

function bankVerrat(
  chronik: ChronikEintrag[],
  namen: Record<string, string>,
  teamsAktiv: boolean,
): Highlight | null {
  let bester: (ChronikEintrag & { art: "bank" }) | null = null;
  for (const e of chronik) {
    if (e.art !== "bank" || e.betrag <= 0) continue;
    if (bester === null || e.betrag > bester.betrag) bester = e;
  }
  if (bester === null) return null;
  // „Team-Pott" nur im Team-Modus — im Einzelspiel gibt es keinen (Playtest 3).
  const quelle = teamsAktiv ? "aus dem Team-Pott" : "aus der Kette";
  return {
    id: `hl-bank-${bester.frageNr}`,
    art: "bank-verrat",
    titel: "🏦 BANK! Der Verrat",
    text: `${nameVon(namen, bester.playerId)} drückt BANK! und reißt ${formatMM(bester.betrag)} ${quelle} — die Kette reißt!`,
    playerId: bester.playerId,
    betrag: bester.betrag,
    frageNr: bester.frageNr,
    score: bester.betrag * 1.1,
  };
}

function jackpotGewinn(chronik: ChronikEintrag[], namen: Record<string, string>): Highlight | null {
  let bester: (ChronikEintrag & { art: "jackpot" }) | null = null;
  for (const e of chronik) {
    if (e.art !== "jackpot" || e.betrag <= 0) continue;
    if (bester === null || e.betrag > bester.betrag) bester = e;
  }
  if (bester === null) return null;
  return {
    id: `hl-jackpot-${bester.frageNr}`,
    art: "jackpot",
    titel: "🏺 Jackpot geknackt!",
    text: `${nameVon(namen, bester.playerId)} ist am schnellsten und schnappt sich das Jackpot-Glas: +${formatMM(bester.betrag)}!`,
    playerId: bester.playerId,
    betrag: bester.betrag,
    frageNr: bester.frageNr,
    score: bester.betrag,
  };
}

/** Comeback-Sprung: größte Rang-Verbesserung von irgendeinem Zwischenstand
 * zum END-Stand (deterministisch: bei Gleichstand gewinnt die frühere
 * playerId in sortierter Reihenfolge). */
function comebackSprung(
  chronik: ChronikEintrag[],
  namen: Record<string, string>,
): Highlight | null {
  const staende = chronik.filter((e): e is ChronikEintrag & { art: "stand" } => e.art === "stand");
  if (staende.length < 2) return null;
  const final = staende[staende.length - 1];
  const spieler = Object.keys(final.staende).sort();
  let bester: { playerId: string; von: number; nach: number; plaetze: number } | null = null;
  for (const id of spieler) {
    const nach = rang(final.staende, id);
    let schlechtester = nach;
    for (const s of staende.slice(0, -1)) {
      schlechtester = Math.max(schlechtester, rang(s.staende, id));
    }
    const plaetze = schlechtester - nach;
    if (plaetze < HIGHLIGHT_MIN_COMEBACK_PLAETZE) continue;
    if (bester === null || plaetze > bester.plaetze) {
      bester = { playerId: id, von: schlechtester, nach, plaetze };
    }
  }
  if (bester === null) return null;
  return {
    id: `hl-comeback-${final.frageNr}`,
    art: "comeback",
    titel: "📈 Die Aufholjagd",
    text: `${nameVon(namen, bester.playerId)} kämpft sich von Platz ${bester.von} auf Platz ${bester.nach} — Comeback des Abends!`,
    playerId: bester.playerId,
    frageNr: final.frageNr,
    score: bester.plaetze * 300,
  };
}

/**
 * DIE Extraktion: alle Heuristik-Kandidaten sammeln, nach Spektakel-Wert die
 * Top-N auswählen und CHRONOLOGISCH (frageNr) für die Sequenz ordnen.
 * Pure + deterministisch: gleiche Chronik ⇒ exakt gleiche Highlights.
 */
export function extrahiereHighlights(
  chronik: ChronikEintrag[],
  namen: Record<string, string>,
  maxAnzahl = HIGHLIGHT_MAX_ANZAHL,
  teamsAktiv = false,
): Highlight[] {
  const kandidaten = [
    groessterKlau(chronik, namen),
    knappsterBuzzer(chronik, namen),
    teuersteFalschantwort(chronik, namen),
    bankVerrat(chronik, namen, teamsAktiv),
    jackpotGewinn(chronik, namen),
    comebackSprung(chronik, namen),
  ].filter((h): h is Highlight => h !== null);
  // Auswahl: Spektakel-Wert absteigend (Gleichstand: stabile Kandidaten-Reihenfolge).
  const auswahl = [...kandidaten].sort((a, b) => b.score - a.score).slice(0, maxAnzahl);
  // Sequenz: chronologisch erzählt (frageNr aufsteigend, Gleichstand: nach Art-Id).
  return auswahl.sort((a, b) => a.frageNr - b.frageNr || a.id.localeCompare(b.id));
}
