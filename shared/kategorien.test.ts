// Label-Helfer (Erklärkarten/Votings): Taxonomie-Namen statt Rohslugs,
// Schwierigkeits-Map Leicht/Mittel/Schwer/ULTRAHARD (Playtest-3-Befund).
import { describe, expect, it } from "vitest";
import { kategorieLabel, schwierigkeitLabel } from "./kategorien";

describe("kategorieLabel", () => {
  it("löst Unterkategorie-Slugs über die Taxonomie auf", () => {
    expect(kategorieLabel("staedte_wahrzeichen")).toBe("Städte & Wahrzeichen");
    expect(kategorieLabel("persoenlichkeiten_entdecker")).toBe("Persönlichkeiten & Entdecker");
    expect(kategorieLabel("promis_boulevard")).toBe("Promis & Boulevard");
  });

  it("löst Oberkategorie-Ids über die Taxonomie auf", () => {
    expect(kategorieLabel("essen_trinken")).toBe("Essen & Trinken");
    expect(kategorieLabel("deutschland_spezial")).toBe("Deutschland-Spezial");
  });

  it("fällt bei unbekannten Ids auf eine Titel-Schreibung zurück", () => {
    expect(kategorieLabel("geheime_test_kategorie")).toBe("Geheime Test Kategorie");
  });
});

describe("schwierigkeitLabel", () => {
  it("mappt die Engine-Stufen auf deutsche Show-Labels", () => {
    expect(schwierigkeitLabel("easy")).toBe("Leicht");
    expect(schwierigkeitLabel("medium")).toBe("Mittel");
    expect(schwierigkeitLabel("hard")).toBe("Schwer");
    expect(schwierigkeitLabel("ultrahard")).toBe("ULTRAHARD");
  });

  it("reicht Unbekanntes unverändert durch", () => {
    expect(schwierigkeitLabel("banane")).toBe("banane");
  });
});
