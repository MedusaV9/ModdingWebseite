// Content-Loader: lädt die echten Packs aus content/packs hinter dem stabilen Interface.
import { describe, expect, it } from "vitest";
import { QuestionSchema } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { createContentLoader } from "./index";

describe("content-loader (stabile Skeleton-Verträge)", () => {
  it("liefert 3 valide Fragen für ein Match (Options-Zahl je kind)", async () => {
    const loader = createContentLoader();
    await loader.loadPacks();
    const fragen = loader.pickQuestions({ anzahl: 3 });
    expect(fragen).toHaveLength(3);
    const optionsJeKind = { choice4: 4, wahr_falsch: 2, schaetz: 0, sortier: 4 };
    for (const frage of fragen) {
      expect(() => QuestionSchema.parse(frage)).not.toThrow();
      expect(frage.options).toHaveLength(optionsJeKind[frage.kind]);
      expect(frage.erklaerung.length).toBeGreaterThan(0); // Pflichtfeld
    }
  });

  it("respektiert usedQuestionIds (No-Repeat)", () => {
    const loader = createContentLoader();
    const erste = loader.pickQuestions({ anzahl: 1 });
    const rest = loader.pickQuestions({ anzahl: 3, usedQuestionIds: [erste[0].id] });
    expect(rest.map((q) => q.id)).not.toContain(erste[0].id);
  });
});

describe("content-loader v1 (Packs von Disk + additive Filter)", () => {
  it("lädt die Seed-Packs (≥120 choice4-fähige Fragen, eindeutige Ids)", () => {
    const loader = createContentLoader();
    const alle = loader.pickQuestions({ anzahl: 10_000 });
    expect(alle.length).toBeGreaterThanOrEqual(120);
    expect(new Set(alle.map((q) => q.id)).size).toBe(alle.length);
  });

  it("filtert nach kategorien (Ober-Slug ODER Unter-Slug)", () => {
    const loader = createContentLoader();
    const gaming = loader.pickQuestions({ anzahl: 100, kategorien: ["gaming"] });
    expect(gaming.length).toBeGreaterThan(0);
    // Alle Treffer gehören laut Katalog zur Ober-Kategorie gaming — bewusst
    // ÜBER den Katalog geprüft statt Pack-Slugs aufzuzählen (Content wächst).
    const oberVon = new Map(loader.alleFragen().map((k) => [k.frage.id, k.oberkategorie]));
    for (const q of gaming) expect(oberVon.get(q.id)).toBe("gaming");
    const bundesliga = loader.pickQuestions({ anzahl: 100, kategorien: ["bundesliga"] });
    expect(bundesliga.length).toBeGreaterThan(0);
    for (const q of bundesliga) expect(q.category).toBe("bundesliga");
  });

  it("filtert nach schwierigkeiten (Engine-Begriffe)", () => {
    const loader = createContentLoader();
    const schwere = loader.pickQuestions({ anzahl: 100, schwierigkeiten: ["ultrahard"] });
    expect(schwere.length).toBeGreaterThan(0);
    for (const q of schwere) expect(q.difficulty).toBe("ultrahard");
  });

  it("region-Regler: global schließt de-Fragen aus, de erlaubt beide", () => {
    const loader = createContentLoader();
    // deutschland_spezial ist per Plan komplett region=de:
    const nurGlobal = loader.pickQuestions({
      anzahl: 100,
      kategorien: ["deutschland_spezial"],
      region: "global",
    });
    expect(nurGlobal).toHaveLength(0);
    const mitDe = loader.pickQuestions({
      anzahl: 100,
      kategorien: ["deutschland_spezial"],
      region: "de",
    });
    expect(mitDe.length).toBeGreaterThan(0);
  });

  it("emoji-Typ: Emojis wandern in den Fragetext (choice4-Abbildung)", () => {
    const loader = createContentLoader();
    const emojis = loader.pickQuestions({ anzahl: 100, typen: ["emoji"] });
    expect(emojis.length).toBeGreaterThan(0);
    for (const q of emojis) {
      expect(q.text).toContain("\n\n");
      expect(() => QuestionSchema.parse(q)).not.toThrow();
    }
  });

  it("gleicher Rng-Seed ⇒ gleiche Auswahl (Determinismus)", () => {
    const loader = createContentLoader();
    const a = loader.pickQuestions({ anzahl: 5, rng: createRng(42) });
    const b = loader.pickQuestions({ anzahl: 5, rng: createRng(42) });
    expect(a.map((q) => q.id)).toEqual(b.map((q) => q.id));
  });

  // Wächter: bild_pixel-Fragen erreichen die Engine MIT Media-URL — der Server
  // liefert repo-assets/ unter /media/ aus (Express-Static in core/http.ts).
  it("bild_pixel-Typ: media.bild zeigt auf die /media-URL des Servers", () => {
    const loader = createContentLoader();
    const bilder = loader.pickQuestions({ anzahl: 100, typen: ["bild_pixel"] });
    expect(bilder.length).toBeGreaterThanOrEqual(12);
    for (const q of bilder) {
      expect(() => QuestionSchema.parse(q)).not.toThrow();
      expect(q.media?.bild).toMatch(/^\/media\/img\/generated\/pixel\/pixel_[a-z]+\.png$/);
    }
  });

  // ---------- Wächter (Eval 5 „1555 Fragen erreichen kein Match") ----------

  it("wahr_falsch-Typ: 2 Optionen Wahr/Falsch, answer aus korrekt_bool", () => {
    const loader = createContentLoader();
    const wf = loader.pickQuestions({ anzahl: 10_000, typen: ["wahr_falsch"] });
    expect(wf.length).toBeGreaterThanOrEqual(500);
    for (const q of wf) {
      expect(() => QuestionSchema.parse(q)).not.toThrow();
      expect(q.kind).toBe("wahr_falsch");
      expect(q.options).toEqual(["Wahr", "Falsch"]);
      expect([0, 1]).toContain(q.answer);
    }
  });

  it("schaetz-Typ: Slider-Daten aus der Frage (Range, Toleranz, Skala)", () => {
    const loader = createContentLoader();
    const schaetz = loader.pickQuestions({ anzahl: 10_000, typen: ["schaetz"] });
    expect(schaetz.length).toBeGreaterThanOrEqual(400);
    for (const q of schaetz) {
      expect(() => QuestionSchema.parse(q)).not.toThrow();
      expect(q.kind).toBe("schaetz");
      const s = q.schaetz!;
      expect(s.eingabeMin).toBeLessThan(s.richtwert);
      expect(s.richtwert).toBeLessThan(s.eingabeMax);
      expect(s.toleranzProzent).toBeGreaterThan(0);
      expect(["linear", "log"]).toContain(s.skala);
    }
  });

  it("sortier-Typ: 4 Elemente in options, aufloesungWerte ELEMENT-indiziert", () => {
    const loader = createContentLoader();
    const sortier = loader.pickQuestions({ anzahl: 10_000, typen: ["sortier"] });
    expect(sortier.length).toBeGreaterThanOrEqual(200);
    for (const q of sortier) {
      expect(() => QuestionSchema.parse(q)).not.toThrow();
      expect(q.kind).toBe("sortier");
      expect(q.options).toHaveLength(4);
      const s = q.sortier!;
      expect([...s.korrektReihenfolge].sort((a, b) => a - b)).toEqual([0, 1, 2, 3]);
      // Loader normalisiert das positions-indizierte Pack-Feld: pro ELEMENT ein Wert.
      for (const wert of s.aufloesungWerte) expect(wert.length).toBeGreaterThan(0);
    }
  });

  it("tips: die 3 Autoren-Tipps wandern mit in die Engine-Frage", () => {
    const loader = createContentLoader();
    const fragen = loader.pickQuestions({ anzahl: 200, typen: ["choice"] });
    const mitTipps = fragen.filter((q) => (q.tips?.length ?? 0) > 0);
    expect(mitTipps.length).toBeGreaterThan(0);
    for (const q of mitTipps) expect(q.tips!.every((t) => t.length > 0)).toBe(true);
  });
});
