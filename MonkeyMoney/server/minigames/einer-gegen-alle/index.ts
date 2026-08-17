// „Einer gegen alle" (Welle 4): der FÜHRENDE des Zwischenstands (ctx.match,
// Gleichstand: Join-Reihenfolge) tritt als SOLIST allein gegen den Rest an.
//
// ABLAUF (eine Runden-Instanz, meta.roundBased — EINE Buchung am Ende):
//   vorstellung (6 s Podest-Beat: Solist vs. Tribüne) → je Frage: frage
//   (12 s: der Solist antwortet für sich, die Menge stimmt kollektiv ab —
//   die MEHRHEIT zählt fürs Team, Gleichstand ⇒ Los via ctx.rng) →
//   enthuellung (6 s: die Abstimmungs-Balken fallen, Deltas fliegen) … →
//   ergebnis (7 s Schluss-Bilanz Solist vs. Team).
//
// GELD-MATHE (Single Source of Truth: egaFrageDeltas in der Meta, alles Bank):
//   Solist richtig + Menge falsch = Solist +400 · beide richtig = je +150 ·
//   Menge richtig + Solist falsch = jedes Mengen-Mitglied +200 · sonst nichts.
//
// LEAK-WACHE (die Spannung des Formats): der Solist sieht die Mengen-Antwort
// NIE vor der Enthüllung — im Frage-Fenster reist NUR die Stimm-Anzahl
// (Beteiligungs-Balken), die Verteilung bleibt bis zur Enthüllung serverseitig
// (auch Screen und Menge sehen sie nicht früher; GM-Spickzettel sieht alles).
//
// EDGE-CASES: Solist-Disconnect ⇒ das Format endet NEUTRAL (alle Scores 0,
// auch bereits verdiente Beats verfallen — niemand profitiert vom Wegbruch);
// Mengen-Mitglied-Disconnect ⇒ Stimme entfällt künftig, das Team spielt
// weiter; KEINE Stimmen in einem Fenster ⇒ die Menge liegt falsch; GM-Skip
// vor dem Ergebnis ⇒ Abbruch ohne Zahlung. POOL-WÄCHTER: init filtert
// kaputte Fragen und wirft ohne brauchbare Frage.
import type { ContentSlice, Question } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import {
  EGA_BEIDE_MM,
  EGA_ENTHUELLUNG_MS,
  EGA_ERGEBNIS_MS,
  EGA_FRAGE_MS,
  EGA_FRAGEN,
  EGA_SOLO_MM,
  EGA_TEAM_MM,
  EGA_VORSTELLUNG_MS,
  EINER_GEGEN_ALLE_META,
  egaFrageDeltas,
  egaMehrheit,
  type EinerGegenAlleAction,
} from "../../../shared/minigames/einer-gegen-alle.meta";
import { SPAETANTWORT_GNADE_MS } from "../../../shared/protocol";
import type {
  Ctx,
  GmAction,
  MinigamePlugin,
  PlayerAction,
  PlayerOutcome,
  Role,
} from "../_api/plugin";

export type EgaPhase = "vorstellung" | "frage" | "enthuellung" | "ergebnis";

/** Ergebnis der letzten Frage — Grundlage des Enthüllungs-Beats. */
export interface EgaFrageErgebnis {
  questionId: string;
  /** Options-Texte der AUFGELÖSTEN Frage (kein Leak — das Fenster ist zu):
   * die Enthüllungs-Balken auf dem Screen brauchen die Beschriftung. */
  optionen: string[];
  correctIndex: number;
  erklaerung: string;
  solistChoice: number | null;
  solistRichtig: boolean;
  mengeChoice: number | null;
  mengeRichtig: boolean;
  gleichstand: boolean;
  verteilung: number[];
  deltas: Record<string, number>;
}

export interface EinerGegenAlleState {
  players: PlayerId[];
  questions: Question[];
  startedAt: number;
  phase: EgaPhase;
  phaseEndsAt: number;
  timerMs: number; // Frage-Fenster (mit mods.timerFaktor)
  solist: PlayerId;
  frageNonce: number;
  frageNr: number; // 1-basiert (max. EGA_FRAGEN)
  frageStartetAt: number | null;
  /** Solist-Antwort + Mengen-Stimmen des AKTUELLEN Fensters (rasten ein). */
  answers: Record<string, { choice: number; nachMs: number }>;
  /** Kumulierte Deltas (Bank) — die Buchungs-Grundlage. */
  deltas: Record<string, number>;
  /** Show-Wertung: gewonnene Beats (Solo-Coups vs. Team-Triumphe). */
  soloPunkte: number;
  teamPunkte: number;
  solistRichtigZaehler: number;
  solistLetzteMs: number | null;
  letzteFrage: EgaFrageErgebnis | null;
  /** Solist-Disconnect: das Format endete neutral (alle Zahlungen verfallen). */
  neutral: boolean;
  abgebrochen: boolean;
  connected: Record<string, boolean>;
  finished: boolean;
}

type Action = PlayerAction<EinerGegenAlleAction> | GmAction;

function aktuelleFrage(state: EinerGegenAlleState): Question {
  // Vorstellung (frageNr 0): die kommende Frage 1 als Identitäts-Anker.
  return state.questions[Math.max(0, state.frageNr - 1) % state.questions.length];
}

function menge(state: EinerGegenAlleState): PlayerId[] {
  return state.players.filter((p) => p !== state.solist);
}

/** Der Führende des Zwischenstands (Gleichstand: frühere Join-Reihenfolge). */
function fuehrender(players: PlayerId[], balances: Record<string, number> | null): PlayerId {
  if (balances === null) return players[0];
  return players.reduce((best, p) => ((balances[p] ?? 0) > (balances[best] ?? 0) ? p : best));
}

function starteFrage(state: EinerGegenAlleState, now: number): EinerGegenAlleState {
  return {
    ...state,
    phase: "frage",
    phaseEndsAt: now + state.timerMs,
    frageNonce: state.frageNonce + 1,
    frageNr: state.frageNr + 1,
    frageStartetAt: now,
    answers: {},
  };
}

function starteErgebnis(
  state: EinerGegenAlleState,
  now: number,
  flags: Partial<Pick<EinerGegenAlleState, "neutral" | "abgebrochen">> = {},
): EinerGegenAlleState {
  return { ...state, phase: "ergebnis", phaseEndsAt: now + EGA_ERGEBNIS_MS, ...flags };
}

/** Frage auswerten: Mehrheits-Auszählung + egaFrageDeltas + Show-Punkte. */
function werteFrageAus(state: EinerGegenAlleState, now: number, ctx: Ctx): EinerGegenAlleState {
  const frage = aktuelleFrage(state);
  const solistAntwort = state.answers[state.solist];
  const stimmen: Record<string, number> = {};
  for (const p of menge(state)) {
    const a = state.answers[p];
    if (a !== undefined) stimmen[p] = a.choice;
  }
  const mehrheit = egaMehrheit(stimmen, frage.options.length, ctx.rng);
  const solistRichtig = solistAntwort?.choice === frage.answer;
  const mengeRichtig = mehrheit.choice === frage.answer;
  const frageDeltas = egaFrageDeltas(state.solist, menge(state), solistRichtig, mengeRichtig);

  const deltas = { ...state.deltas };
  for (const [p, d] of Object.entries(frageDeltas)) deltas[p] = (deltas[p] ?? 0) + d;

  return {
    ...state,
    deltas,
    soloPunkte: state.soloPunkte + (solistRichtig && !mengeRichtig ? 1 : 0),
    teamPunkte: state.teamPunkte + (mengeRichtig && !solistRichtig ? 1 : 0),
    solistRichtigZaehler: state.solistRichtigZaehler + (solistRichtig ? 1 : 0),
    solistLetzteMs: solistAntwort?.nachMs ?? state.solistLetzteMs,
    letzteFrage: {
      questionId: frage.id,
      optionen: [...frage.options],
      correctIndex: frage.answer,
      erklaerung: frage.erklaerung,
      solistChoice: solistAntwort?.choice ?? null,
      solistRichtig,
      mengeChoice: mehrheit.choice,
      mengeRichtig,
      gleichstand: mehrheit.gleichstand,
      verteilung: mehrheit.verteilung,
      deltas: frageDeltas,
    },
    phase: "enthuellung",
    phaseEndsAt: now + EGA_ENTHUELLUNG_MS,
  };
}

/** Solist-Offline-Wache: das Format endet NEUTRAL (niemand bekommt etwas). */
function pruefeSolistOffline(state: EinerGegenAlleState, now: number): EinerGegenAlleState | null {
  if (state.connected[state.solist]) return null;
  return starteErgebnis(state, now, { neutral: true });
}

/** Scores (eine Buchung): kumulierte Bank-Deltas — 0 bei neutral/Abbruch. */
function berechneScores(state: EinerGegenAlleState): Record<PlayerId, number> {
  const result: Record<PlayerId, number> = {};
  for (const p of state.players) {
    result[p] = state.neutral || state.abgebrochen ? 0 : (state.deltas[p] ?? 0);
  }
  return result;
}

export const einerGegenAllePlugin: MinigamePlugin<EinerGegenAlleState, EinerGegenAlleAction> = {
  meta: EINER_GEGEN_ALLE_META,

  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): EinerGegenAlleState {
    // Pool-Wächter: nur Fragen mit sauberem Options/Antwort-Paar aufs Podest.
    const questions = content.questions.filter(
      (q) =>
        q.text.length > 0 &&
        q.options.length >= 2 &&
        Number.isInteger(q.answer) &&
        q.answer >= 0 &&
        q.answer < q.options.length,
    );
    if (questions.length === 0) {
      throw new Error("einer-gegen-alle: ContentSlice ohne brauchbare Frage");
    }
    const now = ctx.clock.now();
    const match = ctx.match;
    const balances = match ? Object.fromEntries(players.map((p) => [p, match.balance(p)])) : null;
    return {
      players,
      questions,
      startedAt: now,
      phase: "vorstellung",
      phaseEndsAt: now + EGA_VORSTELLUNG_MS,
      timerMs: Math.round(EGA_FRAGE_MS * (content.mods?.timerFaktor ?? 1)),
      solist: fuehrender(players, balances),
      frageNonce: 0,
      frageNr: 0,
      frageStartetAt: null,
      answers: {},
      deltas: {},
      soloPunkte: 0,
      teamPunkte: 0,
      solistRichtigZaehler: 0,
      solistLetzteMs: null,
      letzteFrage: null,
      neutral: false,
      abgebrochen: false,
      connected: Object.fromEntries(players.map((p) => [p, true])),
      finished: false,
    };
  },

  reduce(state: EinerGegenAlleState, action: Action, ctx: Ctx): EinerGegenAlleState {
    if (action.kind === "gm") {
      if (action.type === "force.finish") {
        // GM-Skip: steht die Bilanz schon (Ergebnis läuft), gilt sie —
        // sonst verfällt die Runde ohne Zahlung.
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
    void ctx;

    // ---------- Antwort/Stimme (erste Wahl rastet ein) ----------
    if (action.action.type !== "answer") return state;
    if (state.phase !== "frage" || state.frageStartetAt === null) return state;
    const p = action.playerId;
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
        },
      },
    };
  },

  tick(state: EinerGegenAlleState, ctx: Ctx): EinerGegenAlleState {
    if (state.finished) return state;
    const now = ctx.clock.now();

    // Solist-Offline-Wache VOR jedem Fortschritt (außer die Bilanz läuft).
    if (state.phase !== "ergebnis") {
      const offline = pruefeSolistOffline(state, now);
      if (offline !== null) return offline;
    }

    if (state.phase === "vorstellung") {
      if (now < state.phaseEndsAt) return state;
      return starteFrage(state, now);
    }

    if (state.phase === "frage") {
      // Früh-Auswertung: Solist UND alle verbundenen Mengen-Mitglieder fertig.
      const offen = state.players.filter(
        (p) => state.connected[p] && state.answers[p] === undefined,
      );
      if (offen.length === 0 || now >= state.phaseEndsAt + SPAETANTWORT_GNADE_MS) {
        return werteFrageAus(state, now, ctx);
      }
      return state;
    }

    if (state.phase === "enthuellung") {
      if (now < state.phaseEndsAt) return state;
      if (state.frageNr >= EGA_FRAGEN) return starteErgebnis(state, now);
      return starteFrage(state, now);
    }

    // Phase "ergebnis" vorbei ⇒ fertig (die Engine bucht und löst auf).
    if (now < state.phaseEndsAt) return state;
    return { ...state, finished: true };
  },

  onDisconnect(state: EinerGegenAlleState, p: PlayerId, ctx: Ctx): EinerGegenAlleState {
    const s: EinerGegenAlleState = { ...state, connected: { ...state.connected, [p]: false } };
    // Der Solist bricht weg ⇒ das Format endet SOFORT neutral (Design-Edge).
    if (!s.finished && s.phase !== "ergebnis" && p === s.solist) {
      return pruefeSolistOffline(s, ctx.clock.now()) ?? s;
    }
    return s;
  },

  onReconnect(state: EinerGegenAlleState, p: PlayerId, _ctx: Ctx): EinerGegenAlleState {
    // Ein neutral beendetes Format bleibt beendet (kein Wiedereinstieg).
    return { ...state, connected: { ...state.connected, [p]: true } };
  },

  viewFor(state: EinerGegenAlleState, role: Role, player?: PlayerId): unknown {
    const frage = aktuelleFrage(state);
    const frageOffen = state.phase === "frage";
    const timerMs =
      state.phase === "vorstellung"
        ? EGA_VORSTELLUNG_MS
        : state.phase === "frage"
          ? state.timerMs
          : state.phase === "enthuellung"
            ? EGA_ENTHUELLUNG_MS
            : EGA_ERGEBNIS_MS;
    const scores = state.finished || state.phase === "ergebnis" ? berechneScores(state) : null;
    const mengeIds = menge(state);
    const stimmenAbgegeben = mengeIds.filter((p) => state.answers[p] !== undefined).length;

    const basis = {
      questionId: frage.id,
      frageNonce: state.frageNonce,
      phase: state.phase,
      endsAt: state.phaseEndsAt,
      timerMs,
      frageNr: state.frageNr,
      fragen: EGA_FRAGEN,
      solist: state.solist,
      menge: mengeIds,
      spieler: state.players,
      soloPunkte: state.soloPunkte,
      teamPunkte: state.teamPunkte,
      soloMM: EGA_SOLO_MM,
      beideMM: EGA_BEIDE_MM,
      teamMM: EGA_TEAM_MM,
      bilanz: state.neutral || state.abgebrochen ? {} : state.deltas,
      // Frage-Text/Optionen NUR im laufenden Fenster (Leak-Wache).
      text: frageOffen ? frage.text : null,
      options: frageOffen ? frage.options : null,
      // LIVE reist NUR die Beteiligung — die Verteilung bleibt bis zur
      // Enthüllung auf dem Server (anonym = die Spannung des Formats).
      stimmenAbgegeben,
      mengeGroesse: mengeIds.length,
      solistHatGeantwortet: state.answers[state.solist] !== undefined,
      answeredCount: frageOffen ? Object.keys(state.answers).length : 0,
      // Enthüllungs-Beat (Verteilung + correctIndex) erst NACH dem Fenster.
      letzteFrage: state.phase === "enthuellung" ? state.letzteFrage : null,
      ergebnis:
        scores !== null
          ? {
              neutral: state.neutral,
              abgebrochen: state.abgebrochen,
              soloPunkte: state.soloPunkte,
              teamPunkte: state.teamPunkte,
              sieger:
                state.neutral || state.abgebrochen
                  ? null
                  : state.soloPunkte === state.teamPunkte
                    ? null
                    : state.soloPunkte > state.teamPunkte
                      ? "solist"
                      : "menge",
            }
          : null,
      finished: state.finished,
    };

    const aufloesung = state.finished
      ? {
          correctIndex: state.letzteFrage?.correctIndex ?? null,
          erklaerung: state.abgebrochen
            ? "Runde abgebrochen — keine Zahlungen."
            : state.neutral
              ? "Der Solist ist weg — das Format endet neutral, keine Zahlungen."
              : `Solo-Coup ${EGA_SOLO_MM} · beide richtig je ${EGA_BEIDE_MM} · Team-Triumph ${EGA_TEAM_MM} pro Kopf — alles aus der Bank.`,
          perPlayer: state.players.map((p) => ({
            playerId: p,
            choice: null,
            correct:
              state.neutral || state.abgebrochen
                ? false
                : p === state.solist
                  ? state.soloPunkte > state.teamPunkte
                  : state.teamPunkte > state.soloPunkte,
            delta: scores?.[p] ?? 0,
          })),
        }
      : null;

    if (role === "gm") {
      // Spickzettel: Frage + Lösung + LIVE-Verteilung + Solist-Wahl IMMER.
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
      const istSolist = player === state.solist;
      return {
        ...basis,
        duBistSolist: istSolist,
        yourChoice:
          frageOffen && player !== undefined ? (state.answers[player]?.choice ?? null) : null,
        // BEIDE Seiten bekommen die Buttons — der Server zählt getrennt.
        options: frageOffen ? frage.options : null,
        aufloesung,
      };
    }
    return { ...basis, aufloesung };
  },

  isFinished(state: EinerGegenAlleState): boolean {
    return state.finished;
  },

  scores(state: EinerGegenAlleState): Record<PlayerId, number> {
    return berechneScores(state);
  },

  /** Keine Streak (meta) — outcomes dienen Awards/Auto-GM/Chronik. */
  outcomes(state: EinerGegenAlleState): Record<PlayerId, PlayerOutcome> {
    const result: Record<PlayerId, PlayerOutcome> = {};
    const halbe = EGA_FRAGEN / 2;
    for (const p of state.players) {
      if (state.neutral || state.abgebrochen) {
        result[p] = { correct: null };
        continue;
      }
      if (p === state.solist) {
        result[p] = {
          correct: state.solistRichtigZaehler === halbe ? null : state.solistRichtigZaehler > halbe,
          nachMs: state.solistLetzteMs ?? undefined,
        };
        continue;
      }
      result[p] = {
        correct: state.teamPunkte === state.soloPunkte ? null : state.teamPunkte > state.soloPunkte,
      };
    }
    return result;
  },
};
