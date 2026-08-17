// Glücksrad-Runtime (GAME-DESIGN §5.3): Rad-Phase mit deterministischem Dreh
// (seeded Rng), Kompatibilitäts-Matrix, Interaktions-Subphasen (Börsen-Roulette /
// Umarmung / Kompliment) und Modifier-Registrierung. Rad läuft NUR im Zwischenstand.
import {
  RAD_DREH_KURZ_MS,
  RAD_DREH_MS,
  RAD_ERGEBNIS_MS,
  RAD_SEGMENT_MAP,
  baueRadAnzeige,
  kompatibleSegmente,
  zieheSegment,
  type RadKontext,
  type RadSegmentId,
} from "../../shared/wheel";
import type { Ctx } from "../minigames/_api/plugin";
import {
  bananaBailout,
  bucheGeld,
  fehler,
  moment,
  naechsterAbschnitt,
  phaseWechsel,
  tauschBoerse,
  verbundene,
  type EngineDeps,
} from "./flow";
import type { EngineEvent, EngineResult, EngineState } from "./types";

/** Kontext fürs Rad JETZT: Fair-Finale-Fenster, Pity, MC-Kompatibilität. */
export function radKontext(s: EngineState, deps: EngineDeps): RadKontext {
  const plan = s.plan;
  let fairFinale = false;
  let naechsteRundeMc = false;
  if (plan) {
    // Verbleibende normale Runden NACH dem aktuellen Abschnitt.
    const rest = plan.abschnitte.slice(s.abschnittIndex + 1);
    const restRunden = rest.filter((a) => a.typ === "runde").length;
    fairFinale = restRunden <= 2; // letzte 2 Runden + vor dem Finale (§5.3)
    const naechster = rest.find((a) => a.typ !== "jackpot") ?? rest[0];
    if (naechster) {
      naechsteRundeMc = deps.getPlugin(naechster.minigameId).meta.contentKind === "quiz";
    }
  }
  return {
    fairFinale,
    letztesSegment: s.radHistorie.letztesSegment,
    drehsOhneGold: s.radHistorie.drehsOhneGold,
    jemandUnter200: s.order.some((id) => s.players[id].balance < 200),
    naechsteRundeMc,
    spielerzahl: s.order.length,
  };
}

/** Rad anwerfen (Plan-Beat oder GM-Kommando, optional gerigged). */
export function starteRad(
  state: EngineState,
  deps: EngineDeps,
  ctx: Ctx,
  rigTarget?: string,
): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  const kontext = radKontext(s, deps);

  const pool = kompatibleSegmente(kontext);
  if (pool.length === 0) return naechsterAbschnitt(s, deps, ctx);
  const rigged =
    rigTarget !== undefined && pool.some((seg) => seg.id === (rigTarget as RadSegmentId));
  const ergebnis = rigged ? (rigTarget as RadSegmentId) : zieheSegment(ctx.rng, kontext);
  const anzeige = baueRadAnzeige(ctx.rng, kontext, ergebnis);
  const drehMs = s.settings.kurzeShow ? RAD_DREH_KURZ_MS : RAD_DREH_MS;

  s.rad = {
    segmente: anzeige.segmente,
    ergebnisIndex: anzeige.ergebnisIndex,
    ergebnis,
    subphase: "dreh",
    subEndetAt: now + drehMs,
    drehStartetAt: now,
    drehDauerMs: drehMs,
    wahlen: {},
    paar: null,
    betroffen: [],
    respins: 0,
    rigged,
    angewendet: false,
  };
  s.radHistorie = {
    letztesSegment: ergebnis,
    drehsOhneGold:
      RAD_SEGMENT_MAP[ergebnis].klasse === "gold" ? 0 : s.radHistorie.drehsOhneGold + 1,
  };
  phaseWechsel(s, events, "rad", s.rad.subEndetAt);
  events.push({
    type: "rad_gestartet",
    segmente: anzeige.segmente,
    ergebnis,
    rigged,
  });
  return { state: s, events };
}

/** Dreh vorbei: Interaktion starten oder Wirkung sofort anwenden. */
export function radDrehFertig(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  if (!s.rad) return fehler(state, "kein-rad");
  const seg = RAD_SEGMENT_MAP[s.rad.ergebnis];

  if (seg.interaktion) {
    let paar: { von: string; zu: string } | null = null;
    if (seg.interaktion.typ === "kompliment") {
      const kandidaten = verbundene(s);
      if (kandidaten.length >= 2) {
        const von = kandidaten[ctx.rng.int(kandidaten.length)];
        const rest = kandidaten.filter((id) => id !== von);
        paar = { von, zu: rest[ctx.rng.int(rest.length)] };
      }
    }
    s.rad = {
      ...s.rad,
      subphase: "interaktion",
      subEndetAt: now + seg.interaktion.dauerMs,
      paar,
    };
    s.phaseEndsAt = s.rad.subEndetAt;
    return { state: s, events };
  }
  return wendeSegmentAn(s, deps, ctx, events);
}

/** Interaktion vorbei (Timeout oder alle Eingaben da): auflösen + Wirkung. */
export function radInteraktionFertig(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  if (!s.rad) return fehler(state, "kein-rad");
  const seg = RAD_SEGMENT_MAP[s.rad.ergebnis];
  const betroffen: string[] = [];

  if (seg.interaktion?.typ === "umarmt") {
    for (const [pid, wahl] of Object.entries(s.rad.wahlen)) {
      if (wahl === "umarmt" && s.players[pid]) {
        bucheGeld(s, events, pid, 50, "umarmungs-bonus");
        betroffen.push(pid);
      }
    }
    moment(s, events, now, "rad", `🤗 Umarmungs-Bonus: ${betroffen.length}× +50 MM!`);
  } else if (seg.interaktion?.typ === "kompliment" && s.rad.paar) {
    const ja = Object.values(s.rad.wahlen).filter((w) => w === "ja").length;
    const nein = Object.values(s.rad.wahlen).filter((w) => w === "nein").length;
    if (ja >= nein && ja > 0) {
      bucheGeld(s, events, s.rad.paar.von, 50, "kompliment-konto");
      bucheGeld(s, events, s.rad.paar.zu, 50, "kompliment-konto");
      betroffen.push(s.rad.paar.von, s.rad.paar.zu);
      moment(s, events, now, "rad", "💛 Kompliment angenommen: beide +50 MM!");
    } else {
      moment(s, events, now, "rad", "🙊 Kompliment abgelehnt — kein Bonus.");
    }
  } else if (seg.interaktion?.typ === "long-short") {
    // Wetten werden bei der NÄCHSTEN Frage abgerechnet (scoring.ts).
    s.modifiers = [
      ...s.modifiers,
      {
        id: "boersen-roulette",
        scope: "naechste-frage",
        betroffen: [],
        daten: { wahlen: { ...s.rad.wahlen } },
      },
    ];
    const long = Object.values(s.rad.wahlen).filter((w) => w === "long").length;
    moment(
      s,
      events,
      now,
      "rad",
      `📈 Börsen-Roulette: ${long}× Long — Abrechnung nach der nächsten Frage!`,
    );
  }

  s.rad = { ...s.rad, betroffen: [...s.rad.betroffen, ...betroffen] };
  return wendeSegmentAn(s, deps, ctx, events);
}

/** Segment-Wirkung registrieren/anwenden und die Ergebnis-Karte zeigen. */
function wendeSegmentAn(
  s: EngineState,
  deps: EngineDeps,
  ctx: Ctx,
  events: EngineEvent[],
): EngineResult {
  const now = ctx.clock.now();
  if (!s.rad) return fehler(s, "kein-rad");
  const seg = RAD_SEGMENT_MAP[s.rad.ergebnis];
  let betroffen: string[] = [...s.rad.betroffen];

  if (!s.rad.angewendet) {
    switch (seg.id) {
      case "banana-bailout":
        betroffen = [...betroffen, ...bananaBailout(s, events, now)];
        break;
      case "tausch-boerse":
        betroffen = [...betroffen, ...tauschBoerse(s, events, now)];
        break;
      case "steuerpruefung": {
        const leader = [...s.order].sort((a, b) => s.players[b].balance - s.players[a].balance)[0];
        if (leader !== undefined) {
          s.modifiers = [
            ...s.modifiers,
            {
              id: seg.id,
              scope: "naechste-frage",
              betroffen: [leader],
              daten: { leaderId: leader },
            },
          ];
          betroffen = [...betroffen, leader];
          moment(s, events, now, "rad", `🧾 Steuerprüfung für ${s.players[leader].name}!`);
        }
        break;
      }
      case "insider-tipp": {
        // Insider zufällig aus der unteren Tabellen-Hälfte (Underdog-Flavor).
        const sortiert = [...s.order].sort((a, b) => s.players[a].balance - s.players[b].balance);
        const haelfte = sortiert.slice(0, Math.max(1, Math.ceil(sortiert.length / 2)));
        const insider = haelfte[ctx.rng.int(haelfte.length)];
        s.modifiers = [
          ...s.modifiers,
          {
            id: seg.id,
            scope: "naechste-frage",
            betroffen: [insider],
            daten: { playerId: insider },
          },
        ];
        betroffen = [...betroffen, insider];
        moment(s, events, now, "rad", "🕵️ Jemand hat einen Insider-Tipp …");
        break;
      }
      case "umarmungs-bonus":
      case "kompliment-konto":
      case "boersen-roulette":
        break; // in radInteraktionFertig erledigt
      default:
        // Standard: Modifier mit Scope (naechste-frage/runde) für alle.
        s.modifiers = [
          ...s.modifiers,
          { id: seg.id, scope: seg.scope === "runde" ? "runde" : "naechste-frage", betroffen: [] },
        ];
        moment(s, events, now, "rad", `🎡 ${seg.name}: ${seg.wirkung}`);
    }
  }

  s.rad = {
    ...s.rad,
    subphase: "ergebnis",
    subEndetAt: now + RAD_ERGEBNIS_MS,
    betroffen,
    angewendet: true,
  };
  s.phaseEndsAt = s.rad.subEndetAt;
  events.push({ type: "rad_ergebnis", segment: seg.id, betroffen });
  void deps;
  return { state: s, events };
}

/** Ergebnis-Karte vorbei: Rad einpacken, nächster Abschnitt. */
export function radFertig(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const s = { ...state, rad: null };
  return naechsterAbschnitt(s, deps, ctx);
}

/** Tick-Fortschritt der Rad-Subphasen. */
export function radTick(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const rad = state.rad;
  if (!rad) return { state, events: [] };
  const now = ctx.clock.now();

  if (rad.subphase === "interaktion") {
    // Alle Verbundenen haben gewählt? Dann früher auflösen.
    const noetig = verbundene(state);
    const alleGewaehlt = noetig.length > 0 && noetig.every((id) => rad.wahlen[id] !== undefined);
    if (alleGewaehlt || now >= rad.subEndetAt) return radInteraktionFertig(state, deps, ctx);
    return { state, events: [] };
  }
  if (now < rad.subEndetAt) return { state, events: [] };
  if (rad.subphase === "dreh") return radDrehFertig(state, deps, ctx);
  return radFertig(state, deps, ctx);
}
