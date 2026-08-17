// Bananen-Börse: Kurs-Formel-Goldens (3,0 − 1,5 × Anteil, min 1,2),
// Block-Snapshots (eingefroren beim ersten Ereignis im Block, Chart wächst),
// exakte Abrechnungs-Mathe (Gewinn = rundeAuf10(E×(quote−1)), falsch = −E,
// Spread = rundeAuf10(E×0,25)), kaufen/halten/verkaufen inkl. Umschichtung,
// Quote-Einfrieren beim Kauf, Börsenschluss-Wachen, Disconnect, GM + Faktor.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  BOERSE_BLOECKE,
  BOERSE_HANDEL_MS,
  boerseEinsatz,
  boerseGewinn,
  boerseQuote,
  boerseSpreadVerlust,
} from "../../shared/minigames/bananen-boerse.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { bananenBoersePlugin, type BananenBoerseState } from "./bananen-boerse/index";

function frage(difficulty: Question["difficulty"] = "medium"): Question {
  return {
    id: `q_boerse_${difficulty}`,
    kind: "choice4",
    category: "boersen_wissen",
    difficulty,
    text: "Welche Aktie steigt?",
    options: ["Banana Inc", "Kokos AG", "Liane SE", "Palme KG"],
    answer: 0,
    erklaerung: "Banana Inc — der Klassiker.",
  };
}

function setup(difficulty: Question["difficulty"] = "medium", mods?: ContentSlice["mods"]) {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(3) };
  const spieler = ["p1", "p2", "p3", "p4"].map(asPlayerId);
  const content: ContentSlice = mods
    ? { questions: [frage(difficulty)], mods }
    : { questions: [frage(difficulty)] };
  const state = bananenBoersePlugin.init(spieler, content, ctx) as BananenBoerseState;
  return { clock, ctx, state, spieler };
}

type BoerseAction = { type: "answer"; choice: 0 | 1 | 2 | 3 } | { type: "verkaufen" };

function aktion(playerId: string, a: BoerseAction, at: number): PlayerAction<BoerseAction> {
  return { kind: "player", playerId: asPlayerId(playerId), action: a, atServerTime: at };
}

function schluss(s: BananenBoerseState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.endetAt - clock.now()) + 1);
  return bananenBoersePlugin.tick(s, ctx) as BananenBoerseState;
}

describe("bananen-boerse: Kurs-Formel (Goldens §2.12/4)", () => {
  it("Quote = 3,0 − 1,5 × Anteil (4 Spieler: 3,0 / 2,625 / 2,25 / 1,875 / 1,5)", () => {
    expect(boerseQuote(0, 4)).toBe(3.0);
    expect(boerseQuote(1, 4)).toBe(2.625);
    expect(boerseQuote(2, 4)).toBe(2.25);
    expect(boerseQuote(3, 4)).toBe(1.875);
    expect(boerseQuote(4, 4)).toBe(1.5);
  });

  it("Quote-Klemme: nie unter 1,2", () => {
    expect(boerseQuote(2, 1)).toBe(1.2); // theoretischer Extremfall
  });

  it("Einsatz E = W/2 je Schwierigkeit (50/125/250/500)", () => {
    expect(boerseEinsatz(100)).toBe(50);
    expect(boerseEinsatz(250)).toBe(125);
    expect(boerseEinsatz(500)).toBe(250);
    expect(boerseEinsatz(1000)).toBe(500);
    expect(setup("hard").state.einsatz).toBe(250);
  });

  it("Gewinn-/Spread-Rundung auf 10er (medium: Quote 2,25 → 160 · Spread → 30)", () => {
    expect(boerseGewinn(125, 3.0)).toBe(250);
    expect(boerseGewinn(125, 2.25)).toBe(160); // 156,25 → 160
    expect(boerseGewinn(125, 1.5)).toBe(60); // 62,5 → 60? Math.round(6.25)=6 → 60
    expect(boerseSpreadVerlust(125)).toBe(30); // 31,25 → 30
    expect(boerseSpreadVerlust(250)).toBe(60); // 62,5 → 60? Math.round(6.25)=6
  });
});

describe("bananen-boerse: Handel + Abrechnung (exakt)", () => {
  it("Block-0-Kauf zur Start-Quote 3,0: richtig = +2E, falsch = −E", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 500),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p2", { type: "answer", choice: 2 }, 600),
      ctx,
    ) as BananenBoerseState;
    s = schluss(s, ctx, clock);
    const scores = bananenBoersePlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(250); // 125 × (3,0 − 1) = 250
    expect(scores[asPlayerId("p2")]).toBe(-125);
    expect(scores[asPlayerId("p3")]).toBe(0); // nie gehandelt
  });

  it("Herden-Quote: Block-1-Snapshot zählt die Halter am Block-Anfang", () => {
    const { clock, ctx, state } = setup();
    // Block 0: p1 + p2 kaufen Option 0 (Quote 3,0 eingefroren).
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 500),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p2", { type: "answer", choice: 0 }, 600),
      ctx,
    ) as BananenBoerseState;
    // Block 1 beginnt (5 s): der Snapshot sieht 2/4 Halter auf Option 0.
    clock.advance(5_100);
    s = bananenBoersePlugin.tick(s, ctx) as BananenBoerseState;
    expect(s.kursBloecke[1][0]).toBe(2.25); // 3,0 − 1,5 × 0,5
    expect(s.kursBloecke[1][1]).toBe(3.0);
    // p3 kauft die Herden-Option im Block 1 → schlechtere Quote 2,25.
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p3", { type: "answer", choice: 0 }, clock.now()),
      ctx,
    ) as BananenBoerseState;
    expect(s.positionen.p3?.quote).toBe(2.25);
    s = schluss(s, ctx, clock);
    const scores = bananenBoersePlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(250); // frühe Quote bleibt eingefroren
    expect(scores[asPlayerId("p3")]).toBe(160); // rundeAuf10(125 × 1,25)
  });

  it("Die eigene Quote bleibt eingefroren — spätere Herde ändert sie NICHT", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 100),
      ctx,
    ) as BananenBoerseState;
    const quoteVorher = s.positionen.p1?.quote;
    clock.advance(11_000); // Block 2
    s = bananenBoersePlugin.tick(s, ctx) as BananenBoerseState;
    for (const p of ["p2", "p3", "p4"]) {
      s = bananenBoersePlugin.reduce(
        s,
        aktion(p, { type: "answer", choice: 0 }, clock.now()),
        ctx,
      ) as BananenBoerseState;
    }
    expect(s.positionen.p1?.quote).toBe(quoteVorher);
  });

  it("VERKAUFEN: Position weg, Spread −rundeAuf10(E×0,25), zweiter Verkauf gesperrt", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 500),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p1", { type: "verkaufen" }, 1_000),
      ctx,
    ) as BananenBoerseState;
    expect(s.positionen.p1).toBeNull();
    // Ohne Neukauf: nur der Spread-Verlust.
    const fertig = schluss(s, ctx, clock);
    expect(bananenBoersePlugin.scores(fertig)[asPlayerId("p1")]).toBe(-30);
    // Verkaufen ohne Position / über der Kappe: no-op.
    expect(bananenBoersePlugin.reduce(s, aktion("p1", { type: "verkaufen" }, 1_100), ctx)).toBe(s);
  });

  it("Umschichtung: Verkauf + Neukauf rechnet Spread UND neue Position kumulativ", () => {
    const { clock, ctx, state } = setup();
    // Kauf Option 2 (falsch), Panik-Verkauf, Neukauf Option 0 (richtig) im Block 1.
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 2 }, 500),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p1", { type: "verkaufen" }, 4_000),
      ctx,
    ) as BananenBoerseState;
    clock.advance(5_200);
    s = bananenBoersePlugin.tick(s, ctx) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p1", { type: "answer", choice: 0 }, clock.now()),
      ctx,
    ) as BananenBoerseState;
    expect(s.positionen.p1?.quote).toBe(3.0); // Block 1: niemand hält Option 0
    s = schluss(s, ctx, clock);
    // −30 (Spread) + 250 (Gewinn zur Quote 3,0) = 220.
    expect(bananenBoersePlugin.scores(s)[asPlayerId("p1")]).toBe(220);
    // Nach der Umschichtung ist Schluss: kein zweiter Verkauf mehr.
  });

  it("Kauf ohne Verkauf der offenen Position ist gesperrt (erst glattstellen)", () => {
    const { ctx, state } = setup();
    const s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 1 }, 500),
      ctx,
    ) as BananenBoerseState;
    expect(
      bananenBoersePlugin.reduce(s, aktion("p1", { type: "answer", choice: 0 }, 600), ctx),
    ).toBe(s);
  });

  it("Börsenschluss ist hart: Kauf/Verkauf danach verworfen; KEIN Early-Finish", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3", "p4"]) {
      s = bananenBoersePlugin.reduce(
        s,
        aktion(p, { type: "answer", choice: 0 }, 500),
        ctx,
      ) as BananenBoerseState;
    }
    clock.advance(10_000); // alle investiert, aber Verkaufen bleibt eine Option
    s = bananenBoersePlugin.tick(s, ctx) as BananenBoerseState;
    expect(bananenBoersePlugin.isFinished(s)).toBe(false);
    expect(
      bananenBoersePlugin.reduce(s, aktion("p1", { type: "verkaufen" }, s.endetAt + 1), ctx),
    ).toBe(s);
    s = schluss(s, ctx, clock);
    expect(bananenBoersePlugin.isFinished(s)).toBe(true);
  });

  it("Chart wächst bis Börsenschluss auf alle 4 Block-Snapshots (idempotent)", () => {
    const { clock, ctx, state } = setup();
    expect(state.kursBloecke).toHaveLength(1);
    let s = bananenBoersePlugin.tick(state, ctx) as BananenBoerseState;
    s = bananenBoersePlugin.tick(s, ctx) as BananenBoerseState; // Doppel-Tick: kein Doppel-Snapshot
    expect(s.kursBloecke).toHaveLength(1);
    s = schluss(s, ctx, clock);
    expect(s.kursBloecke).toHaveLength(BOERSE_BLOECKE);
  });

  it("Disconnect: offene Position bleibt im Markt und wird normal abgerechnet", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 500),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.onDisconnect(s, asPlayerId("p1"), ctx) as BananenBoerseState;
    s = schluss(s, ctx, clock);
    expect(bananenBoersePlugin.scores(s)[asPlayerId("p1")]).toBe(250);
  });

  it("GM: force.finish rechnet sofort ab, timer.extend verschiebt den Schluss", () => {
    const { ctx, state } = setup();
    const extend: GmAction = { kind: "gm", type: "timer.extend", ms: 5_000 };
    expect((bananenBoersePlugin.reduce(state, extend, ctx) as BananenBoerseState).endetAt).toBe(
      state.endetAt + 5_000,
    );
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    expect(
      bananenBoersePlugin.isFinished(
        bananenBoersePlugin.reduce(state, skip, ctx) as BananenBoerseState,
      ),
    ).toBe(true);
  });

  it("timerFaktor 0,5: Fenster + Block-Länge skalieren gemeinsam", () => {
    const { state } = setup("medium", { timerFaktor: 0.5 });
    expect(state.timerMs).toBe(BOERSE_HANDEL_MS / 2);
    expect(state.blockMs).toBe(BOERSE_HANDEL_MS / 2 / BOERSE_BLOECKE);
  });

  it("outcomes: offene Position = Urteil, glattgestellt/nie gehandelt = null", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBoersePlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 700),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p2", { type: "answer", choice: 3 }, 800),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p3", { type: "answer", choice: 0 }, 900),
      ctx,
    ) as BananenBoerseState;
    s = bananenBoersePlugin.reduce(
      s,
      aktion("p3", { type: "verkaufen" }, 1_000),
      ctx,
    ) as BananenBoerseState;
    s = schluss(s, ctx, clock);
    const outcomes = bananenBoersePlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")]).toEqual({ correct: true, nachMs: 700 });
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBeNull(); // glattgestellt
    expect(outcomes[asPlayerId("p4")].correct).toBeNull(); // nie gehandelt
  });

  it("Leak-Wache: correctIndex nur im GM-View; Positionen sind bewusst public", () => {
    const { ctx, state } = setup();
    const s = bananenBoersePlugin.reduce(
      state,
      aktion("p2", { type: "answer", choice: 1 }, 500),
      ctx,
    ) as BananenBoerseState;
    const player = bananenBoersePlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(player.correctIndex).toBeUndefined();
    expect(player.positionen).toEqual({ p2: { option: 1, quote: 3.0 } }); // Herden-Info
    const gm = bananenBoersePlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(0);
  });
});
