// Speed-Bonus + Grundwerte (GAME-DESIGN §3.1) — pure Funktionen, Seed = Testfall.
import { describe, expect, it } from "vitest";
import { FRAGE_WERTE, formatMM, fragenGewinn, speedBonus } from "./money";

describe("money: Grundwerte", () => {
  it("kennt die verbindlichen Frage-Werte 100/250/500/1000", () => {
    expect(FRAGE_WERTE.easy).toBe(100);
    expect(FRAGE_WERTE.medium).toBe(250);
    expect(FRAGE_WERTE.hard).toBe(500);
    expect(FRAGE_WERTE.ultrahard).toBe(1000);
  });
});

describe("money: speedBonus", () => {
  it("gibt volle +50 % bei Sofort-Antwort", () => {
    expect(speedBonus(100, 0, 15_000)).toBe(50);
  });

  it("gibt volle +50 % bis 20 % der Zeit (Lese-Zeit frei)", () => {
    expect(speedBonus(100, 3_000, 15_000)).toBe(50); // exakt 20 %
  });

  it("fällt danach linear und erreicht 0 am Timer-Ende", () => {
    const mitte = speedBonus(100, 9_000, 15_000); // 60 % der Zeit → (15−9)/12 = 0,5
    expect(mitte).toBe(30); // 100 × 0,5 × 0,5 = 25 → auf 10er gerundet = 30
    expect(speedBonus(100, 15_000, 15_000)).toBe(0);
  });

  it("clampt Spätantworten im Gnadenfenster auf 0 (nie negativ)", () => {
    expect(speedBonus(100, 15_400, 15_000)).toBe(0);
  });

  it("rundet auf 10er (MEDIUM-Beispiel)", () => {
    // 250 × 0,5 × ((15−6)/12 = 0,75) = 93,75 → 90
    expect(speedBonus(250, 6_000, 15_000)).toBe(90);
  });
});

describe("money: fragenGewinn + Format", () => {
  it("summiert Grundwert + Bonus", () => {
    expect(fragenGewinn("easy", 0, 15_000)).toBe(150);
  });

  it("formatiert MM mit deutschem Tausenderpunkt", () => {
    expect(formatMM(1234)).toBe("1.234 MM");
  });
});
