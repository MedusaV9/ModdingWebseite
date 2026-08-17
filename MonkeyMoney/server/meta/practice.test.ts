// Übungsmodus „Trainingslager" (§6.2): Frage-Antwort-Zyklus, kostenlose Tipps,
// Lern-Statistik + Spaced-Repetition-Auswahl (oft-falsch kommt öfter).
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import { createFileStorage } from "../persistence/storage";
import { createPracticeService, type PracticeService } from "./practice";

function frage(id: string, patch: Partial<Question> = {}): Question {
  return {
    id,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${id}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "Weil B.",
    ...patch,
  };
}

function fakeLoader(fragen: Question[]): ContentLoader {
  const katalog: KatalogFrage[] = fragen.map((f) => ({
    frage: f,
    oberkategorie: "wissen",
    planTyp: "mc4",
    region: "global",
  }));
  return {
    async loadPacks() {},
    pickQuestions: () => [],
    alleFragen: () => katalog,
  };
}

let dir: string;
let practice: PracticeService;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-uebung-"));
  practice = createPracticeService(
    createFileStorage(dir),
    fakeLoader([
      frage("q1"),
      frage("q2", { category: "sport", difficulty: "medium" }),
      frage("q3"),
    ]),
    createRng(7),
    createTestClock(1_000_000),
  );
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("meta: Übungsmodus (§6.2)", () => {
  it("Frage-Antwort-Zyklus: Sofort-Auflösung + Lern-Statistik, KEINE AT", async () => {
    const f = await practice.naechsteFrage("geraet1", {});
    expect("fehler" in f).toBe(false);
    if ("fehler" in f) return;
    const antwort = await practice.antwort("geraet1", f.questionId, 1, 1500);
    if ("fehler" in antwort) throw new Error(antwort.fehler);
    expect(antwort.korrekt).toBe(true);
    expect(antwort.erklaerung).toBe("Weil B.");
    expect(antwort.stats.beantwortet).toBe(1);
    expect(antwort.stats.serie).toBe(1);
  });

  it("Filter: Kategorie + Schwierigkeit grenzen die Auswahl ein", async () => {
    for (let i = 0; i < 5; i++) {
      const f = await practice.naechsteFrage("geraet1", {
        kategorie: "sport",
        schwierigkeit: "medium",
      });
      if ("fehler" in f) throw new Error(f.fehler);
      expect(f.questionId).toBe("q2");
      await practice.antwort("geraet1", f.questionId, 0, 100);
    }
    expect(await practice.naechsteFrage("geraet1", { kategorie: "gibts-nicht" })).toEqual({
      fehler: "keine-fragen",
    });
  });

  it("Antwort ohne offene Frage blockt (Anti-Cheat: Lösung nie vorab)", async () => {
    expect(await practice.antwort("geraet1", "q1", 1, 0)).toEqual({
      fehler: "frage-nicht-offen",
    });
  });

  it("Tipp ohne Autoren-Tipps: entfernt genau 2 FALSCHE Optionen, kostenlos", async () => {
    const f = await practice.naechsteFrage("geraet1", {});
    if ("fehler" in f) throw new Error(f.fehler);
    expect(f.tippsGesamt).toBe(0);
    const tipp = practice.tipp("geraet1", f.questionId);
    if ("fehler" in tipp) throw new Error(tipp.fehler);
    if (!("entfernt" in tipp)) throw new Error("erwartet 50:50-Fallback");
    expect(tipp.entfernt).toHaveLength(2);
    expect(tipp.entfernt).not.toContain(1); // die richtige Antwort bleibt stehen
  });

  it("Tipp MIT Autoren-Tipps: stufenweise Enthüllung 1→2→3, dann Schluss", async () => {
    const mitTipps = createPracticeService(
      createFileStorage(dir),
      fakeLoader([frage("qt", { tips: ["Tipp eins", "Tipp zwei", "Tipp drei"] })]),
      createRng(7),
      createTestClock(1_000_000),
    );
    const f = await mitTipps.naechsteFrage("geraet1", {});
    if ("fehler" in f) throw new Error(f.fehler);
    expect(f.tippsGesamt).toBe(3);
    for (const [stufe, text] of [
      [1, "Tipp eins"],
      [2, "Tipp zwei"],
      [3, "Tipp drei"],
    ] as const) {
      const tipp = mitTipps.tipp("geraet1", f.questionId);
      if ("fehler" in tipp || !("tipp" in tipp)) throw new Error("erwartet Text-Tipp");
      expect(tipp).toEqual({ tipp: text, stufe, gesamt: 3 });
    }
    expect(mitTipps.tipp("geraet1", f.questionId)).toEqual({ fehler: "alle-tipps-gesehen" });
  });

  it("Spaced-Repetition: oft-falsche Fragen kommen messbar öfter", async () => {
    // Übungs-Schleife über die beiden affen-Fragen: q1 IMMER falsch, q3 immer
    // richtig ⇒ q1-Gewicht steigt (Falsch-Anteil), q3 sinkt (Leitner-Serie).
    let q1Zaehler = 0;
    const aufwaermen = 15;
    const messung = 25;
    for (let i = 0; i < aufwaermen + messung; i++) {
      const f = await practice.naechsteFrage("geraet1", { kategorie: "affen" });
      if ("fehler" in f) throw new Error(f.fehler);
      if (i >= aufwaermen && f.questionId === "q1") q1Zaehler += 1;
      await practice.antwort("geraet1", f.questionId, f.questionId === "q1" ? 0 : 1, 100);
    }
    // Bei 2 Kandidaten wäre 50:50 fair — die Falsch-Historie muss q1 dominieren lassen.
    expect(q1Zaehler).toBeGreaterThan(Math.round(messung * 0.6));
  });

  it("Quarantäne-Gate: gesperrte Fragen tauchen auch im Training nie auf", async () => {
    const gesperrt = createPracticeService(
      createFileStorage(dir),
      fakeLoader([frage("q1"), frage("q3")]),
      createRng(7),
      createTestClock(1_000_000),
      (qid) => qid === "q1",
    );
    for (let i = 0; i < 10; i++) {
      const f = await gesperrt.naechsteFrage("geraet1", {});
      if ("fehler" in f) throw new Error(f.fehler);
      expect(f.questionId).toBe("q3");
      await gesperrt.antwort("geraet1", f.questionId, 1, 100);
    }
  });

  it("Stats: Schwächen-Kategorien ab 5 Antworten, Quote + Serien", async () => {
    for (let i = 0; i < 6; i++) {
      const f = await practice.naechsteFrage("geraet1", { kategorie: "sport" });
      if ("fehler" in f) throw new Error(f.fehler);
      await practice.antwort("geraet1", f.questionId, 0, 100); // immer falsch
    }
    const stats = await practice.stats("geraet1");
    expect(stats.beantwortet).toBe(6);
    expect(stats.quote).toBe(0);
    expect(stats.schwaechen[0].kategorie).toBe("sport");
  });
});
