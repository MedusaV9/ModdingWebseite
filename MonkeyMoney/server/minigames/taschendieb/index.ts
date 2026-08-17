// Referenz-Minigame „Der Taschendieb-Affe" (GAME-DESIGN §2.7): Point Stealer.
// MC-4 an ALLE; die schnellste RICHTIGE Antwort gewinnt das Klau-Recht →
// geheime Opferwahl (8 s, Default: reichster Spieler) → Klau-Cutscene (6 s).
// Klau: 300 MM (MEDIUM) / 500 MM (HARD), Kappe 25 % des Opfer-Kontos.
// Alle anderen Richtigen: halber Grundwert aus der Bank. Fotofinish <50 ms:
// früherer Server-Timestamp klaut, der andere bekommt den VOLLEN Grundwert.
//
// Faires Fenster-Verfahren OHNE Buzzer-Modul: Es zählt der Server-Empfangs-
// Timestamp (atServerTime); die Auswertung passiert gesammelt am Fragen-Ende,
// exakte Gleichstände löst die Join-Reihenfolge deterministisch auf.
// TODO(Engine-Agent): Sobald das Buzzer-Modul (TECH-SPEC §3.3, Median-RTT +
// Clamp + Fotofinish-Los) existiert, kompensierte Timestamps + echtes Los
// statt Join-Reihenfolge verwenden.
//
// Kontostände + Klau-Schutz kommen aus ctx.match (MatchApi der Engine);
// explizite TaschendiebSlice-Felder haben Vorrang (Test-Injektion).
// TODO(Engine-Agent): letzteOpfer (Anti-Mobbing ÜBER Fragen hinweg) lebt
// außerhalb des Plugin-States — bitte im Slice mitgeben, sobald die Engine
// Klau-Historie führt (innerhalb EINER Frage greift die Sperre bereits).
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import { FRAGE_WERTE } from "../../../shared/money";
import {
  TASCHENDIEB_META,
  TD_CUTSCENE_MS,
  TD_FOTOFINISH_MS,
  TD_FRAGE_MS,
  TD_MAX_OPFER_IN_FOLGE,
  TD_MITMACH_ANTEIL,
  TD_NIEMAND_MS,
  TD_OPFERWAHL_MS,
  tdKlauBetrag,
  type TaschendiebAction,
} from "../../../shared/minigames/taschendieb.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

/** Erweiterter ContentSlice — alle Zusatzfelder optional (Engine-Ausbau, s. o.). */
export interface TaschendiebSlice extends ContentSlice {
  /** MM-Kontostände zum Fragen-Start — Basis für 25-%-Kappe + „reichster"-Default. */
  kontostaende?: Record<string, number>;
  /** Die letzten Klau-Opfer (ältestes zuerst) — Anti-Mobbing über Fragen hinweg. */
  letzteOpfer?: string[];
  /** Spieler mit aktivem Klau-Schutz (Joker „Bananentresor", J6) — Klau prallt ab. */
  klauSchutz?: string[];
  /** Team-Modus (ADDITIV): playerId → TeamId — der Dieb klaut von GEGNER-Teams,
   * Team-Kollegen sind tabu (solange es Gegner gibt). Fehlt: individuell. */
  teamVon?: Record<string, string>;
}

export interface TaschendiebState {
  question: Question;
  /** Maßanzug/Portfolio: eigene Frage pro Spieler (sonst state.question). */
  fragenProSpieler: Record<string, Question>;
  players: PlayerId[];
  kontostaende: Record<string, number> | null;
  letzteOpfer: string[];
  klauSchutz: string[];
  /** Team-Modus: playerId → TeamId (leer = individuell, s. TaschendiebSlice). */
  teamVon: Record<string, string>;
  connected: Record<string, boolean>;
  startedAt: number;
  phase: "frage" | "opferwahl" | "cutscene" | "niemand";
  phaseEndsAt: number;
  frageMs: number;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  dieb: PlayerId | null;
  /** Richtige mit <50 ms Rückstand auf den Dieb → voller Grundwert (Fotofinish). */
  fotofinish: PlayerId[];
  opfer: PlayerId | null;
  klau: { betrag: number; abgeprallt: boolean } | null;
  finished: boolean;
}

type Action = PlayerAction<TaschendiebAction> | GmAction;

function frageVon(state: TaschendiebState, p: string): Question {
  return state.fragenProSpieler[p] ?? state.question;
}

function alleBeantwortet(state: TaschendiebState): boolean {
  return state.players.every((p) => state.answers[p] !== undefined);
}

/** Anti-Mobbing (Server-hart): wer die letzten 2 Klaus Opfer war, ist gesperrt. */
function istGesperrtesOpfer(state: TaschendiebState, id: string): boolean {
  const letzte = state.letzteOpfer.slice(-TD_MAX_OPFER_IN_FOLGE);
  return letzte.length >= TD_MAX_OPFER_IN_FOLGE && letzte.every((o) => o === id);
}

function kontoVon(state: TaschendiebState, id: string): number | null {
  return state.kontostaende === null ? null : (state.kontostaende[id] ?? 0);
}

/** Team-Modus: sind beide im SELBEN Team? (Ohne Team-Daten: nie.) */
function gleichesTeam(state: TaschendiebState, a: string, b: string): boolean {
  const ta = state.teamVon[a];
  return ta !== undefined && ta === state.teamVon[b];
}

/** Gibt es für den Dieb überhaupt ein GEGNER-Team-Ziel? */
function hatGegnerZiel(state: TaschendiebState, dieb: string): boolean {
  return state.players.some((p) => p !== dieb && !gleichesTeam(state, p, dieb));
}

/**
 * Default-Opfer: reichster VERBUNDENER Spieler (ohne Dieb, ohne Anti-Mobbing-
 * Gesperrte). Ohne Kontostands-Daten: erster zulässiger in Join-Reihenfolge.
 * Team-Modus: GEGNER-Teams haben Vorrang — Team-Kollegen nur als Not-Fallback.
 * Fallback-Kaskade, damit auch Rand-Fälle (alle offline) ein Opfer finden.
 */
function defaultOpfer(state: TaschendiebState, dieb: PlayerId): PlayerId | null {
  const reichsterVon = (kandidaten: PlayerId[]): PlayerId | null => {
    if (kandidaten.length === 0) return null;
    if (state.kontostaende === null) return kandidaten[0];
    return kandidaten.reduce((best, k) =>
      (kontoVon(state, k) ?? 0) > (kontoVon(state, best) ?? 0) ? k : best,
    );
  };
  const andere = state.players.filter((p) => p !== dieb);
  const gegner = andere.filter((p) => !gleichesTeam(state, p, dieb));
  return (
    reichsterVon(gegner.filter((p) => state.connected[p] && !istGesperrtesOpfer(state, p))) ??
    reichsterVon(gegner.filter((p) => state.connected[p])) ??
    reichsterVon(gegner) ??
    reichsterVon(andere.filter((p) => state.connected[p] && !istGesperrtesOpfer(state, p))) ??
    reichsterVon(andere.filter((p) => state.connected[p])) ??
    reichsterVon(andere)
  );
}

/** Klau ausführen: Disconnect-Umleitung, Klau-Schutz-Abpraller, 25-%-Kappe. */
function fuehreKlauAus(
  state: TaschendiebState,
  dieb: PlayerId,
  wunsch: PlayerId | null,
  now: number,
): TaschendiebState {
  // Klau auf Disconnected ⇒ automatisch reichster verbundener Spieler (Design).
  let opfer = wunsch !== null && state.connected[wunsch] ? wunsch : defaultOpfer(state, dieb);
  if (opfer === dieb) opfer = null;
  if (opfer === null) {
    return {
      ...state,
      phase: "cutscene",
      phaseEndsAt: now + TD_CUTSCENE_MS,
      opfer: null,
      klau: { betrag: 0, abgeprallt: false },
    };
  }
  // Joker „Bananentresor": Klau prallt ab — Dieb-Affe mit Sternchen, 0 MM.
  const abgeprallt = state.klauSchutz.includes(opfer);
  const betrag = abgeprallt ? 0 : tdKlauBetrag(state.question.difficulty, kontoVon(state, opfer));
  return {
    ...state,
    phase: "cutscene",
    phaseEndsAt: now + TD_CUTSCENE_MS,
    opfer,
    klau: { betrag, abgeprallt },
  };
}

/**
 * Fragen-Ende auswerten: schnellste richtige Antwort gewinnt das Klau-Recht.
 * Sortierung: Server-Timestamp, exakter Gleichstand ⇒ Join-Reihenfolge (s. TODO).
 */
function werteFrageAus(state: TaschendiebState, now: number): TaschendiebState {
  const richtige = state.players
    .filter((p) => state.answers[p]?.choice === frageVon(state, p).answer)
    .sort((a, b) => state.answers[a].atServerTime - state.answers[b].atServerTime);
  if (richtige.length === 0) {
    return { ...state, phase: "niemand", phaseEndsAt: now + TD_NIEMAND_MS };
  }
  const dieb = richtige[0];
  const diebAt = state.answers[dieb].atServerTime;
  const fotofinish = richtige
    .slice(1)
    .filter((p) => state.answers[p].atServerTime - diebAt < TD_FOTOFINISH_MS);
  const s: TaschendiebState = { ...state, dieb, fotofinish };
  // 2-Spieler-Spiel: Opfer ist automatisch der Gegner — keine Opferwahl-Phase.
  if (state.players.length === 2) {
    const gegner = state.players.find((p) => p !== dieb) ?? null;
    return fuehreKlauAus(s, dieb, gegner, now);
  }
  return { ...s, phase: "opferwahl", phaseEndsAt: now + TD_OPFERWAHL_MS };
}

/**
 * Scores: Dieb +Klau / Opfer −Klau (Nullsumme untereinander); Fotofinish-
 * Verlierer voller Grundwert, alle übrigen Richtigen halber Grundwert (Bank).
 * Keine Streak/Speed auf den Klau (Design).
 */
function berechneScores(state: TaschendiebState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  const grundwert = FRAGE_WERTE[state.question.difficulty];
  for (const p of state.players) {
    result[p] = 0;
    const a = state.answers[p];
    const richtig = a !== undefined && a.choice === frageVon(state, p).answer;
    if (!richtig) continue;
    if (p === state.dieb) continue; // Dieb bekommt NUR den Klau
    result[p] = state.fotofinish.includes(p)
      ? grundwert
      : Math.round(grundwert * TD_MITMACH_ANTEIL);
  }
  if (state.dieb !== null && state.opfer !== null && state.klau !== null) {
    result[state.dieb] = (result[state.dieb] ?? 0) + state.klau.betrag;
    result[state.opfer] = (result[state.opfer] ?? 0) - state.klau.betrag;
  }
  return result;
}

export const taschendiebPlugin: MinigamePlugin<TaschendiebState, TaschendiebAction> = {
  meta: TASCHENDIEB_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): TaschendiebState {
    const question = content.questions[0];
    if (!question) throw new Error("taschendieb: ContentSlice ohne Frage");
    const slice = content as TaschendiebSlice;
    const now = ctx.clock.now();
    const frageMs = TD_FRAGE_MS[question.difficulty];
    // Kontostände/Klau-Schutz: explizite Slice-Felder (Tests) vor ctx.match (Engine).
    const match = ctx.match;
    const kontostaende =
      slice.kontostaende ??
      (match ? Object.fromEntries(players.map((p) => [p, match.balance(p)])) : null);
    const klauSchutz =
      slice.klauSchutz ?? (match ? players.filter((p) => match.hatKlauSchutz(p)) : []);
    // Team-Modus (ADDITIV): Zuordnung EINMAL beim Init einfangen (State bleibt
    // JSON-serialisierbar) — ohne Team-Modus bleibt die Map leer (individuell).
    let teamVon: Record<string, string> = slice.teamVon ?? {};
    if (slice.teamVon === undefined && match?.teamVon !== undefined) {
      const tv = match.teamVon.bind(match);
      teamVon = {};
      for (const p of players) {
        const t = tv(p);
        if (t !== null) teamVon[p] = t;
      }
    }
    return {
      question,
      fragenProSpieler: content.mods?.fragenProSpieler ?? {},
      players,
      kontostaende,
      letzteOpfer: slice.letzteOpfer ?? [],
      klauSchutz,
      teamVon,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      startedAt: now,
      phase: "frage",
      phaseEndsAt: now + frageMs,
      frageMs,
      answers: {},
      dieb: null,
      fotofinish: [],
      opfer: null,
      klau: null,
      finished: false,
    };
  },

  reduce(state: TaschendiebState, action: Action, ctx: Ctx): TaschendiebState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: laufende Phase sauber zu Ende denken (Antworten behalten).
        const now = ctx.clock.now();
        if (state.phase === "frage") {
          const s = werteFrageAus(state, now);
          if (s.phase === "opferwahl" && s.dieb !== null) {
            return { ...fuehreKlauAus(s, s.dieb, null, now), finished: true };
          }
          return { ...s, finished: true };
        }
        if (state.phase === "opferwahl" && state.dieb !== null) {
          return { ...fuehreKlauAus(state, state.dieb, null, now), finished: true };
        }
        return { ...state, finished: true };
      }
      if (action.type === "timer.extend") {
        return { ...state, phaseEndsAt: state.phaseEndsAt + action.ms };
      }
      // timer.shift (Pause): Anker + Deadline gemeinsam verschieben.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        phaseEndsAt: state.phaseEndsAt + action.ms,
      };
    }
    if (state.finished) return state;

    if (action.action.type === "answer") {
      if (state.phase !== "frage") return state;
      // Antwort-Lock: die erste Antwort zählt — sie IST der Buzz.
      if (state.answers[action.playerId] !== undefined) return state;
      if (action.atServerTime > state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
      return {
        ...state,
        answers: {
          ...state.answers,
          [action.playerId]: {
            choice: action.action.choice,
            nachMs: Math.max(0, action.atServerTime - state.startedAt),
            atServerTime: action.atServerTime,
          },
        },
      };
    }

    // Geheime Opferwahl: NUR der Dieb, nur in der Opferwahl-Phase.
    if (action.action.type !== "steal") return state;
    if (state.phase !== "opferwahl" || action.playerId !== state.dieb) return state;
    const ziel = action.action.targetId as PlayerId;
    if (!state.players.includes(ziel) || ziel === state.dieb) return state;
    // Anti-Mobbing SERVER-HART: gesperrtes Ziel wird ignoriert (Dieb wählt neu).
    if (istGesperrtesOpfer(state, ziel)) return state;
    // Team-Modus SERVER-HART: Team-Kollegen sind tabu, solange es Gegner gibt.
    if (gleichesTeam(state, ziel, state.dieb) && hatGegnerZiel(state, state.dieb)) return state;
    return fuehreKlauAus(state, state.dieb, ziel, ctx.clock.now());
  },

  tick(state: TaschendiebState, ctx: Ctx): TaschendiebState {
    if (state.finished) return state;
    const now = ctx.clock.now();
    if (state.phase === "frage") {
      // Sammel-Fenster: Auswertung erst NACH dem Gnadenfenster (Spätantworten
      // können nicht mehr gewinnen, aber noch Mitmach-Geld holen).
      if (alleBeantwortet(state) || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteFrageAus(state, now);
      }
      return state;
    }
    if (now < state.phaseEndsAt) return state;
    if (state.phase === "opferwahl" && state.dieb !== null) {
      // Timeout ⇒ Default: reichster Spieler (Design).
      return fuehreKlauAus(state, state.dieb, null, now);
    }
    // cutscene/niemand vorbei ⇒ fertig (Engine übernimmt mit der Auflösung).
    return { ...state, finished: true };
  },

  onDisconnect(state: TaschendiebState, p: PlayerId, _ctx: Ctx): TaschendiebState {
    // Abgegebene Antworten bleiben gültig; Klau auf Offline-Ziele leitet
    // fuehreKlauAus automatisch um (Design). Dieb offline in der Opferwahl ⇒
    // der Timeout-Default greift ohnehin.
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: TaschendiebState, p: PlayerId, _ctx: Ctx): TaschendiebState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: TaschendiebState, role: Role, player?: PlayerId): unknown {
    const timerMs =
      state.phase === "frage"
        ? state.frageMs
        : state.phase === "opferwahl"
          ? TD_OPFERWAHL_MS
          : state.phase === "cutscene"
            ? TD_CUTSCENE_MS
            : TD_NIEMAND_MS;
    const basis = {
      questionId: state.question.id,
      text: state.question.text,
      options: state.question.options,
      schwierigkeit: state.question.difficulty,
      // Slots für die Screen-Inszenierung (Namen mappt die App).
      spieler: state.players,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      answeredCount: Object.keys(state.answers).length,
      // Klau-Recht + Fotofinish sind ab der Auswertung öffentlich (Show-Moment).
      dieb: state.dieb,
      fotofinish: state.fotofinish,
      // Cutscene-Inszenierung: Screen animiert die Affenhand von → zu.
      klau:
        state.phase === "cutscene" && state.klau !== null
          ? {
              von: state.opfer,
              zu: state.dieb,
              betrag: state.klau.betrag,
              abgeprallt: state.klau.abgeprallt,
            }
          : null,
      finished: state.finished,
    };
    const scores =
      state.finished || state.phase === "cutscene" || state.phase === "niemand"
        ? berechneScores(state)
        : {};
    // Maßanzug: die Auflösung folgt der ROLLEN-Frage (Spieler sehen IHRE Frage).
    const rollenFrage =
      role === "player" && player !== undefined ? frageVon(state, player) : state.question;
    const aufloesung = state.finished
      ? {
          correctIndex: rollenFrage.answer,
          erklaerung: rollenFrage.erklaerung,
          klau:
            state.klau !== null
              ? {
                  von: state.opfer,
                  zu: state.dieb,
                  betrag: state.klau.betrag,
                  abgeprallt: state.klau.abgeprallt,
                }
              : null,
          perPlayer: state.players.map((p) => {
            const a = state.answers[p];
            return {
              playerId: p,
              choice: a?.choice ?? null,
              correct: a !== undefined && a.choice === frageVon(state, p).answer,
              delta: scores[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      return {
        ...basis,
        correctIndex: state.question.answer,
        opfer: state.opfer,
        aufloesung,
      };
    }
    if (role === "player") {
      const a = player ? state.answers[player] : undefined;
      const istDieb = player !== undefined && player === state.dieb;
      return {
        ...basis,
        // Maßanzug: das Handy zeigt die EIGENE Frage (Screen behält die Basis-Frage).
        questionId: rollenFrage.id,
        text: rollenFrage.text,
        options: rollenFrage.options,
        yourChoice: a?.choice ?? null,
        istDieb,
        duBistOpfer: state.opfer !== null && player === state.opfer,
        // GEHEIME Opferwahl: das Ziel-Grid sieht NUR der Dieb.
        ziele:
          istDieb && state.phase === "opferwahl"
            ? state.players
                .filter((p) => p !== state.dieb)
                .map((p) => {
                  const kollege =
                    state.dieb !== null &&
                    gleichesTeam(state, p, state.dieb) &&
                    hatGegnerZiel(state, state.dieb);
                  return {
                    id: p,
                    kontostand: kontoVon(state, p),
                    verbunden: state.connected[p],
                    waehlbar: !istGesperrtesOpfer(state, p) && !kollege,
                    geschuetzt: state.klauSchutz.includes(p), // Schutz ist öffentlich (J6)
                    // Team-Modus: eigene Bande ist tabu (UI graut die Kollegen aus).
                    teamKollege: kollege || undefined,
                  };
                })
            : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: TaschendiebState): boolean {
    return state.finished;
  },

  scores(state: TaschendiebState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak auf den Klau (§2.7) — outcomes dienen Pott/Awards/Auto-GM. */
  outcomes(state: TaschendiebState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const a = state.answers[p];
      result[p] =
        a === undefined
          ? { correct: null }
          : { correct: a.choice === frageVon(state, p).answer, nachMs: a.nachMs };
    }
    return result;
  },
};
