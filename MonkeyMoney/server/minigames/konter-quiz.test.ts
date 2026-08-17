// Konter-Quiz: Geld-Mathe-Goldens (Bank-Prämie + Konter-Gutschrift, Transfer
// EXAKT nullsummig über alle Antwort-Kombinationen), Herausforderer-Prinzip
// (Letzter wählt, Feiglings-Schutz, Timeout = Führender), Rundenpunkt über die
// Buzzer-Reihenfolge (Fotofinish-Los), Duell bis zur Bilanz, Disconnect
// (Runde endet OHNE Transfer), 2-Spieler-Sonderfall, GM-Kommandos,
// Leak-Wachen, Pool-Wächter und Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import type { Schwierigkeit } from "../../shared/money";
import {
  KQ_KONTER_MM,
  KQ_RICHTIG_MM,
  KQ_RUNDEN,
  kqFrageDeltas,
  type KonterQuizAction,
} from "../../shared/minigames/konter-quiz.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { konterQuizPlugin, kqGegnerKandidaten, type KonterQuizState } from "./konter-quiz/index";

function fragen(n: number, difficulty: Schwierigkeit = "easy"): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_kq_${i + 1}`,
    kind: "choice4" as const,
    category: "affen_wissen",
    difficulty,
    text: `Blitz-Frage ${i + 1}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  }));
}

// Konten: p4 ist der Letzte (Herausforderer), p1 der Führende, p3 der ärmste
// GEGNER (Feiglings-Schutz).
const KONTEN = { p1: 2_000, p2: 1_500, p3: 1_000, p4: 500 };

function setup(
  opts: {
    balances?: Record<string, number> | null;
    spieler?: string[];
    seed?: number;
    questions?: Question[];
  } = {},
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
  const content: ContentSlice = { questions: opts.questions ?? fragen(KQ_RUNDEN) };
  const state = konterQuizPlugin.init(spieler, content, ctx) as KonterQuizState;
  return { clock, ctx, state, spieler };
}

function aktion(p: string, a: KonterQuizAction, at: number): PlayerAction<KonterQuizAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(s: KonterQuizState, a: PlayerAction<KonterQuizAction> | GmAction, ctx: Ctx) {
  return konterQuizPlugin.reduce(s, a, ctx) as KonterQuizState;
}

function tick(s: KonterQuizState, ctx: Ctx) {
  return konterQuizPlugin.tick(s, ctx) as KonterQuizState;
}

/** Uhr bis nach dem Phasen-Ende, dann tick (Phasen-Übergang erzwingen). */
function phaseVorbei(s: KonterQuizState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndsAt - clock.now()) + 1);
  return tick(s, ctx);
}

/** Standard-Einstieg: p4 fordert p1, der Countdown läuft ab, Frage 1 startet. */
function insDuell(state: KonterQuizState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 1_000), ctx);
  expect(s.phase).toBe("countdown");
  s = phaseVorbei(s, ctx, clock);
  expect(s.phase).toBe("frage");
  return s;
}

/** Eine Frage spielen: Antworten einspeisen (nachMs relativ zum Frage-Start),
 * auswerten — endet im Konter-Beat (oder bei Offline-Duellant im Ergebnis). */
function spieleFrage(
  s: KonterQuizState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
  antworten: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[],
) {
  expect(s.phase).toBe("frage");
  const start = s.frageStartetAt ?? 0;
  for (const a of antworten) {
    s = reduce(s, aktion(a.p, { type: "answer", choice: a.choice }, start + a.nachMs), ctx);
  }
  if (antworten.length < 2) {
    clock.advance(s.phaseEndsAt + SPAETANTWORT_GNADE_MS - clock.now() + 1);
  }
  return tick(s, ctx);
}

function summe(rec: Record<string, number>): number {
  return Object.values(rec).reduce((a, b) => a + b, 0);
}

describe("konter-quiz: Geld-Mathe (kqFrageDeltas, Goldens)", () => {
  it("beide richtig ⇒ je +150 Bank, Transfer 0/0", () => {
    const d = kqFrageDeltas(["a", "b"], { a: { choice: 1 }, b: { choice: 1 } }, 1);
    expect(d.bank).toEqual({ a: KQ_RICHTIG_MM, b: KQ_RICHTIG_MM });
    expect(d.transfer).toEqual({ a: 0, b: 0 });
  });

  it("einer falsch ⇒ 150 wandern als Konter-Gutschrift zum Partner (−150/+150)", () => {
    const d = kqFrageDeltas(["a", "b"], { a: { choice: 0 }, b: { choice: 1 } }, 1);
    expect(d.bank).toEqual({ a: 0, b: KQ_RICHTIG_MM });
    expect(d.transfer).toEqual({ a: -KQ_KONTER_MM, b: KQ_KONTER_MM });
  });

  it("keine Antwort kostet nichts (Schweigen ist gratis, kein Timeout-Malus)", () => {
    const d = kqFrageDeltas(["a", "b"], { b: { choice: 1 } }, 1);
    expect(d.bank).toEqual({ a: 0, b: KQ_RICHTIG_MM });
    expect(d.transfer).toEqual({ a: 0, b: 0 });
    const beideStumm = kqFrageDeltas(["a", "b"], {}, 1);
    expect(beideStumm.bank).toEqual({ a: 0, b: 0 });
    expect(beideStumm.transfer).toEqual({ a: 0, b: 0 });
  });

  it("Transfer-NULLSUMME über ALLE Antwort-Kombinationen (Wächter)", () => {
    const faelle: (undefined | { choice: number })[] = [
      undefined,
      { choice: 0 },
      { choice: 1 },
      { choice: 2 },
    ];
    for (const aAntwort of faelle) {
      for (const bAntwort of faelle) {
        const d = kqFrageDeltas(["a", "b"], { a: aAntwort, b: bAntwort }, 1);
        expect(d.transfer.a + d.transfer.b).toBe(0);
        expect(d.bank.a).toBeGreaterThanOrEqual(0);
        expect(d.bank.b).toBeGreaterThanOrEqual(0);
      }
    }
    // beide falsch: die Gutschriften heben sich gegenseitig auf (je ±0 netto).
    const beideFalsch = kqFrageDeltas(["a", "b"], { a: { choice: 0 }, b: { choice: 2 } }, 1);
    expect(beideFalsch.transfer).toEqual({ a: 0, b: 0 });
  });
});

describe("konter-quiz: Herausforderer-Prinzip", () => {
  it("der Letzte fordert; der ärmste Gegner ist geschützt; Fremd-Wahl verpufft", () => {
    const { ctx, state } = setup();
    expect(state.phase).toBe("herausforderung");
    expect(state.herausforderer).toBe("p4"); // 500 MM = Letzter
    const kandidaten = kqGegnerKandidaten(state);
    expect(kandidaten.find((k) => k.id === "p3")?.waehlbar).toBe(false); // Feiglings-Schutz
    expect(kandidaten.find((k) => k.id === "p1")?.waehlbar).toBe(true);
    expect(reduce(state, aktion("p4", { type: "herausfordern", targetId: "p3" }, 500), ctx)).toBe(
      state,
    );
    expect(reduce(state, aktion("p1", { type: "herausfordern", targetId: "p2" }, 500), ctx)).toBe(
      state,
    );
    const s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p2" }, 500), ctx);
    expect(s.gegner).toBe("p2");
    expect(s.phase).toBe("countdown");
  });

  it("Timeout wählt den Führenden als Gegner („der Führende muss ran“)", () => {
    const { clock, ctx, state } = setup();
    const s = phaseVorbei(state, ctx, clock);
    expect(s.gegner).toBe("p1"); // 2.000 MM = Führender
    expect(s.phase).toBe("countdown");
  });

  it("2-Spieler-Spiel: Gegner fix, KEINE Herausforderungs-Phase, direkt Countdown", () => {
    const { state } = setup({ spieler: ["p1", "p2"], balances: { p1: 800, p2: 400 } });
    expect(state.phase).toBe("countdown");
    expect(state.herausforderer).toBe("p2");
    expect(state.gegner).toBe("p1");
  });

  it("alle Gegner offline beim Timeout ⇒ Abbruch, alle Scores 0", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3"]) {
      s = konterQuizPlugin.onDisconnect(s, asPlayerId(p), ctx) as KonterQuizState;
    }
    s = phaseVorbei(s, ctx, clock);
    expect(s.abgebrochen).toBe(true);
    expect(s.finished).toBe(true);
    expect(summe(konterQuizPlugin.scores(s))).toBe(0);
  });
});

describe("konter-quiz: Duell-Ablauf + Rundenpunkt", () => {
  it("richtig = Bank, falsch = Konter-Gutschrift; der Konter-Beat zeigt die Deltas", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    s = spieleFrage(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 500 },
      { p: "p1", choice: 0, nachMs: 900 },
    ]);
    expect(s.phase).toBe("konter");
    expect(s.letzteRunde?.bank).toEqual({ p4: KQ_RICHTIG_MM, p1: 0 });
    expect(s.letzteRunde?.transfer).toEqual({ p1: -KQ_KONTER_MM, p4: KQ_KONTER_MM });
    expect(s.letzteRunde?.punktFuer).toBe("p4");
    expect(s.bank).toEqual({ p4: KQ_RICHTIG_MM, p1: 0 });
    expect(s.transfer.p1 + s.transfer.p4).toBe(0);
  });

  it("beide richtig ⇒ die SCHNELLERE Antwort holt den Rundenpunkt (Buzzer-Ordnung)", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    s = spieleFrage(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p4", choice: 1, nachMs: 900 }, // > 40 ms später — kein Fotofinish
    ]);
    expect(s.letzteRunde?.fotofinish).toBe(false);
    expect(s.letzteRunde?.punktFuer).toBe("p1");
    expect(s.punkte).toEqual({ p1: 1 });
    // Geld ist unabhängig vom Punkt: BEIDE kassieren die Bank-Prämie.
    expect(s.bank).toEqual({ p1: KQ_RICHTIG_MM, p4: KQ_RICHTIG_MM });
  });

  it("volles Duell (8 Fragen): Scores = Bank + Transfer, Transfer-Anteil nullsummig", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    // p4: 6× richtig, 2× falsch · p1: 3× richtig, 4× falsch, 1× stumm.
    const plan: { p4: 0 | 1; p1?: 0 | 1 }[] = [
      { p4: 1, p1: 1 },
      { p4: 1, p1: 0 },
      { p4: 0, p1: 1 },
      { p4: 1, p1: 0 },
      { p4: 1, p1: 0 },
      { p4: 0, p1: 0 },
      { p4: 1, p1: 1 },
      { p4: 1 },
    ];
    for (const [i, z] of plan.entries()) {
      expect(s.rundeNr).toBe(i + 1);
      const antworten: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[] = [
        { p: "p4", choice: z.p4, nachMs: 500 },
      ];
      if (z.p1 !== undefined) antworten.push({ p: "p1", choice: z.p1, nachMs: 900 });
      s = spieleFrage(s, ctx, clock, antworten);
      expect(s.phase).toBe("konter"); // JEDE Frage endet im Konter-Beat
      s = phaseVorbei(s, ctx, clock);
      expect(s.phase).toBe(i < plan.length - 1 ? "frage" : "ergebnis");
    }
    expect(s.rundeNr).toBe(KQ_RUNDEN);
    s = phaseVorbei(s, ctx, clock);
    expect(konterQuizPlugin.isFinished(s)).toBe(true);
    const scores = konterQuizPlugin.scores(s);
    // p4: 6×150 Bank − 2×150 Konter + 4×150 Gutschrift = 900 − 300 + 600 = 1.200
    expect(scores[asPlayerId("p4")]).toBe(6 * 150 - 2 * 150 + 4 * 150);
    // p1: 3×150 Bank − 4×150 Konter + 2×150 Gutschrift = 450 − 600 + 300 = 150
    expect(scores[asPlayerId("p1")]).toBe(3 * 150 - 4 * 150 + 2 * 150);
    expect(scores[asPlayerId("p2")]).toBe(0); // Zuschauer bleiben unberührt
    expect(s.transfer.p1 + s.transfer.p4).toBe(0); // Nullsummen-Wächter
    // Σ Scores = NUR die Bank-Prämien (die Transfers heben sich auf).
    expect(summe(scores)).toBe(summe(s.bank));
    // Punkte: p4 holt alle 6 richtigen (immer schneller), p1 nur Frage 3
    // (einzige Frage, in der NUR p1 richtig lag).
    expect(s.punkte).toEqual({ p4: 6, p1: 1 });
    const outcomes = konterQuizPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p4")].correct).toBe(true); // 6 > 2
    expect(outcomes[asPlayerId("p1")].correct).toBe(false); // 3 < 4
    expect(outcomes[asPlayerId("p2")].correct).toBeNull();
  });

  it("Zuschauer-/Spät-/Doppel-Antworten verpuffen (nur Duellanten, erste zählt)", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    expect(reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s);
    const zuSpaet = s.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p4", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(s);
    s = reduce(s, aktion("p4", { type: "answer", choice: 0 }, clock.now() + 500), ctx);
    const doppelt = reduce(s, aktion("p4", { type: "answer", choice: 1 }, clock.now() + 600), ctx);
    expect(doppelt.answers.p4.choice).toBe(0);
  });
});

describe("konter-quiz: Disconnect + GM + Leaks + Determinismus", () => {
  it("Duellant-Disconnect ⇒ Runde endet SOFORT und OHNE Transfer (Bank bleibt)", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    s = spieleFrage(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 500 },
      { p: "p1", choice: 0, nachMs: 900 }, // p1 falsch ⇒ Transfer läuft auf
    ]);
    expect(s.transfer.p4).toBe(KQ_KONTER_MM);
    s = phaseVorbei(s, ctx, clock); // → Frage 2
    s = konterQuizPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as KonterQuizState;
    expect(s.phase).toBe("ergebnis");
    expect(s.ohneTransfer).toBe(true);
    expect(s.vorzeitig).toBe(true);
    s = phaseVorbei(s, ctx, clock);
    const scores = konterQuizPlugin.scores(s);
    expect(scores[asPlayerId("p4")]).toBe(KQ_RICHTIG_MM); // NUR die Bank-Prämie
    expect(scores[asPlayerId("p1")]).toBe(0); // kein Abzug offline
    expect(summe(scores)).toBe(summe(s.bank)); // kein Transfer-Rest
  });

  it("Zuschauer-Disconnect stört das Duell NICHT", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    s = konterQuizPlugin.onDisconnect(s, asPlayerId("p2"), ctx) as KonterQuizState;
    expect(s.phase).toBe("frage");
    s = spieleFrage(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 500 },
      { p: "p1", choice: 1, nachMs: 900 },
    ]);
    expect(s.phase).toBe("konter");
  });

  it("GM force.finish VOR dem Ergebnis ⇒ Abbruch ohne Zahlung; im Ergebnis gilt es", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, clock);
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    const abgebrochen = reduce(s, skip, ctx);
    expect(abgebrochen.finished).toBe(true);
    expect(summe(konterQuizPlugin.scores(abgebrochen))).toBe(0);
    for (let i = 0; i < KQ_RUNDEN; i++) {
      s = spieleFrage(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 900 },
      ]);
      if (s.phase === "konter") s = phaseVorbei(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    const fertig = reduce(s, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(konterQuizPlugin.scores(fertig)[asPlayerId("p4")]).toBe(
      KQ_RUNDEN * KQ_RICHTIG_MM + KQ_RUNDEN * KQ_KONTER_MM,
    );
  });

  it("GM timer.extend/timer.shift verschieben die Zeitanker konsistent", () => {
    const { clock, ctx, state } = setup();
    const s = insDuell(state, ctx, clock);
    const laenger = reduce(s, { kind: "gm", type: "timer.extend", ms: 5_000 }, ctx);
    expect(laenger.phaseEndsAt).toBe(s.phaseEndsAt + 5_000);
    expect(laenger.frageStartetAt).toBe(s.frageStartetAt); // extend schiebt NUR das Ende
    const pause = reduce(s, { kind: "gm", type: "timer.shift", ms: 60_000 }, ctx);
    expect(pause.phaseEndsAt).toBe(s.phaseEndsAt + 60_000);
    expect(pause.startedAt).toBe(s.startedAt + 60_000);
    expect(pause.frageStartetAt).toBe((s.frageStartetAt ?? 0) + 60_000);
  });

  it("Leak-Wachen: Frage nur im Fenster, correctIndex nur GM, Optionen nur Duellanten", () => {
    const { clock, ctx, state } = setup();
    let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 1_000), ctx);
    const countdown = konterQuizPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(countdown.text).toBeNull();
    expect(countdown.options).toBeNull();
    s = phaseVorbei(s, ctx, clock); // → frage
    const screen = konterQuizPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.text).toBe("Blitz-Frage 1?");
    expect(screen.correctIndex).toBeUndefined();
    expect(screen.letzteRunde).toBeNull(); // Lösung erst im Konter-Beat
    const duellant = konterQuizPlugin.viewFor(s, "player", asPlayerId("p4")) as Record<
      string,
      unknown
    >;
    expect(duellant.correctIndex).toBeUndefined();
    expect(duellant.duBistDuellant).toBe(true);
    expect(duellant.options).toEqual(["A", "B", "C", "D"]);
    const zuschauer = konterQuizPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(zuschauer.options).toBeNull(); // Zuschauer raten nur im Kopf mit
    expect(zuschauer.duBistDuellant).toBe(false);
    const gm = konterQuizPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
    s = reduce(s, aktion("p4", { type: "answer", choice: 1 }, (s.frageStartetAt ?? 0) + 500), ctx);
    s = reduce(s, aktion("p1", { type: "answer", choice: 0 }, (s.frageStartetAt ?? 0) + 900), ctx);
    s = tick(s, ctx);
    const konter = konterQuizPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect((konter.letzteRunde as { correctIndex: number }).correctIndex).toBe(1);
  });

  it("Gegner-Wahl-Grid sieht NUR der Herausforderer (inkl. Kontostände)", () => {
    const { state } = setup();
    const heraus = konterQuizPlugin.viewFor(state, "player", asPlayerId("p4")) as {
      waehlbareGegner: { id: string; waehlbar: boolean; kontostand: number | null }[] | null;
    };
    expect(heraus.waehlbareGegner?.map((k) => k.id)).toEqual(["p1", "p2", "p3"]);
    expect(heraus.waehlbareGegner?.find((k) => k.id === "p1")?.kontostand).toBe(2_000);
    const andere = konterQuizPlugin.viewFor(state, "player", asPlayerId("p2")) as {
      waehlbareGegner: unknown;
    };
    expect(andere.waehlbareGegner).toBeNull();
  });

  it("Pool-Wächter: kaputte Fragen fliegen raus; ganz ohne Frage wirft init", () => {
    const kaputt: Question = {
      id: "q_defekt",
      kind: "choice4",
      category: "affen_wissen",
      difficulty: "easy",
      text: "Defekt?",
      options: ["A", "B", "C", "D"],
      answer: 9, // Antwort-Index außerhalb der Optionen
      erklaerung: "",
    };
    const { state } = setup({ questions: [...fragen(2), kaputt] });
    expect(state.questions.map((q) => q.id)).toEqual(["q_kq_1", "q_kq_2"]);
    expect(() => setup({ questions: [kaputt] })).toThrow(/ohne brauchbare Frage/);
  });

  it("Seed-Determinismus: Fotofinish-Los (<40 ms) ist mit gleichem Seed reproduzierbar", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = insDuell(state, ctx, clock);
      s = spieleFrage(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 1, nachMs: 510 }, // 10 ms Abstand ⇒ Münzwurf
      ]);
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(a.letzteRunde?.fotofinish).toBe(true);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});
