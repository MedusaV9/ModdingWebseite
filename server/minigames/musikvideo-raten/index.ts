// „Stummfilm-Studio" (musikvideo-raten, Musik-Welle): 3-s-Musikvideo-Clip
// läuft STUMM auf dem Screen — alle raten gleichzeitig aus 4 Optionen
// (Titel + Artist). Beat-Dramaturgie pro Song:
//   STUMM (12 s, Clip im Loop)  → voller Wert W für Richtige
//   TON   (8 s, ms500-Schnipsel) → RETTUNGSSTUFE: nur wer im Stumm-Durchlauf
//         NICHT geantwortet hat, darf noch — für W/2 (Mut wird belohnt:
//         wer stumm falsch lag, ist gesperrt wie im Pixel-Dschungel)
//   AUFDECKUNG (7 s)             → Clip MIT intro5s-Ton + Money-Regen
// Songs kommen aus dem Song-Pack (songs.json, Vertrag im Meta-Kopf) über den
// erweiterten ContentSlice; die 4 Optionen baut das Plugin deterministisch
// aus den ÜBRIGEN Pack-Songs (Rng injiziert). Der Beat-Wert W folgt der
// Schwierigkeit der Slot-Frage (Playlist-Geldkurve bleibt erhalten).
// VERFÜGBARKEIT: ohne einen einzigen video3s-Song meldet sich das Format
// nicht-verfügbar — init() fällt auf eine sofort beendete 0-Punkte-Runde
// zurück (kein Crash, die Show läuft weiter). Songs ohne ms500 überspringen
// die Rettungsstufe. Kein Streak/Speed — die Zwei-Stufen-Wertung ist die
// eigene Ökonomie dieses Formats.
import type { ContentSlice } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  MUSIKVIDEO_RATEN_META,
  MV_AUFDECKUNG_MS,
  MV_STUMM_MS,
  MV_TON_MS,
  mvBaueOptionen,
  mvMediaUrl,
  mvRettungsWert,
  mvSpielbar,
  mvTonReferenz,
  type MusikvideoRatenAction,
  type MvSong,
} from "../../../shared/minigames/musikvideo-raten.meta";
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

/** Erweiterter ContentSlice: das Song-Pack (songs.json) — der Song-Loader/
 * die Engine reicht es beim init() mit rein; Unit-Tests/Bot-Harness ebenso. */
export interface MusikvideoSlice extends ContentSlice {
  songs?: MvSong[];
}

/** Ein Beat = ein Song mit fertig gebauten Optionen (answer bleibt geheim!). */
export interface MvBeat {
  songId: string;
  titel: string;
  artist: string;
  videoUrl: string; // video3s — stumm geloopt (Screen)
  tonUrl: string | null; // ms500 — Rettungsstufe (null ⇒ Stufe entfällt)
  introUrl: string | null; // intro5s — Auflösungs-Ton
  optionen: string[];
  answer: number;
  wert: number; // W dieses Beats (aus der Slot-Frage-Schwierigkeit)
}

/** Öffentlicher Aufdeckungs-Eintrag (Screen-Ticker + Runden-Bilanz). */
export interface MvHistorieEintrag {
  songId: string;
  titel: string;
  artist: string;
  answer: number;
  wert: number;
  stummRichtig: string[];
  tonRichtig: string[];
  falsch: string[];
}

export interface MusikvideoRatenState {
  players: PlayerId[];
  beats: MvBeat[];
  beatIndex: number;
  phase: "stumm" | "ton" | "aufdeckung";
  phaseStartetAt: number;
  phaseEndetAt: number;
  timerFaktor: number;
  startedAt: number;
  /** Antworten des AKTUELLEN Beats — erste Antwort zählt (Sperre). */
  antworten: Record<string, { choice: number; pass: "stumm" | "ton"; nachMs: number }>;
  /** Kumulierte Runden-Deltas = scores(). */
  deltas: Record<string, number>;
  richtigZaehler: Record<string, number>;
  beteiligtZaehler: Record<string, number>;
  letzteAntwort: Record<string, number>;
  historie: MvHistorieEintrag[];
  connected: Record<string, boolean>;
  /** Kein Song mit video3s ⇒ Format nicht verfügbar (sofort beendet, 0 MM). */
  nichtVerfuegbar: boolean;
  finished: boolean;
}

type Action = PlayerAction<MusikvideoRatenAction> | GmAction | JokerAction;

function beat(state: MusikvideoRatenState): MvBeat {
  return state.beats[state.beatIndex];
}

function fenster(state: MusikvideoRatenState, basisMs: number): number {
  return Math.round(basisMs * state.timerFaktor);
}

/** Verbundene Spieler OHNE Antwort im aktuellen Beat (Rettungs-Kandidaten). */
function offeneVerbundene(state: MusikvideoRatenState): string[] {
  return state.players.filter((p) => state.connected[p] && state.antworten[p] === undefined);
}

/** STUMM abschließen: Rettungsstufe nur, wenn es Kandidaten UND Ton gibt. */
function nachStumm(state: MusikvideoRatenState, now: number): MusikvideoRatenState {
  const kandidaten = offeneVerbundene(state);
  if (kandidaten.length > 0 && beat(state).tonUrl !== null) {
    return {
      ...state,
      phase: "ton",
      phaseStartetAt: now,
      phaseEndetAt: now + fenster(state, MV_TON_MS),
    };
  }
  return werteBeatAus(state, now);
}

/** Beat auswerten: stumm richtig +W, ton richtig +W/2, falsch/keine 0. */
function werteBeatAus(state: MusikvideoRatenState, now: number): MusikvideoRatenState {
  const b = beat(state);
  const deltas = { ...state.deltas };
  const richtigZaehler = { ...state.richtigZaehler };
  const beteiligtZaehler = { ...state.beteiligtZaehler };
  const stummRichtig: string[] = [];
  const tonRichtig: string[] = [];
  const falsch: string[] = [];

  for (const p of state.players) {
    const a = state.antworten[p];
    if (a === undefined) continue; // keine Antwort: kein Risiko, kein Money
    beteiligtZaehler[p] = (beteiligtZaehler[p] ?? 0) + 1;
    if (a.choice !== b.answer) {
      falsch.push(p);
      continue;
    }
    richtigZaehler[p] = (richtigZaehler[p] ?? 0) + 1;
    if (a.pass === "stumm") {
      deltas[p] = (deltas[p] ?? 0) + b.wert;
      stummRichtig.push(p);
    } else {
      deltas[p] = (deltas[p] ?? 0) + mvRettungsWert(b.wert);
      tonRichtig.push(p);
    }
  }

  return {
    ...state,
    deltas,
    richtigZaehler,
    beteiligtZaehler,
    phase: "aufdeckung",
    phaseStartetAt: now,
    phaseEndetAt: now + MV_AUFDECKUNG_MS,
    historie: [
      ...state.historie,
      {
        songId: b.songId,
        titel: b.titel,
        artist: b.artist,
        answer: b.answer,
        wert: b.wert,
        stummRichtig,
        tonRichtig,
        falsch,
      },
    ],
  };
}

/** Nächster Beat oder Runden-Ende. */
function naechsterBeat(state: MusikvideoRatenState, now: number): MusikvideoRatenState {
  const beatIndex = state.beatIndex + 1;
  if (beatIndex >= state.beats.length) return { ...state, finished: true };
  return {
    ...state,
    beatIndex,
    antworten: {},
    phase: "stumm",
    phaseStartetAt: now,
    phaseEndetAt: now + fenster(state, MV_STUMM_MS),
  };
}

export const musikvideoRatenPlugin: MinigamePlugin<MusikvideoRatenState, MusikvideoRatenAction> = {
  meta: MUSIKVIDEO_RATEN_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): MusikvideoRatenState {
    const slice = content as MusikvideoSlice;
    const now = ctx.clock.now();
    const timerFaktor = content.mods?.timerFaktor ?? 1;
    // Slice-Transport hat Vorrang, dann ctx.songs (Loader-Konvention von
    // shared/songs.ts) — KEIN Fixture-Fallback: ohne video3s-Songs meldet
    // sich das Format nicht-verfügbar (Task-Vorgabe, s. u.).
    const alleSongs = slice.songs ?? (ctx.songs?.songs as MvSong[] | undefined) ?? [];
    const spielbar = alleSongs.filter(mvSpielbar);

    const basis: Omit<MusikvideoRatenState, "beats" | "nichtVerfuegbar" | "finished"> = {
      players,
      beatIndex: 0,
      phase: "stumm",
      phaseStartetAt: now,
      phaseEndetAt: now + Math.round(MV_STUMM_MS * timerFaktor),
      timerFaktor,
      startedAt: now,
      antworten: {},
      deltas: {},
      richtigZaehler: {},
      beteiligtZaehler: {},
      letzteAntwort: {},
      historie: [],
      connected: Object.fromEntries(players.map((p) => [p, true])),
    };

    // NICHT VERFÜGBAR: kein Song mit video3s — sofort beendete 0-Punkte-Runde
    // (die Engine bucht 0 MM und zieht weiter; kein Crash, kein Hänger).
    if (spielbar.length === 0) {
      return { ...basis, beats: [], nichtVerfuegbar: true, finished: true };
    }

    // Song-Auswahl: deterministisch mischen, so viele Beats wie der Abschnitt
    // Fragen hat (mindestens 1) — kein Song doppelt innerhalb der Runde.
    const gemischt = [...spielbar];
    for (let i = gemischt.length - 1; i > 0; i--) {
      const j = ctx.rng.int(i + 1);
      [gemischt[i], gemischt[j]] = [gemischt[j], gemischt[i]];
    }
    const beatZahl = Math.min(gemischt.length, Math.max(1, content.questions.length));
    const beats: MvBeat[] = gemischt.slice(0, beatZahl).map((song, i) => {
      const { optionen, answer } = mvBaueOptionen(alleSongs, song, ctx.rng);
      const ton = mvTonReferenz(song);
      return {
        songId: song.id,
        titel: song.titel,
        artist: song.artist,
        videoUrl: mvMediaUrl(song.medien?.video3s ?? ""),
        tonUrl: ton !== null ? mvMediaUrl(ton) : null,
        introUrl: song.medien?.intro5s ? mvMediaUrl(song.medien.intro5s) : null,
        optionen,
        answer,
        // Beat-Wert folgt der Slot-Frage-Schwierigkeit (Fallback: medium).
        wert: FRAGE_WERTE[content.questions[i]?.difficulty ?? "medium"],
      };
    });

    return { ...basis, beats, nichtVerfuegbar: false, finished: false };
  },

  reduce(state: MusikvideoRatenState, action: Action, _ctx: Ctx): MusikvideoRatenState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      // extend: aktuelle Phase bekommt Luft; shift (Pause): alle Anker wandern.
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        phaseStartetAt:
          action.type === "timer.shift" ? state.phaseStartetAt + action.ms : state.phaseStartetAt,
        phaseEndetAt: state.phaseEndetAt + action.ms,
      };
    }
    if (action.kind === "joker") return state; // Meta deklariert keine Joker-Hooks
    if (state.finished || state.nichtVerfuegbar) return state;
    if (action.action.type !== "answer") return state;
    if (state.phase === "aufdeckung") return state;
    if (action.atServerTime > state.phaseEndetAt) return state;
    const p = action.playerId;
    // Sperre: erste Antwort zählt — wer stumm falsch lag, ist raus (kein
    // Zweitversuch in der Rettungsstufe; Mut-Belohnung des Formats).
    if (state.antworten[p] !== undefined) return state;
    const choice = action.action.choice;
    if (choice < 0 || choice > 3) return state;
    const nachMs = Math.max(0, action.atServerTime - state.phaseStartetAt);
    return {
      ...state,
      antworten: {
        ...state.antworten,
        [p]: { choice, pass: state.phase, nachMs },
      },
      letzteAntwort: { ...state.letzteAntwort, [p]: nachMs },
    };
  },

  tick(state: MusikvideoRatenState, ctx: Ctx): MusikvideoRatenState {
    if (state.finished) return state;
    const now = ctx.clock.now();
    const alleVerbundenenFertig = offeneVerbundene(state).length === 0;

    if (state.phase === "stumm") {
      // Alle (Verbundenen) haben stumm geantwortet ⇒ niemand braucht die
      // Rettungsstufe — direkt zur Aufdeckung. Timeout ⇒ ton (falls sinnvoll).
      if (alleVerbundenenFertig) return werteBeatAus(state, now);
      if (now >= state.phaseEndetAt) return nachStumm(state, now);
      return state;
    }
    if (state.phase === "ton") {
      if (now >= state.phaseEndetAt || alleVerbundenenFertig) return werteBeatAus(state, now);
      return state;
    }
    // aufdeckung:
    if (now >= state.phaseEndetAt) return naechsterBeat(state, now);
    return state;
  },

  onDisconnect(state: MusikvideoRatenState, p: PlayerId, _ctx: Ctx): MusikvideoRatenState {
    // Keine Strafe — der Beat läuft weiter, Offline blockiert kein Early-Finish.
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: MusikvideoRatenState, p: PlayerId, _ctx: Ctx): MusikvideoRatenState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: MusikvideoRatenState, role: Role, player?: PlayerId): unknown {
    if (state.nichtVerfuegbar) {
      return {
        questionId: "mv-nicht-verfuegbar",
        nichtVerfuegbar: true,
        finished: true,
        aufloesung: {
          erklaerung:
            "Stummfilm-Studio braucht Songs mit 3-s-Videoclip (medien.video3s) — das Song-Pack hat (noch) keine.",
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: false,
            delta: 0,
          })),
        },
      };
    }
    const b = beat(state);
    const inAufdeckung = state.phase === "aufdeckung";
    const basis = {
      questionId: b.songId,
      beatNr: state.beatIndex + 1,
      beatTotal: state.beats.length,
      phase: state.phase,
      wert: b.wert,
      rettungsWert: mvRettungsWert(b.wert),
      videoUrl: b.videoUrl,
      // Ton-Schnipsel erst AB der Rettungsstufe (vorher wäre er ein Leak).
      tonUrl: state.phase !== "stumm" ? b.tonUrl : null,
      // intro5s-Ton NUR in der Aufdeckung (die URL trägt die Song-Id).
      introUrl: inAufdeckung ? b.introUrl : null,
      optionen: b.optionen,
      endsAt: state.phaseEndetAt,
      timerMs:
        state.phase === "stumm"
          ? fenster(state, MV_STUMM_MS)
          : state.phase === "ton"
            ? fenster(state, MV_TON_MS)
            : MV_AUFDECKUNG_MS,
      answeredCount: Object.keys(state.antworten).length,
      spielerZahl: state.players.length,
      eingeloggt: state.players.filter((p) => state.antworten[p] !== undefined),
      // Aufdeckung des AKTUELLEN Beats — vorher bleibt answer geheim.
      // (Historie-Einträge entstehen ERST beim Aufdecken — nie ein Vor-Leak.)
      beat: inAufdeckung ? (state.historie.at(-1) ?? null) : null,
      historie: state.historie.slice(-4),
      deltas: state.deltas,
      finished: state.finished,
      nichtVerfuegbar: false,
    };
    const aufloesung = state.finished
      ? {
          erklaerung: "Stumm erkannt = voller Wert, mit Ton gerettet = die Hälfte.",
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: (state.richtigZaehler[p] ?? 0) > 0,
            delta: state.deltas[p] ?? 0,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: die richtige Option + alle Antworten IMMER sichtbar.
      return {
        ...basis,
        correctIndex: b.answer,
        titel: b.titel,
        artist: b.artist,
        antworten: state.antworten,
        aufloesung,
      };
    }
    if (role === "player") {
      const a = player !== undefined ? state.antworten[player] : undefined;
      return {
        ...basis,
        yourChoice: a?.choice ?? null,
        yourPass: a?.pass ?? null,
        // Rettungsstufe: nur wer noch OHNE Antwort ist, darf tippen.
        darfNoch: !inAufdeckung && a === undefined,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: MusikvideoRatenState): boolean {
    return state.finished;
  },

  /** Runden-Summe (roundBased: EINE Buchung am Ende). */
  scores(state: MusikvideoRatenState): Record<PlayerId, number> {
    const result: Record<PlayerId, number> = {};
    for (const p of state.players) result[p] = state.deltas[p] ?? 0;
    return result;
  },

  /** Awards/Auto-GM: mehrheitlich richtige Beats = „richtig". */
  outcomes(state: MusikvideoRatenState): Record<PlayerId, PlayerOutcome> {
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
