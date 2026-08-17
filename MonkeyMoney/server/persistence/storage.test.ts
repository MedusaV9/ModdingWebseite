// Storage: atomare JSON-Writes + JSONL-Append (Basis von Saves und Event-Log).
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createFileStorage, type Storage } from "./storage";

let dir: string;
let storage: Storage;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-storage-"));
  storage = createFileStorage(dir);
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("persistence: Storage", () => {
  it("schreibt JSON atomar und liest es zurück", async () => {
    await storage.writeJsonAtomic("meta/rooms.json", { schemaVersion: 1, rooms: ["AFFE"] });
    const gelesen = await storage.readJson<{ schemaVersion: number; rooms: string[] }>(
      "meta/rooms.json",
    );
    expect(gelesen).toEqual({ schemaVersion: 1, rooms: ["AFFE"] });
    // Kein tmp-Rest nach dem Rename:
    expect(readFileSync(join(dir, "meta/rooms.json"), "utf8")).toContain("AFFE");
  });

  it("liefert null für fehlende Dateien (kein Wurf)", async () => {
    expect(await storage.readJson("gibts/nicht.json")).toBeNull();
  });

  it("hängt JSONL-Zeilen append-only an", async () => {
    await storage.appendLine("events/m_1.jsonl", JSON.stringify({ v: 1, type: "match_started" }));
    await storage.appendLine("events/m_1.jsonl", JSON.stringify({ v: 1, type: "match_ended" }));
    const zeilen = readFileSync(join(dir, "events/m_1.jsonl"), "utf8").trim().split("\n");
    expect(zeilen).toHaveLength(2);
    expect(JSON.parse(zeilen[0]).type).toBe("match_started");
    expect(JSON.parse(zeilen[1]).type).toBe("match_ended");
  });

  it("löscht Dateien tolerant (fehlende Datei wirft nicht)", async () => {
    await storage.writeJsonAtomic("saves/auto/m_x.json", { a: 1 });
    await storage.loesche("saves/auto/m_x.json");
    expect(await storage.readJson("saves/auto/m_x.json")).toBeNull();
    await expect(storage.loesche("saves/auto/m_x.json")).resolves.toBeUndefined();
  });

  // Eval-7-Befund (P2): tmp-Name war nur pid-eindeutig ⇒ parallele Writes auf
  // dieselbe Datei kollidierten (ENOENT beim rename, live an meta/rooms.json).
  it("Stress: 50 parallele Writes auf DIESELBE Datei — letzter gewinnt, kein Wurf, kein Korrupt-File", async () => {
    const writes = Array.from({ length: 50 }, (_, i) =>
      storage.writeJsonAtomic("meta/rooms.json", { schemaVersion: 1, lauf: i }),
    );
    // KEIN Promise darf rejecten (vorher: ENOENT-Rennen beim rename).
    await Promise.all(writes);
    // Letzter Aufrufer gewinnt (Write-Queue pro Ziel-Datei serialisiert).
    const gelesen = await storage.readJson<{ schemaVersion: number; lauf: number }>(
      "meta/rooms.json",
    );
    expect(gelesen).toEqual({ schemaVersion: 1, lauf: 49 });
    // Datei ist valides JSON (kein Interleaving) und keine tmp-Leichen übrig.
    expect(() => JSON.parse(readFileSync(join(dir, "meta/rooms.json"), "utf8"))).not.toThrow();
    const reste = (await storage.listeDateien("meta")).filter((f) => f.includes(".tmp-"));
    expect(reste).toEqual([]);
  });

  it("Stress: parallele Writes auf VERSCHIEDENE Dateien laufen unabhängig", async () => {
    await Promise.all(
      Array.from({ length: 20 }, (_, i) => storage.writeJsonAtomic(`meta/f${i}.json`, { i })),
    );
    for (let i = 0; i < 20; i++) {
      expect(await storage.readJson(`meta/f${i}.json`)).toEqual({ i });
    }
  });
});
