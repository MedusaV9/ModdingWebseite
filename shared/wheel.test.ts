// Glücksrad-Goldens (GAME-DESIGN §5.3): 14 Segmente / Gewichte = 100 %,
// Kompatibilitäts-Matrix, Pity-Timer, deterministische Ziehung per Seed.
import { describe, expect, it } from "vitest";
import { createRng } from "./rng";
import {
  RAD_PITY_AB_DREHS,
  RAD_SEGMENTE,
  baueRadAnzeige,
  effektiveGewichte,
  kompatibleSegmente,
  zieheSegment,
  type RadKontext,
} from "./wheel";

const basisKontext = (patch: Partial<RadKontext> = {}): RadKontext => ({
  fairFinale: false,
  letztesSegment: null,
  drehsOhneGold: 0,
  jemandUnter200: false,
  naechsteRundeMc: true,
  spielerzahl: 4,
  ...patch,
});

describe("wheel: Katalog-Invarianten (§5.3)", () => {
  it("genau 14 Segmente, Gewichte summieren auf 100 %", () => {
    expect(RAD_SEGMENTE).toHaveLength(14);
    expect(RAD_SEGMENTE.reduce((sum, s) => sum + s.gewicht, 0)).toBe(100);
  });

  it("Klassen-Verteilung: 3× grün (13 %), 7× blau (7 %), 4× gold (3 %)", () => {
    const gruen = RAD_SEGMENTE.filter((s) => s.klasse === "gruen");
    const blau = RAD_SEGMENTE.filter((s) => s.klasse === "blau");
    const gold = RAD_SEGMENTE.filter((s) => s.klasse === "gold");
    expect(gruen).toHaveLength(3);
    expect(blau).toHaveLength(7);
    expect(gold).toHaveLength(4);
    expect(gruen.every((s) => s.gewicht === 13)).toBe(true);
    expect(blau.every((s) => s.gewicht === 7)).toBe(true);
    expect(gold.every((s) => s.gewicht === 3)).toBe(true);
  });
});

describe("wheel: Kompatibilitäts-Matrix", () => {
  it("Fair-Finale-Pool: nur die als fairFinale markierten Segmente", () => {
    const pool = kompatibleSegmente(basisKontext({ fairFinale: true }));
    expect(pool.every((s) => s.fairFinale)).toBe(true);
    expect(pool.map((s) => s.id)).toContain("banana-bailout");
    expect(pool.map((s) => s.id)).not.toContain("tausch-boerse");
    expect(pool.map((s) => s.id)).not.toContain("inflation");
  });

  it("Pech-Schutz: das letzte Segment fliegt aus dem Pool", () => {
    const pool = kompatibleSegmente(basisKontext({ letztesSegment: "doppelter-zaster" }));
    expect(pool.map((s) => s.id)).not.toContain("doppelter-zaster");
  });

  it("brauchtMcFrage-Segmente fliegen raus, wenn die nächste Runde kein MC ist", () => {
    const pool = kompatibleSegmente(basisKontext({ naechsteRundeMc: false }));
    expect(pool.map((s) => s.id)).not.toContain("halbe-miete");
    expect(pool.map((s) => s.id)).not.toContain("boersen-roulette");
    expect(pool.map((s) => s.id)).toContain("doppelter-zaster");
  });

  it("Inflation ist gesperrt, wenn jemand unter 200 MM liegt", () => {
    const pool = kompatibleSegmente(basisKontext({ jemandUnter200: true }));
    expect(pool.map((s) => s.id)).not.toContain("inflation");
  });
});

describe("wheel: Pity-Timer (+2 % Gold pro Dreh ab dem 4.)", () => {
  it("unter der Schwelle bleiben die Grund-Gewichte", () => {
    const pool = kompatibleSegmente(basisKontext());
    const gewichte = effektiveGewichte(pool, basisKontext({ drehsOhneGold: 3 }));
    expect(gewichte).toEqual(pool.map((s) => s.gewicht));
  });

  it("ab 4 Drehs ohne Gold steigt die Gold-Chance", () => {
    const pool = kompatibleSegmente(basisKontext());
    const gewichte = effektiveGewichte(pool, basisKontext({ drehsOhneGold: RAD_PITY_AB_DREHS }));
    const goldSumme = pool.reduce(
      (sum, s, i) => (s.klasse === "gold" ? sum + gewichte[i] : sum),
      0,
    );
    // 4 Gold-Segmente à 3 % = 12 % Grundchance + 2 % Pity-Bonus = 14.
    expect(goldSumme).toBeCloseTo(14, 5);
  });
});

describe("wheel: deterministische Ziehung (Seed = Testfall)", () => {
  it("gleicher Seed ⇒ identisches Segment (Rad-Determinismus)", () => {
    const kontext = basisKontext();
    const a = zieheSegment(createRng(1234), kontext);
    const b = zieheSegment(createRng(1234), kontext);
    expect(a).toBe(b);
  });

  it("Ziehung trifft über 10 000 Drehs ungefähr die Gewichte", () => {
    const kontext = basisKontext();
    const rng = createRng(99);
    const zaehler = new Map<string, number>();
    for (let i = 0; i < 10_000; i++) {
      const seg = zieheSegment(rng, kontext);
      zaehler.set(seg, (zaehler.get(seg) ?? 0) + 1);
    }
    // Doppelter Zaster: 13 % ± 2 Punkte.
    const anteil = (zaehler.get("doppelter-zaster") ?? 0) / 10_000;
    expect(anteil).toBeGreaterThan(0.11);
    expect(anteil).toBeLessThan(0.15);
    // Alle gezogenen Segmente sind kompatibel.
    const erlaubt = new Set(kompatibleSegmente(kontext).map((s) => s.id));
    for (const id of zaehler.keys()) expect(erlaubt.has(id as never)).toBe(true);
  });

  it("Fair-Finale-Ziehung liefert NIE ein Nicht-Finale-Segment", () => {
    const kontext = basisKontext({ fairFinale: true });
    const rng = createRng(5);
    for (let i = 0; i < 1_000; i++) {
      const seg = zieheSegment(rng, kontext);
      expect(RAD_SEGMENTE.find((s) => s.id === seg)?.fairFinale).toBe(true);
    }
  });
});

describe("wheel: Anzeige-Ring", () => {
  it("enthält das Ergebnis garantiert und meldet dessen Index", () => {
    const kontext = basisKontext();
    const anzeige = baueRadAnzeige(createRng(77), kontext, "blackout");
    expect(anzeige.segmente[anzeige.ergebnisIndex]).toBe("blackout");
    expect(anzeige.segmente.length).toBeLessThanOrEqual(10);
    expect(new Set(anzeige.segmente).size).toBe(anzeige.segmente.length); // ohne Dubletten
  });

  it("ist per Seed reproduzierbar", () => {
    const kontext = basisKontext();
    const a = baueRadAnzeige(createRng(3), kontext, "dividende");
    const b = baueRadAnzeige(createRng(3), kontext, "dividende");
    expect(a).toEqual(b);
  });
});
