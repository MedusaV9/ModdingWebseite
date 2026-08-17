// „Risiko-Leiter" (Welle 4): Gewinnleiter-Klassiker — jeder klettert
// INDIVIDUELL die 8-Stufen-Money-Leiter (100→200→400→700→1.100→1.600→2.200→
// 3.000 MM), pro Stufe eine Frage mit steigender Schwierigkeit (init sortiert
// den Vorrat easy → ultrahard).
//
// ABLAUF (eine Runden-Instanz, meta.roundBased — EINE Buchung am Ende):
//   je Stufe: entscheidung (9 s: jeder aktive Kletterer wählt WEITERKLETTERN
//   oder ABSICHERN; Absichern wirkt SOFORT und endgültig — der aktuelle
//   Leiter-Stand ist gesichert, der Spieler wartet charmant als Zuschauer;
//   Timeout = WEITERKLETTERN, sonst gäbe es den Guck-Exploit „erst Frage
//   sehen, dann absichern"; getrennte Kletterer sichern automatisch ab) →
//   frage (15 s MC-4, NUR aktive Kletterer) → aufstieg (5 s Beat: Aufsteiger
//   klettern, Abstürzer fallen) … → ergebnis (8 s Leiter-Bilanz).
//
// SICHERHEITSSTUFEN-REGEL (Gewinnleiter-Klassiker, verbindlich):
//   Falsche Antwort ODER Schweigen nach aktiver Weiter-Wahl = ABSTURZ auf die
//   letzte erklommene Sicherheitsstufe: Stufe 3 = 400 MM (rlAbsturzWert),
//   darunter = 0. Wer Stufe 8 erklimmt, bekommt 3.000 + RL_JACKPOT_BONUS.
//
// EDGE-CASES: Kletterer-Disconnect = sofortige Auto-Absicherung auf dem
// aktuellen Stand (charmanter AFK-Schutz — bereits gegebene Antworten der
// laufenden Frage zählen weiter); alle abgesichert/abgestürzt ⇒ Runde endet
// früher; GM-Skip vor dem Ergebnis ⇒ Abbruch ohne Zahlung (Präzedenz §2.9);
// POOL-WÄCHTER: init filtert kaputte Fragen und wirft ohne brauchbare Frage.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  RISIKO_LEITER_META,
  RL_AUFSTIEG_MS,
  RL_ENTSCHEIDUNG_MS,
  RL_ERGEBNIS_MS,
  RL_FRAGE_MS,
  RL_JACKPOT_BONUS,
  RL_LEITER,
  RL_SCHWIERIGKEITS_RANG,
  RL_SICHERHEITSSTUFE,
  RL_STUFEN,
  rlAbsturzWert,
  rlGipfelWert,
  rlLeiterWert,
  type RisikoLeiterAction,
} from "../../../shared/minigames/risiko-leiter.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export type RlPhase = "entscheidung" | "frage" | "aufstieg" | "ergebnis";
export type RlStatus = "klettert" | "abgesichert" | "abgestuerzt" | "gipfel";

export interface RlSpieler {
  stufe: number; // erklommene Stufen (0..8)
  status: RlStatus;
  /** Finale Gutschrift — 0 solange der Spieler noch klettert. */
  gutschrift: number;
  /** Stufen-Nr der Frage, an der Schluss war (Absturz/Gipfel), sonst null. */
  endeAufStufe: number | null;
}

/** Aufstiegs-Beat: das öffentliche Ergebnis der letzten Stufen-Frage. */
export interface RlAufstiegBeat {
  stufeNr: number;
  questionId: string;
  /** Options-Texte der AUFGELÖSTEN Frage (kein Leak — das Fenster ist zu). */
  optionen: string[];
  correctIndex: number;
  erklaerung: string;
  /** Was ist wem passiert (nur Kletterer dieser Frage). */
  ereignisse: Record<string, "aufstieg" | "gipfel" | "absturz">;
  antworten: Record<string, { choice: number | null; nachMs: number | null }>;
}

export interface RisikoLeiterState {
  players: PlayerId[];
  questions: Question[]; // easy → ultrahard sortiert (die Leiter-Reihenfolge)
  startedAt: number;
  phase: RlPhase;
  phaseEndsAt: number;
  timerMs: number; // Frage-Fenster (mit mods.timerFaktor)
  stufeNr: number; // 1-basiert: die Stufe, um die es gerade geht
  frageNonce: number;
  frageStartetAt: number | null;
  /** Entscheidungen des AKTUELLEN Fensters (erste Wahl rastet ein). */
  entscheidungen: Record<string, "weiter" | "absichern">;
  kletterer: Record<string, RlSpieler>;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  letzterBeat: RlAufstiegBeat | null;
  connected: Record<string, boolean>;
  /** GM-Skip vor dem Ergebnis: NIEMAND bekommt etwas (Präzedenz §2.9). */
  uebersprungen: boolean;
  finished: boolean;
}

type Action = PlayerAction<RisikoLeiterAction> | GmAction;

function aktuelleFrage(state: RisikoLeiterState): Question {
  return state.questions[(state.stufeNr - 1) % state.questions.length];
}

function aktiveKletterer(state: RisikoLeiterState): PlayerId[] {
  return state.players.filter((p) => state.kletterer[p].status === "klettert");
}

/** Spieler absichern: Leiter-Stand gutschreiben, Runde für ihn beenden. */
function sichereAb(state: RisikoLeiterState, p: PlayerId): RisikoLeiterState {
  const k = state.kletterer[p];
  if (k.status !== "klettert") return state;
  return {
    ...state,
    kletterer: {
      ...state.kletterer,
      [p]: { ...k, status: "abgesichert", gutschrift: rlLeiterWert(k.stufe) },
    },
  };
}

function starteEntscheidung(state: RisikoLeiterState, now: number): RisikoLeiterState {
  return {
    ...state,
    phase: "entscheidung",
    phaseEndsAt: now + RL_ENTSCHEIDUNG_MS,
    entscheidungen: {},
  };
}

function starteFrage(state: RisikoLeiterState, now: number): RisikoLeiterState {
  return {
    ...state,
    phase: "frage",
    phaseEndsAt: now + state.timerMs,
    frageNonce: state.frageNonce + 1,
    frageStartetAt: now,
    answers: {},
  };
}

function starteErgebnis(state: RisikoLeiterState, now: number): RisikoLeiterState {
  return { ...state, phase: "ergebnis", phaseEndsAt: now + RL_ERGEBNIS_MS };
}

/** Entscheidungs-Fenster schließen: getrennte Zauderer sichern automatisch ab
 * (AFK-Schutz), verbundene Zauderer klettern weiter („Wer zögert, klettert"). */
function schliesseEntscheidung(state: RisikoLeiterState, now: number): RisikoLeiterState {
  let s = state;
  for (const p of aktiveKletterer(s)) {
    if (s.entscheidungen[p] === undefined && !s.connected[p]) s = sichereAb(s, p);
  }
  if (aktiveKletterer(s).length === 0) return starteErgebnis(s, now);
  return starteFrage(s, now);
}

/** Stufen-Frage auswerten: richtig = Aufstieg (Stufe 8 = Gipfel + Bonus),
 * falsch/stumm = Absturz auf die Sicherheitsstufe. */
function werteStufeAus(state: RisikoLeiterState, now: number): RisikoLeiterState {
  const frage = aktuelleFrage(state);
  const kletterer = { ...state.kletterer };
  const ereignisse: RlAufstiegBeat["ereignisse"] = {};
  const antworten: RlAufstiegBeat["antworten"] = {};
  for (const p of aktiveKletterer(state)) {
    const a = state.answers[p];
    antworten[p] = { choice: a?.choice ?? null, nachMs: a?.nachMs ?? null };
    if (a !== undefined && a.choice === frage.answer) {
      const stufe = state.stufeNr;
      if (stufe >= RL_STUFEN) {
        kletterer[p] = { stufe, status: "gipfel", gutschrift: rlGipfelWert(), endeAufStufe: stufe };
        ereignisse[p] = "gipfel";
      } else {
        kletterer[p] = { ...kletterer[p], stufe };
        ereignisse[p] = "aufstieg";
      }
    } else {
      // Absturz: WEITER gewählt und daneben (oder stumm) ⇒ Sicherheitsstufe.
      kletterer[p] = {
        stufe: kletterer[p].stufe,
        status: "abgestuerzt",
        gutschrift: rlAbsturzWert(kletterer[p].stufe),
        endeAufStufe: state.stufeNr,
      };
      ereignisse[p] = "absturz";
    }
  }
  return {
    ...state,
    kletterer,
    letzterBeat: {
      stufeNr: state.stufeNr,
      questionId: frage.id,
      optionen: [...frage.options],
      correctIndex: frage.answer,
      erklaerung: frage.erklaerung,
      ereignisse,
      antworten,
    },
    phase: "aufstieg",
    phaseEndsAt: now + RL_AUFSTIEG_MS,
  };
}

/** Scores (eine Buchung am Runden-Ende): die finalen Gutschriften. */
function berechneScores(state: RisikoLeiterState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    result[p] = state.uebersprungen ? 0 : state.kletterer[p].gutschrift;
  }
  return result;
}

export const risikoLeiterPlugin: MinigamePlugin<RisikoLeiterState, RisikoLeiterAction> = {
  meta: RISIKO_LEITER_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): RisikoLeiterState {
    // Pool-Wächter: nur Fragen mit sauberem Options/Antwort-Paar auf die Leiter.
    const brauchbar = content.questions.filter(
      (q) =>
        q.text.length > 0 &&
        q.options.length >= 2 &&
        Number.isInteger(q.answer) &&
        q.answer >= 0 &&
        q.answer < q.options.length,
    );
    if (brauchbar.length === 0) {
      throw new Error("risiko-leiter: ContentSlice ohne brauchbare Frage");
    }
    // Die Leiter-Progression: Schwierigkeit steigt mit der Stufe (stabile
    // Sortierung — gleiche Stufen behalten die Slice-Reihenfolge).
    const questions = [...brauchbar].sort(
      (a, b) => RL_SCHWIERIGKEITS_RANG[a.difficulty] - RL_SCHWIERIGKEITS_RANG[b.difficulty],
    );
    const now = ctx.clock.now();
    return {
      players,
      questions,
      startedAt: now,
      phase: "entscheidung",
      phaseEndsAt: now + RL_ENTSCHEIDUNG_MS,
      timerMs: Math.round(RL_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      stufeNr: 1,
      frageNonce: 0,
      frageStartetAt: null,
      entscheidungen: {},
      kletterer: Object.fromEntries(
        players.map((p) => [
          p,
          { stufe: 0, status: "klettert", gutschrift: 0, endeAufStufe: null },
        ]),
      ),
      answers: {},
      letzterBeat: null,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      uebersprungen: false,
      finished: false,
    };
  },

  reduce(state: RisikoLeiterState, action: Action, ctx: Ctx): RisikoLeiterState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: steht die Bilanz schon (Ergebnis läuft), gilt sie —
        // sonst verfällt die Leiter ohne Zahlung.
        if (state.phase === "ergebnis") return { ...state, finished: true };
        return { ...state, uebersprungen: true, finished: true };
      }
      if (action.type === "timer.extend") {
        return { ...state, phaseEndsAt: state.phaseEndsAt + action.ms };
      }
      // timer.shift (Pause): alle absoluten Zeitanker wandern mit.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        phaseEndsAt: state.phaseEndsAt + action.ms,
        frageStartetAt: state.frageStartetAt === null ? null : state.frageStartetAt + action.ms,
      };
    }
    if (state.finished) return state;
    const p = action.playerId;
    void ctx;

    // ---------- Entscheidung: WEITERKLETTERN oder ABSICHERN ----------
    if (action.action.type === "entscheidung") {
      if (state.phase !== "entscheidung") return state;
      if (action.atServerTime > state.phaseEndsAt) return state;
      if (state.kletterer[p]?.status !== "klettert") return state; // Zuschauer
      if (state.entscheidungen[p] !== undefined) return state; // eingerastet
      const wahl = action.action.wahl;
      const s = { ...state, entscheidungen: { ...state.entscheidungen, [p]: wahl } };
      // Absichern wirkt SOFORT (Kasse-Moment auf dem Screen) und ist endgültig.
      return wahl === "absichern" ? sichereAb(s, p) : s;
    }

    // ---------- Stufen-Antwort (NUR aktive Kletterer, erste zählt) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageStartetAt === null) return state;
    if (state.kletterer[p]?.status !== "klettert") return state; // Zuschauer-Wache
    if (state.answers[p] !== undefined) return state;
    if (action.atServerTime > state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
    const frage = aktuelleFrage(state);
    if (action.action.choice >= frage.options.length) return state;
    return {
      ...state,
      answers: {
        ...state.answers,
        [p]: {
          choice: action.action.choice,
          nachMs: Math.max(0, action.atServerTime - state.frageStartetAt),
          atServerTime: action.atServerTime,
        },
      },
    };
  },

  tick(state: RisikoLeiterState, ctx: Ctx): RisikoLeiterState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "entscheidung") {
      const offen = aktiveKletterer(state).filter(
        (p) => state.connected[p] && state.entscheidungen[p] === undefined,
      );
      if (now >= state.phaseEndsAt || offen.length === 0) {
        return schliesseEntscheidung(state, now);
      }
      return state;
    }

    if (state.phase === "frage") {
      const offen = aktiveKletterer(state).filter(
        (p) => state.connected[p] && state.answers[p] === undefined,
      );
      if (offen.length === 0 || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteStufeAus(state, now);
      }
      return state;
    }

    if (state.phase === "aufstieg") {
      if (now < state.phaseEndsAt) return state;
      // Gipfel erreicht oder niemand klettert mehr ⇒ Leiter-Bilanz.
      if (state.stufeNr >= RL_STUFEN || aktiveKletterer(state).length === 0) {
        return starteErgebnis(state, now);
      }
      return starteEntscheidung({ ...state, stufeNr: state.stufeNr + 1 }, now);
    }

    // Phase "ergebnis" vorbei ⇒ fertig (die Engine bucht und löst auf).
    if (now < state.phaseEndsAt) return state;
    return { ...state, finished: true };
  },

  onDisconnect(state: RisikoLeiterState, p: PlayerId, ctx: Ctx): RisikoLeiterState {
    void ctx;
    let s: RisikoLeiterState = { ...state, connected: { ...state.connected, [p]: false } };
    // Charmanter AFK-Schutz: ein Kletterer, der wegbricht, macht automatisch
    // Kasse auf dem aktuellen Stand — AUSSER seine Antwort der laufenden
    // Frage ist schon drin (dann zählt sie regulär im Aufstiegs-Beat).
    if (
      !s.finished &&
      s.kletterer[p]?.status === "klettert" &&
      (s.phase === "entscheidung" || (s.phase === "frage" && s.answers[p] === undefined))
    ) {
      s = sichereAb(s, p);
    }
    return s;
  },

  onReconnect(state: RisikoLeiterState, p: PlayerId, _ctx: Ctx): RisikoLeiterState {
    // Eine vollzogene Auto-Absicherung bleibt bestehen (Design — kein
    // Wiedereinstieg in die laufende Leiter).
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: RisikoLeiterState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const frageOffen = state.phase === "frage";
    const timerMs =
      state.phase === "entscheidung"
        ? RL_ENTSCHEIDUNG_MS
        : state.phase === "frage"
          ? state.timerMs
          : state.phase === "aufstieg"
            ? RL_AUFSTIEG_MS
            : RL_ERGEBNIS_MS;
    const scores = state.finished || state.phase === "ergebnis" ? berechneScores(state) : null;

    // Die Leitern nebeneinander (public): Stufe, Status, finale Gutschrift.
    const leitern = Object.fromEntries(
      state.players.map((p) => {
        const k = state.kletterer[p];
        return [
          p,
          {
            stufe: k.stufe,
            status: k.status,
            gutschrift: k.status === "klettert" ? null : k.gutschrift,
            endeAufStufe: k.endeAufStufe,
            verbunden: state.connected[p],
          },
        ];
      }),
    );

    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      stufeNr: state.stufeNr,
      stufen: RL_STUFEN,
      leiter: RL_LEITER,
      sicherheitsStufe: RL_SICHERHEITSSTUFE,
      jackpotBonus: RL_JACKPOT_BONUS,
      spieler: state.players,
      leitern,
      // Frage-Text/Optionen NUR im laufenden Fenster (Leak-Wache) — die
      // Zuschauer auf der Tribüne raten am Screen mit.
      text: frageOffen ? frage.text : null,
      options: frageOffen ? frage.options : null,
      schwierigkeit: frageOffen ? frage.difficulty : null,
      // Entscheidungs-Fortschritt: NUR die Anzahl (wer weiterklettert bleibt
      // bis zum Fenster-Ende geheim — Absicherungen sind über leitern public).
      entschiedenCount: Object.keys(state.entscheidungen).length,
      klettererCount: aktiveKletterer(state).length,
      answeredCount: frageOffen ? Object.keys(state.answers).length : 0,
      // Aufstiegs-Beat (inkl. correctIndex) erst NACH dem Fenster.
      letzterBeat: state.phase === "aufstieg" ? state.letzterBeat : null,
      ergebnis:
        scores !== null
          ? {
              uebersprungen: state.uebersprungen,
              gipfelstuermer: state.players.filter((p) => state.kletterer[p].status === "gipfel"),
            }
          : null,
      finished: state.finished,
    };

    const aufloesung = state.finished
      ? {
          correctIndex: state.letzterBeat?.correctIndex ?? null,
          erklaerung: state.uebersprungen
            ? "Leiter übersprungen — keine Zahlungen."
            : `Kasse gemacht = Leiter-Stand gesichert · Absturz = Sicherheitsstufe (Stufe ${RL_SICHERHEITSSTUFE} = ${rlLeiterWert(RL_SICHERHEITSSTUFE)} MM) · Gipfel = ${rlLeiterWert(RL_STUFEN)} + ${RL_JACKPOT_BONUS} Jackpot-Bonus.`,
          perPlayer: state.players.map((p) => {
            const k = state.kletterer[p];
            return {
              playerId: p,
              choice: null,
              correct: k.status === "gipfel" || (k.status === "abgesichert" && k.stufe > 0),
              delta: scores?.[p] ?? 0,
              stufe: k.stufe,
              status: k.status,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: Frage + Lösung + Entscheidungen + Antworten IMMER.
      return {
        ...basis,
        text: frage.text,
        options: frage.options,
        correctIndex: frage.answer,
        entscheidungen: state.entscheidungen,
        antworten: state.answers,
        aufloesung,
      };
    }
    if (role === "player") {
      const k = player !== undefined ? state.kletterer[player] : undefined;
      const klettert = k?.status === "klettert";
      return {
        ...basis,
        duKletterst: klettert === true,
        deinStatus: k?.status ?? null,
        deineStufe: k?.stufe ?? null,
        deinStand: k !== undefined ? rlLeiterWert(k.stufe) : null,
        naechsterWert: k !== undefined ? rlLeiterWert(k.stufe + 1) : null,
        deinSicherheitsWert: k !== undefined ? rlAbsturzWert(k.stufe) : null,
        deineGutschrift: k !== undefined && k.status !== "klettert" ? k.gutschrift : null,
        deineWahl:
          player !== undefined && state.phase === "entscheidung"
            ? (state.entscheidungen[player] ?? null)
            : null,
        yourChoice:
          frageOffen && player !== undefined ? (state.answers[player]?.choice ?? null) : null,
        // Antwort-Buttons NUR für aktive Kletterer — Abgesicherte/Abgestürzte
        // raten charmant als Zuschauer mit (eigenes Options-Feld ohne Draht).
        options: frageOffen && klettert ? frage.options : null,
        zuschauerOptionen: frageOffen && !klettert ? frage.options : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: RisikoLeiterState): boolean {
    return state.finished;
  },

  scores(state: RisikoLeiterState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM/Chronik. */
  outcomes(state: RisikoLeiterState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const k = state.kletterer[p];
      if (state.uebersprungen || k.status === "klettert") {
        result[p] = { correct: null };
        continue;
      }
      // Abgesichert auf dem Boden (Stufe 0) hat nichts beantwortet ⇒ null.
      result[p] = {
        correct:
          k.status === "gipfel"
            ? true
            : k.status === "abgestuerzt"
              ? false
              : k.stufe > 0
                ? true
                : null,
      };
    }
    return result;
  },
};
