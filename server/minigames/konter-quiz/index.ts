// „Konter-Quiz" (freundliches 1v1-Schnellrate-Duell): Duellanten-Auswahl nach
// dem Herausforderer-Muster des Boxkampfs, dann KQ_RUNDEN kurze Fragen à ~8 s.
//
// ABLAUF (eine Runden-Instanz, meta.roundBased):
//   herausforderung (10 s: der LETZTE des Zwischenstands wählt den Gegner;
//   Feiglings-Schutz: der ärmste Gegner ist nicht wählbar, solange es
//   Alternativen gibt; Timeout = Führender) → countdown (3 s Duell-Gong) →
//   je Frage: frage (8 s Speed-MC-4, die Antwort IST der Buzz) → konter
//   (3,5 s Beat: Bank-Prämien + Konter-Gutschriften fliegen sichtbar) … →
//   ergebnis (7 s Duell-Bilanz).
//
// GELD-MATHE (Single Source of Truth: kqFrageDeltas in der Meta):
//   richtig = +150 Bank · falsch = 150 als KONTER-GUTSCHRIFT zum Partner
//   (Transfer-Anteil EXAKT nullsummig) · keine Antwort = nichts.
// RUNDENPUNKT (Duell-Balken, ohne Extra-Geld): sind BEIDE richtig, ordnet
// ctx.buzzer die Antworten fair (Median-RTT + Fotofinish-Los; Fallback ohne
// Engine-Ctx: ordneBuzzes mit ctx.rng) — die schnellere holt den Punkt.
// EDGE-CASES: Duellant-Disconnect ⇒ Runde endet SOFORT und OHNE Transfer
// (Bank bleibt, Konter-Gutschriften storniert); 2-Spieler-Spiel ⇒ keine
// Herausforderungs-Phase; GM-Skip vor dem Ergebnis ⇒ Abbruch ohne Zahlung;
// kein wählbarer Gegner (alle offline) ⇒ Abbruch. POOL-WÄCHTER: init filtert
// kaputte Fragen (Optionen/Antwort-Index) und wirft ohne brauchbare Frage.
import { ordneBuzzes, type BuzzErgebnis, type BuzzKandidat } from "../../../shared/buzzer";
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  KONTER_QUIZ_META,
  KQ_COUNTDOWN_MS,
  KQ_ERGEBNIS_MS,
  KQ_FRAGE_MS,
  KQ_HERAUSFORDERUNG_MS,
  KQ_KONTER_MM,
  KQ_KONTER_MS,
  KQ_RICHTIG_MM,
  KQ_RUNDEN,
  kqFrageDeltas,
  type KonterQuizAction,
} from "../../../shared/minigames/konter-quiz.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export type KqPhase = "herausforderung" | "countdown" | "frage" | "konter" | "ergebnis";

/** Ergebnis der letzten Frage — Grundlage des Konter-Beats. */
export interface KqRundenErgebnis {
  questionId: string;
  correctIndex: number;
  antworten: Record<string, { choice: number; nachMs: number }>;
  /** Bank-Prämien DIESER Frage (nur ≥ 0). */
  bank: Record<string, number>;
  /** Konter-Gutschriften DIESER Frage (Σ = 0). */
  transfer: Record<string, number>;
  /** Rundenpunkt: die schnellste RICHTIGE Antwort (Buzzer-Reihenfolge). */
  punktFuer: string | null;
  fotofinish: boolean;
}

export interface KonterQuizState {
  players: PlayerId[];
  questions: Question[];
  startedAt: number;
  phase: KqPhase;
  phaseEndsAt: number;
  timerMs: number; // Frage-Fenster (mit mods.timerFaktor)
  /** Konto-Snapshot beim init (ctx.match) — Letzter/Führender/Feigling. */
  balances: Record<string, number> | null;
  herausforderer: PlayerId;
  gegner: PlayerId | null;
  frageNonce: number;
  frageIndex: number;
  rundeNr: number; // 1-basierte Frage im Duell (max. KQ_RUNDEN)
  frageStartetAt: number | null;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  /** Kumulierte Bank-Prämien (nur ≥ 0). */
  bank: Record<string, number>;
  /** Kumulierte Konter-Gutschriften (Σ = 0, solange kein Disconnect-Storno). */
  transfer: Record<string, number>;
  /** Duell-Balken: Rundenpunkte je Duellant (reine Show-Wertung). */
  punkte: Record<string, number>;
  richtigZaehler: Record<string, number>;
  falschZaehler: Record<string, number>;
  letzteAntwortMs: Record<string, number>;
  letzteRunde: KqRundenErgebnis | null;
  /** Duellant-Disconnect: Duell endete vorzeitig, Transfers storniert. */
  ohneTransfer: boolean;
  vorzeitig: boolean;
  abgebrochen: boolean;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<KonterQuizAction> | GmAction;

function duellanten(state: KonterQuizState): PlayerId[] {
  return state.gegner === null ? [state.herausforderer] : [state.herausforderer, state.gegner];
}

function kontoVon(state: KonterQuizState, p: string): number {
  return state.balances?.[p] ?? 0;
}

function aktuelleFrage(state: KonterQuizState): Question {
  return state.questions[state.frageIndex % state.questions.length];
}

/** Der Letzte des Zwischenstands (Gleichstand: frühere Join-Reihenfolge). */
function letzterSpieler(players: PlayerId[], balances: Record<string, number> | null): PlayerId {
  if (balances === null) return players[0];
  return players.reduce((arm, p) => ((balances[p] ?? 0) < (balances[arm] ?? 0) ? p : arm));
}

/** Gegner-Kandidaten inkl. Feiglings-Schutz (Boxkampf-/Lianensteg-Regel). */
export function kqGegnerKandidaten(
  state: KonterQuizState,
): { id: PlayerId; waehlbar: boolean; verbunden: boolean }[] {
  const andere = state.players.filter((p) => p !== state.herausforderer);
  const verbundene = andere.filter((p) => state.connected[p]);
  let geschuetzt: PlayerId | null = null;
  if (state.balances !== null && verbundene.length >= 2) {
    const aermster = verbundene.reduce((arm, p) =>
      kontoVon(state, p) < kontoVon(state, arm) ? p : arm,
    );
    const striktAermer = verbundene.every(
      (p) => p === aermster || kontoVon(state, p) > kontoVon(state, aermster),
    );
    if (striktAermer) geschuetzt = aermster;
  }
  return andere.map((id) => ({
    id,
    waehlbar: state.connected[id] === true && id !== geschuetzt,
    verbunden: state.connected[id] === true,
  }));
}

/** Timeout-/Auto-Gegner: der reichste wählbare („der Führende muss ran"). */
function defaultGegner(state: KonterQuizState): PlayerId | null {
  const waehlbare = kqGegnerKandidaten(state).filter((k) => k.waehlbar);
  if (waehlbare.length === 0) return null;
  return waehlbare.reduce((best, k) =>
    kontoVon(state, k.id) > kontoVon(state, best.id) ? k : best,
  ).id;
}

function starteCountdown(state: KonterQuizState, now: number): KonterQuizState {
  return { ...state, phase: "countdown", phaseEndsAt: now + KQ_COUNTDOWN_MS };
}

function starteFrage(state: KonterQuizState, now: number): KonterQuizState {
  return {
    ...state,
    phase: "frage",
    phaseEndsAt: now + state.timerMs,
    frageNonce: state.frageNonce + 1,
    rundeNr: state.rundeNr + 1,
    frageStartetAt: now,
    answers: {},
  };
}

function starteErgebnis(
  state: KonterQuizState,
  now: number,
  flags: Partial<Pick<KonterQuizState, "ohneTransfer" | "vorzeitig" | "abgebrochen">> = {},
): KonterQuizState {
  return { ...state, phase: "ergebnis", phaseEndsAt: now + KQ_ERGEBNIS_MS, ...flags };
}

/**
 * Frage auswerten: Bank-Prämien + Konter-Gutschriften (kqFrageDeltas, exakt
 * nullsummiger Transfer) + Rundenpunkt über die Buzzer-Reihenfolge.
 */
function werteFrageAus(state: KonterQuizState, now: number, ctx: Ctx): KonterQuizState {
  const frage = aktuelleFrage(state);
  const [a, b] = duellanten(state);
  if (b === undefined) return starteErgebnis(state, now, { abgebrochen: true });
  const deltas = kqFrageDeltas([a, b], state.answers, frage.answer);

  // Rundenpunkt: schnellste RICHTIGE Antwort — bei zweien entscheidet die
  // faire Buzzer-Reihenfolge (Engine: ctx.buzzer; isolierte Tests: ordneBuzzes).
  const richtige = [a, b].filter((p) => state.answers[p]?.choice === frage.answer);
  let punktFuer: string | null = richtige[0] ?? null;
  let fotofinish = false;
  if (richtige.length >= 2) {
    const kandidaten: BuzzKandidat[] = richtige.map((p) => ({
      playerId: p,
      finalAt: state.answers[p].atServerTime,
    }));
    const geordnet: BuzzErgebnis[] = ctx.buzzer
      ? ctx.buzzer.ordne(kandidaten)
      : ordneBuzzes(kandidaten, ctx.rng);
    punktFuer = geordnet.find((e) => e.rank === 1)?.playerId ?? null;
    fotofinish = geordnet.some((e) => e.fotofinish);
  }

  const bank = { ...state.bank };
  const transfer = { ...state.transfer };
  const punkte = { ...state.punkte };
  const richtigZaehler = { ...state.richtigZaehler };
  const falschZaehler = { ...state.falschZaehler };
  const letzteAntwortMs = { ...state.letzteAntwortMs };
  for (const p of [a, b]) {
    bank[p] = (bank[p] ?? 0) + (deltas.bank[p] ?? 0);
    transfer[p] = (transfer[p] ?? 0) + (deltas.transfer[p] ?? 0);
    const antwort = state.answers[p];
    if (antwort !== undefined) {
      letzteAntwortMs[p] = antwort.nachMs;
      if (antwort.choice === frage.answer) richtigZaehler[p] = (richtigZaehler[p] ?? 0) + 1;
      else falschZaehler[p] = (falschZaehler[p] ?? 0) + 1;
    }
  }
  if (punktFuer !== null) punkte[punktFuer] = (punkte[punktFuer] ?? 0) + 1;

  return {
    ...state,
    bank,
    transfer,
    punkte,
    richtigZaehler,
    falschZaehler,
    letzteAntwortMs,
    letzteRunde: {
      questionId: frage.id,
      correctIndex: frage.answer,
      antworten: Object.fromEntries(
        Object.entries(state.answers).map(([p, x]) => [p, { choice: x.choice, nachMs: x.nachMs }]),
      ),
      bank: deltas.bank,
      transfer: deltas.transfer,
      punktFuer,
      fotofinish,
    },
    phase: "konter",
    phaseEndsAt: now + KQ_KONTER_MS,
  };
}

/** Nach dem Konter-Beat: letzte Frage vorbei ⇒ Ergebnis, sonst nächste Frage. */
function nachKonter(state: KonterQuizState, now: number): KonterQuizState {
  if (state.rundeNr >= KQ_RUNDEN) return starteErgebnis(state, now);
  return starteFrage({ ...state, frageIndex: state.frageIndex + 1 }, now);
}

/** Duellant-Offline-Wache: die Runde endet SOFORT und OHNE Transfer. */
function pruefeDuellantOffline(state: KonterQuizState, now: number): KonterQuizState | null {
  const d = duellanten(state);
  if (d.length < 2) return null;
  if (d.every((p) => state.connected[p])) return null;
  return starteErgebnis(state, now, { ohneTransfer: true, vorzeitig: true });
}

/** Show-Sieger nach Rundenpunkten (reine Anzeige — Geld ist längst verbucht). */
function siegerNachPunkten(state: KonterQuizState): PlayerId | null {
  const [a, b] = duellanten(state);
  if (b === undefined || state.vorzeitig || state.abgebrochen) return null;
  const pa = state.punkte[a] ?? 0;
  const pb = state.punkte[b] ?? 0;
  if (pa === pb) return null;
  return pa > pb ? a : b;
}

/** Scores (Meta-Kopf): Bank + Transfer — Transfers storniert bei Disconnect. */
function berechneScores(state: KonterQuizState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  if (state.abgebrochen) return result;
  for (const p of duellanten(state)) {
    result[p] = (state.bank[p] ?? 0) + (state.ohneTransfer ? 0 : (state.transfer[p] ?? 0));
  }
  return result;
}

export const konterQuizPlugin: MinigamePlugin<KonterQuizState, KonterQuizAction> = {
  meta: KONTER_QUIZ_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): KonterQuizState {
    // Pool-Integritäts-Wächter: nur Fragen mit sauberem Options/Antwort-Paar
    // erreichen das Duell — ganz ohne brauchbare Frage startet kein Kampf.
    const questions = content.questions.filter(
      (q) =>
        q.text.length > 0 &&
        q.options.length >= 2 &&
        Number.isInteger(q.answer) &&
        q.answer >= 0 &&
        q.answer < q.options.length,
    );
    if (questions.length === 0) {
      throw new Error("konter-quiz: ContentSlice ohne brauchbare Frage");
    }
    const now = ctx.clock.now();
    const match = ctx.match;
    const balances = match ? Object.fromEntries(players.map((p) => [p, match.balance(p)])) : null;
    const herausforderer = letzterSpieler(players, balances);
    const basis: KonterQuizState = {
      players,
      questions,
      startedAt: now,
      phase: "herausforderung",
      phaseEndsAt: now + KQ_HERAUSFORDERUNG_MS,
      timerMs: Math.round(KQ_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      balances,
      herausforderer,
      gegner: null,
      frageNonce: 0,
      frageIndex: 0,
      rundeNr: 0,
      frageStartetAt: null,
      answers: {},
      bank: {},
      transfer: {},
      punkte: {},
      richtigZaehler: {},
      falschZaehler: {},
      letzteAntwortMs: {},
      letzteRunde: null,
      ohneTransfer: false,
      vorzeitig: false,
      abgebrochen: false,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
    // 2-Spieler-Spiel: Gegner steht fest — direkt zum Duell-Gong.
    if (players.length === 2) {
      const gegner = players.find((p) => p !== herausforderer) as PlayerId;
      return starteCountdown({ ...basis, gegner }, now);
    }
    return basis;
  },

  reduce(state: KonterQuizState, action: Action, ctx: Ctx): KonterQuizState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: steht das Ergebnis schon, gilt es — sonst Abbruch ohne Zahlung.
        if (state.phase === "ergebnis") return { ...state, finished: true };
        return { ...state, abgebrochen: true, finished: true };
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

    // ---------- Gegner-Wahl (NUR der Herausforderer, nur im Wahl-Fenster) ----------
    if (action.action.type === "herausfordern") {
      if (state.phase !== "herausforderung") return state;
      if (action.playerId !== state.herausforderer) return state;
      const ziel = action.action.targetId as PlayerId;
      const kandidat = kqGegnerKandidaten(state).find((k) => k.id === ziel);
      if (!kandidat?.waehlbar) return state; // Feiglings-Schutz/offline/selbst
      return starteCountdown({ ...state, gegner: ziel }, ctx.clock.now());
    }

    // ---------- Speed-MC-4-Antwort (NUR Duellanten, die Antwort IST der Buzz) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageStartetAt === null) return state;
    const p = action.playerId;
    if (!duellanten(state).includes(p)) return state;
    if (state.answers[p] !== undefined) return state; // erste Antwort zählt
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

  tick(state: KonterQuizState, ctx: Ctx): KonterQuizState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "herausforderung") {
      if (now < state.phaseEndsAt) return state;
      const gegner = defaultGegner(state);
      if (gegner === null) {
        // Kein wählbarer Gegner (alle offline): das Duell fällt aus.
        return { ...starteErgebnis(state, now, { abgebrochen: true }), finished: true };
      }
      return starteCountdown({ ...state, gegner }, now);
    }

    // Ab hier läuft das Duell: Offline-Wache VOR jedem Fortschritt.
    if (state.phase === "countdown" || state.phase === "frage" || state.phase === "konter") {
      const offline = pruefeDuellantOffline(state, now);
      if (offline !== null) return offline;
    }

    if (state.phase === "countdown") {
      if (now < state.phaseEndsAt) return state;
      return starteFrage(state, now);
    }

    if (state.phase === "frage") {
      const alleGeantwortet = duellanten(state).every((d) => state.answers[d] !== undefined);
      if (alleGeantwortet || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteFrageAus(state, now, ctx);
      }
      return state;
    }

    if (now < state.phaseEndsAt) return state;
    if (state.phase === "konter") return nachKonter(state, now);
    // Phase "ergebnis" vorbei ⇒ fertig (die Engine bucht und löst auf).
    return { ...state, finished: true };
  },

  onDisconnect(state: KonterQuizState, p: PlayerId, ctx: Ctx): KonterQuizState {
    const s: KonterQuizState = { ...state, connected: { ...state.connected, [p]: false } };
    // Duellant fällt MITTEN im Duell weg ⇒ sofort Ende ohne Transfer (Design).
    if (
      !s.finished &&
      (s.phase === "countdown" || s.phase === "frage" || s.phase === "konter") &&
      duellanten(s).includes(p)
    ) {
      return pruefeDuellantOffline(s, ctx.clock.now()) ?? s;
    }
    return s;
  },

  onReconnect(state: KonterQuizState, p: PlayerId, _ctx: Ctx): KonterQuizState {
    // Ein bereits beendetes Duell bleibt beendet (Design — kein Wiedereinstieg).
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: KonterQuizState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const [a, b] = duellanten(state);
    const timerMs =
      state.phase === "herausforderung"
        ? KQ_HERAUSFORDERUNG_MS
        : state.phase === "countdown"
          ? KQ_COUNTDOWN_MS
          : state.phase === "frage"
            ? state.timerMs
            : state.phase === "konter"
              ? KQ_KONTER_MS
              : KQ_ERGEBNIS_MS;
    const scores = state.finished || state.phase === "ergebnis" ? berechneScores(state) : null;
    const sieger = siegerNachPunkten(state);

    // Live-Duell-Balken (Zuschauer-Futter): Punkte + laufende Geld-Bilanz.
    const bilanz = Object.fromEntries(
      duellanten(state).map((p) => [
        p,
        (state.bank[p] ?? 0) + (state.ohneTransfer ? 0 : (state.transfer[p] ?? 0)),
      ]),
    );

    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      rundeNr: state.rundeNr,
      runden: KQ_RUNDEN,
      herausforderer: state.herausforderer,
      gegner: state.gegner,
      spieler: state.players,
      punkte: state.punkte,
      bilanz,
      praemieMM: KQ_RICHTIG_MM,
      konterMM: KQ_KONTER_MM,
      // Frage-Text/Optionen NUR im laufenden Fenster (Leak-Wache).
      text: state.phase === "frage" ? frage.text : null,
      options: state.phase === "frage" ? frage.options : null,
      answeredCount: Object.keys(state.answers).length,
      // Runden-Ergebnis (inkl. correctIndex) erst im Konter-Beat.
      letzteRunde: state.phase === "konter" ? state.letzteRunde : null,
      ergebnis:
        scores !== null
          ? {
              sieger,
              geteilt: sieger === null && !state.vorzeitig && !state.abgebrochen && b !== undefined,
              vorzeitig: state.vorzeitig,
              ohneTransfer: state.ohneTransfer,
              abgebrochen: state.abgebrochen,
              punkte: state.punkte,
            }
          : null,
      finished: state.finished,
    };

    const aufloesung = state.finished
      ? {
          correctIndex: state.letzteRunde?.correctIndex ?? null,
          erklaerung: state.abgebrochen
            ? "Duell abgebrochen — keine Zahlungen."
            : state.vorzeitig
              ? "Duell endete vorzeitig (Duellant offline) — Bank-Prämien bleiben, alle Konter-Gutschriften storniert."
              : "Richtig zahlt 150 MM aus der Bank — jede falsche Antwort schenkt dem Partner 150 MM Konter-Gutschrift.",
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: duellanten(state).includes(p)
              ? (state.richtigZaehler[p] ?? 0) > (state.falschZaehler[p] ?? 0)
              : false,
            delta: scores?.[p] ?? 0,
            bank: state.bank[p] ?? 0,
            transfer: state.ohneTransfer ? 0 : (state.transfer[p] ?? 0),
            punkte: state.punkte[p] ?? null,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht Frage + richtige Antwort + Antworten IMMER.
      return {
        ...basis,
        text: frage.text,
        options: frage.options,
        correctIndex: frage.answer,
        antworten: state.answers,
        aufloesung,
      };
    }
    if (role === "player") {
      const istDuellant = player !== undefined && duellanten(state).includes(player);
      const istHerausforderer = player === state.herausforderer;
      return {
        ...basis,
        duBistDuellant: istDuellant,
        duBistHerausforderer: istHerausforderer,
        yourChoice:
          player !== undefined && state.phase === "frage"
            ? (state.answers[player]?.choice ?? null)
            : null,
        // Antwort-Buttons NUR für Duellanten (Zuschauer raten im Kopf mit).
        options: istDuellant && state.phase === "frage" ? frage.options : null,
        // Gegner-Wahl-Grid sieht NUR der Herausforderer im Wahl-Fenster.
        waehlbareGegner:
          istHerausforderer && state.phase === "herausforderung"
            ? kqGegnerKandidaten(state).map((k) => ({
                ...k,
                kontostand: state.balances === null ? null : kontoVon(state, k.id),
              }))
            : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung, duellantA: a ?? null, duellantB: b ?? null };
  },

  isFinished(state: KonterQuizState): boolean {
    return state.finished;
  },

  scores(state: KonterQuizState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM/Chronik. */
  outcomes(state: KonterQuizState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    const d = duellanten(state);
    for (const p of state.players) {
      if (!d.includes(p) || state.abgebrochen) {
        result[p] = { correct: null };
        continue;
      }
      const richtig = state.richtigZaehler[p] ?? 0;
      const falsch = state.falschZaehler[p] ?? 0;
      result[p] = {
        correct: richtig === falsch ? null : richtig > falsch,
        nachMs: state.letzteAntwortMs[p],
      };
    }
    return result;
  },
};
