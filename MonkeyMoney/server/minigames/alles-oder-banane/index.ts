// „Alles oder Banane" (GAME-DESIGN §2.9): die Wettrunde im RISIKO-Slot.
// Drei Phasen pro Frage: SETZEN (12 s, nur Kategorie+Schwierigkeit sichtbar,
// Einsätze geheim) → REVEAL (6 s, alle Einsätze werden aufgedeckt) → FRAGE
// (20 s MC-4). Richtig = +Einsatz, falsch = −Einsatz (an die Bank, NICHT ins
// Glas). Einsatz 100–1.000 in 50er-Schritten, Kappe 50 % des Kontostands
// (Snapshot via ctx.match beim init); Konto < 100 ⇒ 100 MM Gratis-Einsatz der
// Bank (falsch kostet nichts, richtig zahlt +100). Kein Einsatz eingeloggt ⇒
// automatisch das Minimum. Disconnect nach Einsatz ⇒ Einsatz zurückerstattet,
// Frage zählt als keine Antwort. Keine Streak/Speed — Auszahlung exakt ±Einsatz.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  ALLES_ODER_BANANE_META,
  AOB_EINSATZ_MAX,
  AOB_EINSATZ_MIN,
  AOB_FRAGE_MS,
  AOB_REVEAL_MS,
  AOB_SETZEN_MS,
  aobEinsatzMax,
  aobKlemmeEinsatz,
  type AllesOderBananeAction,
} from "../../../shared/minigames/alles-oder-banane.meta";
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

export interface AobEinsatz {
  betrag: number;
  /** Bank-Kredit (Konto < 100): falsch kostet nichts, richtig zahlt +betrag. */
  gratis: boolean;
  /** Nicht selbst eingeloggt — Minimum automatisch gesetzt (§2.9 Edge). */
  auto: boolean;
}

export interface AllesOderBananeState {
  question: Question;
  players: PlayerId[];
  phase: "setzen" | "reveal" | "frage";
  startedAt: number;
  setzenEndetAt: number;
  revealEndetAt: number | null;
  frageStartetAt: number | null;
  frageEndetAt: number | null;
  timerMs: number; // Frage-Fenster (mit timerFaktor)
  /** Konto-Snapshot beim init — Basis der Einsatz-Kappe (50 %). */
  balancesVorRunde: Record<string, number>;
  einsaetze: Record<string, AobEinsatz>;
  /** Disconnect nach Einsatz ohne Antwort: Einsatz zurückerstattet (§2.9). */
  erstattet: Record<string, true>;
  answers: Record<string, { choice: number; nachMs: number }>;
  gesperrt: Record<string, number[]>;
  gesperrtGlobal: number[];
  zweitversuch: Record<string, true>;
  connected: Record<string, boolean>;
  insiderId: string | null;
  insiderVorsprungMs: number;
  geraeteMischung: boolean;
  /** GM-Skip (force.finish): offene Einsätze werden erstattet, nicht bestraft. */
  uebersprungen: boolean;
  finished: boolean;
}

type Action = PlayerAction<AllesOderBananeAction> | GmAction | JokerAction;

/** Ohne match-API (isolierte Läufe): voller Einsatz-Spielraum als Fallback. */
const AOB_FALLBACK_KONTO = AOB_EINSATZ_MAX * 2;

function gesperrtFuer(state: AllesOderBananeState, p: string): number[] {
  return [...new Set([...(state.gesperrt[p] ?? []), ...state.gesperrtGlobal])];
}

function falscheOffeneOptionen(state: AllesOderBananeState, p: string): number[] {
  const zu = new Set(gesperrtFuer(state, p));
  return [0, 1, 2, 3].filter((i) => i !== state.question.answer && !zu.has(i));
}

function verbundene(state: AllesOderBananeState): PlayerId[] {
  return state.players.filter((p) => state.connected[p]);
}

/** Setzen-Ende: Verbundene ohne Einsatz bekommen automatisch das Minimum. */
function schliesseSetzen(state: AllesOderBananeState, now: number): AllesOderBananeState {
  const einsaetze = { ...state.einsaetze };
  for (const p of verbundene(state)) {
    if (einsaetze[p] !== undefined) continue;
    const konto = state.balancesVorRunde[p] ?? AOB_FALLBACK_KONTO;
    einsaetze[p] = {
      betrag: aobKlemmeEinsatz(AOB_EINSATZ_MIN, konto),
      gratis: konto < AOB_EINSATZ_MIN,
      auto: true,
    };
  }
  return { ...state, einsaetze, phase: "reveal", revealEndetAt: now + AOB_REVEAL_MS };
}

/** §2.9-Auszahlung: richtig +Einsatz, falsch −Einsatz (Gratis-Kredit: 0),
 * keine Antwort = Einsatz weg (erstattet/übersprungen/offline = 0). */
function berechneScores(state: AllesOderBananeState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const e = state.einsaetze[p];
    if (e === undefined) {
      result[p] = 0; // nie gesetzt (während des Setzens offline)
      continue;
    }
    const a = state.answers[p];
    if (a !== undefined) {
      if (a.choice === state.question.answer) {
        // Rückgaberecht: Gewinn nur 50 % (auf 10er gerundet).
        result[p] = state.zweitversuch[p] ? Math.round(e.betrag / 2 / 10) * 10 : e.betrag;
      } else {
        result[p] = e.gratis ? 0 : -e.betrag;
      }
      continue;
    }
    // Keine Antwort: erstattet (Disconnect) oder GM-Skip ⇒ 0, sonst Einsatz weg.
    if (state.erstattet[p] || state.uebersprungen || !state.connected[p]) {
      result[p] = 0;
    } else {
      result[p] = e.gratis ? 0 : -e.betrag;
    }
  }
  return result;
}

function alleVerbundenenFertig(state: AllesOderBananeState): boolean {
  const online = verbundene(state);
  return online.length > 0 && online.every((p) => state.answers[p] !== undefined);
}

export const allesOderBananePlugin: MinigamePlugin<AllesOderBananeState, AllesOderBananeAction> = {
  meta: ALLES_ODER_BANANE_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): AllesOderBananeState {
    const question = content.questions[0];
    if (!question) throw new Error("alles-oder-banane: ContentSlice ohne Frage");
    const mods = content.mods;
    const now = ctx.clock.now();
    const balances: Record<string, number> = {};
    for (const p of players) balances[p] = ctx.match?.balance(p) ?? AOB_FALLBACK_KONTO;
    return {
      question,
      players,
      phase: "setzen",
      startedAt: now,
      setzenEndetAt: now + AOB_SETZEN_MS,
      revealEndetAt: null,
      frageStartetAt: null,
      frageEndetAt: null,
      timerMs: Math.round(AOB_FRAGE_MS * (mods?.timerFaktor ?? 1)),
      balancesVorRunde: balances,
      einsaetze: {},
      erstattet: {},
      answers: {},
      gesperrt: {},
      gesperrtGlobal: [],
      zweitversuch: {},
      connected: Object.fromEntries(players.map((p) => [p, true])),
      insiderId: mods?.insiderPlayerId ?? null,
      insiderVorsprungMs: mods?.insiderVorsprungMs ?? 0,
      geraeteMischung: mods?.geraeteMischung === true,
      uebersprungen: false,
      finished: false,
    };
  },

  reduce(state: AllesOderBananeState, action: Action, ctx: Ctx): AllesOderBananeState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: niemand verliert seinen Einsatz für eine geskippte Frage.
        return { ...state, uebersprungen: true, finished: true };
      }
      // timer.extend/shift: die Deadline der AKTUELLEN Phase verschieben
      // (shift wandert zusätzlich alle absoluten Zeitanker mit).
      const shift = action.type === "timer.shift";
      return {
        ...state,
        startedAt: shift ? state.startedAt + action.ms : state.startedAt,
        setzenEndetAt:
          state.phase === "setzen" || shift ? state.setzenEndetAt + action.ms : state.setzenEndetAt,
        revealEndetAt:
          state.revealEndetAt !== null && (state.phase === "reveal" || shift)
            ? state.revealEndetAt + action.ms
            : state.revealEndetAt,
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
      // Info-Joker NUR im Frage-Fenster (§2.9: nach dem Einsatz-Reveal).
      if (state.finished || state.phase !== "frage") return state;
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
      if (action.type === "removeOne") {
        if (action.playerId === null) {
          const zu = new Set(state.gesperrtGlobal);
          const offen = [0, 1, 2, 3].filter((i) => i !== state.question.answer && !zu.has(i));
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
      if (action.type === "secondTry") {
        const p = action.playerId;
        const a = state.answers[p];
        if (a === undefined || state.zweitversuch[p]) return state;
        if (a.choice === state.question.answer) return state; // richtig ⇒ kein Bedarf
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

    // ---------- Einsatz einloggen (nur im Setz-Fenster, rastet ein) ----------
    if (action.action.type === "einsatz") {
      if (state.phase !== "setzen") return state;
      if (action.atServerTime > state.setzenEndetAt) return state;
      const p = action.playerId;
      if (state.einsaetze[p] !== undefined) return state; // eingerastet
      const konto = state.balancesVorRunde[p] ?? AOB_FALLBACK_KONTO;
      const einsatz: AobEinsatz = {
        betrag: aobKlemmeEinsatz(action.action.betrag, konto),
        gratis: konto < AOB_EINSATZ_MIN,
        auto: false,
      };
      return { ...state, einsaetze: { ...state.einsaetze, [p]: einsatz } };
    }

    // ---------- MC-4-Antwort (nur im Frage-Fenster) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageEndetAt === null || state.frageStartetAt === null) {
      return state;
    }
    const p = action.playerId;
    if (state.answers[p] !== undefined) return state; // erste Antwort zählt
    if (state.einsaetze[p] === undefined) return state; // ohne Einsatz keine Wette
    if (gesperrtFuer(state, p).includes(action.action.choice)) return state;
    if (action.atServerTime > state.frageEndetAt + SPAETANTWORT_GNADE_MS) return state;
    const nachMs = Math.max(0, action.atServerTime - state.frageStartetAt);
    return {
      ...state,
      answers: { ...state.answers, [p]: { choice: action.action.choice, nachMs } },
    };
  },

  tick(state: AllesOderBananeState, ctx: Ctx): AllesOderBananeState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "setzen") {
      const alleGesetzt =
        verbundene(state).length > 0 &&
        verbundene(state).every((p) => state.einsaetze[p] !== undefined);
      if (now >= state.setzenEndetAt || alleGesetzt) return schliesseSetzen(state, now);
      return state;
    }
    if (state.phase === "reveal") {
      if (state.revealEndetAt !== null && now >= state.revealEndetAt) {
        return {
          ...state,
          phase: "frage",
          frageStartetAt: now,
          frageEndetAt: now + state.timerMs,
        };
      }
      return state;
    }
    // Phase "frage":
    if (
      (state.frageEndetAt !== null && now >= state.frageEndetAt) ||
      alleVerbundenenFertig(state)
    ) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: AllesOderBananeState, p: PlayerId, _ctx: Ctx): AllesOderBananeState {
    let s: AllesOderBananeState = { ...state, connected: { ...state.connected, [p]: false } };
    // §2.9: Disconnect nach Einsatz ohne Antwort ⇒ Einsatz wird zurückerstattet.
    if (!s.finished && s.einsaetze[p] !== undefined && s.answers[p] === undefined) {
      s = { ...s, erstattet: { ...s.erstattet, [p]: true } };
    }
    return s;
  },

  onReconnect(state: AllesOderBananeState, p: PlayerId, _ctx: Ctx): AllesOderBananeState {
    let s: AllesOderBananeState = { ...state, connected: { ...state.connected, [p]: true } };
    // Zurück im Spiel, Frage läuft noch: die Erstattung ist wieder aufgehoben.
    if (!s.finished && s.erstattet[p]) {
      const erstattet = { ...s.erstattet };
      delete erstattet[p];
      s = { ...s, erstattet };
    }
    return s;
  },

  viewFor(state: AllesOderBananeState, role: Role, player?: PlayerId): unknown {
    const q = state.question;
    // Insider-Tipp: alle ANDEREN sehen die Frage erst `sichtbarAb`.
    const frageStart = state.frageStartetAt ?? 0;
    const sichtbarAb =
      state.insiderId !== null && player !== state.insiderId
        ? frageStart + state.insiderVorsprungMs
        : frageStart;
    const endsAt =
      state.phase === "setzen"
        ? state.setzenEndetAt
        : state.phase === "reveal"
          ? (state.revealEndetAt ?? 0)
          : (state.frageEndetAt ?? 0);
    const timerMs =
      state.phase === "setzen"
        ? AOB_SETZEN_MS
        : state.phase === "reveal"
          ? AOB_REVEAL_MS
          : state.timerMs;
    // Einsätze sind bis zum Reveal GEHEIM — im Setz-Fenster nur „wer ist drin".
    const reveal = state.phase !== "setzen";
    const basis = {
      questionId: q.id,
      phase: state.phase,
      // Teaser (§2.9): NUR Kategorie + Schwierigkeit vor der Frage.
      kategorie: q.category,
      schwierigkeit: q.difficulty,
      endsAt,
      timerMs,
      // Auto-GM-Signal (P1 „+10s-Misfire"): answeredCount zählt MC-Antworten —
      // die gibt es nur im Frage-Fenster. Setzen (Einsätze) und Reveal
      // (reines Zuschauen) melden eingabeOffen=false, sonst verlängert die
      // Heuristik den 6-s-Reveal auf 16 s Dead-Air.
      eingabeOffen: state.phase === "frage" && !state.finished,
      eingeloggt: state.players.filter((p) => state.einsaetze[p] !== undefined),
      einsaetze: reveal
        ? Object.fromEntries(
            Object.entries(state.einsaetze).map(([p, e]) => [
              p,
              { betrag: e.betrag, gratis: e.gratis },
            ]),
          )
        : null,
      // Frage-Text/-Optionen erst IM Frage-Fenster (Leak-Wache serverseitig).
      text: state.phase === "frage" ? q.text : null,
      options: state.phase === "frage" ? q.options : null,
      sichtbarAb,
      geraeteMischung: state.geraeteMischung,
      answeredCount: Object.keys(state.answers).length,
      spielerZahl: state.players.length,
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          correctIndex: q.answer,
          erklaerung: q.erklaerung,
          perPlayer: state.players.map((p) => {
            const a = state.answers[p];
            return {
              playerId: p,
              choice: a?.choice ?? null,
              correct: a !== undefined && a.choice === q.answer,
              delta: scores[p] ?? 0,
              einsatz: state.einsaetze[p]?.betrag ?? null,
              gratis: state.einsaetze[p]?.gratis === true,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Frage + richtige Antwort + alle Einsätze IMMER.
      return {
        ...basis,
        text: q.text,
        options: q.options,
        correctIndex: q.answer,
        sichtbarAb: frageStart,
        einsaetze: Object.fromEntries(
          Object.entries(state.einsaetze).map(([p, e]) => [
            p,
            { betrag: e.betrag, gratis: e.gratis },
          ]),
        ),
        aufloesung,
      };
    }
    if (role === "player") {
      const du = player !== undefined ? state.einsaetze[player] : undefined;
      const konto =
        player !== undefined ? (state.balancesVorRunde[player] ?? AOB_FALLBACK_KONTO) : 0;
      return {
        ...basis,
        yourEinsatz: du !== undefined ? { betrag: du.betrag, gratis: du.gratis } : null,
        einsatzMax: aobEinsatzMax(konto),
        gratisEinsatz: konto < AOB_EINSATZ_MIN,
        yourChoice: player !== undefined ? (state.answers[player]?.choice ?? null) : null,
        gesperrt: player !== undefined ? gesperrtFuer(state, player) : [],
        zweitversuch: player !== undefined && state.zweitversuch[player] === true,
        aufloesung,
      };
    }
    return { ...basis, gesperrt: state.gesperrtGlobal, aufloesung };
  },

  isFinished(state: AllesOderBananeState): boolean {
    return state.finished;
  },

  scores(state: AllesOderBananeState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  outcomes(state: AllesOderBananeState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const a = state.answers[p];
      result[p] =
        a === undefined
          ? { correct: null }
          : {
              correct: a.choice === state.question.answer,
              nachMs: a.nachMs,
              ...(state.zweitversuch[p] ? { zweitversuch: true } : {}),
            };
    }
    return result;
  },
};
