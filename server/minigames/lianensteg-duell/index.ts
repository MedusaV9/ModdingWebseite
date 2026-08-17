// „Duell am Lianensteg" (GAME-DESIGN §2.12/6, Detail docs/ideen/02 Nr. 15):
// 1v1-Buzzer-Duell auf dem Hängesteg — Herausforderer-Prinzip + Zuschauer-Wetten.
//
// ABLAUF (eine Runden-Instanz, meta.roundBased):
//   herausforderung (10 s: der LETZTE des Zwischenstands wählt den Gegner;
//   Feiglings-Schutz: der ärmste Gegner ist nicht wählbar, solange es
//   Alternativen gibt — der Führende ist IMMER wählbar; Timeout = Führender)
//   → wetten (10 s, nur mit Zuschauern: feste 50-MM-Siegerwette, geheim bis
//   Wettschluss) → je Teilfrage: countdown (3 s) → frage (10 s Speed-MC-4,
//   die Antwort IST der Buzz) → schubs (3 s Teilfragen-Ergebnis) … →
//   ergebnis (8 s Sieger-Cutscene + Wett-Abrechnung).
//
// REGELN: Best-of-5 (3 Siege beenden sofort); beide richtig ⇒ ctx.buzzer.ordne
// (Median-RTT-faire Zeiten + Fotofinish-Los; Fallback ohne Engine-Ctx:
// ordneBuzzes mit ctx.rng). Beide falsch ⇒ Stand unverändert, nächste Frage.
// Gleichstand nach 5 ⇒ Sudden Death (max. 2, Teilfragen-Sieger gewinnt das
// Duell); Fotofinish IM Sudden Death ⇒ GETEILTER Sieg (je 150, Wetten zurück).
// Sieger: +300 (Bank) + 100 DIREKT vom Verlierer (nullsummiger Transfer) +
// Wett-Topf-Rundungsrest („Trinkgeld"). Wetten pari-mutuel, EXAKT nullsummig
// (shared/minigames/lianensteg-duell.meta.ts#ldWettAbrechnung).
// EDGE-CASES: Duellant-Disconnect ⇒ kampflos (Sieger +300, KEIN Konto-Abzug,
// Wetten zurück); beide offline ⇒ Abbruch (alle 0); GM-Skip (force.finish
// vor dem Ergebnis) ⇒ Abbruch ohne Zahlung; 2-Spieler-Spiel ⇒ keine
// Herausforderungs-/Wett-Phase (Gegner automatisch). Ungerade Spielerzahl ist
// unkritisch: es duellieren immer genau 2, der Rest wird Wett-Publikum.
import type { ContentSlice, Question } from "../../../shared/content";
import { ordneBuzzes, type BuzzErgebnis, type BuzzKandidat } from "../../../shared/buzzer";
import type { PlayerId } from "../../../shared/ids";
import {
  LD_BESTOF,
  LD_COUNTDOWN_MS,
  LD_ERGEBNIS_MS,
  LD_FRAGE_MS,
  LD_GETEILT_MM,
  LD_HERAUSFORDERUNG_MS,
  LD_SCHUBS_MS,
  LD_SIEG_BANK_MM,
  LD_SIEG_TRANSFER_MM,
  LD_SIEGE,
  LD_SUDDEN_DEATH_MAX,
  LD_WETTE_MM,
  LD_WETTEN_MS,
  LIANENSTEG_DUELL_META,
  ldWettAbrechnung,
  type LianenstegDuellAction,
} from "../../../shared/minigames/lianensteg-duell.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export type LdPhase = "herausforderung" | "wetten" | "countdown" | "frage" | "schubs" | "ergebnis";

/** Ergebnis der letzten Teilfrage — Grundlage der Schubs-Inszenierung. */
export interface LdTeilfrage {
  questionId: string;
  correctIndex: number;
  gewinner: string | null;
  fotofinish: boolean;
  antworten: Record<string, { choice: number; nachMs: number }>;
}

export interface LianenstegDuellState {
  players: PlayerId[];
  questions: Question[];
  startedAt: number;
  phase: LdPhase;
  phaseEndsAt: number;
  timerMs: number; // Teilfragen-Fenster (mit mods.timerFaktor)
  /** Konto-Snapshot beim init (ctx.match) — Letzter/Führender/Feigling. */
  balances: Record<string, number> | null;
  herausforderer: PlayerId;
  gegner: PlayerId | null;
  /** Zuschauer-Wetten: Wetter → getippter Duellant (geheim bis Wettschluss). */
  wetten: Record<string, string>;
  wettenGeschlossen: boolean;
  frageNonce: number;
  frageIndex: number;
  teilfrage: number; // 1-basiert (zählt auch Sudden-Death-Fragen)
  suddenDeath: number; // 0 = regulär, 1..MAX = Sudden-Death-Nummer
  frageStartetAt: number | null;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  siege: Record<string, number>;
  letzteTeilfrage: LdTeilfrage | null;
  sieger: PlayerId | null;
  verlierer: PlayerId | null;
  geteilt: boolean;
  kampflos: boolean;
  abgebrochen: boolean;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<LianenstegDuellAction> | GmAction;

function duellanten(state: LianenstegDuellState): PlayerId[] {
  return state.gegner === null ? [state.herausforderer] : [state.herausforderer, state.gegner];
}

function zuschauer(state: LianenstegDuellState): PlayerId[] {
  const d = duellanten(state);
  return state.players.filter((p) => !d.includes(p));
}

function kontoVon(state: LianenstegDuellState, p: string): number {
  return state.balances?.[p] ?? 0;
}

function aktuelleFrage(state: LianenstegDuellState): Question {
  return state.questions[state.frageIndex % state.questions.length];
}

/** Der Letzte des Zwischenstands (Gleichstand: frühere Join-Reihenfolge). */
function letzterSpieler(players: PlayerId[], balances: Record<string, number> | null): PlayerId {
  if (balances === null) return players[0];
  return players.reduce((arm, p) => ((balances[p] ?? 0) < (balances[arm] ?? 0) ? p : arm));
}

/** Gegner-Kandidaten des Herausforderers inkl. Feiglings-Schutz-Markierung. */
export function gegnerKandidaten(
  state: LianenstegDuellState,
): { id: PlayerId; waehlbar: boolean; verbunden: boolean }[] {
  const andere = state.players.filter((p) => p !== state.herausforderer);
  const verbundene = andere.filter((p) => state.connected[p]);
  // Feiglings-Schutz: der STRIKT ärmste verbundene Gegner ist geschützt —
  // aber nur, wenn danach noch jemand wählbar bleibt (und Konten bekannt sind).
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

/** Timeout-/Auto-Gegner: der reichste wählbare (Design: „der Führende"). */
function defaultGegner(state: LianenstegDuellState): PlayerId | null {
  const waehlbare = gegnerKandidaten(state).filter((k) => k.waehlbar);
  if (waehlbare.length === 0) return null;
  return waehlbare.reduce((best, k) =>
    kontoVon(state, k.id) > kontoVon(state, best.id) ? k : best,
  ).id;
}

function starteWettenOderDuell(state: LianenstegDuellState, now: number): LianenstegDuellState {
  if (zuschauer(state).length === 0) {
    return { ...starteCountdown(state, now), wettenGeschlossen: true };
  }
  return { ...state, phase: "wetten", phaseEndsAt: now + LD_WETTEN_MS };
}

function starteCountdown(state: LianenstegDuellState, now: number): LianenstegDuellState {
  return {
    ...state,
    phase: "countdown",
    phaseEndsAt: now + LD_COUNTDOWN_MS,
    wettenGeschlossen: true,
    frageNonce: state.frageNonce + 1,
    teilfrage: state.teilfrage + 1,
    frageStartetAt: null,
    answers: {},
  };
}

function starteErgebnis(
  state: LianenstegDuellState,
  now: number,
  sieger: PlayerId | null,
  flags: Partial<Pick<LianenstegDuellState, "geteilt" | "kampflos" | "abgebrochen">> = {},
): LianenstegDuellState {
  const d = duellanten(state);
  const verlierer =
    sieger !== null && d.length === 2 ? (d.find((p) => p !== sieger) ?? null) : null;
  return {
    ...state,
    phase: "ergebnis",
    phaseEndsAt: now + LD_ERGEBNIS_MS,
    sieger,
    verlierer,
    ...flags,
  };
}

/** Teilfrage auswerten: 1 Richtiger gewinnt; 2 Richtige ⇒ Buzzer-Ranking. */
function werteTeilfrageAus(
  state: LianenstegDuellState,
  now: number,
  ctx: Ctx,
): LianenstegDuellState {
  const frage = aktuelleFrage(state);
  const richtige = duellanten(state)
    .filter((p) => state.answers[p]?.choice === frage.answer)
    .sort((a, b) => state.answers[a].atServerTime - state.answers[b].atServerTime);

  let gewinner: PlayerId | null = null;
  let fotofinish = false;
  if (richtige.length === 1) gewinner = richtige[0];
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
    const erster = geordnet.find((e) => e.rank === 1);
    gewinner = (erster?.playerId ?? richtige[0]) as PlayerId;
    fotofinish = geordnet.some((e) => e.fotofinish);
    // Doppelter Sudden-Death-Gleichstand (<Fotofinish-Fenster): GETEILTER Sieg.
    if (state.suddenDeath > 0 && fotofinish) {
      return starteErgebnis(state, now, null, { geteilt: true });
    }
  }

  const siege = { ...state.siege };
  if (gewinner !== null) siege[gewinner] = (siege[gewinner] ?? 0) + 1;
  return {
    ...state,
    siege,
    letzteTeilfrage: {
      questionId: frage.id,
      correctIndex: frage.answer,
      gewinner,
      fotofinish,
      antworten: Object.fromEntries(
        Object.entries(state.answers).map(([p, a]) => [p, { choice: a.choice, nachMs: a.nachMs }]),
      ),
    },
    phase: "schubs",
    phaseEndsAt: now + LD_SCHUBS_MS,
  };
}

/** Nach dem Schubs-Beat: Duell-Ende prüfen oder nächste Teilfrage starten. */
function nachSchubs(state: LianenstegDuellState, now: number): LianenstegDuellState {
  const [a, b] = duellanten(state);
  const siegeA = state.siege[a] ?? 0;
  const siegeB = b !== undefined ? (state.siege[b] ?? 0) : 0;
  if (siegeA >= LD_SIEGE) return starteErgebnis(state, now, a);
  if (b !== undefined && siegeB >= LD_SIEGE) return starteErgebnis(state, now, b);

  if (state.suddenDeath > 0) {
    // Sudden Death: der Teilfragen-Sieger gewinnt das DUELL sofort.
    const gewinner = state.letzteTeilfrage?.gewinner ?? null;
    if (gewinner !== null) return starteErgebnis(state, now, gewinner as PlayerId);
    if (state.suddenDeath >= LD_SUDDEN_DEATH_MAX) {
      return starteErgebnis(state, now, null, { geteilt: true });
    }
    return starteCountdown(
      { ...state, suddenDeath: state.suddenDeath + 1, frageIndex: state.frageIndex + 1 },
      now,
    );
  }

  if (state.teilfrage >= LD_BESTOF) {
    if (siegeA !== siegeB) {
      return starteErgebnis(state, now, siegeA > siegeB ? a : (b as PlayerId));
    }
    return starteCountdown({ ...state, suddenDeath: 1, frageIndex: state.frageIndex + 1 }, now);
  }
  return starteCountdown({ ...state, frageIndex: state.frageIndex + 1 }, now);
}

/** Duellanten-Offline-Wache (Duell läuft): kampflos bzw. Abbruch. */
function pruefeDuellantenOffline(
  state: LianenstegDuellState,
  now: number,
): LianenstegDuellState | null {
  const d = duellanten(state);
  if (d.length < 2) return null;
  const offline = d.filter((p) => !state.connected[p]);
  if (offline.length === 0) return null;
  if (offline.length === d.length) {
    return starteErgebnis(state, now, null, { abgebrochen: true });
  }
  const anwesend = d.find((p) => state.connected[p]) as PlayerId;
  return starteErgebnis(state, now, anwesend, { kampflos: true });
}

/** Scores (§ Kopf-Kommentar): Prämie + Transfer + pari-mutuel Wett-Deltas. */
function berechneScores(state: LianenstegDuellState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  if (state.abgebrochen) return result;
  const [a, b] = duellanten(state);
  if (state.geteilt && b !== undefined) {
    result[a] = LD_GETEILT_MM;
    result[b] = LD_GETEILT_MM;
    return result; // Wetten zurück (alle 0)
  }
  if (state.sieger === null) return result;
  result[state.sieger] += LD_SIEG_BANK_MM;
  if (!state.kampflos && state.verlierer !== null) {
    result[state.sieger] += LD_SIEG_TRANSFER_MM;
    result[state.verlierer] -= LD_SIEG_TRANSFER_MM;
    const wetten = ldWettAbrechnung(state.wetten, state.sieger);
    for (const [w, delta] of Object.entries(wetten.deltas)) {
      result[w as PlayerId] = (result[w as PlayerId] ?? 0) + delta;
    }
    result[state.sieger] += wetten.restAnSieger;
  }
  return result;
}

export const lianenstegDuellPlugin: MinigamePlugin<LianenstegDuellState, LianenstegDuellAction> = {
  meta: LIANENSTEG_DUELL_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): LianenstegDuellState {
    if (content.questions.length === 0) {
      throw new Error("lianensteg-duell: ContentSlice ohne Frage");
    }
    const now = ctx.clock.now();
    const match = ctx.match;
    const balances = match ? Object.fromEntries(players.map((p) => [p, match.balance(p)])) : null;
    const herausforderer = letzterSpieler(players, balances);
    const basis: LianenstegDuellState = {
      players,
      questions: content.questions,
      startedAt: now,
      phase: "herausforderung",
      phaseEndsAt: now + LD_HERAUSFORDERUNG_MS,
      timerMs: Math.round(LD_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      balances,
      herausforderer,
      gegner: null,
      wetten: {},
      wettenGeschlossen: false,
      frageNonce: 0,
      frageIndex: 0,
      teilfrage: 0,
      suddenDeath: 0,
      frageStartetAt: null,
      answers: {},
      siege: {},
      letzteTeilfrage: null,
      sieger: null,
      verlierer: null,
      geteilt: false,
      kampflos: false,
      abgebrochen: false,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
    // 2-Spieler-Spiel: Gegner steht fest, keine Zuschauer ⇒ direkt Countdown.
    if (players.length === 2) {
      const gegner = players.find((p) => p !== herausforderer) as PlayerId;
      return starteCountdown({ ...basis, gegner, wettenGeschlossen: true }, now);
    }
    return basis;
  },

  reduce(state: LianenstegDuellState, action: Action, ctx: Ctx): LianenstegDuellState {
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
      const kandidat = gegnerKandidaten(state).find((k) => k.id === ziel);
      if (!kandidat?.waehlbar) return state; // Feiglings-Schutz/offline/selbst
      return starteWettenOderDuell({ ...state, gegner: ziel }, ctx.clock.now());
    }

    // ---------- Zuschauer-Wette (fest 50 MM, eine pro Zuschauer) ----------
    if (action.action.type === "wette") {
      if (state.phase !== "wetten" || state.wettenGeschlossen) return state;
      const p = action.playerId;
      if (!zuschauer(state).includes(p)) return state;
      if (state.wetten[p] !== undefined) return state; // eingerastet
      const auf = action.action.auf;
      if (!duellanten(state).includes(auf as PlayerId)) return state;
      return { ...state, wetten: { ...state.wetten, [p]: auf } };
    }

    // ---------- Speed-MC-4-Antwort (NUR Duellanten, die Antwort IST der Buzz) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageStartetAt === null) return state;
    const p = action.playerId;
    if (!duellanten(state).includes(p)) return state;
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

  tick(state: LianenstegDuellState, ctx: Ctx): LianenstegDuellState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "herausforderung") {
      if (now < state.phaseEndsAt) return state;
      const gegner = defaultGegner(state);
      if (gegner === null) {
        // Kein wählbarer Gegner (alle offline): Duell fällt aus.
        return { ...starteErgebnis(state, now, null, { abgebrochen: true }), finished: true };
      }
      return starteWettenOderDuell({ ...state, gegner }, now);
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

    // Ab hier läuft das Duell: Offline-Wache VOR jedem Fortschritt.
    if (state.phase === "countdown" || state.phase === "frage") {
      const offline = pruefeDuellantenOffline(state, now);
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
      const alleGeantwortet = duellanten(state).every((d) => state.answers[d] !== undefined);
      if (alleGeantwortet || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteTeilfrageAus(state, now, ctx);
      }
      return state;
    }

    if (now < state.phaseEndsAt) return state;
    if (state.phase === "schubs") return nachSchubs(state, now);
    // Phase "ergebnis" vorbei ⇒ fertig (die Engine bucht und löst auf).
    return { ...state, finished: true };
  },

  onDisconnect(state: LianenstegDuellState, p: PlayerId, ctx: Ctx): LianenstegDuellState {
    const s: LianenstegDuellState = { ...state, connected: { ...state.connected, [p]: false } };
    // Duellant fällt MITTEN im Duell weg ⇒ sofort kampflos/Abbruch (Design).
    if (
      !s.finished &&
      (s.phase === "countdown" || s.phase === "frage" || s.phase === "schubs") &&
      duellanten(s).includes(p)
    ) {
      return pruefeDuellantenOffline(s, ctx.clock.now()) ?? s;
    }
    return s;
  },

  onReconnect(state: LianenstegDuellState, p: PlayerId, _ctx: Ctx): LianenstegDuellState {
    // Ein bereits entschiedenes kampflos-Ergebnis bleibt bestehen (Design).
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: LianenstegDuellState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const [a, b] = duellanten(state);
    const timerMs =
      state.phase === "herausforderung"
        ? LD_HERAUSFORDERUNG_MS
        : state.phase === "wetten"
          ? LD_WETTEN_MS
          : state.phase === "countdown"
            ? LD_COUNTDOWN_MS
            : state.phase === "frage"
              ? state.timerMs
              : state.phase === "schubs"
                ? LD_SCHUBS_MS
                : LD_ERGEBNIS_MS;
    const scores = state.finished || state.phase === "ergebnis" ? berechneScores(state) : null;
    const siegeA = state.siege[a] ?? 0;
    const siegeB = b !== undefined ? (state.siege[b] ?? 0) : 0;
    const wettAbrechnung =
      scores !== null && state.sieger !== null && !state.kampflos && !state.geteilt
        ? ldWettAbrechnung(state.wetten, state.sieger)
        : null;

    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      teilfrage: state.teilfrage,
      bestOf: LD_BESTOF,
      siegeZiel: LD_SIEGE,
      suddenDeath: state.suddenDeath,
      herausforderer: state.herausforderer,
      gegner: state.gegner,
      spieler: state.players,
      siege: state.siege,
      /** Steg-Stand aus Sicht des Herausforderers: + schubst den Gegner. */
      stand: Math.max(-LD_SIEGE, Math.min(LD_SIEGE, siegeA - siegeB)),
      // Wetten: während des Wett-Fensters NUR die Anzahl (geheim!), danach
      // hängen die Fähnchen öffentlich an den Seilen (Design).
      wettenAnzahl: Object.keys(state.wetten).length,
      wetten: state.wettenGeschlossen ? state.wetten : null,
      wetteMM: LD_WETTE_MM,
      // Frage-Text/Optionen NUR im laufenden Teilfragen-Fenster (Leak-Wache).
      text: state.phase === "frage" ? frage.text : null,
      options: state.phase === "frage" ? frage.options : null,
      answeredCount: Object.keys(state.answers).length,
      // Teilfragen-Ergebnis (inkl. correctIndex) erst im Schubs-Beat.
      letzteTeilfrage: state.phase === "schubs" ? state.letzteTeilfrage : null,
      ergebnis:
        scores !== null
          ? {
              sieger: state.sieger,
              verlierer: state.verlierer,
              geteilt: state.geteilt,
              kampflos: state.kampflos,
              abgebrochen: state.abgebrochen,
              praemie: state.geteilt ? LD_GETEILT_MM : LD_SIEG_BANK_MM,
              transfer: state.kampflos || state.geteilt ? 0 : LD_SIEG_TRANSFER_MM,
              restAnSieger: wettAbrechnung?.restAnSieger ?? 0,
            }
          : null,
      finished: state.finished,
    };

    const aufloesung = state.finished
      ? {
          correctIndex: state.letzteTeilfrage?.correctIndex ?? null,
          erklaerung: state.abgebrochen
            ? "Duell abgebrochen — keine Zahlungen, Wetten zurück."
            : state.geteilt
              ? "Doppelter Gleichstand: GETEILTER Sieg — je 150 MM, Wetten zurück."
              : state.kampflos
                ? "Kampfloser Sieg (Gegner offline): 300 MM aus der Bank, Wetten zurück."
                : "Sieger: 300 MM + 100 MM direkt vom Verlierer. Richtige Wetten teilen den Wett-Topf.",
          perPlayer: state.players.map((p) => {
            const wette = state.wetten[p];
            return {
              playerId: p,
              choice: null,
              correct:
                p === state.sieger ||
                (state.geteilt && duellanten(state).includes(p)) ||
                (wette !== undefined && !state.kampflos && !state.geteilt
                  ? wette === state.sieger
                  : false),
              delta: scores?.[p] ?? 0,
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
        deineWette: player !== undefined ? (state.wetten[player] ?? null) : null,
        // Gegner-Wahl-Grid sieht NUR der Herausforderer im Wahl-Fenster.
        waehlbareGegner:
          istHerausforderer && state.phase === "herausforderung"
            ? gegnerKandidaten(state).map((k) => ({
                ...k,
                kontostand: state.balances === null ? null : kontoVon(state, k.id),
              }))
            : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: LianenstegDuellState): boolean {
    return state.finished;
  },

  scores(state: LianenstegDuellState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM/Chronik. */
  outcomes(state: LianenstegDuellState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    const d = duellanten(state);
    for (const p of state.players) {
      if (state.abgebrochen) {
        result[p] = { correct: null };
        continue;
      }
      if (d.includes(p)) {
        result[p] = state.geteilt
          ? { correct: true }
          : state.sieger === p
            ? { correct: true }
            : state.kampflos
              ? { correct: null } // offline — keine Wertung (kein Streak-Riss via null)
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
