// „Das 7-Buchstaben-Telegramm" (buchstaben-telegramm, Musik-Welle) — das
// Joko&Klaas-Paar-Spiel. Pro Beat steht EIN Paar auf der Bühne:
//   VORSTELLUNG (4 s)  → Paar-Vorstellung mit Affen (Screen-Inszenierung)
//   TIPPEN (22 s)      → der BESCHREIBER sieht den Begriff auf SEINEM Handy
//                        und tippt NUR Buchstaben/Ziffern als Hinweis —
//                        jedes Zeichen kostet 1 aus seinem MATCH-Budget (60),
//                        max. 8 pro Hinweis; „senden" startet das Raten früher
//   RATEN (18 s)       → der/die RATENDE(n) sehen die Buchstaben groß +
//                        4 Optionen; erste Antwort zählt
//   AUFDECKUNG (6 s)   → Begriff + Money: BEIDE kriegen je 250 MM bei Erfolg
// Paare: bei Teams die Teampartner (slice.teamVon bzw. ctx.match.teamVon),
// sonst Zufalls-Paare pro Runde (ungerade ⇒ ein Dreier). Rollen rotieren:
// tritt ein Paar mehrfach auf, wechselt der Beschreiber.
// Begriffe: Song-Titel aus dem Song-Pack (songs.json) + eingebauter Pool
// (66 Filme/Sprichwörter/Promis) — deterministisch gewählt (Rng injiziert).
// EDGE-CASES: Beschreiber-Disconnect vor dem Senden ⇒ NEUTRALER
// Zufallsbegriff-Skip (NIE Antwort-Buchstaben auto-leaken!); Budget 0 ⇒
// Raten ohne Hinweis; Tippen-Timeout ⇒ Auto-Senden der getippten Zeichen;
// alle Ratenden offline ⇒ Beat wird sofort abgerechnet (keine Antwort = 0).
// BUDGET-REGEL: getippt = verbraucht — ABER ⌫ VOR dem Senden ist eine
// Streifen-Korrektur: das letzte Zeichen verschwindet und geht ins Budget
// ZURÜCK (Vertipper sind keine Telegramm-Wörter; Eval-3-Entscheidung).
// GESENDET (inkl. Auto-Senden beim Timeout) = endgültig verbraucht. Die
// Rückgabe kann das Budget nie über den Beat-Start-Stand heben, weil nur
// Zeichen des AKTUELLEN Streifens zurückgehen. Rest verfällt am
// Match-Ende (Anzeige läuft über budget im View). Runden-übergreifend reicht
// die Engine das Rest-Budget als slice.buchstabenBudget wieder rein
// (TODO(Engine-Agent) — Muster Taschendieb-Opfer-Historie); fehlt das Feld,
// startet jede Runde mit dem vollen Match-Budget.
import type { ContentSlice } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  BT_AUFDECKUNG_MS,
  BT_BEGRIFFS_POOL,
  BT_ERFOLG_MM,
  BT_HINWEIS_MAX,
  BT_MATCH_BUDGET,
  BT_RATEN_MS,
  BT_TIPPEN_MS,
  BT_VORSTELLUNG_MS,
  BUCHSTABEN_TELEGRAMM_META,
  btBaueOptionen,
  btBegriffeAusSongs,
  btBeschreiberIndex,
  btBildePaare,
  btValidiereZeichen,
  type BtBegriff,
  type BtBegriffArt,
  type BtPaar,
  type BuchstabenTelegrammAction,
} from "../../../shared/minigames/buchstaben-telegramm.meta";
import type { MvSong } from "../../../shared/minigames/musikvideo-raten.meta";
import type {
  Ctx,
  GmAction,
  JokerAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

/** Erweiterter ContentSlice — alle Zusatzfelder optional. */
export interface BuchstabenTelegrammSlice extends ContentSlice {
  /** Song-Pack (songs.json) — Titel wandern in den Begriffs-Topf. */
  songs?: MvSong[];
  /** Rest-Zeichen-Budget pro Spieler aus FRÜHEREN Runden dieses Matches
   * (Engine-TODO, Muster Taschendieb) — fehlend ⇒ voller Match-Budget-Start. */
  buchstabenBudget?: Record<string, number>;
  /** Team-Zuordnung playerId → TeamId (Fallback: ctx.match.teamVon). */
  teamVon?: Record<string, string>;
}

/** Ein Beat = ein Paar + ein Begriff (answer bleibt bis zur Aufdeckung geheim). */
export interface BtBeat {
  paarIndex: number;
  beschreiber: string;
  ratende: string[];
  begriff: BtBegriff;
  optionen: string[];
  answer: number;
}

/** Öffentlicher Aufdeckungs-Eintrag (Screen-Ticker + Runden-Bilanz). */
export interface BtHistorieEintrag {
  beatNr: number;
  beschreiber: string;
  ratende: string[];
  begriffText: string;
  art: BtBegriffArt;
  hinweis: string;
  richtige: string[];
  falsche: string[];
  uebersprungen: boolean;
  praemieJe: number;
}

export interface BuchstabenTelegrammState {
  players: PlayerId[];
  paare: BtPaar[];
  beats: BtBeat[];
  beatIndex: number;
  phase: "vorstellung" | "tippen" | "raten" | "aufdeckung";
  phaseStartetAt: number;
  phaseEndetAt: number;
  timerFaktor: number;
  startedAt: number;
  /** Rest-Zeichen-Budget pro Spieler — JEDES getippte Zeichen zieht sofort ab. */
  budget: Record<string, number>;
  /** Hinweis des AKTUELLEN Beats (streamt Zeichen für Zeichen auf den Screen). */
  hinweis: string;
  /** Max. Zeichen dieses Beats: min(8, Budget des Beschreibers beim Beat-Start). */
  maxZeichen: number;
  hinweisGesendet: boolean;
  /** Antworten der Ratenden des AKTUELLEN Beats — erste Antwort zählt. */
  antworten: Record<string, { choice: number; nachMs: number }>;
  /** Kumulierte Runden-Deltas = scores(). */
  deltas: Record<string, number>;
  richtigZaehler: Record<string, number>;
  beteiligtZaehler: Record<string, number>;
  letzteAntwort: Record<string, number>;
  historie: BtHistorieEintrag[];
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<BuchstabenTelegrammAction> | GmAction | JokerAction;

function beat(state: BuchstabenTelegrammState): BtBeat {
  return state.beats[state.beatIndex];
}

function fenster(state: BuchstabenTelegrammState, basisMs: number): number {
  return Math.round(basisMs * state.timerFaktor);
}

function verbundeneRatende(state: BuchstabenTelegrammState): string[] {
  return beat(state).ratende.filter((p) => state.connected[p]);
}

/** RATEN starten (Hinweis eingefroren — gesendet oder Auto-Timeout). */
function starteRaten(state: BuchstabenTelegrammState, now: number): BuchstabenTelegrammState {
  return {
    ...state,
    hinweisGesendet: true,
    phase: "raten",
    phaseStartetAt: now,
    phaseEndetAt: now + fenster(state, BT_RATEN_MS),
    antworten: {},
  };
}

/** Beat abrechnen: Erfolg = je 250 MM für Ratende UND Beschreiber (Bank). */
function werteAus(state: BuchstabenTelegrammState, now: number): BuchstabenTelegrammState {
  const b = beat(state);
  const deltas = { ...state.deltas };
  const richtigZaehler = { ...state.richtigZaehler };
  const beteiligtZaehler = { ...state.beteiligtZaehler };
  const richtige: string[] = [];
  const falsche: string[] = [];

  for (const p of b.ratende) {
    const a = state.antworten[p];
    if (a === undefined) continue;
    beteiligtZaehler[p] = (beteiligtZaehler[p] ?? 0) + 1;
    if (a.choice === b.answer) {
      deltas[p] = (deltas[p] ?? 0) + BT_ERFOLG_MM;
      richtigZaehler[p] = (richtigZaehler[p] ?? 0) + 1;
      richtige.push(p);
    } else {
      falsche.push(p);
    }
  }
  // Beschreiber: Erfolg des Paares zahlt auch ihm die Prämie.
  beteiligtZaehler[b.beschreiber] = (beteiligtZaehler[b.beschreiber] ?? 0) + 1;
  if (richtige.length > 0) {
    deltas[b.beschreiber] = (deltas[b.beschreiber] ?? 0) + BT_ERFOLG_MM;
    richtigZaehler[b.beschreiber] = (richtigZaehler[b.beschreiber] ?? 0) + 1;
  }

  return {
    ...state,
    deltas,
    richtigZaehler,
    beteiligtZaehler,
    phase: "aufdeckung",
    phaseStartetAt: now,
    phaseEndetAt: now + BT_AUFDECKUNG_MS,
    historie: [
      ...state.historie,
      {
        beatNr: state.beatIndex + 1,
        beschreiber: b.beschreiber,
        ratende: b.ratende,
        begriffText: b.begriff.text,
        art: b.begriff.art,
        hinweis: state.hinweis,
        richtige,
        falsche,
        uebersprungen: false,
        praemieJe: BT_ERFOLG_MM,
      },
    ],
  };
}

/** NEUTRALER Zufallsbegriff-Skip (Beschreiber weg): kein Auto-Hinweis aus der
 * Antwort — der Begriff wandert ungenutzt in den Papierkorb, 0 MM für alle. */
function ueberspringeBeat(state: BuchstabenTelegrammState, now: number): BuchstabenTelegrammState {
  const b = beat(state);
  return {
    ...state,
    phase: "aufdeckung",
    phaseStartetAt: now,
    phaseEndetAt: now + BT_AUFDECKUNG_MS,
    historie: [
      ...state.historie,
      {
        beatNr: state.beatIndex + 1,
        beschreiber: b.beschreiber,
        ratende: b.ratende,
        begriffText: b.begriff.text,
        art: b.begriff.art,
        hinweis: state.hinweis,
        richtige: [],
        falsche: [],
        uebersprungen: true,
        praemieJe: BT_ERFOLG_MM,
      },
    ],
  };
}

/** Beat aufstellen: Vorstellung (Budget-Deckel des Beschreibers einfrieren). */
function starteBeat(
  state: BuchstabenTelegrammState,
  beatIndex: number,
  now: number,
): BuchstabenTelegrammState {
  const s: BuchstabenTelegrammState = {
    ...state,
    beatIndex,
    hinweis: "",
    hinweisGesendet: false,
    antworten: {},
    maxZeichen: Math.min(BT_HINWEIS_MAX, state.budget[state.beats[beatIndex].beschreiber] ?? 0),
    phase: "vorstellung",
    phaseStartetAt: now,
    phaseEndetAt: now + BT_VORSTELLUNG_MS,
  };
  return s;
}

/** Nach der Vorstellung: offline-Beschreiber ⇒ Skip; Budget 0 ⇒ Raten ohne
 * Hinweis; sonst Tippen. */
function nachVorstellung(state: BuchstabenTelegrammState, now: number): BuchstabenTelegrammState {
  if (!state.connected[beat(state).beschreiber]) return ueberspringeBeat(state, now);
  if (state.maxZeichen === 0) return starteRaten(state, now);
  return {
    ...state,
    phase: "tippen",
    phaseStartetAt: now,
    phaseEndetAt: now + fenster(state, BT_TIPPEN_MS),
  };
}

export const buchstabenTelegrammPlugin: MinigamePlugin<
  BuchstabenTelegrammState,
  BuchstabenTelegrammAction
> = {
  meta: BUCHSTABEN_TELEGRAMM_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): BuchstabenTelegrammState {
    const slice = content as BuchstabenTelegrammSlice;
    const now = ctx.clock.now();
    const timerFaktor = content.mods?.timerFaktor ?? 1;

    // Team-Zuordnung: Slice-Injektion hat Vorrang, sonst der Match-Blick.
    let teamVon: Record<string, string> | null = slice.teamVon ?? null;
    if (teamVon === null && ctx.match?.teamVon !== undefined) {
      const tv = ctx.match.teamVon.bind(ctx.match);
      const map: Record<string, string> = {};
      for (const p of players) {
        const t = tv(p);
        if (t !== null) map[p] = t;
      }
      teamVon = Object.keys(map).length > 0 ? map : null;
    }
    const paare = btBildePaare(players, teamVon, ctx.rng);

    // Begriffs-Topf: Song-Titel + eingebauter Pool, deterministisch gemischt
    // (Song-Transport: Slice vor ctx.songs — Konvention von shared/songs.ts).
    const kandidaten: BtBegriff[] = [
      ...btBegriffeAusSongs(slice.songs ?? (ctx.songs?.songs as MvSong[] | undefined) ?? []),
      ...BT_BEGRIFFS_POOL,
    ];
    const gemischt = [...kandidaten];
    for (let i = gemischt.length - 1; i > 0; i--) {
      const j = ctx.rng.int(i + 1);
      [gemischt[i], gemischt[j]] = [gemischt[j], gemischt[i]];
    }

    const beatZahl = Math.max(1, content.questions.length);
    const beats: BtBeat[] = [];
    for (let k = 0; k < beatZahl; k++) {
      const paarIndex = k % paare.length;
      const paar = paare[paarIndex];
      const bIdx = btBeschreiberIndex(k, paare.length, paar.mitglieder.length);
      const begriff = gemischt[k % gemischt.length];
      const { optionen, answer } = btBaueOptionen(kandidaten, begriff, ctx.rng);
      beats.push({
        paarIndex,
        beschreiber: paar.mitglieder[bIdx],
        ratende: paar.mitglieder.filter((_, i) => i !== bIdx),
        begriff,
        optionen,
        answer,
      });
    }

    // Budget: Rest aus früheren Runden (Slice) oder voller Match-Start.
    const budget: Record<string, number> = {};
    for (const p of players) {
      const rest = slice.buchstabenBudget?.[p];
      budget[p] = Math.max(0, Math.min(BT_MATCH_BUDGET, rest ?? BT_MATCH_BUDGET));
    }

    const basis: BuchstabenTelegrammState = {
      players,
      paare,
      beats,
      beatIndex: 0,
      phase: "vorstellung",
      phaseStartetAt: now,
      phaseEndetAt: now + BT_VORSTELLUNG_MS,
      timerFaktor,
      startedAt: now,
      budget,
      hinweis: "",
      maxZeichen: 0,
      hinweisGesendet: false,
      antworten: {},
      deltas: {},
      richtigZaehler: {},
      beteiligtZaehler: {},
      letzteAntwort: {},
      historie: [],
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
    return starteBeat(basis, 0, now);
  },

  reduce(state: BuchstabenTelegrammState, action: Action, _ctx: Ctx): BuchstabenTelegrammState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") return { ...state, finished: true };
      return {
        ...state,
        startedAt: action.type === "timer.shift" ? state.startedAt + action.ms : state.startedAt,
        phaseStartetAt:
          action.type === "timer.shift" ? state.phaseStartetAt + action.ms : state.phaseStartetAt,
        phaseEndetAt: state.phaseEndetAt + action.ms,
      };
    }
    if (action.kind === "joker") return state; // Info-Joker passen nicht zum Paar-Spiel
    if (state.finished) return state;
    if (action.atServerTime > state.phaseEndetAt) return state;
    const p = action.playerId;
    const b = beat(state);

    // ---------- TIPPEN: der Beschreiber morst sein Telegramm ----------
    if (state.phase === "tippen" && p === b.beschreiber && !state.hinweisGesendet) {
      if (action.action.type === "buchstabe") {
        // Validierung: NUR A–Z/0–9, max. Zeichen des Beats, Budget > 0.
        const zeichen = btValidiereZeichen(action.action.zeichen);
        if (zeichen === null) return state;
        if (state.hinweis.length >= state.maxZeichen) return state;
        if ((state.budget[p] ?? 0) <= 0) return state;
        return {
          ...state,
          hinweis: state.hinweis + zeichen,
          // Telegramm-Regel: getippt = verbraucht (auch ohne Senden).
          budget: { ...state.budget, [p]: (state.budget[p] ?? 0) - 1 },
        };
      }
      if (action.action.type === "loeschen") {
        // ⌫ (nur VOR dem Senden): letztes Zeichen vom Streifen + Budget-
        // Rückgabe — Vertipper kosten nichts, Gesendetes bleibt verbraucht.
        if (state.hinweis.length === 0) return state;
        return {
          ...state,
          hinweis: state.hinweis.slice(0, -1),
          budget: { ...state.budget, [p]: Math.min(BT_MATCH_BUDGET, (state.budget[p] ?? 0) + 1) },
        };
      }
      if (action.action.type === "senden") {
        return starteRaten(state, action.atServerTime);
      }
      return state;
    }

    // ---------- RATEN: die Ratenden des Paares wählen eine Option ----------
    if (state.phase === "raten" && action.action.type === "answer") {
      if (!b.ratende.includes(p)) return state;
      if (state.antworten[p] !== undefined) return state; // erste Antwort zählt
      const choice = action.action.choice;
      if (choice < 0 || choice > 3) return state;
      const nachMs = Math.max(0, action.atServerTime - state.phaseStartetAt);
      return {
        ...state,
        antworten: { ...state.antworten, [p]: { choice, nachMs } },
        letzteAntwort: { ...state.letzteAntwort, [p]: nachMs },
      };
    }
    return state;
  },

  tick(state: BuchstabenTelegrammState, ctx: Ctx): BuchstabenTelegrammState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    if (state.phase === "vorstellung") {
      if (now >= state.phaseEndetAt) return nachVorstellung(state, now);
      return state;
    }
    if (state.phase === "tippen") {
      // Timeout ⇒ Auto-Senden der getippten Zeichen (auch 0 — Raten ohne Hinweis).
      if (now >= state.phaseEndetAt) return starteRaten(state, now);
      return state;
    }
    if (state.phase === "raten") {
      const online = verbundeneRatende(state);
      const alleFertig = online.length > 0 && online.every((p) => state.antworten[p] !== undefined);
      // Alle Ratenden offline ⇒ sofort abrechnen (keine Antwort = 0).
      if (now >= state.phaseEndetAt || alleFertig || online.length === 0) {
        return werteAus(state, now);
      }
      return state;
    }
    // aufdeckung:
    if (now >= state.phaseEndetAt) {
      const beatIndex = state.beatIndex + 1;
      if (beatIndex >= state.beats.length) return { ...state, finished: true };
      return starteBeat(state, beatIndex, now);
    }
    return state;
  },

  onDisconnect(state: BuchstabenTelegrammState, p: PlayerId, ctx: Ctx): BuchstabenTelegrammState {
    const s: BuchstabenTelegrammState = { ...state, connected: { ...state.connected, [p]: false } };
    if (s.finished) return s;
    const b = beat(s);
    // Beschreiber weg, Hinweis noch nicht gesendet ⇒ NEUTRALER Skip — die
    // Show wartet nicht (und leakt NIE Antwort-Buchstaben als Auto-Hinweis).
    if (
      p === b.beschreiber &&
      !s.hinweisGesendet &&
      (s.phase === "vorstellung" || s.phase === "tippen")
    ) {
      return ueberspringeBeat(s, ctx.clock.now());
    }
    return s;
  },

  onReconnect(state: BuchstabenTelegrammState, p: PlayerId, _ctx: Ctx): BuchstabenTelegrammState {
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: BuchstabenTelegrammState, role: Role, player?: PlayerId): unknown {
    const b = beat(state);
    const inAufdeckung = state.phase === "aufdeckung";
    const duBistBeschreiber = player !== undefined && player === b.beschreiber;
    const duBistRatender = player !== undefined && b.ratende.includes(player);
    const basis = {
      questionId: `bt-${state.beatIndex + 1}-${b.begriff.art}`,
      beatNr: state.beatIndex + 1,
      beatTotal: state.beats.length,
      phase: state.phase,
      beschreiber: b.beschreiber,
      ratende: b.ratende,
      art: b.begriff.art,
      // Der Hinweis ist PUBLIC (Screen-Inszenierung: Zeichen ticken einzeln ein).
      hinweis: state.hinweis,
      maxZeichen: state.maxZeichen,
      hinweisGesendet: state.hinweisGesendet,
      // Budget-Anzeige (Taktik-Kern): Restzeichen ALLER Spieler sind öffentlich.
      budget: state.budget,
      praemie: BT_ERFOLG_MM,
      endsAt: state.phaseEndetAt,
      timerMs:
        state.phase === "vorstellung"
          ? BT_VORSTELLUNG_MS
          : state.phase === "tippen"
            ? fenster(state, BT_TIPPEN_MS)
            : state.phase === "raten"
              ? fenster(state, BT_RATEN_MS)
              : BT_AUFDECKUNG_MS,
      abgestimmt: Object.keys(state.antworten).length,
      raterZahl: b.ratende.length,
      // Optionen sind AB dem Raten öffentlich (Screen rät mit) — der richtige
      // Index bleibt bis zur Aufdeckung geheim.
      optionen: state.phase === "raten" || inAufdeckung ? b.optionen : null,
      beat: inAufdeckung ? (state.historie.at(-1) ?? null) : null,
      historie: state.historie.slice(-4),
      deltas: state.deltas,
      finished: state.finished,
    };
    const aufloesung = state.finished
      ? {
          erklaerung:
            "Telegramm-Bilanz: Erfolg zahlt BEIDEN je 250 MM — der Zeichen-Rest verfällt.",
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct: (state.richtigZaehler[p] ?? 0) > 0,
            delta: state.deltas[p] ?? 0,
            restBudget: state.budget[p] ?? 0,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: Begriff + richtige Option + Antworten IMMER sichtbar.
      return {
        ...basis,
        begriffText: b.begriff.text,
        begriffArtist: b.begriff.artist ?? null,
        optionen: b.optionen,
        correctIndex: b.answer,
        antworten: state.antworten,
        aufloesung,
      };
    }
    if (role === "player") {
      if (duBistBeschreiber) {
        return {
          ...basis,
          duBistBeschreiber: true,
          duBistRatender: false,
          // NUR der Beschreiber sieht den Begriff (View-Leak-Wache!).
          begriffText: !inAufdeckung ? b.begriff.text : null,
          begriffArtist: !inAufdeckung ? (b.begriff.artist ?? null) : null,
          optionen: null, // der Beschreiber rät nicht
          restBudget: state.budget[player] ?? 0,
          aufloesung,
        };
      }
      return {
        ...basis,
        duBistBeschreiber: false,
        duBistRatender,
        // Optionen nur für die Ratenden DES Paares im Rate-Fenster
        // (generischer answer/choice-Draht — Bots + Publikum bleiben passiv).
        optionen: duBistRatender && state.phase === "raten" ? b.optionen : null,
        yourChoice: player !== undefined ? (state.antworten[player]?.choice ?? null) : null,
        restBudget: player !== undefined ? (state.budget[player] ?? 0) : 0,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: BuchstabenTelegrammState): boolean {
    return state.finished;
  },

  /** Runden-Summe der Paar-Prämien (roundBased: EINE Buchung am Ende). */
  scores(state: BuchstabenTelegrammState): Record<PlayerId, number> {
    const result: Record<PlayerId, number> = {};
    for (const p of state.players) result[p] = state.deltas[p] ?? 0;
    return result;
  },

  /** Awards/Auto-GM: mehrheitlich erfolgreiche Beats = „richtig". */
  outcomes(state: BuchstabenTelegrammState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    for (const p of state.players) {
      const beteiligt = state.beteiligtZaehler[p] ?? 0;
      if (beteiligt === 0) {
        result[p] = { correct: null };
        continue;
      }
      result[p] = {
        correct: (state.richtigZaehler[p] ?? 0) * 2 > beteiligt,
        nachMs: state.letzteAntwort[p],
      };
    }
    return result;
  },
};
