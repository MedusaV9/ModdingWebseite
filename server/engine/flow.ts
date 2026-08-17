// Fluss-Steuerung des Match-Plans (GAME-DESIGN §1): Abschnitt für Abschnitt durch
// kategorie-wahl → erklaerkarte → (frage → aufloesung)×N → zwischenstand → rad? …
// bis zur Siegerehrung. Alle Funktionen sind pure: (state, deps, ctx) → Result.
import type { ContentSlice, FrageMods, Question } from "../../shared/content";
import type { Song } from "../../shared/songs";
import type { Rng } from "../../shared/rng";
import { MITLEIDS_BANANE, atFuerEndstand, rundeAuf10, wFinal } from "../../shared/economy";
import type { PlayerId } from "../../shared/ids";
import { FRAGE_WERTE, type Schwierigkeit } from "../../shared/money";
import { BUZZER_FOTOFINISH_MS, BUZZER_SAMMELFENSTER_MS, ordneBuzzes } from "../../shared/buzzer";
import {
  AB_QUICK_DURCHGAENGE,
  AB_QUICK_KETTE_MS,
  AFFENBANK_ID,
} from "../../shared/minigames/affenbank.meta";
import { letztesTeam, teamMitglieder, teamRueckenwindBasis, teamStaende } from "../../shared/teams";
import type { Ctx, MinigamePlugin, PlayerOutcome } from "../minigames/_api/plugin";
import { extrahiereHighlights, HIGHLIGHT_MAX_ANZAHL, type ChronikEintrag } from "./highlights";
import { hatKlauSchutz } from "./jokers";
import { FALLBACK_MINIGAME, kategorieOptionen, waehleFrage } from "./plan";
import { bucheFrage } from "./scoring";
import {
  AUFLOESUNG_MS,
  ERKLAERKARTE_KURZ_MS,
  ERKLAERKARTE_MS,
  HIGHLIGHT_KARTE_MS,
  KATEGORIE_WAHL_MS,
  SIEGEREHRUNG_MS,
  TIEBREAKER_COUNTDOWN_MS,
  TIEBREAKER_ERGEBNIS_MS,
  TIEBREAKER_MAX_RUNDEN,
  TIEBREAKER_SHAKE_MS,
  ZWISCHENSTAND_MS,
  type Abschnitt,
  type EngineEvent,
  type EngineResult,
  type EngineState,
  type TiebreakerZustand,
} from "./types";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AnyPlugin = MinigamePlugin<any, any>;

/** Engine-Abhängigkeiten: Plugin-Registry + Median-RTT-Quelle (Raum-Messung). */
export interface EngineDeps {
  getPlugin(id: string): AnyPlugin;
  /** Median-RTT eines Spielers in ms (Server-Messung) — für ctx.buzzer. */
  rttVon?: (playerId: string) => number;
}

export const fehler = (state: EngineState, error: string): EngineResult => ({
  state,
  events: [],
  error,
});

/** Ctx-Anreicherung für Plugin-Aufrufe: buzzer- und match-API (TECH-SPEC §2.1). */
export function pluginCtx(state: EngineState, deps: EngineDeps, ctx: Ctx): Ctx {
  return {
    clock: ctx.clock,
    rng: ctx.rng,
    buzzer: {
      medianRtt: (p) => deps.rttVon?.(p) ?? 0,
      sammelfensterMs: BUZZER_SAMMELFENSTER_MS,
      fotofinishMs: BUZZER_FOTOFINISH_MS,
      ordne: (kandidaten) => ordneBuzzes(kandidaten, ctx.rng),
    },
    match: {
      balance: (p) => state.players[p]?.balance ?? 0,
      reihenfolge: () => [...state.order] as PlayerId[],
      hatKlauSchutz: (p) => hatKlauSchutz(state, p),
      istVerbunden: (p) => state.players[p]?.connected ?? false,
      // Team-Modus (ADDITIV): Plugins wie Taschendieb klauen von TEAMS.
      teamVon: (p) => state.teams?.zuordnung[p] ?? null,
    },
  };
}

/**
 * Die LAUFENDE Frage des Formats — bei roundBased-Plugins (Boxkampf,
 * Tortenschlacht, Duell, Affenbank …) hält `aktuelleFragen` ALLE Fragen der
 * Runde und das Plugin schaltet intern weiter. Die GM-View verrät per
 * `questionId`, welche gerade dran ist — Spickzettel-Tipps, Tipp-Kanone und
 * Kategorie-Chip zeigten sonst stur Frage 1 der Runde (QA-Welle 3).
 * Plugins ohne questionId in der GM-View fallen auf Frage 1 zurück.
 */
export function aktuelleFrageDesFormats(
  state: EngineState,
  deps: EngineDeps,
): Question | undefined {
  const erste = state.aktuelleFragen[0];
  if (state.minigameId === null || state.aktuelleFragen.length <= 1) return erste;
  const view = deps.getPlugin(state.minigameId).viewFor(state.minigameState, "gm") as {
    questionId?: unknown;
  } | null;
  const qid = view?.questionId;
  if (typeof qid !== "string") return erste;
  return state.aktuelleFragen.find((q) => q.id === qid) ?? erste;
}

export function aktuellerAbschnitt(s: EngineState): Abschnitt | null {
  return s.plan?.abschnitte[s.abschnittIndex] ?? null;
}

/** Kontostände als Map (Team-Topf-Rechnung, Views, Rückenwind-Basis). */
export function kontostaende(s: EngineState): Record<string, number> {
  const b: Record<string, number> = {};
  for (const id of s.order) b[id] = s.players[id].balance;
  return b;
}

export function verbundene(s: EngineState): string[] {
  return s.order.filter((id) => s.players[id].connected);
}

/** Bildschirm-Moment anhängen (Ring der letzten 8) + Event fürs Log. */
export function moment(
  s: EngineState,
  events: EngineEvent[],
  ts: number,
  art: string,
  text: string,
): void {
  s.momentZaehler += 1;
  s.momente = [...s.momente, { id: `mo_${s.momentZaehler}`, ts, art, text }].slice(-8);
  events.push({ type: "moment", art, text });
}

export function phaseWechsel(
  s: EngineState,
  events: EngineEvent[],
  phase: EngineState["phase"],
  endsAt: number | null,
): void {
  s.phase = phase;
  s.phaseEndsAt = endsAt;
  events.push({ type: "phase_changed", phase });
}

/** Geld buchen (ohne Dispo-Klammer — Aufrufer entscheidet) + Event. */
export function bucheGeld(
  s: EngineState,
  events: EngineEvent[],
  playerId: string,
  delta: number,
  grund: string,
): void {
  const p = s.players[playerId];
  if (!p || delta === 0) return;
  const balance = p.balance + delta;
  s.players = { ...s.players, [playerId]: { ...p, balance } };
  events.push({ type: "money_changed", playerId, delta, balance, grund });
}

// ---------- Abschnitts-Steuerung ----------

/** Zum nächsten Abschnitt springen (oder Siegerehrung, wenn der Plan durch ist). */
export function naechsterAbschnitt(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  s.abschnittIndex += 1;
  s.frageInAbschnitt = -1;
  s.minigameId = null;
  s.minigameState = null;
  s.aktuelleFragen = [];
  s.kategorieWahl = null;
  s.erklaerkarte = null;

  if (!s.plan || s.abschnittIndex >= s.plan.abschnitte.length) {
    return beendePlan(s, ctx, events);
  }
  const a = s.plan.abschnitte[s.abschnittIndex];

  if (a.typ === "finale") {
    // W_final ansagen (§3.5) + Mitleids-Banane für den Letzten (§3.4, einmalig).
    // Team-Modus: der Letzte ist der schwächste Affe des LETZTEN Teams (Underdog
    // wirkt team-bezogen — die Banane hilft dem abgeschlagenen Team-Topf).
    const fuehrender = Math.max(0, ...s.order.map((id) => s.players[id].balance));
    s.finaleWert = wFinal(fuehrender, a.fragen, s.settings.finaleFaktor);
    const letzter = letzterSpieler(s);
    if (letzter !== null) {
      bucheGeld(s, events, letzter, MITLEIDS_BANANE, "mitleids-banane");
      const teamZusatz = s.teams !== null ? " (fürs letzte Team)" : "";
      moment(
        s,
        events,
        now,
        "underdog",
        `🍌 Mitleids-Banane: ${s.players[letzter].name} +${MITLEIDS_BANANE} MM vor dem Finale${teamZusatz}!`,
      );
    }
  }

  if (a.typ === "runde") {
    events.push({
      type: "runde_gestartet",
      nr: a.nr,
      minigameId: a.minigameId,
      slot: a.slot,
      kategorie: a.kategorie ?? undefined,
    });
  }
  if (a.typ === "jackpot") {
    moment(s, events, now, "info", `🏺 JACKPOT-FRAGE! 2.000 MM + das Glas (${s.jackpotGlas} MM)!`);
  }

  if (a.typ === "runde" && a.kategorieWahl !== "keine" && s.settings.kategorienWahl !== "aus") {
    return starteKategorieWahl(s, a, ctx, events);
  }
  return starteErklaerkarte(s, deps, ctx, events);
}

// ---------- Kategorien-Wahl ----------

function starteKategorieWahl(
  s: EngineState,
  a: Abschnitt,
  ctx: Ctx,
  events: EngineEvent[],
): EngineResult {
  const optionen = kategorieOptionen(s, a, ctx.rng);
  if (optionen.length <= 1) {
    // Nichts zu wählen — Kategorie direkt setzen und weiter.
    setzeKategorie(s, optionen[0] ?? null);
    return { state: s, events: weiterOhneWahl(s, ctx, events) };
  }
  const now = ctx.clock.now();
  const nurLetzter =
    a.kategorieWahl === "letzter" && s.settings.kategorienWahl === "voting"
      ? letzterSpieler(s)
      : null;
  s.kategorieWahl = { optionen, stimmen: {}, nurLetzter, endetAt: now + KATEGORIE_WAHL_MS };
  phaseWechsel(s, events, "kategorie-wahl", s.kategorieWahl.endetAt);
  return { state: s, events };
}

function weiterOhneWahl(s: EngineState, ctx: Ctx, events: EngineEvent[]): EngineEvent[] {
  const now = ctx.clock.now();
  const dauer = s.settings.kurzeShow ? ERKLAERKARTE_KURZ_MS : ERKLAERKARTE_MS;
  s.erklaerkarte = { bereit: [], streik: [], endetAt: now + dauer };
  phaseWechsel(s, events, "erklaerkarte", s.erklaerkarte.endetAt);
  return events;
}

function setzeKategorie(s: EngineState, kategorie: string | null): void {
  if (!s.plan) return;
  const abschnitte = s.plan.abschnitte.map((x, i) =>
    i === s.abschnittIndex ? { ...x, kategorie } : x,
  );
  s.plan = { ...s.plan, abschnitte };
}

/** Letzter im aktuellen Zwischenstand (Comeback-Regel: „Der Letzte wählt").
 * Team-Modus: der schwächste Affe des LETZTEN Teams (kleinster Team-Topf) —
 * Underdog-Mechaniken wirken team-bezogen (§3.4 + GAME-DESIGN §1.4). */
export function letzterSpieler(s: EngineState): string | null {
  if (s.teams !== null) {
    const teamId = letztesTeam(s.teams, kontostaende(s));
    if (teamId !== null) {
      const mitglieder = teamMitglieder(s.teams, teamId, s.order);
      const sortiert = [...mitglieder].sort((a, b) => s.players[a].balance - s.players[b].balance);
      if (sortiert.length > 0) return sortiert[0];
    }
  }
  const sortiert = [...s.order].sort((a, b) => s.players[a].balance - s.players[b].balance);
  return sortiert[0] ?? null;
}

/**
 * Kategorien-Wahl abschließen: Voting auszählen (Mehrheit, Gleichstand → Los),
 * Comeback-Regel (nur die Stimme des Letzten) oder GM-/Auto-Pick.
 */
export function schliesseKategorieWahl(
  state: EngineState,
  deps: EngineDeps,
  ctx: Ctx,
  gmPick?: string,
): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const wahl = s.kategorieWahl;
  if (!wahl) return fehler(state, "keine-kategorie-wahl");

  let kategorie: string;
  let art: "voting" | "letzter" | "gm" | "auto";
  if (gmPick !== undefined) {
    kategorie = gmPick;
    art = "gm";
  } else if (wahl.nurLetzter !== null) {
    const stimme = wahl.stimmen[wahl.nurLetzter];
    kategorie = stimme ?? wahl.optionen[ctx.rng.int(wahl.optionen.length)];
    art = stimme !== undefined ? "letzter" : "auto";
  } else if (s.settings.kategorienWahl === "gm") {
    kategorie = wahl.optionen[ctx.rng.int(wahl.optionen.length)];
    art = "auto"; // GM hat nicht gepickt → Auto-GM entscheidet
  } else {
    const zaehler = new Map<string, number>();
    for (const k of Object.values(wahl.stimmen)) zaehler.set(k, (zaehler.get(k) ?? 0) + 1);
    const max = Math.max(0, ...zaehler.values());
    const gewinner = wahl.optionen.filter((o) => (zaehler.get(o) ?? 0) === max);
    kategorie = gewinner[ctx.rng.int(gewinner.length)] ?? wahl.optionen[0];
    art = max > 0 ? "voting" : "auto";
  }

  setzeKategorie(s, kategorie);
  s.kategorieWahl = null;
  events.push({ type: "kategorie_gewaehlt", kategorie, art });
  return { state: s, events: weiterOhneWahl(s, ctx, events) };
}

// ---------- Erklärkarte ----------

export function starteErklaerkarte(
  s: EngineState,
  _deps: EngineDeps,
  ctx: Ctx,
  events: EngineEvent[],
): EngineResult {
  return { state: s, events: weiterOhneWahl(s, ctx, events) };
}

// ---------- Frage starten ----------

function schwierigkeitHoch(sch: Schwierigkeit): Schwierigkeit {
  if (sch === "easy") return "medium";
  if (sch === "medium") return "hard";
  return "ultrahard";
}

/** Laufzeit-Mods für den Plugin-init (Rad/Joker/Maßanzug) zusammenstellen. */
function baueMods(s: EngineState, plugin: AnyPlugin, ctx: Ctx): FrageMods | undefined {
  const mods: FrageMods = {};
  const aktiv = (id: string): boolean => s.modifiers.some((m) => m.id === id);
  if (aktiv("halbe-miete")) mods.timerFaktor = 0.5;
  // Finale: den angesagten W_final-Wert ans Plugin durchreichen (Inszenierung).
  if (aktuellerAbschnitt(s)?.typ === "finale" && s.finaleWert !== null) {
    mods.wFinal = s.finaleWert;
  }
  if (aktiv("affentheater")) mods.geraeteMischung = true;
  // Quick Cash (§6.2): kompakte Affenbank — 1 Durchgang mit 45-s-Kette statt
  // 2×90 s (Playtest 3: 184 s Affenbank = 44 % der Quick-Matchzeit).
  if (plugin.meta.id === AFFENBANK_ID && s.settings.modus === "quick") {
    mods.affenbank = { durchgaenge: AB_QUICK_DURCHGAENGE, ketteMs: AB_QUICK_KETTE_MS };
  }
  const insider = s.modifiers.find((m) => m.id === "insider-tipp");
  if (insider && typeof insider.daten?.playerId === "string") {
    mods.insiderPlayerId = insider.daten.playerId;
    mods.insiderVorsprungMs = 3000;
  }
  // Maßanzug-Zuweisungen + Portfolio-Umschichtung: eigene Frage pro Spieler.
  // NUR Plugins mit meta.perSpielerFragen konsumieren sie — sonst bleiben die
  // Zuweisungen stehen und greifen beim nächsten unterstützten Format.
  if (plugin.meta.perSpielerFragen === true) {
    const proSpieler: Record<string, Question> = {};
    for (const [pid, qid] of Object.entries(s.zuweisungen)) {
      const q = s.fragenPool.find((x) => x.id === qid);
      if (q && !s.usedQuestionIds.includes(q.id)) {
        proSpieler[pid] = q;
        s.usedQuestionIds = [...s.usedQuestionIds, q.id];
      }
    }
    if (Object.keys(proSpieler).length > 0) mods.fragenProSpieler = proSpieler;
    s.zuweisungen = {};
  }
  void ctx;
  return Object.keys(mods).length > 0 ? mods : undefined;
}

/**
 * ADDITIV (Musik): Song-Slice für contentKind-"songs"-Formate — Ziel-Song per
 * Rng aus den UNGESPIELTEN Songs (No-Repeat via usedSongIds, analog Fragen),
 * dahinter der komplette Rest als Distraktoren-Pool. Alle gespielt ⇒ Recycle
 * (Ziel aus dem vollen Pool). Leerer Pool ⇒ null (Plugins nutzen dann ihren
 * Fixture-Katalog — ein Match crasht NIE an Songs).
 */
function waehleSongSlice(s: EngineState, rng: Rng): Song[] | null {
  const pool = s.songsPool ?? [];
  if (pool.length === 0) return null;
  const benutzt = new Set(s.usedSongIds ?? []);
  const frisch = pool.filter((song) => !benutzt.has(song.id));
  const kandidaten = frisch.length > 0 ? frisch : pool;
  const ziel = kandidaten[rng.int(kandidaten.length)];
  s.usedSongIds = [...(s.usedSongIds ?? []), ziel.id];
  return [ziel, ...pool.filter((song) => song.id !== ziel.id)];
}

/** Nächste Frage (bzw. Runden-init bei roundBased-Plugins) starten. */
export function starteFrage(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  const a = aktuellerAbschnitt(s);
  if (!a) return fehler(state, "kein-abschnitt");
  const plugin = deps.getPlugin(a.minigameId);
  const roundBased = plugin.meta.roundBased === true;

  // Goldene Banane: nächste Frage 1 Stufe höher (§5.1).
  const goldAktiv = s.modifiers.some((m) => m.id === "goldene-banane");
  const wahlAbschnitt = goldAktiv
    ? { ...a, schwierigkeiten: a.schwierigkeiten.map(schwierigkeitHoch) }
    : a;

  const anzahl = roundBased ? a.fragen : 1;
  const fragen: Question[] = [];
  for (let i = 0; i < anzahl; i++) {
    const { frage, ultrahard } = waehleFrage(s, wahlAbschnitt, ctx.rng);
    fragen.push(frage);
    s.usedQuestionIds = [...s.usedQuestionIds, frage.id];
    if (ultrahard) s.ultrahardGestellt += 1;
  }
  s.naechsteFrageId = null;
  s.fragenZaehler += anzahl;
  s.frageInAbschnitt = roundBased ? 0 : s.frageInAbschnitt + 1;

  const mods = baueMods(s, plugin, ctx);
  const content: ContentSlice = mods ? { questions: fragen, mods } : { questions: fragen };
  // ADDITIV (Musik): contentKind-"songs"-Formate bekommen den Song-Slice —
  // songs[0] = Ziel-Song (Rng-Wahl, No-Repeat über usedSongIds), Rest =
  // Distraktoren-Pool (Vertrag: shared/songs.ts). Pool erschöpft ⇒ Recycle.
  if (plugin.meta.contentKind === "songs") {
    const slice = waehleSongSlice(s, ctx.rng);
    if (slice !== null) content.songs = slice;
  } else if (plugin.meta.wuenschtSongs === true && (s.songsPool ?? []).length > 0) {
    // meta.wuenschtSongs (z. B. Telegramm, contentKind "none"): der KOMPLETTE
    // Pool geht READ-ONLY mit — Song-Titel wandern in den Begriffs-Topf.
    // DESIGN-ENTSCHEIDUNG: KEIN usedSongIds-Verbrauch — diese Formate nutzen
    // nur Titel-TEXTE (keine Medien, kein Ziel-Song); die No-Repeat-Sperre
    // bleibt dem Blitz-DJ-/Rückwärts-Banane-Kontingent (waehleSongSlice).
    content.songs = [...(s.songsPool ?? [])];
  }
  s.minigameId = a.minigameId;
  s.aktuelleFragen = fragen;
  s.minigameState = plugin.init(s.order as PlayerId[], content, pluginCtx(s, deps, ctx));
  s.erklaerkarte = null;
  s.infoJokerFrage = [];
  s.jokerFrageZaehler = {};
  // Team-Modus: der Buzz-pro-Team-Slot lebt PRO FRAGE (Buzzer-Regel §1.4).
  if (s.teams !== null) s.teams = { ...s.teams, buzzVonTeam: {} };
  s.gm = {
    ...s.gm,
    verlaengerungenDieseFrage: 0,
    hintStufeDieseFrage: 0,
    autoTimerVerlaengert: false,
  };
  s.hinweis = {};
  s.gezeigteTipps = []; // Tipp-Kanone: Enthüllung lebt PRO Frage

  phaseWechsel(s, events, "frage", null); // Frage-Timer lebt im Plugin-State
  events.push({
    type: "question_shown",
    questionId: fragen[0].id,
    index: s.fragenZaehler - anzahl,
  });
  if (fragen.some((f) => f.difficulty === "ultrahard")) {
    moment(s, events, now, "info", "💥 ULTRAHARD-Frage — 1.000 MM Grundwert!");
  }
  if (goldAktiv) {
    moment(s, events, now, "joker", "✨ Goldene Banane aktiv: Gewinn ×2, Strafen ×2!");
  }
  return { state: s, events };
}

// ---------- Frage abschließen + buchen ----------

export function schliesseFrageAb(
  state: EngineState,
  deps: EngineDeps,
  ctx: Ctx,
  buchen = true,
): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  const a = aktuellerAbschnitt(s);
  if (!a || !s.minigameId) return fehler(state, "keine-frage-aktiv");
  const plugin = deps.getPlugin(s.minigameId);
  const questionId = s.aktuelleFragen[0]?.id ?? `${s.minigameId}~r${a.nr}`;

  if (buchen) {
    const scores = plugin.scores(s.minigameState) as Record<string, number>;
    const outcomes = plugin.outcomes
      ? (plugin.outcomes(s.minigameState) as Record<string, PlayerOutcome>)
      : null;
    const vorher: Record<string, number> = {};
    for (const id of s.order) vorher[id] = s.players[id].balance;

    const erg = bucheFrage(s.players, {
      questionId,
      scores,
      outcomes,
      order: s.order,
      streakEligible: plugin.meta.streak ?? plugin.meta.contentKind === "quiz",
      hintStufe: s.gm.hintStufeDieseFrage,
      modifiers: s.modifiers,
      pott: s.pott,
      jackpotGlas: s.jackpotGlas,
      strafenInsGlas: plugin.meta.strafenInsGlas === true,
      frageWert: FRAGE_WERTE[s.aktuelleFragen[0]?.difficulty ?? "medium"],
      rng: ctx.rng,
      modus: a.typ === "finale" ? "finale" : a.typ === "jackpot" ? "jackpot" : "normal",
      wFinal: s.finaleWert ?? undefined,
      // Team-Modus: Rückenwind + Überhol-Kappe rechnen auf TEAM-TÖPFEN (§3.4).
      rueckenwindBasis:
        s.teams !== null ? teamRueckenwindBasis(s.teams, kontostaende(s)) : undefined,
    });
    s.players = erg.players;
    s.pott = erg.pott;
    s.jackpotGlas = erg.jackpotGlas;
    events.push(...erg.events);
    for (const m of erg.momente) moment(s, events, now, m.art, m.text);
    const deltas: Record<string, number> = {};
    for (const id of s.order) deltas[id] = s.players[id].balance - vorher[id];
    s.letzteBuchung = { questionId, deltas };
    // v2 Replay-Highlights: Chronik dieses Fragen-Abschlusses festhalten.
    sammleChronik(s, erg.events, outcomes);
  } else {
    s.letzteBuchung = null;
  }

  // „Nächste Frage"-Modifier sind jetzt verbraucht (Rad/J3/Boost).
  s.modifiers = s.modifiers.filter((m) => m.scope !== "naechste-frage");
  s.fluesterTipp = {};
  s.hinweis = {};
  phaseWechsel(s, events, "aufloesung", now + AUFLOESUNG_MS);
  return { state: s, events };
}

/** Nach der Auflösung: nächste Frage im Abschnitt oder Runden-Ende. */
export function weiterNachAufloesung(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const a = aktuellerAbschnitt(state);
  if (!a || !state.minigameId) return naechsterAbschnitt(state, deps, ctx);
  const roundBased = deps.getPlugin(a.minigameId).meta.roundBased === true;
  if (!roundBased && state.frageInAbschnitt + 1 < a.fragen) {
    return starteFrage(state, deps, ctx);
  }
  return rundenEnde(state, deps, ctx);
}

/** Runden-Ende: Runden-Modifier ablaufen lassen, Zwischenstand zeigen. */
export function rundenEnde(state: EngineState, deps: EngineDeps, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const now = ctx.clock.now();
  const a = aktuellerAbschnitt(s);
  s.modifiers = s.modifiers.filter((m) => m.scope !== "runde");
  s.gm = { ...s.gm, encoresDieseRunde: 0, boostsDieseRunde: {}, fluesterDieseRunde: {} };
  s.minigameId = null;
  s.minigameState = null;
  if (a?.typ === "runde") events.push({ type: "runde_beendet", nr: a.nr });
  void deps;
  phaseWechsel(s, events, "zwischenstand", now + ZWISCHENSTAND_MS);
  return { state: s, events };
}

// ---------- v2: Chronik-Sammlung für die Replay-Highlights ----------

/** Duck-Typing-Blick auf Minigame-States (Taschendieb-Klau, Affenbank-Historie). */
interface KlauBlick {
  dieb?: string | null;
  opfer?: string | null;
  klau?: { betrag: number; abgeprallt: boolean } | null;
  answers?: Record<string, { atServerTime?: number; choice?: number }>;
  fotofinish?: string[];
  historie?: { typ: string; playerId?: string; betrag: number }[];
}

/**
 * Nach jeder Buchung: kompakte Chronik-Einträge für die Highlight-Heuristiken
 * anhängen — Antworten (aus answer_judged), Jackpot-Glas-Knacker, Klau/Buzzer
 * (Taschendieb-artige States) und BANK!-Verrat (Affenbank-Historie) plus ein
 * Zwischenstands-Snapshot (Comeback-Erkennung).
 */
function sammleChronik(
  s: EngineState,
  buchungsEvents: EngineEvent[],
  outcomes: Record<string, PlayerOutcome> | null,
): void {
  const frageNr = s.fragenZaehler;
  const eintraege: ChronikEintrag[] = [];
  for (const e of buchungsEvents) {
    if (e.type === "answer_judged") {
      eintraege.push({
        art: "antwort",
        playerId: e.playerId,
        frageNr,
        correct: e.correct,
        delta: e.delta,
        nachMs: outcomes?.[e.playerId]?.nachMs,
      });
    }
    if (e.type === "money_changed" && e.grund === "jackpot-glas" && e.delta > 0) {
      eintraege.push({ art: "jackpot", playerId: e.playerId, betrag: e.delta, frageNr });
    }
  }
  const mg = (s.minigameState ?? null) as KlauBlick | null;
  // Taschendieb-artig: vollzogener Klau + Fotofinish-Buzzer-Delta.
  if (mg && typeof mg.dieb === "string" && typeof mg.opfer === "string" && mg.klau) {
    if (!mg.klau.abgeprallt && mg.klau.betrag > 0) {
      eintraege.push({
        art: "klau",
        dieb: mg.dieb,
        opfer: mg.opfer,
        betrag: mg.klau.betrag,
        frageNr,
      });
    }
    const zweiter = mg.fotofinish?.[0];
    const diebAt = mg.answers?.[mg.dieb]?.atServerTime;
    const zweiterAt = zweiter !== undefined ? mg.answers?.[zweiter]?.atServerTime : undefined;
    if (zweiter !== undefined && typeof diebAt === "number" && typeof zweiterAt === "number") {
      eintraege.push({
        art: "buzzer",
        playerId: mg.dieb,
        zweiterId: zweiter,
        deltaMs: Math.max(0, Math.round(zweiterAt - diebAt)),
        frageNr,
      });
    }
  }
  // Affenbank-artig: jeder BANK!-Drücker ist ein Verrats-Kandidat.
  if (mg && Array.isArray(mg.historie)) {
    for (const h of mg.historie) {
      if (h.typ === "gebankt" && typeof h.playerId === "string" && h.betrag > 0) {
        eintraege.push({ art: "bank", playerId: h.playerId, betrag: h.betrag, frageNr });
      }
    }
  }
  const staende: Record<string, number> = {};
  for (const id of s.order) staende[id] = s.players[id].balance;
  eintraege.push({ art: "stand", frageNr, staende });
  s.chronik = [...(s.chronik ?? []), ...eintraege];
}

// ---------- v2: Plan-Ende → Sudden-Death? → Highlights → Siegerehrung ----------

/**
 * Der Match-Plan ist durch: bei Gleichstand an der SPITZE zündet der
 * Kokosnuss-Shake (Sudden Death, einmal pro Match), sonst geht es direkt in
 * die Replay-Highlights (und von dort zur Siegerehrung).
 * Team-Modus: Gleichstand der TOP-TEAM-TÖPFE — alle Mitglieder der gleichauf
 * liegenden Teams shaken, das Team des Siegers holt Platz 1.
 */
export function beendePlan(s: EngineState, ctx: Ctx, events: EngineEvent[]): EngineResult {
  if (s.teams !== null) {
    const staende = teamStaende(s.teams, kontostaende(s));
    const spitze = staende[0]?.topf ?? 0;
    const gleichauf = staende.filter((t) => t.topf === spitze);
    if (gleichauf.length >= 2 && s.tiebreaker === null) {
      const teams = s.teams;
      const teilnehmer = s.order.filter((id) =>
        gleichauf.some((t) => t.teamId === teams.zuordnung[id]),
      );
      return starteTiebreaker(s, teilnehmer, ctx, events, spitze);
    }
    return starteHighlights(s, ctx, events);
  }
  const spitze = Math.max(...s.order.map((id) => s.players[id].balance));
  const gleichauf = s.order.filter((id) => s.players[id].balance === spitze);
  if (gleichauf.length >= 2 && s.tiebreaker === null) {
    return starteTiebreaker(s, gleichauf, ctx, events);
  }
  return starteHighlights(s, ctx, events);
}

/** Sudden Death: rotes Studiolicht, Herzschlag — der Kokosnuss-Shake beginnt. */
export function starteTiebreaker(
  s: EngineState,
  teilnehmer: string[],
  ctx: Ctx,
  events: EngineEvent[],
  umkaempft?: number,
): EngineResult {
  const now = ctx.clock.now();
  const betrag = umkaempft ?? s.players[teilnehmer[0]]?.balance ?? 0;
  s.tiebreaker = {
    teilnehmer,
    subphase: "countdown",
    endetAt: now + TIEBREAKER_COUNTDOWN_MS,
    runde: 1,
    taps: {},
    sieger: null,
    betrag,
  };
  s.minigameId = null;
  s.minigameState = null;
  phaseWechsel(s, events, "tiebreaker", s.tiebreaker.endetAt);
  events.push({ type: "tiebreaker_gestartet", teilnehmer, betrag });
  const text =
    s.teams !== null
      ? `💥 SUDDEN DEATH! Die Team-Töpfe liegen bei ${betrag} MM exakt gleichauf — der Kokosnuss-Shake entscheidet!`
      : `💥 SUDDEN DEATH! ${teilnehmer.map((id) => s.players[id].name).join(" und ")} liegen bei ${betrag} MM exakt gleichauf — der Kokosnuss-Shake entscheidet!`;
  moment(s, events, now, "info", text);
  return { state: s, events };
}

/** Tick der Tiebreaker-Phase: countdown → shake → ergebnis → Highlights. */
export function tiebreakerTick(state: EngineState, ctx: Ctx): EngineResult {
  const tb = state.tiebreaker;
  const now = ctx.clock.now();
  if (!tb) return starteHighlights({ ...state }, ctx, []);
  if (now < tb.endetAt) return { state, events: [] };
  const s = { ...state };
  const events: EngineEvent[] = [];
  if (tb.subphase === "countdown") {
    s.tiebreaker = { ...tb, subphase: "shake", endetAt: now + TIEBREAKER_SHAKE_MS, taps: {} };
    s.phaseEndsAt = s.tiebreaker.endetAt;
    moment(s, events, now, "info", "🥥 SHAKE! Hämmert auf die Kokosnuss — wer öfter tippt, siegt!");
    return { state: s, events };
  }
  if (tb.subphase === "shake") return werteShakeAus(s, tb, ctx, events);
  // subphase "ergebnis" vorbei → weiter zu den Highlights.
  return starteHighlights(s, ctx, events);
}

/** Shake auswerten: eindeutiger Tap-Sieger ODER Re-Shake (max. 3) ODER Los. */
function werteShakeAus(
  s: EngineState,
  tb: TiebreakerZustand,
  ctx: Ctx,
  events: EngineEvent[],
): EngineResult {
  const now = ctx.clock.now();
  const max = Math.max(0, ...tb.teilnehmer.map((id) => tb.taps[id] ?? 0));
  const beste = tb.teilnehmer.filter((id) => (tb.taps[id] ?? 0) === max);
  if (beste.length > 1 && tb.runde < TIEBREAKER_MAX_RUNDEN) {
    s.tiebreaker = {
      ...tb,
      teilnehmer: beste,
      subphase: "countdown",
      endetAt: now + TIEBREAKER_COUNTDOWN_MS,
      runde: tb.runde + 1,
      taps: {},
    };
    s.phaseEndsAt = s.tiebreaker.endetAt;
    moment(
      s,
      events,
      now,
      "info",
      "🥥 SCHON WIEDER GLEICHSTAND?! Noch ein Shake — Runde " + s.tiebreaker.runde + "!",
    );
    return { state: s, events };
  }
  const sieger = beste.length === 1 ? beste[0] : beste[ctx.rng.int(beste.length)];
  s.tiebreaker = { ...tb, subphase: "ergebnis", endetAt: now + TIEBREAKER_ERGEBNIS_MS, sieger };
  s.phaseEndsAt = s.tiebreaker.endetAt;
  events.push({ type: "tiebreaker_ergebnis", sieger, taps: { ...tb.taps }, runde: tb.runde });
  moment(
    s,
    events,
    now,
    "info",
    `🥥 KNACK! ${s.players[sieger].name} zertrümmert die Kokosnuss (${tb.taps[sieger] ?? 0} Taps) und holt sich Platz 1!`,
  );
  return { state: s, events };
}

/** Replay-Highlights starten — ohne Highlights direkt zur Siegerehrung. */
export function starteHighlights(s: EngineState, ctx: Ctx, events: EngineEvent[]): EngineResult {
  const now = ctx.clock.now();
  const namen: Record<string, string> = {};
  for (const id of s.order) namen[id] = s.players[id].name;
  const karten = extrahiereHighlights(
    s.chronik ?? [],
    namen,
    HIGHLIGHT_MAX_ANZAHL,
    s.teams !== null,
  );
  if (karten.length === 0) return starteSiegerehrung(s, ctx, events);
  s.highlights = { karten, index: 0, endetAt: now + HIGHLIGHT_KARTE_MS };
  s.minigameId = null;
  s.minigameState = null;
  phaseWechsel(s, events, "highlights", s.highlights.endetAt);
  events.push({ type: "highlights_gestartet", anzahl: karten.length });
  events.push({ type: "highlight_gezeigt", highlightId: karten[0].id, art: karten[0].art });
  return { state: s, events };
}

/** Nächste Highlight-Karte (Tick/GM-Skip) — nach der letzten: Siegerehrung. */
export function highlightsWeiter(state: EngineState, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  const hl = s.highlights;
  if (!hl || hl.index + 1 >= hl.karten.length) return starteSiegerehrung(s, ctx, events);
  const now = ctx.clock.now();
  const karte = hl.karten[hl.index + 1];
  s.highlights = { ...hl, index: hl.index + 1, endetAt: now + HIGHLIGHT_KARTE_MS };
  s.phaseEndsAt = s.highlights.endetAt;
  events.push({ type: "highlight_gezeigt", highlightId: karte.id, art: karte.art });
  return { state: s, events };
}

// ---------- Siegerehrung + Ende ----------

export function starteSiegerehrung(s: EngineState, ctx: Ctx, events: EngineEvent[]): EngineResult {
  const now = ctx.clock.now();
  // Sudden-Death-Sieger gewinnt den Gleichstand (Kokosnuss-Shake, v2).
  const shakeSieger = s.tiebreaker?.sieger ?? null;
  const sortiert = [...s.order].sort((a, b) => {
    const diff = s.players[b].balance - s.players[a].balance;
    if (diff !== 0) return diff;
    if (shakeSieger === a) return -1;
    if (shakeSieger === b) return 1;
    return 0;
  });
  // Team-Modus: Sieger = Team mit dem höchsten TOPF (Shake-Sieger-Team bricht
  // Gleichstände) — der Team-Sieger-Bonus (AT ×1,5) geht an ALLE Mitglieder.
  const teamStand =
    s.teams !== null
      ? teamStaende(
          s.teams,
          kontostaende(s),
          shakeSieger !== null ? (s.teams.zuordnung[shakeSieger] ?? null) : null,
        )
      : null;
  const siegerTeamId = teamStand?.[0]?.teamId ?? null;
  const istSieger = (id: string, platz: number): boolean =>
    s.teams !== null ? s.teams.zuordnung[id] === siegerTeamId : platz === 1;
  const platzierungen = sortiert.map((id, i) => ({
    playerId: id,
    platz: i + 1,
    balance: s.players[id].balance,
    at: atFuerEndstand(s.players[id].balance, istSieger(id, i + 1)),
  }));

  const awards: { titel: string; playerId: string; wert: string }[] = [];
  const beste = (wert: (p: EngineState["players"][string]) => number): string | null => {
    let bester: string | null = null;
    for (const id of s.order) {
      if (bester === null || wert(s.players[id]) > wert(s.players[bester])) bester = id;
    }
    return bester !== null && wert(s.players[bester]) > 0 ? bester : null;
  };
  const streaker = beste((p) => p.maxStreak);
  if (streaker !== null && s.players[streaker].maxStreak >= 3) {
    awards.push({
      titel: "🔥 Serien-Champion",
      playerId: streaker,
      wert: `${s.players[streaker].maxStreak}er-Streak`,
    });
  }
  const hirn = beste((p) => p.richtigGesamt);
  if (hirn !== null) {
    awards.push({
      titel: "🧠 Quiz-Hirn",
      playerId: hirn,
      wert: `${s.players[hirn].richtigGesamt}× richtig`,
    });
  }
  const comeback = sortiert.find((id) => s.players[id].rueckenwindAngekuendigt);
  if (comeback !== undefined) {
    awards.push({
      titel: "💨 Comeback des Abends",
      playerId: comeback,
      wert: "Rückenwind genutzt",
    });
  }
  // v2 Sudden-Death: der Kokosnuss-Knacker bekommt seinen eigenen Award.
  if (shakeSieger !== null && s.tiebreaker !== null) {
    awards.push({
      titel: "🥥 Sudden-Death-Held",
      playerId: shakeSieger,
      wert: `${s.tiebreaker.taps[shakeSieger] ?? 0} Shake-Taps`,
    });
  }
  // Team-Modus: bester Einzel-Affe (persönliche Leistung bleibt sichtbar, §1.4).
  if (s.teams !== null && sortiert.length > 0) {
    const bester = sortiert[0];
    awards.unshift({
      titel: "🐒 Bester Einzel-Affe",
      playerId: bester,
      wert: `${s.players[bester].balance} MM solo`,
    });
  }

  s.siegerehrung = { platzierungen, awards };
  if (teamStand !== null) {
    const teamPlatzierungen = teamStand.map((t) => ({
      teamId: t.teamId,
      platz: t.platz,
      topf: t.topf,
    }));
    s.siegerehrung = { ...s.siegerehrung, teamPlatzierungen };
    events.push({ type: "team_ergebnis", platzierungen: teamPlatzierungen });
    const sieger = s.teams?.teams.find((t) => t.id === siegerTeamId);
    if (sieger !== undefined) {
      moment(
        s,
        events,
        now,
        "info",
        `🏆 ${sieger.emoji} ${sieger.name} gewinnt mit ${teamStand[0].topf} MM im Topf!`,
      );
    }
  }
  s.rad = null;
  s.kategorieWahl = null;
  s.erklaerkarte = null;
  s.minigameId = null;
  s.minigameState = null;
  s.highlights = null;
  phaseWechsel(s, events, "siegerehrung", now + SIEGEREHRUNG_MS);
  events.push({
    type: "match_ended",
    standings: platzierungen.map((p) => ({ playerId: p.playerId, balance: p.balance })),
  });
  return { state: s, events };
}

export function beendeMatch(state: EngineState, ctx: Ctx): EngineResult {
  const s = { ...state };
  const events: EngineEvent[] = [];
  void ctx;
  s.feedbackAngefragt = true; // Abspann: Handys zeigen das Feedback-Formular
  phaseWechsel(s, events, "ende", null);
  return { state: s, events };
}

// ---------- Sofort-Wirkungen (Rad-Segmente, auch vom GM nutzbar) ----------

/** Banana Bailout (§5.3/3): Letzter +1 Joker (50:50) + 15 % Abstand zum Vorletzten. */
export function bananaBailout(s: EngineState, events: EngineEvent[], ts: number): string[] {
  const sortiert = [...s.order].sort((a, b) => s.players[a].balance - s.players[b].balance);
  const letzter = sortiert[0];
  if (letzter === undefined) return [];
  const vorletzter = sortiert[1];
  const abstand =
    vorletzter !== undefined
      ? Math.max(0, s.players[vorletzter].balance - s.players[letzter].balance)
      : 0;
  const bonus = rundeAuf10(0.15 * abstand);
  const p = s.players[letzter];
  s.players = {
    ...s.players,
    [letzter]: {
      ...p,
      jokers: { ...p.jokers, "bananen-split": (p.jokers["bananen-split"] ?? 0) + 1 },
    },
  };
  events.push({
    type: "joker_granted",
    playerId: letzter,
    jokerId: "bananen-split",
    quelle: "rad",
  });
  if (bonus > 0) bucheGeld(s, events, letzter, bonus, "banana-bailout");
  moment(s, events, ts, "underdog", `🆘 Banana Bailout: ${p.name} +1 Joker & +${bonus} MM!`);
  return [letzter];
}

/** Affen-Tausch-Börse (§5.3/12): Sitznachbar-Paare tauschen Kontostände (J6 schützt). */
export function tauschBoerse(s: EngineState, events: EngineEvent[], ts: number): string[] {
  const betroffen: string[] = [];
  for (let i = 0; i + 1 < s.order.length; i += 2) {
    const a = s.order[i];
    const b = s.order[i + 1];
    if (hatKlauSchutz(s, a) || hatKlauSchutz(s, b)) {
      const geschuetzt = hatKlauSchutz(s, a) ? a : b;
      moment(
        s,
        events,
        ts,
        "joker",
        `🛡️ Bananentresor! ${s.players[geschuetzt].name} blockt den Tausch.`,
      );
      continue;
    }
    const balanceA = s.players[a].balance;
    const balanceB = s.players[b].balance;
    if (balanceA === balanceB) continue;
    bucheGeld(s, events, a, balanceB - balanceA, "tausch-boerse");
    bucheGeld(s, events, b, balanceA - balanceB, "tausch-boerse");
    betroffen.push(a, b);
  }
  moment(s, events, ts, "rad", "🔀 Affen-Tausch-Börse: Kontostände getauscht!");
  return betroffen;
}

export { FALLBACK_MINIGAME };
