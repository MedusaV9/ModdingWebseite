// data/events-Aufräumer (Eval-7 „Rotation light"): >30 Tage ODER >500 Dateien
// ⇒ die ältesten fliegen beim Server-Boot. Zeit ist injiziert (nowMs).
import { mkdtempSync, rmSync, utimesSync, writeFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { raeumeEventLogsAuf } from "./log-rotation";

let dir: string;
const TAG_MS = 24 * 60 * 60_000;
const JETZT = 1_800_000_000_000;

function schreibeLog(name: string, alterMs: number): void {
  const pfad = join(dir, name);
  writeFileSync(pfad, '{"v":1,"type":"match_started"}\n');
  const mtime = new Date(JETZT - alterMs);
  utimesSync(pfad, mtime, mtime);
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-logrot-"));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("analytics: Event-Log-Rotation beim Boot", () => {
  it("fehlendes Verzeichnis ist ok (frische Installation)", async () => {
    const erg = await raeumeEventLogsAuf(join(dir, "gibts-nicht"), JETZT);
    expect(erg).toEqual({ geloescht: 0, behalten: 0 });
  });

  it("löscht Logs älter als 30 Tage, junge bleiben", async () => {
    schreibeLog("m_alt1.jsonl", 31 * TAG_MS);
    schreibeLog("m_alt2.jsonl", 90 * TAG_MS);
    schreibeLog("m_jung.jsonl", 5 * TAG_MS);
    schreibeLog("m_frisch.jsonl", 0);
    const erg = await raeumeEventLogsAuf(dir, JETZT);
    expect(erg).toEqual({ geloescht: 2, behalten: 2 });
    expect(readdirSync(dir).sort()).toEqual(["m_frisch.jsonl", "m_jung.jsonl"]);
  });

  it("Deckel >maxDateien: die ältesten darüber fliegen (Alter egal)", async () => {
    for (let i = 0; i < 8; i++) schreibeLog(`m_${i}.jsonl`, (8 - i) * 60_000);
    const erg = await raeumeEventLogsAuf(dir, JETZT, { maxDateien: 5 });
    expect(erg).toEqual({ geloescht: 3, behalten: 5 });
    // m_0..m_2 waren die ältesten (größtes Alter) ⇒ weg.
    expect(readdirSync(dir).sort()).toEqual([
      "m_3.jsonl",
      "m_4.jsonl",
      "m_5.jsonl",
      "m_6.jsonl",
      "m_7.jsonl",
    ]);
  });

  it("Nicht-JSONL-Dateien bleiben unangetastet", async () => {
    schreibeLog("m_alt.jsonl", 40 * TAG_MS);
    writeFileSync(join(dir, "notizen.txt"), "bleibt");
    const erg = await raeumeEventLogsAuf(dir, JETZT);
    expect(erg.geloescht).toBe(1);
    expect(readdirSync(dir)).toContain("notizen.txt");
  });
});
