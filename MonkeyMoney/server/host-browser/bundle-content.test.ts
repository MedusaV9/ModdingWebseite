// Bundle-Content-Loader: Filter-Semantik muss dem Datei-Loader
// (server/content-loader/index.ts pickQuestions) 1:1 entsprechen.
import { describe, expect, it } from "vitest";
import { createRng } from "../../shared/rng";
import type { KatalogFrage } from "../content-loader/index";
import { createBundleContentLoader, parseHostContentBundle } from "./bundle-content";

function frage(
  id: string,
  ober: string,
  unter: string,
  schwierigkeit: "easy" | "medium" | "hard" | "ultrahard",
  planTyp: string,
  region: string,
): KatalogFrage {
  return {
    frage: {
      id,
      kind: "choice4",
      category: unter,
      difficulty: schwierigkeit,
      text: `Frage ${id}?`,
      options: ["A", "B", "C", "D"],
      answer: 0,
      erklaerung: "Weil.",
    },
    oberkategorie: ober,
    planTyp,
    region,
  };
}

const KATALOG: KatalogFrage[] = [
  frage("q1", "wissen", "tiere", "easy", "choice", "global"),
  frage("q2", "wissen", "pflanzen", "medium", "choice", "de"),
  frage("q3", "popkultur", "musik", "hard", "emoji", "global"),
  frage("q4", "bilder", "pixel_motive", "medium", "bild_pixel", "global"),
  frage("q5", "wissen", "tiere", "ultrahard", "choice", "us"),
];

describe("createBundleContentLoader", () => {
  it("zieht ohne Filter aus dem ganzen Katalog, respektiert anzahl", () => {
    const loader = createBundleContentLoader(KATALOG);
    expect(loader.pickQuestions({ anzahl: 3, rng: createRng(1) })).toHaveLength(3);
    expect(loader.pickQuestions({ anzahl: 99, rng: createRng(1) })).toHaveLength(5);
  });

  it("No-Repeat: usedQuestionIds fallen raus", () => {
    const loader = createBundleContentLoader(KATALOG);
    const ids = loader
      .pickQuestions({ anzahl: 99, usedQuestionIds: ["q1", "q3"], rng: createRng(2) })
      .map((q) => q.id)
      .sort();
    expect(ids).toEqual(["q2", "q4", "q5"]);
  });

  it("kategorien matcht Ober- ODER Unter-Kategorie", () => {
    const loader = createBundleContentLoader(KATALOG);
    const ober = loader.pickQuestions({ anzahl: 99, kategorien: ["wissen"], rng: createRng(3) });
    expect(ober.map((q) => q.id).sort()).toEqual(["q1", "q2", "q5"]);
    const unter = loader.pickQuestions({ anzahl: 99, kategorien: ["musik"], rng: createRng(3) });
    expect(unter.map((q) => q.id)).toEqual(["q3"]);
  });

  it("schwierigkeiten/typen/region filtern wie der Datei-Loader", () => {
    const loader = createBundleContentLoader(KATALOG);
    expect(
      loader
        .pickQuestions({ anzahl: 99, schwierigkeiten: ["medium"], rng: createRng(4) })
        .map((q) => q.id)
        .sort(),
    ).toEqual(["q2", "q4"]);
    expect(
      loader
        .pickQuestions({ anzahl: 99, typen: ["bild_pixel"], rng: createRng(4) })
        .map((q) => q.id),
    ).toEqual(["q4"]);
    // region "de" ⇒ global + de, nicht us (Datei-Loader-Semantik).
    expect(
      loader
        .pickQuestions({ anzahl: 99, region: "de", rng: createRng(4) })
        .map((q) => q.id)
        .sort(),
    ).toEqual(["q1", "q2", "q3", "q4"]);
  });

  it("liefert Kopien — Mischen beim Aufrufer mutiert den Katalog nicht", () => {
    const loader = createBundleContentLoader(KATALOG);
    const [erste] = loader.pickQuestions({ anzahl: 1, usedQuestionIds: [], rng: createRng(5) });
    erste.options.reverse();
    const nochmal = loader.alleFragen().find((f) => f.frage.id === erste.id);
    expect(nochmal?.frage.options).toEqual(["A", "B", "C", "D"]);
  });
});

describe("parseHostContentBundle", () => {
  it("akzeptiert das Build-Format und wirft bei Müll", () => {
    const ok = parseHostContentBundle({ schemaVersion: 1, quelle: "test", fragen: KATALOG });
    expect(ok.fragen).toHaveLength(5);
    expect(() => parseHostContentBundle(null)).toThrow();
    expect(() => parseHostContentBundle({ fragen: [] })).toThrow();
    expect(() => parseHostContentBundle({ fragen: [{ kaputt: true }] })).toThrow();
  });
});
