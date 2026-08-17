// „Bananen-Bluff" (GAME-DESIGN §2.12/3, v2): Lügen-Erkennung im KONFLIKT-Slot.
// DESIGN-KERN: pro Frage ist EIN Affe der VERKÜNDER (Rotation durch die
// Sitz-Reihenfolge, roundBased wie die Affenbank): nur er sieht die richtige
// Antwort und verkündet eine der 4 Optionen — Wahrheit oder Bluff (kreative
// wahr/falsch-Nutzung der choice4-Fragen). Alle anderen stimmen ab:
// WAHR (0) oder GELOGEN (1). Drei Beats pro Frage: VERKÜNDEN (12 s) →
// RATEN (12 s) → AUFDECKUNG (6 s Show-Moment).
// PAYOFFS (W2 = W/2, exakt — Nullsummen-Invariante siehe Tests):
//   · Rater richtig → +W2 aus der Bank.
//   · Rater fällt auf den Bluff rein → −W2 an den Verkünder (Transfer).
//   · Rater misstraut der Wahrheit → 0.
//   · Ehrlichkeits-Prämie: SELBST verkündete Wahrheit + strikte Mehrheit der
//     abgegebenen Stimmen glaubt → Verkünder +W2 aus der Bank.
// Timeout/Disconnect des Verkünders ⇒ AUTO-WAHRHEIT ohne Prämien-Anspruch.
// Kein Klau-Schutz (J6): Reinfallen ist eigene Leichtgläubigkeit, kein Klau.
// Keine Streak/Speed — die Auszahlung ist Psychologie-Mathe, kein ±W-Standard.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  BANANEN_BLUFF_META,
  BB_AUFDECKUNG_MS,
  BB_RATE_OPTIONEN,
  BB_RATEN_MS,
  BB_VERKUENDEN_MS,
  bbPraemie,
  type BananenBluffAction,
} from "../../../shared/minigames/bananen-bluff.meta";
import { FRAGE_WERTE } from "../../../shared/money";
import type {
  Ctx,
  GmAction,
  JokerAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

/** Öffentlicher Aufdeckungs-Eintrag (Screen-Ticker + Auflösung). */
export interface BbHistorieEintrag {
  questionId: string;
  verkuender: string;
  option: number;
  wahrheit: boolean;
  auto: boolean;
  reingefallen: string[];
  durchschaut: string[];
  glaeubige: string[];
  praemie: number;
  ehrlichkeitsPraemie: boolean;
}

export interface BananenBluffState {
  players: PlayerId[];
  questions: Question[];
  startedAt: number;
  frageIndex: number;
  phase: "verkuenden" | "raten" | "aufdeckung";
  phaseEndetAt: number;
  ratenStartetAt: number | null;
  timerFaktor: number;
  verkuender: string;
  ansage: { option: number; auto: boolean } | null;
  stimmen: Record<string, { wahl: 0 | 1; nachMs: number }>;
  /** Kumulierte Deltas der Runde (Transfers + Prämien) = scores(). */
  deltas: Record<string, number>;
  /** Summe aller Bank-Prämien (Invariante: Σ deltas === bankPraemien). */
  bankPraemien: number;
  /** Award-Zähler: korrekte Urteile/Bluff-Erfolge vs. Beteiligungen. */
  richtigZaehler: Record<string, number>;
  beteiligtZaehler: Record<string, number>;
  letzteStimme: Record<string, number>;
  historie: BbHistorieEintrag[];
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<BananenBluffAction> | GmAction | JokerAction;

function aktuelleFrage(state: BananenBluffState): Question {
  return state.questions[state.frageIndex % state.questions.length];
}

function rater(state: BananenBluffState): string[] {
  return state.players.filter((p) => p !== state.verkuender);
}

function verbundeneRater(state: BananenBluffState): string[] {
  return rater(state).filter((p) => state.connected[p]);
}

function fenster(state: BananenBluffState, basisMs: number): number {
  return Math.round(basisMs * state.timerFaktor);
}

/** VERKÜNDEN abschließen: Ansage einrasten (auto = Wahrheit ohne Prämie). */
function starteRaten(
  state: BananenBluffState,
  ansage: { option: number; auto: boolean },
  now: number,
): BananenBluffState {
  return {
    ...state,
    ansage,
    phase: "raten",
    ratenStartetAt: now,
    phaseEndetAt: now + fenster(state, BB_RATEN_MS),
    stimmen: {},
  };
}

/** RATEN abschließen: Payoffs EXAKT buchen + Aufdeckungs-Beat starten. */
function werteAus(state: BananenBluffState, now: number): BananenBluffState {
  const q = aktuelleFrage(state);
  const ansage = state.ansage ?? { option: q.answer, auto: true };
  const wahrheit = ansage.option === q.answer;
  const praemie = bbPraemie(FRAGE_WERTE[q.difficulty]);

  const deltas = { ...state.deltas };
  const richtigZaehler = { ...state.richtigZaehler };
  const beteiligtZaehler = { ...state.beteiligtZaehler };
  let bankPraemien = state.bankPraemien;
  const reingefallen: string[] = [];
  const durchschaut: string[] = [];
  const glaeubige: string[] = [];

  for (const p of rater(state)) {
    const stimme = state.stimmen[p];
    if (stimme === undefined) continue; // keine Stimme: kein Risiko, keine Prämie
    beteiligtZaehler[p] = (beteiligtZaehler[p] ?? 0) + 1;
    const korrekt = (stimme.wahl === 0) === wahrheit;
    if (korrekt) {
      deltas[p] = (deltas[p] ?? 0) + praemie;
      bankPraemien += praemie;
      richtigZaehler[p] = (richtigZaehler[p] ?? 0) + 1;
      (wahrheit ? glaeubige : durchschaut).push(p);
    } else if (!wahrheit) {
      // Auf die Lüge reingefallen: W2 wandert zum Verkünder (Nullsumme).
      deltas[p] = (deltas[p] ?? 0) - praemie;
      deltas[state.verkuender] = (deltas[state.verkuender] ?? 0) + praemie;
      reingefallen.push(p);
    }
    // wahrheit && wahl === GELOGEN: 0 — nur die Prämie ist futsch.
  }

  // Verkünder-Wertung (nur bei EIGENER Ansage): Bluff-Erfolg oder Ehrlichkeit.
  let ehrlichkeitsPraemie = false;
  if (!ansage.auto) {
    beteiligtZaehler[state.verkuender] = (beteiligtZaehler[state.verkuender] ?? 0) + 1;
    const abgegeben = Object.keys(state.stimmen).length;
    const wahrStimmen = Object.values(state.stimmen).filter((s) => s.wahl === 0).length;
    if (wahrheit && wahrStimmen * 2 > abgegeben) {
      deltas[state.verkuender] = (deltas[state.verkuender] ?? 0) + praemie;
      bankPraemien += praemie;
      ehrlichkeitsPraemie = true;
      richtigZaehler[state.verkuender] = (richtigZaehler[state.verkuender] ?? 0) + 1;
    } else if (!wahrheit && reingefallen.length > 0) {
      richtigZaehler[state.verkuender] = (richtigZaehler[state.verkuender] ?? 0) + 1;
    }
  }

  return {
    ...state,
    deltas,
    bankPraemien,
    richtigZaehler,
    beteiligtZaehler,
    phase: "aufdeckung",
    phaseEndetAt: now + BB_AUFDECKUNG_MS,
    historie: [
      ...state.historie,
      {
        questionId: q.id,
        verkuender: state.verkuender,
        option: ansage.option,
        wahrheit,
        auto: ansage.auto,
        reingefallen,
        durchschaut,
        glaeubige,
        praemie,
        ehrlichkeitsPraemie,
      },
    ],
  };
}

/** Nächste Frage (Verkünder-Rotation) oder Runden-Ende. */
function naechsteFrage(state: BananenBluffState, now: number): BananenBluffState {
  const frageIndex = state.frageIndex + 1;
  if (frageIndex >= state.questions.length) return { ...state, finished: true };
  const verkuender = state.players[frageIndex % state.players.length];
  const s: BananenBluffState = {
    ...state,
    frageIndex,
    verkuender,
    ansage: null,
    stimmen: {},
    phase: "verkuenden",
    phaseEndetAt: now + fenster(state, BB_VERKUENDEN_MS),
    ratenStartetAt: null,
  };
  // Verkünder offline: sofortige Auto-Wahrheit — die Show wartet nicht.
  if (!s.connected[verkuender]) {
    return starteRaten(s, { option: aktuelleFrage(s).answer, auto: true }, now);
  }
  return s;
}

export const bananenBluffPlugin: MinigamePlugin<BananenBluffState, BananenBluffAction> = {
  meta: BANANEN_BLUFF_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): BananenBluffState {
    if (content.questions.length === 0) throw new Error("bananen-bluff: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    const timerFaktor = content.mods?.timerFaktor ?? 1;
    return {
      players,
      questions: content.questions,
      startedAt: now,
      frageIndex: 0,
      phase: "verkuenden",
      phaseEndetAt: now + Math.round(BB_VERKUENDEN_MS * timerFaktor),
      ratenStartetAt: null,
      timerFaktor,
      verkuender: players[0],
      ansage: null,
      stimmen: {},
      deltas: {},
      bankPraemien: 0,
      richtigZaehler: {},
      beteiligtZaehler: {},
      letzteStimme: {},
      historie: [],
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: BananenBluffState, action: Action, ctx: Ctx): BananenBluffState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // extend: aktuelle Phase bekommt Luft; shift: alle Anker wandern.
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        phaseEndetAt: state.phaseEndetAt + action.ms,
        ratenStartetAt:
          action.type === "timer.shift" && state.ratenStartetAt !== null
            ? state.ratenStartetAt + action.ms
            : state.ratenStartetAt,
      };
    }
    if (action.kind === "joker") return state; // Info-Joker passen nicht zum Bluffen
    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    if (action.atServerTime > state.phaseEndetAt) return state;
    const p = action.playerId;

    // ---------- VERKÜNDEN: der Verkünder rastet seine Ansage ein ----------
    if (state.phase === "verkuenden") {
      if (p !== state.verkuender || state.ansage !== null) return state;
      const choice = action.action.choice;
      if (choice < 0 || choice > 3) return state;
      return starteRaten(state, { option: choice, auto: false }, action.atServerTime);
    }

    // ---------- RATEN: alle anderen stimmen WAHR (0) / GELOGEN (1) ----------
    if (state.phase === "raten") {
      if (p === state.verkuender) return state;
      if (state.stimmen[p] !== undefined) return state; // erste Stimme zählt
      const wahl = action.action.choice;
      if (wahl !== 0 && wahl !== 1) return state;
      const nachMs = Math.max(0, action.atServerTime - (state.ratenStartetAt ?? state.startedAt));
      void ctx;
      return {
        ...state,
        stimmen: { ...state.stimmen, [p]: { wahl, nachMs } },
        letzteStimme: { ...state.letzteStimme, [p]: nachMs },
      };
    }
    return state;
  },

  tick(state: BananenBluffState, ctx: Ctx): BananenBluffState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "verkuenden") {
      // Timeout ⇒ Auto-Wahrheit (ohne Prämien-Anspruch).
      if (now >= state.phaseEndetAt) {
        return starteRaten(state, { option: aktuelleFrage(state).answer, auto: true }, now);
      }
      return state;
    }
    if (state.phase === "raten") {
      const online = verbundeneRater(state);
      const alleAbgestimmt =
        online.length > 0 && online.every((p) => state.stimmen[p] !== undefined);
      if (now >= state.phaseEndetAt || alleAbgestimmt) return werteAus(state, now);
      return state;
    }
    // aufdeckung:
    if (now >= state.phaseEndetAt) return naechsteFrage(state, now);
    return state;
  },

  onDisconnect(state: BananenBluffState, p: PlayerId, ctx: Ctx): BananenBluffState {
    const s: BananenBluffState = { ...state, connected: { ...state.connected, [p]: false } };
    // Verkünder weg, Ansage offen ⇒ Auto-Wahrheit sofort (die Show läuft weiter).
    if (!s.finished && s.phase === "verkuenden" && p === s.verkuender && s.ansage === null) {
      return starteRaten(s, { option: aktuelleFrage(s).answer, auto: true }, ctx.clock.now());
    }
    return s;
  },

  onReconnect(state: BananenBluffState, p: PlayerId, _ctx: Ctx): BananenBluffState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: BananenBluffState, role: Role, player?: PlayerId): unknown {
    const q = aktuelleFrage(state);
    const duBistVerkuender = player !== undefined && player === state.verkuender;
    const praemie = bbPraemie(FRAGE_WERTE[q.difficulty]);
    const basis = {
      questionId: q.id,
      frageNr: state.frageIndex + 1,
      frageTotal: state.questions.length,
      phase: state.phase,
      verkuender: state.verkuender,
      text: q.text,
      endsAt: state.phaseEndetAt,
      timerMs:
        state.phase === "verkuenden"
          ? fenster(state, BB_VERKUENDEN_MS)
          : state.phase === "raten"
            ? fenster(state, BB_RATEN_MS)
            : BB_AUFDECKUNG_MS,
      praemie,
      // Verkündete Option ist AB dem Raten public — ob sie stimmt, nicht.
      ansageText:
        state.phase !== "verkuenden" && state.ansage ? q.options[state.ansage.option] : null,
      abgestimmt: Object.keys(state.stimmen).length,
      raterZahl: rater(state).length,
      spielerZahl: state.players.length,
      // Aufdeckung des AKTUELLEN Beats (nur in der Aufdeckungs-Phase).
      beat: state.phase === "aufdeckung" ? (state.historie.at(-1) ?? null) : null,
      historie: state.historie.slice(-4),
      deltas: state.deltas,
      finished: state.finished,
    };
    const aufloesung = state.finished
      ? {
          erklaerung: "Bluffs kassieren bei den Leichtgläubigen — Detektive bei der Bank.",
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: (state.deltas[p] ?? 0) > 0,
            delta: state.deltas[p] ?? 0,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: richtige Antwort + Ansage-Wahrheit IMMER sichtbar.
      return {
        ...basis,
        options: q.options,
        correctIndex: q.answer,
        ansage: state.ansage,
        stimmen: state.stimmen,
        aufloesung,
      };
    }
    if (role === "player") {
      if (duBistVerkuender) {
        return {
          ...basis,
          duBistVerkuender: true,
          // NUR der Verkünder sieht die Optionen + die markierte Wahrheit.
          options: state.phase === "verkuenden" && state.ansage === null ? q.options : null,
          correctIndex: state.phase === "verkuenden" && state.ansage === null ? q.answer : null,
          yourChoice: state.ansage?.option ?? null,
          aufloesung,
        };
      }
      return {
        ...basis,
        duBistVerkuender: false,
        // Rate-Fenster: die 2 Urteils-Buttons über den generischen options-Draht.
        options: state.phase === "raten" ? [...BB_RATE_OPTIONEN] : null,
        yourChoice: player !== undefined ? (state.stimmen[player]?.wahl ?? null) : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: BananenBluffState): boolean {
    return state.finished;
  },

  /** Runden-Summe aus Transfers + Prämien (roundBased: EINE Buchung am Ende). */
  scores(state: BananenBluffState): Record<PlayerId, number> {
    const result: Record<PlayerId, number> = {};
    for (const p of state.players) result[p] = state.deltas[p] ?? 0;
    return result;
  },

  /** Awards/Auto-GM: mehrheitlich richtige Urteile/Bluff-Erfolge = „richtig". */
  outcomes(state: BananenBluffState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const beteiligt = state.beteiligtZaehler[p] ?? 0;
      if (beteiligt === 0) {
        result[p] = { correct: null };
        continue;
      }
      result[p] = {
        correct: (state.richtigZaehler[p] ?? 0) * 2 > beteiligt,
        nachMs: state.letzteStimme[p],
      };
    }
    return result;
  },
};
