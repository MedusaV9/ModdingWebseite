// Pure Zustandsmaschine: (state, action, deps, ctx) → state' + Events. Kein IO,
// keine Uhr — Clock/Rng kommen aus ctx, Plugins aus deps.getPlugin (Registry).
// Der Reducer orchestriert das VOLLE Spiel nach GAME-DESIGN §1: Match-Plan,
// Kategorien-Wahl, Erklärkarten, Fragen, Jackpot, Glücksrad, Joker, Finale,
// Siegerehrung — plus Auto-GM-Heuristiken im Tick.
import { JACKPOT_GLAS_START } from "../../shared/economy";
import type { PlayerId } from "../../shared/ids";
import { JOKER } from "../../shared/jokers";
import { MAX_SPIELER, MIN_SPIELER } from "../../shared/protocol";
import { defaultSettings, type MatchSettings } from "../../shared/settings";
import { angeboteneTeams, bildeTeams, TEAM_MIN_SPIELER, type TeamId } from "../../shared/teams";
import type { Ctx, GmAction, JokerAction, PlayerAction } from "../minigames/_api/plugin";
import {
  aktuellerAbschnitt,
  beendeMatch,
  bucheGeld,
  fehler,
  highlightsWeiter,
  moment,
  naechsterAbschnitt,
  phaseWechsel,
  pluginCtx,
  schliesseFrageAb,
  schliesseKategorieWahl,
  starteFrage,
  tiebreakerTick,
  verbundene,
  weiterNachAufloesung,
  FALLBACK_MINIGAME,
  type EngineDeps,
} from "./flow";
import { reduceGm, zwischenstandWeiter } from "./gm";
import { jokerDef, preisFuer, pruefeNutzung, schildZielRunde } from "./jokers";
import { baueMatchPlan, waehleErsatzFrage } from "./plan";
import { radTick } from "./rad";
import {
  INTRO_MS,
  VOTING_ERGEBNIS_MS,
  type EngineAction,
  type EngineEvent,
  type EngineResult,
  type EngineState,
  type PlayerState,
  type TeamsState,
} from "./types";

export type { EngineDeps } from "./flow";

export function createInitialState(settings?: MatchSettings): EngineState {
  return {
    phase: "lobby",
    matchId: null,
    settings: settings ?? defaultSettings(),
    players: {},
    order: [],
    plan: null,
    abschnittIndex: -1,
    frageInAbschnitt: -1,
    fragenPool: [],
    usedQuestionIds: [],
    ultrahardGestellt: 0,
    fragenZaehler: 0,
    naechsteFrageId: null,
    zuweisungen: {},
    regalFilter: { kategorie: null, schwierigkeit: null },
    minigameId: null,
    minigameState: null,
    aktuelleFragen: [],
    phaseEndsAt: null,
    paused: null,
    jackpotGlas: 0,
    pott: 0,
    modifiers: [],
    infoJokerFrage: [],
    jokerFrageZaehler: {},
    kategorieWahl: null,
    erklaerkarte: null,
    rad: null,
    radHistorie: { letztesSegment: null, drehsOhneGold: 0 },
    voting: null,
    votingErgebnis: null,
    mood: null,
    fluesterTipp: {},
    hinweis: {},
    gezeigteTipps: [],
    momente: [],
    momentZaehler: 0,
    gm: {
      jokerChips: 6,
      verlaengerungenDieseFrage: 0,
      encoresDieseRunde: 0,
      blitzStimmungen: 3,
      hintStufeDieseFrage: 0,
      boostsDieseRunde: {},
      fluesterDieseRunde: {},
      letzteBestrafung: null,
      vorletzteBestrafung: null,
      autoTimerVerlaengert: false,
      stimmungsHistorie: [],
    },
    feedbackAngefragt: false,
    feedback: [],
    finaleWert: null,
    siegerehrung: null,
    letzteBuchung: null,
    chronik: [],
    tiebreaker: null,
    highlights: null,
    teamWuensche: {},
    teams: null,
  };
}

function neuerSpieler(action: EngineAction & { type: "join" }): PlayerState {
  return {
    id: action.playerId,
    name: action.name,
    avatar: action.avatar,
    connected: true,
    graceUntil: null,
    balance: 0,
    streak: 0,
    maxStreak: 0,
    jokers: {},
    jokerKaeufe: {},
    schildBisRunde: null,
    schildZuletztRunde: null,
    clownBisRunde: null,
    rueckenwindAngekuendigt: false,
    richtigGesamt: 0,
  };
}

export function reduce(
  state: EngineState,
  action: EngineAction,
  deps: EngineDeps,
  ctx: Ctx,
): EngineResult {
  const now = ctx.clock.now();

  switch (action.type) {
    case "join": {
      if (state.phase !== "lobby") return fehler(state, "match-laeuft");
      if (state.order.length >= MAX_SPIELER) return fehler(state, "raum-voll");
      if (state.players[action.playerId]) return fehler(state, "schon-dabei");
      return {
        state: {
          ...state,
          players: { ...state.players, [action.playerId]: neuerSpieler(action) },
          order: [...state.order, action.playerId],
        },
        events: [{ type: "player_joined", playerId: action.playerId, name: action.name }],
      };
    }

    case "presence": {
      const p = state.players[action.playerId];
      if (!p) return { state, events: [] };
      const players = {
        ...state.players,
        [action.playerId]: { ...p, connected: action.connected, graceUntil: action.graceUntil },
      };
      let minigameState = state.minigameState;
      if (state.minigameId && state.phase === "frage") {
        const plugin = deps.getPlugin(state.minigameId);
        const hook = action.connected ? plugin.onReconnect : plugin.onDisconnect;
        minigameState = hook(
          minigameState,
          action.playerId as PlayerId,
          pluginCtx(state, deps, ctx),
        );
      }
      return {
        state: { ...state, players, minigameState },
        events: [
          {
            type: "presence",
            playerId: action.playerId,
            connected: action.connected,
            graceUntil: action.graceUntil ?? undefined,
          },
        ],
      };
    }

    case "start": {
      if (state.phase !== "lobby") return fehler(state, "match-laeuft");
      if (state.order.length < MIN_SPIELER) return fehler(state, "zu-wenige-spieler");
      if (action.fragenPool.length === 0) return fehler(state, "keine-fragen");
      const plan = baueMatchPlan(state.settings, action.verfuegbareMinigames);
      // Gratis-Joker-Ladungen austeilen (§5.1) — nur wenn Joker AN sind.
      let players = state.players;
      if (state.settings.jokerAn) {
        players = {};
        for (const id of state.order) {
          const jokers: PlayerState["jokers"] = {};
          for (const def of Object.values(JOKER)) {
            if (def.gratisLadungen > 0) jokers[def.id] = def.gratisLadungen;
          }
          players[id] = { ...state.players[id], jokers };
        }
      }
      // Team-Modus „Affenbanden" (§1.4): Aufstellung aus den Lobby-Wünschen +
      // Stärke-Balance (AT-Stats) — unter 4 Spielern startet das Match individuell.
      let teams: TeamsState | null = null;
      if (state.settings.teams !== "aus" && state.order.length >= TEAM_MIN_SPIELER) {
        const aufstellung = bildeTeams({
          modus: state.settings.teams,
          spieler: [...state.order],
          wuensche: state.teamWuensche,
          staerke: action.staerke,
          rng: ctx.rng,
        });
        teams = { ...aufstellung, buzzVonTeam: {} };
      }
      const s: EngineState = {
        ...state,
        matchId: action.matchId,
        players,
        plan,
        abschnittIndex: -1,
        fragenPool: action.fragenPool,
        // ADDITIV (Musik): Song-Vorrat für contentKind-"songs"-Formate.
        songsPool: action.songsPool ?? [],
        usedSongIds: [],
        jackpotGlas: JACKPOT_GLAS_START,
        teams,
      };
      const events: EngineEvent[] = [
        {
          type: "match_started",
          matchId: action.matchId,
          playerIds: [...state.order],
          modus: state.settings.modus,
        },
      ];
      if (teams !== null) {
        events.push({
          type: "teams_gebildet",
          modus: teams.modus,
          teams: teams.teams.map((t) => ({ id: t.id, name: t.name })),
          zuordnung: { ...teams.zuordnung },
          doppelAffe: teams.doppelAffe,
        });
        const namen = teams.teams.map((t) => `${t.emoji} ${t.name}`).join(" vs ");
        moment(s, events, now, "info", `🐒 AFFENBANDEN! ${namen} — Sieger ist der höchste Topf!`);
        if (teams.doppelAffe !== null) {
          const p = s.players[teams.doppelAffe];
          moment(s, events, now, "info", `🐵🐵 Doppel-Affe: ${p.name} zählt im Team-Topf DOPPELT!`);
        }
      }
      phaseWechsel(s, events, "intro", now + INTRO_MS);
      return { state: s, events };
    }

    case "playerAction": {
      if (state.phase !== "frage" || state.paused) return fehler(state, "keine-frage-aktiv");
      if (action.minigameId !== state.minigameId) return fehler(state, "falsches-minigame");
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      // Team-Modus (Buzzer-Regel §1.4): nur EIN Buzz pro Team zählt — der erste
      // Team-Buzzer belegt den Slot, weitere Team-Mitglieder werden abgelehnt.
      let teams = state.teams;
      const istBuzz = action.action.type === "buzz";
      if (teams !== null && istBuzz) {
        const teamId = teams.zuordnung[action.playerId];
        const buzzer = teamId !== undefined ? teams.buzzVonTeam[teamId] : undefined;
        if (buzzer !== undefined && buzzer !== action.playerId) {
          return fehler(state, "team-hat-gebuzzt");
        }
      }
      const plugin = deps.getPlugin(state.minigameId);
      const playerAction: PlayerAction<{ type: string }> = {
        kind: "player",
        playerId: action.playerId as PlayerId,
        action: action.action,
        atServerTime: action.atServerTime,
      };
      const vorher = state.minigameState;
      const nachher = plugin.reduce(vorher, playerAction, pluginCtx(state, deps, ctx));
      if (nachher === vorher) return { state, events: [] }; // ignoriert (Lock/Spätantwort)
      if (teams !== null && istBuzz) {
        const teamId = teams.zuordnung[action.playerId];
        if (teamId !== undefined && teams.buzzVonTeam[teamId] === undefined) {
          teams = { ...teams, buzzVonTeam: { ...teams.buzzVonTeam, [teamId]: action.playerId } };
        }
      }
      return {
        state: { ...state, minigameState: nachher, teams },
        events: [
          {
            type: "answer_submitted",
            playerId: action.playerId,
            questionId: state.aktuelleFragen[0]?.id ?? state.minigameId,
          },
        ],
      };
    }

    // ---------- Erklärkarte: Bereit-Meldung + Streik (§5.2) ----------
    case "playerReady": {
      if (state.phase !== "erklaerkarte" || !state.erklaerkarte) {
        return fehler(state, "keine-erklaerkarte");
      }
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      if (state.erklaerkarte.bereit.includes(action.playerId)) return { state, events: [] };
      const s = {
        ...state,
        erklaerkarte: {
          ...state.erklaerkarte,
          bereit: [...state.erklaerkarte.bereit, action.playerId],
        },
      };
      const events: EngineEvent[] = [
        { type: "phase_ready", playerId: action.playerId, was: "bereit" },
      ];
      const alle = verbundene(s);
      if (alle.length > 0 && alle.every((id) => s.erklaerkarte?.bereit.includes(id))) {
        const weiter = starteFrage(s, deps, ctx);
        return { state: weiter.state, events: [...events, ...weiter.events] };
      }
      return { state: s, events };
    }

    case "playerStreik": {
      if (state.phase !== "erklaerkarte" || !state.erklaerkarte) {
        return fehler(state, "keine-erklaerkarte");
      }
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      if (state.erklaerkarte.streik.includes(action.playerId)) return { state, events: [] };
      const s = {
        ...state,
        erklaerkarte: {
          ...state.erklaerkarte,
          streik: [...state.erklaerkarte.streik, action.playerId],
        },
      };
      const events: EngineEvent[] = [
        { type: "phase_ready", playerId: action.playerId, was: "streik" },
      ];
      // Mehrheit der Verbundenen streikt ⇒ Minispiel-Tausch aufs Frage-Format (§5.2).
      const a = aktuellerAbschnitt(s);
      const mehrheit = s.erklaerkarte!.streik.length > verbundene(s).length / 2;
      if (mehrheit && a && a.minigameId !== FALLBACK_MINIGAME && s.plan) {
        const abschnitte = s.plan.abschnitte.map((x, i) =>
          i === s.abschnittIndex ? { ...x, minigameId: FALLBACK_MINIGAME } : x,
        );
        s.plan = { ...s.plan, abschnitte };
        moment(
          s,
          events,
          now,
          "info",
          "🪧 STREIK! Minispiel getauscht — es gibt das Frage-Format.",
        );
      }
      return { state: s, events };
    }

    // ---------- Kategorien-Wahl ----------
    case "kategorieVote": {
      const wahl = state.kategorieWahl;
      if (state.phase !== "kategorie-wahl" || !wahl) return fehler(state, "keine-kategorie-wahl");
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      if (state.settings.kategorienWahl === "gm") return fehler(state, "gm-waehlt");
      if (!wahl.optionen.includes(action.kategorie)) return fehler(state, "unbekannte-kategorie");
      if (wahl.nurLetzter !== null && wahl.nurLetzter !== action.playerId) {
        return fehler(state, "nur-letzter-waehlt");
      }
      const s = {
        ...state,
        kategorieWahl: {
          ...wahl,
          stimmen: { ...wahl.stimmen, [action.playerId]: action.kategorie },
        },
      };
      const events: EngineEvent[] = [
        { type: "kategorie_vote", playerId: action.playerId, kategorie: action.kategorie },
      ];
      const fertig =
        wahl.nurLetzter !== null ||
        verbundene(s).every((id) => s.kategorieWahl?.stimmen[id] !== undefined);
      if (fertig) {
        const zu = schliesseKategorieWahl(s, deps, ctx);
        return { state: zu.state, events: [...events, ...zu.events] };
      }
      return { state: s, events };
    }

    // ---------- Voting / Blitz-Stimmung ----------
    case "voteCast": {
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      if (state.mood) {
        if (action.option < 0 || action.option > 4) return fehler(state, "ungueltige-option");
        const s = {
          ...state,
          mood: {
            ...state.mood,
            werte: { ...state.mood.werte, [action.playerId]: action.option },
          },
        };
        const events: EngineEvent[] = [{ type: "mood_vote", playerId: action.playerId }];
        if (verbundene(s).every((id) => s.mood?.werte[id] !== undefined)) {
          const zu = moodFertig(s, ctx);
          return { state: zu.state, events: [...events, ...zu.events] };
        }
        return { state: s, events };
      }
      if (state.voting) {
        if (action.option < 0 || action.option >= state.voting.optionen.length) {
          return fehler(state, "ungueltige-option");
        }
        const s = {
          ...state,
          voting: {
            ...state.voting,
            stimmen: { ...state.voting.stimmen, [action.playerId]: action.option },
          },
        };
        const events: EngineEvent[] = [{ type: "vote_cast", playerId: action.playerId }];
        if (verbundene(s).every((id) => s.voting?.stimmen[id] !== undefined)) {
          const zu = votingFertig(s, ctx);
          return { state: zu.state, events: [...events, ...zu.events] };
        }
        return { state: s, events };
      }
      return fehler(state, "kein-voting");
    }

    // ---------- Rad-Interaktion ----------
    case "radAktion": {
      const rad = state.rad;
      if (state.phase !== "rad" || !rad || rad.subphase !== "interaktion") {
        return fehler(state, "keine-rad-interaktion");
      }
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      if (rad.wahlen[action.playerId] !== undefined) return { state, events: [] }; // Lock
      const seg = rad.ergebnis;
      const gueltig =
        (seg === "boersen-roulette" && (action.wahl === "long" || action.wahl === "short")) ||
        (seg === "umarmungs-bonus" && action.wahl === "umarmt") ||
        (seg === "kompliment-konto" && (action.wahl === "ja" || action.wahl === "nein"));
      if (!gueltig) return fehler(state, "ungueltige-wahl");
      return {
        state: {
          ...state,
          rad: { ...rad, wahlen: { ...rad.wahlen, [action.playerId]: action.wahl } },
        },
        events: [{ type: "rad_wahl", playerId: action.playerId, wahl: action.wahl }],
      };
    }

    // ---------- Joker zünden / nachkaufen ----------
    case "jokerUse":
      return jokerUse(state, action, deps, ctx);

    case "jokerBuy": {
      const def = jokerDef(action.jokerId);
      const p = state.players[action.playerId];
      if (!def || !p) return fehler(state, "unbekannter-joker");
      if (!state.settings.jokerAn) return fehler(state, "joker-aus");
      if ((p.jokerKaeufe[def.id] ?? 0) >= def.maxKaeufe) return fehler(state, "ausverkauft");
      const preis = preisFuer(state, action.playerId, def);
      if (p.balance < preis) return fehler(state, "zu-teuer");
      const s = { ...state };
      const events: EngineEvent[] = [];
      s.players = {
        ...s.players,
        [action.playerId]: {
          ...p,
          balance: p.balance - preis,
          jokers: { ...p.jokers, [def.id]: (p.jokers[def.id] ?? 0) + 1 },
          jokerKaeufe: { ...p.jokerKaeufe, [def.id]: (p.jokerKaeufe[def.id] ?? 0) + 1 },
        },
      };
      if (preis > 0) {
        events.push({
          type: "money_changed",
          playerId: action.playerId,
          delta: -preis,
          balance: s.players[action.playerId].balance,
          grund: `joker-kauf:${def.id}`,
        });
      }
      events.push({
        type: "joker_granted",
        playerId: action.playerId,
        jokerId: def.id,
        quelle: "kauf",
      });
      return { state: s, events };
    }

    // ---------- v2 Sudden-Death: Kokosnuss-Shake-Taps (Batch) ----------
    case "shakeTap": {
      const tb = state.tiebreaker;
      if (state.phase !== "tiebreaker" || !tb) return fehler(state, "kein-tiebreaker");
      if (tb.subphase !== "shake") return fehler(state, "shake-laeuft-nicht");
      if (!tb.teilnehmer.includes(action.playerId)) return fehler(state, "nicht-im-shake");
      // Server-Kappe pro Batch: >40 Taps/250 ms sind physisch unplausibel.
      const taps = Math.max(1, Math.min(40, Math.floor(action.taps)));
      const summe = (tb.taps[action.playerId] ?? 0) + taps;
      return {
        state: {
          ...state,
          tiebreaker: { ...tb, taps: { ...tb.taps, [action.playerId]: summe } },
        },
        events: [{ type: "shake_tap", playerId: action.playerId, taps: summe }],
      };
    }

    // ---------- Team-Modus: Team-Wunsch in der Lobby (§1.4) ----------
    case "teamWahl": {
      if (state.phase !== "lobby") return fehler(state, "nur-in-lobby");
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      if (state.settings.teams === "aus") return fehler(state, "teams-aus");
      // Angebot wie im Lobby-Screen: bei <4 Spielern schon alle Slots zeigen,
      // die ab TEAM_MIN_SPIELER verfügbar wären (Wünsche verfallen nie).
      const angeboten = angeboteneTeams(
        state.settings.teams,
        Math.max(state.order.length, TEAM_MIN_SPIELER),
      );
      if (!angeboten.includes(action.team as TeamId)) return fehler(state, "unbekanntes-team");
      return {
        state: {
          ...state,
          teamWuensche: { ...state.teamWuensche, [action.playerId]: action.team },
        },
        events: [{ type: "team_wahl", playerId: action.playerId, team: action.team }],
      };
    }

    // ---------- Feedback-Freitext ----------
    case "feedbackText": {
      if (!state.feedbackAngefragt) return fehler(state, "kein-feedback-angefragt");
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      const feedback = [
        ...state.feedback.filter((f) => f.playerId !== action.playerId),
        { playerId: action.playerId, text: action.text },
      ];
      return {
        state: { ...state, feedback },
        // Text wandert MIT ins Event-Log — Grundlage der Feedback-Inbox (§7.6/5).
        events: [{ type: "feedback_given", playerId: action.playerId, text: action.text }],
      };
    }

    default:
      return reduceGm(state, action, deps, ctx);
  }
}

// ---------- Joker-Nutzung (Wirkung → Bezahlung, in DIESER Reihenfolge) ----------

function jokerUse(
  state: EngineState,
  action: EngineAction & { type: "jokerUse" },
  deps: EngineDeps,
  ctx: Ctx,
): EngineResult {
  const now = ctx.clock.now();
  const def = jokerDef(action.jokerId);
  const p = state.players[action.playerId];
  if (!def || !p) return fehler(state, "unbekannter-joker");
  const plugin = state.minigameId ? deps.getPlugin(state.minigameId) : null;

  // Schmiergeld Stufe 2 braucht KEIN Plugin (die Engine kennt die Frage).
  let pruefung: string | null;
  if (def.id === "schmiergeld" && action.stufe === 2) {
    pruefung = !state.settings.jokerAn
      ? "joker-aus"
      : aktuellerAbschnitt(state)?.typ === "finale"
        ? "im-finale-gesperrt"
        : state.phase !== "frage"
          ? "fenster-zu"
          : state.infoJokerFrage.includes(action.playerId)
            ? "info-joker-limit"
            : state.aktuelleFragen[0]?.kind !== "choice4"
              ? "format-unterstuetzt-nicht"
              : null;
  } else {
    pruefung = pruefeNutzung(state, action.playerId, def, plugin);
  }
  if (pruefung !== null) return fehler(state, pruefung);

  const ladungen = p.jokers[def.id] ?? 0;
  let kaeufe = p.jokerKaeufe[def.id] ?? 0;
  let preis = 0;
  if (ladungen <= 0) {
    // Sofort-Kauf-und-Zünden (Schmiergeld-Modell).
    if (kaeufe >= def.maxKaeufe) return fehler(state, "ausverkauft");
    preis = preisFuer(state, action.playerId, def, action.stufe);
    if (p.balance < preis) return fehler(state, "zu-teuer");
    kaeufe += 1;
  }

  const s = { ...state };
  const events: EngineEvent[] = [];

  switch (def.id) {
    case "bananen-split":
    case "rueckgaberecht": {
      const typ = def.pluginAktion === "secondTry" ? "secondTry" : "fiftyFifty";
      const jokerAction: JokerAction = {
        kind: "joker",
        type: typ,
        playerId: action.playerId as PlayerId,
      };
      const nachher = plugin?.reduce(state.minigameState, jokerAction, pluginCtx(s, deps, ctx));
      if (nachher === undefined || nachher === state.minigameState) {
        return fehler(state, "nicht-anwendbar");
      }
      s.minigameState = nachher;
      break;
    }
    case "schmiergeld": {
      if (action.stufe === 2) {
        const frage = s.aktuelleFragen[0];
        const antwort = frage.options[frage.answer] ?? "?";
        s.hinweis = {
          ...s.hinweis,
          [action.playerId]: `Psst … der Anfangsbuchstabe ist „${antwort[0].toUpperCase()}“.`,
        };
      } else {
        const jokerAction: JokerAction = {
          kind: "joker",
          type: "removeOne",
          playerId: action.playerId as PlayerId,
        };
        const nachher = plugin?.reduce(state.minigameState, jokerAction, pluginCtx(s, deps, ctx));
        if (nachher === undefined || nachher === state.minigameState) {
          return fehler(state, "nicht-anwendbar");
        }
        s.minigameState = nachher;
      }
      break;
    }
    case "ueberziehungskredit": {
      const gmAction: GmAction = { kind: "gm", type: "timer.extend", ms: 10_000 };
      const nachher = plugin?.reduce(state.minigameState, gmAction, pluginCtx(s, deps, ctx));
      if (nachher === undefined) return fehler(state, "nicht-anwendbar");
      s.minigameState = nachher;
      events.push({ type: "timer_extended", ms: 10_000 });
      break;
    }
    case "goldene-banane": {
      if (
        s.modifiers.some((m) => m.id === "goldene-banane" && m.betroffen.includes(action.playerId))
      ) {
        return fehler(state, "schon-aktiv");
      }
      s.modifiers = [
        ...s.modifiers,
        { id: "goldene-banane", scope: "naechste-frage", betroffen: [action.playerId] },
      ];
      break;
    }
    case "bananentresor": {
      const ziel = schildZielRunde(state);
      s.players = {
        ...s.players,
        [action.playerId]: { ...p, schildBisRunde: ziel, schildZuletztRunde: ziel },
      };
      break;
    }
    case "portfolio-umschichtung": {
      const a = aktuellerAbschnitt(state);
      const ersatz = waehleErsatzFrage(state, ctx.rng, {
        schwierigkeit: a?.schwierigkeiten[0] ?? "medium",
        ausserKategorie: a?.kategorie ?? undefined,
      });
      if (!ersatz) return fehler(state, "keine-ersatzfrage");
      s.zuweisungen = { ...s.zuweisungen, [action.playerId]: ersatz.id };
      break;
    }
  }

  // Bezahlen + Ladung abbuchen (NACH erfolgreicher Wirkung).
  const p2 = s.players[action.playerId];
  s.players = {
    ...s.players,
    [action.playerId]: {
      ...p2,
      balance: p2.balance - preis,
      jokers: { ...p2.jokers, [def.id]: Math.max(0, ladungen - 1) },
      jokerKaeufe: { ...p2.jokerKaeufe, [def.id]: kaeufe },
    },
  };
  if (def.infoJoker) s.infoJokerFrage = [...s.infoJokerFrage, action.playerId];
  const key = `${def.id}:${action.playerId}`;
  s.jokerFrageZaehler = { ...s.jokerFrageZaehler, [key]: (s.jokerFrageZaehler[key] ?? 0) + 1 };

  if (preis > 0) {
    events.push({
      type: "money_changed",
      playerId: action.playerId,
      delta: -preis,
      balance: s.players[action.playerId].balance,
      grund: `joker:${def.id}`,
    });
  }
  events.push({ type: "joker_used", playerId: action.playerId, jokerId: def.id, preis });
  moment(s, events, now, "joker", `${def.emoji} ${p.name} zündet ${def.name}!`);
  return { state: s, events };
}

// ---------- Überlagerte Sub-Zustände: Blitz-Stimmung + Voting ----------

function moodFertig(state: EngineState, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const werte = [0, 0, 0, 0, 0];
  for (const w of Object.values(state.mood?.werte ?? {})) werte[w] += 1;
  s.gm = {
    ...s.gm,
    stimmungsHistorie: [...s.gm.stimmungsHistorie, { ts: ctx.clock.now(), werte }].slice(-10),
  };
  s.mood = null;
  events.push({ type: "mood_result", werte });
  return { state: s, events };
}

function votingFertig(state: EngineState, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const voting = state.voting;
  if (!voting) return { state, events: [] };
  const stimmen = voting.optionen.map(
    (_, i) => Object.values(voting.stimmen).filter((v) => v === i).length,
  );
  const max = Math.max(...stimmen);
  const gewinner = voting.optionen[stimmen.indexOf(max)] ?? "?";
  s.voting = null;
  // Ergebnis-Einblendung (Balken + Sieger-Option) für ~7 s auf Screen + Handys.
  s.votingErgebnis = {
    frage: voting.frage,
    optionen: voting.optionen,
    stimmen,
    gewinnerIndex: max > 0 ? stimmen.indexOf(max) : null,
    endetAt: ctx.clock.now() + VOTING_ERGEBNIS_MS,
  };
  events.push({ type: "vote_result", frage: voting.frage, stimmen });
  moment(s, events, ctx.clock.now(), "info", `📊 Voting „${voting.frage}“: ${gewinner}!`);
  return { state: s, events };
}

// ---------- Tick-System ----------

/** Drama-Bedarf: Führender >50 % vor dem Zweiten ⇒ Auto-GM würfelt das Rad ein. */
function dramaBedarf(state: EngineState): boolean {
  const sortiert = [...state.order].sort(
    (a, b) => state.players[b].balance - state.players[a].balance,
  );
  if (sortiert.length < 2) return false;
  const erster = state.players[sortiert[0]].balance;
  const zweiter = state.players[sortiert[1]].balance;
  return erster > 0 && (erster - zweiter) / erster > 0.5;
}

export function tick(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const now = ctx.clock.now();

  if (state.paused) {
    // Timeout-Screen mit Countdown: automatisch weiter, wenn `bis` erreicht ist.
    if (state.paused.bis !== null && now >= state.paused.bis) {
      return reduceGm(state, { type: "gm.resume" }, deps, ctx);
    }
    return { state, events: [] };
  }

  // Überlagerte Sub-Zustände laufen in JEDER Phase ab.
  if (state.mood && now >= state.mood.endetAt) return moodFertig(state, ctx);
  if (state.voting && now >= state.voting.endetAt) return votingFertig(state, ctx);
  if (state.votingErgebnis && now >= state.votingErgebnis.endetAt) {
    // Einblendung vorbei — Event triggert den Snapshot-Broadcast.
    return {
      state: { ...state, votingErgebnis: null },
      events: [{ type: "vote_ergebnis_ende" }],
    };
  }

  switch (state.phase) {
    case "frage": {
      if (!state.minigameId) return { state, events: [] };
      const plugin = deps.getPlugin(state.minigameId);
      const pctx = pluginCtx(state, deps, ctx);
      const vorher = state.minigameState;
      let nachher = plugin.tick(vorher, pctx);
      if (plugin.isFinished(nachher)) {
        return schliesseFrageAb({ ...state, minigameState: nachher }, deps, ctx);
      }
      // Auto-GM-Tipp (Eval 5 „Tipps nutzen"): zähe Frage — NIEMAND hat nach
      // 60 % der Zeit geantwortet ⇒ Tipp 1 automatisch senden (Setting
      // autoTipp, nur bei aktiver Software-Regie; die Stufe-0-Prüfung macht
      // das einmalig pro Frage). Nur Fragen MIT Autoren-Tipps — die Kosten
      // (−25 %) und der Tipp-Text laufen durch denselben gm.hintGlobal-Pfad.
      if (
        state.settings.autoGm &&
        state.settings.autoTipp &&
        state.gm.hintStufeDieseFrage === 0 &&
        (state.aktuelleFragen[0]?.tips?.length ?? 0) > 0 &&
        plugin.meta.autoVerlaengerung !== false
      ) {
        const view = plugin.viewFor(nachher, "screen") as {
          endsAt?: unknown;
          timerMs?: unknown;
          answeredCount?: unknown;
          eingabeOffen?: unknown;
        } | null;
        if (
          view?.eingabeOffen !== false &&
          typeof view?.endsAt === "number" &&
          typeof view?.timerMs === "number" &&
          typeof view?.answeredCount === "number"
        ) {
          const rest = view.endsAt - now;
          if (view.answeredCount === 0 && rest > 0 && rest <= view.timerMs * 0.4) {
            const zu = reduceGm(
              { ...state, minigameState: nachher },
              { type: "gm.hintGlobal" },
              deps,
              ctx,
            );
            if (!zu.error) {
              const s = { ...zu.state };
              const events = [...zu.events];
              moment(s, events, now, "info", "🤖 Auto-GM: Keiner traut sich — Tipp 1 kommt!");
              return { state: s, events };
            }
          }
        }
      }
      // Auto-GM-Heuristik: <50 % geantwortet und <4 s übrig ⇒ einmalig +10 s.
      // EXPLIZITES Opt-out über meta.autoVerlaengerung === false: Formate,
      // deren answeredCount keine klassischen Antworten zählt (Blitz-DJ),
      // hängen nicht mehr am Duck-Typing der View-Feldnamen allein.
      // ZUSÄTZLICH (P1 „+10s-Misfire"): Formate mit input-losen Sub-Phasen
      // melden additiv view.eingabeOffen — false heißt „gerade ist NICHTS
      // antwortbar" (AOB-Einsatz-Reveal: 3×16 s Dead-Air!), die Heuristik
      // greift dann nicht. Formate ohne das Feld behalten das Alt-Verhalten.
      if (
        state.settings.autoGm &&
        !state.gm.autoTimerVerlaengert &&
        plugin.meta.autoVerlaengerung !== false
      ) {
        const view = plugin.viewFor(nachher, "screen") as {
          endsAt?: unknown;
          answeredCount?: unknown;
          eingabeOffen?: unknown;
        } | null;
        if (
          view?.eingabeOffen !== false &&
          typeof view?.endsAt === "number" &&
          typeof view?.answeredCount === "number"
        ) {
          const rest = view.endsAt - now;
          const halb = Math.ceil(verbundene(state).length / 2);
          if (rest > 0 && rest < 4000 && view.answeredCount < halb) {
            const gmAction: GmAction = { kind: "gm", type: "timer.extend", ms: 10_000 };
            nachher = plugin.reduce(nachher, gmAction, pctx);
            const s = {
              ...state,
              minigameState: nachher,
              gm: { ...state.gm, autoTimerVerlaengert: true },
            };
            const events: EngineEvent[] = [{ type: "timer_extended", ms: 10_000 }];
            moment(s, events, now, "info", "🤖 Auto-GM: +10 s — die Hälfte grübelt noch!");
            return { state: s, events };
          }
        }
      }
      return nachher === vorher
        ? { state, events: [] }
        : { state: { ...state, minigameState: nachher }, events: [] };
    }

    case "kategorie-wahl": {
      if (state.kategorieWahl && now >= state.kategorieWahl.endetAt) {
        return schliesseKategorieWahl(state, deps, ctx);
      }
      return { state, events: [] };
    }

    case "erklaerkarte": {
      if (state.erklaerkarte && now >= state.erklaerkarte.endetAt) {
        return starteFrage(state, deps, ctx);
      }
      return { state, events: [] };
    }

    case "rad":
      return radTick(state, deps, ctx);

    // v2 Sudden-Death: countdown → shake → ergebnis (Deadlines im Sub-Zustand).
    case "tiebreaker":
      return tiebreakerTick(state, ctx);

    default: {
      if (state.phaseEndsAt === null || now < state.phaseEndsAt) return { state, events: [] };
      switch (state.phase) {
        case "intro":
          return naechsterAbschnitt(state, deps, ctx);
        // v2: nächste Highlight-Karte (nach der letzten: Siegerehrung).
        case "highlights":
          return highlightsWeiter(state, ctx);
        case "aufloesung":
          return weiterNachAufloesung(state, deps, ctx);
        case "zwischenstand": {
          // Auto-GM: spontaner Rad-Dreh, wenn das Match auseinanderläuft.
          const a = aktuellerAbschnitt(state);
          if (
            state.settings.autoGm &&
            state.settings.rad === "an" &&
            a !== null &&
            !a.radDanach &&
            state.plan !== null &&
            state.abschnittIndex < state.plan.abschnitte.length - 1 &&
            dramaBedarf(state)
          ) {
            return reduceGm(
              { ...state, phase: "zwischenstand" },
              { type: "gm.wheelSpin" },
              deps,
              ctx,
            );
          }
          return zwischenstandWeiter(state, deps, ctx);
        }
        case "siegerehrung":
          return beendeMatch(state, ctx);
        default:
          return { state, events: [] };
      }
    }
  }
}

// Für Räume/Tests: Geld-Hilfsbuchung mit Event (z. B. Migrations-Szenarien).
export { bucheGeld };
