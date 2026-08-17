// „Affen-Auktion" (GAME-DESIGN §2.12/5, v2): das exklusive Antwortrecht wird
// VERSTEIGERT — der Risiko-Handel im KONFLIKT-Slot.
// DESIGN-KERN: 20-s-Auktion im 25er-Raster, NUR Kategorie + Schwierigkeit als
// Teaser (geboten wird BLIND auf die Frage — das ist das Risiko!). Gebote in
// den letzten 5 s verlängern den Hammer um 5 s (Anti-Sniping, Kappe +20 s);
// der Höchstbietende kann sich nicht selbst überbieten. Danach beantwortet
// NUR der Gewinner die Frage (20 s, Info-Joker erlaubt):
//   · richtig → „Gebot ×2 zurück" = netto +Gebot aus der Bank
//     (Rückgaberecht-Zweitversuch: nur +rundeAuf10(Gebot/2)).
//   · falsch/Timeout → das Gebot wird AN ALLE ANDEREN VERTEILT: jeder erhält
//     aaVerteilAnteil (auf 10er ABgerundet), der Gewinner zahlt EXAKT die
//     Summe der Anteile — der Rundungs-Rest bleibt bei ihm (nullsummig).
// Persönliches Limit: max(100, min(1.000, Konto im 25er-Raster)) — Snapshot
// beim init (ctx.match), Pleite-Affen deckt die Dispo-Klammer (§3.2).
// Keine Gebote ⇒ Frage verfällt. Disconnect des Gewinners vor der Antwort ⇒
// Gebot erstattet (Präzedenz Alles-oder-Banane), Reconnect im Fenster hebt
// die Erstattung auf. Das Bieter-Fenster heißt „setzen" (Setz-Konvention).
import type { ContentSlice, Question } from "../../../shared/content";
import { asPlayerId, type PlayerId } from "../../../shared/ids";
import {
  AA_AUKTION_MAX_EXTRA_MS,
  AA_AUKTION_MS,
  AA_FRAGE_MS,
  AA_MAX_GEBOT,
  AA_SCHRITT,
  AFFEN_AUKTION_META,
  aaKlemmeGebot,
  aaMaxGebot,
  aaVerteilAnteil,
  type AffenAuktionAction,
} from "../../../shared/minigames/affen-auktion.meta";
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

export interface AaGebot {
  playerId: string;
  betrag: number;
  atMs: number;
}

export interface AffenAuktionState {
  question: Question;
  players: PlayerId[];
  startedAt: number;
  phase: "setzen" | "frage";
  auktionEndetAt: number;
  auktionMaxEndetAt: number;
  frageStartetAt: number | null;
  frageEndetAt: number | null;
  timerMs: number;
  hoechstgebot: number;
  hoechstbietender: string | null;
  gebotHistorie: AaGebot[];
  /** Persönliche Gebots-Limits (Konto-Snapshot beim init). */
  limits: Record<string, number>;
  answer: { choice: number; nachMs: number } | null;
  /** Vom fiftyFifty/removeOne gesperrte Optionen (nur der Gewinner antwortet). */
  gesperrt: number[];
  zweitversuch: boolean;
  /** Gewinner-Disconnect vor der Antwort: Gebot erstattet, Frage verfällt. */
  erstattet: boolean;
  uebersprungen: boolean;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<AffenAuktionAction> | GmAction | JokerAction;

/** Ohne match-API (isolierte Läufe): volles Limit als Fallback. */
const AA_FALLBACK_LIMIT = AA_MAX_GEBOT;

function falscheOffeneOptionen(state: AffenAuktionState): number[] {
  const zu = new Set(state.gesperrt);
  return [0, 1, 2, 3].filter((i) => i !== state.question.answer && !zu.has(i));
}

/** Gebot einrasten + Anti-Sniping-Verlängerung. */
function mitGebot(
  state: AffenAuktionState,
  p: string,
  betrag: number,
  at: number,
): AffenAuktionState {
  const verlaengertBis = Math.min(at + 5_000, state.auktionMaxEndetAt);
  return {
    ...state,
    hoechstgebot: betrag,
    hoechstbietender: p,
    gebotHistorie: [...state.gebotHistorie, { playerId: p, betrag, atMs: at - state.startedAt }],
    auktionEndetAt: Math.max(state.auktionEndetAt, verlaengertBis),
  };
}

function berechneScores(state: AffenAuktionState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  const gewinner = state.hoechstbietender === null ? null : asPlayerId(state.hoechstbietender);
  if (
    gewinner === null ||
    state.uebersprungen ||
    (state.erstattet && state.answer === null) // Disconnect-Erstattung
  ) {
    return result;
  }
  const gebot = state.hoechstgebot;
  if (state.answer !== null && state.answer.choice === state.question.answer) {
    // „Gebot ×2 zurück" = netto +Gebot; Zweitversuch: halber Gewinn (10er).
    result[gewinner] = state.zweitversuch ? Math.round(gebot / 2 / 10) * 10 : gebot;
    return result;
  }
  // Falsch ODER keine Antwort: das Gebot wandert an alle anderen (nullsummig).
  const andere = state.players.filter((p) => p !== gewinner);
  const anteil = aaVerteilAnteil(gebot, andere.length);
  for (const p of andere) result[p] = anteil;
  // `anteil === 0 ? 0 : …` normalisiert IEEE-754 −0 (Mini-Gebote < 30).
  result[gewinner] = anteil === 0 ? 0 : -anteil * andere.length;
  return result;
}

export const affenAuktionPlugin: MinigamePlugin<AffenAuktionState, AffenAuktionAction> = {
  meta: AFFEN_AUKTION_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): AffenAuktionState {
    const question = content.questions[0];
    if (!question) throw new Error("affen-auktion: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    const limits: Record<string, number> = {};
    for (const p of players) {
      limits[p] = ctx.match ? aaMaxGebot(ctx.match.balance(p)) : AA_FALLBACK_LIMIT;
    }
    return {
      question,
      players,
      startedAt: now,
      phase: "setzen",
      auktionEndetAt: now + AA_AUKTION_MS,
      auktionMaxEndetAt: now + AA_AUKTION_MS + AA_AUKTION_MAX_EXTRA_MS,
      frageStartetAt: null,
      frageEndetAt: null,
      timerMs: Math.round(AA_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      hoechstgebot: 0,
      hoechstbietender: null,
      gebotHistorie: [],
      limits,
      answer: null,
      gesperrt: [],
      zweitversuch: false,
      erstattet: false,
      uebersprungen: false,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: AffenAuktionState, action: Action, ctx: Ctx): AffenAuktionState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: niemand zahlt für eine geskippte Auktion.
        return { ...state, uebersprungen: true, finished: true };
      }
      const shift = action.type === "timer.shift";
      return {
        ...state,
        startedAt: shift ? state.startedAt + action.ms : state.startedAt,
        auktionEndetAt:
          state.phase === "setzen" || shift
            ? state.auktionEndetAt + action.ms
            : state.auktionEndetAt,
        auktionMaxEndetAt: state.auktionMaxEndetAt + action.ms,
        frageStartetAt:
          shift && state.frageStartetAt !== null
            ? state.frageStartetAt + action.ms
            : state.frageStartetAt,
        frageEndetAt:
          state.frageEndetAt !== null && (state.phase === "frage" || shift)
            ? state.frageEndetAt + action.ms
            : state.frageEndetAt,
      };
    }

    if (action.kind === "joker") {
      // Info-Joker NUR im Frage-Fenster und NUR für den Auktions-Gewinner.
      if (state.finished || state.phase !== "frage") return state;
      const gewinner = state.hoechstbietender;
      if (gewinner === null) return state;
      if (action.type === "fiftyFifty") {
        if (action.playerId !== gewinner || state.answer !== null) return state;
        const offen = falscheOffeneOptionen(state);
        if (offen.length < 2) return state;
        const erste = offen.splice(ctx.rng.int(offen.length), 1)[0];
        const zweite = offen.splice(ctx.rng.int(offen.length), 1)[0];
        return { ...state, gesperrt: [...state.gesperrt, erste, zweite] };
      }
      if (action.type === "removeOne") {
        if (action.playerId !== null && action.playerId !== gewinner) return state;
        if (state.answer !== null) return state;
        const offen = falscheOffeneOptionen(state);
        if (offen.length < 2) return state; // mind. 1 falsche bleibt stehen
        const wahl = offen[ctx.rng.int(offen.length)];
        return { ...state, gesperrt: [...state.gesperrt, wahl] };
      }
      if (action.type === "secondTry") {
        if (action.playerId !== gewinner || state.zweitversuch) return state;
        const a = state.answer;
        if (a === null || a.choice === state.question.answer) return state;
        return {
          ...state,
          answer: null,
          gesperrt: [...state.gesperrt, a.choice],
          zweitversuch: true,
        };
      }
      return state;
    }

    if (state.finished) return state;
    const p = action.playerId;

    // ---------- AUKTION: bieten (+25) oder „erhöhe auf Betrag" ----------
    if (action.action.type === "bieten" || action.action.type === "einsatz") {
      if (state.phase !== "setzen") return state;
      if (action.atServerTime >= state.auktionEndetAt) return state;
      if (state.hoechstbietender === p) return state; // kein Selbst-Überbieten
      const limit = state.limits[p] ?? AA_FALLBACK_LIMIT;
      const ziel =
        action.action.type === "bieten"
          ? state.hoechstgebot + AA_SCHRITT <= limit
            ? state.hoechstgebot + AA_SCHRITT
            : null
          : aaKlemmeGebot(action.action.betrag, state.hoechstgebot, limit);
      if (ziel === null) return state; // Limit erreicht — Gebot verpufft
      return mitGebot(state, p, ziel, action.atServerTime);
    }

    // ---------- FRAGE: nur der Gewinner antwortet (exklusiv) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageEndetAt === null || state.frageStartetAt === null) {
      return state;
    }
    if (p !== state.hoechstbietender) return state;
    if (state.answer !== null) return state;
    if (state.gesperrt.includes(action.action.choice)) return state;
    if (action.atServerTime > state.frageEndetAt + SPAETANTWORT_GNADE_MS) return state;
    return {
      ...state,
      answer: {
        choice: action.action.choice,
        nachMs: Math.max(0, action.atServerTime - state.frageStartetAt),
      },
    };
  },

  tick(state: AffenAuktionState, ctx: Ctx): AffenAuktionState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "setzen") {
      if (now < state.auktionEndetAt) return state;
      // Hammer fällt: ohne Gebote verfällt die Frage sofort.
      if (state.hoechstbietender === null) return { ...state, finished: true };
      return {
        ...state,
        phase: "frage",
        frageStartetAt: now,
        frageEndetAt: now + state.timerMs,
      };
    }
    // Phase "frage": Antwort da ⇒ sofort fertig; sonst Timer abwarten.
    if (state.answer !== null || (state.frageEndetAt !== null && now >= state.frageEndetAt)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: AffenAuktionState, p: PlayerId, _ctx: Ctx): AffenAuktionState {
    let s: AffenAuktionState = { ...state, connected: { ...state.connected, [p]: false } };
    // Gewinner weg, Antwort offen ⇒ Erstattung vormerken (§2.9-Präzedenz).
    if (!s.finished && s.phase === "frage" && p === s.hoechstbietender && s.answer === null) {
      s = { ...s, erstattet: true };
    }
    return s;
  },

  onReconnect(state: AffenAuktionState, p: PlayerId, _ctx: Ctx): AffenAuktionState {
    let s: AffenAuktionState = { ...state, connected: { ...state.connected, [p]: true } };
    // Zurück im Fenster: die Erstattung ist wieder aufgehoben.
    if (!s.finished && p === s.hoechstbietender && s.erstattet) {
      s = { ...s, erstattet: false };
    }
    return s;
  },

  viewFor(state: AffenAuktionState, role: Role, player?: PlayerId): unknown {
    const q = state.question;
    const gewinner = state.hoechstbietender;
    const basis = {
      questionId: q.id,
      phase: state.phase,
      // Teaser wie Alles-oder-Banane: geboten wird BLIND auf die Frage.
      kategorie: q.category,
      schwierigkeit: q.difficulty,
      endsAt: state.phase === "setzen" ? state.auktionEndetAt : (state.frageEndetAt ?? 0),
      timerMs: state.phase === "setzen" ? AA_AUKTION_MS : state.timerMs,
      hoechstgebot: state.hoechstgebot,
      hoechstbietender: gewinner,
      gebotHistorie: state.gebotHistorie.slice(-6),
      schritt: AA_SCHRITT,
      // Frage-Text/-Optionen erst IM Frage-Fenster (Leak-Wache serverseitig).
      text: state.phase === "frage" ? q.text : null,
      answeredCount: state.answer !== null ? 1 : 0,
      spielerZahl: state.players.length,
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          correctIndex: state.phase === "frage" ? q.answer : null,
          erklaerung:
            gewinner === null
              ? "Keine Gebote — der Hammer fiel ins Leere, die Frage verfällt."
              : q.erklaerung,
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: p === gewinner ? (state.answer?.choice ?? null) : null,
            correct: p === gewinner && state.answer !== null && state.answer.choice === q.answer,
            delta: scores[p] ?? 0,
            gebot: p === gewinner ? state.hoechstgebot : null,
            erstattet: p === gewinner && state.erstattet && state.answer === null,
          })),
        }
      : null;

    if (role === "gm") {
      return {
        ...basis,
        text: q.text,
        options: q.options,
        correctIndex: q.answer,
        limits: state.limits,
        aufloesung,
      };
    }
    if (role === "player") {
      const duBistGewinner = player !== undefined && player === gewinner;
      return {
        ...basis,
        // Setz-Konvention (wie Alles-oder-Banane): einsatzMax + yourEinsatz —
        // generische Clients/Bots können damit sofort mitbieten.
        einsatzMax: player !== undefined ? (state.limits[player] ?? AA_FALLBACK_LIMIT) : 0,
        yourEinsatz:
          state.phase === "setzen" && duBistGewinner ? { betrag: state.hoechstgebot } : null,
        duBistGewinner,
        // Optionen NUR für den Gewinner — das Antwortrecht ist exklusiv.
        options: state.phase === "frage" && duBistGewinner ? q.options : null,
        zuschauerOptionen: state.phase === "frage" && !duBistGewinner ? q.options : null,
        yourChoice: duBistGewinner ? (state.answer?.choice ?? null) : null,
        gesperrt: duBistGewinner ? state.gesperrt : [],
        zweitversuch: duBistGewinner && state.zweitversuch,
        aufloesung,
      };
    }
    return {
      ...basis,
      options: state.phase === "frage" ? q.options : null,
      gesperrt: state.gesperrt,
      aufloesung,
    };
  },

  isFinished(state: AffenAuktionState): boolean {
    return state.finished;
  },

  scores(state: AffenAuktionState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Nur der Gewinner wird gewertet — die Anteils-Empfänger bleiben null
   * (sonst würde die delta>0-Heuristik sie fälschlich als „richtig" zählen). */
  outcomes(state: AffenAuktionState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) result[p] = { correct: null };
    const gewinner = state.hoechstbietender === null ? null : asPlayerId(state.hoechstbietender);
    if (gewinner === null || state.uebersprungen) return result;
    if (state.answer !== null) {
      result[gewinner] = {
        correct: state.answer.choice === state.question.answer,
        nachMs: state.answer.nachMs,
        ...(state.zweitversuch ? { zweitversuch: true } : {}),
      };
    } else if (!state.erstattet && state.phase === "frage") {
      // Antwortrecht gekauft und verschenkt: zählt als falsch.
      result[gewinner] = { correct: false };
    }
    return result;
  },
};
