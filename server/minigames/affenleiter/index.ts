// Minigame „Affenleiter" (Sortieren, GAME-DESIGN §2.4): 4 Elemente in die richtige
// Reihenfolge ziehen. Scoring: pro korrekt platziertem Element Grundwert/4 (auf 10er
// gerundet); komplett richtig = +50 % Perfekt-Bonus und NUR DANN Speed-Bonus.
// Edge-Cases: Startreihenfolge serverseitig PRO SPIELER gemischt (nie die Lösung!),
// keine Abgabe = aktueller Stand zählt, Spätantwort +400 ms Gnade, Disconnect = AFK.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import { FRAGE_WERTE, speedBonus } from "../../../shared/money";
import {
  AFFENLEITER_META,
  LEITER_PERFEKT_FAKTOR,
  LEITER_TIMER_MS,
  istGueltigeReihenfolge,
  type AffenleiterAction,
  type LeiterFrage,
} from "../../../shared/minigames/affenleiter.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type { Rng } from "../../../shared/rng";
import type {
  Ctx,
  GmAction,
  JokerAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";
import { LEITER_FRAGEN } from "./fragen";

export interface AffenleiterState {
  frage: LeiterFrage;
  players: PlayerId[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  /** Serverseitig PRO SPIELER gemischte Startreihenfolge (nie == Lösung). */
  startReihenfolgen: Record<string, number[]>;
  /** Letzter Stand pro Spieler — zählt auch ohne Einloggen (§2.4). */
  abgaben: Record<string, { reihenfolge: number[]; eingeloggt: boolean; atMs: number }>;
  offline: Record<string, true>;
  finished: boolean;
}

type Action = PlayerAction<AffenleiterAction> | GmAction | JokerAction;

/** Fisher-Yates mit injiziertem Rng; mischt neu, solange die Lösung herauskäme. */
function mischeStart(korrekt: readonly number[], rng: Rng): number[] {
  const reihenfolge = [...korrekt];
  do {
    for (let i = reihenfolge.length - 1; i > 0; i--) {
      const j = rng.int(i + 1);
      [reihenfolge[i], reihenfolge[j]] = [reihenfolge[j], reihenfolge[i]];
    }
  } while (reihenfolge.every((e, i) => e === korrekt[i]));
  return reihenfolge;
}

function alleFertig(state: AffenleiterState): boolean {
  return state.players.every((p) => state.abgaben[p]?.eingeloggt || state.offline[p]);
}

/**
 * Pool-Wahl OHNE Wiederholung im Match: Die Loader-Fragen tragen eine laufende
 * Nummer am Id-Ende (q_platzhalter_3) — zusammen mit einem match-stabilen
 * Spieler-Hash ergibt das pro Runde einen ANDEREN Pool-Index (Variation
 * zwischen Matches, keine Doppel-Frage im Match). Ohne Nummer: ctx.rng.
 */
function poolIndex(
  content: ContentSlice,
  players: PlayerId[],
  ctx: Ctx,
  poolLaenge: number,
): number {
  const nr = Number(/(\d+)$/.exec(content.questions[0]?.id ?? "")?.[1]);
  if (!Number.isFinite(nr)) return ctx.rng.int(poolLaenge);
  let hash = 0;
  for (const p of players) {
    for (let i = 0; i < p.length; i++) hash = (hash * 31 + p.charCodeAt(i)) >>> 0;
  }
  return (hash + nr) % poolLaenge;
}

/** Pool-Frage (kind "sortier", Content-Loader) → LeiterFrage; sonst null.
 * Elemente stehen in options, Lösung/Anzeige-Werte in q.sortier (bereits
 * element-indiziert — der Loader normalisiert das Pack-Format). */
function frageAusContent(content: ContentSlice): LeiterFrage | null {
  const q: Question | undefined = content.questions[0];
  if (!q || q.kind !== "sortier" || q.sortier === undefined) return null;
  if (q.options.length !== 4) return null;
  return {
    id: q.id,
    text: q.text,
    schwierigkeit: q.difficulty,
    elemente: [q.options[0], q.options[1], q.options[2], q.options[3]],
    korrektReihenfolge: [
      q.sortier.korrektReihenfolge[0],
      q.sortier.korrektReihenfolge[1],
      q.sortier.korrektReihenfolge[2],
      q.sortier.korrektReihenfolge[3],
    ],
    aufloesungWerte: [
      q.sortier.aufloesungWerte[0],
      q.sortier.aufloesungWerte[1],
      q.sortier.aufloesungWerte[2],
      q.sortier.aufloesungWerte[3],
    ],
    erklaerung: q.erklaerung,
  };
}

function standVon(state: AffenleiterState, p: string): number[] {
  return state.abgaben[p]?.reihenfolge ?? state.startReihenfolgen[p];
}

function korrektAnzahl(state: AffenleiterState, reihenfolge: number[]): number {
  return reihenfolge.filter((e, i) => e === state.frage.korrektReihenfolge[i]).length;
}

/**
 * §2.4: pro korrekt platziertem Element Grundwert/4 (Teilsumme auf 10er gerundet,
 * Projekt-Konvention wie speedBonus); komplett richtig = Grundwert × 1,5 + Speed-
 * Bonus über das 30-s-Fenster. Bei 4 Elementen ist „genau 3 richtig" unmöglich.
 */
function berechneScores(state: AffenleiterState): Record<PlayerId, number> {
  const wert = FRAGE_WERTE[state.frage.schwierigkeit];
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const anzahl = korrektAnzahl(state, standVon(state, p));
    if (anzahl === 4) {
      // Perfekt ohne Abgabe ist unmöglich (Start ≠ Lösung) — atMs existiert immer.
      const atMs = state.abgaben[p]?.atMs ?? state.timerMs;
      result[p] = Math.round(wert * LEITER_PERFEKT_FAKTOR) + speedBonus(wert, atMs, state.timerMs);
    } else {
      result[p] = Math.round((anzahl * wert) / 4 / 10) * 10;
    }
  }
  return result;
}

export const affenleiterPlugin: MinigamePlugin<AffenleiterState, AffenleiterAction> = {
  meta: AFFENLEITER_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): AffenleiterState {
    // Echte sortier-Fragen aus dem Content-Pool (218 Stück) haben Vorrang;
    // der eingebaute Mini-Pool ist NUR Fallback (z. B. leerer Slice im Test).
    const frage =
      frageAusContent(content) ??
      LEITER_FRAGEN[poolIndex(content, players, ctx, LEITER_FRAGEN.length)];
    const now = ctx.clock.now();
    const startReihenfolgen: Record<string, number[]> = {};
    for (const p of players) startReihenfolgen[p] = mischeStart(frage.korrektReihenfolge, ctx.rng);
    return {
      frage,
      players,
      startedAt: now,
      endsAt: now + LEITER_TIMER_MS,
      timerMs: LEITER_TIMER_MS,
      startReihenfolgen,
      abgaben: {},
      offline: {},
      finished: false,
    };
  },

  reduce(state: AffenleiterState, action: Action, _ctx: Ctx): AffenleiterState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      if (action.type === "timer.shift") {
        return {
          ...state,
          startedAt: state.startedAt + action.ms,
          endsAt: state.endsAt + action.ms,
        };
      }
      return { ...state, endsAt: state.endsAt + action.ms };
    }
    // Joker-Hooks sind nicht deklariert (meta.jokerAktionen fehlt) ⇒ no-op.
    if (action.kind !== "player") return state;
    if (state.finished) return state;
    if (action.action.type !== "sortierung" && action.action.type !== "einloggen") return state;
    if (!istGueltigeReihenfolge(action.action.reihenfolge)) return state;
    // Eingeloggt = eingerastet: danach kein Umsortieren mehr.
    if (state.abgaben[action.playerId]?.eingeloggt) return state;
    // Spätantwort: Server-Empfangszeit zählt, +400 ms Gnade, danach verworfen.
    if (action.atServerTime > state.endsAt + SPAETANTWORT_GNADE_MS) return state;
    const nachMs = Math.max(0, action.atServerTime - state.startedAt);
    return {
      ...state,
      abgaben: {
        ...state.abgaben,
        [action.playerId]: {
          reihenfolge: [...action.action.reihenfolge],
          eingeloggt: action.action.type === "einloggen",
          atMs: nachMs,
        },
      },
    };
  },

  tick(state: AffenleiterState, ctx: Ctx): AffenleiterState {
    if (state.finished) return state;
    if (ctx.clock.now() >= state.endsAt || alleFertig(state)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: AffenleiterState, p: PlayerId, _ctx: Ctx): AffenleiterState {
    // AFK-Affe: letzter Stand zählt weiter, aber die Runde wartet nicht auf ihn.
    return { ...state, offline: { ...state.offline, [p]: true } };
  },

  onReconnect(state: AffenleiterState, p: PlayerId, _ctx: Ctx): AffenleiterState {
    if (!state.offline[p]) return state;
    const offline = { ...state.offline };
    delete offline[p];
    return { ...state, offline };
  },

  viewFor(state: AffenleiterState, role: Role, player?: PlayerId): unknown {
    const basis = {
      questionId: state.frage.id,
      text: state.frage.text,
      elemente: state.frage.elemente,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      // Für die Bühne: wie viele haben EINGELOGGT (Zwischenstände bleiben privat).
      answeredCount: state.players.filter((p) => state.abgaben[p]?.eingeloggt).length,
      eingeloggte: state.players.filter((p) => state.abgaben[p]?.eingeloggt),
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    // korrektReihenfolge/aufloesungWerte erst NACH finished — Leak-Schutz serverseitig.
    const aufloesung = state.finished
      ? {
          korrektReihenfolge: state.frage.korrektReihenfolge,
          aufloesungWerte: state.frage.aufloesungWerte,
          erklaerung: state.frage.erklaerung,
          perPlayer: state.players.map((p) => {
            const reihenfolge = standVon(state, p);
            const anzahl = korrektAnzahl(state, reihenfolge);
            return {
              playerId: p,
              reihenfolge,
              richtigPositionen: reihenfolge.map((e, i) => e === state.frage.korrektReihenfolge[i]),
              korrektAnzahl: anzahl,
              perfekt: anzahl === 4,
              choice: anzahl, // Generische Auflösung der Apps (nie null: Stand zählt immer)
              correct: (scores[p] ?? 0) > 0,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Lösung + Live-Stände immer.
      return {
        ...basis,
        korrektReihenfolge: state.frage.korrektReihenfolge,
        aufloesungWerte: state.frage.aufloesungWerte,
        liveStaende: state.players.map((p) => ({
          playerId: p,
          reihenfolge: standVon(state, p),
          eingeloggt: state.abgaben[p]?.eingeloggt ?? false,
        })),
        aufloesung,
      };
    }
    if (role === "player") {
      const a = player ? state.abgaben[player] : undefined;
      return {
        ...basis,
        yourStart: player ? state.startReihenfolgen[player] : undefined,
        yourStand: player ? standVon(state, player) : undefined,
        yourEingeloggt: a?.eingeloggt ?? false,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: AffenleiterState): boolean {
    return state.finished;
  },

  scores(state: AffenleiterState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Streak zählt NUR bei Komplett-Richtig (§2.4): Teil-Ketten sind „nicht
   * richtig" (Kette reißt), Teilpunkte gibt es über scores() trotzdem. */
  outcomes(state: AffenleiterState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const perfekt = korrektAnzahl(state, standVon(state, p)) === 4;
      const abgabe = state.abgaben[p];
      result[p] = abgabe
        ? { correct: perfekt, nachMs: abgabe.atMs }
        : { correct: perfekt ? true : null }; // ohne Abgabe: Startstand, kein „falsch"-Stempel
    }
    return result;
  },
};
