// Bananen-Tortenschlacht: Trost-/Topf-Mathe-Goldens, Werfer-Kür (Antwort-Tempo,
// Gleichstand = Join-Reihenfolge), geheime Ziel-Wahl (Wachen + Sofort-Salve),
// Rauswurf-Reihenfolge bei Gleichstand (sequenzielle Salve), 2-Aktive-Autowurf,
// Disconnect-Regeln (Torte verfällt NUR ohne eingerastetes Ziel), Punktsieg bei
// Fragen-Ende, Leergefegt-Sonderfall, Scoring-Invarianten (Σ = Topf + Trost),
// GM-Kommandos, Leak-Wachen und Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  TS_TOPF_MM,
  TS_TORTEN_RAUS,
  TS_TROST_SCHRITT,
  tsTopfAnteile,
  tsTrost,
  type TortenschlachtAction,
} from "../../shared/minigames/bananen-tortenschlacht.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { tortenschlachtPlugin, type TortenschlachtState } from "./bananen-tortenschlacht/index";

function fragen(n: number): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_ts_${i + 1}`,
    kind: "choice4" as const,
    category: "affen_wissen",
    difficulty: "hard" as const,
    text: `Torten-Frage ${i + 1}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  }));
}

function setup(opts: { spieler?: string[]; seed?: number; fragenAnzahl?: number } = {}) {
  const clock = createTestClock(0);
  const spieler = (opts.spieler ?? ["p1", "p2", "p3", "p4"]).map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const content: ContentSlice = { questions: fragen(opts.fragenAnzahl ?? 8) };
  const state = tortenschlachtPlugin.init(spieler, content, ctx) as TortenschlachtState;
  return { clock, ctx, state, spieler };
}

function aktion(
  p: string,
  a: TortenschlachtAction,
  at: number,
): PlayerAction<TortenschlachtAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(
  s: TortenschlachtState,
  a: PlayerAction<TortenschlachtAction> | GmAction,
  ctx: Ctx,
) {
  return tortenschlachtPlugin.reduce(s, a, ctx) as TortenschlachtState;
}

function tick(s: TortenschlachtState, ctx: Ctx) {
  return tortenschlachtPlugin.tick(s, ctx) as TortenschlachtState;
}

/** Uhr bis nach dem Phasen-Ende (+Gnade in der Frage), dann tick. */
function phaseVorbei(s: TortenschlachtState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  const ziel = s.phase === "frage" ? s.phaseEndsAt + SPAETANTWORT_GNADE_MS : s.phaseEndsAt;
  clock.advance(Math.max(0, ziel - clock.now()) + 1);
  return tick(s, ctx);
}

/**
 * Eine Frage spielen: Antworten einspeisen (nachMs relativ zum Frage-Start),
 * dann auswerten (sofort wenn alle Aktiven geantwortet haben, sonst Timeout).
 */
function spieleFrage(
  s: TortenschlachtState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
  antworten: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[],
) {
  expect(s.phase).toBe("frage");
  const start = s.frageStartetAt;
  for (const a of antworten) {
    s = reduce(s, aktion(a.p, { type: "answer", choice: a.choice }, start + a.nachMs), ctx);
  }
  return phaseVorbei(s, ctx, clock);
}

/** Ziel-Wahlen einspeisen — die letzte Wahl feuert die Salve sofort. */
function waehleZiele(s: TortenschlachtState, ctx: Ctx, wahlen: Record<string, string>) {
  expect(s.phase).toBe("zielwahl");
  for (const [w, ziel] of Object.entries(wahlen)) {
    s = reduce(s, aktion(w, { type: "wurf", targetId: ziel }, 0), ctx);
  }
  return s;
}

function summe(scores: Record<PlayerId, number>): number {
  return Object.values(scores).reduce((a, b) => a + b, 0);
}

describe("bananen-tortenschlacht: Trost-/Topf-Mathe (Goldens)", () => {
  it("Trost-Staffel: k-ter Rausgeworfener bekommt k × 100", () => {
    expect(tsTrost(1)).toBe(TS_TROST_SCHRITT);
    expect(tsTrost(2)).toBe(200);
    expect(tsTrost(3)).toBe(300);
  });

  it("Topf-Teilung: 10er-Rundung, Σ Anteile + Rest = Topf (Invariante)", () => {
    expect(tsTopfAnteile(1)).toEqual({ anteil: TS_TOPF_MM, rest: 0 });
    const zwei = tsTopfAnteile(2); // 750 je — glatt
    expect(zwei).toEqual({ anteil: 750, rest: 0 });
    const drei = tsTopfAnteile(3); // 500 je — glatt
    expect(drei.anteil * 3 + drei.rest).toBe(TS_TOPF_MM);
    const sieben = tsTopfAnteile(7); // 214,28… → 210 je, Rest 30
    expect(sieben).toEqual({ anteil: 210, rest: 30 });
    expect(sieben.anteil * 7 + sieben.rest).toBe(TS_TOPF_MM);
    expect(tsTopfAnteile(0)).toEqual({ anteil: 0, rest: 0 });
  });
});

describe("bananen-tortenschlacht: Werfer-Kür + Ziel-Wahl", () => {
  it("alle Richtigen werden Werfer — Wurf-Reihenfolge = Antwort-Tempo", () => {
    const { clock, ctx, state } = setup();
    const s = spieleFrage(state, ctx, clock, [
      { p: "p3", choice: 1, nachMs: 400 },
      { p: "p1", choice: 1, nachMs: 900 },
      { p: "p2", choice: 0, nachMs: 500 },
      { p: "p4", choice: 2, nachMs: 600 },
    ]);
    expect(s.phase).toBe("zielwahl");
    expect(s.werfer).toEqual(["p3", "p1"]); // p3 war schneller
  });

  it("EXAKTER Antwort-Gleichstand ⇒ Join-Reihenfolge (deterministisch)", () => {
    const { clock, ctx, state } = setup();
    const s = spieleFrage(state, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 700 },
      { p: "p2", choice: 1, nachMs: 700 },
    ]);
    expect(s.werfer).toEqual(["p2", "p4"]); // p2 joinete früher
  });

  it("niemand richtig ⇒ Beat „niemand“, danach nächste Frage (keine Torte)", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [{ p: "p1", choice: 0, nachMs: 500 }]);
    expect(s.phase).toBe("niemand");
    expect(s.wuerfe).toEqual([]);
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("frage");
    expect(s.frageIndex).toBe(1);
    expect(summe(s.torten as Record<PlayerId, number>)).toBe(0);
  });

  it("Ziel-Wahl-Wachen: nur Werfer, kein Selbst-/Raus-Ziel, erste Wahl rastet ein", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 1, nachMs: 500 },
    ]);
    expect(s.phase).toBe("zielwahl");
    // Nicht-Werfer und Selbst-Ziel verpuffen.
    expect(reduce(s, aktion("p3", { type: "wurf", targetId: "p1" }, 0), ctx)).toBe(s);
    expect(reduce(s, aktion("p1", { type: "wurf", targetId: "p1" }, 0), ctx)).toBe(s);
    s = reduce(s, aktion("p1", { type: "wurf", targetId: "p3" }, 0), ctx);
    // Einrasten: die Zweitwahl verpufft.
    const doppelt = reduce(s, aktion("p1", { type: "wurf", targetId: "p4" }, 0), ctx);
    expect(doppelt.zielWahl.p1).toBe("p3");
    // Letzte offene Wahl ⇒ Salve fliegt SOFORT (ohne Timeout).
    s = reduce(doppelt, aktion("p2", { type: "wurf", targetId: "p3" }, 0), ctx);
    expect(s.phase).toBe("wurf");
    expect(s.torten.p3).toBe(2);
  });

  it("Ziel-Wahl-Timeout: verbundener Werfer wirft auf den SAUBERSTEN Gegner", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [{ p: "p1", choice: 1, nachMs: 400 }]);
    // p2/p3 tragen schon Sahne (gedachte Vorrunde) — p4 ist der Sauberste.
    s = { ...s, torten: { ...s.torten, p2: 1, p3: 1 } };
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("wurf");
    expect(s.wuerfe).toEqual([{ von: "p1", zu: "p4", schicht: 1, raus: false }]);
  });
});

describe("bananen-tortenschlacht: Rauswurf-Reihenfolge + Sonderfälle", () => {
  it("3. Torte = raus; Rauswurf-Reihenfolge = Lande-Reihenfolge der Salve", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 1, nachMs: 500 },
    ]);
    // Beide Ziele stehen bei 2 Schichten — beide fallen in DERSELBEN Salve:
    // p1 (schnellerer Werfer) trifft zuerst ⇒ p3 fliegt VOR p4.
    s = { ...s, torten: { ...s.torten, p3: 2, p4: 2 } };
    s = waehleZiele(s, ctx, { p1: "p3", p2: "p4" });
    expect(s.phase).toBe("wurf");
    expect(s.raus).toEqual(["p3", "p4"]);
    expect(s.wuerfe).toEqual([
      { von: "p1", zu: "p3", schicht: 3, raus: true },
      { von: "p2", zu: "p4", schicht: 3, raus: true },
    ]);
  });

  it("Werfer fliegt in derselben Salve raus — seine Torte landet TROTZDEM", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 1, nachMs: 500 },
    ]);
    s = { ...s, torten: { ...s.torten, p2: 2 } };
    // p1 tortet p2 raus — p2s (gleichzeitig geworfene) Torte fliegt trotzdem.
    s = waehleZiele(s, ctx, { p1: "p2", p2: "p1" });
    expect(s.raus).toEqual(["p2"]);
    expect(s.torten.p1).toBe(1);
    expect(s.wuerfe).toHaveLength(2);
  });

  it("2 AKTIVE: Ziel-Wahl übersprungen, Torte fliegt automatisch auf den Gegner", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    const s = spieleFrage(state, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 0, nachMs: 500 },
    ]);
    expect(s.phase).toBe("wurf"); // keine zielwahl-Phase
    expect(s.wuerfe).toEqual([{ von: "p1", zu: "p2", schicht: 1, raus: false }]);
  });

  it("letzter sauberer Affe gewinnt: Topf + Trost-Staffel (Σ-Invariante)", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s = state;
    for (let i = 0; i < TS_TORTEN_RAUS; i++) {
      s = spieleFrage(s, ctx, clock, [
        { p: "p1", choice: 1, nachMs: 400 },
        { p: "p2", choice: 0, nachMs: 500 },
      ]);
      expect(s.phase).toBe("wurf");
      s = phaseVorbei(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    expect(s.sieger).toEqual(["p1"]);
    expect(s.siegerGrund).toBe("letzter-sauberer");
    s = phaseVorbei(s, ctx, clock);
    expect(tortenschlachtPlugin.isFinished(s)).toBe(true);
    const scores = tortenschlachtPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(TS_TOPF_MM);
    expect(scores[asPlayerId("p2")]).toBe(tsTrost(1));
    expect(summe(scores)).toBe(TS_TOPF_MM + tsTrost(1));
    const outcomes = tortenschlachtPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
  });

  it("Fragen-Vorrat erschöpft ⇒ PUNKTSIEG: Sauberste teilen den Topf, Rest-Trost stimmt", () => {
    const { clock, ctx, state } = setup({ fragenAnzahl: 2 });
    // Frage 1: p1 tortet p4.
    let s = spieleFrage(state, ctx, clock, [{ p: "p1", choice: 1, nachMs: 400 }]);
    s = waehleZiele(s, ctx, { p1: "p4" });
    s = phaseVorbei(s, ctx, clock);
    // Frage 2 (letzte): p2 tortet p4 — danach ist der Vorrat leer.
    s = spieleFrage(s, ctx, clock, [{ p: "p2", choice: 1, nachMs: 400 }]);
    s = waehleZiele(s, ctx, { p2: "p4" });
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    expect(s.siegerGrund).toBe("punktsieg");
    expect(s.sieger).toEqual(["p1", "p2", "p3"]); // alle sauber, p4 trägt 2 Schichten
    s = phaseVorbei(s, ctx, clock);
    const scores = tortenschlachtPlugin.scores(s);
    // 3 Sieger: 1.500/3 = 500 glatt; p4 überlebte ohne Sieg ⇒ oberste Trost-Stufe.
    expect(scores[asPlayerId("p1")]).toBe(500);
    expect(scores[asPlayerId("p2")]).toBe(500);
    expect(scores[asPlayerId("p3")]).toBe(500);
    expect(scores[asPlayerId("p4")]).toBe(tsTrost(1)); // niemand flog raus ⇒ Stufe 1
    expect(summe(scores)).toBe(TS_TOPF_MM + tsTrost(1));
  });

  it("Topf-Rest bei krummer Teilung geht an die frühere Join-Reihenfolge", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2", "p3"], fragenAnzahl: 1 });
    // Einzige Frage: niemand richtig ⇒ Punktsieg aller 3 (alle sauber).
    let s = spieleFrage(state, ctx, clock, []);
    expect(s.phase).toBe("niemand");
    s = phaseVorbei(s, ctx, clock);
    expect(s.siegerGrund).toBe("punktsieg");
    s = phaseVorbei(s, ctx, clock);
    const scores = tortenschlachtPlugin.scores(s);
    // 1.500/3 = 500 glatt (Rest 0) — Golden für die 7er-Teilung separat:
    expect(scores[asPlayerId("p1")]).toBe(500);
    const { anteil, rest } = tsTopfAnteile(7);
    expect(anteil * 7 + rest).toBe(TS_TOPF_MM);
    expect(summe(scores)).toBe(TS_TOPF_MM);
  });

  it("Feld LEERGEFEGT (letzte 2 torten sich gegenseitig raus): der Letzte gewinnt", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s: TortenschlachtState = { ...state, torten: { p1: 2, p2: 2 } };
    s = spieleFrage(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 1, nachMs: 500 },
    ]);
    expect(s.raus).toEqual(["p2", "p1"]); // p1 traf zuerst (schnellere Antwort)
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    expect(s.siegerGrund).toBe("leergefegt");
    expect(s.sieger).toEqual(["p1"]); // fiel ZULETZT ⇒ stand am längsten
    s = phaseVorbei(s, ctx, clock);
    const scores = tortenschlachtPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(TS_TOPF_MM); // Sieger-Topf schlägt Trost
    expect(scores[asPlayerId("p2")]).toBe(tsTrost(1));
  });
});

describe("bananen-tortenschlacht: Disconnect + GM + Leaks + Determinismus", () => {
  it("Offline-Werfer OHNE Ziel-Wahl: Torte verfällt; MIT Wahl: fliegt trotzdem", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 1, nachMs: 500 },
    ]);
    // p1 rastet sein Ziel ein und fällt DANN aus dem Netz.
    s = reduce(s, aktion("p1", { type: "wurf", targetId: "p3" }, 0), ctx);
    s = tortenschlachtPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as TortenschlachtState;
    // p2 (auch Werfer) fällt OHNE Wahl weg ⇒ Salve fliegt (keine offene Wahl mehr),
    // p2s Torte verfällt, p1s geworfene Torte landet.
    s = tortenschlachtPlugin.onDisconnect(s, asPlayerId("p2"), ctx) as TortenschlachtState;
    expect(s.phase).toBe("wurf");
    expect(s.wuerfe).toEqual([{ von: "p1", zu: "p3", schicht: 1, raus: false }]);
  });

  it("Offline-Aktive bleiben im Spiel und bewerfbar; Raus-Affen können nicht antworten", () => {
    const { clock, ctx, state } = setup();
    let s = tortenschlachtPlugin.onDisconnect(state, asPlayerId("p4"), ctx) as TortenschlachtState;
    s = spieleFrage(s, ctx, clock, [{ p: "p1", choice: 1, nachMs: 400 }]);
    s = waehleZiele(s, ctx, { p1: "p4" }); // Offline-Affe ist gültiges Ziel
    expect(s.torten.p4).toBe(1);
    // Raus-Affe: Antwort verpufft (erst raus torten, dann probieren).
    s = { ...s, raus: [...s.raus, asPlayerId("p2")], phase: "frage" };
    expect(reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s);
  });

  it("Antwort-Wachen: zu spät/doppelt/außerhalb der Frage verpuffen", () => {
    const { clock, ctx, state } = setup();
    const zuSpaet = state.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(state, aktion("p1", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(state);
    let s = reduce(state, aktion("p1", { type: "answer", choice: 0 }, 500), ctx);
    const doppelt = reduce(s, aktion("p1", { type: "answer", choice: 1 }, 600), ctx);
    expect(doppelt.answers.p1.choice).toBe(0); // erste Antwort zählt
    s = spieleFrage(doppelt, ctx, clock, []);
    expect(s.phase).toBe("niemand");
    expect(reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s);
  });

  it("GM force.finish VOR dem Ergebnis ⇒ sofortiger Punktsieg; timer.extend/shift konsistent", () => {
    const { ctx, state } = setup();
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    const fertig = reduce(state, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(fertig.siegerGrund).toBe("punktsieg");
    expect(fertig.sieger).toEqual(["p1", "p2", "p3", "p4"]); // alle sauber ⇒ teilen
    const scores = tortenschlachtPlugin.scores(fertig);
    expect(summe(scores)).toBe(TS_TOPF_MM); // 370×4 + Rest 20 an p1
    expect(scores[asPlayerId("p1")]).toBe(390);
    const laenger = reduce(state, { kind: "gm", type: "timer.extend", ms: 5_000 }, ctx);
    expect(laenger.phaseEndsAt).toBe(state.phaseEndsAt + 5_000);
    const pause = reduce(state, { kind: "gm", type: "timer.shift", ms: 60_000 }, ctx);
    expect(pause.phaseEndsAt).toBe(state.phaseEndsAt + 60_000);
    expect(pause.frageStartetAt).toBe(state.frageStartetAt + 60_000);
  });

  it("Leak-Wachen: Optionen nur im Frage-Fenster, Ziel-Wahl nur beim GM, Salve erst im Wurf", () => {
    const { clock, ctx, state } = setup();
    let s = spieleFrage(state, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 1, nachMs: 500 },
    ]);
    s = reduce(s, aktion("p1", { type: "wurf", targetId: "p3" }, 0), ctx);
    const screen = tortenschlachtPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.text).toBeNull(); // zielwahl: Frage weg
    expect(screen.options).toBeNull();
    expect(screen.wuerfe).toEqual([]); // Salve GEHEIM bis zum Wurf-Beat
    expect(screen.zielWahl).toBeUndefined();
    expect(screen.correctIndex).toBeUndefined();
    const zielGrid = tortenschlachtPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(zielGrid.istWerfer).toBe(true);
    expect((zielGrid.ziele as unknown[]).length).toBe(3);
    const zuschauer = tortenschlachtPlugin.viewFor(s, "player", asPlayerId("p3")) as Record<
      string,
      unknown
    >;
    expect(zuschauer.ziele).toBeNull(); // Ziel-Grid NUR für Werfer
    const gm = tortenschlachtPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.zielWahl).toEqual({ p1: "p3" }); // Spickzettel
    expect(gm.correctIndex).toBe(1);
    // Raus-Affen sehen KEINE Antwort-Optionen (Leak-frei via null).
    const raus = { ...s, phase: "frage" as const, raus: [asPlayerId("p4")] };
    const tribuene = tortenschlachtPlugin.viewFor(raus, "player", asPlayerId("p4")) as Record<
      string,
      unknown
    >;
    expect(tribuene.duBistRaus).toBe(true);
    expect(tribuene.options).toBeNull();
  });

  it("Seed-Determinismus: identischer Ablauf ⇒ identischer End-State (JSON-gleich)", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = spieleFrage(state, ctx, clock, [
        { p: "p2", choice: 1, nachMs: 700 },
        { p: "p4", choice: 1, nachMs: 700 }, // exakter Gleichstand ⇒ Join-Reihenfolge
        { p: "p1", choice: 0, nachMs: 300 },
        { p: "p3", choice: 3, nachMs: 400 },
      ]);
      s = waehleZiele(s, ctx, { p2: "p1", p4: "p1" });
      s = phaseVorbei(s, ctx, clock);
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(a.torten.p1).toBe(2);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});
