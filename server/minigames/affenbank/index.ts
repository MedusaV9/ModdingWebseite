// „Die Affenbank" (GAME-DESIGN §2.8): Kette + Verrat — DIE Signatur-Runde.
// Schnellfeuer-MC-4 an alle im 10-s-Takt: antwortet die MEHRHEIT (strikt, über
// die VERBUNDENEN) richtig, wächst der Team-Pott 50 → … → 1.600. Jeder kann
// jederzeit BANK! drücken: der aktuelle Pott wird ihm PERSÖNLICH gutgeschrieben,
// die Kette reißt sofort (alle Drücker im selben 1-s-Fenster sichern denselben
// Betrag — EIN Reset). Falsche Mehrheit = ungesicherter Pott verbrennt.
// 90 s Kette × 2 Durchgänge; die Mehrheits-Auswertung passiert am
// Serverfenster-Ende (Design-Edge). Keine Streak/Speed — scores() = Summe der
// gebankten Beträge (meta.roundBased: EIN init() pro Runde, Fragen rotieren).
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  AB_BANK_FENSTER_MS,
  AB_DURCHGAENGE,
  AB_FRAGE_MS,
  AB_KETTE,
  AB_KETTE_MS,
  AB_MIN_FENSTER_MS,
  AB_PAUSE_MS,
  abPottWert,
  AFFENBANK_META,
  type AbHistorieEintrag,
  type AffenbankAction,
} from "../../../shared/minigames/affenbank.meta";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export interface AffenbankState {
  players: PlayerId[];
  questions: Question[];
  startedAt: number;
  phase: "kette" | "pause";
  durchgang: number; // 1-basiert
  /** Runden-Tuning aus FrageMods.affenbank (Quick: 1×45 s statt 2×90 s). */
  durchgaengeTotal: number;
  ketteMs: number;
  /** Ketten-Stufe = Mehrheits-Treffer in Folge (0 = Pott leer). */
  stufe: number;
  /** Monoton wachsender Fragen-Zähler — Bots/Clients erkennen daran NEUE
   * Instanzen derselben (zyklisch rotierten) Frage. */
  frageNonce: number;
  frageIndex: number;
  frageStartetAt: number;
  frageEndetAt: number;
  /** Antworten aufs AKTUELLE Fenster (erste zählt, Auswertung am Fenster-Ende). */
  answers: Record<string, number>;
  /** Offenes BANK!-Sammelfenster (1 s): alle Drücker sichern denselben Betrag. */
  bankFenster: { betrag: number; endetAt: number; drueckerIds: string[] } | null;
  /** Gesicherte Beträge pro Spieler (Summe = scores()). */
  gebankt: Record<string, number>;
  /** Wie oft ein Spieler in diesem Spiel richtig geantwortet hat (outcomes). */
  richtig: Record<string, number>;
  beantwortet: Record<string, number>;
  ketteEndetAt: number;
  pauseEndetAt: number | null;
  connected: Record<string, boolean>;
  historie: AbHistorieEintrag[];
  finished: boolean;
}

type Action = PlayerAction<AffenbankAction> | GmAction;

function verbundene(state: AffenbankState): PlayerId[] {
  return state.players.filter((p) => state.connected[p]);
}

function aktuelleFrage(state: AffenbankState): Question {
  return state.questions[state.frageIndex % state.questions.length];
}

function protokolliere(
  state: AffenbankState,
  eintrag: Omit<AbHistorieEintrag, "atMs" | "durchgang">,
  atAbsolutMs: number,
): AffenbankState {
  return {
    ...state,
    historie: [
      ...state.historie,
      { ...eintrag, atMs: atAbsolutMs - state.startedAt, durchgang: state.durchgang },
    ],
  };
}

/** Neues Frage-Fenster ab `ab` (gekappt aufs Ketten-Ende). */
function mitNeuerFrage(state: AffenbankState, ab: number): AffenbankState {
  return {
    ...state,
    frageIndex: state.frageIndex + 1,
    frageNonce: state.frageNonce + 1,
    frageStartetAt: ab,
    frageEndetAt: Math.min(ab + AB_FRAGE_MS, state.ketteEndetAt),
    answers: {},
  };
}

/**
 * Mehrheits-Auswertung am Serverfenster-Ende (§2.8): STRIKTE Mehrheit über die
 * verbundenen Spieler (2 Spieler ⇒ beide müssen richtig sein). Richtig ⇒
 * Stufe +1 (Kappe 1.600), falsch ⇒ ungesicherter Pott verbrennt (Stufe 0).
 */
function werteFensterAus(state: AffenbankState, now: number): AffenbankState {
  const frage = aktuelleFrage(state);
  const online = verbundene(state);
  const richtige = online.filter((p) => state.answers[p] === frage.answer);
  const mehrheit = online.length > 0 && richtige.length * 2 > online.length;

  let s: AffenbankState = {
    ...state,
    richtig: { ...state.richtig },
    beantwortet: { ...state.beantwortet },
  };
  for (const p of state.players) {
    if (state.answers[p] === undefined) continue;
    s.beantwortet[p] = (s.beantwortet[p] ?? 0) + 1;
    if (state.answers[p] === frage.answer) s.richtig[p] = (s.richtig[p] ?? 0) + 1;
  }

  if (mehrheit) {
    const stufe = Math.min(state.stufe + 1, AB_KETTE.length);
    s = { ...s, stufe };
    s = protokolliere(s, { typ: "verdoppelt", betrag: abPottWert(stufe) }, now);
  } else {
    if (state.stufe > 0) s = protokolliere(s, { typ: "verbrannt", betrag: 0 }, now);
    s = { ...s, stufe: 0 };
  }
  return s;
}

// Alt-Saves ohne die Tuning-Felder spielen den §2.8-Standard (2×90 s).
function durchgaengeVon(state: AffenbankState): number {
  return state.durchgaengeTotal ?? AB_DURCHGAENGE;
}

function ketteMsVon(state: AffenbankState): number {
  return state.ketteMs ?? AB_KETTE_MS;
}

/** Durchgangs-Ende: ungesicherter Pott verbrennt; danach Pause oder Schluss. */
function beendeDurchgang(state: AffenbankState, now: number): AffenbankState {
  let s = state;
  if (s.stufe > 0) {
    s = protokolliere(s, { typ: "verbrannt", betrag: 0 }, now);
    s = { ...s, stufe: 0 };
  }
  s = { ...s, bankFenster: null, answers: {} };
  if (s.durchgang >= durchgaengeVon(s)) return { ...s, finished: true };
  return { ...s, phase: "pause", pauseEndetAt: now + AB_PAUSE_MS };
}

export const affenbankPlugin: MinigamePlugin<AffenbankState, AffenbankAction> = {
  meta: AFFENBANK_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): AffenbankState {
    if (content.questions.length === 0) throw new Error("affenbank: ContentSlice ohne Frage");
    const now = ctx.clock.now();
    // Quick Cash: Engine reicht 1×45 s als mods.affenbank durch (§6.2).
    const tuning = content.mods?.affenbank;
    const ketteMs = tuning?.ketteMs ?? AB_KETTE_MS;
    const ketteEndetAt = now + ketteMs;
    return {
      players,
      questions: content.questions,
      startedAt: now,
      phase: "kette",
      durchgang: 1,
      durchgaengeTotal: tuning?.durchgaenge ?? AB_DURCHGAENGE,
      ketteMs,
      stufe: 0,
      frageNonce: 1,
      frageIndex: 0,
      frageStartetAt: now,
      frageEndetAt: Math.min(now + AB_FRAGE_MS, ketteEndetAt),
      answers: {},
      bankFenster: null,
      gebankt: {},
      richtig: {},
      beantwortet: {},
      ketteEndetAt,
      pauseEndetAt: null,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      historie: [{ typ: "durchgang-start", betrag: 0, atMs: 0, durchgang: 1 }],
      finished: false,
    };
  },

  reduce(state: AffenbankState, action: Action, ctx: Ctx): AffenbankState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      if (action.type === "timer.extend") {
        // GM „+15 s": das aktuelle Fenster UND die Kette bekommen Luft.
        return {
          ...state,
          frageEndetAt: state.frageEndetAt + action.ms,
          ketteEndetAt: state.ketteEndetAt + action.ms,
        };
      }
      // timer.shift (Pause): ALLE Deadlines wandern.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        frageStartetAt: state.frageStartetAt + action.ms,
        frageEndetAt: state.frageEndetAt + action.ms,
        ketteEndetAt: state.ketteEndetAt + action.ms,
        pauseEndetAt: state.pauseEndetAt === null ? null : state.pauseEndetAt + action.ms,
        bankFenster:
          state.bankFenster === null
            ? null
            : { ...state.bankFenster, endetAt: state.bankFenster.endetAt + action.ms },
      };
    }
    if (state.finished || state.phase !== "kette") return state;

    // ---------- BANK! (§2.8): jederzeit während die Kette läuft ----------
    if (action.action.type === "bank") {
      const p = action.playerId;
      if (action.atServerTime >= state.ketteEndetAt) return state;
      // Offenes 1-s-Sammelfenster: Nachzügler sichern DENSELBEN Betrag.
      if (state.bankFenster !== null && action.atServerTime < state.bankFenster.endetAt) {
        if (state.bankFenster.drueckerIds.includes(p)) return state;
        const betrag = state.bankFenster.betrag;
        let s: AffenbankState = {
          ...state,
          bankFenster: {
            ...state.bankFenster,
            drueckerIds: [...state.bankFenster.drueckerIds, p],
          },
          gebankt: { ...state.gebankt, [p]: (state.gebankt[p] ?? 0) + betrag },
        };
        s = protokolliere(s, { typ: "gebankt", playerId: p, betrag }, action.atServerTime);
        return s;
      }
      // Erster Drücker: Pott sichern, Kette reißt SOFORT (Stufe 0), Fenster öffnen.
      const betrag = abPottWert(state.stufe);
      if (betrag <= 0) return state; // leerer Pott: BANK! verpufft
      let s: AffenbankState = {
        ...state,
        stufe: 0,
        bankFenster: {
          betrag,
          endetAt: action.atServerTime + AB_BANK_FENSTER_MS,
          drueckerIds: [p],
        },
        gebankt: { ...state.gebankt, [p]: (state.gebankt[p] ?? 0) + betrag },
      };
      s = protokolliere(s, { typ: "gebankt", playerId: p, betrag }, action.atServerTime);
      return s;
    }

    // ---------- MC-4-Antwort im 10-s-Fenster ----------
    if (action.action.type !== "answer") return state;
    if (action.atServerTime > state.frageEndetAt) return state; // Auswertung = Fenster-Ende
    if (state.answers[action.playerId] !== undefined) return state; // erste Antwort zählt
    void ctx;
    return {
      ...state,
      answers: { ...state.answers, [action.playerId]: action.action.choice },
    };
  },

  tick(state: AffenbankState, ctx: Ctx): AffenbankState {
    if (state.finished) return state;
    const now = ctx.clock.now();
    let s = state;

    // Abgelaufenes BANK!-Sammelfenster schließen (rein kosmetisch fürs View).
    if (s.bankFenster !== null && now >= s.bankFenster.endetAt) {
      s = { ...s, bankFenster: null };
    }

    if (s.phase === "pause") {
      if (s.pauseEndetAt !== null && now >= s.pauseEndetAt) {
        // Durchgang 2: frische Kette (Runden-Tuning), Pott leer, Fragen rotieren weiter.
        const ketteEndetAt = now + ketteMsVon(s);
        s = {
          ...s,
          phase: "kette",
          durchgang: s.durchgang + 1,
          stufe: 0,
          ketteEndetAt,
          pauseEndetAt: null,
        };
        s = protokolliere(s, { typ: "durchgang-start", betrag: 0 }, now);
        return mitNeuerFrage(s, now);
      }
      return s;
    }

    // Phase "kette":
    if (now >= s.frageEndetAt) {
      s = werteFensterAus(s, now);
      // Rest-Kette zu kurz für ein lesbares Fenster ⇒ Durchgang beenden.
      if (s.ketteEndetAt - now < AB_MIN_FENSTER_MS || now >= s.ketteEndetAt) {
        return beendeDurchgang(s, now);
      }
      return mitNeuerFrage(s, now);
    }
    return s;
  },

  onDisconnect(state: AffenbankState, p: PlayerId, _ctx: Ctx): AffenbankState {
    // §2.8: KEIN Auto-Bank — gesicherte Beträge bleiben, offene Antwort verfällt
    // (der Spieler zählt ab jetzt nicht mehr zur Mehrheits-Basis).
    return { ...state, connected: { ...state.connected, [p]: false } };
  },

  onReconnect(state: AffenbankState, p: PlayerId, _ctx: Ctx): AffenbankState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: AffenbankState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      durchgang: state.durchgang,
      durchgaengeTotal: durchgaengeVon(state),
      pott: abPottWert(state.stufe),
      stufe: state.stufe,
      kette: AB_KETTE,
      ketteEndetAt: state.ketteEndetAt,
      ketteMs: ketteMsVon(state),
      endsAt: state.phase === "pause" ? (state.pauseEndetAt ?? 0) : state.frageEndetAt,
      timerMs: state.phase === "pause" ? AB_PAUSE_MS : AB_FRAGE_MS,
      // Frage läuft für ALLE gleichzeitig — Text/Optionen sind public.
      text: state.phase === "kette" ? frage.text : null,
      options: state.phase === "kette" ? frage.options : null,
      answeredCount: Object.keys(state.answers).length,
      spielerZahl: verbundene(state).length,
      gebankt: state.gebankt,
      bankFenster:
        state.bankFenster === null
          ? null
          : { betrag: state.bankFenster.betrag, drueckerIds: state.bankFenster.drueckerIds },
      historie: state.historie.slice(-8),
      finished: state.finished,
    };
    const aufloesung = state.finished
      ? {
          erklaerung: "Nur gebankte Beträge zählen — der Rest ist in der Kette verbrannt.",
          perPlayer: state.players.map((p) => {
            const gebankt = (state.gebankt[p] ?? 0) > 0;
            const beteiligt = (state.beantwortet[p] ?? 0) > 0;
            // Formatspezifischer Ergebnis-Status: choice===null heißt hier
            // NICHT „zu langsam" — die Clients zeigen status/hinweis statt
            // des generischen Timeout-Mappings der Frage-Formate.
            return {
              playerId: p,
              choice: null,
              correct: gebankt,
              delta: state.gebankt[p] ?? 0,
              status: gebankt
                ? "💰 GEBANKT!"
                : beteiligt
                  ? "🏦 NICHT GEBANKT"
                  : "🙈 LEER AUSGEGANGEN",
              hinweis: gebankt
                ? undefined
                : beteiligt
                  ? "Deine Antworten sind mit der Kette verbrannt — nur BANK! sichert."
                  : "Kein BANK!, keine Antwort — diesmal nichts gesichert.",
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht die richtige Antwort + wer schon geantwortet hat.
      return {
        ...basis,
        correctIndex: frage.answer,
        answers: state.answers,
        aufloesung,
      };
    }
    if (role === "player") {
      return {
        ...basis,
        you: player ?? null,
        yourChoice: player !== undefined ? (state.answers[player] ?? null) : null,
        yourGebankt: player !== undefined ? (state.gebankt[player] ?? 0) : 0,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: AffenbankState): boolean {
    return state.finished;
  },

  /** §2.8: NUR über BANK! gesicherte Beträge — die Engine bucht die Summe. */
  scores(state: AffenbankState): Record<PlayerId, number> {
    const result: Record<PlayerId, number> = {};
    for (const p of state.players) result[p] = state.gebankt[p] ?? 0;
    return result;
  },

  /** Keine Streak (§2.8) — outcomes dienen Auto-GM/Awards: je gebankt = „richtig". */
  outcomes(state: AffenbankState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const gebankt = (state.gebankt[p] ?? 0) > 0;
      const beteiligt = (state.beantwortet[p] ?? 0) > 0;
      result[p] = { correct: gebankt ? true : beteiligt ? false : null };
    }
    return result;
  },
};
