// „Der Blitz-DJ" (GAME-DESIGN-Geist §2.12, Musik-Welle): Eskalations-Buzzer-
// Raten über Song-Packs — das ERSTE echte Buzzer-Format (Erstnutzer von
// ctx.buzzer, ARCHITEKTUR „Offene Andock-Punkte").
//
// ABLAUF: intro („Plattenspieler dreht auf", 2 s) → je Stufe: lauschen
// (Snippet 0,1/0,2/0,3/0,5/1,0/5,0 s läuft über den SCREEN, buzzen ab
// Snippet-Start bis 4 s nach Snippet-Ende) → erster Buzz öffnet das
// 280-ms-Sammelfenster, ctx.buzzer.ordne kürt den Rater (Median-RTT-fair,
// Fotofinish-Los) → raten (8 s, NUR der Buzz-Sieger, 4 Optionen) → richtig:
// Song geholt, Wert der Stufe (Verfalls-Treppe im Meta-Kopf); falsch/Timeout:
// SPERRE für den Rest des Songs + 50 MM Strafe ins Jackpot-Glas
// (meta.strafenInsGlas), nächste Stufe. Nach Stufe 6 ohne Sieger: Auflösung
// ohne Gewinner. Läuft ohne Song-Slice mit dem Fixture-Katalog (nie crashen).
//
// BUZZ-EINGÄNGE (zwei Wege, beide fair): das buzz-Socket-Event liefert
// `finalAt` bereits Raum-geclampt; player.action-Buzzes (Client-Renderer)
// liefern `pressedAtServerEst`, das Plugin clampt selbst via
// ctx.buzzer.medianRtt + shared/buzzer.clampBuzz. Armierung: max(finalAt,
// Snippet-Start) — vor dem Snippet gibt es nichts zu hören.
import { clampBuzz, ordneBuzzes, type BuzzKandidat } from "../../../shared/buzzer";
import type { ContentSlice } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import type { Schwierigkeit } from "../../../shared/money";
import {
  SONG_SNIPPET_META,
  SS_INTRO_MS,
  SS_RATE_MS,
  SS_SNIPPET_MS,
  SS_STRAFE_MM,
  SS_STUFEN,
  ssLauschFensterMs,
  ssStufenWert,
  type SongSnippetAction,
} from "../../../shared/minigames/song-snippet.meta";
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

export interface SongSnippetState {
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
  phase: "intro" | "lauschen" | "raten" | "fertig";
  stufe: number; // 0–5
  startedAt: number;
  phaseEndsAt: number;
  /** Anker der aktuellen Lausch-Phase = Snippet-Start = Buzz-Armierung. */
  lauschenStartetAt: number;
  /** Buzzes der AKTUELLEN Stufe: playerId → armiertes finalAt. */
  buzzes: Record<string, number>;
  /** Server-Empfang des ersten Buzz — Anker des 280-ms-Sammelfensters. */
  ersterBuzzAt: number | null;
  /** Für den Rest des Songs gesperrt (Falsch-Buzz/Timeout/Rater-Disconnect). */
  gesperrt: PlayerId[];
  raterId: PlayerId | null;
  /** Der aktuelle Rater gewann das Sammelfenster per Fotofinish-Los. */
  fotofinish: boolean;
  /** Fehlversuche MIT Strafe (choice null = Rate-Timeout). */
  fehlversuche: { playerId: PlayerId; stufe: number; choice: number | null; nachMs: number }[];
  gewinner: { playerId: PlayerId; stufe: number; choice: number; nachMs: number } | null;
  finished: boolean;
}

type Action = PlayerAction<SongSnippetAction> | GmAction;

/** Snippet-URL der Stufe (0–4 = buzz.msXXX, 5 = das volle Intro). */
export function ssSnippetUrl(medien: Song["medien"], stufe: number): string {
  const urls = [
    medien.buzz.ms100,
    medien.buzz.ms200,
    medien.buzz.ms300,
    medien.buzz.ms500,
    medien.buzz.ms1000,
    medien.intro5s,
  ];
  return urls[Math.min(SS_STUFEN - 1, Math.max(0, stufe))];
}

/** Nächste Eskalations-Stufe starten — oder fertig (Treppe/Spieler erschöpft). */
function naechsteStufe(state: SongSnippetState, now: number): SongSnippetState {
  const verbleibend = state.players.filter((p) => !state.gesperrt.includes(p));
  if (state.stufe + 1 >= SS_STUFEN || verbleibend.length === 0) {
    return { ...state, phase: "fertig", finished: true, raterId: null };
  }
  const stufe = state.stufe + 1;
  return {
    ...state,
    phase: "lauschen",
    stufe,
    lauschenStartetAt: now,
    phaseEndsAt: now + ssLauschFensterMs(stufe),
    buzzes: {},
    ersterBuzzAt: null,
    raterId: null,
    fotofinish: false,
  };
}

/** Fehlversuch (falsch/Timeout) verbuchen: Sperre + Strafe + Eskalation. */
function fehlversuch(
  state: SongSnippetState,
  playerId: PlayerId,
  choice: number | null,
  now: number,
): SongSnippetState {
  return naechsteStufe(
    {
      ...state,
      gesperrt: [...state.gesperrt, playerId],
      fehlversuche: [
        ...state.fehlversuche,
        { playerId, stufe: state.stufe, choice, nachMs: Math.max(0, now - state.startedAt) },
      ],
    },
    now,
  );
}

function berechneScores(state: SongSnippetState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  for (const f of state.fehlversuche) result[f.playerId] = -SS_STRAFE_MM;
  if (state.gewinner) {
    result[state.gewinner.playerId] = ssStufenWert(state.schwierigkeit, state.gewinner.stufe);
  }
  return result;
}

export const songSnippetPlugin: MinigamePlugin<SongSnippetState, SongSnippetAction> = {
  meta: SONG_SNIPPET_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): SongSnippetState {
    // Song-Quelle: ContentSlice.songs → ctx.songs → Fixture-Katalog (nie
    // crashen). parseSongs validiert strikt (Zod) und verwirft Ungültiges —
    // ein kaputter/fremder Slice fällt sauber auf die Fixtures zurück.
    const songs = parseSongs(content.songs ?? ctx.songs?.songs);
    const { ziel, optionen, correctIndex } = waehleSongUndOptionen(songs, ctx.rng);
    const now = ctx.clock.now();
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
      phase: "intro",
      stufe: 0,
      startedAt: now,
      phaseEndsAt: now + SS_INTRO_MS,
      lauschenStartetAt: now + SS_INTRO_MS,
      buzzes: {},
      ersterBuzzAt: null,
      gesperrt: [],
      raterId: null,
      fotofinish: false,
      fehlversuche: [],
      gewinner: null,
      finished: false,
    };
  },

  reduce(state: SongSnippetState, action: Action, ctx: Ctx): SongSnippetState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        return { ...state, phase: "fertig", finished: true };
      }
      if (action.type === "timer.extend") {
        // GM „+15 s": das AKTUELLE Fenster wächst (Lauschen ODER Raten).
        return { ...state, phaseEndsAt: state.phaseEndsAt + action.ms };
      }
      // timer.shift (Pause/Resume): ALLE Zeit-Anker gemeinsam verschieben.
      const buzzes: Record<string, number> = {};
      for (const [p, at] of Object.entries(state.buzzes)) buzzes[p] = at + action.ms;
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        phaseEndsAt: state.phaseEndsAt + action.ms,
        lauschenStartetAt: state.lauschenStartetAt + action.ms,
        ersterBuzzAt: state.ersterBuzzAt === null ? null : state.ersterBuzzAt + action.ms,
        buzzes,
      };
    }

    if (state.finished) return state;
    const p = action.playerId;

    if (action.action.type === "buzz") {
      // Buzzen nur im Lausch-Fenster; Frühbuzz (intro) verpufft sanft.
      if (state.phase !== "lauschen") return state;
      if (state.gesperrt.includes(p) || state.buzzes[p] !== undefined) return state;
      if (action.atServerTime > state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
      // finalAt: vom Raum geclampt (buzz-Event) ODER hier via Median-RTT.
      const roh =
        action.action.finalAt ??
        clampBuzz({
          pressedAtServerEst: action.action.pressedAtServerEst ?? action.atServerTime,
          receiveTime: action.atServerTime,
          medianRtt: ctx.buzzer?.medianRtt(p) ?? 0,
        });
      const finalAt = Math.max(state.lauschenStartetAt, roh);
      return {
        ...state,
        buzzes: { ...state.buzzes, [p]: finalAt },
        ersterBuzzAt: state.ersterBuzzAt ?? action.atServerTime,
      };
    }

    // Rate-Antwort: NUR der Buzz-Sieger, nur im Rate-Fenster.
    if (action.action.type !== "answer") return state;
    if (state.phase !== "raten" || state.raterId !== p) return state;
    if (action.atServerTime > state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
    if (action.action.choice === state.correctIndex) {
      return {
        ...state,
        gewinner: {
          playerId: p,
          stufe: state.stufe,
          choice: action.action.choice,
          nachMs: Math.max(0, action.atServerTime - state.startedAt),
        },
        phase: "fertig",
        finished: true,
      };
    }
    return fehlversuch(state, p, action.action.choice, action.atServerTime);
  },

  tick(state: SongSnippetState, ctx: Ctx): SongSnippetState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "intro") {
      if (now < state.phaseEndsAt) return state;
      return {
        ...state,
        phase: "lauschen",
        lauschenStartetAt: now,
        phaseEndsAt: now + ssLauschFensterMs(0),
      };
    }

    if (state.phase === "lauschen") {
      if (state.ersterBuzzAt !== null) {
        // Sammelfenster nach dem ERSTEN Buzz — auch über das Lausch-Ende hinaus.
        const fensterEnde = state.ersterBuzzAt + (ctx.buzzer?.sammelfensterMs ?? 280);
        if (now < fensterEnde) return state;
        const kandidaten: BuzzKandidat[] = Object.entries(state.buzzes).map(
          ([playerId, finalAt]) => ({ playerId, finalAt }),
        );
        if (kandidaten.length === 0) return { ...state, ersterBuzzAt: null }; // defensiv
        const geordnet = ctx.buzzer
          ? ctx.buzzer.ordne(kandidaten)
          : ordneBuzzes(kandidaten, ctx.rng);
        const sieger = geordnet.find((e) => e.rank === 1) ?? geordnet[0];
        return {
          ...state,
          phase: "raten",
          raterId: sieger.playerId as PlayerId,
          fotofinish: sieger.fotofinish,
          phaseEndsAt: now + SS_RATE_MS,
        };
      }
      if (now < state.phaseEndsAt) return state;
      // Niemand gebuzzert ⇒ Eskalation (nächste Stufe) oder Auflösung.
      return naechsteStufe(state, now);
    }

    if (state.phase === "raten") {
      if (now < state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
      // Rate-Timeout = wie falsch (sonst wäre Buzz-und-Schweigen ein Blocker).
      return fehlversuch(state, state.raterId as PlayerId, null, now);
    }

    return state;
  },

  onDisconnect(state: SongSnippetState, p: PlayerId, ctx: Ctx): SongSnippetState {
    // Rater weg ⇒ Sperre + Eskalation, aber OHNE Strafe (kein Fehlversuch).
    if (!state.finished && state.phase === "raten" && state.raterId === p) {
      return naechsteStufe({ ...state, gesperrt: [...state.gesperrt, p] }, ctx.clock.now());
    }
    return state;
  },

  onReconnect(state: SongSnippetState, _p: PlayerId, _ctx: Ctx): SongSnippetState {
    return state;
  },

  viewFor(state: SongSnippetState, role: Role, player?: PlayerId): unknown {
    const timerMs =
      state.phase === "intro"
        ? SS_INTRO_MS
        : state.phase === "raten"
          ? SS_RATE_MS
          : ssLauschFensterMs(state.stufe);
    const basis = {
      questionId: state.questionId,
      phase: state.phase,
      stufe: state.stufe,
      stufenTotal: SS_STUFEN,
      snippetMs: SS_SNIPPET_MS[state.stufe],
      schwierigkeit: state.schwierigkeit,
      aktuellerWert: ssStufenWert(state.schwierigkeit, state.stufe),
      startedAt: state.startedAt,
      lauschenStartetAt: state.lauschenStartetAt,
      endsAt: state.phaseEndsAt,
      timerMs,
      raterId: state.raterId,
      fotofinish: state.fotofinish,
      gesperrt: state.gesperrt,
      // BEWUSST buzzCount statt answeredCount: die Auto-GM-Heuristik
      // (engine.tick, „+10 s wenn <50 % geantwortet und <4 s übrig") duck-typt
      // auf endsAt+answeredCount — Buzzes sind aber KEINE Antworten (Schweigen
      // ist hier Design: Eskalation!), und Intro (2 s) + Lausch-Fenster
      // (4,1 s) liegen immer unter 4 s Rest ⇒ sie würde JEDE Blitz-DJ-Frage
      // sofort um 10 tote Sekunden strecken (im Browser-Playtest gefunden).
      buzzCount: Object.keys(state.buzzes).length,
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
          erklaerung: `„${state.titel}" von ${state.artist} (${state.jahr}).`,
          gewinnerId: state.gewinner?.playerId ?? null,
          gewinnerStufe: state.gewinner?.stufe ?? null,
          optionen: state.optionen,
          perPlayer: state.players.map((p) => {
            const fehl = state.fehlversuche.find((f) => f.playerId === p);
            const istGewinner = state.gewinner?.playerId === p;
            return {
              playerId: p,
              choice: istGewinner ? state.gewinner!.choice : (fehl?.choice ?? null),
              stufe: istGewinner ? state.gewinner!.stufe : (fehl?.stufe ?? null),
              correct: istGewinner,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Song + Lösung IMMER.
      return {
        ...basis,
        optionen: state.optionen,
        correctIndex: state.correctIndex,
        titel: state.titel,
        artist: state.artist,
        jahr: state.jahr,
        aufloesung,
      };
    }
    if (role === "player") {
      const duBistRater = player !== undefined && state.raterId === player;
      return {
        ...basis,
        duBistRater,
        duGesperrt: player !== undefined && state.gesperrt.includes(player),
        deinBuzz: player !== undefined && state.buzzes[player] !== undefined,
        // MC-Optionen NUR für den Rater (options-Feld triggert die generische
        // Bot-Antwort und den Optionen-Screen am Handy erst NACH dem Buzz-Sieg).
        ...(duBistRater && state.phase === "raten" ? { options: state.optionen } : {}),
        buzzAktiv:
          state.phase === "lauschen" &&
          player !== undefined &&
          !state.gesperrt.includes(player) &&
          state.buzzes[player] === undefined,
        aufloesung,
      };
    }
    // Screen: Optionen fürs Mitraten + Medien-URLs (NUR hier — die URLs tragen
    // die Song-Id, am Handy wären sie ein Spick-Kanal).
    return {
      ...basis,
      optionen: state.optionen,
      medien: {
        snippetUrl: ssSnippetUrl(state.medien, state.stufe),
        introUrl: state.finished ? state.medien.intro5s : null,
      },
      aufloesung,
    };
  },

  isFinished(state: SongSnippetState): boolean {
    return state.finished;
  },

  scores(state: SongSnippetState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  outcomes(state: SongSnippetState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) result[p] = { correct: null };
    for (const f of state.fehlversuche) {
      result[f.playerId] = { correct: false, nachMs: f.nachMs };
    }
    if (state.gewinner) {
      result[state.gewinner.playerId] = { correct: true, nachMs: state.gewinner.nachMs };
    }
    return result;
  },
};
