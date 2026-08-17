// Event-Log „Rotation light" (Eval-7): Die JSONL-Datei entsteht ERST beim
// Match-Start — Lobby-only-Räume hinterlassen keine Log-Leichen mehr
// (vorher: 101 Dateien in data/events, viele ohne je ein Match).
import { describe, expect, it } from "vitest";
import { createTestClock } from "../../shared/time";
import type { Storage } from "../persistence/storage";
import { createMatchEventLog } from "./event-log";

function memoryStorage(): Storage & { dateien: Map<string, string> } {
  const dateien = new Map<string, string>();
  return {
    dateien,
    resolve: (p) => p,
    async readJson() {
      return null;
    },
    async writeJsonAtomic() {},
    async appendLine(p, line) {
      dateien.set(p, (dateien.get(p) ?? "") + (line.endsWith("\n") ? line : `${line}\n`));
    },
    async readText(p) {
      return dateien.get(p) ?? null;
    },
    async listeDateien() {
      return [...dateien.keys()];
    },
    async loesche(p) {
      dateien.delete(p);
    },
  };
}

const flush = (): Promise<void> => new Promise((r) => setTimeout(r, 20));

describe("analytics: Event-Log entsteht erst beim Match-Start", () => {
  it("Lobby-Events werden gepuffert — KEINE Datei ohne match_started", async () => {
    const storage = memoryStorage();
    const log = createMatchEventLog(storage, "m_lobby", createTestClock(1000));
    log.append(1, { type: "player_joined", actor: "p_1" });
    log.append(2, { type: "gm_command", payload: { cmd: "settings.set" } });
    await flush();
    expect(storage.dateien.has("events/m_lobby.jsonl")).toBe(false);
  });

  it("match_started flusht den Lobby-Puffer in Original-Reihenfolge", async () => {
    const storage = memoryStorage();
    const log = createMatchEventLog(storage, "m_start", createTestClock(1000));
    log.append(1, { type: "player_joined", actor: "p_1" });
    log.append(2, { type: "profile_bound", actor: "p_1", payload: { profileId: "prof_1" } });
    log.append(3, { type: "match_started", payload: { modus: "quick" } });
    log.append(4, { type: "answer_submitted", actor: "p_1" });
    await flush();
    const zeilen = (storage.dateien.get("events/m_start.jsonl") ?? "").trim().split("\n");
    expect(zeilen.map((z) => JSON.parse(z).type)).toEqual([
      "player_joined",
      "profile_bound",
      "match_started",
      "answer_submitted",
    ]);
    expect(zeilen.map((z) => JSON.parse(z).seq)).toEqual([1, 2, 3, 4]);
  });

  it("match_loaded (Save/Load) aktiviert die Datei ebenfalls", async () => {
    const storage = memoryStorage();
    const log = createMatchEventLog(storage, "m_load", createTestClock(1000));
    log.append(7, { type: "match_loaded", payload: { code: "AFFE" } });
    await flush();
    expect(storage.dateien.get("events/m_load.jsonl")).toContain('"match_loaded"');
  });
});
