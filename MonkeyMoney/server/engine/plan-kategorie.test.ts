// Welle 1 (Eval „Kategorie-Votes werden ignoriert"): die gewählte Kategorie
// muss auch wirklich ausgespielt werden. Zwei Wächter:
//   1. waehleFrage degradiert die SCHWIERIGKEIT vor der Kategorie.
//   2. kategorieOptionen bietet nur Kategorien an, die die Runde TRAGEN können.
import { describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { defaultSettings } from "../../shared/settings";
import { createInitialState } from "./engine";
import { kategorieOptionen, waehleFrage } from "./plan";
import type { Abschnitt, EngineState } from "./types";

const frage = (id: string, patch: Partial<Question> = {}): Question => ({
  id,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text: `Frage ${id}?`,
  options: ["A", "B", "C", "D"],
  answer: 1,
  erklaerung: "Weil B.",
  ...patch,
});

const abschnitt = (patch: Partial<Abschnitt> = {}): Abschnitt => ({
  typ: "runde",
  nr: 1,
  slot: "aufbau",
  wunschMinigameId: "vier-lianen",
  minigameId: "vier-lianen",
  fragen: 4,
  schwierigkeiten: ["easy", "medium"],
  kategorieWahl: "voting",
  radDanach: false,
  kategorie: null,
  ...patch,
});

function planState(pool: Question[], a: Abschnitt): EngineState {
  const s = createInitialState(defaultSettings("quick"));
  return {
    ...s,
    fragenPool: pool,
    plan: { abschnitte: [a], rundenTotal: 1, fragenTotal: a.fragen, ultrahardMax: 1 },
    abschnittIndex: 0,
  };
}

describe("waehleFrage: Kategorie-Treue (Vote-Fix)", () => {
  it("hält die gewählte Kategorie, auch wenn nur eine andere Schwierigkeit da ist", () => {
    // Gewählt: „musik" — aber nur noch als hard vorrätig. Der Slot will
    // easy/medium. Alt-Verhalten: easy-Frage aus „affen" (Vote ignoriert!).
    // Neu: die hard-Frage aus „musik" (Kategorie schlägt Schwierigkeit).
    const pool = [
      ...Array.from({ length: 10 }, (_, i) => frage(`qa${i + 1}`)), // affen, easy
      frage("qm1", { category: "musik", difficulty: "hard" }),
    ];
    const a = abschnitt({ kategorie: "musik" });
    const s = planState(pool, a);
    const gewaehlt = waehleFrage(s, a, createRng(3)).frage;
    expect(gewaehlt.category).toBe("musik");
    expect(gewaehlt.id).toBe("qm1");
  });

  it("perfekter Treffer (Kategorie + Schwierigkeit) bleibt erste Wahl", () => {
    const pool = [
      frage("qm1", { category: "musik", difficulty: "hard" }),
      frage("qm2", { category: "musik", difficulty: "easy" }),
      frage("qa1"),
    ];
    const a = abschnitt({ kategorie: "musik" });
    const s = planState(pool, a);
    expect(waehleFrage(s, a, createRng(3)).frage.id).toBe("qm2");
  });
});

describe("kategorieOptionen: nur tragfähige Kategorien (Vote-Fix)", () => {
  it("bietet keine Kategorie an, die die Runde nicht tragen kann", () => {
    // „musik" hat nur 1 passende Frage, die Runde braucht 4 — „musik" darf
    // nicht zur Wahl stehen (der Vote würde sonst ins Leere laufen).
    const pool = [
      ...Array.from({ length: 6 }, (_, i) => frage(`qa${i + 1}`)),
      ...Array.from({ length: 6 }, (_, i) => frage(`qs${i + 1}`, { category: "sport" })),
      frage("qm1", { category: "musik" }),
    ];
    const a = abschnitt();
    const s = planState(pool, a);
    const optionen = kategorieOptionen(s, a, createRng(3));
    expect(optionen).not.toContain("musik");
    expect(optionen.length).toBeGreaterThanOrEqual(2);
    expect(optionen).toEqual(expect.arrayContaining(["affen", "sport"]));
  });

  it("Notleiter: trägt kaum eine Kategorie, kommen die vorrätigsten zuerst", () => {
    const pool = [frage("qa1"), frage("qa2"), frage("qa3"), frage("qm1", { category: "musik" })];
    const a = abschnitt(); // braucht 4 — keine Kategorie trägt allein
    const s = planState(pool, a);
    const optionen = kategorieOptionen(s, a, createRng(3));
    expect(optionen[0]).toBe("affen"); // 3 > 1 Fragen Vorrat
    expect(optionen).toContain("musik");
  });
});
