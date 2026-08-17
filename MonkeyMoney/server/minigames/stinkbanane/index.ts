// Referenz-Minigame „Die Stinkbanane" (GAME-DESIGN §2.6): Pass the Bomb.
// Nur der Halter sieht die Frage (MC-4, 8 s); richtig = Banane wandert im Kreis,
// falsch/zu langsam = festhalten + neue Frage. Platzt sie (VERDECKTER
// Zufalls-Timer 45–75 s via ctx.rng), zahlt der Halter 500 MM ins Jackpot-Glas
// und trägt Matsch. 2 Durchgänge pro Runde.
//
// Edge-Cases (Design): Halter-Disconnect ⇒ Banane wandert straffrei weiter.
// Antwort mit Server-Empfang VOR dem Explosions-Tick zählt noch. 2 Spieler =
// Ping-Pong. Alle offline ⇒ Banane liegt am Boden, Explosion trifft niemanden.
//
// meta.roundBased=true: EIN init() pro Runde mit allen Runden-Fragen im Slice;
// das Plugin rotiert zyklisch, falls die Kette länger wird als der Vorrat.
// meta.strafenInsGlas=true: die Engine bucht die −500 der Explosion ins globale
// Jackpot-Glas — state.jackpotGlas hier ist nur die Anzeige fürs Glas-Overlay.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  SB_DURCHGAENGE,
  SB_EXPLOSION_MM,
  SB_FRAGE_MS,
  SB_SPLATTER_MS,
  SB_WEITERGABE_MM,
  SB_ZUENDSCHNUR_MAX_MS,
  SB_ZUENDSCHNUR_MIN_MS,
  STINKBANANE_META,
  type SbHistorieEintrag,
  type StinkbananeAction,
} from "../../../shared/minigames/stinkbanane.meta";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export interface StinkbananeState {
  players: PlayerId[]; // Sitzkreis = Join-Reihenfolge
  questions: Question[];
  /** Maßanzug: eigene Frage pro Spieler — kommt dran, wenn ER die Banane hält
   * (einmalig; nach Antwort/Timeout verbraucht). */
  fragenProSpieler: Record<string, Question>;
  frageIndex: number;
  startedAt: number;
  phase: "ticken" | "splatter";
  durchgang: number; // 1-basiert
  holder: PlayerId | null; // null = alle offline, Banane liegt am Boden
  /** GEHEIM: Explosions-Zeitpunkt — verlässt den Server nur Richtung GM-Spickzettel. */
  zuendschnurEndetAt: number;
  durchgangStartetAt: number; // öffentlich: Client eskaliert Ticken/Spannung lokal
  frageEndsAt: number;
  splatterEndetAt: number | null;
  connected: Record<string, boolean>;
  weitergaben: Record<string, number>; // je +150 MM
  explodiert: Record<string, number>; // je −500 MM ins Glas
  matsch: string[]; // Matsch-Spritzer-Träger (Avatar-Deko bis Match-Ende)
  trommel: Record<string, number>; // kosmetischer ANFEUERN-Zähler
  historie: SbHistorieEintrag[];
  jackpotGlas: number;
  finished: boolean;
}

type Action = PlayerAction<StinkbananeAction> | GmAction;

function verbundene(state: StinkbananeState): PlayerId[] {
  return state.players.filter((p) => state.connected[p]);
}

/** Nächster verbundener Spieler im Kreis NACH `von` (2 Spieler ⇒ Ping-Pong). */
function naechsterVerbundener(state: StinkbananeState, von: PlayerId): PlayerId | null {
  const i = state.players.indexOf(von);
  for (let schritt = 1; schritt <= state.players.length; schritt++) {
    const kandidat = state.players[(i + schritt) % state.players.length];
    if (kandidat !== von && state.connected[kandidat]) return kandidat;
  }
  return null;
}

function neueZuendschnur(now: number, ctx: Ctx): number {
  const spanne = SB_ZUENDSCHNUR_MAX_MS - SB_ZUENDSCHNUR_MIN_MS;
  return now + SB_ZUENDSCHNUR_MIN_MS + ctx.rng.int(spanne + 1);
}

function aktuelleFrage(state: StinkbananeState): Question {
  // Maßanzug: hält ein zugewiesener Spieler die Banane, ist SEINE Frage dran.
  if (state.holder !== null && state.fragenProSpieler[state.holder] !== undefined) {
    return state.fragenProSpieler[state.holder];
  }
  return state.questions[state.frageIndex % state.questions.length];
}

function mitNeuerFrage(state: StinkbananeState, ab: number): StinkbananeState {
  return { ...state, frageIndex: state.frageIndex + 1, frageEndsAt: ab + SB_FRAGE_MS };
}

/** Maßanzug-Frage des Spielers ist beantwortet/verpasst ⇒ verbraucht. */
function verbraucheZuweisung(state: StinkbananeState, p: string): StinkbananeState {
  if (state.fragenProSpieler[p] === undefined) return state;
  const rest = { ...state.fragenProSpieler };
  delete rest[p];
  return { ...state, fragenProSpieler: rest };
}

function protokolliere(
  state: StinkbananeState,
  eintrag: Omit<SbHistorieEintrag, "atMs" | "durchgang">,
  atAbsolutMs: number,
): StinkbananeState {
  return {
    ...state,
    historie: [
      ...state.historie,
      { ...eintrag, atMs: atAbsolutMs - state.startedAt, durchgang: state.durchgang },
    ],
  };
}

/** Netto-Scores: Weitergaben × 150 − Explosionen × 500 (keine Streak, kein Speed). */
function berechneScores(state: StinkbananeState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    result[p] =
      (state.weitergaben[p] ?? 0) * SB_WEITERGABE_MM - (state.explodiert[p] ?? 0) * SB_EXPLOSION_MM;
  }
  return result;
}

export const stinkbananePlugin: MinigamePlugin<StinkbananeState, StinkbananeAction> = {
  meta: STINKBANANE_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): StinkbananeState {
    if (content.questions.length === 0) throw new Error("stinkbanane: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    const holder = players[ctx.rng.int(players.length)]; // Start bei einem Zufallsspieler
    return {
      players,
      questions: content.questions,
      fragenProSpieler: content.mods?.fragenProSpieler ?? {},
      frageIndex: 0,
      startedAt: now,
      phase: "ticken",
      durchgang: 1,
      holder,
      zuendschnurEndetAt: neueZuendschnur(now, ctx),
      durchgangStartetAt: now,
      frageEndsAt: now + SB_FRAGE_MS,
      splatterEndetAt: null,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      weitergaben: {},
      explodiert: {},
      matsch: [],
      trommel: {},
      historie: [],
      jackpotGlas: 0,
      finished: false,
    };
  },

  reduce(state: StinkbananeState, action: Action, ctx: Ctx): StinkbananeState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      if (action.type === "timer.extend") {
        // GM „+15 s": Frage-Timer UND Zündschnur bekommen Luft.
        return {
          ...state,
          frageEndsAt: state.frageEndsAt + action.ms,
          zuendschnurEndetAt: state.zuendschnurEndetAt + action.ms,
        };
      }
      // timer.shift (Pause): ALLE Deadlines wandern — die Banane tickt nicht in der Pause.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        frageEndsAt: state.frageEndsAt + action.ms,
        zuendschnurEndetAt: state.zuendschnurEndetAt + action.ms,
        durchgangStartetAt: state.durchgangStartetAt + action.ms,
        splatterEndetAt: state.splatterEndetAt === null ? null : state.splatterEndetAt + action.ms,
      };
    }
    if (state.finished) return state;

    if (action.action.type === "anfeuern") {
      // Kosmetik-Trommel: nur Nicht-Halter, triggert Sounds/Konfetti am Screen.
      if (action.playerId === state.holder) return state;
      return {
        ...state,
        trommel: {
          ...state.trommel,
          [action.playerId]: (state.trommel[action.playerId] ?? 0) + 1,
        },
      };
    }

    // MC-4-Antwort: NUR der Halter, nur solange die Banane tickt.
    if (state.phase !== "ticken" || action.playerId !== state.holder) return state;
    // Explosions-Edge: Server-Empfang VOR dem Explosions-Tick zählt noch.
    if (action.atServerTime >= state.zuendschnurEndetAt) return state;
    // Zu langsam (8-s-Fenster vorbei): der Tick regelt „festhalten + neue Frage".
    if (action.atServerTime > state.frageEndsAt) return state;

    const frage = aktuelleFrage(state);
    // Maßanzug-Frage ist mit dieser Antwort verbraucht (richtig ODER falsch).
    const basis = verbraucheZuweisung(state, action.playerId);
    if (action.action.choice === frage.answer) {
      const naechster = naechsterVerbundener(basis, action.playerId);
      let s: StinkbananeState = {
        ...basis,
        weitergaben: {
          ...basis.weitergaben,
          [action.playerId]: (basis.weitergaben[action.playerId] ?? 0) + 1,
        },
        holder: naechster ?? basis.holder, // niemand da ⇒ festhalten (Edge: alle offline)
      };
      s = protokolliere(
        s,
        { typ: "weitergabe", von: action.playerId, zu: s.holder ?? undefined },
        action.atServerTime,
      );
      return mitNeuerFrage(s, ctx.clock.now());
    }
    // Falsch: festhalten, neue Frage.
    const s = protokolliere(basis, { typ: "falsch", von: action.playerId }, action.atServerTime);
    return mitNeuerFrage(s, ctx.clock.now());
  },

  tick(state: StinkbananeState, ctx: Ctx): StinkbananeState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "splatter") {
      if (state.splatterEndetAt !== null && now >= state.splatterEndetAt) {
        // Nächster Durchgang: neuer Zufalls-Halter, frische verdeckte Zündschnur.
        const kandidaten = verbundene(state);
        const holder = kandidaten.length > 0 ? kandidaten[ctx.rng.int(kandidaten.length)] : null;
        let s: StinkbananeState = {
          ...state,
          phase: "ticken",
          durchgang: state.durchgang + 1,
          holder,
          zuendschnurEndetAt: neueZuendschnur(now, ctx),
          durchgangStartetAt: now,
          splatterEndetAt: null,
        };
        s = protokolliere(s, { typ: "durchgang-start", von: holder ?? "niemand" }, now);
        return mitNeuerFrage(s, now);
      }
      return state;
    }

    // Phase "ticken":
    if (now >= state.zuendschnurEndetAt) {
      // EXPLOSION! Der Halter zahlt 500 MM ins Jackpot-Glas + Matsch bis Match-Ende.
      const opfer = state.holder !== null && state.connected[state.holder] ? state.holder : null;
      let s: StinkbananeState = { ...state };
      if (opfer !== null) {
        s = {
          ...s,
          explodiert: { ...s.explodiert, [opfer]: (s.explodiert[opfer] ?? 0) + 1 },
          matsch: s.matsch.includes(opfer) ? s.matsch : [...s.matsch, opfer],
          jackpotGlas: s.jackpotGlas + SB_EXPLOSION_MM,
        };
      }
      s = protokolliere(s, { typ: "explosion", von: opfer ?? "niemand" }, now);
      if (state.durchgang >= SB_DURCHGAENGE) return { ...s, finished: true };
      return { ...s, phase: "splatter", splatterEndetAt: now + SB_SPLATTER_MS };
    }
    if (now >= state.frageEndsAt) {
      // Zu langsam: festhalten, neue Frage (Maßanzug-Frage ist damit verpasst).
      let s = state.holder !== null ? verbraucheZuweisung(state, state.holder) : state;
      s = protokolliere(s, { typ: "timeout", von: state.holder ?? "niemand" }, now);
      return mitNeuerFrage(s, now);
    }
    return state;
  },

  onDisconnect(state: StinkbananeState, p: PlayerId, ctx: Ctx): StinkbananeState {
    let s: StinkbananeState = { ...state, connected: { ...state.connected, [p]: false } };
    // Design: Disconnect des Halters ⇒ Banane wandert automatisch weiter, KEINE
    // Strafe (und keine +150 — die gibt es nur für richtige Antworten).
    if (!s.finished && s.phase === "ticken" && s.holder === p) {
      const naechster = naechsterVerbundener(s, p);
      s = { ...s, holder: naechster }; // null = Banane liegt am Boden (alle offline)
      s = protokolliere(
        s,
        { typ: "weitergabe", von: p, zu: naechster ?? undefined },
        ctx.clock.now(),
      );
      s = mitNeuerFrage(s, ctx.clock.now());
    }
    return s;
  },

  onReconnect(state: StinkbananeState, p: PlayerId, ctx: Ctx): StinkbananeState {
    let s: StinkbananeState = { ...state, connected: { ...state.connected, [p]: true } };
    // Lag die Banane am Boden (alle offline), nimmt der Rückkehrer sie auf.
    if (!s.finished && s.phase === "ticken" && s.holder === null) {
      s = { ...s, holder: p };
      s = mitNeuerFrage(s, ctx.clock.now());
    }
    return s;
  },

  viewFor(state: StinkbananeState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const basis = {
      questionId: frage.id,
      phase: state.phase,
      // Sitzkreis-Slots für die Screen-Inszenierung (Namen mappt die App).
      spieler: state.players,
      verbunden: state.connected,
      durchgang: state.durchgang,
      durchgaengeTotal: SB_DURCHGAENGE,
      holder: state.holder,
      // Client-Eskalation (Ticken schneller/lauter) läuft lokal über
      // durchgangStartetAt + maxMs — der ECHTE Zünd-Zeitpunkt bleibt geheim.
      durchgangStartetAt: state.durchgangStartetAt,
      maxZuendschnurMs: SB_ZUENDSCHNUR_MAX_MS,
      endsAt: state.phase === "splatter" ? (state.splatterEndetAt ?? 0) : state.frageEndsAt,
      timerMs: state.phase === "splatter" ? SB_SPLATTER_MS : SB_FRAGE_MS,
      weitergaben: state.weitergaben,
      matsch: state.matsch,
      trommel: Object.values(state.trommel).reduce((a, b) => a + b, 0),
      historie: state.historie.slice(-8), // Screen braucht nur die letzten Beats
      jackpotGlas: state.jackpotGlas,
      answeredCount: state.historie.length,
      finished: state.finished,
    };
    const scores = state.finished ? berechneScores(state) : {};
    const aufloesung = state.finished
      ? {
          erklaerung: `Die Stinkbanane ist ${SB_DURCHGAENGE}× geplatzt — ${state.jackpotGlas} MM gingen ins Jackpot-Glas.`,
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: (scores[p] ?? 0) > 0,
            delta: scores[p] ?? 0,
            weitergaben: state.weitergaben[p] ?? 0,
            explodiert: state.explodiert[p] ?? 0,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Frage, richtige Antwort UND die geheime Zündschnur.
      return {
        ...basis,
        text: frage.text,
        options: frage.options,
        correctIndex: frage.answer,
        zuendschnurEndetAt: state.zuendschnurEndetAt,
        aufloesung,
      };
    }
    if (role === "player") {
      const istHalter = player !== undefined && player === state.holder;
      return {
        ...basis,
        you: player ?? null,
        istHalter,
        // NUR der Halter sieht die aktuelle Frage (Design-Regel).
        frage:
          istHalter && state.phase === "ticken" && !state.finished
            ? { text: frage.text, options: frage.options }
            : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: StinkbananeState): boolean {
    return state.finished;
  },

  scores(state: StinkbananeState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (§2.6) — outcomes dienen Auto-GM/Awards: weitergegeben = „richtig". */
  outcomes(state: StinkbananeState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const weiter = state.weitergaben[p] ?? 0;
      const explodiert = state.explodiert[p] ?? 0;
      result[p] = { correct: weiter > 0 ? true : explodiert > 0 ? false : null };
    }
    return result;
  },
};
