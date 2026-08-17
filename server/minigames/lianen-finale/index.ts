// „Das große Lianen-Finale" (GAME-DESIGN §2.10 + §3.5): das Finale-Format, fix.
// Jeder Affe hängt an seiner Liane über dem Krokodil-Fluss; die Lianenlänge ist
// der live normierte Kontostand (Führender 100 %, Anzeige-Minimum 25 %,
// Snapshot via ctx.match beim init — pro Finalfrage frisch). MC-4, alle
// gleichzeitig, 12 s fix. Die BUCHUNG macht die Engine (bucheFinale: richtig
// +W_final, falsch −W_final/2, keine Antwort 0, Konto nie unter 0) — dieses
// Plugin liefert outcomes() und inszeniert; scores() spiegelt die Formel nur
// für Anzeige/Fallback. W_final kommt angesagt über ContentSlice.mods.wFinal.
// Kein Speed, keine Streak, keine Joker (meta ohne jokerAktionen — die Engine
// schickt gar keine Joker-Hooks). Finalist-Disconnect spielt 0-Antworten.
import type { ContentSlice, Question } from "../../../shared/content";
import { finaleDelta } from "../../../shared/economy";
import type { PlayerId } from "../../../shared/ids";
import {
  LF_ANZEIGE_MIN,
  LF_FALLBACK_W,
  LF_FRAGE_MS,
  lfLianenLaenge,
  LIANEN_FINALE_META,
  type LianenFinaleAction,
} from "../../../shared/minigames/lianen-finale.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export interface LianenFinaleState {
  question: Question;
  players: PlayerId[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  /** Der angesagte Fragenwert (§3.5) — Engine liefert ihn über mods.wFinal. */
  wFinal: number;
  /** Konto-Snapshot beim init: Basis der Lianen-Längen dieser Frage. */
  balances: Record<string, number>;
  answers: Record<string, { choice: number; nachMs: number }>;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<LianenFinaleAction> | GmAction;

/** §3.5-Deltas (Anzeige + korrektheit-Fallback — die Buchung macht die Engine). */
function berechneScores(state: LianenFinaleState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const a = state.answers[p];
    const korrekt = a === undefined ? null : a.choice === state.question.answer;
    result[p] = finaleDelta(korrekt, state.wFinal);
  }
  return result;
}

function fuehrenderStand(state: LianenFinaleState): number {
  return Math.max(0, ...state.players.map((p) => state.balances[p] ?? 0));
}

export const lianenFinalePlugin: MinigamePlugin<LianenFinaleState, LianenFinaleAction> = {
  meta: LIANEN_FINALE_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): LianenFinaleState {
    const question = content.questions[0];
    if (!question) throw new Error("lianen-finale: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    const balances: Record<string, number> = {};
    for (const p of players) balances[p] = ctx.match?.balance(p) ?? 0;
    return {
      question,
      players,
      startedAt: now,
      endsAt: now + LF_FRAGE_MS,
      timerMs: LF_FRAGE_MS,
      wFinal: content.mods?.wFinal ?? LF_FALLBACK_W,
      balances,
      answers: {},
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: LianenFinaleState, action: Action, _ctx: Ctx): LianenFinaleState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // timer.extend und timer.shift verschieben die Deadline (shift auch den Anker).
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        endsAt: state.endsAt + action.ms,
      };
    }
    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    // Antwort-Lock: erste Antwort zählt (Design: „Handy: nur 4 Buttons").
    if (state.answers[action.playerId] !== undefined) return state;
    // Spätantwort Standard: Server-Empfang + Gnadenfenster, danach verworfen.
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

  tick(state: LianenFinaleState, ctx: Ctx): LianenFinaleState {
    if (state.finished) return state;
    const online = state.players.filter((p) => state.connected[p]);
    const alleFertig = online.length > 0 && online.every((p) => state.answers[p] !== undefined);
    if (ctx.clock.now() >= state.endsAt || alleFertig) return { ...state, finished: true };
    return state;
  },

  onDisconnect(state: LianenFinaleState, p: PlayerId, _ctx: Ctx): LianenFinaleState {
    // §2.10: Finalist-Disconnect spielt 0-Antworten — kein Nachrücker, keine Strafe.
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: LianenFinaleState, p: PlayerId, _ctx: Ctx): LianenFinaleState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: LianenFinaleState, role: Role, player?: PlayerId): unknown {
    const q = state.question;
    const fuehrender = fuehrenderStand(state);
    // Lianen-Tableau: live normierte Längen (Führender 100 %, min. 25 %).
    const lianen = state.players.map((p) => ({
      playerId: p,
      laenge: lfLianenLaenge(state.balances[p] ?? 0, fuehrender),
      kontostand: state.balances[p] ?? 0,
      verbunden: state.connected[p] === true,
    }));
    const basis = {
      questionId: q.id,
      text: q.text,
      options: q.options,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      wFinal: state.wFinal,
      lianen,
      anzeigeMin: LF_ANZEIGE_MIN,
      answeredCount: Object.keys(state.answers).length,
      spielerZahl: state.players.length,
      finished: state.finished,
    };
    // Auflösung erst NACH finished — correctIndex bleibt bis dahin auf dem Server.
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          correctIndex: q.answer,
          erklaerung: q.erklaerung,
          perPlayer: state.players.map((p) => {
            const a = state.answers[p];
            const delta = scores[p] ?? 0;
            // Projizierter Stand nach der Engine-Buchung (Konto ≥ 0) — der
            // Screen animiert damit Ruck (hoch) bzw. Riss (runter) der Liane.
            const nachher = Math.max(0, (state.balances[p] ?? 0) + delta);
            return {
              playerId: p,
              choice: a?.choice ?? null,
              correct: a !== undefined && a.choice === q.answer,
              delta,
              lianeNachher: lfLianenLaenge(
                nachher,
                Math.max(
                  1,
                  ...state.players.map((x) =>
                    Math.max(0, (state.balances[x] ?? 0) + (scores[x] ?? 0)),
                  ),
                ),
              ),
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht die richtige Antwort IMMER.
      return { ...basis, correctIndex: q.answer, aufloesung };
    }
    if (role === "player") {
      const a = player !== undefined ? state.answers[player] : undefined;
      const eigene = lianen.find((l) => l.playerId === player);
      return {
        ...basis,
        yourChoice: a?.choice ?? null,
        // §2.10 Handy: „nur 4 Antwort-Buttons + eigene Restlänge".
        deineLiane: eigene?.laenge ?? 1,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: LianenFinaleState): boolean {
    return state.finished;
  },

  scores(state: LianenFinaleState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  outcomes(state: LianenFinaleState): Record<PlayerId, PlayerOutcome> {
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
