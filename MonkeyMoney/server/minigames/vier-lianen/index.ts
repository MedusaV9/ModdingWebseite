// Referenz-Minigame 1: „Vier Lianen" — klassische 4er-Choice-Frage, Simultan-Eingabe.
// Beweis-Implementierung für das MinigamePlugin-Interface (pure + serialisierbar).
// ENGINE-AUSBAU: Joker-Hooks (50:50 / removeOne / Zweitversuch), outcomes(),
// FrageMods (Timer-Faktor, Insider-Vorsprung, Geräte-Mischung, Frage pro Spieler).
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import { FRAGE_TIMER_MS, fragenGewinn } from "../../../shared/money";
import {
  VIER_LIANEN_META,
  type VierLianenAction,
} from "../../../shared/minigames/vier-lianen.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  JokerAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export interface VierLianenState {
  question: Question;
  players: PlayerId[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  /** Antwort-Lock: pro Spieler zählt nur die ERSTE Antwort (idempotent). */
  answers: Record<string, { choice: number; nachMs: number }>;
  finished: boolean;
  // ---------- Engine-Ausbau ----------
  /** Gesperrte Options-Indizes pro Spieler (Bananen-Split/Schmiergeld). */
  gesperrt: Record<string, number[]>;
  /** Global gesperrte Optionen (GM-Tipp-Kanone via removeOne für alle). */
  gesperrtGlobal: number[];
  /** Rückgaberecht eingelöst — Gewinn dieses Spielers nur noch 50 %. */
  zweitversuch: Record<string, true>;
  /** Maßanzug/Portfolio: eigene Frage pro Spieler (sonst state.question). */
  fragenProSpieler: Record<string, Question>;
  /** Insider-Tipp (Rad): dieser Spieler sieht die Frage `vorsprungMs` früher. */
  insiderId: string | null;
  insiderVorsprungMs: number;
  /** Affentheater (Rad): Handy-Optionen werden pro Gerät gemischt. */
  geraeteMischung: boolean;
}

type Action = PlayerAction<VierLianenAction> | GmAction | JokerAction;

function frageVon(state: VierLianenState, p: string): Question {
  return state.fragenProSpieler[p] ?? state.question;
}

function alleBeantwortet(state: VierLianenState): boolean {
  return state.players.every((p) => state.answers[p] !== undefined);
}

function gesperrtFuer(state: VierLianenState, p: string): number[] {
  return [...new Set([...(state.gesperrt[p] ?? []), ...state.gesperrtGlobal])];
}

/** Money-Vergabe: Grundwert + Speed-Bonus (§3.1); Zweitversuch nur 50 %. */
function berechneScores(state: VierLianenState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const a = state.answers[p];
    const frage = frageVon(state, p);
    const roh =
      a !== undefined && a.choice === frage.answer
        ? fragenGewinn(frage.difficulty, a.nachMs, state.timerMs)
        : 0;
    result[p] = state.zweitversuch[p] ? Math.round(roh / 2 / 10) * 10 : roh;
  }
  return result;
}

/** Falsche, noch offene Optionen eines Spielers (für 50:50/removeOne).
 * Indizes aus der FRAGE (wahr_falsch hat nur 2 Optionen, nicht 4). */
function falscheOffeneOptionen(state: VierLianenState, p: string): number[] {
  const frage = frageVon(state, p);
  const zu = new Set(gesperrtFuer(state, p));
  return frage.options.map((_, i) => i).filter((i) => i !== frage.answer && !zu.has(i));
}

export const vierLianenPlugin: MinigamePlugin<VierLianenState, VierLianenAction> = {
  meta: VIER_LIANEN_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): VierLianenState {
    const question = content.questions[0];
    if (!question) throw new Error("vier-lianen: ContentSlice ohne Frage");
    const mods = content.mods;
    const timerMs = Math.round(FRAGE_TIMER_MS[question.difficulty] * (mods?.timerFaktor ?? 1));
    const now = ctx.clock.now();
    return {
      question,
      players,
      startedAt: now,
      endsAt: now + timerMs,
      timerMs,
      answers: {},
      finished: false,
      gesperrt: {},
      gesperrtGlobal: [],
      zweitversuch: {},
      fragenProSpieler: mods?.fragenProSpieler ?? {},
      insiderId: mods?.insiderPlayerId ?? null,
      insiderVorsprungMs: mods?.insiderVorsprungMs ?? 0,
      geraeteMischung: mods?.geraeteMischung === true,
    };
  },

  reduce(state: VierLianenState, action: Action, ctx: Ctx): VierLianenState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // timer.extend und timer.shift verschieben beide die Deadline.
      return { ...state, endsAt: state.endsAt + action.ms };
    }

    if (action.kind === "joker") {
      if (state.finished) return state;
      // 50:50 — 2 falsche Optionen des Spielers abreißen (nur VOR der Antwort).
      if (action.type === "fiftyFifty") {
        const p = action.playerId;
        if (state.answers[p] !== undefined) return state;
        const offen = falscheOffeneOptionen(state, p);
        if (offen.length < 2) return state;
        const erste = offen.splice(ctx.rng.int(offen.length), 1)[0];
        const zweite = offen.splice(ctx.rng.int(offen.length), 1)[0];
        return {
          ...state,
          gesperrt: { ...state.gesperrt, [p]: [...(state.gesperrt[p] ?? []), erste, zweite] },
        };
      }
      // removeOne — 1 falsche Option sperren (playerId null ⇒ GLOBAL, GM-Hint).
      if (action.type === "removeOne") {
        if (action.playerId === null) {
          const zu = new Set(state.gesperrtGlobal);
          const offen = state.question.options
            .map((_, i) => i)
            .filter((i) => i !== state.question.answer && !zu.has(i));
          if (offen.length < 2) return state; // mind. 1 falsche bleibt stehen
          const wahl = offen[ctx.rng.int(offen.length)];
          return { ...state, gesperrtGlobal: [...state.gesperrtGlobal, wahl] };
        }
        const p = action.playerId;
        if (state.answers[p] !== undefined) return state;
        const offen = falscheOffeneOptionen(state, p);
        if (offen.length === 0) return state;
        const wahl = offen[ctx.rng.int(offen.length)];
        return {
          ...state,
          gesperrt: { ...state.gesperrt, [p]: [...(state.gesperrt[p] ?? []), wahl] },
        };
      }
      // secondTry — falsche Antwort löschen, Option sperren, Gewinn nur 50 %.
      if (action.type === "secondTry") {
        const p = action.playerId;
        const a = state.answers[p];
        if (a === undefined || state.zweitversuch[p]) return state;
        if (a.choice === frageVon(state, p).answer) return state; // richtig ⇒ kein Bedarf
        const answers = { ...state.answers };
        delete answers[p];
        return {
          ...state,
          answers,
          gesperrt: { ...state.gesperrt, [p]: [...(state.gesperrt[p] ?? []), a.choice] },
          zweitversuch: { ...state.zweitversuch, [p]: true },
        };
      }
      return state;
    }

    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    // Antwort-Lock: erste Antwort zählt, Umentscheiden gibt es nicht.
    if (state.answers[action.playerId] !== undefined) return state;
    // Nur echte Options-Indizes (wahr_falsch hat 2, choice4 hat 4 Optionen).
    const optionen = frageVon(state, action.playerId).options.length;
    if (action.action.choice < 0 || action.action.choice >= optionen) return state;
    // Gesperrte Optionen (50:50/Hint) sind nicht wählbar.
    if (gesperrtFuer(state, action.playerId).includes(action.action.choice)) return state;
    // Spätantwort: Server-Empfangszeit zählt, +400 ms Gnadenfenster, danach verworfen.
    if (action.atServerTime > state.endsAt + SPAETANTWORT_GNADE_MS) return state;
    const nachMs = Math.max(0, action.atServerTime - state.startedAt);
    return {
      ...state,
      answers: {
        ...state.answers,
        [action.playerId]: { choice: action.action.choice, nachMs },
      },
    };
  },

  tick(state: VierLianenState, ctx: Ctx): VierLianenState {
    if (state.finished) return state;
    if (ctx.clock.now() >= state.endsAt || alleBeantwortet(state)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: VierLianenState, _p: PlayerId, _ctx: Ctx): VierLianenState {
    return state; // AFK-Regel: letzter Stand zählt, keine Strafe (Standard)
  },

  onReconnect(state: VierLianenState, _p: PlayerId, _ctx: Ctx): VierLianenState {
    return state;
  },

  viewFor(state: VierLianenState, role: Role, player?: PlayerId): unknown {
    const frage = player !== undefined ? frageVon(state, player) : state.question;
    // Insider-Tipp: alle ANDEREN sehen die Frage erst `sichtbarAb` (Client blurred).
    const sichtbarAb =
      state.insiderId !== null && player !== state.insiderId
        ? state.startedAt + state.insiderVorsprungMs
        : state.startedAt;
    const basis = {
      questionId: frage.id,
      text: frage.text,
      options: frage.options,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      answeredCount: Object.keys(state.answers).length,
      finished: state.finished,
      sichtbarAb,
      geraeteMischung: state.geraeteMischung,
    };
    // Auflösung (correctIndex + Detail) erst NACH finished — Leak-Schutz serverseitig.
    const scores = state.finished ? berechneScores(state) : {};
    // Maßanzug: die Auflösung (correctIndex/Erklärung) folgt der ROLLEN-Frage.
    const aufloesung = state.finished
      ? {
          correctIndex: frage.answer,
          erklaerung: frage.erklaerung,
          perPlayer: state.players.map((p) => {
            const a = state.answers[p];
            return {
              playerId: p,
              choice: a?.choice ?? null,
              correct: a !== undefined && a.choice === frageVon(state, p).answer,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht die richtige Antwort IMMER.
      return {
        ...basis,
        correctIndex: state.question.answer,
        aufloesung,
        sichtbarAb: state.startedAt,
      };
    }
    if (role === "player") {
      const a = player ? state.answers[player] : undefined;
      return {
        ...basis,
        yourChoice: a?.choice ?? null,
        gesperrt: player !== undefined ? gesperrtFuer(state, player) : [],
        zweitversuch: player !== undefined && state.zweitversuch[player] === true,
        aufloesung,
      };
    }
    return { ...basis, gesperrt: state.gesperrtGlobal, aufloesung };
  },

  isFinished(state: VierLianenState): boolean {
    return state.finished;
  },

  scores(state: VierLianenState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  outcomes(state: VierLianenState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const a = state.answers[p];
      result[p] =
        a === undefined
          ? { correct: null }
          : {
              correct: a.choice === frageVon(state, p).answer,
              nachMs: a.nachMs,
              // Rückgaberecht genutzt → Jackpot-Buchung halbiert (§5.1: „Gewinn 50 %").
              ...(state.zweitversuch[p] ? { zweitversuch: true } : {}),
            };
    }
    return result;
  },
};
