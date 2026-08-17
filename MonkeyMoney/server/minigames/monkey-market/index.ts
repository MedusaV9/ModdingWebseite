// „Monkey Market" (GAME-DESIGN §2.12/2, v2): Handels-Runde im GELD-Slot.
// DESIGN-KERN: 10 Markt-Chips der Bank (Chip-Wert = W/10) werden im
// 20-s-Handels-Fenster auf die 4 Antwort-FALLTÜREN verteilt — Chip für Chip
// (`chip`/`zurueck`, Umschichten erlaubt) oder als „ALLES AUF EINS" über den
// generischen answer/choice-Draht. Öffnet die richtige Tür: jeder Chip dort
// zahlt ×2 Chip-Wert; falsche + unplatzierte Chips verfallen (Bank-Chips —
// kein eigener Verlust). MUT-BONUS: alle 10 Chips auf EINER Tür und richtig
// ⇒ +25 % (mmAuszahlung, 10er-Rundung). Der Markt schließt früher, sobald
// ALLE Verbundenen voll platziert sind (dann ist nichts mehr zu handeln).
// Kein Streak/Speed — Hedging ist keine Richtig/Falsch-Antwort; outcomes:
// „richtig" = strikte Mehrheit der platzierten Chips lag auf der richtigen
// Tür (Awards/Auto-GM), null = nie gehandelt.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  MM_HANDEL_MS,
  MM_MARKT_CHIPS,
  mmAuszahlung,
  mmChipWert,
  MONKEY_MARKET_META,
  type MonkeyMarketAction,
} from "../../../shared/minigames/monkey-market.meta";
import { FRAGE_WERTE } from "../../../shared/money";
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

export interface MonkeyMarketState {
  question: Question;
  players: PlayerId[];
  startedAt: number;
  endetAt: number;
  timerMs: number;
  chipWert: number;
  /** Chips pro Spieler und Tür: chips[p] = [t0, t1, t2, t3]. */
  chips: Record<string, [number, number, number, number]>;
  /** Server-Zeit des LETZTEN eigenen Chip-Zugs (outcomes.nachMs). */
  letzterZug: Record<string, number>;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<MonkeyMarketAction> | GmAction | JokerAction;

function platziert(state: MonkeyMarketState, p: string): number {
  const c = state.chips[p] ?? [0, 0, 0, 0];
  return c[0] + c[1] + c[2] + c[3];
}

function verbundene(state: MonkeyMarketState): PlayerId[] {
  return state.players.filter((p) => state.connected[p]);
}

function alleVollPlatziert(state: MonkeyMarketState): boolean {
  const online = verbundene(state);
  return online.length > 0 && online.every((p) => platziert(state, p) >= MM_MARKT_CHIPS);
}

function mitChips(
  state: MonkeyMarketState,
  p: string,
  chips: [number, number, number, number],
  atServerTime: number,
): MonkeyMarketState {
  return {
    ...state,
    chips: { ...state.chips, [p]: chips },
    letzterZug: { ...state.letzterZug, [p]: atServerTime },
  };
}

function berechneScores(state: MonkeyMarketState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const c = state.chips[p] ?? [0, 0, 0, 0];
    const gesamt = c[0] + c[1] + c[2] + c[3];
    const richtig = c[state.question.answer] ?? 0;
    const alleAufEiner = gesamt === MM_MARKT_CHIPS && richtig === MM_MARKT_CHIPS;
    result[p] = mmAuszahlung(richtig, state.chipWert, alleAufEiner);
  }
  return result;
}

export const monkeyMarketPlugin: MinigamePlugin<MonkeyMarketState, MonkeyMarketAction> = {
  meta: MONKEY_MARKET_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): MonkeyMarketState {
    const question = content.questions[0];
    if (!question) throw new Error("monkey-market: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    const timerMs = Math.round(MM_HANDEL_MS * (content.mods?.timerFaktor ?? 1));
    return {
      question,
      players,
      startedAt: now,
      endetAt: now + timerMs,
      timerMs,
      chipWert: mmChipWert(FRAGE_WERTE[question.difficulty]),
      chips: {},
      letzterZug: {},
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: MonkeyMarketState, action: Action, _ctx: Ctx): MonkeyMarketState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // timer.extend + timer.shift: die eine Handels-Deadline wandert;
      // shift nimmt zusätzlich den Start-Anker mit (Pause/Resume).
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        endetAt: state.endetAt + action.ms,
      };
    }
    if (action.kind === "joker") return state; // Info-Joker passen nicht zum Hedging

    if (state.finished) return state;
    if (action.atServerTime > state.endetAt + SPAETANTWORT_GNADE_MS) return state;
    const p = action.playerId;
    const chips: [number, number, number, number] = [...(state.chips[p] ?? [0, 0, 0, 0])];
    const frei = MM_MARKT_CHIPS - (chips[0] + chips[1] + chips[2] + chips[3]);

    if (action.action.type === "chip") {
      if (frei <= 0) return state;
      chips[action.action.tuer] += 1;
      return mitChips(state, p, chips, action.atServerTime);
    }
    if (action.action.type === "zurueck") {
      if (chips[action.action.tuer] <= 0) return state;
      chips[action.action.tuer] -= 1;
      return mitChips(state, p, chips, action.atServerTime);
    }
    // „ALLES AUF EINS": alle Rest-Chips auf die gewählte Tür.
    if (action.action.type === "answer") {
      if (frei <= 0) return state;
      chips[action.action.choice] += frei;
      return mitChips(state, p, chips, action.atServerTime);
    }
    return state;
  },

  tick(state: MonkeyMarketState, ctx: Ctx): MonkeyMarketState {
    if (state.finished) return state;
    if (ctx.clock.now() >= state.endetAt || alleVollPlatziert(state)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: MonkeyMarketState, p: PlayerId, _ctx: Ctx): MonkeyMarketState {
    // Platzierte Chips bleiben liegen und werden normal abgerechnet.
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: MonkeyMarketState, p: PlayerId, _ctx: Ctx): MonkeyMarketState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: MonkeyMarketState, role: Role, player?: PlayerId): unknown {
    const q = state.question;
    // Türen-Summen sind PUBLIC (Markt-Getümmel auf dem Screen) — wer wohin
    // gelegt hat, bleibt bis zur Auflösung privat (kein Abschreiben).
    const tuerSummen: [number, number, number, number] = [0, 0, 0, 0];
    for (const p of state.players) {
      const c = state.chips[p] ?? [0, 0, 0, 0];
      for (let i = 0; i < 4; i++) tuerSummen[i] += c[i];
    }
    const basis = {
      questionId: q.id,
      text: q.text,
      options: q.options,
      endsAt: state.endetAt,
      timerMs: state.timerMs,
      chipWert: state.chipWert,
      chipsProSpieler: MM_MARKT_CHIPS,
      tuerSummen,
      fertigCount: state.players.filter((p) => platziert(state, p) >= MM_MARKT_CHIPS).length,
      spielerZahl: state.players.length,
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          correctIndex: q.answer,
          erklaerung: q.erklaerung,
          perPlayer: state.players.map((p) => {
            const c = state.chips[p] ?? [0, 0, 0, 0];
            const gesamt = c[0] + c[1] + c[2] + c[3];
            const richtig = c[q.answer] ?? 0;
            return {
              playerId: p,
              choice: null,
              correct: gesamt > 0 && richtig * 2 > gesamt,
              delta: scores[p] ?? 0,
              chips: c,
              mutBonus: gesamt === MM_MARKT_CHIPS && richtig === MM_MARKT_CHIPS,
            };
          }),
        }
      : null;

    if (role === "gm") {
      return { ...basis, correctIndex: q.answer, chips: state.chips, aufloesung };
    }
    if (role === "player") {
      const eigene = player !== undefined ? (state.chips[player] ?? [0, 0, 0, 0]) : [0, 0, 0, 0];
      const gesamt = eigene[0] + eigene[1] + eigene[2] + eigene[3];
      return {
        ...basis,
        yourChips: eigene,
        chipsFrei: MM_MARKT_CHIPS - gesamt,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: MonkeyMarketState): boolean {
    return state.finished;
  },

  scores(state: MonkeyMarketState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Awards/Auto-GM: „richtig" = strikte Chip-Mehrheit auf der richtigen Tür. */
  outcomes(state: MonkeyMarketState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const c = state.chips[p] ?? [0, 0, 0, 0];
      const gesamt = c[0] + c[1] + c[2] + c[3];
      if (gesamt === 0) {
        result[p] = { correct: null };
        continue;
      }
      result[p] = {
        correct: (c[state.question.answer] ?? 0) * 2 > gesamt,
        nachMs: Math.max(0, (state.letzterZug[p] ?? state.startedAt) - state.startedAt),
      };
    }
    return result;
  },
};
