// Meta-Basics (§7): Level-Formel, Avatar-Extras-Wire-Format, Seltenheit,
// Spaced-Repetition-Gewichte, Drift-Urteil (CONTENT-PLAN-Bänder), Median.
import { describe, expect, it } from "vitest";
import {
  SHOP_ITEMS,
  avatarBasis,
  avatarExtras,
  avatarMitExtras,
  bereinigteQuote,
  buzzerSoundAus,
  driftUrteil,
  extrasAusAusruestung,
  gewichteteWahl,
  konfettiStilAus,
  levelFuerAt,
  lieblingsUndNemesis,
  lobbySlideIndex,
  lobbySlides,
  medianAusBuckets,
  seltenheitFuerPreis,
  uebungsGewicht,
  type Boards,
} from "./meta";

describe("meta: Level-Formel (§7.5)", () => {
  it("Level n ab 1.000 × n × (n+1) / 2 AT", () => {
    expect(levelFuerAt(0)).toBe(0);
    expect(levelFuerAt(999)).toBe(0);
    expect(levelFuerAt(1000)).toBe(1); // 1.000
    expect(levelFuerAt(2999)).toBe(1);
    expect(levelFuerAt(3000)).toBe(2); // 3.000
    expect(levelFuerAt(6000)).toBe(3); // 6.000
    expect(levelFuerAt(10_000)).toBe(4); // 10.000
    expect(levelFuerAt(-50)).toBe(0);
  });
});

describe("meta: Avatar-Wire-Format (abwärtskompatibel)", () => {
  it("Basis bleibt 'affe.farbe'; Extras hängen als drittes Segment an", () => {
    expect(avatarBasis("don-bananas.gelb.hut-zylinder+gesicht-monokel")).toBe("don-bananas.gelb");
    expect(avatarBasis("gelb")).toBe("gelb");
    expect(avatarExtras("don-bananas.gelb.hut-zylinder+gesicht-monokel")).toEqual([
      "hut-zylinder",
      "gesicht-monokel",
    ]);
    expect(avatarExtras("don-bananas.gelb")).toEqual([]);
    expect(avatarMitExtras("don-bananas.gelb", ["hut-zylinder"])).toBe(
      "don-bananas.gelb.hut-zylinder",
    );
    expect(avatarMitExtras("don-bananas.gelb.alt-item", [])).toBe("don-bananas.gelb");
  });

  it("extrasAusAusruestung: visuelle + FX-Slots (Buzzer/Konfetti) wandern mit", () => {
    const extras = extrasAusAusruestung({
      hut: "hut-zylinder",
      buzzer: "buzzer-entenquak",
      konfetti: "konfetti-8bit",
      titel: "titel-bananen-baron",
    });
    expect(extras).toContain("hut-zylinder");
    // Befund-Fix „Shop-Items wirken im Match": Buzzer-Sound + Konfetti-Stil
    // reisen im Wire-Format, damit der Screen sie im Match abspielen kann.
    expect(extras).toContain("buzzer-entenquak");
    expect(extras).toContain("konfetti-8bit");
  });

  it("WELLE 3 ADDITIV: podium/einlauf-Slots reisen mit — Alt-Ausrüstungen unverändert", () => {
    // Neue Slots wandern ins Wire-Format …
    const extras = extrasAusAusruestung({
      hut: "hut-krone",
      fell: "fell-tiger",
      podium: "podium-goldrahmen",
      einlauf: "einlauf-blitz",
    });
    expect(extras).toEqual(["hut-krone", "fell-tiger", "podium-goldrahmen", "einlauf-blitz"]);
    // … und ein ALTES Ausrüstungs-Objekt (ohne die neuen Keys) liefert
    // exakt dieselben Extras wie vor Welle 3 (Rückwärtskompatibilität).
    expect(extrasAusAusruestung({ hut: "hut-zylinder", titel: "titel-bananen-baron" })).toEqual([
      "hut-zylinder",
      "titel-bananen-baron",
    ]);
    // Alt-Clients lesen weiter nur "affe.farbe" — Extras stören die Basis nie.
    expect(avatarBasis("don-bananas.gelb.hut-krone+fell-tiger+podium-goldrahmen+lv7")).toBe(
      "don-bananas.gelb",
    );
    expect(avatarExtras("don-bananas.gelb.podium-goldrahmen+einlauf-blitz")).toEqual([
      "podium-goldrahmen",
      "einlauf-blitz",
    ]);
  });
});

describe("meta: Match-FX aus dem Profil (§7.4 — Shop-Items wirken im Match)", () => {
  it("buzzerSoundAus: gekaufter Buzzer aus den Avatar-Extras, sonst null", () => {
    expect(buzzerSoundAus("don-bananas.gelb.buzzer-entenquak+hut-zylinder")).toBe(
      "buzzer-entenquak",
    );
    expect(buzzerSoundAus("don-bananas.gelb.hut-zylinder")).toBeNull();
    expect(buzzerSoundAus("gelb")).toBeNull(); // Alt-Format ohne Extras
  });

  it("konfettiStilAus: gewählter Stil, 'klassisch' ohne gekauftes Item", () => {
    expect(konfettiStilAus("don-bananas.gelb.konfetti-bananen-regen")).toBe("bananen");
    expect(konfettiStilAus("don-bananas.gelb.konfetti-8bit+hut-zylinder")).toBe("8bit");
    expect(konfettiStilAus("don-bananas.gelb")).toBe("klassisch");
  });
});

describe("meta: Lobby-Rotation (Screen QR ↔ Bestenlisten)", () => {
  const leereBoards: Boards = {
    moneyBoss: [],
    kategorieMeister: [],
    blitzBuzzer: [],
    comebackKoenig: [],
  };
  const eintrag = {
    profileId: "p1",
    name: "Anna",
    avatar: "don-bananas.gelb",
    titel: null,
    wert: 1,
    anzeige: "1 AT",
  };

  it("lobbySlides: nur QR ohne Boards; nicht-leere Boards rotieren mit", () => {
    expect(lobbySlides(null)).toEqual(["qr"]);
    expect(lobbySlides(leereBoards)).toEqual(["qr"]);
    expect(lobbySlides({ ...leereBoards, moneyBoss: [eintrag], blitzBuzzer: [eintrag] })).toEqual([
      "qr",
      "moneyBoss",
      "blitzBuzzer",
    ]);
  });

  it("lobbySlideIndex: 12-s-Takt, deterministisch aus der injizierten Zeit", () => {
    expect(lobbySlideIndex(0, 3)).toBe(0);
    expect(lobbySlideIndex(11_999, 3)).toBe(0);
    expect(lobbySlideIndex(12_000, 3)).toBe(1);
    expect(lobbySlideIndex(24_000, 3)).toBe(2);
    expect(lobbySlideIndex(36_000, 3)).toBe(0); // Rundlauf
    expect(lobbySlideIndex(50_000, 1)).toBe(0); // nur QR ⇒ keine Rotation
  });
});

describe("meta: Shop-Sortiment (§7.4)", () => {
  it("29 v1 + 22 Meta-v2 + 22 Kosmetik-Welle-3-Items", () => {
    expect(SHOP_ITEMS).toHaveLength(73);
    expect(SHOP_ITEMS.filter((i) => i.typ === "badge")).toHaveLength(1);
    // Buzzer-Familie (§4.3 Lücke 3): 8 echte Timbres + die 4 Gag-Buzzer aus v1.
    expect(SHOP_ITEMS.filter((i) => i.slot === "buzzer")).toHaveLength(12);
    // Meta-v2 (§7.5): +10 Titel, +6 Banner, +4 Namens-Stile, +2 Konfetti.
    expect(SHOP_ITEMS.filter((i) => i.typ === "banner")).toHaveLength(6);
    expect(SHOP_ITEMS.filter((i) => i.typ === "namestil")).toHaveLength(4);
    expect(SHOP_ITEMS.filter((i) => i.typ === "titel").length).toBeGreaterThanOrEqual(12);
    expect(SHOP_ITEMS.filter((i) => i.typ === "konfetti")).toHaveLength(4);
    const ids = new Set(SHOP_ITEMS.map((i) => i.id));
    expect(ids.size).toBe(73); // keine Doppel-Ids
  });

  it("Kosmetik-Welle 3: 8 Kopf + 4 Gesicht + 5 Fell-Muster + 3 Podium + 2 Einlauf", () => {
    // Slot-Zählung (Welle 3 additiv zu den Bestands-Items derselben Slots):
    expect(SHOP_ITEMS.filter((i) => i.slot === "hut")).toHaveLength(10); // 2 v1 + 8 neu
    expect(SHOP_ITEMS.filter((i) => i.slot === "gesicht")).toHaveLength(6); // 2 v1 + 4 neu
    expect(SHOP_ITEMS.filter((i) => i.slot === "fell")).toHaveLength(7); // 2 Swaps + 5 Muster
    expect(SHOP_ITEMS.filter((i) => i.slot === "podium")).toHaveLength(3);
    expect(SHOP_ITEMS.filter((i) => i.slot === "einlauf")).toHaveLength(2);
    // ALLE Welle-3-Items sind echte Sichtbar-Items (visuell) und kaufbar
    // (kein passExklusiv — die Exklusivität dieser Welle sind Level-Gates).
    const welle3 = SHOP_ITEMS.filter(
      (i) =>
        i.slot === "podium" ||
        i.slot === "einlauf" ||
        [
          "hut-pirat",
          "hut-krone",
          "hut-propeller",
          "hut-heiligenschein",
          "hut-teufelshoerner",
          "hut-blumenkranz",
          "hut-ritterhelm",
          "hut-partyhut",
          "gesicht-schnurrbart",
          "gesicht-sonnenbrille",
          "gesicht-augenklappe",
          "gesicht-kaugummi",
          "fell-tiger",
          "fell-dalmatiner",
          "fell-sterne",
          "fell-camo",
          "fell-goldglitzer",
        ].includes(i.id),
    );
    expect(welle3).toHaveLength(22);
    expect(welle3.every((i) => i.visuell === true)).toBe(true);
    expect(welle3.every((i) => i.passExklusiv === undefined)).toBe(true);
    // Typ ↔ Slot konsistent (der Store prüft item.slot === slot beim Anlegen).
    for (const i of welle3) {
      if (i.slot === "hut" || i.slot === "gesicht") expect(i.typ).toBe("accessoire");
      if (i.slot === "fell") expect(i.typ).toBe("avatar");
      if (i.slot === "podium") expect(i.typ).toBe("podium");
      if (i.slot === "einlauf") expect(i.typ).toBe("einlauf");
    }
    // Genau 4 Level-Exklusive (Krone L8, Gold-Glitzer L10, Goldrahmen L6, Blitz L7).
    const exklusiv = welle3.filter((i) => i.minLevel !== undefined);
    expect(exklusiv.map((i) => i.id).sort()).toEqual([
      "einlauf-blitz",
      "fell-goldglitzer",
      "hut-krone",
      "podium-goldrahmen",
    ]);
    // Preise folgen dem Seltenheits-Gefüge: Level-Exklusive sind Gold-Stufe.
    for (const i of exklusiv) expect(seltenheitFuerPreis(i.preis)).toBe("gold");
    for (const i of welle3) expect(i.preis).toBeGreaterThan(0);
  });

  it("Seltenheits-Stufen aus dem Preis", () => {
    expect(seltenheitFuerPreis(500)).toBe("gruen");
    expect(seltenheitFuerPreis(3000)).toBe("reif");
    expect(seltenheitFuerPreis(6000)).toBe("gold");
    expect(seltenheitFuerPreis(25_000)).toBe("diamant");
  });
});

describe("meta: Spaced-Repetition (§6.2)", () => {
  it("oft-falsch wiegt mehr als oft-richtig", () => {
    const falsch = uebungsGewicht({ richtig: 1, falsch: 9, serie: 0, zuletztTs: null });
    const richtig = uebungsGewicht({ richtig: 9, falsch: 1, serie: 4, zuletztTs: null });
    const neu = uebungsGewicht(undefined);
    expect(falsch).toBeGreaterThan(neu);
    expect(neu).toBeGreaterThan(richtig);
  });

  it("Serie senkt das Gewicht stufenweise (Leitner-Boxen)", () => {
    const box0 = uebungsGewicht({ richtig: 1, falsch: 1, serie: 0, zuletztTs: null });
    const box2 = uebungsGewicht({ richtig: 3, falsch: 1, serie: 2, zuletztTs: null });
    const box4 = uebungsGewicht({ richtig: 5, falsch: 1, serie: 4, zuletztTs: null });
    expect(box0).toBeGreaterThan(box2);
    expect(box2).toBeGreaterThan(box4);
  });

  it("gewichteteWahl: trifft proportional + robust bei Rand-Werten", () => {
    const kandidaten = [
      { wert: "a", gewicht: 1 },
      { wert: "b", gewicht: 3 },
    ];
    expect(gewichteteWahl(kandidaten, 0)).toBe("a");
    expect(gewichteteWahl(kandidaten, 0.5)).toBe("b");
    expect(gewichteteWahl(kandidaten, 0.999999)).toBe("b");
    expect(gewichteteWahl([], 0.5)).toBeNull();
    expect(gewichteteWahl([{ wert: "x", gewicht: 0 }], 0.5)).toBeNull();
  });
});

describe("meta: Fragen-Gesundheit (§7.6)", () => {
  it("bereinigte Quote zieht die 25-%-Ratebasis ab", () => {
    expect(bereinigteQuote(25, 100)).toBe(0);
    expect(bereinigteQuote(100, 100)).toBe(1);
    expect(bereinigteQuote(0, 0)).toBeNull();
  });

  it("driftUrteil: ok im Band, Vorschlag daneben, Quarantäne bei 2+ Stufen/0 %", () => {
    // easy-Band 80–95 %: 90 % roh ≈ 86,7 % bereinigt ⇒ ok
    expect(driftUrteil("easy", 90, 100).art).toBe("ok");
    // easy mit ~47 % bereinigt ⇒ medium-Band ⇒ Umstufungs-Vorschlag
    const runter = driftUrteil("easy", 60, 100);
    expect(runter.art).toBe("vorschlag");
    expect(runter.zielStufe).toBe("medium");
    // easy mit hard-Quote ⇒ 2 Stufen daneben ⇒ Quarantäne
    const quarantaene = driftUrteil("easy", 40, 100);
    expect(quarantaene.art).toBe("quarantaene");
    // 0 % bei ≥ 10 Antworten ⇒ Quarantäne (Frage der Schande)
    expect(driftUrteil("medium", 0, 12).art).toBe("quarantaene");
    // zu wenig Daten (< 20 Antworten) ⇒ kein Urteil
    expect(driftUrteil("easy", 2, 10).art).toBe("zu-wenig-daten");
  });
});

describe("meta: Stats-Helfer", () => {
  it("medianAusBuckets: Median-Zeit aus dem Histogramm", () => {
    const buckets = new Array(40).fill(0) as number[];
    buckets[2] = 3; // 3 Antworten im Bucket 1.000–1.500 ms
    buckets[6] = 2;
    expect(medianAusBuckets(buckets)).toBe(2 * 500 + 250);
    expect(medianAusBuckets(new Array(40).fill(0) as number[])).toBeNull();
  });

  it("lieblingsUndNemesis: ab 20 Antworten, nie dieselbe Kategorie doppelt", () => {
    const matrix = {
      "wissen|easy": { n: 25, richtig: 22 },
      "sport|easy": { n: 30, richtig: 9 },
      "games|easy": { n: 5, richtig: 5 }, // unter der Schwelle
    };
    const { lieblings, nemesis } = lieblingsUndNemesis(matrix);
    expect(lieblings?.kategorie).toBe("wissen");
    expect(nemesis?.kategorie).toBe("sport");
    const einsam = lieblingsUndNemesis({ "wissen|easy": { n: 40, richtig: 30 } });
    expect(einsam.lieblings?.kategorie).toBe("wissen");
    expect(einsam.nemesis).toBeNull();
  });
});
