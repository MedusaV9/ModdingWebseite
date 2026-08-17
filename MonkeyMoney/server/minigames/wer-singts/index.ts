// „Wer singt's?" (wer-singts, Musik-Welle): Musik-WISSENS-Quiz ohne Audio und
// ohne Liedtexte. Pro Beat senkt sich eine Schallplatten-Karte mit einem
// weltbekannten Song-TITEL + Jahr-Hinweis — gefragt ist der INTERPRET aus 4
// artgleichen Optionen (gleiche Ära/gleiches Genre, wsBaueOptionen).
//
// ABLAUF pro Beat (roundBased, Beat-Zahl = Engine-Fragen der Runde):
//   auflegen (2,5 s: Platte senkt sich, Titel + Jahr lesen — Optionen ZU)
//   → raten (12 s × timerFaktor: ALLE antworten gleichzeitig, MC-4,
//     erste Antwort zählt, Speed-Bonus obendrauf)
//   → aufdeckung (6 s: die Platte dreht sich zum Interpreten).
// WERTUNG: richtig = WS_WERT[bekanntheit] + speedBonus (shared/money.ts),
// falsch/keine Antwort = 0 — kein Streak (meta), die Beats werden schwerer
// (wsWaehleBeats staffelt nach Bekanntheit).
// FAKTEN: eingebauter 60+-Pool + Song-Pack-Zusatzfragen (meta.wuenschtSongs,
// Muster Telegramm — bis zur Hälfte der Beats, wsFaktenAusSongs dedupliziert).
// POOL-INTEGRITÄTS-WÄCHTER: init wirft, wenn wsPoolFehler den eingebauten
// Pool bemängelt (Titel doppelt = Mehrdeutigkeit!) — kaputte Pack-Einträge
// werden still verworfen. EDGE-CASES: Disconnect = AFK-Standard (keine
// Strafe, letzter Stand zählt); sind ALLE Spieler offline, rechnet der Beat
// sofort ab (keine Antwort = 0) — die Show wartet nicht.
import type { ContentSlice } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import { speedBonus } from "../../../shared/money";
import type { MvSong } from "../../../shared/minigames/musikvideo-raten.meta";
import {
  WER_SINGTS_META,
  WS_AUFDECKUNG_MS,
  WS_AUFLEGEN_MS,
  WS_FAKTEN_POOL,
  WS_RATEN_MS,
  WS_WERT,
  wsBaueOptionen,
  wsFaktenAusSongs,
  wsPoolFehler,
  wsWaehleBeats,
  type WerSingtsAction,
  type WsFakt,
} from "../../../shared/minigames/wer-singts.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

/** Erweiterter ContentSlice — Song-Pack optional (Muster Telegramm). */
export interface WerSingtsSlice extends ContentSlice {
  /** Song-Pack (songs.json) — valide Einträge werden Zusatz-Fragen. */
  songs?: MvSong[];
}

/** Ein Beat = ein Fakt + 4 Interpret-Optionen (answer bis Aufdeckung geheim). */
export interface WsBeat {
  fakt: WsFakt;
  optionen: string[];
  answer: number;
}

export type WsPhase = "auflegen" | "raten" | "aufdeckung";

/** Öffentlicher Aufdeckungs-Eintrag (Platten-Regal + Runden-Bilanz). */
export interface WsHistorieEintrag {
  beatNr: number;
  titel: string;
  artist: string;
  jahr: number | null;
  genre: WsFakt["genre"];
  ausSongPack: boolean;
  correctIndex: number;
  richtige: string[];
  falsche: string[];
  wert: number;
}

export interface WerSingtsState {
  players: PlayerId[];
  beats: WsBeat[];
  beatIndex: number;
  phase: WsPhase;
  phaseStartetAt: number;
  phaseEndetAt: number;
  timerFaktor: number;
  startedAt: number;
  /** Antworten des AKTUELLEN Beats — erste Antwort zählt (Antwort-Lock). */
  antworten: Record<string, { choice: number; nachMs: number }>;
  /** Kumulierte Runden-Deltas = scores() (Grundwert + Speed-Bonus je Treffer). */
  deltas: Record<string, number>;
  richtigZaehler: Record<string, number>;
  beteiligtZaehler: Record<string, number>;
  letzteAntwort: Record<string, number>;
  historie: WsHistorieEintrag[];
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<WerSingtsAction> | GmAction;

function beat(state: WerSingtsState): WsBeat {
  return state.beats[state.beatIndex];
}

function ratenFenster(state: WerSingtsState): number {
  return Math.round(WS_RATEN_MS * state.timerFaktor);
}

/** Beat aufstellen: die Platte senkt sich (Titel + Jahr, Optionen noch zu). */
function starteBeat(state: WerSingtsState, beatIndex: number, now: number): WerSingtsState {
  return {
    ...state,
    beatIndex,
    antworten: {},
    phase: "auflegen",
    phaseStartetAt: now,
    phaseEndetAt: now + WS_AUFLEGEN_MS,
  };
}

function starteRaten(state: WerSingtsState, now: number): WerSingtsState {
  return {
    ...state,
    phase: "raten",
    phaseStartetAt: now,
    phaseEndetAt: now + ratenFenster(state),
  };
}

/** Beat abrechnen: richtig = Grundwert (Bekanntheit) + Speed-Bonus, sonst 0. */
function werteAus(state: WerSingtsState, now: number): WerSingtsState {
  const b = beat(state);
  const wert = WS_WERT[b.fakt.schwierigkeit];
  const deltas = { ...state.deltas };
  const richtigZaehler = { ...state.richtigZaehler };
  const beteiligtZaehler = { ...state.beteiligtZaehler };
  const richtige: string[] = [];
  const falsche: string[] = [];
  for (const p of state.players) {
    const a = state.antworten[p];
    if (a === undefined) continue;
    beteiligtZaehler[p] = (beteiligtZaehler[p] ?? 0) + 1;
    if (a.choice === b.answer) {
      deltas[p] = (deltas[p] ?? 0) + wert + speedBonus(wert, a.nachMs, ratenFenster(state));
      richtigZaehler[p] = (richtigZaehler[p] ?? 0) + 1;
      richtige.push(p);
    } else {
      falsche.push(p);
    }
  }
  return {
    ...state,
    deltas,
    richtigZaehler,
    beteiligtZaehler,
    phase: "aufdeckung",
    phaseStartetAt: now,
    phaseEndetAt: now + WS_AUFDECKUNG_MS,
    historie: [
      ...state.historie,
      {
        beatNr: state.beatIndex + 1,
        titel: b.fakt.titel,
        artist: b.fakt.artist,
        jahr: b.fakt.jahr,
        genre: b.fakt.genre,
        ausSongPack: b.fakt.genre === "song-pack",
        correctIndex: b.answer,
        richtige,
        falsche,
        wert,
      },
    ],
  };
}

export const werSingtsPlugin: MinigamePlugin<WerSingtsState, WerSingtsAction> = {
  meta: WER_SINGTS_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): WerSingtsState {
    // Pool-Integritäts-Wächter: ein kaputter eingebauter Pool (Titel doppelt,
    // Jahr absurd, zu wenige Interpreten) darf NIE eine Show erreichen.
    const poolFehler = wsPoolFehler(WS_FAKTEN_POOL);
    if (poolFehler.length > 0) {
      throw new Error(`wer-singts: Fakten-Pool kaputt — ${poolFehler.join(" · ")}`);
    }
    const slice = content as WerSingtsSlice;
    const now = ctx.clock.now();

    // Song-Pack-Zusatzfragen (Slice vor ctx.songs — Konvention shared/songs.ts);
    // wsFaktenAusSongs verwirft kaputte Einträge + Titel-Dubletten still.
    const packFakten = wsFaktenAusSongs(
      slice.songs ?? (ctx.songs?.songs as MvSong[] | undefined) ?? [],
    );

    // Beat-Zahl = Engine-Fragen der Runde (Muster Telegramm, contentKind none).
    const beatZahl = Math.max(1, content.questions.length);
    const fakten = wsWaehleBeats(beatZahl, packFakten, ctx.rng);
    const alleFakten = [...WS_FAKTEN_POOL, ...packFakten];
    const beats: WsBeat[] = fakten.map((fakt) => {
      const { optionen, answer } = wsBaueOptionen(fakt, alleFakten, ctx.rng);
      return { fakt, optionen, answer };
    });

    const basis: WerSingtsState = {
      players,
      beats,
      beatIndex: 0,
      phase: "auflegen",
      phaseStartetAt: now,
      phaseEndetAt: now + WS_AUFLEGEN_MS,
      timerFaktor: content.mods?.timerFaktor ?? 1,
      startedAt: now,
      antworten: {},
      deltas: {},
      richtigZaehler: {},
      beteiligtZaehler: {},
      letzteAntwort: {},
      historie: [],
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
    return starteBeat(basis, 0, now);
  },

  reduce(state: WerSingtsState, action: Action, _ctx: Ctx): WerSingtsState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // timer.extend verlängert die Phase; timer.shift (Pause) schiebt ALLES.
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        phaseStartetAt:
          action.type === "timer.shift" ? state.phaseStartetAt + action.ms : state.phaseStartetAt,
        phaseEndetAt: state.phaseEndetAt + action.ms,
      };
    }
    if (state.finished) return state;
    if (action.action.type !== "answer") return state;
    if (state.phase !== "raten") return state;
    const p = action.playerId;
    if (!state.players.includes(p)) return state;
    if (state.antworten[p] !== undefined) return state; // erste Antwort zählt
    const choice = action.action.choice;
    if (choice < 0 || choice >= beat(state).optionen.length) return state;
    // Spätantwort: Server-Empfangszeit zählt, +Gnadenfenster, danach verworfen.
    if (action.atServerTime > state.phaseEndetAt + SPAETANTWORT_GNADE_MS) return state;
    const nachMs = Math.max(0, action.atServerTime - state.phaseStartetAt);
    return {
      ...state,
      antworten: { ...state.antworten, [p]: { choice, nachMs } },
      letzteAntwort: { ...state.letzteAntwort, [p]: nachMs },
    };
  },

  tick(state: WerSingtsState, ctx: Ctx): WerSingtsState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "auflegen") {
      if (now >= state.phaseEndetAt) return starteRaten(state, now);
      return state;
    }
    if (state.phase === "raten") {
      const online = state.players.filter((p) => state.connected[p]);
      const alleFertig = online.length > 0 && online.every((p) => state.antworten[p] !== undefined);
      // Alle offline ⇒ sofort abrechnen (keine Antwort = 0) — die Show läuft.
      if (now >= state.phaseEndetAt || alleFertig || online.length === 0) {
        return werteAus(state, now);
      }
      return state;
    }
    // aufdeckung:
    if (now >= state.phaseEndetAt) {
      const beatIndex = state.beatIndex + 1;
      if (beatIndex >= state.beats.length) return { ...state, finished: true };
      return starteBeat(state, beatIndex, now);
    }
    return state;
  },

  onDisconnect(state: WerSingtsState, p: PlayerId, _ctx: Ctx): WerSingtsState {
    // AFK-Standard: keine Strafe — der Beat läuft weiter, die abgegebene
    // Antwort bleibt gültig (Abrechnung, wenn alle ONLINE-Spieler fertig sind).
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: WerSingtsState, p: PlayerId, _ctx: Ctx): WerSingtsState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: WerSingtsState, role: Role, player?: PlayerId): unknown {
    const b = beat(state);
    const inAufdeckung = state.phase === "aufdeckung";
    const basis = {
      questionId: `ws-${state.beatIndex + 1}`,
      beatNr: state.beatIndex + 1,
      beatTotal: state.beats.length,
      phase: state.phase,
      endsAt: state.phaseEndetAt,
      timerMs:
        state.phase === "auflegen"
          ? WS_AUFLEGEN_MS
          : state.phase === "raten"
            ? ratenFenster(state)
            : WS_AUFDECKUNG_MS,
      // Die Platte ist PUBLIC: Titel + Jahr + Genre-Chip + Grundwert.
      titel: b.fakt.titel,
      jahr: b.fakt.jahr,
      genre: b.fakt.genre,
      ausSongPack: b.fakt.genre === "song-pack",
      schwierigkeit: b.fakt.schwierigkeit,
      wert: WS_WERT[b.fakt.schwierigkeit],
      // Optionen erst AB dem Raten (Screen rät mit) — der richtige Index und
      // der INTERPRET bleiben bis zur Aufdeckung geheim (View-Leak-Wache).
      // Feldname `options`: der GENERISCHE answer/choice-Draht der Bots
      // (tools/bots) liest genau dieses Feld — Design-Vorgabe der v2-Welle.
      options: state.phase === "raten" || inAufdeckung ? b.optionen : null,
      artist: inAufdeckung ? b.fakt.artist : null,
      answeredCount: Object.keys(state.antworten).length,
      spielerZahl: state.players.length,
      beat: inAufdeckung ? (state.historie.at(-1) ?? null) : null,
      historie: state.historie.slice(-4),
      deltas: state.deltas,
      finished: state.finished,
    };
    const aufloesung = state.finished
      ? {
          correctIndex: state.historie.at(-1)?.correctIndex ?? null,
          erklaerung:
            "Wer singt's? — richtig zahlt den Bekanntheits-Wert plus Speed-Bonus; die Platte kennt nur EIN Original.",
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: (state.richtigZaehler[p] ?? 0) * 2 > (state.beteiligtZaehler[p] ?? 0),
            delta: state.deltas[p] ?? 0,
            treffer: state.richtigZaehler[p] ?? 0,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Interpret + richtige Option + Antworten IMMER.
      return {
        ...basis,
        artist: b.fakt.artist,
        options: b.optionen,
        correctIndex: b.answer,
        antworten: state.antworten,
        aufloesung,
      };
    }
    if (role === "player") {
      return {
        ...basis,
        yourChoice: player !== undefined ? (state.antworten[player]?.choice ?? null) : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: WerSingtsState): boolean {
    return state.finished;
  },

  /** Runden-Summe (roundBased: EINE Buchung am Ende — nur Bank, nie negativ). */
  scores(state: WerSingtsState): Record<PlayerId, number> {
    const result: Record<PlayerId, number> = {};
    for (const p of state.players) result[p] = state.deltas[p] ?? 0;
    return result;
  },

  /** Awards/Auto-GM: mehrheitlich getroffene Beats = „richtig". */
  outcomes(state: WerSingtsState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const beteiligt = state.beteiligtZaehler[p] ?? 0;
      if (beteiligt === 0) {
        result[p] = { correct: null };
        continue;
      }
      result[p] = {
        correct: (state.richtigZaehler[p] ?? 0) * 2 > beteiligt,
        nachMs: state.letzteAntwort[p],
      };
    }
    return result;
  },
};
