// Minigame „Der Bananen-Tresor" (Schätzrunde, GAME-DESIGN §2.3): Jeder tippt einen
// Wert am vertikalen Slider; nächster dran gewinnt, gestaffelt nach Nähe.
// Festwert-Auszahlung 400/250/150/50 („Schätzen lohnt immer"), Volltreffer 1.000 MM;
// HARD-Variante 800/500/300/100, Volltreffer 2.000. Kein Speed-Bonus, keine Streak.
// Edge-Cases: gleiche Distanz = beide der bessere Platz (nächster entfällt),
// letzter bewegter Slider-Stand zählt ohne Einloggen, unbewegt = keine Wertung,
// Disconnect = letzter Stand, Slider-Kappe gegen Überlauf.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  BANANEN_TRESOR_META,
  TRESOR_FESTWERTE,
  TRESOR_TIMER_MS,
  volltrefferToleranz,
  type BananenTresorAction,
  type TresorFrage,
} from "../../../shared/minigames/bananen-tresor.meta";
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
import { TRESOR_FRAGEN } from "./fragen";

export interface BananenTresorState {
  frage: TresorFrage;
  players: PlayerId[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  /** Letzter Slider-Stand pro Spieler — zählt auch OHNE Einloggen (§2.3). */
  tipps: Record<string, { wert: number; eingeloggt: boolean; atMs: number }>;
  offline: Record<string, true>;
  finished: boolean;
}

type Action = PlayerAction<BananenTresorAction> | GmAction | JokerAction;

function alleFertig(state: BananenTresorState): boolean {
  return state.players.every((p) => state.tipps[p]?.eingeloggt || state.offline[p]);
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

interface Wertung {
  distanz: number | null;
  platz: number | null;
  volltreffer: boolean;
  delta: number;
}

/**
 * Nähe-Staffelung mit Competition-Ranking: gleiche Distanz = beide bekommen den
 * BESSEREN Platz, der nächste Platz entfällt (§2.3). Nur Spieler MIT Tipp werden
 * gewertet („unbewegt = keine Wertung"); Volltreffer ersetzt den Platz-1-Festwert.
 * Volltreffer = Tipp im Toleranz-Fenster der Frage (absolut VOR prozent —
 * Jahreszahl-Fix); eingebaute Fragen ohne Toleranz verlangen den exakten Wert.
 */
function berechneWertungen(state: BananenTresorState): Record<string, Wertung> {
  const festwerte = TRESOR_FESTWERTE[state.frage.variante];
  const toleranz = volltrefferToleranz(state.frage);
  const result: Record<string, Wertung> = {};
  for (const p of state.players) {
    result[p] = { distanz: null, platz: null, volltreffer: false, delta: 0 };
  }
  const teilnehmer = state.players
    .filter((p) => state.tipps[p] !== undefined)
    .map((p) => ({ p, distanz: Math.abs(state.tipps[p].wert - state.frage.richtwert) }))
    .sort((a, b) => a.distanz - b.distanz);

  let i = 0;
  while (i < teilnehmer.length) {
    const distanz = teilnehmer[i].distanz;
    const gleiche = teilnehmer.filter((t) => t.distanz === distanz);
    const platz = i + 1; // Competition-Ranking: nach 2× Platz 1 kommt Platz 3.
    for (const t of gleiche) {
      const volltreffer = distanz <= toleranz;
      const delta = volltreffer
        ? festwerte.volltreffer
        : platz <= 3
          ? festwerte.plaetze[platz - 1]
          : festwerte.rest;
      result[t.p] = { distanz, platz, volltreffer, delta };
    }
    i += gleiche.length;
  }
  return result;
}

/** Pool-Frage (kind "schaetz", Content-Loader) → TresorFrage; sonst null.
 * Toleranz/Range kommen aus der Frage; HARD-Festwerte ab Schwierigkeit hard. */
function frageAusContent(content: ContentSlice): TresorFrage | null {
  const q: Question | undefined = content.questions[0];
  if (!q || q.kind !== "schaetz" || q.schaetz === undefined) return null;
  return {
    id: q.id,
    text: q.text,
    einheit: q.schaetz.einheit,
    richtwert: q.schaetz.richtwert,
    eingabeMin: q.schaetz.eingabeMin,
    eingabeMax: q.schaetz.eingabeMax,
    skala: q.schaetz.skala,
    variante: q.difficulty === "hard" || q.difficulty === "ultrahard" ? "hard" : "standard",
    erklaerung: q.erklaerung,
    toleranzProzent: q.schaetz.toleranzProzent,
    ...(q.schaetz.toleranzAbsolut !== undefined
      ? { toleranzAbsolut: q.schaetz.toleranzAbsolut }
      : {}),
  };
}

export const bananenTresorPlugin: MinigamePlugin<BananenTresorState, BananenTresorAction> = {
  meta: BANANEN_TRESOR_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): BananenTresorState {
    // Echte schaetz-Fragen aus dem Content-Pool (492 Stück) haben Vorrang;
    // der eingebaute Mini-Pool ist NUR Fallback (z. B. leerer Slice im Test).
    const frage =
      frageAusContent(content) ??
      TRESOR_FRAGEN[poolIndex(content, players, ctx, TRESOR_FRAGEN.length)];
    const now = ctx.clock.now();
    return {
      frage,
      players,
      startedAt: now,
      endsAt: now + TRESOR_TIMER_MS,
      timerMs: TRESOR_TIMER_MS,
      tipps: {},
      offline: {},
      finished: false,
    };
  },

  reduce(state: BananenTresorState, action: Action, _ctx: Ctx): BananenTresorState {
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
    if (action.action.type !== "tipp" && action.action.type !== "einloggen") return state;
    const roh = action.action.wert;
    if (typeof roh !== "number" || !Number.isFinite(roh)) return state;
    // Eingeloggt = eingerastet: danach kein Umentscheiden mehr.
    if (state.tipps[action.playerId]?.eingeloggt) return state;
    // Spätantwort: Server-Empfangszeit zählt, +400 ms Gnade, danach verworfen.
    if (action.atServerTime > state.endsAt + SPAETANTWORT_GNADE_MS) return state;
    // Slider-Kappe gegen Überlauf (§2.3): hart auf die Frage-Spanne geklemmt.
    const wert = Math.round(
      Math.min(state.frage.eingabeMax, Math.max(state.frage.eingabeMin, roh)),
    );
    const nachMs = Math.max(0, action.atServerTime - state.startedAt);
    return {
      ...state,
      tipps: {
        ...state.tipps,
        [action.playerId]: { wert, eingeloggt: action.action.type === "einloggen", atMs: nachMs },
      },
    };
  },

  tick(state: BananenTresorState, ctx: Ctx): BananenTresorState {
    if (state.finished) return state;
    if (ctx.clock.now() >= state.endsAt || alleFertig(state)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: BananenTresorState, p: PlayerId, _ctx: Ctx): BananenTresorState {
    // „Disconnect = keine Abgabe": der letzte bewegte Stand bleibt gewertet,
    // aber die Runde wartet nicht mehr auf ein Einloggen dieses Spielers.
    return { ...state, offline: { ...state.offline, [p]: true } };
  },

  onReconnect(state: BananenTresorState, p: PlayerId, _ctx: Ctx): BananenTresorState {
    if (!state.offline[p]) return state;
    const offline = { ...state.offline };
    delete offline[p];
    return { ...state, offline };
  },

  viewFor(state: BananenTresorState, role: Role, player?: PlayerId): unknown {
    const basis = {
      questionId: state.frage.id,
      text: state.frage.text,
      einheit: state.frage.einheit,
      eingabeMin: state.frage.eingabeMin,
      eingabeMax: state.frage.eingabeMax,
      skala: state.frage.skala,
      variante: state.frage.variante,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      answeredCount: Object.keys(state.tipps).length,
      // Screen zeigt WER schon getippt/eingeloggt hat — die Werte bleiben geheim
      // bis zur Auflösung („alle Tipps erscheinen GLEICHZEITIG", §2.3).
      abgegeben: state.players
        .filter((p) => state.tipps[p] !== undefined)
        .map((p) => ({ playerId: p, eingeloggt: state.tipps[p].eingeloggt })),
      finished: state.finished,
    };
    const wertungen = state.finished ? berechneWertungen(state) : {};
    const aufloesung = state.finished
      ? {
          richtwert: state.frage.richtwert,
          einheit: state.frage.einheit,
          erklaerung: state.frage.erklaerung,
          perPlayer: state.players.map((p) => {
            const tipp = state.tipps[p]?.wert ?? null;
            const w = wertungen[p];
            return {
              playerId: p,
              tipp,
              choice: tipp, // Generische Auflösung der Apps: null ⇒ „keine Abgabe"
              distanz: w.distanz,
              platz: w.platz,
              volltreffer: w.volltreffer,
              correct: w.delta > 0,
              delta: w.delta,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Richtwert UND Live-Tipps immer (liest Ausreißer vor).
      return {
        ...basis,
        richtwert: state.frage.richtwert,
        liveTipps: state.players
          .filter((p) => state.tipps[p] !== undefined)
          .map((p) => ({ playerId: p, wert: state.tipps[p].wert })),
        aufloesung,
      };
    }
    if (role === "player") {
      const t = player ? state.tipps[player] : undefined;
      return {
        ...basis,
        yourTipp: t ? { wert: t.wert, eingeloggt: t.eingeloggt } : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: BananenTresorState): boolean {
    return state.finished;
  },

  scores(state: BananenTresorState): Record<PlayerId, number> {
    const wertungen = berechneWertungen(state);
    const result: Record<PlayerId, number> = {};
    for (const p of state.players) result[p] = wertungen[p]?.delta ?? 0;
    return result;
  },

  /** Schätzrunde kennt kein „falsch": wer gewertet wurde, war „richtig" (Streak
   * ist per meta.streak: false ohnehin aus); ohne Tipp = keine Antwort (null). */
  outcomes(state: BananenTresorState): Record<PlayerId, PlayerOutcome> {
    const wertungen = berechneWertungen(state);
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const t = state.tipps[p];
      result[p] = t
        ? { correct: (wertungen[p]?.delta ?? 0) > 0, nachMs: t.atMs }
        : { correct: null };
    }
    return result;
  },
};
