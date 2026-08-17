// Match-Plan-Bau (GAME-DESIGN §1.2/§1.3): aus Settings + Modi-Blaupause entsteht
// die Abschnitts-Folge (Runden + Jackpot-Beat + Finale) mit Slot-Dramaturgie.
// Fragen-Auswahl mit Degradations-Kette (Kategorie → Schwierigkeit → Pool → Recycle).
import type { Question } from "../../shared/content";
import type { Rng } from "../../shared/rng";
import type { Schwierigkeit } from "../../shared/money";
import { AFFENLEITER_ID } from "../../shared/minigames/affenleiter.meta";
import { BANANEN_BASICS_ID } from "../../shared/minigames/bananen-basics.meta";
import { BANANEN_TRESOR_ID } from "../../shared/minigames/bananen-tresor.meta";
import { PIXEL_DSCHUNGEL_ID } from "../../shared/minigames/pixel-dschungel.meta";
import { VIER_LIANEN_ID } from "../../shared/minigames/vier-lianen.meta";
import { MODUS_BLAUPAUSEN, rundenFuerSettings, type MatchSettings } from "../../shared/settings";
import type { Abschnitt, EngineState, MatchPlan } from "./types";

/** Fallback-Frageformat: das immer vorhandene Referenz-Plugin. */
export const FALLBACK_MINIGAME = "vier-lianen";

/**
 * Format-Content-Zuordnung: Bild-Fragen (question.media) gehören NUR in
 * Formate, die das Bild inszenieren — heute Pixel-Dschungel. Andere Formate
 * würden „Was enthüllt sich hier?" ohne Bild stellen (kaputt).
 */
const BILD_FORMATE = new Set<string>([PIXEL_DSCHUNGEL_ID]);
/** Schätzfragen (kind "schaetz") spielt NUR der Bananen-Tresor (Slider). */
const SCHAETZ_FORMATE = new Set<string>([BANANEN_TRESOR_ID]);
/** Sortierfragen (kind "sortier") spielt NUR die Affenleiter (dragList). */
const SORTIER_FORMATE = new Set<string>([AFFENLEITER_ID]);
/** Wahr/Falsch (2 XXL-Optionen): Opener + Referenz-Format zeigen sie als
 * 2-Optionen-Frage — andere Quiz-Formate bleiben bewusst bei MC-4 (deren
 * Mechaniken wie Bluff-Einsätze/Markt-Hedging brauchen 4 Optionen). */
const WAHR_FALSCH_FORMATE = new Set<string>([BANANEN_BASICS_ID, VIER_LIANEN_ID]);

/** Darf dieses Format diese Frage stellen? (Frage-Art ↔ Format-Bühne.) */
export function passtFrageZuFormat(frage: Question, minigameId: string): boolean {
  if (frage.media !== undefined && !BILD_FORMATE.has(minigameId)) return false;
  switch (frage.kind) {
    case "schaetz":
      return SCHAETZ_FORMATE.has(minigameId);
    case "sortier":
      return SORTIER_FORMATE.has(minigameId);
    case "wahr_falsch":
      return WAHR_FALSCH_FORMATE.has(minigameId);
    default:
      // choice4 passt in alle Options-Formate — NICHT auf Slider/Leiter-Bühnen.
      return !SCHAETZ_FORMATE.has(minigameId) && !SORTIER_FORMATE.has(minigameId);
  }
}

/**
 * Plan bauen: Playlist der Modi-Matrix, Wunsch-Minigames gegen die verfügbare
 * Registry auflösen (Fallback aufs Frage-Format), Jackpot vor der RISIKO-Runde,
 * Finale als letzter Abschnitt.
 */
export function baueMatchPlan(settings: MatchSettings, verfuegbar: string[]): MatchPlan {
  const blaupause = MODUS_BLAUPAUSEN[settings.modus];
  const abschnitte: Abschnitt[] = [];
  const kannWaehlen = settings.kategorienWahl !== "aus";

  let rundeNr = 0;
  // v2-Runden (§2.12) laufen nur mit Settings-Flag `v2Formate` (Default an).
  for (const r of rundenFuerSettings(blaupause, settings)) {
    rundeNr += 1;
    if (blaupause.jackpotFrage && r.slot === "risiko") {
      // Jackpot-Beat: 1× pro Match, direkt VOR der RISIKO-Runde (§1.1 Phase 4).
      abschnitte.push({
        typ: "jackpot",
        nr: 0,
        wunschMinigameId: FALLBACK_MINIGAME,
        minigameId: aufloesen(FALLBACK_MINIGAME, verfuegbar),
        fragen: 1,
        schwierigkeiten: ["medium", "hard"],
        kategorieWahl: "keine",
        radDanach: false,
        kategorie: null,
      });
    }
    abschnitte.push({
      typ: "runde",
      nr: rundeNr,
      slot: r.slot,
      wunschMinigameId: r.minigameId,
      minigameId: aufloesen(r.minigameId, verfuegbar),
      fragen: r.fragen,
      schwierigkeiten: r.schwierigkeiten,
      kategorieWahl: kannWaehlen ? r.kategorieWahl : "keine",
      radDanach: settings.rad === "an" && r.radDanach,
      kategorie: null,
    });
  }

  abschnitte.push({
    typ: "finale",
    nr: 0,
    slot: "finale",
    wunschMinigameId: "lianen-finale",
    minigameId: aufloesen("lianen-finale", verfuegbar),
    fragen: blaupause.finaleFragen,
    schwierigkeiten: ["medium", "hard"],
    kategorieWahl: "keine",
    radDanach: false,
    kategorie: null,
  });

  return {
    abschnitte,
    rundenTotal: rundeNr,
    fragenTotal: abschnitte.reduce((sum, a) => sum + a.fragen, 0),
    ultrahardMax: blaupause.ultrahardMax,
  };
}

function aufloesen(wunsch: string, verfuegbar: string[]): string {
  return verfuegbar.includes(wunsch) ? wunsch : FALLBACK_MINIGAME;
}

/**
 * Nächste Frage wählen — Degradations-Kette:
 * GM-Pick → [Bild-Formate: media-Fragen bevorzugt] → Kategorie+Schwierigkeit →
 * Schwierigkeit → Kategorie → beliebig ungenutzt (Format-passend) → Recycle
 * (Klon mit neuer Id). ULTRAHARD respektiert die Match-Kappe (§1.2).
 */
export function waehleFrage(
  state: EngineState,
  abschnitt: Abschnitt,
  rng: Rng,
): { frage: Question; ultrahard: boolean } {
  const used = new Set(state.usedQuestionIds);
  const pool = state.fragenPool;

  // 1) GM-Pick aus dem Fragen-Regal (bewusst OHNE Format-Filter: GM-Override).
  if (state.naechsteFrageId) {
    const gewaehlt = pool.find((q) => q.id === state.naechsteFrageId && !used.has(q.id));
    if (gewaehlt) return { frage: gewaehlt, ultrahard: gewaehlt.difficulty === "ultrahard" };
  }

  const ultraErlaubt = state.plan !== null && state.ultrahardGestellt < state.plan.ultrahardMax;
  const schwierigkeiten = abschnitt.schwierigkeiten.filter(
    (s) => s !== "ultrahard" || ultraErlaubt,
  );

  const kandidaten = (filter: (q: Question) => boolean): Question[] =>
    pool.filter((q) => !used.has(q.id) && filter(q));

  const passt = (q: Question): boolean => passtFrageZuFormat(q, abschnitt.minigameId);
  // Bild-Formate ziehen bevorzugt echte Bild-Fragen (statt Platzhalter-Motiven).
  const bildBevorzugt: ((q: Question) => boolean)[] = BILD_FORMATE.has(abschnitt.minigameId)
    ? [
        (q) =>
          q.media !== undefined &&
          (abschnitt.kategorie === null || q.category === abschnitt.kategorie) &&
          schwierigkeiten.includes(q.difficulty),
        (q) => q.media !== undefined && schwierigkeiten.includes(q.difficulty),
        (q) => q.media !== undefined,
      ]
    : [];

  const stufen: ((q: Question) => boolean)[] = [
    ...bildBevorzugt,
    (q) =>
      passt(q) &&
      (abschnitt.kategorie === null || q.category === abschnitt.kategorie) &&
      schwierigkeiten.includes(q.difficulty),
    (q) => passt(q) && schwierigkeiten.includes(q.difficulty),
    (q) => passt(q) && (abschnitt.kategorie === null || q.category === abschnitt.kategorie),
    (q) => passt(q),
    () => true, // Not-Ausstieg: lieber Format-fremd als gar keine Frage
  ];
  for (const filter of stufen) {
    const treffer = kandidaten(filter);
    if (treffer.length > 0) {
      const frage = treffer[rng.int(treffer.length)];
      return { frage, ultrahard: frage.difficulty === "ultrahard" };
    }
  }

  // Recycle: Pool erschöpft — Frage klonen (eindeutige Id für Antwort-Locks).
  const recyclePool = pool.filter(passt).length > 0 ? pool.filter(passt) : pool;
  const basis = recyclePool[rng.int(Math.max(1, recyclePool.length))] ?? notfallFrage();
  const klon: Question = { ...basis, id: `${basis.id}~${state.fragenZaehler + 1}` };
  return { frage: klon, ultrahard: klon.difficulty === "ultrahard" };
}

/** Ersatzfrage gleicher Stufe/Kategorie (Roter Buzzer, J7, Maßanzug). */
export function waehleErsatzFrage(
  state: EngineState,
  rng: Rng,
  opts: { schwierigkeit: Schwierigkeit; ausserKategorie?: string; ausserId?: string },
): Question | null {
  const used = new Set(state.usedQuestionIds);
  // Ersatz ersetzt die Frage im LAUFENDEN Format — gleiche Format-Zuordnung.
  const minigameId = state.plan?.abschnitte[state.abschnittIndex]?.minigameId ?? FALLBACK_MINIGAME;
  const kandidaten = state.fragenPool.filter(
    (q) =>
      !used.has(q.id) &&
      q.id !== opts.ausserId &&
      passtFrageZuFormat(q, minigameId) &&
      q.difficulty === opts.schwierigkeit &&
      (opts.ausserKategorie === undefined || q.category !== opts.ausserKategorie),
  );
  if (kandidaten.length === 0) {
    const locker = state.fragenPool.filter(
      (q) => !used.has(q.id) && q.id !== opts.ausserId && passtFrageZuFormat(q, minigameId),
    );
    if (locker.length === 0) return null;
    return locker[rng.int(locker.length)];
  }
  return kandidaten[rng.int(kandidaten.length)];
}

/** Kategorien-Optionen für die Wahl-Phase (max. 3, aus dem ungenutzten Pool). */
export function kategorieOptionen(state: EngineState, abschnitt: Abschnitt, rng: Rng): string[] {
  const used = new Set(state.usedQuestionIds);
  const passend = state.fragenPool.filter(
    (q) =>
      !used.has(q.id) &&
      passtFrageZuFormat(q, abschnitt.minigameId) &&
      abschnitt.schwierigkeiten.includes(q.difficulty),
  );
  const quelle = passend.length > 0 ? passend : state.fragenPool;
  const kategorien = [...new Set(quelle.map((q) => q.category))];
  // Deterministisch mischen, dann bis zu 3 anbieten.
  for (let i = kategorien.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [kategorien[i], kategorien[j]] = [kategorien[j], kategorien[i]];
  }
  return kategorien.slice(0, 3);
}

/** Fragen-Regal (GM-Werkzeug 3): die nächsten Kandidaten nach Filter. */
export function regalKandidaten(state: EngineState, max = 5): Question[] {
  const used = new Set(state.usedQuestionIds);
  const { kategorie, schwierigkeit } = state.regalFilter;
  return state.fragenPool
    .filter(
      (q) =>
        !used.has(q.id) &&
        (kategorie === null || q.category === kategorie) &&
        (schwierigkeit === null || q.difficulty === schwierigkeit),
    )
    .slice(0, max);
}

function notfallFrage(): Question {
  return {
    id: "q_notfall",
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: "Wie heißt diese Show?",
    options: ["MONKEY MONEY", "AFFEN AG", "BANANA BANK", "KOKOS KASINO"],
    answer: 0,
    erklaerung: "Steht drauf.",
  };
}
