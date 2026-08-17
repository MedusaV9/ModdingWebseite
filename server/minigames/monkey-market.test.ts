// Monkey Market: exakte Falltüren-Mathe (Chips ×2, Mut-Bonus +25 % nur bei
// 10/10, 10er-Rundung), Chip-Kappe + Umschichten, Alles-auf-eins über den
// answer-Draht, Early-Close wenn alle voll platziert, Spätzug-Wache,
// Disconnect (Chips bleiben), GM-Eingriffe, timerFaktor und outcomes-Mehrheit.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  MM_HANDEL_MS,
  MM_MARKT_CHIPS,
  mmAuszahlung,
  mmChipWert,
} from "../../shared/minigames/monkey-market.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { monkeyMarketPlugin, type MonkeyMarketState } from "./monkey-market/index";

function frage(difficulty: Question["difficulty"] = "medium"): Question {
  return {
    id: `q_mm_${difficulty}`,
    kind: "choice4",
    category: "boersen_wissen",
    difficulty,
    text: "Hinter welcher Tür liegt die Wahrheit?",
    options: ["Tür A", "Tür B", "Tür C", "Tür D"],
    answer: 1,
    erklaerung: "Tür B — stand im Prospekt.",
  };
}

function setup(difficulty: Question["difficulty"] = "medium", mods?: ContentSlice["mods"]) {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(7) };
  const spieler = ["p1", "p2", "p3"].map(asPlayerId);
  const content: ContentSlice = mods
    ? { questions: [frage(difficulty)], mods }
    : { questions: [frage(difficulty)] };
  const state = monkeyMarketPlugin.init(spieler, content, ctx) as MonkeyMarketState;
  return { clock, ctx, state, spieler };
}

type MmAction =
  | { type: "chip"; tuer: 0 | 1 | 2 | 3 }
  | { type: "zurueck"; tuer: 0 | 1 | 2 | 3 }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

function aktion(playerId: string, a: MmAction, at: number): PlayerAction<MmAction> {
  return { kind: "player", playerId: asPlayerId(playerId), action: a, atServerTime: at };
}

function fertigTicken(s: MonkeyMarketState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.endetAt - clock.now()) + 1);
  return monkeyMarketPlugin.tick(s, ctx) as MonkeyMarketState;
}

describe("monkey-market: Falltüren-Mathe (exakt)", () => {
  it("Chip-Wert = W/10 je Schwierigkeit (10/25/50/100)", () => {
    expect(mmChipWert(100)).toBe(10);
    expect(mmChipWert(250)).toBe(25);
    expect(mmChipWert(500)).toBe(50);
    expect(mmChipWert(1000)).toBe(100);
    expect(setup("easy").state.chipWert).toBe(10);
    expect(setup("ultrahard").state.chipWert).toBe(100);
  });

  it("Chips auf der richtigen Tür zahlen ×2, falsche verfallen (medium)", () => {
    const { clock, ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(state, aktion("p1", { type: "chip", tuer: 1 }, 500), ctx);
    s = monkeyMarketPlugin.reduce(s, aktion("p1", { type: "chip", tuer: 1 }, 600), ctx);
    s = monkeyMarketPlugin.reduce(s, aktion("p1", { type: "chip", tuer: 1 }, 700), ctx);
    s = monkeyMarketPlugin.reduce(s, aktion("p1", { type: "chip", tuer: 0 }, 800), ctx);
    s = fertigTicken(s as MonkeyMarketState, ctx, clock);
    // 3 Chips richtig × 2 × 25 = 150; der Chip auf Tür A verfällt.
    expect(monkeyMarketPlugin.scores(s)[asPlayerId("p1")]).toBe(150);
  });

  it("ALLES AUF EINS (answer) richtig = ×2 ×1,25 mit 10er-Rundung (medium: 630)", () => {
    const { clock, ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(state, aktion("p1", { type: "answer", choice: 1 }, 500), ctx);
    s = fertigTicken(s as MonkeyMarketState, ctx, clock);
    // 10 × 2 × 25 = 500 · ×1,25 = 625 → rundeAuf10 = 630 (kaufmännisch).
    expect(monkeyMarketPlugin.scores(s)[asPlayerId("p1")]).toBe(630);
    expect(mmAuszahlung(10, 25, true)).toBe(630);
  });

  it("ALLES AUF EINS falsch = 0 (Bank-Chips, kein eigener Verlust)", () => {
    const { clock, ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(state, aktion("p1", { type: "answer", choice: 3 }, 500), ctx);
    s = fertigTicken(s as MonkeyMarketState, ctx, clock);
    expect(monkeyMarketPlugin.scores(s)[asPlayerId("p1")]).toBe(0);
  });

  it("Mut-Bonus NUR bei 10/10 auf der richtigen Tür (9+1 gehedgt: kein Bonus)", () => {
    const { clock, ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(state, aktion("p1", { type: "chip", tuer: 0 }, 400), ctx);
    s = monkeyMarketPlugin.reduce(s, aktion("p1", { type: "answer", choice: 1 }, 500), ctx);
    s = fertigTicken(s as MonkeyMarketState, ctx, clock);
    // 9 richtig × 2 × 25 = 450 — ohne die +25 % (Hedge auf Tür A).
    expect(monkeyMarketPlugin.scores(s)[asPlayerId("p1")]).toBe(450);
  });

  it("Hedge über alle Türen garantiert die halbe Basis (medium: 2/3/2/3 → 150)", () => {
    const { clock, ctx, state } = setup();
    let s = state as MonkeyMarketState;
    const lage: [number, number, number, number] = [2, 3, 2, 3];
    for (let tuer = 0; tuer < 4; tuer++) {
      for (let i = 0; i < lage[tuer]; i++) {
        s = monkeyMarketPlugin.reduce(
          s,
          aktion("p1", { type: "chip", tuer: tuer as 0 | 1 | 2 | 3 }, 500 + tuer * 10 + i),
          ctx,
        ) as MonkeyMarketState;
      }
    }
    s = fertigTicken(s, ctx, clock);
    expect(monkeyMarketPlugin.scores(s)[asPlayerId("p1")]).toBe(150); // 3 × 2 × 25
  });
});

describe("monkey-market: Chip-Regeln + Fenster", () => {
  it("Chip-Kappe 10: der 11. Chip und answer ohne Rest-Chips verpuffen", () => {
    const { ctx, state } = setup();
    const s = monkeyMarketPlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 500),
      ctx,
    ) as MonkeyMarketState;
    expect(s.chips.p1).toEqual([10, 0, 0, 0]);
    const nach11 = monkeyMarketPlugin.reduce(s, aktion("p1", { type: "chip", tuer: 1 }, 600), ctx);
    expect(nach11).toBe(s);
    const nochmalAlles = monkeyMarketPlugin.reduce(
      s,
      aktion("p1", { type: "answer", choice: 1 }, 700),
      ctx,
    );
    expect(nochmalAlles).toBe(s);
  });

  it("zurueck nimmt eigene Chips zurück (Umschichten), bei 0 Chips no-op", () => {
    const { ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(
      state,
      aktion("p1", { type: "chip", tuer: 0 }, 500),
      ctx,
    ) as MonkeyMarketState;
    s = monkeyMarketPlugin.reduce(
      s,
      aktion("p1", { type: "zurueck", tuer: 0 }, 600),
      ctx,
    ) as MonkeyMarketState;
    expect(s.chips.p1).toEqual([0, 0, 0, 0]);
    const nochmal = monkeyMarketPlugin.reduce(
      s,
      aktion("p1", { type: "zurueck", tuer: 0 }, 700),
      ctx,
    );
    expect(nochmal).toBe(s);
  });

  it("Markt schließt FRÜHER, sobald alle Verbundenen voll platziert sind", () => {
    const { clock, ctx, state } = setup();
    let s = state as MonkeyMarketState;
    for (const p of ["p1", "p2", "p3"]) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion(p, { type: "answer", choice: 1 }, 500),
        ctx,
      ) as MonkeyMarketState;
    }
    clock.advance(1_000); // weit vor dem Timer-Ende
    s = monkeyMarketPlugin.tick(s, ctx) as MonkeyMarketState;
    expect(monkeyMarketPlugin.isFinished(s)).toBe(true);
  });

  it("Offline-Spieler blockiert den Early-Close nicht; seine Chips zählen trotzdem", () => {
    const { clock, ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(
      state,
      aktion("p3", { type: "chip", tuer: 1 }, 400),
      ctx,
    ) as MonkeyMarketState;
    s = monkeyMarketPlugin.onDisconnect(s, asPlayerId("p3"), ctx) as MonkeyMarketState;
    for (const p of ["p1", "p2"]) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion(p, { type: "answer", choice: 1 }, 500),
        ctx,
      ) as MonkeyMarketState;
    }
    clock.advance(1_000);
    s = monkeyMarketPlugin.tick(s, ctx) as MonkeyMarketState;
    expect(monkeyMarketPlugin.isFinished(s)).toBe(true);
    // p3s einsamer Chip auf der richtigen Tür zahlt normal: 1 × 2 × 25 = 50.
    expect(monkeyMarketPlugin.scores(s)[asPlayerId("p3")]).toBe(50);
  });

  it("Spätzug nach Handelsschluss + Gnade wird verworfen", () => {
    const { state, ctx } = setup();
    const spaet = monkeyMarketPlugin.reduce(
      state,
      aktion("p1", { type: "chip", tuer: 1 }, state.endetAt + 401),
      ctx,
    );
    expect(spaet).toBe(state);
  });

  it("GM: force.finish beendet sofort, timer.extend verschiebt den Schluss", () => {
    const { state, ctx } = setup();
    const extend: GmAction = { kind: "gm", type: "timer.extend", ms: 10_000 };
    const verlaengert = monkeyMarketPlugin.reduce(state, extend, ctx) as MonkeyMarketState;
    expect(verlaengert.endetAt).toBe(state.endetAt + 10_000);
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    const fertig = monkeyMarketPlugin.reduce(state, skip, ctx) as MonkeyMarketState;
    expect(monkeyMarketPlugin.isFinished(fertig)).toBe(true);
  });

  it("timerFaktor 0,5 halbiert das Handels-Fenster", () => {
    const { state } = setup("medium", { timerFaktor: 0.5 });
    expect(state.timerMs).toBe(MM_HANDEL_MS / 2);
  });
});

describe("monkey-market: outcomes + Leak-Wache", () => {
  it("outcomes: strikte Chip-Mehrheit = richtig, 50:50 = falsch, 0 Chips = null", () => {
    const { clock, ctx, state } = setup();
    let s = state as MonkeyMarketState;
    // p1: 6 richtig / 4 falsch → correct. p2: 5/5 → false. p3: nichts → null.
    for (let i = 0; i < 6; i++) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion("p1", { type: "chip", tuer: 1 }, 500 + i),
        ctx,
      ) as MonkeyMarketState;
    }
    for (let i = 0; i < 4; i++) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion("p1", { type: "chip", tuer: 2 }, 600 + i),
        ctx,
      ) as MonkeyMarketState;
    }
    for (let i = 0; i < 5; i++) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion("p2", { type: "chip", tuer: 1 }, 700 + i),
        ctx,
      ) as MonkeyMarketState;
    }
    for (let i = 0; i < 5; i++) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion("p2", { type: "chip", tuer: 3 }, 800 + i),
        ctx,
      ) as MonkeyMarketState;
    }
    s = fertigTicken(s, ctx, clock);
    const outcomes = monkeyMarketPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBeNull();
    expect(outcomes[asPlayerId("p1")].nachMs).toBe(603); // letzter eigener Zug
  });

  it("Player-View leakt weder correctIndex noch fremde Chip-Lagen", () => {
    const { ctx, state } = setup();
    const s = monkeyMarketPlugin.reduce(
      state,
      aktion("p2", { type: "chip", tuer: 1 }, 500),
      ctx,
    ) as MonkeyMarketState;
    const view = monkeyMarketPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(view.correctIndex).toBeUndefined();
    expect(view.chips).toBeUndefined();
    expect(view.tuerSummen).toEqual([0, 1, 0, 0]); // Markt-Getümmel ist public
    expect(view.yourChips).toEqual([0, 0, 0, 0]);
    const gm = monkeyMarketPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
  });

  it("scores() aller Spieler ist nie negativ (mildes Geld-Format)", () => {
    const { clock, ctx, state } = setup();
    let s = monkeyMarketPlugin.reduce(
      state,
      aktion("p1", { type: "answer", choice: 0 }, 500),
      ctx,
    ) as MonkeyMarketState;
    s = fertigTicken(s, ctx, clock);
    for (const delta of Object.values(monkeyMarketPlugin.scores(s))) {
      expect(delta).toBeGreaterThanOrEqual(0);
    }
  });

  it("MM_MARKT_CHIPS bleibt die Bilanz-Basis: platzierte Chips ≤ 10 in jeder Lage", () => {
    const { ctx, state } = setup();
    let s = state as MonkeyMarketState;
    for (let i = 0; i < 14; i++) {
      s = monkeyMarketPlugin.reduce(
        s,
        aktion("p1", { type: "chip", tuer: (i % 4) as 0 | 1 | 2 | 3 }, 500 + i),
        ctx,
      ) as MonkeyMarketState;
    }
    const c = s.chips.p1;
    expect(c[0] + c[1] + c[2] + c[3]).toBe(MM_MARKT_CHIPS);
  });
});
