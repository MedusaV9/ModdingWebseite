// Minigame „Stopp die Kokosnuss-Uhr" (GAME-DESIGN §2.2): Über der Frage schrumpft
// ein MM-Sack in 50-MM-Ticks auf 0. Antworten friert DEN EIGENEN Sack ein —
// richtig = eingefrorener Betrag, falsch = 0. Ersetzt den Speed-Bonus komplett.
// Edge-Cases: Spätantwort = Tick der Server-Empfangszeit (+400 ms Gnade), Antwort-
// Lock, Disconnect = AFK ohne Strafe (blockiert das Rundenende nicht).
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import { FRAGE_TIMER_MS } from "../../../shared/money";
import {
  KOKOSNUSS_UHR_META,
  SACK_STARTWERTE,
  sackTickIntervallMs,
  sackWertBei,
  type KokosnussUhrAction,
} from "../../../shared/minigames/kokosnuss-uhr.meta";
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

export interface KokosnussUhrState {
  question: Question;
  players: PlayerId[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  sackStart: number;
  tickIntervallMs: number;
  /** Aktueller Sack-Wert für die Views — tick() hält ihn auf Tick-Stufen aktuell. */
  sackWert: number;
  /** Antwort-Lock: pro Spieler zählt nur die ERSTE Antwort; eingefroren = Sack-Tick. */
  answers: Record<string, { choice: number; nachMs: number; eingefroren: number }>;
  /** AFK-Affen (Disconnect): blockieren das „alle haben geantwortet"-Ende nicht. */
  offline: Record<string, true>;
  /** Maßanzug/Portfolio: eigene Frage pro Spieler (sonst state.question). */
  fragenProSpieler: Record<string, Question>;
  finished: boolean;
}

type Action = PlayerAction<KokosnussUhrAction> | GmAction | JokerAction;

function frageVon(state: KokosnussUhrState, p: string): Question {
  return state.fragenProSpieler[p] ?? state.question;
}

function alleEingefroren(state: KokosnussUhrState): boolean {
  return state.players.every((p) => state.answers[p] !== undefined || state.offline[p]);
}

/** Richtig = eingefrorener Sack-Betrag, falsch/keine Antwort = 0 (§2.2). */
function berechneScores(state: KokosnussUhrState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const a = state.answers[p];
    result[p] = a !== undefined && a.choice === frageVon(state, p).answer ? a.eingefroren : 0;
  }
  return result;
}

export const kokosnussUhrPlugin: MinigamePlugin<KokosnussUhrState, KokosnussUhrAction> = {
  meta: KOKOSNUSS_UHR_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): KokosnussUhrState {
    const question = content.questions[0];
    if (!question) throw new Error("kokosnuss-uhr: ContentSlice ohne Frage");
    const timerMs = FRAGE_TIMER_MS[question.difficulty];
    const sackStart = SACK_STARTWERTE[question.difficulty];
    const now = ctx.clock.now();
    return {
      question,
      players,
      startedAt: now,
      endsAt: now + timerMs,
      timerMs,
      sackStart,
      tickIntervallMs: sackTickIntervallMs(sackStart, timerMs),
      sackWert: sackStart,
      answers: {},
      offline: {},
      fragenProSpieler: content.mods?.fragenProSpieler ?? {},
      finished: false,
    };
  },

  reduce(state: KokosnussUhrState, action: Action, _ctx: Ctx): KokosnussUhrState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      if (action.type === "timer.shift") {
        // Pause: ALLE Zeitanker verschieben — der Sack friert über die Pause ein.
        return {
          ...state,
          startedAt: state.startedAt + action.ms,
          endsAt: state.endsAt + action.ms,
        };
      }
      // timer.extend („+15 s"): mehr Antwortzeit, aber der Sack tickt weiter zur 0
      // (der Zeitdruck steckt im Format, §3.1) — nur die Deadline wandert.
      return { ...state, endsAt: state.endsAt + action.ms };
    }
    // Joker-Hooks sind nicht deklariert (meta.jokerAktionen fehlt) ⇒ no-op.
    if (action.kind !== "player") return state;
    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    const choice = action.action.choice;
    if (typeof choice !== "number" || !Number.isInteger(choice) || choice < 0 || choice > 3) {
      return state;
    }
    // Antwort-Lock: erste Antwort zählt, kein Umentscheiden.
    if (state.answers[action.playerId] !== undefined) return state;
    // Spätantwort: Server-Empfangszeit zählt, +400 ms Gnade, danach verworfen.
    if (action.atServerTime > state.endsAt + SPAETANTWORT_GNADE_MS) return state;
    const nachMs = Math.max(0, action.atServerTime - state.startedAt);
    // Der Tick der SERVER-Empfangszeit friert ein (Latenz-fair per Design, §2.2).
    const eingefroren = sackWertBei(state.sackStart, state.tickIntervallMs, nachMs);
    return {
      ...state,
      answers: { ...state.answers, [action.playerId]: { choice, nachMs, eingefroren } },
    };
  },

  tick(state: KokosnussUhrState, ctx: Ctx): KokosnussUhrState {
    if (state.finished) return state;
    const now = ctx.clock.now();
    if (now >= state.endsAt || alleEingefroren(state)) {
      return { ...state, finished: true };
    }
    const sackWert = sackWertBei(state.sackStart, state.tickIntervallMs, now - state.startedAt);
    return sackWert === state.sackWert ? state : { ...state, sackWert };
  },

  onDisconnect(state: KokosnussUhrState, p: PlayerId, _ctx: Ctx): KokosnussUhrState {
    // AFK-Affe: keine Strafe, letzter Stand zählt — aber die Runde wartet nicht auf ihn.
    return { ...state, offline: { ...state.offline, [p]: true } };
  },

  onReconnect(state: KokosnussUhrState, p: PlayerId, _ctx: Ctx): KokosnussUhrState {
    if (!state.offline[p]) return state;
    const offline = { ...state.offline };
    delete offline[p];
    return { ...state, offline };
  },

  viewFor(state: KokosnussUhrState, role: Role, player?: PlayerId): unknown {
    // Maßanzug: der Spieler sieht SEINE Frage — Screen/GM zeigen die Basis-Frage.
    const frage =
      role === "player" && player !== undefined ? frageVon(state, player) : state.question;
    const basis = {
      questionId: frage.id,
      text: frage.text,
      options: frage.options,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      sackStart: state.sackStart,
      sackWert: state.sackWert,
      tickIntervallMs: state.tickIntervallMs,
      answeredCount: Object.keys(state.answers).length,
      // Eis-Overlay auf dem Screen: WER eingefroren hat und bei WELCHEM Betrag ist
      // öffentlich — die Wahl selbst bleibt geheim bis zur Auflösung.
      eingefrorene: state.players
        .filter((p) => state.answers[p] !== undefined)
        .map((p) => ({ playerId: p, betrag: state.answers[p].eingefroren })),
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    // Auflösung (correctIndex + Wahlen) erst NACH finished — Leak-Schutz serverseitig.
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
              eingefroren: a?.eingefroren ?? 0,
              correct: a !== undefined && a.choice === frageVon(state, p).answer,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht die richtige Antwort IMMER.
      return { ...basis, correctIndex: state.question.answer, aufloesung };
    }
    if (role === "player") {
      const a = player ? state.answers[player] : undefined;
      return {
        ...basis,
        yourChoice: a?.choice ?? null,
        yourEingefroren: a?.eingefroren ?? null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: KokosnussUhrState): boolean {
    return state.finished;
  },

  scores(state: KokosnussUhrState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Streak-Wahrheit (§2.2 „Streak zählt normal"): richtig bleibt richtig, auch
   * wenn der Sack schon leer war (delta 0) — deshalb NICHT delta > 0 nehmen. */
  outcomes(state: KokosnussUhrState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const a = state.answers[p];
      result[p] = a
        ? { correct: a.choice === frageVon(state, p).answer, nachMs: a.nachMs }
        : { correct: null };
    }
    return result;
  },
};
