// „Bananen-Börse" (GAME-DESIGN §2.12/4, v2): Live-Investieren im GELD-Slot.
// DESIGN-KERN: Frage + 4 Optionen liegen offen, gehandelt wird 20 s in VIER
// 5-s-KURS-BLÖCKEN. KAUFEN legt den festen Einsatz E = W/2 auf EINE Option
// und friert die Block-Quote ein: quote = max(1,2, 3,0 − 1,5 × Halter/Spieler)
// — Herdenverhalten drückt den Kurs. Der Block-Kurs wird beim ERSTEN Ereignis
// im Block eingefroren (Engine-tick läuft alle 250 ms ⇒ der Snapshot sitzt
// praktisch am Block-Anfang); die Snapshot-Historie ist das Chart-Futter.
// KAUFEN/HALTEN/VERKAUFEN: VERKAUFEN schließt die Position (Spread −25 % von
// E an die Bank, max. 1×), danach ist 1 Neukauf zur dann aktuellen Quote
// erlaubt. Abrechnung am Börsenschluss: richtige Position
// +rundeAuf10(E × (quote − 1)), falsche −E, jeder Verkauf −rundeAuf10(E×0,25),
// nie gehandelt 0. Disconnect: offene Position bleibt liegen (kein
// Auto-Verkauf) und wird normal abgerechnet. Voller Timer — Verkaufen ist bis
// zum Schluss eine Option, deshalb KEIN Early-Finish. Keine Streak/Speed.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  BANANEN_BOERSE_META,
  BOERSE_BLOECKE,
  BOERSE_HANDEL_MS,
  BOERSE_MAX_VERKAEUFE,
  BOERSE_QUOTE_START,
  boerseEinsatz,
  boerseGewinn,
  boerseQuote,
  boerseSpreadVerlust,
  type BananenBoerseAction,
} from "../../../shared/minigames/bananen-boerse.meta";
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

export interface BoersePosition {
  option: number;
  /** Beim Kauf eingefrorene Block-Quote (Abrechnungs-Basis). */
  quote: number;
  block: number;
  kaufNachMs: number;
}

export interface BananenBoerseState {
  question: Question;
  players: PlayerId[];
  startedAt: number;
  endetAt: number;
  timerMs: number;
  blockMs: number;
  einsatz: number;
  /** Eingefrorene Block-Kurse: kursBloecke[block][option] (wächst pro Block). */
  kursBloecke: number[][];
  positionen: Record<string, BoersePosition | null>;
  verkaeufe: Record<string, number>;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<BananenBoerseAction> | GmAction | JokerAction;

/** Aktueller Block-Index (0-basiert, gekappt auf den letzten Block). */
function blockIndex(state: BananenBoerseState, now: number): number {
  return Math.max(
    0,
    Math.min(BOERSE_BLOECKE - 1, Math.floor((now - state.startedAt) / state.blockMs)),
  );
}

/** Halter-Zahl pro Option (offene Positionen JETZT — die Herden-Basis). */
function halterProOption(state: BananenBoerseState): [number, number, number, number] {
  const halter: [number, number, number, number] = [0, 0, 0, 0];
  for (const p of state.players) {
    const pos = state.positionen[p];
    if (pos) halter[pos.option] += 1;
  }
  return halter;
}

/** Kurs-Snapshots bis einschließlich `bisBlock` einfrieren (idempotent). */
function mitSnapshots(state: BananenBoerseState, bisBlock: number): BananenBoerseState {
  if (state.kursBloecke.length > bisBlock) return state;
  const kursBloecke = [...state.kursBloecke];
  const halter = halterProOption(state);
  while (kursBloecke.length <= bisBlock) {
    kursBloecke.push(halter.map((h) => boerseQuote(h, state.players.length)));
  }
  return { ...state, kursBloecke };
}

function berechneScores(state: BananenBoerseState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    let delta = -(state.verkaeufe[p] ?? 0) * boerseSpreadVerlust(state.einsatz);
    const pos = state.positionen[p];
    if (pos) {
      delta +=
        pos.option === state.question.answer
          ? boerseGewinn(state.einsatz, pos.quote)
          : -state.einsatz;
    }
    // normalisiert IEEE-754 −0 (entsteht bei 0 Verkäufen ohne Position)
    result[p] = delta === 0 ? 0 : delta;
  }
  return result;
}

export const bananenBoersePlugin: MinigamePlugin<BananenBoerseState, BananenBoerseAction> = {
  meta: BANANEN_BOERSE_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): BananenBoerseState {
    const question = content.questions[0];
    if (!question) throw new Error("bananen-boerse: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    const timerMs = Math.round(BOERSE_HANDEL_MS * (content.mods?.timerFaktor ?? 1));
    return {
      question,
      players,
      startedAt: now,
      endetAt: now + timerMs,
      timerMs,
      blockMs: Math.round(timerMs / BOERSE_BLOECKE),
      einsatz: boerseEinsatz(FRAGE_WERTE[question.difficulty]),
      // Block 0: niemand hält etwas ⇒ alle Optionen zur Start-Quote 3,0.
      kursBloecke: [[...Array(4)].map(() => BOERSE_QUOTE_START)],
      positionen: {},
      verkaeufe: {},
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: BananenBoerseState, action: Action, _ctx: Ctx): BananenBoerseState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // extend/shift: Börsenschluss wandert; shift nimmt den Start-Anker mit
      // (Blöcke rechnen ab startedAt — die Pause verschiebt beide konsistent).
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        endetAt: state.endetAt + action.ms,
      };
    }
    if (action.kind === "joker") return state; // Info-Joker passen nicht zum Parkett

    if (state.finished) return state;
    if (action.atServerTime >= state.endetAt) return state; // Börsenschluss ist hart
    const p = action.playerId;
    const block = blockIndex(state, action.atServerTime);
    let s = mitSnapshots(state, block);

    // ---------- KAUFEN (answer/choice-Draht): Einsatz zur Block-Quote ----------
    if (action.action.type === "answer") {
      // Erst verkaufen, dann umschichten — die Verkaufs-Kappe (1×) begrenzt
      // die Runde damit auf maximal 2 Käufe.
      if (s.positionen[p]) return state;
      const option = action.action.choice;
      if (option < 0 || option > 3) return state;
      const quote = s.kursBloecke[block][option];
      s = {
        ...s,
        positionen: {
          ...s.positionen,
          [p]: {
            option,
            quote,
            block,
            kaufNachMs: Math.max(0, action.atServerTime - s.startedAt),
          },
        },
      };
      return s;
    }

    // ---------- VERKAUFEN: Position schließen (Spread), max. 1× ----------
    if (action.action.type === "verkaufen") {
      if (!s.positionen[p]) return state;
      if ((s.verkaeufe[p] ?? 0) >= BOERSE_MAX_VERKAEUFE) return state;
      return {
        ...s,
        positionen: { ...s.positionen, [p]: null },
        verkaeufe: { ...s.verkaeufe, [p]: (s.verkaeufe[p] ?? 0) + 1 },
      };
    }
    return state;
  },

  tick(state: BananenBoerseState, ctx: Ctx): BananenBoerseState {
    if (state.finished) return state;
    const now = ctx.clock.now();
    if (now >= state.endetAt) {
      // Schluss-Snapshot fürs Chart, dann Abrechnung.
      return { ...mitSnapshots(state, BOERSE_BLOECKE - 1), finished: true };
    }
    return mitSnapshots(state, blockIndex(state, now));
  },

  onDisconnect(state: BananenBoerseState, p: PlayerId, _ctx: Ctx): BananenBoerseState {
    // Design-Entscheidung: KEIN Auto-Verkauf — die Position bleibt im Markt.
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: BananenBoerseState, p: PlayerId, _ctx: Ctx): BananenBoerseState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: BananenBoerseState, role: Role, player?: PlayerId): unknown {
    const q = state.question;
    const halter = halterProOption(state);
    const aktuellerBlock = state.kursBloecke.length - 1;
    // Positionen sind PUBLIC — das Herdenverhalten IST die Mechanik.
    const positionen = Object.fromEntries(
      state.players
        .filter((p) => state.positionen[p])
        .map((p) => {
          const pos = state.positionen[p]!;
          return [p, { option: pos.option, quote: pos.quote }];
        }),
    );
    const basis = {
      questionId: q.id,
      text: q.text,
      options: q.options,
      endsAt: state.endetAt,
      timerMs: state.timerMs,
      blockMs: state.blockMs,
      bloeckeTotal: BOERSE_BLOECKE,
      aktuellerBlock,
      einsatz: state.einsatz,
      kursBloecke: state.kursBloecke,
      halter,
      positionen,
      // Auto-GM-Konvention: answeredCount = Spieler mit offener Position.
      answeredCount: Object.values(state.positionen).filter((pos) => pos).length,
      spielerZahl: state.players.length,
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          correctIndex: q.answer,
          erklaerung: q.erklaerung,
          perPlayer: state.players.map((p) => {
            const pos = state.positionen[p];
            return {
              playerId: p,
              choice: pos?.option ?? null,
              correct: pos !== null && pos !== undefined && pos.option === q.answer,
              delta: scores[p] ?? 0,
              quote: pos?.quote ?? null,
              verkaeufe: state.verkaeufe[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      return { ...basis, correctIndex: q.answer, aufloesung };
    }
    if (role === "player") {
      const pos = player !== undefined ? state.positionen[player] : undefined;
      return {
        ...basis,
        yourPosition: pos ? { option: pos.option, quote: pos.quote, block: pos.block } : null,
        yourVerkaeufe: player !== undefined ? (state.verkaeufe[player] ?? 0) : 0,
        kannVerkaufen:
          pos !== null &&
          pos !== undefined &&
          player !== undefined &&
          (state.verkaeufe[player] ?? 0) < BOERSE_MAX_VERKAEUFE,
        // options nur ohne offene Position (Kauf-Fenster) — generischer Draht.
        options: pos ? null : q.options,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: BananenBoerseState): boolean {
    return state.finished;
  },

  scores(state: BananenBoerseState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  outcomes(state: BananenBoerseState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const pos = state.positionen[p];
      if (!pos) {
        result[p] = { correct: null }; // nie gehandelt / glattgestellt
        continue;
      }
      result[p] = { correct: pos.option === state.question.answer, nachMs: pos.kaufNachMs };
    }
    return result;
  },
};
