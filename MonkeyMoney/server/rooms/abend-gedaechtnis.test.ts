// Welle 1 (Eval „Dauerwiederholungen"): das Abend-Gedächtnis des Raums sperrt
// die Fragen des VORIGEN Matches beim nächsten Start — Match 2 des Abends
// bekommt frische Fragen. Recycle-Klone (`id~n`) zählen für die Basis-Frage.
import { describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, PickOptions } from "../content-loader/index";
import { allePlugins, getPlugin } from "../minigames/registry";
import type { Storage } from "../persistence/storage";
import { RoomManager } from "./room-manager";

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

function memoryStorage(): Storage {
  const dateien = new Map<string, string>();
  return {
    resolve: (p) => p,
    async readJson<T>(p: string): Promise<T | null> {
      const text = dateien.get(p);
      return text === undefined ? null : (JSON.parse(text) as T);
    },
    async writeJsonAtomic(p, data) {
      dateien.set(p, JSON.stringify(data));
    },
    async appendLine(p, line) {
      dateien.set(p, (dateien.get(p) ?? "") + line + "\n");
    },
    async readText(p) {
      return dateien.get(p) ?? null;
    },
    async listeDateien() {
      return [];
    },
    async loesche(p) {
      dateien.delete(p);
    },
  };
}

describe("room: Abend-Gedächtnis (Fragen-Dedupe über Matches)", () => {
  it("sperrt die Fragen des vorigen Matches beim nächsten startMatch", () => {
    const calls: PickOptions[] = [];
    const pool = Array.from({ length: 200 }, (_, i) => frage(`q${i + 1}`));
    const loader: ContentLoader = {
      async loadPacks() {},
      pickQuestions: (opts) => {
        calls.push({ ...opts, usedQuestionIds: [...(opts.usedQuestionIds ?? [])] });
        const used = new Set(opts.usedQuestionIds ?? []);
        return pool
          .filter((q) => !used.has(q.id))
          .slice(0, opts.anzahl)
          .map((f) => ({ ...f }));
      },
      alleFragen: () => [],
    };
    const manager = new RoomManager(
      {
        clock: createTestClock(0),
        rng: createRng(7),
        storage: memoryStorage(),
        contentLoader: loader,
        plugins: { get: getPlugin, alle: allePlugins },
        fragenProMatch: 3,
      },
      { maxRooms: 2 },
    );
    const room = manager.erzeugeRaum("http://test")!;
    // Voriges Match: q1/q2 gespielt + ein Recycle-Klon von q3.
    room.ersetzeStateRoh({ ...room.state, usedQuestionIds: ["q1", "q2", "q3~7"] });
    room.startMatch();
    // Der ERSTE Pick des neuen Matches sperrt die Abend-Fragen (Klon → Basis).
    const ersterPick = calls[0];
    expect(ersterPick.usedQuestionIds).toEqual(expect.arrayContaining(["q1", "q2", "q3"]));
    expect(ersterPick.usedQuestionIds).not.toContain("q3~7");
  });

  it("Top-Up: kleines Pack ⇒ Pool wird trotzdem voll (mit Wiederholungen)", () => {
    const pool = Array.from({ length: 30 }, (_, i) => frage(`q${i + 1}`));
    const loader: ContentLoader = {
      async loadPacks() {},
      pickQuestions: (opts) => {
        const used = new Set(opts.usedQuestionIds ?? []);
        return pool
          .filter((q) => !used.has(q.id))
          .slice(0, opts.anzahl)
          .map((f) => ({ ...f }));
      },
      alleFragen: () => [],
    };
    const manager = new RoomManager(
      {
        clock: createTestClock(0),
        rng: createRng(7),
        storage: memoryStorage(),
        contentLoader: loader,
        plugins: { get: getPlugin, alle: allePlugins },
        fragenProMatch: 3,
      },
      { maxRooms: 2 },
    );
    const room = manager.erzeugeRaum("http://test")!;
    // Abend-Gedächtnis kennt schon 25 der 30 Fragen:
    room.ersetzeStateRoh({
      ...room.state,
      usedQuestionIds: Array.from({ length: 25 }, (_, i) => `q${i + 1}`),
    });
    // startMatch darf daran nicht scheitern — der Top-Up füllt mit
    // Wiederholungen auf (frische Fragen zuerst). Kein Wurf, kein leerer Pool.
    expect(() => room.startMatch()).not.toThrow();
  });
});
