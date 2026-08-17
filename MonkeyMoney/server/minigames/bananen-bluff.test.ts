// Bananen-Bluff: exakte Payoff-Mathe (W/2-Prämien + Nullsummen-Transfer beim
// Reinfallen — Invariante Σ deltas === Bank-Prämien), Ehrlichkeits-Prämie mit
// Mehrheits-Regel, Auto-Wahrheit (Timeout + Verkünder-Disconnect) OHNE
// Prämien-Anspruch, Verkünder-Rotation über die Runde, Stimm-Locks,
// Early-Auswertung, Leak-Wache (nur der Verkünder sieht die Wahrheit).
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  BB_AUFDECKUNG_MS,
  BB_RATEN_MS,
  BB_VERKUENDEN_MS,
  bbPraemie,
} from "../../shared/minigames/bananen-bluff.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { bananenBluffPlugin, type BananenBluffState } from "./bananen-bluff/index";

function frage(nr: number, difficulty: Question["difficulty"] = "medium"): Question {
  return {
    id: `q_bb_${nr}`,
    kind: "choice4",
    category: "affen_fakten",
    difficulty,
    text: `Behauptung Nr. ${nr}?`,
    options: ["Alpha", "Bravo", "Charlie", "Delta"],
    answer: 2,
    erklaerung: "Charlie war es.",
  };
}

function setup(fragen = 2, difficulty: Question["difficulty"] = "medium") {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(11) };
  const spieler = ["p1", "p2", "p3", "p4"].map(asPlayerId);
  const content: ContentSlice = {
    questions: [...Array(fragen)].map((_, i) => frage(i + 1, difficulty)),
  };
  const state = bananenBluffPlugin.init(spieler, content, ctx) as BananenBluffState;
  return { clock, ctx, state, spieler };
}

type BbAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

function antwort(playerId: string, choice: number, at: number): PlayerAction<BbAction> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "answer", choice: choice as 0 | 1 | 2 | 3 },
    atServerTime: at,
  };
}

/** Aufdeckung überspulen (nächste Frage bzw. Runden-Ende). */
function weiter(s: BananenBluffState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndetAt - clock.now()) + 1);
  return bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
}

describe("bananen-bluff: Payoff-Mathe (exakt, W/2 = 125 bei medium)", () => {
  it("Bluff: Reingefallene zahlen an den Verkünder (Nullsummen-Transfer), Detektive kassieren die Bank", () => {
    const { ctx, state } = setup();
    // p1 verkündet einen BLUFF (Option 0 statt 2).
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    expect(s.phase).toBe("raten");
    s = bananenBluffPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBluffState; // WAHR → reingefallen
    s = bananenBluffPlugin.reduce(s, antwort("p3", 1, 3_000), ctx) as BananenBluffState; // GELOGEN → Detektiv
    s = bananenBluffPlugin.reduce(s, antwort("p4", 0, 4_000), ctx) as BananenBluffState; // reingefallen
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState; // alle Rater fertig
    expect(s.phase).toBe("aufdeckung");
    expect(s.deltas).toEqual({ p1: 250, p2: -125, p3: 125, p4: -125 });
    // Invariante: Σ deltas === Bank-Prämien (Transfers heben sich exakt auf).
    const summe = Object.values(s.deltas).reduce((a, b) => a + b, 0);
    expect(summe).toBe(s.bankPraemien);
    expect(s.bankPraemien).toBe(125); // nur p3s Detektiv-Prämie kam von der Bank
  });

  it("Wahrheit + strikte Mehrheit glaubt = Ehrlichkeits-Prämie; Misstrauische verlieren NICHTS", () => {
    const { ctx, state } = setup();
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 2, 1_000), ctx) as BananenBluffState; // Wahrheit
    s = bananenBluffPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBluffState; // glaubt → +125
    s = bananenBluffPlugin.reduce(s, antwort("p3", 0, 3_000), ctx) as BananenBluffState; // glaubt → +125
    s = bananenBluffPlugin.reduce(s, antwort("p4", 1, 4_000), ctx) as BananenBluffState; // misstraut → 0
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.deltas).toEqual({ p1: 125, p2: 125, p3: 125 });
    expect(s.historie[0].ehrlichkeitsPraemie).toBe(true);
    const summe = Object.values(s.deltas).reduce((a, b) => a + b, 0);
    expect(summe).toBe(s.bankPraemien);
  });

  it("Wahrheit ohne Mehrheit (1 glaubt, 2 misstrauen) = keine Ehrlichkeits-Prämie", () => {
    const { ctx, state } = setup();
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 2, 1_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBluffState; // +125
    s = bananenBluffPlugin.reduce(s, antwort("p3", 1, 3_000), ctx) as BananenBluffState; // 0
    s = bananenBluffPlugin.reduce(s, antwort("p4", 1, 4_000), ctx) as BananenBluffState; // 0
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.deltas.p1 ?? 0).toBe(0);
    expect(s.historie[0].ehrlichkeitsPraemie).toBe(false);
  });

  it("Voller Bluff-Erfolg ist EXAKT nullsummig (alle reingefallen, keine Bank-Prämie)", () => {
    const { ctx, state } = setup();
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 3, 1_000), ctx) as BananenBluffState;
    for (const p of ["p2", "p3", "p4"]) {
      s = bananenBluffPlugin.reduce(s, antwort(p, 0, 2_000), ctx) as BananenBluffState;
    }
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.deltas).toEqual({ p1: 375, p2: -125, p3: -125, p4: -125 });
    expect(s.bankPraemien).toBe(0);
    expect(Object.values(s.deltas).reduce((a, b) => a + b, 0)).toBe(0);
  });

  it("Prämien-Goldens: W/2 über alle Schwierigkeiten (50/125/250/500)", () => {
    expect(bbPraemie(100)).toBe(50);
    expect(bbPraemie(250)).toBe(125);
    expect(bbPraemie(500)).toBe(250);
    expect(bbPraemie(1000)).toBe(500);
    const { ctx, state } = setup(1, "ultrahard");
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p3", 1, 2_500), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p4", 1, 3_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.deltas).toEqual({ p1: 500, p2: -500, p3: 500, p4: 500 });
  });
});

describe("bananen-bluff: Auto-Wahrheit + Rotation + Fenster", () => {
  it("Verkünden-Timeout ⇒ Auto-Wahrheit OHNE Ehrlichkeits-Prämie (trotz Mehrheit)", () => {
    const { clock, ctx, state } = setup();
    clock.advance(BB_VERKUENDEN_MS + 1);
    let s = bananenBluffPlugin.tick(state, ctx) as BananenBluffState;
    expect(s.phase).toBe("raten");
    expect(s.ansage).toEqual({ option: 2, auto: true });
    for (const p of ["p2", "p3", "p4"]) {
      s = bananenBluffPlugin.reduce(s, antwort(p, 0, clock.now() + 500), ctx) as BananenBluffState;
    }
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.deltas.p1 ?? 0).toBe(0); // keine Prämie für die Auto-Wahrheit
    expect(s.deltas.p2).toBe(125);
  });

  it("Verkünder-Disconnect im Verkünden ⇒ sofort Raten mit Auto-Wahrheit", () => {
    const { ctx, state } = setup();
    const s = bananenBluffPlugin.onDisconnect(state, asPlayerId("p1"), ctx) as BananenBluffState;
    expect(s.phase).toBe("raten");
    expect(s.ansage).toEqual({ option: 2, auto: true });
  });

  it("Rotation: nach der Aufdeckung verkündet der nächste Affe der Reihe", () => {
    const { clock, ctx, state } = setup(2);
    expect(state.verkuender).toBe("p1");
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 2, 1_000), ctx) as BananenBluffState;
    for (const p of ["p2", "p3", "p4"]) {
      s = bananenBluffPlugin.reduce(s, antwort(p, 0, 2_000), ctx) as BananenBluffState;
    }
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState; // → aufdeckung
    s = weiter(s, ctx, clock); // → Frage 2
    expect(s.frageIndex).toBe(1);
    expect(s.verkuender).toBe("p2");
    expect(s.phase).toBe("verkuenden");
  });

  it("Nur der Verkünder verkündet, Rater raten erst im Rate-Fenster, Stimmen rasten ein", () => {
    const { ctx, state } = setup();
    // Rater darf nicht verkünden:
    expect(bananenBluffPlugin.reduce(state, antwort("p2", 0, 500), ctx)).toBe(state);
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 2, 1_000), ctx) as BananenBluffState;
    // Verkünder darf nicht mitraten:
    expect(bananenBluffPlugin.reduce(s, antwort("p1", 0, 2_000), ctx)).toBe(s);
    s = bananenBluffPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBluffState;
    // Erste Stimme zählt — Umentscheiden ist gesperrt:
    expect(bananenBluffPlugin.reduce(s, antwort("p2", 1, 3_000), ctx)).toBe(s);
    // Nur 0/1 sind gültige Urteile:
    expect(bananenBluffPlugin.reduce(s, antwort("p3", 3, 3_000), ctx)).toBe(s);
  });

  it("Stimme nach dem Rate-Fenster wird verworfen; Timeout wertet trotzdem aus", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    const zuSpaet = s.phaseEndetAt + 1;
    expect(bananenBluffPlugin.reduce(s, antwort("p2", 0, zuSpaet), ctx)).toBe(s);
    clock.advance(BB_VERKUENDEN_MS + BB_RATEN_MS + 2);
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.phase).toBe("aufdeckung");
    // Niemand hat gestimmt: keine Transfers, keine Prämien.
    expect(s.deltas).toEqual({});
    expect(s.bankPraemien).toBe(0);
  });

  it("Offline-Rater blockiert die Early-Auswertung nicht und bekommt 0", () => {
    const { ctx, state } = setup();
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.onDisconnect(s, asPlayerId("p4"), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p2", 1, 2_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p3", 1, 2_500), ctx) as BananenBluffState;
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(s.phase).toBe("aufdeckung");
    expect(s.deltas.p4 ?? 0).toBe(0);
  });

  it("Runde über 2 Fragen: scores() = kumulierte Deltas, isFinished erst am Ende", () => {
    const { clock, ctx, state } = setup(2);
    // F1: p1 blufft, alle fallen rein (+375 / −125 ×3).
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    for (const p of ["p2", "p3", "p4"]) {
      s = bananenBluffPlugin.reduce(s, antwort(p, 0, 2_000), ctx) as BananenBluffState;
    }
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(bananenBluffPlugin.isFinished(s)).toBe(false);
    s = weiter(s, ctx, clock); // → F2, Verkünder p2
    // F2: p2 sagt die Wahrheit, alle glauben (+125 ×4).
    s = bananenBluffPlugin.reduce(s, antwort("p2", 2, clock.now() + 500), ctx) as BananenBluffState;
    for (const p of ["p1", "p3", "p4"]) {
      s = bananenBluffPlugin.reduce(
        s,
        antwort(p, 0, clock.now() + 1_000),
        ctx,
      ) as BananenBluffState;
    }
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState; // → aufdeckung
    clock.advance(BB_AUFDECKUNG_MS + 1);
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    expect(bananenBluffPlugin.isFinished(s)).toBe(true);
    // p2: −125 (F1 reingefallen) + 125 (F2 Ehrlichkeits-Prämie) = 0.
    expect(bananenBluffPlugin.scores(s)).toEqual({ p1: 500, p2: 0, p3: 0, p4: 0 });
    // Invariante über die GANZE Runde: Σ scores === Σ Bank-Prämien.
    const summe = Object.values(bananenBluffPlugin.scores(s)).reduce((a, b) => a + b, 0);
    expect(summe).toBe(s.bankPraemien);
  });

  it("GM force.finish friert nur bereits aufgedeckte Payoffs ein", () => {
    const { ctx, state } = setup(2);
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBluffState;
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    const fertig = bananenBluffPlugin.reduce(s, skip, ctx) as BananenBluffState;
    expect(bananenBluffPlugin.isFinished(fertig)).toBe(true);
    // Das Rate-Fenster war noch offen — nichts wurde gebucht.
    expect(bananenBluffPlugin.scores(fertig)).toEqual({ p1: 0, p2: 0, p3: 0, p4: 0 });
  });
});

describe("bananen-bluff: Leak-Wache + outcomes", () => {
  it("NUR der Verkünder sieht Optionen + Wahrheit; Rater sehen die 2 Urteils-Buttons", () => {
    const { ctx, state } = setup();
    const verkuenderView = bananenBluffPlugin.viewFor(state, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(verkuenderView.options).toHaveLength(4);
    expect(verkuenderView.correctIndex).toBe(2);
    const raterView = bananenBluffPlugin.viewFor(state, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(raterView.options).toBeNull();
    expect(raterView.correctIndex).toBeUndefined();
    // Im Rate-Fenster: Ansage-TEXT public, Urteils-Buttons für Rater.
    const s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    const raten = bananenBluffPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(raten.ansageText).toBe("Alpha");
    expect(raten.options).toHaveLength(2);
    const verkuenderRaten = bananenBluffPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(verkuenderRaten.options).toBeNull(); // Verkünder stimmt nicht mit
    // Screen sieht NIE, ob die Ansage stimmt:
    const screen = bananenBluffPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.correctIndex).toBeUndefined();
    expect(screen.ansage).toBeUndefined();
  });

  it("outcomes: Detektiv-Mehrheit = richtig, Reingefallene = falsch, Unbeteiligte = null", () => {
    const { clock, ctx, state } = setup();
    let s = bananenBluffPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBluffState;
    s = bananenBluffPlugin.reduce(s, antwort("p2", 1, 2_000), ctx) as BananenBluffState; // Detektiv
    s = bananenBluffPlugin.reduce(s, antwort("p3", 0, 3_000), ctx) as BananenBluffState; // reingefallen
    clock.advance(s.phaseEndetAt + 1); // p4 verpennt das Fenster (Timeout-Auswertung)
    s = bananenBluffPlugin.tick(s, ctx) as BananenBluffState;
    const outcomes = bananenBluffPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true); // Bluff hat gefangen
    expect(outcomes[asPlayerId("p2")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].nachMs).toBe(1_000); // 2 000 − Raten-Start
    expect(outcomes[asPlayerId("p3")].correct).toBe(false);
    expect(outcomes[asPlayerId("p4")].correct).toBeNull();
  });
});
