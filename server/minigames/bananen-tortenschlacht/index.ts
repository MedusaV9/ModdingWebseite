// „Die große Bananen-Tortenschlacht" (Buzz-Klassiker, Money-Gewand):
// Jede Frage geht an ALLE aktiven Affen; alle Richtigen werden WERFER und
// wählen GEHEIM ein Ziel (wie Taschendieb) — die Torten landen dann in
// Antwort-Reihenfolge (schnellster Werfer zuerst, exakter Gleichstand ⇒
// Join-Reihenfolge, s. Taschendieb-Verfahren). 3 Torten = raus, der letzte
// saubere Affe gewinnt den Topf; Trost gestaffelt nach Überlebensdauer
// (Scoring dokumentiert in shared/minigames/bananen-tortenschlacht.meta.ts).
//
// EDGE-CASES (Design, verbindlich):
//   · Rauswurf-Reihenfolge bei Gleichstand: Torten landen SEQUENZIELL in
//     Wurf-Reihenfolge — wer seine 3. Torte früher kassiert, fliegt früher
//     (schlechterer Trost-Rang). Alle Torten einer Salve landen, auch wenn
//     der Werfer in derselben Salve selbst rausfliegt (gleichzeitig geworfen).
//   · Disconnect: Werfer offline OHNE Ziel-Wahl ⇒ seine Torte VERFÄLLT (kein
//     Timeout-Default-Wurf für Offline-Werfer). Hat er sein Ziel VOR dem
//     Disconnect eingerastet (oder steht es bei 2 Aktiven automatisch fest),
//     fliegt die Torte noch — geworfen ist geworfen. Aktive Offline-Affen
//     bleiben im Spiel und sind weiterhin bewerfbar (Anreiz zurückzukommen) —
//     antworten können sie nicht.
//   · 2 AKTIVE (auch 2-Spieler-Start): Ziel steht fest ⇒ Ziel-Wahl-Phase wird
//     übersprungen, jede Torte fliegt automatisch auf den Gegner.
//   · Fragen-Vorrat erschöpft, >1 aktiv ⇒ PUNKTSIEG: die saubersten Affen
//     teilen den Topf (10er-Rundung, Rest an frühere Join-Reihenfolge),
//     übrige Überlebende bekommen die oberste Trost-Stufe.
//   · Feld LEERGEFEGT (letzte Aktive fliegen in EINER Salve): der zuletzt
//     Rausgeworfene stand am längsten und gewinnt den Topf.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  TORTENSCHLACHT_META,
  TS_ERGEBNIS_MS,
  TS_FRAGE_MS,
  TS_NIEMAND_MS,
  TS_TOPF_MM,
  TS_TORTEN_RAUS,
  TS_WURF_MS,
  TS_ZIELWAHL_MS,
  tsTopfAnteile,
  tsTrost,
  type TortenschlachtAction,
} from "../../../shared/minigames/bananen-tortenschlacht.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export type TsPhase = "frage" | "zielwahl" | "wurf" | "niemand" | "ergebnis";

/** Eine gelandete Torte der letzten Salve (Wurf-Inszenierung am Screen). */
export interface TsWurf {
  von: string;
  zu: string;
  /** Sahne-Schicht auf dem Ziel NACH diesem Treffer (1/2/3 …). */
  schicht: number;
  /** Dieser Treffer war die 3. Torte — das Ziel fliegt raus. */
  raus: boolean;
}

export interface TortenschlachtState {
  players: PlayerId[];
  questions: Question[];
  timerFaktor: number;
  startedAt: number;
  phase: TsPhase;
  phaseEndsAt: number;
  timerMs: number; // aktuelles Frage-Fenster (Schwierigkeit × mods.timerFaktor)
  frageIndex: number;
  frageNonce: number; // zählt Frage-Starts (Client-Keying)
  frageStartetAt: number;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  /** Sahne-Schichten im Gesicht (0–3) — öffentlich sichtbar. */
  torten: Record<string, number>;
  /** Rauswurf-Reihenfolge (ältester zuerst) — Basis der Trost-Staffel. */
  raus: string[];
  /** Aktuelle Salve: Werfer in Wurf-Reihenfolge (Antwort-Tempo). */
  werfer: string[];
  /** GEHEIME Ziel-Wahl der Werfer (verlässt den Server nur Richtung GM). */
  zielWahl: Record<string, string>;
  /** Gelandete Torten der letzten Salve (Wurf-Reihenfolge, Anzeige). */
  wuerfe: TsWurf[];
  richtigGesamt: Record<string, number>;
  sieger: string[];
  siegerGrund: "letzter-sauberer" | "punktsieg" | "leergefegt" | null;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<TortenschlachtAction> | GmAction;

function aktuelleFrage(state: TortenschlachtState): Question {
  return state.questions[Math.min(state.frageIndex, state.questions.length - 1)];
}

function aktive(state: TortenschlachtState): PlayerId[] {
  return state.players.filter((p) => !state.raus.includes(p));
}

function frageFenster(state: TortenschlachtState, frage: Question): number {
  return Math.round(TS_FRAGE_MS[frage.difficulty] * state.timerFaktor);
}

/** Nächste Frage starten — oder Punktsieg, wenn der Vorrat erschöpft ist. */
function starteFrage(state: TortenschlachtState, now: number): TortenschlachtState {
  if (state.frageIndex + 1 >= state.questions.length && state.frageNonce > 0) {
    return starteErgebnis(state, now, "punktsieg");
  }
  const frageIndex = state.frageNonce === 0 ? 0 : state.frageIndex + 1;
  const s = { ...state, frageIndex };
  const timerMs = frageFenster(s, aktuelleFrage(s));
  return {
    ...s,
    phase: "frage",
    frageNonce: s.frageNonce + 1,
    frageStartetAt: now,
    phaseEndsAt: now + timerMs,
    timerMs,
    answers: {},
    werfer: [],
    zielWahl: {},
    wuerfe: [],
  };
}

/** Sieger küren: sauberste Aktive (bzw. Sonderfälle laut Kopf-Kommentar). */
function starteErgebnis(
  state: TortenschlachtState,
  now: number,
  grund: "letzter-sauberer" | "punktsieg" | "leergefegt",
): TortenschlachtState {
  let sieger: string[];
  if (grund === "leergefegt") {
    // Feld leer: der zuletzt Rausgeworfene stand am längsten.
    sieger = state.raus.length > 0 ? [state.raus[state.raus.length - 1]] : [];
  } else {
    const uebrig = aktive(state);
    const minTorten = Math.min(...uebrig.map((p) => state.torten[p] ?? 0));
    sieger = uebrig.filter((p) => (state.torten[p] ?? 0) === minTorten);
  }
  return {
    ...state,
    phase: "ergebnis",
    phaseEndsAt: now + TS_ERGEBNIS_MS,
    sieger,
    siegerGrund: grund,
  };
}

/** Default-Ziel: der SAUBERSTE aktive Gegner (Gleichstand ⇒ Join-Reihenfolge). */
function defaultZiel(state: TortenschlachtState, werfer: string): string | null {
  const kandidaten = aktive(state).filter((p) => p !== werfer);
  if (kandidaten.length === 0) return null;
  return kandidaten.reduce((best, p) =>
    (state.torten[p] ?? 0) < (state.torten[best] ?? 0) ? p : best,
  );
}

/**
 * Fragen-Ende auswerten: alle Richtigen werden Werfer (Wurf-Reihenfolge =
 * Antwort-Tempo, exakter Gleichstand ⇒ Join-Reihenfolge — Taschendieb-Muster).
 */
function werteFrageAus(state: TortenschlachtState, now: number): TortenschlachtState {
  const frage = aktuelleFrage(state);
  const werfer = aktive(state)
    .filter((p) => state.answers[p]?.choice === frage.answer)
    .sort((a, b) => state.answers[a].atServerTime - state.answers[b].atServerTime);
  if (werfer.length === 0) {
    return { ...state, phase: "niemand", phaseEndsAt: now + TS_NIEMAND_MS };
  }
  const s: TortenschlachtState = { ...state, werfer };
  // Nur 2 Aktive: das Ziel steht fest — Ziel-Wahl überspringen, direkt werfen.
  if (aktive(s).length === 2) {
    const zielWahl: Record<string, string> = {};
    for (const w of werfer) {
      const gegner = aktive(s).find((p) => p !== w);
      if (gegner !== undefined) zielWahl[w] = gegner;
    }
    return fuehreSalveAus({ ...s, zielWahl }, now);
  }
  return { ...s, phase: "zielwahl", phaseEndsAt: now + TS_ZIELWAHL_MS };
}

/**
 * Torten-Salve: Torten landen SEQUENZIELL in Wurf-Reihenfolge. 3. Torte ⇒
 * Rauswurf (Reihenfolge = Lande-Reihenfolge). Werfer ohne Wahl (Timeout)
 * werfen per Default auf den saubersten Gegner — NUR wenn sie verbunden sind:
 * Offline-Werfer ohne eingerastetes Ziel verlieren ihre Torte (Kopf-Kommentar).
 */
function fuehreSalveAus(state: TortenschlachtState, now: number): TortenschlachtState {
  const torten = { ...state.torten };
  const raus = [...state.raus];
  const wuerfe: TsWurf[] = [];
  for (const w of state.werfer) {
    const ziel = state.zielWahl[w] ?? (state.connected[w] ? defaultZiel(state, w) : null);
    if (ziel === null) continue;
    const schicht = (torten[ziel] ?? 0) + 1;
    torten[ziel] = schicht;
    const fliegtRaus = schicht === TS_TORTEN_RAUS;
    if (fliegtRaus) raus.push(ziel);
    wuerfe.push({ von: w, zu: ziel, schicht, raus: fliegtRaus });
  }
  const s: TortenschlachtState = {
    ...state,
    phase: "wurf",
    phaseEndsAt: now + TS_WURF_MS,
    torten,
    raus,
    wuerfe,
  };
  return s;
}

/** Nach der Salve: Schlacht entschieden oder nächste Frage. */
function nachSalve(state: TortenschlachtState, now: number): TortenschlachtState {
  const uebrig = aktive(state);
  if (uebrig.length === 0) return starteErgebnis(state, now, "leergefegt");
  if (uebrig.length === 1) return starteErgebnis(state, now, "letzter-sauberer");
  return starteFrage(state, now);
}

/**
 * Scores (Meta-Kopf, verbindlich): Sieger teilen den Topf (Rest an frühere
 * Join-Reihenfolge), Rausgeworfene kriegen die Trost-Staffel (k × 100),
 * Überlebende ohne Sieg die oberste Trost-Stufe.
 */
function berechneScores(state: TortenschlachtState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  if (state.siegerGrund === null) return result; // Abbruch vor dem Ergebnis
  state.raus.forEach((p, i) => {
    result[p as PlayerId] = tsTrost(i + 1);
  });
  for (const p of aktive(state)) {
    if (!state.sieger.includes(p)) result[p] = tsTrost(state.raus.length + 1);
  }
  const { anteil, rest } = tsTopfAnteile(state.sieger.length);
  const siegerInJoinReihenfolge = state.players.filter((p) => state.sieger.includes(p));
  siegerInJoinReihenfolge.forEach((p, i) => {
    result[p] = anteil + (i === 0 ? rest : 0);
  });
  return result;
}

export const tortenschlachtPlugin: MinigamePlugin<TortenschlachtState, TortenschlachtAction> = {
  meta: TORTENSCHLACHT_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): TortenschlachtState {
    if (content.questions.length === 0) {
      throw new Error("bananen-tortenschlacht: ContentSlice ohne Frage");
    }
    const now = ctx.clock.now();
    const basis: TortenschlachtState = {
      players,
      questions: content.questions,
      timerFaktor: content.mods?.timerFaktor ?? 1,
      startedAt: now,
      phase: "frage",
      phaseEndsAt: now,
      timerMs: 0,
      frageIndex: 0,
      frageNonce: 0,
      frageStartetAt: now,
      answers: {},
      torten: Object.fromEntries(players.map((p) => [p, 0])),
      raus: [],
      werfer: [],
      zielWahl: {},
      wuerfe: [],
      richtigGesamt: {},
      sieger: [],
      siegerGrund: null,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
    return starteFrage(basis, now);
  },

  reduce(state: TortenschlachtState, action: Action, ctx: Ctx): TortenschlachtState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: steht das Ergebnis, gilt es — sonst sofortiger Punktsieg.
        if (state.phase === "ergebnis") return { ...state, finished: true };
        return { ...starteErgebnis(state, ctx.clock.now(), "punktsieg"), finished: true };
      }
      if (action.type === "timer.extend") {
        return { ...state, phaseEndsAt: state.phaseEndsAt + action.ms };
      }
      // timer.shift (Pause): alle absoluten Zeitanker wandern mit.
      return {
        ...state,
        startedAt: state.startedAt + action.ms,
        phaseEndsAt: state.phaseEndsAt + action.ms,
        frageStartetAt: state.frageStartetAt + action.ms,
      };
    }
    if (state.finished) return state;

    if (action.action.type === "answer") {
      if (state.phase !== "frage") return state;
      const p = action.playerId;
      if (state.raus.includes(p)) return state; // Raus ist raus — nur zugucken.
      if (state.answers[p] !== undefined) return state; // erste Antwort zählt
      if (action.atServerTime > state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
      const richtig = action.action.choice === aktuelleFrage(state).answer;
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
        richtigGesamt: richtig
          ? { ...state.richtigGesamt, [p]: (state.richtigGesamt[p] ?? 0) + 1 }
          : state.richtigGesamt,
      };
    }

    // Geheime Ziel-Wahl: NUR Werfer, nur in der Ziel-Wahl-Phase, Ziel aktiv+fremd.
    if (action.action.type !== "wurf") return state;
    if (state.phase !== "zielwahl") return state;
    const werfer = action.playerId;
    if (!state.werfer.includes(werfer)) return state;
    if (state.zielWahl[werfer] !== undefined) return state; // eingerastet
    const ziel = action.action.targetId as PlayerId;
    if (ziel === werfer || !aktive(state).includes(ziel)) return state;
    const zielWahl = { ...state.zielWahl, [werfer]: ziel };
    const s = { ...state, zielWahl };
    // Alle verbundenen Werfer haben gewählt ⇒ Salve fliegt sofort.
    const offen = s.werfer.filter((w) => s.connected[w] && zielWahl[w] === undefined);
    if (offen.length === 0) return fuehreSalveAus(s, ctx.clock.now());
    return s;
  },

  tick(state: TortenschlachtState, ctx: Ctx): TortenschlachtState {
    if (state.finished) return state;
    const now = ctx.clock.now();
    if (state.phase === "frage") {
      // Sammel-Fenster (Taschendieb-Muster): Auswertung, sobald ALLE aktiven
      // Affen geantwortet haben oder das Gnadenfenster abgelaufen ist.
      const alleDa = aktive(state).every((p) => state.answers[p] !== undefined);
      if (alleDa || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteFrageAus(state, now);
      }
      return state;
    }
    if (now < state.phaseEndsAt) return state;
    if (state.phase === "zielwahl") return fuehreSalveAus(state, now);
    if (state.phase === "wurf") return nachSalve(state, now);
    if (state.phase === "niemand") return starteFrage(state, now);
    // Phase "ergebnis" vorbei ⇒ fertig (die Engine bucht und löst auf).
    return { ...state, finished: true };
  },

  onDisconnect(state: TortenschlachtState, p: PlayerId, ctx: Ctx): TortenschlachtState {
    const s: TortenschlachtState = { ...state, connected: { ...state.connected, [p]: false } };
    // Werfer fällt in der Ziel-Wahl weg: verfallen alle übrigen Wahlen dadurch
    // „komplett", fliegt die Salve sofort (sonst regelt der Timeout-Tick).
    if (!s.finished && s.phase === "zielwahl") {
      const offen = s.werfer.filter((w) => s.connected[w] && s.zielWahl[w] === undefined);
      if (offen.length === 0) return fuehreSalveAus(s, ctx.clock.now());
    }
    return s;
  },

  onReconnect(state: TortenschlachtState, p: PlayerId, _ctx: Ctx): TortenschlachtState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: TortenschlachtState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const timerMs =
      state.phase === "frage"
        ? state.timerMs
        : state.phase === "zielwahl"
          ? TS_ZIELWAHL_MS
          : state.phase === "wurf"
            ? TS_WURF_MS
            : state.phase === "niemand"
              ? TS_NIEMAND_MS
              : TS_ERGEBNIS_MS;
    const scores = state.finished || state.phase === "ergebnis" ? berechneScores(state) : null;
    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      // Sitzkreis-Slots für die Screen-Inszenierung (Namen mappt die App).
      spieler: state.players,
      verbunden: state.connected,
      torten: state.torten,
      tortenRaus: TS_TORTEN_RAUS,
      raus: state.raus,
      // Frage-Text/Optionen NUR im laufenden Fenster (Leak-Wache) — der
      // Screen zeigt sie auch im Wurf-Beat nicht mehr (Fokus: die Salve).
      text: state.phase === "frage" ? frage.text : null,
      options: state.phase === "frage" ? frage.options : null,
      schwierigkeit: frage.difficulty,
      answeredCount: Object.keys(state.answers).length,
      aktiveAnzahl: aktive(state).length,
      // Werfer sind ab der Ziel-Wahl öffentlich (Show-Moment „wer darf werfen").
      werfer: state.phase === "frage" ? [] : state.werfer,
      // Die Salve ist erst im Wurf-Beat öffentlich (geheime Ziel-Wahl davor!).
      wuerfe: state.phase === "wurf" || state.phase === "ergebnis" ? state.wuerfe : [],
      sieger: state.phase === "ergebnis" || state.finished ? state.sieger : [],
      siegerGrund: state.phase === "ergebnis" || state.finished ? state.siegerGrund : null,
      topf: TS_TOPF_MM,
      finished: state.finished,
    };
    const aufloesung = state.finished
      ? {
          correctIndex: frage.answer,
          erklaerung:
            state.siegerGrund === "punktsieg"
              ? "Punktsieg: die saubersten Affen teilen den Topf."
              : state.siegerGrund === "leergefegt"
                ? "Alle voll Sahne! Wer zuletzt fiel, stand am längsten — und gewinnt."
                : "Der letzte saubere Affe gewinnt den Topf!",
          sieger: state.sieger,
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: state.sieger.includes(p),
            delta: scores?.[p] ?? 0,
            torten: state.torten[p] ?? 0,
            rausAls: state.raus.indexOf(p) + 1 || null,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Lösung UND die geheimen Ziel-Wahlen IMMER.
      return {
        ...basis,
        text: frage.text,
        options: frage.options,
        correctIndex: frage.answer,
        zielWahl: state.zielWahl,
        aufloesung,
      };
    }
    if (role === "player") {
      const duBistRaus = player !== undefined && state.raus.includes(player);
      const istWerfer =
        player !== undefined && state.phase === "zielwahl" && state.werfer.includes(player);
      return {
        ...basis,
        you: player ?? null,
        duBistRaus,
        deineTorten: player !== undefined ? (state.torten[player] ?? 0) : 0,
        // Raus = Ehrentribüne: keine Antwort-Buttons mehr (Leak-frei via null).
        options: duBistRaus ? null : basis.options,
        yourChoice:
          player !== undefined && state.phase === "frage"
            ? (state.answers[player]?.choice ?? null)
            : null,
        istWerfer,
        // GEHEIME Ziel-Wahl: das Ziel-Grid sieht NUR der Werfer.
        ziele: istWerfer
          ? aktive(state)
              .filter((p) => p !== player)
              .map((p) => ({
                id: p,
                torten: state.torten[p] ?? 0,
                verbunden: state.connected[p],
              }))
          : null,
        deinZielGewaehlt: player !== undefined && state.zielWahl[player] !== undefined,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: TortenschlachtState): boolean {
    return state.finished;
  },

  scores(state: TortenschlachtState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM: Sieg = „richtig". */
  outcomes(state: TortenschlachtState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      result[p] = state.sieger.includes(p)
        ? { correct: true }
        : state.raus.includes(p)
          ? { correct: false }
          : { correct: (state.richtigGesamt[p] ?? 0) > 0 ? true : null };
    }
    return result;
  },
};
