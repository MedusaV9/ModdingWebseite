// IndexedDB-Storage-Adapter: Datei-Semantik des Storage-Interfaces auf
// IndexedDB (fake-indexeddb liefert die IDB-Globals im Node-Test).
import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import type { Storage } from "../persistence/storage";
import { createBrowserStorage, createMemoryStorage, direkteKinder } from "./browser-storage";

let dbNr = 0;
const frisch = (): Promise<Storage> => createBrowserStorage({ dbName: `test-db-${++dbNr}` });

describe("createBrowserStorage (IndexedDB)", () => {
  it("readJson: null für Unbekanntes, Roundtrip nach writeJsonAtomic", async () => {
    const storage = await frisch();
    expect(await storage.readJson("meta/rooms.json")).toBeNull();
    await storage.writeJsonAtomic("meta/rooms.json", {
      schemaVersion: 1,
      rooms: [{ code: "AFFE" }],
    });
    expect(await storage.readJson("meta/rooms.json")).toEqual({
      schemaVersion: 1,
      rooms: [{ code: "AFFE" }],
    });
  });

  it("writeJsonAtomic entkoppelt vom Aufrufer-Objekt (Datei-Semantik, keine Referenz)", async () => {
    const storage = await frisch();
    const daten = { liste: [1, 2] };
    await storage.writeJsonAtomic("a.json", daten);
    daten.liste.push(3); // Mutation NACH dem Schreiben darf nichts ändern
    expect(await storage.readJson("a.json")).toEqual({ liste: [1, 2] });
  });

  it("appendLine + readText: JSONL-Zeilen mit abschließendem \\n wie im Datei-Log", async () => {
    const storage = await frisch();
    await storage.appendLine("events/m_1.jsonl", '{"seq":1}');
    await storage.appendLine("events/m_1.jsonl", '{"seq":2}\n'); // \n-Varianten normalisiert
    expect(await storage.readText("events/m_1.jsonl")).toBe('{"seq":1}\n{"seq":2}\n');
  });

  it("Ring-Puffer: älteste Zeilen fliegen ab maxLogZeilen", async () => {
    const storage = await createBrowserStorage({
      dbName: `test-db-ring-${++dbNr}`,
      maxLogZeilen: 3,
    });
    for (let i = 1; i <= 5; i++) await storage.appendLine("log.jsonl", `zeile-${i}`);
    expect(await storage.readText("log.jsonl")).toBe("zeile-3\nzeile-4\nzeile-5\n");
  });

  it("readText liest auch JSON-Dokumente (Fallback), sonst null", async () => {
    const storage = await frisch();
    expect(await storage.readText("gibts-nicht.txt")).toBeNull();
    await storage.writeJsonAtomic("doc.json", { a: 1 });
    expect(JSON.parse((await storage.readText("doc.json")) ?? "")).toEqual({ a: 1 });
  });

  it("listeDateien: direkte Kinder über beide Stores, sortiert", async () => {
    const storage = await frisch();
    await storage.writeJsonAtomic("saves/slot2.json", {});
    await storage.writeJsonAtomic("saves/slot1.json", {});
    await storage.appendLine("saves/tief/log.jsonl", "x"); // tiefer Pfad → als Verzeichnis-Name
    expect(await storage.listeDateien("saves")).toEqual(["slot1.json", "slot2.json", "tief"]);
    expect(await storage.listeDateien("leer")).toEqual([]);
  });

  it("resolve liefert eine idb://-Diagnose-Adresse", async () => {
    const storage = await createBrowserStorage({ dbName: "diag-db" });
    expect(storage.resolve("events/m_1.jsonl")).toBe("idb://diag-db/events/m_1.jsonl");
  });
});

describe("direkteKinder (Key-Scan → Verzeichnis-Ansicht)", () => {
  it("filtert Präfix, kürzt tiefe Pfade aufs erste Segment, dedupliziert", () => {
    const keys = ["saves/a.json", "saves/b/log.jsonl", "saves/b/tief/x.json", "meta/rooms.json"];
    expect(direkteKinder(keys, "saves")).toEqual(["a.json", "b"]);
    expect(direkteKinder(keys, "saves/")).toEqual(["a.json", "b"]);
    expect(direkteKinder(keys, "anders")).toEqual([]);
  });
});

describe("createMemoryStorage (Fallback ohne IndexedDB)", () => {
  it("verhält sich wie der IDB-Adapter (Roundtrip, Ring, Liste)", async () => {
    const storage = createMemoryStorage({ maxLogZeilen: 2 });
    await storage.writeJsonAtomic("meta/rooms.json", { rooms: [] });
    expect(await storage.readJson("meta/rooms.json")).toEqual({ rooms: [] });
    await storage.appendLine("log.jsonl", "a");
    await storage.appendLine("log.jsonl", "b");
    await storage.appendLine("log.jsonl", "c");
    expect(await storage.readText("log.jsonl")).toBe("b\nc\n");
    expect(await storage.listeDateien("meta")).toEqual(["rooms.json"]);
    expect(storage.resolve("x")).toBe("memory://x");
  });
});
