// Goldener Affe: Einsatz-/Drop-Mathe-Goldens (50 % vom ECHTEN Konto, Gratis-
// Einsatz, Chip-Auffüll-Regel, ×2-Rückzahlung), Schätz-Showdown (2 Nächste,
// Tie-Break frühere Abgabe, kein Tipp = raus), Siegerwetten der Ausgeschiedenen
// (×3, nur auf Finalisten), Buzzer-Best-of-3 (2 Punkte siegen, Gleichstand ⇒
// Schätz-Showdown), 20-%-Sieger-Transfer (EXAKT nullsummig gegen die Deltas),
// Wildcard-Nachrücker bei Finalist-Disconnect, kampflos/Abbruch/GM-Skip,
// Leak-Wachen (Lösung/Richtwert geheim), Pool- + Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  GA_CHIPS,
  gaDropDelta,
  gaEinsatz,
  gaFuelleChipsAuf,
  gaTransfer,
  type GoldenerAffeAction,
} from "../../shared/minigames/goldener-affe.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { goldenerAffePlugin, type GoldenerAffeState } from "./goldener-affe/index";

function fragen(n = 4): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_ga_${i + 1}`,
    kind: "choice4" as const,
    category: "affen_wissen",
    difficulty: "hard" as const,
    text: `Tempel-Frage ${i + 1}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  }));
}

// Konten: p1 führt (Einsatz 1.000), p4 ist fast pleite (Gratis-Einsatz 100).
const KONTEN = { p1: 2_000, p2: 1_000, p3: 600, p4: 100 };

function setup(
  opts: { balances?: Record<string, number> | null; spieler?: string[]; seed?: number } = {},
) {
  const clock = createTestClock(0);
  const spieler = (opts.spieler ?? ["p1", "p2", "p3", "p4"]).map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const balances: Record<string, number> | null =
    opts.balances === undefined ? KONTEN : opts.balances;
  if (balances !== null) {
    ctx.match = {
      balance: (p: PlayerId) => balances[p] ?? 0,
      reihenfolge: () => spieler,
      hatKlauSchutz: () => false,
      istVerbunden: () => true,
    };
  }
  const content: ContentSlice = { questions: fragen() };
  const state = goldenerAffePlugin.init(spieler, content, ctx) as GoldenerAffeState;
  return { clock, ctx, state, spieler };
}

function aktion(p: string, a: GoldenerAffeAction, at: number): PlayerAction<GoldenerAffeAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(s: GoldenerAffeState, a: PlayerAction<GoldenerAffeAction> | GmAction, ctx: Ctx) {
  return goldenerAffePlugin.reduce(s, a, ctx) as GoldenerAffeState;
}

function tick(s: GoldenerAffeState, ctx: Ctx) {
  return goldenerAffePlugin.tick(s, ctx) as GoldenerAffeState;
}

function phaseVorbei(s: GoldenerAffeState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndsAt - clock.now()) + 1);
  return tick(s, ctx);
}

/**
 * Standard-Einstieg bis zur Wett-Phase: alle gehen im Drop all-in auf die
 * richtige Tür (B), p1 tippt exakt, p2 knapp (früh), p3 knapp (spät), p4 gar
 * nicht ⇒ Finalisten [p1, p2], Ausgeschiedene [p3, p4].
 */
function bisWetten(state: GoldenerAffeState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  let s = state;
  for (const p of ["p1", "p2", "p3", "p4"]) {
    s = reduce(s, aktion(p, { type: "answer", choice: 1 }, 1_000), ctx);
  }
  s = tick(s, ctx); // alle verteilt ⇒ Falltür-Auswertung
  expect(s.phase).toBe("drop-ergebnis");
  s = phaseVorbei(s, ctx, clock);
  expect(s.phase).toBe("schaetzen");
  const r = s.schaetzfrage.richtwert;
  s = reduce(s, aktion("p1", { type: "einloggen", wert: r }, clock.now() + 1_000), ctx);
  s = reduce(s, aktion("p2", { type: "einloggen", wert: r + 2 }, clock.now() + 1_500), ctx);
  s = reduce(s, aktion("p3", { type: "einloggen", wert: r + 2 }, clock.now() + 2_000), ctx);
  s = phaseVorbei(s, ctx, clock); // p4 ohne Tipp ⇒ Timeout wertet aus
  expect(s.phase).toBe("schaetz-ergebnis");
  expect(s.finalisten).toEqual(["p1", "p2"]);
  expect(s.ausgeschieden).toEqual(["p3", "p4"]);
  s = phaseVorbei(s, ctx, clock);
  expect(s.phase).toBe("wetten");
  return s;
}

/** Eine Buzzer-Teilfrage spielen und den Punkte-Beat abwarten. */
function buzzerRunde(
  s: GoldenerAffeState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
  antworten: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[],
) {
  expect(s.phase).toBe("buzzer");
  const start = s.frageStartetAt ?? clock.now();
  for (const a of antworten) {
    s = reduce(s, aktion(a.p, { type: "answer", choice: a.choice }, start + a.nachMs), ctx);
  }
  if (antworten.length < s.finalisten.length) {
    clock.advance(s.phaseEndsAt + SPAETANTWORT_GNADE_MS - clock.now() + 1);
  }
  s = tick(s, ctx);
  expect(s.phase).toBe("buzzer-ergebnis");
  return phaseVorbei(s, ctx, clock);
}

function summe(scores: Record<PlayerId, number>): number {
  return Object.values(scores).reduce((a, b) => a + b, 0);
}

describe("goldener-affe: Einsatz-/Drop-Mathe (Goldens)", () => {
  it("gaEinsatz: 50 % vom Konto auf 10er; unter 100 ⇒ Gratis-Einsatz der Bank", () => {
    expect(gaEinsatz(2_000)).toEqual({ betrag: 1_000, gratis: false });
    expect(gaEinsatz(350)).toEqual({ betrag: 180, gratis: false });
    expect(gaEinsatz(150)).toEqual({ betrag: 100, gratis: true }); // 75 → 80 < 100
    expect(gaEinsatz(0)).toEqual({ betrag: 100, gratis: true });
  });

  it("gaDropDelta: richtige Tür ×2 zurück; Gratis-Einsatz verliert NIE", () => {
    const voll = { betrag: 500, gratis: false };
    expect(gaDropDelta(voll, 10)).toBe(500); // alles richtig: 1.000 zurück
    expect(gaDropDelta(voll, 5)).toBe(0); // halbe-halbe: Einsatz zurück
    expect(gaDropDelta(voll, 0)).toBe(-500); // alles falsch: weg
    const gratis = { betrag: 100, gratis: true };
    expect(gaDropDelta(gratis, 0)).toBe(0); // Bank trägt den Verlust
    expect(gaDropDelta(gratis, 10)).toBe(100);
  });

  it("gaFuelleChipsAuf: reihum auffüllen, leer bleibt leer, Überzug wird gestutzt", () => {
    expect(gaFuelleChipsAuf([2, 3, 0, 0])).toEqual([5, 5, 0, 0]);
    expect(gaFuelleChipsAuf([0, 0, 0, 3])).toEqual([0, 0, 0, 10]);
    expect(gaFuelleChipsAuf([0, 0, 0, 0])).toEqual([0, 0, 0, 0]); // kein Einsatz
    const gestutzt = gaFuelleChipsAuf([20, 20, 0, 0]);
    expect(gestutzt.reduce((a, b) => a + b, 0)).toBe(GA_CHIPS);
    expect(gestutzt).toEqual([5, 5, 0, 0]);
  });

  it("gaTransfer: 20 % auf 10er ABgerundet, nie aus dem Minus", () => {
    expect(gaTransfer(1_234)).toBe(240);
    expect(gaTransfer(1_000)).toBe(200);
    expect(gaTransfer(45)).toBe(0);
    expect(gaTransfer(-500)).toBe(0);
  });
});

describe("goldener-affe: Stufe 1 Money-Drop", () => {
  it("chips: letzter Stand zählt; answer = All-in-Schnellzug; alle fertig ⇒ Auswertung", () => {
    const { ctx, state } = setup();
    let s = reduce(state, aktion("p1", { type: "chips", verteilung: [5, 5, 0, 0] }, 1_000), ctx);
    s = reduce(s, aktion("p1", { type: "chips", verteilung: [0, 10, 0, 0] }, 2_000), ctx);
    expect(s.chips.p1).toEqual([0, 10, 0, 0]);
    s = reduce(s, aktion("p2", { type: "answer", choice: 1 }, 2_500), ctx);
    expect(s.chips.p2).toEqual([0, 10, 0, 0]);
    s = reduce(s, aktion("p3", { type: "answer", choice: 0 }, 3_000), ctx);
    s = reduce(s, aktion("p4", { type: "answer", choice: 1 }, 3_500), ctx);
    s = tick(s, ctx);
    expect(s.phase).toBe("drop-ergebnis");
    // p1 (Einsatz 1.000) alles richtig ⇒ +1.000; p3 (300) alles falsch ⇒ −300;
    // p4 Gratis-Einsatz alles richtig ⇒ +100.
    expect(s.drop?.p1).toEqual({ einsatz: 1_000, gratis: false, delta: 1_000 });
    expect(s.drop?.p3).toEqual({ einsatz: 300, gratis: false, delta: -300 });
    expect(s.drop?.p4).toEqual({ einsatz: 100, gratis: true, delta: 100 });
  });

  it("AFK-Schutz: keine Verteilung = KEIN Einsatz; Teil-Verteilung wird reihum aufgefüllt", () => {
    const { clock, ctx, state } = setup();
    let s = reduce(state, aktion("p1", { type: "chips", verteilung: [2, 3, 0, 0] }, 1_000), ctx);
    s = phaseVorbei(s, ctx, clock); // Timeout: p2–p4 ohne Verteilung
    expect(s.phase).toBe("drop-ergebnis");
    expect(s.chips.p1).toEqual([5, 5, 0, 0]); // aufgefüllt
    expect(s.drop?.p1?.delta).toBe(0); // 5 Chips richtig: Einsatz exakt zurück
    expect(s.drop?.p2).toBeUndefined(); // kein Einsatz — nichts verloren
    expect(s.drop?.p4).toBeUndefined();
  });

  it("2-Spieler-Spiel: Schätz-Stufe entfällt, beide werden direkt Finalisten", () => {
    const { clock, ctx, state } = setup({
      spieler: ["p1", "p2"],
      balances: { p1: 800, p2: 400 },
    });
    let s = reduce(state, aktion("p1", { type: "answer", choice: 1 }, 1_000), ctx);
    s = reduce(s, aktion("p2", { type: "answer", choice: 0 }, 1_500), ctx);
    s = tick(s, ctx);
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("buzzer"); // keine Schätz-/Wett-Phase
    expect(s.finalisten).toEqual(["p1", "p2"]);
    expect(s.ausgeschieden).toEqual([]);
  });
});

describe("goldener-affe: Stufe 2 Schätz-Showdown + Wetten", () => {
  it("die 2 Nächsten werden Finalisten; Distanz-Gleichstand: frühere Abgabe zählt", () => {
    const { clock, ctx, state } = setup();
    const s = bisWetten(state, ctx, clock);
    // bisWetten prüft: Finalisten [p1 (exakt), p2 (knapp, FRÜHER als p3)].
    expect(s.distanzen.p2).toBe(2);
    expect(s.distanzen.p3).toBe(2);
    expect(s.distanzen.p4).toBe(Infinity); // kein Tipp = ausgeschieden
  });

  it("einloggen rastet ein — spätere Tipps verpuffen", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3", "p4"]) {
      s = reduce(s, aktion(p, { type: "answer", choice: 1 }, 1_000), ctx);
    }
    s = tick(s, ctx);
    s = phaseVorbei(s, ctx, clock);
    const r = s.schaetzfrage.richtwert;
    s = reduce(s, aktion("p1", { type: "tipp", wert: r + 5 }, clock.now() + 500), ctx);
    s = reduce(s, aktion("p1", { type: "einloggen", wert: r + 3 }, clock.now() + 800), ctx);
    const danach = reduce(s, aktion("p1", { type: "tipp", wert: r }, clock.now() + 900), ctx);
    expect(danach.tipps.p1.wert).toBe(r + 3); // eingerastet
  });

  it("Wetten: NUR Ausgeschiedene, NUR auf Finalisten, einrasten; alle gewettet ⇒ Buzzer", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    // Finalist darf nicht wetten; Wette auf Nicht-Finalist verpufft.
    expect(reduce(s, aktion("p1", { type: "wette", auf: "p2" }, clock.now()), ctx)).toBe(s);
    expect(reduce(s, aktion("p3", { type: "wette", auf: "p4" }, clock.now()), ctx)).toBe(s);
    s = reduce(s, aktion("p3", { type: "wette", auf: "p1" }, clock.now()), ctx);
    const doppelt = reduce(s, aktion("p3", { type: "wette", auf: "p2" }, clock.now()), ctx);
    expect(doppelt.wetten.p3).toBe("p1"); // eingerastet
    s = reduce(doppelt, aktion("p4", { type: "wette", auf: "p2" }, clock.now()), ctx);
    s = tick(s, ctx);
    expect(s.phase).toBe("buzzer"); // alle Ausgeschiedenen haben gewettet
  });
});

describe("goldener-affe: Stufe 3 Buzzer-Best-of-3 + Krönung", () => {
  it("2 Punkte siegen vorzeitig; 20-%-Transfer EXAKT nullsummig gegen die Deltas", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    s = reduce(s, aktion("p3", { type: "wette", auf: "p1" }, clock.now()), ctx); // richtig
    s = reduce(s, aktion("p4", { type: "wette", auf: "p2" }, clock.now()), ctx); // falsch
    s = tick(s, ctx);
    // p1 holt 2 Punkte in Folge (schnellste RICHTIGE Antwort).
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p2", choice: 1, nachMs: 900 },
    ]);
    expect(s.punkte.p1).toBe(1);
    expect(s.phase).toBe("buzzer");
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p2", choice: 0, nachMs: 500 },
    ]);
    expect(s.phase).toBe("kroenung");
    expect(s.sieger).toBe("p1");
    s = phaseVorbei(s, ctx, clock);
    expect(goldenerAffePlugin.isFinished(s)).toBe(true);
    const scores = goldenerAffePlugin.scores(s);
    // Drop: +1000/+500/+300/+100 · Wetten: p3 +100, p4 −50 · Transfer:
    // p2 (1000+500→1500) 300 · p3 (600+300+100→1000) 200 · p4 (100+100−50→150) 30.
    expect(scores[asPlayerId("p1")]).toBe(1_000 + 530);
    expect(scores[asPlayerId("p2")]).toBe(500 - 300);
    expect(scores[asPlayerId("p3")]).toBe(300 + 100 - 200);
    expect(scores[asPlayerId("p4")]).toBe(100 - 50 - 30);
    // Invariante: Σ scores = Σ Drop-Deltas + Σ Wett-Deltas (Transfer nullsummig).
    const dropSumme = Object.values(s.drop ?? {}).reduce((a, d) => a + d.delta, 0);
    expect(summe(scores)).toBe(dropSumme + 100 - 50);
    const outcomes = goldenerAffePlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBe(true); // Wette richtig
    expect(outcomes[asPlayerId("p4")].correct).toBe(false);
  });

  it("1:1 nach 3 Fragen ⇒ Schätz-Showdown; näher dran gewinnt", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    s = phaseVorbei(s, ctx, clock); // Wett-Timeout ohne Wetten
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p2", choice: 0, nachMs: 400 },
    ]);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p2", choice: 1, nachMs: 300 },
      { p: "p1", choice: 0, nachMs: 400 },
    ]);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 2, nachMs: 300 },
      { p: "p2", choice: 3, nachMs: 400 },
    ]);
    expect(s.phase).toBe("showdown");
    const r = s.showdownFrage.richtwert;
    s = reduce(s, aktion("p2", { type: "tipp", wert: r + 1 }, clock.now() + 500), ctx);
    s = reduce(s, aktion("p1", { type: "tipp", wert: r + 9 }, clock.now() + 600), ctx);
    s = tick(s, ctx); // beide getippt ⇒ Auswertung
    expect(s.phase).toBe("kroenung");
    expect(s.sieger).toBe("p2");
  });

  it("Showdown-Distanz-Gleichstand: frühere Abgabe gewinnt", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    s = phaseVorbei(s, ctx, clock);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p2", choice: 0, nachMs: 400 },
    ]);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p2", choice: 1, nachMs: 300 },
      { p: "p1", choice: 0, nachMs: 400 },
    ]);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 2, nachMs: 300 },
      { p: "p2", choice: 3, nachMs: 400 },
    ]);
    const r = s.showdownFrage.richtwert;
    s = reduce(s, aktion("p2", { type: "tipp", wert: r + 2 }, clock.now() + 500), ctx);
    s = reduce(s, aktion("p1", { type: "tipp", wert: r - 2 }, clock.now() + 800), ctx);
    s = tick(s, ctx);
    expect(s.sieger).toBe("p2"); // gleiche Distanz — p2 war früher dran
  });
});

describe("goldener-affe: Edge-Cases + Leaks + Determinismus", () => {
  it("Finalist-Disconnect ⇒ Wildcard-Nachrücker; Wetten auf den Ersetzten erstattet", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    s = reduce(s, aktion("p3", { type: "wette", auf: "p1" }, clock.now()), ctx);
    s = reduce(s, aktion("p4", { type: "wette", auf: "p2" }, clock.now()), ctx);
    s = tick(s, ctx);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p2", choice: 0, nachMs: 400 },
    ]);
    expect(s.punkte.p1).toBe(1);
    s = goldenerAffePlugin.onDisconnect(s, asPlayerId("p1"), ctx) as GoldenerAffeState;
    // p3 (beste Schätz-Distanz der Verbundenen) rückt nach, p1s Punkte verfallen.
    expect(s.wildcard).toBe("p3");
    expect(s.finalisten).toEqual(["p3", "p2"]);
    expect(s.ausgeschieden).toContain("p1");
    expect(s.wetten.p3).toBeUndefined(); // Wette auf p1 erstattet (+ Nachrücker)
    expect(s.wetten.p4).toBe("p2"); // fremde Wette bleibt
    expect(s.punkte.p1).toBeUndefined();
    expect(s.phase).toBe("buzzer"); // frisches Fenster für die neue Paarung
  });

  it("2-Spieler + Finalist-Disconnect ⇒ kampfloser Titel OHNE 20-%-Transfer", () => {
    const { clock, ctx, state } = setup({
      spieler: ["p1", "p2"],
      balances: { p1: 800, p2: 400 },
    });
    let s = reduce(state, aktion("p1", { type: "answer", choice: 1 }, 1_000), ctx);
    s = reduce(s, aktion("p2", { type: "answer", choice: 0 }, 1_500), ctx);
    s = tick(s, ctx);
    s = phaseVorbei(s, ctx, clock); // → buzzer
    s = goldenerAffePlugin.onDisconnect(s, asPlayerId("p1"), ctx) as GoldenerAffeState;
    expect(s.phase).toBe("kroenung");
    expect(s.kampflos).toBe(true);
    expect(s.sieger).toBe("p2");
    s = phaseVorbei(s, ctx, clock);
    const scores = goldenerAffePlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(400); // NUR das Drop-Delta (richtig)
    expect(scores[asPlayerId("p2")]).toBe(-200); // NUR das Drop-Delta (falsch)
  });

  it("GM force.finish VOR der Krönung ⇒ ALLE 0; in der Krönung gilt die Abrechnung", () => {
    const { clock, ctx, state } = setup();
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    // Mitten im Drop übersprungen: NIEMAND zahlt.
    let s = reduce(state, aktion("p1", { type: "answer", choice: 1 }, 1_000), ctx);
    const abgebrochen = reduce(s, skip, ctx);
    expect(abgebrochen.finished).toBe(true);
    expect(summe(goldenerAffePlugin.scores(abgebrochen))).toBe(0);
    // In der Krönung: Abrechnung bleibt.
    s = bisWetten(state, ctx, clock);
    s = phaseVorbei(s, ctx, clock);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p2", choice: 0, nachMs: 400 },
    ]);
    s = buzzerRunde(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p2", choice: 0, nachMs: 400 },
    ]);
    expect(s.phase).toBe("kroenung");
    const fertig = reduce(s, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(goldenerAffePlugin.scores(fertig)[asPlayerId("p1")]).toBeGreaterThan(0);
  });

  it("Leak-Wache Stufe 1+2: Lösung/Richtwert GEHEIM bis zur Auflösung, GM sieht alles", () => {
    const { clock, ctx, state } = setup();
    const drop = goldenerAffePlugin.viewFor(state, "screen") as Record<string, unknown>;
    expect(drop.options).toEqual(["A", "B", "C", "D"]); // Frage public — alle verteilen
    expect(drop.correctIndex).toBeUndefined();
    expect(drop.dropErgebnis).toBeNull();
    const spieler = goldenerAffePlugin.viewFor(state, "player", asPlayerId("p4")) as Record<
      string,
      unknown
    >;
    expect(spieler.correctIndex).toBeUndefined();
    expect(spieler.deinEinsatz).toEqual({ betrag: 100, gratis: true });
    const gm = goldenerAffePlugin.viewFor(state, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
    // Stufe 2: Richtwert geheim, solange geschätzt wird.
    let s = state;
    for (const p of ["p1", "p2", "p3", "p4"]) {
      s = reduce(s, aktion(p, { type: "answer", choice: 1 }, 1_000), ctx);
    }
    s = tick(s, ctx);
    s = phaseVorbei(s, ctx, clock);
    const schaetzen = goldenerAffePlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect((schaetzen.schaetz as { richtwert: number | null }).richtwert).toBeNull();
    const gmSchaetzen = goldenerAffePlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gmSchaetzen.richtwert).toBe(s.schaetzfrage.richtwert);
  });

  it("Leak-Wache Stufe 3: Buzzer-Antwortrecht NUR für Finalisten", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    s = phaseVorbei(s, ctx, clock); // → buzzer
    const finalist = goldenerAffePlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(finalist.duBistFinalist).toBe(true);
    expect(finalist.options).toEqual(["A", "B", "C", "D"]);
    const zuschauer = goldenerAffePlugin.viewFor(s, "player", asPlayerId("p3")) as Record<
      string,
      unknown
    >;
    expect(zuschauer.options).toBeNull();
    expect(zuschauer.zuschauerOptionen).toEqual(["A", "B", "C", "D"]);
    // Ausgeschiedene können auch NICHT antworten (Server-Wache).
    expect(reduce(s, aktion("p3", { type: "answer", choice: 1 }, clock.now() + 100), ctx)).toBe(s);
  });

  it("Pool- + Seed-Determinismus: gleicher Ablauf ⇒ identischer End-State", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = bisWetten(state, ctx, clock);
      s = phaseVorbei(s, ctx, clock);
      s = buzzerRunde(s, ctx, clock, [
        { p: "p1", choice: 1, nachMs: 300 },
        { p: "p2", choice: 1, nachMs: 310 }, // Fotofinish-Los (<40 ms)
      ]);
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(a.schaetzfrage.id).toBe(b.schaetzfrage.id); // deterministische Pool-Wahl
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  it("Späte/doppelte Buzzer-Antworten verpuffen; Timeout ohne Antworten ⇒ kein Punkt", () => {
    const { clock, ctx, state } = setup();
    let s = bisWetten(state, ctx, clock);
    s = phaseVorbei(s, ctx, clock);
    const start = s.frageStartetAt ?? 0;
    // Zu spät (nach Gnade): verworfen.
    const zuSpaet = s.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p1", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(s);
    // Erste Antwort rastet ein.
    s = reduce(s, aktion("p1", { type: "answer", choice: 0 }, start + 300), ctx);
    const doppelt = reduce(s, aktion("p1", { type: "answer", choice: 1 }, start + 400), ctx);
    expect(doppelt.answers.p1.choice).toBe(0);
    // Timeout ohne richtige Antworten: niemand punktet, nächste Frage kommt.
    clock.advance(s.phaseEndsAt + SPAETANTWORT_GNADE_MS - clock.now() + 1);
    s = tick(s, ctx);
    expect(s.phase).toBe("buzzer-ergebnis");
    expect(s.letzteBuzzerFrage?.gewinner).toBeNull();
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("buzzer");
    expect(s.buzzerRunde).toBe(2);
  });
});
