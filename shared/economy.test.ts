// Ökonomie-Goldens: konkrete Zahlen aus GAME-DESIGN §3 als eingefrorene Verträge.
import { describe, expect, it } from "vitest";
import {
  atFuerEndstand,
  finaleDelta,
  istPfandflaschenModus,
  kappeRueckenwindExtra,
  klemmeAufDispo,
  rueckenwindFaktor,
  rundeAuf10,
  rundeAuf50Hoch,
  sozialrabattFaktor,
  streakFaktor,
  wFinal,
} from "./economy";
import { JOKER, jokerPreis } from "./jokers";
import { FRAGE_WERTE, fragenGewinn, speedBonus } from "./money";

describe("economy: Grundwerte + Speed-Bonus (§3.1)", () => {
  it("Grundwerte: 100/250/500/1000", () => {
    expect(FRAGE_WERTE).toEqual({ easy: 100, medium: 250, hard: 500, ultrahard: 1000 });
  });

  it("voller Speed-Bonus (+50 %) nur in den ersten 20 % der Zeit", () => {
    // MEDIUM (250, 15 s): Antwort nach 2 s ⇒ (15−2)/12 > 1 ⇒ +125 → gerundet 130.
    expect(speedBonus(250, 2_000, 15_000)).toBe(130);
    // Antwort auf den letzten Drücker ⇒ Bonus 0.
    expect(speedBonus(250, 15_000, 15_000)).toBe(0);
    // Blind-Tipp-Exploit-Schutz: Bonus fällt LINEAR, nie negativ.
    expect(speedBonus(250, 20_000, 15_000)).toBe(0);
    // HARD (500, 20 s) nach 3 s ⇒ voller Bonus +250.
    expect(fragenGewinn("hard", 3_000, 20_000)).toBe(750);
  });
});

describe("economy: Streak-Multiplikator (§3.1)", () => {
  it("×1 bis Streak 2, ×1,5 ab 3, ×2,0 ab 5 — harte Kappe ×2", () => {
    expect(streakFaktor(1)).toBe(1.0);
    expect(streakFaktor(2)).toBe(1.0);
    expect(streakFaktor(3)).toBe(1.5);
    expect(streakFaktor(4)).toBe(1.5);
    expect(streakFaktor(5)).toBe(2.0);
    expect(streakFaktor(99)).toBe(2.0);
  });
});

describe("economy: Rückenwind + Überhol-Kappe (§3.4)", () => {
  it(">40 % Rückstand ⇒ ×1,25 · >60 % ⇒ ×1,5", () => {
    expect(rueckenwindFaktor(1000, 1000)).toBe(1.0);
    expect(rueckenwindFaktor(601, 1000)).toBe(1.0); // 39,9 % — kein Wind
    expect(rueckenwindFaktor(599, 1000)).toBe(1.25); // 40,1 %
    expect(rueckenwindFaktor(399, 1000)).toBe(1.5); // 60,1 %
    expect(rueckenwindFaktor(0, 0)).toBe(1.0); // niemand führt ⇒ kein Wind
  });

  it("Kappe: der ZUSATZgewinn katapultiert nie über den Vordermann", () => {
    // Basisbuchung bringt den Underdog auf 900, Vordermann steht bei 950:
    // vom Extra (200) bleiben nur 50 übrig.
    expect(kappeRueckenwindExtra(200, 900, 950)).toBe(50);
    // Vordermann schon überholt (durch die BASIS) ⇒ Extra 0, nie negativ.
    expect(kappeRueckenwindExtra(200, 1000, 950)).toBe(0);
    // Genug Luft ⇒ Extra bleibt voll erhalten.
    expect(kappeRueckenwindExtra(200, 500, 950)).toBe(200);
  });
});

describe("economy: Finale-Formel W_final (§3.5)", () => {
  it("W = max(500, aufrunden(faktor × G / Q, 50er))", () => {
    expect(wFinal(6000, 5, 1.25)).toBe(1500);
    expect(wFinal(6100, 5, 1.25)).toBe(1550); // 1525 → 50er-AUFrundung
    expect(wFinal(1000, 5, 1.25)).toBe(500); // Untergrenze
    expect(wFinal(6000, 5, 1.0)).toBe(1200); // streng
    expect(wFinal(6000, 5, 1.5)).toBe(1800); // Chaos
    expect(wFinal(6000, 0, 1.25)).toBe(500); // Q=0 abgesichert
  });

  it("Finale-Buchung: richtig +W, falsch −W/2, keine Antwort 0", () => {
    expect(finaleDelta(true, 1500)).toBe(1500);
    expect(finaleDelta(false, 1500)).toBe(-750);
    expect(finaleDelta(null, 1500)).toBe(0);
  });
});

describe("economy: Dispo + Pfandflaschen-Modus (§3.2)", () => {
  it("Konto fällt nie unter −500", () => {
    expect(klemmeAufDispo(-9999)).toBe(-500);
    expect(klemmeAufDispo(100)).toBe(100);
  });

  it("Pfandflaschen-Modus greift AM Limit", () => {
    expect(istPfandflaschenModus(-500)).toBe(true);
    expect(istPfandflaschenModus(-499)).toBe(false);
  });
});

describe("economy: All-Time-Umrechnung (§3.6) + Rundungen", () => {
  it("AT = Endstand/10 (mind. 50), Sieger ×1,5", () => {
    expect(atFuerEndstand(4370, false)).toBe(437);
    expect(atFuerEndstand(4370, true)).toBe(656); // 437 × 1,5 = 655,5 → 656
    expect(atFuerEndstand(120, false)).toBe(50); // Mindest-AT
    expect(atFuerEndstand(-300, false)).toBe(50); // nie negativ
  });

  it("Rundungshelfer: 10er kaufmännisch, 50er aufwärts", () => {
    expect(rundeAuf10(87.5)).toBe(90);
    expect(rundeAuf10(84)).toBe(80);
    expect(rundeAuf50Hoch(1525)).toBe(1550);
    expect(rundeAuf50Hoch(1500)).toBe(1500);
  });
});

describe("economy: Sozialrabatt + Joker-Preise (§3.4/§5.1)", () => {
  it("untere Hälfte −30 %, Letzter −50 %", () => {
    expect(sozialrabattFaktor(1, 8)).toBe(1.0);
    expect(sozialrabattFaktor(4, 8)).toBe(1.0);
    expect(sozialrabattFaktor(5, 8)).toBe(0.7);
    expect(sozialrabattFaktor(8, 8)).toBe(0.5);
    expect(sozialrabattFaktor(2, 2)).toBe(0.5); // bei 2 Spielern ist der 2. „Letzter"
  });

  it("Joker-Preisformeln: Prozent vom Fragenwert/Konto, auf 10er gerundet", () => {
    // Bananen-Split: 40 % von HARD (500) = 200; mit Letzter-Rabatt 100.
    expect(jokerPreis(JOKER["bananen-split"], 500, 0)).toBe(200);
    expect(jokerPreis(JOKER["bananen-split"], 500, 0, 0.5)).toBe(100);
    // Schmiergeld: Stufe 1 = 25 %, Stufe 2 = 35 % (MEDIUM 250 → 62,5 → 60 / 87,5 → 90).
    expect(jokerPreis(JOKER.schmiergeld, 250, 0, 1, 1)).toBe(60);
    expect(jokerPreis(JOKER.schmiergeld, 250, 0, 1, 2)).toBe(90);
    // Bananentresor: 10 % vom Konto (nie negativ).
    expect(jokerPreis(JOKER.bananentresor, 0, 2340)).toBe(230);
    expect(jokerPreis(JOKER.bananentresor, 0, -400)).toBe(0);
    // Goldene Banane: gratis; Überziehungskredit: flat 150.
    expect(jokerPreis(JOKER["goldene-banane"], 500, 0)).toBe(0);
    expect(jokerPreis(JOKER.ueberziehungskredit, 500, 0)).toBe(150);
  });
});
