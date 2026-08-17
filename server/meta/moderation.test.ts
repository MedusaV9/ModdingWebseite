// Fragen-Moderation (Admin-Fix W20): Quarantäne nimmt Fragen WIRKLICH aus der
// Match-Rotation (pickQuestions-Dekorator), Entkräften/Geprüft persistieren
// atomar und überleben einen Neustart (ladeInitial).
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage, PickOptions } from "../content-loader/index";
import { createFileStorage, type Storage } from "../persistence/storage";
import { createModerationStore, moderierePickQuestions, type ModerationStore } from "./moderation";

function frage(id: string): Question {
  return {
    id,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${id}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "Weil B.",
  };
}

/** Fake-Loader mit ECHTER usedQuestionIds-Semantik (wie der Produktiv-Loader). */
function fakeLoader(fragen: Question[]): ContentLoader {
  const katalog: KatalogFrage[] = fragen.map((f) => ({
    frage: f,
    oberkategorie: "wissen",
    planTyp: "mc4",
    region: "global",
  }));
  return {
    async loadPacks() {},
    pickQuestions: (opts: PickOptions) => {
      const benutzt = new Set(opts.usedQuestionIds ?? []);
      return fragen.filter((f) => !benutzt.has(f.id)).slice(0, opts.anzahl);
    },
    alleFragen: () => katalog,
  };
}

let dir: string;
let storage: Storage;
let store: ModerationStore;

beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), "mm-moderation-"));
  storage = createFileStorage(dir);
  store = createModerationStore(storage, createTestClock(5_000_000));
  await store.ladeInitial();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("meta: Fragen-Moderation (Admin-Queue-Aktionen)", () => {
  it("QUARANTÄNE wirkt auf pickQuestions: gesperrte Fragen werden nie gezogen", async () => {
    const loader = fakeLoader([frage("q1"), frage("q2"), frage("q3")]);
    moderierePickQuestions(loader, store);
    // Vorher: alle 3 Fragen im Pool.
    expect(loader.pickQuestions({ anzahl: 10 }).map((q) => q.id)).toEqual(["q1", "q2", "q3"]);
    await store.setzeQuarantaene("q2", true);
    expect(store.istGesperrt("q2")).toBe(true);
    expect(loader.pickQuestions({ anzahl: 10 }).map((q) => q.id)).toEqual(["q1", "q3"]);
    // usedQuestionIds des Aufrufers bleiben ZUSÄTZLICH wirksam.
    expect(loader.pickQuestions({ anzahl: 10, usedQuestionIds: ["q1"] }).map((q) => q.id)).toEqual([
      "q3",
    ]);
    // Quarantäne aufheben ⇒ Frage kommt zurück in die Rotation.
    await store.setzeQuarantaene("q2", false);
    expect(loader.pickQuestions({ anzahl: 10 })).toHaveLength(3);
  });

  it("überlebt einen Neustart: Datei laden stellt Quarantäne + Vermerke wieder her", async () => {
    await store.setzeQuarantaene("q9", true);
    await store.setzeGeprueft("q7", true);
    const neu = createModerationStore(storage, createTestClock(6_000_000));
    expect(neu.istGesperrt("q9")).toBe(false); // Cache noch leer
    await neu.ladeInitial();
    expect(neu.istGesperrt("q9")).toBe(true);
    expect(neu.alle()["q7"]?.geprueftTs).toBe(5_000_000);
    expect(neu.gesperrteIds()).toEqual(["q9"]);
  });

  it("ENTKRÄFTEN merkt sich den Zeitpunkt: alte Flags gelten als erledigt, neue zählen", async () => {
    const e = await store.entkraefte("q1");
    expect(e.entkraeftetBis).toBe(5_000_000);
    // Semantik der Queue: Flags mit ts ≤ entkraeftetBis sind ausgeblendet.
    const altesFlag = 4_999_000;
    const neuesFlag = 5_000_001;
    expect(altesFlag <= (e.entkraeftetBis ?? 0)).toBe(true);
    expect(neuesFlag <= (e.entkraeftetBis ?? 0)).toBe(false);
  });

  it("GEPRÜFT ist ein umschaltbarer Sichtvermerk; leere Einträge verschwinden aus der Datei", async () => {
    await store.setzeGeprueft("q4", true);
    expect(store.alle()["q4"]?.geprueftTs).toBe(5_000_000);
    await store.setzeGeprueft("q4", false);
    // Eintrag ist wieder komplett leer ⇒ wird aus Datei + Cache entfernt.
    expect(store.alle()["q4"]).toBeUndefined();
    const datei = await storage.readJson<{ fragen: Record<string, unknown> }>(
      "meta/moderation.json",
    );
    expect(datei?.fragen["q4"]).toBeUndefined();
  });
});
