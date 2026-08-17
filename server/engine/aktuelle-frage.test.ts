// Wächter (QA-Welle 3): aktuelleFrageDesFormats — bei roundBased-Plugins
// (Boxkampf, Tortenschlacht, Duell, Affenbank …) hält aktuelleFragen ALLE
// Fragen der Runde, das Plugin schaltet intern weiter. GM-Spickzettel,
// Tipp-Kanone und Kategorie-Chip müssen der LAUFENDEN Frage folgen (die
// GM-View verrät sie per questionId) statt stur Frage 1 zu zeigen.
import { describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { defaultSettings } from "../../shared/settings";
import type { MinigamePlugin } from "../minigames/_api/plugin";
import { createInitialState } from "./engine";
import { aktuelleFrageDesFormats, type EngineDeps } from "./flow";
import type { EngineState } from "./types";

const frage = (id: string, patch: Partial<Question> = {}): Question => ({
  id,
  kind: "choice4",
  category: `kat-${id}`,
  difficulty: "hard",
  text: `Frage ${id}?`,
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "Weil A.",
  tips: [`Tipp zu ${id}`],
  ...patch,
});

/** Plugin-Attrappe: die GM-View meldet eine konfigurierbare questionId. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function fakePlugin(gmView: unknown): MinigamePlugin<any, any> {
  return {
    meta: {
      id: "fake",
      name: "Fake",
      minPlayers: 1,
      maxPlayers: 8,
      formats: ["buttons"],
      contentKind: "quiz",
      roundBased: true,
    },
    init: () => ({}),
    reduce: (s) => s,
    tick: (s) => s,
    onDisconnect: (s) => s,
    onReconnect: (s) => s,
    viewFor: () => gmView,
    isFinished: () => false,
    scores: () => ({}),
  };
}

function stateMit(fragen: Question[]): EngineState {
  return {
    ...createInitialState(defaultSettings("quick")),
    minigameId: "fake",
    minigameState: {},
    aktuelleFragen: fragen,
  };
}

const deps = (gmView: unknown): EngineDeps => ({ getPlugin: () => fakePlugin(gmView) });

describe("aktuelleFrageDesFormats (GM-Spickzettel folgt der laufenden Frage)", () => {
  it("roundBased: die questionId der GM-View wählt die laufende Frage", () => {
    const fragen = [frage("q1"), frage("q2"), frage("q3")];
    const s = stateMit(fragen);
    expect(aktuelleFrageDesFormats(s, deps({ questionId: "q3" }))?.id).toBe("q3");
    expect(aktuelleFrageDesFormats(s, deps({ questionId: "q3" }))?.tips?.[0]).toBe("Tipp zu q3");
    expect(aktuelleFrageDesFormats(s, deps({ questionId: "q2" }))?.category).toBe("kat-q2");
  });

  it("Einzelfragen-Runde: Frage 1 ohne Plugin-View-Aufruf", () => {
    const s = stateMit([frage("q1")]);
    // getPlugin darf hier gar nicht gebraucht werden (wirft absichtlich).
    const explosiv: EngineDeps = {
      getPlugin: () => {
        throw new Error("viewFor darf bei 1 Frage nicht gefragt werden");
      },
    };
    expect(aktuelleFrageDesFormats(s, explosiv)?.id).toBe("q1");
  });

  it("Fallbacks: keine/unbekannte questionId in der GM-View ⇒ Frage 1", () => {
    const fragen = [frage("q1"), frage("q2")];
    const s = stateMit(fragen);
    expect(aktuelleFrageDesFormats(s, deps({}))?.id).toBe("q1");
    expect(aktuelleFrageDesFormats(s, deps(null))?.id).toBe("q1");
    expect(aktuelleFrageDesFormats(s, deps({ questionId: "fremd" }))?.id).toBe("q1");
    expect(aktuelleFrageDesFormats({ ...s, minigameId: null }, deps({}))?.id).toBe("q1");
  });
});
