// Buchungs-Pipeline (GAME-DESIGN §3, verbindliche Zahlen und Reihenfolge):
// Plugin liefert scores() (Grundwert + Speed-Bonus) und optional outcomes();
// die Engine bucht: Hint-Abzug → Streak-Multiplikator → Verdopplungen (J3/Boost/
// Rad) → Pfandflaschen-Modus → Rückenwind mit Überhol-Kappe → 10er-Rundung →
// Dispo-Klammer. Danach: Pott, Applaus-Almosen, Dividende, Steuerprüfung,
// Affe-würfelt, Börsen-Roulette, Inflation, Jackpot-Glas.
// Sondermodi: Jackpot-Frage (2.000 + Glas) und Finale (W_final, §3.5).
import {
  APPLAUS_ALMOSEN,
  DISPO_LIMIT,
  finaleDelta,
  istPfandflaschenModus,
  JACKPOT_FRAGE_WERT,
  kappeRueckenwindExtra,
  klemmeAufDispo,
  PFAND_GEWINN_FAKTOR,
  rueckenwindFaktor,
  rundeAuf10,
  streakFaktor,
} from "../../shared/economy";
import type { Rng } from "../../shared/rng";
import type { RueckenwindBasis } from "../../shared/teams";
import type { PlayerOutcome } from "../minigames/_api/plugin";
import type { AktiverModifier, EngineEvent, PlayerState } from "./types";

export interface BuchungsOptionen {
  questionId: string;
  /** Plugin-scores(): Grundwert + Speed-Bonus (bzw. Format-Logik). */
  scores: Record<string, number>;
  /** Plugin-outcomes() — null: Engine nimmt delta > 0 als „richtig". */
  outcomes: Record<string, PlayerOutcome> | null;
  order: string[];
  /** Streak-Kette zählt in diesem Format (§3.1: nur Frage-Formate). */
  streakEligible: boolean;
  /** Globale Hint-Stufe dieser Frage (GM-Tipp-Kanone: −25 %/Stufe). */
  hintStufe: number;
  modifiers: AktiverModifier[];
  pott: number;
  jackpotGlas: number;
  /** Negative Plugin-Scores fließen ins Jackpot-Glas (meta.strafenInsGlas). */
  strafenInsGlas: boolean;
  /** Grundwert der Frage (Börsen-Roulette-Prämien). */
  frageWert: number;
  rng: Rng;
  modus: "normal" | "jackpot" | "finale";
  wFinal?: number;
  /** Team-Modus (ADDITIV): Rückenwind + Überhol-Kappe rechnen auf TEAM-Töpfen —
   * pro Spieler vor-aufgelöste Basis (shared/teams.teamRueckenwindBasis).
   * Fehlt das Feld, gilt die klassische Spieler-Basis (Kontostände). */
  rueckenwindBasis?: Record<string, RueckenwindBasis>;
}

export interface BuchungsErgebnis {
  players: Record<string, PlayerState>;
  events: EngineEvent[];
  momente: { art: string; text: string }[];
  pott: number;
  jackpotGlas: number;
}

function hatModifier(mods: AktiverModifier[], id: string, playerId?: string): boolean {
  return mods.some(
    (m) =>
      m.id === id &&
      (m.betroffen.length === 0 || (playerId !== undefined && m.betroffen.includes(playerId))),
  );
}

function findeModifier(mods: AktiverModifier[], id: string): AktiverModifier | undefined {
  return mods.find((m) => m.id === id);
}

/** Richtig/Falsch je Spieler bestimmen (outcomes bevorzugt, sonst delta>0). */
function korrektheit(
  outcomes: Record<string, PlayerOutcome> | null,
  scores: Record<string, number>,
  playerId: string,
): boolean | null {
  if (outcomes && outcomes[playerId] !== undefined) return outcomes[playerId].correct;
  const delta = scores[playerId] ?? 0;
  return delta > 0 ? true : false;
}

/** Buchung einer abgeschlossenen Frage — DIE Geld-Wahrheit der Engine. */
export function bucheFrage(
  players: Record<string, PlayerState>,
  opts: BuchungsOptionen,
): BuchungsErgebnis {
  if (opts.modus === "finale") return bucheFinale(players, opts);
  if (opts.modus === "jackpot") return bucheJackpot(players, opts);

  const events: EngineEvent[] = [];
  const momente: { art: string; text: string }[] = [];
  const neu: Record<string, PlayerState> = {};
  let pott = opts.pott;
  let glas = opts.jackpotGlas;

  // Snapshot VOR der Buchung: Rückenwind-Faktor + Vordermann-Kappe (§3.4).
  // Team-Modus: opts.rueckenwindBasis ersetzt die Spieler-Stände durch Team-Töpfe.
  const vorher: Record<string, number> = {};
  for (const id of opts.order) vorher[id] = players[id].balance;
  const standings = [...opts.order].sort((a, b) => vorher[b] - vorher[a]);
  const fuehrender = standings.length > 0 ? vorher[standings[0]] : 0;
  const vordermannVon = (id: string): number => {
    const idx = standings.indexOf(id);
    return idx <= 0 ? vorher[id] : vorher[standings[idx - 1]];
  };
  const rwStandVon = (id: string): number =>
    opts.rueckenwindBasis?.[id]?.eigenerStand ?? vorher[id];
  const rwFuehrenderVon = (id: string): number =>
    opts.rueckenwindBasis?.[id]?.fuehrenderStand ?? fuehrender;
  const rwVordermannVon = (id: string): number =>
    opts.rueckenwindBasis?.[id]?.vordermannStand ?? vordermannVon(id);

  const roulette = findeModifier(opts.modifiers, "boersen-roulette");
  const rouletteWahlen = (roulette?.daten?.wahlen ?? {}) as Record<string, string>;

  for (const id of opts.order) {
    const p = players[id];
    const delta0 = opts.scores[id] ?? 0;
    const correct = korrektheit(opts.outcomes, opts.scores, id);
    const pfand = istPfandflaschenModus(vorher[id]);

    // ---------- Streak-Kette (§3.1): reißt bei falsch/Timeout, eingefroren bei AFK ----------
    let streak = p.streak;
    if (opts.streakEligible) {
      if (correct === true) streak = p.streak + 1;
      else if (correct === null && !p.connected)
        streak = p.streak; // eingefroren
      else streak = 0;
    }

    let delta = 0;
    if (delta0 > 0) {
      let d = delta0;
      if (opts.hintStufe > 0) d *= Math.max(0, 1 - 0.25 * opts.hintStufe);
      if (opts.streakEligible && correct === true) d *= streakFaktor(streak);
      if (hatModifier(opts.modifiers, "goldene-banane", id)) d *= 2;
      if (hatModifier(opts.modifiers, "boost-x2", id)) d *= 2;
      if (hatModifier(opts.modifiers, "doppelter-zaster", id)) d *= 2;
      if (pfand) d *= PFAND_GEWINN_FAKTOR; // Gewinne nur zu 75 %
      const basis = rundeAuf10(d);
      // Rückenwind ×1,25/×1,5 — Zusatzgewinn mit Überhol-Kappe (§3.4).
      const rw = rueckenwindFaktor(rwStandVon(id), rwFuehrenderVon(id));
      let extra = 0;
      if (rw > 1) {
        extra = kappeRueckenwindExtra(
          rundeAuf10(basis * (rw - 1)),
          rwStandVon(id) + basis,
          rwVordermannVon(id),
        );
        if (!p.rueckenwindAngekuendigt) {
          momente.push({ art: "underdog", text: `💨 Rückenwind für ${p.name} (×${rw})!` });
        }
      }
      delta = basis + extra;
    } else if (delta0 < 0) {
      let d = delta0;
      if (hatModifier(opts.modifiers, "goldene-banane", id)) d *= 2; // Strafen ×2!
      if (pfand) d = 0; // Pfandflaschen-Modus: keine Strafen mehr
      delta = rundeAuf10(d);
      if (opts.strafenInsGlas && delta < 0) glas += Math.abs(delta);
    }

    const balance = klemmeAufDispo(vorher[id] + delta);
    const rwFaktor = rueckenwindFaktor(rwStandVon(id), rwFuehrenderVon(id));
    neu[id] = {
      ...p,
      balance,
      streak,
      maxStreak: Math.max(p.maxStreak, streak),
      richtigGesamt: p.richtigGesamt + (correct === true ? 1 : 0),
      rueckenwindAngekuendigt: p.rueckenwindAngekuendigt || rwFaktor > 1,
    };
    events.push({
      type: "answer_judged",
      playerId: id,
      questionId: opts.questionId,
      correct: correct === true,
      delta,
    });
    if (delta !== 0) {
      events.push({ type: "money_changed", playerId: id, delta, balance, grund: "frage" });
    }
  }

  // ---------- Fragen-Pott: kassiert der schnellste Richtige ----------
  if (pott > 0) {
    const gewinner = schnellsterRichtiger(opts, neu);
    if (gewinner) {
      buche(neu, events, gewinner, pott, "pott");
      momente.push({
        art: "info",
        text: `💰 ${neu[gewinner].name} kassiert den Pott (${pott} MM)!`,
      });
      pott = 0;
    }
  }

  // ---------- Applaus-Almosen (§3.4): als Einziger falsch → +25 MM ----------
  if (opts.outcomes) {
    const falsche = opts.order.filter((id) => opts.outcomes?.[id]?.correct === false);
    const richtige = opts.order.filter((id) => opts.outcomes?.[id]?.correct === true);
    if (falsche.length === 1 && richtige.length === opts.order.length - 1) {
      buche(neu, events, falsche[0], APPLAUS_ALMOSEN, "applaus-almosen");
      momente.push({
        art: "underdog",
        text: `👏 Applaus fürs Mitmachen: ${neu[falsche[0]].name} +${APPLAUS_ALMOSEN} MM`,
      });
    }
  }

  // ---------- Dividende (Rad, Runden-Scope): +5 % Zins pro richtiger Antwort ----------
  if (hatModifier(opts.modifiers, "dividende")) {
    for (const id of opts.order) {
      if (korrektheit(opts.outcomes, opts.scores, id) === true && neu[id].balance > 0) {
        const zins = rundeAuf10(0.05 * neu[id].balance);
        if (zins > 0) buche(neu, events, id, zins, "dividende");
      }
    }
  }

  // ---------- Steuerprüfung (Rad): Führender falsch → 10 % in den Pott ----------
  const steuer = findeModifier(opts.modifiers, "steuerpruefung");
  if (steuer) {
    const leaderId = String(steuer.daten?.leaderId ?? "");
    if (neu[leaderId] && korrektheit(opts.outcomes, opts.scores, leaderId) !== true) {
      const zahlung = rundeAuf10(0.1 * Math.max(0, vorher[leaderId] ?? 0));
      if (zahlung > 0) {
        buche(neu, events, leaderId, -zahlung, "steuerpruefung");
        pott += zahlung;
        momente.push({
          art: "strafe",
          text: `🧾 Steuerprüfung! ${neu[leaderId].name} zahlt ${zahlung} MM in den Pott.`,
        });
      }
    }
  }

  // ---------- Der Affe würfelt (Rad): Bot rät mit, Geschlagene zahlen 50 ----------
  if (hatModifier(opts.modifiers, "affe-wuerfelt")) {
    const botRichtig = opts.rng.next() < 0.25; // MC-4: Bot rät eine von vier
    if (botRichtig) {
      const geschlagene = opts.order.filter(
        (id) => korrektheit(opts.outcomes, opts.scores, id) !== true,
      );
      for (const id of geschlagene) {
        const zahlung = Math.min(50, Math.max(0, neu[id].balance - DISPO_LIMIT));
        if (zahlung > 0) {
          buche(neu, events, id, -zahlung, "schmach-gebuehr");
          pott += zahlung;
        }
      }
      momente.push({
        art: "rad",
        text:
          geschlagene.length > 0
            ? `🎲 Der Bot-Affe lag richtig — ${geschlagene.length} Schmach-Gebühr(en) in den Pott!`
            : "🎲 Der Bot-Affe lag richtig — aber alle auch!",
      });
    } else {
      momente.push({ art: "rad", text: "🎲 Der Bot-Affe lag selbst daneben. Glück gehabt." });
    }
  }

  // ---------- Börsen-Roulette (Rad): Long/Short-Wetten abrechnen ----------
  if (roulette) {
    for (const id of opts.order) {
      const wahl = rouletteWahlen[id];
      if (wahl !== "long" && wahl !== "short") continue;
      const richtig = korrektheit(opts.outcomes, opts.scores, id) === true;
      let bonus = 0;
      if (richtig && wahl === "long") bonus = rundeAuf10(1.5 * opts.frageWert);
      else if (richtig && wahl === "short") bonus = rundeAuf10(0.5 * opts.frageWert);
      else if (!richtig && wahl === "long") bonus = -100;
      if (bonus !== 0) buche(neu, events, id, bonus, "boersen-roulette");
    }
  }

  // ---------- Inflation (Rad, Runden-Scope): −3 % pro Frage-Ende (mind. 50) ----------
  if (hatModifier(opts.modifiers, "inflation")) {
    for (const id of opts.order) {
      if (neu[id].balance <= 0) continue;
      const abzug = Math.min(neu[id].balance, Math.max(50, rundeAuf10(0.03 * neu[id].balance)));
      buche(neu, events, id, -abzug, "inflation");
    }
  }

  return { players: neu, events, momente, pott, jackpotGlas: glas };
}

/** Jackpot-Frage (§1.1 Phase 4): alle Richtigen +2.000; der Schnellste + Glas.
 * Rückgaberecht × Jackpot (Design-Entscheidung, §5.1 „Gewinn 50 %" konsequent):
 * Zweitversuch zahlt den HALBEN Jackpot — Festwert 1.000 statt 2.000, und knackt
 * der Zweitversuch-Spieler das Glas, bekommt er nur die HÄLFTE des Inhalts
 * (der Rest bleibt drin). Risiko/Reward bleibt erhalten. */
function bucheJackpot(
  players: Record<string, PlayerState>,
  opts: BuchungsOptionen,
): BuchungsErgebnis {
  const events: EngineEvent[] = [];
  const momente: { art: string; text: string }[] = [];
  const neu: Record<string, PlayerState> = {};
  let glas = opts.jackpotGlas;
  const zweitversuch = (id: string): boolean => opts.outcomes?.[id]?.zweitversuch === true;

  for (const id of opts.order) {
    const p = players[id];
    const correct = korrektheit(opts.outcomes, opts.scores, id);
    const delta =
      correct === true
        ? zweitversuch(id)
          ? rundeAuf10(JACKPOT_FRAGE_WERT / 2)
          : JACKPOT_FRAGE_WERT
        : 0;
    const streak =
      correct === true ? p.streak + 1 : correct === null && !p.connected ? p.streak : 0;
    neu[id] = {
      ...p,
      balance: p.balance + delta,
      streak,
      maxStreak: Math.max(p.maxStreak, streak),
      richtigGesamt: p.richtigGesamt + (correct === true ? 1 : 0),
    };
    events.push({
      type: "answer_judged",
      playerId: id,
      questionId: opts.questionId,
      correct: correct === true,
      delta,
    });
    if (delta !== 0) {
      events.push({
        type: "money_changed",
        playerId: id,
        delta,
        balance: neu[id].balance,
        grund: "jackpot",
      });
    }
  }

  const schnellster = schnellsterRichtiger(opts, neu);
  if (schnellster && glas > 0) {
    // Zweitversuch: nur der halbe Glas-Inhalt — der Rest bleibt im Glas.
    const anteil = zweitversuch(schnellster) ? rundeAuf10(glas / 2) : glas;
    buche(neu, events, schnellster, anteil, "jackpot-glas");
    momente.push({
      art: "info",
      text: zweitversuch(schnellster)
        ? `🏺 ${neu[schnellster].name} knackt das Glas im ZWEITVERSUCH: +${anteil} MM (die Hälfte bleibt drin)!`
        : `🏺 ${neu[schnellster].name} knackt das Jackpot-Glas: +${anteil} MM!`,
    });
    glas -= anteil;
  }

  return { players: neu, events, momente, pott: opts.pott, jackpotGlas: glas };
}

/** Finale (§3.5): richtig +W, falsch −W/2, keine Antwort 0 — Konto nie unter 0. */
function bucheFinale(
  players: Record<string, PlayerState>,
  opts: BuchungsOptionen,
): BuchungsErgebnis {
  const events: EngineEvent[] = [];
  const neu: Record<string, PlayerState> = {};
  const w = opts.wFinal ?? 500;
  for (const id of opts.order) {
    const p = players[id];
    const correct = korrektheit(opts.outcomes, opts.scores, id);
    const delta = finaleDelta(correct, w);
    const balance = Math.max(0, p.balance + delta);
    neu[id] = {
      ...p,
      balance,
      richtigGesamt: p.richtigGesamt + (correct === true ? 1 : 0),
    };
    events.push({
      type: "answer_judged",
      playerId: id,
      questionId: opts.questionId,
      correct: correct === true,
      delta: balance - p.balance,
    });
    if (balance !== p.balance) {
      events.push({
        type: "money_changed",
        playerId: id,
        delta: balance - p.balance,
        balance,
        grund: "finale",
      });
    }
  }
  return { players: neu, events, momente: [], pott: opts.pott, jackpotGlas: opts.jackpotGlas };
}

/** Schnellster Richtiger (Pott/Glas): min nachMs aus outcomes, sonst Reihenfolge. */
function schnellsterRichtiger(
  opts: BuchungsOptionen,
  players: Record<string, PlayerState>,
): string | null {
  let bester: string | null = null;
  let besteZeit = Infinity;
  for (const id of opts.order) {
    if (!players[id]) continue;
    const correct = korrektheit(opts.outcomes, opts.scores, id);
    if (correct !== true) continue;
    const zeit = opts.outcomes?.[id]?.nachMs ?? Infinity;
    if (bester === null || zeit < besteZeit) {
      bester = id;
      besteZeit = zeit;
    }
  }
  return bester;
}

/** Hilfsbuchung mit Dispo-Klammer + money_changed-Event. */
function buche(
  players: Record<string, PlayerState>,
  events: EngineEvent[],
  playerId: string,
  delta: number,
  grund: string,
): void {
  const p = players[playerId];
  const balance = klemmeAufDispo(p.balance + delta);
  players[playerId] = { ...p, balance };
  events.push({ type: "money_changed", playerId, delta: balance - p.balance, balance, grund });
}
