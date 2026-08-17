// Namens-Check (Eval 6, Join-Härtung): doppelte Namen im selben Raum werden
// abgelehnt — case-insensitiv + getrimmt. Der Socket-Pfad (spielerJoin) fragt
// room.nameVergeben() VOR dem Engine-Join; hier wird die Raum-Methode gegen
// echte Räume aus dem RoomManager getestet (Muster: lobby.test.ts).
import { beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import { allePlugins, getPlugin } from "../minigames/registry";
import type { Storage } from "../persistence/storage";
import type { Room } from "./room";
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

function fakeLoader(): ContentLoader {
  const pool = Array.from({ length: 40 }, (_, i) => frage(`q${i + 1}`));
  const katalog: KatalogFrage[] = pool.map((f) => ({
    frage: f,
    oberkategorie: "wissen",
    planTyp: "mc4",
    region: "global",
  }));
  return {
    async loadPacks() {},
    pickQuestions: ({ anzahl }) => pool.slice(0, anzahl).map((f) => ({ ...f })),
    alleFragen: () => katalog,
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

let manager: RoomManager;
let room: Room;

beforeEach(() => {
  manager = new RoomManager(
    {
      clock: createTestClock(1_000_000),
      rng: createRng(7),
      storage: memoryStorage(),
      contentLoader: fakeLoader(),
      plugins: { get: getPlugin, alle: allePlugins },
      fragenProMatch: 3,
    },
    { maxRooms: 8, ttlMs: 60_000 },
  );
  room = manager.erzeugeRaum("http://test")!;
});

describe("rooms: nameVergeben (Join-Härtung Eval 6)", () => {
  it("leerer Raum: kein Name ist vergeben", () => {
    expect(room.nameVergeben("Anna")).toBe(false);
  });

  it("exakter Doppelgänger wird erkannt", () => {
    expect(
      room.applyAction({ type: "join", playerId: "p1", name: "Anna", avatar: "gelb" }).ok,
    ).toBe(true);
    expect(room.nameVergeben("Anna")).toBe(true);
  });

  it("case-insensitiv + getrimmt (『anna 』 = 『Anna』)", () => {
    room.applyAction({ type: "join", playerId: "p1", name: "Anna", avatar: "gelb" });
    expect(room.nameVergeben("anna")).toBe(true);
    expect(room.nameVergeben("  ANNA  ")).toBe(true);
    expect(room.nameVergeben("Annabell")).toBe(false);
  });

  it("auch OFFLINE-Spieler blockieren den Namen (Grace-Period-Slot bleibt)", () => {
    room.applyAction({ type: "join", playerId: "p1", name: "Ben", avatar: "rot" });
    room.applyAction({ type: "presence", playerId: "p1", connected: false, graceUntil: null });
    expect(room.nameVergeben("Ben")).toBe(true);
  });

  it("Leerstring ist nie vergeben (der Join lehnt name-fehlt separat ab)", () => {
    room.applyAction({ type: "join", playerId: "p1", name: "Anna", avatar: "gelb" });
    expect(room.nameVergeben("   ")).toBe(false);
  });
});
