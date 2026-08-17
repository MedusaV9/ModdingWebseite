// Raum-Lebenszyklus-Wächter (Eval-7 P2 „max-rooms unter Last"): Räume in
// Phase „ende" ohne verbundene Clients geben ihren Slot nach 2 min frei —
// alle anderen leeren Räume behalten die volle 30-min-TTL.
import { describe, expect, it } from "vitest";
import type { Socket } from "socket.io";
import type { Question } from "../../shared/content";
import { ENDE_RAUM_TTL_MS, RAUM_TTL_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader } from "../content-loader/index";
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

function fakeLoader(): ContentLoader {
  const pool = Array.from({ length: 20 }, (_, i) => frage(`q${i + 1}`));
  return {
    async loadPacks() {},
    pickQuestions: ({ anzahl }) => pool.slice(0, anzahl).map((f) => ({ ...f })),
    alleFragen: () => [],
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

function baueManager(clock: ReturnType<typeof createTestClock>): RoomManager {
  return new RoomManager(
    {
      clock,
      rng: createRng(7),
      storage: memoryStorage(),
      contentLoader: fakeLoader(),
      plugins: { get: getPlugin, alle: allePlugins },
      fragenProMatch: 3,
    },
    { maxRooms: 4 },
  );
}

/** Minimaler Fake-Client (attachClient braucht nur socket.id + emit). */
function fakeClient(id: string): { socket: Socket; role: "screen"; playerId: null } {
  return {
    socket: { id, emit: () => undefined } as unknown as Socket,
    role: "screen",
    playerId: null,
  };
}

describe("room-manager: tickAlle-TTL (Eval-7 P2 Ende-Räume)", () => {
  it("Phase „ende‟ + 0 Clients ⇒ Abbau nach 2 min (nicht früher)", () => {
    const clock = createTestClock(1_000_000);
    const manager = baueManager(clock);
    const room = manager.erzeugeRaum("http://test")!;
    room.ersetzeStateRoh({ ...room.state, phase: "ende" as never });
    expect(room.emptySince).not.toBeNull(); // nie jemand verbunden

    clock.advance(ENDE_RAUM_TTL_MS - 1_000);
    manager.tickAlle();
    expect(manager.anzahl).toBe(1); // 1:59 — noch da

    clock.advance(2_000);
    manager.tickAlle();
    expect(manager.anzahl).toBe(0); // 2:01 — Slot frei
  });

  it("Phase „ende‟ MIT verbundenem Client ⇒ bleibt (jemand schaut noch aufs Podium)", () => {
    const clock = createTestClock(1_000_000);
    const manager = baueManager(clock);
    const room = manager.erzeugeRaum("http://test")!;
    room.ersetzeStateRoh({ ...room.state, phase: "ende" as never });
    room.attachClient(fakeClient("s1"));

    clock.advance(ENDE_RAUM_TTL_MS * 5);
    manager.tickAlle();
    expect(manager.anzahl).toBe(1);

    // Client geht ⇒ ab JETZT läuft die 2-min-Uhr.
    room.detachClient("s1");
    clock.advance(ENDE_RAUM_TTL_MS - 1_000);
    manager.tickAlle();
    expect(manager.anzahl).toBe(1);
    clock.advance(2_000);
    manager.tickAlle();
    expect(manager.anzahl).toBe(0);
  });

  it("leere Lobby-Räume behalten die volle 30-min-TTL", () => {
    const clock = createTestClock(1_000_000);
    const manager = baueManager(clock);
    manager.erzeugeRaum("http://test")!;

    clock.advance(RAUM_TTL_MS - 1_000);
    manager.tickAlle();
    expect(manager.anzahl).toBe(1); // 29:59 — Lobby lebt noch

    clock.advance(2_000);
    manager.tickAlle();
    expect(manager.anzahl).toBe(0); // 30:01 — normale TTL
  });
});
