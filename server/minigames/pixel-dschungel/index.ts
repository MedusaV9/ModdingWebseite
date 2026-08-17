// Referenz-Minigame „Pixel-Dschungel" (GAME-DESIGN §2.5): Bild-Enthüllung mit
// Geld-Verfall. Das Bild wird in 8 Stufen à 3 s scharf, der Fragen-Jackpot
// VERFÄLLT pro Stufe — früh antworten = mehr Money + Risiko. Antwort jederzeit
// per MC-4; falsch = 0 + Sperre für den Rest der Frage (Design-Regel).
//
// Fairness OHNE Buzzer-Modul: Die Wertung ist latenztolerant per Design —
// gezählt wird die JACKPOT-STUFE zum Server-Empfangszeitpunkt (3-s-Fenster),
// gleiche Stufe = gleiche Punkte. Millisekunden entscheiden hier nie.
// TODO(Engine-Agent): Sobald das Buzzer-Modul (TECH-SPEC §3.3, Median-RTT +
// Clamp) existiert, kompensierte Timestamps statt roher Empfangszeit nutzen —
// die Stufen-Zuordnung (pdStufeZuZeit) bleibt dabei unverändert.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  PD_GESAMT_MS,
  PD_STUFEN,
  PIXEL_DSCHUNGEL_META,
  pdBildFuerFrage,
  pdJackpotWert,
  pdStufeZuZeit,
  type PixelDschungelAction,
} from "../../../shared/minigames/pixel-dschungel.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export interface PixelDschungelState {
  question: Question;
  players: PlayerId[];
  startedAt: number; // Anker der Stufen-Uhr (Enthüllung + Jackpot-Verfall)
  endsAt: number; // Antwort-Fenster: 24 s Enthüllung + 4 s voll scharf
  timerMs: number;
  /** Erste Antwort zählt — falsch ⇒ 0 MM + Sperre (dieselbe Sperre wie der Lock). */
  answers: Record<string, { choice: number; stufe: number; nachMs: number }>;
  finished: boolean;
}

type Action = PlayerAction<PixelDschungelAction> | GmAction;

function alleGesperrt(state: PixelDschungelState): boolean {
  return state.players.every((p) => state.answers[p] !== undefined);
}

/** MM = Jackpot-Stufe zum Server-Empfang der RICHTIGEN Antwort; falsch/keine = 0. */
function berechneScores(state: PixelDschungelState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const a = state.answers[p];
    result[p] =
      a !== undefined && a.choice === state.question.answer
        ? pdJackpotWert(state.question.difficulty, a.stufe)
        : 0;
  }
  return result;
}

export const pixelDschungelPlugin: MinigamePlugin<PixelDschungelState, PixelDschungelAction> = {
  meta: PIXEL_DSCHUNGEL_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): PixelDschungelState {
    const question = content.questions[0];
    if (!question) throw new Error("pixel-dschungel: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    return {
      question,
      players,
      startedAt: now,
      endsAt: now + PD_GESAMT_MS,
      timerMs: PD_GESAMT_MS,
      answers: {},
      finished: false,
    };
  },

  reduce(state: PixelDschungelState, action: Action, _ctx: Ctx): PixelDschungelState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      if (action.type === "timer.extend") {
        // GM „+15 s": nur das Antwort-Fenster wächst — die Stufen-Uhr läuft
        // weiter, der Jackpot bleibt danach auf der Minimal-Stufe (fair: mehr
        // Zeit gibt es nur zum kleinsten Preis).
        return { ...state, endsAt: state.endsAt + action.ms };
      }
      // timer.shift (Pause/Resume): ALLES verschieben — Enthüllung, Verfall
      // und Deadline frieren gemeinsam ein, sonst frisst die Pause den Jackpot.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        endsAt: state.endsAt + action.ms,
      };
    }
    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    // Sperre: erste Antwort zählt — richtig wie falsch, kein zweiter Versuch.
    if (state.answers[action.playerId] !== undefined) return state;
    // Spätantwort: Server-Empfang zählt, +400 ms Gnadenfenster, danach verworfen.
    if (action.atServerTime > state.endsAt + SPAETANTWORT_GNADE_MS) return state;
    const nachMs = Math.max(0, action.atServerTime - state.startedAt);
    return {
      ...state,
      answers: {
        ...state.answers,
        [action.playerId]: {
          choice: action.action.choice,
          stufe: pdStufeZuZeit(nachMs),
          nachMs,
        },
      },
    };
  },

  tick(state: PixelDschungelState, ctx: Ctx): PixelDschungelState {
    if (state.finished) return state;
    if (ctx.clock.now() >= state.endsAt || alleGesperrt(state)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: PixelDschungelState, _p: PlayerId, _ctx: Ctx): PixelDschungelState {
    return state; // Standard-AFK-Regel: letzter Stand zählt, keine Strafe
  },

  onReconnect(state: PixelDschungelState, _p: PlayerId, _ctx: Ctx): PixelDschungelState {
    return state;
  },

  viewFor(state: PixelDschungelState, role: Role, player?: PlayerId): unknown {
    // Stufen-Uhr rendert der CLIENT lokal aus startedAt + Server-Zeit-Offset —
    // hier gibt es keine Clock (pure), und der Server soll nicht takten.
    const basis = {
      questionId: state.question.id,
      text: state.question.text,
      options: state.question.options,
      bild: pdBildFuerFrage(state.question),
      schwierigkeit: state.question.difficulty,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      stufenTotal: PD_STUFEN,
      answeredCount: Object.keys(state.answers).length,
      // Wer geantwortet hat, „hält sich die Augen zu" (Screen-Inszenierung) —
      // ob richtig oder falsch bleibt bis zur Auflösung geheim (kein Leak).
      eingeloggt: state.players.filter((p) => state.answers[p] !== undefined),
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          correctIndex: state.question.answer,
          erklaerung: state.question.erklaerung,
          perPlayer: state.players.map((p) => {
            const a = state.answers[p];
            return {
              playerId: p,
              choice: a?.choice ?? null,
              stufe: a?.stufe ?? null,
              correct: a !== undefined && a.choice === state.question.answer,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      return { ...basis, correctIndex: state.question.answer, aufloesung };
    }
    if (role === "player") {
      const a = player ? state.answers[player] : undefined;
      return {
        ...basis,
        yourChoice: a?.choice ?? null,
        yourStufe: a?.stufe ?? null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: PixelDschungelState): boolean {
    return state.finished;
  },

  scores(state: PixelDschungelState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Streak-Kette („Streak normal", §2.5) + Pott-Vergabe brauchen richtig/falsch + Zeit. */
  outcomes(state: PixelDschungelState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const a = state.answers[p];
      result[p] =
        a === undefined
          ? { correct: null }
          : { correct: a.choice === state.question.answer, nachMs: a.nachMs };
    }
    return result;
  },
};
