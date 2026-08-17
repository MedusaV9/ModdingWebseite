// GM-Reducer: alle Werkzeuge aus GAME-DESIGN §4.2 als Engine-Aktionen — mit den
// Fairness-Leitplanken aus §4.3 im SERVER (Budgets, Anti-Mobbing, Soft-Caps).
// Jede Wirkung läuft durch denselben Reducer wie Spieler-Aktionen (EIN Kanal).
import { BANANENSTEUER, DISPO_LIMIT, scoreAdjustSoftCap } from "../../shared/economy";
import { FRAGE_WERTE, formatMM } from "../../shared/money";
import { patchSettings } from "../../shared/settings";
import { angeboteneTeams, TEAM_MIN_SPIELER, type TeamId } from "../../shared/teams";
import type { Ctx, GmAction, JokerAction } from "../minigames/_api/plugin";
import { aktuelleRunde, jokerDef } from "./jokers";
import {
  aktuelleFrageDesFormats,
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
  starteHighlights,
  starteSiegerehrung,
  rundenEnde,
  tiebreakerTick,
  weiterNachAufloesung,
  type EngineDeps,
} from "./flow";
import { radDrehFertig, radFertig, radInteraktionFertig, starteRad } from "./rad";
import {
  MOOD_POLL_MS,
  VOTING_MS,
  type EngineAction,
  type EngineEvent,
  type EngineResult,
  type EngineState,
} from "./types";

/** Podest fixiert: ab Sudden-Death/Highlights sind Punkte-Kommandos tabu —
 * der Tiebreaker wäre sonst manipulierbar und die Platzierung würde wackeln. */
function istPodestFixiert(state: EngineState): boolean {
  return ["tiebreaker", "highlights", "siegerehrung", "ende"].includes(state.phase);
}

/** Zwischenstand → Rad-Beat (Plan) oder nächster Abschnitt. */
export function zwischenstandWeiter(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const a = aktuellerAbschnitt(state);
  if (a?.radDanach && state.settings.rad === "an") return starteRad(state, deps, ctx);
  return naechsterAbschnitt(state, deps, ctx);
}

/** Alle Server-Deadlines um `delta` verschieben (Pause/Resume bleibt fair). */
function verschiebeDeadlines(
  state: EngineState,
  deps: EngineDeps,
  ctx: Ctx,
  delta: number,
): EngineState {
  const s = { ...state };
  if (s.phase === "frage" && s.minigameId) {
    const gmAction: GmAction = { kind: "gm", type: "timer.shift", ms: delta };
    s.minigameState = deps
      .getPlugin(s.minigameId)
      .reduce(s.minigameState, gmAction, pluginCtx(s, deps, ctx));
  }
  if (s.phaseEndsAt !== null) s.phaseEndsAt += delta;
  if (s.kategorieWahl)
    s.kategorieWahl = { ...s.kategorieWahl, endetAt: s.kategorieWahl.endetAt + delta };
  if (s.erklaerkarte)
    s.erklaerkarte = { ...s.erklaerkarte, endetAt: s.erklaerkarte.endetAt + delta };
  if (s.rad) {
    s.rad = {
      ...s.rad,
      subEndetAt: s.rad.subEndetAt + delta,
      drehStartetAt: s.rad.drehStartetAt + delta,
    };
  }
  if (s.voting) s.voting = { ...s.voting, endetAt: s.voting.endetAt + delta };
  if (s.votingErgebnis) {
    s.votingErgebnis = { ...s.votingErgebnis, endetAt: s.votingErgebnis.endetAt + delta };
  }
  if (s.mood) s.mood = { ...s.mood, endetAt: s.mood.endetAt + delta };
  return s;
}

export function reduceGm(
  state: EngineState,
  action: EngineAction,
  deps: EngineDeps,
  ctx: Ctx,
): EngineResult {
  const now = ctx.clock.now();

  switch (action.type) {
    // ---------- 1) Punkte ± (Begründungs-Chip PFLICHT, Soft-Cap §4.3) ----------
    case "gm.scoreAdjust": {
      // Ab Siegerehrungs-Start ist das Podest FIXIERT (Befund: Podium-Wackler).
      if (istPodestFixiert(state)) return fehler(state, "podest-fixiert");
      const p = state.players[action.playerId];
      if (!p) return fehler(state, "unbekannter-spieler");
      if (!action.grund) return fehler(state, "grund-pflicht");
      const cap = scoreAdjustSoftCap(aktuellerAbschnitt(state)?.fragen ?? 4);
      if (Math.abs(action.delta) > cap && action.override !== true) {
        return fehler(state, `soft-cap:${cap}`);
      }
      const s = { ...state };
      const events: EngineEvent[] = [];
      bucheGeld(s, events, action.playerId, action.delta, action.grund);
      // §4.2/1: Begründungs-Chip wird ÖFFENTLICH inszeniert (Screen + Handys).
      moment(
        s,
        events,
        now,
        "info",
        `🏦 Bananen-Bank: ${p.name} ${action.delta >= 0 ? "+" : "−"}${formatMM(Math.abs(action.delta))} — ${action.grund}`,
      );
      return { state: s, events };
    }

    // ---------- 2) Zeit +15 s (max. 2× pro Frage) ----------
    case "gm.timerExtend": {
      if (state.paused) return fehler(state, "pausiert");
      if (state.phase === "frage" && state.minigameId) {
        if (state.gm.verlaengerungenDieseFrage >= 2) return fehler(state, "max-verlaengerungen");
        const gmAction: GmAction = { kind: "gm", type: "timer.extend", ms: action.ms };
        const s = { ...state };
        s.minigameState = deps
          .getPlugin(state.minigameId)
          .reduce(state.minigameState, gmAction, pluginCtx(s, deps, ctx));
        s.gm = { ...s.gm, verlaengerungenDieseFrage: s.gm.verlaengerungenDieseFrage + 1 };
        return { state: s, events: [{ type: "timer_extended", ms: action.ms }] };
      }
      if (state.phaseEndsAt === null) return fehler(state, "kein-timer");
      return {
        state: { ...state, phaseEndsAt: state.phaseEndsAt + action.ms },
        events: [{ type: "timer_extended", ms: action.ms }],
      };
    }

    // ---------- 11) Bananen-Pause / Timeout-Screen (Countdown auf ALLEN Geräten) ----------
    case "gm.pause": {
      if (state.paused) return fehler(state, "schon-pausiert");
      if (state.phase === "lobby" || state.phase === "ende") return fehler(state, "nichts-laeuft");
      const bis = action.dauerMs !== undefined ? now + action.dauerMs : null;
      return {
        state: { ...state, paused: { text: action.text, seit: now, bis } },
        events: [{ type: "phase_changed", phase: state.phase }],
      };
    }

    case "gm.resume": {
      if (!state.paused) return fehler(state, "nicht-pausiert");
      const delta = now - state.paused.seit;
      const s = verschiebeDeadlines(state, deps, ctx, delta);
      s.paused = null;
      return { state: s, events: [{ type: "phase_changed", phase: s.phase }] };
    }

    // ---------- Universal-Skip: „Weiter" in jeder Phase ----------
    case "gm.next": {
      if (state.paused) return fehler(state, "pausiert");
      switch (state.phase) {
        case "lobby":
          return fehler(state, "start-ueber-room");
        case "intro":
          return naechsterAbschnitt(state, deps, ctx);
        case "kategorie-wahl":
          return schliesseKategorieWahl(state, deps, ctx);
        case "erklaerkarte":
          return starteFrage(state, deps, ctx);
        case "frage": {
          const gmAction: GmAction = { kind: "gm", type: "force.finish" };
          const minigameState = deps
            .getPlugin(state.minigameId ?? "")
            .reduce(state.minigameState, gmAction, pluginCtx(state, deps, ctx));
          return schliesseFrageAb({ ...state, minigameState }, deps, ctx);
        }
        case "aufloesung":
          return weiterNachAufloesung(state, deps, ctx);
        case "zwischenstand":
          return zwischenstandWeiter(state, deps, ctx);
        case "rad": {
          if (state.rad?.subphase === "dreh") return radDrehFertig(state, deps, ctx);
          if (state.rad?.subphase === "interaktion") return radInteraktionFertig(state, deps, ctx);
          return radFertig(state, deps, ctx);
        }
        // v2 Sudden-Death: Skip = aktuelle Sub-Phase sofort beenden.
        case "tiebreaker": {
          const tb = state.tiebreaker;
          if (!tb) return starteHighlights({ ...state }, ctx, []);
          const s = { ...state, tiebreaker: { ...tb, endetAt: now }, phaseEndsAt: now };
          return tiebreakerTick(s, ctx);
        }
        // v2 Replay-Highlights: Skip = nächste Karte (bzw. Siegerehrung).
        case "highlights":
          return highlightsWeiter(state, ctx);
        case "siegerehrung":
          return beendeMatch(state, ctx);
        default:
          return fehler(state, "nichts-zu-skippen");
      }
    }

    // ---------- Settings (Modus nur in der Lobby wechselbar) ----------
    case "gm.settings": {
      const patch = { ...action.patch };
      if (state.phase !== "lobby") delete patch.modus;
      const settings = patchSettings(state.settings, patch);
      return {
        state: { ...state, settings },
        events: [{ type: "settings_changed", patch }],
      };
    }

    // ---------- 2/3) Kategorie-Pick + Fragen-Regal ----------
    case "gm.kategoriePick": {
      if (state.phase !== "kategorie-wahl" || !state.kategorieWahl) {
        return fehler(state, "keine-kategorie-wahl");
      }
      if (!state.kategorieWahl.optionen.includes(action.kategorie)) {
        return fehler(state, "unbekannte-kategorie");
      }
      return schliesseKategorieWahl(state, deps, ctx, action.kategorie);
    }

    case "gm.questionPick": {
      const q = state.fragenPool.find(
        (x) => x.id === action.questionId && !state.usedQuestionIds.includes(x.id),
      );
      if (!q) return fehler(state, "frage-nicht-verfuegbar");
      return {
        state: { ...state, naechsteFrageId: action.questionId },
        events: [
          { type: "gm_command", cmd: "questionPick", args: { questionId: action.questionId } },
        ],
      };
    }

    // ---------- Maßanzug: Frage pro Spieler zuweisen ----------
    case "gm.questionAssign": {
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      const zuweisungen = { ...state.zuweisungen };
      if (action.questionId === null) {
        delete zuweisungen[action.playerId];
      } else {
        const q = state.fragenPool.find(
          (x) => x.id === action.questionId && !state.usedQuestionIds.includes(x.id),
        );
        if (!q) return fehler(state, "frage-nicht-verfuegbar");
        zuweisungen[action.playerId] = action.questionId;
      }
      return {
        state: { ...state, zuweisungen },
        events: [
          {
            type: "gm_command",
            cmd: "questionAssign",
            args: { playerId: action.playerId, questionId: action.questionId },
          },
        ],
      };
    }

    case "gm.regalFilter": {
      const schwierigkeit =
        action.schwierigkeit === "easy" ||
        action.schwierigkeit === "medium" ||
        action.schwierigkeit === "hard" ||
        action.schwierigkeit === "ultrahard"
          ? action.schwierigkeit
          : null;
      return {
        state: {
          ...state,
          regalFilter: { kategorie: action.kategorie ?? null, schwierigkeit },
        },
        events: [{ type: "gm_command", cmd: "regalFilter", args: {} }],
      };
    }

    // ---------- 6/7) Tipp-Kanone global + Flüster-Tipp privat ----------
    // Stufenweise Enthüllung (Eval 5 „Tipps sind tote Fracht"): Fragen MIT
    // Autoren-Tipps senden den echten Tipp-TEXT (Stufe 1→2→3, öffentlich);
    // Fragen ohne Tipps behalten das alte removeOne (1 falsche Option weg).
    // Beide Wege kosten sichtbar −25 % Gewinn pro Stufe (bucheFrage).
    case "gm.hintGlobal": {
      if (state.phase !== "frage" || !state.minigameId) return fehler(state, "keine-frage-aktiv");
      if (state.gm.hintStufeDieseFrage >= 3) return fehler(state, "max-hints");
      const s = { ...state };
      const events: EngineEvent[] = [];
      const stufe = s.gm.hintStufeDieseFrage + 1;
      const tippText = aktuelleFrageDesFormats(state, deps)?.tips?.[stufe - 1];
      if (tippText !== undefined) {
        s.gezeigteTipps = [...(s.gezeigteTipps ?? []), tippText];
        moment(s, events, now, "info", `💡 Tipp ${stufe}: ${tippText} (Gewinn −${stufe * 25} %)`);
      } else {
        const plugin = deps.getPlugin(state.minigameId);
        if (plugin.meta.jokerAktionen?.includes("removeOne")) {
          const jokerAction: JokerAction = { kind: "joker", type: "removeOne", playerId: null };
          s.minigameState = plugin.reduce(s.minigameState, jokerAction, pluginCtx(s, deps, ctx));
        }
        moment(s, events, now, "info", `💡 Tipp-Kanone Stufe ${stufe} — Gewinn −${stufe * 25} %!`);
      }
      s.gm = { ...s.gm, hintStufeDieseFrage: stufe };
      events.push({ type: "hint_given", art: "global", stufe });
      return { state: s, events };
    }

    case "gm.hintWhisper": {
      const p = state.players[action.playerId];
      if (!p) return fehler(state, "unbekannter-spieler");
      if ((state.gm.fluesterDieseRunde[action.playerId] ?? 0) >= 2) {
        return fehler(state, "max-fluester");
      }
      const s = { ...state };
      s.fluesterTipp = { ...s.fluesterTipp, [action.playerId]: action.text };
      s.gm = {
        ...s.gm,
        fluesterDieseRunde: {
          ...s.gm.fluesterDieseRunde,
          [action.playerId]: (s.gm.fluesterDieseRunde[action.playerId] ?? 0) + 1,
        },
      };
      return {
        state: s,
        events: [{ type: "hint_given", art: "whisper", playerId: action.playerId }],
      };
    }

    // ---------- 8) Publikums-Voting ----------
    case "gm.voteStart": {
      if (state.voting) return fehler(state, "voting-laeuft");
      if (action.optionen.length < 2) return fehler(state, "zu-wenige-optionen");
      return {
        state: {
          ...state,
          voting: {
            frage: action.frage,
            optionen: action.optionen,
            stimmen: {},
            endetAt: now + (action.dauerMs ?? VOTING_MS),
          },
        },
        events: [{ type: "gm_command", cmd: "voteStart", args: { frage: action.frage } }],
      };
    }

    // ---------- 9) Fehlerhaft-Markierung (annul | grantAll) ----------
    case "gm.markBroken": {
      if (state.phase !== "frage" && state.phase !== "aufloesung") {
        return fehler(state, "keine-frage");
      }
      const questionId = state.aktuelleFragen[0]?.id ?? "?";
      const grundwert = FRAGE_WERTE[state.aktuelleFragen[0]?.difficulty ?? "medium"];

      if (state.phase === "frage") {
        // Frage sofort beenden OHNE Buchung, dann ggf. Grundwert für alle.
        const gmAction: GmAction = { kind: "gm", type: "force.finish" };
        const minigameState = deps
          .getPlugin(state.minigameId ?? "")
          .reduce(state.minigameState, gmAction, pluginCtx(state, deps, ctx));
        const zu = schliesseFrageAb({ ...state, minigameState }, deps, ctx, false);
        const s = { ...zu.state };
        const events = [...zu.events];
        if (action.refund === "grantAll") {
          for (const id of s.order) bucheGeld(s, events, id, grundwert, "reklamation");
        }
        events.push({
          type: "question_flagged",
          questionId,
          grund: action.grund,
          refund: action.refund,
        });
        events.push({ type: "frage_annulliert", questionId });
        moment(s, events, now, "info", `⚠️ Frage annulliert (${action.grund}).`);
        return { state: s, events };
      }

      // Auflösung: letzte Buchung rückabwickeln (Streak-Effekte bleiben — dokumentiert).
      if (!state.letzteBuchung || state.letzteBuchung.questionId !== questionId) {
        return fehler(state, "keine-buchung");
      }
      const s = { ...state };
      const events: EngineEvent[] = [];
      for (const [pid, delta] of Object.entries(s.letzteBuchung?.deltas ?? {})) {
        bucheGeld(s, events, pid, -delta, "annulliert");
      }
      if (action.refund === "grantAll") {
        for (const id of s.order) bucheGeld(s, events, id, grundwert, "reklamation");
      }
      s.letzteBuchung = null;
      events.push({
        type: "question_flagged",
        questionId,
        grund: action.grund,
        refund: action.refund,
      });
      events.push({ type: "frage_annulliert", questionId });
      moment(s, events, now, "info", `⚠️ Frage annulliert (${action.grund}).`);
      return { state: s, events };
    }

    // ---------- 10) Skip-Game + Buggy-Flag ----------
    case "gm.gameSkip": {
      if (state.phase === "frage" && state.minigameId) {
        const gmAction: GmAction = { kind: "gm", type: "force.finish" };
        const minigameState = deps
          .getPlugin(state.minigameId)
          .reduce(state.minigameState, gmAction, pluginCtx(state, deps, ctx));
        const zu = schliesseFrageAb({ ...state, minigameState }, deps, ctx, action.keepPoints);
        const ende = rundenEnde(zu.state, deps, ctx);
        return { state: ende.state, events: [...zu.events, ...ende.events] };
      }
      if (
        state.phase === "erklaerkarte" ||
        state.phase === "kategorie-wahl" ||
        state.phase === "aufloesung"
      ) {
        return naechsterAbschnitt(state, deps, ctx);
      }
      return fehler(state, "nichts-zu-skippen");
    }

    case "gm.flagBuggy": {
      const a = aktuellerAbschnitt(state);
      if (!a) return fehler(state, "kein-abschnitt");
      return {
        state,
        events: [{ type: "game_flagged", minigameId: a.minigameId, grund: action.grund }],
      };
    }

    // ---------- 12) Bestrafungs-Karte (Anti-Mobbing: nie 2× in Folge, §4.3) ----------
    case "gm.punish": {
      if (istPodestFixiert(state)) return fehler(state, "podest-fixiert");
      const p = state.players[action.playerId];
      if (!p) return fehler(state, "unbekannter-spieler");
      if (state.gm.letzteBestrafung === action.playerId) return fehler(state, "anti-mobbing");
      const s = { ...state };
      const events: EngineEvent[] = [];
      if (action.strafe === "clown") {
        s.players = {
          ...s.players,
          [action.playerId]: { ...p, clownBisRunde: aktuelleRunde(s) },
        };
        moment(s, events, now, "strafe", `🤡 ${p.name} trägt bis Rundenende die Clownsnase!`);
      } else {
        const zahlung = Math.min(BANANENSTEUER, Math.max(0, p.balance - DISPO_LIMIT));
        bucheGeld(s, events, action.playerId, -zahlung, "bananensteuer");
        s.jackpotGlas += zahlung;
        moment(
          s,
          events,
          now,
          "strafe",
          `🍌 Bananensteuer: ${p.name} zahlt ${zahlung} MM ins Glas!`,
        );
      }
      s.gm = {
        ...s.gm,
        vorletzteBestrafung: s.gm.letzteBestrafung,
        letzteBestrafung: action.playerId,
      };
      events.push({ type: "punished", playerId: action.playerId, strafe: action.strafe });
      return { state: s, events };
    }

    // ---------- 13) Underdog-Boost mit Begründungs-Chip ----------
    case "gm.boost": {
      if (istPodestFixiert(state)) return fehler(state, "podest-fixiert");
      const p = state.players[action.playerId];
      if (!p) return fehler(state, "unbekannter-spieler");
      if (!action.grund) return fehler(state, "grund-pflicht");
      if ((state.gm.boostsDieseRunde[action.playerId] ?? 0) >= 1) {
        return fehler(state, "max-boosts");
      }
      const s = { ...state };
      const events: EngineEvent[] = [];
      if (action.art === "x2") {
        s.modifiers = [
          ...s.modifiers,
          { id: "boost-x2", scope: "naechste-frage", betroffen: [action.playerId] },
        ];
      } else if (action.art === "plus300") {
        bucheGeld(s, events, action.playerId, 300, `boost:${action.grund}`);
      } else {
        s.players = {
          ...s.players,
          [action.playerId]: {
            ...p,
            jokers: { ...p.jokers, "bananen-split": (p.jokers["bananen-split"] ?? 0) + 1 },
          },
        };
        events.push({
          type: "joker_granted",
          playerId: action.playerId,
          jokerId: "bananen-split",
          quelle: "boost",
        });
      }
      s.gm = {
        ...s.gm,
        boostsDieseRunde: {
          ...s.gm.boostsDieseRunde,
          [action.playerId]: (s.gm.boostsDieseRunde[action.playerId] ?? 0) + 1,
        },
      };
      events.push({
        type: "boost",
        playerId: action.playerId,
        art: action.art,
        grund: action.grund,
      });
      moment(s, events, now, "boost", `🚀 Boost für ${p.name}: ${action.grund}`);
      return { state: s, events };
    }

    // ---------- 15) Joker-Vergabe (Budget 6 Chips/Session) ----------
    case "gm.jokerGrant": {
      const def = jokerDef(action.jokerId);
      if (!def) return fehler(state, "unbekannter-joker");
      const ziele =
        action.ziel === "alle"
          ? [...state.order]
          : state.players[action.ziel]
            ? [action.ziel]
            : null;
      if (!ziele) return fehler(state, "unbekannter-spieler");
      if (state.gm.jokerChips < ziele.length) return fehler(state, "joker-budget-leer");
      const s = { ...state };
      const events: EngineEvent[] = [];
      for (const pid of ziele) {
        const p = s.players[pid];
        s.players = {
          ...s.players,
          [pid]: { ...p, jokers: { ...p.jokers, [def.id]: (p.jokers[def.id] ?? 0) + 1 } },
        };
        events.push({ type: "joker_granted", playerId: pid, jokerId: def.id, quelle: "gm" });
      }
      s.gm = { ...s.gm, jokerChips: s.gm.jokerChips - ziele.length };
      moment(
        s,
        events,
        now,
        "joker",
        `🎁 GM verteilt ${def.emoji} ${def.name} (${ziele.length}×)!`,
      );
      return { state: s, events };
    }

    // ---------- 16) Glücksrad (nur im Zwischenstand, optional gerigged) ----------
    case "gm.wheelSpin": {
      if (state.settings.rad !== "an") return fehler(state, "rad-aus");
      if (state.phase !== "zwischenstand") return fehler(state, "nur-im-zwischenstand");
      return starteRad(state, deps, ctx, action.rigTarget);
    }

    // ---------- 17) Blitz-Stimmung (3/Session) ----------
    case "gm.moodPoll": {
      if (state.mood) return fehler(state, "mood-laeuft");
      if (state.gm.blitzStimmungen <= 0) return fehler(state, "mood-budget-leer");
      return {
        state: {
          ...state,
          mood: { endetAt: now + MOOD_POLL_MS, werte: {} },
          gm: { ...state.gm, blitzStimmungen: state.gm.blitzStimmungen - 1 },
        },
        events: [{ type: "gm_command", cmd: "moodPoll", args: {} }],
      };
    }

    // ---------- 14) Feedback einsammeln ----------
    case "gm.feedbackCollect": {
      return {
        state: { ...state, feedbackAngefragt: true },
        events: [{ type: "gm_command", cmd: "feedbackCollect", args: {} }],
      };
    }

    // ---------- Zugabe: +1 Frage in dieser Runde (max. 2) ----------
    case "gm.encore": {
      if (state.phase !== "aufloesung") return fehler(state, "nur-in-aufloesung");
      const a = aktuellerAbschnitt(state);
      if (!a || !state.plan) return fehler(state, "kein-abschnitt");
      if (state.gm.encoresDieseRunde >= 2) return fehler(state, "max-encores");
      if (deps.getPlugin(a.minigameId).meta.roundBased === true) {
        return fehler(state, "format-unterstuetzt-nicht");
      }
      const abschnitte = state.plan.abschnitte.map((x, i) =>
        i === state.abschnittIndex ? { ...x, fragen: x.fragen + 1 } : x,
      );
      const s = {
        ...state,
        plan: { ...state.plan, abschnitte, fragenTotal: state.plan.fragenTotal + 1 },
        gm: { ...state.gm, encoresDieseRunde: state.gm.encoresDieseRunde + 1 },
      };
      const events: EngineEvent[] = [];
      moment(s, events, now, "info", "🎬 ZUGABE! Eine Frage extra in dieser Runde!");
      return { state: s, events };
    }

    // ---------- Soundboard ----------
    case "gm.sound": {
      return { state, events: [{ type: "sound_play", sfxId: action.sfxId }] };
    }

    // ---------- Musik-Rotation: „Nächster Track" fürs Show-Bett ----------
    case "gm.musikSkip": {
      // Nur ein Zähler: der Screen beobachtet musikSkips im View und schaltet
      // seine Bett-Rotation weiter (deterministisch — kein Sound-Zufall hier).
      return {
        state: { ...state, musikSkips: (state.musikSkips ?? 0) + 1 },
        events: [{ type: "gm_command", cmd: "musikSkip", args: {} }],
      };
    }

    // ---------- Team-Modus: GM-Zuweisung in der Lobby (team=null löscht) ----------
    case "gm.teamAssign": {
      if (state.phase !== "lobby") return fehler(state, "nur-in-lobby");
      if (state.settings.teams === "aus") return fehler(state, "teams-aus");
      if (!state.players[action.playerId]) return fehler(state, "unbekannter-spieler");
      const teamWuensche = { ...state.teamWuensche };
      const events: EngineEvent[] = [
        {
          type: "gm_command",
          cmd: "teamAssign",
          args: { playerId: action.playerId, team: action.team },
        },
      ];
      if (action.team === null) {
        delete teamWuensche[action.playerId];
      } else {
        const angeboten = angeboteneTeams(
          state.settings.teams,
          Math.max(state.order.length, TEAM_MIN_SPIELER),
        );
        if (!angeboten.includes(action.team as TeamId)) return fehler(state, "unbekanntes-team");
        teamWuensche[action.playerId] = action.team;
        events.push({ type: "team_wahl", playerId: action.playerId, team: action.team });
      }
      return { state: { ...state, teamWuensche }, events };
    }

    // ---------- Auto-GM an/aus ----------
    case "gm.autoGm": {
      return {
        state: { ...state, settings: { ...state.settings, autoGm: action.enabled } },
        events: [{ type: "settings_changed", patch: { autoGm: action.enabled } }],
      };
    }

    // ---------- GM-Wechsel (Raum meldet: neues aktives Cockpit) ----------
    case "gm.wechsel": {
      const s = { ...state };
      const events: EngineEvent[] = [];
      moment(
        s,
        events,
        now,
        "info",
        action.grund === "takeover"
          ? "🎙️ GM-Wechsel: Die Spielleitung wurde per PIN übernommen!"
          : "🎙️ GM-Wechsel: Ein neuer Spielleiter übernimmt das Cockpit!",
      );
      return { state: s, events };
    }

    // ---------- Match beenden ----------
    case "gm.ende": {
      if (state.phase === "lobby" || state.phase === "ende") return fehler(state, "nichts-laeuft");
      if (state.phase === "siegerehrung") return beendeMatch(state, ctx);
      const s = { ...state, paused: null };
      return starteSiegerehrung(s, ctx, []);
    }

    default:
      return fehler(state, "unbekannte-aktion");
  }
}

export { phaseWechsel };
