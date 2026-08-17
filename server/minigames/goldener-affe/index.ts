// „Der Goldene Affe" (GAME-DESIGN §2.12 v2-Finale-Alternative, Detail
// docs/ideen/02 Nr. 22): dreistufiges Wechselfinale im goldenen Affentempel.
//
// ABLAUF (eine Runden-Instanz, meta.roundBased — EINE Buchung am Ende):
//   STUFE 1 drop (30 s): Money-Drop mit dem ECHTEN Kontostand (ctx.match) —
//   10 Chips auf die 4 Antworten, Einsatz = 50 % des Kontos (mind. 100;
//   Konto < 200 ⇒ Gratis-Einsatz der Bank). Richtige Tür ×2 zurück, Rest weg.
//   `answer` ist der „Alles auf eins"-Schnellzug (generischer Bot-Draht).
//   KEINE Verteilung ⇒ KEIN Einsatz (AFK-Schutz). → drop-ergebnis (8 s).
//   STUFE 2 schaetzen (20 s): Schätz-Showdown (eingebauter Pool, deterministisch
//   gewählt) — die 2 nächsten am Richtwert werden Finalisten (Gleichstand:
//   frühere Abgabe, dann Join-Reihenfolge; kein Tipp = ausgeschieden).
//   2-Spieler-Spiel: Stufe entfällt (Design-Edge). → schaetz-ergebnis (6 s).
//   wetten (10 s, nur mit Ausgeschiedenen): EINE 50-MM-Siegerwette pro
//   Ausgeschiedenem, zahlt ×3 (Design: aus der Bank — netto +100/−50).
//   STUFE 3 buzzer (3 Fragen à 10 s): Speed-MC-4 NUR für die Finalisten, die
//   schnellste RICHTIGE Antwort holt den Punkt (ctx.buzzer.ordne inkl.
//   Fotofinish-Los; Fallback: ordneBuzzes mit ctx.rng), 2 Punkte siegen.
//   Gleichstand nach 3 Fragen ⇒ showdown: finale Schätzfrage, näher dran
//   gewinnt (Gleichstand: frühere Abgabe, dann Los). → kroenung (8 s).
//
// SIEGER-PAYOFF „nimmt die Bananen mit": +20 % der PROJIZIERTEN Konten aller
// anderen (Init-Konto + eigene Drop-/Wett-Deltas, nur positive Konten,
// 10er-Rundung ab) — EXAKT NULLSUMMIGER Transfer. Wetten/Gratis-Einsatz zahlt
// die Bank (nach Design).
// EDGE-CASES: Finalist-Disconnect in Stufe 3 ⇒ WILDCARD-Nachrücker (bester
// verbundener Ausgeschiedener nach Schätz-Distanz; Wetten auf den Ersetzten
// werden erstattet, seine Punkte verfallen); kein Nachrücker ⇒ kampfloser
// Sieg (Titel ohne 20-%-Transfer, ALLE Wetten zurück); beide Finalisten weg ⇒
// Abbruch (Drop-Deltas bleiben — die Falltüren sind gefallen — Wetten zurück,
// kein Sieger). GM-Skip (force.finish vor der Krönung) ⇒ alles 0.
import type { ContentSlice, Question } from "../../../shared/content";
import { ordneBuzzes, type BuzzErgebnis, type BuzzKandidat } from "../../../shared/buzzer";
import type { PlayerId } from "../../../shared/ids";
import {
  GA_BUZZER_ERGEBNIS_MS,
  GA_BUZZER_FRAGE_MS,
  GA_BUZZER_FRAGEN,
  GA_BUZZER_SIEGE,
  GA_CHIPS,
  GA_DROP_ERGEBNIS_MS,
  GA_DROP_MS,
  GA_FINALISTEN,
  GA_KROENUNG_MS,
  GA_SCHAETZ_ERGEBNIS_MS,
  GA_SCHAETZ_MS,
  GA_WETTE_FAKTOR,
  GA_WETTE_MM,
  GA_WETTEN_MS,
  GOLDENER_AFFE_META,
  gaDropDelta,
  gaEinsatz,
  gaFuelleChipsAuf,
  gaTransfer,
  type GaSchaetzfrage,
  type GoldenerAffeAction,
} from "../../../shared/minigames/goldener-affe.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";
import { GA_SCHAETZFRAGEN } from "./fragen";

export type GaPhase =
  | "drop"
  | "drop-ergebnis"
  | "schaetzen"
  | "schaetz-ergebnis"
  | "wetten"
  | "buzzer"
  | "buzzer-ergebnis"
  | "showdown"
  | "kroenung";

/** Ohne match-API (isolierte Läufe): plausibles Konto als Einsatz-Basis. */
const GA_FALLBACK_KONTO = 1_000;

export interface GaBuzzerErgebnis {
  questionId: string;
  correctIndex: number;
  gewinner: string | null;
  fotofinish: boolean;
}

export interface GoldenerAffeState {
  players: PlayerId[];
  questions: Question[];
  schaetzfrage: GaSchaetzfrage;
  showdownFrage: GaSchaetzfrage;
  startedAt: number;
  phase: GaPhase;
  phaseEndsAt: number;
  timerMs: number; // Buzzer-Fenster (mit mods.timerFaktor)
  /** Konto-Snapshot beim init (ctx.match) — Einsatz- und Transfer-Basis. */
  balances: Record<string, number> | null;
  /** Letzter Chip-Stand pro Spieler (zählt beim Fenster-Ende, Design Nr. 9). */
  chips: Record<string, number[]>;
  /** Drop-Auswertung: Einsatz + Delta pro Teilnehmer (null = noch offen). */
  drop: Record<string, { einsatz: number; gratis: boolean; delta: number }> | null;
  /** Schätz-Tipps Stufe 2 (letzter Stand zählt, Einloggen rastet ein). */
  tipps: Record<string, { wert: number; eingeloggt: boolean; atMs: number }>;
  finalisten: PlayerId[];
  ausgeschieden: PlayerId[];
  /** Schätz-Distanzen der Stufe 2 (Nachrücker-Reihenfolge). */
  distanzen: Record<string, number>;
  wildcard: PlayerId | null;
  wetten: Record<string, string>;
  wettenGeschlossen: boolean;
  buzzerRunde: number; // 1-basiert
  frageNonce: number;
  frageStartetAt: number | null;
  answers: Record<string, { choice: number; nachMs: number; atServerTime: number }>;
  punkte: Record<string, number>;
  letzteBuzzerFrage: GaBuzzerErgebnis | null;
  showdownTipps: Record<string, { wert: number; atMs: number }>;
  sieger: PlayerId | null;
  kampflos: boolean;
  abgebrochen: boolean;
  /** GM-Skip vor der Krönung: NIEMAND zahlt/verdient (Präzedenz §2.9). */
  uebersprungen: boolean;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<GoldenerAffeAction> | GmAction;

function kontoVon(state: GoldenerAffeState, p: string): number {
  return state.balances === null ? GA_FALLBACK_KONTO : (state.balances[p] ?? 0);
}

function dropFrage(state: GoldenerAffeState): Question {
  return state.questions[0];
}

function buzzerFrage(state: GoldenerAffeState): Question {
  // q0 ist die Drop-Frage; Buzzer-Serie ab q1, Reserve per Rotation.
  const index =
    state.questions.length > 1 ? 1 + ((state.buzzerRunde - 1) % (state.questions.length - 1)) : 0;
  return state.questions[index];
}

function verbundene(state: GoldenerAffeState, gruppe: PlayerId[]): PlayerId[] {
  return gruppe.filter((p) => state.connected[p]);
}

/** Deterministische Pool-Wahl (Tresor-Muster): Fragen-Nummer + Spieler-Hash. */
function poolIndex(questions: Question[], players: PlayerId[], ctx: Ctx): number {
  const nr = Number(/(\d+)$/.exec(questions[0]?.id ?? "")?.[1]);
  if (!Number.isFinite(nr)) return ctx.rng.int(GA_SCHAETZFRAGEN.length);
  let hash = 0;
  for (const p of players) {
    for (let i = 0; i < p.length; i++) hash = (hash * 31 + p.charCodeAt(i)) >>> 0;
  }
  return (hash + nr) % GA_SCHAETZFRAGEN.length;
}

function klemmeTipp(frage: GaSchaetzfrage, wert: number): number {
  return Math.min(frage.eingabeMax, Math.max(frage.eingabeMin, Math.round(wert)));
}

/** STUFE 1 auswerten: Chips auffüllen (Timeout-Regel), Einsatz + Delta buchen. */
function werteDropAus(state: GoldenerAffeState, now: number): GoldenerAffeState {
  const frage = dropFrage(state);
  const drop: NonNullable<GoldenerAffeState["drop"]> = {};
  const chips: Record<string, number[]> = {};
  for (const p of state.players) {
    const roh = state.chips[p];
    if (roh === undefined) continue; // keine Verteilung = kein Einsatz (AFK-Schutz)
    const voll = gaFuelleChipsAuf(roh);
    if (voll.reduce((a, b) => a + b, 0) === 0) continue;
    chips[p] = voll;
    const einsatz = gaEinsatz(kontoVon(state, p));
    drop[p] = {
      einsatz: einsatz.betrag,
      gratis: einsatz.gratis,
      delta: gaDropDelta(einsatz, voll[frage.answer]),
    };
  }
  return {
    ...state,
    chips,
    drop,
    phase: "drop-ergebnis",
    phaseEndsAt: now + GA_DROP_ERGEBNIS_MS,
  };
}

/** STUFE 2 auswerten: die 2 nächsten am Richtwert werden Finalisten. */
function werteSchaetzenAus(state: GoldenerAffeState, now: number): GoldenerAffeState {
  const distanzen: Record<string, number> = {};
  const geordnet = [...state.players].sort((a, b) => {
    const ta = state.tipps[a];
    const tb = state.tipps[b];
    const da = ta === undefined ? Infinity : Math.abs(ta.wert - state.schaetzfrage.richtwert);
    const db = tb === undefined ? Infinity : Math.abs(tb.wert - state.schaetzfrage.richtwert);
    if (da !== db) return da - db;
    const za = ta?.atMs ?? Infinity;
    const zb = tb?.atMs ?? Infinity;
    if (za !== zb) return za - zb;
    return state.players.indexOf(a) - state.players.indexOf(b); // Join-Reihenfolge
  });
  for (const p of geordnet) {
    const t = state.tipps[p];
    distanzen[p] = t === undefined ? Infinity : Math.abs(t.wert - state.schaetzfrage.richtwert);
  }
  // Verbundene vor Offline-Spielern in die Finalisten-Slots (es MÜSSEN 2 her).
  const kandidaten = [
    ...geordnet.filter((p) => state.connected[p]),
    ...geordnet.filter((p) => !state.connected[p]),
  ];
  const finalisten = kandidaten.slice(0, GA_FINALISTEN);
  const ausgeschieden = state.players.filter((p) => !finalisten.includes(p));
  return {
    ...state,
    distanzen,
    finalisten,
    ausgeschieden,
    phase: "schaetz-ergebnis",
    phaseEndsAt: now + GA_SCHAETZ_ERGEBNIS_MS,
  };
}

function starteWettenOderBuzzer(state: GoldenerAffeState, now: number): GoldenerAffeState {
  if (state.ausgeschieden.length === 0) {
    return starteBuzzerFrage({ ...state, wettenGeschlossen: true }, now);
  }
  return { ...state, phase: "wetten", phaseEndsAt: now + GA_WETTEN_MS };
}

function starteBuzzerFrage(state: GoldenerAffeState, now: number): GoldenerAffeState {
  return {
    ...state,
    phase: "buzzer",
    wettenGeschlossen: true,
    phaseEndsAt: now + state.timerMs,
    frageStartetAt: now,
    frageNonce: state.frageNonce + 1,
    answers: {},
  };
}

function starteKroenung(
  state: GoldenerAffeState,
  now: number,
  sieger: PlayerId | null,
  flags: Partial<Pick<GoldenerAffeState, "kampflos" | "abgebrochen">> = {},
): GoldenerAffeState {
  return {
    ...state,
    phase: "kroenung",
    phaseEndsAt: now + GA_KROENUNG_MS,
    sieger,
    ...flags,
  };
}

/** Buzzer-Frage auswerten: schnellste RICHTIGE Antwort holt den Punkt. */
function werteBuzzerAus(state: GoldenerAffeState, now: number, ctx: Ctx): GoldenerAffeState {
  const frage = buzzerFrage(state);
  const richtige = state.finalisten
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
    const geordnet: BuzzErgebnis[] = ctx.buzzer
      ? ctx.buzzer.ordne(kandidaten)
      : ordneBuzzes(kandidaten, ctx.rng);
    gewinner = (geordnet.find((e) => e.rank === 1)?.playerId ?? richtige[0]) as PlayerId;
    fotofinish = geordnet.some((e) => e.fotofinish);
  }
  const punkte = { ...state.punkte };
  if (gewinner !== null) punkte[gewinner] = (punkte[gewinner] ?? 0) + 1;
  return {
    ...state,
    punkte,
    letzteBuzzerFrage: {
      questionId: frage.id,
      correctIndex: frage.answer,
      gewinner,
      fotofinish,
    },
    phase: "buzzer-ergebnis",
    phaseEndsAt: now + GA_BUZZER_ERGEBNIS_MS,
  };
}

/** Nach dem Punkte-Beat: Sieg, nächste Frage oder Schätz-Showdown. */
function nachBuzzerErgebnis(state: GoldenerAffeState, now: number): GoldenerAffeState {
  const [a, b] = state.finalisten;
  const pa = state.punkte[a] ?? 0;
  const pb = b !== undefined ? (state.punkte[b] ?? 0) : 0;
  if (pa >= GA_BUZZER_SIEGE) return starteKroenung(state, now, a);
  if (b !== undefined && pb >= GA_BUZZER_SIEGE) return starteKroenung(state, now, b);
  if (state.buzzerRunde >= GA_BUZZER_FRAGEN) {
    if (pa !== pb) return starteKroenung(state, now, pa > pb ? a : (b as PlayerId));
    // Gleichstand nach 3 Fragen: die ultimative Schätzfrage entscheidet.
    return {
      ...state,
      phase: "showdown",
      phaseEndsAt: now + GA_SCHAETZ_MS,
      showdownTipps: {},
    };
  }
  return starteBuzzerFrage({ ...state, buzzerRunde: state.buzzerRunde + 1 }, now);
}

/** Showdown auswerten: näher dran gewinnt (Gleichstand: frühere Abgabe, Los). */
function werteShowdownAus(state: GoldenerAffeState, now: number, ctx: Ctx): GoldenerAffeState {
  const [a, b] = state.finalisten;
  const ta = state.showdownTipps[a];
  const tb = b !== undefined ? state.showdownTipps[b] : undefined;
  const da = ta === undefined ? Infinity : Math.abs(ta.wert - state.showdownFrage.richtwert);
  const db = tb === undefined ? Infinity : Math.abs(tb.wert - state.showdownFrage.richtwert);
  let sieger: PlayerId;
  if (da !== db) sieger = da < db ? a : (b as PlayerId);
  else if ((ta?.atMs ?? Infinity) !== (tb?.atMs ?? Infinity)) {
    sieger = (ta?.atMs ?? Infinity) < (tb?.atMs ?? Infinity) ? a : (b as PlayerId);
  } else {
    sieger = ctx.rng.next() < 0.5 ? a : (b as PlayerId); // der ultimative Münzwurf
  }
  return starteKroenung(state, now, sieger);
}

/** Finalisten-Offline-Wache Stufe 3: Wildcard-Nachrücker/kampflos/Abbruch. */
function pruefeFinalistenOffline(state: GoldenerAffeState, now: number): GoldenerAffeState | null {
  if (state.finalisten.length < GA_FINALISTEN) return null;
  const offline = state.finalisten.filter((p) => !state.connected[p]);
  if (offline.length === 0) return null;

  let s = state;
  for (const weg of offline) {
    // Nachrücker: bester VERBUNDENER Ausgeschiedener (Schätz-Distanz-Reihenfolge).
    const nachruecker = verbundene(s, s.ausgeschieden as PlayerId[]).sort(
      (x, y) => (s.distanzen[x] ?? Infinity) - (s.distanzen[y] ?? Infinity),
    )[0];
    if (nachruecker === undefined) continue;
    const wetten = { ...s.wetten };
    // Wetten auf den ersetzten Finalisten werden erstattet (Wette gelöscht).
    for (const [wetter, auf] of Object.entries(wetten)) {
      if (auf === weg) delete wetten[wetter];
    }
    // Der Nachrücker darf nicht gleichzeitig Wetter bleiben.
    delete wetten[nachruecker];
    const punkte = { ...s.punkte };
    delete punkte[weg]; // Punkte des Ersetzten verfallen (Wildcard startet bei 0)
    s = {
      ...s,
      finalisten: s.finalisten.map((p) => (p === weg ? nachruecker : p)),
      ausgeschieden: [...s.ausgeschieden.filter((p) => p !== nachruecker), weg],
      wildcard: nachruecker,
      wetten,
      punkte,
      answers: {},
    };
  }
  const nochOffline = s.finalisten.filter((p) => !s.connected[p]);
  if (nochOffline.length === 0) {
    // Frisches Fenster für die neue Paarung.
    if (s.phase === "buzzer") return starteBuzzerFrage({ ...s, frageStartetAt: null }, now);
    return s;
  }
  if (nochOffline.length === s.finalisten.length) {
    return starteKroenung(s, now, null, { abgebrochen: true });
  }
  const anwesend = s.finalisten.find((p) => s.connected[p]) as PlayerId;
  return starteKroenung(s, now, anwesend, { kampflos: true });
}

/** Scores (eine Buchung): Drop-Delta + Wett-Delta + 20-%-Sieger-Transfer. */
function berechneScores(state: GoldenerAffeState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) result[p] = 0;
  if (state.uebersprungen) return result;
  for (const [p, d] of Object.entries(state.drop ?? {})) result[p as PlayerId] = d.delta;
  if (state.sieger === null || state.kampflos) return result; // Wetten zurück
  for (const [wetter, auf] of Object.entries(state.wetten)) {
    result[wetter as PlayerId] +=
      auf === state.sieger ? GA_WETTE_MM * (GA_WETTE_FAKTOR - 1) : -GA_WETTE_MM;
  }
  // „Der Gewinner nimmt die Bananen mit": 20 % der projizierten Konten —
  // exakt nullsummiger Transfer (Projektion = Init-Konto + eigene Deltas).
  let summe = 0;
  for (const p of state.players) {
    if (p === state.sieger) continue;
    const projektion = (state.balances === null ? 0 : kontoVon(state, p)) + result[p];
    const transfer = gaTransfer(projektion);
    result[p] -= transfer;
    summe += transfer;
  }
  result[state.sieger] += summe;
  return result;
}

export const goldenerAffePlugin: MinigamePlugin<GoldenerAffeState, GoldenerAffeAction> = {
  meta: GOLDENER_AFFE_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): GoldenerAffeState {
    if (content.questions.length === 0) {
      throw new Error("goldener-affe: ContentSlice ohne Frage");
    }
    const now = ctx.clock.now();
    const match = ctx.match;
    const balances = match ? Object.fromEntries(players.map((p) => [p, match.balance(p)])) : null;
    const index = poolIndex(content.questions, players, ctx);
    return {
      players,
      questions: content.questions,
      schaetzfrage: GA_SCHAETZFRAGEN[index],
      showdownFrage: GA_SCHAETZFRAGEN[(index + 1) % GA_SCHAETZFRAGEN.length],
      startedAt: now,
      phase: "drop",
      phaseEndsAt: now + GA_DROP_MS,
      timerMs: Math.round(GA_BUZZER_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      balances,
      chips: {},
      drop: null,
      tipps: {},
      finalisten: [],
      ausgeschieden: [],
      distanzen: {},
      wildcard: null,
      wetten: {},
      wettenGeschlossen: false,
      buzzerRunde: 1,
      frageNonce: 1,
      frageStartetAt: null,
      answers: {},
      punkte: {},
      letzteBuzzerFrage: null,
      showdownTipps: {},
      sieger: null,
      kampflos: false,
      abgebrochen: false,
      uebersprungen: false,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: GoldenerAffeState, action: Action, ctx: Ctx): GoldenerAffeState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: steht der Sieger (Krönung läuft), gilt die Abrechnung —
        // sonst verfällt das Finale ohne Zahlung.
        if (state.phase === "kroenung") return { ...state, finished: true };
        return { ...state, uebersprungen: true, abgebrochen: true, finished: true };
      }
      if (action.type === "timer.extend") {
        return { ...state, phaseEndsAt: state.phaseEndsAt + action.ms };
      }
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

    // ---------- STUFE 1: Chips verteilen (letzter Stand im Fenster zählt) ----------
    if (action.action.type === "chips") {
      if (state.phase !== "drop") return state;
      if (action.atServerTime > state.phaseEndsAt) return state;
      const felder = [0, 1, 2, 3].map((i) =>
        Math.max(
          0,
          Math.floor(Number(action.action.type === "chips" ? action.action.verteilung[i] : 0) || 0),
        ),
      );
      return { ...state, chips: { ...state.chips, [p]: felder } };
    }

    if (action.action.type === "answer") {
      // Stufe 1: „Alles auf eins"-Schnellzug (auch der generische Bot-Draht).
      if (state.phase === "drop") {
        if (action.atServerTime > state.phaseEndsAt) return state;
        const felder = [0, 0, 0, 0];
        felder[action.action.choice] = GA_CHIPS;
        return { ...state, chips: { ...state.chips, [p]: felder } };
      }
      // Stufe 3: Speed-Antwort — NUR Finalisten, erste Antwort zählt.
      if (state.phase !== "buzzer" || state.frageStartetAt === null) return state;
      if (!state.finalisten.includes(p)) return state;
      if (state.answers[p] !== undefined) return state;
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
    }

    // ---------- STUFE 2 + Showdown: Schätz-Slider ----------
    if (action.action.type === "tipp" || action.action.type === "einloggen") {
      const einloggen = action.action.type === "einloggen";
      if (state.phase === "schaetzen") {
        if (action.atServerTime > state.phaseEndsAt) return state;
        const alt = state.tipps[p];
        if (alt?.eingeloggt) return state; // eingerastet
        return {
          ...state,
          tipps: {
            ...state.tipps,
            [p]: {
              wert: klemmeTipp(state.schaetzfrage, action.action.wert),
              eingeloggt: einloggen,
              atMs: Math.max(0, action.atServerTime - state.startedAt),
            },
          },
        };
      }
      if (state.phase === "showdown") {
        if (!state.finalisten.includes(p)) return state;
        if (action.atServerTime > state.phaseEndsAt) return state;
        // Im Showdown zählt schlicht der letzte Stand (kein Einlog-Flag nötig).
        return {
          ...state,
          showdownTipps: {
            ...state.showdownTipps,
            [p]: {
              wert: klemmeTipp(state.showdownFrage, action.action.wert),
              atMs: Math.max(0, action.atServerTime - state.startedAt),
            },
          },
        };
      }
      return state;
    }

    // ---------- Siegerwette der Ausgeschiedenen ----------
    if (action.action.type !== "wette") return state;
    if (state.phase !== "wetten" || state.wettenGeschlossen) return state;
    if (!state.ausgeschieden.includes(p)) return state;
    if (state.wetten[p] !== undefined) return state; // eingerastet
    if (!state.finalisten.includes(action.action.auf as PlayerId)) return state;
    return { ...state, wetten: { ...state.wetten, [p]: action.action.auf } };
  },

  tick(state: GoldenerAffeState, ctx: Ctx): GoldenerAffeState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "drop") {
      const online = verbundene(state, state.players);
      const alleVerteilt =
        online.length > 0 &&
        online.every((p) => (state.chips[p] ?? []).reduce((a, b) => a + b, 0) >= GA_CHIPS);
      if (now >= state.phaseEndsAt || alleVerteilt) return werteDropAus(state, now);
      return state;
    }

    if (state.phase === "drop-ergebnis") {
      if (now < state.phaseEndsAt) return state;
      // 2-Spieler-Spiel: Schätz-Showdown entfällt, beide sind Finalisten.
      if (state.players.length === 2) {
        return starteWettenOderBuzzer(
          { ...state, finalisten: [...state.players], ausgeschieden: [] },
          now,
        );
      }
      return { ...state, phase: "schaetzen", phaseEndsAt: now + GA_SCHAETZ_MS };
    }

    if (state.phase === "schaetzen") {
      const online = verbundene(state, state.players);
      const alleEingeloggt =
        online.length > 0 && online.every((p) => state.tipps[p]?.eingeloggt === true);
      if (now >= state.phaseEndsAt || alleEingeloggt) return werteSchaetzenAus(state, now);
      return state;
    }

    if (state.phase === "schaetz-ergebnis") {
      if (now < state.phaseEndsAt) return state;
      return starteWettenOderBuzzer(state, now);
    }

    if (state.phase === "wetten") {
      const offen = verbundene(state, state.ausgeschieden as PlayerId[]).filter(
        (p) => state.wetten[p] === undefined,
      );
      if (now >= state.phaseEndsAt || offen.length === 0) {
        return starteBuzzerFrage(state, now);
      }
      return state;
    }

    if (state.phase === "buzzer") {
      const offline = pruefeFinalistenOffline(state, now);
      if (offline !== null) return offline;
      const alleGeantwortet = state.finalisten.every((p) => state.answers[p] !== undefined);
      if (alleGeantwortet || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteBuzzerAus(state, now, ctx);
      }
      return state;
    }

    if (state.phase === "buzzer-ergebnis") {
      if (now < state.phaseEndsAt) return state;
      return nachBuzzerErgebnis(state, now);
    }

    if (state.phase === "showdown") {
      const offline = pruefeFinalistenOffline(state, now);
      if (offline !== null) return offline;
      const beideGetippt = state.finalisten.every((p) => state.showdownTipps[p] !== undefined);
      if (now >= state.phaseEndsAt || beideGetippt) return werteShowdownAus(state, now, ctx);
      return state;
    }

    // Phase "kroenung" vorbei ⇒ fertig (Engine bucht + löst auf).
    if (now < state.phaseEndsAt) return state;
    return { ...state, finished: true };
  },

  onDisconnect(state: GoldenerAffeState, p: PlayerId, ctx: Ctx): GoldenerAffeState {
    const s: GoldenerAffeState = { ...state, connected: { ...state.connected, [p]: false } };
    // Finalist fällt in Stufe 3 weg ⇒ sofort Wildcard/kampflos (Design-Edge).
    if (
      !s.finished &&
      (s.phase === "buzzer" || s.phase === "showdown" || s.phase === "wetten") &&
      s.finalisten.includes(p)
    ) {
      return pruefeFinalistenOffline(s, ctx.clock.now()) ?? s;
    }
    return s;
  },

  onReconnect(state: GoldenerAffeState, p: PlayerId, _ctx: Ctx): GoldenerAffeState {
    // Ein vollzogener Wildcard-Tausch bleibt bestehen (Design-Entscheidung).
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: GoldenerAffeState, role: Role, player?: PlayerId): unknown {
    const drop = dropFrage(state);
    const buzzer = buzzerFrage(state);
    const stufe =
      state.phase === "drop" || state.phase === "drop-ergebnis"
        ? 1
        : state.phase === "schaetzen" ||
            state.phase === "schaetz-ergebnis" ||
            state.phase === "wetten"
          ? 2
          : 3;
    const timerMs =
      state.phase === "drop"
        ? GA_DROP_MS
        : state.phase === "drop-ergebnis"
          ? GA_DROP_ERGEBNIS_MS
          : state.phase === "schaetzen" || state.phase === "showdown"
            ? GA_SCHAETZ_MS
            : state.phase === "schaetz-ergebnis"
              ? GA_SCHAETZ_ERGEBNIS_MS
              : state.phase === "wetten"
                ? GA_WETTEN_MS
                : state.phase === "buzzer"
                  ? state.timerMs
                  : state.phase === "buzzer-ergebnis"
                    ? GA_BUZZER_ERGEBNIS_MS
                    : GA_KROENUNG_MS;
    const scores = state.finished || state.phase === "kroenung" ? berechneScores(state) : null;
    const dropOffen = state.phase === "drop";
    const buzzerLaeuft = state.phase === "buzzer";
    const schaetzAktiv = state.phase === "schaetzen";
    const showdownAktiv = state.phase === "showdown";
    const schaetzGeloest =
      stufe === 3 || state.phase === "schaetz-ergebnis" || state.phase === "wetten";

    const basis = {
      // Für Bots/Harness: die Frage-Identität des AKTUELLEN Fensters.
      questionId: buzzerLaeuft || state.phase === "buzzer-ergebnis" ? buzzer.id : drop.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      stufe,
      endsAt: state.phaseEndsAt,
      timerMs,
      spieler: state.players,
      spielerZahl: state.players.length,
      finalisten: state.finalisten,
      ausgeschieden: state.ausgeschieden,
      wildcard: state.wildcard,
      punkte: state.punkte,
      buzzerRunde: state.buzzerRunde,
      buzzerFragen: GA_BUZZER_FRAGEN,
      punkteZiel: GA_BUZZER_SIEGE,
      // STUFE 1: Frage public (alle verteilen live), Lösung erst im Ergebnis.
      text: dropOffen ? drop.text : buzzerLaeuft ? buzzer.text : null,
      options: dropOffen ? drop.options : null,
      // Chips-Fortschritt: während des Fensters NUR wer fertig ist (geheim!).
      chipsFertig: state.players.filter(
        (p) => (state.chips[p] ?? []).reduce((a, b) => a + b, 0) >= GA_CHIPS,
      ),
      // Verteilungen + Drop-Abrechnung public erst AB dem Falltür-Ergebnis.
      dropErgebnis:
        state.drop !== null
          ? {
              correctIndex: drop.answer,
              chips: state.chips,
              perPlayer: state.drop,
            }
          : null,
      // STUFE 2: Schätzfrage (Richtwert GEHEIM bis zum Ergebnis).
      schaetz:
        schaetzAktiv || state.phase === "schaetz-ergebnis" || state.phase === "wetten"
          ? {
              id: state.schaetzfrage.id,
              text: state.schaetzfrage.text,
              einheit: state.schaetzfrage.einheit,
              eingabeMin: state.schaetzfrage.eingabeMin,
              eingabeMax: state.schaetzfrage.eingabeMax,
              richtwert: schaetzGeloest ? state.schaetzfrage.richtwert : null,
              erklaerung: schaetzGeloest ? state.schaetzfrage.erklaerung : null,
              tipps: schaetzGeloest
                ? Object.fromEntries(Object.entries(state.tipps).map(([p, t]) => [p, t.wert]))
                : null,
              abgegeben: Object.keys(state.tipps).length,
            }
          : null,
      // Wetten: während des Fensters nur die Anzahl, danach public.
      wettenAnzahl: Object.keys(state.wetten).length,
      wetten: state.wettenGeschlossen ? state.wetten : null,
      wetteMM: GA_WETTE_MM,
      wetteFaktor: GA_WETTE_FAKTOR,
      // STUFE 3: Punkte-Beat mit Lösung, Showdown-Frage für die Finalisten.
      letzteBuzzerFrage: state.phase === "buzzer-ergebnis" ? state.letzteBuzzerFrage : null,
      showdown: showdownAktiv
        ? {
            id: state.showdownFrage.id,
            text: state.showdownFrage.text,
            einheit: state.showdownFrage.einheit,
            eingabeMin: state.showdownFrage.eingabeMin,
            eingabeMax: state.showdownFrage.eingabeMax,
            abgegeben: Object.keys(state.showdownTipps).length,
          }
        : null,
      answeredCount: buzzerLaeuft
        ? Object.keys(state.answers).length
        : dropOffen
          ? Object.keys(state.chips).length
          : 0,
      ergebnis:
        scores !== null
          ? {
              sieger: state.sieger,
              kampflos: state.kampflos,
              abgebrochen: state.abgebrochen,
              transferSumme:
                state.sieger === null
                  ? 0
                  : state.players
                      .filter((p) => p !== state.sieger)
                      .reduce((sum, p) => {
                        const basisDelta =
                          (state.drop?.[p]?.delta ?? 0) +
                          (state.wetten[p] !== undefined && !state.kampflos
                            ? state.wetten[p] === state.sieger
                              ? GA_WETTE_MM * (GA_WETTE_FAKTOR - 1)
                              : -GA_WETTE_MM
                            : 0);
                        const projektion =
                          (state.balances === null ? 0 : kontoVon(state, p)) + basisDelta;
                        return state.kampflos ? 0 : sum + gaTransfer(projektion);
                      }, 0),
            }
          : null,
      finished: state.finished,
    };

    const aufloesung = state.finished
      ? {
          correctIndex: state.letzteBuzzerFrage?.correctIndex ?? drop.answer,
          erklaerung: state.uebersprungen
            ? "Finale übersprungen — keine Zahlungen."
            : state.abgebrochen
              ? "Finale abgebrochen — Drop-Deltas bleiben, Wetten zurück, kein Sieger."
              : state.kampflos
                ? "Kampfloser Titel (Finalisten offline) — kein 20-%-Transfer, Wetten zurück."
                : "Der Goldene Affe nimmt die Bananen mit: +20 % der Konten aller anderen!",
          perPlayer: state.players.map((p) => {
            const wette = state.wetten[p];
            return {
              playerId: p,
              choice: null,
              correct:
                p === state.sieger ||
                (wette !== undefined && !state.kampflos && wette === state.sieger),
              delta: scores?.[p] ?? 0,
            };
          }),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: Lösungen + Richtwerte + Wetten IMMER sichtbar.
      return {
        ...basis,
        text: dropOffen || state.phase === "drop-ergebnis" ? drop.text : buzzer.text,
        options: dropOffen || state.phase === "drop-ergebnis" ? drop.options : buzzer.options,
        correctIndex:
          buzzerLaeuft || state.phase === "buzzer-ergebnis" ? buzzer.answer : drop.answer,
        richtwert: state.schaetzfrage.richtwert,
        showdownRichtwert: state.showdownFrage.richtwert,
        wetten: state.wetten,
        chips: state.chips,
        aufloesung,
      };
    }
    if (role === "player") {
      const istFinalist = player !== undefined && state.finalisten.includes(player);
      return {
        ...basis,
        duBistFinalist: istFinalist,
        duBistAusgeschieden: player !== undefined && state.ausgeschieden.includes(player),
        deineChips: player !== undefined ? (state.chips[player] ?? null) : null,
        deinEinsatz: player !== undefined ? gaEinsatz(kontoVon(state, player)) : null,
        // Schätz-Slider-Draht (Tresor-Konvention: eingabeMin/Max + yourTipp).
        eingabeMin: schaetzAktiv
          ? state.schaetzfrage.eingabeMin
          : showdownAktiv && istFinalist
            ? state.showdownFrage.eingabeMin
            : undefined,
        eingabeMax: schaetzAktiv
          ? state.schaetzfrage.eingabeMax
          : showdownAktiv && istFinalist
            ? state.showdownFrage.eingabeMax
            : undefined,
        yourTipp: schaetzAktiv
          ? player !== undefined
            ? (state.tipps[player]?.wert ?? null)
            : null
          : showdownAktiv && istFinalist && player !== undefined
            ? (state.showdownTipps[player]?.wert ?? null)
            : null,
        deineWette: player !== undefined ? (state.wetten[player] ?? null) : null,
        yourChoice:
          buzzerLaeuft && player !== undefined ? (state.answers[player]?.choice ?? null) : null,
        // Buzzer-Optionen NUR für Finalisten (Zuschauer raten passiv mit).
        options: dropOffen ? drop.options : buzzerLaeuft && istFinalist ? buzzer.options : null,
        zuschauerOptionen: buzzerLaeuft && !istFinalist ? buzzer.options : null,
        aufloesung,
      };
    }
    return { ...basis, buzzerOptionen: buzzerLaeuft ? buzzer.options : null, aufloesung };
  },

  isFinished(state: GoldenerAffeState): boolean {
    return state.finished;
  },

  scores(state: GoldenerAffeState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM/Chronik. */
  outcomes(state: GoldenerAffeState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      if (state.uebersprungen || state.abgebrochen || state.sieger === null) {
        result[p] = { correct: null };
        continue;
      }
      if (state.finalisten.includes(p)) {
        result[p] =
          p === state.sieger ? { correct: true } : { correct: state.kampflos ? null : false };
        continue;
      }
      const wette = state.wetten[p];
      result[p] =
        wette === undefined || state.kampflos
          ? { correct: null }
          : { correct: wette === state.sieger };
    }
    return result;
  },
};
