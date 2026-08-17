// Geld-Wahrheit der Jackpot-Frage (§1.1 Phase 4) × Rückgaberecht (Befund-Fix):
// Zweitversuch zahlt den HALBEN Jackpot — Festwert 1.000 statt 2.000, und beim
// Glas-Knacken nur die Hälfte des Inhalts (der Rest bleibt drin, §5.1-Geist).
import { describe, expect, it } from "vitest";
import { createRng } from "../../shared/rng";
import { bucheFrage, type BuchungsOptionen } from "./scoring";
import type { PlayerState } from "./types";

function spieler(id: string, name: string): PlayerState {
  return {
    id,
    name,
    avatar: "gelb",
    connected: true,
    graceUntil: null,
    balance: 0,
    streak: 0,
    maxStreak: 0,
    jokers: {},
    jokerKaeufe: {},
    schildBisRunde: null,
    schildZuletztRunde: null,
    clownBisRunde: null,
    rueckenwindAngekuendigt: false,
    richtigGesamt: 0,
  };
}

function jackpotOpts(patch: Partial<BuchungsOptionen> = {}): BuchungsOptionen {
  return {
    questionId: "q_jackpot",
    scores: {},
    outcomes: null,
    order: ["p1", "p2"],
    streakEligible: true,
    hintStufe: 0,
    modifiers: [],
    pott: 0,
    jackpotGlas: 800,
    strafenInsGlas: false,
    frageWert: 500,
    rng: createRng(1),
    modus: "jackpot",
    ...patch,
  };
}

const zwei = () => ({ p1: spieler("p1", "Anna"), p2: spieler("p2", "Ben") });

describe("scoring: Jackpot-Frage × Rückgaberecht (Zweitversuch zahlt 50 %)", () => {
  it("Erstversuch: +2.000 fix, der Schnellste knackt das GANZE Glas", () => {
    const r = bucheFrage(
      zwei(),
      jackpotOpts({
        outcomes: {
          p1: { correct: true, nachMs: 1_000 },
          p2: { correct: false, nachMs: 2_000 },
        },
      }),
    );
    expect(r.players.p1.balance).toBe(2000 + 800);
    expect(r.players.p2.balance).toBe(0);
    expect(r.jackpotGlas).toBe(0); // leergeräumt
  });

  it("Zweitversuch: +1.000 fix und nur der HALBE Glas-Inhalt — der Rest bleibt drin", () => {
    const r = bucheFrage(
      zwei(),
      jackpotOpts({
        outcomes: {
          p1: { correct: true, nachMs: 1_000, zweitversuch: true },
          p2: { correct: false, nachMs: 2_000 },
        },
      }),
    );
    expect(r.players.p1.balance).toBe(1000 + 400);
    expect(r.jackpotGlas).toBe(400); // Hälfte bleibt im Glas
  });

  it("Zweitversuch-Malus trifft NUR den Zweitversuch-Spieler, nicht die anderen", () => {
    const r = bucheFrage(
      zwei(),
      jackpotOpts({
        outcomes: {
          // p1 richtig im Erstversuch, aber LANGSAMER — p2 (Zweitversuch) knackt das Glas.
          p1: { correct: true, nachMs: 3_000 },
          p2: { correct: true, nachMs: 1_000, zweitversuch: true },
        },
      }),
    );
    expect(r.players.p1.balance).toBe(2000); // voller Festwert, kein Glas
    expect(r.players.p2.balance).toBe(1000 + 400); // halber Festwert + halbes Glas
    expect(r.jackpotGlas).toBe(400);
  });
});
