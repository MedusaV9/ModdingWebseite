// „Bananen-Boxkampf" (Buzz-Klassiker, Money-Gewand): 1v1 im Boxring.
//
// ABLAUF (eine Runden-Instanz, meta.roundBased):
//   herausforderung (10 s: der LETZTE des Zwischenstands wählt den Gegner;
//   Feiglings-Schutz wie am Lianensteg: der ärmste Gegner ist nicht wählbar,
//   solange es Alternativen gibt; Timeout = Führender) → wetten (10 s, nur
//   mit Zuschauern: feste 50-MM-Siegerwette, geheim bis Wettschluss) →
//   je Frage: countdown (3 s Ring-Gong) → frage (10 s Speed-MC-4, die Antwort
//   IST der Buzz) → schlag (3,5 s Punch-Cutscene) … → ergebnis (8 s K.O.-/
//   Punktsieg-Cutscene + Wett-Abrechnung).
//
// HP-MATHE: beide starten mit 100 HP; jede RICHTIGE Antwort ist ein Schlag
// mit BX_PUNCH[difficulty] Schaden. Sind BEIDE richtig, ordnet ctx.buzzer die
// Schläge (Median-RTT-faire Zeiten + Fotofinish-Los; Fallback ohne Engine-Ctx:
// ordneBuzzes mit ctx.rng) — der Schnellere schlägt ZUERST. Bringt der
// Erstschlag den Gegner auf 0, ENTFÄLLT dessen Konter (K.O. ist K.O. — die
// Buzzer-Reihenfolge entscheidet Kämpfe!). K.O. beendet sofort; sonst
// Punktsieg nach BX_RUNDEN Fragen (mehr Rest-HP; Gleichstand = Unentschieden,
// je 150, Wetten zurück).
// EDGE-CASES: Boxer-Disconnect ⇒ kampflos (Sieger +300 Bank, KEIN Abzug,
// Wetten zurück); beide offline ⇒ Abbruch (alle 0); GM-Skip vor dem Ergebnis
// ⇒ Abbruch ohne Zahlung; 2-Spieler-Spiel ⇒ keine Herausforderungs-/Wett-Phase.
// Der Verlierer zahlt NIE (sportlicher Faustkampf, s. Meta-Kopf).
import { ordneBuzzes, type BuzzErgebnis, type BuzzKandidat } from "../../../shared/buzzer";
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  BOXKAMPF_META,
  BX_COUNTDOWN_MS,
  BX_ERGEBNIS_MS,
  BX_FRAGE_MS,
  BX_GETEILT_MM,
  BX_HERAUSFORDERUNG_MS,
  BX_MAX_HP,
  BX_PUNCH,
  BX_RUNDEN,
  BX_SCHLAG_MS,
  BX_WETTE_MM,
  BX_WETTEN_MS,
  bxSiegPraemie,
  bxWettAbrechnung,
  type BoxkampfAction,
} from "../../../shared/minigames/bananen-boxkampf.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export type BxPhase = "herausforderung" | "wetten" | "countdown" | "frage" | "schlag" | "ergebnis";

/** Ein gelandeter Schlag des letzten Schlagabtauschs (Punch-Inszenierung). */
export interface BxSchlag {
  von: string;
  schaden: number;
  /** Zweitschlag im selben Abtausch (der Langsamere schlägt zurück). */
  konter: boolean;
  /** Dieser Schlag brachte den Gegner auf 0 — K.O.! */
  ko: boolean;
}

/** Ergebnis der letzten Frage — Grundlage des Schlag-Beats. */
export interface BxSchlagabtausch {
  questionId: string;
  correctIndex: number;
  schlaege: BxSchlag[];
  fotofinish: boolean;
  antworten: Record<string, { choice: number; nachMs: number }>;
}

export interface BoxkampfState {
  players: PlayerId[];
  questions: Question[];
  startedAt: number;
  phase: BxPhase;
  phaseEndsAt: number;
  timerMs: number; // Frage-Fenster (mit mods.timerFaktor)
  /** Konto-Snapshot beim init (ctx.match) — Letzter/Führender/Feigling. */
  balances: Record<string, number> | null;
  herausforderer: PlayerId;
  gegner: PlayerId | null;
  /** Zuschauer-Wetten: Wetter → getippter Boxer (geheim bis Wettschluss). */
  wetten: Record<string, string>;
  wettenGeschlossen: boolean;
  frageNonce: number;
  frageIndex: number;
  rundeNr: number; // 1-basierte Frage im Kampf (max. BX_RUNDEN)
  frageStartetAt: number | null;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  hp: Record<string, number>;
  letzterAbtausch: BxSchlagabtausch | null;
  sieger: PlayerId | null;
  verlierer: PlayerId | null;
  ko: boolean;
  geteilt: boolean;
  kampflos: boolean;
  abgebrochen: boolean;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<BoxkampfAction> | GmAction;

function boxer(state: BoxkampfState): PlayerId[] {
  return state.gegner === null ? [state.herausforderer] : [state.herausforderer, state.gegner];
}

function zuschauer(state: BoxkampfState): PlayerId[] {
  const b = boxer(state);
  return state.players.filter((p) => !b.includes(p));
}

function kontoVon(state: BoxkampfState, p: string): number {
  return state.balances?.[p] ?? 0;
}

function aktuelleFrage(state: BoxkampfState): Question {
  return state.questions[state.frageIndex % state.questions.length];
}

/** Der Letzte des Zwischenstands (Gleichstand: frühere Join-Reihenfolge). */
function letzterSpieler(players: PlayerId[], balances: Record<string, number> | null): PlayerId {
  if (balances === null) return players[0];
  return players.reduce((arm, p) => ((balances[p] ?? 0) < (balances[arm] ?? 0) ? p : arm));
}

/** Gegner-Kandidaten inkl. Feiglings-Schutz (Lianensteg-Regel, §Kopf). */
export function bxGegnerKandidaten(
  state: BoxkampfState,
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

/** Timeout-/Auto-Gegner: der reichste wählbare („der Führende steigt in den Ring"). */
function defaultGegner(state: BoxkampfState): PlayerId | null {
  const waehlbare = bxGegnerKandidaten(state).filter((k) => k.waehlbar);
  if (waehlbare.length === 0) return null;
  return waehlbare.reduce((best, k) =>
    kontoVon(state, k.id) > kontoVon(state, best.id) ? k : best,
  ).id;
}

function starteWettenOderKampf(state: BoxkampfState, now: number): BoxkampfState {
  if (zuschauer(state).length === 0) {
    return { ...starteCountdown(state, now), wettenGeschlossen: true };
  }
  return { ...state, phase: "wetten", phaseEndsAt: now + BX_WETTEN_MS };
}

function starteCountdown(state: BoxkampfState, now: number): BoxkampfState {
  return {
    ...state,
    phase: "countdown",
    phaseEndsAt: now + BX_COUNTDOWN_MS,
    wettenGeschlossen: true,
    frageNonce: state.frageNonce + 1,
    rundeNr: state.rundeNr + 1,
    frageStartetAt: null,
    answers: {},
  };
}

function starteErgebnis(
  state: BoxkampfState,
  now: number,
  sieger: PlayerId | null,
  flags: Partial<Pick<BoxkampfState, "ko" | "geteilt" | "kampflos" | "abgebrochen">> = {},
): BoxkampfState {
  const b = boxer(state);
  const verlierer =
    sieger !== null && b.length === 2 ? (b.find((p) => p !== sieger) ?? null) : null;
  return {
    ...state,
    phase: "ergebnis",
    phaseEndsAt: now + BX_ERGEBNIS_MS,
    sieger,
    verlierer,
    ...flags,
  };
}

/**
 * Frage auswerten: jede richtige Antwort ist ein Schlag. Beide richtig ⇒
 * Buzzer-Reihenfolge (Erstschlag zuerst, K.O. schluckt den Konter).
 */
function werteFrageAus(state: BoxkampfState, now: number, ctx: Ctx): BoxkampfState {
  const frage = aktuelleFrage(state);
  const schaden = BX_PUNCH[frage.difficulty];
  const richtige = boxer(state).filter((p) => state.answers[p]?.choice === frage.answer);

  let reihenfolge: PlayerId[] = richtige;
  let fotofinish = false;
  if (richtige.length >= 2) {
    const kandidaten: BuzzKandidat[] = richtige.map((p) => ({
      playerId: p,
      finalAt: state.answers[p].atServerTime,
    }));
    // Buzzer-Fairness (TECH-SPEC §3.3): Engine-Ranking inkl. Fotofinish-Los;
    // in isolierten Tests ohne ctx.buzzer: dasselbe pure Modul mit ctx.rng.
    const geordnet: BuzzErgebnis[] = ctx.buzzer
      ? ctx.buzzer.ordne(kandidaten)
      : ordneBuzzes(kandidaten, ctx.rng);
    reihenfolge = [...geordnet].sort((a, b) => a.rank - b.rank).map((e) => e.playerId as PlayerId);
    fotofinish = geordnet.some((e) => e.fotofinish);
  }

  const hp = { ...state.hp };
  const schlaege: BxSchlag[] = [];
  for (const [i, p] of reihenfolge.entries()) {
    const opfer = boxer(state).find((x) => x !== p);
    if (opfer === undefined) break;
    if ((hp[p] ?? 0) <= 0) break; // schon am Boden — kein Konter mehr (K.O.!)
    hp[opfer] = Math.max(0, (hp[opfer] ?? 0) - schaden);
    schlaege.push({ von: p, schaden, konter: i > 0, ko: hp[opfer] === 0 });
    if (hp[opfer] === 0) break; // K.O. beendet den Abtausch sofort
  }

  return {
    ...state,
    hp,
    letzterAbtausch: {
      questionId: frage.id,
      correctIndex: frage.answer,
      schlaege,
      fotofinish,
      antworten: Object.fromEntries(
        Object.entries(state.answers).map(([p, a]) => [p, { choice: a.choice, nachMs: a.nachMs }]),
      ),
    },
    phase: "schlag",
    phaseEndsAt: now + BX_SCHLAG_MS,
  };
}

/** Nach dem Schlag-Beat: K.O./Punktsieg prüfen oder nächste Frage läuten. */
function nachSchlag(state: BoxkampfState, now: number): BoxkampfState {
  const [a, b] = boxer(state);
  if (b === undefined) return starteErgebnis(state, now, null, { abgebrochen: true });
  if ((state.hp[a] ?? 0) <= 0) return starteErgebnis(state, now, b, { ko: true });
  if ((state.hp[b] ?? 0) <= 0) return starteErgebnis(state, now, a, { ko: true });
  if (state.rundeNr >= BX_RUNDEN) {
    // Punktsieg: mehr Rest-HP gewinnt; Gleichstand = Unentschieden.
    if ((state.hp[a] ?? 0) === (state.hp[b] ?? 0)) {
      return starteErgebnis(state, now, null, { geteilt: true });
    }
    return starteErgebnis(state, now, (state.hp[a] ?? 0) > (state.hp[b] ?? 0) ? a : b);
  }
  return starteCountdown({ ...state, frageIndex: state.frageIndex + 1 }, now);
}

/** Boxer-Offline-Wache (Kampf läuft): kampflos bzw. Abbruch. */
function pruefeBoxerOffline(state: BoxkampfState, now: number): BoxkampfState | null {
  const b = boxer(state);
  if (b.length < 2) return null;
  const offline = b.filter((p) => !state.connected[p]);
  if (offline.length === 0) return null;
  if (offline.length === b.length) {
    return starteErgebnis(state, now, null, { abgebrochen: true });
  }
  const anwesend = b.find((p) => state.connected[p]) as PlayerId;
  return starteErgebnis(state, now, anwesend, { kampflos: true });
}

/** Scores (Meta-Kopf): Bank-Prämie + pari-mutuel Wett-Deltas (nullsummig). */
function berechneScores(state: BoxkampfState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  if (state.abgebrochen) return result;
  const [a, b] = boxer(state);
  if (state.geteilt && b !== undefined) {
    result[a] = BX_GETEILT_MM;
    result[b] = BX_GETEILT_MM;
    return result; // Wetten zurück (alle 0)
  }
  if (state.sieger === null) return result;
  result[state.sieger] += bxSiegPraemie(state.ko);
  if (!state.kampflos) {
    const wetten = bxWettAbrechnung(state.wetten, state.sieger);
    for (const [w, delta] of Object.entries(wetten.deltas)) {
      result[w as PlayerId] = (result[w as PlayerId] ?? 0) + delta;
    }
    result[state.sieger] += wetten.restAnSieger;
  }
  return result;
}

export const boxkampfPlugin: MinigamePlugin<BoxkampfState, BoxkampfAction> = {
  meta: BOXKAMPF_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): BoxkampfState {
    if (content.questions.length === 0) {
      throw new Error("bananen-boxkampf: ContentSlice ohne Frage");
    }
    const now = ctx.clock.now();
    const match = ctx.match;
    const balances = match ? Object.fromEntries(players.map((p) => [p, match.balance(p)])) : null;
    const herausforderer = letzterSpieler(players, balances);
    const basis: BoxkampfState = {
      players,
      questions: content.questions,
      startedAt: now,
      phase: "herausforderung",
      phaseEndsAt: now + BX_HERAUSFORDERUNG_MS,
      timerMs: Math.round(BX_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      balances,
      herausforderer,
      gegner: null,
      wetten: {},
      wettenGeschlossen: false,
      frageNonce: 0,
      frageIndex: 0,
      rundeNr: 0,
      frageStartetAt: null,
      answers: {},
      hp: {},
      letzterAbtausch: null,
      sieger: null,
      verlierer: null,
      ko: false,
      geteilt: false,
      kampflos: false,
      abgebrochen: false,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
    // 2-Spieler-Spiel: Gegner steht fest, keine Zuschauer ⇒ direkt in den Ring.
    if (players.length === 2) {
      const gegner = players.find((p) => p !== herausforderer) as PlayerId;
      return starteCountdown(
        {
          ...basis,
          gegner,
          wettenGeschlossen: true,
          hp: { [herausforderer]: BX_MAX_HP, [gegner]: BX_MAX_HP },
        },
        now,
      );
    }
    return basis;
  },

  reduce(state: BoxkampfState, action: Action, ctx: Ctx): BoxkampfState {
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
      const kandidat = bxGegnerKandidaten(state).find((k) => k.id === ziel);
      if (!kandidat?.waehlbar) return state; // Feiglings-Schutz/offline/selbst
      return starteWettenOderKampf(
        {
          ...state,
          gegner: ziel,
          hp: { [state.herausforderer]: BX_MAX_HP, [ziel]: BX_MAX_HP },
        },
        ctx.clock.now(),
      );
    }

    // ---------- Zuschauer-Wette (fest 50 MM, eine pro Zuschauer) ----------
    if (action.action.type === "wette") {
      if (state.phase !== "wetten" || state.wettenGeschlossen) return state;
      const p = action.playerId;
      if (!zuschauer(state).includes(p)) return state;
      if (state.wetten[p] !== undefined) return state; // eingerastet
      const auf = action.action.auf;
      if (!boxer(state).includes(auf as PlayerId)) return state;
      return { ...state, wetten: { ...state.wetten, [p]: auf } };
    }

    // ---------- Speed-MC-4-Antwort (NUR Boxer, die Antwort IST der Buzz) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageStartetAt === null) return state;
    const p = action.playerId;
    if (!boxer(state).includes(p)) return state;
    if (state.answers[p] !== undefined) return state; // erste Antwort zählt
    if (action.atServerTime > state.phaseEndsAt + SPAETANTWORT_GNADE_MS) return state;
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

  tick(state: BoxkampfState, ctx: Ctx): BoxkampfState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "herausforderung") {
      if (now < state.phaseEndsAt) return state;
      const gegner = defaultGegner(state);
      if (gegner === null) {
        // Kein wählbarer Gegner (alle offline): der Kampf fällt aus.
        return { ...starteErgebnis(state, now, null, { abgebrochen: true }), finished: true };
      }
      return starteWettenOderKampf(
        {
          ...state,
          gegner,
          hp: { [state.herausforderer]: BX_MAX_HP, [gegner]: BX_MAX_HP },
        },
        now,
      );
    }

    if (state.phase === "wetten") {
      const offeneWetter = zuschauer(state).filter(
        (z) => state.connected[z] && state.wetten[z] === undefined,
      );
      if (now >= state.phaseEndsAt || offeneWetter.length === 0) {
        return starteCountdown(state, now);
      }
      return state;
    }

    // Ab hier läuft der Kampf: Offline-Wache VOR jedem Fortschritt.
    if (state.phase === "countdown" || state.phase === "frage") {
      const offline = pruefeBoxerOffline(state, now);
      if (offline !== null) return offline;
    }

    if (state.phase === "countdown") {
      if (now < state.phaseEndsAt) return state;
      return {
        ...state,
        phase: "frage",
        frageStartetAt: now,
        phaseEndsAt: now + state.timerMs,
      };
    }

    if (state.phase === "frage") {
      const alleGeantwortet = boxer(state).every((b) => state.answers[b] !== undefined);
      if (alleGeantwortet || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteFrageAus(state, now, ctx);
      }
      return state;
    }

    if (now < state.phaseEndsAt) return state;
    if (state.phase === "schlag") return nachSchlag(state, now);
    // Phase "ergebnis" vorbei ⇒ fertig (die Engine bucht und löst auf).
    return { ...state, finished: true };
  },

  onDisconnect(state: BoxkampfState, p: PlayerId, ctx: Ctx): BoxkampfState {
    const s: BoxkampfState = { ...state, connected: { ...state.connected, [p]: false } };
    // Boxer fällt MITTEN im Kampf weg ⇒ sofort kampflos/Abbruch (Design).
    if (
      !s.finished &&
      (s.phase === "countdown" || s.phase === "frage" || s.phase === "schlag") &&
      boxer(s).includes(p)
    ) {
      return pruefeBoxerOffline(s, ctx.clock.now()) ?? s;
    }
    return s;
  },

  onReconnect(state: BoxkampfState, p: PlayerId, _ctx: Ctx): BoxkampfState {
    // Ein bereits entschiedenes kampflos-Ergebnis bleibt bestehen (Design).
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: BoxkampfState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const [a, b] = boxer(state);
    const timerMs =
      state.phase === "herausforderung"
        ? BX_HERAUSFORDERUNG_MS
        : state.phase === "wetten"
          ? BX_WETTEN_MS
          : state.phase === "countdown"
            ? BX_COUNTDOWN_MS
            : state.phase === "frage"
              ? state.timerMs
              : state.phase === "schlag"
                ? BX_SCHLAG_MS
                : BX_ERGEBNIS_MS;
    const scores = state.finished || state.phase === "ergebnis" ? berechneScores(state) : null;
    const wettAbrechnung =
      scores !== null && state.sieger !== null && !state.kampflos && !state.geteilt
        ? bxWettAbrechnung(state.wetten, state.sieger)
        : null;

    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      rundeNr: state.rundeNr,
      runden: BX_RUNDEN,
      herausforderer: state.herausforderer,
      gegner: state.gegner,
      spieler: state.players,
      hp: state.hp,
      maxHp: BX_MAX_HP,
      punch: BX_PUNCH[frage.difficulty],
      // Wetten: während des Wett-Fensters NUR die Anzahl (geheim!), danach
      // hängen die Fähnchen öffentlich an den Ringseilen (Steg-Muster).
      wettenAnzahl: Object.keys(state.wetten).length,
      wetten: state.wettenGeschlossen ? state.wetten : null,
      wetteMM: BX_WETTE_MM,
      // Frage-Text/Optionen NUR im laufenden Fenster (Leak-Wache).
      text: state.phase === "frage" ? frage.text : null,
      options: state.phase === "frage" ? frage.options : null,
      answeredCount: Object.keys(state.answers).length,
      // Schlagabtausch-Ergebnis (inkl. correctIndex) erst im Schlag-Beat.
      letzterAbtausch: state.phase === "schlag" ? state.letzterAbtausch : null,
      ergebnis:
        scores !== null
          ? {
              sieger: state.sieger,
              verlierer: state.verlierer,
              ko: state.ko,
              geteilt: state.geteilt,
              kampflos: state.kampflos,
              abgebrochen: state.abgebrochen,
              praemie: state.geteilt ? BX_GETEILT_MM : bxSiegPraemie(state.ko),
              restAnSieger: wettAbrechnung?.restAnSieger ?? 0,
            }
          : null,
      finished: state.finished,
    };

    const aufloesung = state.finished
      ? {
          correctIndex: state.letzterAbtausch?.correctIndex ?? null,
          erklaerung: state.abgebrochen
            ? "Kampf abgebrochen — keine Zahlungen, Wetten zurück."
            : state.geteilt
              ? "Punktegleichstand: UNENTSCHIEDEN — je 150 MM, Wetten zurück."
              : state.kampflos
                ? "Kampfloser Sieg (Gegner offline): 300 MM aus der Bank, Wetten zurück."
                : state.ko
                  ? "K.O.-Sieg: 400 MM aus der Bank. Richtige Wetten teilen den Wett-Topf."
                  : "Punktsieg (mehr Rest-HP): 300 MM aus der Bank. Richtige Wetten teilen den Topf.",
          perPlayer: state.players.map((p) => {
            const wette = state.wetten[p];
            return {
              playerId: p,
              choice: null,
              correct:
                p === state.sieger ||
                (state.geteilt && boxer(state).includes(p)) ||
                (wette !== undefined && !state.kampflos && !state.geteilt
                  ? wette === state.sieger
                  : false),
              delta: scores?.[p] ?? 0,
              hp: state.hp[p] ?? null,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: GM sieht die richtige Antwort + alle Wetten IMMER.
      return {
        ...basis,
        text: frage.text,
        options: frage.options,
        correctIndex: frage.answer,
        wetten: state.wetten,
        aufloesung,
      };
    }
    if (role === "player") {
      const istBoxer = player !== undefined && boxer(state).includes(player);
      const istHerausforderer = player === state.herausforderer;
      return {
        ...basis,
        duBistBoxer: istBoxer,
        duBistHerausforderer: istHerausforderer,
        deinHp: istBoxer && player !== undefined ? (state.hp[player] ?? BX_MAX_HP) : null,
        yourChoice:
          player !== undefined && state.phase === "frage"
            ? (state.answers[player]?.choice ?? null)
            : null,
        deineWette: player !== undefined ? (state.wetten[player] ?? null) : null,
        // Gegner-Wahl-Grid sieht NUR der Herausforderer im Wahl-Fenster.
        waehlbareGegner:
          istHerausforderer && state.phase === "herausforderung"
            ? bxGegnerKandidaten(state).map((k) => ({
                ...k,
                kontostand: state.balances === null ? null : kontoVon(state, k.id),
              }))
            : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung, boxerA: a ?? null, boxerB: b ?? null };
  },

  isFinished(state: BoxkampfState): boolean {
    return state.finished;
  },

  scores(state: BoxkampfState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM/Chronik. */
  outcomes(state: BoxkampfState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    const b = boxer(state);
    for (const p of state.players) {
      if (state.abgebrochen) {
        result[p] = { correct: null };
        continue;
      }
      if (b.includes(p)) {
        result[p] = state.geteilt
          ? { correct: true }
          : state.sieger === p
            ? { correct: true }
            : state.kampflos
              ? { correct: null } // offline — keine Wertung (kein Streak-Riss)
              : { correct: state.sieger !== null ? false : null };
        continue;
      }
      const wette = state.wetten[p];
      result[p] =
        wette === undefined || state.sieger === null || state.kampflos || state.geteilt
          ? { correct: null }
          : { correct: wette === state.sieger };
    }
    return result;
  },
};
