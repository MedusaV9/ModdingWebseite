// „Rückwärts-Banane" (Musik-Welle): rueckwaerts5s läuft über den SCREEN, alle
// Affen raten GLEICHZEITIG aus 4 Optionen (kein Buzzer — jeder darf einmal).
// Der Abspielplan (Erst-Play + Auto-Replay, GM-„+15 s" hängt eine dritte
// Abspielung an — „2× wiederholbar per GM/Auto") lebt als Server-Zeiten im
// State; der Screen-Client spielt exakt zu diesen Zeitpunkten ab. Die
// AUFLÖSUNG spielt das Intro VORWÄRTS (der Aha-Moment). Scoring wie MC-
// Standard: Grundwert der SONG-Schwierigkeit + Speed-Bonus, Streak zählt.
// Läuft ohne Song-Slice mit dem Fixture-Katalog (Match crasht NIE an Songs).
import type { ContentSlice } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import { fragenGewinn, type Schwierigkeit } from "../../../shared/money";
import {
  RB_GM_REPLAY_VORLAUF_MS,
  RB_MAX_ABSPIELUNGEN,
  RB_TIMER_MS,
  SONG_RUECKWAERTS_META,
  rbAutoAbspielplan,
  type SongRueckwaertsAction,
} from "../../../shared/minigames/song-rueckwaerts.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import { parseSongs, songFrageId, waehleSongUndOptionen, type Song } from "../../../shared/songs";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export interface SongRueckwaertsState {
  questionId: string;
  // GEHEIMNISSE (nur GM/Auflösung; medien nur Screen — URLs tragen die Song-Id!):
  songId: string;
  titel: string;
  artist: string;
  jahr: number;
  medien: Song["medien"];
  correctIndex: number;
  // Öffentlich:
  schwierigkeit: Schwierigkeit;
  optionen: string[];
  players: PlayerId[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  /** Server-Zeiten der Rückwärts-Abspielungen (Erst-Play + Replays, max. 3). */
  abspielplan: number[];
  /** Antwort-Lock: pro Spieler zählt nur die ERSTE Antwort. */
  answers: Record<string, { choice: number; nachMs: number }>;
  finished: boolean;
}

type Action = PlayerAction<SongRueckwaertsAction> | GmAction;

function alleBeantwortet(state: SongRueckwaertsState): boolean {
  return state.players.every((p) => state.answers[p] !== undefined);
}

/** MC-Standard (§3.1): Grundwert der Song-Schwierigkeit + Speed-Bonus. */
function berechneScores(state: SongRueckwaertsState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    const a = state.answers[p];
    result[p] =
      a !== undefined && a.choice === state.correctIndex
        ? fragenGewinn(state.schwierigkeit, a.nachMs, state.timerMs)
        : 0;
  }
  return result;
}

export const songRueckwaertsPlugin: MinigamePlugin<SongRueckwaertsState, SongRueckwaertsAction> = {
  meta: SONG_RUECKWAERTS_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): SongRueckwaertsState {
    // Song-Quelle: ContentSlice.songs → ctx.songs → Fixture-Katalog (nie
    // crashen). parseSongs validiert strikt (Zod) und verwirft Ungültiges —
    // ein kaputter/fremder Slice fällt sauber auf die Fixtures zurück.
    const songs = parseSongs(content.songs ?? ctx.songs?.songs);
    const { ziel, optionen, correctIndex } = waehleSongUndOptionen(songs, ctx.rng);
    const now = ctx.clock.now();
    const timerMs = Math.round(RB_TIMER_MS * (content.mods?.timerFaktor ?? 1));
    return {
      // Nicht-sprechend (Hash): sprechende Song-Ids wären in Views ein Leak.
      questionId: content.questions[0]?.id ?? songFrageId(ziel.id),
      songId: ziel.id,
      titel: ziel.titel,
      artist: ziel.artist,
      jahr: ziel.jahr,
      medien: ziel.medien,
      correctIndex,
      schwierigkeit: ziel.schwierigkeit,
      optionen,
      players,
      startedAt: now,
      endsAt: now + timerMs,
      timerMs,
      abspielplan: rbAutoAbspielplan(now),
      answers: {},
      finished: false,
    };
  },

  reduce(state: SongRueckwaertsState, action: Action, ctx: Ctx): SongRueckwaertsState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      if (action.type === "timer.extend") {
        // GM „+15 s" = mehr Zeit UND (solange der Deckel es erlaubt) eine
        // Bonus-Abspielung — genau der „nochmal hören"-Wunsch des Publikums.
        const abspielplan =
          state.abspielplan.length < RB_MAX_ABSPIELUNGEN
            ? [...state.abspielplan, ctx.clock.now() + RB_GM_REPLAY_VORLAUF_MS]
            : state.abspielplan;
        return { ...state, endsAt: state.endsAt + action.ms, abspielplan };
      }
      // timer.shift (Pause/Resume): alle Anker inkl. Abspielplan verschieben.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        endsAt: state.endsAt + action.ms,
        abspielplan: state.abspielplan.map((t) => t + action.ms),
      };
    }

    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    // Antwort-Lock: die erste Antwort zählt, Umentscheiden gibt es nicht.
    if (state.answers[action.playerId] !== undefined) return state;
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

  tick(state: SongRueckwaertsState, ctx: Ctx): SongRueckwaertsState {
    if (state.finished) return state;
    if (ctx.clock.now() >= state.endsAt || alleBeantwortet(state)) {
      return { ...state, finished: true };
    }
    return state;
  },

  onDisconnect(state: SongRueckwaertsState, _p: PlayerId, _ctx: Ctx): SongRueckwaertsState {
    return state; // Standard-AFK-Regel: letzter Stand zählt, keine Strafe
  },

  onReconnect(state: SongRueckwaertsState, _p: PlayerId, _ctx: Ctx): SongRueckwaertsState {
    return state;
  },

  viewFor(state: SongRueckwaertsState, role: Role, player?: PlayerId): unknown {
    const basis = {
      questionId: state.questionId,
      schwierigkeit: state.schwierigkeit,
      options: state.optionen,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      timerMs: state.timerMs,
      abspielplan: state.abspielplan,
      maxAbspielungen: RB_MAX_ABSPIELUNGEN,
      answeredCount: Object.keys(state.answers).length,
      eingeloggt: state.players.filter((p) => state.answers[p] !== undefined),
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    // Auflösung erst NACH finished — Titel/Artist/correctIndex leaken NIE vorher.
    const aufloesung = state.finished
      ? {
          correctIndex: state.correctIndex,
          titel: state.titel,
          artist: state.artist,
          jahr: state.jahr,
          erklaerung: `„${state.titel}" von ${state.artist} (${state.jahr}) — vorwärts klingt's besser.`,
          perPlayer: state.players.map((p) => {
            const a = state.answers[p];
            return {
              playerId: p,
              choice: a?.choice ?? null,
              correct: a !== undefined && a.choice === state.correctIndex,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      return {
        ...basis,
        correctIndex: state.correctIndex,
        titel: state.titel,
        artist: state.artist,
        jahr: state.jahr,
        aufloesung,
      };
    }
    if (role === "player") {
      const a = player ? state.answers[player] : undefined;
      return { ...basis, yourChoice: a?.choice ?? null, aufloesung };
    }
    // Screen: Medien-URLs NUR hier (die URLs tragen die Song-Id — am Handy
    // wären sie ein Spick-Kanal). Vorwärts-Intro erst mit der Auflösung.
    return {
      ...basis,
      medien: {
        rueckwaertsUrl: state.medien.rueckwaerts5s,
        introUrl: state.finished ? state.medien.intro5s : null,
      },
      aufloesung,
    };
  },

  isFinished(state: SongRueckwaertsState): boolean {
    return state.finished;
  },

  scores(state: SongRueckwaertsState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  outcomes(state: SongRueckwaertsState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const a = state.answers[p];
      result[p] =
        a === undefined
          ? { correct: null }
          : { correct: a.choice === state.correctIndex, nachMs: a.nachMs };
    }
    return result;
  },
};
