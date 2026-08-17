// In-Prozess-AI-Spieler (GAME-DESIGN §Modi/AI): server-seitige Bot-Spieler mit
// den Personas aus shared/meta (Skill-Profile, Kategorie-Stärken, Tempo, Mut).
// Kein externer Prozess: Bots hängen am Manager-Tick, lesen ihre ROLLEN-
// GEFILTERTE PlayerView (wie echte Handys) und handeln über room.applyAction —
// nur die RICHTIGKEIT zieht den Spickzettel aus dem Engine-State (Skill-Würfel).
import { BOT_PERSONAS, botSkillFuer, type BotPersona } from "../../shared/meta";
import type { Rng } from "../../shared/rng";
import type { AvatarFarbe } from "../../shared/ids";
import type { Room } from "../rooms/room";

interface GeplanteAktion {
  at: number;
  run: () => void;
}

interface BotZustand {
  playerId: string;
  persona: BotPersona;
  erledigt: Set<string>;
  plan: Map<string, GeplanteAktion>;
}

/** Lose getypte Player-View (nur die Felder, die Bots brauchen). */
interface BotSicht {
  phase: string;
  frageNr: number;
  paused?: unknown;
  abschnitt?: { kategorie: string | null } | null;
  minigame?: {
    id: string;
    view: {
      questionId?: string;
      finished?: boolean;
      options?: unknown[];
      buzzAktiv?: boolean;
      endsAt?: number;
      eingabeMin?: number;
      eingabeMax?: number;
      startReihenfolge?: number[];
      deineAbgabe?: unknown;
      deinTipp?: unknown;
    };
  } | null;
  kategorieWahl?: { optionen: string[]; endetAt: number; deineStimme?: number | null } | null;
  erklaerkarte?: { bereit: string[]; endetAt: number } | null;
  rad?: {
    interaktion: { typ: string; endetAt: number; deineWahl?: string | null } | null;
  } | null;
  voting?: { optionen: string[]; endetAt: number; deineStimme?: number | null } | null;
  feedbackAngefragt?: boolean;
}

export interface BotManager {
  addBot(room: Room, personaId?: string): { ok: boolean; error?: string; name?: string };
  removeBot(room: Room): { ok: boolean; error?: string; name?: string };
  tick(room: Room): void;
  botsVon(room: Room): { playerId: string; personaId: string }[];
  /** Nach Save-Load: Bots aus der Save-Datei wieder anbinden. */
  restauriere(room: Room, bots: { playerId: string; personaId: string }[]): void;
}

export function createBotManager(rng: Rng): BotManager {
  const proRaum = new WeakMap<Room, Map<string, BotZustand>>();

  const bots = (room: Room): Map<string, BotZustand> => {
    let map = proRaum.get(room);
    if (!map) {
      map = new Map();
      proRaum.set(room, map);
    }
    return map;
  };

  function neuerZustand(playerId: string, persona: BotPersona): BotZustand {
    return { playerId, persona, erledigt: new Set(), plan: new Map() };
  }

  /** Einmalige Aktion mit Verzögerung einplanen (Dedupe über den Schlüssel). */
  function plane(
    bot: BotZustand,
    key: string,
    now: number,
    delayMs: number,
    run: () => void,
  ): void {
    if (bot.erledigt.has(key) || bot.plan.has(key)) return;
    bot.erledigt.add(key);
    bot.plan.set(key, { at: now + Math.max(0, delayMs), run });
  }

  /** Persona-Tempo als Anteil der verfügbaren Zeit (min…max), sonst Basis-Delay. */
  function tempoDelay(persona: BotPersona, now: number, endsAt: number | undefined): number {
    const frac = persona.tempo.min + rng.next() * (persona.tempo.max - persona.tempo.min);
    if (endsAt !== undefined && endsAt > now + 1500) {
      return Math.min((endsAt - now - 700) * frac + 500, endsAt - now - 500);
    }
    return 700 + frac * 2600;
  }

  function frageAntwort(room: Room, bot: BotZustand, sicht: BotSicht, now: number): void {
    const mg = sicht.minigame;
    if (!mg || mg.view.finished === true) return;
    const qid = mg.view.questionId;
    if (qid === undefined) return;
    const kategorie = sicht.abschnitt?.kategorie ?? null;
    const skill = botSkillFuer(bot.persona, kategorie);

    // ---------- Buzzer-Formate (Taschendieb): erst buzzen, dann antworten ----------
    if (mg.view.buzzAktiv === true) {
      const key = `buzz:${sicht.frageNr}:${qid}`;
      // Mutige Personas hauen früh drauf; vorsichtige buzzen nur bei gutem Gefühl.
      if (rng.next() > 0.25 + 0.7 * bot.persona.mut) return;
      plane(bot, key, now, 400 + rng.next() * 1800 * (1 - bot.persona.mut), () => {
        room.applyBuzz(bot.playerId, {
          minigameId: mg.id,
          pressedAtServerEst: room.deps.clock.now(),
          idemKey: `bot-${bot.playerId}-${key}`,
        });
      });
      return;
    }

    // ---------- Schätz-Slider (Bananen-Tresor): Wert nahe am Richtwert ----------
    if (typeof mg.view.eingabeMin === "number" && typeof mg.view.eingabeMax === "number") {
      const min = mg.view.eingabeMin;
      const max = mg.view.eingabeMax;
      const key = `tresor:${sicht.frageNr}:${qid}`;
      plane(bot, key, now, tempoDelay(bot.persona, now, mg.view.endsAt), () => {
        const mgState = room.state.minigameState as { frage?: { richtwert?: number } } | null;
        const richtwert = mgState?.frage?.richtwert;
        const spanne = max - min;
        const wert =
          typeof richtwert === "number"
            ? richtwert + (rng.next() * 2 - 1) * spanne * 0.45 * (1 - skill)
            : min + rng.next() * spanne;
        room.applyAction({
          type: "playerAction",
          playerId: bot.playerId,
          minigameId: mg.id,
          action: { type: "einloggen", wert: Math.round(Math.min(max, Math.max(min, wert))) },
          atServerTime: room.deps.clock.now(),
        });
      });
      return;
    }

    // ---------- Sortieren (Affenleiter): Lösung mit Skill-Fehlern ----------
    if (Array.isArray(mg.view.startReihenfolge)) {
      const key = `leiter:${sicht.frageNr}:${qid}`;
      plane(bot, key, now, tempoDelay(bot.persona, now, mg.view.endsAt), () => {
        const mgState = room.state.minigameState as {
          frage?: { korrektReihenfolge?: number[] };
        } | null;
        const korrekt = mgState?.frage?.korrektReihenfolge ?? [0, 1, 2, 3];
        const reihenfolge = [...korrekt];
        if (rng.next() >= skill) {
          // Fehler-Muster: zwei benachbarte Sprossen vertauscht (realistisch).
          const i = rng.int(reihenfolge.length - 1);
          [reihenfolge[i], reihenfolge[i + 1]] = [reihenfolge[i + 1], reihenfolge[i]];
        }
        room.applyAction({
          type: "playerAction",
          playerId: bot.playerId,
          minigameId: mg.id,
          action: { type: "einloggen", reihenfolge },
          atServerTime: room.deps.clock.now(),
        });
      });
      return;
    }

    // ---------- choice4-Formate: richtige Antwort mit Skill-Wahrscheinlichkeit ----------
    if (Array.isArray(mg.view.options)) {
      const key = `antwort:${sicht.frageNr}:${qid}`;
      const anzahl = Math.max(1, mg.view.options.length);
      plane(bot, key, now, tempoDelay(bot.persona, now, mg.view.endsAt), () => {
        const frage =
          room.state.aktuelleFragen.find((f) => f.id === qid) ??
          room.state.fragenPool.find((f) => f.id === qid);
        let choice = rng.int(anzahl);
        if (frage !== undefined) {
          if (rng.next() < skill) {
            choice = frage.answer;
          } else {
            const falsche = [...Array(anzahl).keys()].filter((i) => i !== frage.answer);
            choice = falsche[rng.int(falsche.length)] ?? 0;
          }
        }
        room.applyAction({
          type: "playerAction",
          playerId: bot.playerId,
          minigameId: mg.id,
          action: { type: "answer", choice },
          atServerTime: room.deps.clock.now(),
        });
      });
    }
  }

  function handle(room: Room, bot: BotZustand, now: number): void {
    const sicht = room.viewFuer("player", bot.playerId) as BotSicht;
    if (sicht.paused) return;

    if (sicht.phase === "kategorie-wahl" && sicht.kategorieWahl) {
      const kw = sicht.kategorieWahl;
      plane(bot, `kat:${kw.endetAt}`, now, 900 + rng.next() * 2200, () => {
        // Lieblings-Kategorie der Persona bevorzugen, sonst Zufall.
        const stark = kw.optionen.find((o) =>
          Object.keys(bot.persona.staerken).some(
            (slug) => bot.persona.staerken[slug] > 0 && (o === slug || o.includes(slug)),
          ),
        );
        const kategorie = stark ?? kw.optionen[rng.int(kw.optionen.length)];
        if (kategorie !== undefined) {
          room.applyAction({ type: "kategorieVote", playerId: bot.playerId, kategorie });
        }
      });
    }

    if (sicht.phase === "erklaerkarte" && sicht.erklaerkarte) {
      const ek = sicht.erklaerkarte;
      if (!ek.bereit.includes(bot.playerId)) {
        plane(bot, `bereit:${ek.endetAt}`, now, 800 + rng.next() * 1700, () => {
          room.applyAction({ type: "playerReady", playerId: bot.playerId });
        });
      }
    }

    if (sicht.phase === "frage") frageAntwort(room, bot, sicht, now);

    if (sicht.phase === "rad" && sicht.rad?.interaktion) {
      const ia = sicht.rad.interaktion;
      if (ia.deineWahl === null || ia.deineWahl === undefined) {
        plane(bot, `rad:${ia.endetAt}`, now, 700 + rng.next() * 1800, () => {
          const wahl =
            ia.typ === "long-short"
              ? rng.next() < bot.persona.mut
                ? "long"
                : "short"
              : ia.typ === "umarmt"
                ? "umarmt"
                : rng.next() < 0.75
                  ? "ja"
                  : "nein";
          room.applyAction({ type: "radAktion", playerId: bot.playerId, wahl });
        });
      }
    }

    if (
      sicht.voting &&
      (sicht.voting.deineStimme === null || sicht.voting.deineStimme === undefined)
    ) {
      const v = sicht.voting;
      plane(bot, `vote:${v.endetAt}`, now, 700 + rng.next() * 1500, () => {
        room.applyAction({
          type: "voteCast",
          playerId: bot.playerId,
          option: rng.int(Math.max(1, v.optionen.length)),
        });
      });
    }

    if (sicht.feedbackAngefragt === true) {
      plane(bot, "feedback", now, 1200 + rng.next() * 2000, () => {
        room.applyAction({
          type: "feedbackText",
          playerId: bot.playerId,
          text: bot.persona.skill > 0.7 ? "Piep-boop: mehr ULTRAHARD! 🤖" : "Banane! 🤖🍌",
        });
      });
    }
  }

  return {
    addBot(room, personaId) {
      if (room.state.phase !== "lobby") return { ok: false, error: "nur-in-lobby" };
      const aktive = bots(room);
      const benutzt = new Set([...aktive.values()].map((b) => b.persona.id));
      const persona =
        (personaId !== undefined ? BOT_PERSONAS.find((p) => p.id === personaId) : undefined) ??
        BOT_PERSONAS.find((p) => !benutzt.has(p.id));
      if (!persona) return { ok: false, error: "alle-personas-vergeben" };
      if (persona !== undefined && benutzt.has(persona.id)) {
        return { ok: false, error: "persona-schon-dabei" };
      }
      const playerId = `p_bot_${persona.id}_${rng.int(10_000)}`;
      const result = room.applyAction({
        type: "join",
        playerId,
        name: persona.name,
        avatar: persona.avatar as AvatarFarbe,
      });
      if (!result.ok) return { ok: false, error: result.error };
      aktive.set(playerId, neuerZustand(playerId, persona));
      room.broadcastSnapshots();
      return { ok: true, name: persona.name };
    },

    removeBot(room) {
      if (room.state.phase !== "lobby") return { ok: false, error: "nur-in-lobby" };
      const aktive = bots(room);
      const letzter = [...aktive.values()].pop();
      if (!letzter) return { ok: false, error: "kein-bot" };
      aktive.delete(letzter.playerId);
      // Lobby-Chirurgie: Engine kennt kein „leave" — Bot-Slot sauber entfernen.
      const players = { ...room.state.players };
      delete players[letzter.playerId];
      room.ersetzeStateRoh({
        ...room.state,
        players,
        order: room.state.order.filter((id) => id !== letzter.playerId),
      });
      return { ok: true, name: letzter.persona.name };
    },

    tick(room) {
      const aktive = proRaum.get(room);
      if (!aktive || aktive.size === 0) return;
      const now = room.deps.clock.now();
      for (const bot of aktive.values()) {
        // Fällige Aktionen ausführen …
        for (const [key, aktion] of bot.plan) {
          if (aktion.at <= now) {
            bot.plan.delete(key);
            try {
              aktion.run();
            } catch {
              // Bot-Fehler dürfen NIE den Raum-Tick reißen.
            }
          }
        }
        // … und Neues aus der aktuellen View einplanen.
        try {
          handle(room, bot, now);
        } catch {
          /* View-Race — nächster Tick versucht es erneut */
        }
      }
    },

    botsVon(room) {
      const aktive = proRaum.get(room);
      if (!aktive) return [];
      return [...aktive.values()].map((b) => ({
        playerId: b.playerId,
        personaId: b.persona.id,
      }));
    },

    restauriere(room, liste) {
      const aktive = bots(room);
      for (const { playerId, personaId } of liste) {
        const persona = BOT_PERSONAS.find((p) => p.id === personaId);
        if (persona && room.state.players[playerId] !== undefined) {
          aktive.set(playerId, neuerZustand(playerId, persona));
        }
      }
    },
  };
}
