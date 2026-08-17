// Level-System (§7.5 / Ideen-S-12): Kurve auf Lifetime-AT-Basis, Kauf-Gates
// (minLevel + Pass-Exklusive) und die Level-Up-Erkennung zwischen Buchungen.
import { describe, expect, it } from "vitest";
import {
  SHOP_ITEMS,
  atFuerLevel,
  levelAusExtras,
  levelFortschritt,
  levelFuerAt,
  levelToken,
} from "../../shared/meta";
import { saisonItems } from "../../shared/quests";
import { kaufSperre, levelUpZwischen } from "./level";

describe("level: Kurve = Funktion der Lifetime-AT (Ausgeben senkt nie!)", () => {
  it("dokumentierte Schwellen: L1=1.000 · L5=15.000 · L10=55.000 · L100=5,05 Mio.", () => {
    expect(levelFuerAt(0)).toBe(0);
    expect(levelFuerAt(999)).toBe(0);
    expect(levelFuerAt(1000)).toBe(1);
    expect(levelFuerAt(14_999)).toBe(4);
    expect(levelFuerAt(15_000)).toBe(5);
    expect(levelFuerAt(55_000)).toBe(10);
    expect(levelFuerAt(210_000)).toBe(20);
    expect(levelFuerAt(5_050_000)).toBe(100); // Level 100+ bleibt erreichbar
    expect(levelFuerAt(5_050_000 + 101_000)).toBe(101); // nach oben offen
  });

  it("atFuerLevel ist die Umkehrung; Fortschritts-Anteil bleibt in [0,1]", () => {
    for (const lvl of [1, 5, 10, 50, 100]) {
      expect(levelFuerAt(atFuerLevel(lvl))).toBe(lvl);
      expect(levelFuerAt(atFuerLevel(lvl) - 1)).toBe(lvl - 1);
    }
    const f = levelFortschritt(1500); // Lv 1 (ab 1.000), Lv 2 ab 3.000
    expect(f.level).toBe(1);
    expect(f.aktuellAb).toBe(1000);
    expect(f.naechstesAb).toBe(3000);
    expect(f.anteil).toBeCloseTo(0.25);
    expect(levelFortschritt(-50).anteil).toBe(0);
  });

  it("lv-Token: Level reist als Pseudo-Extra im Avatar-String", () => {
    expect(levelToken(0)).toBeNull(); // Lv 0 zeigt kein Badge
    expect(levelToken(7)).toBe("lv7");
    expect(levelAusExtras(["hut-zylinder", "lv12"])).toBe(12);
    expect(levelAusExtras(["hut-zylinder"])).toBeNull();
    expect(levelAusExtras(["lvxx"])).toBeNull(); // kein Zahlen-Match
  });
});

describe("level: Kauf-Gates (8-14 Items level-gated, Pass-Exklusive nie kaufbar)", () => {
  it("Katalog hat 8-14 minLevel-Items; Sperre öffnet exakt an der Schwelle", () => {
    const gated = SHOP_ITEMS.filter((i) => i.minLevel !== undefined);
    expect(gated.length).toBeGreaterThanOrEqual(8);
    // Kosmetik-Welle 3 bringt 4 Level-Exklusive mit (hut-krone, fell-goldglitzer,
    // podium-goldrahmen, einlauf-blitz) — Deckel bewusst mitgezogen, damit der
    // Test weiter vor unkontrollierter Gate-Inflation warnt.
    expect(gated.length).toBeLessThanOrEqual(14);
    for (const item of gated) {
      const schwelle = atFuerLevel(item.minLevel!);
      expect(kaufSperre(item, schwelle - 1)).toBe("level-zu-niedrig");
      expect(kaufSperre(item, schwelle)).toBeNull();
    }
  });

  it("Items ohne Gate sind immer kaufbar; Saison-Exklusive nie", () => {
    const frei = SHOP_ITEMS.find((i) => i.id === "hut-zylinder")!;
    expect(kaufSperre(frei, 0)).toBeNull();
    for (const item of saisonItems("2026-08")) {
      expect(kaufSperre(item, 99_999_999)).toBe("nur-im-pass");
    }
  });

  it("levelUpZwischen erkennt Sprünge (auch Mehrfach-Level) und Nicht-Sprünge", () => {
    expect(levelUpZwischen(0, 999)).toBeNull();
    expect(levelUpZwischen(900, 1200)).toEqual({ von: 0, zu: 1 });
    expect(levelUpZwischen(500, 6500)).toEqual({ von: 0, zu: 3 }); // 6.000er-Schwelle
    expect(levelUpZwischen(1200, 1200)).toBeNull();
  });
});
